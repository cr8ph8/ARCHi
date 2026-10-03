import Foundation
import CryptoKit

/// Task-loop adapter for the existing document owner, following Stack R2's
/// TaskBinding/OutcomeRecord -> MeasurementRecord boundary in
/// research/representation/archi_repe/stack_contracts.py. These metadata are
/// evidence references, not an additional journal or an authorization token.
struct HamptonQ2EOutcomeBinding: Codable, Equatable, Sendable {
    // The owner journal also retains its existing 1 MiB archive limit. Bound a
    // single hashed record before copying any provenance into the next decision.
    static let maximumSourceRecordBytes = 131_072
    enum Disposition: String, Codable, Sendable { case support, correction, unknown }
    let recordID: String
    let recordDigest: String
    let requestID: String
    let provider: String
    let targetID: String
    let sourceDigest: String
    let sourceRevision: UInt64
    let selectionStart: Int
    let selectionLength: Int
    let mustBeShorter: Bool
    let preserveNumbersAndLinks: Bool
    let createdAt: Date
    let updatedAt: Date
    let state: DocumentWorkRecord.State
    let proposedDigest: String?
    let expectedAfterDigest: String?
    let actualAfterDigest: String?
    let afterRevision: UInt64?
    let checks: [DocumentWorkAuditCheck]
    /// Nil remains unavailable on older/uncompleted records, never synthesized.
    let learning: DocumentWorkLearningContext?
    let feedback: DocumentWorkFeedback?
    let feedbackUsageSyncedID: String?
    let procedureUse: DocumentProcedureUse?
    let procedureUseRejected: Bool?
    /// Derived from the live source owners, never a rewrite of the old outcome.
    /// Nil preserves prior frozen bindings; true removes current support while
    /// retaining this attempt and its provenance in the bounded evidence window.
    let knowledgeDependencyUnavailable: Bool?
    let attributedLane: HamptonQ2ELane?
    let decisionDigest: String?

    init?(record: DocumentWorkRecord, knowledgeDependencyUnavailable: Bool = false) {
        if let decision = record.q2eDecision {
            guard decision.isValid, decision.domain == "document-revision",
                  decision.contextID == record.sourceDigest, decision.lane != .stop else { return nil }
            if let evidence = decision.outcomeEvidence {
                guard evidence.mustBeShorter == record.mustBeShorter,
                      evidence.preserveNumbersAndLinks == record.preserveNumbersAndLinks else { return nil }
            }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let bytes = try? encoder.encode(record), bytes.count <= Self.maximumSourceRecordBytes else { return nil }
        recordID = record.id
        recordDigest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        requestID = record.requestID; provider = record.provider; targetID = record.targetID
        sourceDigest = record.sourceDigest; sourceRevision = record.sourceRevision
        selectionStart = record.selectionStart; selectionLength = record.selectionLength
        mustBeShorter = record.mustBeShorter; preserveNumbersAndLinks = record.preserveNumbersAndLinks
        createdAt = record.createdAt; updatedAt = record.updatedAt; state = record.state
        proposedDigest = record.proposedDigest; expectedAfterDigest = record.expectedAfterDigest
        actualAfterDigest = record.actualAfterDigest; afterRevision = record.afterRevision
        checks = record.checks; learning = record.learning; feedback = record.feedback
        feedbackUsageSyncedID = record.feedbackUsageSyncedID
        procedureUse = record.procedureUse; procedureUseRejected = record.procedureUseRejected
        self.knowledgeDependencyUnavailable = knowledgeDependencyUnavailable ? true : nil
        let control = record.q2eDecision
        attributedLane = control?.lane; decisionDigest = control?.bindingDigest
        guard isValid else { return nil }
    }

    /// Reconstruct only the outcome fields needed by the established Helpful
    /// rule. A decision is deliberately not nested, keeping lineage bounded.
    private var outcomeRecord: DocumentWorkRecord {
        DocumentWorkRecord(id: recordID, requestID: requestID, provider: provider,
            targetID: targetID, sourceDigest: sourceDigest, sourceRevision: sourceRevision,
            selectionStart: selectionStart, selectionLength: selectionLength,
            mustBeShorter: mustBeShorter, preserveNumbersAndLinks: preserveNumbersAndLinks,
            createdAt: createdAt, updatedAt: updatedAt, state: state,
            proposedDigest: proposedDigest, expectedAfterDigest: expectedAfterDigest,
            actualAfterDigest: actualAfterDigest, afterRevision: afterRevision, checks: checks,
            learning: learning, feedback: feedback, feedbackUsageSyncedID: feedbackUsageSyncedID,
            procedureUse: procedureUse, procedureUseRejected: procedureUseRejected)
    }

    var disposition: Disposition {
        guard isValid else { return .unknown }
        if knowledgeDependencyUnavailable == true { return .unknown }
        if procedureUseRejected == true || feedback.map({ $0.verdict != .helpful }) == true
            || (state == .blocked && checks.contains { !$0.passed }) { return .correction }
        return HamptonMethodOutcomes(records: [outcomeRecord]).helpful == 1 ? .support : .unknown
    }

    var isValid: Bool {
        guard Self.text(recordID, limit: 384), Self.text(requestID, limit: 128),
              Self.text(provider, limit: 128), Self.text(targetID, limit: 128),
              Self.digest(recordDigest), Self.digest(sourceDigest),
              selectionStart >= 0, selectionStart <= 100_000,
              selectionLength > 0, selectionLength <= 100_000 - selectionStart,
              createdAt.timeIntervalSince1970.isFinite, updatedAt.timeIntervalSince1970.isFinite,
              updatedAt >= createdAt, checks.count <= 24,
              Set(checks.map(\.id)).count == checks.count,
              checks.allSatisfy({ Self.text($0.id, limit: 128) && Self.text($0.title, limit: 160) }),
              [proposedDigest, expectedAfterDigest, actualAfterDigest, decisionDigest].compactMap({ $0 }).allSatisfy(Self.digest),
              afterRevision.map({ $0 > sourceRevision }) ?? true,
              learning?.isValid ?? true, procedureUse?.isValid ?? true,
              procedureUse != nil || procedureUseRejected == nil,
              knowledgeDependencyUnavailable == nil || knowledgeDependencyUnavailable == true,
              procedureUse != nil || knowledgeDependencyUnavailable == nil,
              (attributedLane == nil) == (decisionDigest == nil), attributedLane != .stop else { return false }
        if procedureUse != nil,
           [.undoing, .undone].contains(state) || feedback.map({ $0.verdict != .helpful }) == true {
            guard procedureUseRejected == true else { return false }
        }
        if let feedback {
            guard feedback.isValid, [.applied, .undone, .undoing, .failed].contains(state),
                  UUID(uuidString: requestID) != nil, learning != nil,
                  expectedAfterDigest != nil, actualAfterDigest == expectedAfterDigest,
                  afterRevision != nil, feedback.recordedAt >= createdAt, feedback.recordedAt <= updatedAt,
                  feedbackUsageSyncedID == nil || feedbackUsageSyncedID == feedback.id else { return false }
        } else if feedbackUsageSyncedID != nil { return false }
        if state == .applied, expectedAfterDigest == nil || actualAfterDigest != expectedAfterDigest || afterRevision == nil { return false }
        return true
    }

    private static func text(_ value: String, limit: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.unicodeScalars.count <= limit
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
    private static func digest(_ value: String) -> Bool {
        let raw = value.hasPrefix("sha256:") ? String(value.dropFirst(7)) : value
        return raw.utf8.count == 64 && raw.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

struct HamptonQ2EOutcomeEvidence: Codable, Equatable, Sendable {
    static let version = "hampton-document-outcome-projection/v1"
    static let maximumEncodedBytes = 65_536
    let version: String
    let mustBeShorter: Bool
    let preserveNumbersAndLinks: Bool
    let bindings: [HamptonQ2EOutcomeBinding]
    /// A malformed/conflicting owner snapshot is not a smaller successful sample.
    /// It stops the consumer until the existing owner can supply a coherent view.
    let reconciliationIssue: String?
    var support: Int { bindings.filter { $0.disposition == .support }.count }
    var corrections: Int { bindings.filter { $0.disposition == .correction }.count }
    var unknown: Int { bindings.filter { $0.disposition == .unknown }.count }
    var strategyResults: [String: HamptonQ2EStrategyEvidence] {
        Dictionary(uniqueKeysWithValues: [HamptonQ2ELane.retain, .expand, .repair].map { lane in
            let records = bindings.filter { $0.attributedLane == lane }
            return (lane.rawValue, HamptonQ2EStrategyEvidence(
                helpful: records.filter { $0.disposition == .support }.count,
                corrections: records.filter { $0.disposition == .correction }.count))
        })
    }
    var isValid: Bool {
        guard version == Self.version, bindings.count <= 8,
              Set(bindings.map(\.recordID)).count == bindings.count,
              bindings.allSatisfy({ $0.isValid && $0.mustBeShorter == mustBeShorter
                  && $0.preserveNumbersAndLinks == preserveNumbersAndLinks }),
              Set(bindings.compactMap { $0.feedback?.id.lowercased() }).count == bindings.compactMap(\.feedback).count
        else { return false }
        if let issue = reconciliationIssue {
            guard bindings.isEmpty && ["record-limit", "conflicting-record", "invalid-record", "repeated-feedback", "evidence-limit"].contains(issue) else { return false }
        }
        return (try? JSONEncoder().encode(self).count).map { $0 <= Self.maximumEncodedBytes } ?? false
    }
    func matches(_ signals: HamptonQ2ESignals) -> Bool {
        isValid && signals.observations == bindings.count && signals.retainedSupport == support
            && signals.contradictions == corrections && signals.unchangedSteps == 0
            && signals.strategyResults == strategyResults
            && signals.remainingBudget == 1 && signals.totalBudget == 1
            && (reconciliationIssue == nil || !signals.prerequisitesSatisfied)
    }
}

/// Reuses the document journal's bounded, newest-first requirement scope. Unlike
/// the old two count paths, reconciliation precedes scope/window selection and
/// both signs plus unknowns come from exactly these frozen bindings. Reviewed
/// verdicts remain opinions about this task, not general skill measurements.
struct HamptonQ2EOutcomeAdapter: Sendable {
    let records: [DocumentWorkRecord]
    let evidence: HamptonQ2EOutcomeEvidence

    init(records input: [DocumentWorkRecord], requirements: DocumentWorkRequirements,
         knowledgeUnavailableRecordIDs: Set<String> = []) {
        var unique: [String: DocumentWorkRecord] = [:]
        var issue: String?
        for record in input {
            if let prior = unique[record.id] {
                if prior != record { issue = "conflicting-record"; break }
            } else {
                guard unique.count < 64 else { issue = "record-limit"; break }
                unique[record.id] = record
            }
        }
        var bindings: [String: HamptonQ2EOutcomeBinding] = [:]
        if issue == nil {
            for record in unique.values {
                guard let binding = HamptonQ2EOutcomeBinding(record: record,
                    knowledgeDependencyUnavailable: knowledgeUnavailableRecordIDs.contains(record.id)) else {
                    issue = "invalid-record"; break
                }
                bindings[record.id] = binding
            }
            let feedbackIDs = bindings.values.compactMap { $0.feedback?.id.lowercased() }
            if Set(feedbackIDs).count != feedbackIDs.count { issue = "repeated-feedback" }
        }
        let selected = issue == nil ? Array(unique.values.filter {
            $0.mustBeShorter == requirements.mustBeShorter
                && $0.preserveNumbersAndLinks == requirements.preserveNumbersAndLinks
        }.sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt }.prefix(8)) : []
        let projected = HamptonQ2EOutcomeEvidence(version: HamptonQ2EOutcomeEvidence.version,
            mustBeShorter: requirements.mustBeShorter, preserveNumbersAndLinks: requirements.preserveNumbersAndLinks,
            bindings: selected.compactMap { bindings[$0.id] }, reconciliationIssue: issue)
        if projected.isValid {
            records = selected; evidence = projected
        } else {
            records = []
            evidence = HamptonQ2EOutcomeEvidence(version: HamptonQ2EOutcomeEvidence.version,
                mustBeShorter: requirements.mustBeShorter, preserveNumbersAndLinks: requirements.preserveNumbersAndLinks,
                bindings: [], reconciliationIssue: "evidence-limit")
        }
    }

    func signals(alternatives: Int, prerequisitesSatisfied: Bool) -> HamptonQ2ESignals {
        HamptonQ2ESignals(observations: evidence.bindings.count, retainedSupport: evidence.support,
            contradictions: evidence.corrections, unchangedSteps: 0, availableAlternatives: alternatives,
            remainingBudget: 1, totalBudget: 1,
            prerequisitesSatisfied: prerequisitesSatisfied && evidence.isValid && evidence.reconciliationIssue == nil,
            strategyResults: evidence.strategyResults)
    }
}
