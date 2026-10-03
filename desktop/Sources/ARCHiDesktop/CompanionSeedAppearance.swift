import SwiftUI

/// An appearance preference, never a second individual or a development record.
enum CompanionSeedAppearance: String, CaseIterable, Codable, Identifiable {
    case archiLight, kinParticles, hamptonLiminal, vela
    var id: Self { self }
    var title: String {
        switch self {
        case .archiLight: "ARCHi · Ball of Light"
        case .kinParticles: "KIN · Particle Seed"
        case .hamptonLiminal: "Hampton · Liminal Seed"
        case .vela: "Vela · Opal Seed"
        }
    }
    var detail: String {
        switch self {
        case .archiLight: "Light sphere · inner constellation"
        case .kinParticles: "Open particle field · pearl core"
        case .hamptonLiminal: "Luminous shell · gold connections"
        case .vela: "Opal light · folded lantern wings"
        }
    }
    var starterForm: CompanionForm {
        switch self {
        case .archiLight: .corePearl
        case .kinParticles: .particleSeed
        case .hamptonLiminal: .hamptonSeed
        case .vela: .velaSeed
        }
    }
    var personalForm: CompanionForm { self == .kinParticles ? .kinSeed : starterForm }
}

/// The Blender portrait keeps its exact core and proportions. The shared Seed
/// clock supplies bounded rotation and focus settling, including Reduce Motion.
struct ArchiLightSeedArt: View {
    let size: CGFloat
    let reduceMotion: Bool
    var lightExpression: KinLightExpression = .resting
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.companionSeedColor) private var seedColor
    @State private var motion: KinSeedMotion?
    private var policy: KinSeedMotion.Policy {
        .init(mode: lightExpression.mode, reduceMotion: reduceMotion, systemReduceMotion: systemReduceMotion)
    }
    var body: some View {
        let still = reduceMotion || systemReduceMotion
        TimelineView(.animation(minimumInterval: 1 / 24, paused: still)) { _ in
            let angle = still ? 0 : motion?.sample(at: ProcessInfo.processInfo.systemUptime).angle ?? 0
            Group {
                if let image = SeedColorRendering.image(for: .corePearl, color: seedColor) {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                        .rotationEffect(.degrees(angle))
                } else {
                    LightFormFrame(form: .corePearl, phase: 0)
                        .modifier(SeedFallbackColor(color: seedColor))
                }
            }
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
        .accessibilityLabel("ARCHi, ball of light")
    }
}

/// The three supported presentation families share the existing companion owner.
/// Archived seed preferences still decode, but are not promoted as new identities.
struct SeedAppearanceCard: View {
    @ObservedObject var store: CompanionStore
    var body: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Companion form").font(.system(size: 23, weight: .medium, design: .rounded))
                Text("Proto, KIN and Liminal are forms of your continuing companion. Choose its presentation here; its identity, memories and reviewed outcomes stay together.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
                    ForEach(CompanionPresentationStyle.allCases) { style in
                        choice(style)
                    }
                }
                if store.companionPresentationStyle == nil {
                    Text("Your saved appearance is still in use. Choose Proto, KIN or Liminal when you want to change it; no saved form has been replaced.")
                        .font(.callout).foregroundStyle(.secondary)
                        .accessibilityIdentifier("companion-form.saved-appearance")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Presentation", selection: Binding(
                        get: { store.companionPresentationPose },
                        set: { store.chooseCompanionPresentationPose($0) })) {
                        ForEach(CompanionPresentationPose.allCases) { pose in
                            Text(pose.title).tag(pose)
                                .disabled(pose == .body && !store.canPresentCompanionBody)
                        }
                    }
                    .pickerStyle(.segmented).frame(maxWidth: 330)
                    .disabled(store.companionPresentationStyle == nil)
                    .accessibilityIdentifier("companion-form.pose")
                    Text(store.canPresentCompanionBody
                         ? "Seed is the compact form and desktop cursor. Body previews the same companion in its body form; choosing it does not award growth."
                         : "Seed is the compact form and desktop cursor. Body preview is unavailable for the current form. Your kept development stays in QiMon development.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    if store.companionPresentationStyle == .liminal {
                        Text("Choose Liminal’s curled or beast shape in Living constellation below.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("QiMon development & forms") { store.open(.evolution) }
                            .accessibilityIdentifier("companion-form.open-development")
                        Button("Room & Arena") { store.open(.unity) }
                            .accessibilityIdentifier("companion-form.open-worlds")
                    }.buttonStyle(.borderless)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Seed color", selection: Binding(get: { store.preferences.seedColor }, set: { store.chooseSeedColor($0) })) {
                        ForEach(CompanionSeedColor.allCases) { color in
                            Text(color.title).tag(color)
                        }
                    }
                    .frame(maxWidth: 330)
                    .accessibilityIdentifier("seed-color.picker")
                    Text("Color follows your Seed and cursor. Original keeps the artwork’s colors. Color and form choices do not award experience.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("Keep appearance for next time") { store.rememberPreferences = true; store.savePreferences() }
                        .accessibilityIdentifier("seed-color.keep")
                    Text(store.status).font(.caption).foregroundStyle(.secondary)
                }
            }
        }.accessibilityIdentifier("seed-appearance.card")
    }
    private func choice(_ style: CompanionPresentationStyle) -> some View {
        let selected = store.companionPresentationStyle == style
        return Button { store.chooseCompanionPresentationStyle(style) } label: {
            VStack(spacing: 8) {
                CompanionPresenceArt(form: style.seedForm, family: nil, size: 144, reduceMotion: true,
                    treatment: style.treatment, seedColor: store.preferences.seedColor)
                    .accessibilityHidden(true)
                Label(style.title, systemImage: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .medium))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Text(style.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16).padding(.horizontal, 10)
            .background(WorkspaceTheme.accent.opacity(selected ? 0.20 : 0.06), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(selected ? WorkspaceTheme.accent : .secondary.opacity(0.2), lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .disabled(store.hasPersonalQiMon && store.activeQiMon == nil)
        .accessibilityLabel("Choose \(style.title) form")
        .accessibilityHint("Keeps the same companion, memories and reviewed outcomes.")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("companion-form.\(style.id)")
    }
}
