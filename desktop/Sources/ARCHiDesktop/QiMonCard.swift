import SwiftUI

/// A personal companion record, never an entry in the starter-art catalogue.
@MainActor
struct QiMonCard: View {
    @ObservedObject var store: CompanionStore
    var compact = false

    var body: some View {
        if let kin = store.activeQiMon {
            let form = store.presentationForm
            let formLabel = store.kinBodyTitle
            let accent = Color(red: 0.94, green: 0.72, blue: 0.40)
            HStack(spacing: compact ? 18 : 28) {
                CompanionPresenceArt(form: form, family: store.presentationFamily, size: compact ? 88 : 192,
                    reduceMotion: store.preferences.reduceMotion || store.preferences.quiet,
                    treatment: store.preferences.visualTreatment, recipe: store.presentationRecipe,
                    naturalVariation: store.presentationNaturalVariation, equipment: store.preferences.equipment,
                    lightExpression: store.kinLightExpression, seedColor: store.preferences.seedColor)
                    .accessibilityLabel("\(kin.name), your QiMon, \(formLabel)")
                    .accessibilityValue(store.kinLightExpression.label)
                VStack(alignment: .leading, spacing: 10) {
                    Text("YOUR QIMON").font(.system(size: 10, weight: .semibold)).tracking(2)
                        .foregroundStyle(accent)
                    Text(kin.name).font(.system(size: compact ? 28 : 42, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                    Text("\(formLabel) · \(kin.character == .hampton ? kin.dedication : "Hampton’s companion")").font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                    if form == .kin && CompanionVisualAsset.usesProto(store.preferences.visualTreatment) {
                        Text("Proto expression").font(.system(size: 11)).foregroundStyle(accent)
                    }
                    Text("Desktop cursor · \(kin.stageTitle)").font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .accessibilityIdentifier("kin-cursor-form")
                    Text(store.kinLightExpression.label)
                        .font(.system(size: 11)).foregroundStyle(accent)
                        .accessibilityIdentifier("kin-light-expression")
                    if !compact {
                        Text("One beginning. Room to grow together.")
                            .font(.system(size: 14)).foregroundStyle(.white.opacity(0.75))
                        Text("Welcomed \(kin.welcomedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                    }
                    HStack(spacing: 14) {
                        if store.allowsPlay { Button("Visit Habitat") { store.open(.play) } }
                        if store.section != .evolution {
                            Button("Life with \(kin.name)") { store.open(.evolution) }
                        }
                    }.buttonStyle(.borderless).tint(accent)
                        .font(.system(size: 12, weight: .medium)).padding(.top, 5)
                }
                Spacer(minLength: 0)
            }
            .padding(compact ? 18 : 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors:
                [Color(red: 0.055, green: 0.035, blue: 0.035), Color(red: 0.15, green: 0.055, blue: 0.085)],
                startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(accent.opacity(0.28)))
            .accessibilityIdentifier("personal-qimon-card")
        } else if store.keptQiMon != nil {
            WorkspaceCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your saved QiMon").font(.system(size: 17, weight: .medium))
                    Text("Open the Journey this companion belongs to, and \(store.keptQiMon?.name ?? "your companion") will return with it.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    if store.allowsPlay { Button("Open Habitat") { store.open(.play) }.buttonStyle(.borderless) }
                }
            }
        }
    }
}
