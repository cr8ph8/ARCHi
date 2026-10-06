import Foundation
import simd

/// Read-only expression of the existing activity owner. A color cue is not a
/// feeling measurement, a learned ability, or permission to change state.
struct LiminalLightFrame: Equatable, Sendable {
    let intensity: Float
    let accent: SIMD3<Float>
    let glow: Float
    static let revision = "liminal-expression/v1"

    /// The UTC clock keeps native and Unity in phase without per-frame IPC.
    /// Reduced motion and inspection retain a steady, legible activity cue.
    static func sample(mode: KinLightMode, unixTime: Double, reduced: Bool = false) -> Self {
        let phase = reduced || !unixTime.isFinite ? 0 :
            (unixTime.truncatingRemainder(dividingBy: 4) + 4).truncatingRemainder(dividingBy: 4) * .pi / 2
        let emission = Float(KinLightEmission.intensity(mode: mode, phase: phase))
        let accent: SIMD3<Float>
        switch mode {
        case .rest, .core: accent = SIMD3(1, 0.72, 0.22)
        case .orbit: accent = SIMD3(0.65, 0.40, 1)
        case .focus: accent = SIMD3(0.20, 0.90, 0.85)
        case .pulse: accent = SIMD3(1, 0.40, 0.58)
        case .delight: accent = SIMD3(0.45, 1, 0.72)
        case .hold: accent = SIMD3(1, 0.65, 0.20)
        }
        return .init(intensity: 1 + emission, accent: accent, glow: emission * 0.6)
    }
}
