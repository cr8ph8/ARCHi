import AppKit
import XCTest
@testable import ARCHiDesktop

final class LiminalSurfaceLightTests: XCTestCase {
    func testExpressionIsBoundedAndStaticClockIsExact() {
        for time in stride(from: -8.0, through: 8, by: 0.05) {
            let phase = LiminalSurfaceLight.phase(unixTime: time, moving: true)
            XCTAssertTrue((0.994...1.00601).contains(LiminalSurfaceLight.breath(phase: phase)))
            XCTAssertEqual(LiminalSurfaceLight.phase(unixTime: time, moving: false), 0)
        }
        XCTAssertEqual(LiminalSurfaceLight.phase(unixTime: .nan, moving: true), 0)
        XCTAssertEqual(LiminalSurfaceLight.phase(unixTime: .infinity, moving: true), 0)
    }
    @MainActor func testRealLightDataAndMetalCaptures() throws {
        let env = ProcessInfo.processInfo.environment
        guard let root = env["ARCHI_LIMINAL_LIVE_PACKAGE"], let finish = env["ARCHI_LIMINAL_FINISH"],
              let lights = env["ARCHI_LIMINAL_LIGHT"], let destination = env["ARCHI_LIMINAL_LIGHT_OUTPUT"] else {
            throw XCTSkip("Set source/finish/light and output paths for reviewed runtime qualification")
        }
        let manifest = "9f89cc0914f537242d6cbc3d6ab4040c56f97f08872d954ed3cf3c33bb07e1ed"
        let original = try LiminalPointAsset.load(packageURL: URL(fileURLWithPath: root), expectedManifestSHA256: manifest, finishURL: URL(fileURLWithPath: finish))
        let asset = try LiminalPointAsset.load(packageURL: URL(fileURLWithPath: root), expectedManifestSHA256: manifest,
            finishURL: URL(fileURLWithPath: finish), lightURL: URL(fileURLWithPath: lights))
        let light = try XCTUnwrap(asset.surfaceLight)
        XCTAssertEqual(light.digest,LiminalSurfaceLight.expectedSHA256)
        let output = URL(fileURLWithPath: destination)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var frameRecords: [[String:Any]] = []
        var lightSegments: [[String:Any]] = []
        for (name,frame) in [("beast",24),("ball",66),("seed",108),("transition-42",42),("transition-90",90)] {
            let progress = Double(frame - 1) / 119
            let source = try original.framePair(progress: progress, detail: .low)
            let finished = try asset.framePair(progress: progress, detail: .low)
            XCTAssertEqual(source.lower.data,finished.lower.data)
            let segments = light.segments(frame: frame)
            XCTAssertEqual(segments.count,1408)
            XCTAssertEqual(LiminalSurfaceLight.packed(segments).count,1408*64)
            XCTAssertTrue(segments.allSatisfy { segment in
                [segment.start.x,segment.start.y,segment.start.z,segment.end.x,segment.end.y,segment.end.z].allSatisfy { $0.isFinite && abs($0)<8 }
                && segment.u0 >= 0 && segment.u1 <= 1.00001 && segment.u1 >= segment.u0
            })
            let before = try LiminalMetalView.snapshotPNGData(asset: original, progress: progress, seedColor: .garnet)
            let after = try LiminalMetalView.snapshotPNGData(asset: asset, progress: progress, seedColor: .garnet)
            XCTAssertNotEqual(before,after)
            try before.write(to: output.appendingPathComponent(name+"-before.png"))
            try after.write(to: output.appendingPathComponent(name+"-base.png"))
            let a = try XCTUnwrap(SeedColorRendering.rgba(try XCTUnwrap(NSImage(data: before))))
            let b = try XCTUnwrap(SeedColorRendering.rgba(try XCTUnwrap(NSImage(data: after))))
            let beforeCovered = stride(from:3,to:a.bytes.count,by:4).filter { a.bytes[$0]>160 }.count
            let afterCovered = stride(from:3,to:b.bytes.count,by:4).filter { b.bytes[$0]>160 }.count
            XCTAssertGreaterThan(afterCovered,beforeCovered,"The visual upgrade must actually fill more of the porous body")
            let probes = segments.enumerated().filter { $0.offset % 31 == 0 || $0.offset % 44 == 0 }.map { i,s in
                ["frame":frame,"index":i,"color":[s.color.x,s.color.y,s.color.z],"start":[s.start.x,s.start.y,s.start.z],"end":[s.end.x,s.end.y,s.end.z],
                 "width":s.width,"intensity":s.intensity,"u0":s.u0,"u1":s.u1,"pathPhase":s.phase] as [String:Any]
            }
            lightSegments.append(contentsOf:probes)
            frameRecords.append(["frame":frame,"beforeCoveredPixels":beforeCovered,"afterCoveredPixels":afterCovered,
                "sourceSHA256":LiminalPointAsset.digest(source.lower.data),"segments":probes])
        }
        let progress = 23.0/119
        let movingA = try LiminalMetalView.snapshotPNGData(asset: asset, progress: progress, lightMode: .focus, unixTime: 0, reduceMotion: false)
        let movingB = try LiminalMetalView.snapshotPNGData(asset: asset, progress: progress, lightMode: .focus, unixTime: 1, reduceMotion: false)
        XCTAssertNotEqual(movingA,movingB)
        try movingA.write(to: output.appendingPathComponent("beast-active-0.png"))
        try movingB.write(to: output.appendingPathComponent("beast-active-1.png"))
        let stillA = try LiminalMetalView.snapshotPNGData(asset: asset, progress: progress, lightMode: .focus, unixTime: 0, reduceMotion: true)
        let stillB = try LiminalMetalView.snapshotPNGData(asset: asset, progress: progress, lightMode: .focus, unixTime: 1, reduceMotion: true)
        XCTAssertEqual(stillA,stillB)
        let inspectedA = try LiminalMetalView.snapshotPNGData(asset: asset, progress: progress, lightMode: .focus, unixTime: 0, reduceMotion: false, inspection: true)
        let inspectedB = try LiminalMetalView.snapshotPNGData(asset: asset, progress: progress, lightMode: .focus, unixTime: 1, reduceMotion: false, inspection: true)
        XCTAssertEqual(inspectedA,inspectedB)
        try JSONSerialization.data(withJSONObject:["style":LiminalSurfaceLight.style,"lightSHA256":light.digest,
            "synthetic":true,"frames":frameRecords,"lightSegments":lightSegments,"reducedMotionExact":true,"inspectionExact":true],options:[.prettyPrinted,.sortedKeys])
            .write(to:output.appendingPathComponent("light-readback.json"))
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("liminal-light-reject-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:bad) }
        try FileManager.default.copyItem(at:URL(fileURLWithPath:lights),to:bad)
        try Data("{}".utf8).write(to:bad.appendingPathComponent("curves.json"))
        XCTAssertThrowsError(try LiminalSurfaceLight.load(root:bad,manifestSHA256:manifest,lodSHA256:asset.manifest.lod.ids.sha256,lowIDs:asset.lowDetailIDs))
    }
}
