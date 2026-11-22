import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import ARCHiDesktop

/// Exercises the actual bundled page in WebKit with synthetic inputs. Captures
/// are opt-in output only; every behavior assertion runs without capture paths.
final class SeedDiveRenderingTests: XCTestCase {
    @MainActor
    func testNativeChangesSettleClearAndExposeHonestModes() async throws {
        let app = NSApplication.shared, previousPolicy = app.activationPolicy()
        _ = app.setActivationPolicy(.regular)
        app.finishLaunching()
        defer { _ = app.setActivationPolicy(previousPolicy) }
        let initial = graph(includeRequest: false)
        let changed = graph(includeRequest: true)
        let host = NSHostingView(rootView: SeedDivePage(snapshot: initial,
            telemetry: metadata(graph: initial), still: false, failed: { XCTFail("Seed delivery failed") }))
        let window = makeWindow(size: CGSize(width: 1320, height: 820))
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        show(window)
        try await wait("Native page baseline") {
            guard let web = self.webView(in: host), !web.isHidden else { return false }
            return try await self.boolean(web, "window.seedDive?.inspect().origin === 'native' && !document.hidden")
        }
        let web = try XCTUnwrap(webView(in: host))
        XCTAssertFalse(web.configuration.websiteDataStore.isPersistent)
        _ = await recordDiagnostics(web, label: "native-baseline")
        try await capture(web, name: "native-baseline-wide")
        let baseline = try await inspect(web)
        XCTAssertFalse(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            "Motion qualification requires a genuinely motion-enabled OS; see captured diagnostics")
        XCTAssertEqual(baseline["reducedMotion"] as? Bool, false,
            "WebKit must independently report motion enabled before this test can qualify pulses")
        XCTAssertEqual(baseline["eventCount"] as? Int, 0)
        XCTAssertEqual(baseline["pulseCount"] as? Int, 0)

        host.rootView = SeedDivePage(snapshot: changed, telemetry: metadata(graph: changed, working: true),
            still: false, failed: { XCTFail("Changed Seed delivery failed") })
        try await wait("An actual snapshot change produces an observed pulse", web: web) {
            try await self.boolean(web, "window.seedDive.inspect().pulseCount > 0")
        }
        try await capture(web, name: "native-memory-wide")
        let fewerLinks = CompanionGraphSnapshot(nodes: changed.nodes,
            edges: changed.edges.filter { $0.id != "e4" && $0.id != "e5" }, truncatedCount: 0)
        host.rootView = SeedDivePage(snapshot: fewerLinks, telemetry: metadata(graph: fewerLinks, working: true),
            still: false, failed: { XCTFail("Edge replacement delivery failed") })
        try await wait("Edge withdrawal reaches the current snapshot", web: web) {
            try await self.boolean(web, "document.querySelector('#counts').textContent === '5 records / 3 links'")
        }
        let afterEdgeRemoval = try await inspect(web)
        XCTAssertEqual(afterEdgeRemoval["pulseCount"] as? Int, 0, "Removed connections must clear pulses immediately")
        XCTAssertEqual(afterEdgeRemoval["eventCount"] as? Int, 0, "Removed connections must clear earlier observed events")
        try await wait("Transient animation settles", web: web) {
            try await self.boolean(web, "window.seedDive.inspect().pulseCount === 0 && !window.seedDive.inspect().scheduled")
        }

        try await click("harnessView", in: web)
        let harnessVisible = try await boolean(web,
            "!document.querySelector('#harness').hidden && document.querySelector('#harness').textContent.includes('Qwen')")
        XCTAssertTrue(harnessVisible)
        try await capture(web, name: "native-harness-wide")
        try await click("neuralView", in: web)
        let neuralUnavailable = try await boolean(web,
            "!document.querySelector('#neural').hidden && document.querySelector('#neural').textContent.toLowerCase().includes('not connected')")
        let graphHidden = try await boolean(web, "document.querySelector('#field').hidden")
        XCTAssertTrue(neuralUnavailable)
        XCTAssertTrue(graphHidden)
        try await capture(web, name: "native-neural-unavailable-wide")

        host.rootView = SeedDivePage(snapshot: changed, telemetry: metadata(graph: changed, working: true),
            still: true, failed: { XCTFail("Reduced-motion delivery failed") })
        try await wait("Reduced motion", web: web) {
            try await self.boolean(web, "window.seedDive.inspect().reducedMotion && window.seedDive.inspect().pulseCount === 0")
        }
        try await click("memoryView", in: web)
        window.setContentSize(CGSize(width: 680, height: 620))
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(180))
        let widthFits = try await boolean(web,
            "document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1")
        XCTAssertTrue(widthFits)
        try await capture(web, name: "native-memory-compact")

        host.rootView = SeedDivePage(snapshot: .empty, telemetry: metadata(graph: .empty, generation: 2),
            still: true, failed: { XCTFail("Cleared Seed delivery failed") })
        try await wait("Context replacement removes old content and animation", web: web) {
            try await self.boolean(web, """
                document.querySelector('#counts').textContent === '0 records / 0 links'
                && !document.body.innerText.includes('Synthetic scene frame')
                && window.seedDive.inspect().pulseCount === 0
                && window.seedDive.inspect().eventCount === 0
                """)
        }
    }

    @MainActor
    func testStandaloneReplayPausesAndNativeArrivalPermanentlyFencesIt() async throws {
        let app = NSApplication.shared, previousPolicy = app.activationPolicy()
        _ = app.setActivationPolicy(.regular)
        app.finishLaunching()
        defer { _ = app.setActivationPolicy(previousPolicy) }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: configuration)
        let window = makeWindow(size: CGSize(width: 1320, height: 820))
        window.contentView = web
        defer { web.stopLoading(); window.contentView = nil; window.close() }
        show(window)
        let url = try XCTUnwrap(SeedDivePage.pageURL)
        web.loadHTMLString(try String(contentsOf: url, encoding: .utf8), baseURL: nil)
        try await wait("Standalone page loaded and visible", web: web) {
            try await self.boolean(web, "!!window.seedDive && !document.hidden")
        }
        _ = await recordDiagnostics(web, label: "standalone-baseline")
        try await click("demoStart", in: web)
        try await wait("Explicit synthetic replay", web: web) {
            try await self.boolean(web, "window.seedDive.inspect().origin === 'synthetic' && window.seedDive.inspect().playing")
        }
        if let expected = ProcessInfo.processInfo.environment["SEED_EXPECT_REDUCED_MOTION"] {
            let requestedReduction = expected == "1"
            XCTAssertEqual(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, requestedReduction,
                "The real operating-system preference must match this qualification variant")
            let webReduction = try await boolean(web, "matchMedia('(prefers-reduced-motion: reduce)').matches")
            XCTAssertEqual(webReduction, requestedReduction,
                "WebKit must independently observe the actual OS preference")
        }
        let syntheticLabel = try await boolean(web, "document.querySelector('#mode').textContent.includes('Synthetic')")
        XCTAssertTrue(syntheticLabel)
        try await click("motionToggle", in: web)
        _ = await recordDiagnostics(web, label: "standalone-after-pause-click")
        let paused = try await inspect(web)
        XCTAssertEqual(paused["paused"] as? Bool, true)
        let pausedStep = paused["demoStep"] as? Int
        // Exceeds the 1600 ms demo cadence, so an uncleared timer would advance.
        try await Task.sleep(for: .milliseconds(1_900))
        let stillPaused = try await inspect(web)
        XCTAssertEqual(stillPaused["demoStep"] as? Int, pausedStep)
        XCTAssertEqual(stillPaused["pulseCount"] as? Int, 0)
        try await click("motionToggle", in: web)
        try await wait("Replay resumes", web: web) {
            let state = try await self.inspect(web)
            return (state["demoStep"] as? Int ?? -1) > (pausedStep ?? -1)
        }
        try await capture(web, name: "synthetic-replay-wide")

        // Preserve an actual WebKit frame sequence for design review. It remains
        // visibly labelled synthetic and is never claimed as recorded inference.
        if ProcessInfo.processInfo.environment["SEED_CAPTURE_OUTPUT"] != nil {
            try await click("replay", in: web)
            for frame in 0..<64 {
                try await capture(web, name: String(format: "replay/frame-%03d", frame))
                try await Task.sleep(for: .milliseconds(140))
            }
        }

        let nativeGraph = graph(includeRequest: false)
        var payload = try metadata(graph: nativeGraph).webPayload()
        payload["nodes"] = nativeGraph.nodes.map { node -> [String: Any] in
            ["id": node.id, "kind": node.kind.rawValue, "title": node.title,
             "subtitle": node.subtitle, "status": node.status,
             "details": node.details.map { ["label": $0.label, "value": $0.value] }]
        }
        payload["edges"] = nativeGraph.edges.map { ["source": $0.source, "target": $0.target, "label": $0.label] }
        payload["truncatedCount"] = 0
        _ = try await web.callAsyncJavaScript("window.seedDive.replace(snapshot, false); return true;",
            arguments: ["snapshot": payload], in: nil, contentWorld: .page)
        try await wait("Native arrival locks out synthetic replacement", web: web) {
            try await self.boolean(web, "window.seedDive.inspect().nativeLocked && window.seedDive.inspect().origin === 'native' && !window.seedDive.inspect().playing")
        }
        try await click("replay", in: web)
        try await click("demoStart", in: web)
        try await Task.sleep(for: .milliseconds(1_700))
        let fenced = try await inspect(web)
        let demoControlsHidden = try await boolean(web,
            "document.querySelector('#replay').hidden && document.querySelector('#demoStart').hidden")
        let demoCaptionVisible = try await boolean(web, "!document.querySelector('#demoCaption').hidden")
        XCTAssertEqual(fenced["origin"] as? String, "native")
        XCTAssertTrue(demoControlsHidden)
        XCTAssertFalse(demoCaptionVisible)
    }

    private func graph(includeRequest: Bool) -> CompanionGraphSnapshot {
        var nodes: [CompanionGraphNode] = [
            .init(id: "seed", title: "ARCHi", subtitle: "Synthetic test fixture", kind: .companion,
                status: "Read-only", details: [], target: nil),
            .init(id: "frame", title: "Synthetic scene frame", subtitle: "Shot 07 · draft v3", kind: .source,
                status: "Shared", details: [.init(label: "Scope", value: "Synthetic image reference")], target: nil),
            .init(id: "motion", title: "Motion reference", subtitle: "Pass behind the column", kind: .context,
                status: "Temporary", details: [], target: nil),
            .init(id: "lesson", title: "Preserve screen direction", subtitle: "Previously reviewed fixture", kind: .lesson,
                status: "Kept", details: [], target: nil),
        ]
        var edges = [
            CompanionGraphEdge(id: "e1", source: "seed", target: "frame", label: "shared source"),
            CompanionGraphEdge(id: "e2", source: "seed", target: "lesson", label: "kept lesson"),
            CompanionGraphEdge(id: "e3", source: "frame", target: "motion", label: "temporary reference"),
        ]
        if includeRequest {
            nodes.append(.init(id: "request", title: "Continuity review", subtitle: "Synthetic request fixture",
                kind: .request, status: "pending", details: [], target: nil))
            edges.append(.init(id: "e4", source: "frame", target: "request", label: "request input"))
            edges.append(.init(id: "e5", source: "lesson", target: "request", label: "reviewed context"))
        }
        return .init(nodes: nodes, edges: edges, truncatedCount: 0)
    }

    private func metadata(graph: CompanionGraphSnapshot, working: Bool = false,
                          generation: UInt64 = 1) -> SeedTelemetrySnapshot {
        let context = ContextTicket(generation: generation, placement: 1, source: 1, selection: 1)
        var lanes: [AssistantProvider: AssistantLaneResult] = [:]
        if working {
            var receipt = AssistantLaneReceipt(requestID: "synthetic-request", route: .local, provider: .qwen,
                context: context, inputDigest: "fixture", inputContract: "fixture",
                deadline: Date(timeIntervalSince1970: 1), modelIdentity: "Synthetic recorded model", state: .pending)
            receipt.requestStarted = true
            lanes[.qwen] = .init(text: "", status: "In progress", state: .pending, receipt: receipt)
        }
        return SeedTelemetryProjection.build(context: context, lessonRevision: 1, graph: graph,
            keptLessonCount: graph.nodes.filter { $0.kind == .lesson }.count,
            temporaryRecordCount: graph.nodes.filter { $0.kind == .context }.count,
            isWorking: working, lanes: lanes, peerLab: .init())
    }

    @MainActor
    private func makeWindow(size: CGSize) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 40, y: 40), size: size),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "ARCHi Seed · synthetic WebKit verification"
        window.isReleasedWhenClosed = false
        return window
    }

    @MainActor
    private func show(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        dispatchEvents()
        window.orderFrontRegardless()
        dispatchEvents()
    }

    @MainActor
    private func webView(in view: NSView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        for child in view.subviews { if let web = webView(in: child) { return web } }
        return nil
    }

    @MainActor
    private func boolean(_ web: WKWebView, _ script: String) async throws -> Bool {
        dispatchEvents()
        return try await web.evaluateJavaScript(script) as? Bool == true
    }

    @MainActor
    private func inspect(_ web: WKWebView) async throws -> [String: Any] {
        let result = try await web.evaluateJavaScript("window.seedDive.inspect()")
        return try XCTUnwrap(result as? [String: Any])
    }

    @MainActor
    private func click(_ id: String, in web: WKWebView) async throws {
        _ = try await web.callAsyncJavaScript("document.getElementById(id).click(); return true;",
            arguments: ["id": id], in: nil, contentWorld: .page)
        dispatchEvents()
    }

    @MainActor
    private func wait(_ label: String, web: WKWebView? = nil,
                      condition: @escaping @MainActor () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while true {
            dispatchEvents()
            if (try? await condition()) == true { return }
            guard Date() < deadline else {
                let diagnostics = await recordDiagnostics(web, label: "timeout-" + label)
                throw NSError(domain: "SeedDiveRenderingTests", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: label + " timed out. " + diagnostics])
            }
            try await Task.sleep(for: .milliseconds(40))
        }
    }

    @MainActor
    private func capture(_ web: WKWebView, name: String) async throws {
        guard let path = ProcessInfo.processInfo.environment["SEED_CAPTURE_OUTPUT"] else { return }
        dispatchEvents()
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = true
        let image = try await web.takeSnapshot(configuration: config)
        let data = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 8_000)
        let url = URL(fileURLWithPath: path).appendingPathComponent(name + ".png")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        let metadata: [String: Any] = [
            "schema": "archi-seed-webkit-capture/v1", "name": name,
            "pixelWidth": bitmap.pixelsWide, "pixelHeight": bitmap.pixelsHigh,
            "capturedAtUptimeSeconds": ProcessInfo.processInfo.systemUptime,
            "capturedAtUnixSeconds": Date().timeIntervalSince1970,
            "observation": await diagnostics(web)
        ]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: url.deletingPathExtension().appendingPathExtension("json"))
    }

    /// Read actual operating-system and WebKit state. Never replace matchMedia,
    /// document.hidden, or native accessibility preferences to satisfy a test.
    @MainActor
    private func diagnostics(_ web: WKWebView?) async -> [String: Any] {
        var result: [String: Any] = [
            "systemReduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            "applicationActive": NSApplication.shared.isActive
        ]
        guard let web else { return result }
        result["nativeHidden"] = web.isHidden
        result["nativeHiddenAncestor"] = web.isHiddenOrHasHiddenAncestor
        result["windowVisible"] = web.window?.isVisible ?? false
        result["windowOcclusionVisible"] = web.window?.occlusionState.contains(.visible) ?? false
        result["webWidth"] = Double(web.bounds.width)
        result["webHeight"] = Double(web.bounds.height)
        do {
            result["page"] = try await web.callAsyncJavaScript("""
                return {
                  state: window.seedDive ? window.seedDive.inspect() : null,
                  mediaReduceMotion: matchMedia('(prefers-reduced-motion: reduce)').matches,
                  mediaNoPreference: matchMedia('(prefers-reduced-motion: no-preference)').matches,
                  documentHidden: document.hidden,
                  visibilityState: document.visibilityState,
                  motionControlDisabled: document.getElementById('motionToggle')?.disabled ?? null,
                  motionControlText: document.getElementById('motionToggle')?.textContent ?? null,
                  counts: document.getElementById('counts')?.textContent ?? null,
                  innerWidth, innerHeight, devicePixelRatio,
                  clientWidth: document.documentElement.clientWidth,
                  scrollWidth: document.documentElement.scrollWidth
                };
                """, arguments: [:], in: nil, contentWorld: .page)
        } catch {
            result["pageError"] = error.localizedDescription
        }
        return result
    }

    @MainActor
    private func recordDiagnostics(_ web: WKWebView?, label: String) async -> String {
        let state = await diagnostics(web)
        guard let bytes = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]),
              let json = String(data: bytes, encoding: .utf8) else { return "Diagnostics could not be encoded" }
        print("SEED_DIAGNOSTICS \(label): \(json)")
        if let path = ProcessInfo.processInfo.environment["SEED_CAPTURE_OUTPUT"] {
            let safeName = label.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "-" }
            let url = URL(fileURLWithPath: path).appendingPathComponent("diagnostics-" + String(safeName) + ".json")
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: url)
            } catch { print("SEED_DIAGNOSTICS_WRITE_FAILED \(label): \(error.localizedDescription)") }
        }
        return json
    }

    @MainActor
    private func dispatchEvents() {
        let app = NSApplication.shared
        for _ in 0..<100 {
            guard let event = app.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) else { break }
            app.sendEvent(event)
        }
        app.updateWindows()
    }
}
