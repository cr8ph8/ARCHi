import Foundation

/// Retained document-method outcomes, derived without creating another store.
/// Counts describe provider-lane records, not independent tasks or general skill.
/// Exact-version results can prioritize explicitly available methods; they never
/// certify a capability, admit a procedure, select it, or execute an action.
struct HamptonMethodOutcomes: Equatable, Sendable {
    private(set) var attempts = 0
    /// Current applied state, including records without qualifying review evidence.
    private(set) var applied = 0
    private(set) var helpful = 0
    /// Includes withdrawn reviews and permanent counterexample markers.
    private(set) var needsCorrection = 0
    /// Undo is a separate state count and can also count as needsCorrection.
    private(set) var undone = 0
    private(set) var awaitingReview = 0

    // Mirrors the bounded document journal. Kept here to avoid an actor-owned
    // store dependency in this pure value computation. No partial sample is used
    // when an input exceeds that number of distinct record identities.
    private static let maximumRecords = 64

    init(procedure: DocumentProcedureUse, records: [DocumentWorkRecord]) {
        self.init(records: records, matching: procedure)
    }

    /// Aggregate the supplied scope, including ordinary work without a procedure.
    /// The caller defines that scope; these are still provider-lane outcomes.
    init(records: [DocumentWorkRecord]) {
        self.init(records: records, matching: nil)
    }

    private init(records: [DocumentWorkRecord], matching procedure: DocumentProcedureUse?) {
        guard procedure?.isValid ?? true else { return }
        var unique: [String: DocumentWorkRecord] = [:]
        var contradictory = Set<String>()
        for record in records {
            if let prior = unique[record.id] {
                if prior != record { contradictory.insert(record.id) }
            } else {
                guard unique.count < Self.maximumRecords else { return }
                unique[record.id] = record
            }
        }

        // Reconcile identities before filtering: a conflicting copy attributed
        // to a different procedure cannot leave an apparently valid positive.
        for record in unique.values where !contradictory.contains(record.id) {
            guard procedure == nil || record.procedureUse == procedure else { continue }
            attempts += 1
            if record.state == .applied { applied += 1 }
            if record.state == .undone { undone += 1 }

            let negative = record.procedureUseRejected == true
                || record.feedback.map { $0.verdict != .helpful } == true
            if negative {
                needsCorrection += 1
            } else if Self.hasVerifiedAppliedResult(record) {
                if let feedback = record.feedback {
                    if feedback.verdict == .helpful, feedback.isValid,
                       feedback.recordedAt >= record.createdAt,
                       feedback.recordedAt <= record.updatedAt,
                       record.feedbackUsageSyncedID == nil || record.feedbackUsageSyncedID == feedback.id {
                        helpful += 1
                    }
                } else {
                    awaitingReview += 1
                }
            }
        }
    }

    /// Strict descending Beta(1,1) posterior-mean order; ties remain the caller's
    /// existing order. Adapted from Qi Experiments' qi_experiments/critic.py
    /// (BetaCell, TabularBetaCritic) and HamptonARCTrainingOrder's exact arithmetic.
    /// Here Helpful is a retained user verdict; correction/withdrawal is negative.
    /// This is a prioritization heuristic, not calibrated success probability or
    /// capability certification. No exploration bonus or hypothetical evidence.
    static func rankBefore(lhs: HamptonMethodOutcomes, rhs: HamptonMethodOutcomes) -> Bool {
        // Positive and negative counts are disjoint and sum to at most 64.
        // Each cross-product is at most 65 * 66, safely inside Int bounds.
        let left = (lhs.helpful + 1) * (rhs.helpful + rhs.needsCorrection + 2)
        let right = (rhs.helpful + 1) * (lhs.helpful + lhs.needsCorrection + 2)
        return left > right
    }

    private static func hasVerifiedAppliedResult(_ record: DocumentWorkRecord) -> Bool {
        guard record.state == .applied, record.learning?.isValid == true,
              UUID(uuidString: record.requestID) != nil,
              let proposed = record.proposedDigest, let expected = record.expectedAfterDigest,
              let actual = record.actualAfterDigest, actual == expected,
              [record.sourceDigest, proposed, expected, actual].allSatisfy(validRecordDigest),
              record.afterRevision.map({ $0 > record.sourceRevision }) == true,
              !record.checks.isEmpty, record.checks.count <= 24,
              Set(record.checks.map(\.id)).count == record.checks.count,
              record.checks.allSatisfy(\.passed),
              record.createdAt.timeIntervalSince1970.isFinite,
              record.updatedAt.timeIntervalSince1970.isFinite,
              record.updatedAt >= record.createdAt else { return false }
        return true
    }

    private static func validRecordDigest(_ value: String) -> Bool {
        let digest = value.hasPrefix("sha256:") ? String(value.dropFirst(7)) : value
        return digest.utf8.count == 64
            && digest.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
