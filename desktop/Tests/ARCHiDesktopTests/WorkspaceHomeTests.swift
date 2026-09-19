import AppKit
import ApplicationServices
import SwiftUI
import XCTest
@testable import ARCHiDesktop

/// Opt-in acceptance of the real workspace shell with disposable local state.
/// Native buttons navigate; no model, microphone, game, or real profile is used.
final class WorkspaceHomeTests: XCTestCase {
    @MainActor
    func testWideHomeNavigationPreservesTheCurrentVisit() async throws {
        try await checkHome(size: NSSize(width: 1280, height: 820), name: "wide-light", appearance: .aqua)
    }

    @MainActor
    func testMinimumHomeKeepsEveryActionReachableWithoutGrowingTheWindow() async throws {
        try await checkHome(size: NSSize(width: 880, height: 640), name: "minimum-light", appearance: .aqua)
    }

    @MainActor
    func testDarkHomeKeepsTheSameRoutesAndControls() async throws {
        try await checkHome(size: NSSize(width: 880, height: 640), name: "minimum-dark", appearance: .darkAqua)
    }

    @MainActor
    private func checkHome(size: NSSize, name: String, appearance: NSAppearance.Name) async throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_HOME_RENDER_DIR"], !path.isEmpty else {
            throw XCTSkip("Set ARCHI_HOME_RENDER_DIR for disposable native Home navigation and rendering acceptance.")
        }
        let output = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent("home-\(name)-\(UUID())", isDirectory: true)
        let profile = FileManager.default.temporaryDirectory
            .appendingPathComponent("archi-home-profile-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: profile) }

        // The fixture has two active lessons and one expired lesson, so the
        // Home count cannot pass by showing the total number of saved records.
        let now = Date()
        let earlier = now.addingTimeInterval(-4 * 86_400)
        var preferences = CompanionPreferences()
        preferences.reduceMotion = true
        preferences.quiet = true
        let lessons = [
            KeptLesson(topic: "Planning", text: "Use a short synthetic checklist.", createdAt: earlier),
            KeptLesson(topic: "Writing", text: "Keep synthetic examples concise.", createdAt: earlier,
                       expiresAt: now.addingTimeInterval(2 * 86_400)),
            KeptLesson(topic: "Archived", text: "This synthetic lesson has expired.", createdAt: earlier,
                       expiresAt: now.addingTimeInterval(-86_400))
        ]
        let saved = try NativePreferenceDocument(preferences: preferences, lessons: lessons).encoded()
        let preferenceURL = profile.appendingPathComponent("preferences.json")
        try saved.write(to: preferenceURL)
        let client = HomeNoCallsAssistant()
        let store = CompanionStore(preferenceURL: preferenceURL, assistant: client,
            assistantFactory: { _, _ in client }, wallClock: { now }, allowsPlay: false)
        defer { store.disconnectAssistant() }
        XCTAssertEqual(store.section, .home, "The current app should open at Home.")
        XCTAssertEqual(store.keptLessons.count, 3)
        store.share(text: "Synthetic workshop notes. Keep this local working copy through navigation.",
                    name: "Synthetic workshop.txt")
        store.prompt = "An unsent synthetic draft must stay here."
        let draft = store.prompt, source = store.sharedText, sourceName = store.sourceName
        let sourceRevision = store.sourceRevision
        var opened: [WorkspaceSection] = []
        store.onOpenWorkspace = { opened.append($0) }

        let app = NSApplication.shared, previousPolicy = app.activationPolicy()
        _ = app.setActivationPolicy(.accessory)
        app.finishLaunching()
        defer { _ = app.setActivationPolicy(previousPolicy) }
        let play = HostedPlayHost(profile: .acceptance, assetDirectory: nil)
        let window = WorkspaceWindow(contentRect: NSRect(origin: CGPoint(x: 40, y: 40), size: size),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "ARCHi · Disposable Home \(name) acceptance"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        let hosting = WorkspaceView.makeHostingView(store: store, playHost: play)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        defer { window.contentView = nil; window.close() }

        var samples: [[String: Any]] = []
        var accessibilityInitialization: Int32?
        defer {
            let evidence: [String: Any] = [
                "schema": "archi-home-native-acceptance/v1", "samples": samples,
                "requestedContentSize": NSStringFromSize(size),
                "assistantCalls": client.calls,
                "accessibilityClientInitialization": accessibilityInitialization.map(Int.init) ?? -1,
                "boundary": "Synthetic native navigation and layout only. No live profile, provider inference, microphone, game, or install acceptance."
            ]
            try? JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("layout.json"))
            print("Native Home acceptance evidence: \(output.path)")
        }

        try await settle(hosting, window: window)
        WorkspaceView.applyWindowMinimum(to: window)
        window.setContentSize(size)
        try await settle(hosting, window: window)
        assertWindow(window, size: size)
        // SwiftUI installs its native accessibility proxies after attachment.
        // Query the window owner, not only the original hosting subview: native
        // split-view containers may expose their children through that owner.
        accessibilityInitialization = await initializeFixtureAccessibility()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(8))
        while clock.now < deadline {
            if snapshot(window).contains(where: { $0.id == "home.ask" }) { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertTrue(snapshot(window).contains { $0.id == "home.workspace" },
                      "Home must expose its own native accessibility container.")
        for id in ["home.ask", "home.appearance", "home.play-arena", "home.unity", "home.marketplace"] {
            let action = try XCTUnwrap(snapshot(window).first { $0.id == id })
            XCTAssertTrue(isVisible(action, inside: window.convertToScreen(window.contentLayoutRect)),
                          "\(id) must be visible on arrival, including at the minimum window size.")
        }
        try capture("home-\(name)", hosting: hosting, window: window, output: output, samples: &samples)

        _ = try await reachable("home.lesson-count", hosting: hosting, window: window)
        let countText = readableText("home.lesson-count", in: snapshot(window))
        XCTAssertNotNil(countText.range(of: "(?<![0-9])2(?![0-9])", options: .regularExpression),
                        "The readable lesson count must exclude the expired record: \(countText)")
        try capture("home-memories-\(name)", hosting: hosting, window: window, output: output, samples: &samples)
        for state in [AssistantConnectionState.disconnected, .connecting, .ready, .failed] {
            // Change presentation state directly; do not open a real connection.
            store.connectionState = state
            try await settle(hosting, window: window)
            _ = try await reachable("home.connections", hosting: hosting, window: window)
            XCTAssertTrue(readableText("home.connections", in: snapshot(window)).contains(HomeWorkspace.chatStatus(state)),
                          "Home must expose the current connection state, including failure.")
        }
        store.connectionState = .disconnected

        let routes: [(String, WorkspaceSection, String)] = [
            ("home.ask", .assistant, "assistant"),
            ("home.document", .context, "work-together"),
            ("home.memory", .memory, "memory"),
            ("home.appearance", .appearance, "appearance"),
            ("home.connections", .connections, "connections"),
            ("home.unity", .unity, "unity-area"),
            ("home.marketplace", .marketplace, "marketplace")
        ] + WorkspaceNavigation.allHomeFeatures.map {
            (HomeFeatureDirectory.identifier(for: $0), $0, "directory-\($0.id)")
        }
        _ = try await reachable(HomeFeatureDirectory.identifier(for: .advanced), hosting: hosting, window: window)
        try capture("all-features-\(name)", hosting: hosting, window: window, output: output, samples: &samples)
        for (identifier, destination, filename) in routes {
            let action = try await reachable(identifier, hosting: hosting, window: window, needsPress: true)
            samples.append(sample("reachable-\(identifier)", nodes: snapshot(window), window: window))
            try press(action)
            try await settle(hosting, window: window)
            XCTAssertEqual(store.section, destination, "The native Home action must reach its existing owner.")
            XCTAssertEqual(opened.last, destination, "Home actions should use the store's existing navigation route.")
            assertWindow(window, size: size)
            XCTAssertEqual(store.prompt, draft)
            XCTAssertEqual(store.sharedText, source)
            XCTAssertEqual(store.sourceName, sourceName)
            XCTAssertEqual(store.sourceRevision, sourceRevision)
            if WorkspaceNavigation.tools.contains(destination) {
                let sidebar = try await reachable("workspace.nav.\(destination.id)", hosting: hosting,
                                                   window: window, needsPress: true)
                try press(sidebar)
                try await settle(hosting, window: window)
                XCTAssertEqual(store.section, destination, "More tools must expose its own working native buttons.")
            }
            try capture("\(filename)-\(name)", hosting: hosting, window: window, output: output, samples: &samples)
            if destination == .assistant {
                for id in ["assistant.prompt", "assistant.send", "assistant.route", "assistant.settings"] {
                    let node = try XCTUnwrap(snapshot(window).first { $0.id == id })
                    XCTAssertTrue(isVisible(node, inside: window.convertToScreen(window.contentLayoutRect)),
                                  "\(id) must remain visible after Home navigation.")
                }
            }
            if !identifier.hasPrefix("home.feature."), destination == .appearance || destination == .connections {
                let tabs = WorkspaceNavigation.tabs(for: destination)
                for tab in tabs.dropFirst() {
                    let title = WorkspaceNavigation.tabTitle(tab)
                    let control = try XCTUnwrap(descendants(window.contentView?.superview ?? hosting)
                        .compactMap { $0 as? NSSegmentedControl }
                        .first { segment in (0..<segment.segmentCount).contains { segment.label(forSegment: $0) == title } })
                    let index = try XCTUnwrap((0..<control.segmentCount).first { control.label(forSegment: $0) == title })
                    control.selectedSegment = index
                    XCTAssertTrue(control.sendAction(control.action, to: control.target))
                    try await settle(hosting, window: window)
                    XCTAssertEqual(store.section, tab, "Grouped navigation must reach its existing section owner.")
                    XCTAssertEqual(store.prompt, draft)
                    XCTAssertEqual(store.sharedText, source)
                    XCTAssertEqual(store.preferences, preferences)
                    assertWindow(window, size: size)
                    try capture("grouped-\(title.lowercased())-\(name)", hosting: hosting, window: window, output: output, samples: &samples)
                }
            }
            if destination == .appearance {
                // Capturing the new Growth view can initiate another layout pass.
                // Let that native render turn finish before a direct AX return.
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DispatchQueue.main.async { continuation.resume() }
                }
                try await Task.sleep(for: .milliseconds(200))
            }
            let home = try await reachable("workspace.nav.home", hosting: hosting, window: window, needsPress: true)
            try press(home)
            try await settle(hosting, window: window)
            XCTAssertEqual(store.section, .home, "The native sidebar must return to the same Home.")
        }

        XCTAssertEqual(store.prompt, draft)
        XCTAssertEqual(store.sharedText, source)
        XCTAssertEqual(store.preferences, preferences)
        XCTAssertEqual(store.keptLessons, lessons)
        XCTAssertEqual(try Data(contentsOf: preferenceURL), saved, "Navigation must not save or rewrite the profile.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.appendingPathComponent("preferences.evolution.json").path))
        XCTAssertEqual(client.calls, 0, "Viewing Home and opening existing destinations must not call a provider.")
        XCTAssertNil(play.webView, "The suspended game must remain unstarted.")
        XCTAssertFalse(store.unityPresentation.isSharing, "Opening Unity Area must not start its renderer.")
        XCTAssertNil(store.unityPresentation.snapshotURL, "Navigation must not publish any presentation data.")
        XCTAssertFalse(store.marketplaceCatalog.connected, "Navigation must not connect to the creator service.")
        XCTAssertNil(store.marketplaceCatalog.account)
        XCTAssertFalse(store.isWorking)
        await store.shutdownAssistant()
        await play.shutdown()
    }

    @MainActor
    private func assertWindow(_ window: NSWindow, size: NSSize) {
        XCTAssertEqual(window.contentMinSize, NSSize(width: 880, height: 640))
        XCTAssertEqual(window.contentLayoutRect.width, size.width, accuracy: 1)
        XCTAssertEqual(window.contentLayoutRect.height, size.height, accuracy: 1,
                       "Content changes must not raise the native window's chosen size.")
    }

    /// The existing DesktopInterestPresentationTests fixture uses this public
    /// client path to initialize lazy SwiftUI AX proxies. The detached request
    /// keeps the main actor available to answer it. Only this test process's
    /// synthetic windows are queried; no permission request or private AX flag.
    @MainActor
    private func initializeFixtureAccessibility() async -> Int32 {
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
        print("Home fixture AX client initialization: \(status)")
        return status
    }

    private struct Node {
        let object: NSObject
        let id: String?
        let text: String
        let role: String?
        let frame: NSRect?
        let canPress: Bool
        let typeName: String
        let modernChildCount: Int
        let legacyChildCount: Int
        let nativeSubviewCount: Int
    }

    @MainActor
    private func snapshot(_ root: NSObject) -> [Node] {
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
            let texts = [value("accessibilityValue") as? String, value("accessibilityLabel") as? String,
                         value("accessibilityTitle") as? String,
                         object.accessibilityAttributeValue(.value) as? String,
                         object.accessibilityAttributeValue(.title) as? String]
                .compactMap { $0 }.filter { !$0.isEmpty }
            var frame = (object as? NSAccessibilityProtocol)?.accessibilityFrame()
            if frame == nil, object.responds(to: NSSelectorFromString("accessibilityFrame")),
               let boxed = object.value(forKey: "accessibilityFrame") as? NSValue {
                frame = boxed.rectValue
            }
            if frame == nil,
               let position = object.accessibilityAttributeValue(.position) as? NSValue,
               let size = object.accessibilityAttributeValue(.size) as? NSValue {
                frame = NSRect(origin: position.pointValue, size: size.sizeValue)
            }
            let role: String? = id == nil ? nil
                : ((object as? NSAccessibilityProtocol)?.accessibilityRole()?.rawValue
                   ?? value("accessibilityRole") as? String)
            let modern = value("accessibilityChildren") as? [Any] ?? []
            let legacy = attributes.contains(.children) ? object.accessibilityAttributeValue(.children) as? [Any] ?? [] : []
            nodes.append(Node(object: object, id: id, text: texts.joined(separator: " · "), role: role,
                              frame: frame, canPress: object.responds(to: NSSelectorFromString("accessibilityPerformPress")),
                              typeName: String(describing: type(of: object)), modernChildCount: modern.count,
                              legacyChildCount: legacy.count, nativeSubviewCount: (object as? NSView)?.subviews.count ?? 0))
            for child in modern + legacy {
                if let child = child as? NSObject { visit(child, depth: depth + 1) }
            }
            if let window = object as? NSWindow, let content = window.contentView {
                visit(content, depth: depth + 1)
                // The frame view is an actual AppKit sibling owner. Walking it
                // does not manufacture identifiers, geometry, or Press actions.
                if let frame = content.superview { visit(frame, depth: depth + 1) }
            }
            if let view = object as? NSView { for child in view.subviews { visit(child, depth: depth + 1) } }
        }
        visit(root, depth: 0)
        return nodes
    }

    private func readableText(_ identifier: String, in nodes: [Node]) -> String {
        let text = nodes.filter { $0.id == identifier }.map(\.text).joined(separator: " · ")
        XCTAssertFalse(text.isEmpty, "\(identifier) must expose readable native accessibility text.")
        return text
    }

    private func isVisible(_ node: Node, inside viewport: NSRect) -> Bool {
        guard let frame = node.frame, frame.width > 2, frame.height > 2,
              frame.origin.x.isFinite, frame.origin.y.isFinite, frame.width.isFinite, frame.height.isFinite else { return false }
        return viewport.insetBy(dx: -1, dy: -1).contains(frame)
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    @MainActor
    private func reachable(_ identifier: String, hosting: NSView, window: NSWindow, needsPress: Bool = false) async throws -> Node {
        let sidebarAction = identifier.hasPrefix("workspace.nav.")
        let scrolls = descendants(window.contentView?.superview ?? window.contentView ?? hosting).compactMap { $0 as? NSScrollView }
            .filter {
                let width = $0.contentView.bounds.width
                return !($0.documentView is NSTextView) && (sidebarAction ? width > 120 && width < 350 : width > 350)
            }
            .sorted {
                sidebarAction ? $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX
                    : $0.contentView.bounds.width > $1.contentView.bounds.width
            }
        func visibleNode() -> Node? {
            var viewport = window.convertToScreen(window.contentLayoutRect)
            if sidebarAction || identifier.hasPrefix("home."), let scroll = scrolls.first {
                viewport = viewport.intersection(window.convertToScreen(scroll.contentView.convert(scroll.contentView.bounds, to: nil)))
            }
            let matches = snapshot(window).filter { $0.id == identifier && isVisible($0, inside: viewport) }
            if needsPress {
                return matches.first { $0.canPress && $0.role == NSAccessibility.Role.button.rawValue }
                    ?? matches.first { $0.canPress }
            }
            return matches.first
        }
        if let node = visibleNode() { return node }
        for scroll in scrolls {
            let maximum = max(0, (scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.height)
            let count = min(30, max(1, Int(ceil(maximum / max(80, scroll.contentView.bounds.height * 0.55)))))
            for index in 0...count {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: maximum * CGFloat(index) / CGFloat(count)))
                scroll.reflectScrolledClipView(scroll.contentView)
                try await settle(hosting, window: window)
                if let node = visibleNode() { return node }
            }
        }
        return try XCTUnwrap(visibleNode(), "\(identifier) must become fully visible through native scrolling.")
    }

    @MainActor
    private func press(_ node: Node) throws {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        XCTAssertTrue(node.canPress, "\(node.id ?? "Home action") needs a native Press implementation.")
        guard node.canPress else { throw AssistantFailure.unavailable }
        if let control = node.object as? NSAccessibilityProtocol {
            XCTAssertTrue(control.accessibilityPerformPress())
        } else {
            let action = unsafeBitCast(node.object.method(for: selector),
                                       to: (@convention(c) (AnyObject, Selector) -> Bool).self)
            XCTAssertTrue(action(node.object, selector))
        }
    }

    @MainActor
    private func sample(_ stage: String, nodes: [Node], window: NSWindow) -> [String: Any] {
        ["stage": stage, "contentSize": NSStringFromSize(window.contentLayoutRect.size),
         "windowMinimum": NSStringFromSize(window.contentMinSize), "windowVisible": window.isVisible,
         "windowKey": window.isKeyWindow, "applicationActive": NSApplication.shared.isActive,
         "accessibilityNodeCount": nodes.count, "identifiedNodeCount": nodes.filter { $0.id != nil }.count,
         "traversal": nodes.map { node in
             ["type": node.typeName, "id": node.id ?? "", "modernChildren": String(node.modernChildCount),
              "legacyChildren": String(node.legacyChildCount), "nativeSubviews": String(node.nativeSubviewCount)]
         },
         "nodes": nodes.filter { $0.id != nil }.map { node in
             ["id": node.id ?? "", "text": node.text, "role": node.role ?? "unavailable",
              "frame": node.frame.map(NSStringFromRect) ?? "unavailable", "canPress": String(node.canPress)]
         }]
    }

    @MainActor
    private func capture(_ name: String, hosting: NSView, window: NSWindow, output: URL,
                         samples: inout [[String: Any]]) throws {
        samples.append(sample(name, nodes: snapshot(window), window: window))
        let content = window.contentView ?? hosting
        let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 8000, "The screenshot must contain a rendered workspace.")
        try png.write(to: output.appendingPathComponent(name + ".png"))
    }

    @MainActor
    private func settle(_ view: NSView, window: NSWindow) async throws {
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(140))
        view.layoutSubtreeIfNeeded()
    }

    @MainActor
    private final class HomeNoCallsAssistant: AssistantClient {
        var calls = 0
        func connect() async throws { calls += 1; throw AssistantFailure.unavailable }
        func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
            calls += 1
            throw AssistantFailure.unavailable
        }
        func disconnect() {}
    }
}
