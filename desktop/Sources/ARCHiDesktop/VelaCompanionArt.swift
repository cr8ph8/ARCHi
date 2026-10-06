import SwiftUI

/// Two presentations of the same light. This view owns no companion, growth,
/// permission or saved state; all materials use the existing Seed preference.
struct VelaCompanionArt: View {
    let form: CompanionForm
    let size: CGFloat
    let reduceMotion: Bool
    var lightExpression: KinLightExpression = .resting
    var seedColor: CompanionSeedColor = .original
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        let still = reduceMotion || systemReduceMotion || lightExpression.mode == .hold
        TimelineView(.animation(minimumInterval: 1 / 24, paused: still)) { time in
            VelaCompanionFrame(lantern: form == .velaLantern,
                phase: VelaGeometry.phase(at: time.date.timeIntervalSinceReferenceDate,
                    reduceMotion: still, systemReduceMotion: systemReduceMotion),
                expression: lightExpression)
                .environment(\.companionSeedColor, seedColor)
        }
        .frame(width: size, height: size)
        .transaction { $0.animation = nil }
    }
}

enum VelaGeometry {
    static let revision = "vela-opal-lantern-native-v1"

    static func phase(at time: Double, reduceMotion: Bool, systemReduceMotion: Bool) -> Double {
        guard !reduceMotion, !systemReduceMotion, time.isFinite else { return 0 }
        return (time * 1.2).truncatingRemainder(dividingBy: .pi * 2)
    }

    static func normalized(_ phase: Double) -> Double {
        phase.isFinite ? phase.truncatingRemainder(dividingBy: .pi * 2) : 0
    }
}

/// Deterministic geometry used by the live view and the ordinary native export.
/// Every glow has a finite transparent edge, with space for the complete motion.
struct VelaCompanionFrame: View {
    let lantern: Bool
    let phase: Double
    var expression: KinLightExpression = .resting
    @Environment(\.companionSeedColor) private var seedColor

    var body: some View {
        Canvas { context, canvas in
            let unit = min(canvas.width, canvas.height)
            guard unit.isFinite, unit > 0 else { return }
            let phase = VelaGeometry.normalized(phase)
            let float = sin(phase) * 0.009
            context.translateBy(x: (canvas.width - unit) / 2, y: (canvas.height - unit) / 2 + float * unit)
            let drawing = VelaDrawing(unit: unit, phase: phase, mode: expression.mode, color: seedColor)
            drawing.draw(context: &context, lantern: lantern)
        }
    }
}

private struct VelaPalette {
    let aqua: Color
    let rose: Color
    let coral: Color
    let edge: Color
    let shadow: Color

    init(_ color: CompanionSeedColor) {
        if color == .original {
            aqua = Color(red: 0.43, green: 0.85, blue: 0.85)
            rose = Color(red: 0.84, green: 0.67, blue: 0.91)
            coral = Color(red: 0.98, green: 0.74, blue: 0.61)
            edge = Color(red: 0.92, green: 0.79, blue: 0.57)
            shadow = Color(red: 0.27, green: 0.44, blue: 0.51)
        } else {
            let saturation = color == .pearl ? 0.035 : 0.43
            func hue(_ offset: Double) -> Double { (color.hue + offset + 1).truncatingRemainder(dividingBy: 1) }
            aqua = Color(hue: hue(0), saturation: saturation, brightness: 0.91)
            rose = Color(hue: hue(0.08), saturation: saturation * 0.65, brightness: 0.97)
            coral = Color(hue: hue(-0.06), saturation: saturation * 0.78, brightness: 0.94)
            edge = Color(hue: hue(-0.04), saturation: saturation * 0.55, brightness: 0.90)
            shadow = Color(hue: hue(0.02), saturation: saturation * 0.85, brightness: 0.46)
        }
    }
}

private struct VelaDrawing {
    let unit: CGFloat
    let phase: Double
    let mode: KinLightMode
    let color: CompanionSeedColor
    private var palette: VelaPalette { VelaPalette(color) }
    private var energy: Double {
        switch mode {
        case .rest: 0.12
        case .core: 0.56
        case .orbit: 0.48
        case .focus: 0.38
        case .pulse: 0.72 + sin(phase * 2) * 0.12
        case .delight: 0.90
        case .hold: 0.28
        }
    }

    func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * unit, y: y * unit) }
    func ellipse(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Path {
        Path(ellipseIn: CGRect(x: x * unit, y: y * unit, width: w * unit, height: h * unit))
    }
    func circle(_ x: Double, _ y: Double, _ radius: Double) -> Path {
        ellipse(x - radius, y - radius, radius * 2, radius * 2)
    }

    func draw(context: inout GraphicsContext, lantern: Bool) {
        context.fill(ellipse(0.28, 0.84, 0.44, 0.06), with: .radialGradient(
            Gradient(colors: [palette.shadow.opacity(0.15), .clear]), center: point(0.5, 0.87),
            startRadius: 0, endRadius: unit * 0.22))
        let haloRadius = lantern ? 0.34 : 0.37
        context.fill(circle(0.5, 0.49, haloRadius), with: .radialGradient(
            Gradient(stops: [.init(color: .white.opacity(0.18 + energy * 0.10), location: 0),
                .init(color: palette.aqua.opacity(0.09 + energy * 0.07), location: 0.42),
                .init(color: .clear, location: 1)]), center: point(0.5, 0.49), startRadius: 0,
            endRadius: unit * haloRadius))
        if lantern { wings(context: &context) }
        shell(context: &context, lantern: lantern)
        core(context: &context)
        if !lantern { frontPetal(context: &context) }
        activity(context: &context, lantern: lantern)
    }

    private func membrane(_ path: Path, context: inout GraphicsContext,
                          start: CGPoint, end: CGPoint, opacity: Double = 1) {
        context.fill(path, with: .linearGradient(Gradient(stops: [
            .init(color: palette.shadow.opacity(0.54 * opacity), location: 0),
            .init(color: palette.aqua.opacity(0.63 * opacity), location: 0.22),
            .init(color: .white.opacity(0.74 * opacity), location: 0.40),
            .init(color: palette.rose.opacity(0.60 * opacity), location: 0.56),
            .init(color: palette.coral.opacity(0.67 * opacity), location: 0.72),
            .init(color: palette.aqua.opacity(0.49 * opacity), location: 0.86),
            .init(color: palette.shadow.opacity(0.50 * opacity), location: 1)
        ]), startPoint: start, endPoint: end))
        context.stroke(path, with: .color(palette.shadow.opacity(0.40)), lineWidth: unit * 0.009)
        context.stroke(path, with: .linearGradient(Gradient(colors: [.white.opacity(0.90), palette.edge, .white.opacity(0.8)]),
            startPoint: start, endPoint: end), lineWidth: unit * 0.005)
        context.stroke(path, with: .color(.white.opacity(0.45)), lineWidth: unit * 0.0013)
    }

    private func wings(context: inout GraphicsContext) {
        let spread = (mode == .focus ? 0.92 : mode == .delight ? 1.045 : 1.0) + sin(phase) * 0.024
        for side in [-1.0, 1.0] {
            var wingContext = context
            wingContext.translateBy(x: unit * 0.5, y: unit * 0.49)
            wingContext.scaleBy(x: side * spread, y: 1 - sin(phase) * 0.018)
            wingContext.translateBy(x: -unit * 0.5, y: -unit * 0.49)
            var upper = Path()
            upper.move(to: point(0.535, 0.49))
            upper.addCurve(to: point(0.91, 0.19), control1: point(0.58, 0.22), control2: point(0.92, 0.34))
            upper.addCurve(to: point(0.93, 0.28), control1: point(0.943, 0.11), control2: point(0.944, 0.21))
            upper.addCurve(to: point(0.57, 0.55), control1: point(0.98, 0.60), control2: point(0.70, 0.61))
            upper.addQuadCurve(to: point(0.535, 0.49), control: point(0.54, 0.53))
            membrane(upper, context: &wingContext, start: point(0.61, 0.28), end: point(0.84, 0.59))

            var lower = Path()
            lower.move(to: point(0.53, 0.535))
            lower.addCurve(to: point(0.79, 0.73), control1: point(0.71, 0.51), control2: point(0.75, 0.58))
            lower.addQuadCurve(to: point(0.85, 0.80), control: point(0.81, 0.77))
            lower.addCurve(to: point(0.54, 0.61), control1: point(0.72, 0.72), control2: point(0.59, 0.78))
            lower.addQuadCurve(to: point(0.53, 0.535), control: point(0.53, 0.57))
            membrane(lower, context: &wingContext, start: point(0.55, 0.55), end: point(0.83, 0.76), opacity: 0.91)

            var vein = Path()
            vein.move(to: point(0.55, 0.50))
            vein.addCurve(to: point(0.916, 0.229), control1: point(0.76, 0.45), control2: point(0.93, 0.55))
            vein.move(to: point(0.55, 0.55))
            vein.addCurve(to: point(0.82, 0.78), control1: point(0.62, 0.57), control2: point(0.72, 0.73))
            wingContext.stroke(vein, with: .color(palette.edge.opacity(0.86)), style: StrokeStyle(lineWidth: unit * 0.003, lineCap: .round))
            wingContext.stroke(vein, with: .color(.white.opacity(0.6)), lineWidth: unit * 0.001)
            constellation([(0.62, 0.42), (0.68, 0.38), (0.74, 0.39), (0.81, 0.33)], context: &wingContext)
            constellation([(0.60, 0.59), (0.65, 0.63), (0.69, 0.69)], context: &wingContext)
        }
    }

    private func shell(context: inout GraphicsContext, lantern: Bool) {
        let top = lantern ? 0.30 : 0.145
        let bottom = lantern ? 0.70 : 0.815
        let left = lantern ? 0.367 : 0.255
        let right = 1 - left
        var shell = Path()
        shell.move(to: point(0.505, top))
        shell.addCurve(to: point(0.5, bottom), control1: point(0.53, top + 0.10), control2: point(right + 0.22, 0.55))
        shell.addCurve(to: point(0.505, top), control1: point(left - 0.19, 0.60), control2: point(0.46, top + 0.13))
        membrane(shell, context: &context, start: point(left, 0.30), end: point(right, 0.70))
        var seam = Path()
        seam.move(to: point(0.505, top + 0.007))
        seam.addCurve(to: point(0.50, bottom - 0.004), control1: point(0.45, 0.40), control2: point(0.75, 0.60))
        context.stroke(seam, with: .color(.white.opacity(0.80)), lineWidth: unit * 0.003)
        if !lantern {
            var petal = Path()
            petal.move(to: point(0.497, 0.16))
            petal.addCurve(to: point(0.495, 0.80), control1: point(0.23, 0.40), control2: point(0.31, 0.71))
            petal.addCurve(to: point(0.497, 0.16), control1: point(0.26, 0.63), control2: point(0.49, 0.49))
            membrane(petal, context: &context, start: point(0.3, 0.32), end: point(0.52, 0.75), opacity: 0.85)
            constellation([(0.335, 0.47), (0.347, 0.59), (0.394, 0.67)], context: &context)
        }
    }

    private func core(context: inout GraphicsContext) {
        // This exact pearl and face are retained in both presentations.
        let radius = 0.104
        let center = point(0.5, 0.515)
        context.fill(circle(0.5, 0.515, radius * 1.40), with: .radialGradient(
            Gradient(colors: [palette.coral.opacity(0.55 + energy * 0.2), .clear]), center: center,
            startRadius: unit * 0.04, endRadius: unit * radius * 1.4))
        context.fill(circle(0.5, 0.515, radius), with: .radialGradient(
            Gradient(stops: [.init(color: .white, location: 0),
                .init(color: Color(red: 1, green: 0.98, blue: 0.85), location: 0.54),
                .init(color: Color(red: 0.98, green: 0.85, blue: 0.62), location: 1)]),
            center: point(0.473, 0.48), startRadius: 0, endRadius: unit * 0.142))
        context.stroke(circle(0.5, 0.515, radius), with: .color(.white.opacity(0.92)), lineWidth: unit * 0.003)
        context.fill(ellipse(0.448, 0.447, 0.055, 0.027), with: .radialGradient(
            Gradient(colors: [.white.opacity(0.92), .clear]), center: point(0.475, 0.46), startRadius: 0, endRadius: unit * 0.035))
        for x in [0.46, 0.54] {
            let height = mode == .delight ? 0.027 : mode == .hold ? 0.022 : 0.038
            let eye = ellipse(x - 0.010, 0.512 - height / 2, 0.020, height)
            context.fill(eye, with: .linearGradient(Gradient(colors: [Color(red: 0.12, green: 0.20, blue: 0.23),
                Color(red: 0.39, green: 0.27, blue: 0.21)]), startPoint: point(x, 0.49), endPoint: point(x, 0.54)))
            context.stroke(eye, with: .color(palette.edge.opacity(0.8)), lineWidth: unit * 0.002)
            context.fill(circle(x - 0.002, 0.503, 0.0038), with: .color(.white.opacity(0.97)))
        }
    }

    private func frontPetal(context: inout GraphicsContext) {
        var petal = Path()
        petal.move(to: point(0.455, 0.267))
        petal.addCurve(to: point(0.657, 0.604), control1: point(0.54, 0.33), control2: point(0.78, 0.39))
        petal.addCurve(to: point(0.492, 0.804), control1: point(0.60, 0.69), control2: point(0.51, 0.70))
        petal.addCurve(to: point(0.571, 0.593), control1: point(0.46, 0.71), control2: point(0.55, 0.65))
        petal.addCurve(to: point(0.455, 0.267), control1: point(0.70, 0.45), control2: point(0.40, 0.39))
        membrane(petal, context: &context, start: point(0.43, 0.28), end: point(0.67, 0.74), opacity: 0.94)
        constellation([(0.54, 0.365), (0.605, 0.43), (0.623, 0.514), (0.602, 0.589)], context: &context)
    }

    private func constellation(_ positions: [(Double, Double)], context: inout GraphicsContext) {
        var line = Path()
        for (index, position) in positions.enumerated() {
            if index == 0 { line.move(to: point(position.0, position.1)) }
            else { line.addLine(to: point(position.0, position.1)) }
        }
        context.stroke(line, with: .color(palette.edge.opacity(0.62 + energy * 0.20)), lineWidth: unit * 0.0018)
        for (index, position) in positions.enumerated() {
            let radius = index % 2 == 0 ? 0.004 : 0.0054
            context.fill(circle(position.0, position.1, radius * 3), with: .radialGradient(
                Gradient(colors: [palette.coral.opacity(0.35 + energy * 0.25), .clear]),
                center: point(position.0, position.1), startRadius: 0, endRadius: unit * radius * 3))
            context.fill(circle(position.0, position.1, radius), with: .color(.white.opacity(0.88)))
        }
    }

    private func activity(context: inout GraphicsContext, lantern: Bool) {
        guard mode != .rest else { return }
        let count = mode == .delight ? 5 : mode == .orbit ? 3 : 2
        for index in 0..<count {
            let angle = phase + Double(index) * 2 * .pi / Double(count) - .pi / 2
            let radius = lantern ? 0.28 : 0.36
            let x = 0.5 + cos(angle) * radius
            let y = 0.49 + sin(angle) * radius * (lantern ? 1.1 : 1)
            let starRadius = mode == .focus ? 0.008 : 0.012
            let glow = circle(x, y, starRadius * 2.8)
            context.fill(glow, with: .radialGradient(Gradient(colors: [palette.coral.opacity(0.32), .clear]),
                center: point(x, y), startRadius: 0, endRadius: unit * starRadius * 2.8))
            var star = Path()
            star.move(to: point(x, y - starRadius))
            star.addQuadCurve(to: point(x + starRadius * 0.65, y), control: point(x, y))
            star.addQuadCurve(to: point(x, y + starRadius), control: point(x, y))
            star.addQuadCurve(to: point(x - starRadius * 0.65, y), control: point(x, y))
            star.addQuadCurve(to: point(x, y - starRadius), control: point(x, y))
            context.fill(star, with: .color(palette.edge.opacity(0.9)))
        }
    }
}
