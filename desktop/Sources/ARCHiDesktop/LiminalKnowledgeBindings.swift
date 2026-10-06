import Foundation
import CryptoKit

/// A disposable presentation map, never a second knowledge store. Reservations
/// survive filtering and removal for the lifetime of this asset/session so an
/// old particle cannot silently become a different record.
struct LiminalKnowledgeBindings {
    struct Binding: Codable, Equatable {
        let nodeID: String
        let anchorID: UInt32
        let particleIDs: [UInt32]
    }
    struct Sidecar: Codable, Equatable {
        let schemaVersion: Int
        let sessionID: String
        let originDigest: String
        let manifestSHA256: String
        let graphDigest: String
        let bindings: [Binding]

        func data() throws -> Data {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(self)
            guard data.count <= 524_288 else { throw BindingError.oversized }
            return data
        }
        func filtered(to nodeIDs: Set<String>) -> Self {
            .init(schemaVersion: schemaVersion, sessionID: sessionID, originDigest: originDigest,
                  manifestSHA256: manifestSHA256, graphDigest: graphDigest,
                  bindings: bindings.filter { nodeIDs.contains($0.nodeID) })
        }
        /// The native allocator owns art identities. Transport ownership remains
        /// bound to the receiving presentation's independently checked session.
        func forSession(_ sessionID: String) throws -> Self {
            guard UUID(uuidString: sessionID) != nil else { throw BindingError.invalidIdentity }
            let value = Self(schemaVersion: schemaVersion, sessionID: sessionID, originDigest: originDigest,
                             manifestSHA256: manifestSHA256, graphDigest: graphDigest, bindings: bindings)
            _ = try value.data()
            return value
        }
    }
    struct PresentationProjection {
        let sidecar: Sidecar
        let inspectionUnavailableReason: String?
    }
    enum BindingError: Error, Equatable { case invalidIdentity, invalidIDs, invalidGraph, exhausted, oversized }
    private struct Owner: Equatable {
        let sessionID: UUID
        let originDigest: String
    }
    private let manifestSHA256: String
    private let availableIDs: [UInt32]
    private var owner: Owner?
    private var reservations: [String: Binding] = [:]
    private var reserved = Set<UInt32>()

    init(manifestSHA256: String, lowDetailIDs: [UInt32]) throws {
        guard Self.isDigest(manifestSHA256) else { throw BindingError.invalidIdentity }
        guard !lowDetailIDs.isEmpty, lowDetailIDs.count <= 50_000,
              lowDetailIDs.allSatisfy({ $0 < 800_000 }),
              Set(lowDetailIDs).count == lowDetailIDs.count else { throw BindingError.invalidIDs }
        self.manifestSHA256 = manifestSHA256
        availableIDs = lowDetailIDs
    }

    mutating func project(_ graph: CompanionGraphSnapshot, sessionID: String, originDigest: String) throws -> Sidecar {
        guard let session = UUID(uuidString: sessionID), Self.isDigest(originDigest) else { throw BindingError.invalidIdentity }
        let nextOwner = Owner(sessionID: session, originDigest: originDigest)
        // A session belongs to one companion. Callers already start a fresh
        // session when changing companions; silently keeping its reservations
        // would make a reused node label look like the previous companion's record.
        if let owner, owner.sessionID == session, owner.originDigest != originDigest {
            throw BindingError.invalidIdentity
        }
        try Self.validate(graph)
        let continuingSession = owner == nextOwner
        var nextReservations = continuingSession ? reservations : [:]
        var nextReserved = continuingSession ? reserved : Set<UInt32>()
        var bindings: [Binding] = []
        for node in graph.nodes.sorted(by: { $0.id < $1.id }) {
            if let existing = nextReservations[node.id] { bindings.append(existing); continue }
            // Initial positions are reproducible after restart. A session is an
            // authorization boundary, not part of a record's visual identity.
            let hash = Array(SHA256.hash(data: Data((manifestSHA256 + ":" + originDigest + ":" + node.id).utf8)))
            let start = Int(hash.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }) % availableIDs.count
            var cluster: [UInt32] = []
            for offset in 0..<availableIDs.count {
                let id = availableIDs[(start + offset) % availableIDs.count]
                if !nextReserved.contains(id) { cluster.append(id) }
                if cluster.count == 32 { break }
            }
            guard cluster.count == 32 else { throw BindingError.exhausted }
            let binding = Binding(nodeID: node.id, anchorID: cluster[0], particleIDs: cluster)
            nextReservations[node.id] = binding; nextReserved.formUnion(cluster); bindings.append(binding)
        }
        let sidecar = Sidecar(schemaVersion: 1, sessionID: sessionID, originDigest: originDigest,
                              manifestSHA256: manifestSHA256, graphDigest: Self.digest(graph), bindings: bindings)
        // Exhaustion or an encoding limit must leave both identity and all
        // retired reservations intact, so a smaller retry can still succeed.
        _ = try sidecar.data()
        owner = nextOwner; reservations = nextReservations; reserved = nextReserved
        return sidecar
    }

    /// Anchor capacity limits inspection, not the authored particle body. Publish
    /// the current identity and digest with no selectable records instead of
    /// retaining stale picks or silently reassigning retired particle IDs.
    mutating func projectForPresentation(_ graph: CompanionGraphSnapshot, sessionID: String,
                                         originDigest: String) throws -> PresentationProjection {
        do {
            return .init(sidecar: try project(graph, sessionID: sessionID, originDigest: originDigest),
                         inspectionUnavailableReason: nil)
        } catch BindingError.exhausted {
            // project() already validated the full graph and ownership before
            // allocation, and its failed transaction left all reservations intact.
            let sidecar = Sidecar(schemaVersion: 1, sessionID: sessionID, originDigest: originDigest,
                                  manifestSHA256: manifestSHA256, graphDigest: Self.digest(graph), bindings: [])
            _ = try sidecar.data()
            // Publishing even an empty sidecar claims this session's origin.
            // An explicitly new session has no reservations yet; an existing
            // session keeps every retired ID despite this inspection fallback.
            if let session = UUID(uuidString: sessionID), owner?.sessionID != session {
                owner = Owner(sessionID: session, originDigest: originDigest)
                reservations = [:]; reserved = []
            }
            return .init(sidecar: sidecar,
                         inspectionUnavailableReason: "Knowledge inspection is unavailable because this session’s particle anchors are full. Liminal’s appearance remains available.")
        }
    }

    private static func validIdentifier(_ text: String) -> Bool {
        text.utf8.count <= 256 && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    private static func detailLimit(for node: CompanionGraphNode) -> Int {
        // Document work owns a larger, already bounded metadata projection:
        // even the ordinary eight checks follow twenty-five retained fields.
        // Preserve those checks without relaxing other node or text limits.
        let prefix = "document-work-"
        if node.kind == .context, node.target == .context, node.id.hasPrefix(prefix),
           isDigest(String(node.id.dropFirst(prefix.count))) {
            return DocumentWorkGraph.maximumTaskDetails
        }
        return 32
    }

    static func validate(_ graph: CompanionGraphSnapshot) throws {
        guard graph.nodes.count <= CompanionGraph.maximumNodes,
              graph.edges.count <= CompanionGraph.maximumEdges, graph.truncatedCount >= 0,
              graph.nodes.allSatisfy({ validIdentifier($0.id) }),
              graph.edges.allSatisfy({ validIdentifier($0.id) && validIdentifier($0.source) && validIdentifier($0.target) }) else { throw BindingError.invalidGraph }
        let nodeIDs = Set(graph.nodes.map(\.id))
        guard nodeIDs.count == graph.nodes.count,
              Set(graph.edges.map(\.id)).count == graph.edges.count else { throw BindingError.invalidGraph }
        // Knowledge-page bodies can contain 8 KiB; preserve those inspected
        // words while bounding the total work before hashing a caller's graph.
        var remainingBytes = 2_097_152
        func textFits(_ text: String) -> Bool {
            let count = text.utf8.count
            guard count <= 8_192, count <= remainingBytes else { return false }
            remainingBytes -= count
            return true
        }
        for node in graph.nodes {
            guard node.details.count <= detailLimit(for: node),
                  [node.id, node.title, node.subtitle, node.status].allSatisfy(textFits),
                  node.details.allSatisfy({ textFits($0.label) && textFits($0.value) }) else { throw BindingError.invalidGraph }
            let target = targetPieces(node.target)
            guard target.allSatisfy(textFits), target.dropFirst().allSatisfy(validIdentifier),
                  node.evidenceTrail.count <= 32 else { throw BindingError.invalidGraph }
            if case let .documentMethod(binding) = node.target, !binding.isValid { throw BindingError.invalidGraph }
            if case let .knowledgePage(binding) = node.target, !binding.isValid { throw BindingError.invalidGraph }
            if case let .readingSource(binding) = node.target, !binding.isValid { throw BindingError.invalidGraph }
            for evidence in node.evidenceTrail {
                guard validIdentifier(evidence.id),
                      evidence.relatedNodeID.map(validIdentifier) ?? true,
                      [evidence.id, evidence.summary, evidence.reference ?? "", evidence.relatedNodeID ?? ""].allSatisfy(textFits)
                else { throw BindingError.invalidGraph }
            }
        }
        for edge in graph.edges {
            guard nodeIDs.contains(edge.source), nodeIDs.contains(edge.target),
                  [edge.id, edge.source, edge.target, edge.label, edge.rationale ?? "", edge.reference ?? ""].allSatisfy(textFits)
            else { throw BindingError.invalidGraph }
        }
    }

    private static func targetPieces(_ target: CompanionGraphTarget?) -> [String] {
        switch target {
        case nil: ["none"]
        case .assistant: ["assistant"]
        case .context: ["context"]
        case .memory: ["memory"]
        case .advanced: ["advanced"]
        case .capabilities: ["capabilities"]
        case .steward: ["steward"]
        case .interactiveARC: ["interactiveARC"]
        case let .arcEvidence(proposalHash): ["arcEvidence", proposalHash]
        case let .stewardTask(taskID): ["stewardTask", taskID]
        case let .knowledgePage(binding): ["knowledgePage", binding.id, String(binding.revision), binding.digest]
        case let .readingSource(binding): ["readingSource", binding.id, String(binding.revision), binding.digest, binding.provenanceDigest ?? "none"]
        case let .documentMethod(binding): ["documentMethod", binding.id, String(binding.revision), binding.digest]
        }
    }

    static func isDigest(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func digest(_ graph: CompanionGraphSnapshot) -> String {
        // Include availability and version details: a retained historical node
        // can become unavailable without changing its identity.
        var pieces = ["archi-point-knowledge-state/v2", String(graph.truncatedCount), String(graph.nodes.count)]
        for node in graph.nodes.sorted(by: { $0.id < $1.id }) {
            pieces += [node.id, node.kind.rawValue, node.title, node.subtitle, node.status,
                       node.presentationState.rawValue, String(node.details.count)]
            for detail in node.details { pieces += [detail.label, detail.value] }
            let target = targetPieces(node.target)
            pieces += [String(target.count)] + target
            pieces += [String(node.evidenceTrail.count)]
            for evidence in node.evidenceTrail {
                pieces += [evidence.id, evidence.stage.rawValue, evidence.summary,
                           evidence.reference ?? "", evidence.relatedNodeID ?? ""]
            }
        }
        pieces += [String(graph.edges.count)]
        for edge in graph.edges.sorted(by: { $0.id < $1.id }) {
            pieces += [edge.id, edge.source, edge.target, edge.label, edge.relationship.rawValue,
                       edge.rationale ?? "", edge.reference ?? ""]
        }
        return sha256(Data(pieces.map { "\($0.utf8.count):\($0)" }.joined().utf8))
    }
}

struct LiminalKnowledgeSelection: Codable {
    let schemaVersion: Int
    let sessionID: String
    let originDigest: String
    let revision: Int
    let manifestSHA256: String
    let graphDigest: String
    let nodeID: String
    let artParticleID: UInt32
    let sequence: Int
    let updatedAtUnix: Double

    func resolves(in sidecar: LiminalKnowledgeBindings.Sidecar, graph: CompanionGraphSnapshot,
                  revisions: Set<Int>, after sequence: Int, now: Date) -> CompanionGraphNode? {
        guard schemaVersion == 1, sidecar.schemaVersion == 1, self.sequence > sequence, self.sequence > 0,
              (try? LiminalKnowledgeBindings.validate(graph)) != nil,
              sessionID == sidecar.sessionID, originDigest == sidecar.originDigest,
              manifestSHA256 == sidecar.manifestSHA256, graphDigest == sidecar.graphDigest,
              graphDigest == LiminalKnowledgeBindings.digest(graph), revisions.contains(revision),
              updatedAtUnix.isFinite, (-5...5).contains(now.timeIntervalSince1970 - updatedAtUnix),
              sidecar.bindings.contains(where: { $0.nodeID == nodeID && $0.particleIDs.contains(artParticleID) }) else { return nil }
        return graph.nodes.first { $0.id == nodeID }
    }
}
