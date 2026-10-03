import Foundation

/// ARC3's bounded task-usefulness adaptation. These frozen authored coefficients
/// match the document adapters; coordinate meanings and receipt identity remain
/// separate. No game coordinates, latent intelligence or companion development
/// state transfers through this matrix.
enum HamptonARC3NumericalControl {
    static let version = "hampton-arc3-numerical-control/v1"
    static let coordinateSchema = "hampton-arc3-approach-usefulness/v1"
    static let coordinates = ["retainARC3Usefulness", "expandARC3Usefulness", "repairARC3Usefulness"]
    static let lanes: [HamptonQ2ELane] = [.retain, .expand, .repair]
    static let initial = [0.5, 0.5, 0.5]
    static let identity: [[Double]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    static let couplingMatrix: [[Double]] = [[0.5, -0.125, 0], [-0.125, 0.5, 0], [0, 0, 0.5]]

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
                guard let useful = binding.useful, let index = lanes.firstIndex(of: binding.attributedLane) else { continue }
                let observed = useful ? 1.0 : 0.0
                var target = state
                target[index] = observed
                var innovation = [0.0, 0.0, 0.0]
                var error = innovation
                innovation[index] = observed; error[index] = state[index]
                let force = try HamptonNumericalDynamics.intelligenceForce(previous: state,
                    target: target, potentialMatrix: identity, metricMatrix: identity, gain: 0.25)
                let candidate = try HamptonNumericalDynamics.boundedQuotientCandidate(
                    coordinates: coordinates, previous: state, innovation: zip(innovation, force).map(+),
                    learningMatrix: identity, error: error,
                    configuration: .init(learningRate: 0.25, deltaMax: 0.125,
                        target: target, potentialMatrix: identity, allowedIncrease: 0, maxBacktracks: 12))
                let coupling = try HamptonNumericalDynamics.couple(candidate: candidate,
                    configuration: .init(sourceCoordinates: coordinates, destinationCoordinates: lanes.map(\.rawValue),
                        matrix: couplingMatrix, spectralNormBound: 0.625))
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
