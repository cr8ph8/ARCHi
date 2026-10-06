import XCTest
@testable import ARCHiDesktop

final class CompanionParticleSceneTests: XCTestCase {
    private let origin = String(repeating: "a", count: 64)
    private let content = String(repeating: "b", count: 64)
    private let support = String(repeating: "c", count: 64)

    // Same owner-shaped graph fixture used by KnowledgeParticleFieldTests.
    private func node(_ id: String, _ kind: CompanionGraphKind = .knowledge,
                      state: CompanionGraphPresentationState = .recorded) -> CompanionGraphNode {
        var result = CompanionGraphNode(id: id, title: "Private title", subtitle: "Private subtitle", kind: kind,
            status: "Private status", details: [.init(label: "Your note", value: "Private body")], target: .memory)
        result.presentationState = state
        return result
    }
    private var graph: CompanionGraphSnapshot {
        .init(nodes: [node("root", .companion), node("source", .source), node("concept"), node("lesson", .lesson)],
              edges: [.init(id: "link-1", source: "concept", target: "source", label: "source passage"),
                      .init(id: "link-2", source: "lesson", target: "concept", label: "retained from")], truncatedCount: 2)
    }
    private func developmentNode(_ aliases: [String], contentID: String? = nil, count: Int = 2,
                                 supportDigest: String? = nil) -> LiminalFormDevelopment.Node {
        .init(id: contentID ?? content, lessonIDs: [], graphNodeIDs: aliases, title: "Retained knowledge",
              applications: min(8, count), reviewedApplicationCount: count, supportDigest: supportDigest ?? support)
    }
    private func development(_ nodes: [LiminalFormDevelopment.Node], originDigest: String? = nil,
                             available: Bool = true) -> LiminalFormDevelopment.Snapshot {
        .init(originDigest: originDigest ?? origin, nodes: nodes, unavailableLessons: 0,
              duplicateLessons: 0, evidenceAvailable: available)
    }

    @MainActor func testFullGraphAndExactFieldSurviveDeduplicatedDevelopment() throws {
        let dev = development([developmentNode(["concept", "lesson", "absent"])])
        let scene = try XCTUnwrap(CompanionParticleScene.build(originDigest: origin, graph: graph, development: dev))
        XCTAssertEqual(scene.graph, graph)
        XCTAssertEqual(scene.graphDigest, LiminalKnowledgeBindings.digest(graph))
        XCTAssertEqual(scene.field.particles, KnowledgeParticleField(snapshot: graph).particles)
        XCTAssertEqual(scene.field.edges, KnowledgeParticleField(snapshot: graph).edges)
        XCTAssertEqual(scene.field.omittedCount, graph.truncatedCount)
        XCTAssertEqual(Set(scene.field.particles.map(\.nodeID)), Set(graph.nodes.map(\.id)))
        XCTAssertEqual(Set(scene.growthByRecordID.keys), ["concept", "lesson"])
        XCTAssertEqual(scene.growthByRecordID["concept"], scene.growthByRecordID["lesson"])
        XCTAssertEqual(scene.growthByRecordID["concept"]?.contentID, content)
        XCTAssertEqual(scene.growthByRecordID["concept"]?.reviewedApplicationCount, 2)
        XCTAssertNil(scene.growthByRecordID["absent"])
    }

    @MainActor func testMissingForeignOrUnavailableDevelopmentDoesNotRemoveRecords() throws {
        let nodes = [developmentNode(["concept"])]
        for dev in [nil, development(nodes, originDigest: String(repeating: "d", count: 64)),
                    development(nodes, available: false)] {
            let scene = try XCTUnwrap(CompanionParticleScene.build(originDigest: origin, graph: graph, development: dev))
            XCTAssertEqual(scene.graph, graph)
            XCTAssertEqual(scene.field.particles.count, graph.nodes.count)
            XCTAssertTrue(scene.growthByRecordID.isEmpty)
        }
    }

    @MainActor func testAmbiguousAliasesSuppressOnlyConflictedGrowthAndDuplicateContentFailsClosed() throws {
        let first = developmentNode(["concept", "concept", "lesson"])
        let second = developmentNode(["concept"], contentID: String(repeating: "d", count: 64))
        let scene = try XCTUnwrap(CompanionParticleScene.build(originDigest: origin, graph: graph,
            development: development([first, second])))
        XCTAssertNil(scene.growthByRecordID["concept"])
        XCTAssertEqual(scene.growthByRecordID["lesson"]?.contentID, content)
        XCTAssertEqual(scene.graph.nodes.count, graph.nodes.count)
        let duplicate = try XCTUnwrap(CompanionParticleScene.build(originDigest: origin, graph: graph,
            development: development([first, first])))
        XCTAssertTrue(duplicate.growthByRecordID.isEmpty)
        XCTAssertEqual(duplicate.graph, graph)
    }

    @MainActor func testUnavailableRecordsAndOldVersionAliasesNeverGainGrowth() throws {
        let states: [CompanionGraphPresentationState] = [.historical, .candidate, .needsReview, .unavailable, .withdrawn, .corrected]
        for state in states {
            let snapshot = CompanionGraphSnapshot(nodes: [node("concept-v2", state: state), node("lesson", .lesson)], edges: [], truncatedCount: 0)
            let scene = try XCTUnwrap(CompanionParticleScene.build(originDigest: origin, graph: snapshot,
                development: development([developmentNode(["concept-v1", "concept-v2", "lesson"])])))
            XCTAssertEqual(scene.growthByRecordID.keys.sorted(), ["lesson"])
            XCTAssertEqual(scene.graph, snapshot)
        }
    }

    @MainActor func testFingerprintTracksExactSupportBeyondArtisticCapAndIgnoresOrdering() throws {
        let dev = development([developmentNode(["concept", "lesson"], count: 9)])
        let scene = try XCTUnwrap(CompanionParticleScene.build(originDigest: origin, graph: graph, development: dev))
        XCTAssertEqual(scene.growthByRecordID["concept"]?.applications, 8)
        XCTAssertEqual(scene.growthByRecordID["concept"]?.reviewedApplicationCount, 9)
        XCTAssertEqual(scene.digest, scene.fingerprint)
        XCTAssertEqual(scene.digest, CompanionParticleScene.fingerprint(originDigest: origin, graph: graph, development: dev))
        let reordered = CompanionGraphSnapshot(nodes: graph.nodes.reversed(), edges: graph.edges.reversed(), truncatedCount: 2)
        XCTAssertEqual(scene.digest, CompanionParticleScene.fingerprint(originDigest: origin, graph: reordered,
            development: development([developmentNode(["lesson", "concept"], count: 9)])))
        for updated in [development([developmentNode(["concept", "lesson"], count: 10)]),
                        development([developmentNode(["concept", "lesson"], count: 9, supportDigest: String(repeating: "e", count: 64))]),
                        development(dev.nodes, available: false)] {
            XCTAssertNotEqual(scene.digest, CompanionParticleScene.fingerprint(originDigest: origin, graph: graph, development: updated))
        }
        XCTAssertEqual(scene, CompanionParticleScene.build(originDigest: origin, graph: graph, development: dev))
    }

    @MainActor func testCurrentnessRejectsChangedIdentityRecordEvidenceAndRelationships() throws {
        let scene = try XCTUnwrap(CompanionParticleScene.build(originDigest: origin, graph: graph, development: nil))
        XCTAssertTrue(scene.isCurrent(graph: graph, originDigest: origin, sessionID: scene.sessionID))
        XCTAssertFalse(scene.isCurrent(graph: graph, originDigest: String(repeating: "d", count: 64), sessionID: scene.sessionID))
        var changed = graph.nodes
        changed[2].evidenceTrail = [.init(id: "correction", stage: .correction, summary: "Exact source corrected")]
        var edges = graph.edges
        edges[0].relationship = .contradicts
        for updated in [CompanionGraphSnapshot(nodes: changed, edges: graph.edges, truncatedCount: 2),
                        .init(nodes: graph.nodes, edges: edges, truncatedCount: 2),
                        .init(nodes: Array(graph.nodes.prefix(2)), edges: [], truncatedCount: 2),
                        .init(nodes: graph.nodes, edges: graph.edges, truncatedCount: 3)] {
            XCTAssertFalse(scene.isCurrent(graph: updated, originDigest: origin, sessionID: scene.sessionID))
        }
    }

    @MainActor func testSharedSelectionResolvesOnlyCurrentOriginVersionAndRecord() throws {
        let scene = try XCTUnwrap(CompanionParticleScene.build(originDigest: origin, graph: graph, development: nil))
        let selection = try XCTUnwrap(CompanionParticleSelection(nodeID: "concept", in: scene))
        XCTAssertEqual(selection.selectedID(in: scene), "concept")
        XCTAssertNil(CompanionParticleSelection(nodeID: "absent", in: scene))
        let foreign = try XCTUnwrap(CompanionParticleScene.build(originDigest: String(repeating: "d", count: 64),
                                                                graph: graph, development: nil))
        XCTAssertNil(selection.selectedID(in: foreign))
        var revised = graph.nodes
        revised[2].evidenceTrail = [.init(id: "revision-2", stage: .correction, summary: "Source version corrected")]
        let changed = CompanionGraphSnapshot(nodes: revised, edges: graph.edges, truncatedCount: graph.truncatedCount)
        let removed = CompanionGraphSnapshot(nodes: graph.nodes.filter { $0.id != "concept" },
            edges: graph.edges.filter { $0.source != "concept" && $0.target != "concept" }, truncatedCount: graph.truncatedCount)
        for snapshot in [changed, removed] {
            let current = try XCTUnwrap(CompanionParticleScene.build(originDigest: origin, graph: snapshot, development: nil))
            XCTAssertNil(selection.selectedID(in: current))
        }
    }

    @MainActor func testSessionRetiresCallbacksWithoutChangingContentAndUnrelatedRecordsPreserveSelection() throws {
        let session = UUID().uuidString
        let scene = try XCTUnwrap(CompanionParticleScene.build(originDigest: origin, graph: graph,
            development: nil, sessionID: session))
        let selection = try XCTUnwrap(CompanionParticleSelection(nodeID: "concept", in: scene))
        let next = try XCTUnwrap(CompanionParticleScene.build(originDigest: origin, graph: graph,
            development: nil, sessionID: UUID().uuidString))
        XCTAssertEqual(scene.digest, next.digest, "A transient session must not change content identity")
        XCTAssertEqual(scene.field.particles, next.field.particles)
        XCTAssertNotEqual(scene, next)
        XCTAssertFalse(scene.isCurrent(graph: next.graph, originDigest: next.originDigest, sessionID: next.sessionID))
        XCTAssertNil(selection.selectedID(in: next))

        let expandedGraph = CompanionGraphSnapshot(nodes: graph.nodes + [node("unrelated")],
            edges: graph.edges + [.init(id: "new-link", source: "source", target: "unrelated", label: "source passage")],
            truncatedCount: graph.truncatedCount)
        let expanded = try XCTUnwrap(CompanionParticleScene.build(originDigest: origin, graph: expandedGraph,
            development: nil, sessionID: session))
        XCTAssertEqual(selection.selectedID(in: expanded), "concept", "The exact selected record is unchanged")
        XCTAssertFalse(scene.isCurrent(graph: expanded.graph, originDigest: origin, sessionID: session),
            "Preserving a highlight must not make old interaction callbacks current")
        var retargeted = expandedGraph.nodes
        retargeted[2] = CompanionGraphNode(id: "concept", title: "Private title", subtitle: "Private subtitle",
            kind: .knowledge, status: "Private status", details: [.init(label: "Your note", value: "Private body")],
            target: .context)
        let changedTarget = try XCTUnwrap(CompanionParticleScene.build(originDigest: origin,
            graph: .init(nodes: retargeted, edges: expandedGraph.edges, truncatedCount: graph.truncatedCount),
            development: nil, sessionID: session))
        XCTAssertNil(selection.selectedID(in: changedTarget), "An ID alone must not preserve a changed target")
    }

    @MainActor func testInvalidTopologyIsRejectedWithoutQuietlyDroppingRecords() {
        let badEdge = CompanionGraphEdge(id: "bad", source: "absent", target: "concept", label: "invalid")
        let oversizedNodes = (0...CompanionGraph.maximumNodes).map { node("node-\($0)") }
        let oversizedEdges = (0...CompanionGraph.maximumEdges).map {
            CompanionGraphEdge(id: "edge-\($0)", source: "source", target: "concept", label: "recorded")
        }
        let invalid: [CompanionGraphSnapshot] = [
            .init(nodes: graph.nodes + [graph.nodes[0]], edges: graph.edges, truncatedCount: 0),
            .init(nodes: graph.nodes, edges: graph.edges + [graph.edges[0]], truncatedCount: 0),
            .init(nodes: graph.nodes, edges: [badEdge], truncatedCount: 0),
            .init(nodes: oversizedNodes, edges: [], truncatedCount: 0),
            .init(nodes: graph.nodes, edges: oversizedEdges, truncatedCount: 0),
            .init(nodes: [node("bad\nID")], edges: [], truncatedCount: 0),
            .init(nodes: graph.nodes, edges: graph.edges, truncatedCount: -1)
        ]
        for snapshot in invalid {
            XCTAssertNil(CompanionParticleScene.build(originDigest: origin, graph: snapshot, development: nil))
            XCTAssertNil(CompanionParticleScene.fingerprint(originDigest: origin, graph: snapshot, development: nil))
        }
        XCTAssertNil(CompanionParticleScene.build(originDigest: "unbound", graph: graph, development: nil))
    }

    @MainActor func testEveryBoundedGraphRecordAndEdgeRemainsBeyondDevelopmentLimit() throws {
        let nodes = (0..<CompanionGraph.maximumNodes).map { node("node-\($0)", CompanionGraphKind.allCases[$0 % CompanionGraphKind.allCases.count]) }
        let edges = (0..<CompanionGraph.maximumEdges).map {
            CompanionGraphEdge(id: "edge-\($0)", source: "node-\($0 % nodes.count)",
                               target: "node-\(($0 + 1) % nodes.count)", label: "recorded")
        }
        let graph = CompanionGraphSnapshot(nodes: nodes, edges: edges, truncatedCount: 7)
        let scene = try XCTUnwrap(CompanionParticleScene.build(originDigest: origin, graph: graph,
            development: development([developmentNode(["node-0"])])))
        XCTAssertEqual(scene.graph, graph)
        XCTAssertEqual(scene.field.particles.count, CompanionGraph.maximumNodes)
        XCTAssertEqual(scene.field.edges.count, CompanionGraph.maximumEdges)
        XCTAssertEqual(scene.field.omittedCount, 7)
        XCTAssertEqual(scene.growthByRecordID.count, 1)
    }

    @MainActor func testMalformedDevelopmentCannotIntroduceExperience() throws {
        let invalidNodes: [[LiminalFormDevelopment.Node]] = [
            [developmentNode(["concept"], count: -1)],
            [developmentNode(["concept"], count: EvolutionStore.maximumUsefulReceipts + 1)],
            [developmentNode(["concept"], contentID: "invented")],
            [developmentNode(["concept"], supportDigest: "unchecked")],
            Array(repeating: developmentNode(["concept"]), count: LiminalFormDevelopment.maximumNodes + 1)
        ]
        for nodes in invalidNodes {
            let scene = try XCTUnwrap(CompanionParticleScene.build(originDigest: origin, graph: graph, development: development(nodes)))
            XCTAssertTrue(scene.growthByRecordID.isEmpty)
            XCTAssertEqual(scene.graph, graph)
        }
    }
}
