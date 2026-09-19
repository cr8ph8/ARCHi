import SwiftUI

/// Passive navigation and explicit play share the existing session owner.
@MainActor
struct HomeUnityDestination: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject private var connection: UnityPresentationConnection

    init(store: CompanionStore) {
        self.store = store
        connection = store.unityPresentation
    }

    var body: some View {
        let entry = ArenaEntryState(store: store)
        HomeDestinationSurface(icon: "gamecontroller", title: "Arena") {
            Text("A little friendly competition.")
                .font(.system(size: 13)).foregroundStyle(WorkspaceTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("home.unity-destinations")
            Spacer(minLength: 4)
            Button {
                Task { await ArenaEntryAction.open(store: store) }
            } label: {
                Label(entry.canEnter ? entry.actionTitle : "Open Arena", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WorkspaceActionStyle(prominent: true))
            .disabled(store.isShuttingDown)
            .accessibilityIdentifier("home.play-arena")
            .help(entry.summary)
            Button("Arena & companion room") { store.open(.unity) }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(WorkspaceTheme.muted)
                .accessibilityIdentifier("home.unity")
        }
    }
}

@MainActor
struct HomeMarketplaceDestination: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        HomeDestinationSurface(icon: "bag", title: "Marketplace") {
            Text(store.preferences.equipment.item.map { "Wearing \($0.title). Find your next favorite." }
                 ?? "Find a new look, or create your own.")
                .font(.system(size: 13)).foregroundStyle(WorkspaceTheme.muted)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("home.marketplace-outfit")
            Spacer(minLength: 4)
            Button { store.open(.marketplace) } label: {
                Label("Browse designs", systemImage: "bag").frame(maxWidth: .infinity)
            }
            .buttonStyle(WorkspaceActionStyle())
            .accessibilityIdentifier("home.marketplace")
            Text(store.itemLibrary.isEmpty ? "Make something that feels like you." : "\(store.itemLibrary.count) \(store.itemLibrary.count == 1 ? "design" : "designs") in your collection")
                .font(.system(size: 11)).foregroundStyle(WorkspaceTheme.muted)
        }
    }
}

private struct HomeDestinationSurface<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(WorkspaceTheme.accent)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 192, alignment: .topLeading)
        .modifier(WorkspaceSurface())
    }
}
