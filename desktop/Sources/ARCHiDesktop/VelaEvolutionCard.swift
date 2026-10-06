import SwiftUI

/// A visual possibility for the same continuing core. Selection uses the
/// existing appearance owner; this card cannot commit personal development.
@MainActor
struct VelaEvolutionCard: View {
    @ObservedObject var store: CompanionStore

    private var usesVelaSeed: Bool {
        store.activeQiMon != nil ? store.preferences.seedAppearance == .vela
            : store.presentationFamily == nil && store.presentationForm == .velaSeed
    }

    var body: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 18) {
                header
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
                    stage(form: .velaSeed, number: "01", title: "Opal Seed", label: "A beginning",
                          detail: "Folded light. A warm heart waiting to unfold.")
                    stage(form: .velaLantern, number: "02", title: "Lantern Wing", label: "Visual potential",
                          detail: "Translucent wings open around the same bright core.")
                }
                Text("Lantern Wing is a potential form study. Viewing or choosing these looks does not award growth or change your companion’s identity.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                actions
            }
        }
        .accessibilityIdentifier("vela-evolution.card")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("A NEW LIGHT", systemImage: "sparkle")
                .font(.system(size: 10, weight: .semibold)).tracking(1.8)
                .foregroundStyle(WorkspaceTheme.accent)
            Text("Vela").font(.system(size: 30, weight: .medium, design: .rounded))
            Text("From a quiet opal to a little lantern of light.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    private func stage(form: CompanionForm, number: String, title: String, label: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(number).font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(label).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WorkspaceTheme.accent)
            }
            CompanionPresenceArt(form: form, family: nil, size: 168,
                reduceMotion: store.preferences.reduceMotion || store.preferences.quiet,
                seedColor: store.preferences.seedColor)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            Text(title).font(.system(size: 17, weight: .medium, design: .rounded))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 32, alignment: .topLeading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: [WorkspaceTheme.accent.opacity(0.12), WorkspaceTheme.accent.opacity(0.025)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(WorkspaceTheme.accent.opacity(0.18)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(form == .velaSeed ? "vela-evolution.seed" : "vela-evolution.lantern")
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button(usesVelaSeed ? "Vela Seed selected" : "Use Vela Seed",
                       systemImage: usesVelaSeed ? "checkmark.circle.fill" : "sparkle") {
                    store.chooseSeedAppearance(.vela)
                }
                .buttonStyle(.borderedProminent)
                .disabled(usesVelaSeed || (store.hasPersonalQiMon && store.activeQiMon == nil))
                .accessibilityHint("Changes your Seed appearance while keeping the same companion and development history.")
                .accessibilityIdentifier("vela-evolution.use-seed")
                if store.canChooseStartingForm {
                    Button("Try Lantern study") { store.chooseStartingForm(.velaLantern) }
                        .disabled(store.presentationFamily == nil && store.presentationForm == .velaLantern)
                        .accessibilityHint("Shows the Lantern Wing form study without awarding growth.")
                        .accessibilityIdentifier("vela-evolution.try-lantern")
                }
            }
            if store.presentationForm == .kin && store.preferences.seedAppearance == .vela {
                Text("Vela lights your Seed cursor. Your kept First Light body remains available.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}
