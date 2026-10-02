import SwiftUI

@MainActor
extension CompanionStore {
    /// A current projection of existing owners. Reading the graph never dispatches,
    /// saves, moves the companion or reconstructs withdrawn historical text.
    func companionGraphSnapshot(at now: Date = Date()) -> CompanionGraphSnapshot {
        let base = CompanionGraph.build(
            receipts: compareResults.values.compactMap(\.receipt),
            lessons: keptLessons,
            source: sourceName.map { CompanionGraphSource(name: $0, text: sharedText, revision: sourceRevision) },
            now: now, records: hamptonSnapshot.records, turn: hamptonSnapshot.turn,
            arcRecords: arcCapabilities.records, arcError: arcCapabilities.lastError,
            accountingTasks: tokenSteward.tasks, accountingError: tokenSteward.loadError)
        let recordedSummary = lastARC3Summary.flatMap { summary in
            tokenSteward.loadError == nil && tokenSteward.tasks.contains {
                $0.id == summary.sessionID && $0.route == "arc-interactive" && $0.startedAt == summary.startedAt
            } ? summary : nil
        }
        let knowledge = KnowledgePageGraph.append(to: base, library: readingSources)
        let interactive = ARC3Graph.append(to: knowledge, observation: arc3.observation, transitions: arc3.transitions, summary: recordedSummary)
        let work = DocumentWorkGraph.append(to: interactive, records: documentWork.records,
            accountingTaskIDs: tokenSteward.loadError == nil ? Set(tokenSteward.tasks.map(\.id)) : [], lessons: keptLessons)
        return DocumentMethodGraph.append(to: work, store: self)
    }

    func openGraphTarget(_ target: CompanionGraphTarget) {
        switch target {
        case .assistant: open(.assistant)
        case .context: open(.context)
        case .memory: open(.memory)
        case .knowledgePage(let id):
            selectedKnowledgePageID = id
            open(.memory)
        case .documentMethod(let binding):
            inspectedDocumentMethod = .init(binding: binding,
                methodOwner: ObjectIdentifier(documentProcedures), historyOwner: ObjectIdentifier(documentWork),
                sourceOwner: ObjectIdentifier(readingSources))
            open(.nodeLab)
        case .advanced: open(.advanced)
        case .capabilities: open(.capabilities)
        case .steward: open(.steward)
        case .interactiveARC: runARC3(.open)
        case .stewardTask(let taskID): openDocumentUsage(taskID: taskID)
        case .arcEvidence(let proposalHash):
            arcCapabilities.selectRecord(id: proposalHash)
            openReasoningTools()
        }
    }
}

@MainActor
struct CompanionGraphWorkspace: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject private var library: ReadingSourceLibrary
    let initialShowcase: Bool
    @State private var includesActivity = false

    init(store: CompanionStore, initialShowcase: Bool = false) {
        self.store = store
        library = store.readingSources
        self.initialShowcase = initialShowcase
        // A receipt opened from an existing activity route stays reachable.
        let memory = store.memoryMapSnapshot()
        _includesActivity = State(initialValue: !initialShowcase && store.selectedGraphNodeID.map { selected in
            !memory.nodes.contains { $0.id == selected }
        } == true)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Map scope", selection: $includesActivity) {
                    Text("Memory").tag(false)
                    Text("All activity").tag(true)
                }.pickerStyle(.segmented).frame(width: 226)
                    .accessibilityIdentifier("memory-map.scope")
                Text(includesActivity ? "Includes requests, outcomes, and usage." : "Sources, pages, lessons, and saved methods.")
                    .font(.system(size: 11)).foregroundStyle(WorkspaceTheme.muted)
                Spacer(minLength: 0)
                Button("Manage memories", systemImage: "bookmark") { store.open(.memory) }
                    .buttonStyle(.borderless).font(.system(size: 11))
                    .accessibilityIdentifier("memory-map.manage")
            }.padding(.horizontal, 20).padding(.top, 14)
            // Refresh expiry without running a model or writing any record.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let snapshot = includesActivity ? store.companionGraphSnapshot(at: context.date)
                    : store.memoryMapSnapshot(at: context.date)
                CompanionGraphView(snapshot: snapshot,
                    onOpen: store.openGraphTarget, initialSelectionID: initialShowcase ? nil : store.selectedGraphNodeID,
                    reduceMotion: store.preferences.reduceMotion || store.preferences.quiet,
                    seedColor: store.preferences.seedColor, initialShowcase: initialShowcase)
                    .id(store.selectedGraphNodeID)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("node-lab.workspace")
        .sheet(item: $store.inspectedDocumentMethod) { selection in
            DocumentMethodInspectionView(store: store, selection: selection)
        }
        .onChange(of: ObjectIdentifier(store.documentProcedures)) { _, _ in store.inspectedDocumentMethod = nil }
        .onChange(of: ObjectIdentifier(store.documentWork)) { _, _ in store.inspectedDocumentMethod = nil }
        .onChange(of: ObjectIdentifier(store.readingSources)) { _, _ in store.inspectedDocumentMethod = nil }
        .onChange(of: store.section) { _, section in
            if section != .nodeLab { store.inspectedDocumentMethod = nil }
        }
    }
}
