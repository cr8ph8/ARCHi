import SwiftUI

/// A reversible expression preference, never a new identity or a growth commit.
@MainActor
struct ProtoAppearanceCard: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Body expression").font(.system(size: 17, weight: .medium))
                Text("Choose KIN’s garnet expression or the original long-eared aqua Proto. His Core Seed, lessons and Journey stay with him.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(spacing: 18) {
                    choice(.original, title: "KIN")
                    choice(.protoStudy, title: "ARCHi Proto")
                }
                Text(store.presentationForm == .kin
                     ? "This changes the expression of your kept First Light body."
                     : "Body previews. Your current Seed stays unchanged; the selected expression is used when you keep First Light.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if store.preferences.visualTreatment == .protoStudy && CompanionVisualAsset.protoImage == nil {
                    Text("Proto artwork is unavailable. KIN’s existing body is shown.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }.accessibilityIdentifier("proto-expression.card")
    }

    private func choice(_ treatment: CompanionVisualTreatment, title: String) -> some View {
        let selected = treatment == .protoStudy ? store.preferences.visualTreatment == .protoStudy
            : store.preferences.visualTreatment != .protoStudy
        return Button {
            store.preferences.visualTreatment = treatment
        } label: {
            VStack(spacing: 8) {
                CompanionPresenceArt(form: .kin, family: nil, size: 112, reduceMotion: true, treatment: treatment)
                    .accessibilityHidden(true)
                Label(title, systemImage: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity).padding(12)
            .background(WorkspaceTheme.accent.opacity(selected ? 0.3 : 0.08), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(selected ? WorkspaceTheme.accent : .secondary.opacity(0.2)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose \(title) body expression")
        .accessibilityHint("Changes appearance only. The Seed cursor and growth milestone are unchanged.")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(treatment == .protoStudy ? "proto-expression.proto" : "proto-expression.kin")
    }
}
