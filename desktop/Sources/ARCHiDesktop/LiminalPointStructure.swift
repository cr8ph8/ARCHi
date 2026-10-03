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

    @MainActor static func make(_ snapshot: LiminalFormDevelopment.Snapshot, sessionID: String,
                               manifestSHA256: String, lowDetailIDs: [UInt32]) -> Self? {
        guard UUID(uuidString: sessionID) != nil, LiminalKnowledgeBindings.isDigest(manifestSHA256),
              !lowDetailIDs.isEmpty, lowDetailIDs.count <= 50_000,
              lowDetailIDs.allSatisfy({ $0 < 800_000 }), Set(lowDetailIDs).count == lowDetailIDs.count else { return nil }
        var used = Set<UInt32>(), nodes: [Node] = []
        for node in snapshot.visibleNodes {
            let hash = LiminalKnowledgeBindings.sha256(Data((snapshot.originDigest + ":" + manifestSHA256 + ":" + node.id).utf8))
            let start = Int(UInt32(hash.prefix(8), radix: 16) ?? 0) % lowDetailIDs.count
            guard let anchor = (0..<lowDetailIDs.count).lazy.map({ lowDetailIDs[(start + $0) % lowDetailIDs.count] }).first(where: { !used.contains($0) }) else { return nil }
            used.insert(anchor)
            nodes.append(.init(contentID: node.id, anchorID: anchor, applications: node.applications))
        }
        // Include exact current references and support, including non-visible nodes.
        // Only this digest crosses the boundary; lesson text and titles do not.
        let evidence = [LiminalFormDevelopment.revision, snapshot.originDigest, String(snapshot.evidenceAvailable)]
            + snapshot.nodes.flatMap {
                [$0.id, String($0.applications), String($0.reviewedApplicationCount),
                 $0.evidenceState.rawValue, $0.supportDigest ?? "unrecorded"]
                    + $0.lessonIDs.sorted() + $0.graphNodeIDs.sorted()
            }
        let value = Self(schemaVersion: 1, recipeVersion: version, sessionID: sessionID,
                         originDigest: snapshot.originDigest, manifestSHA256: manifestSHA256,
                         evidenceDigest: LiminalKnowledgeBindings.sha256(Data(evidence.map { "\($0.utf8.count):\($0)" }.joined().utf8)),
                         detail: snapshot.availableDetail, nodes: nodes)
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
    func liminalPointStructure(sessionID: String, asset: LiminalPointAsset, at date: Date = Date()) -> LiminalPointStructure? {
        guard preferences.visualTreatment == .liminalV008, let snapshot = liminalFormDevelopment(at: date) else { return nil }
        return LiminalPointStructure.make(snapshot, sessionID: sessionID, manifestSHA256: asset.manifestSHA256, lowDetailIDs: asset.lowDetailIDs)
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
    @State private var sessionID = UUID().uuidString
    @State private var recheckedAt = Date()
    func body(content: Content) -> some View {
        let snapshot = store.liminalFormDevelopment(at: recheckedAt)
        let structure = LiminalV008Runtime.asset.flatMap { asset -> LiminalPointStructure? in
            guard store.preferences.visualTreatment == .liminalV008, let snapshot else { return nil }
            return LiminalPointStructure.make(snapshot, sessionID: sessionID,
                manifestSHA256: asset.manifestSHA256, lowDetailIDs: asset.lowDetailIDs)
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
