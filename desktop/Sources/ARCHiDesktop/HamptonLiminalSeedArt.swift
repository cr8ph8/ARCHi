import SwiftUI

/// Presentation of the reviewed Liminal Seed. The existing Seed clock controls
/// its gentle motion; this view owns no identity, potential or growth state.
struct HamptonLiminalSeedArt: View {
    let size: CGFloat
    let reduceMotion: Bool
    var lightExpression: KinLightExpression = .resting
    var seedColor: CompanionSeedColor = .original
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var motion: KinSeedMotion?

    private var policy: KinSeedMotion.Policy {
        .init(mode: lightExpression.mode, reduceMotion: reduceMotion, systemReduceMotion: systemReduceMotion)
    }

    var body: some View {
        let still = reduceMotion || systemReduceMotion
        TimelineView(.animation(minimumInterval: 1 / 24, paused: still)) { _ in
            let angle = still ? 0 : motion?.sample(at: ProcessInfo.processInfo.systemUptime).angle ?? 0
            Group {
                if let image = SeedColorRendering.image(for: .hamptonSeed, color: seedColor) {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                } else {
                    HamptonLiminalSeedFallback(seedColor: seedColor)
                }
            }
            .rotationEffect(.degrees(angle))
            .frame(width: size, height: size)
            .overlay {
                if lightExpression.mode != .rest {
                    KinLightEffects(expression: lightExpression, size: size, reduceMotion: still, centerY: 0.5)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
        }
        .frame(width: size, height: size)
        .transaction { $0.animation = nil }
        .onChange(of: policy, initial: true) { _, value in
            let now = ProcessInfo.processInfo.systemUptime
            if motion == nil { motion = KinSeedMotion(at: now, policy: value) }
            else { motion?.transition(to: value, at: now) }
        }
        .accessibilityLabel(CompanionVisualAsset.label(form: .hamptonSeed, family: nil, treatment: .original, seedColor: seedColor))
    }
}

/// A distinct local fallback. Missing artwork must not turn this Seed into KIN.
private struct HamptonLiminalSeedFallback: View {
    let seedColor: CompanionSeedColor
    var body: some View {
        GeometryReader { geometry in
            let unit = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle().fill(RadialGradient(colors: [.white,
                    seedColor == .original ? Color(red: 0.54, green: 0.87, blue: 0.88) : Color(hue: seedColor.hue, saturation: seedColor == .pearl ? 0 : 0.55, brightness: 0.87),
                    seedColor == .original ? Color(red: 0.11, green: 0.34, blue: 0.48) : Color(hue: seedColor.hue, saturation: seedColor == .pearl ? 0 : 0.75, brightness: 0.40)], center: .center, startRadius: 0, endRadius: unit * 0.28))
                    .frame(width: unit * 0.54, height: unit * 0.54)
                Ellipse().trim(from: 0.04, to: 0.83)
                    .stroke(Color(red: 0.89, green: 0.66, blue: 0.29), style: StrokeStyle(lineWidth: unit * 0.018, lineCap: .round))
                    .frame(width: unit * 0.77, height: unit * 0.36).rotationEffect(.degrees(-30))
                Ellipse().trim(from: 0.12, to: 0.87)
                    .stroke((seedColor == .original ? Color(red: 0.22, green: 0.59, blue: 0.72) : seedColor.accent).opacity(0.8), lineWidth: unit * 0.012)
                    .frame(width: unit * 0.38, height: unit * 0.77).rotationEffect(.degrees(-25))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}
