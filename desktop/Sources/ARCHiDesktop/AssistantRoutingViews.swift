import SwiftUI

/// Routing chooses the destination of the next request, independently of connections.
@MainActor
struct AssistantRouteSelector: View {
    @ObservedObject var store: CompanionStore
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AssistantRoutePicker(store: store, compact: compact, showsTitle: true)
            Text(disclosure)
                .font(.system(size: compact ? 10 : 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            AssistantConversationControls(store: store)
        }
    }

    private var disclosure: String {
        switch store.route {
        case .local:
            store.sessionContextEnabled
                ? "Send runs on this Mac with optional local session excerpts."
                : "Send runs on this Mac."
        case .codex:
            store.route.disclosure
        case .compare:
            store.sessionContextEnabled || !store.nextReplyLessons.isEmpty
                ? "Send shares your message, full shared copy and reply settings with local Qwen and external Codex for comparison. Only Qwen receives kept lessons, enabled session excerpts and recent Qwen conversation."
                : store.route.disclosure
        case .automatic:
            store.route.disclosure
        }
    }
}

/// The same route action is available in both native workspaces.
@MainActor
struct AssistantRoutePicker: View {
    @ObservedObject var store: CompanionStore
    var compact = false
    var showsTitle = false

    var body: some View {
        HStack(spacing: 6) {
            if showsTitle {
                Text("Answer with").font(.system(size: compact ? 11 : 12, weight: .medium))
            }
            Picker("Answer with", selection: Binding(get: { store.route }, set: { store.setAssistantRoute($0) })) {
                Text(AssistantRoute.local.title).tag(AssistantRoute.local)
                Text(AssistantRoute.automatic.title).tag(AssistantRoute.automatic)
                Text(AssistantRoute.codex.title).tag(AssistantRoute.codex)
                Text(AssistantRoute.compare.title).tag(AssistantRoute.compare)
            }
            .pickerStyle(.menu).controlSize(compact ? .small : .regular)
            .labelsHidden()
            .accessibilityLabel("Answer route")
            .accessibilityIdentifier("assistant.route")
            .disabled(store.isShuttingDown)
            if showsTitle { Spacer(minLength: 0) }
        }
    }
}

/// Inspecting or clearing conversation uses the existing request owner's state.
@MainActor
struct AssistantComposerSettingsView: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NextReplySettingsView(store: store)
                Divider()
                Text(store.route.disclosure).font(.system(size: 11)).foregroundStyle(.secondary)
                AssistantConversationControls(store: store)
            }
            .padding(20)
        }
        .frame(width: 330, height: 400)
    }
}

/// Recovery belongs beside the composer, including after Stop or a failed reply.
@MainActor
struct AssistantComposerConnections: View {
    @ObservedObject var store: CompanionStore
    var body: some View {
        if !store.isWorking && store.route != .automatic {
            ForEach(store.route.providers.filter { store.connection(for: $0) != .ready }) { provider in
                HStack(alignment: .center, spacing: 8) {
                    ProviderConnectionControls(store: store, provider: provider)
                    Text(store.message(for: provider))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(2).help(store.message(for: provider))
                }
            }
        }
    }
}

@MainActor
struct ProviderConnectionControls: View {
    @ObservedObject var store: CompanionStore
    let provider: AssistantProvider

    var body: some View {
        Group {
            switch store.connection(for: provider) {
            case .ready:
                Button("Disconnect", systemImage: "xmark") { store.disconnectAssistant(provider: provider) }
                    .buttonStyle(.bordered)
                    .help("Disconnect \(provider.name). The other assistant keeps its connection and active reply.")
            case .connecting:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).accessibilityLabel("Connecting to \(provider.name)")
                    Button("Cancel") { store.disconnectAssistant(provider: provider) }.buttonStyle(.borderless)
                }
            case .disconnected, .failed:
                Button(store.connection(for: provider) == .failed ? "Try again" : "Connect \(provider.name)", systemImage: "link") {
                    store.connectAssistant(provider: provider)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .accessibilityIdentifier("assistant.connection.\(provider.name.lowercased())")
        .disabled(store.isShuttingDown)
    }
}

@MainActor
struct AssistantProviderPanel: View {
    @ObservedObject var store: CompanionStore
    let provider: AssistantProvider

    var body: some View {
        WorkspaceCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: provider == .qwen ? "desktopcomputer" : "bubble.left.and.bubble.right")
                    .font(.system(size: 23, weight: .light)).foregroundStyle(ArchiPalette.violet)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 7) {
                    Text(provider.rawValue).font(.system(size: 18, weight: .medium, design: .rounded))
                    Text(provider.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                ProviderConnectionControls(store: store, provider: provider)
            }
            Divider().padding(.vertical, 12)
            HStack(spacing: 7) {
                Image(systemName: store.connection(for: provider) == .ready ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(ArchiPalette.violet)
                Text(store.connection(for: provider).rawValue).font(.system(size: 12, weight: .medium))
            }
            Text(store.message(for: provider)).font(.system(size: 12)).foregroundStyle(.secondary)
                .lineSpacing(3).textSelection(.enabled).padding(.top, 3)
            if provider == .qwen {
                localModels.padding(.top, 12)
                Divider()
                QwenVoiceControls(voice: store.qwenVoice, text: QwenVoice.preview, enabled: store.canReadAloud, settings: true)
            } else {
                Text("Optional external reference or alternative using your Codex login. Choose the route and Send to share the current request. The resolved model name is not reported by this adapter. Connecting does not send your draft or shared copy.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3).padding(.top, 10)
                Text("Review your provider account’s data and licensing terms before sharing sensitive or proprietary material. ARCHi makes no copyright or exclusive ownership guarantee.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3).padding(.top, 6)
            }
        }
    }

    private var localModels: some View {
        VStack(alignment: .leading, spacing: 9) {
            Picker("Reasoning model", selection: Binding(get: { store.qwenModel }, set: { store.selectQwenModel($0) })) {
                ForEach(QwenAssistant.supportedModels, id: \.self) { model in Text(model).tag(model) }
            }
            .pickerStyle(.menu).accessibilityLabel("Local Qwen model")
            Picker("Context model", selection: Binding(get: { store.qwenContextModel }, set: { store.selectQwenContextModel($0) })) {
                ForEach(QwenAssistant.supportedModels, id: \.self) { model in Text(model).tag(model) }
            }
            .pickerStyle(.menu).accessibilityLabel("Local Qwen context model")
            Text("The context role selects exact excerpts only when Temporary session context is on. Changing a local model stops the local reply and clears its context; Codex stays available.")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            Button("Manage session context") { store.open(.memory) }.buttonStyle(.borderless)
            Text("Connect checks the installed Ollama model without generating an answer. Only Send starts local inference. Model choices apply to this visit.")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
        }
        .disabled(store.isShuttingDown)
    }
}

@MainActor
struct ComparisonReplyPanels: View {
    @ObservedObject var store: CompanionStore
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if compact {
                VStack(alignment: .leading, spacing: 12) { lanes }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) { lanes }
                    VStack(alignment: .leading, spacing: 12) { lanes }
                }
            }
            Text("Independent answers. Agreement does not establish correctness, and neither model is being trained.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var lanes: some View {
        ComparisonReplyLane(store: store, provider: .qwen, compact: compact)
        ComparisonReplyLane(store: store, provider: .codex, compact: compact)
    }
}

@MainActor
private struct ComparisonReplyLane: View {
    @ObservedObject var store: CompanionStore
    let provider: AssistantProvider
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(provider == .qwen ? "Qwen · local" : "Codex · ChatGPT")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 4)
                if let lane = store.compareResults[provider], lane.state == .pending {
                    AssistantTaskCue(activity: lane.text.isEmpty ? .working : .responding,
                        quiet: store.preferences.quiet, reduceMotion: store.preferences.reduceMotion, showsLabel: false)
                }
            }
            if let lane = store.compareResults[provider] {
                Text(lane.text.isEmpty ? "No answer received." : lane.text)
                    .font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(lane.status).font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if provider == .qwen, lane.state == .complete {
                    HamptonReplyReferences(snapshot: store.hamptonSnapshot)
                }
                if provider == .qwen, lane.state == .complete, !lane.text.isEmpty {
                    QwenVoiceControls(voice: store.qwenVoice, text: lane.text, enabled: store.canReadAloud)
                }
                EvolutionReplyFeedback(store: store, provider: provider)
                LessonReplyControls(store: store, provider: provider)
                if let receipt = lane.receipt { AssistantReceiptDetails(receipt: receipt, onOpenGraph: { store.open(.nodeLab) }) }
            } else {
                Text(store.connection(for: provider) == .ready
                     ? "Ready for your next question."
                     : "Connect \(provider.name) before comparing.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(minWidth: compact ? 0 : 230, maxWidth: .infinity, alignment: .topLeading)
        .background(ArchiPalette.lilac.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(provider.name) comparison result")
    }
}

struct HamptonReplyReferences: View {
    let snapshot: HamptonAssistantSnapshot

    var body: some View {
        if let proposal = snapshot.proposal {
            VStack(alignment: .leading, spacing: 7) {
                if !proposal.uncertainty.isEmpty {
                    Text(proposal.uncertainty).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                let labels = proposal.sourceIDs.map { id in
                    id.hasPrefix("conversation-") ? "earlier Qwen conversation"
                        : id == "selected-passage" ? "selected passage" : id == "shared-copy" ? "shared copy" : "your message"
                }
                if !labels.isEmpty || !proposal.memoryIDs.isEmpty {
                    let lessons = proposal.memoryIDs.filter { $0.hasPrefix("kept-") }.count
                    let excerpts = proposal.memoryIDs.count - lessons
                    let memoryLabels = (lessons == 0 ? [] : ["\(lessons) kept lesson(s)"])
                        + (excerpts == 0 ? [] : ["\(excerpts) session excerpt(s)"])
                    Text("References: " + (labels + memoryLabels).joined(separator: ", "))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if proposal.kind != .answer {
                    Text(proposal.kind == .clarify ? "More context needed" : "Unable to answer from this context")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(ArchiPalette.violet)
                }
            }
        }
    }
}
