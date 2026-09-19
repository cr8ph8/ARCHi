import SwiftUI

@MainActor
struct WorkspaceView: View {
    @ObservedObject var store: CompanionStore
    let playHost: HostedPlayHost
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var showsRetention = false
    @State private var showsSidebar = true
    @State private var showsMoreTools = false

    /// The native window owns its chosen size and minimum. Reply length must
    /// not publish a new intrinsic or minimum size back into that window.
    static func makeHostingView(store: CompanionStore, playHost: HostedPlayHost) -> NSHostingView<WorkspaceView> {
        let hosting = NSHostingView(rootView: WorkspaceView(store: store, playHost: playHost))
        hosting.sizingOptions = []
        return hosting
    }

    static func applyWindowMinimum(to window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        window.contentMinSize = NSSize(width: 880, height: 640)
    }

    var body: some View {
        HSplitView {
            if showsSidebar {
                sidebar
                    .frame(minWidth: 205, idealWidth: 220, maxWidth: 250)
                    .frame(maxHeight: .infinity)
            }
            VStack(spacing: 0) {
                workspaceHeader
                Divider().opacity(0.6)
                ARCActiveWorkBar(store: store)
                if let notice = store.workspaceRoutingNotice {
                    HStack(alignment: .top, spacing: 10) {
                        Label(notice, systemImage: "info.circle")
                            .font(.callout).foregroundStyle(WorkspaceTheme.muted)
                        Spacer(minLength: 0)
                        Button { store.dismissWorkspaceRoutingNotice() } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).accessibilityLabel("Dismiss navigation notice")
                    }.padding(14).background(WorkspaceTheme.panel)
                        .accessibilityIdentifier("workspace.routing-notice")
                }
                if store.section == .home {
                    HomeWorkspace(store: store)
                } else if store.section == .context {
                    WorkTogetherWorkspace(store: store)
                } else if store.section == .assistant {
                    AssistantWorkspace(store: store)
                } else if store.section == .marketplace {
                    MarketplaceWorkspace(store: store)
                } else if store.section == .unity {
                    UnityWorkspace(store: store)
                } else if store.section == .nodeLab {
                    CompanionGraphWorkspace(store: store)
                } else if store.section == .steward {
                    TokenStewardWorkspace(store: store.tokenSteward, notice: store.stewardMessage, onRetry: store.retryStewardAccounting,
                        selectedTaskID: store.selectedStewardTaskID,
                        onOpenEvidence: { _ = store.openARCEvidenceForUsage(taskID: $0) },
                        canOpenEvidence: store.canOpenARCEvidenceForUsage)
                } else if store.section == .capabilities {
                    ARCCapabilitiesWorkspace(store: store.arcCapabilities, onEvaluation: store.recordARCEvaluation,
                        onOpenUsage: { _ = store.openARCUsage(taskID: $0) },
                        onOpenGraph: { _ = store.openARCGraph(evidenceID: $0) }, qwenModel: store.qwenModel,
                        interactive: AnyView(ARC3Workspace(owner: store, session: store.arc3)),
                        prefersInteractive: store.showsARC3Reply)
                } else if store.section == .play && store.allowsPlay {
                    PlayWorkspace(store: store, host: playHost)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if !WorkspaceNavigation.tabs(for: store.section).isEmpty {
                                WorkspaceSectionTabs(store: store)
                            }
                            sectionHeading
                            sectionContent
                        }
                        .frame(maxWidth: 980, alignment: .leading)
                        .padding(32)
                        .frame(maxWidth: .infinity)
                    }
                }
                Divider().opacity(0.5)
                statusBar
            }
            .background(WorkspaceTheme.background)
        }
        .preferredColorScheme(store.preferences.workspaceAppearance.colorScheme)
        .tint(WorkspaceTheme.accent)
        // The native window owns the 880 × 640 content minimum.
        .frame(minWidth: 880)
        .sheet(isPresented: $showsRetention) {
            DesktopRetentionSummary(store: store) { showsRetention = false }
        }
        .onChange(of: store.section, initial: true) { _, section in
            if WorkspaceNavigation.tools.contains(section) { showsMoreTools = true }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                ARCHiWordmark()
                Text("Your desktop companion")
                    .font(.system(size: 9))
                    .foregroundStyle(WorkspaceTheme.muted)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 22)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    navigationGroup("EVERYDAY", sections: WorkspaceNavigation.work)
                    navigationGroup("YOUR COMPANION", sections: WorkspaceNavigation.companion)
                    navigationGroup("PLAY & CREATE", sections: WorkspaceNavigation.explore)
                    DisclosureGroup(isExpanded: $showsMoreTools) {
                        VStack(spacing: 4) {
                            ForEach(WorkspaceNavigation.tools) { section in sidebarRow(section) }
                        }.padding(.top, 8)
                    } label: {
                        Label("More tools", systemImage: "ellipsis.circle")
                            .font(.system(size: 12)).foregroundStyle(WorkspaceTheme.muted)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("workspace.more-tools")
                    .padding(.horizontal, 12)
                }.padding(.horizontal, 12).padding(.bottom, 16)
            }
            .scrollIndicators(.automatic)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 12) {
                Rectangle().fill(WorkspaceTheme.line).frame(height: 1)
                sidebarRow(.connections)
            }.padding(.horizontal, 22).padding(.bottom, 19).padding(.top, 5)
        }
        .background(WorkspaceTheme.sidebar)
    }

    private func navigationGroup(_ title: String, sections: [WorkspaceSection]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 9, weight: .medium)).tracking(1.4)
                .foregroundStyle(WorkspaceTheme.muted.opacity(0.75))
                .padding(.horizontal, 12).padding(.bottom, 7)
            ForEach(sections) { section in sidebarRow(section) }
        }
    }

    private func sidebarRow(_ section: WorkspaceSection) -> some View {
        let selected = WorkspaceNavigation.parent(of: store.section) == section
        let title = WorkspaceNavigation.title(for: section)
        return Button {
            // Native accessibility actions can arrive during a SwiftUI layout
            // callback. Navigate on the next event turn, after that update ends.
            DispatchQueue.main.async { store.open(section) }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: section == .connections ? "gearshape" : section.icon)
                    .font(.system(size: 14, weight: .light)).frame(width: 19)
                Text(title).font(.system(size: 13, weight: selected ? .medium : .regular))
                Spacer(minLength: 0)
                if selected { Circle().fill(WorkspaceTheme.accent).frame(width: 4, height: 4) }
            }
        }
        .buttonStyle(WorkspaceNavigationStyle(selected: selected,
            reduceMotion: systemReduceMotion || store.preferences.reduceMotion || store.preferences.quiet))
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(section == .home ? "workspace.nav.home" : "workspace.nav.\(section.id)")
    }

    private var workspaceHeader: some View {
        HStack(spacing: 14) {
            Button { showsSidebar.toggle() } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.plain).foregroundStyle(WorkspaceTheme.muted)
            .accessibilityLabel(showsSidebar ? "Hide navigation" : "Show navigation")
            .accessibilityIdentifier("workspace.toggle-navigation")
            HStack(spacing: 9) {
                Image(systemName: store.section.icon).foregroundStyle(WorkspaceTheme.accent)
                Text(workspaceTitle).fontWeight(.medium)
            }
            .font(.system(size: 12))
            .accessibilityLabel("ARCHi view: \(store.section.displayTitle(companionName: store.activeQiMon?.name ?? store.keptQiMon?.name))")
            Spacer()
            Button {
                store.isVisible ? store.hideCompanion() : store.showCompanion()
            } label: {
                Label(store.isVisible ? "Hide companion" : "Show companion", systemImage: store.isVisible ? "eye.slash" : "eye")
            }.buttonStyle(.borderless)
            Button("Back to desktop", systemImage: "arrow.up.right") {
                let workspace = NSApplication.shared.keyWindow
                playHost.setVisible(false)
                store.invalidateTextSelection(reason: "Workspace hidden; passage reference cleared.")
                store.showCompanion()
                workspace?.orderOut(nil)
            }.buttonStyle(.bordered)
        }
        .padding(.horizontal, 24).padding(.vertical, 15)
        .background(WorkspaceTheme.sidebar.opacity(0.55))
    }

    private var workspaceTitle: String {
        switch WorkspaceNavigation.parent(of: store.section) {
        case .appearance: "Companion · \(WorkspaceNavigation.tabTitle(store.section))"
        case .connections: "Settings · \(WorkspaceNavigation.tabTitle(store.section))"
        default: store.section.displayTitle(companionName: store.activeQiMon?.name ?? store.keptQiMon?.name)
        }
    }

    private var sectionHeading: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(store.section.eyebrow.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(WorkspaceTheme.accent)
            Text(store.hasPersonalQiMon && store.section == .appearance ? "Your QiMon"
                : store.hasPersonalQiMon && store.section == .evolution ? "Life with \(store.activeQiMon?.name ?? "your companion")" : store.section.heading)
                .font(.system(size: 30, weight: .medium, design: .rounded))
            Text(store.hasPersonalQiMon && store.section == .appearance ? "One companion, growing alongside you."
                : store.hasPersonalQiMon && store.section == .evolution ? "His beginning, your shared experiences, and what comes next." : store.section.subtitle)
                .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
        }
    }

    @ViewBuilder private var sectionContent: some View {
        switch store.section {
        case .home: EmptyView() // The overview owns its responsive scrolling.
        case .assistant: EmptyView() // The assistant keeps its composer below its reply scroll.
        case .marketplace: EmptyView()
        case .unity: EmptyView() // The Unity area observes the existing presentation owner.
        case .nodeLab: EmptyView() // The native graph owns its canvas and inspector scrolling.
        case .steward, .capabilities: EmptyView()
        case .play: EmptyView() // Hosted separately so the game owns its scrolling and focus.
        case .appearance: AppearanceWorkspace(store: store)
        case .evolution: EvolutionWorkspace(store: store, evolution: store.evolution)
        case .rhythm: RhythmWorkspace(store: store)
        case .memory: MemoryWorkspace(store: store)
        case .context: EmptyView() // The workbench owns its full-height document and review columns.
        case .connections: ConnectionsWorkspace(store: store)
        case .accessibility: AccessibilityWorkspace(store: store)
        case .advanced: AdvancedWorkspace(store: store)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 7) {
            Circle().fill(store.connectionState == .ready ? WorkspaceTheme.positive : WorkspaceTheme.muted)
                .frame(width: 5, height: 5)
            Text(store.status).lineLimit(1)
            Spacer()
            Button("Saved on this Mac", systemImage: "externaldrive") { showsRetention = true }
                .buttonStyle(.borderless)
                .fixedSize()
                .accessibilityIdentifier("desktop-retention.open")
                .help("See what is retained on this Mac and what stays in this visit. Opening this summary saves nothing.")
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .padding(.horizontal, 28).padding(.vertical, 11)
        .accessibilityElement(children: .contain)
    }
}

@MainActor
private struct AssistantWorkspace: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        CompanionPresenceArt(form: store.presentationForm, family: store.presentationFamily,
                            size: 52, reduceMotion: store.preferences.reduceMotion || store.preferences.quiet,
                            treatment: store.preferences.visualTreatment, recipe: store.presentationRecipe,
                            naturalVariation: store.presentationNaturalVariation, equipment: store.preferences.equipment,
                            lightExpression: store.kinLightExpression, seedColor: store.preferences.seedColor)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(store.activeQiMon == nil ? "Here, with you." : "\(store.activeQiMon?.name ?? "ARCHi") is here, with you.")
                                .font(.system(size: 23, weight: .medium, design: .rounded))
                            if store.activeQiMon != nil {
                                Button("Life with \(store.activeQiMon?.name ?? "your companion")") { store.open(.evolution) }
                                    .buttonStyle(.borderless).font(.system(size: 11))
                            } else {
                                Text("Start with a thought. Add a document when it helps.")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        AssistantTaskCue(activity: store.assistantActivity, quiet: store.preferences.quiet,
                            reduceMotion: store.preferences.reduceMotion)
                    }
                    attachmentSummary
                    VoiceTranscriptPreview(voice: store.voiceInput)
                    AssistantReplyContent(store: store)
                }
                .frame(maxWidth: 980, alignment: .leading)
                .padding(20).frame(maxWidth: .infinity)
            }
            .frame(minHeight: 0, maxHeight: .infinity)
            .accessibilityIdentifier("assistant.reply-scroll")
            Divider()
            AssistantReplyComposer(store: store)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 980)
                .padding(16).frame(maxWidth: .infinity)
                .background(.regularMaterial)
        }
        .frame(minHeight: 0, maxHeight: .infinity)
    }

    private var attachmentSummary: some View {
        WorkspaceCard(inset: 12) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text").foregroundStyle(WorkspaceTheme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.sourceName ?? "Add a document")
                        .font(.system(size: 12, weight: .medium)).lineLimit(1)
                        .help(store.sourceName ?? "Choose a UTF-8 text file")
                        .accessibilityIdentifier("assistant.attachment-name")
                    Text(store.sourceName == nil ? "Optional · UTF-8 text" : "Full working copy shared with your next message")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if store.sourceName != nil {
                    Button("Work together", systemImage: "doc.text.viewfinder") { store.section = .context }
                        .buttonStyle(.bordered).controlSize(.small)
                        .accessibilityIdentifier("assistant.open-document")
                    Menu {
                        Button("Change document…") { store.chooseDocument() }
                        Button("Stop sharing") { store.requestStopSharing() }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("Shared document actions")
                } else {
                    Button("Choose…") { store.chooseDocument() }.buttonStyle(.bordered).controlSize(.small)
                        .accessibilityLabel("Choose document")
                }
            }
            DesktopInterestSharingNotice(store: store)
        }
    }
}

/// The draft and Send stay in place while reply text, receipts and voice previews scroll.
@MainActor
private struct AssistantReplyComposer: View {
    @ObservedObject var store: CompanionStore
    @State private var showsSettings = false
    @FocusState private var composerFocused: Bool

    var body: some View {
        let state = AssistantComposerState(store: store)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                AssistantRoutePicker(store: store, compact: true)
                Spacer(minLength: 0)
                Button("Next reply", systemImage: "slider.horizontal.3") { showsSettings.toggle() }
                    .buttonStyle(.borderless).font(.system(size: 11))
                    .accessibilityIdentifier("assistant.settings")
                    .help(store.nextReplySettings.summary)
                    .popover(isPresented: $showsSettings) { AssistantComposerSettingsView(store: store) }
            }
            HStack {
                WorkReplyModePicker(store: store).frame(maxWidth: 280)
                ARCActiveAssistantActions(store: store)
            }
            AssistantComposerConnections(store: store)
            TextField(store.requestsRevision ? "How should this passage change?" : "What would you like to work on?",
                      text: $store.prompt, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 14)).lineLimit(2...3)
                .accessibilityLabel("Message to ARCHi")
                .accessibilityIdentifier("assistant.prompt")
                .focused($composerFocused)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(.primary.opacity(0.12), lineWidth: 1))
            VoiceInputControls(store: store, surface: .assistant)
            HStack(alignment: .center, spacing: 12) {
                Text(state.sendDisclosure).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("assistant.send-disclosure")
                Spacer(minLength: 0)
                if store.isWorking {
                    Button("Stop", systemImage: "stop.fill") { store.cancelWork() }
                        .buttonStyle(.bordered).keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("assistant.stop")
                        .help("Stop the current reply. The message already sent cannot be unsent.")
                } else {
                    Button("Send", systemImage: "arrow.up") { store.submit() }
                        .buttonStyle(.borderedProminent).disabled(!state.canSend)
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityIdentifier("assistant.send")
                }
            }.controlSize(.small)
        }
    }
}

@MainActor
private struct AssistantReplyContent: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selection = store.replySourceSelection ?? store.textSelection {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Source passage for this reply", systemImage: "text.quote")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(WorkspaceTheme.accent)
                    Text(selection.quote).font(.system(size: 12)).lineSpacing(4)
                        .lineLimit(4).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).help(selection.quote)
                }
                .padding(12)
                .background(WorkspaceTheme.accent.opacity(0.17), in: RoundedRectangle(cornerRadius: 10))
            }
            if store.showsARC3Reply {
                        ARC3AssistantReply(store: store, session: store.arc3)
                    } else if store.activeARCAnswer != nil {
                ARCActiveAssistantReply(store: store)
            } else if store.compareResults.values.contains(where: { $0.revision != nil }) {
                ForEach(AssistantProvider.allCases) { provider in
                    if let result = store.compareResults[provider] {
                        WorkTogetherReplyLane(store: store, provider: provider, result: result)
                    }
                }
            } else if store.route == .compare {
                ComparisonReplyPanels(store: store)
            } else {
                Text(store.reply).font(.system(size: 14)).lineSpacing(5)
                if store.assistantProvider == .qwen { HamptonReplyReferences(snapshot: store.hamptonSnapshot) }
                DocumentReadingFeedback(store: store, provider: store.assistantProvider)
                EvolutionReplyFeedback(store: store, provider: store.assistantProvider)
                LessonReplyControls(store: store, provider: store.assistantProvider)
                if let receipt = store.compareResults[store.assistantProvider]?.receipt {
                    AssistantReceiptDetails(receipt: receipt, onOpenGraph: { store.open(.nodeLab) })
                }
            }
            Text("Moving ARCHi or changing shared context stops the current reply.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

@MainActor
private struct AppearanceWorkspace: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            WorkspaceCard {
                WorkspaceAppearancePicker(selection: $store.preferences.workspaceAppearance)
                Button("Keep appearance for next time", systemImage: "bookmark") { store.open(.memory) }
                    .buttonStyle(.borderless).font(.system(size: 11)).padding(.top, 6)
                    .accessibilityHint("Open Memories to save your preferences on this Mac.")
            }
            PersonalContextCard(store: store)
            SeedDesignTestCard(store: store)
            SeedAppearanceCard(store: store)
            QiMonCard(store: store)
            if !store.hasPersonalQiMon {
            HStack(spacing: 24) {
                CompanionPresenceArt(form: store.presentationForm, family: store.presentationFamily, size: 152, reduceMotion: store.preferences.reduceMotion || store.preferences.quiet, treatment: store.preferences.visualTreatment, recipe: store.presentationRecipe, naturalVariation: store.presentationNaturalVariation, equipment: store.preferences.equipment, seedColor: store.preferences.seedColor)
                    .frame(width: 200, height: 180)
                    .background(WorkspaceTheme.accent.opacity(0.17), in: RoundedRectangle(cornerRadius: 28))
                VStack(alignment: .leading, spacing: 9) {
                    StatusPill(text: "Your current form", icon: "checkmark")
                    Text(store.presentationFamily?.title ?? store.presentationForm.rawValue).font(.system(size: 25, weight: .medium, design: .rounded))
                    Text(store.presentationFamily?.summary ?? store.presentationForm.description).font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
                    if store.presentationFamily == nil && store.presentationForm.isStillArtwork {
                        Text("Still artwork with a gentle floating motion. Reduce motion keeps it still.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                    }
                }
                Spacer()
            }
            }
            if store.keptQiMon?.character == .kin {
                ProtoAppearanceCard(store: store)
            }
            CompanionWardrobeCard(store: store)
            if store.activeQiMon != nil {
                DisclosureGroup("Light & sound") { personalLightAbilities.padding(.top, 14) }
            }
            if store.canChooseStartingForm {
            DisclosureGroup("Explore more forms") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 124, maximum: 190), spacing: 12)], spacing: 12) {
                ForEach(CompanionForm.starterChoices.filter { $0 != .corePearl && $0 != .particleSeed && $0 != .hamptonSeed }) { form in
                    Button {
                        store.chooseStartingForm(form)
                    } label: {
                        VStack(spacing: 9) {
                            if form.isStillArtwork {
                                CompanionPresenceArt(form: form, family: nil, size: 86, reduceMotion: true, seedColor: store.preferences.seedColor)
                            } else {
                                CompanionArt(form: form, size: 86, reduceMotion: true)
                            }
                            HStack(spacing: 5) {
                                Text(form.rawValue).font(.system(size: 12, weight: .medium))
                                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                                if store.presentationFamily == nil && form == store.presentationForm { Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.accent) }
                            }
                            .frame(minHeight: 30)
                            Text(form.isStillArtwork ? "Still artwork" : " ")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                                .accessibilityHidden(!form.isStillArtwork)
                        }
                        .frame(maxWidth: .infinity).padding(.horizontal, 8).padding(.vertical, 14)
                        .background(store.presentationFamily == nil && form == store.presentationForm ? WorkspaceTheme.accent.opacity(0.30) : WorkspaceTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(store.presentationFamily == nil && form == store.presentationForm ? WorkspaceTheme.accent.opacity(0.65) : .secondary.opacity(0.12), lineWidth: 1))
                    }.buttonStyle(.plain)
                        .accessibilityLabel("Choose \(form.rawValue) form")
                        .accessibilityHint(form.isStillArtwork ? "Still artwork for the same companion." : "Change the companion’s starting form.")
                        .accessibilityAddTraits(store.presentationFamily == nil && form == store.presentationForm ? [.isSelected] : [])
                }
            }
            }
            }
            WorkspaceCard {
                if store.canChooseStartingForm && store.presentationForm == .companion && store.presentationFamily == nil {
                    SettingsRow(title: "Companion finish", detail: "Choose the original, soft Pearl or long-eared aqua Proto.", icon: "paintpalette") {
                        Picker("Companion finish", selection: $store.preferences.visualTreatment) {
                            ForEach(CompanionVisualTreatment.allCases) { treatment in
                                Text(treatment.rawValue).tag(treatment)
                            }
                        }
                        .pickerStyle(.menu).labelsHidden().frame(width: 180)
                        .accessibilityIdentifier("companion-visual-treatment")
                    }
                    if store.preferences.visualTreatment == .pearlStudy && CompanionVisualAsset.image == nil {
                        Text("Pearl study is unavailable. Your original is shown.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    if store.preferences.visualTreatment == .protoStudy && CompanionVisualAsset.protoImage == nil {
                        Text("Proto is unavailable. Your original is shown.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Divider().padding(.vertical, 10)
                }
                Button("Size & movement settings", systemImage: "accessibility") { store.open(.accessibility) }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("companion.comfort-settings")
                Text("Adjust desktop size and Reduce Motion in Settings → Comfort.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            PreferenceFootnote(store: store)
        }
    }
    private var personalLightAbilities: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(store.kinBodyTitle) · light abilities").font(.system(size: 17, weight: .medium))
                    Text("His light gathers, focuses and opens as you work together, within the body you have kept.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if store.kinLightPreview != nil {
                    Button("Stop preview") { store.stopKinLightPreview() }
                        .buttonStyle(.borderless).font(.system(size: 12))
                        .accessibilityIdentifier("kin-light-stop-preview")
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Musical light cues", isOn: $store.preferences.musicalCues)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("kin-musical-cues")
                Text("One musical voice: C major pentatonic · C, D, E, G, A. Each short phrase returns to C. Try a light below to hear it.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    Button("Play Seedlight", systemImage: "music.note") { store.previewHarmonyTheme() }
                        .disabled(!store.canPreviewHarmonyTheme)
                        .accessibilityIdentifier("kin-play-theme")
                    if store.harmonyThemeRequest != nil {
                        Button("Stop theme", systemImage: "stop.fill") { store.stopHarmonyTheme() }
                            .accessibilityIdentifier("kin-stop-theme")
                    }
                }.buttonStyle(.bordered).controlSize(.small)
                Text("An original eight-bar theme · 84 BPM · Warm bell tone. It plays only when you choose it.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if store.preferences.musicalCues {
                    HStack {
                        Text("Volume").font(.system(size: 12))
                        Slider(value: $store.preferences.musicalVolume, in: 0...1)
                            .frame(maxWidth: 200).accessibilityLabel("Musical cue volume")
                        Text(store.preferences.musicalVolume, format: .percent.precision(.fractionLength(0)))
                            .font(.system(size: 11).monospacedDigit())
                    }
                    Text(store.preferences.quiet ? "Quiet mode silences musical cues." : store.harmonyMessage)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(WorkspaceTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 178, maximum: 260), spacing: 12)], spacing: 12) {
                ForEach(KinLightMode.allCases.filter { $0 != .rest }) { mode in
                    VStack(alignment: .leading, spacing: 9) {
                        CompanionPresenceArt(form: store.cursorPresentationForm, family: nil, size: 116, reduceMotion: true,
                            lightExpression: .init(mode: mode, isPreview: true), seedColor: store.preferences.seedColor)
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                        Text(mode.title).font(.system(size: 14, weight: .medium))
                        Text(mode.colorName).font(.system(size: 11)).foregroundStyle(.secondary)
                        if let cue = HarmonyCue.forMode(mode) {
                            Text(cue.noteNames.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Text(mode.rule).font(.system(size: 12)).foregroundStyle(.secondary)
                            .lineSpacing(3).frame(minHeight: 72, alignment: .topLeading)
                        Button("Preview for 5 seconds") { _ = store.previewKinLight(mode) }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(!store.canPreviewKinLight)
                            .accessibilityLabel("Preview \(store.activeQiMon?.name ?? "your companion")’s \(mode.title) light for 5 seconds")
                            .accessibilityHint("Try this light around his current body. No request or saved change.")
                            .accessibilityIdentifier("kin-light-preview-\(mode.rawValue)")
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(WorkspaceTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(.secondary.opacity(0.16)))
                }
            }
            Text("A passage focus takes priority, then an active reply. Previews last five seconds. Stop returns your companion to rest; Quiet mode keeps the original light, and Reduce Motion keeps every effect still.")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            Button("Focus on a passage", systemImage: "doc.text.viewfinder") { store.open(.context) }
                .buttonStyle(.borderless).font(.system(size: 12))
        }
        .accessibilityIdentifier("personal-light-abilities")
    }

}

@MainActor
private struct RhythmWorkspace: View {
    @ObservedObject var store: CompanionStore
    private let tones = ["Calm", "Direct", "Playful", "Warm"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            WorkspaceCard {
                Text("How we talk").font(.system(size: 16, weight: .medium))
                Text("Choose the voice you want to hear in ARCHi’s writing.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.bottom, 12)
                Picker("Tone", selection: $store.preferences.tone) {
                    ForEach(tones, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented)
                Text("This preference guides the next reply from your connected assistant.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 10)
                Divider().padding(.vertical, 15)
                SettingsRow(title: "Reply length", detail: "From a quick thought to a little more detail.", icon: "text.alignleft") {
                    VStack(spacing: 5) {
                        Slider(value: $store.preferences.replyLength, in: 0...1).accessibilityLabel("Reply length")
                        HStack { Text("Brief"); Spacer(); Text("Detailed") }.font(.system(size: 10)).foregroundStyle(.secondary)
                    }.frame(width: 210)
                }
            }
            WorkspaceCard {
                SettingsRow(title: "Quiet mode", detail: "Keep assistant task cues still while you work.", icon: "moon") {
                    Toggle("Quiet mode", isOn: $store.preferences.quiet).labelsHidden().toggleStyle(.switch)
                }
                Text("Proactive messages and scheduled quiet hours are not connected in this preview.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 12)
            }
            QuoteCard(text: "Useful when you need me. A little quieter when you don’t.", detail: "The direction for ARCHi’s timing")
            PreferenceFootnote(store: store)
        }
    }
}

@MainActor
private struct MemoryWorkspace: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button("Explore memory connections", systemImage: "point.3.connected.trianglepath.dotted") {
                store.open(.nodeLab)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("memory.open-graph")
            KeptLessonsCard(store: store)
            WorkspaceCard {
                SettingsRow(title: "Temporary session context", detail: "Let local Qwen refer to useful excerpts from earlier questions during this visit.", icon: "text.bubble") {
                    Toggle("Temporary session context", isOn: Binding(get: { store.sessionContextEnabled }, set: { store.setSessionContextEnabled($0) }))
                        .labelsHidden().toggleStyle(.switch).disabled(store.isShuttingDown)
                }
                Text("Off by default. Excerpts stay in this app’s memory and are cleared when you quit, turn this off, change models, or replace the shared copy. They are not used to train the models.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3).padding(.top, 10)
                if store.route == .codex {
                    Text("Use Local Qwen or Compare both to include these excerpts. Codex never receives them.")
                        .font(.system(size: 11)).foregroundStyle(WorkspaceTheme.accent).padding(.top, 6)
                }
                Divider().padding(.vertical, 12)
                HStack {
                    Text("\(store.hamptonSnapshot.records.count) / 24 session excerpts").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("Clear session context") { store.clearSessionContext() }
                        .disabled(store.isShuttingDown || (store.hamptonSnapshot.records.isEmpty && !store.isWorking))
                }
                if store.hamptonSnapshot.records.isEmpty {
                    Text("Nothing retained. Only a completed, accepted local reply can add excerpts here.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 10)
                } else {
                    ForEach(store.hamptonSnapshot.records) { record in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.text).font(.system(size: 12)).textSelection(.enabled)
                            Text((record.kind == .document ? "Shared-copy excerpt" : "Your earlier message")
                                 + " · expires in \(max(0, record.expiresAtTurn - store.hamptonSnapshot.turn)) completed context turns")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                        Divider()
                    }
                    Text("These are source excerpts, not independently verified facts. Current instructions take precedence.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 8)
                }
            }
            WorkspaceCard {
                SettingsRow(title: "Remember my preferences", detail: "Save the choices below on this Mac when you press Save.", icon: "bookmark") {
                    Toggle("Remember my preferences", isOn: $store.rememberPreferences).labelsHidden().toggleStyle(.switch)
                }
                Divider().padding(.vertical, 15)
                HStack(alignment: .top, spacing: 28) {
                    PreferenceSummary(title: "Appearance settings", value: store.hasPersonalQiMon ? "Size, motion & items" : store.preferences.form.rawValue, detail: "Kept body: Save in Evolution")
                    PreferenceSummary(title: "Personal rhythm", value: store.preferences.tone, detail: "Reply length and quiet mode")
                }.frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Button("Save preferences", systemImage: "checkmark") { store.savePreferences() }
                        .buttonStyle(.borderedProminent).disabled(!store.rememberPreferences)
                    Button("Forget saved preferences", role: .destructive) { store.forgetPreferences() }
                        .buttonStyle(.borderless)
                    Spacer()
                }.padding(.top, 16)
            }
            WorkspaceCard {
                Label("Your choices are the starting point", systemImage: "hand.raised")
                    .font(.system(size: 15, weight: .medium))
                Text("ARCHi saves the appearance, rhythm and lessons you explicitly keep in its settings file. Kept lessons go only to local Qwen when their scope matches. Temporary session context is separate. Send shares your message, the full shared document copy, and any selected passage with your connected assistant.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(5).padding(.top, 7)
                Text("Turning the switch off does not erase saved choices. Forget saved preferences removes saved appearance and rhythm; withdraw lessons individually above.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 8)
            }
        }
    }

}

@MainActor
struct PlacementPreviewCard: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        WorkspaceCard(fillsHeight: true, inset: 14) {
            HStack(spacing: 7) {
                Label("Beside this passage", systemImage: "arrow.up.right")
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
                Text(store.isRecordingSpatial ? "RECORDING" : store.spatialPreview == nil ? "LOCAL" : "PREVIEW")
                    .font(.system(size: 9, weight: .medium)).tracking(0.8)
                    .foregroundStyle(WorkspaceTheme.accent)
            }
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                .lineSpacing(2).lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
                .help(message)
                .accessibilityLabel(message)
            HStack(spacing: 10) {
                if let preview = store.spatialPreview {
                    Button(preview.candidate.staysPut ? "Stay here" : "Move here", systemImage: preview.candidate.staysPut ? "checkmark" : "arrow.up.right") {
                        store.applyPlacementPreview()
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .fixedSize(horizontal: true, vertical: true)
                    .disabled(store.isWorking)
                    .accessibilityIdentifier("placement.apply")
                    Button("Dismiss") { store.dismissPlacementPreview() }
                        .buttonStyle(.borderless).controlSize(.small)
                        .fixedSize(horizontal: true, vertical: true)
                        .accessibilityLabel("Dismiss placement preview")
                        .accessibilityIdentifier("placement.dismiss")
                } else {
                    Button("Preview placement", systemImage: "viewfinder") { store.previewPlacement() }
                        .buttonStyle(.bordered).controlSize(.small)
                        .fixedSize(horizontal: true, vertical: true)
                        .disabled(store.textSelection == nil || store.isWorking)
                        .accessibilityIdentifier("placement.preview")
                        .help("Preview a spot beside the selected passage. ARCHi moves only after you choose Move here.")
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var message: String {
        if let preview = store.spatialPreview { return preview.candidate.reason }
        return store.spatialMessage.isEmpty ? "Preview a spot without moving ARCHi." : store.spatialMessage
    }
}

@MainActor
private struct ConnectionsWorkspace: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WorkspaceCard {
                Text("Qwen at the core. Your choice of help.")
                    .font(.system(size: 21, weight: .medium, design: .rounded))
                Text("Local Qwen is the default. Use Codex deliberately for an external reference, second opinion or alternative. A local failure never sends your work outside this Mac. Changing the route sends nothing.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4).padding(.top, 6)
                Divider().padding(.vertical, 12)
                AssistantRouteSelector(store: store)
            }
            AssistantProviderPanel(store: store, provider: .qwen)
            AssistantProviderPanel(store: store, provider: .codex)
            ReactorExpressionPanel(reactor: store.reactor)
            WorkspaceCard {
                ConnectionRow(icon: "desktopcomputer", title: "Desktop companion", detail: "Local window, movement, form choices, and menus.", status: "Available", available: true)
                Divider().padding(.vertical, 12)
                ConnectionRow(icon: "doc.text", title: "Local documents", detail: "Share one UTF-8 text file with this workspace.", status: "Available", available: true)
                Divider().padding(.vertical, 12)
                ConnectionRow(icon: "camera", title: "Camera & AR", detail: "Bring ARCHi into a camera view with anchored highlights.", status: "Planned", available: false)
            }
        }
    }
}

@MainActor
private struct AccessibilityWorkspace: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            WorkspaceCard {
                SettingsRow(title: "Reduce motion", detail: "Keep ARCHi still while idle.", icon: "figure.stand") {
                    Toggle("Reduce motion", isOn: $store.preferences.reduceMotion).labelsHidden().toggleStyle(.switch)
                }
                Divider().padding(.vertical, 12)
                SettingsRow(title: "Companion size", detail: "Make ARCHi easier to see on your desktop.", icon: "arrow.up.left.and.arrow.down.right") {
                    Slider(value: $store.preferences.size, in: 0.65...1.6).frame(width: 180).accessibilityLabel("Companion size")
                }
            }
            WorkspaceCard {
                Label("At your keyboard", systemImage: "keyboard").font(.system(size: 16, weight: .medium))
                KeyboardRow(action: "Move between controls", keys: "Tab / Shift Tab")
                KeyboardRow(action: "Send the composer text", keys: "⌘ Return")
                KeyboardRow(action: "Close the workspace", keys: "⌘ W")
                Divider().padding(.vertical, 10)
                Text("Use macOS Keyboard Navigation to reach all controls with Tab. Every appearance option includes a VoiceOver label.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            }
            PreferenceFootnote(store: store)
        }
    }
}

@MainActor
private struct AdvancedWorkspace: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            WorkspaceCard {
                Label("Local role receipts", systemImage: "list.bullet.clipboard")
                    .font(.system(size: 15, weight: .medium))
                Text(store.hamptonSnapshot.phase).font(.system(size: 12)).foregroundStyle(.secondary)
                DisclosureGroup("Attempted local calls · \(store.hamptonSnapshot.invocations.count)") {
                    LocalInvocationDetails(invocations: store.hamptonSnapshot.invocations)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.accessibilityIdentifier("advanced-local-invocations")
                Text("Each receipt records a completed role whose output passed structural and reference checks. This does not establish that the answer is true. No raw prompts or hidden reasoning are recorded here.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3).padding(.vertical, 8)
                ForEach(store.hamptonSnapshot.receipts) { receipt in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(receipt.role.rawValue) · \(receipt.model.name) · \(receipt.elapsedMilliseconds) ms")
                            .font(.system(size: 11, weight: .medium))
                        Text("Model \(receipt.model.digest.prefix(12)) · input \(receipt.inputDigest.prefix(12)) · output \(receipt.outputDigest.prefix(12))")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }.padding(.vertical, 5)
                }
            }
            WorkspaceCard {
                HStack(alignment: .top, spacing: 18) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 34, weight: .light)).foregroundStyle(WorkspaceTheme.accent)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ARCHi Node Lab").font(.system(size: 20, weight: .medium, design: .rounded))
                        Text("Explore the sources, kept lessons and request steps connected to ARCHi's current work.")
                            .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
                        Button("Open Node Lab", systemImage: "point.3.connected.trianglepath.dotted") { store.open(.nodeLab) }
                            .buttonStyle(.borderedProminent).padding(.top, 8)
                            .accessibilityIdentifier("advanced.open-graph")
                    }
                }
                Text("The native graph reads existing records and receipts. Inspecting connections makes no model call and changes no saved state. Historical placement replay remains a separate retained tool.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 16)
            }
            WorkspaceCard {
                Label("Record placement geometry", systemImage: "record.circle")
                    .font(.system(size: 15, weight: .medium))
                Text("Capture positions, proposals, timing, and outcomes. Document text, filenames, device identifiers, and absolute screen origins are excluded.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                HStack(spacing: 12) {
                    if store.isRecordingSpatial {
                        Button("Stop recording", systemImage: "stop.fill") { store.stopSpatialRecording() }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("recording.stop")
                    } else {
                        Button(store.spatialRecordCount == 0 ? "Start recording" : "New recording", systemImage: "record.circle") { store.startSpatialRecording() }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("recording.start")
                    }
                    Text("\(store.spatialRecordCount) / 100 previews").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                }.padding(.vertical, 5)
                HStack(spacing: 12) {
                    Button("Export recording…", systemImage: "square.and.arrow.up") { store.exportSpatialRecording() }
                        .disabled(store.isRecordingSpatial || store.spatialRecordCount == 0)
                        .accessibilityIdentifier("recording.export")
                    Button("Clear") { store.clearSpatialRecording() }
                        .disabled(store.isRecordingSpatial || store.spatialRecordCount == 0)
                        .accessibilityLabel("Clear placement recording")
                }
                Text(store.spatialRecordingMessage).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                if store.spatialRecordCount > 0 && !store.isRecordingSpatial {
                    Text("New recording replaces this session’s retained recording. It does not change exported files.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            WorkspaceCard {
                Label("This session", systemImage: "clock.arrow.circlepath").font(.system(size: 15, weight: .medium))
                HStack(spacing: 30) {
                    PreferenceSummary(title: "Placement", value: String(store.placementRevision), detail: "Current revision")
                    PreferenceSummary(title: "Shared source", value: String(store.sourceRevision), detail: "Current revision")
                }.padding(.vertical, 12)
                if let receipt = store.lastPlacementReceipt {
                    Divider().padding(.vertical, 8)
                    Label("Last placement check", systemImage: "viewfinder")
                        .font(.system(size: 12, weight: .medium))
                    Text("Requested: " + String(describing: receipt.requestedFrame))
                        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    Text("Observed: " + (receipt.actualFrame.map { String(describing: $0) } ?? "Unavailable"))
                        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    Divider().padding(.vertical, 8)
                }
                if store.activity.isEmpty {
                    Text("Desktop and context changes will appear here.").font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(store.activity.suffix(8).enumerated()), id: \.offset) { _, entry in
                        Text(entry).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }
                }
            }
        }
    }
}

struct WorkspaceCard<Content: View>: View {
    var fillsHeight = false
    var inset: CGFloat = 22
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(inset).frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
            .modifier(WorkspaceSurface())
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    let detail: String
    let icon: String
    @ViewBuilder let control: Control
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon).foregroundStyle(WorkspaceTheme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            control
        }.padding(.vertical, 4)
    }
}

private struct StatusPill: View {
    let text: String
    let icon: String
    var body: some View {
        Label(text, systemImage: icon).font(.system(size: 10, weight: .medium))
            .foregroundStyle(WorkspaceTheme.accent)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(WorkspaceTheme.accent.opacity(0.25), in: Capsule())
    }
}

private struct QuoteCard: View {
    let text: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(.system(size: 20, weight: .regular, design: .rounded)).lineSpacing(4)
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(WorkspaceTheme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 20))
    }
}

@MainActor
private struct PreferenceFootnote: View {
    @ObservedObject var store: CompanionStore
    var body: some View {
        HStack(spacing: 6) {
            Text("Keep these choices for next time in")
            Button("What I remember") { store.section = .memory }.buttonStyle(.borderless)
            Spacer(minLength: 0)
        }.font(.system(size: 11)).foregroundStyle(.secondary)
    }
}

private struct PreferenceSummary: View {
    let title: String
    let value: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 17, weight: .medium, design: .rounded))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConnectionRow: View {
    let icon: String
    let title: String
    let detail: String
    let status: String
    let available: Bool
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon).font(.system(size: 19, weight: .light)).foregroundStyle(WorkspaceTheme.accent).frame(width: 32)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            }
            Spacer(minLength: 20)
            Label(status, systemImage: available ? "checkmark.circle" : "circle.dashed")
                .font(.system(size: 11)).foregroundStyle(available ? WorkspaceTheme.accent : .secondary)
        }.padding(.vertical, 6)
    }
}

private struct KeyboardRow: View {
    let action: String
    let keys: String
    var body: some View {
        HStack {
            Text(action).font(.system(size: 12))
            Spacer()
            Text(keys).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
        }.padding(.top, 10)
    }
}

private extension CompanionForm {
    var isStillArtwork: Bool {
        switch self {
        case .constellation, .sprout, .ribbonSpirit, .geode: true
        default: false
        }
    }

    var description: String {
        switch self {
        case .companion: "A soft, familiar presence beside your work."
        case .light: "A small glow, with just enough personality."
        case .particle: "A mint-white cloud of light, gathered into a quiet floating orb."
        case .corePearl: "A translucent aqua ball of light. One continuing core, with room to become."
        case .particleSeed: "Gold and garnet particles gather around a steady ivory core."
        case .hamptonSeed: "A sea-glass core and open gold arcs, with room to become."
        case .orbitField: "A fine green-blue orbit gathers around a small pearl, with sparks tracing its field."
        case .lightForm: "Translucent mint petals open around a luminous pearl, held within a delicate orbit of light."
        case .ribbon: "A fluid line that gives your desk a little movement."
        case .ink: "A quiet mark with a playful point of view."
        case .pixel: "A little nostalgia, one square at a time."
        case .constellation: "Fine threads and green-blue sparks gather around a bright, familiar core."
        case .sprout: "Leaf-like ears and a soft jade glow give ARCHi a little woodland character."
        case .ribbonSpirit: "Flowing ribbons of sea-glass light curl around the same luminous heart."
        case .geode: "Floating crystal facets hold a little green-blue light at their center."
        case .kin: "KIN’s First Light: a swept garnet crest, warm core, and flowing gold currents."
        case .kinSeed: "KIN’s beginning: gold and garnet particles circle a steady ivory core."
        case .kinSpark: "An earlier KIN Spark study: a round living ember with budding limbs."
        case .kinSimple: "KIN’s everyday expression, drawn simply for a clear presence at small sizes."
        }
    }
}

private extension WorkspaceSection {
    func displayTitle(companionName: String?) -> String {
        if let companionName, self == .evolution { return "Life with \(companionName)" }
        return WorkspaceNavigation.title(for: self)
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .assistant: "bubble.left.and.bubble.right"
        case .nodeLab: "point.3.connected.trianglepath.dotted"
        case .steward: "chart.bar.doc.horizontal"
        case .capabilities: "square.grid.3x3"
        case .unity: "gamecontroller"
        case .play: "gamecontroller"
        case .marketplace: "bag"
        case .appearance: "paintpalette"
        case .evolution: "sparkles"
        case .rhythm: "waveform"
        case .memory: "bookmark"
        case .context: "doc.text.viewfinder"
        case .connections: "point.3.connected.trianglepath.dotted"
        case .accessibility: "accessibility"
        case .advanced: "slider.horizontal.3"
        }
    }
    var eyebrow: String {
        switch self {
        case .home: ARCHiIdentity.descriptor
        case .assistant: "A little space to think"
        case .nodeLab: "Connected knowledge"
        case .steward, .capabilities: "Work and evidence"
        case .unity: "Explore & create"
        case .play: "Your world of play"
        case .marketplace, .appearance, .evolution, .rhythm: "Make it yours"
        case .memory, .context: "Always your choice"
        case .connections, .accessibility, .advanced: "ARCHi preferences"
        }
    }
    var heading: String {
        switch self {
        case .home: "Here, with you."
        case .assistant: "Here, with you."
        case .nodeLab: "Your connections, in view."
        case .steward: "Understand the work."
        case .capabilities: "Capabilities, with evidence."
        case .unity: "More room to be."
        case .play: "A little room to play."
        case .marketplace: "A little more you."
        case .appearance: "A familiar presence. Your style."
        case .evolution: "A life together."
        case .rhythm: "At your pace. In your tone."
        case .memory: "What I remember"
        case .context: "Work together"
        case .connections: "A world of connections"
        case .accessibility: "Comfort comes first"
        case .advanced: "A closer look"
        }
    }
    var subtitle: String {
        switch self {
        case .home: "Your companion, context, and kept memories."
        case .assistant: "Your thoughts, your context, and a companion close by."
        case .nodeLab: "Follow the sources, lessons and work behind each answer."
        case .steward: "Measured usage, explicit outcomes and spending boundaries."
        case .capabilities: "Review locally checked ARC evidence."
        case .unity: "Bring your companion into Unity, with the same identity and chosen appearance."
        case .play: "Return to your Habitat, continue your Journey, and meet in the Practice Arena."
        case .marketplace: "Discover, make and exchange local companion items."
        case .appearance: "Choose how ARCHi shows up on your desktop."
        case .evolution: "Familiar family traits. Small individual differences. Shared experiences."
        case .rhythm: "Set the kind of conversation that feels right for you."
        case .memory: "Keep the preferences you choose. Change your mind whenever you like."
        case .context: "Keep your draft in view. Review each change before it becomes your working copy."
        case .connections: "See what’s available and what’s still taking shape."
        case .accessibility: "A little more space, a little less motion, and familiar controls."
        case .advanced: "Tools for exploring how ARCHi works."
        }
    }
}
