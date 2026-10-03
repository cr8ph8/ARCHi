import Foundation

/// A read-only view of one exact method version's existing journal records.
/// No retained text, inferred verdict, new learning credit or additional store.
struct MethodLearningHistory: Equatable, Sendable {
    let records: [DocumentWorkRecord]
    let outcomes: HamptonMethodOutcomes

    init?(procedure: DocumentProcedureUse, records: [DocumentWorkRecord], historyIsCurrent: Bool) {
        guard historyIsCurrent, procedure.isValid else { return nil }
        var unique: [String: DocumentWorkRecord] = [:]
        for record in records {
            if let prior = unique[record.id], prior != record { return nil }
            unique[record.id] = record
            // The journal's bounded scope; do not present a partial history.
            guard unique.count <= 64 else { return nil }
        }
        self.records = unique.values.filter { $0.procedureUse == procedure }.sorted {
            let leftNeedsReview = Self.disposition(of: $0) == .awaitingReview
            let rightNeedsReview = Self.disposition(of: $1) == .awaitingReview
            if leftNeedsReview != rightNeedsReview { return leftNeedsReview }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
        outcomes = HamptonMethodOutcomes(procedure: procedure, records: self.records)
    }

    enum Disposition: Equatable, Sendable {
        case helpful, awaitingReview, needsCorrection, withdrawnReview, counterexample, undone
        case unverifiedApplied, other(DocumentWorkRecord.State)

        var title: String {
            switch self {
            case .helpful: "Reviewed Helpful"
            case .awaitingReview: "Applied · awaiting your review"
            case .needsCorrection: "Reviewed Needs correction"
            case .withdrawnReview: "Review withdrawn"
            case .counterexample: "Counterexample retained"
            case .undone: "Undone"
            case .unverifiedApplied: "Applied · review evidence incomplete"
            case .other(let state): state.rawValue.capitalized
            }
        }
    }

    static func disposition(of record: DocumentWorkRecord) -> Disposition {
        // A later Helpful verdict cannot erase an earlier rejection.
        if record.procedureUseRejected == true { return .counterexample }
        if record.feedback?.verdict == .needsCorrection { return .needsCorrection }
        if record.feedback?.verdict == .withdrawn { return .withdrawnReview }
        if record.state == .undone { return .undone }
        let outcome = HamptonMethodOutcomes(records: [record])
        if outcome.helpful == 1 { return .helpful }
        if outcome.awaitingReview == 1 { return .awaitingReview }
        if record.state == .applied { return .unverifiedApplied }
        return .other(record.state)
    }
}

/// Explains the existing owner's preparation gate; it never changes that gate.
enum MethodLearningReuseGuidance: Equatable, Sendable {
    case unavailable(String), historical, finishWork, chooseRevise, selectPassage
    case matchRequirements, ready, unavailablePreparation

    init(unavailableReason: String?, isHistorical: Bool, isWorking: Bool,
         requestsRevision: Bool, hasCurrentSelection: Bool,
         requirementsMatch: Bool, canPrepare: Bool) {
        if let unavailableReason { self = .unavailable(unavailableReason) }
        else if isHistorical { self = .historical }
        else if isWorking { self = .finishWork }
        else if !requestsRevision { self = .chooseRevise }
        else if !hasCurrentSelection { self = .selectPassage }
        else if !requirementsMatch { self = .matchRequirements }
        else if canPrepare { self = .ready }
        else { self = .unavailablePreparation }
    }

    var text: String {
        switch self {
        case .unavailable(let reason): reason
        case .historical: "Earlier version · review its outcomes here. Choose the latest available version for a new passage."
        case .finishWork: "Finish or stop the current request before preparing another method."
        case .chooseRevise: "Choose Revise, then select a passage to try this version."
        case .selectPassage: "Select a passage in the current working copy to try this version."
        case .matchRequirements: "Match the revision checks to this version’s length and exact-token requirements, then choose Use for this passage."
        case .ready: "Choose Use for this passage, review the instruction, then Send. Each new result still needs your review."
        case .unavailablePreparation: "Method preparation is unavailable. Resolve the current work or profile notice before trying again."
        }
    }
}
