import CryptoKit
import Foundation

/// A recent, same-field exchange preference. Scores are authored policy state,
/// not success probabilities, causal move values or companion development.
enum HamptonArenaNumericalControl {
    static let version = "hampton-arena-numerical-control/v1"
    static let coordinateSchema = "hampton-arena-move-exchange/v1"
    static let moves = ["pulse", "guard", "signature"]
    static let coordinates = ["pulseExchange", "guardExchange", "signatureExchange"]
    /// Authored deterministic tie order; an unobserved move retains its neutral prior.
    static let tieOrder = ["guard", "pulse", "signature"]
    private static let identity: [[Double]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]

    struct RankedMove: Codable, Equatable, Sendable {
        let move: String
        let score: Double
        let observationCount: Int
    }
    struct Step: Codable, Equatable, Sendable {
        let actionID: String
        let sequence: Int
        let observedValue: Double
        let force: [Double]
        let candidate: HamptonNumericalDynamics.QuotientCandidate
        let coupling: HamptonNumericalDynamics.CouplingProposal
    }
    struct Receipt: Codable, Equatable, Sendable {
        let version: String
        let coordinateSchema: String
        let field: String
        let outcomes: [WorldActionOutcome]
        let initial: [Double]
        let final: [Double]
        let steps: [Step]
        let rankedMoves: [RankedMove]

        var evidenceDigest: String { ArenaAdviceEvidence.digest(outcomes) }
        var isValid: Bool {
            HamptonArenaNumericalControl.replay(outcomes: outcomes, field: field) == self
        }
    }

    static func replay(outcomes: [WorldActionOutcome], field: String) -> Receipt? {
        guard ["guardian", "scout"].contains(field), ArenaAdviceEvidence.valid(outcomes) else { return nil }
        // Validate the entire supplied window before choosing the field. A malformed
        // unrelated row cannot silently become a smaller successful sample.
        let selected = outcomes.filter { $0.field == field }.sorted { $0.sequence < $1.sequence }
        let initial = [0.5, 0.5, 0.5]
        var state = initial
        var scores = initial
        var steps: [Step] = []
        do {
            for outcome in selected {
                guard let index = moves.firstIndex(of: outcome.action) else { return nil }
                let dealt = outcome.rivalIntegrityBefore - outcome.rivalIntegrityAfter
                let taken = outcome.integrityBefore - outcome.integrityAfter
                let observed = 0.5 + Double(dealt - taken) / 20
                var target = state
                target[index] = observed
                var innovation = [0.0, 0.0, 0.0]
                var error = innovation
                innovation[index] = observed
                error[index] = state[index]
                let force = try HamptonNumericalDynamics.intelligenceForce(previous: state, target: target,
                    potentialMatrix: identity, metricMatrix: identity, gain: 0.25)
                let candidate = try HamptonNumericalDynamics.boundedQuotientCandidate(
                    coordinates: coordinates, previous: state, innovation: zip(innovation, force).map(+),
                    learningMatrix: identity, error: error,
                    configuration: .init(learningRate: 0.25, deltaMax: 0.125, target: target,
                        potentialMatrix: identity, allowedIncrease: 0, maxBacktracks: 12))
                let coupling = try HamptonNumericalDynamics.couple(candidate: candidate,
                    configuration: .init(sourceCoordinates: coordinates, destinationCoordinates: moves,
                        matrix: [[0.5, 0, 0], [0, 0.5, 0], [0, 0, 0.5]], spectralNormBound: 0.5))
                scores = zip(scores, coupling.destinationDelta).map { min(1, max(0, $0 + $1)) }
                state = candidate.candidate
                steps.append(Step(actionID: outcome.actionID, sequence: outcome.sequence,
                    observedValue: observed, force: force, candidate: candidate, coupling: coupling))
            }
        } catch { return nil }
        let ranked = moves.enumerated().map { index, move in
            RankedMove(move: move, score: scores[index], observationCount: selected.filter { $0.action == move }.count)
        }.sorted { left, right in
            left.score == right.score
                ? tieOrder.firstIndex(of: left.move)! < tieOrder.firstIndex(of: right.move)!
                : left.score > right.score
        }
        return Receipt(version: version, coordinateSchema: coordinateSchema, field: field,
            outcomes: selected, initial: initial, final: state, steps: steps, rankedMoves: ranked)
    }
}

/// Conditional advice after one observed round. The v1 stream does not observe
/// the current bout before input, so this receipt never grants dispatch authority.
struct ArenaMoveAdvice: Codable, Equatable, Identifiable, Sendable {
    static let version = "hampton-arena-move-advice/v1"
    let version: String
    let id: String
    let sessionID: String
    let sessionKind: String
    /// Session-salted binding; the profile origin digest itself is never exported.
    let sessionContextDigest: String
    let baseOutcome: WorldActionOutcome
    let evidenceDigest: String
    let receipt: HamptonArenaNumericalControl.Receipt
    let rankedMoves: [HamptonArenaNumericalControl.RankedMove]
    let selectedMove: String
    let preparedAt: Date
    let snapshotUpdatedAtUnix: Double
    let missingCount: Int
    let retiredCount: Int

    /// The owner supplies its already presentation-validated snapshot and history.
    init?(history: WorldOutcomeHistory, snapshot: WorldOutcomeSnapshot, preparedAt: Date, id: UUID = UUID()) {
        guard let report = ArenaAdviceEvidence.context(history: history, snapshot: snapshot, now: preparedAt),
              let base = report.outcomes.last, base.sequence == report.consumedSequence,
              !base.complete, base.round < 20, base.sequence < Int.max,
              let receipt = HamptonArenaNumericalControl.replay(outcomes: report.outcomes, field: base.field) else { return nil }
        let ranked = receipt.rankedMoves.filter { $0.move != "signature" || base.sparkAfter > 0 }
        guard let selected = ranked.first else { return nil }
        version = Self.version
        self.id = id.uuidString
        sessionID = report.sessionID
        sessionKind = report.sessionKind
        sessionContextDigest = ArenaAdviceEvidence.sessionDigest(snapshot)
        baseOutcome = base
        evidenceDigest = receipt.evidenceDigest
        self.receipt = receipt
        rankedMoves = ranked
        selectedMove = selected.move
        self.preparedAt = preparedAt
        snapshotUpdatedAtUnix = snapshot.updatedAtUnix
        missingCount = report.missingCount
        retiredCount = report.retiredCount
    }

    var isValid: Bool {
        let age = preparedAt.timeIntervalSince1970 - snapshotUpdatedAtUnix
        let expected = receipt.rankedMoves.filter { $0.move != "signature" || baseOutcome.sparkAfter > 0 }
        return version == Self.version && UUID(uuidString: id) != nil && UUID(uuidString: sessionID) != nil
            && ["companion", "localPractice"].contains(sessionKind)
            && sessionContextDigest.utf8.count == 64 && sessionContextDigest.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
            && preparedAt.timeIntervalSince1970.isFinite && preparedAt.timeIntervalSince1970 > 0
            && snapshotUpdatedAtUnix.isFinite && snapshotUpdatedAtUnix > 0 && (-5...5).contains(age)
            && receipt.isValid && receipt.field == baseOutcome.field && receipt.outcomes.last == baseOutcome
            && !baseOutcome.complete && baseOutcome.round < 20 && baseOutcome.sequence < Int.max
            && evidenceDigest == receipt.evidenceDigest && rankedMoves == expected
            && selectedMove == expected.first?.move && missingCount >= 0 && retiredCount >= 0
    }

    var bindingDigest: String { ArenaAdviceEvidence.digest(self) }
}

/// Owned by the connection, never advanced by rendering a view. Matching a
/// suggestion records correlation with an actual input, not causal improvement.
struct ArenaAdviceTracking: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable { case pending, matched, differentAction, unlinked }
    let advice: ArenaMoveAdvice
    private(set) var status: Status
    private(set) var outcome: WorldActionOutcome?
    private(set) var reason: String?

    init(advice: ArenaMoveAdvice) {
        self.advice = advice
        status = advice.isValid ? .pending : .unlinked
        reason = advice.isValid ? nil : "The frozen advice did not pass its receipt checks."
    }

    /// Only a pending suggestion can become unlinked. Resolved observations remain
    /// historical facts until their connection owner clears the session.
    mutating func invalidate(reason: String) {
        guard status == .pending else { return }
        status = .unlinked
        outcome = nil
        self.reason = String(reason.prefix(300))
    }

    mutating func observe(history: WorldOutcomeHistory, snapshot: WorldOutcomeSnapshot, now: Date) {
        guard status == .pending else { return }
        guard advice.isValid else {
            invalidate(reason: "The frozen advice did not pass its receipt checks."); return
        }
        guard snapshot.sessionID == advice.sessionID,
              ArenaAdviceEvidence.sessionDigest(snapshot) == advice.sessionContextDigest else {
            invalidate(reason: "The practice session changed."); return
        }
        guard snapshot.currentArea == "arena", snapshot.mode == "solo" else {
            invalidate(reason: "The observation is no longer solo Arena practice."); return
        }
        guard let report = ArenaAdviceEvidence.context(history: history, snapshot: snapshot, now: now) else {
            invalidate(reason: "A fresh, consistent practice observation is unavailable."); return
        }
        let base = advice.baseOutcome
        if let retainedBase = report.outcomes.first(where: { $0.sequence == base.sequence }), retainedBase != base {
            invalidate(reason: "The frozen base action changed."); return
        }
        guard report.consumedSequence >= base.sequence else {
            invalidate(reason: "The action sequence moved behind the frozen observation."); return
        }
        if report.consumedSequence == base.sequence { return }
        guard let next = report.outcomes.first(where: { $0.sequence == base.sequence + 1 }) else {
            invalidate(reason: "The exact next action was not retained; no result was attributed."); return
        }
        guard UUID(uuidString: next.boutID) == UUID(uuidString: base.boutID),
              next.round == base.round + 1, next.field == base.field,
              next.integrityBefore == base.integrityAfter,
              next.rivalIntegrityBefore == base.rivalIntegrityAfter,
              next.sparkBefore == base.sparkAfter, next.rivalSparkBefore == base.rivalSparkAfter,
              next.atUnix > advice.preparedAt.timeIntervalSince1970,
              next.presentationRevision >= base.presentationRevision else {
            invalidate(reason: "The next action did not match the frozen round and state, or preceded preparation."); return
        }
        outcome = next
        status = next.action == advice.selectedMove ? .matched : .differentAction
        reason = next.action == advice.selectedMove
            ? "The next observed input matched the suggestion; this does not establish that the advice caused it."
            : "The next observed input used a different move."
    }
}

private enum ArenaAdviceEvidence {
    static func digest<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return "unavailable" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sessionDigest(_ snapshot: WorldOutcomeSnapshot) -> String {
        digest(["version": ArenaMoveAdvice.version, "sessionID": snapshot.sessionID,
                "sessionKind": snapshot.sessionKind, "originDigest": snapshot.originDigest])
    }

    /// Consistency checks complement, but never replace, the owner's actual
    /// presentation authentication. No fabricated presentation is used here.
    static func context(history: WorldOutcomeHistory, snapshot: WorldOutcomeSnapshot, now: Date) -> ArenaPracticeReport? {
        let age = now.timeIntervalSince1970 - snapshot.updatedAtUnix
        guard now.timeIntervalSince1970.isFinite, snapshot.updatedAtUnix.isFinite, (-5...5).contains(age),
              snapshot.schemaVersion == 1, UUID(uuidString: snapshot.sessionID) != nil,
              ["companion", "localPractice"].contains(snapshot.sessionKind), snapshot.revision > 0,
              snapshot.currentArea == "arena", snapshot.mode == "solo",
              !snapshot.outcomes.isEmpty, valid(snapshot.outcomes), valid(history.outcomes),
              snapshot.firstSequence > 0, snapshot.lastSequence >= snapshot.firstSequence,
              snapshot.lastSequence - snapshot.firstSequence == snapshot.outcomes.count - 1,
              snapshot.outcomes.first?.sequence == snapshot.firstSequence,
              snapshot.outcomes.last?.sequence == snapshot.lastSequence,
              snapshot.outcomes.enumerated().allSatisfy({ $0.element.sequence == snapshot.firstSequence + $0.offset }),
              snapshot.outcomes.allSatisfy({ $0.presentationRevision <= snapshot.revision && $0.atUnix <= snapshot.updatedAtUnix }),
              history.outcomes.allSatisfy({ $0.presentationRevision <= snapshot.revision && $0.atUnix <= snapshot.updatedAtUnix }) else { return nil }
        return ArenaPracticeReport(history: history, snapshot: snapshot, capturedAt: now)
    }

    static func valid(_ outcomes: [WorldActionOutcome]) -> Bool {
        guard outcomes.count <= WorldOutcomeSnapshot.maximumOutcomes,
              Set(outcomes.map(\.sequence)).count == outcomes.count,
              Set(outcomes.compactMap { UUID(uuidString: $0.actionID) }).count == outcomes.count,
              outcomes.allSatisfy(valid) else { return false }
        let ordered = outcomes.sorted { $0.sequence < $1.sequence }
        var terminalBouts = Set<UUID>()
        for (index, value) in ordered.enumerated() {
            guard let bout = UUID(uuidString: value.boutID), !terminalBouts.contains(bout) else { return false }
            if value.complete { terminalBouts.insert(bout) }
            if index > 0 {
                let previous = ordered[index - 1]
                guard value.atUnix >= previous.atUnix,
                      value.presentationRevision >= previous.presentationRevision else { return false }
            }
        }
        return true
    }

    /// Reuse the wire contract even for direct pure-projection input. The owner
    /// separately binds revision and observation time to an actual presentation.
    private static func valid(_ value: WorldActionOutcome) -> Bool {
        value.isValid(revision: value.presentationRevision, observedAt: value.atUnix)
    }
}
