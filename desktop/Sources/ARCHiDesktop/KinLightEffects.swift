import SwiftUI

/// Ephemeral light around the existing Core Seed portrait. No ability replaces,
/// recolors, scales or persists the underlying body. Rest draws nothing at all.
struct KinLightEffects: View {
    let expression: KinLightExpression
    let size: CGFloat
    let reduceMotion: Bool
    var centerY: Double = 0.5
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        let still = reduceMotion || systemReduceMotion || expression.mode == .hold
        Group {
            if expression.mode != .rest {
                TimelineView(.animation(minimumInterval: 1 / 15, paused: still)) { time in
                    KinLightEffectsFrame(expression: expression,
                        phase: KinLightEffectsGeometry.phase(at: time.date.timeIntervalSinceReferenceDate,
                            reduceMotion: still, systemReduceMotion: systemReduceMotion),
                        centerY: centerY)
                }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A fixed effects-only frame for native inspection; canonical artwork exports
/// use CompanionPresenceArt's unchanged resting path instead of this overlay.
struct KinLightEffectsFrame: View {
    let expression: KinLightExpression
    let phase: Double
    var centerY: Double = 0.5

    var body: some View {
        Canvas { context, canvas in
            let unit = min(canvas.width, canvas.height)
            guard unit > 0, expression.mode != .rest else { return }
            let phase = LightFormGeometry.normalizedPhase(self.phase)
            let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2 + (centerY - 0.5) * unit)
            let palette = KinLightPalette(mode: expression.mode)
            context.clip(to: Path(CGRect(origin: .zero, size: canvas)))

            let breath = 1 + sin(phase) * (expression.mode == .pulse ? 0.025 : 0.012)
            drawHalo(context: &context, center: center, unit: unit, breath: breath, palette: palette)
            switch expression.mode {
            case .rest: break
            case .core:
                drawCore(context: &context, center: center, unit: unit, breath: breath, palette: palette)
            case .orbit:
                drawOrbit(context: &context, center: center, unit: unit, phase: phase, palette: palette, nested: true)
            case .focus:
                drawPetals(context: &context, center: center, unit: unit, phase: phase,
                    palette: palette, open: false)
                drawOrbit(context: &context, center: center, unit: unit * 0.95, phase: phase, palette: palette, nested: false)
            case .pulse:
                drawCore(context: &context, center: center, unit: unit * 1.04, breath: breath, palette: palette)
                drawPetals(context: &context, center: center, unit: unit, phase: phase,
                    palette: palette, open: false)
            case .delight:
                drawPetals(context: &context, center: center, unit: unit, phase: phase,
                    palette: palette, open: true)
                drawOrbit(context: &context, center: center, unit: unit, phase: phase, palette: palette, nested: false)
            case .hold:
                drawHold(context: &context, center: center, unit: unit, palette: palette)
            }
            drawMotes(context: &context, center: center, unit: unit, phase: phase, palette: palette,
                sparse: expression.mode == .core || expression.mode == .hold)
        }
        .mask {
            GeometryReader { geometry in
                let unit = min(geometry.size.width, geometry.size.height)
                let relativeY = geometry.size.height > 0
                    ? 0.5 + (centerY - 0.5) * unit / geometry.size.height : 0.5
                // Keep every central pixel untouched, then introduce the light
                // gradually. A feather avoids a dark cut-out around the pearl.
                RadialGradient(gradient: Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: KinLightEffectsGeometry.protectedCoreRadius * 2),
                    .init(color: .white.opacity(0.12), location: 0.386),
                    .init(color: .white.opacity(0.68), location: 0.434),
                    .init(color: .white, location: KinLightEffectsGeometry.featherOuterRadius * 2),
                    .init(color: .white, location: 1)
                ]), center: UnitPoint(x: 0.5, y: relativeY), startRadius: 0, endRadius: unit * 0.5)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawHalo(context: inout GraphicsContext, center: CGPoint, unit: CGFloat,
                          breath: Double, palette: KinLightPalette) {
        let radius = unit * 0.424 * breath
        context.fill(circle(center, radius: radius), with: .radialGradient(Gradient(stops: [
            .init(color: .clear, location: 0.39),
            .init(color: palette.accent.opacity(0.05), location: 0.57),
            .init(color: palette.accent.opacity(0.018), location: 0.85),
            .init(color: .clear, location: 1)
        ]), center: center, startRadius: 0, endRadius: radius))
    }

    private func drawCore(context: inout GraphicsContext, center: CGPoint, unit: CGFloat,
                          breath: Double, palette: KinLightPalette) {
        for (index, scale) in [0.213, 0.246, 0.285].enumerated() {
            let ring = circle(center, radius: unit * scale * breath)
            context.stroke(ring, with: .color(palette.accent.opacity(0.04)), lineWidth: unit * 0.016)
            context.stroke(ring, with: .color(palette.highlight.opacity(index == 0 ? 0.65 : 0.28)),
                           lineWidth: max(0.45, unit * 0.0019))
        }
    }

    private func drawPetals(context: inout GraphicsContext, center: CGPoint, unit: CGFloat,
                            phase: Double, palette: KinLightPalette, open: Bool) {
        // Reuse the optical lenses from the supplied light study, around KIN's
        // preserved core. An ability never paints a second pearl or opaque body.
        for petal in LightFormGeometry.petals(phase: phase) where open || petal.front {
            var lens = context
            let spread = open ? 1.5 : 1.2
            lens.translateBy(x: center.x + petal.x * unit * spread, y: center.y + petal.y * unit * spread)
            lens.rotate(by: .radians(petal.rotation))
            let width = unit * (open ? 0.276 : 0.218) * petal.scale
            let height = unit * (open ? 0.49 : 0.455) * petal.scale
            let shape = Path(ellipseIn: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
            lens.fill(shape, with: .linearGradient(Gradient(stops: [
                .init(color: palette.highlight.opacity(petal.front ? 0.175 : 0.07), location: 0),
                .init(color: palette.accent.opacity(petal.front ? 0.125 : 0.04), location: 0.26),
                .init(color: palette.accent.opacity(0.0125), location: 0.6),
                .init(color: palette.accent.opacity(petal.front ? 0.08 : 0.035), location: 1)
            ]), startPoint: CGPoint(x: -width * 0.2, y: -height / 2),
                endPoint: CGPoint(x: width * 0.35, y: height / 2)))
            lens.stroke(shape, with: .color(palette.shadow.opacity(0.12)), lineWidth: max(0.65, unit * 0.003))
            lens.stroke(shape, with: .linearGradient(Gradient(colors: [palette.highlight.opacity(0.7),
                palette.accent.opacity(0.28), palette.highlight.opacity(0.44)]),
                startPoint: CGPoint(x: -width / 2, y: -height / 2), endPoint: CGPoint(x: width / 2, y: height / 2)),
                lineWidth: max(0.4, unit * 0.0018))
        }
    }

    private func drawOrbit(context: inout GraphicsContext, center: CGPoint, unit: CGFloat,
                           phase: Double, palette: KinLightPalette, nested: Bool) {
        // Broken ellipses leave open space around the original particle Seed.
        // A dimmer far side and brighter near side suggest depth without a
        // second body, moving window, or additional character-state owner.
        for arc in KinOrbitGeometry.arcs(nested: nested) {
            var path = Path()
            for (index, sample) in arc.points.enumerated() {
                let point = CGPoint(x: center.x + sample.x * unit, y: center.y + sample.y * unit)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            let near = (arc.depth + 1) * 0.5
            context.stroke(path, with: .color(palette.shadow.opacity(0.12 + near * 0.16)),
                style: StrokeStyle(lineWidth: max(0.55, unit * 0.003), lineCap: .round))
            context.stroke(path, with: .color(palette.highlight.opacity(0.18 + near * 0.48)),
                style: StrokeStyle(lineWidth: max(0.4, unit * (0.0013 + near * 0.0006)), lineCap: .round))
        }
        for particle in KinOrbitGeometry.motes(phase: phase, nested: nested) {
            mote(context: &context,
                at: CGPoint(x: center.x + particle.position.x * unit, y: center.y + particle.position.y * unit),
                radius: max(0.4, unit * particle.radius), opacity: particle.opacity, palette: palette)
        }
    }

    private func drawHold(context: inout GraphicsContext, center: CGPoint, unit: CGFloat, palette: KinLightPalette) {
        // Four quiet brackets express a hold without a flashing alarm or shield
        // claim. Their geometry is static even when ordinary motion is enabled.
        for index in 0..<4 {
            var arc = Path()
            arc.addArc(center: center, radius: unit * 0.395,
                       startAngle: .degrees(Double(index) * 90 + 16),
                       endAngle: .degrees(Double(index) * 90 + 74), clockwise: false)
            context.stroke(arc, with: .color(palette.accent.opacity(0.12)),
                           style: StrokeStyle(lineWidth: unit * 0.013, lineCap: .round))
            context.stroke(arc, with: .color(palette.highlight.opacity(0.72)),
                           style: StrokeStyle(lineWidth: max(0.7, unit * 0.003), lineCap: .round))
        }
    }

    private func drawMotes(context: inout GraphicsContext, center: CGPoint, unit: CGFloat,
                           phase: Double, palette: KinLightPalette, sparse: Bool) {
        // These modes already have sparse motes traveling on their own tracks.
        // Do not pile the generic outer dust field on top of that circulation.
        guard ![KinLightMode.orbit, .focus, .delight].contains(expression.mode) else { return }
        for (index, particle) in LightFormGeometry.motes(phase: phase).enumerated() {
            if sparse && !index.isMultiple(of: 4) { continue }
            mote(context: &context, at: CGPoint(x: center.x + particle.x * unit, y: center.y + particle.y * unit),
                 radius: max(0.4, unit * particle.radius), opacity: particle.opacity * 0.74, palette: palette)
        }
    }

    private func mote(context: inout GraphicsContext, at point: CGPoint, radius: CGFloat,
                      opacity: Double, palette: KinLightPalette) {
        context.fill(circle(point, radius: radius * 4), with: .radialGradient(
            Gradient(colors: [palette.accent.opacity(opacity * 0.45), .clear]),
            center: point, startRadius: 0, endRadius: radius * 4))
        context.fill(circle(point, radius: radius), with: .color(palette.highlight.opacity(opacity)))
    }

    private func circle(_ center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}

/// KIN-specific projected light paths. All values are in portrait units, with
/// the existing core at the origin. The finite, wrapped phase changes drawing
/// only; path gaps and fixed projections stay stable across updates and previews.
enum KinOrbitGeometry {
    struct Point: Equatable {
        let x: Double, y: Double
    }
    struct Track: Equatable {
        let radiusX: Double, radiusY: Double, rotation: Double, gapOffset: Double

        func point(at angle: Double) -> Point {
            let angle = LightFormGeometry.normalizedPhase(angle)
            let x = cos(angle) * radiusX, y = sin(angle) * radiusY
            return Point(x: x * cos(rotation) - y * sin(rotation),
                         y: x * sin(rotation) + y * cos(rotation))
        }
    }
    struct Arc {
        let trackIndex: Int
        let startAngle: Double, endAngle: Double
        let points: [Point]
        let depth: Double
    }
    struct Mote {
        let trackIndex: Int, index: Int
        let angle: Double
        let position: Point
        let depth: Double, radius: Double, opacity: Double
    }

    static func tracks(nested: Bool) -> [Track] {
        let primary = Track(radiusX: 0.385, radiusY: 0.245, rotation: -.pi / 7, gapOffset: 0)
        guard nested else { return [primary] }
        return [primary, Track(radiusX: 0.365, radiusY: 0.275, rotation: .pi / 3, gapOffset: 0.17)]
    }

    static func arcs(nested: Bool) -> [Arc] {
        tracks(nested: nested).enumerated().flatMap { trackIndex, track in
            (0..<4).map { quadrant in
                let start = Double(quadrant) * .pi / 2 + 0.12 + track.gapOffset
                let end = Double(quadrant + 1) * .pi / 2 - 0.12 + track.gapOffset
                let points = (0...20).map { index in
                    track.point(at: start + (end - start) * Double(index) / 20)
                }
                return Arc(trackIndex: trackIndex, startAngle: start, endAngle: end,
                           points: points, depth: sin((start + end) * 0.5))
            }
        }.sorted { $0.depth < $1.depth }
    }

    static func motes(phase: Double, nested: Bool) -> [Mote] {
        let phase = LightFormGeometry.normalizedPhase(phase)
        return tracks(nested: nested).enumerated().flatMap { trackIndex, track in
            let count = trackIndex == 0 ? 5 : 4
            let direction = trackIndex == 0 ? 1.0 : -1.0
            return (0..<count).map { index in
                let angle = LightFormGeometry.normalizedPhase(Double(index) * .pi * 2 / Double(count)
                    + track.gapOffset + direction * phase)
                let depth = sin(angle), near = (depth + 1) * 0.5
                return Mote(trackIndex: trackIndex, index: index, angle: angle, position: track.point(at: angle),
                    depth: depth, radius: 0.0018 + near * 0.0016,
                    opacity: 0.30 + near * 0.55)
            }
        }.sorted { $0.depth < $1.depth }
    }
}

enum KinLightEffectsGeometry {
    static let protectedCoreRadius = 0.18
    static let featherOuterRadius = 0.235

    static func phase(at time: Double, reduceMotion: Bool, systemReduceMotion: Bool) -> Double {
        guard !reduceMotion, !systemReduceMotion, time.isFinite else { return 0 }
        return LightFormGeometry.normalizedPhase(time * 0.16)
    }
}

/// Shared expression colors for KIN and his desktop focus boundary.
struct KinLightPalette {
    let accent: Color
    let highlight: Color
    let shadow: Color

    init(mode: KinLightMode) {
        switch mode {
        case .rest, .core:
            accent = Color(red: 1, green: 0.72, blue: 0.35)
            highlight = Color(red: 1, green: 0.94, blue: 0.72)
            shadow = Color(red: 0.48, green: 0.24, blue: 0.11)
        case .orbit:
            accent = Color(red: 0.64, green: 0.48, blue: 0.95)
            highlight = Color(red: 0.86, green: 0.76, blue: 1)
            shadow = Color(red: 0.31, green: 0.17, blue: 0.50)
        case .focus:
            accent = Color(red: 0.25, green: 0.83, blue: 0.78)
            highlight = Color(red: 0.75, green: 1, blue: 0.91)
            shadow = Color(red: 0.10, green: 0.38, blue: 0.34)
        case .pulse:
            accent = Color(red: 0.96, green: 0.39, blue: 0.62)
            highlight = Color(red: 1, green: 0.78, blue: 0.86)
            shadow = Color(red: 0.48, green: 0.13, blue: 0.27)
        case .delight:
            accent = Color(red: 0.51, green: 0.91, blue: 0.72)
            highlight = Color(red: 0.85, green: 1, blue: 0.88)
            shadow = Color(red: 0.15, green: 0.40, blue: 0.28)
        case .hold:
            accent = Color(red: 1, green: 0.63, blue: 0.24)
            highlight = Color(red: 1, green: 0.87, blue: 0.58)
            shadow = Color(red: 0.47, green: 0.27, blue: 0.10)
        }
    }
}
