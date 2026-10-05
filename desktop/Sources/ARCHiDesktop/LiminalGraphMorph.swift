import Foundation
import simd

/// Disposable correspondence between current graph records and authenticated art
/// particles. Density and interpolation never create records or change evidence.
struct LiminalGraphMorph: Equatable, Sendable {
    static let targetProgress = 23.0 / 119.0
    static let targetFrame = 24
    static let maximumClusterOffset: Float = 6

    struct Anchor: Equatable, Sendable {
        let nodeID: String
        let artID: UInt32
        let rank: Int
        /// SwiftUI coordinates: origin at the upper left, measured in points.
        let mapPoint: CGPoint
        /// Metal clip coordinates: x right, y up.
        let mapClip: SIMD2<Float>
        /// The same record's compact Seed position, not another art or memory owner.
        let seedPoint: CGPoint
        let seedClip: SIMD2<Float>
        let isVisible: Bool
    }

    let digest: String
    let manifestSHA256: String
    let originDigest: String
    let graphDigest: String
    let mapGraphDigest: String
    let viewport: CGSize
    let anchors: [Anchor]
    let mapPoints: [String: CGPoint]
    /// xy = map endpoint, z = visible(1), hidden(-1), decorative(0); w is unused.
    let mapTargetsByRank: [Int: SIMD4<Float>]
    let seedTargetsByRank: [Int: SIMD4<Float>]
    private let finishDigest: String?

    var anchorArtIDsByNodeID: [String: UInt32] {
        Dictionary(uniqueKeysWithValues: anchors.map { ($0.nodeID, $0.artID) })
    }
    var nodeIDsByAnchorArtID: [UInt32: String] {
        Dictionary(uniqueKeysWithValues: anchors.map { ($0.artID, $0.nodeID) })
    }

    /// The caller captures both projections from current owners. The memory map
    /// may be a strict subset of the full activity graph; its digest is separate.
    /// Filtering must use visibleNodeIDs, never a newly laid-out filtered field.
    static func make(asset: LiminalPointAsset, bindings: LiminalKnowledgeBindings.Sidecar,
                     fullGraph: CompanionGraphSnapshot, mapGraph: CompanionGraphSnapshot,
                     field: KnowledgeParticleField, originDigest: String, viewport: CGSize,
                     visibleNodeIDs: Set<String>, focusIDs: Set<String>? = nil) -> Self? {
        guard validViewport(viewport), LiminalKnowledgeBindings.isDigest(originDigest),
              asset.manifest.assetID == "liminal-v008", LiminalKnowledgeBindings.isDigest(asset.manifestSHA256),
              bindings.schemaVersion == 1, UUID(uuidString: bindings.sessionID) != nil,
              bindings.originDigest == originDigest, bindings.manifestSHA256 == asset.manifestSHA256,
              (try? LiminalKnowledgeBindings.validate(fullGraph)) != nil,
              (try? LiminalKnowledgeBindings.validate(mapGraph)) != nil,
              bindings.graphDigest == LiminalKnowledgeBindings.digest(fullGraph),
              bindings.bindings.count <= CompanionGraph.maximumNodes,
              let sidecarData = try? bindings.data() else { return nil }

        let fullNodes = Dictionary(uniqueKeysWithValues: fullGraph.nodes.map { ($0.id, $0) })
        let fullEdges = Dictionary(uniqueKeysWithValues: fullGraph.edges.map { ($0.id, $0) })
        let mapIDs = Set(mapGraph.nodes.map(\.id))
        guard mapGraph.nodes.allSatisfy({ nodeMatches(map: $0, full: fullNodes[$0.id]) }),
              mapGraph.edges.allSatisfy({ fullEdges[$0.id] == $0 }),
              visibleNodeIDs.isSubset(of: mapIDs), focusIDs?.isSubset(of: mapIDs) ?? true else { return nil }
        let topology = KnowledgeParticleField.topology(of: mapGraph)
        guard field.particles.map({ KnowledgeParticleField.Topology.Node(nodeID: $0.nodeID, kind: $0.kind) }) == topology.nodes,
              field.edges == topology.edges, field.omittedCount == topology.omittedCount,
              field.particles.allSatisfy({
                  $0.orb.x.isFinite && $0.orb.y.isFinite && $0.constellation.x.isFinite
                      && $0.constellation.y.isFinite && $0.phase.isFinite
              }) else { return nil }

        let lowIDs = asset.lowDetailIDs
        guard !lowIDs.isEmpty, lowIDs.count <= LiminalPointAsset.Detail.low.rawValue,
              Set(lowIDs).count == lowIDs.count, lowIDs.allSatisfy({ $0 < 800_000 }) else { return nil }
        let ranks = Dictionary(uniqueKeysWithValues: lowIDs.enumerated().map { ($0.element, $0.offset) })
        var boundRecords = Set<String>(), boundArt = Set<UInt32>()
        for binding in bindings.bindings {
            guard fullNodes[binding.nodeID] != nil, boundRecords.insert(binding.nodeID).inserted,
                  binding.particleIDs.count == 32, binding.particleIDs.contains(binding.anchorID),
                  binding.particleIDs.allSatisfy({ ranks[$0] != nil && boundArt.insert($0).inserted }) else { return nil }
        }
        // Exhaustion may legitimately publish no bindings. Keep the ordinary map
        // rather than silently omitting one of its records from the morph.
        guard mapIDs.isSubset(of: boundRecords) else { return nil }

        let frame = KnowledgeParticleField.framing(particles: field.particles, spread: 1,
                                                   reduceMotion: true, focusIDs: focusIDs)
        let positions = KnowledgeParticleField.displayPositions(particles: field.particles, frame: frame,
            spread: 1, reduceMotion: true, width: viewport.width, height: viewport.height)
        let mapPoints = positions.mapValues { CGPoint(x: $0.x, y: $0.y) }
        // Seed framing always uses the complete field. Search or focus must not
        // move its records to a different place in the continuing companion.
        let seedFrame = KnowledgeParticleField.framing(particles: field.particles, spread: 0, reduceMotion: true)
        let seedPositions = KnowledgeParticleField.displayPositions(particles: field.particles, frame: seedFrame,
            spread: 0, reduceMotion: true, width: viewport.width, height: viewport.height)
        var targets: [Int: SIMD4<Float>] = [:], seedTargets: [Int: SIMD4<Float>] = [:], anchors: [Anchor] = []
        for binding in bindings.bindings.sorted(by: { $0.nodeID < $1.nodeID }) where mapIDs.contains(binding.nodeID) {
            guard let point = mapPoints[binding.nodeID], let clip = clipPosition(point: point, viewport: viewport),
                  let seed = seedPositions[binding.nodeID],
                  let seedClip = clipPosition(point: CGPoint(x: seed.x, y: seed.y), viewport: viewport),
                  let anchorRank = ranks[binding.anchorID] else { return nil }
            let visible = visibleNodeIDs.contains(binding.nodeID)
            anchors.append(.init(nodeID: binding.nodeID, artID: binding.anchorID, rank: anchorRank,
                                 mapPoint: point, mapClip: clip, seedPoint: CGPoint(x: seed.x, y: seed.y),
                                 seedClip: seedClip, isVisible: visible))
            for id in binding.particleIDs {
                guard let rank = ranks[id] else { return nil }
                let offset = clusterOffset(artID: id, anchorID: binding.anchorID)
                let shifted = CGPoint(x: point.x + CGFloat(offset.x), y: point.y + CGFloat(offset.y))
                guard let target = clipPosition(point: shifted, viewport: viewport) else { return nil }
                targets[rank] = SIMD4(target.x, target.y, visible ? 1 : -1, 0)
                guard let seedTarget = clipPosition(point: CGPoint(x: seed.x + Double(offset.x),
                    y: seed.y + Double(offset.y)), viewport: viewport) else { return nil }
                seedTargets[rank] = SIMD4(seedTarget.x, seedTarget.y, visible ? 1 : -1, 0)
            }
        }
        let mapDigest = LiminalKnowledgeBindings.digest(mapGraph)
        var pieces = ["liminal-graph-morph/v2", originDigest, bindings.graphDigest, mapDigest,
                      LiminalKnowledgeBindings.sha256(sidecarData), asset.manifestSHA256,
                      asset.finish?.digest ?? "", String(Double(viewport.width)), String(Double(viewport.height))]
        for rank in targets.keys.sorted() {
            let value = targets[rank]!
            pieces += [String(rank), String(value.x.bitPattern), String(value.y.bitPattern), String(value.z)]
            let seed = seedTargets[rank]!
            pieces += [String(seed.x.bitPattern), String(seed.y.bitPattern), String(seed.z)]
        }
        let digest = LiminalKnowledgeBindings.sha256(Data(pieces.map { "\($0.utf8.count):\($0)" }.joined().utf8))
        return .init(digest: digest, manifestSHA256: asset.manifestSHA256, originDigest: originDigest,
                     graphDigest: bindings.graphDigest, mapGraphDigest: mapDigest, viewport: viewport,
                     anchors: anchors, mapPoints: mapPoints, mapTargetsByRank: targets,
                     seedTargetsByRank: seedTargets,
                     finishDigest: asset.finish?.digest)
    }

    /// The runtime uses only authenticated nested prefixes. All bound points
    /// are in the lowest prefix, so adapting density cannot lose an anchor.
    func mapTargets(count: Int) -> [SIMD4<Float>] {
        paddedTargets(mapTargetsByRank, count: count)
    }

    func seedTargets(count: Int) -> [SIMD4<Float>] {
        paddedTargets(seedTargetsByRank, count: count)
    }

    private func paddedTargets(_ targets: [Int: SIMD4<Float>], count: Int) -> [SIMD4<Float>] {
        guard count > 0, count <= LiminalPointAsset.Detail.high.rawValue,
              targets.keys.allSatisfy({ $0 >= 0 && $0 < count }) else { return [] }
        var values = [SIMD4<Float>](repeating: .zero, count: count)
        for (rank, value) in targets { values[rank] = value }
        return values
    }

    /// -1 = gathered record motes, 0 = map, +1 = authored Beast. Nonfinite
    /// input falls back to the map; this value never enters saved appearance.
    static func boundedProgress(_ progress: Double) -> Double {
        progress.isFinite ? min(1, max(-1, progress)) : 0
    }

    static func signedSmoothstep(_ progress: Double) -> Float {
        let value = boundedProgress(progress)
        return value < 0 ? -smoothstep(-value) : smoothstep(value)
    }

    static func smoothstep(_ progress: Double) -> Float {
        let t = progress.isFinite ? Float(min(1, max(0, progress))) : 0
        return t * t * (3 - 2 * t)
    }

    static func interpolate(map: SIMD2<Float>, body: SIMD2<Float>, progress: Double) -> SIMD2<Float>? {
        guard finite(map), finite(body) else { return nil }
        let t = smoothstep(progress)
        if t == 0 { return map }
        if t == 1 { return body }
        return map * (1 - t) + body * t
    }

    static func interpolate(seed: SIMD2<Float>, map: SIMD2<Float>, body: SIMD2<Float>,
                            progress: Double) -> SIMD2<Float>? {
        guard finite(seed), finite(map), finite(body) else { return nil }
        let t = signedSmoothstep(progress)
        if t == -1 { return seed }
        if t == 0 { return map }
        if t == 1 { return body }
        return t < 0 ? map * (1 + t) - seed * t : map * (1 - t) + body * t
    }

    /// Match liminal_vertex's orthographic projection after authored finishing.
    /// Breathing is deliberately absent during morphing and inspection.
    static func bodyClipPosition(position: SIMD3<Float>, asset: LiminalPointAsset,
                                 frame: Int, viewport: CGSize) -> SIMD2<Float>? {
        guard validViewport(viewport), (1...120).contains(frame),
              position.x.isFinite, position.y.isFinite, position.z.isFinite else { return nil }
        let framing = LiminalSeedStyle.framing(center: asset.center, span: asset.span,
                                               frame: frame, refined: asset.finish != nil)
        guard framing.span.isFinite, framing.span > 0 else { return nil }
        let width = Float(viewport.width), height = Float(viewport.height), side = min(width, height)
        let result = (SIMD2(position.x, position.y) - SIMD2(framing.center.x, framing.center.y))
            * (2 / framing.span) * SIMD2(side / width, side / height)
        return finite(result) ? result : nil
    }

    /// Bounded CPU picking/overlay geometry from the exact loaded target frame.
    /// Rebuild the descriptor when viewport, graph, filters or owner changes.
    func anchorPositions(asset: LiminalPointAsset, frame: LiminalPointAsset.Frame,
                         progress: Double) -> [String: CGPoint] {
        guard asset.manifestSHA256 == manifestSHA256, asset.finish?.digest == finishDigest,
              frame.frame == Self.targetFrame, frame.pointCount > 0,
              frame.pointCount <= LiminalPointAsset.Detail.high.rawValue,
              frame.data.count == frame.pointCount * 32,
              anchors.allSatisfy({ $0.rank < frame.pointCount && $0.rank < asset.artIDs.count
                  && asset.artIDs[$0.rank] == $0.artID }) else { return [:] }
        var points: [String: CGPoint] = [:]
        for anchor in anchors where anchor.isVisible {
            guard let source = frame.sample(at: anchor.rank) else { return [:] }
            let finished = asset.finish?.display(source, rank: anchor.rank, frame: frame.frame) ?? source
            guard let body = Self.bodyClipPosition(position: finished.position, asset: asset, frame: frame.frame, viewport: viewport),
                  let clip = Self.interpolate(seed: anchor.seedClip, map: anchor.mapClip, body: body, progress: progress) else { return [:] }
            points[anchor.nodeID] = Self.screenPosition(clip: clip, viewport: viewport)
        }
        return points
    }

    static func clipPosition(point: CGPoint, viewport: CGSize) -> SIMD2<Float>? {
        guard validViewport(viewport), point.x.isFinite, point.y.isFinite else { return nil }
        let clip = SIMD2(Float(2 * point.x / viewport.width - 1), Float(1 - 2 * point.y / viewport.height))
        return finite(clip) ? clip : nil
    }

    static func screenPosition(clip: SIMD2<Float>, viewport: CGSize) -> CGPoint {
        CGPoint(x: CGFloat((clip.x + 1) * 0.5) * viewport.width,
                y: CGFloat((1 - clip.y) * 0.5) * viewport.height)
    }

    private static func clusterOffset(artID: UInt32, anchorID: UInt32) -> SIMD2<Float> {
        guard artID != anchorID else { return .zero }
        let key = "\(anchorID):\(artID)"
        let angle = KnowledgeParticleField.fraction(key, salt: "morph-cluster-angle") * 2 * .pi
        let radius = Double(maximumClusterOffset) * sqrt(KnowledgeParticleField.fraction(key, salt: "morph-cluster-radius"))
        return SIMD2(Float(cos(angle) * radius), Float(sin(angle) * radius))
    }
    private static func nodeMatches(map: CompanionGraphNode, full: CompanionGraphNode?) -> Bool {
        guard let full else { return false }
        if map == full { return true }
        // MemoryMapSnapshot intentionally has no working copy. The full graph
        // may have that exact copy open, changing only this derived status. Keep
        // the map's status and evidence intact; never admit a different version.
        guard map.kind == .lesson, full.kind == .lesson,
              map.status == "Waiting for shared copy", full.status == "Current",
              map.details.contains(where: { $0.label == "Bound source" && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return false }
        return CompanionGraphNode(id: map.id, title: map.title, subtitle: map.subtitle, kind: map.kind,
            status: full.status, details: map.details, target: map.target,
            presentationState: map.presentationState, evidenceTrail: map.evidenceTrail) == full
    }
    private static func finite(_ point: SIMD2<Float>) -> Bool { point.x.isFinite && point.y.isFinite }
    private static func validViewport(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width >= 1 && size.height >= 1
            && size.width <= 65_536 && size.height <= 65_536
    }
}
