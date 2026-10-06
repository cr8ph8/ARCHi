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
    let sessionID: String
    let graphDigest: String
    let nodeID: String
    private let recordDigest: String

    init?(nodeID: String, in scene: CompanionParticleScene) {
        guard let node = scene.graph.nodes.first(where: { $0.id == nodeID }) else { return nil }
        originDigest = scene.originDigest
        sessionID = scene.sessionID
        graphDigest = scene.graphDigest
        self.nodeID = nodeID
        recordDigest = Self.digest(node)
    }

    func selectedID(in scene: CompanionParticleScene) -> String? {
        guard scene.originDigest == originDigest, scene.sessionID == sessionID,
              let node = scene.graph.nodes.first(where: { $0.id == nodeID }),
              Self.digest(node) == recordDigest else { return nil }
        // Unrelated graph edits need not erase this exact record's highlight.
        // Interaction callbacks still validate the complete displayed scene.
        return nodeID
    }

    private static func digest(_ node: CompanionGraphNode) -> String {
        LiminalKnowledgeBindings.digest(.init(nodes: [node], edges: [], truncatedCount: 0))
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

/// The floating companion is the map's connected record field at cursor scale.
/// A fixed drawing size keeps nodes and reviewed-use motifs legible as the user
/// resizes the panel. No second layout, record collection or growth state exists.
struct CompanionMemoryAvatar: View {
    let scene: CompanionParticleScene
    let size: CGFloat
    let reduceMotion: Bool
    var seedColor: CompanionSeedColor = .original
    var equipment: CompanionEquipment = .empty
    var expression: KinLightExpression = .resting
    var animationVisible: Bool? = nil
    var selectedID: String?
    var activity: CompanionParticleActivity = .empty

    var body: some View {
        ZStack {
            KnowledgeParticleView(field: scene.field, nodes: scene.graph.nodes, selectedID: selectedID,
                spread: 1, pulses: !reduceMotion, reduceMotion: reduceMotion, tint: seedColor.accent,
                showsLabels: false, expression: expression, preparedIDs: activity.preparedNodeIDs,
                requestIDs: activity.requestNodeIDs, interactive: false,
                growthByRecordID: scene.growthByRecordID, animationVisible: animationVisible, onSelect: { _ in })
                .frame(width: 256, height: 256)
                .scaleEffect(size / 256)
                .frame(width: size, height: size)
            if !equipment.isEmpty {
                CompanionEquipmentArt(equipment: equipment, size: size, activated: false,
                    reduceMotion: reduceMotion)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ARCHi memory avatar")
        .accessibilityValue("\(activity.preparedNodeIDs.count) prepared for next reply. \(activity.requestNodeIDs.count) referenced by current request.")
        .accessibilityIdentifier("companion.memory-avatar")
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
        if particleSceneCache?.digest == digest, particleSceneCache?.sessionID == liminalStructureSessionID {
            return particleSceneCache
        }
        particleSceneCache = CompanionParticleScene.build(originDigest: development.originDigest,
            graph: graph, development: development, sessionID: liminalStructureSessionID)
        return particleSceneCache
    }

}
