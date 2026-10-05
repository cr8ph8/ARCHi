import Foundation

/// ARC3's bounded task-usefulness adaptation. These frozen authored coefficients
/// match the document adapters; coordinate meanings and receipt identity remain
/// separate. No game coordinates, latent intelligence or companion development
/// state transfers through this matrix.
enum HamptonARC3NumericalControl {
    static let version = "hampton-arc3-numerical-control/v1"
    static let coordinateSchema = "hampton-arc3-approach-usefulness/v1"
    static let coordinates = ["retainARC3Usefulness", "expandARC3Usefulness", "repairARC3Usefulness"]
    static let lanes = HamptonApproachNumericalPolicy.lanes
    static let initial = HamptonApproachNumericalPolicy.initial

    struct Step: Codable, Equatable, Sendable {
        let attemptID: String
        let bindingDigest: String
        let lane: HamptonQ2ELane
        let useful: Bool
        let force: [Double]
        let candidate: HamptonNumericalDynamics.QuotientCandidate
        let coupling: HamptonNumericalDynamics.CouplingProposal
    }
    struct Receipt: Codable, Equatable, Sendable {
        let version: String
        let coordinateSchema: String
        let evidenceDigest: String
        let initial: [Double]
        let final: [Double]
        let steps: [Step]
        let laneAdjustments: [String: Double]
    }
    static func replay(evidence: HamptonARC3OutcomeEvidence) -> Receipt? {
        guard evidence.isValid, evidence.reconciliationIssue == nil else { return nil }
        var state = initial
        var steps: [Step] = []
        var adjustments = Dictionary(uniqueKeysWithValues: lanes.map { ($0.rawValue, 0.0) })
        // Rebuild from the current eight-outcome projection every time. A RESET,
        // invalidation or replaced record removes its former influence.
        let bindings = evidence.bindings.sorted { $0.baseDispatches < $1.baseDispatches }
        do {
            for binding in bindings {
                guard let useful = binding.useful, lanes.contains(binding.attributedLane) else { continue }
                let update = try HamptonApproachNumericalPolicy.update(coordinates: coordinates,
                    previous: state, lane: binding.attributedLane, useful: useful)
                let force = update.force, candidate = update.candidate, coupling = update.coupling
                for (offset, lane) in lanes.enumerated() {
                    adjustments[lane.rawValue, default: 0] += coupling.destinationDelta[offset]
                }
                state = candidate.candidate
                steps.append(Step(attemptID: binding.attemptID, bindingDigest: binding.digest,
                    lane: binding.attributedLane, useful: useful, force: force, candidate: candidate, coupling: coupling))
            }
        } catch { return nil }
        return Receipt(version: version, coordinateSchema: coordinateSchema, evidenceDigest: evidence.digest,
            initial: initial, final: state, steps: steps, laneAdjustments: adjustments)
    }
}
