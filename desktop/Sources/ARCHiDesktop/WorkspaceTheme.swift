import SwiftUI

enum WorkspaceAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Follow System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
    var appKitAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

struct WorkspaceAppearancePicker: View {
    @Binding var selection: WorkspaceAppearance

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Label("App appearance", systemImage: "circle.lefthalf.filled")
                    .font(.system(size: 14, weight: .medium))
                Text("Choose how your ARCHi workspace looks.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Picker("App appearance", selection: $selection) {
                ForEach(WorkspaceAppearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }
            .pickerStyle(.menu).labelsHidden().frame(width: 165)
            .accessibilityLabel("App appearance")
            .accessibilityValue(selection.title)
            .accessibilityIdentifier("workspace.appearance")
        }
    }
}

/// Workspace chrome is separate from the companion's own appearance palette.
enum WorkspaceTheme {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.43, green: 0.84, blue: 0.91, alpha: 1)
            : NSColor(calibratedRed: 0.35, green: 0.29, blue: 0.58, alpha: 1)
    })
    static let background = adaptive(light: NSColor(calibratedRed: 0.98, green: 0.976, blue: 0.99, alpha: 1),
                                     dark: NSColor(calibratedRed: 0.035, green: 0.061, blue: 0.073, alpha: 1))
    static let sidebar = adaptive(light: NSColor(calibratedRed: 0.94, green: 0.944, blue: 0.956, alpha: 1),
                                  dark: NSColor(calibratedRed: 0.044, green: 0.077, blue: 0.087, alpha: 1))
    static let panel = adaptive(light: .white,
                                dark: NSColor(calibratedRed: 0.064, green: 0.103, blue: 0.116, alpha: 1))
    static let line = accent.opacity(0.18)
    static let muted = adaptive(light: NSColor(calibratedRed: 0.37, green: 0.40, blue: 0.45, alpha: 1),
                                dark: NSColor(calibratedRed: 0.60, green: 0.70, blue: 0.72, alpha: 1))
    static let positive = adaptive(light: NSColor(calibratedRed: 0.20, green: 0.43, blue: 0.30, alpha: 1),
                                   dark: NSColor(calibratedRed: 0.52, green: 0.80, blue: 0.63, alpha: 1))
    static let corner: CGFloat = 16

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

struct WorkspaceSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    var emphasis = false

    func body(content: Content) -> some View {
        content
            .background {
                if colorScheme == .dark {
                    RoundedRectangle(cornerRadius: WorkspaceTheme.corner)
                        .fill(reduceTransparency ? WorkspaceTheme.panel : WorkspaceTheme.panel.opacity(0.88))
                } else {
                    RoundedRectangle(cornerRadius: WorkspaceTheme.corner).fill(.regularMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: WorkspaceTheme.corner)
                    .strokeBorder(WorkspaceTheme.accent.opacity(emphasis ? 0.30 : 0.16), lineWidth: 1)
            }
    }
}

struct WorkspaceActionStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 15).padding(.vertical, 10)
            .foregroundStyle(prominent ? (colorScheme == .dark ? WorkspaceTheme.background : .white) : WorkspaceTheme.accent)
            .background(prominent ? WorkspaceTheme.accent : WorkspaceTheme.accent.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(WorkspaceTheme.accent.opacity(prominent ? 0 : 0.24)))
            .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Hover is decorative. Selection and keyboard activation remain native buttons.
struct WorkspaceNavigationStyle: ButtonStyle {
    let selected: Bool
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        WorkspaceNavigationLabel(selected: selected, pressed: configuration.isPressed, reduceMotion: reduceMotion) {
            configuration.label
        }
    }
}

private struct WorkspaceNavigationLabel<Content: View>: View {
    let selected: Bool
    let pressed: Bool
    let reduceMotion: Bool
    @ViewBuilder let content: Content
    @State private var hovered = false

    var body: some View {
        content
            .padding(.horizontal, 12).padding(.vertical, 10)
            .foregroundStyle(selected ? WorkspaceTheme.accent : Color.primary.opacity(0.78))
            .background(WorkspaceTheme.accent.opacity(selected ? 0.13 : hovered ? 0.065 : 0),
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(WorkspaceTheme.accent.opacity(selected ? 0.28 : 0)))
            .opacity(pressed ? 0.65 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selected)
    }
}

struct WorkspaceEyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .medium)).tracking(1.5)
            .foregroundStyle(WorkspaceTheme.accent)
    }
}
