import SwiftUI

/// Record identity, layout and support come from the same projection as the map.
/// Original art remains the companion's body, not a memory store.
enum CompanionMemoryParticles {
    static func applies(form: CompanionForm, family: EvolutionFamily?, treatment: CompanionVisualTreatment) -> Bool {
        family == nil && (form == .kin || form == .kinSeed || form == .particleSeed || form == .corePearl
            || form == .hamptonSeed || (form == .companion && treatment == .protoStudy))
    }
}

struct CompanionParticleSelection: Equatable {
    let originDigest: String
    let graphDigest: String
    let nodeID: String

    func selectedID(in scene: CompanionParticleScene) -> String? {
        guard scene.originDigest == originDigest, scene.graphDigest == graphDigest,
              scene.graph.nodes.contains(where: { $0.id == nodeID }) else { return nil }
        return nodeID
    }
}

struct CompanionMemoryParticleField: View {
    let scene: CompanionParticleScene
    let reduceMotion: Bool
    var seedColor: CompanionSeedColor = .original
    var selectedID: String?
    var onSelect: ((String) -> Void)?

    var body: some View {
        KnowledgeParticleView(field: scene.field, nodes: scene.graph.nodes, selectedID: selectedID,
            spread: 0, pulses: !reduceMotion, reduceMotion: reduceMotion, tint: seedColor.accent,
            showsLabels: false, compact: true, interactive: onSelect != nil,
            growthByRecordID: scene.growthByRecordID, onSelect: { onSelect?($0) })
    }
}

/// Captures presentation choices for unfolding the current Seed into its map.
/// Folding never changes saved identity, form, equipment or personal color.
struct CompanionParticleAppearance {
    let form: CompanionForm
    let family: EvolutionFamily?
    let treatment: CompanionVisualTreatment
    let recipe: CompanionAppearanceRecipe?
    let naturalVariation: CompanionNaturalVariation?
    let equipment: CompanionEquipment
    let seedColor: CompanionSeedColor

    @MainActor init(store: CompanionStore) {
        form = store.presentationForm(for: store.preferences, role: .cursor)
        family = store.presentationFamily
        treatment = store.preferences.visualTreatment
        recipe = store.presentationRecipe
        naturalVariation = store.presentationNaturalVariation
        equipment = store.preferences.equipment
        seedColor = store.preferences.seedColor
    }

    @MainActor func art(size: CGFloat, reduceMotion: Bool) -> some View {
        CompanionPresenceArt(form: form, family: family, size: size, reduceMotion: reduceMotion,
            treatment: treatment, recipe: recipe, naturalVariation: naturalVariation,
            equipment: equipment, seedColor: seedColor)
            .environment(\.companionParticleScene, nil)
            .environment(\.liminalPointStructure, nil)
            .environment(\.liminalPointProgress, LiminalV008Runtime.orbProgress)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct CompanionParticleSceneKey: EnvironmentKey { static let defaultValue: CompanionParticleScene? = nil }
private struct CompanionParticleSelectionKey: EnvironmentKey { static let defaultValue: CompanionParticleSelection? = nil }
extension EnvironmentValues {
    var companionParticleScene: CompanionParticleScene? {
        get { self[CompanionParticleSceneKey.self] }
        set { self[CompanionParticleSceneKey.self] = newValue }
    }
    var companionParticleSelection: CompanionParticleSelection? {
        get { self[CompanionParticleSelectionKey.self] }
        set { self[CompanionParticleSelectionKey.self] = newValue }
    }
}

@MainActor extension CompanionStore {
    func companionParticleScene(at date: Date = Date()) -> CompanionParticleScene? {
        guard let development = liminalFormDevelopment(at: date) else { particleSceneCache = nil; return nil }
        let graph = memoryMapSnapshot(at: date)
        guard let digest = CompanionParticleScene.fingerprint(originDigest: development.originDigest,
            graph: graph, development: development) else { particleSceneCache = nil; return nil }
        if particleSceneCache?.digest == digest { return particleSceneCache }
        particleSceneCache = CompanionParticleScene.build(originDigest: development.originDigest,
            graph: graph, development: development)
        return particleSceneCache
    }

}
