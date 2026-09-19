import AppKit
import XCTest
@testable import ARCHiDesktop

final class DesktopInterestCueTests: XCTestCase {
    func testOutlineBelongsOnlyToLiveAcquisitionAndNeverClaimsCapturedContentOnHover() {
        let target = cueTarget()
        for phase in [DesktopInterestPhase.idle, .aiming, .targeted, .reading, .review, .failed] {
            let cue = DesktopInterestCue(phase: phase, target: target)
            let visible = phase == .aiming || phase == .targeted || phase == .reading
            XCTAssertEqual(cue.outlineFrame, visible ? target.frame : nil)
            XCTAssertEqual(cue.targetName, "Synthetic Editor · Synthetic notes")
            if phase == .idle || phase == .aiming || phase == .targeted {
                XCTAssertEqual(cue.scope, "No content read")
            }
        }
        XCTAssertEqual(DesktopInterestCue(phase: .review, target: target).scope, "Captured copy · no live access")
        XCTAssertEqual(DesktopInterestCue(phase: .reading, target: target).scope, "Only this window · no model request")
    }

    func testMissingAndInvalidTargetsCannotShowOrAnimateAnOutline() {
        let invalidFrames = [CGRect.zero, CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100),
                             CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 100)]
        for phase in [DesktopInterestPhase.aiming, .targeted, .reading] {
            for target in [nil] + invalidFrames.map({ Optional(cueTarget(frame: $0)) }) {
                let cue = DesktopInterestCue(phase: phase, target: target)
                XCTAssertNil(cue.outlineFrame)
                XCTAssertFalse(cue.animates(quiet: false, reduceMotion: false, systemReduceMotion: false))
            }
        }
        XCTAssertEqual(DesktopInterestCue(phase: .aiming, target: nil).title, "Pointing")
    }

    func testOnlyActiveReadingMovesAndEveryMotionPreferenceStopsIt() {
        for phase in [DesktopInterestPhase.idle, .aiming, .targeted, .reading, .review, .failed] {
            let cue = DesktopInterestCue(phase: phase, target: cueTarget())
            for quiet in [false, true] {
                for appReduced in [false, true] {
                    for systemReduced in [false, true] {
                        XCTAssertEqual(cue.animates(quiet: quiet, reduceMotion: appReduced,
                            systemReduceMotion: systemReduced), phase == .reading && !quiet && !appReduced && !systemReduced)
                    }
                }
            }
        }
        for time in stride(from: -10.0, through: 10, by: 0.05) {
            XCTAssertEqual(DesktopInterestCue.opacity(at: time, animated: false), 1)
            XCTAssertTrue((0.679...1).contains(DesktopInterestCue.opacity(at: time, animated: true)))
        }
        for time in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(DesktopInterestCue.opacity(at: time, animated: true), 1)
        }
    }

    @MainActor
    func testPointingUsesKINFocusWithoutReadingAndQuietPreservesTheSelectedScope() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-interest-kin-focus-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let preference = directory.appendingPathComponent("profile.json")
        let kin = LocalQiMon(character: .kin, originDigest: String(repeating: "a", count: 64), welcomedAt: Date())
        let saved = try NativePreferenceDocument(preferences: CompanionPreferences(), qiMon: kin).encoded()
        try saved.write(to: preference)
        let reader = CueReader(), assistant = CueAssistant()
        let store = CompanionStore(preferenceURL: preference, assistant: assistant,
            allowsPlay: false, interestReader: reader)
        XCTAssertEqual(store.activeQiMon, kin)
        XCTAssertEqual(store.cursorPresentationForm, .kinSeed)
        XCTAssertEqual(store.kinLightExpression.mode, .rest)

        store.desktopInterest.begin()
        XCTAssertEqual(store.kinLightExpression.mode, .rest, "Pointing without a candidate has no scope to focus on")
        store.desktopInterest.hover(at: .zero)
        XCTAssertEqual(store.desktopInterest.phase, .aiming)
        XCTAssertEqual(store.kinLightExpression.mode, .focus)
        XCTAssertEqual(store.desktopInterest.cue.scope, "No content read")
        store.desktopInterest.finishAim()
        let selected = store.desktopInterest.target
        XCTAssertEqual(store.desktopInterest.phase, .targeted)
        XCTAssertEqual(store.kinLightExpression.mode, .focus)

        store.preferences.reduceMotion = true
        XCTAssertEqual(store.kinLightExpression.mode, .focus, "Reduced motion retains the truthful static focus cue")
        XCTAssertEqual(KinSeedMotion.Policy(mode: store.kinLightExpression.mode,
            reduceMotion: store.preferences.reduceMotion).targetSpeed, 0)
        store.preferences.quiet = true
        XCTAssertEqual(store.kinLightExpression.mode, .rest)
        XCTAssertEqual(store.desktopInterest.target, selected, "Quiet changes presentation, not selection or access")
        XCTAssertEqual(store.desktopInterest.phase, .targeted)
        store.preferences.quiet = false
        XCTAssertEqual(store.kinLightExpression.mode, .focus)
        store.desktopInterest.cancel()
        XCTAssertEqual(store.kinLightExpression.mode, .rest)
        XCTAssertNil(store.desktopInterest.cue.outlineFrame)
        XCTAssertNil(store.desktopInterest.capture)
        XCTAssertFalse(reader.started)
        XCTAssertEqual(assistant.calls, 0)
        XCTAssertEqual(store.activeQiMon, kin)
        XCTAssertEqual(store.presentationForm, .kinSeed)
        XCTAssertEqual(store.cursorPresentationForm, .kinSeed)
        XCTAssertNil(store.evolution.kinGrowthRecord)
        XCTAssertEqual(try Data(contentsOf: preference), saved)
        await store.shutdownAssistant()
    }

    @MainActor
    func testHabitatHandoffImmediatelyCancelsReadingAndRejectsALateSnapshot() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-interest-handoff-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = CueReader(), assistant = CueAssistant()
        let store = CompanionStore(preferenceURL: directory.appendingPathComponent("profile.json"),
            assistant: assistant, allowsPlay: false, interestReader: reader)
        let panel = CompanionPanelController(store: store)
        defer { reader.finish(); panel.window.close() }
        store.desktopInterest.begin()
        store.desktopInterest.hover(at: .zero)
        store.desktopInterest.finishAim()
        store.desktopInterest.read()
        for _ in 0..<100 where !reader.started { await Task.yield() }
        XCTAssertTrue(reader.started)
        XCTAssertEqual(store.desktopInterest.phase, .reading)
        panel.setPresentedInHabitat(true)
        XCTAssertEqual(store.desktopInterest.phase, .idle, "Handoff must not wait for a later tracking tick")
        XCTAssertNil(store.desktopInterest.cue.outlineFrame)
        reader.finish()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertNil(store.desktopInterest.capture)
        XCTAssertEqual(store.desktopInterest.phase, .idle)
        XCTAssertEqual(assistant.calls, 0)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        await store.shutdownAssistant()
    }
}

private func cueTarget(frame: CGRect = CGRect(x: 50, y: 50, width: 300, height: 200)) -> DesktopInterestTarget {
    .init(windowID: 314, processID: 1234, appName: "Synthetic Editor", title: "Synthetic notes", frame: frame,
        observedAt: Date(timeIntervalSince1970: 1_800_000_000))
}

@MainActor
private final class CueReader: DesktopInterestReading {
    var started = false
    private var continuation: CheckedContinuation<DesktopInterestCapture, any Error>?
    func target(at point: CGPoint) -> DesktopInterestTarget? { cueTarget() }
    func isCurrent(_ target: DesktopInterestTarget) -> Bool { true }
    func read(_ target: DesktopInterestTarget) async throws -> DesktopInterestCapture {
        started = true
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish() {
        let pending = continuation; continuation = nil
        pending?.resume(returning: .init(target: cueTarget(), text: "Synthetic late text", method: "Fixture", capturedAt: Date()))
    }
}

@MainActor
private final class CueAssistant: AssistantClient {
    var calls = 0
    func connect() async throws { calls += 1 }
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws { calls += 1 }
}
