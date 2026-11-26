import AppKit
import AVFoundation
import Darwin
import SwiftUI

@MainActor
final class QwenVoice: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let speakers = ["Ryan", "Aiden", "Vivian", "Serena", "Dylan", "Eric", "Sohee", "Ono_Anna", "Uncle_Fu"]
    static let preview = "Aloha. Ready for another take?"
    @Published var speaker = "Ryan"
    @Published var instruction = "Warm and conversational."
    @Published private(set) var active = false
    @Published private(set) var message = ""

    private let runtime: URL
    private let resources: URL?
    private var process: Process?
    private var channel: FileHandle?
    private var pendingID: String?
    private let idleDelay: Duration
    private var idleTask: Task<Void, Never>?
    private let writer = DispatchQueue(label: "archi.qwen.voice.input")
    private var player: AVAudioPlayer?

    init(runtime: URL? = nil, resources: URL? = nil, idleDelay: Duration = .seconds(60)) {
        self.idleDelay = idleDelay
        self.runtime = runtime ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ARCHi/QwenVoice")
        if let resources {
            self.resources = resources
        } else if Bundle.main.bundleURL.pathExtension == "app" {
            self.resources = Bundle.main.resourceURL?.appendingPathComponent("QwenVoice")
        } else {
            self.resources = Bundle.module.url(forResource: "QwenVoice", withExtension: nil)
        }
    }

    func openSetup() {
        guard let setup = resources?.appendingPathComponent("Setup.command"),
              NSWorkspace.shared.open(setup) else {
            message = "Voice setup could not open. Run Setup.command in the QwenVoice resources."
            return
        }
        message = "When setup finishes in Terminal, choose Preview direction."
    }

    func speak(_ text: String) {
        guard !active else { return }
        let python = runtime.appendingPathComponent("venv/bin/python")
        guard FileManager.default.isExecutableFile(atPath: python.path),
              FileManager.default.fileExists(atPath: runtime.appendingPathComponent("ready-0.6.8-f35faf1").path)
        else { message = "Open Connections → Local Qwen and choose Set up voices."; return }
        guard let worker = resources?.appendingPathComponent("speech.py"),
              Self.speakers.contains(speaker), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= 65_536, instruction.utf8.count <= 1024
        else { message = "Use a shorter reply or performance direction."; return }

        let id = UUID().uuidString.lowercased()
        do {
            var data = try JSONEncoder().encode(["id": id, "text": text, "voice": speaker, "instruction": instruction])
            data.append(10)
            if process?.isRunning != true {
                releaseWorker()
                try launch(python: python, worker: worker)
            }
            guard let channel else { throw CocoaError(.fileWriteUnknown) }
            idleTask?.cancel()
            pendingID = id
            active = true
            message = "Preparing and reading with " + speaker + " on this Mac…"
            let bytes = data
            writer.async { [weak self] in
                do { try channel.write(contentsOf: bytes) }
                catch {
                    Task { @MainActor in
                        guard let self, self.pendingID == id else { return }
                        self.workerFailed()
                    }
                }
            }
        } catch {
            releaseWorker()
            active = false
            message = "Could not start the voice engine. Run voice setup in Connections."
        }
    }

    private func launch(python: URL, worker: URL) throws {
        // A private socket pair provides stdio with no listener. Closing a retired
        // peer must report a write error without delivering SIGPIPE to the app.
        var fds = [Int32](repeating: -1, count: 2)
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else { throw CocoaError(.fileWriteUnknown) }
        let host = FileHandle(fileDescriptor: fds[0], closeOnDealloc: true)
        let peer = FileHandle(fileDescriptor: fds[1], closeOnDealloc: true)
        defer { try? peer.close() }
        var yes: Int32 = 1
        guard setsockopt(fds[0], SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size)) == 0,
              fcntl(fds[0], F_SETFD, FD_CLOEXEC) == 0, fcntl(fds[1], F_SETFD, FD_CLOEXEC) == 0
        else { throw CocoaError(.fileWriteUnknown) }

        let child = Process()
        child.executableURL = python
        child.arguments = [worker.path, "--session"]
        child.standardInput = peer
        child.standardOutput = peer
        child.standardError = FileHandle.nullDevice
        child.environment = ProcessInfo.processInfo.environment.merging([
            "HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1", "PYTHONNOUSERSITE": "1"
        ]) { _, new in new }
        let lines = LocalWorkerLineBuffer { [weak self, weak child] line in
            guard let self, let child, self.process === child, let id = self.pendingID,
                  line == Data(id.utf8) else { return }
            self.pendingID = nil
            self.active = false
            self.message = "Reading finished."
            self.idleTask = Task { [weak self, delay = self.idleDelay] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self, self.process === child, self.pendingID == nil else { return }
                self.releaseWorker()
            }
        }
        child.terminationHandler = { [weak self] ended in
            Task { @MainActor in
                guard let self, self.process === ended else { return }
                if self.pendingID != nil { self.workerFailed() } else { self.releaseWorker() }
            }
        }
        try child.run()
        channel = host
        process = child
        host.readabilityHandler = { handle in
            let bytes = handle.availableData
            if bytes.isEmpty { handle.readabilityHandler = nil } else { lines.append(bytes) }
        }
    }

    private func workerFailed() {
        releaseWorker()
        active = false
        message = "Playback failed. Check the Mac’s audio output or run voice setup again."
    }

    private func releaseWorker() {
        idleTask?.cancel()
        idleTask = nil
        pendingID = nil
        let child = process
        process = nil
        channel?.readabilityHandler = nil
        if let channel { _ = shutdown(channel.fileDescriptor, SHUT_RDWR) }
        channel = nil
        if let child, child.isRunning {
            child.terminate()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
    }

    var sampleURL: URL? {
        guard Self.speakers.contains(speaker) else { return nil }
        return resources?.appendingPathComponent("Samples/\(speaker).wav")
    }

    func playSample() {
        guard !active, let sampleURL else { return }
        do {
            let sample = try AVAudioPlayer(contentsOf: sampleURL)
            sample.delegate = self
            guard sample.prepareToPlay(), sample.play() else { throw CocoaError(.fileReadUnknown) }
            player = sample
            active = true
            message = "Playing the recorded " + speaker + " sample."
        } catch {
            message = "Could not play the sample. Check this build and the Mac’s audio output."
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully success: Bool) {
        sampleEnded(ObjectIdentifier(finished), success: success)
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        sampleEnded(ObjectIdentifier(player), success: false)
    }

    private nonisolated func sampleEnded(_ identity: ObjectIdentifier, success: Bool) {
        Task { @MainActor [weak self] in
            guard let self, let player = self.player, ObjectIdentifier(player) == identity else { return }
            self.player = nil
            self.active = false
            self.message = success ? "Sample finished." : "Sample playback failed."
        }
    }

    func stop() {
        let wasActive = active
        player?.stop()
        player = nil
        releaseWorker()
        active = false
        if wasActive { message = "Reading stopped." }
    }
}

@MainActor
struct QwenVoiceControls: View {
    @ObservedObject var voice: QwenVoice
    let text: String
    let enabled: Bool
    var settings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if settings {
                Picker("Speaking voice", selection: $voice.speaker) {
                    ForEach(QwenVoice.speakers, id: \.self) { Text($0).tag($0) }
                }.disabled(voice.active)
                TextField("Performance direction", text: $voice.instruction)
                    .accessibilityLabel("Performance direction").disabled(voice.active)
            }
            HStack {
                if voice.active {
                    Button("Stop reading", systemImage: "stop.fill") { voice.stop() }
                } else {
                    if settings {
                        Button("Play sample") { if enabled { voice.playSample() } }
                            .disabled(!enabled)
                            .help("Hear this recorded speaker immediately. Custom direction applies to generated readings.")
                    }
                    Button(settings ? "Preview direction" : "Read aloud", systemImage: "speaker.wave.2") {
                        if enabled { voice.speak(text) }
                    }.disabled(!enabled)
                }
                if settings {
                    Button("Set up voices…") { voice.openSetup() }.disabled(voice.active)
                        .help("Download the Qwen voice engine and model using Terminal.")
                }
            }.buttonStyle(.borderless)
            if !voice.message.isEmpty {
                Text(voice.message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
