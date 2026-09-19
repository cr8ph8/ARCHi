import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

/// Opt-in acceptance of the real production NSOpenPanel/NSSavePanel cancel paths.
/// Uses only a disposable profile and a no-calls assistant. Successful selection
/// and save acceptance are deliberately not claimed by this test: macOS hosts
/// these panels remotely, and a URL passed to a store is not file-panel proof.
final class StewardARCFilePanelTests: XCTestCase {
    @MainActor
    func testNativeFilePanelCancellationPreservesEvidenceAndUsage() async throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_STEWARD_FILE_PANEL_DIR"], !path.isEmpty else {
            throw XCTSkip("Set ARCHI_STEWARD_FILE_PANEL_DIR for disposable native file-panel cancellation acceptance.")
        }
        let output = URL(fileURLWithPath: path).appendingPathComponent("steward-arc-file-panels-\(UUID())")
        let profile = FileManager.default.temporaryDirectory.appendingPathComponent("archi-file-panel-profile-\(UUID())")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: profile) }
        var preferences = CompanionPreferences()
        preferences.reduceMotion = true
        preferences.quiet = true
        let preferenceURL = profile.appendingPathComponent("preferences.json")
        let originalPreferences = try NativePreferenceDocument(preferences: preferences).encoded()
        try originalPreferences.write(to: preferenceURL)
        let client = NoCallsAssistant()
        let store = CompanionStore(preferenceURL: preferenceURL, assistant: client,
            assistantFactory: { _, _ in client }, allowsPlay: false)
        defer { store.disconnectAssistant() }
        store.prompt = "UNSENT_FILE_PANEL_DRAFT"
        store.share(text: "PRIVATE_FILE_PANEL_SOURCE", name: "Synthetic source.txt")
        // Seed a nonempty shelf and journal so cancellation must preserve useful
        // existing data. This setup is not a native import acceptance assertion.
        store.recordARCEvaluation(store.arcCapabilities.runSyntheticDemonstration())
        XCTAssertNil(store.arcCapabilities.lastError)
        XCTAssertEqual(store.arcCapabilities.records.count, 1)
        XCTAssertEqual(store.tokenSteward.summary.evaluationTaskCount, 1)
        let originalJournal = try store.tokenSteward.exportData()
        let originalFiles = try profileFiles(profile)
        let originalTasks = store.tokenSteward.tasks
        let originalEvidenceIDs = store.arcCapabilities.records.map(\.id)
        let originalEvidenceBundles = store.arcCapabilities.records.map(\.bundle)
        let originalEvolutionRevision = store.evolution.revision
        let originalEvolutionHistory = store.evolution.history
        let originalDraft = store.prompt, originalSource = store.sharedText

        let app = NSApplication.shared, previousPolicy = app.activationPolicy()
        _ = app.setActivationPolicy(.accessory)
        app.finishLaunching()
        defer { _ = app.setActivationPolicy(previousPolicy) }
        let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 980, height: 760),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "ARCHi · Disposable file panel cancellation"
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        var samples: [[String: Any]] = []
        defer {
            let report: [String: Any] = [
                "schema": "archi-steward-arc-file-panels/v1",
                "samples": samples,
                "assistantCalls": client.calls,
                "coverage": "Real production import/export button actions and native panel cancellation; disposable profile only.",
                "unverified": "Successful Open/Save selection, valid and invalid imports through the panel, and export through an accepted Save panel. Store/file-boundary tests are separate evidence."
            ]
            try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("file-panels.json"), options: .atomic)
            print("Steward / ARC native file-panel cancellation: \(output.path)")
        }

        for kind in [PanelKind.open, .save] {
            let hosting: NSView
            let identifier: String
            if kind == .open {
                hosting = NSHostingView(rootView: ARCCapabilitiesWorkspace(store: store.arcCapabilities,
                    onEvaluation: store.recordARCEvaluation))
                identifier = "capabilities.import"
            } else {
                hosting = NSHostingView(rootView: TokenStewardWorkspace(store: store.tokenSteward))
                identifier = "steward.export"
            }
            window.contentView = hosting
            window.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)
            try await settle(hosting, window)
            try await NativeAccessibilityFixture.initialize(waitingFor: identifier) {
                self.nodes(window).contains { $0.identifier == identifier }
            }
            let button = try await reachable(identifier, hosting, window)
            let driver = CancellationDriver(kind: kind)
            driver.start()
            defer { driver.stop() }
            try press(button)
            let deadline = ContinuousClock.now.advanced(by: .seconds(15))
            while !driver.finished && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(40))
            }
            driver.stop()
            try await settle(hosting, window)
            samples.append([
                "action": identifier,
                "expectedPanel": kind.rawValue,
                "observedPanel": driver.observedPanel ?? "none",
                "cancelRequested": driver.cancelRequested,
                "watchdogUsed": driver.watchdogUsed,
                "closed": driver.finished,
                "profileFilesUnchanged": try profileFiles(profile) == originalFiles
            ])
            XCTAssertEqual(driver.observedPanel, kind.rawValue, "The production view action must open its real native panel.")
            XCTAssertTrue(driver.cancelRequested, "The test must invoke the panel's public Cancel action.")
            XCTAssertTrue(driver.finished, "The native panel must close after cancellation.")
            XCTAssertFalse(driver.watchdogUsed, "A watchdog abort is not native cancellation acceptance.")
            XCTAssertNil(app.modalWindow, "The test must leave no modal window running.")
            XCTAssertEqual(try profileFiles(profile), originalFiles, "Cancel must not write, remove, or replace profile files.")
            XCTAssertEqual(try store.tokenSteward.exportData(), originalJournal)
            XCTAssertEqual(store.tokenSteward.tasks, originalTasks)
            XCTAssertEqual(store.arcCapabilities.records.map(\.id), originalEvidenceIDs)
            XCTAssertEqual(store.arcCapabilities.records.map(\.bundle), originalEvidenceBundles)
            XCTAssertNil(store.arcCapabilities.lastError)
            XCTAssertNil(store.tokenSteward.loadError)
            XCTAssertNil(store.tokenSteward.budget)
            XCTAssertEqual(store.preferences, preferences)
            XCTAssertEqual(store.evolution.revision, originalEvolutionRevision)
            XCTAssertEqual(store.evolution.history, originalEvolutionHistory)
            XCTAssertEqual(store.prompt, originalDraft)
            XCTAssertEqual(store.sharedText, originalSource)
            XCTAssertEqual(try Data(contentsOf: preferenceURL), originalPreferences)
            XCTAssertEqual(client.calls, 0)
        }
        await store.shutdownAssistant()
    }

    private enum PanelKind: String { case open = "NSOpenPanel", save = "NSSavePanel" }

    /// Runs in both normal and modal run-loop modes. Only this process's active
    /// modal file panel is touched; no private selector, global key, user default,
    /// injected URL, or another application's UI participates.
    @MainActor private final class CancellationDriver {
        let kind: PanelKind
        private var timer: Timer?
        private var started = Date()
        private var panel: NSSavePanel?
        private var cancellationTime: Date?
        private(set) var observedPanel: String?
        private(set) var cancelRequested = false
        private(set) var watchdogUsed = false
        private(set) var finished = false

        init(kind: PanelKind) { self.kind = kind }

        func start() {
            started = Date()
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
            RunLoop.main.add(timer, forMode: .modalPanel)
        }

        func stop() { timer?.invalidate(); timer = nil }

        private func tick() {
            let app = NSApplication.shared
            if let panel, cancelRequested, !panel.isVisible, app.modalWindow !== panel {
                finished = true
                stop()
                return
            }
            if panel == nil, let candidate = app.modalWindow as? NSSavePanel {
                let actual: PanelKind = candidate is NSOpenPanel ? .open : .save
                panel = candidate
                observedPanel = actual.rawValue
                if actual != kind { watchdogUsed = true }
                // Let the remote panel complete its first display before Cancel.
                cancellationTime = Date().addingTimeInterval(0.35)
            }
            if !cancelRequested, let panel, let cancellationTime, Date() >= cancellationTime {
                cancelRequested = true
                panel.cancel(nil)
            }
            if Date().timeIntervalSince(started) >= 10 {
                watchdogUsed = true
                panel?.cancel(nil)
                if app.modalWindow != nil { app.abortModal() }
                panel?.orderOut(nil)
                finished = true
                stop()
            }
        }
    }

    private struct Node {
        let object: NSObject
        let identifier: String?
        let frame: NSRect?
    }

    @MainActor private func nodes(_ root: NSObject) -> [Node] {
        var result: [Node] = [], seen = Set<ObjectIdentifier>()
        func visit(_ object: NSObject, depth: Int) {
            guard depth < 40, result.count < 4000, seen.insert(ObjectIdentifier(object)).inserted else { return }
            func value(_ name: String) -> Any? {
                let selector = NSSelectorFromString(name)
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
            result.append(Node(object: object, identifier: identifier, frame: frame))
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
        let scrolls = descendants(hosting).compactMap { $0 as? NSScrollView }.filter { !($0.documentView is NSTextView) }
        func visible() -> Node? {
            let viewport = window.convertToScreen(window.contentLayoutRect)
            return nodes(window).first { node in
                guard node.identifier == identifier, let frame = node.frame, frame.width > 2, frame.height > 2 else { return false }
                return viewport.insetBy(dx: -1, dy: -1).contains(frame)
            }
        }
        if let node = visible() { return node }
        for scroll in scrolls {
            let maximum = max(0, (scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.height)
            for index in 0...20 {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: maximum * CGFloat(index) / 20))
                scroll.reflectScrolledClipView(scroll.contentView)
                try await settle(hosting, window)
                if let node = visible() { return node }
            }
        }
        return try XCTUnwrap(visible(), "The production \(identifier) button must be visible before invoking its file panel.")
    }

    @MainActor private func press(_ node: Node) throws {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard node.object.responds(to: selector) else { throw PanelFailure.missingPressAction }
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

    private func profileFiles(_ directory: URL) throws -> [String: Data] {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey], options: []))
        var result: [String: Data] = [:]
        for case let url as URL in enumerator {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[String(url.path.dropFirst(directory.path.count + 1))] = try Data(contentsOf: url)
            }
        }
        return result
    }

    private enum PanelFailure: Error { case missingPressAction }

    @MainActor private final class NoCallsAssistant: AssistantClient {
        var calls = 0
        func connect() async throws { calls += 1; throw AssistantFailure.unavailable }
        func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
            calls += 1; throw AssistantFailure.unavailable
        }
        func disconnect() {}
    }
}
