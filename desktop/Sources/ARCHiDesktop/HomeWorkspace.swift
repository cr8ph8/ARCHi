import SwiftUI

/// Home reads existing owners. Connections, play and changes still require an
/// explicit action; simply visiting this page creates no companion or save.
@MainActor
struct HomeWorkspace: View {
    @ObservedObject var store: CompanionStore
    @State private var showsShowcase = false
    @State private var showsAllFeatures = false
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
                    companionStage
                    HomeMemoryMapCard(store: store, onExplore: { store.openMemoryMap() },
                                      onShowcase: { showsShowcase = true })
                    HomeWorkSummaryCard(store: store)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            HomeUnityDestination(store: store).frame(minWidth: 255)
                            HomeMarketplaceDestination(store: store).frame(minWidth: 255)
                        }
                        VStack(spacing: 12) {
                            HomeUnityDestination(store: store)
                            HomeMarketplaceDestination(store: store)
                        }
                    }
                    DisclosureGroup(isExpanded: $showsAllFeatures) {
                        HomeFeatureDirectory(store: store).padding(.top, 16)
                    } label: {
                        Label("Explore all features", systemImage: "square.grid.2x2")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .tint(WorkspaceTheme.accent)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("home.features-disclosure")
                }
                .frame(maxWidth: 1080)
                .padding(geometry.size.width < 800 ? 20 : 28)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showsShowcase) {
            VStack(spacing: 0) {
                HStack {
                    Label("Your local memory", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(WorkspaceTheme.muted)
                    Spacer()
                    Button("Close", systemImage: "xmark") { showsShowcase = false }
                        .keyboardShortcut("w", modifiers: .command)
                        .accessibilityIdentifier("home.showcase-close")
                }.padding(.horizontal, 20).padding(.vertical, 12)
                CompanionGraphWorkspace(store: store, initialShowcase: true)
            }
            .frame(minWidth: 720, idealWidth: 1040, minHeight: 560, idealHeight: 740)
            .background(WorkspaceTheme.background)
        }
        .onChange(of: store.section) { _, section in
            if section != .home { showsShowcase = false }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.workspace")
    }

    private var companionStage: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                WorkspaceEyebrow(text: "With \(companionName)")
                Text("Think together.\nKeep what matters.")
                    .font(.system(size: 32, weight: .medium, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                Text("A helping hand for your work. A memory you can explore.")
                    .font(.system(size: 13)).foregroundStyle(WorkspaceTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Button { store.open(.assistant) } label: {
                        Label(AskARCHiBrand.title, systemImage: "bubble.left.and.bubble.right")
                    }
                    .buttonStyle(WorkspaceActionStyle(prominent: true))
                    .accessibilityLabel(AskARCHiBrand.title)
                    .accessibilityIdentifier("home.ask")
                    Button { store.open(.connections) } label: {
                        HStack(spacing: 6) {
                            Circle().fill(store.connectionState == .ready ? WorkspaceTheme.positive : WorkspaceTheme.muted)
                                .frame(width: 5, height: 5)
                            Text(Self.chatStatus(store.connectionState))
                        }
                    }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(WorkspaceTheme.muted)
                    .accessibilityLabel("Ask ARCHi connection")
                    .accessibilityValue(Self.chatStatus(store.connectionState))
                    .accessibilityIdentifier("home.connections")
                    .help("Manage the connection used by Ask ARCHi")
                }
                if store.assistantActivity != .idle {
                    Text(store.assistantActivity.title).font(.system(size: 12))
                        .foregroundStyle(WorkspaceTheme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 8) {
                CompanionPresenceArt(form: store.presentationForm, family: store.presentationFamily,
                    size: 112, reduceMotion: still,
                    treatment: store.preferences.visualTreatment, recipe: store.presentationRecipe,
                    naturalVariation: store.presentationNaturalVariation, equipment: store.preferences.equipment,
                    lightExpression: store.kinLightExpression, seedColor: store.preferences.seedColor)
                    .frame(width: 128, height: 128)
                    .background {
                        Circle().fill(store.preferences.seedColor.accent.opacity(0.07))
                    }
                    .accessibilityLabel("\(companionName), current companion appearance")
                Button("My companion", systemImage: "slider.horizontal.3") { store.open(.appearance) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(WorkspaceTheme.accent)
                    .accessibilityIdentifier("home.appearance")
                    .help("Your companion's appearance and growth")
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }
}
