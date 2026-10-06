import Foundation
import CryptoKit

/// Authored resource tie-breaker for reviewed document methods. The established
/// Beta helpfulness order remains primary. This projection spends nothing and
/// neither admits a method nor estimates dollars, latency or general skill.
struct HamptonMethodResourceOutcomes: Equatable, Sendable {
    let totalTokens: Int64
    let recordedUses: Int
    let localAttempts: Int
    let helpfulResults: Int
    /// Matched source-workload proxy and recorded model-name/digest identities.
    /// Prompts, lesson context and reply settings can still differ; this is an
    /// observed ordering heuristic, not a controlled efficiency experiment.
    let comparisonSignature: String

    init?(procedure: DocumentProcedureUse, records: [DocumentWorkRecord],
          tasks: [TokenStewardTask], observations: [TokenStewardObservation]) {
        guard procedure.isValid else { return nil }
        var unique: [String: DocumentWorkRecord] = [:]
        for record in records {
            if let old = unique[record.id], old != record { return nil }
            unique[record.id] = record
        }
        guard unique.count <= 64 else { return nil }
        // A request/provider owns one document record. Different record IDs
        // cannot attribute the same charged lane to different method versions.
        let ownerKeys = unique.values.map { Self.encode([$0.requestID, $0.provider]) }
        let feedbackIDs = unique.values.compactMap { $0.feedback?.id.lowercased() }
        guard Set(ownerKeys).count == ownerKeys.count,
              Set(feedbackIDs).count == feedbackIDs.count else { return nil }
        let uses = unique.values.filter { $0.procedureUse == procedure }
        let helpful = HamptonMethodOutcomes(procedure: procedure, records: records).helpful
        guard !uses.isEmpty, helpful > 0,
              Set(uses.map(\.requestID)).count == uses.count else { return nil }
        var total: Int64 = 0
        var attemptCount = 0
        var workloads: [String] = []
        for record in uses {
            guard record.provider == AssistantProvider.qwen.rawValue,
                  !record.state.isActive,
                  HamptonQ2EOutcomeBinding(record: record) != nil else { return nil }
            let matchingTasks = tasks.filter { $0.id == record.requestID }
            guard matchingTasks.count == 1, let task = matchingTasks.first,
                  [AssistantRoute.native.rawValue, AssistantRoute.local.rawValue,
                   AssistantRoute.automatic.rawValue].contains(task.route),
                  task.isClosed, task.lanes.count == 1, let lane = task.lanes.first,
                  lane.provider == AssistantProvider.qwen.name, lane.dispatched,
                  ["complete", "failed", "cancelled"].contains(lane.state),
                  lane.localAttemptsMeasured else { return nil }
            if HamptonMethodOutcomes(records: [record]).helpful > 0, lane.state != "complete" { return nil }
            let attempts = observations.filter { $0.taskID == task.id }
            guard !attempts.isEmpty, attempts.count <= 64,
                  Set(attempts.map(\.id)).count == attempts.count else { return nil }
            var modelRoles = Set<String>()
            for attempt in attempts {
                guard attempt.provider == AssistantProvider.qwen.name, attempt.accountID == "native",
                      attempt.resource == .localInference,
                      Self.isNativeAttemptID(attempt.id, taskID: task.id, provider: AssistantProvider.qwen.name),
                      let model = attempt.model, !model.isEmpty,
                      let modelDigest = attempt.modelDigest, Self.validDigest(modelDigest),
                      let inputDigest = attempt.inputDigest, Self.validDigest(inputDigest),
                      let role = attempt.role, LocalModelRole(rawValue: role) != nil,
                      ["completed", "failed", "cancelled"].contains(attempt.outcome),
                      let input = attempt.inputTokens, let output = attempt.outputTokens,
                      input >= 0, output >= 0,
                      attempt.cacheReadTokens.map({ $0 >= 0 && $0 <= input }) ?? true,
                      attempt.cacheWriteTokens.map({ $0 >= 0 && $0 <= input }) ?? true,
                      attempt.reasoningTokens.map({ $0 >= 0 && $0 <= output }) ?? true
                else { return nil }
                let cached = (attempt.cacheReadTokens ?? 0).addingReportingOverflow(attempt.cacheWriteTokens ?? 0)
                guard !cached.overflow, cached.partialValue <= input else { return nil }
                modelRoles.insert(Self.encode([model, modelDigest.lowercased(), role]))
                // Cache and reasoning counts are inclusive subsets, not extras.
                let combined = input.addingReportingOverflow(output)
                guard !combined.overflow else { return nil }
                let next = total.addingReportingOverflow(combined.partialValue)
                guard !next.overflow else { return nil }
                total = next.partialValue
                attemptCount += 1
            }
            // Different sources/selected occurrences or role sets are not a
            // matched workload. Repeated uses remain repeated in this multiset.
            workloads.append(Self.encode([record.sourceDigest, String(record.selectionStart),
                String(record.selectionLength), String(record.mustBeShorter),
                String(record.preserveNumbersAndLinks), Self.encode(modelRoles.sorted())]))
        }
        guard total > 0 else { return nil }
        totalTokens = total
        recordedUses = uses.count
        localAttempts = attemptCount
        helpfulResults = helpful
        let key = Self.encode(workloads.sorted())
        comparisonSignature = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Only an entire equal-quality cohort with complete comparable evidence is
    /// reordered. Pairwise fallback to old order would create comparator cycles
    /// when an unknown-cost item occurs between known cheap and costly items.
    static func refineEqualQualityOrder(_ ordered: [DocumentProcedure],
        outcomes: [DocumentProcedureUse: HamptonMethodOutcomes],
        resources: [DocumentProcedureUse: HamptonMethodResourceOutcomes]) -> [DocumentProcedure] {
        var result = ordered
        var start = 0
        while start < ordered.count {
            guard let quality = outcomes[ordered[start].binding] else { start += 1; continue }
            var end = start + 1
            while end < ordered.count, let next = outcomes[ordered[end].binding],
                  !HamptonMethodOutcomes.rankBefore(lhs: quality, rhs: next),
                  !HamptonMethodOutcomes.rankBefore(lhs: next, rhs: quality) { end += 1 }
            let cohort = Array(ordered[start..<end])
            let costs = cohort.compactMap { resources[$0.binding] }
            if cohort.count > 1, costs.count == cohort.count,
               Set(costs.map(\.comparisonSignature)).count == 1 {
                let ranked = cohort.enumerated().sorted { left, right in
                    let a = resources[left.element.binding]!
                    let b = resources[right.element.binding]!
                    if a.costBefore(b) { return true }
                    if b.costBefore(a) { return false }
                    return left.offset < right.offset
                }.map(\.element)
                result.replaceSubrange(start..<end, with: ranked)
            }
            start = end
        }
        return result
    }

    private static func encode(_ fields: [String]) -> String {
        fields.map { "\($0.utf8.count):\($0)" }.joined()
    }

    /// Total local tokens / current verified Helpful results. Full-width
    /// cross-products preserve exact order even near Int64's journal bound.
    private func costBefore(_ other: Self) -> Bool {
        let left = UInt64(totalTokens).multipliedFullWidth(by: UInt64(other.helpfulResults))
        let right = UInt64(other.totalTokens).multipliedFullWidth(by: UInt64(helpfulResults))
        return left.high == right.high ? left.low < right.low : left.high < right.high
    }

    private static func validDigest(_ value: String) -> Bool {
        return value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0) || (65...70).contains($0)
        }
    }

    private static func isNativeAttemptID(_ id: String, taskID: String, provider: String) -> Bool {
        let prefix = encode([taskID, provider])
        guard id.hasPrefix(prefix) else { return false }
        let suffix = id.dropFirst(prefix.count)
        guard let colon = suffix.firstIndex(of: ":"),
              let count = Int(suffix[..<colon]), count > 0,
              String(count) == String(suffix[..<colon]) else { return false }
        return suffix[suffix.index(after: colon)...].utf8.count == count
    }
}
