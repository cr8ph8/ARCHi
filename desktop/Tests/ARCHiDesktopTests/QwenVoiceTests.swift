import Foundation
import XCTest
@testable import ARCHiDesktop

final class QwenVoiceTests: XCTestCase {
    @MainActor
    func testMissingRuntimeReturnsSetupHint() {
        let voice = QwenVoice(runtime: URL(fileURLWithPath: "/missing-archi-voice-fixture"))
        voice.speak("Aloha.")
        XCTAssertFalse(voice.active)
        XCTAssertTrue(voice.message.contains("Set up voices"))
    }

    @MainActor
    func testProcessReceivesExactTextAndDirectionAndStopRetiresOldProcess() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let bin = root.appendingPathComponent("venv/bin")
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: bin.appendingPathComponent("python"), withDestinationURL: URL(fileURLWithPath: "/bin/sh"))
        try Data().write(to: root.appendingPathComponent("ready-0.6.8-f35faf1"))
        let capture = root.appendingPathComponent("capture")
        try """
        cat > '\(capture.path)'
        exec /bin/sleep 30
        """.write(to: root.appendingPathComponent("speech.py"), atomically: true, encoding: .utf8)
        let voice = QwenVoice(runtime: root, resources: root)
        defer { voice.stop() }
        voice.speaker = "Vivian"
        voice.instruction = "Read this quietly."
        let line = "Aloha, \"pH\".\nReady?"
        voice.speak(line)
        XCTAssertTrue(voice.active)
        let expected = ["voice": "Vivian", "instruction": voice.instruction, "text": line]
        var captured: [String: String]?
        for _ in 0..<100 {
            if let data = try? Data(contentsOf: capture),
               let request = try? JSONDecoder().decode([String: String].self, from: data) {
                captured = request
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(captured, expected)
        voice.stop()
        XCTAssertFalse(voice.active)
        voice.speak("Next line.")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(voice.active, "Late termination must not stop the next reading")
    }
}
