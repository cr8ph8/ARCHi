import AppKit
import Metal
import SwiftUI
import XCTest
@testable import ARCHiDesktop

/// A real AppKit mount, distinct from the offscreen Metal snapshot tests. All
/// records are synthetic; the only asset read is the qualified point package.
final class LiminalGraphMorphHostingTests: XCTestCase {
    @MainActor func testAppKitHostCompletesSeedMapAndBodyWithoutAnActiveSwiftUIScene() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ARCHI_LIMINAL_MORPH_NATIVE"] == "1",
              let packagePath = environment["ARCHI_LIMINAL_MORPH_PACKAGE"] else {
            throw XCTSkip("Set ARCHI_LIMINAL_MORPH_NATIVE=1 and ARCHI_LIMINAL_MORPH_PACKAGE for a mounted native check")
        }
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("A Metal device is required") }
        let asset = try LiminalPointAsset.load(packageURL: URL(fileURLWithPath: packagePath),
            expectedManifestSHA256: "9f89cc0914f537242d6cbc3d6ab4040c56f97f08872d954ed3cf3c33bb07e1ed")
        let graph = CompanionGraphSnapshot(nodes: (0..<3).map { index in
            .init(id: "host-record-\(index)", title: "Synthetic record \(index)", subtitle: "Hosting fixture",
                  kind: .lesson, status: "Synthetic", details: [], target: .memory)
        }, edges: [], truncatedCount: 0)
        let origin = String(repeating: "a", count: 64)
        var allocator = try LiminalKnowledgeBindings(manifestSHA256: asset.manifestSHA256, lowDetailIDs: asset.lowDetailIDs)
        let bindings = try allocator.project(graph, sessionID: "00000000-0000-4000-8000-000000000001", originDigest: origin)
        let field = KnowledgeParticleField(snapshot: graph)
        let source = LiminalGraphMorphSource(asset: asset, bindings: bindings, fullGraph: graph, originDigest: origin)
        let state = MorphHostingState()
        let app = NSApplication.shared, priorPolicy = app.activationPolicy()
        _ = app.setActivationPolicy(.accessory)
        app.finishLaunching()
        defer { _ = app.setActivationPolicy(priorPolicy) }
        let panel = NSPanel(contentRect: CGRect(x: 100, y: 100, width: 512, height: 512),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "ARCHi particle hosting · synthetic check"
        panel.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: MorphHostingFixture(state: state, source: source, graph: graph, field: field))
        host.sizingOptions = []
        panel.contentView = host
        defer { panel.contentView = nil; panel.close() }
        panel.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        host.layoutSubtreeIfNeeded()
        let identifier = "companion-graph.liminal-morph"
        try await NativeAccessibilityFixture.initialize(waitingFor: identifier) {
            self.objects(panel).contains { self.value($0, "accessibilityIdentifier") as? String == identifier }
        }
        let mountClock = ContinuousClock(), mountDeadline = mountClock.now.advanced(by: .seconds(8))
        while findSurface(host) == nil && mountClock.now < mountDeadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        let surface = try XCTUnwrap(findSurface(host))
        XCTAssertNotNil(surface.device, "The representable must use the designated Metal initializer")
        XCTAssertTrue(surface.delegate === surface, "The mounted surface must install its drawing delegate")
        // The renderer deliberately refuses to draw while the native window is
        // occluded. A locked or unavailable desktop is not mounted GPU evidence.
        let visibilityDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while surface.window?.occlusionState.contains(.visible) != true && ContinuousClock.now < visibilityDeadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        guard surface.window === panel, surface.window?.isVisible == true,
              surface.window?.occlusionState.contains(.visible) == true else {
            throw XCTSkip("Mounted GPU qualification needs an unoccluded desktop: \(nativeState(surface))")
        }
        var completedKey: String?
        for progress in [-1.0, 0, 1, -1] {
            state.progress = progress
            state.selectedID = nil
            let deadline = ContinuousClock.now.advanced(by: .seconds(8))
            var completed = false
            while ContinuousClock.now < deadline {
                host.layoutSubtreeIfNeeded()
                let status = Mirror(reflecting: surface)
                let available = status.descendant("reportedMorphAvailability") as? (key: String, ready: Bool)
                let displayed = status.descendant("reportedMorphProgress") as? (key: String, progress: Double)
                // These values publish only from a completed GPU command, not
                // from the requested SwiftUI form or a loaded CPU source frame.
                if available?.ready == true, displayed?.progress == progress,
                   available?.key == displayed?.key {
                    if let completedKey { XCTAssertEqual(displayed?.key, completedKey) }
                    else { completedKey = displayed?.key }
                    completed = true; break
                }
                try await Task.sleep(for: .milliseconds(25))
            }
            if !completed { print("Unready mounted morph at \(progress): \(nativeState(surface))") }
            XCTAssertTrue(completed, "A visible mounted surface must complete GPU progress \(progress)")
            guard completed else { return }
            XCTAssertTrue(findSurface(host) === surface, "Changing form must preserve the mounted Metal surface")
            XCTAssertFalse(objects(panel).contains { node in
                ["accessibilityLabel", "accessibilityValue", "accessibilityTitle"].contains {
                    (value(node, $0) as? String)?.contains("Point form is not available yet") == true
                }
            })
            let button = try XCTUnwrap(objects(panel).first { isRecordButton($0) },
                "A completed endpoint must expose its record action")
            let press = NSSelectorFromString("accessibilityPerformPress")
            XCTAssertTrue(button.responds(to: press))
            let action = unsafeBitCast(button.method(for: press), to: (@convention(c) (AnyObject, Selector) -> Bool).self)
            XCTAssertTrue(action(button, press))
            XCTAssertEqual(state.selectedID, "host-record-0")
            print("Mounted morph completed progress=\(progress), selected=\(state.selectedID ?? "nil"), sameSurface=true")
        }
    }

    @MainActor private func nativeState(_ surface: LiminalMetalSurface) -> String {
        let mirror = Mirror(reflecting: surface)
        let fields = mirror.children.filter {
            ["frameNumbers", "loadedKey", "loadingKey", "failedKey", "reportedMorphAvailability", "reportedMorphProgress"].contains($0.label ?? "")
        }.map { "\($0.label ?? "field")=\($0.value)" }.joined(separator: "; ")
        let configuration = mirror.descendant("configuration") as? LiminalMetalView
        return "device=\(surface.device != nil), delegate=\(surface.delegate === surface), configuredVisible=\(configuration?.isVisible == true), windowVisible=\(surface.window?.isVisible == true), nativeVisibleBit=\(surface.window?.occlusionState.contains(.visible) == true), occlusion=\(surface.window?.occlusionState.rawValue ?? 0), hidden=\(surface.isHiddenOrHasHiddenAncestor), drawable=\(surface.drawableSize); \(fields)"
    }

    @MainActor private func findSurface(_ view: NSView) -> LiminalMetalSurface? {
        if let surface = view as? LiminalMetalSurface { return surface }
        return view.subviews.lazy.compactMap { self.findSurface($0) }.first
    }
    @MainActor private func value(_ object: NSObject, _ name: String) -> Any? {
        let selector = NSSelectorFromString(name)
        if object.responds(to: selector) { return object.perform(selector)?.takeUnretainedValue() }
        return nil
    }
    @MainActor private func isRecordButton(_ object: NSObject) -> Bool {
        let label = value(object, "accessibilityLabel") as? String ?? ""
        return label.contains("Synthetic record 0") && (value(object, "accessibilityRole") as? String) == "AXButton"
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
}

@MainActor private final class MorphHostingState: ObservableObject {
    @Published var progress = -1.0
    @Published var selectedID: String?
}
@MainActor private struct MorphHostingFixture: View {
    @ObservedObject var state: MorphHostingState
    let source: LiminalGraphMorphSource
    let graph: CompanionGraphSnapshot
    let field: KnowledgeParticleField
    var body: some View {
        LiminalGraphMorphView(source: source, graph: graph, field: field, nodes: graph.nodes,
            selectedID: state.selectedID, progress: state.progress, reduceMotion: true, seedColor: .original,
            focusIDs: nil, growthByRecordID: [:], preparedIDs: [], expression: .resting,
            onSelect: { state.selectedID = $0 })
            // Raw AppKit hosts do not publish an active SwiftUI Scene phase.
            // A visible native window must still complete its first GPU frame.
            .environment(\.scenePhase, .background)
    }
}
