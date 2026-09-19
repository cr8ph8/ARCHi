import SwiftUI

/// Native artwork for small desktop sizes. The same drawing is snapshotted for
/// Habitat; it has no identity, progression, or assistant authority of its own.
struct KinArt: View {
    let form: CompanionForm
    let size: CGFloat
    let reduceMotion: Bool
    var lightExpression: KinLightExpression = .resting
    var treatment: CompanionVisualTreatment = .original
    var seedColor: CompanionSeedColor = .original
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        Group {
            if form == .kinSeed || form == .kin {
                // One stable view and attention clock survive Keep/Return/Resume.
                KinLivingPortrait(form: form == .kin ? .firstLight : .seed, size: size,
                    reduceMotion: reduceMotion, lightExpression: lightExpression,
                    bodyImage: CompanionVisualAsset.firstLightImage(treatment: treatment))
            } else {
                TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion || systemReduceMotion)) { time in
                    KinDrawing(spark: form == .kinSpark, detailed: form == .kin)
                        .offset(y: reduceMotion || systemReduceMotion ? 0 : sin(time.date.timeIntervalSinceReferenceDate * 1.4) * size * 0.014)
                }
            }
        }
        .environment(\.companionSeedColor, seedColor)
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CompanionVisualAsset.label(form: form, family: nil, treatment: treatment, seedColor: seedColor))
    }
}

/// Retained entry point for reviewed-body/fallback previews. Its source image is
/// injected only for local verification, never through a user asset importer.
struct KinFirstLightPortrait: View {
    let size: CGFloat
    let reduceMotion: Bool
    let lightExpression: KinLightExpression
    let bodyImage: NSImage?

    var body: some View {
        KinLivingPortrait(form: .firstLight, size: size, reduceMotion: reduceMotion,
            lightExpression: lightExpression, bodyImage: bodyImage)
    }
}

private struct KinLivingPortrait: View {
    let form: KinPresentationTransition.Form
    let size: CGFloat
    let reduceMotion: Bool
    let lightExpression: KinLightExpression
    let bodyImage: NSImage?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var motion: KinSeedMotion?
    @State private var transition: KinPresentationTransition?

    private var motionPolicy: KinSeedMotion.Policy {
        .init(mode: lightExpression.mode, reduceMotion: reduceMotion, systemReduceMotion: systemReduceMotion)
    }
    private var transitionPolicy: KinPresentationTransition.Policy {
        .init(reduceMotion: reduceMotion, systemReduceMotion: systemReduceMotion)
    }

    var body: some View {
        let still = reduceMotion || systemReduceMotion
        TimelineView(.animation(minimumInterval: 1 / 24, paused: still)) { _ in
            let now = ProcessInfo.processInfo.systemUptime
            let pose = motion?.sample(at: now) ?? KinSeedMotion(at: 0, policy: motionPolicy).sample(at: 0)
            // A static render/export always contains the exact requested body.
            let sample = still ? KinPresentationTransition(form: form).sample(at: 0)
                : (transition?.sample(at: now) ?? KinPresentationTransition(form: form).sample(at: 0))
            KinPresentationFrame(size: size, pose: pose, sample: sample,
                reduceMotion: still, lightExpression: lightExpression, bodyImage: bodyImage)
        }
        .frame(width: size, height: size)
        .onChange(of: motionPolicy, initial: true) { _, policy in
            let now = ProcessInfo.processInfo.systemUptime
            if motion == nil { motion = KinSeedMotion(at: now, policy: policy) }
            else { motion?.transition(to: policy, at: now) }
        }
        .onChange(of: form, initial: true) { _, _ in updateTransition() }
        .onChange(of: transitionPolicy) { _, _ in updateTransition() }
    }

    private func updateTransition() {
        let now = ProcessInfo.processInfo.systemUptime
        if transition == nil { transition = KinPresentationTransition(form: form, policy: transitionPolicy, at: now) }
        else { transition?.transition(to: form, policy: transitionPolicy, at: now) }
    }
}

/// Shared render frame for current portraits, their reversible transition, and
/// deterministic visual checks. Only the approved portraits are dissolved. The
/// same light expression follows their common pearl; there are no two identities.
struct KinPresentationFrame: View {
    let size: CGFloat
    let pose: KinSeedMotion.Sample
    let sample: KinPresentationTransition.Sample
    let reduceMotion: Bool
    let lightExpression: KinLightExpression
    let bodyImage: NSImage?
    @Environment(\.companionSeedColor) private var seedColor

    var body: some View {
        let progress = sample.bodyAmount
        let float = KinFirstLightPresentation.verticalOffset(for: pose) * size * progress
        ZStack {
            if sample.seedOpacity > 0 {
                Group {
                    if let image = SeedColorRendering.image(for: .kinSeed, color: seedColor) {
                        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                            .rotationEffect(.degrees(pose.angle))
                    } else {
                        KinCoreSeedFrame(phase: pose.radians)
                            .modifier(SeedFallbackColor(color: seedColor, sourceHue: 0.105))
                    }
                }
                .frame(width: size, height: size)
                .scaleEffect(sample.seedScale)
                .offset(x: size * (sample.coreX - 0.5), y: size * (sample.coreY - 0.5) + float)
                .opacity(sample.seedOpacity)
            }
            if sample.bodyOpacity > 0 {
                Group {
                    if let bodyImage {
                        Image(nsImage: bodyImage).resizable().interpolation(.high).scaledToFit()
                    } else {
                        KinDrawing(spark: false, detailed: true)
                    }
                }
                .frame(width: size, height: size)
                .scaleEffect(sample.bodyScale)
                .offset(x: size * (sample.coreX - (0.5 + (KinFirstLightPresentation.coreX - 0.5) * sample.bodyScale)),
                    y: size * (sample.coreY - (0.5 + (KinFirstLightPresentation.coreY - 0.5) * sample.bodyScale)) + float)
                .opacity(sample.bodyOpacity)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if lightExpression.mode != .rest {
                KinLightEffects(expression: lightExpression,
                    size: size * (1 + (KinFirstLightPresentation.effectScale - 1) * progress),
                    reduceMotion: reduceMotion,
                    centerY: CompanionVisualAsset.kinSeedImage == nil && progress == 0 ? 0.465 : 0.5)
                    .offset(x: size * (sample.coreX - 0.5), y: size * (sample.coreY - 0.5) + float)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
        // The sampled clock owns timing; a surrounding SwiftUI animation must
        // not tween these frames or delay an accessibility/Quiet stop.
        .transaction { $0.animation = nil }
    }
}

enum KinFirstLightPresentation {
    static let coreX = 0.52
    static let coreY = 0.62
    // The smaller field keeps its lower orbit inside the fixed native portrait.
    // Its existing protected center still fully contains KIN's opaque pearl.
    static let effectScale = 0.78

    static func verticalOffset(for pose: KinSeedMotion.Sample) -> CGFloat {
        // An integer cycle count remains continuous as the shared clock wraps.
        CGFloat(sin(pose.radians * 18) * 0.014)
    }
}

private struct KinDrawing: View {
    let spark: Bool
    let detailed: Bool
    private let garnet = Color(red: 0.52, green: 0.035, blue: 0.15)
    private let plum = Color(red: 0.23, green: 0.025, blue: 0.13)
    private let gold = Color(red: 1, green: 0.73, blue: 0.34)

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height)
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale)
            }
            var body = Path()
            if spark {
                body.move(to: pt(0.31, 0.35))
                body.addCurve(to: pt(0.60, 0.29), control1: pt(0.24, 0.24), control2: pt(0.49, 0.19))
                body.addCurve(to: pt(0.73, 0.65), control1: pt(0.77, 0.42), control2: pt(0.77, 0.54))
                body.addCurve(to: pt(0.74, 0.74), control1: pt(0.83, 0.72), control2: pt(0.80, 0.77))
                body.addQuadCurve(to: pt(0.68, 0.72), control: pt(0.70, 0.77))
                body.addCurve(to: pt(0.69, 0.85), control1: pt(0.68, 0.79), control2: pt(0.75, 0.83))
                body.addQuadCurve(to: pt(0.54, 0.84), control: pt(0.62, 0.91))
                body.addQuadCurve(to: pt(0.35, 0.87), control: pt(0.44, 0.93))
                body.addQuadCurve(to: pt(0.32, 0.74), control: pt(0.27, 0.84))
                body.addCurve(to: pt(0.25, 0.71), control1: pt(0.20, 0.79), control2: pt(0.19, 0.76))
                body.addQuadCurve(to: pt(0.33, 0.64), control: pt(0.27, 0.66))
                body.addCurve(to: pt(0.36, 0.43), control1: pt(0.24, 0.57), control2: pt(0.29, 0.49))
                body.addQuadCurve(to: pt(0.31, 0.35), control: pt(0.47, 0.29))
            } else {
                body.move(to: pt(0.31, 0.22))
                body.addCurve(to: pt(0.64, 0.15), control1: pt(0.23, 0.13), control2: pt(0.54, 0.035))
                body.addCurve(to: pt(0.70, 0.47), control1: pt(0.73, 0.24), control2: pt(0.81, 0.39))
                body.addQuadCurve(to: pt(0.62, 0.52), control: pt(0.67, 0.50))
                body.addCurve(to: pt(0.78, 0.69), control1: pt(0.60, 0.57), control2: pt(0.79, 0.58))
                body.addCurve(to: pt(0.67, 0.73), control1: pt(0.83, 0.81), control2: pt(0.70, 0.81))
                body.addLine(to: pt(0.64, 0.67))
                body.addCurve(to: pt(0.68, 0.84), control1: pt(0.68, 0.78), control2: pt(0.60, 0.78))
                body.addCurve(to: pt(0.65, 0.91), control1: pt(0.79, 0.89), control2: pt(0.76, 0.94))
                body.addQuadCurve(to: pt(0.52, 0.88), control: pt(0.57, 0.91))
                body.addCurve(to: pt(0.30, 0.93), control1: pt(0.48, 0.97), control2: pt(0.35, 0.97))
                body.addCurve(to: pt(0.36, 0.78), control1: pt(0.20, 0.88), control2: pt(0.37, 0.84))
                body.addLine(to: pt(0.36, 0.69))
                body.addCurve(to: pt(0.23, 0.73), control1: pt(0.32, 0.81), control2: pt(0.19, 0.82))
                body.addCurve(to: pt(0.38, 0.52), control1: pt(0.16, 0.65), control2: pt(0.38, 0.58))
                body.addCurve(to: pt(0.34, 0.33), control1: pt(0.21, 0.47), control2: pt(0.29, 0.40))
                body.addQuadCurve(to: pt(0.31, 0.22), control: pt(0.45, 0.18))
            }
            body.closeSubpath()
            context.fill(body, with: .linearGradient(Gradient(colors: [garnet, plum]),
                startPoint: pt(0.24, 0.3), endPoint: pt(0.77, 0.8)))
            context.stroke(body, with: .color(gold), style: StrokeStyle(lineWidth: scale * 0.013, lineCap: .round, lineJoin: .round))
            let eyeY: CGFloat = spark ? 0.51 : 0.36
            for (x, tilt): (CGFloat, CGFloat) in [(0.40, 1), (0.62, -1)] {
                var eye = Path()
                eye.move(to: pt(x - 0.045, eyeY - 0.012 * tilt))
                eye.addQuadCurve(to: pt(x + 0.043, eyeY + 0.025 * tilt), control: pt(x + 0.015, eyeY - 0.048))
                eye.addQuadCurve(to: pt(x - 0.045, eyeY - 0.012 * tilt), control: pt(x - 0.02, eyeY + 0.052))
                context.fill(eye, with: .color(gold))
            }
            var smile = Path()
            smile.move(to: pt(0.49, eyeY + 0.075))
            smile.addQuadCurve(to: pt(0.55, eyeY + 0.075), control: pt(0.52, eyeY + 0.104))
            context.stroke(smile, with: .color(gold), style: StrokeStyle(lineWidth: scale * 0.009, lineCap: .round))
            var brow = Path()
            brow.addArc(center: pt(0.57, spark ? 0.40 : 0.255), radius: scale * (spark ? 0.025 : 0.037),
                startAngle: .degrees(28), endAngle: .degrees(spark ? 238 : 320), clockwise: false)
            context.stroke(brow, with: .color(gold), style: StrokeStyle(lineWidth: scale * 0.010, lineCap: .round))
            let coreY: CGFloat = spark ? 0.71 : 0.62
            context.fill(Path(ellipseIn: rect(0.46, coreY - 0.06, 0.12, 0.12)), with: .color(gold.opacity(0.45)))
            context.fill(Path(ellipseIn: rect(0.477, coreY - 0.043, 0.086, 0.086)), with: .color(Color(red: 1, green: 0.96, blue: 0.79)))
            if detailed {
                var current = Path()
                current.move(to: pt(0.34, 0.18))
                current.addCurve(to: pt(0.52, 0.62), control1: pt(0.62, 0.06), control2: pt(0.16, 0.48))
                current.addCurve(to: pt(0.37, 0.90), control1: pt(0.78, 0.83), control2: pt(0.45, 0.92))
                context.stroke(current, with: .color(gold.opacity(0.6)), lineWidth: scale * 0.005)
                for index in 0..<9 {
                    let x = 0.37 + CGFloat((index * 7) % 19) / 80
                    let y = 0.20 + CGFloat((index * 13) % 49) / 85
                    context.fill(Path(ellipseIn: rect(x, y, 0.007, 0.007)), with: .color(gold))
                }
            }
        }
    }
}
