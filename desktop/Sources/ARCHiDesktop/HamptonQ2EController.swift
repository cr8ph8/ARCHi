import Foundation
import CryptoKit

/// Native translation of QuotientSchema(NATIVE_PRESSURES) in
/// research/representation/archi_repe/stack_contracts.py. These definitions come
/// from docs/native-q2e-control.md; they are neither the archived 18 coordinates
/// nor model activation assays. The schema is fixed, not caller-authored data.
enum HamptonQ2ECoordinateSchema {
    static let id = "hampton-native-five-pressures/v1"
    struct Coordinate: Equatable, Sendable {
        let name: String
        let definition: String
        let unit: String
        let range = 0.0...1.0
    }
    static let coordinates = [
        Coordinate(name: "support", definition: "Beta(1,1) statistic from retained support and correction counts", unit: "dimensionless"),
        Coordinate(name: "coveragePressure", definition: "One minus support when alternatives exist; otherwise one", unit: "dimensionless"),
        Coordinate(name: "verifierPressure", definition: "Clipped authored pressure 0.20 corrections + 0.15 unchanged steps", unit: "dimensionless"),
        Coordinate(name: "alternativeCoverage", definition: "Clipped available-alternative count divided by eight", unit: "dimensionless"),
        Coordinate(name: "resourceRemaining", definition: "Remaining divided by total domain action budget", unit: "action-budget fraction")
    ]
    static var names: Set<String> { Set(coordinates.map(\.name)) }
    static func contains(_ values: [String: Double]) -> Bool {
        Set(values.keys) == names && values.values.allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

/// Bounded content reference, not a recursive copy of the decision history.
/// Its digest links to the existing owner's original decision. Structural
/// validation cannot authenticate a supplied history or invent an old revision.
struct HamptonQ2EPredecessor: Codable, Equatable, Sendable {
    let version: String
    let domain: String
    let contextID: String
    let revision: Int
    let pressures: [String: Double]
    let decisionDigest: String

    init(_ decision: HamptonQ2EDecision) {
        version = decision.version; domain = decision.domain; contextID = decision.contextID
        revision = decision.revision; pressures = decision.pressures; decisionDigest = decision.bindingDigest
    }
    var isValid: Bool {
        HamptonQ2EController.supportedVersions.contains(version)
            && (1...10_001).contains(revision) && HamptonQ2ECoordinateSchema.contains(pressures)
            && decisionDigest.utf8.count == 64
            && decisionDigest.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

/// Native operational adaptation of qstate_controller.py and
/// qstate_coupling_matrix.py. Inputs are admitted domain observations, never
/// model confidence. The coefficients below are authored policy, not learned
/// coupling, a universal intelligence score, or a stability certificate.
enum HamptonQ2ELane: String, Codable, Sendable {
    case retain, expand, repair, stop

    var title: String {
        switch self {
        case .retain: "Reuse supported work"
        case .expand: "Try a bounded alternative"
        case .repair: "Correct before continuing"
        case .stop: "Pause and review"
        }
    }
}

/// Shared, frozen v1 approach policy. Domain adapters retain their own evidence
/// admission, chronology, coordinate names and receipts; only the pure numerical
/// step is shared. These authored coefficients are not learned intelligence.
enum HamptonApproachNumericalPolicy {
    static let lanes: [HamptonQ2ELane] = [.retain, .expand, .repair]
    static let initial = [0.5, 0.5, 0.5]
    static let identity: [[Double]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    static let couplingMatrix: [[Double]] = [[0.5, -0.125, 0], [-0.125, 0.5, 0], [0, 0, 0.5]]

    struct Update {
        let force: [Double]
        let candidate: HamptonNumericalDynamics.QuotientCandidate
        let coupling: HamptonNumericalDynamics.CouplingProposal
    }

    static func update(coordinates: [String], previous: [Double],
                       lane: HamptonQ2ELane, useful: Bool) throws -> Update {
        guard coordinates.count == lanes.count, previous.count == lanes.count,
              let index = lanes.firstIndex(of: lane) else {
            throw HamptonNumericalDynamics.Failure.invalidInput("approach coordinates or lane")
        }
        let observed = useful ? 1.0 : 0.0
        var target = previous
        target[index] = observed
        var innovation = [0.0, 0.0, 0.0]
        var error = innovation
        innovation[index] = observed
        error[index] = previous[index]
        let force = try HamptonNumericalDynamics.intelligenceForce(previous: previous,
            target: target, potentialMatrix: identity, metricMatrix: identity, gain: 0.25)
        // Domain policy: d = eta * (L I - E + F), with L/P/G = identity.
        // Preserve the operation order used by existing v1 replay receipts.
        let candidate = try HamptonNumericalDynamics.boundedQuotientCandidate(
            coordinates: coordinates, previous: previous, innovation: zip(innovation, force).map(+),
            learningMatrix: identity, error: error,
            configuration: .init(learningRate: 0.25, deltaMax: 0.125,
                target: target, potentialMatrix: identity, allowedIncrease: 0, maxBacktracks: 12))
        let coupling = try HamptonNumericalDynamics.couple(candidate: candidate,
            configuration: .init(sourceCoordinates: coordinates, destinationCoordinates: lanes.map(\.rawValue),
                matrix: couplingMatrix, spectralNormBound: 0.625))
        return Update(force: force, candidate: candidate, coupling: coupling)
    }
}

struct HamptonQ2EStrategyEvidence: Codable, Equatable, Sendable {
    let helpful: Int
    let corrections: Int
    var isValid: Bool { (0...10_000).contains(helpful) && (0...10_000).contains(corrections) }
    /// Beta-Bernoulli outcome critic from Qi Experiments. Unknown outcomes are
    /// absent; each retained outcome contributes to one native strategy only.
    var mean: Double { (Double(helpful) + 1) / (Double(helpful) + Double(corrections) + 2) }
}

struct HamptonQ2ESignals: Codable, Equatable, Sendable {
    let observations: Int
    let retainedSupport: Int
    let contradictions: Int
    let unchangedSteps: Int
    let availableAlternatives: Int
    let remainingBudget: Int
    let totalBudget: Int
    var prerequisitesSatisfied: Bool = true
    var strategyResults: [String: HamptonQ2EStrategyEvidence] = [:]

    var isValid: Bool {
        (0...10_000).contains(observations)
            && (0...observations).contains(retainedSupport)
            && (0...observations).contains(contradictions)
            && (0...observations).contains(unchangedSteps)
            && (0...4096).contains(availableAlternatives)
            && (1...1500).contains(totalBudget)
            && (0...totalBudget).contains(remainingBudget)
            && Set(strategyResults.keys).isSubset(of: ["retain", "expand", "repair"])
            && strategyResults.values.allSatisfy(\.isValid)
    }
}

struct HamptonQ2EDecision: Codable, Equatable, Sendable {
    let version: String
    let domain: String
    let contextID: String
    let revision: Int
    let signals: HamptonQ2ESignals
    /// Operational Q coordinates, each in [0,1]; meanings are policy-defined.
    let pressures: [String: Double]
    let delta: [String: Double]
    let laneWeights: [String: Double]
    let lane: HamptonQ2ELane
    let reason: String
    /// Nil only on legacy v1 records. No migration rewrites their evidence.
    var coordinateSchema: String? = nil
    /// On v2+, nil means the explicitly defined initial zero reference, not an
    /// observed previous state. Legacy v1 did not record predecessor lineage.
    /// An incompatible/invalid previous decision is not reused.
    var predecessor: HamptonQ2EPredecessor? = nil
    /// Available for the document-revision adapter; other domain owners retain
    /// their existing evidence contracts rather than fabricating these records.
    var outcomeEvidence: HamptonQ2EOutcomeEvidence? = nil
    /// Present on v3 document decisions. Recomputed from frozen bindings during
    /// validation; never trusted as an imported score or independent authority.
    var numericalControl: HamptonDocumentNumericalControl.Receipt? = nil
    /// V4 reading receipts contain flattened task/answer/review bindings, never
    /// recursive copies of earlier controller decisions or source text.
    var readingEvidence: HamptonReadingOutcomeEvidence? = nil
    var readingNumericalControl: HamptonReadingNumericalControl.Receipt? = nil
    /// V5 binds task-local environment evidence to numerical approach choices.
    var arc3Evidence: HamptonARC3OutcomeEvidence? = nil
    var arc3NumericalControl: HamptonARC3NumericalControl.Receipt? = nil

    var isValid: Bool {
        guard HamptonQ2EController.supportedVersions.contains(version), signals.isValid,
              !domain.isEmpty, domain.utf8.count <= 80,
              !contextID.isEmpty, contextID.utf8.count <= 256,
              (1...10_001).contains(revision), reason.utf8.count <= 400,
              !domain.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !contextID.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              Set(pressures.keys) == Set(delta.keys),
              pressures.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              delta.values.allSatisfy({ $0.isFinite && (-1...1).contains($0) }),
              laneWeights.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return false }
        let usesNumerics = version == HamptonQ2EController.numericalVersion
        if usesNumerics {
            guard domain == "document-revision", let evidence = outcomeEvidence,
                  evidence.matches(signals), evidence.reconciliationIssue == nil,
                  numericalControl != nil else { return false }
        } else if numericalControl != nil { return false }
        let usesReadingNumerics = version == HamptonQ2EController.readingNumericalVersion
        if usesReadingNumerics {
            guard domain == "document-reading", outcomeEvidence == nil,
                  let evidence = readingEvidence, evidence.sourceDigest == contextID,
                  evidence.matches(signals), readingNumericalControl != nil else { return false }
        } else if readingEvidence != nil || readingNumericalControl != nil { return false }
        let usesARC3Numerics = version == HamptonQ2EController.arc3NumericalVersion
        if usesARC3Numerics {
            guard domain == "arc3", outcomeEvidence == nil, readingEvidence == nil,
                  let evidence = arc3Evidence, evidence.contextID == contextID,
                  evidence.reconciliationIssue == nil, evidence.matches(signals),
                  arc3NumericalControl != nil else { return false }
        } else if arc3Evidence != nil || arc3NumericalControl != nil { return false }
        let expected = HamptonQ2EController.decide(domain: domain, contextID: contextID, signals: signals,
            outcomeEvidence: usesNumerics ? outcomeEvidence : nil,
            readingEvidence: usesReadingNumerics ? readingEvidence : nil,
            arc3Evidence: usesARC3Numerics ? arc3Evidence : nil,
            useNumericalControl: usesNumerics || usesReadingNumerics || usesARC3Numerics)
        guard pressures == expected.pressures && laneWeights == expected.laneWeights,
              lane == expected.lane && reason == expected.reason,
              numericalControl == expected.numericalControl,
              readingNumericalControl == expected.readingNumericalControl,
              arc3NumericalControl == expected.arc3NumericalControl else { return false }
        if version == HamptonQ2EController.legacyVersion {
            // The old format never recorded a predecessor. Preserve its former
            // read contract; do not claim reconstructed delta lineage for it.
            return coordinateSchema == nil && predecessor == nil && outcomeEvidence == nil
        }
        guard coordinateSchema == HamptonQ2ECoordinateSchema.id,
              HamptonQ2ECoordinateSchema.contains(pressures) else { return false }
        if let predecessor {
            guard predecessor.isValid, predecessor.domain == domain, predecessor.contextID == contextID,
                  revision == min(10_000, predecessor.revision) + 1 else { return false }
        } else if revision != 1 { return false }
        // q_next - q_previous is the effective native pressure change. It is
        // not a requested actuator increment, latent signal or learned coupling.
        guard delta == pressures.mapValuesWithKey({ key, value in value - (predecessor?.pressures[key] ?? 0) }) else { return false }
        if let outcomeEvidence {
            guard domain == "document-revision", outcomeEvidence.matches(signals) else { return false }
        }
        return true
    }

    var bindingDigest: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "unavailable" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum HamptonQ2EController {
    static let version = "hampton-native-qstate-control/v2"
    static let legacyVersion = "hampton-native-qstate-control/v1"
    static let numericalVersion = "hampton-native-qstate-control/v3"
    static let readingNumericalVersion = "hampton-native-qstate-control/v4"
    static let arc3NumericalVersion = "hampton-native-qstate-control/v5"
    static let supportedVersions = [legacyVersion, version, numericalVersion, readingNumericalVersion, arc3NumericalVersion]

    /// Q(t+1) is recomputed from the current admitted observations. Delta is
    /// retained for explanation; stale feedback is not compounded or counted
    /// twice. M(t) couples support/coverage/verifier pressure to bounded lanes.
    /// Domain owners implement the selected lane and retain actual outcomes.
    static func decide(domain: String, contextID: String, signals: HamptonQ2ESignals,
                       previous: HamptonQ2EDecision? = nil,
                       outcomeEvidence: HamptonQ2EOutcomeEvidence? = nil,
                       readingEvidence: HamptonReadingOutcomeEvidence? = nil,
                       arc3Evidence: HamptonARC3OutcomeEvidence? = nil,
                       useNumericalControl: Bool = true) -> HamptonQ2EDecision {
        let compatible = previous.flatMap {
            $0.isValid && $0.domain == domain && $0.contextID == contextID ? $0 : nil
        }
        let clip: (Double) -> Double = { min(1, max(0, $0)) }
        let positive = Double(max(0, min(10_000, signals.retainedSupport)))
        let negative = Double(max(0, min(10_000, signals.contradictions)))
        // Unreviewed attempts remain unknown, rather than becoming failures.
        let support = (positive + 1) / (positive + negative + 2)
        // Adapt the donor's typed verifier-pressure construction. Here the
        // terms mean contradictions and unchanged observed steps, explicitly.
        let verifier = clip(0.2 * Double(max(0, min(10_000, signals.contradictions)))
            + 0.15 * Double(max(0, min(10_000, signals.unchangedSteps))))
        let coverage = signals.availableAlternatives > 0 ? 1 - support : 1
        let novelty = clip(Double(max(0, min(4096, signals.availableAlternatives))) / 8)
        let resource = clip(Double(max(0, min(1500, signals.remainingBudget))) / Double(max(1, min(1500, signals.totalBudget))))
        let q = ["support": support, "coveragePressure": coverage,
                 "verifierPressure": verifier, "alternativeCoverage": novelty,
                 "resourceRemaining": resource]
        var weights = [
            "retain": clip(support * (1 - verifier)),
            "expand": clip(0.45 * coverage + 0.25 * novelty + 0.15 * (1 - support) - 0.25 * verifier),
            "repair": clip(verifier + 0.25 * coverage)
        ]
        let requiresNumerics = useNumericalControl && domain == "document-revision"
            && outcomeEvidence != nil && outcomeEvidence?.reconciliationIssue == nil
        let numerical = requiresNumerics ? outcomeEvidence.flatMap {
            $0.matches(signals) ? HamptonDocumentNumericalControl.replay(evidence: $0) : nil
        } : nil
        let requiresReadingNumerics = useNumericalControl && domain == "document-reading" && readingEvidence != nil
        let readingNumerical = requiresReadingNumerics ? readingEvidence.flatMap {
            $0.sourceDigest == contextID && $0.matches(signals) ? HamptonReadingNumericalControl.replay(evidence: $0) : nil
        } : nil
        let requiresARC3Numerics = useNumericalControl && domain == "arc3" && arc3Evidence != nil
        let arc3Numerical = requiresARC3Numerics ? arc3Evidence.flatMap {
            $0.contextID == contextID && $0.matches(signals) ? HamptonARC3NumericalControl.replay(evidence: $0) : nil
        } : nil
        if let adjustments = numerical?.laneAdjustments ?? readingNumerical?.laneAdjustments ?? arc3Numerical?.laneAdjustments {
            // One critic per outcome. Numerical domain versions replace the old strategy multiplier,
            // retaining aggregate pressures and all prerequisite/action checks.
            for (lane, adjustment) in adjustments {
                weights[lane] = clip(weights[lane, default: 0] + adjustment)
            }
        } else if !requiresNumerics && !requiresReadingNumerics && !requiresARC3Numerics {
            for (lane, result) in signals.strategyResults where result.isValid {
                if result.helpful > 0 || result.corrections > 0 {
                    weights[lane] = clip(weights[lane, default: 0] * (0.5 + result.mean))
                }
            }
        }
        let lane: HamptonQ2ELane
        let reason: String
        if !signals.isValid || domain.isEmpty || contextID.isEmpty || !signals.prerequisitesSatisfied
            || (requiresNumerics && numerical == nil) || (requiresReadingNumerics && readingNumerical == nil)
            || (requiresARC3Numerics && arc3Numerical == nil) {
            lane = .stop; reason = "The current inputs or prerequisites need review before another action."
        } else if signals.remainingBudget == 0 {
            lane = .stop; reason = "The authorized action budget is exhausted."
        } else if signals.availableAlternatives == 0 {
            lane = .stop; reason = "No currently available action fits this work."
        } else if signals.unchangedSteps >= 8 {
            lane = .stop; reason = "Repeated actions made no observed progress. Review the goal or inputs."
        } else if verifier >= 0.4 || signals.unchangedSteps >= 3
                    || (signals.contradictions > 0 && weights["repair", default: 0] > max(weights["retain", default: 0], weights["expand", default: 0])) {
            lane = .repair; reason = "Corrections or stalled progress call for a different bounded approach."
        } else if signals.retainedSupport > 0 && weights["retain", default: 0] >= weights["expand", default: 0] {
            lane = .retain; reason = "Current observations support reusing an available method or transition."
        } else {
            lane = .expand; reason = "Current support is limited; prepare one bounded alternative and observe its result."
        }
        let revision = compatible.map { min(10_000, max(0, $0.revision)) + 1 } ?? 1
        let delta = q.mapValues { $0 }
            .map { (key: $0.key, value: $0.value - (compatible?.pressures[$0.key] ?? 0)) }
        let outputVersion = requiresARC3Numerics ? arc3NumericalVersion
            : (requiresReadingNumerics ? readingNumericalVersion : (requiresNumerics ? numericalVersion : version))
        return HamptonQ2EDecision(version: outputVersion, domain: domain, contextID: contextID,
            revision: revision, signals: signals, pressures: q,
            delta: Dictionary(uniqueKeysWithValues: delta.map { ($0.key, $0.value) }),
            laneWeights: weights, lane: lane, reason: reason,
            coordinateSchema: HamptonQ2ECoordinateSchema.id,
            predecessor: compatible.map(HamptonQ2EPredecessor.init), outcomeEvidence: outcomeEvidence,
            numericalControl: numerical, readingEvidence: readingEvidence, readingNumericalControl: readingNumerical,
            arc3Evidence: arc3Evidence, arc3NumericalControl: arc3Numerical)
    }
}

private extension Dictionary where Key == String, Value == Double {
    func mapValuesWithKey(_ transform: (String, Double) -> Double) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: map { ($0.key, transform($0.key, $0.value)) })
    }
}
