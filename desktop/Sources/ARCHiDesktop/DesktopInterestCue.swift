import Foundation

/// A presentation of the existing acquisition session, never an observation or
/// a new source of permission. Selection and reading remain distinct steps.
struct DesktopInterestCue: Equatable, Sendable {
    let phase: DesktopInterestPhase
    let targetName: String?
    let outlineFrame: CGRect?

    init(phase: DesktopInterestPhase, target: DesktopInterestTarget?) {
        self.phase = phase
        targetName = target.map {
            $0.title.isEmpty ? $0.appName : $0.appName + " · " + $0.title
        }
        let isLive = phase == .aiming || phase == .targeted || phase == .reading
        outlineFrame = isLive && target.map({ DesktopInterestGeometry.valid($0.frame) }) == true
            ? target?.frame : nil
    }

    var title: String {
        switch phase {
        case .idle: "Choose a window"
        case .aiming: outlineFrame == nil ? "Pointing" : "Window in reach"
        case .targeted: "Window selected"
        case .reading: "Reading locally"
        case .review: "Snapshot ready"
        case .failed: "Read unavailable"
        }
    }

    var scope: String {
        switch phase {
        case .idle, .aiming, .targeted: "No content read"
        case .reading: "Only this window · no model request"
        case .review: "Captured copy · no live access"
        case .failed: "No snapshot adopted"
        }
    }

    var symbol: String {
        switch phase {
        case .idle, .aiming: "viewfinder"
        case .targeted: "scope"
        case .reading: "text.viewfinder"
        case .review: "doc.text"
        case .failed: "exclamationmark.circle"
        }
    }

    var accessibilityLabel: String { title + ". " + scope }

    func animates(quiet: Bool, reduceMotion: Bool, systemReduceMotion: Bool) -> Bool {
        phase == .reading && outlineFrame != nil && !quiet && !reduceMotion && !systemReduceMotion
    }

    /// A slow, bounded opacity cue. No position, scale, content or stored state
    /// is changed by a frame tick. A static cue is fully visible.
    static func opacity(at time: TimeInterval, animated: Bool) -> Double {
        guard animated, time.isFinite else { return 1 }
        let phase = time.truncatingRemainder(dividingBy: 2.8) / 2.8 * 2 * .pi
        return 0.84 + 0.16 * cos(phase)
    }
}
