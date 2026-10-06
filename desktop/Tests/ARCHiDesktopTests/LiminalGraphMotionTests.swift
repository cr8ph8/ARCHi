import AppKit
import MetalKit
import XCTest
@testable import ARCHiDesktop

/// Real authenticated v008 geometry with synthetic, explicitly local graph
/// records. These checks exercise the native renderer, never a model or profile.
@MainActor final class LiminalGraphMotionTests: XCTestCase {
    private let manifest = "9f89cc0914f537242d6cbc3d6ab4040c56f97f08872d954ed3cf3c33bb07e1ed"
    private let origin = String(repeating: "a", count: 64)
    private let viewport = CGSize(width: 512, height: 512)
    private let session = "00000000-0000-4000-8000-000000000002"

    private func asset() throws -> LiminalPointAsset {
        let path = ProcessInfo.processInfo.environment["ARCHI_LIMINAL_LIVE_PACKAGE"]
            ?? "/Applications/ARCHi.app/Contents/Resources/LiminalV008"
        guard FileManager.default.fileExists(atPath: path + "/manifest.json") else {
            throw XCTSkip("Real v008 package unavailable; set ARCHI_LIMINAL_LIVE_PACKAGE for native GPU qualification")
        }
        return try LiminalPointAsset.load(packageURL: URL(fileURLWithPath: path), expectedManifestSHA256: manifest)
    }
    private var graph: CompanionGraphSnapshot {
        .init(nodes: ["memory-a", "memory-b", "root"].map { id in
            .init(id: id, title: "Synthetic \(id)", subtitle: "Fixture version", kind: id == "root" ? .companion : .knowledge,
                  status: "Recorded", details: [], target: .memory)
        }, edges: [.init(id: "a-root", source: "memory-a", target: "root", label: "Retained by"),
                   .init(id: "a-b", source: "memory-a", target: "memory-b", label: "Related")], truncatedCount: 0)
    }
    private func projection(_ asset: LiminalPointAsset, focus: Set<String>? = nil)
        throws -> (LiminalGraphMorph, LiminalKnowledgeBindings.Sidecar, KnowledgeParticleField) {
        let field = KnowledgeParticleField(snapshot: graph)
        var allocator = try LiminalKnowledgeBindings(manifestSHA256: manifest, lowDetailIDs: asset.lowDetailIDs)
        let bindings = try allocator.project(graph, sessionID: session, originDigest: origin)
        let morph = try XCTUnwrap(LiminalGraphMorph.make(asset: asset, bindings: bindings,
            fullGraph: graph, mapGraph: graph, field: field, originDigest: origin, viewport: viewport,
            visibleNodeIDs: Set(graph.nodes.map(\.id)), focusIDs: focus))
        return (morph, bindings, field)
    }

    func testSharedDisplacementMatchesCanvasEndpointsAndEveryBoundCluster() throws {
        let asset = try asset(), (morph, bindings, field) = try projection(asset, focus: ["memory-a", "root"])
        let frame = try asset.framePair(progress: LiminalGraphMorph.targetProgress, detail: .low).lower
        let bytes = frame.data, digest = morph.digest
        let offset = KnowledgeParticleField.Vector(x: 0.13, y: -0.07)
        let motion = CompanionParticleMotion.Frame(offsets: ["memory-a": offset, "not-a-record": .init(x: 1, y: 1)], revision: 9)
        for (progress, spread) in [(-1.0, 0.0), (0.0, 1.0)] {
            let framing = KnowledgeParticleField.framing(particles: field.particles, spread: spread,
                reduceMotion: true, focusIDs: spread == 1 ? ["memory-a", "root"] : nil)
            let canvas = KnowledgeParticleField.displayPositions(particles: field.particles, frame: framing,
                spread: spread, reduceMotion: true, width: viewport.width, height: viewport.height, motionOffsets: motion.offsets)
            let projected = morph.anchorPositions(asset: asset, frame: frame, progress: progress, motion: motion)
            for id in graph.nodes.map(\.id) {
                let point = try XCTUnwrap(projected[id]), expected = try XCTUnwrap(canvas[id])
                XCTAssertEqual(point.x, expected.x, accuracy: 0.0001)
                XCTAssertEqual(point.y, expected.y, accuracy: 0.0001)
            }
        }
        for progress in [-1.0, -0.4, 0, 0.4, 1] {
            let before = try XCTUnwrap(morph.anchorPositions(asset: asset, frame: frame, progress: progress)["memory-a"])
            let after = try XCTUnwrap(morph.anchorPositions(asset: asset, frame: frame, progress: progress, motion: motion)["memory-a"])
            XCTAssertEqual(after.x - before.x, offset.x * morph.motionPointScale(progress: progress), accuracy: 0.0001)
            XCTAssertEqual(after.y - before.y, offset.y * morph.motionPointScale(progress: progress), accuracy: 0.0001)
        }
        XCTAssertEqual(morph.motionPointScale(progress: 1), morph.motionPointScale(progress: 0) * 0.08, accuracy: 1e-12)
        let ranks = Dictionary(uniqueKeysWithValues: asset.artIDs.enumerated().map { ($0.element, $0.offset) })
        for detail in [LiminalPointAsset.Detail.low, .medium, .high] {
            let targets = morph.motionTargets(count: detail.rawValue, motion: motion)
            XCTAssertEqual(targets.count, detail.rawValue)
            for binding in bindings.bindings {
                for artID in binding.particleIDs {
                    XCTAssertEqual(targets[try XCTUnwrap(ranks[artID])], morph.motionClipOffsets(nodeID: binding.nodeID, motion: motion))
                }
            }
            XCTAssertEqual(targets.filter { $0 != .zero }.count, 32, "Only the actual record's complete bound cluster moves")
        }
        XCTAssertEqual(morph.motionTargets(count: 1, motion: motion), [])
        XCTAssertEqual(morph.motionClipOffsets(nodeID: "memory-a", motion: .init(offsets: ["memory-a": .init(x: .nan, y: 0)], revision: 10)), .zero)
        XCTAssertEqual(morph.digest, digest)
        XCTAssertEqual(frame.data, bytes)
        // Build and execute the production MSL independently of window startup;
        // a shader failure must surface here rather than as a visibility timeout.
        let png = try LiminalMetalView.snapshotPNGData(asset: asset, progress: LiminalGraphMorph.targetProgress,
            reduceMotion: false, inspection: true, graphMorph: morph, graphMorphProgress: 0.45, graphMotion: motion)
        XCTAssertNotNil(NSImage(data: png))
    }

    func testRealMetalCompletionsStreamMotionWithoutReloadAndPickDisplayedAnchor() async throws {
        let asset = try asset(), (morph, _, _) = try projection(asset)
        let frame = try asset.framePair(progress: LiminalGraphMorph.targetProgress, detail: .low).lower
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("No Metal device") }
        let application = NSApplication.shared, priorPolicy = application.activationPolicy()
        let previousFront = NSWorkspace.shared.frontmostApplication
        _ = application.setActivationPolicy(.accessory)
        application.finishLaunching()
        defer {
            _ = application.setActivationPolicy(priorPolicy)
            if previousFront?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousFront?.activate(options: []) }
        }
        let surface = LiminalMetalSurface(frame: CGRect(origin: .zero, size: viewport), device: MTLCreateSystemDefaultDevice())
        let window = NSWindow(contentRect: CGRect(x: 32, y: 32, width: 512, height: 512), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.level = .floating; window.contentView = surface
        window.title = "ARCHi · synthetic particle motion check"
        defer { surface.stop(); window.contentView = nil; window.orderOut(nil); window.close() }
        window.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)
        try await wait("native window visibility", surface: surface) { window.isVisible && window.occlusionState.contains(.visible) }
        let anchor = try XCTUnwrap(morph.anchors.first { $0.nodeID == "memory-a" })
        var completed: [(Double, CompanionParticleMotion.Frame)] = [], selected: UInt32?
        func configuration(visible: Bool = true, motion: CompanionParticleMotion.Frame = .still,
                           progress: Double = 0) -> LiminalMetalView {
            LiminalMetalView(asset: asset, progress: LiminalGraphMorph.targetProgress, reduceMotion: false,
                isVisible: visible, inspection: true, graphMorph: morph, graphMorphProgress: progress,
                graphMotion: motion, selectableIDs: [anchor.artID], onSelectArtID: { selected = $0 },
                onGraphMorphDisplayedMotion: { completed.append(($0, $1)) })
        }
        var config = configuration()
        surface.configure(config)
        try await wait("initial GPU completion", surface: surface) { completed.last?.1 == .still }
        let uploads = surface.geometryUploadCount
        XCTAssertEqual(uploads, 1)
        for (index, progress) in [-1.0, 0, 0.45, 1].enumerated() {
            let motion = CompanionParticleMotion.Frame(offsets: ["memory-a": .init(x: 0.08 + Double(index) * 0.01, y: -0.05)], revision: UInt64(index + 1))
            config.graphMotion = motion; config.graphMorphProgress = progress
            surface.configure(config)
            try await wait("GPU progress \(progress), revision \(motion.revision)", surface: surface) {
                completed.last?.0 == progress && completed.last?.1 == motion
            }
            XCTAssertEqual(surface.geometryUploadCount, uploads, "Motion must not re-read or re-upload source geometry")
            let point = try XCTUnwrap(morph.anchorPositions(asset: asset, frame: frame, progress: progress, motion: motion)[anchor.nodeID])
            let local = CGPoint(x: point.x, y: surface.bounds.height - point.y)
            let location = surface.convert(local, to: nil)
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: index, clickCount: 1, pressure: 1))
            selected = nil; surface.mouseDown(with: event)
            XCTAssertEqual(selected, anchor.artID, "Picking must use the actual GPU-completed frame")
        }
        let callbacks = completed.count, motionUploads = surface.motionUploadCount
        for _ in 0..<5 { surface.configure(config) }
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(completed.count, callbacks, "Acknowledgment feedback must not create more acknowledgments")
        XCTAssertEqual(surface.motionUploadCount, motionUploads)
        XCTAssertEqual(surface.geometryUploadCount, uploads)
        config = configuration(visible: false, motion: config.graphMotion, progress: config.graphMorphProgress)
        surface.configure(config)
        config.graphMotion = .init(offsets: ["memory-a": .init(x: -0.1, y: 0.1)], revision: 100)
        surface.configure(config); surface.draw()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(surface.isPaused)
        XCTAssertEqual(completed.count, callbacks)
        XCTAssertEqual(surface.motionUploadCount, motionUploads)
    }

    func testLiveReviewedDampingUsesOnlyCachedMotifAndStopsWhenReducedOrHidden() async throws {
        let asset = try asset(), frame = try asset.framePair(progress: LiminalGraphMorph.targetProgress, detail: .low).lower
        let structure = LiminalPointStructure(schemaVersion: 1, recipeVersion: LiminalPointStructure.version,
            sessionID: session, originDigest: origin, manifestSHA256: manifest, evidenceDigest: String(repeating: "c", count: 64),
            detail: 2, nodes: [.init(contentID: String(repeating: "d", count: 64), anchorID: asset.lowDetailIDs[0], applications: 2)])
        let base = structure.samples(frame: frame, asset: asset)
        for elapsed in [0.0, 0.3, 1, 3] {
            let cached = LiminalStructureMotion.samples(base, structure: structure, span: asset.span, elapsed: elapsed)
            let direct = structure.samples(frame: frame, asset: asset, elapsed: elapsed)
            XCTAssertEqual(cached.count, 6)
            for (a, b) in zip(cached, direct) {
                XCTAssertEqual(a.position.x, b.position.x, accuracy: 0.000001)
                XCTAssertEqual(a.position.y, b.position.y); XCTAssertEqual(a.position.z, b.position.z)
                XCTAssertEqual(a.color, b.color); XCTAssertEqual(a.radius, b.radius); XCTAssertEqual(a.emission, b.emission)
            }
        }
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("No Metal device") }
        let application = NSApplication.shared, priorPolicy = application.activationPolicy()
        let previousFront = NSWorkspace.shared.frontmostApplication
        _ = application.setActivationPolicy(.accessory)
        application.finishLaunching()
        defer {
            _ = application.setActivationPolicy(priorPolicy)
            if previousFront?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousFront?.activate(options: []) }
        }
        let surface = LiminalMetalSurface(frame: CGRect(origin: .zero, size: viewport), device: MTLCreateSystemDefaultDevice())
        let window = NSWindow(contentRect: CGRect(x: 32, y: 32, width: 512, height: 512), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.level = .floating; window.contentView = surface
        window.title = "ARCHi · synthetic particle motion check"
        defer { surface.stop(); window.contentView = nil; window.orderOut(nil); window.close() }
        window.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)
        try await wait("native window visibility", surface: surface) { window.isVisible && window.occlusionState.contains(.visible) }
        func configuration(reduced: Bool = false, visible: Bool = true, inspection: Bool = false) -> LiminalMetalView {
            LiminalMetalView(asset: asset, progress: LiminalGraphMorph.targetProgress,
                reduceMotion: reduced, isVisible: visible, inspection: inspection, structure: structure)
        }
        surface.configure(configuration())
        try await wait("two live motif uploads", surface: surface) { surface.structureMotionUploadCount >= 2 }
        let geometryUploads = surface.geometryUploadCount
        surface.configure(configuration(reduced: true))
        let reducedUploads = surface.structureMotionUploadCount
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(surface.isPaused); XCTAssertEqual(surface.structureMotionUploadCount, reducedUploads)
        XCTAssertEqual(surface.geometryUploadCount, geometryUploads)
        surface.configure(configuration(visible: false))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(surface.isPaused); XCTAssertEqual(surface.structureMotionUploadCount, reducedUploads)
        surface.configure(configuration(inspection: true))
        XCTAssertTrue(surface.isPaused); XCTAssertEqual(surface.structureMotionUploadCount, reducedUploads)
        XCTAssertEqual(structure.samples(frame: frame, asset: asset), base)
    }

    private func wait(_ stage: String, surface: LiminalMetalSurface, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while true {
            // XCTest schedules async tasks but does not run NSApplication.run().
            // Deliver only events already queued for this test application's
            // windows; never synthesize visibility or bypass the renderer gate.
            let app = NSApplication.shared
            for _ in 0..<100 {
                guard let event = app.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) else { break }
                app.sendEvent(event)
            }
            app.updateWindows()
            if condition() { return }
            guard Date() < deadline else {
                let state = nativeState(surface)
                XCTFail("Timed out at \(stage): \(state)")
                throw NSError(domain: "LiminalGraphMotionTests", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: stage + ": " + state])
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    private func nativeState(_ surface: LiminalMetalSurface) -> String {
        let mirror = Mirror(reflecting: surface)
        let fields = mirror.children.filter {
            ["pipeline", "frameNumbers", "loadedKey", "loadingKey", "failedKey", "reportedMorphAvailability", "reportedMorphProgress"].contains($0.label ?? "")
        }.map { "\($0.label ?? "field")=\($0.value)" }.joined(separator: "; ")
        return "active=\(NSApplication.shared.isActive), policy=\(NSApplication.shared.activationPolicy().rawValue), device=\(surface.device != nil), delegate=\(surface.delegate === surface), windowVisible=\(surface.window?.isVisible == true), occlusion=\(surface.window?.occlusionState.rawValue ?? 0), hidden=\(surface.isHiddenOrHasHiddenAncestor), drawableSize=\(surface.drawableSize), paused=\(surface.isPaused), geometryUploads=\(surface.geometryUploadCount), motionUploads=\(surface.motionUploadCount), motifUploads=\(surface.structureMotionUploadCount); \(fields)"
    }
}
