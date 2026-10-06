import Foundation

extension CompanionParticleScene {
    /// The same saved graph reopened in a different native session is not the
    /// same simulation or interaction authority.
    nonisolated var motionID: String { sessionID + ":" + digest }
}

/// One transient presentation clock over the current native scene. Coordinates
/// and gestures never write records, add support or alter source permissions.
@MainActor
final class CompanionParticleMotion {
    struct Frame: Equatable, Sendable {
        let offsets: [String: KnowledgeParticleField.Vector]
        let revision: UInt64
        /// Projection of actual displacement onto each live attraction target.
        /// Released targets disappear here while their offsets keep settling.
        let attractionProgress: [String: Double]
        init(offsets: [String: KnowledgeParticleField.Vector], revision: UInt64,
             attractionProgress: [String: Double] = [:]) {
            self.offsets = offsets; self.revision = revision
            self.attractionProgress = attractionProgress
        }
        static let still = Self(offsets: [:], revision: 0)
    }

    private var sceneDigest: String?
    private var sessionID: String?
    private var originDigest: String?
    private var dynamics = CompanionParticleDynamics()
    private var revision: UInt64 = 0
    private var lastTick: Double?
    private var latestTime: Double?
    private var attractionLease: UUID?
    private var attractionUpdatedAt: Double?
    private var running = false
    private static let step = 1.0 / 120.0
    private static let maximumSteps = 8

    func reconcile(scene: CompanionParticleScene) {
        if sessionID != scene.sessionID || originDigest != scene.originDigest { reset() }
        guard sceneDigest != scene.motionID else { return }
        let before = dynamics.offsets
        clearAttraction()
        dynamics.reconcile(scene: scene)
        sceneDigest = scene.motionID; sessionID = scene.sessionID; originDigest = scene.originDigest
        if before != dynamics.offsets { revision &+= 1 }
    }

    func reset() {
        sceneDigest = nil; sessionID = nil; originDigest = nil
        dynamics = CompanionParticleDynamics(); revision = 0
        lastTick = nil; latestTime = nil; running = false
        attractionLease = nil; attractionUpdatedAt = nil
    }

    /// sceneDigest is the scene's composite motionID, including its session.
    /// All surfaces use the same monotonic timestamp. Quantization prevents two
    /// views in one display interval from advancing two different simulations.
    /// Visibility is supplied for the shared presentation, not a single hidden view.
    func sample(sceneDigest: String, time: Double, active: Bool, reduceMotion: Bool) -> Frame {
        guard self.sceneDigest == sceneDigest else { return .still }
        guard time.isFinite, time >= 0, time <= 1e12 else { return frame }
        guard active, !reduceMotion else {
            lastTick = floor(max(time, latestTime ?? time) / Self.step)
            latestTime = max(time, latestTime ?? time); running = false
            dynamics.cancelInteraction(); clearAttraction()
            return frame
        }
        guard time >= (latestTime ?? 0) else { return frame }
        latestTime = time
        if let updated = attractionUpdatedAt, time - updated > 0.5 { clearAttraction() }
        let tick = floor(time / Self.step)
        guard running, let previous = lastTick else {
            lastTick = tick; running = true
            return frame
        }
        guard tick > previous else { return frame }
        guard tick - previous <= 24 else {
            lastTick = tick
            return frame
        }
        let steps = Int(min(Double(Self.maximumSteps), tick - previous))
        // Drop excess wall time instead of integrating an unbounded catch-up.
        lastTick = tick
        guard !dynamics.isSleeping else { return frame }
        let before = dynamics.offsets
        for _ in 0..<steps { dynamics.step(Self.step) }
        if before != dynamics.offsets { revision &+= 1 }
        return frame
    }

    /// A hidden/still surface reads without stopping another visible driver.
    func snapshot(sceneDigest: String) -> Frame {
        self.sceneDigest == sceneDigest ? frame : .still
    }

    /// The offset is measured from this exact scene's rest constellation.
    @discardableResult
    func grab(nodeID: String, offset: KnowledgeParticleField.Vector, sceneDigest: String) -> Bool {
        guard self.sceneDigest == sceneDigest else { return false }
        let before = dynamics.offsets
        guard dynamics.grab(nodeID: nodeID, offset: offset) else { return false }
        if before != dynamics.offsets { revision &+= 1 }
        return true
    }

    func release(nodeID: String, sceneDigest: String) {
        guard self.sceneDigest == sceneDigest else { return }
        dynamics.release(nodeID: nodeID)
    }

    func cancelInteraction() { dynamics.cancelInteraction(); clearAttraction() }

    /// Acquisition/source review belongs to the caller. This lease grants only
    /// transient forces over this exact current scene; a newer producer wins.
    func beginAttraction(sceneDigest: String) -> UUID? {
        guard self.sceneDigest == sceneDigest else { return nil }
        clearAttraction()
        let lease = UUID(); attractionLease = lease
        return lease
    }

    func isAttractionCurrent(lease: UUID, sceneDigest: String) -> Bool {
        self.sceneDigest == sceneDigest && attractionLease == lease
    }

    /// Use the same monotonic time domain as sample. Updates older than the
    /// already displayed/sampled frame cannot change that frame's force input.
    @discardableResult
    func updateAttraction(lease: UUID, sceneDigest: String,
                          offsets: [String: KnowledgeParticleField.Vector], time: Double) -> Bool {
        guard isAttractionCurrent(lease: lease, sceneDigest: sceneDigest),
              time.isFinite, time >= 0, time <= 1e12,
              time >= (latestTime ?? 0), time >= (attractionUpdatedAt ?? 0) else { return false }
        // A delayed producer cannot renew a lease after its freshness deadline,
        // even if no visible surface sampled the interval in between.
        if let updated = attractionUpdatedAt, time - updated > 0.5 {
            clearAttraction(); return false
        }
        let before = dynamics.attractionProgress
        guard dynamics.setAttraction(offsets: offsets) else { return false }
        attractionUpdatedAt = time; latestTime = time
        if before != dynamics.attractionProgress { revision &+= 1 }
        return true
    }

    func endAttraction(lease: UUID) {
        guard attractionLease == lease else { return }
        clearAttraction()
    }

    private func clearAttraction() {
        if !dynamics.attractionProgress.isEmpty { revision &+= 1 }
        dynamics.clearAttraction()
        attractionLease = nil; attractionUpdatedAt = nil
    }

    private var frame: Frame {
        .init(offsets: dynamics.offsets, revision: revision, attractionProgress: dynamics.attractionProgress)
    }
}

/// Bounded damped springs around the authored record layout. Pair forces are
/// measured relative to that rest layout, so a settled field remains still
/// and released movement settles without random driving or new relationships.
struct CompanionParticleDynamics {
    typealias Vector = KnowledgeParticleField.Vector
    struct Body {
        var rest: Vector
        var position: Vector
        var velocity: Vector
        var damping: Double
    }
    static let maximumGrabOffset = 0.25
    static let maximumAttractionOffset = 0.65
    static let maximumPosition = 1.5
    static let maximumVelocity = 1.5
    // Record IDs are resolved only at scene/interaction boundaries. The fixed
    // step uses dense indices, avoiding string hashing for every force pair.
    private var ids: [String] = []
    private var indices: [String: Int] = [:]
    private var states: [Body] = []
    private var goals: [Vector] = []
    private var forces: [Vector] = []
    var bodies: [String: Body] {
        Dictionary(uniqueKeysWithValues: zip(ids, states))
    }
    private(set) var isSleeping = true
    private var settledSteps = 0
    private var links: [(Int, Int)] = []
    private var pins: [Vector?] = []
    private var pinCount = 0
    private var canAttract: [Bool] = []
    private var attractionOffsets: [Vector?] = []
    private var attractionIndices: [Int] = []
    private struct Pair {
        let left: Int
        let right: Int
        let fallback: Vector
        let restRepulsion: Vector
        var goalRepulsion: Vector
    }
    private var pairs: [Pair] = []

    var offsets: [String: Vector] {
        var result: [String: Vector] = [:]
        result.reserveCapacity(ids.count)
        for index in states.indices { result[ids[index]] = states[index].position - states[index].rest }
        return result
    }

    var attractionProgress: [String: Double] {
        var result: [String: Double] = [:]
        for index in attractionIndices {
            guard let target = attractionOffsets[index] else { continue }
            let offset = states[index].position - states[index].rest
            let fraction = (offset.x * target.x + offset.y * target.y) / (target.x * target.x + target.y * target.y)
            result[ids[index]] = min(1, max(0, fraction))
        }
        return result
    }

    mutating func reconcile(scene: CompanionParticleScene) {
        let currentIDs = Set(scene.graph.nodes.filter { $0.presentationState != .withdrawn }.map(\.id))
        var nextIDs: [String] = [], nextStates: [Body] = [], nextCanAttract: [Bool] = []
        nextIDs.reserveCapacity(currentIDs.count); nextStates.reserveCapacity(currentIDs.count)
        for particle in scene.field.particles where currentIDs.contains(particle.nodeID) {
            let count = min(8, max(0, scene.growthByRecordID[particle.nodeID]?.reviewedApplicationCount ?? 0))
            let damping = 4.2 + Double(count) * 0.12
            nextIDs.append(particle.nodeID)
            nextCanAttract.append(particle.kind != .companion)
            if let index = indices[particle.nodeID] {
                var existing = states[index]
                existing.rest = particle.constellation
                existing.damping = damping
                nextStates.append(existing)
            } else {
                nextStates.append(.init(rest: particle.constellation, position: particle.constellation,
                    // A single reproducible appearance impulse; no ongoing noise.
                    velocity: particle.kind == .companion ? .zero
                        : Vector(x: cos(particle.phase), y: sin(particle.phase)) * 0.035,
                    damping: damping))
            }
        }
        ids = nextIDs; states = nextStates
        goals = states.map(\.rest)
        canAttract = nextCanAttract
        attractionOffsets = .init(repeating: nil, count: states.count); attractionIndices = []
        indices = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
        forces = .init(repeating: .zero, count: states.count)
        links = scene.field.edges.compactMap { edge in
            guard let left = indices[edge.source], let right = indices[edge.target] else { return nil }
            return (left, right)
        }
        pairs.removeAll(keepingCapacity: true)
        pairs.reserveCapacity(states.count * max(0, states.count - 1) / 2)
        for left in states.indices {
            for right in (left + 1)..<states.count {
                let phase = KnowledgeParticleField.fraction(ids[left] + ":" + ids[right], salt: "motion-separation") * 2 * .pi
                let fallback = Vector(x: cos(phase), y: sin(phase))
                let rest = states[left].rest - states[right].rest
                let repulsion = Self.repulsion(rest, fallback: fallback)
                pairs.append(.init(left: left, right: right, fallback: fallback,
                    restRepulsion: repulsion, goalRepulsion: repulsion))
            }
        }
        // A changed scene invalidates the captured gesture even when other IDs
        // survive. Released coordinates and momentum continue from their old state.
        pins = .init(repeating: nil, count: states.count); pinCount = 0
        wake()
    }

    mutating func grab(nodeID: String, offset: Vector) -> Bool {
        guard offset.x.isFinite, offset.y.isFinite, let index = indices[nodeID] else { return false }
        wake()
        let target = states[index].rest + offset.bounded(Self.maximumGrabOffset)
        if pins[index] == nil { pinCount += 1 }
        pins[index] = target
        states[index].position = target; states[index].velocity = .zero
        return true
    }

    mutating func release(nodeID: String) {
        if let index = indices[nodeID], pins[index] != nil {
            pins[index] = nil; pinCount -= 1; wake()
        }
    }
    mutating func cancelInteraction() {
        if pinCount > 0 {
            pins = .init(repeating: nil, count: states.count); pinCount = 0; wake()
        }
    }

    /// Validate the whole update before replacing any target. The same links and
    /// repulsion use these temporary goals as their shared equilibrium. No body
    /// is pinned or teleported, and the original baselines remain restorable.
    mutating func setAttraction(offsets: [String: Vector]) -> Bool {
        var next = [Vector?](repeating: nil, count: states.count)
        for (id, offset) in offsets {
            guard offset.x.isFinite, offset.y.isFinite,
                  let index = indices[id], canAttract[index] else { return false }
            // Keep the effective goal reachable under the existing absolute
            // position bound, including anchors already near its outer edge.
            let bounded = (states[index].rest + offset.bounded(Self.maximumAttractionOffset))
                .bounded(Self.maximumPosition) - states[index].rest
            if bounded.length > 1e-9 { next[index] = bounded }
        }
        if attractionOffsets != next {
            attractionOffsets = next
            attractionIndices = next.indices.filter { next[$0] != nil }
            refreshAttractionGoals()
            wake()
        }
        return true
    }

    mutating func clearAttraction() {
        guard !attractionIndices.isEmpty else { return }
        for index in attractionIndices { attractionOffsets[index] = nil }
        attractionIndices = []; refreshAttractionGoals(); wake()
    }

    private mutating func refreshAttractionGoals() {
        for index in states.indices {
            goals[index] = attractionOffsets[index].map { states[index].rest + $0 } ?? states[index].rest
        }
        if attractionIndices.isEmpty {
            for index in pairs.indices { pairs[index].goalRepulsion = pairs[index].restRepulsion }
        } else {
            for index in pairs.indices {
                let pair = pairs[index]
                pairs[index].goalRepulsion = Self.repulsion(goals[pair.left] - goals[pair.right], fallback: pair.fallback)
            }
        }
    }

    private mutating func wake() { isSleeping = states.isEmpty; settledSteps = 0 }

    mutating func step(_ elapsed: Double) {
        guard !isSleeping, elapsed.isFinite, elapsed > 0 else { return }
        let dt = min(1.0 / 120.0, elapsed)
        for index in states.indices { forces[index] = (goals[index] - states[index].position) * 18 }
        for (left, right) in links {
            let a = states[left], b = states[right]
            let force = ((b.position - a.position) - (goals[right] - goals[left])) * 3
            forces[left] = forces[left] + force
            forces[right] = forces[right] - force
        }
        for pair in pairs {
            let a = states[pair.left], b = states[pair.right]
            let force = (Self.repulsion(a.position - b.position, fallback: pair.fallback)
                - pair.goalRepulsion).bounded(6)
            forces[pair.left] = forces[pair.left] + force
            forces[pair.right] = forces[pair.right] - force
        }
        var settled = true
        for index in states.indices {
            var body = states[index]
            if let pin = pins[index] { body.position = pin; body.velocity = .zero }
            else {
                let acceleration = forces[index].bounded(24)
                body.velocity = ((body.velocity + acceleration * dt) * exp(-body.damping * dt))
                    .bounded(Self.maximumVelocity)
                body.position = (body.position + body.velocity * dt).bounded(Self.maximumPosition)
                if (body.position - goals[index]).length < 1e-7, body.velocity.length < 1e-7 {
                    body.position = goals[index]; body.velocity = .zero
                }
                if body.velocity.length >= 1e-6 || acceleration.length >= 1e-5 { settled = false }
            }
            states[index] = body
        }
        settledSteps = settled ? settledSteps + 1 : 0
        if settledSteps >= 24 {
            // No visual displacement is introduced by sleep. An explicit input,
            // release or reconciled scene wakes the same continuing positions.
            isSleeping = true
            for index in states.indices { states[index].velocity = .zero }
        }
    }

    private static func repulsion(_ delta: Vector, fallback: Vector) -> Vector {
        let distance = delta.length
        let direction = distance > 1e-8 ? delta * (1 / distance) : fallback
        return direction * (0.0012 / max(0.0036, distance * distance))
    }
}
