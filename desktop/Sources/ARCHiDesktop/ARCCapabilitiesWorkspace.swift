import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
struct ARCCapabilitiesWorkspace: View {
    @ObservedObject var store: ARCCapabilitiesStore
    var onEvaluation: @MainActor (ARCCapabilitiesEvent) -> Void = { _ in }
    var onOpenUsage: ((String) -> Void)?
    var onOpenGraph: ((String) -> Void)?
    var qwenModel: String = QwenAssistant.defaultModel
    var interactive: AnyView? = nil
    var prefersInteractive = false
    var presentation: Presentation = .reasoning
    enum Presentation { case reasoning, arena }
    var gridStartUnavailableReason: String? = nil
    @State private var importError: String?
    @State private var page: Page = .solve
    private enum Page { case solve, interactive, results }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heading
                    HStack(spacing: 8) {
                        pageButton(presentation == .arena ? "Pattern Trials" : "Grid tools", page: .solve, identifier: "capabilities.page.solve")
                        if interactive != nil { pageButton(presentation == .arena ? "World Trials" : "Local environments", page: .interactive, identifier: "capabilities.page.arc3") }
                        pageButton("\(presentation == .arena ? "Trial records" : "Saved results") · \(store.records.count)", page: .results, identifier: "capabilities.page.results")
                        Spacer(minLength: 0)
                    }
                    if let error = importError ?? store.lastError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange).textSelection(.enabled)
                            .accessibilityIdentifier("capabilities.error")
                    }
                    if let notice = store.selectionNotice {
                        Label(notice, systemImage: "link.badge.plus")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("capabilities.selection-notice")
                    }
                    if page == .solve {
                        if let reason = gridStartUnavailableReason {
                            Text(reason).font(.callout).foregroundStyle(.secondary)
                                .accessibilityIdentifier("capabilities.grid-unavailable")
                            if interactive != nil {
                                Button("Return to World Trials") { page = .interactive }
                                    .accessibilityIdentifier("capabilities.return-arc3")
                            }
                        }
                        ARCSolverPanel(store: store, onEvaluation: onEvaluation,
                            onOpenUsage: onOpenUsage, onOpenGraph: onOpenGraph,
                            onShowQwen: { reader.scrollTo("arc-qwen-panel", anchor: .top) },
                            startUnavailableReason: gridStartUnavailableReason, isArenaTrial: presentation == .arena)
                            .id("arc-solver-panel")
                        ARCQwenProposalPanel(store: store, model: qwenModel, onEvaluation: onEvaluation,
                            onOpenUsage: onOpenUsage, onOpenGraph: onOpenGraph,
                            startUnavailableReason: gridStartUnavailableReason)
                            .id("arc-qwen-panel")
                    } else if page == .interactive {
                        interactive
                    } else {
                        if store.records.isEmpty {
                            ContentUnavailableView("Your results will appear here", systemImage: "square.grid.3x3",
                                description: Text("Solve a puzzle or import an evaluation to keep its evidence on this Mac."))
                        }
                        ForEach(store.records) { record in recordCard(record).id(record.id) }
                    }
                    if page != .interactive { evaluationImport }
                }.padding(24).frame(maxWidth: 1000, alignment: .leading).frame(maxWidth: .infinity)
            }.accessibilityIdentifier("capabilities.workspace")
                .onAppear {
                    if prefersInteractive { page = .interactive }
                    else if store.isSolving || store.isProposing { page = .solve }
                    else if let id = store.selectedRecordID {
                        page = .results
                        DispatchQueue.main.async {
                            if page == .results && store.selectedRecordID == id { reader.scrollTo(id, anchor: .top) }
                        }
                    }
                }
                .onChange(of: prefersInteractive) { _, value in if value { page = .interactive } }
                .onChange(of: store.selectedRecordID) { _, id in
                    if let id, !store.isSolving, !store.isProposing {
                        page = .results
                        DispatchQueue.main.async {
                            if page == .results && store.selectedRecordID == id { reader.scrollTo(id, anchor: .top) }
                        }
                    }
                }
                .onChange(of: store.isProposing) { _, proposing in
                    if proposing { page = .solve; store.clearRecordSelection() }
                }
                .onChange(of: store.isSolving) { _, isSolving in
                    if isSolving {
                        page = .solve
                        store.clearRecordSelection()
                        DispatchQueue.main.async {
                            if page == .solve { reader.scrollTo("arc-solver-panel", anchor: .top) }
                        }
                    }
                }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(presentation == .arena ? "ARCHi Trials" : "Reasoning tools").font(.system(size: 28, weight: .medium, design: .rounded))
            Text(presentation == .arena ? "Find a pattern. Try an action. See what holds up."
                 : "Inspect the examples, environment controls, and evidence behind a task.")
                .foregroundStyle(WorkspaceTheme.muted)
            Text(presentation == .arena
                 ? "Discover patterns and explore unfamiliar worlds with ARCHi. Choose a trial below; nothing starts until you ask."
                 : "Everyday work stays in Chat and Work together. These controls are available when you want to inspect or run a specific grid or environment task.")
                .font(.callout).foregroundStyle(.secondary)
            if presentation == .arena {
                DisclosureGroup("Sources & trial records") {
                    Text("ARCHi’s trial experience uses ARC-format grid tasks and installed ARC3 environments. Original source names, versions and evidence remain in the records. Local trial results are not official ARC Prize scores. Pattern solving and World Trial exploration use no model tokens; Qwen is a separate choice.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                }.font(.caption).accessibilityIdentifier("arena.arc.scope")
            }
            Label("Local rule search · Optional Qwen proposals", systemImage: "desktopcomputer")
                .font(.caption).foregroundStyle(WorkspaceTheme.accent)
                .accessibilityIdentifier("capabilities.local-status")
        }
    }

    private func pageButton(_ title: String, page destination: Page, identifier: String) -> some View {
        Button {
            if destination == .solve { store.clearRecordSelection() }
            page = destination
        } label: {
            Text(title).font(.system(size: 12, weight: .medium))
                .foregroundStyle(page == destination ? WorkspaceTheme.background : Color.primary)
                .padding(.horizontal, 15).padding(.vertical, 10)
                .background(page == destination ? WorkspaceTheme.accent : WorkspaceTheme.panel,
                            in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(WorkspaceTheme.line))
        }
            .buttonStyle(.plain)
            .accessibilityAddTraits(page == destination ? .isSelected : [])
            .accessibilityIdentifier(identifier)
    }

    private var evaluationImport: some View {
        DisclosureGroup("More ways to review evidence") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Have predictions from another solver? Import a portable evaluation. ARCHi checks all answers, including missing or invalid ones.")
                    .foregroundStyle(WorkspaceTheme.muted)
                ViewThatFits(in: .horizontal) {
                    HStack { importButton; demonstrationButton }
                    VStack(alignment: .leading) { importButton; demonstrationButton }
                }
                Text("The demonstration checks two fixed sample predictions, one correct and one incorrect. It does not run the solver or establish a benchmark score.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 12)
        }.padding(16).modifier(WorkspaceSurface())
            .accessibilityIdentifier("capabilities.more-evidence")
    }

    private var importButton: some View {
        Button("Import evaluation…", systemImage: "square.and.arrow.down", action: importBundle)
            .buttonStyle(WorkspaceActionStyle())
            .accessibilityIdentifier("capabilities.import")
    }

    private var demonstrationButton: some View {
        Button("Check a demonstration") {
            importError = nil
            onEvaluation(store.runSyntheticDemonstration())
            page = .results
        }.buttonStyle(WorkspaceActionStyle())
            .accessibilityIdentifier("capabilities.synthetic-demo")
    }

    private func recordCard(_ record: ARCCapabilitiesRecord) -> some View {
        let summary = record.summary
        let counts = summary.counts
        return VStack(alignment: .leading, spacing: 12) {
            if store.selectedRecordID == record.id {
                Label("Selected evidence", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.caption).foregroundStyle(WorkspaceTheme.accent)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Selected ARC receipt")
                    .accessibilityIdentifier("capabilities.selected-record")
            }
            HStack {
                Text(summary.sourceLabel).font(.headline)
                Spacer()
                Text("Proposed · Not certified").font(.caption).foregroundStyle(.secondary)
            }
            Text(recordSource(record))
                .font(.caption).foregroundStyle(.secondary)
            Text("\(counts.exact) of \(counts.totalExamples) examples exact · \(counts.exactTasks) of \(counts.totalTasks) tasks exact")
                .font(.title3).accessibilityIdentifier("capabilities.result")
            Text("Incorrect \(counts.incorrect) · Missing \(counts.missing) · Invalid \(counts.invalid) · Unscored \(counts.unscored)")
                .font(.callout)
            Text("Solver: \(summary.solverID) · \(record.recordedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
            if let evidence = record.solverEvidence {
                Text("Local search: \(ARCSolverPanel.outcomeTitle(evidence.run.outcome)) · \(evidence.run.matchingPrograms) training fits · \(evidence.elapsedMilliseconds) ms")
                    .font(.callout)
                Button("Run again", systemImage: "arrow.clockwise") {
                    page = .solve
                    store.clearRecordSelection()
                    guard gridStartUnavailableReason == nil else { return }
                    store.replaySolver(recordID: record.id, onEvaluation: onEvaluation)
                }
                .buttonStyle(WorkspaceActionStyle())
                .disabled(store.isSolving || store.isProposing || gridStartUnavailableReason != nil)
                .help("Repeat this retained task with the local solver and compare its trace.")
                .accessibilityIdentifier("capabilities.solver.replay.\(record.id)")
                Text("Exact counts above come from the independent checker. A training fit or matching replay does not establish a correct test answer.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                if let onOpenUsage {
                    Button("Usage", systemImage: "chart.bar") { onOpenUsage(record.taskID) }
                        .accessibilityIdentifier("capabilities.record.usage.\(record.id)")
                }
                if let onOpenGraph {
                    Button("Activity map", systemImage: "point.3.connected.trianglepath.dotted") { onOpenGraph(record.id) }
                        .accessibilityIdentifier("capabilities.record.graph.\(record.id)")
                }
            }.buttonStyle(.plain).font(.callout).foregroundStyle(WorkspaceTheme.accent)
            DisclosureGroup("Evidence details") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Manifest: \(summary.manifestID)")
                    Text("Manifest hash: \(summary.manifestHash)")
                    Text("Bundle hash: \(record.bundleHash)")
                    Text("Application task: \(record.taskID)")
                    Text("Proposal: \(summary.proposalHash)")
                    Text("Receipt coverage: \(summary.receiptCoverageComplete ? "complete" : "incomplete") · Scored coverage: \(summary.scoredCoverageComplete ? "complete" : "incomplete")")
                    ForEach(summary.receiptHashes, id: \.self) { hash in Text("Checker receipt: \(hash)") }
                    Text("Hashes check content integrity. They do not authenticate the source or certify capability. No Journey, memory, permission, action or XP changes are granted.")
                }.font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(16).modifier(WorkspaceSurface())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("capabilities.record.\(record.id)")
    }

    private func recordSource(_ record: ARCCapabilitiesRecord) -> String {
        let source = record.summary.sourceStatus == "synthetic-fixture" ? "Synthetic sample" : "Imported task · Source unverified"
        return record.solverEvidence == nil
            ? (record.summary.sourceStatus == "synthetic-fixture" ? "Synthetic fixture · Rescored locally" : "Unverified offline snapshot · Solver provenance unattested")
            : "\(source) · Generated by the local solver · Checked independently"
    }

    private func importBundle() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an archi-arc-evaluation-bundle/v1 JSON file (up to 2 MiB)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        do {
            importError = nil
            onEvaluation(try store.evaluate(fileURL: url))
            page = .results
        } catch { importError = error.localizedDescription }
    }
}
