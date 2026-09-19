import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class FocusGestureLayoutTests: XCTestCase {
    /// Uses the actual workspace and native accessibility geometry. The Play
    /// owner is never started, and the synthetic assistant rejects any call.
    @MainActor
    func testMinimumWorkspaceKeepsGestureControlsSeparateAndTeachingReachable() async throws {
        try await checkMinimumWorkspace(hasKin: false)
    }

    @MainActor
    func testMinimumKinWorkspaceReservesFocusLightAndStaffRows() async throws {
        try await checkMinimumWorkspace(hasKin: true)
    }

    @MainActor
    private func checkMinimumWorkspace(hasKin: Bool) async throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_GESTURE_LAYOUT_DIR"] else {
            throw XCTSkip("Set ARCHI_GESTURE_LAYOUT_DIR for real native gesture layout acceptance.")
        }
        let output = URL(fileURLWithPath: path).appendingPathComponent("layout-\(UUID())")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let app = NSApplication.shared, previousPolicy = app.activationPolicy()
        _ = app.setActivationPolicy(.accessory)
        app.finishLaunching()
        defer { _ = app.setActivationPolicy(previousPolicy) }
        let client = LayoutAssistant()
        let preferenceURL = output.appendingPathComponent("unused-preferences.json")
        let preferences: Data?
        if hasKin {
            preferences = try NativePreferenceDocument(qiMon: LocalQiMon(character: .kin,
                originDigest: String(repeating: "a", count: 64), welcomedAt: Date())).encoded()
            try preferences?.write(to: preferenceURL)
        } else {
            preferences = nil
        }
        let store = CompanionStore(preferenceURL: preferenceURL, assistant: client, allowsPlay: false)
        XCTAssertEqual(store.activeQiMon != nil, hasKin)
        store.preferences.form = .particle
        store.preferences.reduceMotion = true
        store.preferences.equipment = CompanionEquipment(hand: .focusStaff)
        store.share(text: "A useful synthetic passage. A second sentence for layout inspection.", name: "layout.txt")
        store.section = .context
        let host = HostedPlayHost(profile: .acceptance, assetDirectory: nil)
        let window = WorkspaceWindow(contentRect: NSRect(x: 80, y: 80, width: 1080, height: 750),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "ARCHi · Staff gesture layout acceptance"
        let hosting = WorkspaceView.makeHostingView(store: store, playHost: host)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        app.activate()
        defer {
            store.stopFocusGesture()
            window.contentView = nil
            window.close()
        }
        var samples: [[String: Any]] = []
        defer {
            try? JSONSerialization.data(withJSONObject: ["schema": "archi-focus-gesture-layout/v1", "samples": samples],
                options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("layout.json"))
            print("Native staff gesture layout evidence: \(output.path)")
        }

        let requestedSize = NSSize(width: 880, height: 640)
        // Let the split view attach its toolbar before applying the same native
        // minimum policy as production, then exercise an actual user resize.
        try await settle(hosting, window: window)
        WorkspaceView.applyWindowMinimum(to: window)
        window.setContentSize(requestedSize)
        try await settle(hosting, window: window)
        try await NativeAccessibilityFixture.initialize(waitingFor: "work.explain") {
            self.snapshot(hosting).contains { $0.id == "work.explain" }
        }
        let baselineSize = window.contentLayoutRect.size
        samples.append(["stage": "minimum-before-teaching",
            "requestedContentSize": NSStringFromSize(requestedSize),
            "actualContentLayoutSize": NSStringFromSize(baselineSize),
            "windowFrame": NSStringFromRect(window.frame), "hostingBounds": NSStringFromRect(hosting.bounds),
            "windowMinimum": NSStringFromSize(window.contentMinSize), "windowVisible": window.isVisible,
            "windowKey": window.isKeyWindow, "applicationActive": app.isActive])
        try saveImage(hosting, to: output.appendingPathComponent("minimum-before-teaching.png"))
        XCTAssertEqual(window.contentMinSize, requestedSize, "The native window must retain its minimum constraint.")
        XCTAssertEqual(baselineSize.width, requestedSize.width, accuracy: 1,
            "The root must respect the app's native minimum width.")
        XCTAssertEqual(baselineSize.height, requestedSize.height, accuracy: 1,
            "The root must respect the app's native minimum height.")
        store.beginFocusGestureTeaching()
        try await settle(hosting, window: window)
        XCTAssertEqual(window.contentLayoutRect.width, baselineSize.width, accuracy: 1,
            "Opening a teaching draft must not widen the existing native minimum.")
        XCTAssertEqual(window.contentLayoutRect.height, baselineSize.height, accuracy: 1,
            "Opening a teaching draft must not raise the existing native minimum.")
        let contentScreen = window.convertToScreen(window.contentLayoutRect)
        let work = snapshot(hosting)
        samples.append(evidence("work-minimum", nodes: work, viewport: contentScreen))
        try saveImage(hosting, to: output.appendingPathComponent("work-minimum.png"))
        let workIDs = ["work.explain", "work.rewrite", "work.shorten", "work.focus-staff", "work.point-and-explain",
            "focus-gesture.practice", "focus-gesture.review", "focus-gesture.work-options",
            "focus-gesture.work-status", "work.prompt", "work.send", "work.notice"]
            + (hasKin ? ["work.kin-focus-light"] : [])
        var workFrames: [String: NSRect] = [:]
        for id in workIDs {
            let node = try unique(id, in: work)
            let frame = try XCTUnwrap(node.frame, "No native accessibility frame for \(id)")
            XCTAssertGreaterThan(frame.width, 2, id)
            XCTAssertGreaterThan(frame.height, 2, id)
            XCTAssertTrue(contentScreen.insetBy(dx: -1, dy: -1).contains(frame),
                "\(id) must fit in the actual minimum window: \(frame)")
            workFrames[id] = frame
        }
        for (index, left) in workIDs.enumerated() {
            for right in workIDs.dropFirst(index + 1) {
                let overlap = try XCTUnwrap(workFrames[left]).intersection(try XCTUnwrap(workFrames[right]))
                XCTAssertTrue(overlap.isNull || overlap.width <= 1 || overlap.height <= 1,
                    "Independent controls overlap: \(left) and \(right): \(overlap)")
            }
        }
        let document = try XCTUnwrap(descendants(hosting).compactMap { $0 as? NSScrollView }
            .first { ($0.documentView as? NSTextView)?.string == store.sharedText })
        let documentScreen = window.convertToScreen(document.convert(document.bounds, to: nil))
        XCTAssertGreaterThan(documentScreen.height, 90, "The real shared document needs a usable viewport.")
        XCTAssertGreaterThan(documentScreen.width, 200)
        XCTAssertTrue(contentScreen.contains(documentScreen))
        XCTAssertLessThanOrEqual(try XCTUnwrap(workFrames["work.explain"]).maxY, documentScreen.minY + 1,
            "Passage actions must remain below the actual document viewport.")

        if !hasKin {
            store.section = .appearance
            try await settle(hosting, window: window)
            let scroll = try XCTUnwrap(descendants(hosting).compactMap { $0 as? NSScrollView }
                .filter { $0.contentView.bounds.width > 400 && ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height }
                .max { $0.contentView.bounds.width < $1.contentView.bounds.width },
                "The production Appearance scrolling surface must be available.")
            let documentView = try XCTUnwrap(scroll.documentView)
            let maximumY = max(0, documentView.bounds.height - scroll.contentView.bounds.height)
            let step = max(80, scroll.contentView.bounds.height * 0.55)
            let positions = Array(stride(from: CGFloat(0), through: maximumY, by: step)) + [maximumY]
            let teachingIDs: Set<String> = ["focus-gesture.pace", "focus-gesture.sparkle", "focus-gesture.hold",
                "focus-gesture.preview", "focus-gesture.stop", "focus-gesture.open-practice", "focus-gesture.keep", "focus-gesture.cancel"]
            var reached = Set<String>()
            for (index, position) in positions.enumerated() {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: position))
                scroll.reflectScrolledClipView(scroll.contentView)
                try await settle(hosting, window: window)
                let viewport = window.convertToScreen(scroll.contentView.convert(scroll.contentView.bounds, to: nil))
                let nodes = snapshot(hosting)
                samples.append(evidence("appearance-scroll-\(index)", nodes: nodes, viewport: viewport))
                var newlyVisible = false
                for id in teachingIDs {
                    let matching = nodes.filter { $0.id == id }
                    guard !matching.isEmpty else { continue }
                    let node = try unique(id, in: nodes)
                    if let frame = node.frame, frame.width > 2, frame.height > 2,
                       viewport.insetBy(dx: -1, dy: -1).contains(frame) {
                        newlyVisible = reached.insert(id).inserted || newlyVisible
                    }
                }
                if newlyVisible {
                    try saveImage(hosting, to: output.appendingPathComponent("appearance-scroll-\(index).png"))
                }
            }
            XCTAssertEqual(reached, teachingIDs, "Every teaching picker and action must become fully visible through native scrolling.")
        }
        XCTAssertNotNil(store.focusGestureDraft, "The same draft survives production navigation and scrolling.")
        XCTAssertNil(host.webView, "Layout acceptance must not start WebKit or play.")
        XCTAssertEqual(client.calls, 0, "No model operation belongs to this layout check.")
        if let preferences {
            XCTAssertEqual(try Data(contentsOf: preferenceURL), preferences)
        } else {
            XCTAssertFalse(FileManager.default.fileExists(atPath: preferenceURL.path))
        }
        await store.shutdownAssistant()
    }

    /// Long replies and attachment names must never scroll the draft or Send away.
    @MainActor
    func testAssistantComposerRemainsVisibleWhenReplyScrolls() async throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_GESTURE_LAYOUT_DIR"] else {
            throw XCTSkip("Set ARCHI_GESTURE_LAYOUT_DIR for native assistant composer layout acceptance.")
        }
        let output = URL(fileURLWithPath: path).appendingPathComponent("assistant-layout-\(UUID())")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var samples: [[String: Any]] = []
        defer {
            try? JSONSerialization.data(withJSONObject: ["schema": "archi-assistant-composer-layout/v1", "samples": samples],
                options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("layout.json"))
            print("Native assistant composer layout evidence: \(output.path)")
        }
        let app = NSApplication.shared, previousPolicy = app.activationPolicy()
        _ = app.setActivationPolicy(.accessory)
        app.finishLaunching()
        defer { _ = app.setActivationPolicy(previousPolicy) }
        let client = LayoutAssistant()
        let preferenceURL = output.appendingPathComponent("unused-preferences.json")
        let store = CompanionStore(preferenceURL: preferenceURL, assistant: client,
            assistantFactory: { _, _ in client }, allowsPlay: false)
        store.preferences.reduceMotion = true
        store.share(text: String(repeating: "A synthetic document passage. ", count: 100),
            name: String(repeating: "A long document title ", count: 10) + ".txt")
        store.setAssistantRoute(.automatic)
        // Changing routes clears an earlier reply; install the long fixture afterward.
        store.reply = String(repeating: "A long synthetic reply remains readable in its own scrolling area.\n\n", count: 70)
        store.prompt = "My draft stays reachable."
        store.section = .assistant
        let source = store.sharedText, draft = store.prompt
        let host = HostedPlayHost(profile: .acceptance, assetDirectory: nil)
        let window = WorkspaceWindow(contentRect: NSRect(x: 80, y: 80, width: 880, height: 640),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hosting = WorkspaceView.makeHostingView(store: store, playHost: host)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        app.activate()
        defer { window.contentView = nil; window.close() }
        try await settle(hosting, window: window)
        WorkspaceView.applyWindowMinimum(to: window)
        window.setContentSize(NSSize(width: 880, height: 640))
        try await settle(hosting, window: window)
        try await NativeAccessibilityFixture.initialize(waitingFor: "assistant.prompt") {
            self.snapshot(hosting).contains { $0.id == "assistant.prompt" }
        }
        samples.append(["stage": "minimum-before-scroll", "requestedContentSize": "{880, 640}",
            "actualContentLayoutSize": NSStringFromSize(window.contentLayoutRect.size),
            "windowFrame": NSStringFromRect(window.frame), "windowVisible": window.isVisible,
            "windowKey": window.isKeyWindow, "applicationActive": app.isActive,
            "hostingBounds": NSStringFromRect(hosting.bounds), "windowMinimum": NSStringFromSize(window.contentMinSize)])
        try saveImage(hosting, to: output.appendingPathComponent("assistant-top.png"))
        XCTAssertEqual(window.contentMinSize, NSSize(width: 880, height: 640),
            "The native window must retain its minimum constraint.")
        XCTAssertEqual(window.contentLayoutRect.width, 880, accuracy: 1)
        XCTAssertEqual(window.contentLayoutRect.height, 640, accuracy: 1)
        let viewport = window.convertToScreen(window.contentLayoutRect)
        let ids = ["assistant.prompt", "assistant.send", "assistant.route", "assistant.settings", "voice.start"]
        let before = snapshot(hosting)
        samples.append(evidence("top", nodes: before, viewport: viewport))
        var frames: [String: NSRect] = [:]
        for id in ids {
            let frame = try XCTUnwrap(try unique(id, in: before).frame)
            XCTAssertGreaterThan(frame.width, 2)
            XCTAssertGreaterThan(frame.height, 2)
            XCTAssertTrue(viewport.insetBy(dx: -1, dy: -1).contains(frame), id)
            frames[id] = frame
        }
        let scroll = try XCTUnwrap(descendants(hosting).compactMap { $0 as? NSScrollView }
            .filter { $0.contentView.bounds.width > 400 && ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height }
            .max { $0.contentView.bounds.width < $1.contentView.bounds.width })
        let scrollFrame = window.convertToScreen(scroll.contentView.convert(scroll.contentView.bounds, to: nil))
        XCTAssertGreaterThan(scrollFrame.height, 100, "The pinned composer must leave a usable reply viewport.")
        for id in ids {
            let overlap = scrollFrame.intersection(try XCTUnwrap(frames[id]))
            XCTAssertTrue(overlap.isNull || overlap.width <= 1 || overlap.height <= 1, id)
        }
        scroll.contentView.scroll(to: NSPoint(x: 0,
            y: max(0, (scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.height)))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await settle(hosting, window: window)
        let after = snapshot(hosting)
        samples.append(evidence("bottom", nodes: after, viewport: viewport))
        for id in ids {
            XCTAssertEqual(try unique(id, in: after).frame, frames[id], "\(id) must remain pinned while replies scroll.")
        }
        try saveImage(hosting, to: output.appendingPathComponent("assistant-bottom.png"))
        XCTAssertEqual(store.prompt, draft)
        XCTAssertEqual(store.sharedText, source)
        XCTAssertNil(host.webView)
        XCTAssertEqual(client.calls, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: preferenceURL.path))
        await store.shutdownAssistant()
    }

    /// The real coordinator produces a mixed receipt: one selector reports input
    /// tokens, then the answer transport fails without returning any telemetry.
    @MainActor
    func testAssistantEvidenceExpansionKeepsUnknownCountsHonestAndComposerPinned() async throws {
        let output = try nativeOutput("assistant-evidence")
        let profile = output.appendingPathComponent("disposable-preferences.json")
        let saved = try NativePreferenceDocument().encoded()
        try saved.write(to: profile)
        let reasoner = EvidenceLayoutRoleClient(fails: true)
        let selector = EvidenceLayoutRoleClient(fails: false)
        let assistant = HamptonReasonsAssistant(reasoner: reasoner, contextSelector: selector)
        let store = CompanionStore(preferenceURL: profile, assistant: assistant,
            assistantFactory: { _, _ in assistant }, allowsPlay: false)
        defer { store.disconnectAssistant(provider: .qwen) }
        store.share(text: "The synthetic release is Friday. The venue opens at noon.", name: "receipt-fixture.txt")
        store.setSessionContextEnabled(true)
        store.prompt = "Explain the synthetic release."
        store.connectAssistant()
        try await waitForNativeFixture { store.connectionState == .ready }
        store.submit()
        try await waitForNativeFixture { !store.isWorking }
        let receipt = try XCTUnwrap(store.compareResults[.qwen]?.receipt)
        XCTAssertEqual(receipt.state, .failed)
        XCTAssertEqual(receipt.localInvocationReceipts?.map(\.outcome), [.completed, .failed])
        XCTAssertEqual(receipt.localInvocationReceipts?.first?.metrics?.inputTokens, 44)
        XCTAssertNil(receipt.localInvocationReceipts?.last?.metrics)
        store.prompt = "This unsent draft stays reachable."
        store.section = .assistant
        let draft = store.prompt, source = store.sharedText
        let app = NSApplication.shared, previousPolicy = app.activationPolicy()
        _ = app.setActivationPolicy(.accessory); app.finishLaunching()
        defer { _ = app.setActivationPolicy(previousPolicy) }
        let host = HostedPlayHost(profile: .acceptance, assetDirectory: nil)
        let window = WorkspaceWindow(contentRect: NSRect(x: 80, y: 80, width: 880, height: 640),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "ARCHi · Disposable receipt layout acceptance"
        let hosting = WorkspaceView.makeHostingView(store: store, playHost: host)
        window.contentView = hosting; window.makeKeyAndOrderFront(nil); app.activate()
        defer { window.contentView = nil; window.close() }
        try await settle(hosting, window: window)
        WorkspaceView.applyWindowMinimum(to: window)
        window.setContentSize(NSSize(width: 880, height: 640))
        try await settle(hosting, window: window)
        try await NativeAccessibilityFixture.initialize(waitingFor: "assistant.prompt") {
            self.snapshot(hosting).contains { $0.id == "assistant.prompt" }
        }
        XCTAssertEqual(window.contentLayoutRect.width, 880, accuracy: 1)
        XCTAssertEqual(window.contentLayoutRect.height, 640, accuracy: 1)
        let viewport = window.convertToScreen(window.contentLayoutRect)
        var samples: [[String: Any]] = []
        defer { writeNativeSamples(samples, to: output) }
        let before = snapshot(hosting)
        samples.append(evidence("collapsed", nodes: before, viewport: viewport))
        let composerIDs = ["assistant.prompt", "assistant.send", "assistant.route", "assistant.settings", "voice.start"]
        var composerFrames: [String: NSRect] = [:]
        for id in composerIDs {
            let frame = try visibleFrame(id, in: before, viewport: viewport)
            composerFrames[id] = frame
        }
        try press(try unique("assistant-evidence-cost", in: before))
        try await settle(hosting, window: window)
        let expanded = snapshot(hosting)
        samples.append(evidence("expanded", nodes: expanded, viewport: viewport))
        // SwiftUI applies the enclosing disclosure's identifier to its expanded
        // descendants. Check each actual native text value uniquely; do not
        // invent the child identifier which the runtime does not expose.
        let metricLabels = ["Input tokens · 44 known · 1/2 calls reported", "Output tokens · Unavailable"]
        for label in metricLabels { _ = try uniqueLabel(label, in: expanded) }
        let failedCall = try uniquePressableLabel("Call 2 · Answer · Failed", in: expanded)
        try press(failedCall)
        try await settle(hosting, window: window)
        let detailed = snapshot(hosting)
        samples.append(evidence("failed-call-expanded", nodes: detailed, viewport: viewport))
        _ = try uniqueLabel("Model not reported · input unavailable tokens · output unavailable tokens", in: detailed)
        _ = try uniqueLabel("Model total · Unavailable", in: detailed)
        let scroll = try XCTUnwrap(descendants(hosting).compactMap { $0 as? NSScrollView }
            .filter { $0.contentView.bounds.width > 400 && ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height }
            .max { $0.contentView.bounds.width < $1.contentView.bounds.width })
        let document = try XCTUnwrap(scroll.documentView)
        let maximumY = max(0, document.bounds.height - scroll.contentView.bounds.height)
        XCTAssertGreaterThan(maximumY, 0, "Expanded production receipts must exercise the real reply scroll surface.")
        var reached = Set<String>()
        for (index, position) in [CGFloat(0), maximumY / 2, maximumY].enumerated() {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: position))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await settle(hosting, window: window)
            let nodes = snapshot(hosting)
            let replyViewport = window.convertToScreen(scroll.contentView.convert(scroll.contentView.bounds, to: nil))
            samples.append(evidence("expanded-scroll-\(index)", nodes: nodes, viewport: replyViewport))
            for label in metricLabels {
                let frame = try XCTUnwrap(try uniqueLabel(label, in: nodes).frame)
                XCTAssertGreaterThan(frame.width, 2); XCTAssertGreaterThan(frame.height, 2)
                if replyViewport.insetBy(dx: -1, dy: -1).contains(frame) {
                    reached.insert(label)
                }
            }
            for id in composerIDs {
                let frame = try visibleFrame(id, in: nodes, viewport: viewport)
                XCTAssertEqual(frame, composerFrames[id], "\(id) must stay pinned while receipt details expand and scroll.")
                let overlap = replyViewport.intersection(frame)
                XCTAssertTrue(overlap.isNull || overlap.width <= 1 || overlap.height <= 1, id)
            }
            try saveImage(hosting, to: output.appendingPathComponent("expanded-scroll-\(index).png"))
        }
        XCTAssertEqual(reached, Set(metricLabels))
        XCTAssertEqual(store.prompt, draft); XCTAssertEqual(store.sharedText, source)
        XCTAssertEqual(store.compareResults[.qwen]?.receipt, receipt)
        XCTAssertEqual(selector.calls, 1); XCTAssertEqual(reasoner.calls, 1)
        XCTAssertNil(host.webView)
        XCTAssertEqual(try Data(contentsOf: profile), saved)
        await store.shutdownAssistant()
    }

    /// This covers production controls' initial/blocked projections only. File
    /// panels, restore preview and Cancel preview remain separate UI acceptance.
    @MainActor
    func testRecoveryControlsExposeSavedBackupAndBlockRestoreForVisitChanges() async throws {
        let output = try nativeOutput("recovery-controls")
        let profile = output.appendingPathComponent("disposable-preferences.json")
        let saved = try NativePreferenceDocument().encoded()
        try saved.write(to: profile)
        let client = LayoutAssistant()
        let store = CompanionStore(preferenceURL: profile, assistant: client,
            assistantFactory: { _, _ in client }, allowsPlay: false)
        store.prompt = "Recovery must preserve this unsent draft."
        let app = NSApplication.shared, previousPolicy = app.activationPolicy()
        _ = app.setActivationPolicy(.accessory); app.finishLaunching()
        defer { _ = app.setActivationPolicy(previousPolicy) }
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 560, height: 360),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "ARCHi · Disposable recovery control acceptance"
        let hosting = NSHostingView(rootView: DesktopRecoveryControls(store: store).padding(20))
        window.contentView = hosting; window.makeKeyAndOrderFront(nil); app.activate()
        defer { window.contentView = nil; window.close() }
        var samples: [[String: Any]] = []
        defer { writeNativeSamples(samples, to: output) }
        let viewport = window.convertToScreen(window.contentLayoutRect)
        try await settle(hosting, window: window)
        try await NativeAccessibilityFixture.initialize(waitingFor: "desktop-recovery.backup") {
            self.snapshot(hosting).contains { $0.id == "desktop-recovery.backup" }
        }
        let initial = snapshot(hosting)
        samples.append(evidence("saved-profile", nodes: initial, viewport: viewport))
        for id in ["desktop-recovery.backup", "desktop-recovery.choose"] {
            _ = try visibleFrame(id, in: initial, viewport: viewport)
            XCTAssertEqual(try unique(id, in: initial).enabled, true, id)
        }
        XCTAssertFalse(initial.contains { $0.id == "desktop-recovery.preview" })
        XCTAssertFalse(initial.contains { $0.id == "desktop-recovery.cancel-preview" })
        try saveImage(hosting, to: output.appendingPathComponent("saved-profile.png"))
        store.preferences.tone = "Warm"
        try await settle(hosting, window: window)
        let blocked = snapshot(hosting)
        samples.append(evidence("unsaved-visit", nodes: blocked, viewport: viewport))
        XCTAssertEqual(try unique("desktop-recovery.backup", in: blocked).enabled, true,
            "Saved-only backup remains available without silently saving this visit.")
        XCTAssertEqual(try unique("desktop-recovery.choose", in: blocked).enabled, false)
        _ = try visibleFrame("desktop-recovery.blocked", in: blocked, viewport: viewport)
        XCTAssertEqual(try unique("desktop-recovery.blocked", in: blocked).label,
            "Save your changed appearance and rhythm settings before restoring.")
        try saveImage(hosting, to: output.appendingPathComponent("unsaved-visit.png"))
        XCTAssertEqual(try Data(contentsOf: profile), saved)
        XCTAssertEqual(store.prompt, "Recovery must preserve this unsent draft.")
        XCTAssertEqual(client.calls, 0)
        await store.shutdownAssistant()
    }

    private struct Node {
        let object: ObjectIdentifier
        let nativeObject: NSObject
        let id: String?
        let role: String?
        let hasPressImplementation: Bool
        let label: String?
        let labelSource: String
        let enabled: Bool?
        let enabledSource: String
        let frame: NSRect?
        let frameSource: String
        let typeName: String
        let modernChildCount: Int?
        let legacyChildCount: Int?
        let nativeSubviewCount: Int?
    }

    @MainActor private func snapshot(_ root: NSObject) -> [Node] {
        var seen = Set<ObjectIdentifier>(), nodes: [Node] = []
        func visit(_ element: NSObject, depth: Int) {
            guard depth < 40, seen.insert(ObjectIdentifier(element)).inserted else { return }
            func value(_ selectorName: String) -> Any? {
                let selector = NSSelectorFromString(selectorName)
                return element.responds(to: selector) ? element.perform(selector)?.takeUnretainedValue() : nil
            }
            let attributes = element.accessibilityAttributeNames()
            let id = value("accessibilityIdentifier") as? String
                ?? (attributes.contains(.identifier) ? element.accessibilityAttributeValue(.identifier) as? String : nil)
            // Native static text exposes its content as AXValue. Buttons and
            // disclosure proxies commonly expose AXLabel or AXTitle instead.
            let texts: [(String, String?)] = [
                ("accessibilityLabel", value("accessibilityLabel") as? String),
                ("accessibilityTitle", value("accessibilityTitle") as? String),
                ("accessibilityValue", value("accessibilityValue") as? String),
                ("AXTitle", element.accessibilityAttributeValue(.title) as? String),
                ("AXValue", element.accessibilityAttributeValue(.value) as? String)]
            let nativeText = texts.first { !($0.1?.isEmpty ?? true) }
            let label = nativeText?.1
            // Only the receipt action candidates need a role lookup. Avoid
            // probing hosting containers or enumerating legacy action APIs.
            let role: String? = label?.hasPrefix("Call ") == true
                ? (element as? NSAccessibilityProtocol)?.accessibilityRole()?.rawValue
                    ?? value("accessibilityRole") as? String
                : nil
            var frame = (element as? NSAccessibilityProtocol)?.accessibilityFrame()
            var frameSource = frame == nil ? "unavailable" : "NSAccessibilityProtocol.accessibilityFrame"
            // KVC boxes the native NSRect getter for SwiftUI proxies that
            // implement the selector without declaring protocol conformance.
            if frame == nil, element.responds(to: NSSelectorFromString("accessibilityFrame")),
               let nativeFrame = element.value(forKey: "accessibilityFrame") as? NSValue {
                frame = nativeFrame.rectValue
                frameSource = "native accessibilityFrame getter"
            }
            // SwiftUI's native AX proxy can provide the legacy NSObject
            // attributes without declaring the modern protocol. These are
            // native screen-coordinate values, not reconstructed view frames.
            if frame == nil,
               let position = element.accessibilityAttributeValue(.position) as? NSValue,
               let size = element.accessibilityAttributeValue(.size) as? NSValue {
                frame = NSRect(origin: position.pointValue, size: size.sizeValue)
                frameSource = "native AXPosition and AXSize"
            }
            let modernChildren = value("accessibilityChildren") as? [Any]
            let legacyChildren = attributes.contains(.children) ? element.accessibilityAttributeValue(.children) as? [Any] : nil
            let enabled: Bool?
            let enabledSource: String
            if let accessible = element as? NSAccessibilityProtocol {
                enabled = accessible.isAccessibilityEnabled()
                enabledSource = "NSAccessibilityProtocol.isAccessibilityEnabled"
            } else if element.responds(to: NSSelectorFromString("isAccessibilityEnabled")) {
                // BOOL getters must use their actual ABI, never NSObject.perform
                // which treats the return value as an object pointer.
                let selector = NSSelectorFromString("isAccessibilityEnabled")
                let getter = unsafeBitCast(element.method(for: selector),
                    to: (@convention(c) (AnyObject, Selector) -> Bool).self)
                enabled = getter(element, selector)
                enabledSource = "native isAccessibilityEnabled getter"
            } else {
                enabled = element.accessibilityAttributeValue(.enabled) as? Bool
                enabledSource = enabled == nil ? "unavailable" : "AXEnabled"
            }
            nodes.append(Node(object: ObjectIdentifier(element), nativeObject: element, id: id,
                role: role,
                hasPressImplementation: element.responds(to: NSSelectorFromString("accessibilityPerformPress")), label: label,
                labelSource: nativeText?.0 ?? "unavailable", enabled: enabled, enabledSource: enabledSource,
                frame: frame, frameSource: frameSource,
                typeName: String(describing: type(of: element)), modernChildCount: modernChildren?.count,
                legacyChildCount: legacyChildren?.count, nativeSubviewCount: (element as? NSView)?.subviews.count))
            // Native hosts can return [] from the modern getter while the
            // legacy API still exposes real children. Visit both and retain
            // object-identity deduplication instead of discarding that branch.
            let children = (modernChildren ?? []) + (legacyChildren ?? [])
            for child in children { if let object = child as? NSObject { visit(object, depth: depth + 1) } }
            // Like the native Arena readback fixture, traverse the actual AppKit
            // content when an ignored hosting container has cached no AX children.
            // Identifiers and frames still come only from native accessibility;
            // view hierarchy traversal does not manufacture acceptance geometry.
            if let window = element as? NSWindow, let content = window.contentView { visit(content, depth: depth + 1) }
            if let view = element as? NSView {
                for child in view.subviews { visit(child, depth: depth + 1) }
            }
        }
        visit(root, depth: 0)
        return nodes
    }

    private func unique(_ id: String, in nodes: [Node]) throws -> Node {
        let values = nodes.filter { $0.id == id }
        XCTAssertEqual(values.count, 1, "\(id) needs its own single native accessibility child; observed \(values.count).")
        return try XCTUnwrap(values.first, "Native control is not independently accessible: \(id)")
    }

    private func uniqueLabel(_ label: String, in nodes: [Node]) throws -> Node {
        let values = nodes.filter { $0.label == label }
        XCTAssertEqual(values.count, 1, "Expected one independently readable native text value: \(label)")
        return try XCTUnwrap(values.first, "Native text is not independently accessible: \(label)")
    }

    private func uniquePressableLabel(_ label: String, in nodes: [Node]) throws -> Node {
        // A disclosure and its backing static label can expose the same text.
        // Select the actual native control/action, while uniqueLabel remains
        // strict for independently readable receipt values.
        let values = nodes.filter { node in
            node.label == label && node.hasPressImplementation &&
                node.role == NSAccessibility.Role.disclosureTriangle.rawValue
        }
        XCTAssertEqual(values.count, 1, "Expected one native disclosure/Press control: \(label)")
        return try XCTUnwrap(values.first, "Native disclosure action is unavailable: \(label)")
    }

    private func evidence(_ stage: String, nodes: [Node], viewport: NSRect) -> [String: Any] {
        let root = nodes.first
        let viewCount = nodes.filter { $0.nativeSubviewCount != nil }.count
        let accessibleViewCount = nodes.filter {
            $0.nativeSubviewCount != nil && (($0.modernChildCount ?? 0) > 0 || ($0.legacyChildCount ?? 0) > 0)
        }.count
        let traversal: [String: String] = ["rootType": root?.typeName ?? "unavailable",
            "rootModernAXChildren": root?.modernChildCount.map { String($0) } ?? "unavailable",
            "rootLegacyAXChildren": root?.legacyChildCount.map { String($0) } ?? "unavailable",
            "rootNativeSubviews": root?.nativeSubviewCount.map { String($0) } ?? "unavailable",
            "appKitViewsVisited": String(viewCount), "appKitViewsWithAXChildren": String(accessibleViewCount)]
        let identifiedNodes: [[String: Any]] = nodes.compactMap { node -> [String: Any]? in
            guard let id = node.id else { return nil }
            return ["id": id, "role": node.role ?? "unavailable",
                "hasPressImplementation": node.hasPressImplementation,
                "label": node.label ?? "", "frameScreen": node.frame.map(NSStringFromRect) ?? "unavailable",
                "frameSource": node.frameSource, "labelSource": node.labelSource,
                "enabled": node.enabled.map(String.init) ?? "unavailable", "enabledSource": node.enabledSource]
        }
        let callControls: [[String: Any]] = nodes.filter { $0.label?.hasPrefix("Call ") == true }.map { node in
            ["id": node.id ?? "unavailable", "role": node.role ?? "unavailable",
             "hasPressImplementation": node.hasPressImplementation, "label": node.label ?? "",
             "labelSource": node.labelSource, "type": node.typeName]
        }
        return ["stage": stage, "viewportScreen": NSStringFromRect(viewport),
            "accessibilityNodeCount": nodes.count, "identifiedControlCount": identifiedNodes.count,
            "traversal": traversal, "nodes": identifiedNodes, "callControlNodes": callControls]
    }

    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    private func nativeOutput(_ name: String) throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_GESTURE_LAYOUT_DIR"] else {
            throw XCTSkip("Set ARCHI_GESTURE_LAYOUT_DIR for opt-in native production UI acceptance.")
        }
        let output = URL(fileURLWithPath: path).appendingPathComponent("\(name)-\(UUID())")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        return output
    }

    private func writeNativeSamples(_ samples: [[String: Any]], to output: URL) {
        try? JSONSerialization.data(withJSONObject: ["schema": "archi-native-control-layout/v1", "samples": samples],
            options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("layout.json"))
        print("Native production control evidence: \(output.path)")
    }

    private func visibleFrame(_ id: String, in nodes: [Node], viewport: NSRect) throws -> NSRect {
        let frame = try XCTUnwrap(try unique(id, in: nodes).frame)
        XCTAssertGreaterThan(frame.width, 2, id); XCTAssertGreaterThan(frame.height, 2, id)
        XCTAssertTrue(viewport.insetBy(dx: -1, dy: -1).contains(frame), "\(id) must fit its native viewport.")
        return frame
    }

    @MainActor private func press(_ node: Node) throws {
        if let control = node.nativeObject as? NSAccessibilityProtocol {
            XCTAssertTrue(control.accessibilityPerformPress())
        } else {
            let selector = NSSelectorFromString("accessibilityPerformPress")
            guard node.nativeObject.responds(to: selector) else {
                XCTFail("Native control \(node.id ?? node.label ?? "unknown") does not support Press"); return
            }
            let action = unsafeBitCast(node.nativeObject.method(for: selector),
                to: (@convention(c) (AnyObject, Selector) -> Bool).self)
            XCTAssertTrue(action(node.nativeObject, selector))
        }
    }

    @MainActor private func waitForNativeFixture(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("In-process native layout fixture did not finish within the bounded wait")
        throw AssistantFailure.unavailable
    }

    @MainActor private final class EvidenceLayoutRoleClient: LocalRoleClient {
        let fails: Bool
        var calls = 0
        init(fails: Bool) { self.fails = fails }
        func connect() async throws {}
        func disconnect() {}
        func shutdown() async {}
        func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
            calls += 1
            if fails { throw QwenFailure.unavailable }
            XCTAssertEqual(request.role, .memorySelection)
            let payload: JSONValue = .object(["requestID": .string(request.id),
                "schema": .string("archi-session-selection/v1"), "candidateIDs": .array([])])
            return LocalRoleResult(requestID: request.id, role: request.role,
                text: String(decoding: try JSONEncoder().encode(payload), as: UTF8.self),
                model: QwenModelMetadata(name: "native-layout-fixture", family: "fixture", parameterSize: "fixture",
                    quantization: "fixture", digest: String(repeating: "a", count: 64)),
                elapsedMilliseconds: 12, metrics: LocalInferenceMetrics(inputTokens: 44))
        }
    }

    @MainActor private func settle(_ view: NSView, window: NSWindow) async throws {
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(140))
        view.layoutSubtreeIfNeeded()
    }

    @MainActor private func saveImage(_ view: NSView, to url: URL) throws {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }

    @MainActor private final class LayoutAssistant: AssistantClient {
        var calls = 0
        func connect() async throws { calls += 1; throw AssistantFailure.unavailable }
        func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
            calls += 1; throw AssistantFailure.unavailable
        }
        func disconnect() {}
    }
}
