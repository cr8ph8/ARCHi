import Foundation

/// An exportable view of an already validated, session-bound observation window.
/// It neither persists practice state nor grants learning, growth or command authority.
struct ArenaPracticeReport: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let sessionID: String
    let sessionKind: String
    let capturedAtUnix: Double
    let presentationRevision: Int
    let snapshotUpdatedAtUnix: Double
    let currentArea: String
    let currentMode: String
    let consumedSequence: Int
    let retainedCount: Int
    /// Sequence positions never observed by this native consumer.
    let missingCount: Int
    /// Previously observed actions removed from the bounded native window.
    let retiredCount: Int
    let actionCounts: [String: Int]
    let damageDealt: Int
    let damageTaken: Int
    let damageAbsorbed: Int
    /// Terminal outcomes present in this retained window, not lifetime bout totals.
    let observedWins: Int
    let observedLosses: Int
    let observedDraws: Int
    let outcomes: [WorldActionOutcome]
    /// Optional, explicitly frozen native suggestion and its observational link.
    let adviceTracking: ArenaAdviceTracking?
    let evidenceScope: String
    let limitations: [String]

    /// The owner must validate the snapshot against its actual presentation before
    /// ingestion. Replaying it into a value copy verifies the existing session
    /// identity (including its private origin digest), cursor and immutable overlap.
    init?(history: WorldOutcomeHistory, snapshot: WorldOutcomeSnapshot, capturedAt: Date,
          adviceTracking: ArenaAdviceTracking? = nil) {
        let capturedAtUnix = capturedAt.timeIntervalSince1970
        guard capturedAtUnix.isFinite, capturedAtUnix > 0,
              snapshot.updatedAtUnix.isFinite, snapshot.updatedAtUnix > 0,
              capturedAtUnix >= snapshot.updatedAtUnix - 5,
              history.consumedSequence == snapshot.lastSequence,
              history.consumedSequence >= 0, history.missingCount >= 0,
              history.missingCount <= history.consumedSequence,
              !history.outcomes.isEmpty,
              history.outcomes.count <= WorldOutcomeSnapshot.maximumOutcomes,
              history.outcomes.count <= history.consumedSequence - history.missingCount else { return nil }
        var checkedHistory = history
        do { try checkedHistory.ingest(snapshot) } catch { return nil }
        guard checkedHistory == history else { return nil }

        // Bounds come from validated WorldActionOutcome facts. Checking the values
        // consumed below also keeps this pure projection safe from arithmetic overflow.
        let actions = ["pulse", "guard", "signature"]
        guard history.outcomes.allSatisfy({
            actions.contains($0.action) && (0...10).contains($0.damageDealt)
                && (0...10).contains($0.damageTaken) && (0...7).contains($0.absorbed)
                && ["", "one", "two", "draw"].contains($0.winner)
                && $0.complete == !$0.winner.isEmpty
        }) else { return nil }
        let terminalOutcomes = history.outcomes.filter(\.complete)
        // A terminal fact is one observed bout result. Refuse an ambiguous repeated
        // terminal bout instead of inflating results, including UUID case variants.
        guard Set(terminalOutcomes.compactMap { UUID(uuidString: $0.boutID) }).count
                == terminalOutcomes.count else { return nil }

        schemaVersion = 2
        sessionID = snapshot.sessionID
        sessionKind = snapshot.sessionKind
        self.capturedAtUnix = capturedAtUnix
        presentationRevision = snapshot.revision
        snapshotUpdatedAtUnix = snapshot.updatedAtUnix
        currentArea = snapshot.currentArea
        currentMode = snapshot.mode
        consumedSequence = history.consumedSequence
        retainedCount = history.outcomes.count
        missingCount = history.missingCount
        // Subtract in this order: consumed + missing + retained can overflow for
        // a valid large sequence gap even though the resulting count cannot.
        retiredCount = max(history.consumedSequence - history.missingCount - history.outcomes.count, 0)
        outcomes = history.outcomes
        self.adviceTracking = adviceTracking
        actionCounts = Dictionary(uniqueKeysWithValues: actions.map { action in
            (action, history.outcomes.filter { $0.action == action }.count)
        })
        damageDealt = history.outcomes.reduce(0) { $0 + $1.damageDealt }
        damageTaken = history.outcomes.reduce(0) { $0 + $1.damageTaken }
        damageAbsorbed = history.outcomes.reduce(0) { $0 + $1.absorbed }
        observedWins = terminalOutcomes.filter { $0.winner == "one" }.count
        observedLosses = terminalOutcomes.filter { $0.winner == "two" }.count
        observedDraws = terminalOutcomes.filter { $0.winner == "draw" }.count
        evidenceScope = "Retained solo Unity rule outcomes from explicit player inputs."
        limitations = [
            "All action, damage, absorption and terminal-outcome measures cover only the retained window, not full session totals.",
            "Missing actions were never observed by this consumer; retired actions were observed but are no longer retained.",
            "A paired or unavailable current mode may retain earlier solo outcomes; paired play contributes no outcomes in this schema.",
            "A tracked native suggestion links only to the exact next matching observed context; it does not dispatch the action or establish causal improvement.",
            "These observations do not establish physics contacts, autonomous actions, general learning or saved companion growth."
        ]
    }

    var coverageSummary: String {
        "\(retainedCount) retained actions · \(missingCount) unobserved · \(retiredCount) observed then retired"
    }

    var actionSummary: String {
        "Pulse \(actionCounts["pulse", default: 0]) · Guard \(actionCounts["guard", default: 0]) · Signature \(actionCounts["signature", default: 0])"
    }

    var outcomeSummary: String {
        "Observed terminal outcomes: \(observedWins) wins · \(observedLosses) losses · \(observedDraws) draws"
    }
}
