import AppKit
import Metal
import XCTest
@testable import ARCHiDesktop

/// Opt-in production Metal readback over the independently qualified package.
/// The three records are synthetic; no profile, model or game is opened.
final class LiminalGraphMorphGPUTests: XCTestCase {
    @MainActor func testQualifiedParticlesMorphFromMapToExactBeastAndHideFilteredRecords() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let packagePath = environment["ARCHI_LIMINAL_MORPH_PACKAGE"],
              let outputPath = environment["ARCHI_LIMINAL_MORPH_OUTPUT"] else {
            throw XCTSkip("Set ARCHI_LIMINAL_MORPH_PACKAGE and a new ARCHI_LIMINAL_MORPH_OUTPUT for qualified GPU captures")
        }
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("A Metal device is required for renderer readback") }
        let package = URL(fileURLWithPath: packagePath).resolvingSymlinksInPath()
        let output = URL(fileURLWithPath: outputPath).resolvingSymlinksInPath()
        guard output != package, !output.path.hasPrefix(package.path + "/"),
              !FileManager.default.fileExists(atPath: output.path) else {
            XCTFail("Capture output must be new and outside the qualified package"); return
        }
        let manifest = "9f89cc0914f537242d6cbc3d6ab4040c56f97f08872d954ed3cf3c33bb07e1ed"
        let asset = try LiminalPointAsset.load(packageURL: package, expectedManifestSHA256: manifest)
        XCTAssertEqual(try XCTUnwrap(asset.finish).digest, LiminalPointFinish.expectedSHA256)
        let graph = CompanionGraphSnapshot(nodes: (0..<3).map { index in
            .init(id: "morph-record-\(index)", title: "Synthetic record \(index)", subtitle: "Renderer fixture",
                  kind: .lesson, status: "Synthetic", details: [], target: .memory)
        }, edges: [], truncatedCount: 0)
        let origin = String(repeating: "a", count: 64)
        var allocator = try LiminalKnowledgeBindings(manifestSHA256: manifest, lowDetailIDs: asset.lowDetailIDs)
        let bindings = try allocator.project(graph, sessionID: "00000000-0000-4000-8000-000000000001", originDigest: origin)
        let field = KnowledgeParticleField(snapshot: graph)
        func descriptor(visible: Set<String>) throws -> LiminalGraphMorph {
            try XCTUnwrap(LiminalGraphMorph.make(asset: asset, bindings: bindings, fullGraph: graph, mapGraph: graph,
                field: field, originDigest: origin, viewport: CGSize(width: 512, height: 512), visibleNodeIDs: visible))
        }
        let morph = try descriptor(visible: Set(graph.nodes.map(\.id)))
        let source = try asset.framePair(progress: LiminalGraphMorph.targetProgress, detail: .low).lower
        let sourceHash = LiminalPointAsset.digest(source.data), artIDs = asset.artIDs
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var captures: [[String: Any]] = []
        func capture(_ name: String, progress: Double, recipe: LiminalGraphMorph) throws -> Data {
            let data = try LiminalMetalView.snapshotPNGData(asset: asset, progress: 1, seedColor: .original,
                lightMode: .focus, unixTime: 2, reduceMotion: false,
                graphMorph: recipe, graphMorphProgress: progress)
            try LiminalPointAsset.validatePNG(data)
            try data.write(to: output.appendingPathComponent(name + ".png"), options: .withoutOverwriting)
            captures.append(["name": name, "progress": progress, "pngSHA256": LiminalPointAsset.digest(data)])
            return data
        }
        let map = try capture("map", progress: 0, recipe: morph)
        let middle = try capture("midpoint", progress: 0.5, recipe: morph)
        let beast = try capture("beast", progress: 1, recipe: morph)
        XCTAssertNotEqual(map, middle); XCTAssertNotEqual(middle, beast); XCTAssertNotEqual(map, beast)
        let ordinaryBeast = try LiminalMetalView.snapshotPNGData(asset: asset, progress: LiminalGraphMorph.targetProgress,
            seedColor: .original, inspection: true, detail: .low)
        XCTAssertEqual(beast, ordinaryBeast, "The endpoint must be the same finish-treated authored Beast, with no extra geometry")
        let steady = try LiminalMetalView.snapshotPNGData(asset: asset, progress: 0, seedColor: .original,
            lightIntensity: 2, lightMode: .delight, unixTime: 99, reduceMotion: true,
            graphMorph: morph, graphMorphProgress: 0.5)
        XCTAssertEqual(middle, steady, "Morph position/color must not depend on unrelated pose, clock or activity")
        let personalColor = try LiminalMetalView.snapshotPNGData(asset: asset, progress: 0, seedColor: .aqua,
            graphMorph: morph, graphMorphProgress: 0.5)
        XCTAssertNotEqual(middle, personalColor, "The existing personal color policy must still apply during morphing")

        let rgba = try XCTUnwrap(SeedColorRendering.rgba(try XCTUnwrap(NSImage(data: map))))
        XCTAssertEqual(rgba.width, 512); XCTAssertEqual(rgba.height, 512)
        let positions = morph.anchorPositions(asset: asset, frame: source, progress: 0)
        XCTAssertEqual(positions.count, graph.nodes.count)
        for point in positions.values {
            let x = Int(point.x.rounded()), y = Int(point.y.rounded())
            let nearby = (-3...3).flatMap { dy in (-3...3).compactMap { dx -> UInt8? in
                guard (0..<512).contains(x + dx), (0..<512).contains(y + dy) else { return nil }
                return rgba.bytes[((y + dy) * 512 + x + dx) * 4 + 3]
            } }
            XCTAssertTrue(nearby.contains { $0 > 0 }, "Each selectable CPU anchor must coincide with rendered map particles")
        }
        let hidden = try capture("filtered-map", progress: 0, recipe: descriptor(visible: []))
        let hiddenRGBA = try XCTUnwrap(SeedColorRendering.rgba(try XCTUnwrap(NSImage(data: hidden))))
        XCTAssertTrue(stride(from: 3, to: hiddenRGBA.bytes.count, by: 4).allSatisfy { hiddenRGBA.bytes[$0] == 0 },
                      "Hidden mapped points and unbound artwork must not leak into the map endpoint")
        XCTAssertEqual(asset.artIDs, artIDs)
        XCTAssertEqual(LiminalPointAsset.digest(try asset.framePair(progress: LiminalGraphMorph.targetProgress, detail: .low).lower.data), sourceHash)
        try JSONSerialization.data(withJSONObject: ["schema": "archi-graph-beast-morph-gpu/v1",
            "manifestSHA256": manifest, "morphDigest": morph.digest, "sourceSampleSHA256": sourceHash,
            "syntheticRecords": graph.nodes.count, "pointCount": source.pointCount, "artIDsPreserved": true, "sourceUnchanged": true,
            "profileOpened": false, "modelCalls": 0, "captures": captures], options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("receipt.json"), options: .withoutOverwriting)
    }
}
