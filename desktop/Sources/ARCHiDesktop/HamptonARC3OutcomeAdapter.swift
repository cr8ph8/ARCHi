import Foundation
import CryptoKit

/// A text/frame-free attribution of one native action. The original attempt,
/// transition and controller remain with the episode owner; their digests bind
/// this projection without recursively embedding earlier controller receipts.
struct HamptonARC3OutcomeBinding: Codable, Equatable, Sendable {
    let attemptID: String
    let transitionID: String
    let proposedAt: Date
    let gameID: String
    let level: Int
    let afterLevel: Int
    let afterState: String
    let baseDispatches: Int
    let beforeDigest: String
    let actualDigest: String
    let predictedDigest: String?
    let action: Int
    let x: Int?
    let y: Int?
    let verdict: ARC3PredictionVerdict
    let invalidated: Bool
    let decisionDigest: String
    let attemptDigest: String
    let transitionDigest: String
    let attributedLane: HamptonQ2ELane

    /// Correction takes precedence; an invalidated older result never supplies
    /// helpful credit. A changed frame or a supported prediction alone is unknown.
    var useful: Bool? {
        if verdict == .refuted || afterState == "GAME_OVER" { return false }
        if !invalidated && (afterLevel > level || afterState == "WIN") { return true }
        return nil
    }
    var digest: String { HamptonARC3OutcomeAdapter.digest(self) }
    var isValid: Bool {
        HamptonARC3OutcomeAdapter.validID(attemptID)
            && UUID(uuidString: transitionID) != nil && proposedAt.timeIntervalSince1970.isFinite
            && HamptonARC3OutcomeAdapter.validGameID(gameID)
            && (0...254).contains(level) && (level...254).contains(afterLevel)
            && ["NOT_PLAYED", "NOT_FINISHED", "WIN", "GAME_OVER"].contains(afterState)
            && (1...63).contains(baseDispatches)
            && [beforeDigest, actualDigest, decisionDigest, attemptDigest, transitionDigest]
                .allSatisfy(DocumentReadingTrace.isDigest)
            && (predictedDigest.map(DocumentReadingTrace.isDigest) ?? true)
            && (1...7).contains(action) && HamptonARC3OutcomeAdapter.validCoordinates(action: action, x: x, y: y)
            && attributedLane != .stop
            && verdict == HamptonARC3OutcomeAdapter.verdict(action: action, beforeLevel: level,
                afterLevel: afterLevel, afterState: afterState, predicted: predictedDigest, actual: actualDigest)
    }
}

/// Bounded source/episode evidence. Aggregate frame-pressure counts keep their
/// existing meaning; lane learning is separately limited to eight attributable
/// outcomes after the last explicit RESET. Hashes are provenance references,
/// not authentication: the native owner must reproject before dispatch.
struct HamptonARC3OutcomeEvidence: Codable, Equatable, Sendable {
    static let version = "hampton-arc3-outcome-projection/v1"
    static let maximumEncodedBytes = 65_536
    let version: String
    let gameID: String
    let level: Int
    let currentDispatches: Int
    let currentFrameDigest: String
    let episodeStartDispatches: Int
    let nativeHistoryDigest: String
    let observations: Int
    let retainedSupport: Int
    let contradictions: Int
    let unchangedSteps: Int
    let remainingBudget: Int
    let totalBudget: Int
    let bindings: [HamptonARC3OutcomeBinding]
    let reconciliationIssue: String?

    var contextID: String { "\(gameID)|level:\(level)" }
    var digest: String { HamptonARC3OutcomeAdapter.digest(self) }
    var strategyResults: [String: HamptonQ2EStrategyEvidence] {
        Dictionary(uniqueKeysWithValues: [HamptonQ2ELane.retain, .expand, .repair].map { lane in
            let records = bindings.filter { $0.attributedLane == lane }
            return (lane.rawValue, HamptonQ2EStrategyEvidence(
                helpful: records.filter { $0.useful == true }.count,
                corrections: records.filter { $0.useful == false }.count))
        })
    }
    var isValid: Bool {
        guard version == Self.version, HamptonARC3OutcomeAdapter.validGameID(gameID),
              (0...254).contains(level), (1...64).contains(totalBudget),
              (1...totalBudget).contains(currentDispatches),
              (1...currentDispatches).contains(episodeStartDispatches),
              remainingBudget == totalBudget - currentDispatches,
              [currentFrameDigest, nativeHistoryDigest].allSatisfy(DocumentReadingTrace.isDigest),
              (1...64).contains(observations), (0..<observations).contains(retainedSupport),
              (0..<observations).contains(contradictions), (0..<observations).contains(unchangedSteps),
              observations <= currentDispatches - episodeStartDispatches + 1,
              bindings.count <= 8, Set(bindings.map(\.attemptID)).count == bindings.count,
              Set(bindings.map(\.transitionID)).count == bindings.count,
              Set(bindings.map(\.baseDispatches)).count == bindings.count,
              bindings == bindings.sorted(by: HamptonARC3OutcomeAdapter.newestFirst),
              bindings.allSatisfy({ $0.isValid && $0.gameID == gameID && $0.afterLevel <= level
                  && $0.baseDispatches >= episodeStartDispatches && $0.baseDispatches < currentDispatches })
        else { return false }
        if let issue = reconciliationIssue {
            guard bindings.isEmpty, observations == 1, retainedSupport == 0, contradictions == 0,
                  unchangedSteps == 0, HamptonARC3OutcomeAdapter.issues.contains(issue) else { return false }
        }
        return HamptonARC3OutcomeAdapter.encoded(self).map { $0.count <= Self.maximumEncodedBytes } ?? false
    }

    func matches(_ signals: HamptonQ2ESignals) -> Bool {
        isValid && signals.observations == observations && signals.retainedSupport == retainedSupport
            && signals.contradictions == contradictions && signals.unchangedSteps == unchangedSteps
            && signals.remainingBudget == remainingBudget && signals.totalBudget == totalBudget
            && signals.strategyResults == strategyResults
            && (reconciliationIssue == nil || !signals.prerequisitesSatisfied)
    }
}

enum HamptonARC3OutcomeAdapter {
    static let maximumTransitions = 63
    static let maximumAttempts = 64
    static let issues: Set<String> = ["history-limit", "conflicting-transition", "conflicting-attempt",
        "invalid-observation", "invalid-transition", "history-discontinuity", "invalid-attempt",
        "ambiguous-attribution", "evidence-limit"]

    static func project(current: ARC3Observation, transitions: [ARC3Transition],
                        attempts: [ARC3ActionAttempt]) -> HamptonARC3OutcomeEvidence {
        func result(bindings: [HamptonARC3OutcomeBinding] = [], historyDigest: String? = nil,
                    episodeStart: Int? = nil, observations: Int = 1, support: Int = 0,
                    contradictions: Int = 0, unchanged: Int = 0,
                    issue: String? = nil) -> HamptonARC3OutcomeEvidence {
            HamptonARC3OutcomeEvidence(version: HamptonARC3OutcomeEvidence.version,
                gameID: current.gameID, level: current.levelsCompleted, currentDispatches: current.dispatches,
                currentFrameDigest: current.frameDigest, episodeStartDispatches: episodeStart ?? current.dispatches,
                nativeHistoryDigest: historyDigest ?? digest(current), observations: observations,
                retainedSupport: support, contradictions: contradictions, unchangedSteps: unchanged,
                remainingBudget: current.remainingActions, totalBudget: current.budget,
                bindings: bindings, reconciliationIssue: issue)
        }
        guard validGameID(current.gameID), (try? current.validate(gameID: current.gameID, budget: current.budget)) != nil else {
            return result(issue: "invalid-observation")
        }
        // Bound raw work while permitting a repeated identical import. The
        // retained unique native episode can never exceed the dispatch budget.
        guard transitions.count <= maximumTransitions * 2, attempts.count <= maximumAttempts * 2 else {
            return result(issue: "history-limit")
        }
        var transitionMap: [UUID: ARC3Transition] = [:]
        var transitionHashes: [UUID: String] = [:]
        for transition in transitions {
            guard validTransition(transition, current: current) else { return result(issue: "invalid-transition") }
            let fingerprint = digest(transition)
            if let prior = transitionHashes[transition.id], prior != fingerprint { return result(issue: "conflicting-transition") }
            transitionHashes[transition.id] = fingerprint; transitionMap[transition.id] = transition
        }
        guard transitionMap.count <= maximumTransitions else { return result(issue: "history-limit") }
        let history = transitionMap.values.sorted { $0.before.dispatches < $1.before.dispatches }
        guard history.count == current.dispatches - 1,
              Set(history.map { $0.before.dispatches }).count == history.count else {
            return result(issue: "history-discontinuity")
        }
        if let first = history.first, let last = history.last {
            guard first.before.dispatches == 1, last.after == current else { return result(issue: "history-discontinuity") }
            for index in 1..<history.count where history[index - 1].after != history[index].before {
                return result(issue: "history-discontinuity")
            }
        }
        let initial = history.first?.before ?? current
        var attemptMap: [String: ARC3ActionAttempt] = [:]
        var attemptHashes: [String: String] = [:]
        for attempt in attempts {
            guard validID(attempt.id), attempt.proposedAt.timeIntervalSince1970.isFinite,
                  (0...current.dispatches).contains(attempt.baseDispatches),
                  (0...7).contains(attempt.action), validCoordinates(action: attempt.action, x: attempt.x, y: attempt.y),
                  ["requested", "observed", "unreconciled"].contains(attempt.state),
                  [attempt.baseFrameDigest, attempt.predictedDigest, attempt.actualDigest].compactMap({ $0 })
                    .allSatisfy(DocumentReadingTrace.isDigest),
                  let bytes = encoded(attempt), bytes.count <= 131_072 else { return result(issue: "invalid-attempt") }
            let fingerprint = digest(bytes: bytes)
            if let prior = attemptHashes[attempt.id], prior != fingerprint { return result(issue: "conflicting-attempt") }
            attemptHashes[attempt.id] = fingerprint; attemptMap[attempt.id] = attempt
        }
        guard attemptMap.count <= maximumAttempts else { return result(issue: "history-limit") }
        guard Set(attemptMap.values.map(\.baseDispatches)).count == attemptMap.count else {
            return result(issue: "ambiguous-attribution")
        }
        let resetIndex = history.lastIndex { $0.action == 0 }
        let episodeStart = resetIndex.map { history[$0].after.dispatches } ?? 1
        let episode = Array(history.dropFirst(resetIndex.map { $0 + 1 } ?? 0))
        var candidates: [HamptonARC3OutcomeBinding] = []
        for attempt in attemptMap.values {
            // Initial RESET has no prior frame or transition. It can establish
            // episode identity but never creates a useful-action observation.
            if attempt.baseDispatches == 0 {
                guard attempt.action == 0, attempt.baseFrameDigest == nil, attempt.predictedDigest == nil,
                      attempt.state == "observed", attempt.actualDigest == initial.frameDigest,
                      attempt.decision == nil, attempt.outcome == nil || attempt.outcome == "initial-reset" else {
                    return result(issue: "invalid-attempt")
                }
                continue
            }
            if attempt.state != "observed" {
                guard attempt.baseDispatches == current.dispatches, attempt.baseFrameDigest == current.frameDigest,
                      attempt.actualDigest == nil, attempt.outcome == nil,
                      legalAction(attempt.action, x: attempt.x, y: attempt.y, before: current) else {
                    return result(issue: "invalid-attempt")
                }
                continue
            }
            guard let transition = history.first(where: { $0.before.dispatches == attempt.baseDispatches }),
                  attempt.baseFrameDigest == transition.beforeDigest, attempt.actualDigest == transition.afterDigest,
                  attempt.action == transition.action, attempt.x == transition.x, attempt.y == transition.y,
                  attempt.predictedDigest == transition.predictedDigest,
                  attempt.outcome == nil || attempt.outcome == outcome(transition, history: history) else {
                return result(issue: "invalid-attempt")
            }
            // Manual and legacy unattributed actions still supply frame history;
            // they cannot manufacture an attributed strategy update.
            guard let proposal = attempt.decision else { continue }
            guard proposal.controller.isValid, proposal.controller.domain == "arc3",
                  proposal.controller.contextID == "\(proposal.gameID)|level:\(proposal.level)",
                  proposal.controller.lane != .stop, proposal.gameID == current.gameID,
                  proposal.level == transition.before.levelsCompleted,
                  proposal.baseDispatches == transition.before.dispatches,
                  proposal.baseFrameDigest == transition.beforeDigest,
                  proposal.action == ARC3PlannedAction(action: transition.action, x: transition.x, y: transition.y) else {
                return result(issue: "invalid-attempt")
            }
            if proposal.expectedDigest != attempt.predictedDigest {
                // Older transports could fill a nil proposal expectation from
                // a task-local cache. Preserve that history but withhold lane
                // credit because its proposal did not bind the expectation.
                guard proposal.controller.version != HamptonQ2EController.arc3NumericalVersion,
                      proposal.expectedDigest == nil, attempt.predictedDigest != nil else {
                    return result(issue: "invalid-attempt")
                }
                continue
            }
            guard transition.action != 0, transition.before.dispatches >= episodeStart else { continue }
            let binding = HamptonARC3OutcomeBinding(attemptID: attempt.id, transitionID: transition.id.uuidString,
                proposedAt: attempt.proposedAt, gameID: current.gameID, level: transition.before.levelsCompleted,
                afterLevel: transition.after.levelsCompleted, afterState: transition.after.state,
                baseDispatches: transition.before.dispatches, beforeDigest: transition.beforeDigest,
                actualDigest: transition.afterDigest, predictedDigest: transition.predictedDigest,
                action: transition.action, x: transition.x, y: transition.y, verdict: transition.verdict,
                invalidated: transition.invalidated, decisionDigest: proposal.controller.bindingDigest,
                attemptDigest: attemptHashes[attempt.id]!, transitionDigest: transitionHashes[transition.id]!,
                attributedLane: proposal.controller.lane)
            guard binding.isValid else { return result(issue: "invalid-attempt") }
            candidates.append(binding)
        }
        let boundary = episode.lastIndex {
            $0.before.levelsCompleted != current.levelsCompleted || $0.after.levelsCompleted != current.levelsCompleted
        }
        let levelHistory = Array(episode.dropFirst(boundary.map { $0 + 1 } ?? 0))
        struct HistoryReference: Encodable { let current: String; let transitions: [String]; let attempts: [String] }
        let historyDigest = digest(HistoryReference(current: digest(current),
            transitions: history.map { transitionHashes[$0.id]! },
            attempts: attemptMap.values.sorted { $0.baseDispatches < $1.baseDispatches }.map { attemptHashes[$0.id]! }))
        let projected = result(bindings: Array(candidates.sorted(by: newestFirst).prefix(8)), historyDigest: historyDigest,
            episodeStart: episodeStart, observations: levelHistory.count + 1,
            support: levelHistory.filter { !$0.invalidated && $0.verdict == .supported && $0.beforeDigest != $0.afterDigest }.count,
            contradictions: levelHistory.filter { $0.verdict == .refuted }.count, unchanged: stalledSteps(levelHistory))
        return projected.isValid ? projected : result(issue: "evidence-limit")
    }

    static func newestFirst(_ lhs: HamptonARC3OutcomeBinding, _ rhs: HamptonARC3OutcomeBinding) -> Bool {
        lhs.baseDispatches == rhs.baseDispatches ? lhs.attemptID < rhs.attemptID : lhs.baseDispatches > rhs.baseDispatches
    }
    static func validGameID(_ value: String) -> Bool { validID(value) && value.utf8.count <= 192 }
    static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 2_048 && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
    static func validCoordinates(action: Int, x: Int?, y: Int?) -> Bool {
        if action == 6 { return x.map { (0...63).contains($0) } == true && y.map { (0...63).contains($0) } == true }
        return x == nil && y == nil
    }
    private static func legalAction(_ action: Int, x: Int?, y: Int?, before: ARC3Observation) -> Bool {
        !before.isTerminal && before.remainingActions > 0 && (action == 0 || before.availableActions.contains(action))
            && validCoordinates(action: action, x: x, y: y)
    }
    static func verdict(action: Int, beforeLevel: Int, afterLevel: Int, afterState: String,
                        predicted: String?, actual: String) -> ARC3PredictionVerdict {
        if action == 0 || beforeLevel != afterLevel || ["WIN", "GAME_OVER"].contains(afterState) { return .inconclusive }
        if let predicted { return predicted == actual ? .supported : .refuted }
        return .observed
    }
    private static func validTransition(_ value: ARC3Transition, current: ARC3Observation) -> Bool {
        guard (try? value.before.validate(gameID: current.gameID, budget: current.budget)) != nil,
              (try? value.after.validate(gameID: current.gameID, budget: current.budget)) != nil,
              value.beforeDigest == value.before.frameDigest, value.afterDigest == value.after.frameDigest,
              value.after.dispatches == value.before.dispatches + 1, value.after.dispatches <= current.dispatches,
              value.after.winLevels == value.before.winLevels,
              value.action == 0 || value.after.levelsCompleted >= value.before.levelsCompleted,
              legalAction(value.action, x: value.x, y: value.y, before: value.before),
              value.predictedDigest.map(DocumentReadingTrace.isDigest) ?? true else { return false }
        return value.verdict == verdict(action: value.action, beforeLevel: value.before.levelsCompleted,
            afterLevel: value.after.levelsCompleted, afterState: value.after.state,
            predicted: value.predictedDigest, actual: value.afterDigest)
    }
    private static func outcome(_ value: ARC3Transition, history: [ARC3Transition]) -> String {
        if value.action == 0 { return "explicit-reset" }
        if value.after.state == "WIN" { return "environment-win" }
        if value.after.state == "GAME_OVER" { return "environment-game-over" }
        if value.after.levelsCompleted > value.before.levelsCompleted { return "environment-level-progress" }
        if value.beforeDigest == value.afterDigest { return "unchanged-visible-frame" }
        if history.contains(where: { $0.before.dispatches < value.before.dispatches
            && $0.before.levelsCompleted == value.after.levelsCompleted
            && ($0.beforeDigest == value.afterDigest || $0.afterDigest == value.afterDigest) }) { return "revisited-visible-frame" }
        return "new-visible-frame"
    }
    private static func stateKey(_ value: ARC3Observation) -> String {
        "\(value.gameID)|\(value.levelsCompleted)|\(value.state)|\(value.frameDigest)|\(value.availableActions.sorted())"
    }
    private static func stalledSteps(_ history: [ARC3Transition]) -> Int {
        var seen: Set<String> = [], stalled = 0
        for value in history {
            seen.insert(stateKey(value.before))
            let novel = seen.insert(stateKey(value.after)).inserted
            let progress = value.after.levelsCompleted > value.before.levelsCompleted || value.after.state == "WIN"
            stalled = progress || (novel && value.beforeDigest != value.afterDigest) ? 0 : stalled + 1
        }
        return stalled
    }
    static func encoded<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(value)
    }
    static func digest<T: Encodable>(_ value: T) -> String { encoded(value).map { digest(bytes: $0) } ?? "unavailable" }
    static func digest(bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
}
