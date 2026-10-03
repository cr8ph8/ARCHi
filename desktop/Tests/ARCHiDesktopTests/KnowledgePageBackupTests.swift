import Foundation
import CryptoKit
import XCTest
@testable import ARCHiDesktop

@MainActor
final class KnowledgePageBackupTests: XCTestCase {
    func testSourceAndPageHistoryRoundTripAndUndoRestoreExactBytesTogether() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let incoming = try seed(fixture.source, label: "Incoming")
        _ = try seed(fixture.target, label: "Earlier")
        let before = try profileBytes(fixture.target)
        let captured = try profileBytes(fixture.source)
        let summary = try DesktopProfileBackup.create(profile: .custom, preferenceURL: fixture.source,
            archiveURL: fixture.archive)
        XCTAssertEqual(summary.readingSourceCount, 1)
        XCTAssertEqual(summary.knowledgePageVersionCount, 4)
        XCTAssertTrue(summary.includesDocumentWork)
        let preview = try DesktopProfileBackup.preview(archiveURL: fixture.archive, profile: .custom,
            preferenceURL: fixture.target)
        let report = try DesktopProfileBackup.restore(preview, rollbackDirectory: fixture.recovery)
        XCTAssertEqual(try profileBytes(fixture.target), captured)
        let reopened = ReadingSourceLibrary(url: libraryURL(fixture.target))
        XCTAssertEqual(reopened.knowledgePages, incoming.knowledgePages)
        XCTAssertEqual(reopened.sources, incoming.sources)
        let reviewed = try XCTUnwrap(reopened.latestKnowledgePages.first { $0.state == .reviewed })
        XCTAssertNil(reopened.availability(of: reviewed))
        XCTAssertEqual(reopened.quote(for: try XCTUnwrap(reviewed.anchors.first)), "Incoming evidence 😀.")
        XCTAssertTrue(reopened.latestKnowledgePages.contains { $0.state == .withdrawn })
        _ = try DesktopProfileBackup.undoRestore(report)
        XCTAssertEqual(try profileBytes(fixture.target), before)
        XCTAssertEqual(try profileBytes(fixture.source), captured)
    }

    func testAbsenceAndLegacyArchivesPreserveLibraryOwnershipBoundaries() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        _ = try seed(fixture.target, label: "Retained")
        let retained = try profileBytes(fixture.target)
        let summary = try DesktopProfileBackup.create(profile: .custom, preferenceURL: fixture.source,
            archiveURL: fixture.archive)
        XCTAssertEqual(summary.readingSourceCount, 0)
        XCTAssertEqual(summary.knowledgePageVersionCount, 0)
        let absent = try DesktopProfileBackup.preview(archiveURL: fixture.archive, profile: .custom,
            preferenceURL: fixture.target)
        let report = try DesktopProfileBackup.restore(absent, rollbackDirectory: fixture.recovery)
        XCTAssertEqual(try profileBytes(fixture.target), Array<Data?>(repeating: nil, count: 5))
        _ = try DesktopProfileBackup.undoRestore(report)
        XCTAssertEqual(try profileBytes(fixture.target), retained)

        let source = ReadingSourceSnapshot(id: UUID().uuidString, title: "Legacy source", revision: 1, text: "Older retained text.")
        let oldLibrary = try canonical(["schema": "archi-reading-sources/v1",
            "sources": [JSONSerialization.jsonObject(with: JSONEncoder().encode(source))]])
        try oldLibrary.write(to: libraryURL(fixture.source))
        let legacySourceArchive = fixture.root.appendingPathComponent("old-source.archibackup")
        _ = try DesktopProfileBackup.create(profile: .custom, preferenceURL: fixture.source, archiveURL: legacySourceArchive)
        let oldSource = try DesktopProfileBackup.preview(archiveURL: legacySourceArchive, profile: .custom,
            preferenceURL: fixture.target)
        _ = try DesktopProfileBackup.restore(oldSource, rollbackDirectory: fixture.recovery)
        XCTAssertEqual(try Data(contentsOf: libraryURL(fixture.target)), oldLibrary)
        XCTAssertTrue(ReadingSourceLibrary(url: libraryURL(fixture.target)).knowledgePages.isEmpty)

        var legacyProfile = try dictionary(Data(contentsOf: legacySourceArchive))
        legacyProfile["schema"] = "archi-desktop-profile-backup/v1"
        var pair = try XCTUnwrap(legacyProfile["pair"] as? [String: Any])
        for key in ["documentWork", "documentProcedures", "readingSources"] { pair.removeValue(forKey: key) }
        legacyProfile["pair"] = pair
        let legacyProfileURL = fixture.root.appendingPathComponent("old-profile.archibackup")
        try canonical(legacyProfile).write(to: legacyProfileURL)
        let beforeConflict = try profileBytes(fixture.target)
        XCTAssertThrowsError(try DesktopProfileBackup.preview(archiveURL: legacyProfileURL, profile: .custom,
            preferenceURL: fixture.target))
        XCTAssertEqual(try profileBytes(fixture.target), beforeConflict)
        let empty = fixture.root.appendingPathComponent("empty/preferences.json")
        let compatible = try DesktopProfileBackup.preview(archiveURL: legacyProfileURL, profile: .custom, preferenceURL: empty)
        XCTAssertFalse(compatible.summary.includesDocumentWork)
        _ = try DesktopProfileBackup.restore(compatible, rollbackDirectory: fixture.recovery)
        XCTAssertFalse(FileManager.default.fileExists(atPath: libraryURL(empty).path))
    }

    func testFailureAndInterruptedRestoreRecoverWholeLibraryAndRejectChangedPreview() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        _ = try seed(fixture.source, label: "Incoming")
        let destination = try seed(fixture.target, label: "Earlier")
        _ = try DesktopProfileBackup.create(profile: .custom, preferenceURL: fixture.source, archiveURL: fixture.archive)
        let stale = try DesktopProfileBackup.preview(archiveURL: fixture.archive, profile: .custom, preferenceURL: fixture.target)
        let current = try XCTUnwrap(destination.latestKnowledgePages.first { $0.state == .reviewed })
        _ = try destination.withdrawKnowledgePage(id: current.id, expectedRevision: current.revision)
        let before = try profileBytes(fixture.target)
        XCTAssertThrowsError(try DesktopProfileBackup.restore(stale, rollbackDirectory: fixture.recovery))
        XCTAssertEqual(try profileBytes(fixture.target), before)

        let preview = try DesktopProfileBackup.preview(archiveURL: fixture.archive, profile: .custom, preferenceURL: fixture.target)
        XCTAssertThrowsError(try DesktopProfileBackup.restore(preview, rollbackDirectory: fixture.recovery) { step in
            if case .pairInstalled = step { throw FixtureFailure.injected }
        }) { error in XCTAssertNotNil((error as? DesktopProfileBackup.Failure)?.rollbackArchiveURL) }
        XCTAssertEqual(try profileBytes(fixture.target), before)
        XCTAssertFalse(DesktopProfileBackup.hasPendingJournal(preferenceURL: fixture.target))

        let next = try DesktopProfileBackup.preview(archiveURL: fixture.archive, profile: .custom, preferenceURL: fixture.target)
        XCTAssertThrowsError(try DesktopProfileBackup.restore(next, rollbackDirectory: fixture.recovery) { step in
            if case .pairInstalled = step { throw DesktopProfileBackup.Interrupted() }
        })
        XCTAssertEqual(try profileBytes(fixture.target), try profileBytes(fixture.source))
        let pending = try XCTUnwrap(DesktopProfileBackup.pendingRecovery(profile: .custom, preferenceURL: fixture.target))
        _ = try DesktopProfileBackup.recover(pending)
        XCTAssertEqual(try profileBytes(fixture.target), before)
        XCTAssertFalse(DesktopProfileBackup.hasPendingJournal(preferenceURL: fixture.target))
    }

    func testEightMiBOwnerFitsEnvelopeButOversizedAndUnknownPayloadsAreRejected() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        _ = try seed(fixture.source, label: "Bounded")
        let ordinary = try Data(contentsOf: libraryURL(fixture.source))
        var padded = ordinary
        padded.append(Data(repeating: 0x20, count: 8 * 1_024 * 1_024 - ordinary.count))
        try padded.write(to: libraryURL(fixture.source))
        let summary = try DesktopProfileBackup.create(profile: .custom, preferenceURL: fixture.source, archiveURL: fixture.archive)
        XCTAssertEqual(summary.knowledgePageVersionCount, 4)
        let archived = try Data(contentsOf: fixture.archive)
        XCTAssertGreaterThan(archived.count, 8 * 1_024 * 1_024, "Base64 must not hit the former outer archive limit.")
        XCTAssertLessThanOrEqual(archived.count, DesktopProfileBackup.maximumArchiveBytes)
        let preview = try DesktopProfileBackup.preview(archiveURL: fixture.archive, profile: .custom, preferenceURL: fixture.target)
        _ = try DesktopProfileBackup.restore(preview, rollbackDirectory: fixture.recovery)
        XCTAssertEqual(try Data(contentsOf: libraryURL(fixture.target)), padded)
        let destinationBytes = try profileBytes(fixture.target)

        var unknown = try dictionary(ordinary)
        unknown["schema"] = "archi-reading-sources/future"
        let unknownBytes = try canonical(unknown)
        var forgedArchive = try dictionary(archived)
        var pair = try XCTUnwrap(forgedArchive["pair"] as? [String: Any])
        pair["readingSources"] = ["present": true, "byteCount": unknownBytes.count,
            "data": unknownBytes.base64EncodedString(), "sha256": digest(unknownBytes)]
        forgedArchive["pair"] = pair
        let forgedURL = fixture.root.appendingPathComponent("future-source.archibackup")
        try canonical(forgedArchive).write(to: forgedURL)
        XCTAssertThrowsError(try DesktopProfileBackup.preview(archiveURL: forgedURL, profile: .custom, preferenceURL: fixture.target))
        XCTAssertEqual(try profileBytes(fixture.target), destinationBytes)

        for invalid in [unknownBytes, padded + Data([0x20])] {
            try invalid.write(to: libraryURL(fixture.source))
            let rejected = fixture.root.appendingPathComponent("rejected-\(UUID()).archibackup")
            XCTAssertThrowsError(try DesktopProfileBackup.create(profile: .custom, preferenceURL: fixture.source, archiveURL: rejected))
            XCTAssertFalse(FileManager.default.fileExists(atPath: rejected.path))
            XCTAssertEqual(try Data(contentsOf: libraryURL(fixture.source)), invalid)
        }
    }

    private enum FixtureFailure: Error { case injected }
    private func seed(_ url: URL, label: String) throws -> ReadingSourceLibrary {
        _ = try NativePreferencePersistence.write(document: NativePreferenceDocument(), to: url, expected: nil)
        let library = ReadingSourceLibrary(url: libraryURL(url))
        let source = try library.keep(title: label, text: "\(label) evidence 😀.")
        let anchor = try library.makeAnchor(sourceID: source.id, range: NSRange(location: 0, length: source.text.utf16.count))
        let draft = try library.saveKnowledgePage(title: "\(label) concept", body: "User-authored interpretation.", kind: .concept, anchors: [anchor])
        _ = try library.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        let other = try library.saveKnowledgePage(title: "\(label) claim", body: "A claim later withdrawn.", kind: .claim, anchors: [anchor])
        _ = try library.withdrawKnowledgePage(id: other.id, expectedRevision: other.revision)
        return library
    }
    private func libraryURL(_ url: URL) -> URL { url.deletingPathExtension().appendingPathExtension("reading-sources.json") }
    private func profileBytes(_ url: URL) throws -> [Data?] {
        let urls = [url] + ["evolution.json", "document-work.json", "document-procedures.json", "reading-sources.json"].map {
            url.deletingPathExtension().appendingPathExtension($0)
        }
        return try urls.map { FileManager.default.fileExists(atPath: $0.path) ? try Data(contentsOf: $0) : nil }
    }
    private func dictionary(_ bytes: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    }
    private func canonical(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    private func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    private struct Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("archi-knowledge-backup-\(UUID())")
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
