import XCTest
import simd
@testable import ARCHiDesktop

/// Synthetic record fixtures still pass through the production graph allocator.
/// Tests must not recreate the retired independent content-to-art hash.
enum LiminalPointStructureTestFixtures {
    static func graph(_ snapshot: LiminalFormDevelopment.Snapshot) -> CompanionGraphSnapshot {
        .init(nodes: Set(snapshot.nodes.flatMap(\.graphNodeIDs)).sorted().map {
            .init(id: $0, title: "Synthetic retained record", subtitle: "Exact test record", kind: .lesson,
                  status: "Retained", details: [], target: .memory)
        }, edges: [], truncatedCount: 0)
    }

    @MainActor static func make(_ snapshot: LiminalFormDevelopment.Snapshot, sessionID: String,
                               manifestSHA256: String, lowDetailIDs: [UInt32]) throws -> LiminalPointStructure? {
        let graph = graph(snapshot)
        var allocator = try LiminalKnowledgeBindings(manifestSHA256: manifestSHA256, lowDetailIDs: lowDetailIDs)
        let sidecar = try allocator.project(graph, sessionID: sessionID, originDigest: snapshot.originDigest)
        return LiminalPointStructure.make(snapshot, graph: graph, bindings: sidecar, lowDetailIDs: lowDetailIDs)
    }
}

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
        let first = try XCTUnwrap(LiminalPointStructureTestFixtures.make(snapshot(), sessionID: session, manifestSHA256: manifest, lowDetailIDs: ids))
        let other = try XCTUnwrap(LiminalPointStructureTestFixtures.make(snapshot(), sessionID: UUID().uuidString, manifestSHA256: manifest, lowDetailIDs: ids))
        XCTAssertEqual(first.nodes, other.nodes)
        XCTAssertNotEqual(first.digest, other.digest, "Wire ownership remains session-bound")
        XCTAssertEqual(first.particleCount, 168)
        XCTAssertEqual(Set(first.nodes.map(\.anchorID)).count, 12)
        let bytes = try JSONEncoder().encode(first)
        XCTAssertLessThan(bytes.count, 12000)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("Not exported"))
        XCTAssertThrowsError(try LiminalPointStructureTestFixtures.make(snapshot(), sessionID: session, manifestSHA256: manifest, lowDetailIDs: [1,1]))
    }

    @MainActor func testEveryMotifUsesItsExactInspectedRecordAnchorIncludingTransportRebinding() throws {
        let state = snapshot(), graph = LiminalPointStructureTestFixtures.graph(snapshot())
        let ids = Array(UInt32(0)..<UInt32(50000))
        var allocator = try LiminalKnowledgeBindings(manifestSHA256: manifest, lowDetailIDs: ids)
        let sidecar = try allocator.project(graph, sessionID: session, originDigest: origin)
        let recipe = try XCTUnwrap(LiminalPointStructure.make(state, graph: graph, bindings: sidecar, lowDetailIDs: ids))
        for node in recipe.nodes {
            let content = try XCTUnwrap(state.nodes.first { $0.id == node.contentID })
            let inspected = try XCTUnwrap(sidecar.bindings.first { content.graphNodeIDs.contains($0.nodeID) })
            XCTAssertEqual(node.anchorID, inspected.anchorID)
            XCTAssertTrue(inspected.particleIDs.contains(node.anchorID))
        }
        let transport = try sidecar.forSession(UUID().uuidString)
        let world = try XCTUnwrap(LiminalPointStructure.make(state, graph: graph, bindings: transport, lowDetailIDs: ids))
        XCTAssertEqual(world.nodes, recipe.nodes)
        XCTAssertNotEqual(world.digest, recipe.digest, "Transport sessions remain isolated despite shared native art IDs")
    }

    @MainActor func testCorrectionAndRemovalRetireMotifsWithoutReassigningInspectionParticles() throws {
        let state = snapshot(2), graph = LiminalPointStructureTestFixtures.graph(snapshot(2))
        let ids = Array(UInt32(0)..<UInt32(5000))
        var allocator = try LiminalKnowledgeBindings(manifestSHA256: manifest, lowDetailIDs: ids)
        let original = try allocator.project(graph, sessionID: session, originDigest: origin)
        let before = try XCTUnwrap(LiminalPointStructure.make(state, graph: graph, bindings: original, lowDetailIDs: ids))
        var records = graph.nodes
        records[0].presentationState = .corrected
        records[0].evidenceTrail = [.init(id: "correction-v2", stage: .correction, summary: "Source revision changed")]
        let corrected = CompanionGraphSnapshot(nodes: records, edges: [], truncatedCount: 0)
        XCTAssertNil(LiminalPointStructure.make(state, graph: corrected, bindings: original, lowDetailIDs: ids))
        let checked = try allocator.project(corrected, sessionID: session, originDigest: origin)
        let after = try XCTUnwrap(LiminalPointStructure.make(state, graph: corrected, bindings: checked, lowDetailIDs: ids))
        XCTAssertEqual(after.nodes.map(\.contentID), [state.nodes[1].id])
        XCTAssertEqual(after.nodes.first?.anchorID, before.nodes.last?.anchorID)
        XCTAssertNotEqual(after.evidenceDigest, before.evidenceDigest)
        XCTAssertEqual(checked.bindings, original.bindings)
        let retired = try XCTUnwrap(original.bindings.first { $0.nodeID == records[0].id })
        let added = CompanionGraphNode(id: "new-record", title: "New", subtitle: "", kind: .knowledge,
                                      status: "Reviewed", details: [], target: .memory)
        let nextGraph = CompanionGraphSnapshot(nodes: [records[1], added], edges: [], truncatedCount: 0)
        let next = try allocator.project(nextGraph, sessionID: session, originDigest: origin)
        let retained = try XCTUnwrap(LiminalPointStructure.make(state, graph: nextGraph, bindings: next, lowDetailIDs: ids))
        XCTAssertEqual(retained.nodes, after.nodes)
        XCTAssertTrue(Set(retired.particleIDs).isDisjoint(with: next.bindings.flatMap(\.particleIDs)))
    }

    @MainActor func testAliasesShareOneMotifAndConflictingAliasesNeverGetSummed() throws {
        func state(_ nodes: [LiminalFormDevelopment.Node]) -> LiminalFormDevelopment.Snapshot {
            .init(originDigest: origin, nodes: nodes, unavailableLessons: 0, duplicateLessons: 0, evidenceAvailable: true)
        }
        let first = LiminalFormDevelopment.Node(id: String(repeating: "b", count: 64), lessonIDs: [],
            graphNodeIDs: ["record-b", "record-a", "record-a"], title: "Shared content", applications: 2)
        let second = LiminalFormDevelopment.Node(id: String(repeating: "c", count: 64), lessonIDs: [],
            graphNodeIDs: ["record-a"], title: "Conflicting content", applications: 3)
        let graph = LiminalPointStructureTestFixtures.graph(state([first]))
        let ids = Array(UInt32(0)..<UInt32(5000))
        var allocator = try LiminalKnowledgeBindings(manifestSHA256: manifest, lowDetailIDs: ids)
        let sidecar = try allocator.project(graph, sessionID: session, originDigest: origin)
        let single = try XCTUnwrap(LiminalPointStructure.make(state([first]), graph: graph, bindings: sidecar, lowDetailIDs: ids))
        XCTAssertEqual(single.nodes.count, 1)
        XCTAssertEqual(single.nodes.first?.anchorID, sidecar.bindings.first { $0.nodeID == "record-a" }?.anchorID)
        let conflict = try XCTUnwrap(LiminalPointStructure.make(state([first, second]), graph: graph, bindings: sidecar, lowDetailIDs: ids))
        XCTAssertEqual(conflict.nodes.count, 1)
        XCTAssertEqual(conflict.nodes.first?.anchorID, sidecar.bindings.first { $0.nodeID == "record-b" }?.anchorID)
        XCTAssertEqual(conflict.nodes.first?.applications, 2)
        let duplicate = try XCTUnwrap(LiminalPointStructure.make(state([first, first]), graph: graph, bindings: sidecar, lowDetailIDs: ids))
        XCTAssertTrue(duplicate.nodes.isEmpty)
        XCTAssertEqual(duplicate.detail, 0)
        XCTAssertEqual(sidecar.bindings.count, 2, "Deduplicating motifs cannot remove inspected records")
    }

    @MainActor func testMalformedOrStaleSidecarCannotSupplyAnyMotif() throws {
        let state = snapshot(2), graph = LiminalPointStructureTestFixtures.graph(snapshot(2))
        let ids = Array(UInt32(0)..<UInt32(5000))
        var allocator = try LiminalKnowledgeBindings(manifestSHA256: manifest, lowDetailIDs: ids)
        let sidecar = try allocator.project(graph, sessionID: session, originDigest: origin)
        func altered(schema: Int = 1, sessionID: String? = nil, owner: String? = nil,
                     asset: String? = nil, graphDigest: String? = nil,
                     records: [LiminalKnowledgeBindings.Binding]? = nil) -> LiminalKnowledgeBindings.Sidecar {
            .init(schemaVersion: schema, sessionID: sessionID ?? sidecar.sessionID, originDigest: owner ?? sidecar.originDigest,
                  manifestSHA256: asset ?? sidecar.manifestSHA256, graphDigest: graphDigest ?? sidecar.graphDigest,
                  bindings: records ?? sidecar.bindings)
        }
        let a = sidecar.bindings[0], b = sidecar.bindings[1]
        let invalid = [
            altered(schema: 2), altered(sessionID: "invalid"), altered(owner: String(repeating: "f", count: 64)),
            altered(asset: "v002"), altered(graphDigest: String(repeating: "e", count: 64)),
            altered(records: [a, a]),
            altered(records: [a, .init(nodeID: b.nodeID, anchorID: a.anchorID, particleIDs: a.particleIDs)]),
            altered(records: [.init(nodeID: "absent", anchorID: a.anchorID, particleIDs: a.particleIDs)]),
            altered(records: [.init(nodeID: a.nodeID, anchorID: 799_999, particleIDs: a.particleIDs)]),
            altered(records: [.init(nodeID: a.nodeID, anchorID: 799_999, particleIDs: [799_999])]),
            altered(records: [.init(nodeID: a.nodeID, anchorID: a.anchorID, particleIDs: [a.anchorID, a.anchorID])]),
            altered(records: [.init(nodeID: a.nodeID, anchorID: a.anchorID, particleIDs: [])]),
            altered(records: Array(repeating: a, count: CompanionGraph.maximumNodes + 1))
        ]
        for candidate in invalid {
            XCTAssertNil(LiminalPointStructure.make(state, graph: graph, bindings: candidate, lowDetailIDs: ids))
        }
        XCTAssertNil(LiminalPointStructure.make(state, graph: graph, bindings: sidecar, lowDetailIDs: [1, 1]))
        let changed = CompanionGraphSnapshot(nodes: [graph.nodes[0]], edges: [], truncatedCount: 0)
        XCTAssertNil(LiminalPointStructure.make(state, graph: changed, bindings: sidecar, lowDetailIDs: ids))
    }

    @MainActor func testExhaustedInspectionProducesNoInventedGrowthAnchor() throws {
        let state = snapshot(2), graph = LiminalPointStructureTestFixtures.graph(snapshot(2))
        let ids = Array(UInt32(0)..<UInt32(32))
        var allocator = try LiminalKnowledgeBindings(manifestSHA256: manifest, lowDetailIDs: ids)
        let unavailable = try allocator.projectForPresentation(graph, sessionID: session, originDigest: origin)
        XCTAssertNotNil(unavailable.inspectionUnavailableReason)
        let recipe = try XCTUnwrap(LiminalPointStructure.make(state, graph: graph, bindings: unavailable.sidecar, lowDetailIDs: ids))
        XCTAssertTrue(recipe.isValid)
        XCTAssertEqual(recipe.particleCount, 0)
        XCTAssertEqual(recipe.detail, 0)
    }

    @MainActor func testAllInspectionRecordsRemainWhileMotifsRespectVisibleDetailLimit() throws {
        let state = snapshot(30), graph = LiminalPointStructureTestFixtures.graph(snapshot(30))
        let ids = Array(UInt32(0)..<UInt32(5000))
        var allocator = try LiminalKnowledgeBindings(manifestSHA256: manifest, lowDetailIDs: ids)
        let sidecar = try allocator.project(graph, sessionID: session, originDigest: origin)
        let recipe = try XCTUnwrap(LiminalPointStructure.make(state, graph: graph, bindings: sidecar, lowDetailIDs: ids))
        XCTAssertEqual(recipe.nodes.count, LiminalFormDevelopment.maximumVisibleNodes)
        XCTAssertEqual(sidecar.bindings.count, 30)
        XCTAssertEqual(Set(recipe.nodes.map(\.anchorID)).count, recipe.nodes.count)
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
        let recipe = try XCTUnwrap(LiminalPointStructureTestFixtures.make(snapshot(), sessionID: session, manifestSHA256: manifest, lowDetailIDs: Array(0..<50000)))
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
        let recipe = try XCTUnwrap(LiminalPointStructureTestFixtures.make(snapshot(), sessionID: session, manifestSHA256: manifest, lowDetailIDs: Array(0..<50000)))
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
        let recipe = try XCTUnwrap(LiminalPointStructureTestFixtures.make(snapshot(), sessionID: session, manifestSHA256: manifest, lowDetailIDs: asset.lowDetailIDs))
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
