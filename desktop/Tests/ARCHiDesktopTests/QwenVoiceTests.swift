import AVFoundation
import CryptoKit
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
    func testBundledSamplesDecodeWithoutAnInstalledRuntime() throws {
        let voice = QwenVoice(runtime: URL(fileURLWithPath: "/missing-archi-voice-fixture"))
        struct Bank: Decodable {
            struct Take: Decodable { let speaker: String; let sha256: String }
            let text: String
            let instruction: String
            let assets: [Take]
        }
        let folder = try XCTUnwrap(voice.sampleURL).deletingLastPathComponent()
        let manifest = try JSONDecoder().decode(Bank.self, from: Data(contentsOf: folder.appendingPathComponent("auditions.json")))
        XCTAssertEqual(manifest.text, QwenVoice.preview)
        XCTAssertEqual(manifest.instruction, voice.instruction)
        XCTAssertEqual(manifest.assets.map(\.speaker), QwenVoice.speakers)
        XCTAssertEqual(Set(manifest.assets.map(\.sha256)).count, QwenVoice.speakers.count)
        for take in manifest.assets {
            voice.speaker = take.speaker
            let url = try XCTUnwrap(voice.sampleURL)
            let digest = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, take.sha256)
            let file = try AVAudioFile(forReading: url)
            XCTAssertEqual(file.processingFormat.sampleRate, 24000)
            XCTAssertEqual(file.processingFormat.channelCount, 1)
            XCTAssertGreaterThan(file.length, 12000)
        }
        voice.speaker = "../missing"
        XCTAssertNil(voice.sampleURL)
    }

    @MainActor
    func testWarmWorkerGetsFreshTextAndDirectionAndExpiresWhenIdle() async throws {
        let root = try prepareWorker()
        defer { try? FileManager.default.removeItem(at: root) }
        let voice = QwenVoice(runtime: root, resources: root, idleDelay: .milliseconds(650))
        defer { voice.stop() }
        let text = "Aloha, \"pH\".\nReady?"
        voice.speak(text)
        try await waitUntil { !voice.active }
        XCTAssertEqual(voice.message, "Reading finished.")
        voice.speaker = "Vivian"
        voice.instruction = "Quietly."
        voice.speak("Second reading.")
        try await waitUntil { !voice.active }
        let capture = try String(contentsOf: root.appendingPathComponent("capture"), encoding: .utf8)
        let lines = try capture.split(separator: "\n").map { try JSONDecoder().decode([String: String].self, from: Data($0.utf8)) }
        XCTAssertEqual(lines.map { $0["text"] }, [text, "Second reading."])
        XCTAssertEqual(lines.last?["voice"], "Vivian")
        XCTAssertEqual(lines.last?["instruction"], "Quietly.")
        XCTAssertNotEqual(lines.first?["id"], lines.last?["id"])
        let launches = root.appendingPathComponent("launches")
        XCTAssertEqual(try String(contentsOf: launches, encoding: .utf8).split(separator: "\n").count, 1)
        try await Task.sleep(for: .milliseconds(1200))
        voice.speak("After timeout.")
        try await waitUntil { !voice.active }
        XCTAssertEqual(try String(contentsOf: launches, encoding: .utf8).split(separator: "\n").count, 2)
    }

    @MainActor
    func testStopAndLateExitCannotFinishTheReplacementReading() async throws {
        let root = try prepareWorker()
        defer { try? FileManager.default.removeItem(at: root) }
        let voice = QwenVoice(runtime: root, resources: root)
        defer { voice.stop() }
        voice.speak("hold")
        try await waitUntil { FileManager.default.fileExists(atPath: root.appendingPathComponent("capture").path) }
        voice.stop()
        XCTAssertFalse(voice.active)
        voice.speak("hold")
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(voice.active)
        voice.stop()
        voice.speak("Recovered.")
        try await waitUntil { !voice.active }
        XCTAssertEqual(voice.message, "Reading finished.")
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for voice state")
    }

    private func prepareWorker() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bin = root.appendingPathComponent("venv/bin")
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: bin.appendingPathComponent("python"), withDestinationURL: URL(fileURLWithPath: "/bin/sh"))
        try Data().write(to: root.appendingPathComponent("ready-0.6.8-f35faf1"))
        let script = #"""
        cd "$(dirname "$0")" || exit 1
        echo "$$" >> launches
        while IFS= read -r line; do
            printf '%s\n' "$line" >> capture
            case "$line" in *'"text":"hold"'*) exec /bin/sleep 30 ;; esac
            printf '%s\n' "$line" | /usr/bin/sed -E 's/.*"id":"([-a-f0-9]+)".*/\1/'
        done
        """#
        try script.write(to: root.appendingPathComponent("speech.py"), atomically: true, encoding: .utf8)
        return root
    }
}
