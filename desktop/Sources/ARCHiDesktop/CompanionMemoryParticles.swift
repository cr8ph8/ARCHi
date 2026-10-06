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
            growthByRecordID: scene.growthByRecordID, motionSceneDigest: scene.motionID, onSelect: { onSelect?($0) })
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
    var formProgress = 0.0
    var liminalGraphSource: LiminalGraphMorphSource?
    var seedAppearance: CompanionParticleAppearance?
    @Environment(\.companionParticleMotionEnabled) private var sharedMotionEnabled

    var body: some View {
        ZStack {
            Group {
                if let liminalGraphSource {
                    LiminalGraphMorphView(source: liminalGraphSource, graph: scene.graph, field: scene.field,
                        nodes: scene.graph.nodes, selectedID: selectedID, progress: formProgress,
                        reduceMotion: reduceMotion, seedColor: seedColor, focusIDs: nil,
                        growthByRecordID: scene.growthByRecordID, preparedIDs: activity.preparedNodeIDs,
                        requestIDs: activity.requestNodeIDs, expression: expression, seedAppearance: seedAppearance,
                        motionSceneDigest: scene.motionID, motionEnabled: animationVisible ?? true,
                        compact: true, includesSeedEquipment: false, onSelect: { _ in })
                } else {
                    ZStack {
                        if let seedAppearance {
                            seedAppearance.art(size: 256,
                                reduceMotion: reduceMotion || animationVisible == false || !sharedMotionEnabled || formProgress >= 0,
                                includesEquipment: false)
                                .opacity(max(0, -formProgress))
                        }
                        KnowledgeParticleView(field: scene.field, nodes: scene.graph.nodes, selectedID: selectedID,
                            spread: 1 + min(0, formProgress), pulses: !reduceMotion, reduceMotion: reduceMotion, tint: seedColor.accent,
                            showsLabels: false, expression: expression, preparedIDs: activity.preparedNodeIDs,
                            requestIDs: activity.requestNodeIDs, interactive: false,
                            growthByRecordID: scene.growthByRecordID, animationVisible: animationVisible,
                            motionSceneDigest: scene.motionID, onSelect: { _ in })
                    }
                }
            }
            .frame(width: 256, height: 256)
            .scaleEffect(size / 256)
            .frame(width: size, height: size)
            if !equipment.isEmpty {
                CompanionEquipmentArt(equipment: equipment, size: size, activated: false,
                    reduceMotion: reduceMotion || animationVisible == false || !sharedMotionEnabled)
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

    @MainActor func art(size: CGFloat, reduceMotion: Bool, includesEquipment: Bool = true) -> some View {
        CompanionPresenceArt(form: form, family: family, size: size, reduceMotion: reduceMotion,
            treatment: treatment, recipe: recipe, naturalVariation: naturalVariation,
            equipment: includesEquipment ? equipment : .empty, seedColor: seedColor)
            .environment(\.companionParticleScene, nil)
            .environment(\.liminalPointStructure, nil)
            .environment(\.liminalPointProgress, LiminalV008Runtime.orbProgress)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct CompanionParticleMotionEnabledKey: EnvironmentKey { static let defaultValue = true }
private struct CompanionParticleMotionKey: EnvironmentKey { static let defaultValue: CompanionParticleMotion? = nil }
private struct CompanionParticleSceneKey: EnvironmentKey { static let defaultValue: CompanionParticleScene? = nil }
private struct CompanionParticleSelectionKey: EnvironmentKey { static let defaultValue: CompanionParticleSelection? = nil }
extension EnvironmentValues {
    var companionParticleMotionEnabled: Bool {
        get { self[CompanionParticleMotionEnabledKey.self] }
        set { self[CompanionParticleMotionEnabledKey.self] = newValue }
    }
    var companionParticleMotion: CompanionParticleMotion? {
        get { self[CompanionParticleMotionKey.self] }
        set { self[CompanionParticleMotionKey.self] = newValue }
    }
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
    func liminalGraphMorphSource(scene: CompanionParticleScene, at date: Date = Date()) -> LiminalGraphMorphSource? {
        guard let asset = LiminalV008Runtime.asset else { return nil }
        return liminalGraphMorphSource(scene: scene, asset: asset, at: date)
    }

    /// The sidecar and its complete graph come from one current owner read. A
    /// second full graph walk repeated source/lineage hashing and could observe
    /// different owner bytes than the exact graph already bound by the sidecar.
    func liminalGraphMorphSource(scene: CompanionParticleScene, asset: LiminalPointAsset,
                                at date: Date = Date()) -> LiminalGraphMorphSource? {
        guard let presentation = liminalKnowledgePresentation(asset: asset, at: date, forMemoryMap: true),
              presentation.sidecar.originDigest == scene.originDigest else { return nil }
        return LiminalGraphMorphSource(asset: asset, bindings: presentation.sidecar,
            fullGraph: presentation.graph, originDigest: scene.originDigest)
    }

    /// Geometry polling must not rebuild every source and backlink on the main
    /// thread. Reuse the canonical presentation cache for at most two seconds,
    /// matching the visible avatar's existing support refresh. Profile/session
    /// replacement retires it immediately; file-backed changes retire it on the
    /// next refresh. This accessor is only for drawing, never record admission,
    /// reading a window, sending context or applying a reviewed outcome.
    func desktopParticlePresentationScene(atUptime now: Double = ProcessInfo.processInfo.systemUptime) -> CompanionParticleScene? {
        guard now.isFinite, now >= 0 else { desktopParticleSceneCheck = nil; return nil }
        if let scene = particleSceneCache, scene.sessionID == liminalStructureSessionID,
           let checked = desktopParticleSceneCheck, checked.motionID == scene.motionID,
           now >= checked.uptime, now - checked.uptime < 2 {
            return scene
        }
        guard let scene = companionParticleScene() else { desktopParticleSceneCheck = nil; return nil }
        desktopParticleSceneCheck = (scene.motionID, now)
        return scene
    }

    func companionParticleScene(at date: Date = Date()) -> CompanionParticleScene? {
        guard let development = liminalFormDevelopment(at: date) else { particleSceneCache = nil; particleMotion.reset(); return nil }
        let graph = memoryMapSnapshot(at: date)
        guard let digest = CompanionParticleScene.fingerprint(originDigest: development.originDigest,
            graph: graph, development: development) else { particleSceneCache = nil; particleMotion.reset(); return nil }
        if particleSceneCache?.digest == digest, particleSceneCache?.sessionID == liminalStructureSessionID {
            return particleSceneCache
        }
        particleSceneCache = CompanionParticleScene.build(originDigest: development.originDigest,
            graph: graph, development: development, sessionID: liminalStructureSessionID)
        if let scene = particleSceneCache { particleMotion.reconcile(scene: scene) }
        else { particleMotion.reset() }
        return particleSceneCache
    }

}
