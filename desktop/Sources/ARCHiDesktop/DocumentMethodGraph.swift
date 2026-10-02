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
        func link(_ source: String, _ target: String, _ label: String) {
            let id = key(["method-edge", source, target, label])
            guard !edgeIDs.contains(id) else { return }
            guard ids.contains(source), ids.contains(target), edges.count < CompanionGraph.maximumEdges else {
                omitted += 1; return
            }
            edges.append(.init(id: id, source: source, target: target, label: label)); edgeIDs.insert(id)
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
            _ = add(.init(id: nodeID(method.binding), title: method.title, subtitle: "Saved method · v\(method.revision)",
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
                target: .documentMethod(method.binding)))
        }
        for method in methods where ids.contains(nodeID(method.binding)) {
            let id = nodeID(method.binding)
            link("companion-archi", id, "saved method")
            if let prior = method.supersedes { link(id, nodeID(prior), "supersedes version") }
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
                    target: nil)) { link(id, sourceID, "authored from concept") }
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
                    target: nil)) { link(id, supportID, "kept from reviewed edit") }
            }
        }
        // In All activity, connect retained uses already present in that map.
        // The Memory surface does not add every request or accounting record.
        for record in store.documentWork.records {
            guard let use = record.procedureUse,
                  ids.contains(DocumentWorkGraph.nodeID(recordID: record.id)), ids.contains(nodeID(use)) else { continue }
            link(DocumentWorkGraph.nodeID(recordID: record.id), nodeID(use), "used exact method version")
        }
        return .init(nodes: nodes, edges: edges, truncatedCount: omitted)
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
