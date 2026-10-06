import Foundation

/// One disposable native presentation over the current owner's graph. The Seed
/// and memory map use these same record IDs and field; neither owns new memory.
struct CompanionParticleScene: Equatable {
    struct Growth: Equatable, Sendable {
        let contentID: String
        let applications: Int
        let reviewedApplicationCount: Int
    }

    let graph: CompanionGraphSnapshot
    let field: KnowledgeParticleField
    let originDigest: String
    /// Transient presentation ownership. Kept separate from the content digest
    /// so reopening the same records does not change artwork/cache identity.
    let sessionID: String
    let graphDigest: String
    /// Includes exact graph metadata and current development support, not layout alone.
    let digest: String
    var fingerprint: String { digest }
    /// Aliases decorate existing graph records. Counts must not be summed across
    /// aliases: several records can refer to the same retained content.
    let growthByRecordID: [String: Growth]

    private init(originDigest: String, graph: CompanionGraphSnapshot, inputs: Inputs, sessionID: String) {
        self.originDigest = originDigest
        self.sessionID = sessionID
        self.graph = graph
        graphDigest = inputs.graphDigest
        digest = inputs.digest
        growthByRecordID = inputs.growth
        field = KnowledgeParticleField(topology: inputs.topology)
    }

    @MainActor static func build(originDigest: String, graph: CompanionGraphSnapshot,
                                 development: LiminalFormDevelopment.Snapshot?, sessionID: String = "") -> Self? {
        // Empty belongs only to standalone synthetic projections. Live callers
        // supply the existing owner's UUID and validate it on every callback.
        guard sessionID.isEmpty || UUID(uuidString: sessionID) != nil,
              let inputs = inputs(originDigest: originDigest, graph: graph, development: development) else { return nil }
        return Self(originDigest: originDigest, graph: graph, inputs: inputs, sessionID: sessionID)
    }

    /// A view-local cache can check support without recomputing particle coordinates.
    @MainActor static func fingerprint(originDigest: String, graph: CompanionGraphSnapshot,
                                       development: LiminalFormDevelopment.Snapshot?) -> String? {
        inputs(originDigest: originDigest, graph: graph, development: development)?.digest
    }

    /// Dense authored particles need the same evidence projection, not another
    /// force-layout pass. Keep the validation and growth meanings in one place.
    @MainActor static func developmentProjection(originDigest: String, graph: CompanionGraphSnapshot,
                                                 development: LiminalFormDevelopment.Snapshot?)
        -> (growth: [String: Growth], digest: String)? {
        guard let value = inputs(originDigest: originDigest, graph: graph, development: development) else { return nil }
        return (value.growth, value.digest)
    }

    /// Recheck the current owner before resolving a pick. To revalidate growth
    /// as well, compare fingerprint with the owner's fresh development snapshot.
    func isCurrent(graph: CompanionGraphSnapshot, originDigest: String, sessionID: String) -> Bool {
        self.sessionID == sessionID && self.originDigest == originDigest && Self.validTopology(originDigest: originDigest, graph: graph) != nil
            && graphDigest == LiminalKnowledgeBindings.digest(graph)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sessionID == rhs.sessionID && lhs.digest == rhs.digest && lhs.graph == rhs.graph
            && lhs.growthByRecordID == rhs.growthByRecordID
    }

    private struct Inputs {
        let topology: KnowledgeParticleField.Topology
        let graphDigest: String
        let digest: String
        let growth: [String: Growth]
    }

    private static func validTopology(originDigest: String, graph: CompanionGraphSnapshot) -> KnowledgeParticleField.Topology? {
        guard LiminalKnowledgeBindings.isDigest(originDigest), graph.truncatedCount >= 0,
              graph.nodes.count <= CompanionGraph.maximumNodes,
              graph.edges.count <= CompanionGraph.maximumEdges,
              graph.nodes.allSatisfy({ validIdentifier($0.id) }),
              graph.edges.allSatisfy({ validIdentifier($0.id) && validIdentifier($0.source) && validIdentifier($0.target) })
        else { return nil }
        let topology = KnowledgeParticleField.topology(of: graph)
        // The existing field rejects duplicates and dangling edges. A shared
        // scene must reject that input instead of silently losing graph records.
        guard topology.nodes.count == graph.nodes.count, topology.edges.count == graph.edges.count else { return nil }
        return topology
    }

    private static func validIdentifier(_ value: String) -> Bool {
        value.utf8.count <= 256 && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    private static func inputs(originDigest: String, graph: CompanionGraphSnapshot,
                               development: LiminalFormDevelopment.Snapshot?) -> Inputs? {
        guard let topology = validTopology(originDigest: originDigest, graph: graph) else { return nil }
        let graphDigest = LiminalKnowledgeBindings.digest(graph)
        let projection = projectDevelopment(development, originDigest: originDigest, graph: graph)
        return Inputs(topology: topology, graphDigest: graphDigest,
                      digest: hash(["archi-companion-particle-scene/v1", originDigest, graphDigest, projection.digest]),
                      growth: projection.growth)
    }

    private static func projectDevelopment(_ development: LiminalFormDevelopment.Snapshot?, originDigest: String,
                                           graph: CompanionGraphSnapshot) -> (growth: [String: Growth], digest: String) {
        guard let development else { return ([:], hash(["absent"])) }
        guard development.originDigest == originDigest, development.evidenceAvailable else {
            return ([:], hash(["unavailable"]))
        }
        guard development.nodes.count <= LiminalFormDevelopment.maximumNodes,
              Set(development.nodes.map(\.id)).count == development.nodes.count,
              development.nodes.allSatisfy({ node in
                  LiminalKnowledgeBindings.isDigest(node.id)
                      && (0...EvolutionStore.maximumUsefulReceipts).contains(node.reviewedApplicationCount)
                      && node.applications == min(8, node.reviewedApplicationCount)
                      && node.graphNodeIDs.count <= LiminalFormDevelopment.maximumNodes
                      && node.graphNodeIDs.allSatisfy(validIdentifier)
                      && (node.supportDigest.map(LiminalKnowledgeBindings.isDigest) ?? true)
              }) else { return ([:], hash(["invalid-development"])) }

        // Current source owners decide availability. Keep historical/stale nodes
        // in the graph while refusing to decorate them as current development.
        let eligibleIDs = Set(graph.nodes.filter {
            $0.presentationState == .recorded || $0.presentationState == .reviewed
        }.map(\.id))
        var candidates: [String: [Growth]] = [:]
        var pieces = ["current-development/v1", development.originDigest]
        for node in development.nodes.sorted(by: { $0.id < $1.id }) {
            let aliases = Set(node.graphNodeIDs).sorted()
            pieces += [node.id, String(node.applications), String(node.reviewedApplicationCount),
                       node.supportDigest ?? "", String(aliases.count)] + aliases
            let growth = Growth(contentID: node.id, applications: node.applications,
                                reviewedApplicationCount: node.reviewedApplicationCount)
            for id in aliases where eligibleIDs.contains(id) { candidates[id, default: []].append(growth) }
        }
        // Two distinct content owners claiming one record is ambiguous, even
        // when their counts agree. Do not pick a winner or add their experience.
        let growth = candidates.compactMapValues { $0.count == 1 ? $0[0] : nil }
        return (growth, hash(pieces))
    }

    private static func hash(_ pieces: [String]) -> String {
        LiminalKnowledgeBindings.sha256(Data(pieces.map { "\($0.utf8.count):\($0)" }.joined().utf8))
    }
}
