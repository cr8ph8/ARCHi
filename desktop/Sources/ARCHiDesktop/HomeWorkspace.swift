import SwiftUI

/// Home reads existing owners. Connections, play and changes still require an
/// explicit action; simply visiting this page creates no companion or save.
@MainActor
struct HomeWorkspace: View {
    @ObservedObject var store: CompanionStore
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var companionName: String { store.activeQiMon?.name ?? "ARCHi" }
    private var still: Bool { systemReduceMotion || store.preferences.reduceMotion || store.preferences.quiet }

    static func chatStatus(_ state: AssistantConnectionState) -> String {
        switch state {
        case .disconnected: "Set up chat"
        case .connecting: "Connecting…"
        case .ready: "Ready to chat"
        case .failed: "Chat needs attention"
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    introduction
                    companionStage
                    HStack(alignment: .top, spacing: 16) {
                        HomeUnityDestination(store: store)
                        HomeMarketplaceDestination(store: store)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your space").font(.system(size: 16, weight: .medium))
                        HStack(alignment: .top, spacing: 16) {
                            contextPanel
                            memoryPanel
                        }
                    }.padding(.top, 4)
                    arcEntry
                    HomeFeatureDirectory(store: store).padding(.top, 6)
                }
                .frame(maxWidth: 1080)
                .padding(geometry.size.width < 800 ? 20 : 28)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.workspace")
    }

    private var introduction: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Here, with you.").font(.system(size: 27, weight: .medium, design: .rounded))
                Text("Talk, create, or take a break.")
                    .font(.system(size: 13)).foregroundStyle(WorkspaceTheme.muted)
            }
            Spacer(minLength: 8)
            Button { store.open(.connections) } label: {
                HStack(spacing: 7) {
                    Circle().fill(store.connectionState == .ready ? WorkspaceTheme.positive : WorkspaceTheme.muted)
                        .frame(width: 6, height: 6)
                    Text(Self.chatStatus(store.connectionState))
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium))
                }
            }
            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(WorkspaceTheme.muted)
            .accessibilityLabel("Chat connection")
            .accessibilityValue(Self.chatStatus(store.connectionState))
            .accessibilityIdentifier("home.connections")
            .help("Manage your chat connection")
        }
    }

    private var companionStage: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(WorkspaceTheme.accent.opacity(0.06)).frame(width: 112, height: 112)
                CompanionPresenceArt(form: store.presentationForm, family: store.presentationFamily,
                    size: 108, reduceMotion: still,
                    treatment: store.preferences.visualTreatment, recipe: store.presentationRecipe,
                    naturalVariation: store.presentationNaturalVariation, equipment: store.preferences.equipment,
                    lightExpression: store.kinLightExpression, seedColor: store.preferences.seedColor)
                    .accessibilityLabel("\(companionName), current companion appearance")
            }.frame(width: 116, height: 116)
            VStack(alignment: .leading, spacing: 8) {
                Text(companionName).font(.system(size: 24, weight: .medium, design: .rounded))
                Text(store.isVisible ? "Your companion on the desktop" : "Your companion is taking a break")
                    .font(.system(size: 12)).foregroundStyle(WorkspaceTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if store.assistantActivity != .idle {
                    Text(store.assistantActivity.title)
                        .font(.system(size: 12)).foregroundStyle(WorkspaceTheme.accent)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 12) {
                Button { store.open(.assistant) } label: {
                    Label("Let's talk", systemImage: "bubble.left.and.bubble.right")
                }
                .buttonStyle(WorkspaceActionStyle(prominent: true))
                .accessibilityLabel("Talk with \(companionName)")
                .accessibilityIdentifier("home.ask")
                Button("Customize", systemImage: "slider.horizontal.3") { store.open(.appearance) }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(WorkspaceTheme.accent)
                    .accessibilityIdentifier("home.appearance")
                    .help("Your companion's appearance and growth")
            }
        }
        .padding(18)
        .background {
            RadialGradient(colors: [WorkspaceTheme.accent.opacity(0.09), .clear],
                           center: .leading, startRadius: 20, endRadius: 380)
        }
        .modifier(WorkspaceSurface(emphasis: true))
        .clipShape(RoundedRectangle(cornerRadius: WorkspaceTheme.corner))
    }

    private var arcEntry: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 24, weight: .light)).foregroundStyle(WorkspaceTheme.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text("ARC works with ARCHi").font(.system(size: 14, weight: .medium))
                Text("Use ARC from Chat, Work together or your Seed. Grid reasoning and interactive actions share task controls, evidence, Usage and the Activity map.")
                    .font(.system(size: 12)).foregroundStyle(WorkspaceTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            ARCActiveAssistantActions(store: store)
            Button("Manage ARC", systemImage: "arrow.right") { store.open(.capabilities) }
                .buttonStyle(WorkspaceActionStyle())
                .accessibilityIdentifier("home.arc-lab")
        }.padding(18).modifier(WorkspaceSurface())
    }

    private var contextPanel: some View {
        HomePersonalCard(title: store.sourceName == nil ? "Work together" : "Continue together", icon: "doc.text") {
            Text(store.sourceName ?? "Bring something you're working on.")
                .font(.system(size: 13, weight: .medium)).lineLimit(2)
                .help(store.sourceName ?? "Choose a document to read or refine with ARCHi")
            Text(store.sourceName == nil ? "Read, write, and refine with a little help." : "Your draft is right where you left it.")
                .font(.system(size: 12)).foregroundStyle(WorkspaceTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button { store.open(.context) } label: {
                HStack { Text(store.sourceName == nil ? "Choose a document" : "Open document"); Spacer(); Image(systemName: "arrow.right") }
            }
            .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(WorkspaceTheme.accent)
            .accessibilityIdentifier("home.document")
        }
    }

    private var memoryPanel: some View {
        TimelineView(.periodic(from: .now, by: 30)) { time in
            let lessons = store.keptLessons.filter { $0.isValid && ($0.expiresAt.map { $0 > time.date } ?? true) }
            HomePersonalCard(title: "Memories", icon: "bookmark") {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(lessons.count)").font(.system(size: 17, weight: .medium, design: .rounded))
                        .accessibilityIdentifier("home.lesson-count")
                    Text(lessons.count == 1 ? "thing you've kept" : "things you've kept")
                        .font(.system(size: 12)).foregroundStyle(WorkspaceTheme.muted)
                }
                if let latest = lessons.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
                    Text(latest.topic).font(.system(size: 12)).foregroundStyle(WorkspaceTheme.muted).lineLimit(2)
                } else {
                    Text("Keep the details you'd like ARCHi to remember.")
                        .font(.system(size: 12)).foregroundStyle(WorkspaceTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Button { store.open(.memory) } label: {
                    HStack { Text("View memories"); Spacer(); Image(systemName: "arrow.right") }
                }
                .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(WorkspaceTheme.accent)
                .accessibilityIdentifier("home.memory")
            }
        }
    }
}

private struct HomePersonalCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.system(size: 14, weight: .medium))
            content
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 170, alignment: .topLeading)
        .modifier(WorkspaceSurface())
    }
}
