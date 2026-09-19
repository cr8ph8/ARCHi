import SwiftUI

/// A complete directory of existing screens, including those grouped in tabs.
/// Navigation uses the same store as the sidebar and never starts a service.
@MainActor
struct HomeFeatureDirectory: View {
    @ObservedObject var store: CompanionStore

    static func identifier(for section: WorkspaceSection) -> String { "home.feature.\(section.id)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("All features").font(.system(size: 20, weight: .medium, design: .rounded))
                Text("Everything in one place.").font(.system(size: 13)).foregroundStyle(WorkspaceTheme.muted)
            }
            ForEach(WorkspaceNavigation.homeFeatureGroups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.title).font(.system(size: 12, weight: .medium)).foregroundStyle(WorkspaceTheme.muted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], spacing: 10) {
                        ForEach(group.destinations) { section in
                            let detail = Self.detail(for: section)
                            Button { store.open(section) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: detail.icon).font(.system(size: 17))
                                        .foregroundStyle(WorkspaceTheme.accent).frame(width: 24)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(WorkspaceNavigation.title(for: section)).font(.system(size: 13, weight: .medium))
                                        Text(detail.subtitle).font(.system(size: 11)).foregroundStyle(WorkspaceTheme.muted)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(WorkspaceTheme.muted)
                                }
                                .padding(13).frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
                                .contentShape(RoundedRectangle(cornerRadius: WorkspaceTheme.corner))
                            }
                            .buttonStyle(.plain).modifier(WorkspaceSurface())
                            .accessibilityIdentifier(Self.identifier(for: section))
                            .accessibilityLabel(WorkspaceNavigation.title(for: section))
                            .accessibilityHint(detail.subtitle)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.all-features")
    }

    private static func detail(for section: WorkspaceSection) -> (icon: String, subtitle: String) {
        switch section {
        case .assistant: ("bubble.left.and.bubble.right", "Start or continue a chat")
        case .context: ("doc.text", "Read, write, and refine")
        case .appearance: ("paintpalette", "Looks, outfits, and presence")
        case .evolution: ("sparkles", "Your companion's journey")
        case .memory: ("bookmark", "The details you've kept")
        case .unity: ("gamecontroller", "Play or visit the companion room")
        case .marketplace: ("bag", "Discover, create, and share designs")
        case .connections: ("point.3.connected.trianglepath.dotted", "Connect your assistant")
        case .rhythm: ("waveform", "Tone, reply length, and quiet mode")
        case .accessibility: ("accessibility", "Motion, contrast, and comfort")
        case .advanced: ("slider.horizontal.3", "Privacy, storage, and diagnostics")
        case .nodeLab: ("point.3.filled.connected.trianglepath.dotted", "Explore connected activity")
        case .steward: ("chart.bar", "Review activity and usage")
        case .capabilities: ("checkmark.shield", "Explore capability checks")
        case .home, .play: ("house", "Your workspace")
        }
    }
}
