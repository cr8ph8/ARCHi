import SwiftUI

enum ArchiPalette {
    static let violet = Color(red: 0.49, green: 0.40, blue: 0.74)
    static let lavender = Color(red: 0.80, green: 0.76, blue: 0.96)
    static let lilac = Color(red: 0.91, green: 0.87, blue: 0.98)
    static let peach = Color(red: 0.98, green: 0.79, blue: 0.68)
    static let ink = Color(red: 0.22, green: 0.19, blue: 0.34)
}

/// The desktop body is entirely local drawing. It owns no input or assistant state.
struct CompanionArt: View {
    let form: CompanionForm
    let size: CGFloat
    let reduceMotion: Bool
    var naturalVariation: CompanionNaturalVariation? = nil
    var lightExpression: KinLightExpression = .resting
    var treatment: CompanionVisualTreatment = .original
    var seedColor: CompanionSeedColor = .original

    private var effectiveNaturalVariation: CompanionNaturalVariation? {
        form == .companion ? naturalVariation : nil
    }

    var body: some View {
        Group {
            if form == .hamptonSeed {
                HamptonLiminalSeedArt(size: size, reduceMotion: reduceMotion, lightExpression: lightExpression, seedColor: seedColor)
            } else if form == .corePearl {
                ArchiLightSeedArt(size: size, reduceMotion: reduceMotion, lightExpression: lightExpression)
            } else if form == .particleSeed {
                KinArt(form: .kinSeed, size: size, reduceMotion: reduceMotion, lightExpression: lightExpression, seedColor: seedColor)
            } else if form == .particle {
                ParticleLightArt(size: size, reduceMotion: reduceMotion)
            } else if form.isOpticalLight {
                LightFormArt(form: form, size: size, reduceMotion: reduceMotion)
            } else if form.isKin {
                KinArt(form: form, size: size, reduceMotion: reduceMotion,
                    lightExpression: form == .kinSeed || form == .kin ? lightExpression : .resting, treatment: treatment, seedColor: seedColor)
            } else if [.constellation, .sprout, .ribbonSpirit, .geode].contains(form) {
                TealCompanionFallback(form: form).frame(width: size, height: size)
            } else {
                familiarBody
            }
        }
        .environment(\.companionSeedColor, seedColor)
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(effectiveNaturalVariation == nil
            ? "ARCHi, " + CompanionVisualAsset.label(form: form, family: nil, treatment: treatment, seedColor: seedColor) + " form"
            : "ARCHi, \(form.rawValue) form, individual variation")
    }

    private var familiarBody: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * 1.5
            let float = reduceMotion ? 0 : sin(phase) * size * 0.018
            ZStack {
                Ellipse()
                    .fill(ArchiPalette.violet.opacity(0.13))
                    .frame(width: size * 0.56, height: size * 0.09)
                    .blur(radius: size * 0.04)
                    .offset(y: size * 0.39)
                if let variation = effectiveNaturalVariation {
                    formBody
                        .frame(width: size * 0.88, height: size * 0.88)
                        .modifier(CompanionNaturalFinish(variation: variation))
                        .offset(y: float - size * 0.025)
                } else {
                    formBody
                        .frame(width: size * 0.88, height: size * 0.88)
                        .offset(y: float - size * 0.025)
                }
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private var formBody: some View {
        switch form {
        case .companion: softCompanion
        case .light: guideLight
        case .particle: ParticleLightFrame(phase: 0)
        case .particleSeed: KinCoreSeedFrame(phase: 0)
        case .hamptonSeed: HamptonLiminalSeedArt(size: size, reduceMotion: reduceMotion, lightExpression: lightExpression, seedColor: seedColor)
        case .corePearl, .orbitField, .lightForm: LightFormFrame(form: form, phase: 0)
        case .ribbon: ribbon
        case .ink: ink
        case .pixel: pixel
        case .kin, .kinSpark, .kinSimple, .kinSeed:
            KinArt(form: form, size: size, reduceMotion: reduceMotion,
                lightExpression: form == .kinSeed || form == .kin ? lightExpression : .resting, treatment: treatment, seedColor: seedColor)
        case .constellation, .sprout, .ribbonSpirit, .geode:
            TealCompanionFallback(form: form)
        }
    }

    private var softCompanion: some View {
        ZStack {
            CompanionSilhouette()
                .fill(LinearGradient(colors: [.white, ArchiPalette.lilac, ArchiPalette.lavender], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: ArchiPalette.violet.opacity(0.25), radius: size * 0.04, x: 0, y: size * 0.035)
            CompanionSilhouette()
                .stroke(.white.opacity(0.82), lineWidth: max(0.8, size * 0.009))
            Ellipse().fill(.white.opacity(0.76))
                .frame(width: size * 0.21, height: size * 0.105)
                .rotationEffect(.degrees(-28))
                .offset(x: -size * 0.18, y: -size * 0.22)
                .blur(radius: size * 0.026)
            face
                .offset(y: size * 0.045)
        }
    }

    private var guideLight: some View {
        ZStack {
            Circle().fill(ArchiPalette.lavender.opacity(0.20)).blur(radius: size * 0.05)
            Circle().fill(RadialGradient(colors: [.white, ArchiPalette.lilac, ArchiPalette.lavender.opacity(0.62), .clear], center: .init(x: 0.38, y: 0.32), startRadius: 0, endRadius: size * 0.40))
                .padding(size * 0.05)
            Circle().stroke(.white.opacity(0.8), lineWidth: 1).padding(size * 0.13)
            face.scaleEffect(0.82)
        }
    }

    private var ribbon: some View {
        ZStack {
            RibbonShape().stroke(ArchiPalette.violet.opacity(0.18), style: StrokeStyle(lineWidth: size * 0.17, lineCap: .round))
                .blur(radius: size * 0.035).offset(y: size * 0.025)
            RibbonShape().stroke(LinearGradient(colors: [ArchiPalette.peach, ArchiPalette.lilac, ArchiPalette.violet, ArchiPalette.lavender], startPoint: .topLeading, endPoint: .bottomTrailing), style: StrokeStyle(lineWidth: size * 0.125, lineCap: .round))
            RibbonShape().stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: size * 0.018, lineCap: .round))
                .offset(x: -size * 0.024)
            face.scaleEffect(0.72).offset(y: -size * 0.12)
        }
    }

    private var ink: some View {
        ZStack {
            InkShape().fill(LinearGradient(colors: [ArchiPalette.ink, ArchiPalette.violet], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: ArchiPalette.ink.opacity(0.18), radius: size * 0.035, y: size * 0.03)
            HStack(spacing: size * 0.10) {
                Capsule().fill(ArchiPalette.lilac).frame(width: size * 0.042, height: size * 0.092)
                Capsule().fill(ArchiPalette.lilac).frame(width: size * 0.042, height: size * 0.092)
            }.offset(y: -size * 0.025)
            Capsule().fill(.white.opacity(0.22)).frame(width: size * 0.12, height: size * 0.024)
                .rotationEffect(.degrees(-48)).offset(x: -size * 0.20, y: -size * 0.18)
        }
    }

    private var pixel: some View {
        Canvas { context, rect in
            let cells = [
                "0001111000", "0011111100", "0111111110", "1111111111",
                "1112112111", "1112112111", "1111111111", "0111221110",
                "0011111100", "0011001100"
            ]
            let cell = min(rect.width, rect.height) / 12
            let origin = CGPoint(x: (rect.width - cell * 10) / 2, y: (rect.height - cell * 10) / 2)
            for (y, row) in cells.enumerated() {
                for (x, value) in row.enumerated() where value != "0" {
                    let box = CGRect(x: origin.x + CGFloat(x) * cell, y: origin.y + CGFloat(y) * cell, width: cell + 0.2, height: cell + 0.2)
                    let color = value == "2" ? ArchiPalette.ink : (y < 3 ? ArchiPalette.lilac : ArchiPalette.lavender)
                    context.fill(Path(box), with: .color(color))
                }
            }
        }
        .shadow(color: ArchiPalette.violet.opacity(0.20), radius: 0, x: size * 0.025, y: size * 0.035)
    }

    private var face: some View {
        VStack(spacing: size * 0.055) {
            HStack(spacing: size * 0.13) {
                eye
                eye
            }
            SmileShape().stroke(ArchiPalette.ink.opacity(0.86), style: StrokeStyle(lineWidth: max(1, size * 0.012), lineCap: .round))
                .frame(width: size * 0.085, height: size * 0.032)
        }
    }

    private var eye: some View {
        Capsule().fill(ArchiPalette.ink)
            .frame(width: size * 0.037, height: size * 0.077)
    }
}

/// Small, deterministic local bodies for a missing or rejected bundled study.
/// Each preserves its chosen silhouette, inside the same unchanged art frame.
struct TealCompanionFallback: View {
    let form: CompanionForm

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height)
            let teal = Color(red: 0.29, green: 0.69, blue: 0.65)
            let mint = Color(red: 0.73, green: 0.97, blue: 0.90)
            func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * unit, y: y * unit) }
            func ellipse(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Path {
                Path(ellipseIn: CGRect(x: x * unit, y: y * unit, width: w * unit, height: h * unit))
            }
            func polygon(_ points: [(Double, Double)]) -> Path {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: point(first.0, first.1))
                    for item in points.dropFirst() { path.addLine(to: point(item.0, item.1)) }
                    path.closeSubpath()
                }
            }
            context.fill(ellipse(0.27, 0.84, 0.46, 0.035), with: .color(teal.opacity(0.10)))
            switch form {
            case .constellation:
                let sphere = ellipse(0.19, 0.18, 0.62, 0.62)
                context.fill(sphere, with: .radialGradient(Gradient(colors: [mint.opacity(0.30), teal.opacity(0.14)]),
                    center: point(0.43, 0.42), startRadius: 0, endRadius: unit * 0.4))
                context.stroke(sphere, with: .color(mint.opacity(0.85)), lineWidth: unit * 0.008)
                let positions = (0..<20).map { index -> CGPoint in
                    let angle = Double(index) * 2.4
                    let radius = 0.08 + Double(index % 5) * 0.05
                    return point(0.5 + cos(angle) * radius, 0.49 + sin(angle) * radius)
                }
                for (index, start) in positions.enumerated() {
                    var link = Path(); link.move(to: start); link.addLine(to: positions[(index + 7) % positions.count])
                    context.stroke(link, with: .color(mint.opacity(0.33)), lineWidth: max(0.4, unit * 0.0015))
                    context.fill(Path(ellipseIn: CGRect(x: start.x - unit * 0.004, y: start.y - unit * 0.004,
                        width: unit * 0.008, height: unit * 0.008)), with: .color(mint))
                }
            case .sprout:
                let leaves = [polygon([(0.44, 0.36), (0.26, 0.14), (0.25, 0.30), (0.39, 0.41)]),
                    polygon([(0.56, 0.36), (0.74, 0.14), (0.75, 0.30), (0.61, 0.41)])]
                for leaf in leaves {
                    context.fill(leaf, with: .color(teal.opacity(0.70)))
                    context.stroke(leaf, with: .color(mint.opacity(0.8)), lineWidth: unit * 0.007)
                }
                for body in [ellipse(0.34, 0.54, 0.32, 0.27), ellipse(0.28, 0.31, 0.44, 0.34),
                    ellipse(0.26, 0.60, 0.12, 0.13), ellipse(0.62, 0.60, 0.12, 0.13)] {
                    context.fill(body, with: .color(teal.opacity(0.70)))
                    context.stroke(body, with: .color(mint.opacity(0.8)), lineWidth: unit * 0.006)
                }
                for x in [0.40, 0.56] {
                    context.fill(ellipse(x, 0.43, 0.035, 0.055), with: .color(Color(red: 0.08, green: 0.26, blue: 0.30)))
                }
            case .ribbonSpirit:
                for index in 0..<3 {
                    let offset = Double(index - 1) * 0.075
                    var ribbon = Path()
                    ribbon.move(to: point(0.67 + offset, 0.20))
                    ribbon.addCurve(to: point(0.33 + offset, 0.77),
                        control1: point(0.09 + offset, 0.32), control2: point(0.89 + offset, 0.60))
                    context.stroke(ribbon, with: .linearGradient(Gradient(colors: [mint.opacity(0.75), teal.opacity(0.42)]),
                        startPoint: point(0.3, 0.2), endPoint: point(0.7, 0.8)),
                        style: StrokeStyle(lineWidth: unit * 0.055, lineCap: .round))
                }
            case .geode:
                for index in 0..<7 {
                    let angle = Double(index) * 2 * Double.pi / 7
                    let centerX = 0.5 + cos(angle) * 0.23
                    let centerY = 0.49 + sin(angle) * 0.23
                    let shard = polygon([(centerX - 0.045, centerY), (centerX, centerY - 0.105),
                        (centerX + 0.055, centerY - 0.005), (centerX + 0.018, centerY + 0.070)])
                    context.fill(shard, with: .color(teal.opacity(0.55)))
                    context.stroke(shard, with: .color(mint.opacity(0.85)), lineWidth: unit * 0.006)
                }
            default: break
            }
            let coreY = form == .sprout ? 0.67 : 0.49
            context.fill(ellipse(0.42, coreY - 0.08, 0.16, 0.16),
                with: .radialGradient(Gradient(colors: [.white, mint.opacity(0.8), teal.opacity(0)]),
                    center: point(0.5, coreY), startRadius: 0, endRadius: unit * 0.08))
            context.fill(ellipse(0.481, coreY - 0.019, 0.038, 0.038), with: .color(.white))
        }
    }
}

private struct CompanionSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0.50, y: 0.08))
            path.addCurve(to: CGPoint(x: 0.88, y: 0.60), control1: CGPoint(x: 0.80, y: 0.06), control2: CGPoint(x: 0.91, y: 0.30))
            path.addCurve(to: CGPoint(x: 0.72, y: 0.83), control1: CGPoint(x: 0.88, y: 0.77), control2: CGPoint(x: 0.82, y: 0.88))
            path.addCurve(to: CGPoint(x: 0.52, y: 0.82), control1: CGPoint(x: 0.62, y: 0.79), control2: CGPoint(x: 0.62, y: 0.78))
            path.addCurve(to: CGPoint(x: 0.27, y: 0.87), control1: CGPoint(x: 0.36, y: 0.90), control2: CGPoint(x: 0.28, y: 0.96))
            path.addCurve(to: CGPoint(x: 0.13, y: 0.56), control1: CGPoint(x: 0.14, y: 0.84), control2: CGPoint(x: 0.09, y: 0.74))
            path.addCurve(to: CGPoint(x: 0.50, y: 0.08), control1: CGPoint(x: 0.15, y: 0.26), control2: CGPoint(x: 0.23, y: 0.09))
            path.closeSubpath()
        }.applying(CGAffineTransform(scaleX: rect.width, y: rect.height))
    }
}

private struct RibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0.72, y: 0.85))
            path.addCurve(to: CGPoint(x: 0.32, y: 0.62), control1: CGPoint(x: 0.44, y: 0.88), control2: CGPoint(x: 0.34, y: 0.73))
            path.addCurve(to: CGPoint(x: 0.56, y: 0.18), control1: CGPoint(x: 0.17, y: 0.28), control2: CGPoint(x: 0.32, y: 0.04))
            path.addCurve(to: CGPoint(x: 0.44, y: 0.63), control1: CGPoint(x: 0.85, y: 0.36), control2: CGPoint(x: 0.80, y: 0.63))
            path.addCurve(to: CGPoint(x: 0.25, y: 0.88), control1: CGPoint(x: 0.20, y: 0.62), control2: CGPoint(x: 0.16, y: 0.73))
        }.applying(CGAffineTransform(scaleX: rect.width, y: rect.height))
    }
}

private struct InkShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0.65, y: 0.07))
            path.addCurve(to: CGPoint(x: 0.80, y: 0.69), control1: CGPoint(x: 0.62, y: 0.36), control2: CGPoint(x: 0.91, y: 0.37))
            path.addCurve(to: CGPoint(x: 0.56, y: 0.83), control1: CGPoint(x: 0.75, y: 0.84), control2: CGPoint(x: 0.66, y: 0.85))
            path.addCurve(to: CGPoint(x: 0.15, y: 0.80), control1: CGPoint(x: 0.38, y: 0.79), control2: CGPoint(x: 0.20, y: 0.92))
            path.addCurve(to: CGPoint(x: 0.65, y: 0.07), control1: CGPoint(x: 0.08, y: 0.52), control2: CGPoint(x: 0.32, y: 0.20))
            path.closeSubpath()
        }.applying(CGAffineTransform(scaleX: rect.width, y: rect.height))
    }
}

private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addQuadCurve(to: CGPoint(x: rect.width, y: 0), control: CGPoint(x: rect.midX, y: rect.height * 1.5))
        }
    }
}
