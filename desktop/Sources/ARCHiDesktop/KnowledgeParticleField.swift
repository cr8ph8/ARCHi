import Foundation
import CryptoKit

/// Presentation coordinates over existing records. Motion never edits knowledge.
/// Liminal v008 supplies the bounded local-spin idea; these are native 2D paths,
/// not Houdini simulation output or a scientific particle-physics model.
struct KnowledgeParticleField {
    struct Vector: Codable, Equatable, Sendable {
        var x: Double
        var y: Double
        static let zero = Self(x: 0, y: 0)
        static func + (a: Self, b: Self) -> Self { .init(x: a.x + b.x, y: a.y + b.y) }
        static func - (a: Self, b: Self) -> Self { .init(x: a.x - b.x, y: a.y - b.y) }
        static func * (a: Self, b: Double) -> Self { .init(x: a.x * b, y: a.y * b) }
        var length: Double { hypot(x, y) }
        func bounded(_ limit: Double) -> Self { self * min(1, limit / max(length, 1e-9)) }
    }
    struct Particle: Equatable {
        let nodeID: String
        let kind: CompanionGraphKind
        let orb: Vector
        let constellation: Vector
        let phase: Double
    }
    /// Only inputs that change this field belong in its view-local cache key.
    /// Authored titles, details, status and chat text remain outside the layout.
    struct Topology: Equatable, Sendable {
        struct Node: Equatable, Sendable {
            let nodeID: String
            let kind: CompanionGraphKind
        }
        let nodes: [Node]
        let edges: [CompanionGraphEdge]
        let omittedCount: Int
    }

    /// A camera transform over particle coordinates, separate from their layout.
    struct Frame: Equatable, Sendable {
        let center: Vector
        let halfExtent: Double

        init(center: Vector, halfExtent: Double) {
            self.center = KnowledgeParticleField.finitePosition(center) ?? .zero
            self.halfExtent = halfExtent.isFinite
                ? min(KnowledgeParticleField.maximumCoordinate * 2, max(0.24, halfExtent)) : 1
        }

        func normalize(_ position: Vector) -> Vector {
            guard let position = KnowledgeParticleField.finitePosition(position) else { return .zero }
            return (position - center) * (1 / halfExtent)
        }
    }

    private static let maximumCoordinate = 1_000_000.0
    /// A bounded quadratic arc over the existing ID positions. The endpoint is
    /// derived from ID, not result rank, so filtering does not reshuffle it.
    static func regionPositions(base: [String: Vector], target: CGRect?, canvas: CGSize,
                                progress: Double) -> [String: Vector] {
        guard let target, !target.isNull, !target.isInfinite,
              [target.origin.x, target.origin.y, target.size.width, target.size.height, canvas.width, canvas.height].allSatisfy(\.isFinite),
              target.size.width > 0, target.size.height > 0, canvas.width > 36, canvas.height > 36,
              CGRect(origin: .zero, size: canvas).contains(target) else { return base }
        func bounded(_ p: Vector) -> Vector {
            // Keep both the selection ring and reviewed-support satellites in frame.
            .init(x: min(canvas.width - 18, max(18, p.x)), y: min(canvas.height - 18, max(18, p.y)))
        }
        return base.reduce(into: [:]) { result, pair in
            let (id, start) = pair
            let u = progress.isFinite ? min(1, max(0, progress)) : 0
            let t = u * u * (3 - 2 * u)
            let angle = fraction(id, salt: "region-anchor") * 2 * .pi
            let end = bounded(.init(x: target.midX + cos(angle) * (target.width / 2 + 22),
                                    y: target.midY + sin(angle) * (target.height / 2 + 22)))
            let mid = (start + end) * 0.5
            let control = bounded(mid + .init(x: -sin(angle), y: cos(angle)) * min(60, (end - start).length * 0.25))
            result[id] = start * ((1 - t) * (1 - t)) + control * (2 * (1 - t) * t) + end * (t * t)
        }
    }
    let particles: [Particle]
    let edges: [CompanionGraphEdge]
    let omittedCount: Int

    init(snapshot: CompanionGraphSnapshot) {
        self.init(topology: Self.topology(of: snapshot))
    }

    static func topology(of snapshot: CompanionGraphSnapshot) -> Topology {
        // IDs, not array indices or particle proximity, own the correspondence.
        var seen = Set<String>()
        let sorted = snapshot.nodes.sorted { $0.id < $1.id }
            .filter { seen.insert($0.id).inserted }
        let nodes = Array(sorted.prefix(CompanionGraph.maximumNodes))
        let ids = Set(nodes.map(\.id))
        var edgeIDs = Set<String>()
        let validEdges = snapshot.edges.sorted { $0.id < $1.id }.filter {
            ids.contains($0.source) && ids.contains($0.target) && edgeIDs.insert($0.id).inserted
        }
        let edges = Array(validEdges.prefix(CompanionGraph.maximumEdges))
        let omittedCount = snapshot.truncatedCount + max(0, sorted.count - nodes.count)
            + max(0, validEdges.count - edges.count)
        return .init(nodes: nodes.map { .init(nodeID: $0.id, kind: $0.kind) },
            edges: edges, omittedCount: omittedCount)
    }

    init(topology: Topology) {
        let nodes = topology.nodes
        edges = topology.edges
        omittedCount = topology.omittedCount
        let anchors: [Vector] = nodes.map { node in
            if node.kind == .companion { return .zero }
            let group = Double(CompanionGraphKind.allCases.firstIndex(of: node.kind) ?? 0)
            let angle = group * 2 * .pi / Double(CompanionGraphKind.allCases.count)
            let offset = Self.unit(node.nodeID, salt: "position")
            return Vector(x: cos(angle) * 0.55, y: sin(angle) * 0.55) + offset * 0.24
        }
        var relaxed = anchors
        // A bounded deterministic layout: repel crowding, weakly attract recorded
        // neighbours, and retain a type anchor. Forces carry no epistemic meaning.
        let indices = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($0.element.nodeID, $0.offset) })
        for _ in 0..<36 {
            var force = nodes.indices.map { (anchors[$0] - relaxed[$0]) * 0.04 }
            for a in nodes.indices {
                for b in nodes.indices where b > a {
                    var delta = relaxed[a] - relaxed[b]
                    if delta.length < 1e-6 { delta = Self.unit(nodes[a].nodeID + nodes[b].nodeID, salt: "separate") * 0.01 }
                    let push = delta * (0.0014 / max(0.002, delta.length * delta.length))
                    force[a] = force[a] + push; force[b] = force[b] - push
                }
            }
            for edge in edges {
                guard let a = indices[edge.source], let b = indices[edge.target] else { continue }
                let pull = (relaxed[b] - relaxed[a]) * 0.009
                force[a] = force[a] + pull; force[b] = force[b] - pull
            }
            for index in nodes.indices {
                relaxed[index] = nodes[index].kind == .companion ? .zero
                    : (relaxed[index] + force[index].bounded(0.04)).bounded(0.86)
            }
        }
        particles = nodes.enumerated().map { index, node in
            let point = Self.unit(node.nodeID, salt: "orb")
            let radius = 0.20 + 0.16 * Self.fraction(node.nodeID, salt: "radius")
            return .init(nodeID: node.nodeID, kind: node.kind,
                orb: node.kind == .companion ? .zero : point * radius,
                constellation: relaxed[index], phase: Self.fraction(node.nodeID, salt: "phase") * 2 * .pi)
        }
    }

    /// Supply the complete field and the unfiltered focus neighbourhood IDs.
    /// Search changes visibility only; it must not change this camera's inputs.
    static func framing(particles: [Particle], spread: Double, reduceMotion: Bool,
                        focusIDs: Set<String>? = nil) -> Frame {
        let positions = particles.compactMap { particle -> Vector? in
            guard focusIDs?.contains(particle.nodeID) ?? true else { return nil }
            return finitePosition(position(particle, spread: spread, reduceMotion: reduceMotion))
        }
        guard let first = positions.first else { return .init(center: .zero, halfExtent: 1) }
        var low = first, high = first
        for point in positions.dropFirst() {
            low.x = min(low.x, point.x); low.y = min(low.y, point.y)
            high.x = max(high.x, point.x); high.y = max(high.y, point.y)
        }
        let center = (low + high) * 0.5
        let radius = max(high.x - low.x, high.y - low.y) * 0.5
        // Keep particle centers inside 72% of the frame, with extra space for
        // halos and nearby labels. A minimum extent avoids single-node zoom.
        let t = spread.isFinite ? min(1, max(0, spread)) : 1
        // The Seed has an authored center. A single memory must not be recentered
        // over its pearl, and adding a record must not move existing Seed lights.
        let mapExtent = max(0.24, radius / 0.72 + 0.04)
        let cameraCenter = center * t
        let requiredExtent = positions.map { max(abs($0.x - cameraCenter.x), abs($0.y - cameraCenter.y)) }.max() ?? 0
        return .init(center: cameraCenter,
            halfExtent: max(0.54 * (1 - t) + mapExtent * t, requiredExtent / 0.72 + 0.04))
    }

    /// The Seed overlay and expanded map share this exact projection. Display
    /// filtering changes visibility only; use the complete field for framing.
    static func displayPositions(particles: [Particle], frame: Frame, spread: Double,
                                 reduceMotion: Bool, width: Double, height: Double,
                                 motionOffsets: [String: Vector] = [:]) -> [String: Vector] {
        let width = width.isFinite ? max(0, width) : 0
        let height = height.isFinite ? max(0, height) : 0
        let scale = max(0, min(width, height) * 0.43 - 12)
        let center = Vector(x: width / 2, y: height / 2)
        return particles.reduce(into: [:]) { points, particle in
            let t = spread.isFinite ? min(1, max(0, spread)) : 1
            let offset = motionOffsets[particle.nodeID].flatMap(finitePosition) ?? .zero
            let point = frame.normalize(position(particle, spread: spread, reduceMotion: reduceMotion)
                + offset * (0.4 + 0.6 * t))
            points[particle.nodeID] = center + point * scale
        }
    }

    /// A bounded visual motif for current reviewed support, never another record
    /// or an experience score. Unknown or inconsistent support adds no satellites.
    static func reviewedSatelliteCount(applications: Int, reviewedApplicationCount: Int) -> Int {
        min(6, max(0, min(applications, reviewedApplicationCount)))
    }

    private static func finitePosition(_ position: Vector) -> Vector? {
        guard position.x.isFinite, position.y.isFinite else { return nil }
        return .init(x: min(maximumCoordinate, max(-maximumCoordinate, position.x)),
            y: min(maximumCoordinate, max(-maximumCoordinate, position.y)))
    }

    /// Endpoint-exact bounded local curl; reduced motion removes the deviation.
    static func position(_ particle: Particle, spread: Double, reduceMotion: Bool) -> Vector {
        let t = spread.isFinite ? min(1, max(0, spread)) : 1
        let straight = particle.orb * (1 - t) + particle.constellation * t
        guard !reduceMotion, t > 0, t < 1 else { return straight }
        let envelope = pow(max(0, sin(.pi * t)), 1.5)
        let angle = 2 * Double.pi * 1.15 * t + particle.phase
        let deviation = Vector(x: cos(angle), y: sin(angle))
            * (min(0.065, 0.16 * (particle.constellation - particle.orb).length) * envelope)
        return straight + deviation
    }

    static func fraction(_ id: String, salt: String) -> Double {
        let digest = Array(SHA256.hash(data: Data((salt + ":" + id).utf8)))
        let value = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return Double(value) / Double(UInt32.max)
    }
    private static func unit(_ id: String, salt: String) -> Vector {
        let angle = fraction(id, salt: salt) * 2 * Double.pi
        return .init(x: cos(angle), y: sin(angle))
    }
}

/// Explicit local DCC export. No titles, source bodies, prompts or attribution.
/// The string node ID survives point reordering; ptnum is never knowledge identity.
struct KnowledgeParticleExport: Codable {
    struct Node: Codable {
        let nodeID: String
        let kind: String
        let orb: KnowledgeParticleField.Vector
        let constellation: KnowledgeParticleField.Vector
    }
    struct Edge: Codable { let id: String; let source: String; let target: String; let relationship: String }
    let schema: String
    let scope: String
    let omittedCount: Int
    let nodes: [Node]
    let edges: [Edge]
    init(field: KnowledgeParticleField) {
        schema = "archi-knowledge-particles/v1"
        scope = "Read-only presentation snapshot; IDs and recorded relationships only. No knowledge write-back."
        omittedCount = field.omittedCount
        nodes = field.particles.map { .init(nodeID: $0.nodeID, kind: $0.kind.rawValue, orb: $0.orb, constellation: $0.constellation) }
        edges = field.edges.map { .init(id: $0.id, source: $0.source, target: $0.target, relationship: $0.label) }
    }
    func data() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
