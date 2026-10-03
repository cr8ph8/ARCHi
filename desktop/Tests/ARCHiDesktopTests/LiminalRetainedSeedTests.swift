import AppKit
import XCTest
@testable import ARCHiDesktop

/// Opt-in captures of the production compositor, using the existing pinned package.
/// Synthetic retained records only; this never opens a profile or installed app.
final class LiminalRetainedSeedTests: XCTestCase {
    @MainActor func testRetainedArtworkSurvivesFinishAndKeepsExistingDynamics() throws {
        let env = ProcessInfo.processInfo.environment
        guard let package = env["ARCHI_LIMINAL_RETAINED_SEED_PACKAGE"],
              let destination = env["ARCHI_LIMINAL_RETAINED_SEED_OUTPUT"] else {
            throw XCTSkip("Set the qualified package and a new capture directory for retained Seed GPU validation")
        }
        let output = URL(fileURLWithPath: destination).standardizedFileURL
        let packageURL = URL(fileURLWithPath: package).resolvingSymlinksInPath()
        guard !output.path.hasPrefix(packageURL.path + "/"), output != packageURL,
              !FileManager.default.fileExists(atPath: output.path) else {
            XCTFail("Capture output must be new and outside the source package"); return
        }
        let digest = "9f89cc0914f537242d6cbc3d6ab4040c56f97f08872d954ed3cf3c33bb07e1ed"
        let asset = try LiminalPointAsset.load(packageURL: packageURL, expectedManifestSHA256: digest)
        XCTAssertEqual(try XCTUnwrap(asset.finish).digest, LiminalPointFinish.expectedSHA256)
        XCTAssertEqual(try XCTUnwrap(asset.surfaceLight).digest, LiminalSurfaceLight.expectedSHA256)
        let retainedURL = try XCTUnwrap(CompanionVisualAsset.resourceURL(named: CompanionVisualAsset.hamptonGarnetFilename))
        XCTAssertEqual(LiminalPointAsset.digest(try Data(contentsOf: retainedURL)), CompanionVisualAsset.hamptonGarnetDigest)
        let artwork = try XCTUnwrap(SeedColorRendering.rgba(try XCTUnwrap(CompanionVisualAsset.hamptonGarnetImage)))
        let state = LiminalFormDevelopment.Snapshot(originDigest: String(repeating: "a", count: 64), nodes: (0..<12).map { i in
            .init(id: String(format: "%064x", i + 1), lessonIDs: ["synthetic-\(i)"], graphNodeIDs: ["lesson:synthetic-\(i)"],
                  title: "Synthetic", applications: i < 6 ? 3 : 0)
        }, unavailableLessons: 0, duplicateLessons: 0, evidenceAvailable: true)
        let structure = try XCTUnwrap(LiminalPointStructureTestFixtures.make(state,
            sessionID: "00000000-0000-4000-8000-000000000001", manifestSHA256: digest, lowDetailIDs: asset.lowDetailIDs))
        let structureDigest = structure.digest, ids = asset.artIDs
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var records: [[String: Any]] = []
        func capture(_ name: String, frame: Int = 108, color: CompanionSeedColor = .garnet,
                     mode: KinLightMode = .rest, clock: Double = 0, reduced: Bool = true,
                     recipe: LiminalPointStructure? = nil, elapsed: Double? = nil) throws -> Data {
            let progress = Double(frame - 1) / 119
            let before = try asset.framePair(progress: progress, detail: .medium).lower.data
            let data = try LiminalMetalView.snapshotPNGData(asset: asset, progress: progress, seedColor: color,
                lightMode: mode, unixTime: clock, reduceMotion: reduced, structure: recipe, structureElapsed: elapsed)
            try LiminalPointAsset.validatePNG(data)
            XCTAssertEqual(try asset.framePair(progress: progress, detail: .medium).lower.data, before)
            XCTAssertEqual(asset.artIDs, ids)
            try data.write(to: output.appendingPathComponent(name + ".png"), options: .withoutOverwriting)
            records.append(["name": name, "frame": frame, "pngSHA256": LiminalPointAsset.digest(data),
                            "sourceSampleSHA256": LiminalPointAsset.digest(before), "sourceUnchanged": true])
            return data
        }
        let seed = try capture("seed-rest")
        let original = try capture("seed-original-palette", color: .original)
        XCTAssertEqual(seed, original, "The original Liminal route must retain the same garnet artwork")

        // Compare opaque artwork pixels after the production camera translation.
        // This detects the old finish gate even if the result is a valid PNG.
        let rendered = try XCTUnwrap(SeedColorRendering.rgba(try XCTUnwrap(NSImage(data: seed))))
        XCTAssertEqual(rendered.width, 512); XCTAssertEqual(rendered.height, 512)
        let framing = LiminalSeedStyle.framing(center: asset.center, span: asset.span, frame: 108, refined: true)
        let shift = Double(framing.center.x) * 512 / Double(framing.span)
        var totalError = 0.0, compared = 0
        for y in 0..<512 {
            for x in 0..<512 {
                let sourceX = Double(x) + shift, left = Int(floor(sourceX)), blend = sourceX - floor(sourceX)
                guard (0..<511).contains(left) else { continue }
                let a = (y * 512 + left) * 4, b = a + 4, target = (y * 512 + x) * 4
                guard artwork.bytes[a + 3] >= 250, artwork.bytes[b + 3] >= 250 else { continue }
                for channel in 0..<3 {
                    let expected = Double(artwork.bytes[a + channel]) * (1 - blend) + Double(artwork.bytes[b + channel]) * blend
                    totalError += abs(Double(rendered.bytes[target + channel]) - expected)
                }
                compared += 1
            }
        }
        // Most of the authored garnet membrane is deliberately translucent.
        // Its core, rim and constellation still provide thousands of opaque probes.
        XCTAssertGreaterThan(compared, 4_000)
        let meanError = totalError / Double(max(1, compared) * 3)
        XCTAssertLessThan(meanError, 5, "The original garnet sphere must remain visible through the finished/light package")

        let decorated = try capture("seed-retained-records", recipe: structure)
        XCTAssertNotEqual(seed, decorated, "Retained records must still add their independent motif")
        let moving0 = try capture("seed-record-motion-0", reduced: false, recipe: structure, elapsed: 0)
        let moving1 = try capture("seed-record-motion-1", reduced: false, recipe: structure, elapsed: 0.5)
        XCTAssertNotEqual(moving0, moving1)
        XCTAssertEqual(decorated, try capture("seed-record-motion-settled", reduced: false, recipe: structure, elapsed: 3))
        XCTAssertEqual(decorated, try capture("seed-record-reduced", recipe: structure, elapsed: 0.5))
        XCTAssertEqual(structure.digest, structureDigest)
        let active0 = try capture("seed-active-0", mode: .orbit, clock: 0, reduced: false)
        let active1 = try capture("seed-active-1", mode: .orbit, clock: 1, reduced: false)
        XCTAssertNotEqual(seed, active0); XCTAssertNotEqual(active0, active1)
        XCTAssertEqual(try capture("seed-active-reduced-0", mode: .orbit, clock: 0),
                       try capture("seed-active-reduced-1", mode: .orbit, clock: 1))
        for (name, frame) in [("body",24),("ball",66),("transition-start",90),("transition-mid",99),("seed-hold",120)] {
            _ = try capture(name, frame: frame)
        }
        XCTAssertEqual(seed, try capture("seed-return"), "Returning from body/ball must restore the identical resting Seed")

        let fallback = try XCTUnwrap(LiminalV008Runtime.fallbackSnapshot(asset: asset,
            progress: LiminalV008Runtime.orbProgress, seedColor: .original))
        XCTAssertEqual(try XCTUnwrap(SeedColorRendering.rgba(fallback)).bytes, artwork.bytes)
        XCTAssertNil(LiminalV008Runtime.fallbackSnapshot(asset: asset, progress: LiminalV008Runtime.orbProgress, structure: structure))
        XCTAssertNil(LiminalV008Runtime.fallbackSnapshot(asset: asset, progress: LiminalV008Runtime.standingProgress))
        try JSONSerialization.data(withJSONObject: ["schema": "archi-retained-seed-render/v1", "renderer": "production Metal",
            "manifestSHA256": digest, "retainedSeedSHA256": CompanionVisualAsset.hamptonGarnetDigest,
            "style": LiminalSeedStyle.revision, "comparedOpaquePixels": compared, "meanArtworkChannelError": meanError,
            "records": records, "structureDigest": structureDigest, "profileOpened": false,
            "installedAppChanged": false, "unityRuntimeExercised": false], options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("receipt.json"), options: .withoutOverwriting)
    }
}
