import SwiftUI

/// Visiting this page never launches a game. Home, this page and app menus
/// all use the existing native connection owner for explicit play actions.
@MainActor
struct UnityWorkspace: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject private var connection: UnityPresentationConnection
    @ObservedObject private var evolution: EvolutionStore
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var setupExpanded = false

    init(store: CompanionStore, connection: UnityPresentationConnection? = nil) {
        self.store = store
        self.connection = connection ?? store.unityPresentation
        evolution = store.evolution
    }

    private var entry: ArenaEntryState { ArenaEntryState(store: store, connection: connection) }
    private var session: UnityWorkspaceState { UnityWorkspaceState(connection: connection) }
    private var still: Bool { systemReduceMotion || store.preferences.reduceMotion || store.preferences.quiet || !store.isVisible }
    private var roomAvailable: Bool {
        guard store.unityPresentationUnavailableReason(for: connection.availablePlayer) == nil, store.activeQiMon?.isValid == true, let app = connection.availablePlayer else { return false }
        return (store.preferences.seedAppearance == .kinParticles || UnityPresentationConnection.supportsSeedAppearances(app))
            && (store.preferences.equipment.design == nil || UnityPresentationConnection.supportsStaffRecipes(app))
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Arena").font(.system(size: 30, weight: .medium))
                        Text("Take a break. Try a round. Find your rhythm together.")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    arenaCard
                    if connection.isSharing { sessionStatus }
                    connectionDetails
                    companionRoom
                }
                .frame(maxWidth: 980)
                .padding(geometry.size.width < 800 ? 20 : 28)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("unity.workspace")
    }

    private var arenaCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("PRACTICE TOGETHER", systemImage: "gamecontroller")
                        .font(.system(size: 10, weight: .semibold)).tracking(1.2)
                        .foregroundStyle(WorkspaceTheme.accent)
                    Text(entry.title).font(.system(size: 24, weight: .medium))
                        .accessibilityIdentifier("arena.entry-title")
                    Text(entry.summary).font(.system(size: 13)).foregroundStyle(.secondary)
                        .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("arena.entry-summary")
                    if let item = store.preferences.equipment.item, store.activeQiMon != nil {
                        Label(item.title, systemImage: "tshirt").font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                companionPortrait
            }
            HStack(spacing: 14) {
                Button {
                    if entry.canEnter {
                        Task { await ArenaEntryAction.open(store: store, connection: connection) }
                    } else { setupExpanded = true }
                } label: {
                    Label(entry.actionTitle, systemImage: entry.canEnter ? "play.fill" : "wrench.and.screwdriver")
                        .frame(minWidth: 154)
                }
                .buttonStyle(WorkspaceActionStyle(prominent: true))
                .disabled(store.isShuttingDown)
                .accessibilityIdentifier("unity-area.open-arena")
                Text("Practice lasts for this session.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .modifier(WorkspaceSurface(emphasis: true))
    }

    private var companionPortrait: some View {
        VStack(spacing: 6) {
            if let companion = store.activeQiMon {
                CompanionPresenceArt(form: store.presentationForm, family: store.presentationFamily,
                    size: 112, reduceMotion: still, treatment: store.preferences.visualTreatment,
                    recipe: store.presentationRecipe, naturalVariation: store.presentationNaturalVariation,
                    equipment: store.preferences.equipment, lightExpression: store.kinLightExpression, seedColor: store.preferences.seedColor)
                    .frame(width: 128, height: 120)
                    .accessibilityLabel("\(companion.name), current appearance")
                Text(companion.name).font(.system(size: 12, weight: .medium))
                Text(store.kinBodyTitle)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("unity.current-body")
            } else {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 42, weight: .light)).foregroundStyle(WorkspaceTheme.accent)
                    .frame(width: 120, height: 120)
                    .background(WorkspaceTheme.accent.opacity(0.07), in: Circle())
                    .accessibilityHidden(true)
                Text("Practice roster").font(.system(size: 12, weight: .medium))
                Text("Ready to explore").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.frame(width: 142)
    }

    private var companionRoom: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Companion room", systemImage: "sparkles")
                .font(.system(size: 18, weight: .medium))
            Text(store.unityPresentationUnavailableReason(for: connection.availablePlayer) ?? (store.activeQiMon == nil
                 ? "Set up your companion to spend time together here. You can already try the practice roster in Arena."
                 : "A quieter place to spend time together, with your companion’s current look and motion settings."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("unity.profile-required")
            HStack(spacing: 18) {
                if store.activeQiMon == nil {
                    Button("Meet your companion") { store.open(.appearance) }
                        .buttonStyle(WorkspaceActionStyle())
                        .accessibilityIdentifier("arena.meet-companion")
                } else {
                    Button {
                        if !store.isVisible { store.showCompanion() }
                        Task { await connection.open(store: store, destination: .companion) }
                    } label: {
                        Label(!store.isVisible ? "Show & open room"
                            : connection.isSharing && connection.destination == .companion ? "Return to room" : "Open room",
                            systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(WorkspaceActionStyle())
                    .disabled(!roomAvailable || store.isShuttingDown)
                    .accessibilityIdentifier("unity-area.open")
                }
                Button("Change look") { store.open(.appearance) }
                    .accessibilityIdentifier("unity.open-appearance")
                Button("Find an outfit") { store.open(.marketplace) }
                    .accessibilityIdentifier("unity.open-marketplace")
            }.buttonStyle(.borderless).font(.system(size: 11))
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .modifier(WorkspaceSurface())
    }

    private var sessionStatus: some View {
        HStack(alignment: .center, spacing: 11) {
            Circle().fill(session.isFollowing ? WorkspaceTheme.positive : WorkspaceTheme.muted)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title).font(.system(size: 12, weight: .medium))
                    .accessibilityIdentifier("unity.session-state")
                Text(session.summary).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("End session", systemImage: "stop.fill") { connection.stop() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("unity-area.stop")
        }.padding(.horizontal, 3)
    }

    private var connectionDetails: some View {
        DisclosureGroup("Advanced", isExpanded: $setupExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Arena opens in its own window. Connect an ARCHi Arena app here if it isn’t included with this copy.")
                    .fixedSize(horizontal: false, vertical: true)
                if !connection.isSharing {
                    HStack(spacing: 16) {
                        Button("Choose Arena app…", systemImage: "folder") { connection.choosePlayer() }
                            .accessibilityIdentifier("unity-area.choose-player")
                        Button("Check again") { connection.refreshAvailability() }
                            .accessibilityIdentifier("arena.check-availability")
                        if let included = connection.includedPlayer, included != connection.selectedPlayer {
                            Button("Use included Arena") { connection.selectPlayer(included) }
                                .accessibilityIdentifier("arena.use-included")
                        }
                    }.buttonStyle(.borderless)
                }
                if let player = connection.availablePlayer {
                    Text(player == connection.includedPlayer ? "Included with this ARCHi app" : player.deletingPathExtension().lastPathComponent)
                        .help(player.path).accessibilityIdentifier("unity.player-availability")
                }
                Text(connection.status).accessibilityIdentifier("unity-area.status")
                Text("Arena receives your appearance and session controls. Your conversations, documents and memories stay in ARCHi. Practice does not change saved growth.")
                if connection.isSharing, let snapshot = connection.lastSnapshot {
                    Text("Session \(snapshot.sessionID.prefix(8)) · revision \(snapshot.revision) · \(session.isFollowing ? "acknowledged" : "waiting")")
                        .font(.system(size: 10, design: .monospaced))
                }
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.top, 12)
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("arena.advanced")
    }
}

/// A live area is reported only after the current session is acknowledged.
struct UnityWorkspaceState: Equatable {
    let title: String
    let summary: String
    let isFollowing: Bool

    @MainActor init(connection: UnityPresentationConnection) {
        isFollowing = connection.isSharing && connection.hasRenderAcknowledgment
            && connection.lastSnapshot?.active == true && connection.lastSnapshot?.visible == true
        if !connection.isSharing {
            title = "Ready when you are"
            summary = "Play a round or visit the companion room."
        } else if connection.lastSnapshot?.active == false {
            title = "Session paused"
            summary = "Show your companion to continue, or end the session."
        } else if connection.lastSnapshot?.visible == false {
            title = "Companion hidden"
            summary = "Show your companion to return to your session."
        } else if isFollowing {
            title = connection.destination == .arena ? "Arena is open" : "Companion room is open"
            summary = connection.isLocalPractice ? "You’re using the practice roster. This session won’t create a saved companion."
                : "Your companion’s current look and outfit are connected."
        } else {
            title = "Getting your session ready"
            summary = "If it takes longer, end the session and try again."
        }
    }
}
