import AppKit
import CryptoKit
import XCTest
@testable import ARCHiDesktop

final class PointAndExplainTests: XCTestCase {
    @MainActor
    func testUnavailableBusyHiddenAndOffscreenTargetsSendNothing() async throws {
        let changes: [(PointHelpFixture) -> Void] = [
            { $0.store.preferences.equipment = .empty },
            { $0.store.hideCompanion() },
            { $0.store.clearTextSelection() },
            { $0.store.isWorking = true },
            { $0.store.onObserveSelectedPassage = { nil } },
            { $0.geometry = $0.offsetGeometry(dy: 500) },
            { $0.store.sharedText = "The selection no longer matches." },
            { $0.store.prompt = String(repeating: "a", count: 16_000) }
        ]
        for change in changes {
            let f = PointHelpFixture(); defer { f.cleanup() }
            try await f.connect(.local)
            change(f)
            XCTAssertFalse(f.store.pointAndExplainSelection())
            await Task.yield()
            XCTAssertTrue(f.local.replies.isEmpty)
            XCTAssertTrue(f.cloud.replies.isEmpty)
            XCTAssertNil(f.store.focusGesturePlayback)
            XCTAssertNil(f.store.spatialPreview)
            XCTAssertTrue(f.moves.isEmpty)
        }
        let disconnected = PointHelpFixture(); defer { disconnected.cleanup() }
        XCTAssertFalse(disconnected.store.canPointAndExplainSelection)
        XCTAssertFalse(disconnected.store.pointAndExplainSelection())
        XCTAssertEqual(disconnected.local.connectCount, 0)
        XCTAssertEqual(disconnected.cloud.connectCount, 0)
        XCTAssertTrue(disconnected.local.replies.isEmpty)
    }

    @MainActor
    func testCompareRequiresBothConnectionsBeforeEitherRequest() async throws {
        for ready in [AssistantProvider.qwen, .codex] {
            let f = PointHelpFixture(); defer { f.cleanup() }
            f.store.setAssistantRoute(.compare)
            f.store.connectAssistant(provider: ready)
            try await waitForPointHelp("Single connection ready") { f.store.connection(for: ready) == .ready }
            XCTAssertFalse(f.store.canPointAndExplainSelection)
            XCTAssertFalse(f.store.pointAndExplainSelection())
            await Task.yield()
            XCTAssertTrue(f.local.replies.isEmpty)
            XCTAssertTrue(f.cloud.replies.isEmpty)
            XCTAssertNil(f.store.focusGesturePlayback)
        }
    }

    @MainActor
    func testEachRouteSendsExactlyOnceAndPreservesComposerRevisionModeAndCopy() async throws {
        for route in AssistantRoute.allCases {
            let f = PointHelpFixture(); defer { f.cleanup() }
            try await f.connect(route)
            f.store.prompt = "Use two short sentences for this explanation."
            f.store.requestsRevision = true
            let source = f.store.sharedText, selection = f.store.textSelection
            let revision = f.store.evolution.revision, position = f.store.position
            XCTAssertTrue(f.store.canPointAndExplainSelection)
            XCTAssertTrue(f.store.pointAndExplainSelection())
            XCTAssertFalse(f.store.pointAndExplainSelection(), "A second click while working must not dispatch again")
            try await f.waitForRequests(route)
            for provider in route.providers {
                let request = try XCTUnwrap(f.client(provider).replies.first?.request)
                XCTAssertEqual(request.prompt, "Explain the selected passage.\n\nMy instructions for this explanation:\nUse two short sentences for this explanation.")
                XCTAssertEqual(request.sourceText, source)
                XCTAssertEqual(request.selection, selection)
                XCTAssertNil(request.revisionTarget, "This action explains even when the draft was prepared for revision")
                XCTAssertTrue(request.hasValidSelection)
                XCTAssertNil(request.settings.role)
                XCTAssertNil(request.settings.helpStyle)
                XCTAssertEqual(f.client(provider).replies.count, 1)
                XCTAssertTrue(f.store.compareResults[provider]?.receipt?.requestStarted == true)
            }
            XCTAssertEqual(f.local.replies.count, route.providers.contains(.qwen) ? 1 : 0)
            XCTAssertEqual(f.cloud.replies.count, route.providers.contains(.codex) ? 1 : 0)
            XCTAssertEqual(f.store.prompt, "Use two short sentences for this explanation.")
            XCTAssertTrue(f.store.requestsRevision)
            XCTAssertEqual(f.store.focusGesturePlayback?.purpose, .explaining)
            for provider in route.providers {
                f.client(provider).emit(0, text: "An explanation of this passage.")
                f.client(provider).resolve(0)
            }
            try await waitForPointHelp("All selected lanes complete") { !f.store.isWorking }
            XCTAssertTrue(route.providers.allSatisfy { f.store.compareResults[$0]?.state == .complete })
            XCTAssertNil(f.store.focusGesturePlayback)
            XCTAssertNil(f.store.spatialPreview)
            XCTAssertEqual(f.store.sharedText, source)
            XCTAssertEqual(f.store.evolution.revision, revision)
            XCTAssertEqual(f.store.position, position)
            XCTAssertFalse(f.store.hasUnexportedWorkingCopy)
            XCTAssertTrue(f.moves.isEmpty)
        }
    }

    @MainActor
    func testUsesKeptGestureAndCapturesSettingsAndOnlyEligibleLocalLessonsInCompare() async throws {
        let f = PointHelpFixture(); defer { f.cleanup() }
        f.store.beginFocusGestureTeaching()
        let kept = FocusGestureConfiguration(pace: .quick, sparkle: .none, hold: .brief)
        f.store.focusGestureDraft = kept
        XCTAssertTrue(f.store.keepFocusGesture())
        try f.keepLesson(topic: "selected passage", text: "Explain with one concrete example.")
        try f.keepLesson(topic: "gardening", text: "Discuss the soil first.")
        f.store.beginFocusGestureTeaching()
        let draft = FocusGestureConfiguration(pace: .unhurried, sparkle: .bright, hold: .lingering)
        f.store.focusGestureDraft = draft
        f.store.section = .context
        // The lesson editor leaves Work together, retiring its spatial scope.
        // Re-select the current passage as a native user must on return.
        f.store.selectText(range: f.geometry.selection.range, sourceRevision: f.store.sourceRevision)
        f.store.preferences.tone = "Warm"
        f.store.preferences.replyLength = 0.8
        f.store.evolution.confirmRole(.muse)
        f.store.evolution.confirmHelpStyle(.stepByStep)
        try await f.connect(.compare)
        let settings = f.store.nextReplySettings
        let lessons = f.store.matchingLessons(question: "Explain the selected passage.")
        XCTAssertEqual(lessons.count, 1)
        XCTAssertTrue(f.store.pointAndExplainSelection())
        XCTAssertEqual(f.store.focusGesturePlayback?.configuration, kept)
        XCTAssertEqual(f.store.focusGestureDraft, draft)
        f.store.prompt = "A later unsent draft."
        f.store.evolution.confirmRole(.beacon)
        f.store.evolution.confirmHelpStyle(.concise)
        try await f.waitForRequests(.compare)
        let local = try XCTUnwrap(f.local.replies.first?.request)
        let cloud = try XCTUnwrap(f.cloud.replies.first?.request)
        XCTAssertEqual(local.settings, settings)
        XCTAssertEqual(cloud.settings, settings)
        XCTAssertNotEqual(f.store.nextReplySettings, settings)
        XCTAssertEqual(local.localLessons, lessons)
        XCTAssertTrue(cloud.localLessons.isEmpty)
        XCTAssertEqual(try decoded(local.input), try decoded(cloud.input))
        XCTAssertFalse(local.input.contains(lessons[0].text))
        XCTAssertFalse(cloud.localInput.contains(lessons[0].text))
        XCTAssertTrue(local.localInput.contains(lessons[0].text))
        let localReceipt = try XCTUnwrap(f.store.compareResults[.qwen]?.receipt)
        let cloudReceipt = try XCTUnwrap(f.store.compareResults[.codex]?.receipt)
        XCTAssertEqual(localReceipt.requestID, cloudReceipt.requestID)
        XCTAssertEqual(localReceipt.inputDigest, cloudReceipt.inputDigest)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let expectedDigest = SHA256.hash(data: try encoder.encode(decoded(local.input)))
            .map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(localReceipt.inputDigest, expectedDigest)
        for receipt in [localReceipt, cloudReceipt] {
            XCTAssertEqual(receipt.settings, settings)
            XCTAssertEqual(receipt.pointing?.gesture, kept)
            XCTAssertEqual(receipt.pointing?.geometry, f.geometry)
            XCTAssertEqual(receipt.pointing?.environment, f.environment)
            XCTAssertFalse(local.input.contains("companionFrame"), "Native rectangles remain outside the model request")
        }
        XCTAssertEqual(localReceipt.localLessons, lessons)
        XCTAssertTrue(cloudReceipt.localLessons.isEmpty)
        XCTAssertNotNil(localReceipt.localLessonDigest)
        XCTAssertNil(cloudReceipt.localLessonDigest)
    }

    @MainActor
    func testStopCancelsBothOwnersAndLateEventsCannotReviveStoppedOrReplacementWork() async throws {
        let f = PointHelpFixture(); defer { f.cleanup() }
        try await f.connect(.compare)
        XCTAssertTrue(f.store.pointAndExplainSelection())
        try await f.waitForRequests(.compare)
        let oldGesture = try XCTUnwrap(f.store.focusGesturePlayback)
        f.local.emit(0, text: "Partial explanation")
        f.store.stopFocusGesture()
        XCTAssertFalse(f.store.isWorking)
        XCTAssertNil(f.store.focusGesturePlayback)
        XCTAssertNil(f.store.spatialPreview)
        XCTAssertTrue(f.store.compareResults.values.allSatisfy { $0.state == .cancelled })
        try await f.connect(.compare)
        XCTAssertTrue(f.store.pointAndExplainSelection())
        try await waitForPointHelp("Replacement requests begin") { f.local.replies.count == 2 && f.cloud.replies.count == 2 }
        let replacement = try XCTUnwrap(f.store.focusGesturePlayback)
        XCTAssertNotEqual(oldGesture.id, replacement.id)
        f.local.emit(0, text: "Obsolete local text")
        f.cloud.emit(0, text: "Obsolete cloud text")
        f.local.resolve(0, result: .failure(AssistantFailure.turnFailed))
        f.cloud.resolve(0)
        try await waitForPointHelp("Old continuations drain") { f.local.finished.contains(0) && f.cloud.finished.contains(0) }
        XCTAssertTrue(f.store.isWorking)
        XCTAssertEqual(f.store.focusGesturePlayback?.id, replacement.id)
        XCTAssertFalse(f.store.validateFocusGesturePlayback(id: oldGesture.id))
        XCTAssertFalse(f.store.compareResults.values.contains { $0.text.contains("Obsolete") })
        for client in [f.local, f.cloud] { client.emit(1, text: "Current explanation"); client.resolve(1) }
        try await waitForPointHelp("Replacement completes") { !f.store.isWorking }
        XCTAssertEqual(f.store.assistantActivity, .ready)
        XCTAssertNil(f.store.focusGesturePlayback)
    }

    @MainActor
    func testSourcePlacementAndVisibilityChangesCancelAndFenceLateAnswers() async throws {
        let changes: [(CompanionStore) -> Void] = [
            { $0.share(text: "New source", name: "replacement.txt") },
            { $0.placed(at: CGPoint(x: 10, y: 20)) },
            { $0.hideCompanion() },
            { $0.clearTextSelection() }
        ]
        for change in changes {
            let f = PointHelpFixture(); defer { f.cleanup() }
            try await f.connect(.local)
            XCTAssertTrue(f.store.pointAndExplainSelection())
            try await f.waitForRequests(.local)
            change(f.store)
            XCTAssertFalse(f.store.isWorking)
            XCTAssertNil(f.store.focusGesturePlayback)
            XCTAssertNil(f.store.spatialPreview)
            let status = f.store.status, reply = f.store.reply
            f.local.emit(0, text: "Late answer to an old target")
            f.local.resolve(0)
            try await waitForPointHelp("Invalidated answer drains") { f.local.finished.contains(0) }
            XCTAssertEqual(f.store.status, status)
            XCTAssertEqual(f.store.reply, reply)
            XCTAssertFalse(f.store.compareResults.values.contains { $0.state == .complete })
            XCTAssertTrue(f.moves.isEmpty)
        }
    }

    @MainActor
    func testUnannouncedGeometryChangeAfterGestureExpiryRejectsLateTextAndCompletion() async throws {
        for changeEnvironment in [false, true] {
            let f = PointHelpFixture(); defer { f.cleanup() }
            try await f.connect(.local)
            XCTAssertTrue(f.store.pointAndExplainSelection())
            try await f.waitForRequests(.local)
            let gesture = try XCTUnwrap(f.store.focusGesturePlayback)
            f.clock.now += gesture.configuration.duration + 0.1
            XCTAssertFalse(f.store.validateFocusGesturePlayback(id: gesture.id))
            XCTAssertNil(f.store.focusGesturePlayback)
            XCTAssertTrue(f.store.isWorking, "A finished visual cue must not pretend the answer is finished")
            if changeEnvironment { f.shiftCompanionGeometry() }
            else { f.geometry = f.offsetGeometry(dy: 1) }
            // Exercise both streaming-event admission and silent completion admission.
            if !changeEnvironment { f.local.emit(0, text: "Wrong-location answer") }
            f.local.resolve(0)
            try await waitForPointHelp("Stale answer drains") { f.local.finished.contains(0) }
            XCTAssertFalse(f.store.isWorking)
            XCTAssertNil(f.store.spatialPreview)
            XCTAssertNotEqual(f.store.reply, "Wrong-location answer")
            XCTAssertEqual(f.store.compareResults[.qwen]?.state, .cancelled)
            XCTAssertTrue(f.moves.isEmpty)
        }
    }

    @MainActor
    func testPreviewCallbackChangingGeometryBeforeDispatchMakesZeroRequests() async throws {
        let f = PointHelpFixture(); defer { f.cleanup() }
        try await f.connect(.compare)
        f.store.onPresentPlacementPreview = { [weak f] preview in
            guard preview != nil else { return }
            f?.shiftCompanionGeometry()
        }
        _ = f.store.pointAndExplainSelection()
        try await waitForPointHelp("Changed native target cancels before either transport starts") { !f.store.isWorking }
        XCTAssertTrue(f.local.replies.isEmpty)
        XCTAssertTrue(f.cloud.replies.isEmpty)
        XCTAssertNil(f.store.focusGesturePlayback)
        XCTAssertNil(f.store.spatialPreview)
        XCTAssertTrue(f.store.compareResults.values.allSatisfy { $0.receipt?.requestStarted == false })
        XCTAssertTrue(f.moves.isEmpty)
    }

    @MainActor
    func testFailureRetiresPointingAndKeepsTheWorkingCopyIntact() async throws {
        let f = PointHelpFixture(); defer { f.cleanup() }
        try await f.connect(.local)
        let source = f.store.sharedText
        XCTAssertTrue(f.store.pointAndExplainSelection())
        try await f.waitForRequests(.local)
        f.local.emit(0, text: "An incomplete thought")
        f.local.resolve(0, result: .failure(AssistantFailure.timedOut))
        try await waitForPointHelp("The failed lane finishes") { !f.store.isWorking }
        XCTAssertEqual(f.store.compareResults[.qwen]?.state, .failed)
        XCTAssertEqual(f.store.assistantActivity, .failed)
        XCTAssertNil(f.store.focusGesturePlayback)
        XCTAssertNil(f.store.spatialPreview)
        XCTAssertFalse(f.store.reply.contains("An incomplete thought"))
        XCTAssertEqual(f.store.sharedText, source)
        XCTAssertFalse(f.store.hasUnexportedWorkingCopy)
    }

    @MainActor
    func testPartialCompareFailureKeepsTheSurvivingLaneAndRetiresCueOnLastResult() async throws {
        for failure in [AssistantProvider.qwen, .codex] {
            let f = PointHelpFixture(); defer { f.cleanup() }
            try await f.connect(.compare)
            XCTAssertTrue(f.store.pointAndExplainSelection())
            try await f.waitForRequests(.compare)
            let survivor: AssistantProvider = failure == .qwen ? .codex : .qwen
            f.client(failure).resolve(0, result: .failure(AssistantFailure.turnFailed))
            try await waitForPointHelp("Failing lane finishes independently") { f.store.compareResults[failure]?.state == .failed }
            XCTAssertTrue(f.store.isWorking)
            XCTAssertEqual(f.store.compareResults[survivor]?.state, .pending)
            XCTAssertEqual(f.store.focusGesturePlayback?.purpose, .explaining)
            XCTAssertNotNil(f.store.spatialPreview)
            f.client(survivor).emit(0, text: "A completed independent answer")
            f.client(survivor).resolve(0)
            try await waitForPointHelp("Remaining answer finishes") { !f.store.isWorking }
            XCTAssertEqual(f.store.compareResults[survivor]?.state, .complete)
            XCTAssertEqual(f.store.compareResults[failure]?.state, .failed)
            XCTAssertEqual(f.store.assistantActivity, .ready)
            XCTAssertNil(f.store.focusGesturePlayback)
            XCTAssertNil(f.store.spatialPreview)
            XCTAssertTrue(f.moves.isEmpty)
        }
    }

    @MainActor
    func testAnUnchangedTargetAcceptsAnAnswerAfterItsShortGestureFinishes() async throws {
        let f = PointHelpFixture(); defer { f.cleanup() }
        try await f.connect(.local)
        XCTAssertTrue(f.store.pointAndExplainSelection())
        try await f.waitForRequests(.local)
        let gesture = try XCTUnwrap(f.store.focusGesturePlayback)
        f.clock.now += gesture.configuration.duration + 0.1
        XCTAssertFalse(f.store.validateFocusGesturePlayback(id: gesture.id))
        XCTAssertTrue(f.store.isWorking)
        f.local.emit(0, text: "A useful explanation arrived after the animation.")
        f.local.resolve(0)
        try await waitForPointHelp("Still-current answer finishes") { !f.store.isWorking }
        XCTAssertEqual(f.store.compareResults[.qwen]?.state, .complete)
        XCTAssertEqual(f.store.reply, "A useful explanation arrived after the animation.")
        XCTAssertNil(f.store.focusGesturePlayback)
        XCTAssertNil(f.store.spatialPreview, "Finishing the last explaining lane retires its highlight even after motion ended")
        XCTAssertTrue(f.moves.isEmpty)
    }

    @MainActor
    func testHamptonRejectsStalePointingBeforeCommittingTentativeContextAfterGestureExpires() async throws {
        let reasoner = PointHelpRoleClient(), selector = PointHelpRoleClient()
        let assistant = HamptonReasonsAssistant(reasoner: reasoner, contextSelector: selector)
        let f = PointHelpFixture(localAssistant: assistant)
        defer { f.cleanup(); reasoner.drain(); selector.drain() }
        f.store.setSessionContextEnabled(true)
        try await f.connect(.local)
        f.store.prompt = "An earlier user constraint worth retaining."
        f.store.submit()
        try await waitForPointHelp("Baseline Hampton answer commits") {
            f.store.compareResults[.qwen]?.state == .complete
        }
        let baselineRecords = assistant.snapshot.records
        let baselineTurn = assistant.snapshot.turn
        XCTAssertEqual(baselineTurn, 1)
        XCTAssertEqual(baselineRecords.count, 1)
        XCTAssertEqual(baselineRecords.first?.text, "An earlier user constraint worth retaining.")
        XCTAssertNil(baselineRecords.first?.lastReminderTurn)

        reasoner.hold = true
        f.store.prompt = "Use one concrete example."
        XCTAssertTrue(f.store.pointAndExplainSelection())
        try await waitForPointHelp("Pointed answer pauses at the real Hampton reasoning boundary") {
            reasoner.pendingIndices == [1]
        }
        XCTAssertEqual(selector.requests.map(\.role), [.memorySelection, .memorySelection, .memoryReminder])
        let reminder = try XCTUnwrap(selector.requests.last)
        XCTAssertEqual(reminder.input["memories"]?.array?.first?["id"]?.string, baselineRecords.first?.id)
        XCTAssertEqual(assistant.snapshot.attemptedInvocations, [.memorySelection, .memoryReminder, .reasoning])
        XCTAssertEqual(assistant.snapshot.records, baselineRecords, "The additional selected question and reminder use are still tentative")
        let gesture = try XCTUnwrap(f.store.focusGesturePlayback)
        f.clock.now += gesture.configuration.duration + 0.1
        XCTAssertFalse(f.store.validateFocusGesturePlayback(id: gesture.id))
        XCTAssertNil(f.store.focusGesturePlayback)
        XCTAssertTrue(f.store.isWorking)
        // No source/placement notification is delivered. The model returns a
        // structurally valid result after the animation's ownership has ended.
        f.shiftCompanionGeometry()
        reasoner.resolve(1)
        try await waitForPointHelp("Native admission rejects the result and the lane drains") {
            reasoner.finished.contains(1) && !f.store.isWorking
        }
        XCTAssertEqual(reasoner.generatedResults.count, 2, "Both baseline and late results were valid fixture payloads")
        XCTAssertEqual(f.store.compareResults[.qwen]?.state, .cancelled)
        XCTAssertEqual(assistant.snapshot.records, baselineRecords)
        XCTAssertEqual(assistant.snapshot.turn, baselineTurn)
        XCTAssertEqual(f.store.hamptonSnapshot.records, baselineRecords)
        XCTAssertEqual(f.store.hamptonSnapshot.turn, baselineTurn)
        XCTAssertNil(assistant.snapshot.proposal)
        XCTAssertNil(f.store.focusGesturePlayback)
        XCTAssertNil(f.store.spatialPreview)
        XCTAssertFalse(f.store.reply.contains("Validated Hampton fixture answer"))
        XCTAssertTrue(f.moves.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.directory.appendingPathComponent("preferences.json").path))
    }

    private func decoded(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }
}

@MainActor
private final class PointHelpFixture {
    final class Clock { var now: TimeInterval = 10 }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-point-help-\(UUID())")
    let clock = Clock()
    let local = PointHelpClient(), cloud = PointHelpClient()
    let store: CompanionStore
    var geometry: SelectedPassageGeometry
    var environment: SpatialEnvironment
    var moves: [CGRect] = []

    init(localAssistant: (any AssistantClient)? = nil) {
        let clock = clock, local = local, cloud = cloud
        store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"),
            assistant: localAssistant ?? local, assistantFactory: { provider, _ in provider == .qwen ? local : cloud },
            monotonicTime: { clock.now })
        store.section = .context
        store.preferences.form = .particle
        store.preferences.equipment = CompanionEquipment(hand: .focusStaff)
        store.evolution.observeJourneyOrigin(String(repeating: "b", count: 64))
        store.share(text: "A useful passage. Another sentence.", name: "practice.txt")
        store.selectText(range: NSRange(location: 0, length: 17), sourceRevision: store.sourceRevision)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        geometry = SelectedPassageGeometry(selection: store.textSelection!,
            rects: [CGRect(x: 300, y: 500, width: 220, height: 20)],
            viewport: CGRect(x: 280, y: 300, width: 340, height: 300),
            windowFrame: CGRect(x: 200, y: 100, width: 1000, height: 700),
            windowNumber: 12, screenID: 1, screenFrame: screen)
        environment = SpatialEnvironment(companionFrame: CGRect(x: 360, y: 450, width: 128, height: 154),
            displays: [SpatialDisplay(id: 1, frame: screen, visibleFrame: screen)])
        store.onObserveSelectedPassage = { [weak self] in self?.geometry }
        store.onObserveSpatialEnvironment = { [weak self] in self?.environment }
        store.onMoveCompanion = { [weak self] frame in self?.moves.append(frame) }
    }

    func client(_ provider: AssistantProvider) -> PointHelpClient { provider == .qwen ? local : cloud }
    func connect(_ route: AssistantRoute) async throws {
        store.setAssistantRoute(route)
        store.connectAssistant()
        try await waitForPointHelp("Chosen connections become ready") { route.providers.allSatisfy { self.store.connection(for: $0) == .ready } }
    }
    func waitForRequests(_ route: AssistantRoute) async throws {
        try await waitForPointHelp("Chosen request lanes start") { route.providers.allSatisfy { self.client($0).replies.count == 1 } }
    }
    func keepLesson(topic: String, text: String) throws {
        store.beginLessonCorrection()
        store.lessonDraft?.topic = topic
        store.lessonDraft?.text = text
        XCTAssertTrue(store.keepLesson(try XCTUnwrap(store.lessonDraft)))
    }
    func offsetGeometry(dy: CGFloat) -> SelectedPassageGeometry {
        SelectedPassageGeometry(selection: geometry.selection, rects: geometry.rects.map { $0.offsetBy(dx: 0, dy: dy) },
            viewport: geometry.viewport, windowFrame: geometry.windowFrame, windowNumber: geometry.windowNumber,
            screenID: geometry.screenID, screenFrame: geometry.screenFrame)
    }
    func shiftCompanionGeometry() {
        environment = SpatialEnvironment(companionFrame: environment.companionFrame.offsetBy(dx: 1, dy: 0), displays: environment.displays)
    }
    func cleanup() {
        store.cancelWork()
        store.disconnectAssistant(provider: .qwen)
        store.disconnectAssistant(provider: .codex)
        local.drain(); cloud.drain()
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class PointHelpClient: AssistantClient {
    struct Reply {
        let request: AssistantRequest
        let onEvent: @MainActor (AssistantEvent) -> Void
    }
    var connectCount = 0
    private(set) var replies: [Reply] = []
    private(set) var finished = Set<Int>()
    private var pending: [Int: CheckedContinuation<Void, any Error>] = [:]
    func connect() async throws { connectCount += 1 }
    func disconnect() {} // Keep late callbacks available to exercise the store's ownership boundary.
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        let index = replies.count
        replies.append(Reply(request: request, onEvent: onEvent))
        defer { finished.insert(index) }
        try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func emit(_ index: Int, text: String) { replies[index].onEvent(.text(text)) }
    func resolve(_ index: Int, result: Result<Void, any Error> = .success(())) {
        guard let continuation = pending.removeValue(forKey: index) else { XCTFail("Request \(index) was not pending"); return }
        continuation.resume(with: result)
    }
    func drain() {
        let work = Array(pending.values); pending.removeAll()
        for continuation in work { continuation.resume(throwing: AssistantFailure.stopped) }
    }
}

private enum PointHelpWaitFailure: Error { case timedOut }

/// Exercises the actual Hampton coordinator entirely in process. Selection
/// retains a new exact question, reminder uses an earlier record, and the held
/// reasoner returns valid JSON even after disconnect to stress final admission.
@MainActor
private final class PointHelpRoleClient: LocalRoleClient {
    var hold = false
    private(set) var requests: [LocalRoleRequest] = []
    private(set) var generatedResults: [LocalRoleResult] = []
    private(set) var finished = Set<Int>()
    private var pending: [Int: CheckedContinuation<Void, any Error>] = [:]
    var pendingIndices: Set<Int> { Set(pending.keys) }
    func connect() async throws {}
    func disconnect() {}
    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
        let index = requests.count
        requests.append(request)
        defer { finished.insert(index) }
        if hold { try await withCheckedThrowingContinuation { pending[index] = $0 } }
        func ids(_ key: String) -> [String] {
            request.input[key]?.array?.prefix(1).compactMap { $0["id"]?.string } ?? []
        }
        var payload: [String: JSONValue] = ["requestID": .string(request.id)]
        switch request.role {
        case .memorySelection:
            payload["schema"] = .string("archi-session-selection/v1")
            payload["candidateIDs"] = .array(ids("candidates").map(JSONValue.string))
        case .memoryReminder:
            let selected = ids("memories")
            payload["schema"] = .string("archi-session-reminder/v1")
            payload["decision"] = .string(selected.isEmpty ? "NONE" : "SELECT")
            payload["memoryIDs"] = .array(selected.map(JSONValue.string))
        case .reasoning:
            payload["schema"] = .string("archi-reason-proposal/v1")
            payload["kind"] = .string("ANSWER")
            payload["answer"] = .string("Validated Hampton fixture answer")
            payload["uncertainty"] = .string("")
            payload["sourceIDs"] = .array(ids("sources").map(JSONValue.string))
            payload["memoryIDs"] = .array(ids("memories").map(JSONValue.string))
        }
        let result = LocalRoleResult(requestID: request.id, role: request.role,
            text: String(decoding: try JSONEncoder().encode(JSONValue.object(payload)), as: UTF8.self),
            model: QwenModelMetadata(name: "point-help-fixture", family: "fixture", parameterSize: "fixture",
                quantization: "fixture", digest: String(repeating: "a", count: 64)), elapsedMilliseconds: 1)
        generatedResults.append(result)
        return result
    }
    func resolve(_ index: Int) {
        guard let continuation = pending.removeValue(forKey: index) else { XCTFail("Reasoning was not pending"); return }
        continuation.resume()
    }
    func drain() {
        let work = Array(pending.values); pending.removeAll()
        for continuation in work { continuation.resume(throwing: QwenFailure.stopped) }
    }
}

@MainActor
private func waitForPointHelp(_ message: String, file: StaticString = #filePath, line: UInt = #line,
                              _ condition: @MainActor () -> Bool) async throws {
    for _ in 0..<250 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(2))
    }
    XCTFail(message, file: file, line: line)
    throw PointHelpWaitFailure.timedOut
}
