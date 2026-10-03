import Foundation

/// The first native numerical domain adapter. These three coordinates express
/// bounded usefulness of task approaches, not model IQ/EQ or a person's traits.
/// Rebuild from the owner's current evidence window so redraws never advance
/// state, and revised/withdrawn reviews replace their earlier influence.
enum HamptonDocumentNumericalControl {
    static let version = "hampton-document-numerical-control/v1"
    static let coordinateSchema = "hampton-approach-usefulness/v1"
    static let coordinates = ["retainUsefulness", "expandUsefulness", "repairUsefulness"]
    static let lanes: [HamptonQ2ELane] = [.retain, .expand, .repair]
    static let initial = [0.5, 0.5, 0.5]
    static let identity: [[Double]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    // Authored v1 domain configuration. Positive evidence for retain/expand
    // modestly lowers the competing preference. This is not a learned causal M.
    static let couplingMatrix: [[Double]] = [[0.5, -0.125, 0], [-0.125, 0.5, 0], [0, 0, 0.5]]

    struct Step: Codable, Equatable, Sendable {
        let recordID: String
        let recordDigest: String
        let lane: HamptonQ2ELane
        let disposition: HamptonQ2EOutcomeBinding.Disposition
        let force: [Double]
        let candidate: HamptonNumericalDynamics.QuotientCandidate
        let coupling: HamptonNumericalDynamics.CouplingProposal
    }
    struct Receipt: Codable, Equatable, Sendable {
        let version: String
        let coordinateSchema: String
        let initial: [Double]
        let final: [Double]
        let steps: [Step]
        let laneAdjustments: [String: Double]
    }

    static func replay(evidence: HamptonQ2EOutcomeEvidence) -> Receipt? {
        guard evidence.isValid, evidence.reconciliationIssue == nil else { return nil }
        var state = initial
        var steps: [Step] = []
        var adjustments = Dictionary(uniqueKeysWithValues: lanes.map { ($0.rawValue, 0.0) })
        // Stable original task chronology; a later review edits that task's
        // observation without masquerading as an additional experience.
        let bindings = evidence.bindings.sorted {
            $0.createdAt == $1.createdAt ? $0.recordID < $1.recordID : $0.createdAt < $1.createdAt
        }
        do {
            for binding in bindings {
                // Fixed workControl guidance is delivered only to local Qwen.
                // An external reply cannot establish that this local approach
                // helped merely because a historical row carries a lane label.
                guard binding.provider == AssistantProvider.qwen.rawValue,
                      let lane = binding.attributedLane, let index = lanes.firstIndex(of: lane),
                      binding.disposition != .unknown else { continue }
                let observed = binding.disposition == .support ? 1.0 : 0.0
                var target = state
                target[index] = observed
                var innovation = [0.0, 0.0, 0.0]
                var error = innovation
                innovation[index] = observed
                error[index] = state[index]
                // The manuscript keeps the innovation and force terms distinct.
                // This declared domain adapter combines them before the bounded
                // finite step: d = eta * (L I - E + F). G=P=identity here.
                let force = try HamptonNumericalDynamics.intelligenceForce(previous: state,
                    target: target, potentialMatrix: identity, metricMatrix: identity, gain: 0.25)
                let drivenInnovation = zip(innovation, force).map(+)
                let candidate = try HamptonNumericalDynamics.boundedQuotientCandidate(
                    coordinates: coordinates, previous: state, innovation: drivenInnovation,
                    learningMatrix: identity, error: error,
                    configuration: .init(learningRate: 0.25, deltaMax: 0.125,
                        target: target, potentialMatrix: identity, allowedIncrease: 0, maxBacktracks: 12))
                let coupling = try HamptonNumericalDynamics.couple(candidate: candidate,
                    configuration: .init(sourceCoordinates: coordinates,
                        destinationCoordinates: lanes.map(\.rawValue), matrix: couplingMatrix,
                        spectralNormBound: 0.625))
                for (offset, destination) in lanes.enumerated() {
                    adjustments[destination.rawValue, default: 0] += coupling.destinationDelta[offset]
                }
                state = candidate.candidate
                steps.append(Step(recordID: binding.recordID, recordDigest: binding.recordDigest,
                    lane: lane, disposition: binding.disposition, force: force,
                    candidate: candidate, coupling: coupling))
            }
        } catch { return nil }
        return Receipt(version: version, coordinateSchema: coordinateSchema,
            initial: initial, final: state, steps: steps, laneAdjustments: adjustments)
    }
}
