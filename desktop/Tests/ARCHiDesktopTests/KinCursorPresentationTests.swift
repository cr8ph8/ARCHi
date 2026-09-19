import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

/// The Seed cursor and a kept body are projections of the same personal record.
/// All data, windows and completed-answer fixtures here are local and disposable.
final class KinCursorPresentationTests: XCTestCase {
    @MainActor
    func testLightAppearanceKeepsOneIdentityAndBodyMilestoneAcrossSaveAndReturn() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let store = fixture.store
        _ = try keepGrowth(in: fixture)
        let identity = store.activeQiMon, growth = store.evolution.kinGrowthRecord
        let history = store.evolution.history, position = store.position
        let originalBytes = try Data(contentsOf: fixture.preferenceURL)
        store.chooseSeedAppearance(.archiLight)
        XCTAssertEqual(store.presentationForm, .kin)
        XCTAssertEqual(store.cursorPresentationForm, .corePearl)
        XCTAssertEqual(store.activeQiMon, identity)
        XCTAssertEqual(store.evolution.kinGrowthRecord, growth)
        XCTAssertEqual(store.evolution.history, history)
        XCTAssertEqual(store.position, position)
        XCTAssertEqual(try Data(contentsOf: fixture.preferenceURL), originalBytes, "A look choice alone is not a save")
        let snapshot = try XCTUnwrap(UnityPresentationSnapshot.capture(store: store, sessionID: UUID(), revision: 1,
            active: true, now: Date(), systemReduceMotion: true))
        XCTAssertEqual(snapshot.seedAppearance, "archiLight")
        XCTAssertEqual(snapshot.seedAssetSHA256, CompanionVisualAsset.lightSeedDigest)
        XCTAssertEqual(snapshot.body, "firstLight")
        store.returnKinToSeed()
        XCTAssertEqual(store.presentationForm, .corePearl)
        store.rememberPreferences = true
        store.savePreferences()
        XCTAssertTrue(store.evolution.save())
        let reopened = fixture.reopen()
        XCTAssertEqual(reopened.preferences.seedAppearance, .archiLight)
        XCTAssertEqual(reopened.presentationForm, .corePearl)
        XCTAssertEqual(reopened.activeQiMon, identity)
        XCTAssertTrue(reopened.evolution.load())
        XCTAssertTrue(reopened.resumeKinFirstLight())
        XCTAssertEqual(reopened.presentationForm, .kin)
        XCTAssertEqual(reopened.cursorPresentationForm, .corePearl)
        reopened.chooseSeedAppearance(.kinParticles)
        XCTAssertEqual(reopened.cursorPresentationForm, .kinSeed)
        XCTAssertEqual(reopened.presentationForm, .kin)
        await reopened.shutdownAssistant()
        await store.shutdownAssistant()
    }

    @MainActor
    func testSeedCursorSurvivesBodyKeepLoadReturnResumeAndLessonWithdrawal() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let store = fixture.store
        let identity = store.activeQiMon, preferences = store.preferences
        let position = store.position, placement = store.placementRevision
        let initialPreferenceBytes = try Data(contentsOf: fixture.preferenceURL)
        XCTAssertEqual(store.presentationForm, .kinSeed)
        XCTAssertEqual(store.cursorPresentationForm, .kinSeed)
        let requestID = try retainUse(in: fixture)
        XCTAssertTrue(store.previewKinGrowth(receiptID: requestID))
        XCTAssertEqual(store.presentationForm, .kinSeed)
        XCTAssertEqual(store.cursorPresentationForm, .kinSeed)
        XCTAssertTrue(store.keepKinGrowth())
        let growth = try XCTUnwrap(store.evolution.kinGrowthRecord)
        assertFirstLightBodyAndSeedCursor(store)
        XCTAssertTrue(store.evolution.save())
        XCTAssertEqual(try Data(contentsOf: fixture.preferenceURL), initialPreferenceBytes)

        let reopened = fixture.reopen()
        XCTAssertEqual(reopened.presentationForm, .kinSeed, "Evolution Load remains explicit")
        XCTAssertEqual(reopened.cursorPresentationForm, .kinSeed)
        XCTAssertTrue(reopened.evolution.load())
        assertFirstLightBodyAndSeedCursor(reopened)
        XCTAssertEqual(reopened.activeQiMon, identity)
        XCTAssertEqual(reopened.preferences, preferences)
        XCTAssertEqual(reopened.evolution.kinGrowthRecord, growth)
        reopened.returnKinToSeed()
        XCTAssertEqual(reopened.presentationForm, .kinSeed)
        XCTAssertEqual(reopened.cursorPresentationForm, .kinSeed)
        XCTAssertTrue(reopened.resumeKinFirstLight())
        assertFirstLightBodyAndSeedCursor(reopened)

        let lesson = try XCTUnwrap(reopened.keptLessons.first)
        XCTAssertTrue(reopened.withdrawLesson(id: lesson.id, expectedRevision: reopened.lessonRevision))
        XCTAssertTrue(reopened.keptLessons.isEmpty)
        XCTAssertTrue(reopened.kinGrowthEvidence.isEmpty)
        assertFirstLightBodyAndSeedCursor(reopened)
        XCTAssertTrue(reopened.evolution.save())
        let afterWithdrawal = fixture.reopen()
        XCTAssertTrue(afterWithdrawal.evolution.load())
        assertFirstLightBodyAndSeedCursor(afterWithdrawal)
        XCTAssertTrue(afterWithdrawal.keptLessons.isEmpty)
        XCTAssertEqual(afterWithdrawal.activeQiMon, identity)
        XCTAssertEqual(afterWithdrawal.preferences, preferences)
        XCTAssertEqual(afterWithdrawal.evolution.kinGrowthRecord, growth)
        XCTAssertEqual(store.position, position)
        XCTAssertEqual(store.placementRevision, placement)
        XCTAssertEqual(store.activeQiMon, identity)
        XCTAssertEqual(store.preferences, preferences)
        XCTAssertEqual(fixture.client.calls, 0)
        await afterWithdrawal.shutdownAssistant()
        await reopened.shutdownAssistant()
        await store.shutdownAssistant()
    }

    @MainActor
    func testBothPresentationsRequireTheSameActiveIndividualAcrossNativeAndRetainedOriginRules() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        _ = try keepGrowth(in: fixture)
        XCTAssertTrue(fixture.store.evolution.save())
        let bytes = try Data(contentsOf: fixture.preferenceURL)

        // Native-only mode uses the validated saved personal record. It does not
        // require or invent a live game host, even if stale projection data exists.
        fixture.store.observeQiMonJourney(projection(String(repeating: "b", count: 64)))
        assertFirstLightBodyAndSeedCursor(fixture.store)
        let nativeIdentity = fixture.store.activeQiMon

        // This checks the retained origin contract with synthetic projection
        // values only. No HostedPlayHost, WebKit view or server is constructed.
        let originBound = fixture.reopen(allowsPlay: true)
        XCTAssertTrue(originBound.evolution.load())
        XCTAssertNil(originBound.activeQiMon)
        XCTAssertEqual(originBound.presentationForm, .companion)
        XCTAssertEqual(originBound.cursorPresentationForm, .companion)
        XCTAssertFalse(originBound.cursorAccessibilityValue.contains("Seed cursor"))
        originBound.observeQiMonJourney(projection(fixture.origin))
        assertFirstLightBodyAndSeedCursor(originBound)
        XCTAssertEqual(originBound.activeQiMon, nativeIdentity)
        for invalid in [projection(String(repeating: "b", count: 64)),
                        projection(fixture.origin, storage: .sessionOnly), projection(nil)] {
            originBound.observeQiMonJourney(invalid)
            XCTAssertNil(originBound.activeQiMon)
            XCTAssertEqual(originBound.presentationForm, .companion)
            XCTAssertEqual(originBound.cursorPresentationForm, .companion)
            XCTAssertFalse(originBound.cursorAccessibilityValue.contains("KIN"))
        }
        originBound.observeQiMonJourney(projection(fixture.origin))
        assertFirstLightBodyAndSeedCursor(originBound)
        XCTAssertEqual(try Data(contentsOf: fixture.preferenceURL), bytes)

        // A legacy appearance string without a personal record cannot recreate
        // KIN on either surface. Generic appearances still share their one form.
        let unnamed = try makeFixture(includeKin: false, form: .kin)
        defer { unnamed.clean() }
        XCTAssertNil(unnamed.store.activeQiMon)
        XCTAssertEqual(unnamed.store.presentationForm, .companion)
        XCTAssertEqual(unnamed.store.cursorPresentationForm, .companion)
        unnamed.store.preferences.form = .light
        XCTAssertEqual(unnamed.store.presentationForm, .light)
        XCTAssertEqual(unnamed.store.cursorPresentationForm, .light)
        XCTAssertEqual(unnamed.store.cursorAccessibilityValue, unnamed.store.assistantAccessibilityValue)

        // A well-formed growth archive for a different individual cannot put
        // either that body or a fabricated cursor identity onto the active KIN.
        let foreign = try makeFixture()
        defer { foreign.clean() }
        _ = try retainUse(in: foreign)
        let receipt = try XCTUnwrap(foreign.store.evolution.usefulReceipts.first)
        let candidate = try XCTUnwrap(foreign.store.evolution.proposeKinGrowth(
            originDigest: String(repeating: "d", count: 64), receipt: receipt))
        XCTAssertTrue(foreign.store.evolution.keepKinGrowth(candidate))
        XCTAssertEqual(foreign.store.presentationForm, .kinSeed)
        XCTAssertEqual(foreign.store.cursorPresentationForm, .kinSeed)
        XCTAssertEqual(foreign.store.activeQiMon?.originDigest, foreign.origin)
        XCTAssertEqual(fixture.client.calls + unnamed.client.calls + foreign.client.calls, 0)
        await foreign.store.shutdownAssistant()
        await unnamed.store.shutdownAssistant()
        await originBound.shutdownAssistant()
        await fixture.store.shutdownAssistant()
    }

    @MainActor
    func testActualLiveAndFloatingRenderersKeepTheSeedCursorWhileBodyUnfolds() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let store = fixture.store
        let cursorBefore = try render(LiveCompanionPresence(store: store, size: 128, role: .cursor))
        let floatingBefore = try render(FloatingCompanionBody(store: store).frame(width: 128, height: 154))
        let identity = store.activeQiMon, position = store.position, preferences = store.preferences
        _ = try keepGrowth(in: fixture)
        let cursor = try render(LiveCompanionPresence(store: store, size: 128, role: .cursor))
        let body = try render(LiveCompanionPresence(store: store, size: 128))
        let floating = try render(FloatingCompanionBody(store: store).frame(width: 128, height: 154))
        let seedReference = try render(CompanionPresenceArt(form: .kinSeed, family: nil, size: 128, reduceMotion: true))
        let bodyReference = try render(CompanionPresenceArt(form: .kin, family: nil, size: 128, reduceMotion: true))
        for (first, second, label) in [(cursorBefore, cursor, "cursor before and after growth"),
                                        (cursor, seedReference, "live cursor and Core Seed"),
                                        (body, bodyReference, "live body and First Light"),
                                        (floatingBefore, floating, "actual floating view before and after growth")] {
            let comparison = try NaturalPresentationComparison.compare(first, second)
            XCTAssertTrue(comparison.withinAlphaPresentationBound, "\(label): \(comparison.receipt)")
        }
        XCTAssertNotEqual(body, cursor)
        XCTAssertEqual(store.activeQiMon, identity)
        XCTAssertEqual(store.position, position)
        XCTAssertEqual(store.preferences, preferences)
        XCTAssertEqual(fixture.client.calls, 0)
        try save(cursor, name: "live-seed-cursor.png")
        try save(body, name: "live-first-light-body.png")
        try save(floating, name: "floating-seed-cursor.png")
        if ProcessInfo.processInfo.environment["ARCHI_KIN_CURSOR_RENDER_DIR"] != nil {
            let guide = VStack(spacing: 20) {
                Text("KIN · ONE CONTINUING COMPANION")
                    .font(.system(size: 15, weight: .medium, design: .rounded)).tracking(2)
                HStack(spacing: 40) {
                    VStack(spacing: 12) {
                        LiveCompanionPresence(store: store, size: 200, role: .cursor)
                        Text("Desktop cursor · Core Seed")
                    }
                    VStack(spacing: 12) {
                        LiveCompanionPresence(store: store, size: 200, role: .body)
                        Text("Kept body · First Light")
                    }
                }
                Text("Shared identity, knowledge, light and activity")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
            }
            .font(.system(size: 13, weight: .medium)).foregroundStyle(Color(red: 0.94, green: 0.87, blue: 0.73))
            .padding(28).background(Color(red: 0.07, green: 0.065, blue: 0.08))
            try save(try render(guide), name: "kin-cursor-and-body.png")
        }
        await store.shutdownAssistant()
    }

    @MainActor
    func testActualFloatingPanelAccessibilityTracksGrowthIncomingPreferencesAndActivityWithoutMoving() async throws {
        let activityClient = CursorActivityClient()
        let fixture = try makeFixture(assistant: activityClient)
        defer { fixture.clean() }
        let store = fixture.store, panel = CompanionPanelController(store: fixture.store)
        defer { panel.window.close() }
        let content = try XCTUnwrap(panel.window.contentView)
        let frame = panel.window.frame, position = store.position, placement = store.placementRevision
        let identity = store.activeQiMon, preferences = store.preferences
        let bytes = try Data(contentsOf: fixture.preferenceURL)
        XCTAssertFalse(panel.window.isVisible)
        XCTAssertFalse(panel.window.isKeyWindow)
        XCTAssertEqual(content.accessibilityValue() as? String, store.cursorAccessibilityValue)
        XCTAssertTrue((content.accessibilityValue() as? String)?.contains("Seed cursor") == true)
        _ = try keepGrowth(in: fixture)
        XCTAssertEqual(content.accessibilityValue() as? String, store.cursorAccessibilityValue)
        XCTAssertFalse((content.accessibilityValue() as? String)?.contains("First Light") == true)
        XCTAssertTrue(store.assistantAccessibilityValue.contains("First Light"))
        XCTAssertTrue(store.evolution.save())
        store.returnKinToSeed()
        XCTAssertEqual(content.accessibilityValue() as? String, store.cursorAccessibilityValue)
        XCTAssertTrue(store.evolution.load())
        assertFirstLightBodyAndSeedCursor(store)
        XCTAssertEqual(content.accessibilityValue() as? String, store.cursorAccessibilityValue)

        // A @Published preference is delivered before storage is updated. AX
        // must use the supplied value immediately, not the previous equipment.
        store.preferences.equipment = CompanionEquipment(hand: .focusStaff)
        XCTAssertTrue((content.accessibilityValue() as? String)?.contains("Focus Staff") == true)
        XCTAssertEqual(content.accessibilityValue() as? String, store.cursorAccessibilityValue)
        for expected in [AssistantActivity.ready, .failed, .stopped] {
            store.connectAssistant(provider: .qwen)
            try await waitUntil { store.connection(for: .qwen) == .ready }
            store.prompt = "Describe this synthetic cursor test."
            store.submit()
            try await waitUntil { activityClient.hasPending }
            XCTAssertEqual(store.assistantActivity, .working)
            try await waitUntil { (content.accessibilityValue() as? String) == store.cursorAccessibilityValue }
            XCTAssertTrue((content.accessibilityValue() as? String)?.contains("Assistant: Working") == true)
            switch expected {
            case .ready:
                activityClient.emit("Synthetic completed answer.")
                XCTAssertEqual(store.assistantActivity, .responding)
                try await waitUntil { (content.accessibilityValue() as? String) == store.cursorAccessibilityValue }
                XCTAssertTrue((content.accessibilityValue() as? String)?.contains("Assistant: Responding") == true)
                activityClient.finish()
            case .failed: activityClient.fail()
            default: store.cancelWork()
            }
            try await waitUntil { !store.isWorking && store.assistantActivity == expected }
            try await waitUntil { (content.accessibilityValue() as? String) == store.cursorAccessibilityValue }
            XCTAssertEqual(store.assistantActivity, expected)
            let value = try XCTUnwrap(content.accessibilityValue() as? String)
            XCTAssertTrue(value.contains("Assistant: " + expected.title))
            XCTAssertTrue(value.contains("Seed cursor"))
            XCTAssertFalse(value.contains("First Light"))
        }
        store.connectAssistant(provider: .qwen)
        try await waitUntil { store.connection(for: .qwen) == .ready }
        store.prompt = "Describe another synthetic cursor test."
        store.submit()
        try await waitUntil { activityClient.hasPending }
        activityClient.emit("Synthetic answer for a Quiet cue.")
        activityClient.finish()
        try await waitUntil { !store.isWorking && store.assistantActivity == .ready }
        try await waitUntil { (content.accessibilityValue() as? String) == store.cursorAccessibilityValue }
        let activeValue = try XCTUnwrap(content.accessibilityValue() as? String)
        store.preferences.quiet = true
        let quietValue = try XCTUnwrap(content.accessibilityValue() as? String)
        XCTAssertEqual(quietValue, store.cursorAccessibilityValue)
        XCTAssertNotEqual(quietValue, activeValue, "Quiet must immediately report the resting light")
        // A deliberate local route change clears results through the supported
        // owner; this does not connect or send to an external model.
        store.setAssistantRoute(.automatic)
        store.setAssistantRoute(.local)
        store.preferences = preferences
        try await waitUntil { (content.accessibilityValue() as? String) == store.cursorAccessibilityValue }
        XCTAssertTrue((content.accessibilityValue() as? String)?.contains("Assistant: Idle") == true)
        XCTAssertEqual(panel.window.frame, frame)
        XCTAssertEqual(store.position, position)
        XCTAssertEqual(store.placementRevision, placement)
        XCTAssertEqual(store.activeQiMon, identity)
        XCTAssertEqual(store.preferences, preferences)
        XCTAssertEqual(try Data(contentsOf: fixture.preferenceURL), bytes)
        XCTAssertFalse(panel.window.isVisible)
        XCTAssertFalse(panel.window.isKeyWindow)
        XCTAssertEqual(fixture.client.calls, 0)
        XCTAssertEqual(activityClient.requests.count, 4, "Four in-process scripted requests; no model transport is present")
        await store.shutdownAssistant()
    }

    @MainActor private func assertFirstLightBodyAndSeedCursor(_ store: CompanionStore,
                                                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(store.presentationForm, .kin, file: file, line: line)
        XCTAssertEqual(store.cursorPresentationForm, .kinSeed, file: file, line: line)
        XCTAssertTrue(store.assistantAccessibilityValue.contains("First Light"), file: file, line: line)
        XCTAssertTrue(store.cursorAccessibilityValue.contains("Seed cursor"), file: file, line: line)
        XCTAssertTrue(store.cursorAccessibilityValue.contains("Core Seed"), file: file, line: line)
        XCTAssertFalse(store.cursorAccessibilityValue.contains("First Light"), file: file, line: line)
    }

    @MainActor private func makeFixture(includeKin: Bool = true, form: CompanionForm = .companion,
                                       assistant: (any AssistantClient)? = nil) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kin-cursor-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let preferenceURL = directory.appendingPathComponent("preferences.json")
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let origin = String(repeating: "a", count: 64)
        let lesson = KeptLesson(topic: "Writing plans", text: "Begin with one useful next step.", createdAt: now)
        var preferences = CompanionPreferences()
        preferences.form = form
        preferences.reduceMotion = true
        preferences.tone = "Warm"
        let kin = LocalQiMon(character: .kin, originDigest: origin, welcomedAt: now)
        try NativePreferenceDocument(preferences: preferences, lessons: [lesson], qiMon: includeKin ? kin : nil)
            .encoded().write(to: preferenceURL)
        let client = CursorNoCalls()
        let actualAssistant: any AssistantClient = assistant ?? client
        let store = CompanionStore(preferenceURL: preferenceURL, assistant: actualAssistant,
            assistantFactory: { _, _ in actualAssistant }, wallClock: { now }, allowsPlay: false)
        store.placed(at: CGPoint(x: 500, y: 350))
        return Fixture(directory: directory, preferenceURL: preferenceURL, origin: origin, now: now,
            lesson: lesson, client: client, store: store)
    }

    @MainActor private func retainUse(in fixture: Fixture) throws -> UUID {
        let requestID = UUID(), snapshot = LessonSnapshot(lesson: fixture.lesson)
        let source = String(repeating: "b", count: 64)
        var receipt = AssistantLaneReceipt(requestID: requestID.uuidString, route: .local, provider: .qwen,
            context: fixture.store.contextTicket(), inputDigest: String(repeating: "c", count: 64),
            sourceDigest: source, inputContract: "native-assistant-input/v4", deadline: .distantFuture,
            modelIdentity: "synthetic-cursor-fixture", state: .complete)
        receipt.localLessons = [snapshot]
        receipt.usedLessonIDs = [snapshot.modelID]
        XCTAssertTrue(fixture.store.evolution.markUseful(receipt: receipt, sourceDigest: source, confirmedLesson: snapshot))
        return requestID
    }

    @MainActor @discardableResult private func keepGrowth(in fixture: Fixture) throws -> UUID {
        let requestID = try retainUse(in: fixture)
        XCTAssertTrue(fixture.store.previewKinGrowth(receiptID: requestID))
        XCTAssertTrue(fixture.store.keepKinGrowth())
        return requestID
    }

    private func projection(_ origin: String?, storage: HostedPlayProjection.Storage = .localBrowser) -> HostedPlayProjection {
        HostedPlayProjection(version: 3, host: "archi-desktop", sessionId: UUID().uuidString,
            sequence: 1, kind: "journey-projection", readiness: .ready, storage: storage, mode: .habitat,
            journeyId: "ARCHI-AAAAAAAA", revision: "synthetic-revision", eventCount: 0, visible: false,
            originDigest: origin, practices: [], arena: nil)
    }

    @MainActor private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Native cursor accessibility did not reflect the existing store within its bounded delivery time")
    }

    @MainActor private func render<V: View>(_ view: V) throws -> Data {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let tiff = try XCTUnwrap(renderer.nsImage?.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }

    private func save(_ data: Data, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_KIN_CURSOR_RENDER_DIR"] else { return }
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name))
    }

    @MainActor private struct Fixture {
        let directory: URL
        let preferenceURL: URL
        let origin: String
        let now: Date
        let lesson: KeptLesson
        let client: CursorNoCalls
        let store: CompanionStore
        func reopen(allowsPlay: Bool = false) -> CompanionStore {
            CompanionStore(preferenceURL: preferenceURL, assistant: client,
                assistantFactory: { _, _ in client }, wallClock: { now }, allowsPlay: allowsPlay)
        }
        func clean() { try? FileManager.default.removeItem(at: directory) }
    }
}

@MainActor private final class CursorNoCalls: AssistantClient {
    private(set) var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.configuration }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1
        throw AssistantFailure.configuration
    }
    func disconnect() {}
}

/// Controls the real CompanionStore request lifecycle entirely in process.
/// There is no Ollama, Codex, network or other model invocation in this client.
@MainActor private final class CursorActivityClient: AssistantClient {
    private(set) var requests: [AssistantRequest] = []
    private var pending: CheckedContinuation<Void, Error>?
    private var onEvent: (@MainActor (AssistantEvent) -> Void)?
    var hasPending: Bool { pending != nil }
    func connect() async throws {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        requests.append(request)
        self.onEvent = onEvent
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func emit(_ text: String) { onEvent?(.text(text)) }
    func finish() {
        let continuation = pending
        pending = nil; onEvent = nil
        continuation?.resume()
    }
    func fail() {
        let continuation = pending
        pending = nil; onEvent = nil
        continuation?.resume(throwing: AssistantFailure.turnFailed)
    }
    func disconnect() {
        let continuation = pending
        pending = nil; onEvent = nil
        continuation?.resume(throwing: AssistantFailure.stopped)
    }
}
