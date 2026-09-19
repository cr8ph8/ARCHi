import AppKit
import Combine
import SwiftUI

enum CompanionChatEdge: Equatable, Sendable { case leading, trailing, top, bottom }

struct CompanionChatLayout: Equatable, Sendable {
    let frame: CGRect
    let edge: CompanionChatEdge
    /// Offset in SwiftUI's top-left coordinate space along the attachment edge.
    let tipOffset: CGFloat

    var contentInsets: EdgeInsets {
        EdgeInsets(top: edge == .top ? 25 : 13, leading: edge == .leading ? 25 : 13,
                   bottom: edge == .bottom ? 25 : 13, trailing: edge == .trailing ? 25 : 13)
    }
}

/// Places only the bubble. If no readable bubble fits without covering ARCHi,
/// the caller opens the existing full Assistant instead of moving the character.
enum CompanionChatPlacement {
    static let preferredSize = CGSize(width: 390, height: 530)
    static let minimumSize = CGSize(width: 300, height: 500)
    static let gap: CGFloat = 7

    static func layout(companion: CGRect, screens: [CGRect]) -> CompanionChatLayout? {
        func valid(_ rect: CGRect) -> Bool {
            [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
                && !rect.isEmpty && !rect.isNull && !rect.isInfinite
        }
        guard valid(companion) else { return nil }
        let center = CGPoint(x: companion.midX, y: companion.midY)
        let screens = screens.filter(valid)
        guard let screen = screens.first(where: { $0.contains(center) }) ?? screens.max(by: {
            area($0.intersection(companion)) < area($1.intersection(companion))
        }), screen.intersects(companion) else { return nil }
        let safe = screen.insetBy(dx: 8, dy: 8)
        let choices: [(CompanionChatEdge, CGFloat, CGFloat)] = [
            (.leading, safe.maxX - companion.maxX - gap, safe.height),
            (.trailing, companion.minX - safe.minX - gap, safe.height),
            (.bottom, safe.width, safe.maxY - companion.maxY - gap),
            (.top, safe.width, companion.minY - safe.minY - gap)
        ]
        var best: CompanionChatLayout?
        for (edge, availableWidth, availableHeight) in choices {
            let width = min(preferredSize.width, availableWidth)
            let height = min(preferredSize.height, availableHeight)
            guard width >= minimumSize.width, height >= minimumSize.height else { continue }
            let x: CGFloat, y: CGFloat
            switch edge {
            case .leading: x = companion.maxX + gap; y = center.y - height / 2
            case .trailing: x = companion.minX - gap - width; y = center.y - height / 2
            case .bottom: x = center.x - width / 2; y = companion.maxY + gap
            case .top: x = center.x - width / 2; y = companion.minY - gap - height
            }
            let frame = CGRect(x: min(max(x, safe.minX), safe.maxX - width),
                y: min(max(y, safe.minY), safe.maxY - height), width: width, height: height)
            guard safe.contains(frame), !frame.intersects(companion) else { continue }
            let vertical = edge == .leading || edge == .trailing
            let offset = vertical ? frame.maxY - center.y : center.x - frame.minX
            let tip = min(max(offset, 30), (vertical ? height : width) - 30)
            let candidate = CompanionChatLayout(frame: frame, edge: edge, tipOffset: tip)
            // Prefer full readable space; stable right/left/above/below order
            // breaks ties without making the bubble jump between equal choices.
            if best == nil || area(frame) > area(best!.frame) { best = candidate }
        }
        return best
    }

    private static func area(_ frame: CGRect) -> CGFloat {
        frame.isNull || frame.isEmpty ? 0 : frame.width * frame.height
    }
}

private final class CompanionChatPanel: NSPanel {
    var dismiss: (() -> Void)?
    var cancelVoiceOnResignKey: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { dismiss?() }
    override func resignKey() {
        super.resignKey()
        cancelVoiceOnResignKey?()
    }
}

/// Owns the presentation/focus edge only. Draft, route, connections, requests,
/// cancellation, result validation and memory remain in CompanionStore.
@MainActor
final class CompanionChatBubbleController {
    let window: NSPanel
    private weak var companionWindow: NSWindow?
    private let store: CompanionStore
    private var hosting: NSHostingView<CompanionChatBubble>?
    private var focusRequest = 0
    private var lessonDraftSubscription: AnyCancellable?

    init(store: CompanionStore, companionWindow: NSWindow) {
        self.store = store
        self.companionWindow = companionWindow
        let panel = CompanionChatPanel(contentRect: CGRect(origin: .zero, size: CompanionChatPlacement.preferredSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window = panel
        panel.title = "Chat with ARCHi"
        panel.identifier = NSUserInterfaceItemIdentifier("archi.companionChat")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.dismiss = { [weak self] in self?.dismiss() }
        // A nonactivating panel can lose keyboard focus without the app itself
        // resigning active. Its own microphone session must stop on that edge.
        panel.cancelVoiceOnResignKey = { [weak store] in store?.voiceInput.cancel(ifOwnedBy: .bubble) }
        // Both single-provider and Compare controls use the existing lesson
        // owner. Dismiss on the draft event itself, even when Memory was already
        // selected and its section does not change. The sole editor stays there.
        lessonDraftSubscription = store.$lessonDraft.dropFirst().sink { [weak self] draft in
            if draft != nil { self?.dismiss() }
        }
    }

    /// Does not order a window, activate the app, or call any assistant.
    @discardableResult
    func prepare(screens: [CGRect]) -> Bool {
        guard let parent = companionWindow,
              let layout = CompanionChatPlacement.layout(companion: parent.frame, screens: screens) else { return false }
        let view = CompanionChatBubble(store: store, layout: layout, focusRequest: focusRequest,
            dismiss: { [weak self] in self?.dismiss() },
            openAssistant: { [weak self] in self?.openAssistant() },
            openLessons: { [weak self] in self?.openLessons() })
        if let hosting { hosting.rootView = view }
        else {
            let host = NSHostingView(rootView: view)
            hosting = host; window.contentView = host
        }
        window.setFrame(layout.frame, display: window.isVisible, animate: false)
        return true
    }

    @discardableResult
    func show() -> Bool {
        guard store.isVisible, !store.isShuttingDown, let parent = companionWindow, parent.isVisible else { return false }
        focusRequest &+= 1
        guard prepare(screens: NSScreen.screens.map(\.visibleFrame)) else { return false }
        if window.parent !== parent { parent.addChildWindow(window, ordered: .above) }
        // Opening is an explicit click/keyboard action, so taking text focus is
        // intentional. Merely showing the companion still never takes focus.
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func followCompanion() {
        guard window.isVisible else { return }
        if !prepare(screens: NSScreen.screens.map(\.visibleFrame)) { dismiss() }
    }

    func dismiss() {
        store.voiceInput.cancel(ifOwnedBy: .bubble)
        window.orderOut(nil)
        window.parent?.removeChildWindow(window)
    }

    func openAssistant() {
        dismiss()
        store.open(.assistant)
    }

    func openLessons() {
        dismiss()
        guard !store.isShuttingDown else { return }
        store.open(.memory)
    }
}

/// Question/command text uses the exact same request path as the full Assistant.
/// Voice enters only the shared draft; this view never interprets commands.
@MainActor
struct CompanionChatBubble: View {
    @ObservedObject var store: CompanionStore
    let layout: CompanionChatLayout
    let focusRequest: Int
    let dismiss: () -> Void
    let openAssistant: () -> Void
    let openLessons: () -> Void
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right").foregroundStyle(ArchiPalette.violet)
                Text(store.activeQiMon.map { "\($0.name) · ARCHi" } ?? "ARCHi")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
                AssistantTaskCue(activity: store.assistantActivity, quiet: store.preferences.quiet,
                                 reduceMotion: store.preferences.reduceMotion)
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).accessibilityLabel("Close chat bubble")
                    .accessibilityIdentifier("companion-chat.close")
            }
            ScrollViewReader { scroll in
              ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if store.desktopInterest.phase != .idle {
                        DesktopInterestCard(store: store)
                    }
                    VoiceTranscriptPreview(voice: store.voiceInput).id("companion-chat.voice-review")
                    AssistantRouteSelector(store: store, compact: true)
                    DesktopInterestSharingNotice(store: store)
                    Text(sharedContextDisclosure).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("companion-chat.shared-context")
                    Text("Next reply · " + store.nextReplySettings.summary)
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Button(store.route == .codex ? "Kept lessons · local Qwen only"
                        : store.nextReplyLessons.isEmpty ? "Kept lessons · none for this reply"
                        : "Kept lessons · \(store.nextReplyLessons.count) for local Qwen", action: openLessons)
                        .buttonStyle(.borderless).font(.system(size: 10))
                        .disabled(store.isShuttingDown)
                        .accessibilityIdentifier("companion-chat.lessons")
                        .help("Inspect, correct or withdraw lessons in What I remember. Matched lessons: "
                            + store.nextReplyLessons.map(\.topic).joined(separator: ", ")
                            + ". Kept lessons stay on this Mac; opening them makes no model call.")
                    Text(store.nextCallBudget).font(.system(size: 10)).foregroundStyle(.secondary)
                    if store.requestsRevision {
                        Label("Revision mode · review and apply in the full Assistant", systemImage: "pencil")
                            .font(.system(size: 11)).foregroundStyle(ArchiPalette.violet)
                    }
                    Divider()
                    replies
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
              .onChange(of: store.voiceInput.phase) { _, phase in
                  if phase == .review { scroll.scrollTo("companion-chat.voice-review", anchor: .top) }
              }
            }
            .frame(minHeight: 65, maxHeight: .infinity)
            Divider()
            HStack {
                AssistantComposerConnections(store: store)
                ARCActiveAssistantActions(store: store)
            }
            TextField("Ask a question or describe a task…", text: $store.prompt, axis: .vertical)
                .font(.system(size: 13)).textFieldStyle(.plain).lineLimit(2...3)
                .focused($composerFocused)
                .padding(9)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.primary.opacity(0.14)))
                .accessibilityLabel("Message to ARCHi")
                .accessibilityIdentifier("companion-chat.prompt")
            VoiceInputControls(store: store, surface: .bubble)
            Text(store.status).font(.system(size: 10)).foregroundStyle(.secondary)
                .lineLimit(2).help(store.status)
                .accessibilityIdentifier("companion-chat.submission-status")
            HStack(alignment: .center, spacing: 8) {
                Button("Full Assistant", systemImage: "arrow.up.left.and.arrow.down.right", action: openAssistant)
                    .buttonStyle(.borderless).font(.system(size: 11))
                    .accessibilityIdentifier("companion-chat.full-assistant")
                Spacer(minLength: 0)
                if store.isWorking {
                    Button("Stop", systemImage: "stop.fill") { store.cancelWork() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("companion-chat.stop")
                } else {
                    Button("Send", systemImage: "arrow.up") { store.submit() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!AssistantComposerState(store: store).canSend)
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityIdentifier("companion-chat.send")
                }
            }
            Text("⌘ Return sends · Escape closes · closing keeps your draft")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .controlSize(.small)
        .padding(layout.contentInsets)
        .background(CompanionChatBubbleShape(edge: layout.edge, tipOffset: layout.tipOffset)
            .fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(CompanionChatBubbleShape(edge: layout.edge, tipOffset: layout.tipOffset)
            .stroke(ArchiPalette.violet.opacity(0.35), lineWidth: 1))
        .onExitCommand(perform: dismiss)
        .task(id: focusRequest) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            composerFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ARCHi attached chat")
    }

    private var sharedContextDisclosure: String {
        if let name = store.sourceName {
            return "Includes the full shared copy: \(name)." + (store.textSelection == nil ? "" : " A selected passage is also marked.")
        }
        return "No document shared. Send uses your message and current reply settings."
    }

    @ViewBuilder private var replies: some View {
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
            ComparisonReplyPanels(store: store, compact: true)
        } else if let result = store.compareResults[store.assistantProvider] {
            VStack(alignment: .leading, spacing: 8) {
                Text(result.text.isEmpty ? result.status : result.text)
                    .font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("companion-chat.reply")
                if store.assistantProvider == .qwen { HamptonReplyReferences(snapshot: store.hamptonSnapshot) }
                if result.revision != nil {
                    Button("Review revision in Assistant", action: openAssistant).buttonStyle(.borderless)
                }
                DocumentReadingFeedback(store: store, provider: store.assistantProvider)
                LessonReplyControls(store: store, provider: store.assistantProvider)
                if let receipt = result.receipt {
                    DisclosureGroup("Reply details") { AssistantReceiptDetails(receipt: receipt, onOpenGraph: { store.open(.nodeLab) }) }
                        .font(.system(size: 10))
                }
            }
        } else {
            Text(store.isWorking ? store.status : "What would you like to work on?")
                .font(.system(size: 14)).foregroundStyle(.secondary)
                .padding(.vertical, 12)
        }
    }
}

/// A single closed outline avoids a seam across the tail's base. The pointer is
/// entirely inside the bubble window, directed toward the unchanged companion.
struct CompanionChatBubbleShape: Shape {
    let edge: CompanionChatEdge
    let tipOffset: CGFloat
    func path(in rect: CGRect) -> Path {
        let tail: CGFloat = 12, radius: CGFloat = 16, half: CGFloat = 7
        let body = CGRect(x: rect.minX + (edge == .leading ? tail : 0),
            y: rect.minY + (edge == .top ? tail : 0),
            width: rect.width - (edge == .leading || edge == .trailing ? tail : 0),
            height: rect.height - (edge == .top || edge == .bottom ? tail : 0))
        var p = Path()
        p.move(to: CGPoint(x: body.minX + radius, y: body.minY))
        if edge == .top {
            p.addLine(to: CGPoint(x: tipOffset - half, y: body.minY))
            p.addLine(to: CGPoint(x: tipOffset, y: rect.minY))
            p.addLine(to: CGPoint(x: tipOffset + half, y: body.minY))
        }
        p.addLine(to: CGPoint(x: body.maxX - radius, y: body.minY))
        p.addQuadCurve(to: CGPoint(x: body.maxX, y: body.minY + radius), control: CGPoint(x: body.maxX, y: body.minY))
        if edge == .trailing {
            p.addLine(to: CGPoint(x: body.maxX, y: tipOffset - half))
            p.addLine(to: CGPoint(x: rect.maxX, y: tipOffset))
            p.addLine(to: CGPoint(x: body.maxX, y: tipOffset + half))
        }
        p.addLine(to: CGPoint(x: body.maxX, y: body.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: body.maxX - radius, y: body.maxY), control: CGPoint(x: body.maxX, y: body.maxY))
        if edge == .bottom {
            p.addLine(to: CGPoint(x: tipOffset + half, y: body.maxY))
            p.addLine(to: CGPoint(x: tipOffset, y: rect.maxY))
            p.addLine(to: CGPoint(x: tipOffset - half, y: body.maxY))
        }
        p.addLine(to: CGPoint(x: body.minX + radius, y: body.maxY))
        p.addQuadCurve(to: CGPoint(x: body.minX, y: body.maxY - radius), control: CGPoint(x: body.minX, y: body.maxY))
        if edge == .leading {
            p.addLine(to: CGPoint(x: body.minX, y: tipOffset + half))
            p.addLine(to: CGPoint(x: rect.minX, y: tipOffset))
            p.addLine(to: CGPoint(x: body.minX, y: tipOffset - half))
        }
        p.addLine(to: CGPoint(x: body.minX, y: body.minY + radius))
        p.addQuadCurve(to: CGPoint(x: body.minX + radius, y: body.minY), control: CGPoint(x: body.minX, y: body.minY))
        p.closeSubpath()
        return p
    }
}
