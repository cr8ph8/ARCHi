import Foundation
import CryptoKit

enum CompanionGraphKind: String, CaseIterable, Identifiable, Sendable {
    case companion, source, lesson, request, invocation, answer, context, omission, evaluation, accounting
    var id: String { rawValue }
    var title: String {
        switch self {
        case .companion: "Companion"
        case .source: "Source"
        case .lesson: "Kept lesson"
        case .request: "Request"
        case .invocation: "Model call"
        case .answer: "Answer outcome"
        case .context: "Temporary context"
        case .omission: "Omission"
        case .evaluation: "ARC evidence"
        case .accounting: "Task accounting"
        }
    }
    var symbol: String {
        switch self {
        case .companion: "sparkles"
        case .source: "doc.text"
        case .lesson: "bookmark"
        case .request: "bubble.left"
        case .invocation: "arrow.triangle.2.circlepath"
        case .answer: "text.bubble"
        case .context: "text.quote"
        case .omission: "minus.circle"
        case .evaluation: "square.grid.3x3"
        case .accounting: "chart.bar.doc.horizontal"
        }
    }
}

enum CompanionGraphTarget: Equatable, Sendable {
    case assistant, context, memory, advanced, capabilities, steward, interactiveARC
    case arcEvidence(proposalHash: String)
    case stewardTask(taskID: String)
}
struct CompanionGraphDetail: Equatable, Sendable { let label: String; let value: String }
struct CompanionGraphNode: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let kind: CompanionGraphKind
    let status: String
    let details: [CompanionGraphDetail]
    let target: CompanionGraphTarget?
}
struct CompanionGraphEdge: Identifiable, Equatable, Sendable {
    let id: String
    let source: String
    let target: String
    let label: String
}
struct CompanionGraphSnapshot: Equatable, Sendable {
    let nodes: [CompanionGraphNode]
    let edges: [CompanionGraphEdge]
    /// Counts unprojected input items and graph elements; not missing memories.
    let truncatedCount: Int
    static let empty = Self(nodes: [], edges: [], truncatedCount: 0)
}
struct CompanionGraphSource: Equatable, Sendable { let name: String; let text: String; let revision: UInt64 }

/// A read-only projection. IDs describe existing evidence; edges grant no authority.
/// No model, persistence, entity extraction, or character-state owner is created here.
enum CompanionGraph {
    static let maximumNodes = 220
    static let maximumEdges = 500
    static func build(receipts: [AssistantLaneReceipt], lessons: [KeptLesson], source: CompanionGraphSource?,
                      now: Date, records: [SessionContextRecord] = [], turn: Int = 0,
                      arcRecords: [ARCCapabilitiesRecord] = [], arcError: String? = nil,
                      accountingTasks: [TokenStewardTask] = [], accountingError: String? = nil) -> CompanionGraphSnapshot {
        var projection = Projection(source: source, now: now)
        projection.add("companion-archi", title: "ARCHi", subtitle: "Your existing companion", kind: .companion,
            status: "Read-only view", details: [.init(label: "Scope", value: "Existing records and request receipts. Connections do not establish truth or change memory.")], target: .assistant)
        projection.addCurrentSource()
        // ARC owns the checked bundles. The graph never re-scores or persists them.
        projection.addARC(arcRecords, error: arcError, tasks: accountingTasks, accountingError: accountingError)
        let orderedLessons = lessons.sorted { lessonKey($0) < lessonKey($1) }
        projection.truncated += max(0, orderedLessons.count - 64)
        for lesson in orderedLessons.prefix(64) where lesson.isValid { projection.addLesson(lesson) }
        let orderedRecords = records.sorted { recordKey($0) < recordKey($1) }
        projection.truncated += max(0, orderedRecords.count - 64)
        for record in orderedRecords.prefix(64) where record.createdTurn >= 0 && record.createdTurn <= turn && record.expiresAtTurn > turn {
            projection.addRecord(record, turn: turn)
        }
        let orderedReceipts = receipts.sorted { receiptKey($0) < receiptKey($1) }
        projection.truncated += max(0, orderedReceipts.count - 64)
        for receipt in orderedReceipts.prefix(64) { projection.addReceipt(receipt) }
        return .init(nodes: projection.nodes, edges: projection.edges, truncatedCount: projection.truncated)
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private static func key(_ parts: String...) -> String { digest(parts.map { "\($0.utf8.count):\($0)" }.joined()) }
    private static func receiptKey(_ receipt: AssistantLaneReceipt) -> String {
        key("request", receipt.provider.rawValue, receipt.requestID, receipt.inputDigest,
            String(receipt.context.source), String(receipt.context.placement), String(receipt.context.generation), String(receipt.context.selection))
    }
    private static func lessonKey(_ lesson: KeptLesson) -> String {
        key("lesson", lesson.id, String(lesson.revision), digest(lesson.text), lesson.source?.digest ?? "", lesson.source?.name ?? "")
    }
    private static func recordKey(_ record: SessionContextRecord) -> String {
        key("record", record.id, record.sourceID, record.sourceDigest, String(record.sourceRevision),
            String(record.range.location), String(record.range.length), String(record.createdTurn))
    }
    private static func limited(_ text: String, to limit: Int = 240) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    private struct Projection {
        let source: CompanionGraphSource?
        let now: Date
        let sourceDigest: String?
        var sourceNode: String?
        var nodes: [CompanionGraphNode] = []
        var edges: [CompanionGraphEdge] = []
        var nodeIDs = Set<String>()
        var edgeIDs = Set<String>()
        var currentLessons: [String: [(KeptLesson, String)]] = [:]
        var truncated = 0

        init(source: CompanionGraphSource?, now: Date) {
            self.source = source; self.now = now
            sourceDigest = source.map { digest($0.text) }
        }

        @discardableResult
        mutating func add(_ id: String, title: String, subtitle: String, kind: CompanionGraphKind,
                          status: String, details: [CompanionGraphDetail] = [], target: CompanionGraphTarget? = nil) -> Bool {
            if nodeIDs.contains(id) { return true }
            guard nodes.count < maximumNodes else { truncated += 1; return false }
            nodes.append(.init(id: id, title: limited(title, to: 100), subtitle: limited(subtitle), kind: kind,
                status: limited(status), details: details.map { .init(label: limited($0.label), value: limited($0.value, to: 800)) }, target: target))
            nodeIDs.insert(id)
            return true
        }
        mutating func edge(_ from: String, _ to: String, _ label: String) {
            let id = key("edge", from, to, label)
            guard !edgeIDs.contains(id) else { return }
            guard nodeIDs.contains(from), nodeIDs.contains(to), edges.count < maximumEdges else { truncated += 1; return }
            edges.append(.init(id: id, source: from, target: to, label: label)); edgeIDs.insert(id)
        }

        mutating func addARC(_ records: [ARCCapabilitiesRecord], error: String?,
                             tasks: [TokenStewardTask], accountingError: String?) {
            if let error {
                let id = "arc-shelf-error"
                add(id, title: "ARC operation needs attention", subtitle: "Existing owner reported a problem",
                    kind: .evaluation, status: "Review required",
                    details: [.init(label: "Outcome", value: error),
                        .init(label: "Meaning", value: "The latest operation did not complete. Existing results retain their last successful evaluation. Open ARC to review the reported problem; this graph does not repair files.")], target: .capabilities)
                edge("companion-archi", id, "evidence review needed")
            }
            let ordered = records.sorted { $0.id < $1.id }
            truncated += max(0, ordered.count - 16)
            for record in ordered.prefix(16) {
                let summary = record.summary, counts = summary.counts
                let scope: String
                let accountingScope: String
                if let solving = record.solverEvidence {
                    scope = "Recorded local symbolic search: \(solving.run.attemptedPrograms) rule attempts, \(solving.run.matchingPrograms) training fits; \(solving.run.outcome.rawValue). No model calls, growth, memory or permission changes. Opening this graph does not rerun the solver."
                    accountingScope = "Local search and checking elapsed time. No model calls or API charges; CPU and energy cost is unmeasured. Repeated runs remain separate tasks in Token Steward."
                } else {
                    scope = "Local rescoring of supplied predictions. No solver execution or model calls; no growth, memory or permission changes."
                    accountingScope = "Rescoring invokes no model. The cost of originally generating these predictions is unknown. Repeated checks remain separate tasks in Token Steward."
                }
                let id = key("arc-evaluation", record.id)
                let sourceID = key("arc-manifest", summary.manifestHash)
                let target = CompanionGraphTarget.arcEvidence(proposalHash: record.id)
                add(sourceID, title: summary.sourceLabel, subtitle: "Frozen ARC manifest", kind: .source,
                    status: summary.sourceStatus == "synthetic-fixture" ? "Synthetic fixture" : "Unverified offline snapshot",
                    details: [.init(label: "Manifest ID", value: summary.manifestID),
                        .init(label: "Manifest hash", value: summary.manifestHash),
                        .init(label: "Scope", value: "\(counts.totalTasks) tasks · \(counts.totalExamples) test examples"),
                        .init(label: "Meaning", value: "A retained bundle reference. Hashes identify content; they do not authenticate its source.")], target: target)
                add(id, title: "ARC · \(counts.exact) of \(counts.totalExamples) exact",
                    subtitle: summary.sourceLabel, kind: .evaluation,
                    status: "Proposed · Not certified",
                    details: [.init(label: "Outcome", value: "Exact \(counts.exact) · Incorrect \(counts.incorrect) · Missing \(counts.missing) · Invalid \(counts.invalid) · Unscored \(counts.unscored)"),
                        .init(label: "Coverage", value: "Receipts \(summary.receiptCoverageComplete ? "complete" : "incomplete") · Scoring \(summary.scoredCoverageComplete ? "complete" : "incomplete")"),
                        .init(label: "Scope", value: scope),
                        .init(label: "Solver ID", value: summary.solverID),
                        .init(label: "Meaning", value: "Solver provenance remains unattested. A perfect score still does not certify a capability."),
                        .init(label: "Recorded", value: record.recordedAt.ISO8601Format()),
                        .init(label: "Application task ID", value: record.taskID),
                        .init(label: "Proposal hash", value: record.id),
                        .init(label: "Bundle hash", value: record.bundleHash),
                        .init(label: "Checker", value: ARCCapabilitiesEvaluator.scorer)], target: target)
                edge("companion-archi", id, "checked evidence")
                edge(sourceID, id, "rescored from")

                // The usage journal is shared across profiles. Only the exact
                // application-owned retention task may join this profile's graph.
                let task = accountingError == nil ? tasks.first { task in
                    task.id == record.taskID && task.route == "arc-evaluation" &&
                    task.outcomes.contains { $0.kind == .checked && $0.evidenceID == record.id && $0.value == summary.allExact }
                } : nil
                let accountingID = key("arc-accounting", record.taskID)
                let duration = task?.lanes.first?.elapsedMilliseconds.map { "\($0) ms" } ?? "Unavailable"
                add(accountingID, title: "ARC task accounting", subtitle: "Original retention task", kind: .accounting,
                    status: task == nil ? "Accounting unavailable" : "Recorded · Offline check",
                    details: [.init(label: "Application task ID", value: record.taskID),
                        .init(label: "Elapsed", value: duration),
                        .init(label: "Outcome", value: task == nil ? (accountingError ?? "No matching accounting receipt is available.") : "The check completed. All predictions exact: \(summary.allExact ? "yes" : "no")."),
                        .init(label: "Scope", value: accountingScope)], target: .stewardTask(taskID: record.taskID))
                edge(id, accountingID, task == nil ? "accounting unavailable" : "accounted by")
            }
        }

        mutating func addCurrentSource() {
            guard let source, let sourceDigest else { return }
            let id = key("current-source", source.name, String(source.revision), sourceDigest)
            if add(id, title: source.name, subtitle: "Shared working copy · revision \(source.revision)", kind: .source, status: "Current",
                details: [.init(label: "Source", value: source.name), .init(label: "Revision", value: String(source.revision)),
                    .init(label: "SHA-256", value: sourceDigest), .init(label: "Size", value: "\(source.text.utf8.count) UTF-8 bytes"),
                    .init(label: "Content", value: "Open Work together to inspect the current copy. Its full text is not copied into this graph.")], target: .context) {
                sourceNode = id; edge("companion-archi", id, "current shared copy")
            }
        }

        mutating func addLesson(_ lesson: KeptLesson) {
            let id = lessonKey(lesson)
            let expired = lesson.expiresAt.map { $0 <= now } ?? false
            let unavailable = lesson.source.map { $0.digest != sourceDigest || $0.name != source?.name } ?? false
            let status = expired ? "Expired" : unavailable ? "Waiting for shared copy" : "Current"
            var details: [CompanionGraphDetail] = [.init(label: "Lesson ID", value: lesson.id),
                .init(label: "Revision", value: String(lesson.revision)), .init(label: "Your kept words", value: lesson.text),
                .init(label: "Scope", value: "\(lesson.topic) · local Qwen only"),
                .init(label: "Retention", value: "Explicitly kept; not an automatically inferred fact.")]
            if let expiry = lesson.expiresAt { details.append(.init(label: "Expires", value: expiry.ISO8601Format())) }
            if let binding = lesson.source { details.append(.init(label: "Bound source", value: binding.name + " · " + binding.digest)) }
            if add(id, title: lesson.topic, subtitle: "Kept lesson · revision \(lesson.revision)", kind: .lesson,
                status: status, details: details, target: .memory) {
                currentLessons[lesson.id, default: []].append((lesson, id)); edge("companion-archi", id, "explicitly kept")
                if let sourceNode, lesson.source?.digest == sourceDigest, lesson.source?.name == source?.name { edge(id, sourceNode, "bound to exact copy") }
            }
        }

        mutating func addRecord(_ record: SessionContextRecord, turn: Int) {
            let id = recordKey(record)
            let currentSource: Bool
            if record.kind == .userQuestion { currentSource = true }
            else if let source, record.sourceDigest == sourceDigest, record.sourceRevision == source.revision {
                let text = source.text as NSString
                currentSource = record.range.location >= 0 && record.range.length >= 0
                    && record.range.location <= text.length && record.range.length <= text.length - record.range.location
                    && text.substring(with: record.range).utf8.elementsEqual(record.text.utf8)
            } else { currentSource = false }
            var details: [CompanionGraphDetail] = [.init(label: "Record ID", value: record.id), .init(label: "Source ID", value: record.sourceID),
                .init(label: "Source revision", value: String(record.sourceRevision)), .init(label: "Source digest", value: record.sourceDigest),
                .init(label: "UTF-16 range", value: "\(record.range.location), length \(record.range.length)"),
                .init(label: "Lifetime", value: "Created turn \(record.createdTurn); expires turn \(record.expiresAtTurn); current turn \(turn)"),
                .init(label: "Meaning", value: "Temporary exact source excerpt, not a verified fact or saved lesson.")]
            details.append(.init(label: "Excerpt", value: currentSource ? record.text : "Source unavailable; the old excerpt is not shown."))
            if add(id, title: record.kind == .document ? "Shared-copy excerpt" : "Earlier question excerpt", subtitle: record.id,
                kind: .context, status: currentSource ? "Temporary" : "Source unavailable", details: details, target: .memory) {
                edge("companion-archi", id, "temporary context")
                if record.kind == .document, currentSource, let sourceNode { edge(id, sourceNode, "excerpt of") }
            }
        }

        mutating func addReceipt(_ receipt: AssistantLaneReceipt) {
            let requestID = receiptKey(receipt), answerID = key(requestID, "answer")
            let status = receipt.state == .cancelled ? "Stopped" : receipt.state == .failed ? "Failed"
                : receipt.state == .complete ? "Finished" : receipt.requestStarted ? "Working" : "Prepared"
            guard add(requestID, title: "\(receipt.provider.name) request", subtitle: receipt.requestID, kind: .request, status: status,
                details: [.init(label: "Provider", value: receipt.provider.name), .init(label: "Request ID", value: receipt.requestID),
                    .init(label: "Input digest", value: receipt.inputDigest), .init(label: "Contract", value: receipt.inputContract),
                    .init(label: "Access scope", value: receipt.provider == .qwen ? "Selected local input; exact dispatched references are shown separately."
                        : "External current question and shared copy. Private lessons and local conversation are excluded."),
                    .init(label: "Elapsed", value: receipt.elapsedMilliseconds.map { "\($0) ms" } ?? "Unavailable")], target: .assistant) else { return }
            edge("companion-archi", requestID, "request receipt")
            let answerStatus: String
            switch receipt.state {
            case .cancelled: answerStatus = "Stopped"
            case .failed: answerStatus = "Not accepted"
            case .pending: answerStatus = "Not delivered"
            case .complete:
                if !receipt.requestStarted { answerStatus = "Not delivered" }
                else if receipt.admissionOutcome?.status == .rejected || receipt.admissionOutcome?.status == .stopped { answerStatus = "Not accepted" }
                else { answerStatus = receipt.admissionOutcome?.status == .accepted ? "Response checks passed" : "Delivered · checks not recorded" }
            }
            add(answerID, title: "Answer outcome", subtitle: receipt.provider.name, kind: .answer, status: answerStatus,
                details: [.init(label: "Outcome", value: answerStatus),
                    .init(label: "Meaning", value: "A delivered or structurally checked response is generated text, not a verified fact or saved memory."),
                    .init(label: "Admission", value: receipt.admissionOutcome?.detail ?? "No separate admission record supplied.")], target: .assistant)
            edge(requestID, answerID, "answer outcome")
            addInvocations(receipt, requestID: requestID)

            if receipt.provider == .qwen {
                addLocalEvidence(receipt, requestID: requestID, answerID: answerID)
            } else {
                // Ignore any accidentally attached private local metadata on an external lane.
                addPublicReference("current-question", receipt: receipt, requestID: requestID, prepared: true, dispatched: receipt.requestStarted)
                if receipt.sourceDigest != nil { addPublicReference("shared-copy", receipt: receipt, requestID: requestID, prepared: true, dispatched: receipt.requestStarted) }
            }
        }

        mutating func addInvocations(_ receipt: AssistantLaneReceipt, requestID: String) {
            if receipt.provider == .codex {
                guard receipt.requestStarted else { return }
                let id = key(requestID, "external-attempt")
                add(id, title: "Codex request", subtitle: "External reference", kind: .invocation,
                    status: receipt.state == .cancelled ? "Stopped" : receipt.state == .failed ? "Failed" : receipt.state == .complete ? "Response received" : "Attempted",
                    details: [.init(label: "Scope", value: "One Codex request attempted. This is not a local model-call count.")], target: .assistant)
                edge(requestID, id, "attempted"); return
            }
            if let invocations = receipt.localInvocationReceipts {
                truncated += max(0, invocations.count - 32)
                for (index, invocation) in invocations.prefix(32).enumerated() {
                    let id = key(requestID, "invocation", String(index), invocation.id, invocation.inputDigest)
                    let outcome: String
                    switch invocation.outcome {
                    case .dispatched: outcome = "Attempted"
                    case .completed: outcome = "Response received"
                    case .failed: outcome = "Failed"
                    case .cancelled: outcome = "Stopped"
                    }
                    add(id, title: "Call \(index + 1) · \(invocation.role.rawValue)", subtitle: invocation.model?.name ?? "Model not reported",
                        kind: .invocation, status: outcome,
                        details: [.init(label: "Input digest", value: invocation.inputDigest), .init(label: "Outcome", value: outcome),
                            .init(label: "Elapsed", value: invocation.elapsedMilliseconds.map { "\($0) ms" } ?? "Unavailable"),
                            .init(label: "Input tokens", value: invocation.metrics?.inputTokens.map(String.init) ?? "Unavailable"),
                            .init(label: "Output tokens", value: invocation.metrics?.outputTokens.map(String.init) ?? "Unavailable"),
                            .init(label: "Meaning", value: "Attempted means the local client was invoked. Response received does not establish answer admission or factual accuracy.")], target: .advanced)
                    edge(requestID, id, "attempted")
                }
            } else if let roles = receipt.localInvocations {
                truncated += max(0, roles.count - 32)
                for (index, role) in roles.prefix(32).enumerated() {
                    let id = key(requestID, "legacy-attempt", String(index), role.rawValue)
                    add(id, title: "Call \(index + 1) · \(role.rawValue)", subtitle: "Detailed receipt unavailable", kind: .invocation,
                        status: "Attempted", target: .advanced)
                    edge(requestID, id, "attempted")
                }
            }
        }

        mutating func addPublicReference(_ reference: String, receipt: AssistantLaneReceipt, requestID: String,
                                        prepared: Bool, dispatched: Bool) {
            let id = key(requestID, "source-ref", reference)
            let matches = receipt.sourceDigest != nil && receipt.sourceDigest == sourceDigest && receipt.context.source == source?.revision
            let isCopy = reference == "shared-copy" || reference == "selected-passage"
            let digestDetail = isCopy
                ? CompanionGraphDetail(label: "Source copy digest", value: receipt.sourceDigest ?? "Not recorded")
                : CompanionGraphDetail(label: "Request input digest", value: receipt.inputDigest)
            var details: [CompanionGraphDetail] = [.init(label: "Reference", value: reference), digestDetail]
            if isCopy { details.append(.init(label: "Captured source revision", value: String(receipt.context.source))) }
            else { details.append(.init(label: "Digest scope", value: "The complete captured request input, not the question alone.")) }
            details.append(.init(label: "Content", value: isCopy && !matches ? "The original source is not available. Current text has not been substituted." : "Reference only; full source text is not copied here."))
            add(id, title: reference, subtitle: "Captured source reference", kind: .source,
                status: isCopy && !matches ? "Source unavailable" : dispatched ? "Dispatched" : prepared ? "Prepared" : "Available",
                details: details, target: isCopy && matches ? .context : .assistant)
            if prepared { edge(id, requestID, "prepared for") }
            if dispatched { edge(id, requestID, "dispatched to") }
            if !prepared && !dispatched { edge(id, requestID, "available to request") }
            if isCopy, matches, let sourceNode { edge(id, sourceNode, "same captured copy") }
        }

        mutating func addLocalEvidence(_ receipt: AssistantLaneReceipt, requestID: String, answerID: String) {
            let evidence = receipt.evidence
            let publicIDs = Set(["current-question", "shared-copy", "selected-passage"])
            let sourceIDs = Set((evidence?.sourceIDsAvailable ?? []) + (evidence?.reasoningSourceIDsOffered ?? [])
                + (evidence?.reasoningSourceIDsDispatched ?? []) + (evidence?.sourceIDsCited ?? []))
            truncated += max(0, sourceIDs.count - 128)
            for reference in sourceIDs.sorted().prefix(128) {
                let offered = evidence?.reasoningSourceIDsOffered.contains(reference) == true
                let dispatched = evidence?.reasoningSourceIDsDispatched.contains(reference) == true
                let cited = evidence?.sourceIDsCited.contains(reference) == true
                let id = key(requestID, "source-ref", reference)
                if publicIDs.contains(reference) {
                    addPublicReference(reference, receipt: receipt, requestID: requestID, prepared: offered, dispatched: dispatched)
                } else {
                    add(id, title: reference.hasPrefix("conversation-") ? "Earlier Qwen conversation" : "Local source reference",
                        subtitle: reference, kind: .context, status: cited ? "Citation recorded" : dispatched ? "Dispatched" : offered ? "Prepared" : "Available",
                        details: [.init(label: "Reference", value: reference), .init(label: "Scope", value: "This request only. Rolling conversation labels are not global identities."),
                            .init(label: "Captured conversation digest", value: receipt.localConversationDigest ?? "Not recorded")], target: .assistant)
                    if offered { edge(id, requestID, "prepared for") }
                    if dispatched { edge(id, requestID, "dispatched to") }
                    if !offered && !dispatched && !cited { edge(id, requestID, "available to request") }
                }
                if cited { edge(id, answerID, "citation recorded") }
            }
            let captured = Dictionary(grouping: receipt.localLessons, by: \.modelID)
            let memoryIDs = Set((evidence?.lessonIDsAvailable ?? []) + (evidence?.reasoningMemoryIDsOffered ?? [])
                + (evidence?.reasoningMemoryIDsDispatched ?? []) + (evidence?.memoryIDsCited ?? []) + receipt.localLessons.map(\.modelID))
            truncated += max(0, memoryIDs.count - 128)
            for reference in memoryIDs.sorted().prefix(128) {
                let id = key(requestID, "memory-ref", reference)
                let offered = evidence?.reasoningMemoryIDsOffered.contains(reference) == true
                let dispatched = evidence?.reasoningMemoryIDsDispatched.contains(reference) == true
                let cited = evidence?.memoryIDsCited.contains(reference) == true
                if let snapshots = captured[reference], snapshots.count == 1, let snapshot = snapshots.first {
                    addLessonReference(snapshot, id: id)
                } else {
                    add(id, title: "Temporary memory reference", subtitle: reference, kind: .context,
                        status: cited ? "Citation recorded" : dispatched ? "Dispatched" : offered ? "Prepared" : "Available",
                        details: [.init(label: "Reference", value: reference), .init(label: "Content", value: "No historical text is reconstructed from a reference."),
                            .init(label: "Binding", value: "The earlier full record binding was not retained in this receipt. A matching current label does not establish the same historical content.")], target: .memory)
                }
                if offered { edge(id, requestID, "prepared for") }
                if dispatched { edge(id, requestID, "dispatched to") }
                if cited { edge(id, answerID, "citation recorded") }
                if !offered && !dispatched && !cited { edge(id, requestID, "available to request") }
            }
            for (name, selection) in [("Candidates", evidence?.candidates), ("Earlier records", evidence?.reminders)] {
                guard let selection else { continue }
                let refs = Set(selection.eligibleIDs + selection.offeredIDs + selection.dispatchedIDs + selection.selectedIDs)
                truncated += max(0, refs.count - 128)
                for reference in refs.sorted().prefix(128) {
                    let id = key(requestID, "selector-ref", name, reference)
                    add(id, title: name == "Candidates" ? "Candidate excerpt" : "Earlier context reference", subtitle: reference, kind: .context,
                        status: selection.selectedIDs.contains(reference) ? "Selected" : selection.dispatchedIDs.contains(reference) ? "Dispatched" : selection.offeredIDs.contains(reference) ? "Prepared" : "Eligible",
                        details: [.init(label: "Reference", value: reference), .init(label: "Role", value: name),
                            .init(label: "Meaning", value: "A selected reference is not a verified fact or a durable memory write.")], target: .memory)
                    if selection.eligibleIDs.contains(reference) { edge(id, requestID, "eligible for selector") }
                    if selection.offeredIDs.contains(reference) { edge(id, requestID, "prepared for selector") }
                    if selection.dispatchedIDs.contains(reference) { edge(id, requestID, "dispatched to selector") }
                    if selection.selectedIDs.contains(reference) { edge(id, requestID, "selected by response") }
                }
            }
            // Captured evidence already includes lane lesson omissions in current
            // stores. Preserve distinct metadata, without drawing duplicate events.
            var omissionIDs = Set<String>()
            let omissions = ((evidence?.omissions ?? []) + receipt.localLessonOmissions).filter { omission in
                let references = omission.ids.map { "\($0.utf8.count):\($0)" }.joined()
                return omissionIDs.insert(key("omission-metadata", omission.kind.rawValue, omission.reason.rawValue,
                    omission.count.map(String.init) ?? "unavailable", references)).inserted
            }
            truncated += max(0, omissions.count - 64)
            for (index, omission) in omissions.prefix(64).enumerated() {
                let id = key(requestID, "omission", String(index), omission.kind.rawValue, omission.reason.rawValue)
                add(id, title: "\(omission.kind.rawValue) omitted", subtitle: omission.reason.rawValue, kind: .omission, status: "Omitted",
                    details: [.init(label: "Reason", value: omission.reason.rawValue), .init(label: "Count", value: omission.count.map(String.init) ?? "Unavailable"),
                        .init(label: "Reference IDs", value: omission.ids.prefix(8).joined(separator: ", "))], target: .advanced)
                edge(requestID, id, "omission recorded")
            }
        }

        mutating func addLessonReference(_ snapshot: LessonSnapshot, id: String) {
            let candidates = currentLessons[snapshot.id] ?? []
            let exact = candidates.filter { LessonSnapshot(lesson: $0.0) == snapshot }
            let current = exact.count == 1 ? exact.first : nil
            let status: String
            if let current {
                if current.0.expiresAt.map({ $0 <= now }) == true { status = "Expired" }
                else if let binding = current.0.source, binding.name != source?.name || binding.digest != sourceDigest { status = "Waiting for shared copy" }
                else { status = "Current" }
            }
            else { status = candidates.isEmpty ? "No longer kept" : "Earlier revision" }
            add(id, title: "Kept lesson reference", subtitle: "Captured revision \(snapshot.revision)", kind: .lesson, status: status,
                details: [.init(label: "Lesson ID", value: snapshot.id), .init(label: "Captured revision", value: String(snapshot.revision)),
                    .init(label: "Captured text digest", value: digest(snapshot.text)),
                    .init(label: "Content", value: "Historical lesson words are not copied from an answer receipt. Inspect the exact current record when available.")], target: .memory)
            if let current { edge(id, current.1, status == "Expired" ? "same saved version · expired" : "same kept version") }
        }
    }
}
