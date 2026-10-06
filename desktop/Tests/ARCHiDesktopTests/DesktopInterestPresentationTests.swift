import AppKit
import ApplicationServices
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class DesktopInterestPresentationTests: XCTestCase {
    @MainActor
    func testNativePointReadReviewAndAdoptControlsUseTheExistingCopy() async throws {
        guard ProcessInfo.processInfo.environment["ARCHI_INTEREST_NATIVE"] == "1" else {
            throw XCTSkip("Set ARCHI_INTEREST_NATIVE=1 for the synthetic native object-of-interest controls.")
        }
        let app = NSApplication.shared, policy = app.activationPolicy()
        _ = app.setActivationPolicy(.accessory); app.finishLaunching()
        defer { _ = app.setActivationPolicy(policy) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-interest-ui-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = InterestPresentationReader(), assistant = InterestPresentationAssistant()
        let store = CompanionStore(preferenceURL: directory.appendingPathComponent("profile.json"),
            assistant: assistant, allowsPlay: false, interestReader: reader)
        store.prompt = "Help me plan this workshop."
        let window = NSPanel(contentRect: CGRect(x: 100, y: 100, width: 390, height: 560),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "ARCHi · synthetic target review"
        let host = NSHostingView(rootView: DesktopInterestCard(store: store).padding(15)
            .background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.light))
        host.sizingOptions = []
        window.contentView = host
        window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
        defer { window.contentView = nil; window.close() }
        // SwiftUI accessibility proxies can arrive after the first visible
        // frame. Wait for the real control rather than treating 180 ms as a
        // guarantee; the same assertion still fails if readiness never arrives.
        host.layoutSubtreeIfNeeded()
        try await initializeFixtureAccessibility()
        try await waitForControl("interest.begin", root: window)
        if let path = ProcessInfo.processInfo.environment["ARCHI_INTEREST_RENDER_DIR"],
           let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to:
                URL(fileURLWithPath: path).appendingPathComponent("native-target-idle.png"))
            let hierarchy = nodes(window).map { node in
                ["accessibilityIdentifier", "accessibilityLabel", "accessibilityRole"].map { name in
                    let selector = NSSelectorFromString(name)
                    return node.responds(to: selector) ? String(describing: node.perform(selector)?.takeUnretainedValue()) : "unavailable"
                }.joined(separator: " | ")
            }.joined(separator: "\n")
            try hierarchy.write(to: URL(fileURLWithPath: path).appendingPathComponent("native-target-idle-ax.txt"), atomically: true, encoding: .utf8)
            try renderOutlineStates(target: reader.selected, directory: URL(fileURLWithPath: path))
        }
        try press("interest.begin", root: window)
        XCTAssertEqual(store.desktopInterest.phase, .aiming)
        store.desktopInterest.hover(at: CGPoint(x: 120, y: 120))
        try await Task.sleep(for: .milliseconds(100))
        try press("interest.choose", root: window)
        XCTAssertEqual(reader.reads, 0)
        try await Task.sleep(for: .milliseconds(100))
        assertScope("Window selected. No content read", root: window)
        try press("interest.read", root: window)
        for _ in 0..<100 where store.desktopInterest.phase != .review {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(store.desktopInterest.phase, .review)
        XCTAssertEqual(reader.reads, 1)
        XCTAssertNil(store.sourceName)
        try await Task.sleep(for: .milliseconds(60))
        assertScope("Snapshot ready. Captured copy · no live access", root: window)
        host.layoutSubtreeIfNeeded()
        if let path = ProcessInfo.processInfo.environment["ARCHI_INTEREST_RENDER_DIR"],
           let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to:
                URL(fileURLWithPath: path).appendingPathComponent("native-target-review.png"))
        }
        try press("interest.use", root: window)
        XCTAssertEqual(store.sharedText, "Workshop: Friday at 3 PM. Bring the revised outline.")
        XCTAssertEqual(store.prompt, "Help me plan this workshop.")
        XCTAssertEqual(store.section, .context)
        XCTAssertEqual(store.desktopInterest.phase, .idle)
        let play = HostedPlayHost(profile: .acceptance, assetDirectory: nil)
        let workspace = WorkspaceView.makeHostingView(store: store, playHost: play)
        window.contentView = workspace
        WorkspaceView.applyWindowMinimum(to: window)
        window.setContentSize(CGSize(width: 880, height: 640))
        store.setAssistantRoute(.codex)
        try await Task.sleep(for: .milliseconds(200))
        workspace.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(workspace.bounds.width, 881)
        XCTAssertLessThanOrEqual(workspace.bounds.height, 641)
        XCTAssertFalse(store.canShareDesktopInterestWithRoute)
        try press("interest.allow-external", root: window)
        XCTAssertTrue(store.canShareDesktopInterestWithRoute)
        if let path = ProcessInfo.processInfo.environment["ARCHI_INTEREST_RENDER_DIR"],
           let bitmap = workspace.bitmapImageRepForCachingDisplay(in: workspace.bounds) {
            workspace.cacheDisplay(in: workspace.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to:
                URL(fileURLWithPath: path).appendingPathComponent("work-together-880.png"))
        }
        XCTAssertNil(play.webView)
        XCTAssertEqual(assistant.calls, 0)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        await store.shutdownAssistant()
        await play.shutdown()
    }

    /// Exercise the public client path against this test process only. SwiftUI
    /// does not always instantiate its AX proxies until a client requests them.
    /// No permissions are requested and no foreign window is read.
    @MainActor private func initializeFixtureAccessibility() async throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let status = await Task.detached {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 1)
            var windows: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windows)
            if status == .success, let windows = windows as? [AXUIElement] {
                for window in windows.prefix(2) {
                    var children: CFTypeRef?
                    AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &children)
                }
            }
            return status.rawValue
        }.value
        print("Fixture AX client initialization: \(status)")
    }

    @MainActor private func waitForControl(_ identifier: String, root: NSObject) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(8))
        while clock.now < deadline {
            if control(identifier, root: root) != nil { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        _ = try XCTUnwrap(control(identifier, root: root), "Native control did not become ready: \(identifier)")
    }

    @MainActor private func assertScope(_ expected: String, root: NSObject) {
        let selector = NSSelectorFromString("accessibilityLabel")
        XCTAssertTrue(nodes(root).contains {
            $0.responds(to: selector) && ($0.perform(selector)?.takeUnretainedValue() as? String) == expected
        }, "Missing native scope label: \(expected)")
    }

    @MainActor private func renderOutlineStates(target: DesktopInterestTarget, directory: URL) throws {
        for phase in [DesktopInterestPhase.aiming, .targeted, .reading] {
            let cue = DesktopInterestCue(phase: phase, target: target)
            let view = ZStack(alignment: .topLeading) {
                Color(red: 0.075, green: 0.085, blue: 0.085)
                VStack(alignment: .leading, spacing: 18) {
                    Text("Workshop notes").font(.system(size: 22, weight: .semibold))
                    Text("Friday · 3 PM").font(.system(size: 15))
                    Text("Bring the revised outline.\n\nConfirm the agenda with the team.")
                        .font(.system(size: 14)).lineSpacing(6)
                }.foregroundStyle(.white.opacity(0.85)).padding(.horizontal, 35).padding(.top, 100)
                DesktopInterestOutlineView(cue: cue, animated: false)
            }.frame(width: 600, height: 420)
            let host = NSHostingView(rootView: view)
            host.frame = CGRect(x: 0, y: 0, width: 600, height: 420)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: directory.appendingPathComponent("outline-" + phase.rawValue + "-static.png"))
        }
    }

    @MainActor private func nodes(_ root: NSObject) -> [NSObject] {
        var found: [NSObject] = [], seen = Set<ObjectIdentifier>()
        func visit(_ node: NSObject, depth: Int) {
            guard depth < 35, found.count < 2000, seen.insert(ObjectIdentifier(node)).inserted else { return }
            found.append(node)
            let selector = NSSelectorFromString("accessibilityChildren")
            if node.responds(to: selector), let children = node.perform(selector)?.takeUnretainedValue() as? [NSObject] {
                for child in children { visit(child, depth: depth + 1) }
            }
            if node.accessibilityAttributeNames().contains(.children) {
                for child in node.accessibilityAttributeValue(.children) as? [NSObject] ?? [] { visit(child, depth: depth + 1) }
            }
            if let window = node as? NSWindow, let content = window.contentView { visit(content, depth: depth + 1) }
            if let view = node as? NSView { for child in view.subviews { visit(child, depth: depth + 1) } }
        }
        visit(root, depth: 0); return found
    }
    @MainActor private func control(_ identifier: String, root: NSObject) -> NSObject? {
        nodes(root).first {
            let selector = NSSelectorFromString("accessibilityIdentifier")
            return ($0.responds(to: selector) ? $0.perform(selector)?.takeUnretainedValue() as? String : nil) == identifier
                || ($0.accessibilityAttributeNames().contains(.identifier)
                    && $0.accessibilityAttributeValue(.identifier) as? String == identifier)
        }
    }
    @MainActor private func press(_ identifier: String, root: NSObject) throws {
        let node = try XCTUnwrap(control(identifier, root: root), "Missing native control \(identifier)")
        let selector = NSSelectorFromString("accessibilityPerformPress")
        XCTAssertTrue(node.responds(to: selector))
        guard node.responds(to: selector) else { return }
        let action = unsafeBitCast(node.method(for: selector), to: (@convention(c) (AnyObject, Selector) -> Bool).self)
        XCTAssertTrue(action(node, selector))
    }
}

@MainActor private final class InterestPresentationReader: DesktopInterestReading {
    var reads = 0
    let selected = DesktopInterestTarget(windowID: 991, processID: 999,
        appName: "Synthetic Notes", title: "Workshop", frame: CGRect(x: 100, y: 100, width: 600, height: 420),
        observedAt: Date(timeIntervalSince1970: 1_800_000_000))
    func target(at point: CGPoint) -> DesktopInterestTarget? { selected }
    func isCurrent(_ target: DesktopInterestTarget) -> Bool { target == selected }
    func read(_ target: DesktopInterestTarget) async throws -> DesktopInterestCapture {
        reads += 1
        return DesktopInterestCapture(target: selected,
            text: "Workshop: Friday at 3 PM. Bring the revised outline.", method: "Synthetic app-exposed text fixture", capturedAt: selected.observedAt)
    }
}
@MainActor private final class InterestPresentationAssistant: AssistantClient {
    var calls = 0
    func connect() async throws { calls += 1 }
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws { calls += 1 }
}
