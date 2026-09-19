import SwiftUI

/// The same task service is available from every assistant surface.
@MainActor
struct ARCActiveAssistantActions: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        Menu {
            Button("Revise selected passage") { store.preparePassageRevision() }
                .disabled(store.textSelection == nil || store.isWorking)
            Button("Shorten selected passage") { store.preparePassageRevision(shorten: true) }
                .disabled(store.textSelection == nil || store.isWorking)
            Button("Open document work") { store.open(.context) }
            Divider()
            Button("Solve shared or loaded grid task") { store.runARC(.solve) }
                .disabled(store.isWorking || store.voiceInput.isActive || store.isShuttingDown)
            Button("Propose a rule with local Qwen") { store.runARC(.propose) }
                .disabled(store.isWorking || store.voiceInput.isActive || store.isShuttingDown)
            Divider()
            Button("Open interactive ARC3") { store.runARC3(.open) }
            Button("Explore current ARC3 environment") { store.runARC3(.explore) }
                .disabled(store.isWorking || !store.arc3.isSessionActive || store.voiceInput.isActive || store.isShuttingDown)
            Divider()
            Button("Manage ARC tasks and results") { store.open(.capabilities) }
        } label: {
            Label("Work task", systemImage: "square.grid.3x3")
        }
        .menuStyle(.borderlessButton).fixedSize()
        .accessibilityIdentifier("assistant.arc-actions")
        .help("Prepare document work or use the shared ARC services. Preparing a document revision does not send it.")
    }
}

/// Navigation does not create a second execution owner. The current ARC job
/// stays inspectable and stoppable throughout the native workspace.
@MainActor
struct ARCActiveWorkBar: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        if let document = store.documentWork.records.first(where: { [.proposing, .ready].contains($0.state) }) {
            HStack(spacing: 12) {
                Label(document.state == .ready ? "Document revision ready for review" : "ARCHi is revising a passage", systemImage: "doc.text")
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
                Text(document.state == .ready ? "Nothing applied" : "Preparing a proposal").font(.caption).foregroundStyle(.secondary)
                Button("Stop") { store.cancelWork() }
                    .accessibilityIdentifier("workspace.document.stop")
            }
            .padding(.horizontal, 18).padding(.vertical, 10).background(WorkspaceTheme.panel)
            .accessibilityIdentifier("workspace.document.active")
        }
        if store.arc3.isSessionActive || store.arc3.isWorking || store.activeARCAnswer?.isWorking == true {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.3x3").foregroundStyle(WorkspaceTheme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.arc3.isSessionActive || store.arc3.isWorking ? "ARCHi is working with ARC3" : "ARCHi is reasoning with ARC")
                        .font(.callout.weight(.medium))
                    Text(store.arc3.isSessionActive || store.arc3.isWorking ? store.arc3.status : store.activeARCAnswer?.status ?? "Working…")
                        .font(.caption).foregroundStyle(WorkspaceTheme.muted).lineLimit(2)
                }
                Spacer(minLength: 0)
                Button("Open task") {
                    if store.arc3.isSessionActive || store.arc3.isWorking { store.runARC3(.open) }
                    else { store.open(.capabilities) }
                }.accessibilityIdentifier("workspace.arc.open")
                Button("Stop") { store.cancelWork() }
                    .accessibilityIdentifier("workspace.arc.stop")
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(WorkspaceTheme.panel)
            .accessibilityIdentifier("workspace.arc.active")
        }
    }
}

@MainActor
struct ARCActiveAssistantReply: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        if let answer = store.activeARCAnswer {
            VStack(alignment: .leading, spacing: 10) {
                Label("ARCHi · ARC", systemImage: "square.grid.3x3")
                    .font(.headline).foregroundStyle(WorkspaceTheme.accent)
                if let name = answer.inputName {
                    Text(name).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if answer.isWorking { ProgressView().controlSize(.small) }
                Text(answer.status).font(.callout).textSelection(.enabled)
                    .accessibilityIdentifier("assistant.arc-status")
                if let error = answer.error {
                    Text(error).foregroundStyle(.orange).font(.callout).textSelection(.enabled)
                }
                if let predictions = answer.predictions {
                    ForEach(predictions.indices, id: \.self) { index in
                        ARCNativeGrid(grid: predictions[index], title: "Prediction \(index + 1)",
                            identifier: "assistant.arc.prediction.\(index)")
                    }
                }
                if let summary = answer.summary {
                    Text("Checked result: \(summary.counts.exact) exact · \(summary.counts.incorrect) incorrect · \(summary.counts.missing) missing · \(summary.counts.unscored) unscored")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("assistant.arc-checker")
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { links(answer) }
                    VStack(alignment: .leading, spacing: 8) { links(answer) }
                }
                Text("Predictions are checked when expected answers are available. Otherwise they are marked unscored.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12).modifier(WorkspaceSurface())
            .accessibilityIdentifier("assistant.arc-result")
        }
    }

    @ViewBuilder private func links(_ answer: ARCActiveAssistantAnswer) -> some View {
        if let taskID = answer.taskID, !answer.isWorking {
            Button("Usage") { _ = store.openARCUsage(taskID: taskID) }
                .accessibilityIdentifier("assistant.arc-usage")
        }
        if let evidenceID = answer.evidenceID {
            Button("Activity map") { _ = store.openARCGraph(evidenceID: evidenceID) }
                .accessibilityIdentifier("assistant.arc-graph")
            Button("Review reasoning") {
                if store.arcCapabilities.selectRecord(id: evidenceID) { store.open(.capabilities) }
            }.accessibilityIdentifier("assistant.arc-evidence")
        }
    }
}
