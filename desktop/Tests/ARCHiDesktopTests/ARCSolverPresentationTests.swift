import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

/// Exercises production SwiftUI buttons through their native accessibility actions.
/// Opt-in because it creates a visible window; all evidence lives in a disposable shelf.
final class ARCSolverPresentationTests: XCTestCase {
    @MainActor
    func testSampleSolveAndRetainedReplayThroughNativeControls() async throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_ARC_SOLVER_LAYOUT_DIR"], !path.isEmpty else {
            throw XCTSkip("Set ARCHI_ARC_SOLVER_LAYOUT_DIR for disposable native ARC solver acceptance.")
        }
        let output = URL(fileURLWithPath: path).appendingPathComponent("arc-solver-\(UUID())")
        let profile = FileManager.default.temporaryDirectory.appendingPathComponent("arc-solver-presentation-\(UUID())")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: profile) }
        let store = ARCCapabilitiesStore(storageURL: profile.appendingPathComponent("evidence.json"))
        var events: [ARCCapabilitiesEvent] = []
        var usageLinks: [String] = []
        var graphLinks: [String] = []
        let app = NSApplication.shared, previousPolicy = app.activationPolicy()
        _ = app.setActivationPolicy(.accessory)
        app.finishLaunching()
        defer { _ = app.setActivationPolicy(previousPolicy) }
        let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 880, height: 640),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "ARCHi · Disposable ARC solver acceptance"
        window.isReleasedWhenClosed = false
        defer { store.stopSolving(); window.contentView = nil; window.close() }
        // Reserve the width occupied by workspace navigation to exercise the
        // panel's compact layout inside an 880 × 640 content viewport.
        let hosting = NSHostingView(rootView: HStack(spacing: 0) {
            Color.clear.frame(width: 230).accessibilityHidden(true)
            ARCCapabilitiesWorkspace(store: store, onEvaluation: { events.append($0) },
                onOpenUsage: { usageLinks.append($0) }, onOpenGraph: { graphLinks.append($0) })
        }.preferredColorScheme(.light))
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        try await settle(hosting, window)
        try await NativeAccessibilityFixture.initialize(waitingFor: "capabilities.solver.sample") {
            self.nodes(window).contains { $0.identifier == "capabilities.solver.sample" }
        }
        for identifier in ["capabilities.solver.import", "capabilities.solver.sample", "capabilities.solver.solve", "capabilities.solver.stop"] {
            _ = try await reachable(identifier, hosting, window)
        }
        XCTAssertNil(store.solverDocument)
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertTrue(events.isEmpty)

        try press(try await reachable("capabilities.solver.sample", hosting, window))
        try await settle(hosting, window)
        XCTAssertEqual(store.solverDocument?.isSynthetic, true)
        XCTAssertFalse(store.isSolving, "Load sample should only load a task.")
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertTrue(events.isEmpty)
        _ = try await reachable("capabilities.solver.source", hosting, window)
        try capture(hosting, at: output.appendingPathComponent("sample-light.png"))
        try press(try await reachable("capabilities.solver.training", hosting, window))
        try await settle(hosting, window)
        let trainingRow = try await reachable("capabilities.solver.grid.training.0.input.row.0", hosting, window)
        let expectedRow = try XCTUnwrap(store.solverDocument?.input.training.first?.input.first)
            .map(String.init).joined(separator: ", ")
        XCTAssertTrue(trainingRow.spokenContent.contains(expectedRow),
                      "The native row must expose its numeric content, independently of cell colors. Read: \(trainingRow.spokenContent)")

        try press(try await reachable("capabilities.solver.solve", hosting, window))
        try await finishRun(store, hosting, window)
        let review = try XCTUnwrap(store.solverReview)
        XCTAssertEqual(review.run.outcome, .predicted, "The built-in sample must produce a proposed prediction.")
        XCTAssertNotNil(review.run.predictions)
        XCTAssertNil(review.error)
        XCTAssertEqual(events.count, 1, "The visible Solve action must report the completed evaluation once.")
        let record = try XCTUnwrap(store.records.first { $0.id == review.evidenceID })
        XCTAssertNotNil(record.solverEvidence)
        XCTAssertTrue(record.summary.allExact, "The sample prediction must pass the independent checker.")
        _ = try await reachable("capabilities.solver.checker", hosting, window)
        try capture(hosting, at: output.appendingPathComponent("checker-light.png"))
        try press(try await reachable("capabilities.solver.open-usage", hosting, window))
        try press(try await reachable("capabilities.solver.open-graph", hosting, window))
        XCTAssertEqual(usageLinks, [review.taskID])
        XCTAssertEqual(graphLinks, [record.id])

        try press(try await reachable("capabilities.page.results", hosting, window))
        try await settle(hosting, window)
        try press(try await reachable("capabilities.solver.replay.\(record.id)", hosting, window))
        try await finishRun(store, hosting, window)
        XCTAssertEqual(store.solverReview?.replayMatched, true)
        XCTAssertEqual(events.count, 2)
        try press(try await reachable("capabilities.solver.open-usage", hosting, window))
        XCTAssertEqual(usageLinks.last, store.solverReview?.taskID)
        XCTAssertNotEqual(usageLinks.last, review.taskID, "Replay must link to its own usage attempt.")
        XCTAssertEqual(store.records.count, 1, "Replaying retained evidence should preserve a single evidence record.")
        _ = try await reachable("capabilities.solver.replay-result", hosting, window)
        try capture(hosting, at: output.appendingPathComponent("replay-light.png"))

        let darkHosting = NSHostingView(rootView: HStack(spacing: 0) {
            Color.clear.frame(width: 230).accessibilityHidden(true)
            ARCCapabilitiesWorkspace(store: store, onEvaluation: { events.append($0) },
                onOpenUsage: { usageLinks.append($0) }, onOpenGraph: { graphLinks.append($0) })
        }.preferredColorScheme(.dark))
        window.contentView = darkHosting
        try await settle(darkHosting, window)
        try press(try await reachable("capabilities.page.solve", darkHosting, window))
        try await settle(darkHosting, window)
        _ = try await reachable("capabilities.solver.sample", darkHosting, window)
        _ = try await reachable("capabilities.solver.solve", darkHosting, window)
        try capture(darkHosting, at: output.appendingPathComponent("solver-dark.png"))
        XCTAssertEqual(window.contentLayoutRect.width, 880, accuracy: 1)
        XCTAssertEqual(window.contentLayoutRect.height, 640, accuracy: 1)
        try JSONSerialization.data(withJSONObject: [
            "schema": "archi-arc-solver-presentation/v1",
            "nativeActions": ["load-sample", "expand-training", "solve-locally", "open-exact-usage", "open-graph", "saved-results", "run-again", "replay-usage"],
            "viewport": "880x640; 230 pixels reserved for navigation",
            "source": "built-in-synthetic-sample",
            "accessibleTrainingRow": trainingRow.spokenContent,
            "outcome": review.run.outcome.rawValue,
            "replayMatched": store.solverReview?.replayMatched == true,
            "boundary": "Disposable native controls and synthetic evidence. No imported task acceptance or benchmark claim."
        ], options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("presentation.json"))
        print("ARC solver native presentation evidence: \(output.path)")
    }

    /// One explicitly enabled local model request through the production button.
    /// This is a workflow smoke check, never a benchmark or accuracy threshold.
    @MainActor
    func testOneLocalQwenProposalThroughNativeControls() async throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_ARC_QWEN_SMOKE_DIR"], !path.isEmpty else {
            throw XCTSkip("Set ARCHI_ARC_QWEN_SMOKE_DIR to make one local Qwen synthetic proposal.")
        }
        let output = URL(fileURLWithPath: path).appendingPathComponent("qwen-proposal-\(UUID())")
        let profile = FileManager.default.temporaryDirectory.appendingPathComponent("arc-qwen-smoke-\(UUID())")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: profile) }
        let store = ARCCapabilitiesStore(storageURL: profile.appendingPathComponent("evidence.json"))
        var events: [ARCCapabilitiesEvent] = []
        let app = NSApplication.shared, policy = app.activationPolicy()
        _ = app.setActivationPolicy(.accessory); app.finishLaunching()
        defer { _ = app.setActivationPolicy(policy) }
        let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 880, height: 640),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "ARCHi · One local Qwen ARC proposal"
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: ARCCapabilitiesWorkspace(store: store,
            onEvaluation: { events.append($0) }).preferredColorScheme(.dark))
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
        defer {
            try? capture(hosting, at: output.appendingPathComponent("qwen-result-dark.png"))
            let review = store.qwenProposalReview
            let counts = store.records.first { $0.id == review?.evidenceID }?.summary.counts
            let result: [String: Any] = [
                "schema": "archi-arc-qwen-native-smoke/v1",
                "status": store.qwenProposalStatus,
                "model": review?.inference.model ?? QwenAssistant.defaultModel,
                "outcome": review?.result.map { String(describing: $0.status) } ?? "unavailable",
                "trainingPassed": review?.result?.trainingPassed ?? 0,
                "trainingCount": review?.result?.trainingCount ?? 0,
                "exactExamples": counts?.exact ?? 0,
                "testExamples": counts?.totalExamples ?? 0,
                "inputTokens": review?.inference.inputTokens.map { $0 as Any } ?? NSNull(),
                "outputTokens": review?.inference.outputTokens.map { $0 as Any } ?? NSNull(),
                "elapsedMilliseconds": review?.elapsedMilliseconds ?? 0,
                "evidenceID": review?.evidenceID ?? "none",
                "terminalEvents": events.filter { !$0.proposalInProgress }.count,
                "boundary": "One actual local model request on a synthetic sample, using production native controls and disposable evidence. No benchmark, paid call, real profile or installed acceptance claim."
            ]
            try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("smoke.json"))
            store.stopQwenProposal(); window.contentView = nil; window.close()
            print("Local Qwen ARC native smoke: \(output.path)")
        }
        try await settle(hosting, window)
        try await NativeAccessibilityFixture.initialize(waitingFor: "capabilities.solver.sample") {
            self.nodes(window).contains { $0.identifier == "capabilities.solver.sample" }
        }
        try press(try await reachable("capabilities.solver.sample", hosting, window))
        try await settle(hosting, window)
        try press(try await reachable("capabilities.qwen.propose", hosting, window))
        let deadline = ContinuousClock.now.advanced(by: .seconds(190))
        while store.isProposing && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(store.isProposing, "The explicit local proposal must finish within the transport deadline.")
        let review = try XCTUnwrap(store.qwenProposalReview)
        XCTAssertNil(review.error)
        XCTAssertNotNil(review.result)
        XCTAssertNotNil(review.evidenceID)
        XCTAssertEqual(events.filter { !$0.proposalInProgress }.count, 1)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertNil(store.records.first?.solverEvidence, "A Qwen proposal must not pretend to be catalog-search evidence.")
        _ = try await reachable("capabilities.qwen.checker", hosting, window)
    }

    private struct Node {
        let object: NSObject
        let identifier: String?
        let frame: NSRect?
        let spokenContent: String
    }

    @MainActor private func nodes(_ root: NSObject) -> [Node] {
        var result: [Node] = [], seen = Set<ObjectIdentifier>()
        func visit(_ object: NSObject, depth: Int) {
            guard depth < 40, result.count < 6000, seen.insert(ObjectIdentifier(object)).inserted else { return }
            func value(_ selectorName: String) -> Any? {
                let selector = NSSelectorFromString(selectorName)
                return object.responds(to: selector) ? object.perform(selector)?.takeUnretainedValue() : nil
            }
            let attributes = object.accessibilityAttributeNames()
            let identifier = value("accessibilityIdentifier") as? String
                ?? (attributes.contains(.identifier) ? object.accessibilityAttributeValue(.identifier) as? String : nil)
            var frame = (object as? NSAccessibilityProtocol)?.accessibilityFrame()
            if frame == nil, object.responds(to: NSSelectorFromString("accessibilityFrame")),
               let boxed = object.value(forKey: "accessibilityFrame") as? NSValue { frame = boxed.rectValue }
            if frame == nil, let position = object.accessibilityAttributeValue(.position) as? NSValue,
               let size = object.accessibilityAttributeValue(.size) as? NSValue {
                frame = NSRect(origin: position.pointValue, size: size.sizeValue)
            }
            func string(_ value: Any?) -> String? {
                if let text = value as? String, !text.isEmpty { return text }
                if let text = value as? NSAttributedString, !text.string.isEmpty { return text.string }
                return nil
            }
            // SwiftUI may publish static text through either the modern
            // protocol or AppKit's attribute interface, sometimes attributed.
            let spokenContent = [
                string(value("accessibilityValue")),
                string(value("accessibilityLabel")),
                attributes.contains(.value) ? string(object.accessibilityAttributeValue(.value)) : nil,
                attributes.contains(.title) ? string(object.accessibilityAttributeValue(.title)) : nil,
                attributes.contains(.description) ? string(object.accessibilityAttributeValue(.description)) : nil
            ].compactMap { $0 }.joined(separator: "\n")
            result.append(Node(object: object, identifier: identifier, frame: frame, spokenContent: spokenContent))
            let modern = value("accessibilityChildren") as? [Any] ?? []
            let legacy = attributes.contains(.children) ? object.accessibilityAttributeValue(.children) as? [Any] ?? [] : []
            for child in modern + legacy { if let child = child as? NSObject { visit(child, depth: depth + 1) } }
            if let window = object as? NSWindow, let content = window.contentView { visit(content, depth: depth + 1) }
            if let view = object as? NSView { for child in view.subviews { visit(child, depth: depth + 1) } }
        }
        visit(root, depth: 0)
        return result
    }

    @MainActor private func reachable(_ identifier: String, _ hosting: NSView, _ window: NSWindow) async throws -> Node {
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let scrolls = descendants(hosting).compactMap { $0 as? NSScrollView }
            .filter { !($0.documentView is NSTextView) && $0.contentView.bounds.width > 350 }
        func visible() -> Node? {
            let viewport = window.convertToScreen(window.contentLayoutRect)
            return nodes(window).first { node in
                guard node.identifier == identifier, let frame = node.frame, frame.width > 2, frame.height > 2,
                      viewport.insetBy(dx: -1, dy: -1).contains(frame) else { return false }
                return scrolls.contains { scroll in
                    let clip = window.convertToScreen(scroll.contentView.convert(scroll.contentView.bounds, to: nil))
                    return clip.insetBy(dx: -1, dy: -1).contains(frame)
                }
            }
        }
        if let node = visible() { return node }
        for scroll in scrolls {
            let maximum = max(0, (scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.height)
            let count = min(40, max(1, Int(ceil(maximum / max(80, scroll.contentView.bounds.height * 0.4)))))
            for index in 0...count {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: maximum * CGFloat(index) / CGFloat(count)))
                scroll.reflectScrolledClipView(scroll.contentView)
                try await settle(hosting, window)
                if let node = visible() { return node }
            }
        }
        return try XCTUnwrap(visible(), "\(identifier) must be fully reachable in the compact native viewport.")
    }

    @MainActor private func press(_ node: Node) throws {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard node.object.responds(to: selector) else { throw NativeFailure.missingAction }
        if let control = node.object as? NSAccessibilityProtocol { XCTAssertTrue(control.accessibilityPerformPress()) }
        else {
            let action = unsafeBitCast(node.object.method(for: selector), to: (@convention(c) (AnyObject, Selector) -> Bool).self)
            XCTAssertTrue(action(node.object, selector))
        }
    }

    @MainActor private func finishRun(_ store: ARCCapabilitiesStore, _ hosting: NSView, _ window: NSWindow) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while store.isSolving && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(30)) }
        XCTAssertFalse(store.isSolving, "The bounded sample run must finish.")
        try await settle(hosting, window)
    }

    @MainActor private func settle(_ hosting: NSView, _ window: NSWindow) async throws {
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        hosting.layoutSubtreeIfNeeded()
    }

    @MainActor private func capture(_ hosting: NSView, at url: URL) throws {
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }

    private enum NativeFailure: Error { case missingAction }
}
