import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

/// Opt-in production workspace navigation in a disposable profile. Native AX
/// actions exercise the real callbacks and owners; they do not qualify physical
/// keyboard use, VoiceOver, an installed app, or official ARC performance.
final class ARCWorkspaceRoundTripPresentationTests: XCTestCase {
    @MainActor
    func testExactOlderRunRoundTripThroughProductionWorkspaceAndReopen() async throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_ARC_ROUNDTRIP_DIR"], !path.isEmpty else {
            throw XCTSkip("Set ARCHI_ARC_ROUNDTRIP_DIR for isolated native ARC / Usage / Activity round-trip acceptance.")
        }
        let output = URL(fileURLWithPath: path).appendingPathComponent("arc-roundtrip-\(UUID())")
        let profile = FileManager.default.temporaryDirectory.appendingPathComponent("archi-arc-roundtrip-\(UUID())")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: profile) }
        var preferences = CompanionPreferences()
        preferences.reduceMotion = true
        preferences.quiet = true
        preferences.workspaceAppearance = .light
        let preferenceURL = profile.appendingPathComponent("preferences.json")
        let originalPreferences = try NativePreferenceDocument(preferences: preferences).encoded()
        try originalPreferences.write(to: preferenceURL)
        let client = NoDispatchAssistant()
        let store = CompanionStore(preferenceURL: preferenceURL, assistant: client,
            assistantFactory: { _, _ in client }, allowsPlay: false)
        defer { store.arcCapabilities.stopSolving(); store.disconnectAssistant() }
        let play = HostedPlayHost(profile: .acceptance, assetDirectory: nil)
        let app = NSApplication.shared, previousPolicy = app.activationPolicy()
        _ = app.setActivationPolicy(.accessory)
        app.finishLaunching()
        defer { _ = app.setActivationPolicy(previousPolicy) }
        let size = NSSize(width: 880, height: 640)
        let window = WorkspaceWindow(contentRect: NSRect(origin: NSPoint(x: 40, y: 40), size: size),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "ARCHi · Disposable ARC workspace round trip"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        let hosting = WorkspaceView.makeHostingView(store: store, playHost: play)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        defer { window.contentView = nil; window.close() }
        var actions: [String] = []
        var focusObservations: [[String: Any]] = []
        var targetTaskID: String?
        var targetEvidenceID: String?
        defer {
            if let content = window.contentView { try? capture(content, output.appendingPathComponent("last-state.png")) }
            let evidence: [String: Any] = [
                "schema": "archi-arc-workspace-roundtrip/v1",
                "nativeActions": actions,
                "automaticFocusObservations": focusObservations,
                "targetTaskID": targetTaskID ?? "not-created",
                "targetEvidenceID": targetEvidenceID ?? "not-created",
                "viewport": "880x640 production WorkspaceView including sidebar and header",
                "assistantCalls": client.calls,
                "usageTestScrollOperations": 0,
                "keyboardAndVoiceOver": "Not exercised. Activation uses native accessibility Press actions.",
                "persistenceScope": "Stores recreated against the disposable saved files in the same process; no whole-app relaunch claim.",
                "assertionOutcome": "Use the enclosing XCTest result. These captures are observations, not an independent passing receipt.",
                "boundary": "Synthetic local fixture only. No real profile, model, budget change, file picker, install or benchmark."
            ]
            try? JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("roundtrip.json"))
            print("ARC workspace round-trip native evidence: \(output.path)")
        }
        try await settle(hosting, window)
        WorkspaceView.applyWindowMinimum(to: window)
        window.setContentSize(size)
        try await settle(hosting, window)
        try await NativeAccessibilityFixture.initialize(waitingFor: "home.arc-lab") {
            self.nodes(window).contains { $0.id == "home.arc-lab" }
        }
        XCTAssertEqual(store.section, .home)
        try press(try await reachable("home.arc-lab", store, hosting, window))
        try await settle(hosting, window)
        XCTAssertEqual(store.section, .capabilities)
        actions.append("home-to-arc-lab")
        try press(try await reachable("capabilities.solver.sample", store, hosting, window))
        try await settle(hosting, window)
        XCTAssertFalse(store.arcCapabilities.isSolving)
        XCTAssertTrue(store.arcCapabilities.records.isEmpty)
        XCTAssertTrue(store.tokenSteward.tasks.isEmpty)
        try press(try await reachable("capabilities.solver.solve", store, hosting, window))
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while store.arcCapabilities.isSolving && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTAssertFalse(store.arcCapabilities.isSolving, "The bounded synthetic solve must finish.")
        try await settle(hosting, window)
        let review = try XCTUnwrap(store.arcCapabilities.solverReview)
        XCTAssertNil(review.error)
        let record = try XCTUnwrap(store.arcCapabilities.records.first { $0.id == review.evidenceID })
        let task = try XCTUnwrap(store.tokenSteward.tasks.first { $0.id == review.taskID })
        XCTAssertEqual(record.taskID, task.id)
        XCTAssertTrue(record.summary.allExact)
        XCTAssertTrue(task.checkedSuccessful)
        XCTAssertEqual(review.run.outcome, .predicted)
        targetTaskID = task.id
        targetEvidenceID = record.id
        actions.append("sample-loaded-and-solved-by-native-controls")
        try capture(hosting, output.appendingPathComponent("arc-solved.png"))

        // A different, newer retained receipt prevents reverse navigation from
        // passing by opening the only record. The remaining setup rows are
        // explicitly failed synthetic evaluations, with no invented evidence.
        let other = store.arcCapabilities.runSyntheticDemonstration()
        store.recordARCEvaluation(other)
        XCTAssertNotEqual(other.evidenceID, record.id)
        let newer = Date().addingTimeInterval(1)
        for index in 0..<24 {
            let time = newer.addingTimeInterval(Double(index))
            try store.tokenSteward.recordEvaluation(taskID: UUID().uuidString,
                evidenceID: nil, passed: nil, startedAt: time, finishedAt: time,
                sourceStatus: nil, error: "Synthetic round-trip setup: no evaluation evidence.")
        }
        let originalIndex = try XCTUnwrap(store.tokenSteward.tasks.firstIndex { $0.id == task.id })
        XCTAssertGreaterThanOrEqual(originalIndex, 20)
        XCTAssertFalse(store.tokenSteward.tasks.prefix(20).contains { $0.id == task.id })
        XCTAssertNotEqual(store.arcCapabilities.records.first?.id, record.id)
        XCTAssertEqual(store.arcCapabilities.solverReview?.taskID, task.id)
        let savedFiles = try files(in: profile)
        let revision = store.evolution.revision, history = store.evolution.history
        let lessons = store.keptLessons

        try press(try await reachable("capabilities.solver.open-usage", store, hosting, window))
        let firstFocus = try await automaticUsageFocus(task.id, store, hosting, window)
        focusObservations.append(["phase": "arc-current-run", "originalJournalIndex": originalIndex,
            "rowFrame": firstFocus.row, "reverseButtonFrame": firstFocus.button])
        actions.append("arc-to-exact-older-usage-automatically-visible")
        try capture(hosting, output.appendingPathComponent("usage-older-automatic.png"))
        try press(firstFocus.control)
        try await settle(hosting, window)
        XCTAssertEqual(store.section, .capabilities)
        XCTAssertEqual(store.arcCapabilities.selectedRecordID, record.id)
        _ = try await waitVisible("capabilities.selected-record", hosting, window)
        actions.append("usage-reverse-to-exact-saved-result")
        try capture(hosting, output.appendingPathComponent("arc-reverse-selected.png"))

        try press(try await reachable("capabilities.record.graph.\(record.id)", store, hosting, window))
        try await settle(hosting, window)
        XCTAssertEqual(store.section, .nodeLab)
        let graph = store.companionGraphSnapshot()
        let evidenceNode = try XCTUnwrap(graph.nodes.first { $0.id == store.selectedGraphNodeID })
        XCTAssertEqual(evidenceNode.kind, .evaluation)
        XCTAssertEqual(evidenceNode.target, .arcEvidence(proposalHash: record.id))
        let accountingNode = try XCTUnwrap(graph.nodes.first { $0.target == .stewardTask(taskID: task.id) })
        XCTAssertTrue(graph.edges.contains {
            $0.source == evidenceNode.id && $0.target == accountingNode.id && $0.label == "accounted by"
        })
        let openEvidence = try await reachable("companion-graph.open-target", store, hosting, window)
        XCTAssertTrue(openEvidence.text.contains("ARC"), "The automatically selected inspector must offer its ARC receipt.")
        try capture(hosting, output.appendingPathComponent("activity-exact-evidence.png"))
        actions.append("saved-result-to-exact-activity-evidence")
        try press(try await reachable("companion-graph.list-toggle", store, hosting, window))
        try await settle(hosting, window)
        try press(try await reachable("companion-graph.list-node.\(accountingNode.id)", store, hosting, window))
        try await settle(hosting, window)
        let openAccounting = try await reachable("companion-graph.open-target", store, hosting, window)
        XCTAssertTrue(openAccounting.text.contains("Usage"), "Selected accounting must offer the exact Usage route.")
        try capture(hosting, output.appendingPathComponent("activity-original-accounting.png"))
        try press(openAccounting)
        let graphFocus = try await automaticUsageFocus(task.id, store, hosting, window)
        focusObservations.append(["phase": "activity-accounting", "rowFrame": graphFocus.row,
            "reverseButtonFrame": graphFocus.button])
        actions.append("activity-accounting-to-exact-usage-automatically-visible")
        try capture(hosting, output.appendingPathComponent("usage-from-activity.png"))
        XCTAssertEqual(try files(in: profile), savedFiles, "Navigation must not rewrite retained owner data.")
        XCTAssertEqual(store.preferences, preferences)
        XCTAssertEqual(store.evolution.revision, revision)
        XCTAssertEqual(store.evolution.history, history)
        XCTAssertEqual(store.keptLessons, lessons)
        XCTAssertNil(store.tokenSteward.budget)
        XCTAssertTrue(store.tokenSteward.observations.isEmpty)
        XCTAssertTrue(store.tokenSteward.reservations.isEmpty)
        XCTAssertEqual(store.tokenSteward.summary.usefulTaskCount, 0)
        XCTAssertEqual(client.calls, 0)
        XCTAssertNil(play.webView)
        XCTAssertFalse(store.unityPresentation.isSharing)
        window.contentView = nil
        await store.shutdownAssistant()

        // Recreate the actual stores, then re-enter through visible production
        // controls. No transient selected ID or live solver review is restored.
        let reopened = CompanionStore(preferenceURL: preferenceURL, assistant: client,
            assistantFactory: { _, _ in client }, allowsPlay: false)
        defer { reopened.disconnectAssistant() }
        XCTAssertNil(reopened.selectedStewardTaskID)
        XCTAssertNil(reopened.selectedGraphNodeID)
        XCTAssertNil(reopened.arcCapabilities.selectedRecordID)
        XCTAssertNil(reopened.arcCapabilities.solverReview)
        XCTAssertEqual(reopened.arcCapabilities.records.map(\.id), store.arcCapabilities.records.map(\.id))
        XCTAssertEqual(reopened.tokenSteward.tasks, store.tokenSteward.tasks)
        XCTAssertEqual(try files(in: profile), savedFiles)
        let reopenedHost = WorkspaceView.makeHostingView(store: reopened, playHost: play)
        window.contentView = reopenedHost
        try await settle(reopenedHost, window)
        try press(try await reachable("home.arc-lab", reopened, reopenedHost, window))
        try await settle(reopenedHost, window)
        try press(try await reachable("capabilities.page.results", reopened, reopenedHost, window))
        try await settle(reopenedHost, window)
        try press(try await reachable("capabilities.record.usage.\(record.id)", reopened, reopenedHost, window))
        let reopenedFocus = try await automaticUsageFocus(task.id, reopened, reopenedHost, window)
        focusObservations.append(["phase": "recreated-stores", "rowFrame": reopenedFocus.row,
            "reverseButtonFrame": reopenedFocus.button])
        actions.append("recreated-stores-retain-evidence-and-exact-older-usage-route")
        try capture(reopenedHost, output.appendingPathComponent("usage-reopened-automatic.png"))
        try press(reopenedFocus.control)
        try await settle(reopenedHost, window)
        XCTAssertEqual(reopened.section, .capabilities)
        XCTAssertEqual(reopened.arcCapabilities.selectedRecordID, record.id)
        _ = try await waitVisible("capabilities.selected-record", reopenedHost, window)
        try capture(reopenedHost, output.appendingPathComponent("arc-reopened-reverse.png"))
        actions.append("recreated-stores-reverse-to-original-evidence-without-live-review")
        XCTAssertEqual(try files(in: profile), savedFiles)
        XCTAssertEqual(try Data(contentsOf: preferenceURL), originalPreferences)
        XCTAssertEqual(client.calls, 0)
        XCTAssertNil(reopened.tokenSteward.budget)
        XCTAssertTrue(reopened.tokenSteward.observations.isEmpty)
        XCTAssertTrue(reopened.tokenSteward.reservations.isEmpty)
        XCTAssertEqual(window.contentLayoutRect.width, size.width, accuracy: 1)
        XCTAssertEqual(window.contentLayoutRect.height, size.height, accuracy: 1)
        await reopened.shutdownAssistant()
        await play.shutdown()
    }

    private struct Node {
        let object: NSObject
        let id: String?
        let frame: NSRect?
        let text: String
    }

    @MainActor private func automaticUsageFocus(_ taskID: String, _ store: CompanionStore,
                                               _ hosting: NSView, _ window: NSWindow) async throws
        -> (control: Node, row: String, button: String) {
        XCTAssertEqual(store.section, .steward)
        XCTAssertEqual(store.selectedStewardTaskID, taskID)
        XCTAssertNil(store.workspaceRoutingNotice)
        // Deliberately no reachable(), scrollTo(), clip-view movement or manual
        // selection here. Production onAppear/onChange owns the entire scroll.
        let row = try await waitVisible("steward.task.\(taskID)", hosting, window)
        _ = try await waitVisible("steward.selected-task", hosting, window)
        let button = try await waitVisible("steward.open-arc.\(taskID)", hosting, window)
        return (button, NSStringFromRect(try XCTUnwrap(row.frame)), NSStringFromRect(try XCTUnwrap(button.frame)))
    }

    @MainActor private func nodes(_ root: NSObject) -> [Node] {
        var result: [Node] = [], seen = Set<ObjectIdentifier>()
        func visit(_ object: NSObject, depth: Int) {
            guard depth < 40, result.count < 6000, seen.insert(ObjectIdentifier(object)).inserted else { return }
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
               let size = object.accessibilityAttributeValue(.size) as? NSValue {
                frame = NSRect(origin: position.pointValue, size: size.sizeValue)
            }
            func string(_ value: Any?) -> String? {
                if let text = value as? String { return text }
                return (value as? NSAttributedString)?.string
            }
            let text = [string(value("accessibilityValue")), string(value("accessibilityLabel")),
                attributes.contains(.value) ? string(object.accessibilityAttributeValue(.value)) : nil,
                attributes.contains(.title) ? string(object.accessibilityAttributeValue(.title)) : nil,
                attributes.contains(.description) ? string(object.accessibilityAttributeValue(.description)) : nil]
                .compactMap { $0 }.joined(separator: "\n")
            result.append(Node(object: object, id: id, frame: frame, text: text))
            let modern = value("accessibilityChildren") as? [Any] ?? []
            let legacy = attributes.contains(.children) ? object.accessibilityAttributeValue(.children) as? [Any] ?? [] : []
            for child in modern + legacy { if let child = child as? NSObject { visit(child, depth: depth + 1) } }
            if let window = object as? NSWindow, let content = window.contentView { visit(content, depth: depth + 1) }
            if let view = object as? NSView { for child in view.subviews { visit(child, depth: depth + 1) } }
        }
        visit(root, depth: 0)
        return result
    }

    @MainActor private func scrollViews(_ hosting: NSView) -> [NSScrollView] {
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        return descendants(hosting).compactMap { $0 as? NSScrollView }
            .filter { !($0.documentView is NSTextView) && $0.contentView.bounds.width > 300 }
    }

    @MainActor private func visible(_ identifier: String, _ hosting: NSView, _ window: NSWindow) -> Node? {
        let viewport = window.convertToScreen(window.contentLayoutRect)
        return nodes(window).first { node in
            guard node.id == identifier, let frame = node.frame, frame.width > 2, frame.height > 2,
                  viewport.insetBy(dx: -1, dy: -1).contains(frame) else { return false }
            return scrollViews(hosting).contains { scroll in
                let clip = window.convertToScreen(scroll.contentView.convert(scroll.contentView.bounds, to: nil))
                return clip.insetBy(dx: -1, dy: -1).contains(frame)
            }
        }
    }

    @MainActor private func waitVisible(_ identifier: String, _ hosting: NSView, _ window: NSWindow) async throws -> Node {
        for _ in 0..<40 {
            if let node = visible(identifier, hosting, window) { return node }
            try await settle(hosting, window)
        }
        let matching = nodes(window).filter { $0.id == identifier }.map { $0.frame.map(NSStringFromRect) ?? "missing-frame" }
        let clips = scrollViews(hosting).map { NSStringFromRect($0.contentView.bounds) }
        return try XCTUnwrap(visible(identifier, hosting, window),
            "\(identifier) must become fully visible automatically; observed frames \(matching), clip bounds \(clips). No test scroll was performed.")
    }

    /// Ordinary scrolling is allowed to reach ARC/graph buttons, but never on
    /// Usage: doing so would hide precisely the focus regression under test.
    @MainActor private func reachable(_ identifier: String, _ store: CompanionStore,
                                     _ hosting: NSView, _ window: NSWindow) async throws -> Node {
        guard store.section != .steward else {
            XCTFail("The round-trip test must never manually scroll Usage.")
            throw NativeFailure.forbiddenUsageScroll
        }
        if let node = visible(identifier, hosting, window) { return node }
        for scroll in scrollViews(hosting) {
            let maximum = max(0, (scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.height)
            let count = min(35, max(1, Int(ceil(maximum / max(80, scroll.contentView.bounds.height * 0.4)))))
            for index in 0...count {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: maximum * CGFloat(index) / CGFloat(count)))
                scroll.reflectScrolledClipView(scroll.contentView)
                try await settle(hosting, window)
                if let node = visible(identifier, hosting, window) { return node }
            }
        }
        return try XCTUnwrap(visible(identifier, hosting, window), "\(identifier) must be reachable in the production workspace.")
    }

    @MainActor private func press(_ node: Node) throws {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard node.object.responds(to: selector) else { throw NativeFailure.missingPress }
        if let control = node.object as? NSAccessibilityProtocol { XCTAssertTrue(control.accessibilityPerformPress()) }
        else {
            let action = unsafeBitCast(node.object.method(for: selector), to: (@convention(c) (AnyObject, Selector) -> Bool).self)
            XCTAssertTrue(action(node.object, selector))
        }
    }

    @MainActor private func settle(_ view: NSView, _ window: NSWindow) async throws {
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
        view.layoutSubtreeIfNeeded()
    }

    @MainActor private func capture(_ view: NSView, _ url: URL) throws {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }

    private func files(in directory: URL) throws -> [String: Data] {
        let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        return try Dictionary(uniqueKeysWithValues: entries.filter {
            try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        }.map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    }

    private enum NativeFailure: Error { case missingPress, forbiddenUsageScroll }

    @MainActor private final class NoDispatchAssistant: AssistantClient {
        var calls = 0
        func connect() async throws { calls += 1; throw AssistantFailure.unavailable }
        func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
            calls += 1; throw AssistantFailure.unavailable
        }
        func disconnect() {}
    }
}
