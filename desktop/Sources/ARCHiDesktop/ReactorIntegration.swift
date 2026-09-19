import AppKit
import SwiftUI

@MainActor
extension CompanionStore {
    func refreshReactorReference(family: EvolutionFamily? = nil, usesExplicitFamily: Bool = false) {
        let selectedFamily = hasPersonalQiMon ? nil : (usesExplicitFamily ? family : evolution.activeFamily)
        let recipe = presentationRecipe
        let id = CompanionVisualAsset.appearanceID(form: presentationForm, family: selectedFamily,
            treatment: preferences.visualTreatment, recipe: recipe, naturalVariation: presentationNaturalVariation,
            equipment: preferences.equipment, seedColor: preferences.seedColor)
        let bytes = reactor.appearanceID == id ? reactor.referencePNG : CompanionPresenceArt.png(
            form: presentationForm, family: selectedFamily, treatment: preferences.visualTreatment,
            recipe: recipe, naturalVariation: presentationNaturalVariation, equipment: preferences.equipment, seedColor: preferences.seedColor)
        reactor.updateReference(id: id,
            label: CompanionVisualAsset.label(form: presentationForm, family: selectedFamily,
                treatment: preferences.visualTreatment, recipe: recipe, naturalVariation: presentationNaturalVariation,
                equipment: preferences.equipment, seedColor: preferences.seedColor),
            png: bytes,
            motionAllowed: !preferences.quiet && !preferences.reduceMotion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            visible: isVisible && !(NSApp?.isHidden ?? false))
    }

    /// A candidate frame is usable only for the current body and equipped item.
    /// Preference changes may redraw SwiftUI before the reference observer runs.
    var reactorReferenceMatchesCurrentAppearance: Bool {
        reactor.appearanceID == CompanionVisualAsset.appearanceID(form: presentationForm, family: presentationFamily,
            treatment: preferences.visualTreatment, recipe: presentationRecipe,
            naturalVariation: presentationNaturalVariation, equipment: preferences.equipment, seedColor: preferences.seedColor)
    }
}

/// Candidate motion stays outside artwork exports and saved character identity.
@MainActor
struct LiveCompanionPresence: View {
    @ObservedObject var store: CompanionStore
    let size: CGFloat
    var role: CompanionPresentationRole = .body
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    var body: some View {
        let form = store.presentationForm(for: store.preferences, role: role)
        Group {
            // KIN's authored Seed and event-bound light remain native. A full
            // generated raster must not replace his body or contradict a cue.
            if !store.hasPersonalQiMon,
               !store.preferences.quiet && !store.preferences.reduceMotion && !systemReduceMotion,
               store.reactorReferenceMatchesCurrentAppearance,
               let image = store.reactor.frameImage {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                    .accessibilityLabel("ARCHi · " + CompanionVisualAsset.label(form: form,
                        family: store.presentationFamily, treatment: store.preferences.visualTreatment,
                        recipe: store.presentationRecipe, naturalVariation: store.presentationNaturalVariation,
                        equipment: store.preferences.equipment, seedColor: store.preferences.seedColor) + " · " + store.reactor.state.title)
            } else {
                CompanionPresenceArt(form: form, family: store.presentationFamily,
                    size: size, reduceMotion: store.preferences.reduceMotion || systemReduceMotion || store.preferences.quiet,
                    treatment: store.preferences.visualTreatment, recipe: store.presentationRecipe,
                    naturalVariation: store.presentationNaturalVariation, equipment: store.preferences.equipment,
                    lightExpression: store.kinLightExpression, seedColor: store.preferences.seedColor)
            }
        }.frame(width: size, height: size)
        .accessibilityValue(store.activeQiMon == nil ? "" : store.kinLightExpression.label)
    }
}
