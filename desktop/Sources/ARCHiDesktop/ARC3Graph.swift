import Foundation

/// Read-only projection of the current interactive episode. No rules are promoted
/// into companion memory and no environment or model action occurs here.
enum ARC3Graph {
    static func append(to base: CompanionGraphSnapshot, observation: ARC3Observation?,
                       transitions: [ARC3Transition], summary: ARC3SessionSummary?) -> CompanionGraphSnapshot {
        guard let observation else { return base }
        var nodes = base.nodes, edges = base.edges, omitted = base.truncatedCount
        let id = "arc3-current-episode"
        guard nodes.count < CompanionGraph.maximumNodes else {
            return .init(nodes: nodes, edges: edges, truncatedCount: omitted + 1 + transitions.count)
        }
        nodes.append(.init(id: id, title: "Interactive ARC3", subtitle: observation.gameID,
            kind: .evaluation, status: observation.state,
            details: [.init(label: "Scope", value: "Current local episode; environment progress is not a benchmark or companion skill."),
                      .init(label: "Actions confirmed", value: "\(observation.dispatches)/\(observation.budget)"),
                      .init(label: "Frame digest", value: observation.frameDigest)], target: .interactiveARC))
        func connect(_ from: String, _ to: String, _ label: String) {
            if edges.count < CompanionGraph.maximumEdges {
                edges.append(.init(id: "arc3-edge-\(from)-\(to)", source: from, target: to, label: label))
            } else { omitted += 1 }
        }
        connect("companion-archi", id, "explores within session budget")
        omitted += max(0, transitions.count - 16)
        for transition in transitions.suffix(16) {
            guard nodes.count < CompanionGraph.maximumNodes else { omitted += 1; continue }
            let target = "arc3-transition-" + transition.id.uuidString
            nodes.append(.init(id: target, title: transition.actionName, subtitle: "Observed transition",
                kind: .context, status: transition.invalidated ? "Prediction invalidated" : transition.verdict.rawValue,
                details: [.init(label: "Before", value: transition.beforeDigest),
                          .init(label: "Predicted", value: transition.predictedDigest ?? "No prior transition hypothesis"),
                          .init(label: "Observed", value: transition.afterDigest),
                          .init(label: "Meaning", value: "Task-local evidence only; support is scoped to this visible state and action.")], target: .interactiveARC))
            connect(id, target, "observed action")
        }
        if let summary, nodes.count < CompanionGraph.maximumNodes {
            let task = "arc3-usage-" + summary.sessionID
            nodes.append(.init(id: task, title: "ARC3 session accounting", subtitle: "No model calls",
                kind: .accounting, status: summary.outcome,
                details: [.init(label: "Session", value: summary.sessionID)], target: .stewardTask(taskID: summary.sessionID)))
            connect(id, task, "recorded execution")
        }
        return .init(nodes: nodes, edges: edges, truncatedCount: omitted)
    }
}
