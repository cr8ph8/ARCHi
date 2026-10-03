import Foundation
import CryptoKit

/// Text-free projection of one completed local reading attempt. The original
/// trace stays with Token Steward; hashing it links this bounded projection to
/// that owner without recursively copying earlier decisions and evidence.
struct HamptonReadingOutcomeBinding: Codable, Equatable, Sendable {
    static let maximumTraceBytes = 131_072
    let taskID: String
    let startedAt: Date
    let route: String
    let provider: String
    let dispatched: Bool
    let state: String
    let traceDigest: String
    let decisionDigest: String
    let sourceDigest: String
    let questionDigest: String
    let planDigest: String
    let sectionIDs: [String]
    let references: [ReadingSourceBinding]?
    let answerDigest: String
    let citedSectionIDs: [String]
    let attributedLane: HamptonQ2ELane
    let review: TokenStewardOutcome?

    var useful: Bool? { review?.value }
    var digest: String { HamptonReadingOutcomeAdapter.digest(self) }

    init?(task: TokenStewardTask) {
        guard HamptonReadingOutcomeAdapter.validReadingTask(task),
              let trace = task.documentReading, let result = task.documentReadingResult,
              result.kind == "ANSWER",
              let lane = task.lanes.first(where: { $0.provider == AssistantProvider.qwen.name }),
              lane.dispatched, lane.state == "complete",
              let traceBytes = HamptonReadingOutcomeAdapter.encoded(trace),
              traceBytes.count <= Self.maximumTraceBytes else { return nil }
        taskID = task.id; startedAt = task.startedAt; route = task.route
        provider = lane.provider; dispatched = lane.dispatched; state = lane.state
        traceDigest = HamptonReadingOutcomeAdapter.digest(bytes: traceBytes)
        decisionDigest = trace.control.bindingDigest
        sourceDigest = trace.sourceDigest; questionDigest = trace.questionDigest
        planDigest = trace.planDigest; sectionIDs = trace.sectionIDs; references = trace.references
        answerDigest = result.answerDigest; citedSectionIDs = result.citedSectionIDs
        attributedLane = trace.control.lane
        review = task.outcomes.last { $0.evidenceID.hasPrefix(DocumentReadingTrace.feedbackEvidencePrefix) }
        guard isValid else { return nil }
    }

    var isValid: Bool {
        guard HamptonReadingOutcomeAdapter.validID(taskID), startedAt.timeIntervalSince1970.isFinite,
              ["native", "local", "automatic", "compare"].contains(route),
              provider == AssistantProvider.qwen.name, dispatched, state == "complete",
              [traceDigest, decisionDigest, sourceDigest, questionDigest, planDigest, answerDigest]
                .allSatisfy(DocumentReadingTrace.isDigest),
              (1...6).contains(sectionIDs.count), Set(sectionIDs).count == sectionIDs.count,
              sectionIDs.allSatisfy(HamptonReadingOutcomeAdapter.validSectionID),
              (references?.count ?? 0) <= 4, ReadingSourceBinding.valid(references),
              citedSectionIDs.count <= 6, Set(citedSectionIDs).count == citedSectionIDs.count,
              Set(citedSectionIDs).isSubset(of: Set(sectionIDs)), attributedLane != .stop else { return false }
        return review.map(HamptonReadingOutcomeAdapter.validReadingReview) ?? true
    }
}

/// A frozen, current-source window. A malformed owner snapshot is represented
/// explicitly rather than silently becoming a smaller successful sample.
struct HamptonReadingOutcomeEvidence: Codable, Equatable, Sendable {
    static let version = "hampton-reading-outcome-projection/v1"
    static let maximumEncodedBytes = 65_536
    let version: String
    let sourceDigest: String
    let bindings: [HamptonReadingOutcomeBinding]
    let reconciliationIssue: String?

    var observations: Int { bindings.count }
    var support: Int { bindings.filter { $0.useful == true }.count }
    var corrections: Int { bindings.filter { $0.useful == false }.count }
    var unknown: Int { bindings.filter { $0.useful == nil }.count }
    var digest: String { HamptonReadingOutcomeAdapter.digest(self) }
    var strategyResults: [String: HamptonQ2EStrategyEvidence] {
        Dictionary(uniqueKeysWithValues: [HamptonQ2ELane.retain, .expand, .repair].map { lane in
            let records = bindings.filter { $0.attributedLane == lane }
            return (lane.rawValue, HamptonQ2EStrategyEvidence(
                helpful: records.filter { $0.useful == true }.count,
                corrections: records.filter { $0.useful == false }.count))
        })
    }
    var isValid: Bool {
        guard version == Self.version, DocumentReadingTrace.isDigest(sourceDigest), bindings.count <= 8,
              Set(bindings.map(\.taskID)).count == bindings.count,
              bindings.allSatisfy({ $0.isValid && $0.sourceDigest == sourceDigest }),
              bindings == bindings.sorted(by: HamptonReadingOutcomeAdapter.newestFirst),
              Set(bindings.compactMap { $0.review?.evidenceID.lowercased() }).count == bindings.compactMap(\.review).count
        else { return false }
        if let issue = reconciliationIssue {
            guard bindings.isEmpty && ["task-limit", "conflicting-task", "invalid-task", "repeated-review", "evidence-limit"].contains(issue) else { return false }
        }
        return HamptonReadingOutcomeAdapter.encoded(self).map { $0.count <= Self.maximumEncodedBytes } ?? false
    }

    func matches(_ signals: HamptonQ2ESignals) -> Bool {
        isValid && signals.observations == observations && signals.retainedSupport == support
            && signals.contradictions == corrections && signals.unchangedSteps == 0
            && signals.strategyResults == strategyResults
            && signals.remainingBudget == 1 && signals.totalBudget == 1
            && (reconciliationIssue == nil || !signals.prerequisitesSatisfied)
    }

    /// Reuse only the latest explicitly helpful task for the same question.
    /// A corrected task no longer supplies its former preferred section list.
    func preferredSectionIDs(for questionDigest: String) -> [String] {
        guard isValid, reconciliationIssue == nil else { return [] }
        return bindings.first { $0.questionDigest == questionDigest && $0.useful == true }?.sectionIDs ?? []
    }
}

enum HamptonReadingOutcomeAdapter {
    // The owner already has a 32 MiB journal limit. This additional work bound
    // prevents arbitrary in-memory snapshots from growing projection work.
    static let maximumTasks = 100_000
    static let maximumOutcomesPerTask = 4_096

    static func project(tasks: [TokenStewardTask], sourceDigest: String,
                        excludingRequestID: String? = nil) -> HamptonReadingOutcomeEvidence {
        func result(_ bindings: [HamptonReadingOutcomeBinding] = [], _ issue: String? = nil) -> HamptonReadingOutcomeEvidence {
            HamptonReadingOutcomeEvidence(version: HamptonReadingOutcomeEvidence.version,
                sourceDigest: sourceDigest, bindings: bindings, reconciliationIssue: issue)
        }
        guard tasks.count <= maximumTasks else { return result([], "task-limit") }
        var unique: [String: TokenStewardTask] = [:]
        for task in tasks where task.id != excludingRequestID {
            if let prior = unique[task.id] {
                guard prior == task else { return result([], "conflicting-task") }
            } else { unique[task.id] = task }
        }
        let dependencyWithdrawals = HamptonMemoryDependencies.invalidatedReadings(tasks: tasks)
            .subtracting(HamptonMemoryDependencies.correctedReadings(tasks: tasks))
        var candidates: [HamptonReadingOutcomeBinding] = []
        var reviews: Set<String> = []
        // Reconcile the whole matching source before taking eight. A corrupted
        // older review cannot disappear merely because newer work filled a page.
        for task in unique.values where task.documentReading?.sourceDigest == sourceDigest {
            guard validReadingTask(task) else { return result([], "invalid-task") }
            for outcome in task.outcomes where outcome.evidenceID.hasPrefix(DocumentReadingTrace.feedbackEvidencePrefix) {
                guard reviews.insert(outcome.evidenceID.lowercased()).inserted else { return result([], "repeated-review") }
            }
            guard task.documentReadingResult?.kind == "ANSWER",
                  task.lanes.contains(where: { $0.provider == AssistantProvider.qwen.name && $0.dispatched && $0.state == "complete" }) else { continue }
            guard let binding = HamptonReadingOutcomeBinding(task: task) else { return result([], "invalid-task") }
            // Withdraw dependent support; do not invent a new negative review.
            if let id = UUID(uuidString: task.id), dependencyWithdrawals.contains(id) { continue }
            candidates.append(binding)
        }
        let projected = result(Array(candidates.sorted(by: newestFirst).prefix(8)))
        return projected.isValid ? projected : result([], "evidence-limit")
    }

    static func newestFirst(_ lhs: HamptonReadingOutcomeBinding, _ rhs: HamptonReadingOutcomeBinding) -> Bool {
        lhs.startedAt == rhs.startedAt ? lhs.taskID < rhs.taskID : lhs.startedAt > rhs.startedAt
    }

    static func validReadingTask(_ task: TokenStewardTask) -> Bool {
        guard validID(task.id), task.startedAt.timeIntervalSince1970.isFinite,
              let trace = task.documentReading, trace.isValid,
              task.lanes.count <= 2, Set(task.lanes.map(\.provider)).count == task.lanes.count,
              task.lanes.allSatisfy({ ["pending", "complete", "failed", "cancelled"].contains($0.state)
                  && ($0.elapsedMilliseconds.map { $0 >= 0 } ?? true) }),
              let local = task.lanes.first(where: { $0.provider == AssistantProvider.qwen.name }),
              task.outcomes.count <= maximumOutcomesPerTask else { return false }
        let providers = Set(task.lanes.map(\.provider))
        switch task.route {
        case "local", "automatic":
            guard providers == [AssistantProvider.qwen.name] else { return false }
        case "compare":
            guard providers == [AssistantProvider.qwen.name, AssistantProvider.codex.name] else { return false }
        case "native":
            guard providers == [AssistantProvider.qwen.name]
                || (providers == [AssistantProvider.qwen.name, AssistantProvider.codex.name] && local.state == "failed") else { return false }
        default: return false
        }
        if let result = task.documentReadingResult {
            guard local.dispatched, result.isValid(for: trace) else { return false }
        }
        var priorRevision = 0
        var outcomeKeys: Set<String> = []
        for outcome in task.outcomes {
            guard outcome.revision > priorRevision, validID(outcome.evidenceID),
                  outcome.recordedAt.timeIntervalSince1970.isFinite,
                  outcomeKeys.insert(outcome.kind.rawValue + ":" + outcome.evidenceID).inserted else { return false }
            if outcome.evidenceID.hasPrefix(DocumentReadingTrace.feedbackEvidencePrefix) {
                guard validReadingReview(outcome),
                      local.dispatched, local.state == "complete", task.documentReadingResult?.kind == "ANSWER" else { return false }
            }
            priorRevision = outcome.revision
        }
        return true
    }

    static func validReadingReview(_ review: TokenStewardOutcome) -> Bool {
        guard review.kind == .userUseful, review.revision > 0,
              review.recordedAt.timeIntervalSince1970.isFinite,
              review.evidenceID.hasPrefix(DocumentReadingTrace.feedbackEvidencePrefix) else { return false }
        return UUID(uuidString: String(review.evidenceID.dropFirst(DocumentReadingTrace.feedbackEvidencePrefix.count))) != nil
    }

    static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 2_048
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
    static func validSectionID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && !value.unicodeScalars.contains {
            CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
        }
    }
    static func encoded<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(value)
    }
    static func digest<T: Encodable>(_ value: T) -> String {
        encoded(value).map { digest(bytes: $0) } ?? "unavailable"
    }
    static func digest(bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
