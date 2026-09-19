import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A task canvas; execution, checking and persistence remain owned by the store.
@MainActor
struct ARCSolverPanel: View {
    @ObservedObject var store: ARCCapabilitiesStore
    var onEvaluation: @MainActor (ARCCapabilitiesEvent) -> Void = { _ in }
    var onOpenUsage: ((String) -> Void)? = nil
    var onOpenGraph: ((String) -> Void)? = nil
    var onShowQwen: (() -> Void)? = nil
    @State private var importError: String?
    @State private var showTraining = false
    @State private var showHowItWorks = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Label("ARC task canvas", systemImage: "square.grid.3x3.fill")
                    .font(.title3.weight(.semibold))
                Text("Load examples. Find a rule. Review the result.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            stepContext
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { loadControls; Spacer(minLength: 8); runControls }
                VStack(alignment: .leading, spacing: 10) { loadControls; runControls }
            }
            if let error = importError {
                ARCPanelNotice(title: "Task could not be loaded", detail: error)
                    .accessibilityIdentifier("capabilities.solver.import-error")
            }
            HStack(alignment: .top, spacing: 8) {
                if store.isSolving || store.isProposing { ProgressView().controlSize(.small) }
                Text(store.isProposing ? store.qwenProposalStatus : store.solverStatus)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    .accessibilityIdentifier("capabilities.solver.status")
            }
            if let document = store.solverDocument {
                Divider()
                documentContent(document)
            }
            if let review = store.solverReview {
                Divider()
                reviewContent(review)
            }
            howItWorks
        }
        .padding(16).modifier(WorkspaceSurface(emphasis: true))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capabilities.solver")
    }

    private var stepContext: some View {
        HStack(spacing: 8) {
            step("1 · Load", active: store.solverDocument == nil)
            step("2 · Solve", active: store.solverDocument != nil && store.solverReview == nil)
            step("3 · Review", active: store.solverReview != nil)
        }.accessibilityIdentifier("capabilities.solver.steps")
    }

    private func step(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.caption.weight(active ? .semibold : .regular))
            .foregroundStyle(active ? WorkspaceTheme.accent : Color.secondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(active ? WorkspaceTheme.accent.opacity(0.10) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .accessibilityLabel(title + (active ? ", current step" : ""))
    }

    private var loadControls: some View {
        HStack(spacing: 10) {
            Button("Import ARC task…", systemImage: "square.and.arrow.down", action: importTask)
                .help("Open one standard ARC train/test JSON task.")
                .accessibilityIdentifier("capabilities.solver.import")
            Button("Load sample") {
                do {
                    try store.loadSolverSample()
                    importError = nil
                } catch { importError = error.localizedDescription }
            }
            .help("Load the built-in synthetic task. Loading does not run the solver.")
            .accessibilityIdentifier("capabilities.solver.sample")
        }.disabled(store.isSolving || store.isProposing)
    }

    private var runControls: some View {
        HStack(spacing: 10) {
            Button("Solve locally", systemImage: "play.fill") {
                importError = nil
                store.startSolving(onEvaluation: onEvaluation)
            }
            .buttonStyle(WorkspaceActionStyle(prominent: true))
            .disabled(store.solverDocument == nil || store.isSolving || store.isProposing)
            .accessibilityIdentifier("capabilities.solver.solve")
            if let onShowQwen {
                Button("Try Qwen", action: onShowQwen)
                    .help("Go to the local Qwen proposal controls.")
                    .accessibilityIdentifier("capabilities.solver.show-qwen")
            }
            Button("Stop", systemImage: "stop.fill") { store.stopSolving() }
                .disabled(!store.isSolving && !store.isProposing)
                .accessibilityIdentifier("capabilities.solver.stop")
        }
    }

    private func documentContent(_ document: ARCSolverDocument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(document.name).font(.headline).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Label(document.isSynthetic ? "Synthetic sample" : "Imported task · Source unverified",
                      systemImage: document.isSynthetic ? "testtube.2" : "doc")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("capabilities.solver.source")
            }
            DisclosureGroup("Training pairs (\(document.input.training.count))", isExpanded: $showTraining) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(document.input.training.indices, id: \.self) { index in
                        let pair = document.input.training[index]
                        gridPair(left: pair.input, leftTitle: "Training \(index + 1) · Input",
                                 right: pair.output, rightTitle: "Training \(index + 1) · Output",
                                 identifier: "training.\(index)")
                    }
                }.padding(.top, 10)
            }.accessibilityIdentifier("capabilities.solver.training")
            if !hasPredictionPreview(for: document) {
                Text("Test inputs · \(document.input.testInputs.count)")
                    .font(.subheadline.weight(.semibold))
                ForEach(document.input.testInputs.indices, id: \.self) { index in
                    ARCNativeGrid(grid: document.input.testInputs[index], title: "Test \(index + 1) · Input",
                                  identifier: "test.\(index).input")
                }
            }
        }
    }

    private func hasPredictionPreview(for document: ARCSolverDocument) -> Bool {
        guard let review = store.solverReview else { return false }
        return review.document.inputDigest == document.inputDigest
            && review.run.outcome == .predicted && review.run.predictions != nil
    }

    private func reviewContent(_ review: ARCSolverReview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label(Self.outcomeTitle(review.run.outcome),
                      systemImage: review.run.outcome == .predicted ? "square.grid.3x3" : "hand.raised")
                    .font(.headline)
                    .foregroundStyle(review.run.outcome == .predicted ? WorkspaceTheme.accent : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("capabilities.solver.outcome")
                Text(outcomeExplanation(review.run.outcome))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], spacing: 8) {
                ARCMetricTile(value: String(review.run.attemptedPrograms), title: "Rules tried", identifier: "programs")
                ARCMetricTile(value: String(review.run.matchingPrograms), title: "Training fits", identifier: "fits")
                ARCMetricTile(value: String(review.run.cellOperations), title: "Cell work", identifier: "cell-work")
                ARCMetricTile(value: "\(review.elapsedMilliseconds) ms", title: "Elapsed", identifier: "elapsed")
            }.accessibilityIdentifier("capabilities.solver.metrics")
            if let error = review.error {
                ARCPanelNotice(title: "Result could not be saved", detail: error)
                    .accessibilityIdentifier("capabilities.solver.review-error")
            }
            if let matched = review.replayMatched {
                Label(matched ? "Replay matches the retained result and trace" : "Replay differs from the retained result or trace",
                      systemImage: matched ? "equal.circle" : "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(matched ? WorkspaceTheme.positive : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("capabilities.solver.replay-result")
            }
            if review.run.outcome == .predicted, let predictions = review.run.predictions {
                ForEach(predictions.indices, id: \.self) { index in
                    if review.document.input.testInputs.indices.contains(index) {
                        gridPair(left: review.document.input.testInputs[index], leftTitle: "Test \(index + 1) · Input",
                                 right: predictions[index], rightTitle: "Test \(index + 1) · Prediction",
                                 identifier: "prediction.\(index)")
                    }
                }
            }
            checkerContent(review)
            reviewActions(review)
            traceContent(review.run)
        }
    }

    @ViewBuilder
    private func checkerContent(_ review: ARCSolverReview) -> some View {
        if let record = store.records.first(where: { $0.id == review.evidenceID }) {
            let counts = record.summary.counts
            VStack(alignment: .leading, spacing: 6) {
                Label("Independent exact check", systemImage: "checkmark.viewfinder")
                    .font(.subheadline.weight(.semibold))
                Text("Exact \(counts.exact) of \(counts.totalExamples) · Incorrect \(counts.incorrect) · Missing \(counts.missing) · Invalid \(counts.invalid) · Unscored \(counts.unscored)")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("capabilities.solver.checker")
                Text(review.document.isSynthetic
                     ? "Synthetic answers · Not a benchmark"
                     : "File-supplied answers · Source unverified")
                    .font(.caption).foregroundStyle(.secondary)
                if counts.unscored > 0 {
                    Text("Inputs without supplied answers remain unscored.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(WorkspaceTheme.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        } else {
            Label("No saved checker receipt for this run", systemImage: "doc.badge.ellipsis")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func reviewActions(_ review: ARCSolverReview) -> some View {
        let taskID: String? = review.taskID
        if (taskID != nil && onOpenUsage != nil) || (review.evidenceID != nil && onOpenGraph != nil) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { reviewActionButtons(review) }
                VStack(alignment: .leading, spacing: 8) { reviewActionButtons(review) }
            }
        }
    }

    @ViewBuilder
    private func reviewActionButtons(_ review: ARCSolverReview) -> some View {
        let taskID: String? = review.taskID
        if let taskID, let onOpenUsage {
            Button("View run in Usage", systemImage: "chart.bar") { onOpenUsage(taskID) }
                .buttonStyle(WorkspaceActionStyle())
                .help("Review this attempt’s elapsed time and accounting.")
                .accessibilityIdentifier("capabilities.solver.open-usage")
        }
        if let evidenceID = review.evidenceID, let onOpenGraph {
            Button("View in Activity map", systemImage: "point.3.connected.trianglepath.dotted") { onOpenGraph(evidenceID) }
                .buttonStyle(WorkspaceActionStyle())
                .help("Open this retained evidence in the Activity map.")
                .accessibilityIdentifier("capabilities.solver.open-graph")
        }
    }

    private var howItWorks: some View {
        DisclosureGroup("How this works", isExpanded: $showHowItWorks) {
            VStack(alignment: .leading, spacing: 10) {
                Text("The local solver searches a fixed catalog of grid rules. Each fitting rule must pass every training pair, and all fitting rules must agree on every test prediction. A partial search or disagreement produces no prediction.")
                Text("Hampton feedback uses training falsifications to choose which example to check first. Counts reset for each run. Supplied test answers stay outside the solver and are used only by the independent checker.")
                Text("Import standard ARC JSON with 1–20 train and test examples. Grids must be rectangular, up to 30 × 30, with integer colors 0–9. Training outputs are required; test outputs are optional. Files are limited to 2 MiB; extra fields are rejected.")
                Text("Cell work is an abstract search budget; elapsed time describes this run. No model calls are made, and local CPU/energy cost is unmeasured. Synthetic or imported-file checks are not benchmark certification or permission for companion growth.")
            }
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled).padding(.top, 8)
        }.accessibilityIdentifier("capabilities.solver.how-it-works")
    }

    private func traceContent(_ run: ARCSolverRun) -> some View {
        DisclosureGroup("Search trace (\(run.trace.count) retained entries)") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Each entry describes a rule attempted against training pairs. A fit is evidence about training; test correctness comes from the separate checker.")
                    .foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(run.trace.prefix(200).enumerated()), id: \.offset) { index, entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(index + 1). \(entry.programID)").font(.system(.caption, design: .monospaced))
                                Text("\(traceStatus(entry.status)) · \(entry.trainingExamplesChecked) training pairs checked")
                                    .foregroundStyle(.secondary)
                                Text("Example order: " + entry.checkedTrainingIndices.map { String($0 + 1) }.joined(separator: " → "))
                                    .foregroundStyle(.secondary)
                                if (entry.status == .trainingMismatch || entry.status == .trainingUndefined), let failed = entry.checkedTrainingIndices.last {
                                    Text("Counterexample: training pair \(failed + 1)").foregroundStyle(.orange)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }.frame(maxHeight: 200)
                if run.trace.count > 200 { Text("Showing the first 200 entries; the complete retained trace stays with the evidence.").foregroundStyle(.secondary) }
                if run.traceTruncated { Text("The trace reached its retention limit. It is incomplete.").foregroundStyle(.orange) }
            }
            .font(.caption).textSelection(.enabled).padding(.top, 6)
        }.accessibilityIdentifier("capabilities.solver.trace")
    }

    private func gridPair(left: ARCGrid, leftTitle: String, right: ARCGrid, rightTitle: String, identifier: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ARCNativeGrid(grid: left, title: leftTitle, identifier: "\(identifier).input")
                ARCNativeGrid(grid: right, title: rightTitle, identifier: "\(identifier).output")
            }
            VStack(alignment: .leading, spacing: 12) {
                ARCNativeGrid(grid: left, title: leftTitle, identifier: "\(identifier).input")
                ARCNativeGrid(grid: right, title: rightTitle, identifier: "\(identifier).output")
            }
        }
    }

    static func outcomeTitle(_ outcome: ARCSolverRun.Outcome) -> String {
        switch outcome {
        case .predicted: "Training consensus · Predictions proposed"
        case .ambiguous: "Abstained · Ambiguous rules"
        case .noMatch: "Abstained · No matching rule"
        case .budgetExhausted: "Abstained · Search limit reached"
        }
    }

    private func outcomeExplanation(_ outcome: ARCSolverRun.Outcome) -> String {
        switch outcome {
        case .predicted: "All rules fitting the training pairs agree on the test grids. Agreement is not a correctness claim."
        case .ambiguous: "Fitting rules disagree or a fitting rule cannot produce a test grid. No prediction is offered."
        case .noMatch: "No rule in this limited search fits every training pair. No prediction is offered."
        case .budgetExhausted: "The bounded search did not finish. A partial search cannot establish consensus, so no prediction is offered."
        }
    }

    private func traceStatus(_ status: ARCSolverTraceEntry.Status) -> String {
        switch status {
        case .trainingMismatch: "Training mismatch"
        case .trainingUndefined: "Rule undefined on training input"
        case .redundantPalette: "Redundant color mapping skipped"
        case .matched: "Training fit; test prediction defined"
        case .predictionUndefined: "Training fit; test prediction undefined"
        case .budgetExhausted: "Search limit reached"
        }
    }

    private func importTask() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.title = "Import ARC task"
        panel.prompt = "Load task"
        panel.message = "Choose one standard ARC JSON task (up to 2 MiB) with 1–20 examples in each of the train and test arrays. Training examples require input and output; test examples require input and may include output. Grids must be rectangular, 1–30 cells per side, with integer colors 0–9. Extra fields are rejected."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        do {
            try store.loadSolverTask(fileURL: url)
            importError = nil
        } catch { importError = error.localizedDescription }
    }
}
