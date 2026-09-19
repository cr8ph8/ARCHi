import Foundation
import CryptoKit

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

    var isValid: Bool {
        guard version == HamptonQ2EController.version, signals.isValid,
              !domain.isEmpty, domain.utf8.count <= 80,
              !contextID.isEmpty, contextID.utf8.count <= 256,
              (1...10_001).contains(revision), reason.utf8.count <= 400,
              !domain.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !contextID.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              Set(pressures.keys) == Set(delta.keys),
              pressures.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              delta.values.allSatisfy({ $0.isFinite && (-1...1).contains($0) }),
              laneWeights.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return false }
        let expected = HamptonQ2EController.decide(domain: domain, contextID: contextID, signals: signals)
        return pressures == expected.pressures && laneWeights == expected.laneWeights
            && lane == expected.lane && reason == expected.reason
    }

    var bindingDigest: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "unavailable" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum HamptonQ2EController {
    static let version = "hampton-native-qstate-control/v1"

    /// Q(t+1) is recomputed from the current admitted observations. Delta is
    /// retained for explanation; stale feedback is not compounded or counted
    /// twice. M(t) couples support/coverage/verifier pressure to bounded lanes.
    /// Domain owners implement the selected lane and retain actual outcomes.
    static func decide(domain: String, contextID: String, signals: HamptonQ2ESignals,
                       previous: HamptonQ2EDecision? = nil) -> HamptonQ2EDecision {
        let compatible = previous.flatMap {
            $0.version == version && $0.domain == domain && $0.contextID == contextID ? $0 : nil
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
        for (lane, result) in signals.strategyResults where result.isValid {
            if result.helpful > 0 || result.corrections > 0 {
                weights[lane] = clip(weights[lane, default: 0] * (0.5 + result.mean))
            }
        }
        let lane: HamptonQ2ELane
        let reason: String
        if !signals.isValid || domain.isEmpty || contextID.isEmpty || !signals.prerequisitesSatisfied {
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
        return HamptonQ2EDecision(version: version, domain: domain, contextID: contextID,
            revision: revision, signals: signals, pressures: q,
            delta: Dictionary(uniqueKeysWithValues: delta.map { ($0.key, $0.value) }),
            laneWeights: weights, lane: lane, reason: reason)
    }
}
