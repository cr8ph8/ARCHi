import SwiftUI

/// A read projection of the existing task owners, not a new execution service.
/// Merely visiting this page never runs a puzzle, model or environment action.
@MainActor
struct ReasoningWorkspace: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject var session: ARC3SessionStore

    var body: some View {
        if store.showsReasoningTools {
            VStack(alignment: .leading, spacing: 0) {
                Button("Back to everyday reasoning", systemImage: "arrow.left") {
                    store.showsReasoningTools = false
                }
                .buttonStyle(.plain).foregroundStyle(WorkspaceTheme.accent)
                .padding(.horizontal, 24).padding(.top, 18)
                .accessibilityIdentifier("reasoning.back")
                ARCCapabilitiesWorkspace(store: store.arcCapabilities, onEvaluation: store.recordARCEvaluation,
                    onOpenUsage: { _ = store.openARCUsage(taskID: $0) },
                    onOpenGraph: { _ = store.openARCGraph(evidenceID: $0) }, qwenModel: store.qwenModel,
                    interactive: AnyView(ARC3Workspace(owner: store, session: session)),
                    prefersInteractive: store.reasoningToolsShowWorlds,
                    gridStartUnavailableReason: store.arcGridStartUnavailableReason)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Work it through together")
                            .font(.system(size: 28, weight: .medium, design: .rounded))
                        Text("Understand the context. Consider a next step. Review what changed.")
                            .foregroundStyle(WorkspaceTheme.muted)
                    }
                    currentWork
                    if store.activeARCAnswer != nil { ARCActiveAssistantReply(store: store) }
                    if session.observation != nil || session.isWorking || session.error != nil {
                        ARC3AssistantReply(store: store, session: session)
                    }
                    WorkspaceRouteRow(title: "Talk it through", detail: "Continue in Ask ARCHi with your question and the context you've shared.",
                        icon: "bubble.left.and.bubble.right", identifier: "reasoning.chat") { store.open(.assistant) }
                    WorkspaceRouteRow(title: "Explore a connected environment",
                        detail: "Choose a local environment, observe it together, and review bounded actions.",
                        icon: "viewfinder", identifier: "reasoning.worlds") { store.openReasoningTools(worlds: true) }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What carries forward").font(.headline)
                        Text("In document work, your reviewed outcomes help choose the next approach. In connected environments, observed changes guide the next action. You choose what to apply and what to remember.")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack(spacing: 16) {
                            Button("Memories") { store.open(.memory) }
                            Button("Activity map") { store.open(.nodeLab) }
                        }.buttonStyle(.borderless)
                    }.padding(18).modifier(WorkspaceSurface())
                    DisclosureGroup("Advanced reasoning tools") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Inspect grid rules, supplied answers, saved receipts, and runtime controls. Opening these tools runs nothing.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Open grid tools and saved results", systemImage: "slider.horizontal.3") {
                                store.openReasoningTools()
                            }.accessibilityIdentifier("reasoning.tools")
                            Button("Open ARCHi Trials in Arena", systemImage: "gamecontroller") { store.openArena(.arc) }
                                .accessibilityIdentifier("reasoning.arena-arc")
                            Text("ARCHi Trials hosts the same grid and interactive world tools. Unity companion practice uses its own controls; world actions stay inside the selected environment.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.top, 10)
                    }.accessibilityIdentifier("reasoning.advanced")
                    Text("ARCHi · ARC Hampton Interphase")
                        .font(.caption).foregroundStyle(WorkspaceTheme.muted)
                }.padding(24).frame(maxWidth: 960, alignment: .leading).frame(maxWidth: .infinity)
            }.accessibilityIdentifier("reasoning.workspace")
        }
    }

    private var currentWork: some View {
        let decision = store.documentQ2EDecision
        return VStack(alignment: .leading, spacing: 12) {
            Label("What we're working with", systemImage: "doc.text.magnifyingglass").font(.headline)
            if let source = store.sourceName {
                Text(source).font(.callout.weight(.medium)).lineLimit(2).textSelection(.enabled)
                Text(store.textSelection == nil
                     ? "Your shared copy is available. Select a passage in Work together when you want a revision."
                     : "A passage is selected. ARCHi can prepare a revision for you to review.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Share a document or bring a question to Ask ARCHi. Your current context stays under your control.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if decision.lane != .stop {
                Text(approach(decision.lane)).font(.callout)
                Button("Prepare a revision", systemImage: "pencil") {
                    store.prepareAdaptiveDocumentWork()
                    store.open(.context)
                }
                .buttonStyle(WorkspaceActionStyle(prominent: true))
                .disabled(store.isWorking || store.isShuttingDown || store.voiceInput.isActive)
                .help("Prepares the current passage and approach. You still choose Send and review before Apply.")
                .accessibilityIdentifier("reasoning.prepare")
                Text("Preparation sends nothing. You'll review the request before sending.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button(store.sourceName == nil ? "Work with a document" : "Return to your document", systemImage: "arrow.right") {
                store.open(.context)
            }.buttonStyle(.borderless).accessibilityIdentifier("reasoning.document")
        }.padding(18).modifier(WorkspaceSurface(emphasis: true))
    }

    private func approach(_ lane: HamptonQ2ELane) -> String {
        switch lane {
        case .retain: "Next, we can reuse an existing approach while keeping this passage's requirements."
        case .expand: "Next, we can consider another approach to this passage."
        case .repair: "Next, we can revisit the approach in light of your corrections."
        case .stop: "Choose a current passage before preparing a revision."
        }
    }
}
