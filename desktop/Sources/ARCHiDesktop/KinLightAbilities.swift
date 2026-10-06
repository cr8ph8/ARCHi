import Foundation

/// Expressions of the companion's current body, never alternate bodies or upgrades
/// to identity, permissions, memory, or model capability.
enum KinLightMode: String, CaseIterable, Identifiable, Sendable {
    case rest, core, orbit, focus, pulse, delight, hold
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rest: "Resting"
        case .core: "Core glow"
        case .orbit: "Gather"
        case .focus: "Focus"
        case .pulse: "Respond"
        case .delight: "Delight"
        case .hold: "Hold"
        }
    }
    var colorName: String {
        switch self {
        case .rest, .core: "Warm gold"
        case .orbit: "Curious violet"
        case .focus: "Clear teal"
        case .pulse: "Warm rose"
        case .delight: "Bright mint"
        case .hold: "Soft amber"
        }
    }
    var rule: String {
        switch self {
        case .rest: "Your companion rests in the current body when no work is active, after Stop, or in Quiet mode."
        case .core: "A gentle glow from his existing core. Preview it here without sending a request."
        case .orbit: "The orbit gathers light while your companion prepares your reply."
        case .focus: "Optical petals focus when you ask your companion to focus on a selected passage."
        case .pulse: "A soft pulse follows the text arriving in your reply."
        case .delight: "Mint light opens when a completed answer is ready for you."
        case .hold: "Steady amber marks an answer that could not finish."
        }
    }
}

struct KinLightExpression: Equatable, Sendable {
    let mode: KinLightMode
    var isPreview = false
    static let resting = Self(mode: .rest)
    var label: String {
        (isPreview ? "Preview: " : "") + mode.title + (mode == .rest ? "" : " · " + mode.colorName)
    }
}

enum KinLightRules {
    static func resolve(activity: AssistantActivity, hasFreshFocus: Bool, preview: KinLightMode?,
                        visible: Bool, quiet: Bool, activeKin: Bool) -> KinLightExpression {
        guard activeKin, visible, !quiet else { return .resting }
        if hasFreshFocus { return .init(mode: .focus) }
        if activity == .working { return .init(mode: .orbit) }
        if activity == .responding { return .init(mode: .pulse) }
        if let preview { return .init(mode: preview, isPreview: true) }
        switch activity {
        case .ready: return .init(mode: .delight)
        case .failed: return .init(mode: .hold)
        default: return .resting
        }
    }
}

struct KinLightPreview: Equatable {
    static let lifetime: TimeInterval = 5
    let id: UUID
    let mode: KinLightMode
    let startedAt: TimeInterval
    let ticket: ContextTicket

    func isFresh(at now: TimeInterval, ticket: ContextTicket) -> Bool {
        self.ticket == ticket && now.isFinite && startedAt.isFinite && startedAt >= 0
            && now >= startedAt && now - startedAt < Self.lifetime
    }
}
