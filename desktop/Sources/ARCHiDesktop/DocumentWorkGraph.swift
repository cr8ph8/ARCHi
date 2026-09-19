import Foundation
import CryptoKit

/// A pure view of retained document-task metadata. It neither reads the working
/// copy nor applies an edit, reruns checks, infers meaning, or updates a journal.
enum DocumentWorkGraph {
    static func append(to base: CompanionGraphSnapshot, records: [DocumentWorkRecord],
                       accountingTaskIDs: Set<String>) -> CompanionGraphSnapshot {
        var nodes = Array(base.nodes.prefix(CompanionGraph.maximumNodes))
        var nodeIDs = Set(nodes.map(\.id))
        var edges: [CompanionGraphEdge] = []
        var edgeIDs = Set<String>()
        var omitted = base.truncatedCount + max(0, base.nodes.count - nodes.count)
        // Preserve bounded existing edges only when both endpoints survived.
        for edge in base.edges {
            guard edges.count < CompanionGraph.maximumEdges,
                  nodeIDs.contains(edge.source), nodeIDs.contains(edge.target),
                  !edgeIDs.contains(edge.id) else { omitted += 1; continue }
            edges.append(edge)
            edgeIDs.insert(edge.id)
        }
        let accountingIDs = Set(accountingTaskIDs.map { Data($0.utf8) })
        let latest = records.sorted {
            $0.createdAt == $1.createdAt ? key($0.id) < key($1.id) : $0.createdAt > $1.createdAt
        }
        // Each older record counts as one unprojected input, without inventing
        // nodes or edges for details this projection never attempts to expand.
        omitted += max(0, latest.count - 12)

        @discardableResult
        func add(_ node: CompanionGraphNode) -> Bool {
            if nodeIDs.contains(node.id) { return true }
            guard nodes.count < CompanionGraph.maximumNodes else { omitted += 1; return false }
            nodes.append(node)
            nodeIDs.insert(node.id)
            return true
        }

        func connect(_ source: String, _ target: String, _ label: String) {
            let id = "document-work-edge-" + key(source + "|" + target + "|" + label)
            if edgeIDs.contains(id) { return }
            guard edges.count < CompanionGraph.maximumEdges,
                  nodeIDs.contains(source), nodeIDs.contains(target) else { omitted += 1; return }
            edges.append(.init(id: id, source: source, target: target, label: label))
            edgeIDs.insert(id)
        }

        for record in latest.prefix(12) {
            let taskID = "document-work-" + key(record.id)
            let hasAccounting = accountingIDs.contains(Data(record.requestID.utf8))
            var details: [CompanionGraphDetail] = [
                .init(label: "Scope", value: "Selected-passage task metadata. Mechanical checks do not establish factual accuracy or preserved meaning."),
                .init(label: "Request ID", value: limited(record.requestID, to: 128)),
                .init(label: "Provider", value: limited(record.provider, to: 128)),
                .init(label: "Target ID", value: limited(record.targetID, to: 128)),
                .init(label: "State", value: record.state.rawValue),
                .init(label: "Your review", value: record.feedback?.verdict.rawValue ?? "Not reviewed"),
                .init(label: "Review event", value: record.feedback?.id ?? "Not recorded"),
                .init(label: "Captured lesson versions", value: String(record.learning?.usedLessons.count ?? 0)),
                .init(label: "Procedure version", value: record.procedureUse.map { "\($0.id) · v\($0.revision) · \($0.digest)" } ?? "No procedure selected"),
                .init(label: "Procedure counterexample", value: record.procedureUseRejected == true ? "Retained; reuse unavailable" : "Not recorded"),
                .init(label: "Learning boundary", value: "User judgment is separate from mechanical checks. Kept lessons and Evolution have their own explicit review/save controls."),
                .init(label: "Status detail", value: record.detail.isEmpty ? "No additional status recorded." : limited(record.detail, to: 800)),
                .init(label: "Source revision", value: String(record.sourceRevision)),
                .init(label: "Selection (UTF-16)", value: "Start \(record.selectionStart), length \(record.selectionLength)"),
                .init(label: "Source digest", value: limited(record.sourceDigest, to: 80)),
                .init(label: "Proposed passage digest", value: record.proposedDigest.map { limited($0, to: 80) } ?? "Not recorded"),
                .init(label: "Expected result digest", value: record.expectedAfterDigest.map { limited($0, to: 80) } ?? "Not recorded"),
                .init(label: "Actual result digest", value: record.actualAfterDigest.map { limited($0, to: 80) } ?? "Not recorded"),
                .init(label: "Result revision", value: record.afterRevision.map(String.init) ?? "Not recorded"),
                .init(label: "Shorter passage", value: record.mustBeShorter ? "Required" : "Not required"),
                .init(label: "Numbers and URLs", value: record.preserveNumbersAndLinks ? "Exact mechanical preservation required" : "Preservation check not requested"),
                .init(label: "Created", value: date(record.createdAt)),
                .init(label: "Updated", value: date(record.updatedAt)),
                .init(label: "Accounting", value: hasAccounting ? "Matching request ID available in Usage." : "No matching accounting task supplied.")
            ]
            if record.checks.isEmpty {
                details.append(.init(label: "Mechanical checks", value: "No checks recorded."))
            } else {
                details.append(contentsOf: record.checks.prefix(24).map { check in
                    .init(label: limited(check.title, to: 160), value: check.passed ? "Passed (mechanical)" : "Did not pass (mechanical)")
                })
            }
            guard add(.init(id: taskID, title: "Document revision", subtitle: "Selected passage · " + limited(record.provider, to: 128),
                            kind: .context, status: record.state.rawValue, details: details, target: .context)) else { continue }
            omitted += max(0, record.checks.count - 24)
            connect("companion-archi", taskID, "retained document task")

            // A request ID absent from Usage has no navigable accounting node.
            // Compare bytes rather than canonically equivalent String values.
            guard hasAccounting else { continue }
            let existing = nodes.first { node in
                guard node.kind == .accounting, let target = node.target,
                      case .stewardTask(let requestID) = target else { return false }
                return requestID.utf8.elementsEqual(record.requestID.utf8)
            }
            let accountingID = existing?.id ?? ("document-work-accounting-" + key(record.requestID))
            if existing == nil {
                guard add(.init(id: accountingID, title: "Document task accounting", subtitle: "Exact request association",
                                kind: .accounting, status: "Matching request ID",
                                details: [.init(label: "Request ID", value: limited(record.requestID, to: 128)),
                                          .init(label: "Scope", value: "Open the existing Usage task. This connection adds no cost, completion, or semantic-success claim.")],
                                target: .stewardTask(taskID: record.requestID))) else { continue }
            }
            connect(taskID, accountingID, "matching accounting request")
        }
        return .init(nodes: nodes, edges: edges, truncatedCount: omitted)
    }

    private static func key(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func limited(_ value: String, to count: Int) -> String {
        value.count > count ? String(value.prefix(count)) + "…" : value
    }

    private static func date(_ value: Date) -> String {
        value.timeIntervalSince1970.isFinite ? value.ISO8601Format() : "Invalid date"
    }
}
