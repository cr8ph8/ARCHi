import AppKit
import XCTest
@testable import ARCHiDesktop

/// Opt-in production GPU captures. Never downloads an asset or changes a profile.
final class LiminalRenderedExpressionTests: XCTestCase {
    @MainActor func testQualifiedPackageExpressionCaptures() throws {
        let env = ProcessInfo.processInfo.environment
        guard let packagePath = env["ARCHI_LIMINAL_CAPTURE_PACKAGE"],
              let digest = env["ARCHI_LIMINAL_CAPTURE_DIGEST"],
              let outputPath = env["ARCHI_LIMINAL_CAPTURE_OUTPUT"] else {
            throw XCTSkip("Requires an explicitly supplied qualified package and new capture directory.")
        }
        let output = URL(fileURLWithPath: outputPath).standardizedFileURL
        let package = URL(fileURLWithPath: packagePath).resolvingSymlinksInPath()
        guard output.path.hasPrefix("/"), !output.path.hasPrefix(package.path + "/"),
              !FileManager.default.fileExists(atPath: output.path) else {
            XCTFail("Capture output must be new and outside the source package."); return
        }
        let asset = try LiminalPointAsset.load(packageURL: package, expectedManifestSHA256: digest)
        XCTAssertNotNil(CompanionVisualAsset.hamptonGarnetImage)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var records: [[String: Any]] = []
        var images: [String: Data] = [:]
        let cases: [(String, Int, KinLightMode, Double, Bool, Bool, CompanionSeedColor)] = [
            ("standing-rest", 24, .rest, 0, true, false, .original),
            ("curled-rest", 66, .rest, 0, true, false, .original),
            ("orb-rest", 108, .rest, 0, true, false, .original),
            ("orb-orbit-0", 108, .orbit, 0, false, false, .original),
            ("orb-orbit-1", 108, .orbit, 1, false, false, .original),
            ("orb-orbit-4", 108, .orbit, 4, false, false, .original),
            ("orb-pulse-0", 108, .pulse, 0, false, false, .original),
            ("orb-orbit-reduced", 108, .orbit, 1, true, false, .original),
            ("orb-inspection-empty", 108, .rest, 0, true, true, .original),
            ("orb-violet", 108, .rest, 0, true, false, .violet)
        ]
        for (name, frame, mode, clock, reduced, inspection, color) in cases {
            let data = try LiminalMetalView.snapshotPNGData(asset: asset, progress: Double(frame-1)/119,
                seedColor: color, lightMode: mode, unixTime: clock, reduceMotion: reduced, inspection: inspection)
            try LiminalPointAsset.validatePNG(data)
            try data.write(to: output.appendingPathComponent(name + ".png"), options: .withoutOverwriting)
            images[name] = data
            records.append(["name": name, "frame": frame, "mode": mode.rawValue, "unixTime": clock,
                "reduced": reduced, "inspection": inspection, "color": color.rawValue,
                "sha256": LiminalPointAsset.digest(data), "bytes": data.count])
        }
        XCTAssertNotEqual(images["orb-rest"], images["orb-orbit-0"])
        XCTAssertNotEqual(images["orb-orbit-0"], images["orb-orbit-1"])
        XCTAssertEqual(images["orb-orbit-0"], images["orb-orbit-4"])
        XCTAssertEqual(images["orb-orbit-0"], images["orb-orbit-reduced"])
        XCTAssertNotEqual(images["orb-inspection-empty"], images["orb-rest"])
        XCTAssertNotEqual(images["orb-violet"], images["orb-rest"])
        let report: [String: Any] = ["schema": "archi-liminal-expression-capture/v1", "manifestSHA256": digest,
            "renderer": "production LiminalMetalView.snapshotPNGData", "style": LiminalSeedStyle.revision,
            "expression": LiminalLightFrame.revision, "resolution": [512,512], "pointCount": 100_000,
            "records": records, "profileModified": false, "liveWalkthrough": false]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("receipt.json"), options: .withoutOverwriting)
    }
}
