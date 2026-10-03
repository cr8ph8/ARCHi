import Foundation
import SwiftUI
import simd

/// Disposable geometry recipe. Extra motif points follow authenticated anchors;
/// none of the authored body or Seed samples are moved, removed, or reclassified.
struct LiminalPointStructure: Codable, Equatable, Sendable {
    static let version = "liminal-bound-structure/v1"
    struct Node: Codable, Equatable, Sendable {
        let contentID: String
        let anchorID: UInt32
        let applications: Int
    }
    let schemaVersion: Int
    let recipeVersion: String
    let sessionID: String
    let originDigest: String
    let manifestSHA256: String
    let evidenceDigest: String
    let detail: Int
    let nodes: [Node]

    var isValid: Bool {
        schemaVersion == 1 && recipeVersion == Self.version && UUID(uuidString: sessionID) != nil
            && [originDigest, manifestSHA256, evidenceDigest].allSatisfy(LiminalKnowledgeBindings.isDigest)
            && (0...4).contains(detail) && nodes.count <= 24 && (detail != 0 || nodes.isEmpty)
            && nodes.allSatisfy { LiminalKnowledgeBindings.isDigest($0.contentID) && $0.anchorID < 800_000 && (0...8).contains($0.applications) }
            && nodes.map(\.contentID) == nodes.map(\.contentID).sorted()
            && Set(nodes.map(\.contentID)).count == nodes.count && Set(nodes.map(\.anchorID)).count == nodes.count
    }
    var digest: String {
        let pieces = [recipeVersion, String(schemaVersion), sessionID, originDigest, manifestSHA256, evidenceDigest,
                      String(detail), String(nodes.count)] + nodes.flatMap { [$0.contentID, String($0.anchorID), String($0.applications)] }
        return LiminalKnowledgeBindings.sha256(Data(pieces.map { "\($0.utf8.count):\($0)" }.joined().utf8))
    }
    var samplesPerNode: Int { isValid ? [0, 1, 6, 10, 14][detail] : 0 }
    var particleCount: Int { samplesPerNode * nodes.count }

    @MainActor static func make(_ snapshot: LiminalFormDevelopment.Snapshot, graph: CompanionGraphSnapshot,
                               bindings: LiminalKnowledgeBindings.Sidecar, lowDetailIDs: [UInt32]) -> Self? {
        guard bindings.schemaVersion == 1, UUID(uuidString: bindings.sessionID) != nil,
              bindings.originDigest == snapshot.originDigest,
              LiminalKnowledgeBindings.isDigest(bindings.manifestSHA256),
              (try? LiminalKnowledgeBindings.validate(graph)) != nil,
              bindings.graphDigest == LiminalKnowledgeBindings.digest(graph),
              bindings.bindings.count <= CompanionGraph.maximumNodes,
              snapshot.nodes.count <= LiminalFormDevelopment.maximumNodes,
              snapshot.nodes.allSatisfy({ $0.graphNodeIDs.count <= LiminalFormDevelopment.maximumNodes }),
              !lowDetailIDs.isEmpty, lowDetailIDs.count <= 50_000,
              lowDetailIDs.allSatisfy({ $0 < 800_000 }), Set(lowDetailIDs).count == lowDetailIDs.count,
              let projection = CompanionParticleScene.developmentProjection(originDigest: snapshot.originDigest,
                  graph: graph, development: snapshot),
              let bindingBytes = try? bindings.data() else { return nil }
        let available = Set(lowDetailIDs), graphIDs = Set(graph.nodes.map(\.id))
        var recordBindings: [String: LiminalKnowledgeBindings.Binding] = [:]
        var reserved = Set<UInt32>()
        for binding in bindings.bindings {
            guard graphIDs.contains(binding.nodeID), recordBindings[binding.nodeID] == nil,
                  binding.particleIDs.count == 32, binding.particleIDs.contains(binding.anchorID),
                  binding.particleIDs.allSatisfy({ available.contains($0) && reserved.insert($0).inserted })
            else { return nil }
            recordBindings[binding.nodeID] = binding
        }

        // The projection has checked origin, evidence, duplicate content and
        // ambiguous aliases. A content group gets one motif at an actual inspected
        // record anchor, never a second independently hashed art location.
        var eligible: [LiminalFormDevelopment.Node] = [], nodes: [Node] = []
        for node in snapshot.nodes.sorted(by: { $0.id < $1.id }) {
            let binding = Set(node.graphNodeIDs).sorted().compactMap { id -> LiminalKnowledgeBindings.Binding? in
                guard projection.growth[id]?.contentID == node.id else { return nil }
                return recordBindings[id]
            }.first
            guard let binding else { continue }
            eligible.append(node)
            if nodes.count < LiminalFormDevelopment.maximumVisibleNodes {
                nodes.append(.init(contentID: node.id, anchorID: binding.anchorID, applications: node.applications))
            }
        }
        let current = LiminalFormDevelopment.Snapshot(originDigest: snapshot.originDigest, nodes: eligible,
            unavailableLessons: 0, duplicateLessons: 0, evidenceAvailable: snapshot.evidenceAvailable)
        // Full graph, exact record-to-art assignment and all current support stay
        // bound even when visual detail displays only the first content groups.
        // Only digests cross the wire; no lesson text, titles or source bodies do.
        let evidence = ["liminal-inspection-bound-support/v1", bindings.graphDigest, projection.digest,
                        LiminalKnowledgeBindings.sha256(bindingBytes)]
        let value = Self(schemaVersion: 1, recipeVersion: version, sessionID: bindings.sessionID,
                         originDigest: snapshot.originDigest, manifestSHA256: bindings.manifestSHA256,
                         evidenceDigest: LiminalKnowledgeBindings.sha256(Data(evidence.map { "\($0.utf8.count):\($0)" }.joined().utf8)),
                         detail: current.availableDetail, nodes: nodes)
        return value.isValid ? value : nil
    }

    /// Same equation as Unity. The span normalizes the motif across source units.
    static func offset(contentID: String, applications: Int, index: Int, detail: Int, span: Float,
                       elapsed: Double? = nil) -> SIMD3<Float> {
        guard (1...4).contains(detail), span.isFinite, span > 0 else { return .zero }
        let count = [0, 1, 6, 10, 14][detail]
        let phase = Double(UInt32(contentID.prefix(8), radix: 16) ?? 0) / Double(UInt32.max) * 2 * .pi
        let angle = phase + Double(index) * 2 * .pi / Double(count)
        let radius: Float = count == 1 ? 0 : (0.008 + 0.004 * Float(detail)) * span
        var result = SIMD3(Float(cos(angle)) * radius, Float(sin(angle)) * radius, 0)
        if let t = elapsed, t.isFinite, t >= 0, t < 3 {
            let k = 5 + 0.35 * Double(min(8, max(0, applications)))
            result.x += span * Float(0.035 * (1 + k * t) * exp(-k * t))
        }
        return result
    }

    func samples(frame: LiminalPointAsset.Frame, asset: LiminalPointAsset, elapsed: Double? = nil) -> [LiminalPointAsset.Sample] {
        guard isValid, manifestSHA256 == asset.manifestSHA256 else { return [] }
        let ranks = Dictionary(uniqueKeysWithValues: asset.lowDetailIDs.enumerated().map { ($0.element, $0.offset) })
        var result: [LiminalPointAsset.Sample] = []
        for node in nodes {
            guard let rank = ranks[node.anchorID], let source = frame.sample(at: rank) else { return [] }
            let anchor = asset.finish?.display(source, rank: rank, frame: frame.frame) ?? source
            for index in 0..<samplesPerNode {
                result.append(.init(position: anchor.position + Self.offset(contentID: node.contentID, applications: node.applications,
                    index: index, detail: detail, span: asset.span, elapsed: elapsed),
                    color: SIMD3(0.95, 0.55, 0.12), radius: asset.span * 0.0022, emission: 2.5))
            }
        }
        return result
    }
    static func packed(_ samples: [LiminalPointAsset.Sample]) -> Data {
        var data = Data(capacity: samples.count * 32)
        for p in samples {
            for v in [p.position.x, p.position.y, p.position.z, p.color.x, p.color.y, p.color.z, p.radius, p.emission] {
                var bits = v.bitPattern.littleEndian
                withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
            }
        }
        return data
    }
}

@MainActor extension CompanionStore {
    /// All native surfaces and exports share this disposable reservation history.
    /// An Arena session receives the same anchors with its own replay boundary.
    func liminalKnowledgePresentation(asset: LiminalPointAsset, sessionID: String? = nil,
                                     at date: Date = Date(), forMemoryMap: Bool = false)
        -> (sidecar: LiminalKnowledgeBindings.Sidecar, structure: LiminalPointStructure?, inspectionUnavailableReason: String?)? {
        // The memory map may preview the authenticated body without replacing
        // the saved companion appearance or creating another allocation owner.
        guard preferences.visualTreatment == .liminalV008 || forMemoryMap,
              let development = liminalFormDevelopment(at: date) else { return nil }
        let identity = development.originDigest + ":" + asset.manifestSHA256
        let graph = companionGraphSnapshot(at: date)
        do {
            if liminalKnowledgeIdentity != identity {
                liminalKnowledgeBindings = try LiminalKnowledgeBindings(manifestSHA256: asset.manifestSHA256,
                                                                         lowDetailIDs: asset.lowDetailIDs)
                liminalKnowledgeIdentity = identity
                liminalStructureSessionID = UUID().uuidString
            }
            guard let projection = try liminalKnowledgeBindings?.projectForPresentation(graph,
                sessionID: liminalStructureSessionID, originDigest: development.originDigest) else { return nil }
            let sidecar = try projection.sidecar.forSession(sessionID ?? liminalStructureSessionID)
            let structure = LiminalPointStructure.make(development, graph: graph, bindings: sidecar,
                                                       lowDetailIDs: asset.lowDetailIDs)
            return (sidecar, structure, projection.inspectionUnavailableReason)
        } catch { return nil }
    }

    @discardableResult
    func inspectLiminalKnowledgeParticle(_ artID: UInt32, sidecar: LiminalKnowledgeBindings.Sidecar,
                                         asset: LiminalPointAsset) -> Bool {
        guard let current = liminalKnowledgePresentation(asset: asset), current.sidecar == sidecar,
              let binding = sidecar.bindings.first(where: { $0.anchorID == artID }) else { return false }
        return inspectKnowledgeParticle(nodeID: binding.nodeID, graphDigest: sidecar.graphDigest)
    }
}

private struct LiminalStructureKey: EnvironmentKey { static let defaultValue: LiminalPointStructure? = nil }
extension EnvironmentValues {
    var liminalPointStructure: LiminalPointStructure? {
        get { self[LiminalStructureKey.self] }
        set { self[LiminalStructureKey.self] = newValue }
    }
}

/// Rechecks file-backed support even when no in-process owner publishes a change.
@MainActor struct LiminalStructureScope: ViewModifier {
    @ObservedObject var store: CompanionStore
    @State private var recheckedAt = Date()
    func body(content: Content) -> some View {
        let structure = LiminalV008Runtime.asset.flatMap {
            store.liminalKnowledgePresentation(asset: $0, at: recheckedAt)?.structure
        }
        // Keep the artwork in the ordinary view tree so explicit ImageRenderer
        // snapshots never capture a TimelineView placeholder. The task expires
        // with this presentation and refreshes file-backed support while visible.
        content.environment(\.companionParticleScene, store.companionParticleScene(at: recheckedAt))
            .environment(\.companionParticleSelection, store.memoryParticleSelection)
            .environment(\.liminalPointStructure, structure)
            .task {
                recheckedAt = Date()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    guard !Task.isCancelled else { return }
                    recheckedAt = Date()
                }
            }
    }
}
