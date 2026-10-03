import XCTest
import simd
@testable import ARCHiDesktop

final class LiminalPointStructureTests: XCTestCase {
    let origin = String(repeating: "a", count: 64)
    let manifest = "9f89cc0914f537242d6cbc3d6ab4040c56f97f08872d954ed3cf3c33bb07e1ed"
    let session = "00000000-0000-4000-8000-000000000001"
    @MainActor func snapshot(_ count: Int = 12) -> LiminalFormDevelopment.Snapshot {
        .init(originDigest: origin, nodes: (0..<count).map { i in
            .init(id: String(format: "%064x", i + 1), lessonIDs: ["synthetic-\(i)"], graphNodeIDs: ["lesson:synthetic-\(i)"], title: "Not exported \(i)", applications: i < 6 ? 3 : 0)
        }, unavailableLessons: 0, duplicateLessons: 0, evidenceAvailable: true)
    }
    @MainActor func testStableAnchorIdentityAcrossSessionsAndDetailBudgets() throws {
        let ids = Array(UInt32(0)..<UInt32(50000))
        let first = try XCTUnwrap(LiminalPointStructure.make(snapshot(), sessionID: session, manifestSHA256: manifest, lowDetailIDs: ids))
        let other = try XCTUnwrap(LiminalPointStructure.make(snapshot(), sessionID: UUID().uuidString, manifestSHA256: manifest, lowDetailIDs: ids))
        XCTAssertEqual(first.nodes, other.nodes)
        XCTAssertNotEqual(first.digest, other.digest, "Wire ownership remains session-bound")
        XCTAssertEqual(first.particleCount, 168)
        XCTAssertEqual(Set(first.nodes.map(\.anchorID)).count, 12)
        let bytes = try JSONEncoder().encode(first)
        XCTAssertLessThan(bytes.count, 12000)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("Not exported"))
        XCTAssertNil(LiminalPointStructure.make(snapshot(), sessionID: session, manifestSHA256: manifest, lowDetailIDs: [1,1]))
    }
    func testGeometryAndImpulseAreBoundedAndStopIsExact() {
        for detail in 1...4 {
            for i in 0..<14 {
                let rest = LiminalPointStructure.offset(contentID: origin, applications: 8, index: i, detail: detail, span: 3)
                for t in [0.0, 0.1, 0.5, 1, 2.99] {
                    let moving = LiminalPointStructure.offset(contentID: origin, applications: 8, index: i, detail: detail, span: 3, elapsed: t)
                    XCTAssertLessThanOrEqual(simd_length(moving-rest), 3 * 0.035 + 0.00001)
                }
                for invalid in [Double.nan, .infinity, -1, 3, 100] {
                    XCTAssertEqual(rest, LiminalPointStructure.offset(contentID: origin, applications: 8, index: i, detail: detail, span: 3, elapsed: invalid))
                }
            }
        }
    }
    @MainActor func testWireValidationAndDigestBindExactSupport() throws {
        let recipe = try XCTUnwrap(LiminalPointStructure.make(snapshot(), sessionID: session, manifestSHA256: manifest, lowDetailIDs: Array(0..<50000)))
        let data = try JSONEncoder().encode(recipe)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["detail"] = 9
        XCTAssertFalse(try JSONDecoder().decode(LiminalPointStructure.self, from: JSONSerialization.data(withJSONObject: object)).isValid)
        object["detail"] = 4
        var nodes = object["nodes"] as! [[String: Any]]
        nodes[0]["applications"] = 4; object["nodes"] = nodes
        let changed = try JSONDecoder().decode(LiminalPointStructure.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(changed.isValid); XCTAssertNotEqual(recipe.digest, changed.digest)
        nodes[1] = nodes[0]; object["nodes"] = nodes
        XCTAssertFalse(try JSONDecoder().decode(LiminalPointStructure.self, from: JSONSerialization.data(withJSONObject: object)).isValid)
    }
    @MainActor func testHostedFailureRetiresPreviouslyRenderedStructureAndCanRecover() throws {
        let recipe = try XCTUnwrap(LiminalPointStructure.make(snapshot(), sessionID: session, manifestSHA256: manifest, lowDetailIDs: Array(0..<50000)))
        var failure = false
        let host = HostedPlayHost(assetDirectory: nil, pointSnapshotRenderer: { _,_,_ in nil },
            structureSnapshotRenderer: { _,_,_,_ in failure ? nil : Data([1,2,3]) })
        func update(_ structure: LiminalPointStructure?) {
            host.updateAppearance(form: .hamptonSeed, family: nil, reduceMotion: true,
                                  treatment: .liminalV008, pointStructure: structure)
        }
        update(recipe)
        let first = try XCTUnwrap(host.presentedAppearanceID)
        XCTAssertTrue(first.hasPrefix("liminal-live-"))
        XCTAssertLessThanOrEqual(first.count, 100, "The real hosted bridge bounds appearance IDs")
        failure = true
        update(nil)
        XCTAssertNotEqual(host.presentedAppearanceID, first)
        XCTAssertTrue(host.presentedAppearanceID?.hasSuffix("-render-unavailable") == true)
        XCTAssertLessThanOrEqual(host.presentedAppearanceID?.count ?? 101, 100)
        XCTAssertFalse(host.presentedAppearanceID?.contains(recipe.digest) == true)
        XCTAssertTrue(host.appearanceDeliveryDiagnostics.contains { $0.contains("retired-derived-appearance") })
        failure = false
        update(recipe)
        XCTAssertEqual(host.presentedAppearanceID, first)
    }
    @MainActor func testQualifiedFramesKeepBodyBytesAndLODAnchorsWhileRenderingRealMotifs() throws {
        guard let package = ProcessInfo.processInfo.environment["ARCHI_LIMINAL_LIVE_PACKAGE"],
              let output = ProcessInfo.processInfo.environment["ARCHI_LIMINAL_LIVE_OUTPUT"] else {
            throw XCTSkip("Set ARCHI_LIMINAL_LIVE_PACKAGE and ARCHI_LIMINAL_LIVE_OUTPUT for actual source/GPU qualification")
        }
        let asset = try LiminalPointAsset.load(packageURL: URL(fileURLWithPath: package), expectedManifestSHA256: manifest)
        let recipe = try XCTUnwrap(LiminalPointStructure.make(snapshot(), sessionID: session, manifestSHA256: manifest, lowDetailIDs: asset.lowDetailIDs))
        let target = URL(fileURLWithPath: output); try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        try enc.encode(recipe).write(to: target.appendingPathComponent("structure.json"))
        var comparisons: [[String: Any]] = []
        for (name, progress) in [("beast",23.0/119),("ball",65.0/119),("seed",107.0/119)] {
            let low = try asset.framePair(progress: progress, detail: .low)
            let before = LiminalPointAsset.digest(low.lower.data)
            let medium = try asset.framePair(progress: progress, detail: .medium)
            let a = recipe.samples(frame: low.lower, asset: asset), b = recipe.samples(frame: medium.lower, asset: asset)
            XCTAssertEqual(a, b, "Actual anchors must be identical across LOD")
            XCTAssertEqual(a.count, 168)
            XCTAssertEqual(before, LiminalPointAsset.digest(low.lower.data), "No original body or Seed sample was written")
            let base = try LiminalMetalView.snapshotPNGData(asset: asset, progress: progress, seedColor: .garnet)
            let decorated = try LiminalMetalView.snapshotPNGData(asset: asset, progress: progress, seedColor: .garnet, structure: recipe)
            XCTAssertNotEqual(base, decorated)
            try base.write(to: target.appendingPathComponent(name + "-base.png"))
            try decorated.write(to: target.appendingPathComponent(name + "-structure.png"))
            if name == "beast" {
                let pulse = try LiminalMetalView.snapshotPNGData(asset: asset, progress: progress, seedColor: .garnet, reduceMotion: false, structure: recipe, structureElapsed: 0.1)
                XCTAssertNotEqual(decorated, pulse)
                try pulse.write(to: target.appendingPathComponent("beast-response.png"))
            }
            comparisons.append(["pose":name,"frame":low.lower.frame,"baseSHA256":before,"bodyPoints":low.lower.pointCount,"motifPoints":a.count,"lodIdentical":true])
        }
        let first = try asset.framePair(progress: 23.0/119, detail: .low)
        let samples = recipe.samples(frame: first.lower, asset: asset)
        let parity = samples.enumerated().map { ["index":$0.offset,"position":[$0.element.position.x,$0.element.position.y,$0.element.position.z],"radius":$0.element.radius] as [String: Any] }
        try JSONSerialization.data(withJSONObject: ["recipeDigest":recipe.digest,"synthetic":true,"frames":comparisons,"beastSamples":parity],options:[.prettyPrinted,.sortedKeys]).write(to:target.appendingPathComponent("readback.json"))
    }
}
