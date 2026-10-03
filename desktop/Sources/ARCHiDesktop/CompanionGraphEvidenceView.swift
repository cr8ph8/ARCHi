import SwiftUI

/// Inspection of recorded events only; this view has no mutation or model route.
struct CompanionGraphEvidenceView: View {
    let trail: [CompanionGraphEvidence]
    let snapshot: CompanionGraphSnapshot
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Use and outcome history", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 12, weight: .semibold))
            Text("Preparation, execution and your review are separate records.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            ForEach(trail.prefix(3)) { item in row(item) }
            if trail.count > 3 {
                DisclosureGroup("\(trail.count - 3) more recorded steps") {
                    ForEach(trail.dropFirst(3)) { item in row(item).padding(.top, 7) }
                }.font(.system(size: 11))
            }
        }
        .accessibilityIdentifier("companion-graph.evidence-trail")
    }

    private func row(_ item: CompanionGraphEvidence) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(item.stage.title, systemImage: item.stage.symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(item.summary).font(.system(size: 11)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let reference = item.reference {
                DisclosureGroup("Evidence reference") {
                    Text(reference).font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if let id = item.relatedNodeID, snapshot.nodes.contains(where: { $0.id == id }) {
                Button("Inspect recorded use", systemImage: "arrow.up.right") { onSelect(id) }
                    .buttonStyle(.borderless).font(.system(size: 11))
            }
        }
        .padding(9).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }
}

struct CompanionGraphConnectionView: View {
    let edge: CompanionGraphEdge
    let source: CompanionGraphNode
    let target: CompanionGraphNode
    let incoming: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(edge.label, systemImage: edge.relationship.symbol)
                        .font(.system(size: 11, weight: .semibold))
                    endpoint(source)
                    Image(systemName: "arrow.down").font(.system(size: 9)).foregroundStyle(.secondary)
                    endpoint(target)
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(source.title), \(source.subtitle), \(edge.label), \(target.title), \(target.subtitle)")
            .accessibilityHint("Inspect \(incoming ? source.title : target.title)")
            .accessibilityIdentifier("companion-graph.link.\(incoming ? "incoming" : "outgoing").\(edge.id)")
            if let rationale = edge.rationale {
                DisclosureGroup("Why linked") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(rationale).textSelection(.enabled)
                        Text("Reviewed declaration; factual support is not certified.").foregroundStyle(.secondary)
                        if let reference = edge.reference {
                            Text(reference).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }.font(.system(size: 11)).fixedSize(horizontal: false, vertical: true).padding(.top, 5)
                }.font(.system(size: 11))
            }
        }
        .padding(9).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    private func endpoint(_ node: CompanionGraphNode) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: node.presentationState.needsAttention ? node.presentationState.symbol : node.kind.symbol)
                .foregroundStyle(graphColor(node.kind)).frame(width: 13)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.title).fontWeight(.medium)
                if !node.subtitle.isEmpty { Text(node.subtitle).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
        }.font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
    }
}
