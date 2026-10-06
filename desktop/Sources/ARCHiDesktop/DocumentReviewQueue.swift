import Foundation

/// Read-only follow-through for the current profile's complete journal scope.
/// The owner supplies current review eligibility; this projection cannot grant
/// it, restore document text, infer a verdict or create learning evidence.
struct DocumentReviewQueue: Equatable, Sendable {
    /// Strict applied/unreviewed outcomes the owner currently permits reviewing,
    /// oldest first. The separately displayed current outcome is omitted.
    let records: [DocumentWorkRecord]
    /// Strict applied/unreviewed outcomes excluded because the owner does not
    /// currently permit review. Also excludes the separately displayed current
    /// outcome. This is not a count of failed proposals or missing evidence.
    let blockedCount: Int

    init?(records: [DocumentWorkRecord], historyIsCurrent: Bool,
          reviewableRecordIDs: Set<String>, currentOutcomeID: String?) {
        guard historyIsCurrent else { return nil }
        var unique: [String: DocumentWorkRecord] = [:]
        // Validate the whole supplied scope before selecting outcomes. An
        // excluded record cannot hide conflicting or oversized history.
        for record in records {
            if let prior = unique[record.id], prior != record { return nil }
            unique[record.id] = record
            guard unique.count <= 64 else { return nil }
        }
        let awaiting = unique.values.filter { record in
            record.id != currentOutcomeID && record.state == .applied && record.feedback == nil
                && HamptonMethodOutcomes(records: [record]).awaitingReview == 1
        }
        self.records = awaiting.filter { reviewableRecordIDs.contains($0.id) }.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
        blockedCount = awaiting.filter { !reviewableRecordIDs.contains($0.id) }.count
    }
}
