import SwiftUI

/// Presentation groups reuse the existing destinations. They never copy profile
/// state or save a preference when a user moves between related screens.
enum WorkspaceNavigation {
    static let work: [WorkspaceSection] = [.home, .assistant, .context]
    static let companion: [WorkspaceSection] = [.appearance, .memory]
    static let explore: [WorkspaceSection] = [.unity, .marketplace]
    static let tools: [WorkspaceSection] = [.nodeLab, .steward, .capabilities]
    static var allSidebarDestinations: [WorkspaceSection] { work + companion + explore + tools + [.connections] }
    static let homeFeatureGroups: [(title: String, destinations: [WorkspaceSection])] = [
        ("Everyday", [.assistant, .context]),
        ("Your companion", [.appearance, .evolution, .memory]),
        ("Play & create", [.unity, .marketplace]),
        ("Make it yours", [.connections, .rhythm, .accessibility, .advanced]),
        ("More tools", [.nodeLab, .steward, .capabilities])
    ]
    static var allHomeFeatures: [WorkspaceSection] { homeFeatureGroups.flatMap(\.destinations) }

    static func title(for section: WorkspaceSection) -> String {
        switch section {
        case .home: "Home"
        case .assistant: "Chat"
        case .appearance: "My companion"
        case .memory: "Memories"
        case .unity: "Arena"
        case .nodeLab: "Activity map"
        case .steward: "Usage"
        case .capabilities: "ARC"
        case .connections: "Settings"
        case .evolution: "Growth"
        case .rhythm: "Conversation"
        case .accessibility: "Accessibility"
        default: section.rawValue
        }
    }

    static func parent(of section: WorkspaceSection) -> WorkspaceSection {
        switch section {
        case .evolution: .appearance
        case .rhythm, .accessibility, .advanced: .connections
        default: section
        }
    }

    static func tabs(for section: WorkspaceSection) -> [WorkspaceSection] {
        switch parent(of: section) {
        case .appearance: [.appearance, .evolution]
        case .connections: [.connections, .rhythm, .accessibility, .advanced]
        default: []
        }
    }

    static func tabTitle(_ section: WorkspaceSection) -> String {
        switch section {
        case .appearance: "Appearance"
        case .evolution: "Growth"
        case .connections: "Connections"
        case .rhythm: "Conversation"
        case .accessibility: "Comfort"
        case .advanced: "Advanced"
        default: section.rawValue
        }
    }
}

@MainActor
struct WorkspaceSectionTabs: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        let parent = WorkspaceNavigation.parent(of: store.section)
        let tabs = WorkspaceNavigation.tabs(for: parent)
        Picker("Workspace section", selection: Binding(get: { store.section }, set: { section in
            // AppKit can finish a segmented-control selection while SwiftUI
            // removes its page. Publish navigation after that layout turn.
            DispatchQueue.main.async {
                guard WorkspaceNavigation.parent(of: store.section) == parent,
                      tabs.contains(section) else { return }
                store.open(section)
            }
        })) {
            ForEach(tabs) { section in
                Text(WorkspaceNavigation.tabTitle(section)).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .id(WorkspaceNavigation.parent(of: store.section))
        .accessibilityIdentifier("workspace.section-tabs")
        .padding(.bottom, 2)
    }
}

/// A navigation row for related work. The destination owns the full controls.
@MainActor
struct WorkspaceRouteRow: View {
    let title: String
    let detail: String
    let icon: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon).font(.system(size: 19, weight: .light))
                    .foregroundStyle(WorkspaceTheme.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WorkspaceTheme.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(WorkspaceSurface())
        .accessibilityIdentifier(identifier)
    }
}
