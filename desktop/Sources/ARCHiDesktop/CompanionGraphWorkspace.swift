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
    @State private var showsAssistant = false
    @State private var attachmentMessage: String?
    @State private var methodAuthoring: KnowledgeMapMethodSelection?
    @State private var showsWork = false
    @State private var imageRegionContext: PastedDocumentImportContext?

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
                Spacer(minLength: 0)
                Button("Image region…", systemImage: "photo.badge.magnifyingglass") {
                    imageRegionContext = store.beginPastedDocumentImport()
                }.buttonStyle(.borderless).font(.system(size: 11))
                    .disabled(!store.canBeginPastedDocumentImport)
                    .accessibilityIdentifier("memory-map.image-region")
                Button("Work", systemImage: "arrow.triangle.branch") { showsWork.toggle() }
                    .buttonStyle(.borderless).font(.system(size: 11))
                    .accessibilityIdentifier("memory-map.work")
                    .popover(isPresented: $showsWork) {
                        MemoryMapWorkView(store: store) { showsWork = false }
                    }
                Button("Manage memories", systemImage: "bookmark") { store.open(.memory) }
                    .buttonStyle(.borderless).font(.system(size: 11))
                    .accessibilityIdentifier("memory-map.manage")
                Button(showsAssistant ? "Close Ask ARCHi" : "Ask ARCHi", systemImage: "bubble.left.and.bubble.right") {
                    showsAssistant.toggle()
                }
                .buttonStyle(.bordered).controlSize(.small)
                .accessibilityIdentifier("memory-map.ask-toggle")
                .help("Use the same question draft, model route and replies alongside the map. Selecting a node does not attach it.")
            }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
            if let attachmentMessage {
                HStack {
                    Label(attachmentMessage, systemImage: "info.circle").font(.caption)
                    Spacer()
                    Button { self.attachmentMessage = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).accessibilityLabel("Dismiss memory context notice")
                }.padding(.horizontal, 16).padding(.vertical, 8)
                    .accessibilityIdentifier("memory-map.context-notice")
            }
            HSplitView {
                // Keep this host mounted while Ask opens or closes, preserving
                // map selection, filters and focus. The store owns all requests.
                TimelineView(.periodic(from: .now, by: 2)) { context in
                    let particleScene = includesActivity ? nil : store.companionParticleScene(at: context.date)
                    let snapshot = particleScene?.graph ?? (includesActivity ? store.companionGraphSnapshot(at: context.date)
                        : store.memoryMapSnapshot(at: context.date))
                    CompanionGraphView(snapshot: snapshot,
                        onOpen: store.openGraphTarget, initialLayout: .particles,
                        initialSelectionID: initialShowcase ? nil : store.selectedGraphNodeID,
                        reduceMotion: store.preferences.reduceMotion || store.preferences.quiet,
                        seedColor: store.preferences.seedColor, initialShowcase: initialShowcase,
                        onAsk: { node in
                            guard let page = currentPage(for: node) else {
                                attachmentMessage = "This page changed. Select its current reviewed version before attaching it."
                                return
                            }
                            guard store.useKnowledgePageInChat(page, openAssistant: false) else {
                                attachmentMessage = store.knowledgePageMessage ?? "This page could not be attached. Review its source and status."
                                return
                            }
                            attachmentMessage = nil
                            showsAssistant = true
                        }, canAsk: { currentPage(for: $0) != nil },
                        lightExpression: store.kinLightExpression,
                        preparedNodeIDs: store.currentKnowledgeContext == nil ? []
                            : Set(store.selectedKnowledgePages.map { KnowledgePageGraph.nodeID($0) }),
                        onCreateMethod: { node in
                            guard let selection = store.beginKnowledgeMapMethod(node: node) else {
                                attachmentMessage = "This concept changed. Select its current reviewed version before creating a method."
                                return
                            }
                            methodAuthoring = selection
                        }, canCreateMethod: { store.beginKnowledgeMapMethod(node: $0) != nil },
                        particleScene: particleScene,
                        seedAppearance: particleScene == nil ? nil : CompanionParticleAppearance(store: store),
                        liminalGraphSource: particleScene.flatMap { scene in
                            guard let asset = LiminalV008Runtime.asset,
                                  let presentation = store.liminalKnowledgePresentation(asset: asset, at: context.date, forMemoryMap: true),
                                  presentation.sidecar.originDigest == scene.originDigest else { return nil }
                            return LiminalGraphMorphSource(asset: asset, bindings: presentation.sidecar,
                                fullGraph: store.companionGraphSnapshot(at: context.date), originDigest: scene.originDigest)
                        },
                        selectionID: store.selectedGraphNodeID,
                        onSelectionChange: { id in
                            store.selectGraphRecord(id, in: snapshot, particleScene: particleScene)
                        })
                        .id(ObjectIdentifier(store.readingSources))
                }
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                if showsAssistant {
                    VStack(spacing: 0) {
                        HStack {
                            Text(AskARCHiBrand.title).font(.system(size: 15, weight: .medium))
                            Spacer()
                            Button { showsAssistant = false } label: { Image(systemName: "xmark") }
                                .buttonStyle(.borderless).accessibilityLabel("Close Ask ARCHi pane")
                        }.padding(14)
                        Divider()
                        AssistantWorkspace(store: store, compact: true)
                    }
                    .frame(minWidth: 330, idealWidth: 390, maxWidth: 460, maxHeight: .infinity)
                    .accessibilityIdentifier("memory-map.assistant-pane")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("node-lab.workspace")
        .sheet(item: $store.inspectedDocumentMethod) { selection in
            DocumentMethodInspectionView(store: store, selection: selection)
        }
        .sheet(item: $imageRegionContext) { ImageRegionImportSheet(store: store, context: $0) }
        .sheet(item: $methodAuthoring) { selection in
            KnowledgeMapMethodSheet(store: store, selection: selection) { saved in
                methodAuthoring = nil
                if let saved {
                    includesActivity = false
                    if store.openDocumentMethodMap(saved) {
                        attachmentMessage = "Candidate saved. Inspect this method version to choose a passage. No work has been sent or reviewed."
                    }
                }
            }
        }
        .onChange(of: store.selectedGraphNodeID) { _, id in
            guard let id, !includesActivity else { return }
            let memory = store.memoryMapSnapshot()
            if !memory.nodes.contains(where: { $0.id == id }),
               store.companionGraphSnapshot().nodes.contains(where: { $0.id == id }) {
                includesActivity = true
            }
        }
        .onChange(of: ObjectIdentifier(store.documentProcedures)) { _, _ in
            store.inspectedDocumentMethod = nil; methodAuthoring = nil; showsWork = false
        }
        .onChange(of: ObjectIdentifier(store.documentWork)) { _, _ in
            store.inspectedDocumentMethod = nil; methodAuthoring = nil; showsWork = false
        }
        .onChange(of: ObjectIdentifier(store.readingSources)) { _, _ in
            store.inspectedDocumentMethod = nil; attachmentMessage = nil; methodAuthoring = nil; showsWork = false
        }
        .onChange(of: store.section) { _, section in
            if section != .nodeLab { store.inspectedDocumentMethod = nil; methodAuthoring = nil; showsWork = false }
        }
    }

    /// Re-resolve the exact displayed version at interaction time. A newer page
    /// with the same logical ID must not silently replace the selected node.
    private func currentPage(for node: CompanionGraphNode) -> KnowledgePage? {
        guard case .knowledgePage(let id) = node.target,
              let page = store.readingSources.latestKnowledgePages.first(where: {
                  $0.id == id && KnowledgePageGraph.nodeID($0.binding) == node.id
              }), store.readingSources.availability(of: page) == nil else { return nil }
        return page
    }

}
