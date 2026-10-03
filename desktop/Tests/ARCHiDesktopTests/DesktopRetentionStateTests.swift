import Combine
import Foundation
import XCTest
@testable import ARCHiDesktop

final class DesktopRetentionStateTests: XCTestCase {
    @MainActor
    func testFreshVisitProjectionsDoNotCreateOrLoadFiles() throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let store = fixture.store
        XCTAssertEqual(store.preferenceRetention, .thisVisit)
        XCTAssertFalse(store.hasSavedPreferences)
        XCTAssertEqual(store.knownRetainedLessonCount, 0)
        XCTAssertFalse(store.hasRetainedQiMon)
        XCTAssertFalse(store.hasRetainedFocusGesture)
        XCTAssertEqual(store.evolution.retentionState, .notLoaded)
        XCTAssertFalse(store.evolution.hasKnownSavedBaseline)
        store.rememberPreferences = true
        XCTAssertEqual(store.preferenceRetention, .thisVisit, "The toggle alone is not a Save")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.url.deletingLastPathComponent().path).isEmpty)
        XCTAssertEqual(fixture.client.calls, 0)
    }

    @MainActor
    func testSavedChangedRevertedAndRememberOffUseTheKnownPreferenceSnapshot() throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let store = fixture.store
        store.rememberPreferences = true
        store.preferences.tone = "Warm"
        store.savePreferences()
        let saved = store.preferences, bytes = try Data(contentsOf: fixture.url)
        XCTAssertTrue(store.hasSavedPreferences)
        XCTAssertEqual(store.preferenceRetention, .saved)
        store.preferences.tone = "Direct"
        XCTAssertEqual(store.preferenceRetention, .changed)
        store.preferences = saved
        XCTAssertEqual(store.preferenceRetention, .saved, "Returning to known saved choices needs no new Save")
        store.rememberPreferences = false
        XCTAssertEqual(store.preferenceRetention, .saved)
        XCTAssertTrue(store.hasSavedPreferences)
        store.preferences.quiet = true
        store.savePreferences()
        XCTAssertEqual(store.preferenceRetention, .changed, "Remember off must not conceal a difference from the earlier save")
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
        store.rememberPreferences = true
        store.savePreferences()
        XCTAssertEqual(store.preferenceRetention, .saved)
        let current = store.preferences
        store.forgetPreferences()
        XCTAssertEqual(store.preferenceRetention, .thisVisit)
        XCTAssertFalse(store.hasSavedPreferences)
        XCTAssertEqual(store.preferences, current)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.url.path))
    }

    @MainActor
    func testKnowledgeAndIdentityCountsOnlyUseAdmittedDocumentRecords() throws {
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let expired = KeptLesson(topic: "Writing plans", text: "Start with one useful step.",
            createdAt: now.addingTimeInterval(-120), expiresAt: now.addingTimeInterval(-60))
        let kin = LocalQiMon(character: .kin, originDigest: String(repeating: "a", count: 64), welcomedAt: now)
        let saved = CompanionPreferences()
        let fixture = try makeFixture(document: NativePreferenceDocument(preferences: saved, lessons: [expired], qiMon: kin), now: now)
        defer { fixture.clean() }
        let store = fixture.store
        XCTAssertEqual(store.knownRetainedLessonCount, 1, "Expired is retained, although no longer eligible")
        XCTAssertTrue(store.matchingLessons(question: "Writing plans").isEmpty)
        XCTAssertTrue(store.hasRetainedQiMon)
        XCTAssertFalse(store.hasRetainedFocusGesture)
        store.preferences.tone = "Warm"
        store.beginLessonCorrection()
        var draft = try XCTUnwrap(store.lessonDraft)
        draft.topic = "Useful next step"; draft.text = "Name one clear next action."
        store.lessonDraft = draft
        XCTAssertEqual(store.knownRetainedLessonCount, 1, "A draft is not a retained lesson")
        var observedCounts: [Int] = []
        let observation = store.$lessonRevision.dropFirst().sink { _ in
            observedCounts.append(store.knownRetainedLessonCount)
        }
        XCTAssertTrue(store.keepLesson(draft))
        XCTAssertEqual(store.knownRetainedLessonCount, 2)
        XCTAssertEqual(observedCounts.last, 2, "Existing publication follows the admitted document update")
        withExtendedLifetime(observation) {}
        XCTAssertEqual(store.preferenceRetention, .changed, "Keeping a lesson does not save unrelated settings")
        store.beginFocusGestureTeaching()
        XCTAssertFalse(store.hasRetainedFocusGesture)
        XCTAssertTrue(store.keepFocusGesture())
        XCTAssertTrue(store.hasRetainedFocusGesture)
        XCTAssertEqual(store.preferenceRetention, .changed)
        XCTAssertEqual(try NativePreferencePersistence.read(fixture.url).document.preferences, saved)
        XCTAssertTrue(store.forgetFocusGesture())
        XCTAssertFalse(store.hasRetainedFocusGesture)
        store.forgetPreferences()
        XCTAssertEqual(store.preferenceRetention, .thisVisit)
        XCTAssertEqual(store.knownRetainedLessonCount, 2)
        XCTAssertTrue(store.hasRetainedQiMon)
        XCTAssertEqual(fixture.client.calls, 0)
    }

    @MainActor
    func testPreferenceConflictKeepsLastKnownProjectionAndRejectsFalseSuccess() throws {
        let fixture = try makeFixture(document: NativePreferenceDocument(preferences: CompanionPreferences()))
        defer { fixture.clean() }
        let store = fixture.store
        let known = store.preferences
        var external = try NativePreferencePersistence.read(fixture.url).document
        external.preferences?.tone = "Playful"
        external.lessons = [KeptLesson(topic: "External note", text: "Written by another owner.")]
        let bytes = try external.encoded()
        try bytes.write(to: fixture.url)
        XCTAssertEqual(store.preferenceRetention, .saved, "This means last known save, not a continuous disk assertion")
        XCTAssertEqual(store.knownRetainedLessonCount, 0, "Projections do not silently reread foreign changes")
        store.preferences.tone = "Warm"
        store.savePreferences()
        XCTAssertEqual(store.preferenceRetention, .changed)
        XCTAssertTrue(store.hasSavedPreferences)
        XCTAssertEqual(store.knownRetainedLessonCount, 0)
        XCTAssertTrue(store.status.contains("Could not save"))
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
        store.preferences = known
        XCTAssertEqual(store.preferenceRetention, .saved)
    }

    @MainActor
    func testCorruptPreferenceFileRemainsUnavailableAndPreserved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("retention-corrupt-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preferences.json")
        let bytes = Data("{invalid preferences".utf8)
        try bytes.write(to: url)
        let client = RetentionNoCalls()
        let store = makeStore(url: url, client: client)
        defer { store.disconnectAssistant() }
        XCTAssertEqual(store.preferenceRetention, .unavailable)
        XCTAssertFalse(store.hasSavedPreferences)
        XCTAssertEqual(store.knownRetainedLessonCount, 0)
        XCTAssertFalse(store.hasRetainedQiMon)
        XCTAssertFalse(store.hasRetainedFocusGesture)
        store.rememberPreferences = true
        store.preferences.tone = "Warm"
        store.savePreferences()
        XCTAssertEqual(store.preferenceRetention, .unavailable)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(client.calls, 0)
    }

    @MainActor
    func testEvolutionOnlyReportsSavedAfterExplicitLoadOrSave() throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let evolution = fixture.store.evolution
        let url = try XCTUnwrap(evolution.saveURL)
        let earlier = EvolutionStore(saveURL: url)
        earlier.confirmRole(.muse)
        XCTAssertTrue(earlier.save())
        let bytes = try Data(contentsOf: url)
        XCTAssertEqual(evolution.retentionState, .notLoaded, "A saved file exists but was not loaded by this owner")
        XCTAssertFalse(evolution.hasKnownSavedBaseline)
        XCTAssertNil(evolution.confirmedRole)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertTrue(evolution.load())
        XCTAssertEqual(evolution.retentionState, .saved)
        XCTAssertTrue(evolution.hasKnownSavedBaseline)
        evolution.confirmHelpStyle(.reflective)
        XCTAssertEqual(evolution.retentionState, .changed)
        XCTAssertTrue(evolution.save())
        XCTAssertEqual(evolution.retentionState, .saved)
        XCTAssertTrue(evolution.forget())
        XCTAssertEqual(evolution.retentionState, .notLoaded)
        XCTAssertFalse(evolution.hasKnownSavedBaseline)
        evolution.confirmRole(.keeper)
        XCTAssertEqual(evolution.retentionState, .changed)
        XCTAssertFalse(evolution.hasKnownSavedBaseline, "A changed fresh session has no saved baseline")
        XCTAssertTrue(evolution.save())
        XCTAssertEqual(evolution.retentionState, .saved)
    }

    @MainActor
    func testFailedEvolutionLoadAndConflictsNeverAdoptAnUnreviewedSave() throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let evolution = fixture.store.evolution
        let url = try XCTUnwrap(evolution.saveURL)
        XCTAssertFalse(evolution.load())
        XCTAssertEqual(evolution.retentionState, .notLoaded)
        evolution.confirmRole(.keeper)
        XCTAssertTrue(evolution.save())
        try Data("{invalid evolution".utf8).write(to: url)
        XCTAssertFalse(evolution.load())
        XCTAssertTrue(evolution.hasKnownSavedBaseline)
        XCTAssertEqual(evolution.retentionState, .saved, "Failed Load preserves the prior known session; requiresReplacement reports the separate error")
        XCTAssertTrue(evolution.requiresReplacement)
        evolution.confirmHelpStyle(.concise)
        XCTAssertEqual(evolution.retentionState, .changed)
        let replacement = EvolutionStore(saveURL: url)
        replacement.confirmRole(.guardian)
        XCTAssertTrue(replacement.save(replacingInvalidFile: true))
        let foreignBytes = try Data(contentsOf: url)
        XCTAssertFalse(evolution.save())
        XCTAssertFalse(evolution.forget())
        XCTAssertEqual(evolution.retentionState, .changed)
        XCTAssertTrue(evolution.hasKnownSavedBaseline)
        XCTAssertEqual(try Data(contentsOf: url), foreignBytes)
        XCTAssertTrue(evolution.load())
        XCTAssertEqual(evolution.retentionState, .saved)
        XCTAssertEqual(evolution.confirmedRole, .guardian)
    }

    @MainActor
    func testProfileLabelsUseOnlyTheConfiguredFolder() throws {
        for (folder, label) in [("ARCHiDesktopReview", "ARCHi"), ("ARCHiDesktop", "Legacy Desktop Preview"), ("another-profile", "Custom local profile")] {
            let fixture = try makeFixture(profile: folder)
            defer { fixture.clean() }
            XCTAssertEqual(fixture.store.retentionProfileLabel, label)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.url.deletingLastPathComponent().path).isEmpty)
            XCTAssertEqual(fixture.client.calls, 0)
        }
    }

    @MainActor
    private func makeFixture(document: NativePreferenceDocument? = nil, profile: String = "test-profile",
                             now: Date = Date()) throws -> RetentionFixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("desktop-retention-\(UUID())")
        let profileDirectory = directory.appendingPathComponent(profile)
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        let url = profileDirectory.appendingPathComponent("preferences.json")
        if let document { try document.encoded().write(to: url) }
        let client = RetentionNoCalls()
        return RetentionFixture(directory: directory, url: url, client: client,
            store: makeStore(url: url, client: client, now: now))
    }

    @MainActor
    private func makeStore(url: URL, client: RetentionNoCalls, now: Date = Date()) -> CompanionStore {
        CompanionStore(preferenceURL: url, assistant: client, assistantFactory: { _, _ in client },
            wallClock: { now }, allowsPlay: false)
    }
}

@MainActor
private struct RetentionFixture {
    let directory: URL
    let url: URL
    let client: RetentionNoCalls
    let store: CompanionStore

    func clean() {
        store.disconnectAssistant()
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class RetentionNoCalls: AssistantClient {
    private(set) var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.stopped }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1
        throw AssistantFailure.stopped
    }
    func disconnect() {}
}
