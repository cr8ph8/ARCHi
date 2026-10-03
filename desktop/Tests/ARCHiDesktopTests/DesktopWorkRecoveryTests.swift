import Foundation
import XCTest
@testable import ARCHiDesktop

@MainActor
final class DesktopWorkRecoveryTests: XCTestCase {
    func testFiveFileRestoreReloadsOwnersAndAllowsLaterWritesWithoutDispatch() throws {
        let f = try Fixture(); defer { f.remove() }
        try seed(f.source, label: "Incoming")
        try seed(f.target, label: "Earlier")
        let original = try bytes(f.target)
        let incoming = try bytes(f.source)
        let client = WorkRecoveryNoCalls()
        let store = makeStore(f.target, client)
        let oldSources = store.readingSources
        store.share(text: "An unsaved working copy.", name: "draft.txt")
        store.prompt = "An unsent question."
        let summary = try DesktopProfileBackup.create(profile: .custom, preferenceURL: f.source, archiveURL: f.archive)
        XCTAssertTrue(summary.includesDocumentWork)
        XCTAssertEqual(summary.documentRecordCount, 1)
        XCTAssertEqual(summary.procedureCount, 1)
        XCTAssertEqual(summary.readingSourceCount, 1)
        let review = try store.previewProfileRestore(from: f.archive)
        let report = try store.restoreProfile(review)
        XCTAssertEqual(try bytes(f.target), incoming)
        XCTAssertEqual(store.readingSources.sources.first?.title, "Incoming")
        XCTAssertEqual(store.documentWork.records.count, 1)
        let method = try XCTUnwrap(store.documentProcedures.procedures.first)
        XCTAssertNil(store.documentProcedures.availability(of: method, records: store.documentWork.records))
        XCTAssertEqual(store.sharedText, "An unsaved working copy.")
        XCTAssertEqual(store.prompt, "An unsent question.")
        XCTAssertThrowsError(try oldSources.keep(title: "Stale writer", text: "Must not replace restored copies."))
        try store.readingSources.keep(title: "After restore", text: "The newly loaded owner can save.")
        try store.documentProcedures.withdraw(binding: method.binding)
        var record = try XCTUnwrap(store.documentWork.records.first)
        record.detail = "Reviewed after restore."
        try store.documentWork.save(record)
        XCTAssertEqual(ReadingSourceLibrary(url: sidecar(f.target, "reading-sources.json")).sources.count, 2)
        XCTAssertTrue(try XCTUnwrap(DocumentProcedureLibrary(url: sidecar(f.target, "document-procedures.json")).procedures.first).withdrawn)
        let rollback = try store.previewProfileRestore(from: report.rollbackArchiveURL)
        _ = try store.restoreProfile(rollback)
        XCTAssertEqual(try bytes(f.target), original)
        XCTAssertEqual(store.readingSources.sources.first?.title, "Earlier")
        XCTAssertEqual(client.calls, 0)
    }

    func testInterruptedThirdFileInstallRecoversAllFiveBeforeLoadingOwners() throws {
        let f = try Fixture(); defer { f.remove() }
        try seed(f.source, label: "Incoming")
        try seed(f.target, label: "Earlier")
        let original = try bytes(f.target)
        _ = try DesktopProfileBackup.create(profile: .custom, preferenceURL: f.source, archiveURL: f.archive)
        let preview = try DesktopProfileBackup.preview(archiveURL: f.archive, profile: .custom, preferenceURL: f.target)
        XCTAssertThrowsError(try DesktopProfileBackup.restore(preview, rollbackDirectory: f.recovery) { stage in
            if case .documentWorkInstalled = stage { throw DesktopProfileBackup.Interrupted() }
        })
        XCTAssertNotEqual(try bytes(f.target), original)
        let client = WorkRecoveryNoCalls()
        let store = makeStore(f.target, client)
        XCTAssertNil(store.profileRecoveryBlock)
        XCTAssertEqual(try bytes(f.target), original)
        XCTAssertEqual(store.readingSources.sources.first?.title, "Earlier")
        let method = try XCTUnwrap(store.documentProcedures.procedures.first)
        XCTAssertNil(store.documentProcedures.availability(of: method, records: store.documentWork.records))
        XCTAssertFalse(DesktopProfileBackup.hasPendingJournal(preferenceURL: f.target))
        XCTAssertEqual(client.calls, 0)
    }

    func testLegacyBackupOnlyRestoresWithoutDocumentFilesIncludingAfterPreview() throws {
        let f = try Fixture(); defer { f.remove() }
        try seed(f.source, label: "Legacy")
        _ = try DesktopProfileBackup.create(profile: .custom, preferenceURL: f.source, archiveURL: f.archive)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: f.archive)) as? [String: Any])
        object["schema"] = "archi-desktop-profile-backup/v1"
        var pair = try XCTUnwrap(object["pair"] as? [String: Any])
        for key in ["documentWork", "documentProcedures", "readingSources"] { pair.removeValue(forKey: key) }
        object["pair"] = pair
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]).write(to: f.archive)
        let preview = try DesktopProfileBackup.preview(archiveURL: f.archive, profile: .custom, preferenceURL: f.target)
        XCTAssertFalse(preview.summary.includesDocumentWork)
        _ = try DesktopProfileBackup.restore(preview, rollbackDirectory: f.recovery)
        XCTAssertEqual(try Data(contentsOf: f.target), try Data(contentsOf: f.source))
        let next = try DesktopProfileBackup.preview(archiveURL: f.archive, profile: .custom, preferenceURL: f.target)
        try ReadingSourceLibrary(url: sidecar(f.target, "reading-sources.json")).keep(title: "New copy", text: "Created after the preview.")
        let retained = try bytes(f.target)
        XCTAssertThrowsError(try DesktopProfileBackup.restore(next, rollbackDirectory: f.recovery))
        XCTAssertThrowsError(try DesktopProfileBackup.preview(archiveURL: f.archive, profile: .custom, preferenceURL: f.target))
        XCTAssertEqual(try bytes(f.target), retained)
        XCTAssertFalse(DesktopProfileBackup.hasPendingJournal(preferenceURL: f.target))
    }

    func testMalformedWorkAndChangedReadingCopyDoNotOverwriteOrExport() throws {
        let f = try Fixture(); defer { f.remove() }
        try seed(f.source, label: "Incoming")
        try seed(f.target, label: "Earlier")
        _ = try DesktopProfileBackup.create(profile: .custom, preferenceURL: f.source, archiveURL: f.archive)
        let preview = try DesktopProfileBackup.preview(archiveURL: f.archive, profile: .custom, preferenceURL: f.target)
        let sources = ReadingSourceLibrary(url: sidecar(f.target, "reading-sources.json"))
        try sources.replace(id: XCTUnwrap(sources.sources.first?.id), title: "Edited", text: "Changed after preview.")
        let retained = try bytes(f.target)
        XCTAssertThrowsError(try DesktopProfileBackup.restore(preview, rollbackDirectory: f.recovery))
        XCTAssertEqual(try bytes(f.target), retained)
        let invalid = Data("{ malformed method file".utf8)
        try invalid.write(to: sidecar(f.source, "document-procedures.json"))
        let output = f.root.appendingPathComponent("invalid.archibackup")
        XCTAssertThrowsError(try DesktopProfileBackup.create(profile: .custom, preferenceURL: f.source, archiveURL: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(try Data(contentsOf: sidecar(f.source, "document-procedures.json")), invalid)
    }

    func testUnrecoverableJournalHidesAndBlocksAllDocumentOwners() throws {
        let f = try Fixture(); defer { f.remove() }
        try seed(f.target, label: "Retained")
        let original = try bytes(f.target)
        try Data("invalid recovery journal".utf8).write(to: f.target.deletingLastPathComponent().appendingPathComponent(DesktopProfileBackup.journalFilename))
        let client = WorkRecoveryNoCalls()
        let store = makeStore(f.target, client)
        XCTAssertNotNil(store.profileRecoveryBlock)
        XCTAssertTrue(store.documentWork.records.isEmpty)
        XCTAssertTrue(store.documentProcedures.procedures.isEmpty)
        XCTAssertTrue(store.readingSources.sources.isEmpty)
        XCTAssertNotNil(store.documentWork.loadError)
        XCTAssertNotNil(store.documentProcedures.loadError)
        XCTAssertNotNil(store.readingSources.loadError)
        XCTAssertThrowsError(try store.readingSources.keep(title: "Blocked", text: "Do not save."))
        XCTAssertEqual(try bytes(f.target), original)
        XCTAssertEqual(client.calls, 0)
    }

    private func makeStore(_ url: URL, _ client: WorkRecoveryNoCalls) -> CompanionStore {
        CompanionStore(preferenceURL: url, assistant: client, assistantFactory: { _, _ in client }, allowsPlay: false)
    }
    private func sidecar(_ url: URL, _ suffix: String) -> URL {
        url.deletingPathExtension().appendingPathExtension(suffix)
    }
    private func bytes(_ url: URL) throws -> [Data?] {
        try [url, sidecar(url, "evolution.json"), sidecar(url, "document-work.json"),
             sidecar(url, "document-procedures.json"), sidecar(url, "reading-sources.json")].map {
            FileManager.default.fileExists(atPath: $0.path) ? try Data(contentsOf: $0) : nil
        }
    }
    private func seed(_ url: URL, label: String) throws {
        var document = NativePreferenceDocument()
        var preferences = CompanionPreferences(); preferences.tone = label == "Incoming" ? "Direct" : "Warm"
        document.preferences = preferences
        _ = try NativePreferencePersistence.write(document: document, to: url, expected: nil)
        let evolution = EvolutionStore(saveURL: sidecar(url, "evolution.json"))
        evolution.confirmRole(.guardian)
        XCTAssertTrue(evolution.save())
        let journal = DocumentWorkJournal(url: sidecar(url, "document-work.json"))
        let request = UUID().uuidString
        let date = Date(timeIntervalSince1970: 1_789_000_000)
        var record = DocumentWorkRecord(id: request + "-Qwen", requestID: request, provider: "Qwen", targetID: UUID().uuidString,
            sourceDigest: String(repeating: "a", count: 64), sourceRevision: 1, selectionStart: 0, selectionLength: 12,
            preserveNumbersAndLinks: true, createdAt: date, updatedAt: date, state: .proposing,
            proposedDigest: String(repeating: "b", count: 64), expectedAfterDigest: String(repeating: "c", count: 64),
            checks: [.init(id: "source", title: "Exact source", passed: true)],
            learning: .init(requestBinding: .init(inputDigest: String(repeating: "d", count: 64), contextDigest: String(repeating: "e", count: 64))))
        try journal.save(record)
        record.state = .ready; try journal.save(record)
        record.state = .applying; try journal.save(record)
        record.state = .applied; record.actualAfterDigest = record.expectedAfterDigest; record.afterRevision = 2
        try journal.save(record)
        record.feedback = .init(revision: 1, verdict: .helpful, recordedAt: date)
        try journal.save(record)
        let methods = DocumentProcedureLibrary(url: sidecar(url, "document-procedures.json"))
        _ = try methods.keep(from: record, title: label, instruction: "Use direct verbs.", records: journal.records)
        try ReadingSourceLibrary(url: sidecar(url, "reading-sources.json")).keep(title: label, text: "A synthetic reading copy for recovery.")
    }
    private struct Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("archi-work-recovery-\(UUID())")
        var source: URL { root.appendingPathComponent("source/preferences.json") }
        var target: URL { root.appendingPathComponent("target/preferences.json") }
        var archive: URL { root.appendingPathComponent("saved.archibackup") }
        var recovery: URL { root.appendingPathComponent("Recovery") }
        init() throws {
            for url in [source, target] { try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true) }
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}

@MainActor private final class WorkRecoveryNoCalls: AssistantClient {
    private(set) var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.stopped }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; throw AssistantFailure.stopped
    }
    func disconnect() {}
}
