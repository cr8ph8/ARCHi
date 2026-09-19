import SwiftUI

/// An explicit, optional local proposal lane beside the deterministic search.
@MainActor
struct ARCQwenProposalPanel: View {
    @ObservedObject var store: ARCCapabilitiesStore
    let model: String
    var onEvaluation: @MainActor (ARCCapabilitiesEvent) -> Void
    var onOpenUsage: ((String) -> Void)?
    var onOpenGraph: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Try a rule with Qwen", systemImage: "sparkles")
                .font(.headline)
            Text("Let your local model propose a short rule. ARCHi tests it against every training example before making a prediction.")
                .font(.callout).foregroundStyle(.secondary)
            Label(model + " · on this Mac", systemImage: "desktopcomputer")
                .font(.caption).foregroundStyle(WorkspaceTheme.accent)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { controls }
                VStack(alignment: .leading, spacing: 10) { controls }
            }
            HStack(alignment: .top, spacing: 8) {
                if store.isProposing { ProgressView().controlSize(.small) }
                Text(store.qwenProposalStatus)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("capabilities.qwen.status")
            }
            if let review = store.qwenProposalReview {
                if let result = review.result {
                    Text(title(result.status)).font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("capabilities.qwen.outcome")
                    Text(rule(result)).font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Text("Training examples passed: \(result.trainingPassed) of \(result.trainingCount) · \(review.elapsedMilliseconds) ms")
                        .font(.caption).foregroundStyle(.secondary)
                    if let predictions = result.predictions {
                        ForEach(predictions.indices, id: \.self) { index in
                            ARCNativeGrid(grid: predictions[index], title: "Qwen rule · Test \(index + 1) prediction",
                                identifier: "qwen.prediction.\(index)")
                        }
                    }
                }
                if let id = review.evidenceID,
                   let record = store.records.first(where: { $0.id == id }) {
                    let counts = record.summary.counts
                    Text("Independent check: \(counts.exact) exact · \(counts.incorrect) incorrect · \(counts.missing) missing · \(counts.unscored) unscored")
                        .font(.callout).accessibilityIdentifier("capabilities.qwen.checker")
                    Text(review.document.isSynthetic ? "Synthetic sample · Not a benchmark" : "One proposed rule · Not a certified capability")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    if let onOpenUsage {
                        Button("View run in Usage") { onOpenUsage(review.taskID) }
                            .accessibilityIdentifier("capabilities.qwen.open-usage")
                    }
                    if let id = review.evidenceID, let onOpenGraph {
                        Button("View in Activity map") { onOpenGraph(id) }
                            .accessibilityIdentifier("capabilities.qwen.open-graph")
                    }
                }.buttonStyle(.plain).font(.callout).foregroundStyle(WorkspaceTheme.accent)
            }
            Text("Shares only this puzzle’s training pairs and test inputs with local Qwen. Expected test answers stay with the checker. Choose the local model in Settings.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16).modifier(WorkspaceSurface())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capabilities.qwen")
    }

    private var controls: some View {
        Group {
            Button("Ask Qwen for a rule", systemImage: "sparkles") {
                store.startQwenProposal(model: model, onEvaluation: onEvaluation)
            }
            .buttonStyle(WorkspaceActionStyle())
            .disabled(store.solverDocument == nil || store.isSolving || store.isProposing)
            .accessibilityIdentifier("capabilities.qwen.propose")
            Button("Stop Qwen", systemImage: "stop.fill") { store.stopQwenProposal() }
                .disabled(!store.isProposing)
                .accessibilityIdentifier("capabilities.qwen.stop")
        }
    }

    private func rule(_ result: ARCQwenProposalResult) -> String {
        guard result.status != .abstained else { return "No rule proposed." }
        let steps = result.steps.map(\.rawValue) + (result.learnPalette ? ["learn palette from training"] : [])
        return steps.isEmpty ? "identity" : steps.joined(separator: " → ")
    }

    private func title(_ status: ARCQwenProposalResult.Status) -> String {
        switch status {
        case .predicted: "Rule fits training · Prediction proposed"
        case .abstained: "Qwen abstained"
        case .trainingMismatch: "Rule did not fit the training examples"
        case .trainingUndefined: "Rule could not process a training example"
        case .predictionUndefined: "Rule could not process every test input"
        case .budgetExhausted: "Rule reached its local work limit"
        }
    }
}
