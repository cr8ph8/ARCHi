import AppKit
import Combine
import CryptoKit

enum ReactorExpressionState: String {
    case idle, checking, prepared, previewing, connecting, live, stopping, stopped, failed
    var title: String {
        switch self {
        case .idle: "Local artwork"
        case .checking: "Checking Reactor"
        case .prepared: "Ready to review"
        case .previewing: "Local motion preview"
        case .connecting: "Connecting Reactor"
        case .live: "Reactor expression"
        case .stopping: "Closing Reactor"
        case .stopped: "Local artwork restored"
        case .failed: "Reactor unavailable"
        }
    }
}

struct ReactorTrialQuote: Equatable {
    let id: UUID
    let appearanceID: String
    let referenceDigest: String
    let date: Date
    let creditsPerSecond: Double
    let creditsPerUSD: Double
    var maximumCredits: Double { creditsPerSecond * 15 }
    var maximumUSD: Double { maximumCredits / creditsPerUSD }
}

/// Ephemeral expression only. It has no path to identity, learning, battle or placement writes.
@MainActor
final class ReactorExpressionStore: ObservableObject {
    static let durationSeconds = 15
    static let prompt = "One ARCHi companion, matching the selected reference exactly, with its existing face, core and any orbital ornaments. Gentle restrained breathing, centered and fully visible, fixed camera. Flat pure green background, no ground, no text, no additional characters or objects. Preserve the reference silhouette and colors."
    @Published private(set) var state: ReactorExpressionState = .idle
    @Published private(set) var status = "Use local artwork, or preview a short optional Reactor expression."
    @Published private(set) var quote: ReactorTrialQuote?
    @Published private(set) var framePNG: Data?
    @Published private(set) var frameImage: NSImage?
    @Published private(set) var frameRevision: UInt64 = 0
    @Published private(set) var acceptedFrames = 0
    @Published private(set) var rejectedFrames = 0
    @Published private(set) var terminationConfirmed: Bool?
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var referenceLabel = "ARCHi"
    @Published private(set) var runtimeReady = false
    @Published private(set) var controlsAvailable = true
    private(set) var referencePNG: Data?
    private(set) var appearanceID = ""
    /// Re-read the native evidence owner immediately before preview or dispatch.
    /// A cached reference alone does not establish that its support is current.
    var refreshCurrentReference: (@MainActor () -> Void)?
    private var cue = "idle"
    private var worker: (any ReactorWorkerPort)?
    private var owner: UUID?
    private var lastSequence = -1
    private var lastFrameAt: Date?
    private var startedAt: Date?
    private var timer: Task<Void, Never>?
    private var shutdownTimer: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var composition: Task<Void, Never>?
    private var liveAttempt = false
    private var transportStage = "idle"
    private var receivedLines = 0
    private var retired = false
    private let now: () -> Date
    private let factory: () throws -> any ReactorWorkerPort

    init(now: @escaping () -> Date = Date.init, factory: (() throws -> any ReactorWorkerPort)? = nil) {
        self.now = now
        self.factory = factory ?? {
            guard let path = Bundle.main.object(forInfoDictionaryKey: "ARCHiReactorPython") as? String,
                  FileManager.default.isExecutableFile(atPath: path),
                  let script = Bundle.main.resourceURL?.appendingPathComponent("ReactorBridge/worker.py"),
                  FileManager.default.fileExists(atPath: script.path) else { throw CocoaError(.fileNoSuchFile) }
            return ReactorWorkerConnection(python: URL(fileURLWithPath: path), script: script)
        }
    }

    var busy: Bool { [.checking, .previewing, .connecting, .live, .stopping].contains(state) }
    var canPrepare: Bool { !retired && !busy && referencePNG != nil }
    var canPreview: Bool { canPrepare && controlsAvailable }
    var canStart: Bool {
        guard !retired, !busy, controlsAvailable, runtimeReady, let quote else { return false }
        return quote.appearanceID == appearanceID && now().timeIntervalSince(quote.date) < 300
    }

    func updateReference(id: String, label: String, png: Data?, motionAllowed: Bool, visible: Bool) {
        let changed = id != appearanceID
        controlsAvailable = motionAllowed && visible
        if changed { stop(reason: "Appearance changed. Local artwork restored."); quote = nil }
        appearanceID = id; referenceLabel = label; referencePNG = png
        if !controlsAvailable { stop(reason: "Motion is off or ARCHi is hidden. Local artwork restored.") }
    }

    func updateCue(_ activity: AssistantActivity) {
        let next = [AssistantActivity.working, .responding, .ready].contains(activity) ? activity.rawValue : "idle"
        guard next != cue else { return }; cue = next
        if state == .live || state == .connecting { send(["command": "cue", "cue": next]) }
    }

    func prepare() {
        refreshCurrentReference?()
        guard canPrepare else { return }
        resetAttempt(); state = .checking; status = "Checking the local transport and public price. No session is started."
        quote = nil; runtimeReady = false
        launch(command: ["command": "preflight"])
        armTimeout(seconds: 25, reason: "The Reactor check timed out. No live session was requested.")
    }

    func startLocalPreview() {
        refreshCurrentReference?()
        guard canPreview, let reference = referencePNG else { return }
        resetAttempt(); state = .previewing; status = "Local motion preview · no Reactor session or model call."
        let id = UUID(); owner = id; startedAt = now()
        previewTask = Task { [weak self] in
            for index in 0..<60 {
                guard let self, !Task.isCancelled, self.owner == id, self.state == .previewing else { return }
                do {
                    let result = try await Task.detached(priority: .userInitiated) {
                        let candidate = try ReactorFrameCompositor.makeLocalPreviewFrame(approvedReferencePNG: reference, phase: Double(index) / 6)
                        return try ReactorFrameCompositor.composite(candidatePNG: candidate, approvedReferencePNG: reference)
                    }.value
                    guard !Task.isCancelled, self.owner == id, self.state == .previewing else { return }
                    try self.publish(result)
                    self.duration = self.now().timeIntervalSince(self.startedAt ?? self.now())
                    if self.duration >= 10 { break }
                } catch {
                    guard self.owner == id, self.state == .previewing else { return }
                    self.rejectedFrames += 1; self.stop(reason: "Local composition could not preserve this form. Original artwork restored."); return
                }
                try? await Task.sleep(for: .milliseconds(167))
            }
            self?.stop(reason: "Local preview finished. No model calls were made.")
        }
    }

    func startLive(apiKey: String, reviewedQuote: ReactorTrialQuote) {
        refreshCurrentReference?()
        guard canStart, quote == reviewedQuote, let reference = referencePNG,
              reviewedQuote.referenceDigest == Self.digest(reference),
              apiKey.hasPrefix("rk_"), (10...512).contains(apiKey.utf8.count),
              !apiKey.contains(where: { $0.isWhitespace }) else {
            status = "Review a fresh trial and supply a Reactor API key before starting."; return
        }
        do {
            let providerReference = try ReactorFrameCompositor.makeProviderReference(approvedReferencePNG: reference)
            resetAttempt(); quote = nil; state = .connecting; liveAttempt = true; startedAt = now()
            status = "Starting one Reactor session, capped at 15 seconds."
            launch(command: ["command": "start", "apiKey": apiKey, "referencePNG": providerReference.base64EncodedString(),
                "prompt": Self.prompt, "durationSeconds": Self.durationSeconds,
                "model": "reactor/helios", "maximumCredits": reviewedQuote.maximumCredits,
                "maximumUSD": reviewedQuote.maximumUSD, "cue": cue])
            armTimeout(seconds: 30, reason: "The trial reached its local deadline. Closing Reactor.")
        } catch { state = .failed; status = "The chosen reference could not be prepared. Local artwork is unchanged." }
    }

    func stop(reason: String = "Stopped. Local artwork restored.") {
        previewTask?.cancel(); previewTask = nil; timer?.cancel(); timer = nil
        composition?.cancel(); composition = nil
        clearFrame()
        if let start = startedAt { duration = now().timeIntervalSince(start) }
        guard owner != nil else { return }
        status = reason
        if liveAttempt, worker != nil {
            guard state != .stopping else { return }
            state = .stopping; send(["command": "stop"])
            let id = owner
            shutdownTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(24))
                guard let self, !Task.isCancelled, self.owner == id else { return }
                self.terminationConfirmed = false
                self.finish(state: .failed, message: "Local artwork restored. Provider closure was not confirmed; the 15-second server cap remains the backstop.")
            }
        } else { finish(state: .stopped, message: reason) }
    }

    func shutdown() async {
        retired = true; stop(reason: "Closing ARCHi and restoring local artwork.")
        for _ in 0..<250 where owner != nil { try? await Task.sleep(for: .milliseconds(100)) }
        worker?.terminate(); worker = nil
    }

    func control(_ request: [String: Any]) -> [String: Any] {
        switch request["action"] as? String {
        case "status": break
        case "prepare": prepare()
        case "preview": startLocalPreview()
        case "stop": stop()
        default: return ["ok": false, "error": "Unsupported control. Live start is reviewed in the native app."]
        }
        var result: [String: Any] = ["ok": true, "state": state.rawValue, "status": status,
            "appearance": referenceLabel, "acceptedFrames": acceptedFrames, "rejectedFrames": rejectedFrames,
            "appearanceRevision": appearanceID,
            "runtimeReady": runtimeReady, "durationSeconds": duration, "liveStart": "Review and start in native Connections"]
        result["transportStage"] = transportStage
        result["receivedTransportLines"] = receivedLines
        if let connection = worker as? ReactorWorkerConnection { result["workerRunning"] = connection.isRunning }
        if let terminationConfirmed { result["terminationConfirmed"] = terminationConfirmed }
        if let referencePNG { result["referenceSHA256"] = Self.digest(referencePNG) }
        if let quote { result["estimatedMaximumUSD"] = quote.maximumUSD; result["maximumCredits"] = quote.maximumCredits }
        return result
    }

    private func resetAttempt() {
        shutdownTimer?.cancel(); shutdownTimer = nil
        owner = nil; worker?.terminate(); worker = nil
        acceptedFrames = 0; rejectedFrames = 0; duration = 0; terminationConfirmed = nil
        startedAt = nil
        transportStage = "idle"; receivedLines = 0
        lastSequence = -1; lastFrameAt = nil; liveAttempt = false; clearFrame()
    }

    private func launch(command: [String: Any]) {
        let id = UUID(); owner = id
        do {
            let child = try factory(); worker = child
            try child.launch(onLine: { [weak self] line in
                guard let self, self.owner == id else { return }
                self.receivedLines += 1
                self.transportStage = "received"
                self.receive(line, owner: id)
            }, onExit: { [weak self] in
                guard let self, self.owner == id else { return }
                self.finish(state: .failed, message: self.liveAttempt
                    ? "Transport ended. Local artwork restored; provider closure was not confirmed."
                    : "The local Reactor transport ended before its check completed.")
            })
            transportStage = "launched"
            send(command)
        } catch { finish(state: .failed, message: "Reactor runtime is unavailable. Run the local Reactor setup, then Check again.") }
    }

    private func send(_ command: [String: Any]) {
        guard let owner else { return }
        var message = command; message["requestId"] = owner.uuidString
        if let bytes = try? JSONSerialization.data(withJSONObject: message) { worker?.send(bytes) }
    }

    private func receive(_ line: Data, owner id: UUID) {
        guard owner == id, line.count <= 2_500_000,
              let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              event["requestId"] as? String == id.uuidString else { return }
        switch event["event"] as? String {
        case "preflight":
            guard state == .checking else { return }
            runtimeReady = event["runtimeReady"] as? Bool == true
            if runtimeReady, let rate = event["rateCreditsPerSecond"] as? Double,
               let usd = event["creditsPerUSD"] as? Double, rate.isFinite, usd.isFinite,
               rate > 0, rate <= 1_000_000, usd > 0, let reference = referencePNG {
                quote = ReactorTrialQuote(id: UUID(), appearanceID: appearanceID, referenceDigest: Self.digest(reference),
                    date: now(), creditsPerSecond: rate, creditsPerUSD: usd)
                finish(state: .prepared, message: "Transport and public price checked. Account access and live animation are not yet verified.")
            } else { finish(state: .failed, message: "Runtime or current pricing could not be verified. Local preview remains available.") }
        case "state":
            guard liveAttempt, state != .stopping else { return }
            if event["state"] as? String == "closing" { stop(reason: "The provider trial is closing. Local artwork restored.") }
        case "frame":
            guard liveAttempt, state == .connecting || state == .live,
                  let number = event["sequence"] as? Int, number > lastSequence,
                  let text = event["png"] as? String, text.utf8.count <= 1_900_000,
                  let bytes = Data(base64Encoded: text), let reference = referencePNG else { return }
            lastSequence = number
            if let previous = lastFrameAt, now().timeIntervalSince(previous) < 0.12 { return }
            guard composition == nil else { return }
            lastFrameAt = now()
            // One in-flight frame, no growing frame queue and no image work on the UI actor.
            composition = Task { [weak self] in
                do {
                    let result = try await Task.detached(priority: .userInitiated) {
                        try ReactorFrameCompositor.composite(candidatePNG: bytes, approvedReferencePNG: reference)
                    }.value
                    guard let self, !Task.isCancelled, self.owner == id,
                          self.state == .connecting || self.state == .live else { return }
                    try self.publish(result)
                    self.duration = self.now().timeIntervalSince(self.startedAt ?? self.now())
                    if self.acceptedFrames >= 2 { self.state = .live; self.status = "Receiving Reactor motion. Local position and activity remain app-owned." }
                    self.composition = nil
                } catch {
                    guard let self, !Task.isCancelled, self.owner == id else { return }
                    self.composition = nil; self.rejectedFrames += 1
                    self.stop(reason: "Generated frame did not fit the chosen body. Restoring local artwork and closing Reactor.")
                }
            }
        case "closed":
            guard liveAttempt else { return }
            terminationConfirmed = event["terminationConfirmed"] as? Bool == true
            let failed = event["reason"] as? String == "failed"
            finish(state: terminationConfirmed == true && !failed ? .stopped : .failed,
                message: terminationConfirmed == true ? (failed
                    ? "The Reactor trial failed. No active provider session remains; local artwork is restored."
                    : "Reactor session closed. Local artwork restored.")
                    : "Local artwork restored. Provider closure could not be confirmed.")
        case "error":
            if liveAttempt { stop(reason: "Reactor could not complete this trial. Local artwork restored.") }
            else { finish(state: .failed, message: "The Reactor check failed. Local artwork is available.") }
        default: break
        }
    }

    private func publish(_ result: ReactorCompositedFrame) throws {
        guard let image = NSImage(data: result.pngData) else { throw CocoaError(.fileReadCorruptFile) }
        acceptedFrames += 1; framePNG = result.pngData; frameImage = image; frameRevision &+= 1
    }

    private func clearFrame() { framePNG = nil; frameImage = nil; frameRevision &+= 1 }
    private func finish(state: ReactorExpressionState, message: String) {
        owner = nil; timer?.cancel(); timer = nil; shutdownTimer?.cancel(); shutdownTimer = nil
        previewTask?.cancel(); previewTask = nil; worker?.terminate(); worker = nil
        composition?.cancel(); composition = nil
        clearFrame(); self.state = state; status = message
    }
    private func armTimeout(seconds: Int, reason: String) {
        let id = owner
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled, self.owner == id else { return }; self.stop(reason: reason)
        }
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
