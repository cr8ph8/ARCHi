import AppKit
import Darwin
import SwiftUI

@MainActor
final class QwenVoice: ObservableObject {
    static let speakers = ["Ryan", "Aiden", "Vivian", "Serena", "Dylan", "Eric", "Sohee", "Ono_Anna", "Uncle_Fu"]
    static let preview = "Aloha. I’m ready when you are. Let’s take this one line at a time."
    @Published var speaker = "Ryan"
    @Published var instruction = "Warm and conversational. Pause naturally between sentences."
    @Published private(set) var active = false
    @Published private(set) var message = ""

    private let runtime: URL
    private let resources: URL?
    private var process: Process?

    init(runtime: URL? = nil, resources: URL? = nil) {
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
        message = "When setup finishes in Terminal, choose Preview voice."
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

        let child = Process()
        child.executableURL = python
        child.arguments = [worker.path]
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        child.environment = ProcessInfo.processInfo.environment.merging([
            "HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1", "PYTHONNOUSERSITE": "1"
        ]) { _, new in new }

        do {
            // Anonymous input avoids a visible script file, command-line transcript,
            // and blocking the UI on a child which is still loading model weights.
            guard let file = tmpfile() else { throw CocoaError(.fileWriteUnknown) }
            defer { fclose(file) }
            let input = FileHandle(fileDescriptor: fileno(file), closeOnDealloc: false)
            let data = try JSONEncoder().encode(["text": text, "voice": speaker, "instruction": instruction])
            try input.write(contentsOf: data)
            try input.seek(toOffset: 0)
            child.standardInput = input
            child.terminationHandler = { [weak self] finished in
                Task { @MainActor in
                    guard let self, self.process === finished else { return }
                    self.process = nil
                    self.active = false
                    self.message = finished.terminationStatus == 0 ? "Reading finished."
                        : "Playback failed. Check the Mac’s audio output or run voice setup again."
                }
            }
            try child.run()
            process = child
            active = true
            message = "Preparing and reading with " + speaker + " on this Mac…"
        } catch {
            message = "Could not start the voice engine. Run voice setup in Connections."
        }
    }

    func stop() {
        guard let child = process else { return }
        process = nil
        active = false
        if child.isRunning { child.terminate() }
        message = "Reading stopped."
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
                    Button(settings ? "Preview voice" : "Read aloud", systemImage: "speaker.wave.2") {
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
