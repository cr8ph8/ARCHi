import SwiftUI

/// A presentation preference shared by every Seed. It grants no identity,
/// ability, growth or permission and leaves the authored Original untouched.
enum CompanionSeedColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case original, aqua, garnet, violet, gold, pearl

    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: "Original"
        case .aqua: "Green-blue"
        case .garnet: "Garnet"
        case .violet: "Violet"
        case .gold: "Warm gold"
        case .pearl: "Pearl"
        }
    }

    var hue: Double {
        switch self {
        case .original, .aqua: 0.475
        case .garnet: 0.967
        case .violet: 0.745
        case .gold: 0.105
        case .pearl: 0
        }
    }

    var accent: Color {
        switch self {
        case .original, .aqua: Color(red: 0.25, green: 0.79, blue: 0.71)
        case .garnet: Color(red: 0.72, green: 0.10, blue: 0.22)
        case .violet: Color(red: 0.59, green: 0.34, blue: 0.85)
        case .gold: Color(red: 0.92, green: 0.65, blue: 0.23)
        case .pearl: Color(red: 0.91, green: 0.92, blue: 0.94)
        }
    }
}

private struct CompanionSeedColorKey: EnvironmentKey {
    static let defaultValue = CompanionSeedColor.original
}

extension EnvironmentValues {
    var companionSeedColor: CompanionSeedColor {
        get { self[CompanionSeedColorKey.self] }
        set { self[CompanionSeedColorKey.self] = newValue }
    }
}

/// Used only on a Seed's local fallback drawing, never on its status/equipment
/// overlay. Hue rotation leaves white neutral and does not change geometry.
struct SeedFallbackColor: ViewModifier {
    let color: CompanionSeedColor
    var sourceHue: Double = 0.475

    @ViewBuilder func body(content: Content) -> some View {
        if color == .original { content }
        else if color == .pearl { content.saturation(0) }
        else { content.hueRotation(.degrees((color.hue - sourceHue) * 360)) }
    }
}
