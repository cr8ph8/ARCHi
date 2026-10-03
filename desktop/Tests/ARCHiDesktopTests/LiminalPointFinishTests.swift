import AppKit
import XCTest
import simd
@testable import ARCHiDesktop

final class LiminalPointFinishTests: XCTestCase {
    /// Opt-in actual player test. Only synthetic presentation files are written;
    /// no installed application or personal CompanionStore is opened.
    @MainActor func testLiveCandidateFinishRoundTripAndRetraction() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let playerPath = env["ARCHI_LIMINAL_CANDIDATE_PLAYER"], let output = env["ARCHI_LIMINAL_CANDIDATE_OUTPUT"] else {
            throw XCTSkip("Set the separate v11 candidate player and evidence directory for the live bridge check")
        }
        let useLight = env["ARCHI_LIMINAL_CANDIDATE_LIGHT"] == "1"
        let playerURL = URL(fileURLWithPath: playerPath)
        let target = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bundle = try XCTUnwrap(Bundle(url: playerURL))
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "ARCHiLiminalPointAssetVersion") as? Int, useLight ? 7 : 6)
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "ARCHiLiminalPointFinishSHA256") as? String, LiminalPointFinish.expectedSHA256)
        let manifest = "9f89cc0914f537242d6cbc3d6ab4040c56f97f08872d954ed3cf3c33bb07e1ed"
        let asset = try LiminalPointAsset.load(packageURL: playerURL.appendingPathComponent("Contents/Resources/Data/StreamingAssets/LiminalV008"), expectedManifestSHA256: manifest)
        XCTAssertNotNil(asset.finish)
        if useLight {
            XCTAssertEqual(bundle.object(forInfoDictionaryKey: "ARCHiLiminalPointLightStyle") as? String, LiminalSurfaceLight.style)
            XCTAssertEqual(bundle.object(forInfoDictionaryKey: "ARCHiLiminalPointLightSHA256") as? String, LiminalSurfaceLight.expectedSHA256)
            XCTAssertNotNil(asset.surfaceLight)
        }
        let session = UUID().uuidString, origin = String(repeating: "a", count: 64)
        let node = LiminalPointStructure.Node(contentID: String(repeating: "b", count: 64), anchorID: asset.lowDetailIDs[0], applications: 3)
        let structure = LiminalPointStructure(schemaVersion: 1, recipeVersion: LiminalPointStructure.version,
            sessionID: session, originDigest: origin, manifestSHA256: manifest, evidenceDigest: String(repeating: "c", count: 64), detail: 4, nodes: [node])
        let knowledge = LiminalKnowledgeBindings.Sidecar(schemaVersion: 1, sessionID: session, originDigest: origin,
            manifestSHA256: manifest, graphDigest: String(repeating: "d", count: 64), bindings: [])
        // A helper app can be blocked on macOS Documents access. Keep its
        // synthetic live IPC outside protected folders; copy only receipts out.
        let bridge = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("liminal-review-bridge-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: bridge, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let path = bridge.appendingPathComponent("presentation.json")
        let knowledgeBytes = try knowledge.data()
        try knowledgeBytes.write(to: path.appendingPathExtension("knowledge"), options: .atomic)
        var revision = 0
        func publish(frame: Int, finished: Bool, decorated: Bool, lit: Bool = true, active: Bool = true) throws -> UnityPresentationSnapshot {
            revision += 1
            var value = UnityPresentationSnapshot(schemaVersion: 1, sessionID: session, revision: revision,
                originDigest: origin, displayName: "Synthetic Liminal finish review", body: "seed", appearance: "kin", cursor: "seed",
                seedAssetSHA256: CompanionVisualAsset.hamptonGarnetDigest, bodyAssetSHA256: CompanionVisualAsset.hamptonGarnetDigest,
                activity: "idle", lightMode: "rest", quiet: true, reduceMotion: true, visible: true, equippedFocusStaff: false,
                staffPalette: nil, staffCrown: nil, active: active, updatedAtUnix: Date().timeIntervalSince1970,
                sessionKind: "companion", destination: "companion", destinationRevision: 1,
                seedAppearance: "hamptonLiminal", seedColor: "garnet")
            value.pointPresentation = .init(schemaVersion: 1, assetID: "liminal-v008", manifestSHA256: manifest,
                progress: Double(frame - 1) / 119, motion: "reduced", color: "garnet", visible: active)
            value.pointKnowledgeSHA256 = LiminalKnowledgeBindings.sha256(knowledgeBytes)
            value.pointStructure = decorated ? structure : nil
            value.pointFinishSHA256 = finished ? LiminalPointFinish.expectedSHA256 : nil
            value.pointLightStyle = useLight && finished && lit ? LiminalSurfaceLight.style : nil
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(value).write(to: path, options: .atomic)
            return value
        }
        _ = try publish(frame: 108, finished: true, decorated: true)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["-archiNativePresentation", path.path, "-archiNativeSession", session,
                                   "-logFile", bridge.appendingPathComponent("player.log").path]
        let player = try await NSWorkspace.shared.openApplication(at: playerURL, configuration: configuration)
        defer { if !player.isTerminated { player.terminate() } }
        var results: [[String: Any]] = []
        for (name, frame, finished, decorated, lit) in [("seed",108,true,true,true),("ball",66,true,true,true),("beast",24,true,true,true),
                                                   ("light-withdrawn",24,true,true,false),
                                                   ("finish-withdrawn",24,false,true,false),("structure-withdrawn",24,false,false,false),
                                                   ("finish-restored",24,true,true,true)] {
            var snapshot = try publish(frame: frame, finished: finished, decorated: decorated, lit: lit)
            var ackData: Data?, acknowledged = false
            let deadline = Date().addingTimeInterval(25)
            while Date() < deadline && !player.isTerminated {
                if let data = try? Data(contentsOf: path.appendingPathExtension("ack")),
                   let ack = try? JSONDecoder().decode(UnityPresentationAcknowledgment.self, from: data),
                   ack.matches(snapshot, now: Date()),
                   let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let rendered = raw["pointRenderedProgress"] as? Double,
                   abs(rendered - Double(frame - 1) / 119) < 0.00001,
                   decorated || (ack.pointStructureDigest ?? "").isEmpty {
                    ackData = data; acknowledged = true; break
                }
                if Date().timeIntervalSince1970 - snapshot.updatedAtUnix > 1 {
                    snapshot = try publish(frame: frame, finished: finished, decorated: decorated, lit: lit)
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertTrue(acknowledged, "Actual candidate failed phase \(name)")
            if let ackData { try ackData.write(to: target.appendingPathComponent(name + "-ack.json")) }
            results.append(["phase":name,"frame":frame,"acknowledged":acknowledged,"finish":finished,"structure":decorated,"light":useLight && finished && lit])
        }
        _ = try publish(frame: 24, finished: false, decorated: false, active: false)
        try await Task.sleep(for: .milliseconds(800))
        player.terminate()
        for _ in 0..<100 {
            if player.isTerminated { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(player.isTerminated)
        if let log = try? Data(contentsOf: bridge.appendingPathComponent("player.log")) {
            try log.write(to: target.appendingPathComponent("player.log"))
        }
        if player.isTerminated { try? FileManager.default.removeItem(at: bridge) }
        try JSONSerialization.data(withJSONObject: ["synthetic":true,"player":playerPath,"finishSHA256":LiminalPointFinish.expectedSHA256,
            "surfaceLight":useLight,"phases":results,"ownedPlayerTerminated":player.isTerminated,"personalProfileOpened":false], options: [.prettyPrinted,.sortedKeys])
            .write(to: target.appendingPathComponent("receipt.json"))
    }

    func testDisplayWeightsHoldAuthoredPosesAndStayBounded() {
        for frame in 1...120 {
            let w = LiminalPointFinish.weights(frame: frame)
            XCTAssertEqual(w.x + w.y + w.z, 1, accuracy: 0.000001)
            XCTAssertTrue(w.x >= 0 && w.y >= 0 && w.z >= 0)
        }
        for frame in 1...24 { XCTAssertEqual(LiminalPointFinish.weights(frame: frame), SIMD3(1,0,0)) }
        for frame in 60...72 { XCTAssertEqual(LiminalPointFinish.weights(frame: frame), SIMD3(0,1,0)) }
        for frame in 108...120 { XCTAssertEqual(LiminalPointFinish.weights(frame: frame), SIMD3(0,0,1)) }
    }

    @MainActor func testQualifiedFinishPreservesSourceAndRendersAllForms() throws {
        let env = ProcessInfo.processInfo.environment
        guard let package = env["ARCHI_LIMINAL_LIVE_PACKAGE"], let finishPath = env["ARCHI_LIMINAL_FINISH"],
              let output = env["ARCHI_LIMINAL_FINISH_OUTPUT"] else {
            throw XCTSkip("Set source package, finish and output paths for real GPU acceptance")
        }
        let root = URL(fileURLWithPath: package), finishRoot = URL(fileURLWithPath: finishPath)
        let manifest = "9f89cc0914f537242d6cbc3d6ab4040c56f97f08872d954ed3cf3c33bb07e1ed"
        let original = try LiminalPointAsset.load(packageURL: root, expectedManifestSHA256: manifest)
        let asset = try LiminalPointAsset.load(packageURL: root, expectedManifestSHA256: manifest, finishURL: finishRoot)
        let finish = try XCTUnwrap(asset.finish)
        XCTAssertEqual(finish.digest, LiminalPointFinish.expectedSHA256)
        XCTAssertEqual(asset.artIDs, original.artIDs)
        let target = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let state = LiminalFormDevelopment.Snapshot(originDigest: String(repeating: "a", count: 64), nodes: (0..<12).map { i in
            .init(id: String(format: "%064x", i + 1), lessonIDs: ["synthetic-\(i)"], graphNodeIDs: ["lesson:synthetic-\(i)"], title: "Synthetic", applications: i < 6 ? 3 : 0)
        }, unavailableLessons: 0, duplicateLessons: 0, evidenceAvailable: true)
        let recipe = try XCTUnwrap(LiminalPointStructureTestFixtures.make(state, sessionID: "00000000-0000-4000-8000-000000000001",
            manifestSHA256: manifest, lowDetailIDs: asset.lowDetailIDs))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(recipe).write(to: target.appendingPathComponent("structure.json"))
        var frames: [[String: Any]] = [], probes: [[String: Any]] = []
        for (name, number) in [("beast",24),("ball",66),("seed",108)] {
            let progress = Double(number - 1) / 119
            let source = try original.framePair(progress: progress, detail: .high)
            let pair = try asset.framePair(progress: progress, detail: .high)
            XCTAssertEqual(source.lower.data, pair.lower.data, "Display mapping must not rewrite source samples")
            var seeds = 0, moved = 0, recorded = Set<UInt32>(), cohortProbe: Int?
            for rank in 0..<pair.lower.pointCount {
                let p = try XCTUnwrap(pair.lower.sample(at: rank))
                let display = finish.display(p, rank: rank, frame: number)
                let flags = finish.annotations.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: rank * 16 + 12, as: UInt32.self).littleEndian }
                if flags & 1 != 0 {
                    seeds += 1; cohortProbe = cohortProbe ?? rank
                    XCTAssertEqual(display.color, SIMD3(1,0.40,0.028))
                    XCTAssertEqual(display.emission, 0.9, accuracy: 0.00001)
                    let core = LiminalPointFinish.seed(frame: number)
                    XCTAssertEqual(simd_distance(display.position, SIMD3(core.x,core.y,core.z)), core.w, accuracy: 0.000001)
                } else { XCTAssertEqual(display.position, p.position) }
                if display.position != p.position { moved += 1 }
                if recorded.insert(flags).inserted {
                    probes.append(["frame":number,"rank":rank,"sourceID":asset.artIDs[rank],"flags":flags,
                        "position":[display.position.x,display.position.y,display.position.z],
                        "color":[display.color.x,display.color.y,display.color.z],"radius":display.radius,"emission":display.emission])
                }
            }
            XCTAssertEqual(seeds, 2114); XCTAssertEqual(moved, 2114)
            let low = try asset.framePair(progress: progress, detail: .low)
            let medium = try asset.framePair(progress: progress, detail: .medium)
            XCTAssertEqual(recipe.samples(frame: low.lower, asset: asset), recipe.samples(frame: medium.lower, asset: asset))
            let rank = try XCTUnwrap(cohortProbe)
            let seedRecipe = LiminalPointStructure(schemaVersion: 1, recipeVersion: LiminalPointStructure.version,
                sessionID: recipe.sessionID, originDigest: recipe.originDigest, manifestSHA256: manifest,
                evidenceDigest: recipe.evidenceDigest, detail: 1,
                nodes: [.init(contentID: String(repeating: "b", count: 64), anchorID: asset.artIDs[rank], applications: 0)])
            XCTAssertEqual(seedRecipe.samples(frame: low.lower, asset: asset).first?.position,
                finish.display(try XCTUnwrap(low.lower.sample(at: rank)), rank: rank, frame: number).position)
            let old = try LiminalMetalView.snapshotPNGData(asset: original, progress: progress, seedColor: .garnet)
            let base = try LiminalMetalView.snapshotPNGData(asset: asset, progress: progress, seedColor: .garnet)
            let decorated = try LiminalMetalView.snapshotPNGData(asset: asset, progress: progress, seedColor: .garnet, structure: recipe)
            XCTAssertNotEqual(base, old); XCTAssertNotEqual(base, decorated)
            try old.write(to: target.appendingPathComponent(name + "-before.png"))
            try base.write(to: target.appendingPathComponent(name + "-base.png"))
            try decorated.write(to: target.appendingPathComponent(name + "-structure.png"))
            frames.append(["pose":name,"frame":number,"sourceSHA256":LiminalPointAsset.digest(pair.lower.data),
                           "bodyPoints":pair.lower.pointCount,"seedPoints":seeds,"onlySeedMoved":true,"lodIdentical":true])
        }
        let ranks = Array(Set(probes.compactMap { $0["rank"] as? Int })).sorted()
        for number in [42, 90] {
            let pair = try asset.framePair(progress: Double(number - 1) / 119, detail: .high)
            for rank in ranks {
                let d = finish.display(try XCTUnwrap(pair.lower.sample(at: rank)), rank: rank, frame: number)
                probes.append(["frame":number,"rank":rank,"sourceID":asset.artIDs[rank],
                    "position":[d.position.x,d.position.y,d.position.z],"color":[d.color.x,d.color.y,d.color.z],
                    "radius":d.radius,"emission":d.emission])
            }
            try LiminalMetalView.snapshotPNGData(asset: asset, progress: Double(number - 1) / 119, seedColor: .garnet,
                structure: recipe).write(to: target.appendingPathComponent("transition-\(number).png"))
        }
        let first = try asset.framePair(progress: 23.0 / 119, detail: .low)
        let motifs = recipe.samples(frame: first.lower, asset: asset).enumerated().map {
            ["index":$0.offset,"position":[$0.element.position.x,$0.element.position.y,$0.element.position.z],"radius":$0.element.radius] as [String:Any]
        }
        let readback: [String:Any] = ["synthetic":true,"finishSHA256":finish.digest,"recipeDigest":recipe.digest,
                                    "frames":frames,"beastSamples":motifs,"finishSamples":probes]
        try JSONSerialization.data(withJSONObject: readback, options: [.prettyPrinted,.sortedKeys]).write(to: target.appendingPathComponent("readback.json"))
        // A package cannot approve its own finish, and corrupt annotations are refused.
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("liminal-finish-reject-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: bad) }
        try FileManager.default.copyItem(at: finishRoot, to: bad)
        try Data("{}".utf8).write(to: bad.appendingPathComponent("manifest.json"))
        XCTAssertThrowsError(try LiminalPointFinish.load(root: bad, sourceManifestSHA256: manifest, lodSHA256: asset.manifest.lod.ids.sha256))
        try Data(contentsOf: finishRoot.appendingPathComponent("manifest.json")).write(to: bad.appendingPathComponent("manifest.json"))
        var corrupt = finish.annotations; corrupt[0] ^= 1
        try corrupt.write(to: bad.appendingPathComponent("annotations.bin"))
        XCTAssertThrowsError(try LiminalPointFinish.load(root: bad, sourceManifestSHA256: manifest, lodSHA256: asset.manifest.lod.ids.sha256))
    }
}
