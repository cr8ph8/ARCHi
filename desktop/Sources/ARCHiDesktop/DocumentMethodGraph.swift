import Foundation
import CryptoKit

/// Existing methods and their retained support, projected without saving a graph,
/// restoring a document, granting learning credit or preparing a new request.
@MainActor
enum DocumentMethodGraph {
    static func nodeID(_ binding: DocumentProcedureUse) -> String {
        key(["method", binding.id, String(binding.revision), binding.digest])
    }

    static func append(to base: CompanionGraphSnapshot, store: CompanionStore) -> CompanionGraphSnapshot {
        var nodes = Array(base.nodes.prefix(CompanionGraph.maximumNodes))
        var ids = Set(nodes.map(\.id))
        var edges: [CompanionGraphEdge] = []
        var edgeIDs = Set<String>()
        var omitted = base.truncatedCount + max(0, base.nodes.count - nodes.count)
        for edge in base.edges {
            guard ids.contains(edge.source), ids.contains(edge.target), !edgeIDs.contains(edge.id),
                  edges.count < CompanionGraph.maximumEdges else { omitted += 1; continue }
            edges.append(edge); edgeIDs.insert(edge.id)
        }
        func add(_ node: CompanionGraphNode) -> Bool {
            if ids.contains(node.id) { return true }
            guard nodes.count < CompanionGraph.maximumNodes else { omitted += 1; return false }
            nodes.append(node); ids.insert(node.id); return true
        }
        func link(_ source: String, _ target: String, _ label: String,
                  relationship: CompanionGraphRelationship = .recorded) {
            let id = key(["method-edge", source, target, label])
            guard !edgeIDs.contains(id) else { return }
            guard ids.contains(source), ids.contains(target), edges.count < CompanionGraph.maximumEdges else {
                omitted += 1; return
            }
            var edge = CompanionGraphEdge(id: id, source: source, target: target, label: label)
            edge.relationship = relationship
            edges.append(edge); edgeIDs.insert(id)
        }
        let current = store.profileRecoveryBlock == nil && store.documentProcedures.isCurrentOnDisk
            && store.documentWork.isCurrentOnDisk
        let methods = store.documentProcedures.procedures.sorted {
            $0.id == $1.id ? $0.revision > $1.revision : $0.id < $1.id
        }
        let latest = Set(store.documentProcedures.latestProcedures.map(\.binding))
        // Admit method nodes first so supporting receipts cannot crowd out the
        // very methods this surface is intended to make inspectable.
        for method in methods {
            let issue = current ? store.documentProcedureUnavailable(method.binding)
                : "Method history changed or needs recovery. Reopen before using its outcomes."
            let outcomes = current ? store.outcomes(for: method) : nil
            let status = !current ? "History needs review" : method.withdrawn ? "Withdrawn"
                : issue != nil ? "Unavailable for reuse" : !latest.contains(method.binding) ? "Earlier version"
                : (outcomes?.helpful ?? 0) > 0 ? "Reviewed Helpful uses" : "Candidate · no Helpful use"
            var node = CompanionGraphNode(id: nodeID(method.binding), title: method.title, subtitle: "Saved method · v\(method.revision)",
                kind: .method, status: status,
                details: [.init(label: "Your instruction", value: method.instruction),
                    .init(label: "Availability", value: issue ?? (latest.contains(method.binding)
                        ? "Available for a matching passage. Every new result still needs review."
                        : "Retained for history. Choose the latest available version for a new passage.")),
                    .init(label: "Outcome", value: outcomes.map {
                        "\($0.helpful) Helpful · \($0.needsCorrection) corrected or withdrawn · \($0.awaitingReview) awaiting review · \($0.attempts) uses"
                    } ?? "Outcome history is unavailable."),
                    .init(label: "Requirements", value: (method.mustBeShorter ? "Shorter text" : "Flexible length")
                        + " · " + (method.preserveNumbersAndLinks ? "Exact numbers and links" : "No exact-token requirement")),
                    .init(label: "Method ID", value: method.id),
                    .init(label: "Revision", value: String(method.revision)),
                    .init(label: "Digest", value: method.binding.digest),
                    .init(label: "Meaning", value: "An authored candidate and its recorded outcomes. Keeping or inspecting it does not demonstrate usefulness on another task.")],
                target: .documentMethod(method.binding))
            node.presentationState = !current ? .needsReview : method.withdrawn ? .withdrawn
                : (outcomes?.needsCorrection ?? 0) > 0 ? .corrected : issue != nil ? .unavailable
                : !latest.contains(method.binding) ? .historical
                : (outcomes?.helpful ?? 0) > 0 ? .reviewed : .candidate
            node.evidenceTrail = evidenceTrail(for: method, store: store, historyIsCurrent: current,
                isLatest: latest.contains(method.binding), unavailableReason: issue)
            _ = add(node)
        }
        for method in methods where ids.contains(nodeID(method.binding)) {
            let id = nodeID(method.binding)
            link("companion-archi", id, "saved method")
            if let prior = method.supersedes { link(id, nodeID(prior), "supersedes version", relationship: .supersedes) }
            if let origin = method.knowledgeOrigin {
                let exact = store.readingSources.knowledgePages.first { $0.binding == origin }
                let latestPage = store.readingSources.latestKnowledgePages.first { $0.binding == origin }
                let existing = latestPage.flatMap { page in
                    // Activity also contains older captured references with the
                    // same navigation target. Only the page owner's exact node
                    // represents this retained origin revision.
                    nodes.first { $0.id == KnowledgePageGraph.nodeID(page.binding) }
                }
                let sourceID = existing?.id ?? key(["method-concept", origin.id, String(origin.revision), origin.digest])
                if existing != nil || add(.init(id: sourceID,
                    title: exact?.title ?? "Unavailable concept version", subtitle: "Origin concept · v\(origin.revision)",
                    kind: .knowledge, status: "Historical reference",
                    details: [.init(label: "Knowledge page ID", value: origin.id),
                        .init(label: "Revision", value: String(origin.revision)),
                        .init(label: "Digest", value: origin.digest),
                        .init(label: "Meaning", value: "The method retains this exact origin. A newer concept never replaces this reference.")],
                    target: .knowledgePage(origin))) { link(id, sourceID, "authored from concept", relationship: .authoredFrom) }
            }
            if !method.originRecordID.isEmpty {
                let record = store.documentWork.records.first { $0.id == method.originRecordID }
                let supportID = DocumentWorkGraph.nodeID(recordID: method.originRecordID)
                let exactReview = record?.feedback?.id == method.originFeedbackID
                let disposition = record.map { MethodLearningHistory.disposition(of: $0).title } ?? "Supporting edit unavailable"
                let status = !current ? "History needs review"
                    : record != nil && !exactReview ? "Original review changed" : disposition
                if add(.init(id: supportID, title: "Supporting passage edit", subtitle: "Retained review reference",
                    kind: .answer, status: status,
                    details: [.init(label: "Outcome", value: status),
                        .init(label: "Record ID", value: method.originRecordID),
                        .init(label: "Original review ID", value: method.originFeedbackID),
                        .init(label: "Current review ID", value: record?.feedback?.id ?? "Unavailable"),
                        .init(label: "Request ID", value: record?.requestID ?? "Unavailable"),
                        .init(label: "Meaning", value: "This receipt supported a saved candidate. Document and reply text are not retained here.")],
                    target: nil)) { link(id, supportID, "kept from reviewed edit", relationship: .retainedFrom) }
            }
        }
        // In All activity, connect retained uses already present in that map.
        // The Memory surface does not add every request or accounting record.
        for record in store.documentWork.records {
            guard let use = record.procedureUse,
                  ids.contains(DocumentWorkGraph.nodeID(recordID: record.id)), ids.contains(nodeID(use)) else { continue }
            link(DocumentWorkGraph.nodeID(recordID: record.id), nodeID(use), "used exact method version", relationship: .usedMethod)
        }
        return .init(nodes: nodes, edges: edges, truncatedCount: omitted)
    }

    /// Display metadata from the existing owners. No new evidence is admitted,
    /// and a retained use record alone never proves that its lane dispatched.
    private static func evidenceTrail(for method: DocumentProcedure, store: CompanionStore,
                                      historyIsCurrent: Bool, isLatest: Bool,
                                      unavailableReason: String?) -> [CompanionGraphEvidence] {
        let binding = method.binding
        let methodReference = "\(binding.id) · v\(binding.revision) · \(binding.digest)"
        guard historyIsCurrent,
              HamptonMethodOutcomes(records: store.documentWork.records).reconciliationIssue == nil,
              let history = MethodLearningHistory(procedure: binding, records: store.documentWork.records,
                historyIsCurrent: true) else {
            return [.init(id: key(["method-evidence", binding.digest, "unavailable"]), stage: .unknown,
                summary: "Method or outcome history is unavailable or needs reconciliation. No current outcome or state change is established.",
                reference: methodReference)]
        }
        var trail: [CompanionGraphEvidence] = []
        func add(_ suffix: String, _ stage: CompanionGraphEvidenceStage, _ summary: String,
                 reference: String? = nil, relatedNodeID: String? = nil) {
            trail.append(.init(id: key(["method-evidence", binding.digest, suffix]), stage: stage,
                summary: summary, reference: reference ?? methodReference, relatedNodeID: relatedNodeID))
        }
        if !isLatest {
            add("historical", .historical, "Earlier exact method version. Its outcomes remain with this version; later versions do not inherit them.")
        }
        if method.withdrawn {
            add("withdrawn", .withdrawn, "The owner withdrew this exact method. Retained uses remain inspectable and do not restore eligibility.")
        } else if let unavailableReason {
            add("unavailable", .unknown, "Reuse is unavailable: \(unavailableReason)")
        }
        if store.preparedDocumentProcedure == binding {
            if unavailableReason == nil && store.preparedProcedureMatchesCurrentDraft(question: store.prompt) {
                add("prepared", .prepared, "This exact version is prepared in the current draft. Preparation does not establish dispatch, checks or an outcome.")
            } else {
                add("prepared-stale", .unknown, "A prepared reference remains, but it no longer matches an eligible current draft. No new use is established.")
            }
        }
        let records = history.records.sorted {
            $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt
        }
        if records.isEmpty {
            add("no-uses", .unknown, "No retained uses of this exact version. No checked result, owner-reviewed outcome or Hampton state change is recorded.")
        }
        for record in records.prefix(3) {
            let recordReference = "\(methodReference) · record \(record.id) · request \(record.requestID) · \(record.provider)"
            let related = DocumentWorkGraph.nodeID(recordID: record.id)
            let provider = AssistantProvider(rawValue: record.provider)
                ?? AssistantProvider.allCases.first { $0.name == record.provider }
            let tasks = store.tokenSteward.tasks.filter { $0.id == record.requestID }
            let lanes = tasks.count == 1 ? tasks[0].lanes.filter { $0.provider == provider?.name } : []
            let dispatched = store.tokenSteward.loadError == nil && tasks.count == 1
                && AssistantRoute(rawValue: tasks[0].route) != nil && lanes.count == 1 && lanes[0].dispatched
            add(record.id + "-dispatch", dispatched ? .dispatched : .unknown,
                dispatched ? "Usage retained a dispatch for this exact request and provider. This does not prove a successful result."
                    : "No unambiguous dispatch receipt is available for this request and provider. Its retained work state is \(record.state.rawValue).",
                reference: recordReference, relatedNodeID: related)
            if record.checks.isEmpty {
                add(record.id + "-checks", .unknown, "No mechanical checks are retained for this use.",
                    reference: recordReference, relatedNodeID: related)
            } else {
                let passed = record.checks.filter(\.passed).count
                add(record.id + "-checks", .checked,
                    "\(passed) of \(record.checks.count) recorded mechanical checks passed. Retained state: \(record.state.rawValue). Checks do not establish factual accuracy, preserved meaning or Helpful review.",
                    reference: recordReference, relatedNodeID: related)
            }
            if let feedback = record.feedback {
                add(record.id + "-review-" + feedback.id, feedback.verdict == .withdrawn ? .withdrawn : .ownerReviewed,
                    "Owner verdict: \(feedback.verdict.rawValue) · review v\(feedback.revision). Current disposition: \(MethodLearningHistory.disposition(of: record).title). This is the retained current event; prior verdicts are not reconstructed.",
                    reference: recordReference + " · review " + feedback.id, relatedNodeID: related)
            } else {
                add(record.id + "-unreviewed", .unknown,
                    "No owner review is recorded. Current disposition: \(MethodLearningHistory.disposition(of: record).title).",
                    reference: recordReference, relatedNodeID: related)
            }
            if record.procedureUseRejected == true {
                add(record.id + "-counterexample", .correction,
                    "The owner retains a method counterexample. A later Helpful verdict or method withdrawal cannot erase this marker.",
                    reference: recordReference, relatedNodeID: related)
            }
            if let decision = record.q2eDecision, decision.isValid,
               decision.domain == "document-revision", decision.contextID == record.sourceDigest, decision.lane != .stop {
                let signals = decision.signals
                let strategies = signals.strategyResults.sorted { $0.key < $1.key }.map {
                    "\($0.key): \($0.value.helpful) Helpful, \($0.value.corrections) corrections"
                }.joined(separator: "; ")
                let predecessor = decision.predecessor.map { "retained predecessor v\($0.revision) · \($0.decisionDigest)" }
                    ?? (decision.version == HamptonQ2EController.legacyVersion
                        ? "not recorded by legacy receipt" : "initial zero reference; no observed predecessor")
                add(record.id + "-control", .adaptation,
                    "Captured Hampton decision \(decision.version), schema \(decision.coordinateSchema ?? "not recorded (legacy)"), revision \(decision.revision). Inputs: \(signals.observations) observations, \(signals.retainedSupport) support, \(signals.contradictions) contradictions, \(signals.unchangedSteps) unchanged steps, \(signals.availableAlternatives) alternatives, budget \(signals.remainingBudget)/\(signals.totalBudget), prerequisites \(signals.prerequisitesSatisfied). Strategy inputs: \(strategies.isEmpty ? "none" : strategies). Coordinates: \(coordinates(decision.pressures)). Delta: \(coordinates(decision.delta)); reference: \(predecessor). Action: \(decision.lane.rawValue); weights: \(coordinates(decision.laneWeights)). This receipt records a control decision, not a learning gain or persistent companion state change.",
                    reference: recordReference + " · source " + decision.contextID + " · decision " + decision.bindingDigest,
                    relatedNodeID: related)
            } else {
                add(record.id + "-control-unknown", .unknown,
                    "No valid exact-source Hampton control receipt is retained for this use. No controller update or state change is established.",
                    reference: recordReference, relatedNodeID: related)
            }
        }
        if records.count > 3 {
            add("older-uses", .historical,
                "Showing the latest 3 of \(records.count) exact-version uses. \(records.count - 3) earlier uses remain in the owner's method history.")
        }
        return trail
    }

    private static func coordinates(_ values: [String: Double]) -> String {
        values.keys.sorted().map { "\($0)=\(values[$0]!)" }.joined(separator: ", ")
    }

    private static func key(_ parts: [String]) -> String {
        let bytes = Data(parts.map { "\($0.utf8.count):\($0)" }.joined().utf8)
        return "document-method-" + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

/// Visit-only selection binds the sheet to its owners across profile changes.
struct DocumentMethodInspectionSelection: Identifiable {
    let id = UUID()
    let binding: DocumentProcedureUse
    let methodOwner: ObjectIdentifier
    let historyOwner: ObjectIdentifier
    let sourceOwner: ObjectIdentifier
}

@MainActor
extension CompanionStore {
    func memoryMapSnapshot(at date: Date = Date()) -> CompanionGraphSnapshot {
        DocumentMethodGraph.append(to: MemoryMapSnapshot.build(library: readingSources, lessons: keptLessons, at: date), store: self)
    }

    func methodForInspection(_ selection: DocumentMethodInspectionSelection) -> DocumentProcedure? {
        guard !isShuttingDown, profileRecoveryBlock == nil,
              selection.methodOwner == ObjectIdentifier(documentProcedures),
              selection.historyOwner == ObjectIdentifier(documentWork),
              selection.sourceOwner == ObjectIdentifier(readingSources),
              documentProcedures.isCurrentOnDisk, documentWork.isCurrentOnDisk else { return nil }
        return documentProcedures.procedure(matching: selection.binding)
    }
}
