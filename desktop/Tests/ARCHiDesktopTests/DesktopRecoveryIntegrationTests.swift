import Foundation
import XCTest
@testable import ARCHiDesktop

final class DesktopRecoveryIntegrationTests: XCTestCase {
    @MainActor
    func testRestoreLoadsExistingOwnersPreservesDraftAndPlacementAndAllowsLaterSave() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source/preferences.json")
        try write(tone: "Warm", to: source)
        let archive = directory.appendingPathComponent("warm.archibackup")
        _ = try DesktopProfileBackup.create(profile: .custom, preferenceURL: source, archiveURL: archive)
        let target = directory.appendingPathComponent("target/preferences.json")
        try write(tone: "Direct", to: target)
        let client = RecoveryIntegrationNoCalls()
        let store = makeStore(target, client)
        store.evolution.confirmRole(.guardian)
        XCTAssertTrue(store.evolution.save())
        store.share(text: "A synthetic working document stays in this visit.", name: "draft.txt")
        store.prompt = "Preserve this unsent question."
        store.placed(at: CGPoint(x: 410, y: 212))
        let position = store.position
        let preview = try store.previewProfileRestore(from: archive)
        XCTAssertEqual(store.preferences.tone, "Direct", "Preview must not admit choices")
        let report = try store.restoreProfile(preview)
        XCTAssertEqual(store.preferences.tone, "Warm")
        XCTAssertEqual(store.preferenceRetention, .saved)
        XCTAssertNil(store.evolution.confirmedRole, "Absent saved Evolution clears the old owner")
        XCTAssertFalse(store.evolution.hasUnsavedChanges)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.deletingPathExtension().appendingPathExtension("evolution.json").path))
        XCTAssertEqual(store.prompt, "Preserve this unsent question.")
        XCTAssertEqual(store.sharedText, "A synthetic working document stays in this visit.")
        XCTAssertEqual(store.position, position)
        XCTAssertTrue(store.compareResults.isEmpty)
        XCTAssertTrue(store.localConversation.exchanges.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.rollbackArchiveURL.path))
        store.preferences.tone = "Calm"
        store.savePreferences()
        XCTAssertEqual(try NativePreferencePersistence.read(target).document.preferences?.tone, "Calm", "Restore must adopt the actual baseline")
        XCTAssertEqual(client.calls, 0)
    }

    @MainActor
    func testKeepDuringRestorePreservesItsDraftAndReopensTheRestoredPair() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let client = RecoveryIntegrationNoCalls()
        let source = directory.appendingPathComponent("source/preferences.json")
        try write(tone: "Warm", to: source)
        let incoming = makeStore(source, client)
        incoming.beginLessonCorrection()
        var incomingDraft = try XCTUnwrap(incoming.lessonDraft)
        incomingDraft.topic = "planning"
        incomingDraft.text = "Keep the archived plan."
        XCTAssertTrue(incoming.keepLesson(incomingDraft))
        incoming.evolution.confirmRole(.muse)
        XCTAssertTrue(incoming.evolution.save())
        let archive = directory.appendingPathComponent("profile.archibackup")
        _ = try incoming.createProfileBackup(at: archive)

        let target = directory.appendingPathComponent("target/preferences.json")
        try write(tone: "Direct", to: target)
        let writer = makeStore(target, client)
        writer.evolution.confirmRole(.guardian)
        XCTAssertTrue(writer.evolution.save())
        writer.evolution.confirmRole(.keeper)
        writer.share(text: "The working copy belongs to this visit.", name: "plan.txt")
        writer.beginLessonCorrection()
        var draft = try XCTUnwrap(writer.lessonDraft)
        draft.topic = "planning"
        draft.text = "Keep the competing plan."
        draft.source = try XCTUnwrap(writer.currentLessonSource)
        writer.lessonDraft = draft

        let preview = try DesktopProfileBackup.preview(archiveURL: archive, profile: .custom, preferenceURL: target)
        _ = try DesktopProfileBackup.restore(preview, rollbackDirectory: directory.appendingPathComponent("rollback")) { step in
            guard case .journalPrepared = step else { return }
            // The competing writer still has the exact on-disk preference baseline.
            XCTAssertFalse(writer.keepLesson(draft))
            XCTAssertTrue(writer.lessonMessage.contains("Another ARCHi session"))
            XCTAssertFalse(writer.evolution.save())
            XCTAssertFalse(writer.evolution.forget())
            XCTAssertEqual(writer.evolution.confirmedRole, .keeper)
            XCTAssertTrue(writer.evolution.hasUnsavedChanges)
        }
        XCTAssertEqual(writer.lessonDraft, draft)
        XCTAssertFalse(writer.keepLesson(draft), "The winning restore changed the baseline")
        XCTAssertEqual(writer.lessonDraft, draft)

        let reopened = makeStore(target, client)
        XCTAssertEqual(reopened.preferences.tone, "Warm")
        XCTAssertEqual(reopened.keptLessons, incoming.keptLessons)
        XCTAssertTrue(reopened.evolution.load())
        XCTAssertEqual(reopened.evolution.confirmedRole, .muse)
        XCTAssertFalse(DesktopProfileBackup.hasPendingJournal(preferenceURL: target))
        XCTAssertEqual(client.calls, 0)
    }

    @MainActor
    func testChangedVisitOrBusyRequestCannotUseEarlierRestorePreview() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("profile/preferences.json")
        try write(tone: "Warm", to: url)
        let client = RecoveryIntegrationNoCalls()
        let store = makeStore(url, client)
        let archive = directory.appendingPathComponent("backup.archibackup")
        _ = try store.createProfileBackup(at: archive)
        let review = try store.previewProfileRestore(from: archive)
        let bytes = try Data(contentsOf: url)
        store.preferences.tone = "Direct"
        XCTAssertThrowsError(try store.restoreProfile(review))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        store.preferences.tone = "Warm"
        store.evolution.confirmHelpStyle(.concise)
        XCTAssertThrowsError(try store.restoreProfile(review))
        XCTAssertTrue(store.evolution.save())
        XCTAssertThrowsError(try store.restoreProfile(review), "Even saved changes invalidate the earlier reviewed visit")
        store.isWorking = true
        XCTAssertThrowsError(try store.createProfileBackup(at: directory.appendingPathComponent("busy.archibackup")))
        XCTAssertThrowsError(try store.previewProfileRestore(from: archive))
        XCTAssertEqual(client.calls, 0)
    }

    @MainActor
    func testBackupCopiesSavedValuesAndNeverSilentlySavesVisitChanges() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("profile/preferences.json")
        try write(tone: "Warm", to: url)
        let client = RecoveryIntegrationNoCalls()
        let store = makeStore(url, client)
        store.preferences.tone = "Playful"
        let archive = directory.appendingPathComponent("saved-only.archibackup")
        _ = try store.createProfileBackup(at: archive)
        let target = directory.appendingPathComponent("other/preferences.json")
        let preview = try DesktopProfileBackup.preview(archiveURL: archive, profile: .custom, preferenceURL: target)
        _ = try DesktopProfileBackup.restore(preview, rollbackDirectory: directory.appendingPathComponent("rollback"))
        XCTAssertEqual(try NativePreferencePersistence.read(target).document.preferences?.tone, "Warm")
        XCTAssertEqual(store.preferences.tone, "Playful")
        XCTAssertEqual(store.preferenceRetention, .changed)
        XCTAssertEqual(client.calls, 0)
    }

    @MainActor
    func testStartupRecoversInterruptedPairBeforeAdmittingPreferences() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source/preferences.json")
        try write(tone: "Direct", to: source)
        let archive = directory.appendingPathComponent("source.archibackup")
        _ = try DesktopProfileBackup.create(profile: .custom, preferenceURL: source, archiveURL: archive)
        let target = directory.appendingPathComponent("target/preferences.json")
        try write(tone: "Warm", to: target)
        let oldBytes = try Data(contentsOf: target)
        let preview = try DesktopProfileBackup.preview(archiveURL: archive, profile: .custom, preferenceURL: target)
        XCTAssertThrowsError(try DesktopProfileBackup.restore(preview, rollbackDirectory: directory.appendingPathComponent("rollback")) { stage in
            if case .firstFileInstalled = stage { throw DesktopProfileBackup.Interrupted() }
        })
        XCTAssertTrue(DesktopProfileBackup.hasPendingJournal(preferenceURL: target))
        let client = RecoveryIntegrationNoCalls()
        let store = makeStore(target, client)
        XCTAssertNil(store.profileRecoveryBlock)
        XCTAssertEqual(store.preferences.tone, "Warm")
        XCTAssertEqual(try Data(contentsOf: target), oldBytes)
        XCTAssertFalse(DesktopProfileBackup.hasPendingJournal(preferenceURL: target))
        XCTAssertEqual(client.calls, 0)
    }

    @MainActor
    func testInvalidJournalBlocksBothOwnersWithoutAdmittingOrOverwritingFiles() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("profile/preferences.json")
        try write(tone: "Warm", to: url)
        let original = try Data(contentsOf: url)
        let journal = url.deletingLastPathComponent().appendingPathComponent(DesktopProfileBackup.journalFilename)
        try Data("invalid journal".utf8).write(to: journal)
        let client = RecoveryIntegrationNoCalls()
        let store = makeStore(url, client)
        XCTAssertNotNil(store.profileRecoveryBlock)
        XCTAssertEqual(store.preferenceRetention, .unavailable)
        XCTAssertEqual(store.preferences.tone, "Calm", "Unrecovered data is not admitted")
        store.rememberPreferences = true
        store.preferences.tone = "Direct"
        store.savePreferences()
        XCTAssertFalse(store.evolution.save())
        XCTAssertFalse(store.evolution.load())
        XCTAssertFalse(store.evolution.forget())
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(try Data(contentsOf: journal), Data("invalid journal".utf8))
        XCTAssertEqual(client.calls, 0)
        store.evolution.confirmRole(.muse)
        try FileManager.default.removeItem(at: journal) // Simulates an independently repaired interruption.
        XCTAssertThrowsError(try store.retryInterruptedProfileRecovery(), "Changed visit choices need explicit review")
        try store.retryInterruptedProfileRecovery(discardVisitChoices: true)
        XCTAssertNil(store.profileRecoveryBlock)
        XCTAssertEqual(store.preferences.tone, "Warm")
        XCTAssertNil(store.evolution.confirmedRole)
        XCTAssertEqual(client.calls, 0)
    }

    @MainActor
    func testRetryAdmissionFailureKeepsBothPersistenceOwnersBlocked() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("profile/preferences.json")
        try write(tone: "Warm", to: url)
        let evolutionURL = url.deletingPathExtension().appendingPathExtension("evolution.json")
        let invalid = Data("invalid saved development".utf8)
        try invalid.write(to: evolutionURL)
        let journal = url.deletingLastPathComponent().appendingPathComponent(DesktopProfileBackup.journalFilename)
        try Data("invalid journal".utf8).write(to: journal)
        let client = RecoveryIntegrationNoCalls()
        let store = makeStore(url, client)
        try FileManager.default.removeItem(at: journal)
        XCTAssertThrowsError(try store.retryInterruptedProfileRecovery())
        XCTAssertNotNil(store.profileRecoveryBlock)
        XCTAssertNotNil(store.evolution.persistenceBlockedReason)
        XCTAssertFalse(store.evolution.save(replacingInvalidFile: true))
        XCTAssertFalse(store.evolution.forget())
        XCTAssertEqual(try Data(contentsOf: evolutionURL), invalid)
        XCTAssertEqual(client.calls, 0)
        // A completed journal recovery may expose invalid older owner data.
        // Once the journal is gone, a verified backup must remain a way out.
        let valid = directory.appendingPathComponent("valid/preferences.json")
        try write(tone: "Playful", to: valid)
        let archive = directory.appendingPathComponent("valid.archibackup")
        _ = try DesktopProfileBackup.create(profile: .custom, preferenceURL: valid, archiveURL: archive)
        store.evolution.confirmRole(.muse)
        store.preferences.tone = "Direct"
        let review = try store.previewProfileRestore(from: archive)
        _ = try store.restoreProfile(review)
        XCTAssertNil(store.profileRecoveryBlock)
        XCTAssertNil(store.evolution.persistenceBlockedReason)
        XCTAssertEqual(store.preferences.tone, "Playful")
        XCTAssertEqual(client.calls, 0)
    }

    @MainActor private func makeStore(_ url: URL, _ client: RecoveryIntegrationNoCalls) -> CompanionStore {
        CompanionStore(preferenceURL: url, assistant: client, assistantFactory: { _, _ in client }, allowsPlay: false)
    }
    private func root() throws -> URL {
        let result = FileManager.default.temporaryDirectory.appendingPathComponent("desktop-recovery-integration-\(UUID())")
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
        return result
    }
    private func write(tone: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var document = NativePreferenceDocument()
        var preferences = CompanionPreferences(); preferences.tone = tone
        document.preferences = preferences
        _ = try NativePreferencePersistence.write(document: document, to: url, expected: nil)
    }
}

@MainActor private final class RecoveryIntegrationNoCalls: AssistantClient {
    private(set) var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.stopped }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; throw AssistantFailure.stopped
    }
    func disconnect() {}
}
