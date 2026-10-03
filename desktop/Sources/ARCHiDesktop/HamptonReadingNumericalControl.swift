import Foundation

/// Reading-specific adaptation of the native finite-step primitives. Frozen
/// coefficients match the first document adapter, while evidence, coordinate
/// schema and receipt version remain distinct. These are task-usefulness
/// coordinates, not latent intelligence measures or reading truth scores.
enum HamptonReadingNumericalControl {
    static let version = "hampton-reading-numerical-control/v1"
    static let coordinateSchema = "hampton-reading-approach-usefulness/v1"
    static let coordinates = ["retainReadingUsefulness", "expandReadingUsefulness", "repairReadingUsefulness"]
    static let lanes: [HamptonQ2ELane] = [.retain, .expand, .repair]
    static let initial = [0.5, 0.5, 0.5]
    static let identity: [[Double]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    static let couplingMatrix: [[Double]] = [[0.5, -0.125, 0], [-0.125, 0.5, 0], [0, 0, 0.5]]

    struct Step: Codable, Equatable, Sendable {
        let taskID: String
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

    static func replay(evidence: HamptonReadingOutcomeEvidence) -> Receipt? {
        guard evidence.isValid, evidence.reconciliationIssue == nil else { return nil }
        var state = initial
        var steps: [Step] = []
        var adjustments = Dictionary(uniqueKeysWithValues: lanes.map { ($0.rawValue, 0.0) })
        // Rebuild in task chronology. Reversing a review replaces that task's
        // observation; previewing again never creates an extra update.
        let bindings = evidence.bindings.sorted {
            $0.startedAt == $1.startedAt ? $0.taskID < $1.taskID : $0.startedAt < $1.startedAt
        }
        do {
            for binding in bindings {
                guard let useful = binding.useful, let index = lanes.firstIndex(of: binding.attributedLane) else { continue }
                let observed = useful ? 1.0 : 0.0
                var target = state
                target[index] = observed
                var innovation = [0.0, 0.0, 0.0]
                var error = innovation
                innovation[index] = observed
                error[index] = state[index]
                let force = try HamptonNumericalDynamics.intelligenceForce(previous: state,
                    target: target, potentialMatrix: identity, metricMatrix: identity, gain: 0.25)
                // Declared domain choice: d = eta * (L I - E + F), with
                // identity L/P/G. The measured effective delta drives M.
                let candidate = try HamptonNumericalDynamics.boundedQuotientCandidate(
                    coordinates: coordinates, previous: state, innovation: zip(innovation, force).map(+),
                    learningMatrix: identity, error: error,
                    configuration: .init(learningRate: 0.25, deltaMax: 0.125,
                        target: target, potentialMatrix: identity, allowedIncrease: 0, maxBacktracks: 12))
                let coupling = try HamptonNumericalDynamics.couple(candidate: candidate,
                    configuration: .init(sourceCoordinates: coordinates,
                        destinationCoordinates: lanes.map(\.rawValue), matrix: couplingMatrix,
                        spectralNormBound: 0.625))
                for (offset, lane) in lanes.enumerated() {
                    adjustments[lane.rawValue, default: 0] += coupling.destinationDelta[offset]
                }
                state = candidate.candidate
                steps.append(Step(taskID: binding.taskID, bindingDigest: binding.digest,
                    lane: binding.attributedLane, useful: useful, force: force, candidate: candidate, coupling: coupling))
            }
        } catch { return nil }
        return Receipt(version: version, coordinateSchema: coordinateSchema, evidenceDigest: evidence.digest,
            initial: initial, final: state, steps: steps, laneAdjustments: adjustments)
    }
}
