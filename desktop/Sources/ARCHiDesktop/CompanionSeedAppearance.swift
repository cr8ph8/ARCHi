import SwiftUI

/// An appearance preference, never a second individual or a development record.
enum CompanionSeedAppearance: String, CaseIterable, Codable, Identifiable {
    case archiLight, kinParticles, hamptonLiminal
    var id: Self { self }
    var title: String {
        switch self {
        case .archiLight: "ARCHi · Ball of Light"
        case .kinParticles: "KIN · Particle Seed"
        case .hamptonLiminal: "Hampton · Liminal Seed"
        }
    }
    var detail: String {
        switch self {
        case .archiLight: "Light sphere · inner constellation"
        case .kinParticles: "Open particle field · pearl core"
        case .hamptonLiminal: "Luminous shell · gold connections"
        }
    }
    var starterForm: CompanionForm {
        switch self {
        case .archiLight: .corePearl
        case .kinParticles: .particleSeed
        case .hamptonLiminal: .hamptonSeed
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

struct SeedAppearanceCard: View {
    @ObservedObject var store: CompanionStore
    var body: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose your light").font(.system(size: 23, weight: .medium, design: .rounded))
                Text("One core. Many forms. Your light stays with you as your companion takes shape.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    ForEach(CompanionSeedAppearance.allCases) { appearance in
                        choice(appearance)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Seed color", selection: Binding(get: { store.preferences.seedColor }, set: { store.chooseSeedColor($0) })) {
                        ForEach(CompanionSeedColor.allCases) { color in
                            Text(color.title).tag(color)
                        }
                    }
                    .frame(maxWidth: 330)
                    .accessibilityIdentifier("seed-color.picker")
                    Text("Applies to every Seed look and your desktop cursor. Original restores each design’s authored colors. Working and response cues keep their own meaning.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("Keep Seed color for next time") { store.rememberPreferences = true; store.savePreferences() }
                        .accessibilityIdentifier("seed-color.keep")
                    Text(store.status).font(.caption).foregroundStyle(.secondary)
                }
                if store.activeQiMon != nil {
                    HStack {
                        Text(store.presentationForm == .kin
                             ? "Your Seed cursor uses this light. Your kept body stays with you."
                             : "Your desktop companion and Seed cursor share this light.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        if store.presentationForm == .kin {
                            Button("Show as light") { store.returnKinToSeed() }
                                .accessibilityIdentifier("seed-appearance.show-light")
                        } else if store.activeQiMon?.character == .kin && store.evolution.kinGrowthRecord != nil {
                            Button("Resume First Light") { _ = store.resumeKinFirstLight() }
                                .accessibilityIdentifier("seed-appearance.resume-body")
                        }
                    }
                }
            }
        }.accessibilityIdentifier("seed-appearance.card")
    }
    private func choice(_ appearance: CompanionSeedAppearance) -> some View {
        let selected = store.activeQiMon != nil ? store.preferences.seedAppearance == appearance
            : store.presentationFamily == nil && store.presentationForm == appearance.starterForm
        return Button { store.chooseSeedAppearance(appearance) } label: {
            VStack(spacing: 8) {
                CompanionPresenceArt(form: appearance.starterForm, family: nil, size: 144, reduceMotion: true,
                    seedColor: store.preferences.seedColor)
                    .accessibilityHidden(true)
                Label(appearance.title, systemImage: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .medium))
                Text(appearance.detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16).padding(.horizontal, 10)
            .background(WorkspaceTheme.accent.opacity(selected ? 0.20 : 0.06), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(selected ? WorkspaceTheme.accent : .secondary.opacity(0.2), lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .disabled(store.hasPersonalQiMon && store.activeQiMon == nil)
        .accessibilityLabel("Choose \(appearance.title)")
        .accessibilityHint("Changes the light's appearance while keeping the same companion.")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("seed-appearance.\(appearance.rawValue)")
    }
}
