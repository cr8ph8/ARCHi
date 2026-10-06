import Foundation

enum WorldOutcomeHistoryError: Error, Equatable {
    case changedSession, rewrittenOutcome, duplicateActionID, missingCountOverflow
}

/// Bounded, session-only observations. The caller validates each snapshot first.
/// Retained overlapping facts are immutable across polls; this is not a complete
/// log, persistence, command authority or evidence of native companion growth.
struct WorldOutcomeHistory: Equatable, Sendable {
    private(set) var outcomes: [WorldActionOutcome] = []
    private(set) var consumedSequence = 0
    private(set) var missingCount = 0

    private struct Session: Equatable, Sendable {
        let id: String
        let originDigest: String
        let kind: String
    }
    private var session: Session?

    mutating func ingest(_ snapshot: WorldOutcomeSnapshot) throws {
        let incomingSession = Session(id: snapshot.sessionID, originDigest: snapshot.originDigest,
                                      kind: snapshot.sessionKind)
        if let session, session != incomingSession { throw WorldOutcomeHistoryError.changedSession }
        let batch = try snapshot.batch(after: consumedSequence)
        let retainedBySequence = Dictionary(uniqueKeysWithValues: outcomes.map { ($0.sequence, $0) })
        var sequenceByAction = Dictionary(uniqueKeysWithValues: outcomes.map { ($0.actionID.lowercased(), $0.sequence) })
        for outcome in snapshot.outcomes {
            if let prior = retainedBySequence[outcome.sequence], prior != outcome {
                throw WorldOutcomeHistoryError.rewrittenOutcome
            }
            let actionIdentity = outcome.actionID.lowercased()
            if let sequence = sequenceByAction[actionIdentity], sequence != outcome.sequence {
                throw WorldOutcomeHistoryError.duplicateActionID
            }
            sequenceByAction[actionIdentity] = outcome.sequence
        }
        let (nextMissing, overflow) = missingCount.addingReportingOverflow(batch.missingCount)
        guard !overflow else { throw WorldOutcomeHistoryError.missingCountOverflow }
        let nextOutcomes = Array((outcomes + batch.outcomes).suffix(WorldOutcomeSnapshot.maximumOutcomes))

        // Commit only after every check, including unchanged-cursor overlaps.
        session = incomingSession
        outcomes = nextOutcomes
        consumedSequence = snapshot.lastSequence
        missingCount = nextMissing
    }

    mutating func reset() { self = Self() }
}
