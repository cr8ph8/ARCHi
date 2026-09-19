import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class CompanionGraphPresentationTests: XCTestCase {
    @MainActor
    func testARCNodeOpensTheExactNativeReceiptAtMinimumSize() async throws {
        guard ProcessInfo.processInfo.environment["ARCHI_GRAPH_NATIVE_ACTIONS"] == "1" else {
            throw XCTSkip("Set ARCHI_GRAPH_NATIVE_ACTIONS=1 for native ARC graph navigation.")
        }
        let app = NSApplication.shared, policy = app.activationPolicy()
        _ = app.setActivationPolicy(.accessory)
        app.finishLaunching()
        defer { _ = app.setActivationPolicy(policy) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-arc-graph-native-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = GraphPresentationAssistant()
        let store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"),
            assistant: client, assistantFactory: { _, _ in client }, allowsPlay: false)
        let event = store.arcCapabilities.runSyntheticDemonstration()
        store.recordARCEvaluation(event)
        let record = try XCTUnwrap(store.arcCapabilities.records.first)
        var otherBundle = try XCTUnwrap(JSONSerialization.jsonObject(with: ARCCapabilitiesEvaluator.syntheticBundle) as? [String: Any])
        otherBundle["evaluations"] = []
        store.recordARCEvaluation(store.arcCapabilities.evaluate(data: try JSONSerialization.data(withJSONObject: otherBundle)))
        let graph = store.companionGraphSnapshot()
        let node = try XCTUnwrap(graph.nodes.first { $0.kind == .evaluation && $0.target == .arcEvidence(proposalHash: record.id) })
        let play = HostedPlayHost(profile: .acceptance, assetDirectory: nil)
        store.section = .nodeLab
        let window = WorkspaceWindow(contentRect: CGRect(x: 100, y: 100, width: 880, height: 640),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "ARCHi ARC graph · synthetic native check"
        let host = WorkspaceView.makeHostingView(store: store, playHost: play)
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        try await Task.sleep(for: .milliseconds(250))
        WorkspaceView.applyWindowMinimum(to: window)
        window.setContentSize(CGSize(width: 880, height: 640))
        try await NativeAccessibilityFixture.initialize(waitingFor: "companion-graph.list-toggle") {
            self.objects(window).contains { self.value($0, "accessibilityIdentifier") as? String == "companion-graph.list-toggle" }
        }
        try press("companion-graph.list-toggle", root: window)
        try await Task.sleep(for: .milliseconds(80))
        try press("companion-graph.list-node.\(node.id)", root: window)
        try await Task.sleep(for: .milliseconds(100))
        try capture("arc-node-selected", host: host)
        try press("companion-graph.open-target", root: window)
        try await Task.sleep(for: .milliseconds(160))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(store.section, .capabilities)
        XCTAssertEqual(store.arcCapabilities.selectedRecordID, record.id)
        try await NativeAccessibilityFixture.initialize(waitingFor: "capabilities.selected-record") {
            self.objects(window).contains { self.value($0, "accessibilityIdentifier") as? String == "capabilities.selected-record" }
        }
        XCTAssertLessThanOrEqual(host.bounds.width, 881)
        XCTAssertLessThanOrEqual(host.bounds.height, 641)
        try capture("arc-opened-receipt", host: host)
        XCTAssertEqual(client.calls, 0)
        XCTAssertTrue(store.tokenSteward.observations.isEmpty)
        XCTAssertNil(play.webView)
        await store.shutdownAssistant()
        await play.shutdown()
    }

    @MainActor private func capture(_ name: String, host: NSView) throws {
        guard let directory = ProcessInfo.processInfo.environment["ARCHI_GRAPH_RENDER_DIR"],
              let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to:
            URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
    }

    func testAllLayoutsKeepNodesDistinctFiniteAndInsideTheirCanvas() {
        let graph = Self.fixture()
        for layout in CompanionGraphLayout.allCases {
            let geometry = CompanionGraphGeometry.make(nodes: graph.nodes, edges: graph.edges, layout: layout)
            XCTAssertEqual(geometry.positions.count, graph.nodes.count)
            XCTAssertTrue(geometry.size.width.isFinite && geometry.size.height.isFinite)
            let rectangles = graph.nodes.compactMap { node -> CGRect? in
                guard let point = geometry.positions[node.id] else { return nil }
                return CGRect(x: point.x - CompanionGraphGeometry.nodeSize.width / 2,
                    y: point.y - CompanionGraphGeometry.nodeSize.height / 2,
                    width: CompanionGraphGeometry.nodeSize.width, height: CompanionGraphGeometry.nodeSize.height)
            }
            for (index, rect) in rectangles.enumerated() {
                XCTAssertTrue(CGRect(origin: .zero, size: geometry.size).contains(rect), layout.rawValue)
                for other in rectangles.dropFirst(index + 1) {
                    XCTAssertFalse(rect.intersects(other), "Overlapping nodes in \(layout.rawValue)")
                }
            }
            let repeated = CompanionGraphGeometry.make(nodes: graph.nodes, edges: graph.edges, layout: layout)
            XCTAssertEqual(geometry.positions, repeated.positions)
            for viewport in [CGSize(width: 500, height: 280), CGSize(width: 760, height: 430)] {
                let scale = geometry.fittedScale(in: viewport)
                XCTAssertTrue(scale.isFinite && scale > 0)
                XCTAssertLessThanOrEqual(geometry.size.width * scale, viewport.width)
                XCTAssertLessThanOrEqual(geometry.size.height * scale, viewport.height)
            }
        }
    }

    @MainActor
    func testNativeGraphRendersAtMinimumAndWideSizesInAllLayouts() async throws {
        let graph = Self.fixture()
        for layout in CompanionGraphLayout.allCases {
            for width in [CGFloat(640), 1120] {
                let view = CompanionGraphView(snapshot: graph, onOpen: { _ in XCTFail("Rendering cannot navigate") },
                    initialLayout: layout, initialSelectionID: graph.nodes.first { $0.kind == .request }?.id)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .preferredColorScheme(.light)
                let size = CGSize(width: width, height: 620)
                let (panel, host) = Self.host(view, size: size)
                defer { panel.contentView = nil; panel.close() }
                try await Task.sleep(for: .milliseconds(180))
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.bounds.size, size)
                XCTAssertFalse(panel.isVisible)
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                XCTAssertGreaterThan(png.count, 8_000)
                if let directory = ProcessInfo.processInfo.environment["ARCHI_GRAPH_RENDER_DIR"] {
                    let url = URL(fileURLWithPath: directory)
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    try png.write(to: url.appendingPathComponent("\(layout.rawValue.lowercased())-\(Int(width)).png"))
                }
            }
        }
    }

    @MainActor
    func testNodeLabFitsTheExistingMinimumWindowAndOpensAssistantWithoutInference() async throws {
        guard ProcessInfo.processInfo.environment["ARCHI_GRAPH_NATIVE_ACTIONS"] == "1" else {
            throw XCTSkip("Set ARCHI_GRAPH_NATIVE_ACTIONS=1 for native workspace navigation.")
        }
        let app = NSApplication.shared, policy = app.activationPolicy()
        _ = app.setActivationPolicy(.accessory)
        app.finishLaunching()
        defer { _ = app.setActivationPolicy(policy) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-graph-window-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = GraphPresentationAssistant()
        let store = CompanionStore(preferenceURL: directory.appendingPathComponent("unused.json"),
                                   assistant: client, allowsPlay: false)
        store.share(text: "Synthetic workshop notes. Review the plan on Friday.", name: "Workshop notes.txt")
        store.section = .nodeLab
        let play = HostedPlayHost(profile: .acceptance, assetDirectory: nil)
        let window = WorkspaceWindow(contentRect: CGRect(x: 100, y: 100, width: 1120, height: 780),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "ARCHi Node Lab · synthetic workspace check"
        let host = WorkspaceView.makeHostingView(store: store, playHost: play)
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        try await Task.sleep(for: .milliseconds(200))
        WorkspaceView.applyWindowMinimum(to: window)
        window.setContentSize(CGSize(width: 880, height: 640))
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        try await NativeAccessibilityFixture.initialize(waitingFor: "node-lab.ask") {
            self.objects(window).contains { self.value($0, "accessibilityIdentifier") as? String == "node-lab.ask" }
        }
        XCTAssertEqual(window.contentMinSize, CGSize(width: 880, height: 640))
        XCTAssertLessThanOrEqual(host.bounds.width, 881)
        XCTAssertLessThanOrEqual(host.bounds.height, 641)
        if let directory = ProcessInfo.processInfo.environment["ARCHI_GRAPH_RENDER_DIR"],
           let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to:
                URL(fileURLWithPath: directory).appendingPathComponent("workspace-880.png"))
        }
        try press("node-lab.ask", root: window)
        XCTAssertEqual(store.section, .assistant)
        XCTAssertEqual(client.calls, 0)
        XCTAssertNil(play.webView)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        await store.shutdownAssistant()
        await play.shutdown()
    }

    @MainActor
    func testNativeButtonsOpenExistingOwnerAndRemovedSelectionCannotRetainText() async throws {
        guard ProcessInfo.processInfo.environment["ARCHI_GRAPH_NATIVE_ACTIONS"] == "1" else {
            throw XCTSkip("Set ARCHI_GRAPH_NATIVE_ACTIONS=1 to exercise native graph accessibility controls.")
        }
        let app = NSApplication.shared
        let priorPolicy = app.activationPolicy()
        _ = app.setActivationPolicy(.accessory)
        app.finishLaunching()
        defer { _ = app.setActivationPolicy(priorPolicy) }
        let graph = Self.fixture()
        let lesson = try XCTUnwrap(graph.nodes.first { $0.kind == .lesson && $0.title == "Planning" })
        var opened: CompanionGraphTarget?
        let view = CompanionGraphView(snapshot: graph, onOpen: { opened = $0 }, initialSelectionID: lesson.id)
        let (panel, host) = Self.host(view, size: CGSize(width: 1120, height: 780))
        defer { panel.contentView = nil; panel.close() }
        panel.styleMask = [.titled, .closable, .resizable]
        panel.title = "ARCHi Node Lab · synthetic native check"
        panel.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        try await Task.sleep(for: .milliseconds(350))
        host.layoutSubtreeIfNeeded()
        try await NativeAccessibilityFixture.initialize(waitingFor: "companion-graph.open-target") {
            self.objects(panel).contains { self.value($0, "accessibilityIdentifier") as? String == "companion-graph.open-target" }
        }
        if let directory = ProcessInfo.processInfo.environment["ARCHI_GRAPH_RENDER_DIR"],
           let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to:
                URL(fileURLWithPath: directory).appendingPathComponent("native-selected-lesson.png"))
        }
        try press("companion-graph.open-target", root: panel)
        XCTAssertEqual(opened, .memory)
        try press("companion-graph.list-toggle", root: panel)
        try await Task.sleep(for: .milliseconds(80))
        let source = try XCTUnwrap(graph.nodes.first { $0.kind == .source })
        try press("companion-graph.list-node.\(source.id)", root: panel)
        try await Task.sleep(for: .milliseconds(80))
        try press("companion-graph.open-target", root: panel)
        XCTAssertEqual(opened, .context)

        host.rootView = CompanionGraphView(snapshot: .empty, onOpen: { opened = $0 })
        try await Task.sleep(for: .milliseconds(80))
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(objects(panel).contains { value($0, "accessibilityIdentifier") as? String == "companion-graph.open-target" })
        XCTAssertFalse(objects(panel).contains { node in
            ["accessibilityLabel", "accessibilityValue", "accessibilityTitle"].contains {
                (value(node, $0) as? String)?.contains("Use the three-step outline.") == true
            }
        })
    }

    @MainActor
    private static func host<V: View>(_ view: V, size: CGSize) -> (NSPanel, NSHostingView<V>) {
        let panel = NSPanel(contentRect: CGRect(origin: CGPoint(x: 100, y: 100), size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        panel.contentView = hosting
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        return (panel, hosting)
    }

    @MainActor private func value(_ object: NSObject, _ name: String) -> Any? {
        let selector = NSSelectorFromString(name)
        if object.responds(to: selector), let value = object.perform(selector)?.takeUnretainedValue() { return value }
        let attribute: NSAccessibility.Attribute? = switch name {
        case "accessibilityIdentifier": .identifier
        case "accessibilityLabel": .description
        case "accessibilityTitle": .title
        case "accessibilityValue": .value
        case "accessibilityRole": .role
        default: nil
        }
        if let attribute, object.accessibilityAttributeNames().contains(attribute) {
            return object.accessibilityAttributeValue(attribute)
        }
        return nil
    }
    @MainActor private func objects(_ root: NSObject) -> [NSObject] {
        var result: [NSObject] = [], seen = Set<ObjectIdentifier>()
        func visit(_ node: NSObject, _ depth: Int) {
            guard depth < 40, result.count < 2400, seen.insert(ObjectIdentifier(node)).inserted else { return }
            result.append(node)
            for child in value(node, "accessibilityChildren") as? [NSObject] ?? [] { visit(child, depth + 1) }
            if node.accessibilityAttributeNames().contains(.children) {
                for child in node.accessibilityAttributeValue(.children) as? [NSObject] ?? [] { visit(child, depth + 1) }
            }
            if let window = node as? NSWindow, let content = window.contentView { visit(content, depth + 1) }
            if let view = node as? NSView { for child in view.subviews { visit(child, depth + 1) } }
        }
        visit(root, 0); return result
    }
    @MainActor private func press(_ identifier: String, root: NSObject) throws {
        let children = objects(root)
        if !children.contains(where: { value($0, "accessibilityIdentifier") as? String == identifier }),
           let directory = ProcessInfo.processInfo.environment["ARCHI_GRAPH_RENDER_DIR"] {
            let dump = children.map { "\(type(of: $0)): id=\(value($0, "accessibilityIdentifier") ?? "nil") label=\(value($0, "accessibilityLabel") ?? "nil") role=\(value($0, "accessibilityRole") ?? "nil")" }.joined(separator: "\n")
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try dump.write(to: URL(fileURLWithPath: directory).appendingPathComponent("native-missing-control.txt"), atomically: true, encoding: .utf8)
        }
        let node = try XCTUnwrap(children.first { value($0, "accessibilityIdentifier") as? String == identifier },
            "Missing native graph control: \(identifier)")
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard node.responds(to: selector) else { XCTFail("Control has no native Press action"); return }
        let action = unsafeBitCast(node.method(for: selector), to: (@convention(c) (AnyObject, Selector) -> Bool).self)
        XCTAssertTrue(action(node, selector))
    }

    private static func fixture() -> CompanionGraphSnapshot {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let digest = String(repeating: "a", count: 64)
        let lesson = KeptLesson(topic: "Planning", text: "Use the three-step outline.", createdAt: now)
        var receipt = AssistantLaneReceipt(requestID: "00000000-0000-0000-0000-000000000001", route: .local,
            provider: .qwen, context: .init(generation: 1, placement: 0, source: 1, selection: 0), inputDigest: digest,
            sourceDigest: LessonSource.digest(of: "The workshop is Friday."), inputContract: "native-assistant-input/v2",
            deadline: now.addingTimeInterval(180), modelIdentity: "Synthetic Qwen fixture", state: .complete,
            settings: .init(tone: "Calm", replyLength: 0.4), requestStarted: true)
        receipt.localLessons = [LessonSnapshot(lesson: lesson)]
        receipt.localInvocations = [.memorySelection, .memoryReminder, .reasoning]
        receipt.localInvocationReceipts = receipt.localInvocations!.enumerated().map { index, role in
            HamptonInvocationReceipt(id: "fixture-call-\(index)", role: role, inputDigest: digest,
                systemDigest: digest, schemaDigest: digest, outcome: .completed, elapsedMilliseconds: 100)
        }
        var evidence = AssistantEvidenceReceipt(contextEnabled: true)
        evidence.sourceIDsAvailable = ["current-question", "shared-copy"]
        evidence.reasoningSourceIDsOffered = evidence.sourceIDsAvailable
        evidence.reasoningSourceIDsDispatched = evidence.sourceIDsAvailable
        evidence.sourceIDsCited = ["shared-copy"]
        evidence.lessonIDsAvailable = [LessonSnapshot(lesson: lesson).modelID]
        evidence.reasoningMemoryIDsOffered = evidence.lessonIDsAvailable
        evidence.reasoningMemoryIDsDispatched = evidence.lessonIDsAvailable
        evidence.memoryIDsCited = evidence.lessonIDsAvailable
        evidence.candidates = .init(eligibleIDs: ["candidate-1", "candidate-2"], offeredIDs: ["candidate-1"], dispatchedIDs: ["candidate-1"], selectedIDs: ["candidate-1"])
        evidence.omissions = [.init(kind: .candidates, reason: .budget, ids: ["candidate-2"], count: 1)]
        receipt.evidence = evidence
        return CompanionGraph.build(receipts: [receipt], lessons: [lesson],
            source: .init(name: "Workshop notes.txt", text: "The workshop is Friday.", revision: 1), now: now)
    }
}

@MainActor private final class GraphPresentationAssistant: AssistantClient {
    var calls = 0
    func connect() async throws { calls += 1; XCTFail("Graph navigation must not connect a model") }
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; XCTFail("Graph navigation must not request inference")
    }
}
