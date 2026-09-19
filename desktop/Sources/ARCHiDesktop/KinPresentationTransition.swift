import Foundation

/// A short, reversible presentation of an already accepted body choice. This
/// value owns no identity, evidence, persistence or delayed completion callback.
/// It dissolves the reviewed portraits; it is not a 3D mesh morph.
struct KinPresentationTransition: Equatable, Sendable {
    static let duration: TimeInterval = 1.2

    enum Form: Double, Equatable, Sendable {
        case seed = 0, firstLight = 1
    }

    struct Policy: Equatable, Sendable {
        let isStatic: Bool

        init(quiet: Bool = false, reduceMotion: Bool = false, systemReduceMotion: Bool = false) {
            isStatic = quiet || reduceMotion || systemReduceMotion
        }
    }

    struct Sample: Equatable, Sendable {
        let bodyAmount: Double
        let isTransitioning: Bool
        var seedOpacity: Double { 1 - bodyAmount }
        var bodyOpacity: Double { bodyAmount }
        // Carry the pearl from the existing Seed center into the existing body's
        // chest. Neither source image nor the app-owned outer frame is changed.
        var coreX: Double { 0.5 + 0.02 * bodyAmount }
        var coreY: Double { 0.5 + 0.12 * bodyAmount }
        var seedScale: Double { max(0.32, 1 - 0.68 * bodyAmount) }
        var bodyScale: Double { 0.76 + 0.24 * bodyAmount }
    }

    private(set) var target: Form
    private(set) var policy: Policy
    private var anchorTime: TimeInterval
    private var initialAmount: Double
    private var travelDuration: TimeInterval = 0

    init(form: Form, policy: Policy = .init(), at time: TimeInterval = 0) {
        target = form
        self.policy = policy
        initialAmount = form.rawValue
        anchorTime = time.isFinite && time >= 0 ? time : 0
    }

    mutating func transition(to form: Form, policy next: Policy, at time: TimeInterval) {
        guard time.isFinite, time >= anchorTime, form != target || next != policy else { return }
        let current = sample(at: time).bodyAmount
        anchorTime = time
        target = form
        policy = next
        // Accessibility/Quiet selects the exact accepted destination immediately.
        // Disabling it later cannot revive an interrupted animation.
        initialAmount = next.isStatic ? form.rawValue : current
        travelDuration = next.isStatic ? 0 : Self.duration * abs(form.rawValue - current)
    }

    func sample(at time: TimeInterval) -> Sample {
        let elapsed = time.isFinite && time >= anchorTime ? time - anchorTime : 0
        guard travelDuration > 0, elapsed < travelDuration else {
            return .init(bodyAmount: target.rawValue, isTransitioning: false)
        }
        let fraction = elapsed / travelDuration
        let eased = fraction * fraction * (3 - 2 * fraction)
        let amount = initialAmount + (target.rawValue - initialAmount) * eased
        return .init(bodyAmount: min(1, max(0, amount)), isTransitioning: true)
    }
}
