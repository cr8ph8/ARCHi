import AppKit
import Speech
import Combine
import XCTest
@testable import ARCHiDesktop

final class VoiceInputTests: XCTestCase {
    @MainActor
    func testRetiringIdleVoiceDuringNavigationDoesNotPublishAViewChange() {
        let voice = VoiceInputController(service: VoiceTestService(), scheduler: VoiceTestScheduler())
        var publications = 0
        let observation = voice.objectWillChange.sink { publications += 1 }
        voice.cancel()
        voice.cancel(ifOwnedBy: .assistant)
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(voice.phase, .idle)
        XCTAssertTrue(voice.transcript.isEmpty)
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testPartialTextStaysCandidateAndFinishStopsCaptureBeforeFinalReview() async throws {
        let service = VoiceTestService(), clock = VoiceTestScheduler()
        let voice = VoiceInputController(service: service, scheduler: clock)
        voice.start(from: .bubble)
        try await settle { voice.phase == .recording }
        XCTAssertEqual(clock.delays, [45, 30])
        service.emit(.partial("A first guess"))
        XCTAssertEqual(voice.transcript, "A first guess")
        XCTAssertNil(voice.takeReviewedTranscript())
        voice.finish()
        XCTAssertEqual(voice.phase, .finalizing)
        XCTAssertFalse(service.capturing)
        XCTAssertEqual(service.finishes, 1)
        XCTAssertEqual(clock.delays, [45, 30, 4])
        service.emit(.final("A corrected transcript."))
        XCTAssertEqual(voice.phase, .review)
        XCTAssertFalse(voice.isActive)
        XCTAssertFalse(service.capturing)
        service.emit(.partial("Late callback must not replace the reviewed text"))
        XCTAssertEqual(voice.takeReviewedTranscript(), "A corrected transcript.")
        XCTAssertEqual(voice.phase, .idle)
        XCTAssertTrue(voice.transcript.isEmpty)
        XCTAssertNil(voice.takeReviewedTranscript(), "Use text can consume a candidate only once")
    }

    @MainActor
    func testMaximumDurationFinishesAndFinalizationTimeoutMarksPartialThenFencesLateFinal() async throws {
        let service = VoiceTestService(), clock = VoiceTestScheduler()
        let voice = VoiceInputController(service: service, scheduler: clock)
        voice.start(from: .work)
        try await settle { voice.phase == .recording }
        service.emit(.partial("Last partial text"))
        clock.fireLast()
        XCTAssertEqual(voice.phase, .finalizing)
        XCTAssertFalse(service.capturing)
        clock.fireLast()
        XCTAssertEqual(voice.phase, .review)
        XCTAssertTrue(voice.message.contains("partial"))
        service.emit(.final("Late final"))
        XCTAssertEqual(voice.transcript, "Last partial text")
    }

    @MainActor
    func testEmptyTimeoutFailureAndCancellationKeepNoCandidate() async throws {
        let service = VoiceTestService(), clock = VoiceTestScheduler()
        let voice = VoiceInputController(service: service, scheduler: clock)
        voice.start(from: .assistant)
        try await settle { voice.phase == .recording }
        voice.finish(); clock.fireLast()
        XCTAssertEqual(voice.phase, .failed)
        XCTAssertNil(voice.takeReviewedTranscript())
        voice.start(from: .assistant)
        try await settle { service.starts == 2 && voice.phase == .recording }
        service.emit(.partial("Do not keep this"))
        service.emit(.failed("Synthetic local recognition failure"))
        XCTAssertEqual(voice.phase, .failed)
        XCTAssertFalse(service.capturing)
        XCTAssertTrue(voice.transcript.isEmpty)
        voice.cancel()
        service.emit(.final("A late answer"))
        XCTAssertEqual(voice.phase, .idle)
        XCTAssertTrue(voice.transcript.isEmpty)
    }

    @MainActor
    func testReplacedSessionAndOtherSurfaceDismissalCannotAffectCurrentCapture() async throws {
        let service = VoiceTestService(), clock = VoiceTestScheduler()
        let voice = VoiceInputController(service: service, scheduler: clock)
        voice.start(from: .bubble)
        try await settle { voice.phase == .recording }
        voice.start(from: .assistant)
        try await settle { service.starts == 2 && voice.phase == .recording }
        voice.cancel(ifOwnedBy: .bubble)
        XCTAssertEqual(voice.phase, .recording)
        service.emit(.final("Old session text"), index: 0)
        XCTAssertEqual(voice.phase, .recording)
        XCTAssertTrue(voice.transcript.isEmpty)
        service.emit(.partial("Current session text"), index: 1)
        XCTAssertEqual(voice.transcript, "Current session text")
        voice.cancel(ifOwnedBy: .assistant)
        XCTAssertEqual(voice.phase, .idle)
        XCTAssertFalse(service.capturing)
    }

    @MainActor
    func testOversizedResultIsNotSilentlyTruncatedOrOffered() async throws {
        let service = VoiceTestService()
        let voice = VoiceInputController(service: service, scheduler: VoiceTestScheduler())
        voice.start(from: .assistant)
        try await settle { voice.phase == .recording }
        service.emit(.final(String(repeating: "a", count: VoiceInputController.maximumTranscriptCharacters + 1)))
        XCTAssertEqual(voice.phase, .failed)
        XCTAssertNil(voice.takeReviewedTranscript())
        XCTAssertFalse(service.capturing)
    }
}

final class AppleVoiceCaptureServiceTests: XCTestCase {
    @MainActor
    func testActualRequestConfigurationAlwaysRequiresOnDeviceRecognition() {
        // Construction alone requests no access and consumes no audio.
        let request = AppleOnDeviceSpeechSession.localRecognitionRequest()
        XCTAssertTrue(request.requiresOnDeviceRecognition)
        XCTAssertTrue(request.shouldReportPartialResults)
        XCTAssertEqual(request.taskHint, .dictation)
    }

    @MainActor
    func testUnsupportedOrUnavailableLocalSpeechNeverAsksForMicrophoneOrStartsCapture() async {
        for (supports, available) in [(false, true), (true, false)] {
            let authorization = VoiceTestAuthorization(), session = VoiceTestSession()
            session.supportsOnDeviceRecognition = supports; session.isAvailable = available
            let service = AppleVoiceCaptureService(authorization: authorization, sessionFactory: { session })
            do { try await service.start { _ in XCTFail("Unavailable local recognizer produced an event") }; XCTFail("Expected unavailable") }
            catch { XCTAssertTrue(error is LocalVoiceCaptureError) }
            XCTAssertEqual(authorization.microphoneCalls, 0)
            XCTAssertEqual(session.starts, 0)
        }
    }

    @MainActor
    func testPermissionDenialsNeverCapture() async {
        for deniedSpeech in [true, false] {
            let authorization = VoiceTestAuthorization(), session = VoiceTestSession()
            authorization.speechAllowed = !deniedSpeech
            authorization.microphoneAllowed = false
            let service = AppleVoiceCaptureService(authorization: authorization, sessionFactory: { session })
            do { try await service.start { _ in XCTFail("Denied permission produced an event") }; XCTFail("Expected denied access") }
            catch { XCTAssertTrue(error is LocalVoiceCaptureError) }
            XCTAssertEqual(session.starts, 0)
            XCTAssertEqual(authorization.microphoneCalls, deniedSpeech ? 0 : 1)
        }
    }

    @MainActor
    func testAuthorizationTimeoutOrLeavingUIFencesLateSpeechAndMicrophoneApproval() async throws {
        for waitingForSpeech in [true, false] {
            for timeout in [true, false] {
                let authorization = VoiceTestAuthorization(), session = VoiceTestSession(), clock = VoiceTestScheduler()
                authorization.holdSpeech = waitingForSpeech
                authorization.holdMicrophone = !waitingForSpeech
                let service = AppleVoiceCaptureService(authorization: authorization, sessionFactory: { session })
                let voice = VoiceInputController(service: service, scheduler: clock)
                voice.start(from: .bubble)
                try await settle { authorization.pending != nil }
                if timeout { clock.fireLast() } else { voice.cancel(ifOwnedBy: .bubble) }
                XCTAssertEqual(voice.phase, timeout ? .failed : .idle)
                authorization.resolve(true)
                for _ in 0..<20 { await Task.yield() }
                XCTAssertEqual(session.starts, 0, "A late permission response cannot start recording")
                XCTAssertEqual(voice.phase, timeout ? .failed : .idle)
                XCTAssertTrue(voice.transcript.isEmpty)
            }
        }
    }

    @MainActor
    func testCapabilityIsRecheckedAfterPermissionAndCancelledSessionEventsAreIgnored() async throws {
        let authorization = VoiceTestAuthorization(), session = VoiceTestSession()
        authorization.holdMicrophone = true
        let service = AppleVoiceCaptureService(authorization: authorization, sessionFactory: { session })
        let attempt = Task { try await service.start { _ in XCTFail("No event is expected") } }
        try await settle { authorization.pending != nil }
        session.supportsOnDeviceRecognition = false
        authorization.resolve(true)
        do { try await attempt.value; XCTFail("Capability changed before capture") } catch { }
        XCTAssertEqual(session.starts, 0)

        session.supportsOnDeviceRecognition = true
        authorization.holdMicrophone = false
        var events = 0
        try await service.start { _ in events += 1 }
        XCTAssertEqual(session.starts, 1)
        service.finish()
        XCTAssertEqual(session.finishes, 1)
        service.cancel()
        session.emit(.final("Late after cancellation"))
        XCTAssertEqual(events, 0)
        XCTAssertGreaterThanOrEqual(session.cancels, 1)
    }
}

final class VoiceInputStoreTests: XCTestCase {
    @MainActor
    func testReviewedAppendPreservesCurrentTypedEditsRouteAndMemoryWithoutSubmitting() async throws {
        let fixture = VoiceStoreFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.setAssistantRoute(.codex)
        store.prompt = "Original typed prefix."
        store.beginVoiceInput(from: .assistant)
        try await settle { fixture.voice.phase == .recording }
        fixture.service.emit(.partial("Partial voice text"))
        XCTAssertEqual(store.prompt, "Original typed prefix.")
        store.prompt += " Additional keyboard edit."
        fixture.service.emit(.final("Reviewed dictated sentence."))
        XCTAssertEqual(store.prompt, "Original typed prefix. Additional keyboard edit.")
        store.appendVoiceTranscript()
        XCTAssertEqual(store.prompt, "Original typed prefix. Additional keyboard edit.\nReviewed dictated sentence.")
        XCTAssertEqual(store.route, .codex)
        XCTAssertTrue(store.keptLessons.isEmpty)
        XCTAssertTrue(store.compareResults.isEmpty)
        XCTAssertEqual(fixture.assistant.connects + fixture.assistant.requests, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.preferenceURL.path))
    }

    @MainActor
    func testActiveVoiceBlocksSendAndWorkingReplyBlocksVoiceWithoutMakingCalls() async throws {
        let fixture = VoiceStoreFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.setAssistantRoute(.automatic)
        store.prompt = "An unsent typed question."
        store.isWorking = true
        store.beginVoiceInput(from: .assistant)
        XCTAssertEqual(fixture.service.starts, 0)
        store.isWorking = false
        store.beginVoiceInput(from: .assistant)
        try await settle { fixture.voice.phase == .recording }
        XCTAssertFalse(store.canBeginReply)
        store.submit()
        XCTAssertEqual(fixture.voice.phase, .recording)
        XCTAssertTrue(store.status.contains("voice"))
        XCTAssertEqual(fixture.assistant.connects + fixture.assistant.requests, 0)
        XCTAssertTrue(store.compareResults.isEmpty)
        fixture.service.emit(.final("A candidate."))
        store.isWorking = true
        store.appendVoiceTranscript()
        XCTAssertEqual(store.prompt, "An unsent typed question.")
        XCTAssertEqual(fixture.voice.phase, .review)
        store.isWorking = false
    }

    @MainActor
    func testMemoryHandoffAndShutdownCancelCaptureAndLateTextCannotChangeDraft() async throws {
        let fixture = VoiceStoreFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.prompt = "Keep my draft."
        store.beginVoiceInput(from: .assistant)
        try await settle { fixture.voice.phase == .recording }
        store.open(.memory)
        XCTAssertEqual(fixture.voice.phase, .idle)
        XCTAssertFalse(fixture.service.capturing)
        fixture.service.emit(.final("Do not append me"))
        XCTAssertEqual(store.prompt, "Keep my draft.")
        store.beginVoiceInput(from: .assistant)
        try await settle { fixture.voice.phase == .recording }
        await store.shutdownAssistant()
        XCTAssertEqual(fixture.voice.phase, .idle)
        XCTAssertFalse(fixture.service.capturing)
        fixture.service.emit(.final("Do not revive shutdown"))
        store.beginVoiceInput(from: .assistant)
        XCTAssertEqual(fixture.service.starts, 2)
        XCTAssertEqual(store.prompt, "Keep my draft.")
    }

    @MainActor
    func testNonactivatingBubbleResignKeyStopsOnlyItsOwnVoiceSession() async throws {
        _ = NSApplication.shared
        let fixture = VoiceStoreFixture()
        defer { fixture.cleanUp() }
        let parent = NSPanel(contentRect: CGRect(x: 550, y: 360, width: 128, height: 154),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        let bubble = CompanionChatBubbleController(store: fixture.store, companionWindow: parent)
        defer { bubble.dismiss(); bubble.window.close(); parent.close() }
        fixture.store.beginVoiceInput(from: .bubble)
        try await settle { fixture.voice.phase == .recording }
        bubble.window.resignKey()
        XCTAssertEqual(fixture.voice.phase, .idle)
        XCTAssertFalse(fixture.service.capturing)
        fixture.store.beginVoiceInput(from: .assistant)
        try await settle { fixture.voice.phase == .recording }
        bubble.window.resignKey()
        XCTAssertEqual(fixture.voice.phase, .recording)
        bubble.dismiss()
        XCTAssertEqual(fixture.voice.phase, .recording)
        XCTAssertFalse(parent.isVisible)
        XCTAssertFalse(bubble.window.isVisible)
    }
}

@MainActor
private func settle(_ predicate: () -> Bool) async throws {
    for _ in 0..<200 {
        if predicate() { return }
        await Task.yield()
    }
    XCTFail("Synthetic voice operation did not reach its expected state")
    throw VoiceTestFailure.timeout
}
private enum VoiceTestFailure: Error { case timeout }

@MainActor
private final class VoiceTestService: VoiceCaptureService {
    var starts = 0, finishes = 0
    var capturing = false
    var observers: [@MainActor (VoiceCaptureEvent) -> Void] = []
    func start(onEvent: @escaping @MainActor (VoiceCaptureEvent) -> Void) async throws {
        starts += 1; capturing = true; observers.append(onEvent)
    }
    func finish() { finishes += 1; capturing = false }
    func cancel() { capturing = false }
    func emit(_ event: VoiceCaptureEvent, index: Int? = nil) {
        guard !observers.isEmpty else { return }
        observers[index ?? observers.count - 1](event)
    }
}

@MainActor
private final class VoiceTestScheduler: VoiceInputScheduling {
    final class Entry: VoiceInputDeadline {
        var cancelled = false
        let action: @MainActor () -> Void
        init(_ action: @escaping @MainActor () -> Void) { self.action = action }
        func cancel() { cancelled = true }
    }
    var entries: [Entry] = []
    var delays: [TimeInterval] = []
    func schedule(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any VoiceInputDeadline {
        let entry = Entry(action); entries.append(entry); delays.append(seconds); return entry
    }
    func fireLast() {
        guard let entry = entries.last, !entry.cancelled else { XCTFail("No active voice timer"); return }
        entry.action()
    }
}

@MainActor
private final class VoiceTestAuthorization: VoiceCaptureAuthorization {
    var speechAllowed = true, microphoneAllowed = true
    var holdSpeech = false, holdMicrophone = false
    var speechCalls = 0, microphoneCalls = 0
    var pending: CheckedContinuation<Bool, Never>?
    func speechAuthorized() async -> Bool {
        speechCalls += 1
        if holdSpeech { return await withCheckedContinuation { pending = $0 } }
        return speechAllowed
    }
    func microphoneAuthorized() async -> Bool {
        microphoneCalls += 1
        if holdMicrophone { return await withCheckedContinuation { pending = $0 } }
        return microphoneAllowed
    }
    func resolve(_ value: Bool) { let saved = pending; pending = nil; saved?.resume(returning: value) }
}

@MainActor
private final class VoiceTestSession: OnDeviceSpeechSession {
    var supportsOnDeviceRecognition = true, isAvailable = true
    var starts = 0, finishes = 0, cancels = 0
    var observer: (@MainActor (VoiceCaptureEvent) -> Void)?
    func start(onEvent: @escaping @MainActor (VoiceCaptureEvent) -> Void) throws { starts += 1; observer = onEvent }
    func finish() { finishes += 1 }
    func cancel() { cancels += 1 }
    func emit(_ event: VoiceCaptureEvent) { observer?(event) }
}

@MainActor
private final class VoiceStoreFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ARCHiVoiceTest-\(UUID().uuidString)")
    var preferenceURL: URL { directory.appendingPathComponent("preferences.json") }
    let service = VoiceTestService(), assistant = VoiceTestAssistant()
    lazy var voice = VoiceInputController(service: service, scheduler: VoiceTestScheduler())
    lazy var store = CompanionStore(preferenceURL: preferenceURL, assistant: assistant,
        assistantFactory: { [assistant] _, _ in assistant }, allowsPlay: false, voiceInput: voice)
    func cleanUp() { store.cancelWork(); try? FileManager.default.removeItem(at: directory) }
}

@MainActor
private final class VoiceTestAssistant: AssistantClient {
    var connects = 0, requests = 0
    func connect() async throws { connects += 1 }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws { requests += 1 }
    func disconnect() { }
}
