import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

/// Opt-in, real native controls in a disposable profile. Never calls a model,
/// opens a file picker, changes a budget, installs an app, or touches a user profile.
final class TokenStewardCapabilityLayoutTests: XCTestCase {
    @MainActor
    func testMinimumWorkspaceMakesStewardAndCapabilitiesReachableWithoutInference() async throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_STEWARD_LAYOUT_DIR"], !path.isEmpty else {
            throw XCTSkip("Set ARCHI_STEWARD_LAYOUT_DIR for disposable native Token Steward / ARC layout acceptance.")
        }
        let output = URL(fileURLWithPath: path).appendingPathComponent("steward-capabilities-\(UUID())")
        let profile = FileManager.default.temporaryDirectory.appendingPathComponent("archi-steward-layout-\(UUID())")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: profile) }
        var preferences = CompanionPreferences()
        preferences.reduceMotion = true
        preferences.quiet = true
        let original = try NativePreferenceDocument(preferences: preferences).encoded()
        let preferenceURL = profile.appendingPathComponent("preferences.json")
        try original.write(to: preferenceURL)
        let client = NoCallsAssistant()
        let store = CompanionStore(preferenceURL: preferenceURL, assistant: client,
            assistantFactory: { _, _ in client }, allowsPlay: false)
        defer { store.disconnectAssistant() }
        store.prompt = "A local unsent draft."
        store.share(text: "Synthetic document kept through navigation.", name: "Synthetic.txt")
        let draft = store.prompt, source = store.sharedText, lessons = store.keptLessons
        let app = NSApplication.shared, previousPolicy = app.activationPolicy()
        _ = app.setActivationPolicy(.accessory)
        app.finishLaunching()
        defer { _ = app.setActivationPolicy(previousPolicy) }
        let play = HostedPlayHost(profile: .acceptance, assetDirectory: nil)
        let size = NSSize(width: 880, height: 640)
        let window = WorkspaceWindow(contentRect: NSRect(origin: CGPoint(x: 40, y: 40), size: size),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "ARCHi · Disposable Steward and ARC acceptance"
        window.isReleasedWhenClosed = false
        let hosting = WorkspaceView.makeHostingView(store: store, playHost: play)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        defer { window.contentView = nil; window.close() }
        try await settle(hosting, window)
        WorkspaceView.applyWindowMinimum(to: window)
        window.setContentSize(size)
        try await settle(hosting, window)
        try await NativeAccessibilityFixture.initialize(waitingFor: "workspace.nav.home") {
            self.snapshot(window).contains { $0.id == "workspace.nav.home" }
        }
        var samples: [[String: String]] = []
        defer {
            try? JSONSerialization.data(withJSONObject: ["schema": "archi-steward-capabilities-layout/v1", "samples": samples,
                "assistantCalls": client.calls, "boundary": "Disposable local native controls; no live model, budget change, install or real profile."],
                options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("layout.json"))
            print("Token Steward / ARC native acceptance: \(output.path)")
        }

        let capabilities = try await reachable("workspace.nav.ARC Capabilities", hosting, window)
        try press(capabilities)
        try await settle(hosting, window)
        XCTAssertEqual(store.section, .capabilities)
        for id in ["capabilities.import", "capabilities.synthetic-demo"] {
            let node = try await reachable(id, hosting, window)
            XCTAssertTrue(node.canPress, "\(id) must support native keyboard/assistive activation.")
            samples.append(["id": id, "frame": node.frame.map(NSStringFromRect) ?? "missing"])
        }
        try capture(hosting, output.appendingPathComponent("capabilities-minimum.png"))
        XCTAssertTrue(store.arcCapabilities.records.isEmpty)
        XCTAssertTrue(store.tokenSteward.tasks.isEmpty, "Viewing workspaces must not manufacture usage.")
        let demonstration = try await reachable("capabilities.synthetic-demo", hosting, window)
        try press(demonstration)
        try await settle(hosting, window)
        XCTAssertEqual(store.arcCapabilities.records.count, 1)
        XCTAssertEqual(store.arcCapabilities.records.first?.summary.counts.exact, 1)
        XCTAssertEqual(store.tokenSteward.summary.evaluationTaskCount, 1)
        XCTAssertEqual(store.tokenSteward.summary.localAttemptCount, 0)
        XCTAssertEqual(store.tokenSteward.summary.usefulTaskCount, 0)
        XCTAssertEqual(store.tokenSteward.summary.syntheticCheckedTaskCount, 0,
            "The fixed demonstration has an incorrect prediction; a successful import is not a passed check.")

        let steward = try await reachable("workspace.nav.Token Steward", hosting, window)
        try press(steward)
        try await settle(hosting, window)
        XCTAssertEqual(store.section, .steward)
        for id in ["steward.guard-status", "steward.daily-budget", "steward.monthly-budget", "steward.save-budget", "steward.clear-budget", "steward.export"] {
            let node = try await reachable(id, hosting, window)
            if id == "steward.save-budget" || id == "steward.export" { XCTAssertTrue(node.canPress) }
            samples.append(["id": id, "frame": node.frame.map(NSStringFromRect) ?? "missing"])
            XCTAssertEqual(window.contentLayoutRect.width, size.width, accuracy: 1)
            XCTAssertEqual(window.contentLayoutRect.height, size.height, accuracy: 1)
        }
        _ = try await reachable("steward.save-budget", hosting, window)
        try capture(hosting, output.appendingPathComponent("steward-budget-minimum.png"))
        XCTAssertNil(store.tokenSteward.budget, "Inspecting controls must not set spending permission.")
        XCTAssertEqual(window.contentMinSize, size)
        XCTAssertEqual(store.preferences, preferences)
        XCTAssertEqual(store.keptLessons, lessons)
        XCTAssertEqual(store.prompt, draft)
        XCTAssertEqual(store.sharedText, source)
        XCTAssertEqual(try Data(contentsOf: preferenceURL), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.appendingPathComponent("preferences.evolution.json").path))
        XCTAssertEqual(client.calls, 0)
        XCTAssertNil(play.webView)
        XCTAssertFalse(store.unityPresentation.isSharing)
        XCTAssertFalse(store.marketplaceCatalog.connected)
        await store.shutdownAssistant()
        await play.shutdown()
    }

    private struct Node {
        let object: NSObject
        let id: String?
        let frame: NSRect?
        let canPress: Bool
    }

    @MainActor private func snapshot(_ root: NSObject) -> [Node] {
        var nodes: [Node] = [], seen = Set<ObjectIdentifier>()
        func visit(_ object: NSObject, depth: Int) {
            guard depth < 40, nodes.count < 4000, seen.insert(ObjectIdentifier(object)).inserted else { return }
            func value(_ name: String) -> Any? {
                let selector = NSSelectorFromString(name)
                return object.responds(to: selector) ? object.perform(selector)?.takeUnretainedValue() : nil
            }
            let attributes = object.accessibilityAttributeNames()
            let id = value("accessibilityIdentifier") as? String
                ?? (attributes.contains(.identifier) ? object.accessibilityAttributeValue(.identifier) as? String : nil)
            var frame = (object as? NSAccessibilityProtocol)?.accessibilityFrame()
            if frame == nil, object.responds(to: NSSelectorFromString("accessibilityFrame")),
               let boxed = object.value(forKey: "accessibilityFrame") as? NSValue { frame = boxed.rectValue }
            if frame == nil, let position = object.accessibilityAttributeValue(.position) as? NSValue,
               let size = object.accessibilityAttributeValue(.size) as? NSValue { frame = NSRect(origin: position.pointValue, size: size.sizeValue) }
            nodes.append(Node(object: object, id: id, frame: frame,
                canPress: object.responds(to: NSSelectorFromString("accessibilityPerformPress"))))
            let modern = value("accessibilityChildren") as? [Any] ?? []
            let legacy = attributes.contains(.children) ? object.accessibilityAttributeValue(.children) as? [Any] ?? [] : []
            for child in modern + legacy { if let child = child as? NSObject { visit(child, depth: depth + 1) } }
            if let window = object as? NSWindow, let content = window.contentView {
                visit(content, depth: depth + 1)
                if let frame = content.superview { visit(frame, depth: depth + 1) }
            }
            if let view = object as? NSView { for child in view.subviews { visit(child, depth: depth + 1) } }
        }
        visit(root, depth: 0)
        return nodes
    }

    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    @MainActor private func reachable(_ id: String, _ hosting: NSView, _ window: NSWindow) async throws -> Node {
        let sidebar = id.hasPrefix("workspace.nav.")
        let scrolls = descendants(window.contentView?.superview ?? hosting).compactMap { $0 as? NSScrollView }
            .filter { !($0.documentView is NSTextView) && (sidebar ? $0.contentView.bounds.width < 300 : $0.contentView.bounds.width > 350) }
        func visible() -> Node? {
            let windowViewport = window.convertToScreen(window.contentLayoutRect)
            return snapshot(window).first { node in
                guard node.id == id, let frame = node.frame, frame.width > 2, frame.height > 2,
                      windowViewport.insetBy(dx: -1, dy: -1).contains(frame) else { return false }
                return scrolls.contains { scroll in
                    let viewport = window.convertToScreen(scroll.contentView.convert(scroll.contentView.bounds, to: nil))
                    return viewport.insetBy(dx: -1, dy: -1).contains(frame)
                }
            }
        }
        if let node = visible() { return node }
        for scroll in scrolls {
            let maximum = max(0, (scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.height)
            let count = min(30, max(1, Int(ceil(maximum / max(80, scroll.contentView.bounds.height * 0.45)))))
            for index in 0...count {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: maximum * CGFloat(index) / CGFloat(count)))
                scroll.reflectScrolledClipView(scroll.contentView)
                try await settle(hosting, window)
                if let node = visible() { return node }
            }
        }
        return try XCTUnwrap(visible(), "\(id) must become fully visible inside its native scroll viewport at 880×640.")
    }

    @MainActor private func press(_ node: Node) throws {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard node.canPress else { XCTFail("No native Press action for \(node.id ?? "control")"); throw AssistantFailure.unavailable }
        if let control = node.object as? NSAccessibilityProtocol { XCTAssertTrue(control.accessibilityPerformPress()) }
        else {
            let action = unsafeBitCast(node.object.method(for: selector), to: (@convention(c) (AnyObject, Selector) -> Bool).self)
            XCTAssertTrue(action(node.object, selector))
        }
    }

    @MainActor private func settle(_ view: NSView, _ window: NSWindow) async throws {
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(140))
        view.layoutSubtreeIfNeeded()
    }

    @MainActor private func capture(_ view: NSView, _ url: URL) throws {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }

    @MainActor private final class NoCallsAssistant: AssistantClient {
        var calls = 0
        func connect() async throws { calls += 1; throw AssistantFailure.unavailable }
        func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
            calls += 1; throw AssistantFailure.unavailable
        }
        func disconnect() {}
    }
}
