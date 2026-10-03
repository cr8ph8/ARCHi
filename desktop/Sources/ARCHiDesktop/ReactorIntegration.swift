import AppKit
import SwiftUI

@MainActor
extension CompanionStore {
    func refreshReactorReference(family: EvolutionFamily? = nil, usesExplicitFamily: Bool = false) {
        reactor.refreshCurrentReference = { [weak self] in self?.refreshReactorReference() }
        let selectedFamily = hasPersonalQiMon ? nil : (usesExplicitFamily ? family : evolution.activeFamily)
        let recipe = presentationRecipe
        let reference = currentReactorReference(family: selectedFamily)
        let bytes = reactor.appearanceID == reference.id && reactor.referencePNG != nil ? reactor.referencePNG : CompanionPresenceArt.png(
            form: presentationForm, family: selectedFamily, treatment: preferences.visualTreatment,
            recipe: recipe, naturalVariation: presentationNaturalVariation, equipment: preferences.equipment, seedColor: preferences.seedColor,
            pointProgress: preferences.liminalPointProgress, pointStructure: reference.structure,
            memoryDevelopment: reference.memory)
        reactor.updateReference(id: reference.id,
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
        reactor.referencePNG != nil && reactor.appearanceID == currentReactorReference(family: presentationFamily).id
    }

    /// Capture current origin-bound evidence once so the cache key and pixels
    /// describe the same records. A failed replacement retires the old reference
    /// through Reactor's existing identity-change cancellation.
    private func currentReactorReference(family: EvolutionFamily?) -> (id: String, structure: LiminalPointStructure?, memory: LiminalFormDevelopment.Snapshot?) {
        let usesPoints = LiminalV008Runtime.applies(form: presentationForm, family: family, treatment: preferences.visualTreatment)
        let memoryApplies = !usesPoints && CompanionMemoryParticles.applies(form: presentationForm, family: family,
            treatment: preferences.visualTreatment)
        let snapshot = usesPoints || memoryApplies ? liminalFormDevelopment() : nil
        let structure = usesPoints ? LiminalV008Runtime.asset.flatMap { asset -> LiminalPointStructure? in
            guard let snapshot else { return nil }
            return LiminalPointStructure.make(snapshot, sessionID: liminalStructureSessionID,
                manifestSHA256: asset.manifestSHA256, lowDetailIDs: asset.lowDetailIDs)
        } : nil
        let memory = memoryApplies ? snapshot : nil
        let id = CompanionVisualAsset.appearanceID(form: presentationForm, family: family,
            treatment: preferences.visualTreatment, recipe: presentationRecipe,
            naturalVariation: presentationNaturalVariation, equipment: preferences.equipment, seedColor: preferences.seedColor,
            pointProgress: preferences.liminalPointProgress)
            + (structure.map { "-structure-" + $0.digest } ?? "")
            + (memory.map { "-memory-" + CompanionMemoryParticles.identity($0) } ?? "")
        return (id, structure, memory)
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
                    .environment(\.liminalPointProgress, role == .cursor ? LiminalV008Runtime.orbProgress : store.preferences.liminalPointProgress)
            }
        }.frame(width: size, height: size)
        .modifier(LiminalStructureScope(store: store))
        .accessibilityValue(store.activeQiMon == nil ? "" : store.kinLightExpression.label)
    }
}
