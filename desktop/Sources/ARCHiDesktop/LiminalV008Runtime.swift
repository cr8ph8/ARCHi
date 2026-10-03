import AppKit
import SwiftUI

/// Bundled qualification is installed with the signed app, never read from a
/// user's profile or inferred from an arbitrary directory name.
@MainActor
enum LiminalV008Runtime {
    struct Qualification: Codable {
        let schemaVersion: Int
        let assetID: String
        let manifestSHA256: String
        let sourceCooked: Bool
        let nativeEndpointsPassed: Bool
        let unityEndpointsPassed: Bool
        let installedWalkthroughPassed: Bool
        var isValid: Bool {
            schemaVersion == 1 && assetID == "liminal-v008" && LiminalKnowledgeBindings.isDigest(manifestSHA256)
                && sourceCooked && nativeEndpointsPassed && unityEndpointsPassed
        }
    }
    static let orbProgress = 107.0 / 119.0
    static let curledProgress = 65.0 / 119.0
    static let standingProgress = 23.0 / 119.0
    static let asset: LiminalPointAsset? = {
        guard Bundle.main.bundleURL.pathExtension == "app", let resources = Bundle.main.resourceURL else { return nil }
        let root = resources.appendingPathComponent("LiminalV008", isDirectory: true)
        let receipt = resources.appendingPathComponent("LiminalV008-qualification.json")
        guard let size = try? receipt.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey]),
              size.isSymbolicLink != true, let count = size.fileSize, count > 0, count <= 4096,
              let data = try? Data(contentsOf: receipt),
              let qualification = try? JSONDecoder().decode(Qualification.self, from: data), qualification.isValid,
              let asset = try? LiminalPointAsset.load(packageURL: root, expectedManifestSHA256: qualification.manifestSHA256),
              [standingProgress, curledProgress, orbProgress].allSatisfy({
                  (try? asset.endpointPNGData(progress: $0)) != nil
              }) else { return nil }
        return asset
    }()

    static func applies(form: CompanionForm, family: EvolutionFamily?, treatment: CompanionVisualTreatment) -> Bool {
        form == .hamptonSeed && family == nil && treatment == .liminalV008 && asset != nil
    }
    static func snapshot(progress: Double, seedColor: CompanionSeedColor = .original, structure: LiminalPointStructure? = nil) -> NSImage? {
        guard let asset else { return nil }
        if let data = try? LiminalMetalView.snapshotPNGData(asset: asset, progress: progress, seedColor: seedColor, structure: structure) {
            return NSImage(data: data)
        }
        return fallbackSnapshot(asset: asset, progress: progress, seedColor: seedColor, structure: structure)
    }

    static func fallbackSnapshot(asset: LiminalPointAsset, progress: Double,
                                 seedColor: CompanionSeedColor = .original, structure: LiminalPointStructure? = nil) -> NSImage? {
        // A reference fallback cannot claim to contain the requested live recipe.
        guard structure == nil || structure?.particleCount == 0 else { return nil }
        if abs(progress - orbProgress) < 0.001 {
            return SeedColorRendering.image(for: .hamptonSeed, color: LiminalSeedStyle.color(seedColor))
        }
        // The authored body fallback carries Original colors only. Do not present
        // that image as a refined or personal-color capture after a GPU failure.
        guard asset.finish == nil, seedColor == .original,
              let data = try? asset.endpointPNGData(progress: progress) else { return nil }
        return NSImage(data: data)
    }
}

private struct LiminalLightKey: EnvironmentKey { static let defaultValue = KinLightExpression.resting }
private struct LiminalProgressKey: EnvironmentKey { static let defaultValue = 107.0 / 119.0 }
extension EnvironmentValues {
    var liminalLightExpression: KinLightExpression {
        get { self[LiminalLightKey.self] }
        set { self[LiminalLightKey.self] = newValue }
    }
    var liminalPointProgress: Double {
        get { self[LiminalProgressKey.self] }
        set { self[LiminalProgressKey.self] = newValue }
    }
}

@MainActor
struct LiminalV008AppearanceCard: View {
    @ObservedObject var store: CompanionStore
    var body: some View {
        if store.preferences.seedAppearance == .hamptonLiminal {
            WorkspaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Liminal · living constellation").font(.headline)
                    Text(LiminalV008Runtime.asset == nil
                         ? "The living constellation is not available in this copy yet. Your current Liminal stays with you."
                         : "One companion, from your desktop to the room and Arena. Choose a shape; your color and light follow along.")
                        .font(.callout).foregroundStyle(.secondary)
                    Toggle("Living constellation", isOn: Binding(get: { store.preferences.visualTreatment == .liminalV008 }, set: {
                        guard !$0 || LiminalV008Runtime.asset != nil else { return }
                        store.preferences.visualTreatment = $0 ? .liminalV008 : .original
                    }))
                    .disabled(LiminalV008Runtime.asset == nil)
                    .accessibilityIdentifier("liminal-v008.select")
                    if store.preferences.visualTreatment == .liminalV008, LiminalV008Runtime.asset != nil {
                        if let asset = LiminalV008Runtime.asset {
                            LiminalKnowledgePreview(store: store, asset: asset)
                                .frame(height: 360)
                        }
                        Picker("Shape", selection: $store.preferences.liminalPointProgress) {
                            Text("Seed orb").tag(LiminalV008Runtime.orbProgress)
                            Text("Ball / Coin").tag(LiminalV008Runtime.curledProgress)
                            Text("Beast Form").tag(LiminalV008Runtime.standingProgress)
                        }.pickerStyle(.segmented)
                        Text("Supported learning adds small constellations that follow each form. Light responds to ARCHi’s activity. Inspect pauses the presentation so you can explore its knowledge.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Keep this appearance") { store.rememberPreferences = true; store.savePreferences() }
                                .buttonStyle(.borderedProminent)
                            Button("Room & Arena", systemImage: "gamecontroller") { store.open(.unity) }
                                .accessibilityIdentifier("liminal-v008.open-worlds")
                        }
                        DisclosureGroup("About this appearance") {
                            Text("The authored v008 particles share one presentation across native and Unity views. Shape and glow are visual choices; they do not change saved development. Each selectable anchor resolves to an existing knowledge record.")
                                .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                        }.font(.caption)
                    }
                }
            }.accessibilityIdentifier("liminal-v008.appearance")
        }
    }
}

@MainActor
private struct LiminalKnowledgePreview: View {
    @ObservedObject var store: CompanionStore
    let asset: LiminalPointAsset
    @State private var inspection = false
    @State private var map: LiminalKnowledgeBindings?
    @State private var sidecar: LiminalKnowledgeBindings.Sidecar?
    @State private var inspectionUnavailableReason: String?
    @State private var sessionID = UUID().uuidString
    @State private var origin: String?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.liminalPointStructure) private var pointStructure
    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { context in
            let graph = store.companionGraphSnapshot(at: context.date)
            VStack {
                HStack {
                    Label(store.kinLightExpression.label, systemImage: "sparkle")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Inspect knowledge", isOn: $inspection).toggleStyle(.switch)
                        .fixedSize().accessibilityIdentifier("liminal-v008.inspect")
                }
                LiminalAnimatedPresence(asset: asset, progress: store.preferences.liminalPointProgress,
                    reduceMotion: store.preferences.reduceMotion || store.preferences.quiet || systemReduceMotion,
                    seedColor: store.preferences.seedColor,
                    lightExpression: store.kinLightExpression, structure: pointStructure, inspection: inspection,
                    selectableIDs: inspection ? sidecar?.bindings.map(\.anchorID) ?? [] : [],
                    onSelectArtID: { id in
                        guard inspection, let sidecar,
                              let binding = sidecar.bindings.first(where: { $0.particleIDs.contains(id) }) else { return }
                        _ = store.inspectKnowledgeParticle(nodeID: binding.nodeID, graphDigest: sidecar.graphDigest)
                    })
                    .overlay {
                        GeometryReader { geometry in
                            CompanionEquipmentArt(equipment: store.preferences.equipment,
                                size: min(geometry.size.width, geometry.size.height), activated: false,
                                reduceMotion: store.preferences.reduceMotion || systemReduceMotion)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }.allowsHitTesting(false).accessibilityHidden(true)
                    }
                Text(inspectionUnavailableReason ?? (inspection ? (sidecar?.bindings.isEmpty != false ? "No knowledge records are available to inspect yet." : "Select an anchor to inspect its current source, version and connections.")
                     : "Your color. Your constellation."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .onChange(of: graph, initial: true) { _, graph in refresh(graph) }
            .onChange(of: store.activeQiMon?.originDigest) { _, _ in refresh(graph) }
        }
    }
    private func refresh(_ graph: CompanionGraphSnapshot) {
        guard let digest = store.activeQiMon?.originDigest else {
            sidecar = nil; inspectionUnavailableReason = nil; return
        }
        if origin != digest { map = nil; sidecar = nil; sessionID = UUID().uuidString; origin = digest }
        do {
            if map == nil { map = try LiminalKnowledgeBindings(manifestSHA256: asset.manifestSHA256, lowDetailIDs: asset.lowDetailIDs) }
            let projection = try map?.projectForPresentation(graph, sessionID: sessionID, originDigest: digest)
            sidecar = projection?.sidecar
            inspectionUnavailableReason = projection?.inspectionUnavailableReason
        } catch {
            sidecar = nil
            inspectionUnavailableReason = "Knowledge inspection is unavailable because its current record bindings could not be checked. Liminal’s appearance remains available."
        }
    }
}
