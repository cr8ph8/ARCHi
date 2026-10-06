import Combine
import Foundation

enum VoiceInputSurface: Equatable { case bubble, assistant, work }
enum VoiceInputPhase: Equatable { case idle, authorizing, recording, finalizing, review, failed }
enum VoiceCaptureEvent: Sendable { case partial(String), final(String), failed(String) }

/// Audio recognition is an input adapter. It cannot submit a request, change
/// model routing, write a lesson or touch the user's composer.
@MainActor
protocol VoiceCaptureService: AnyObject {
    func start(onEvent: @escaping @MainActor (VoiceCaptureEvent) -> Void) async throws
    func finish()
    func cancel()
}

@MainActor protocol VoiceInputDeadline: AnyObject { func cancel() }
@MainActor protocol VoiceInputScheduling {
    func schedule(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any VoiceInputDeadline
}

@MainActor
private final class VoiceTimer: VoiceInputDeadline {
    private var task: Task<Void, Never>?
    init(seconds: TimeInterval, action: @escaping @MainActor () -> Void) {
        task = Task {
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard !Task.isCancelled else { return }
            action()
        }
    }
    func cancel() { task?.cancel(); task = nil }
}

@MainActor
struct VoiceInputScheduler: VoiceInputScheduling {
    func schedule(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any VoiceInputDeadline {
        VoiceTimer(seconds: seconds, action: action)
    }
}

/// One short, ephemeral dictation session shared by the native composers.
/// Candidate text stays separate until the person explicitly uses it.
@MainActor
final class VoiceInputController: ObservableObject {
    static let authorizationLimit: TimeInterval = 45
    static let recordingLimit: TimeInterval = 30
    static let finalizationLimit: TimeInterval = 4
    static let maximumTranscriptCharacters = 6_000

    @Published private(set) var phase: VoiceInputPhase = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var message = "On this Mac · review before Send"
    private(set) var surface: VoiceInputSurface?
    private let service: any VoiceCaptureService
    private let scheduler: any VoiceInputScheduling
    private var sessionID: UUID?
    private var startTask: Task<Void, Never>?
    private var deadline: (any VoiceInputDeadline)?

    var isActive: Bool { phase == .authorizing || phase == .recording || phase == .finalizing }
    var showsDetails: Bool { phase != .idle }

    init(service: any VoiceCaptureService = AppleVoiceCaptureService(),
         scheduler: any VoiceInputScheduling = VoiceInputScheduler()) {
        self.service = service
        self.scheduler = scheduler
    }

    func start(from surface: VoiceInputSurface) {
        cancel()
        let id = UUID()
        sessionID = id
        self.surface = surface
        phase = .authorizing
        message = "Checking local speech and microphone access…"
        deadline = scheduler.schedule(after: Self.authorizationLimit) { [weak self] in
            guard self?.sessionID == id else { return }
            self?.fail("Voice access took too long. Your draft is unchanged; click Dictate to try again.")
        }
        startTask = Task { [weak self, service] in
            do {
                try await service.start { [weak self] event in self?.receive(event, session: id) }
                guard let self, self.sessionID == id, self.phase == .authorizing, !Task.isCancelled else { return }
                self.phase = .recording
                self.message = "Recording on this Mac · Finish when ready"
                self.deadline?.cancel()
                self.deadline = self.scheduler.schedule(after: Self.recordingLimit) { [weak self] in
                    guard self?.sessionID == id else { return }
                    self?.finish()
                }
            } catch {
                guard let self, self.sessionID == id, !Task.isCancelled else { return }
                self.fail((error as? LocalizedError)?.errorDescription ?? "Local dictation could not start. Your draft is unchanged.")
            }
        }
    }

    func finish() {
        guard phase == .recording, let id = sessionID else { return }
        phase = .finalizing
        message = "Microphone stopped · finishing transcription…"
        deadline?.cancel()
        // Finish stops the engine before waiting for the recognizer's final text.
        service.finish()
        guard sessionID == id, phase == .finalizing else { return }
        deadline = scheduler.schedule(after: Self.finalizationLimit) { [weak self] in
            guard let self, self.sessionID == id else { return }
            if self.transcript.isEmpty { self.fail("No speech was transcribed. Your draft is unchanged.") }
            else { self.review(message: "Final text did not arrive. Review this partial transcription before using it.") }
        }
    }

    func cancel(ifOwnedBy surface: VoiceInputSurface? = nil) {
        if let surface, self.surface != surface { return }
        retire()
        // Navigation also retires an idle owner. Do not publish unchanged UI
        // state from a segmented picker or a disappearing composer.
        if !transcript.isEmpty { transcript = "" }
        if phase != .idle { phase = .idle }
        self.surface = nil
        let idleMessage = "On this Mac · review before Send"
        if message != idleMessage { message = idleMessage }
    }

    func takeReviewedTranscript() -> String? {
        guard phase == .review, !transcript.isEmpty else { return nil }
        let text = transcript
        cancel()
        return text
    }

    private func receive(_ event: VoiceCaptureEvent, session: UUID) {
        guard sessionID == session, isActive else { return }
        switch event {
        case .partial(let text), .final(let text):
            guard text.count <= Self.maximumTranscriptCharacters else {
                fail("This dictation was too long. Your typed draft is unchanged; try a shorter recording.")
                return
            }
            transcript = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if case .final = event {
                if transcript.isEmpty { fail("No speech was transcribed. Your draft is unchanged.") }
                else { review(message: "Review this text, then add it to your draft. Nothing has been sent.") }
            }
        case .failed(let message): fail(message)
        }
    }

    private func review(message: String) {
        retire()
        phase = .review
        self.message = message
    }

    private func fail(_ message: String) {
        retire()
        transcript = ""
        phase = .failed
        self.message = message
    }

    private func retire() {
        // Fence first: cancel/endAudio can itself deliver a late callback.
        sessionID = nil
        deadline?.cancel(); deadline = nil
        startTask?.cancel(); startTask = nil
        service.cancel()
    }
}

extension CompanionStore {
    func beginVoiceInput(from surface: VoiceInputSurface) {
        guard !isShuttingDown, !isWorking else { return }
        voiceInput.start(from: surface)
    }

    func appendVoiceTranscript() {
        guard !isShuttingDown, !isWorking, let text = voiceInput.takeReviewedTranscript() else { return }
        // Read the *current* draft only at this explicit click. Incoming typed
        // edits are preserved byte-for-byte; asynchronous speech never writes it.
        prompt += prompt.isEmpty || prompt.hasSuffix("\n") ? text : "\n" + text
    }
}
