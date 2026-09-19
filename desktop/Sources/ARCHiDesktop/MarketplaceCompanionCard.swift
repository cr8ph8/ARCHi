import SwiftUI

/// A projection of the existing companion and the two outfit lifetimes. Merely
/// browsing the Marketplace must never equip, retain, or create an individual.
@MainActor
struct MarketplaceCompanionCard: View {
    @ObservedObject var store: CompanionStore
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var companionName: String { store.activeQiMon?.name ?? "ARCHi" }
    private var still: Bool { systemReduceMotion || store.preferences.reduceMotion || store.preferences.quiet }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle().stroke(WorkspaceTheme.accent.opacity(0.10), lineWidth: 1)
                    .frame(width: 92, height: 92)
                Circle().stroke(WorkspaceTheme.accent.opacity(0.18), lineWidth: 1)
                    .frame(width: 71, height: 71)
                CompanionPresenceArt(form: store.presentationForm, family: store.presentationFamily,
                    size: 94, reduceMotion: still, treatment: store.preferences.visualTreatment,
                    recipe: store.presentationRecipe, naturalVariation: store.presentationNaturalVariation,
                    equipment: store.preferences.equipment, lightExpression: store.kinLightExpression, seedColor: store.preferences.seedColor)
            }
            .frame(width: 104, height: 104)
            .background {
                RadialGradient(colors: [WorkspaceTheme.accent.opacity(0.10), .clear],
                    center: .center, startRadius: 12, endRadius: 82)
                    .clipShape(Circle())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(companionName), current companion appearance. \(store.preferences.equipment.item?.title ?? "No item equipped").")
            .accessibilityIdentifier("marketplace.companion.preview")

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(companionName).font(.system(size: 16, weight: .medium))
                    Spacer(minLength: 0)
                }
                Text("Wearing now: \(store.preferences.equipment.item?.title ?? "No item")")
                    .font(.system(size: 12, weight: .medium))
                    .accessibilityIdentifier("marketplace.outfit.current")
                Label(nextVisitOutfit, systemImage: store.marketplaceOutfitReadable ? "bookmark" : "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("marketplace.outfit.saved")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) { destinations }
                    VStack(alignment: .leading, spacing: 9) { destinations }
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(WorkspaceSurface(emphasis: true))
    }

    @ViewBuilder private var destinations: some View {
        Button("Review saved choices", systemImage: "bookmark") { store.open(.memory) }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("marketplace.outfit.review")
        Button("Arena & room", systemImage: "gamecontroller") { store.open(.unity) }
            .buttonStyle(.borderless)
            .accessibilityHint("Open the Arena and companion room.")
            .accessibilityIdentifier("marketplace.open-unity")
    }

    private var nextVisitOutfit: String {
        guard store.marketplaceOutfitReadable else {
            return "Next visit: saved outfit unavailable. Review profile recovery in What I remember."
        }
        guard let saved = store.savedMarketplaceEquipment else { return "Next visit: no saved outfit" }
        return "Next visit: \(saved.item?.title ?? "No item") · saved"
    }
}
