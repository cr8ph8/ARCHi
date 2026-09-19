import SwiftUI

/// The AppKit document keeps the same identity and frame across every reply state.
/// Only the independent review scroll changes as a proposal arrives or is dismissed.
@MainActor
struct WorkTogetherWorkspace: View {
    @ObservedObject var store: CompanionStore
    @State private var showsConnections = false
    @State private var showsPlacement = false
    @State private var showsSettings = false
    @State private var showsInterest = false
    @State private var showsMeetingNotes = false
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            workbenchHeader
            Divider()
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    documentPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    reviewRail
                        .frame(width: min(400, max(292, geometry.size.width * 0.44)),
                               height: geometry.size.height)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .sheet(isPresented: $showsMeetingNotes) { MeetingNotesImportSheet(store: store) }
    }

    private var workbenchHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Work together").font(.system(size: 23, weight: .medium, design: .rounded))
                Text("Point at something. Bring its context into your work.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Look here", systemImage: "scope") { showsInterest.toggle() }
                .buttonStyle(.borderless).accessibilityIdentifier("work.interest")
                .popover(isPresented: $showsInterest) { DesktopInterestCard(store: store).frame(width: 350).padding(12) }
            Button("Place ARCHi", systemImage: "viewfinder") { showsPlacement.toggle() }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("work.placement")
                .popover(isPresented: $showsPlacement) {
                    PlacementPreviewCard(store: store).frame(width: 330, height: 148).padding(12)
                }
            Button { showsConnections.toggle() } label: {
                Image(systemName: "point.3.connected.trianglepath.dotted")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Assistant connections")
            .help("Review local Qwen and Codex connections")
            .popover(isPresented: $showsConnections) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Assistant connections").font(.headline)
                    ForEach(AssistantProvider.allCases) { provider in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(provider.name).font(.system(size: 12, weight: .medium))
                                Text(store.connection(for: provider).rawValue)
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            ProviderConnectionControls(store: store, provider: provider)
                        }
                    }
                    Button("Connection settings") { showsConnections = false; store.open(.connections) }
                        .buttonStyle(.borderless)
                }
                .padding(20).frame(width: 330)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 20)
        .frame(height: 64)
    }

    private var documentPane: some View {
        VStack(spacing: 0) {
            documentToolbar
            if store.desktopInterestSource != nil {
                DesktopInterestSharingNotice(store: store).padding(10)
            }
            Divider()
            SharedDocumentView(store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("work.document")
                .overlay {
                    if store.sourceName == nil { emptyDocument }
                }
            Divider()
            passageActions
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var documentToolbar: some View {
        HStack(spacing: 9) {
            Image(systemName: "doc.text").foregroundStyle(WorkspaceTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.sourceName ?? "Your working copy")
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                    .help(store.sourceName ?? "Choose a UTF-8 text document")
                Text(store.hasUnexportedWorkingCopy ? "Session edits · Export to keep"
                     : store.desktopInterestSource != nil ? "Captured copy · original window unchanged" : "Original file unchanged")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("work.persistence-status")
            }
            Spacer(minLength: 0)
            Button { store.undoWorkingCopyEdit() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!store.canUndoWorkingCopyEdit)
                .keyboardShortcut("z", modifiers: .command)
                .accessibilityLabel("Undo working copy edit")
                .accessibilityIdentifier("work.undo")
                .help("Undo the last applied passage revision")
            Button { store.exportWorkingCopy() } label: { Image(systemName: "square.and.arrow.up") }
                .disabled(store.sourceName == nil)
                .accessibilityLabel("Export working copy")
                .accessibilityIdentifier("work.export")
                .help("Save a separate text draft")
            Menu {
                Button(store.sourceName == nil ? "Choose document…" : "Change document…") { store.chooseDocument() }
                Button("Import meeting notes…") { showsMeetingNotes = true }
                Button("Prepare meeting digest") { store.prepareMeetingDigest() }
                    .disabled(store.sourceName == nil || store.isWorking)
                Button("Stop sharing") { store.requestStopSharing() }.disabled(store.sourceName == nil)
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Document actions")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .frame(height: 50)
    }

    private var emptyDocument: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 38, weight: .ultraLight)).foregroundStyle(WorkspaceTheme.accent)
            Text("Bring something into focus.")
                .font(.system(size: 19, weight: .medium, design: .rounded))
            Text("Point ARCHi at a window to read a local snapshot, or choose a text document. Then select a passage to work on together.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button("Choose document…", systemImage: "plus") { store.chooseDocument() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("work.choose-document")
            Button("Import meeting notes…", systemImage: "text.bubble") { showsMeetingNotes = true }
                .buttonStyle(.bordered).accessibilityIdentifier("work.import-meeting-notes")
            Button("Point at a window", systemImage: "scope") { store.beginDesktopInterest() }
                .buttonStyle(.bordered).accessibilityIdentifier("work.point-window")
            Text("UTF-8 text · up to 100 KB").font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var passageActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "text.cursor").foregroundStyle(WorkspaceTheme.accent)
                Text(store.textSelection.map { "\($0.quote.count.formatted()) characters selected" } ?? "Select a passage in your draft")
                    .font(.system(size: 11)).lineLimit(1)
                    .accessibilityIdentifier("work.selection-status")
                Spacer(minLength: 0)
                Button("Clear") { store.clearTextSelection() }
                    .buttonStyle(.borderless).font(.system(size: 11))
                    .disabled(store.textSelection == nil)
                    .accessibilityLabel("Clear selected passage")
            }
            HStack(spacing: 7) {
                Button("Explain") { store.preparePassageExplanation(); composerFocused = true }
                    .accessibilityIdentifier("work.explain")
                Button("Rewrite", systemImage: "pencil.line") { store.preparePassageRevision(); composerFocused = true }
                    .accessibilityIdentifier("work.rewrite")
                Button("Shorten") { store.preparePassageRevision(shorten: true); composerFocused = true }
                    .accessibilityIdentifier("work.shorten")
                Spacer(minLength: 0)
            }
            .buttonStyle(.bordered).controlSize(.small)
            .disabled(store.textSelection == nil || store.isWorking)
            .help("Prepare an instruction for this exact passage. Send starts the request.")
            if store.activeQiMon != nil {
                HStack(spacing: 8) {
                    Button("Focus light", systemImage: "sparkle.magnifyingglass") {
                        store.previewPlacement()
                        showsPlacement = store.spatialPreview != nil
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(store.textSelection == nil || store.isWorking || !store.isVisible || store.preferences.quiet)
                    .accessibilityIdentifier("work.kin-focus-light")
                    .help("Your companion focuses on the selected passage and previews a nearby position. Nothing is sent; your companion stays in place.")
                    if store.hasFreshKinFocus {
                        Button("Stop focus") { store.dismissPlacementPreview() }
                            .buttonStyle(.borderless).font(.system(size: 11))
                            .accessibilityIdentifier("work.kin-stop-focus")
                    }
                    Spacer(minLength: 0)
                }
            }
            if store.preferences.equipment.supportsPointing {
                HStack(spacing: 6) {
                    Button("Point with staff") {
                        if store.activateEquippedItem() { showsPlacement = true }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(store.textSelection == nil || store.isWorking || !store.isVisible)
                    .accessibilityIdentifier("work.focus-staff")
                    .help("Use your staff gesture to highlight this passage and preview a nearby position. Nothing is sent; ARCHi stays in place.")
                    Button("Point and explain") { _ = store.pointAndExplainSelection() }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(!store.canPointAndExplainSelection)
                        .accessibilityIdentifier("work.point-and-explain")
                        .accessibilityHint(pointAndExplainHelp)
                        .help(pointAndExplainHelp)
                    Spacer(minLength: 0)
                    if store.focusGesturePlayback != nil {
                        Button("Stop") { store.stopFocusGesture() }
                            .buttonStyle(.borderless).font(.system(size: 11))
                            .accessibilityLabel("Stop staff action")
                            .accessibilityIdentifier("focus-gesture.work-stop")
                            .help("Stop this gesture and any answer started with Point and explain.")
                    }
                    Menu {
                        Button(store.focusGestureDraft == nil ? "Edit gesture…" : "Review gesture…") {
                            if store.focusGestureDraft == nil { store.beginFocusGestureTeaching() }
                            store.open(.appearance)
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("Staff gesture options")
                    .accessibilityIdentifier("focus-gesture.work-options")
                }
            }
            if store.focusGestureDraft != nil {
                HStack(spacing: 10) {
                    Button("Practice gesture") {
                        if store.practiceFocusGesture() { showsPlacement = true }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(!store.preferences.equipment.supportsPointing || store.textSelection == nil
                              || store.isWorking || !store.isVisible)
                    .accessibilityIdentifier("focus-gesture.practice")
                    .help("Try your unsaved gesture on this selected passage. No assistant request or automatic movement.")
                    Button("Review gesture") { store.open(.appearance) }
                        .buttonStyle(.borderless).font(.system(size: 11))
                        .accessibilityIdentifier("focus-gesture.review")
                    if !store.preferences.equipment.supportsPointing && store.focusGesturePlayback != nil {
                        Button("Stop") { store.stopFocusGesture() }
                            .buttonStyle(.borderless).font(.system(size: 11))
                            .accessibilityLabel("Stop staff gesture")
                            .accessibilityIdentifier("focus-gesture.work-stop")
                    }
                    Spacer(minLength: 0)
                }
            }
            if showsGestureControls {
                VStack(alignment: .leading, spacing: 2) {
                    Text(gestureStatus)
                        .lineLimit(store.preferences.equipment.supportsPointing ? 1 : 2)
                        .help(gestureStatus)
                        .accessibilityIdentifier("focus-gesture.work-status")
                    if store.preferences.equipment.supportsPointing {
                        Text("Point and explain sends now to \(pointAndExplainDestination).")
                            .lineLimit(1).minimumScaleFactor(0.9)
                            .help(pointAndExplainHelp)
                            .accessibilityIdentifier("work.point-and-explain-disclosure")
                    }
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(height: 26, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: passageActionsHeight)
    }

    private var showsGestureControls: Bool {
        store.preferences.equipment.supportsPointing || store.focusGestureDraft != nil
    }

    /// Optional rows reserve their own space; a changing playback message does
    /// not resize the shared document or its selection geometry.
    private var passageActionsHeight: CGFloat {
        80 + (store.activeQiMon != nil ? 32 : 0)
            + (store.preferences.equipment.supportsPointing ? 32 : 0)
            + (store.focusGestureDraft != nil ? 32 : 0) + (showsGestureControls ? 36 : 0)
    }

    private var gestureStatus: String {
        if store.focusGestureDraft != nil && !store.preferences.equipment.supportsPointing {
            return "Equip the Focus Staff in Appearance to practice. Your gesture draft is waiting."
        }
        if !store.focusGestureMessage.isEmpty { return store.focusGestureMessage }
        return store.focusGestureDraft != nil ? "Practice tries your draft. Point with staff uses your staff gesture."
            : "Point with staff uses your staff gesture. Edit it in the staff options."
    }

    private var pointAndExplainDestination: String {
        switch store.route {
        case .native: "Qwen on this Mac, with one Codex fallback if Qwen is unavailable or times out"
        case .local: "Qwen on this Mac"
        case .codex: "Codex"
        case .compare: "both assistants"
        case .automatic: "Qwen on this Mac"
        }
    }

    private var pointAndExplainHelp: String {
        "Send an explanation request to \(pointAndExplainDestination) now and point with your staff gesture. "
            + "Your message adds instructions and stays in the composer. "
            + store.route.disclosure
    }

    private var reviewRail: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                CompanionPresenceArt(form: store.presentationForm, family: store.presentationFamily,
                    size: 34, reduceMotion: store.preferences.reduceMotion || store.preferences.quiet, treatment: store.preferences.visualTreatment, recipe: store.presentationRecipe, naturalVariation: store.presentationNaturalVariation, equipment: store.preferences.equipment, lightExpression: store.kinLightExpression, seedColor: store.preferences.seedColor)
                Text("ARCHi").font(.system(size: 15, weight: .medium, design: .rounded))
                Spacer(minLength: 0)
                AssistantTaskCue(activity: store.assistantActivity, quiet: store.preferences.quiet,
                                 reduceMotion: store.preferences.reduceMotion)
            }
            .padding(.horizontal, 14).frame(height: 54)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VoiceTranscriptPreview(voice: store.voiceInput)
                    DocumentWorkHistory(store: store)
                    if let selection = store.textSelection,
                       !store.compareResults.values.contains(where: { $0.state == .complete && $0.revision != nil }) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("SELECTED PASSAGE").font(.system(size: 9, weight: .semibold)).tracking(1)
                                .foregroundStyle(WorkspaceTheme.accent)
                            Text(selection.quote).font(.system(size: 12)).lineSpacing(3).lineLimit(3)
                                .help(selection.quote)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).background(WorkspaceTheme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if store.showsARC3Reply {
                        ARC3AssistantReply(store: store, session: store.arc3)
                    } else if store.activeARCAnswer != nil {
                        ARCActiveAssistantReply(store: store)
                    } else if store.compareResults.isEmpty {
                        reviewIntroduction
                    } else {
                        ForEach(store.resultProviders) { provider in
                            if let result = store.compareResults[provider] {
                                WorkTogetherReplyLane(store: store, provider: provider, result: result)
                            }
                        }
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Text(store.workingCopyNotice)
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).frame(height: 38)
                .help(store.workingCopyNotice)
                .accessibilityIdentifier("work.notice")
            Divider()
            composer
        }
        .background(.regularMaterial)
    }

    private var reviewIntroduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.canUndoWorkingCopyEdit ? "Your change is in the draft." : "A second pair of eyes.")
                .font(.system(size: 18, weight: .medium, design: .rounded))
            Text(store.canUndoWorkingCopyEdit
                 ? "Read it in place, undo it, or export a separate draft when you are ready."
                 : "Select a passage, then ask a question or prepare a revision. Proposed changes appear here for you to review.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            if store.canUndoWorkingCopyEdit && !store.reply.isEmpty {
                Text(store.reply).font(.system(size: 12)).lineSpacing(4).textSelection(.enabled)
            }
        }
        .padding(.vertical, 7)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                WorkReplyModePicker(store: store)
                ARCActiveAssistantActions(store: store)
                Button { showsSettings.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Next reply settings")
                    .accessibilityIdentifier("work.settings")
                    .popover(isPresented: $showsSettings) {
                        AssistantComposerSettingsView(store: store)
                    }
            }
            HStack(spacing: 5) {
                AssistantRoutePicker(store: store, compact: true)
                if !store.isWorking, !store.arcCommandSelected, !store.route.connectsAutomatically,
                   let provider = store.route.providers.first(where: { store.connection(for: $0) != .ready }) {
                    ProviderConnectionControls(store: store, provider: provider).controlSize(.small)
                }
                Spacer(minLength: 0)
                Button("Lessons · \(store.nextReplyLessons.count)") { showsSettings = true }
                    .buttonStyle(.borderless).font(.system(size: 10))
                    .accessibilityLabel("Kept lessons for local Qwen: \(store.nextReplyLessons.count)")
                    .accessibilityIdentifier("assistant-next-lessons")
                    .help("Matching kept lessons go only to local Qwen. Review the next reply settings.")
            }
            TextField(store.requestsRevision ? "How should this passage change?" : "What would you like to know?",
                      text: $store.prompt, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 13)).lineLimit(2...3)
                .focused($composerFocused)
                .accessibilityLabel("Message to ARCHi").accessibilityIdentifier("work.prompt")
                .padding(10).frame(height: 64, alignment: .topLeading)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(.primary.opacity(0.12), lineWidth: 1))
            VoiceInputControls(store: store, surface: .work)
            HStack(alignment: .center, spacing: 8) {
                Text(AssistantComposerState(store: store).sendDisclosure).font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("work.send-disclosure")
                Spacer(minLength: 0)
                if store.isWorking {
                    Button("Stop", systemImage: "stop.fill") { store.cancelWork() }
                        .buttonStyle(.bordered).keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("work.stop")
                } else {
                    Button("Send", systemImage: "arrow.up") { store.submit() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!AssistantComposerState(store: store).canSend)
                        .accessibilityIdentifier("work.send")
                }
            }
            .controlSize(.small)
            .frame(height: 42, alignment: .center)
        }
        .padding(14)
        .frame(height: 248, alignment: .top)
    }

}

/// Shared with the Assistant page so revising is never a hidden request mode.
@MainActor
struct WorkReplyModePicker: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
        Picker("Reply mode", selection: $store.requestsRevision) {
            Text("Ask").tag(false)
            Text("Revise passage").tag(true)
        }
        .pickerStyle(.segmented).controlSize(.small)
        .accessibilityLabel("Reply mode").accessibilityIdentifier("work.reply-mode")
        .disabled(store.isWorking)
        .help("Ask for an answer, or request a proposed change to the selected passage.")
        PreparedDocumentProcedureView(store: store)
        if store.requestsRevision {
            Toggle("Require shorter text", isOn: $store.documentRequirements.mustBeShorter)
                .accessibilityIdentifier("document.require-shorter")
            Toggle("Keep exact numbers and links", isOn: $store.documentRequirements.preserveNumbersAndLinks)
                .accessibilityIdentifier("document.preserve-tokens")
            Text("Checks are captured when you Send. You review meaning and facts.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        }.font(.caption).disabled(store.isWorking)
    }
}

@MainActor
struct WorkTogetherReplyLane: View {
    @ObservedObject var store: CompanionStore
    let provider: AssistantProvider
    let result: AssistantLaneResult

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 5) {
                Text(provider.name).font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Text(stateTitle).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if let proposal = result.revision, result.state == .complete {
                if proposal.decision == .propose {
                    HStack {
                        Button("Apply change", systemImage: "checkmark") {
                            store.applyPassageRevision(provider: provider, targetID: proposal.target.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!store.canApplyDocumentRevision(provider: provider, proposal: proposal))
                        .accessibilityLabel("Apply \(provider.name) revision")
                        .accessibilityIdentifier("work.apply.\(provider.name.lowercased())")
                        Button("Dismiss") { store.dismissPassageRevision(provider: provider) }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Dismiss \(provider.name) revision")
                            .accessibilityIdentifier("work.dismiss.\(provider.name.lowercased())")
                        Spacer(minLength: 0)
                    }
                    .controlSize(.small)
                    DocumentWorkCheckView(verification: store.documentVerification(proposal))
                    passage("Before", text: proposal.target.selection.quote, proposed: false)
                    passage("After", text: proposal.replacement, proposed: true)
                } else {
                    Text(proposal.decision == .clarify ? "A little more detail would help." : "No change proposed.")
                        .font(.system(size: 13, weight: .medium))
                    Button("Dismiss") { store.dismissPassageRevision(provider: provider) }.buttonStyle(.borderless)
                }
                if !proposal.explanation.isEmpty {
                    Text(proposal.explanation).font(.system(size: 12)).lineSpacing(4).textSelection(.enabled)
                }
            } else {
                if !result.text.isEmpty {
                    Text(result.text).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                }
                Text(result.status).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if result.state == .complete {
                    DocumentReadingFeedback(store: store, provider: provider)
                    EvolutionReplyFeedback(store: store, provider: provider)
                    LessonReplyControls(store: store, provider: provider)
                }
            }
            if let receipt = result.receipt {
                DisclosureGroup("Request details") {
                    AssistantReceiptDetails(receipt: receipt, onOpenGraph: { store.open(.nodeLab) }).padding(.top, 6)
                    if provider == .qwen { HamptonReplyReferences(snapshot: store.hamptonSnapshot) }
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.07), lineWidth: 1))
    }

    private func passage(_ title: String, text: String, proposed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(proposed ? WorkspaceTheme.accent : .secondary)
            Text(text).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(proposed ? WorkspaceTheme.accent.opacity(0.16) : Color.primary.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(provider.name)")
    }

    private var stateTitle: String {
        switch result.state {
        case .pending: "Working"
        case .complete: result.revision?.decision == .propose ? "Ready to review" : "Answer ready"
        case .failed: "Failed"
        case .cancelled: "Stopped"
        }
    }
}
