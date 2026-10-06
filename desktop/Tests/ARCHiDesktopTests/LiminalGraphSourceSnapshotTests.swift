import Foundation
import XCTest
@testable import ARCHiDesktop

/// Fresh owner projections over disposable records, without model calls or a
/// native user profile. Timings measure this path only, not rendered frame rate.
@MainActor
final class LiminalGraphSourceSnapshotTests: XCTestCase {
    func testDesktopPresentationReusesOwnerProjectionUntilTwoSecondRefreshThenRetiresStaleLease() throws {
        let fixture = try GraphSourceFixture(sourceCount: 1, pageCount: 2)
        defer { fixture.clean() }
        let store = fixture.store, start = 100.0
        let scene = try XCTUnwrap(store.desktopParticlePresentationScene(atUptime: start))
        let pageID = KnowledgePageGraph.nodeID(try XCTUnwrap(store.readingSources.latestKnowledgePages.first).binding)
        XCTAssertEqual(scene.graph.nodes.first { $0.id == pageID }?.presentationState, .reviewed)
        let lease = try XCTUnwrap(store.particleMotion.beginAttraction(sceneDigest: scene.motionID))
        XCTAssertTrue(store.particleMotion.updateAttraction(lease: lease, sceneDigest: scene.motionID,
            offsets: [pageID: .init(x: 0.1, y: 0)], time: start))

        let external = ReadingSourceLibrary(url: fixture.readingURL)
        let original = try XCTUnwrap(external.sources.first)
        try external.replace(id: original.id, title: original.title, text: "A corrected source version.")
        XCTAssertFalse(store.readingSources.isCurrentOnDisk)
        let files = try fixture.files()

        // With the owner already known stale, an identical scene establishes
        // that a geometry poll did not repeat the expensive owner projection.
        // Repeated polling must not slide the original freshness deadline.
        for step in 0...11 {
            let now = start + Double(step) * 0.18
            XCTAssertEqual(store.desktopParticlePresentationScene(atUptime: now), scene)
            XCTAssertEqual(store.desktopParticleSceneCheck?.uptime, start)
            XCTAssertTrue(store.particleMotion.updateAttraction(lease: lease, sceneDigest: scene.motionID,
                offsets: [pageID: .init(x: 0.1, y: 0)], time: now))
        }
        XCTAssertTrue(store.particleMotion.isAttractionCurrent(lease: lease, sceneDigest: scene.motionID))
        let current = try XCTUnwrap(store.desktopParticlePresentationScene(atUptime: start + 2))
        XCTAssertNotEqual(current.motionID, scene.motionID)
        XCTAssertEqual(current.graph.nodes.first { $0.id == pageID }?.presentationState, .needsReview)
        XCTAssertEqual(store.desktopParticleSceneCheck?.uptime, start + 2)
        XCTAssertFalse(scene.isCurrent(graph: current.graph, originDigest: current.originDigest, sessionID: current.sessionID))
        XCTAssertFalse(store.particleMotion.isAttractionCurrent(lease: lease, sceneDigest: scene.motionID))
        XCTAssertFalse(store.particleMotion.updateAttraction(lease: lease, sceneDigest: scene.motionID,
            offsets: [pageID: .init(x: 0.1, y: 0)], time: start + 2))
        XCTAssertEqual(store.particleMotion.snapshot(sceneDigest: scene.motionID), .still)
        XCTAssertEqual(store.readingSources.sources.first?.revision, original.revision,
            "Presentation refresh marks stale support without admitting another owner's source bytes.")
        XCTAssertEqual(try fixture.files(), files)
        XCTAssertEqual(fixture.client.calls, 0)
    }

    func testDesktopPresentationProfileReloadRetiresIdenticalCacheAndLeaseImmediately() throws {
        let fixture = try GraphSourceFixture(sourceCount: 1, pageCount: 2)
        defer { fixture.clean() }
        let store = fixture.store, start = 100.0
        let scene = try XCTUnwrap(store.desktopParticlePresentationScene(atUptime: start))
        let lease = try XCTUnwrap(store.particleMotion.beginAttraction(sceneDigest: scene.motionID))
        let files = try fixture.files()

        // The real profile admission path replaces session ownership even when
        // every saved byte is identical and the two-second window just began.
        try store.admitRestoredProfile()
        XCTAssertNotEqual(store.liminalStructureSessionID, scene.sessionID)
        // Reload refreshes the Reactor reference synchronously, which can
        // repopulate this disposable cache. Any such scene must already belong
        // to the new session; cache emptiness is not the invalidation contract.
        if let rebuilt = store.particleSceneCache {
            XCTAssertEqual(rebuilt.sessionID, store.liminalStructureSessionID)
            XCTAssertNotEqual(rebuilt.motionID, scene.motionID)
        }
        XCTAssertNotEqual(store.desktopParticleSceneCheck?.motionID, scene.motionID)
        XCTAssertFalse(store.particleMotion.isAttractionCurrent(lease: lease, sceneDigest: scene.motionID))
        XCTAssertEqual(store.particleMotion.snapshot(sceneDigest: scene.motionID), .still)
        XCTAssertNil(store.particleMotion.beginAttraction(sceneDigest: scene.motionID))
        let current = try XCTUnwrap(store.desktopParticlePresentationScene(atUptime: start + 0.01))
        XCTAssertEqual(current.graph, scene.graph)
        XCTAssertEqual(current.digest, scene.digest)
        XCTAssertNotEqual(current.sessionID, scene.sessionID)
        XCTAssertNotEqual(current.motionID, scene.motionID)
        XCTAssertEqual(current.sessionID, store.liminalStructureSessionID)
        XCTAssertEqual(store.desktopParticleSceneCheck?.motionID, current.motionID)
        XCTAssertEqual(store.particleMotion.snapshot(sceneDigest: scene.motionID), .still)
        XCTAssertEqual(store.desktopParticlePresentationScene(atUptime: start + 0.02), current)
        XCTAssertEqual(try fixture.files(), files)
        XCTAssertEqual(fixture.client.calls, 0)
    }

    func testMorphSourceUsesExactCapturedGraphAndStillRechecksExternalSourceChanges() throws {
        let fixture = try GraphSourceFixture(sourceCount: 1, pageCount: 2)
        defer { fixture.clean() }
        let store = fixture.store, date = Date()
        let scene = try XCTUnwrap(store.companionParticleScene(at: date))
        let presentation = try XCTUnwrap(store.liminalKnowledgePresentation(asset: fixture.asset, at: date, forMemoryMap: true))
        XCTAssertEqual(presentation.sidecar.graphDigest, LiminalKnowledgeBindings.digest(presentation.graph))
        let source = try XCTUnwrap(store.liminalGraphMorphSource(scene: scene, asset: fixture.asset, at: date))
        XCTAssertEqual(source.fullGraph, presentation.graph)
        XCTAssertEqual(source.bindings.graphDigest, LiminalKnowledgeBindings.digest(source.fullGraph))
        let pageID = KnowledgePageGraph.nodeID(try XCTUnwrap(store.readingSources.latestKnowledgePages.first).binding)
        XCTAssertEqual(source.fullGraph.nodes.first { $0.id == pageID }?.presentationState, .reviewed)

        // The same captured date cannot serve as a freshness cache key. Another
        // legitimate owner replaces the source between two presentation reads.
        let external = ReadingSourceLibrary(url: fixture.readingURL)
        let original = try XCTUnwrap(external.sources.first)
        try external.replace(id: original.id, title: original.title, text: "A corrected source version.")
        XCTAssertFalse(store.readingSources.isCurrentOnDisk)
        let files = try fixture.files()
        let rechecked = try XCTUnwrap(store.liminalGraphMorphSource(scene: scene, asset: fixture.asset, at: date))
        XCTAssertNotEqual(rechecked.fullGraph, source.fullGraph)
        XCTAssertEqual(rechecked.bindings.graphDigest, LiminalKnowledgeBindings.digest(rechecked.fullGraph))
        XCTAssertEqual(rechecked.fullGraph.nodes.first { $0.id == pageID }?.presentationState, .needsReview)
        XCTAssertEqual(store.readingSources.sources.first?.revision, original.revision,
            "Rendering must not silently reload or upgrade the captured source owner.")
        XCTAssertEqual(try fixture.files(), files)
        XCTAssertEqual(fixture.client.calls, 0)
    }

    func testPopulatedSceneAndMorphProjectionCostPreservesAllOwnerBytes() throws {
        let fixture = try GraphSourceFixture(sourceCount: 4, pageCount: 12)
        defer { fixture.clean() }
        let files = try fixture.files()
        var samples: [Double] = [], nodes = 0, edges = 0
        for _ in 0..<3 {
            let started = ProcessInfo.processInfo.systemUptime
            let date = Date()
            let scene = try XCTUnwrap(fixture.store.companionParticleScene(at: date))
            let source = try XCTUnwrap(fixture.store.liminalGraphMorphSource(scene: scene, asset: fixture.asset, at: date))
            samples.append((ProcessInfo.processInfo.systemUptime - started) * 1_000)
            nodes = source.fullGraph.nodes.count; edges = source.fullGraph.edges.count
            XCTAssertEqual(source.bindings.graphDigest, LiminalKnowledgeBindings.digest(source.fullGraph))
        }
        XCTAssertEqual(try fixture.files(), files)
        XCTAssertEqual(fixture.client.calls, 0)
        let report: [String: Any] = [
            "schema": "archi-populated-particle-projection-cost/v1", "samplesMs": samples,
            "sourceCount": fixture.store.readingSources.sources.count,
            "sourceBytes": fixture.store.readingSources.sources.reduce(0) { $0 + $1.text.utf8.count },
            "pageCount": fixture.store.readingSources.latestKnowledgePages.count,
            "linkCount": fixture.store.readingSources.latestKnowledgeLinks.count,
            "nodes": nodes, "edges": edges,
            "scope": "Disposable source owners: companionParticleScene plus liminalGraphMorphSource; excludes rendering and window composition."
        ]
        print("PARTICLE_PROJECTION_COST " + String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self))
    }
}

@MainActor private final class GraphSourceFixture {
    let root: URL
    let readingURL: URL
    let client = GraphSourceNoCalls()
    let store: CompanionStore
    lazy var asset = makeAsset()

    init(sourceCount: Int, pageCount: Int) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("archi-graph-source-snapshot-\(UUID())")
        let profile = root.appendingPathComponent("preferences.json")
        readingURL = profile.deletingPathExtension().appendingPathExtension("reading-sources.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let identity = LocalQiMon(character: .kin, originDigest: String(repeating: "a", count: 64), welcomedAt: Date())
        try NativePreferenceDocument(qiMon: identity).encoded().write(to: profile)
        let local = client
        store = CompanionStore(preferenceURL: profile, assistant: local, assistantFactory: { _, _ in local }, allowsPlay: false)
        var sources: [ReadingSourceSnapshot] = []
        for index in 0..<sourceCount {
            let parents = sources.last.map { [ReadingSourceParent(binding: $0.binding)] } ?? []
            let provenance = ReadingSourceProvenance(origin: .human,
                acquisition: parents.isEmpty ? .userCopy : .derivedCopy, attribution: "Synthetic measurement fixture", parents: parents)
            let text = String(repeating: "Synthetic source \(index). Review the exact passage before reuse.\n", count: 350)
            sources.append(try store.readingSources.keep(title: "Synthetic source \(index)", text: text, provenance: provenance))
        }
        let anchors = try sources.map { try store.readingSources.makeAnchor(sourceID: $0.id, range: NSRange(location: 0, length: 40)) }
        var pages: [KnowledgePage] = []
        for index in 0..<pageCount {
            let draft = try store.readingSources.saveKnowledgePage(title: "Synthetic concept \(index)",
                body: "Reviewed synthetic claim \(index), retained for this projection test only.", kind: .concept, anchors: anchors)
            pages.append(try store.readingSources.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision))
        }
        for pair in zip(pages, pages.dropFirst()) {
            let draft = try store.readingSources.saveKnowledgeLink(from: pair.0.binding, to: pair.1.binding,
                kind: .supports, rationale: "Synthetic explicitly reviewed relation.")
            try store.readingSources.reviewKnowledgeLink(id: draft.id, expectedRevision: draft.revision)
        }
    }

    func clean() { store.disconnectAssistant(); try? FileManager.default.removeItem(at: root) }

    func files() throws -> [String: Data] {
        let entries = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
        var result: [String: Data] = [:]
        for case let file as URL in entries where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            result[String(file.path.dropFirst(root.path.count))] = try Data(contentsOf: file)
        }
        return result
    }

    private func makeAsset() -> LiminalPointAsset {
        let digest = String(repeating: "b", count: 64)
        let reference = LiminalPointAsset.FileReference(file: "synthetic.bin", sha256: digest, bytes: 32)
        let manifest = LiminalPointAsset.Manifest(schema: "archi-liminal-point-asset/v2", assetID: "liminal-v008",
            source: .init(hipSHA256: LiminalPointAsset.sourceSHA256, houdiniVersion: "synthetic", node: LiminalPointAsset.sourceNode, originalUnchanged: true, dependencies: []),
            pointCount: 800_000, runtimePointCount: 200_000,
            encoding: .init(byteOrder: "little", float: "ieee754-binary32", masterStride: 100, cohortStride: 8, idStride: 4, sampleStride: 32),
            coordinates: .init(space: "houdini-sop-local", handedness: "right", upAxis: "+Y", units: "authored-scene-units", nativeMapping: [1,1,1], unityMapping: [1,1,-1], objectToWorldRowMajor: [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]),
            appearance: .init(colorSpace: "linear-rec709", radiusAttribute: "pscale", emissionAttribute: "heat", emissionRule: "Cd*heat"),
            timeline: .init(fps: 24, firstFrame: 1, lastFrame: 120, interpolation: "nearest-half-up", poseFrames: ["standing":24,"curled":66,"orb":108]),
            bounds: .init(min: [-3,-3,-3], max: [3,3,3], maximumRadius: 0.01, maximumEmission: 8),
            master: reference, cohorts: reference, lod: .init(algorithm: "sha256-rank-v1", counts: [50_000,100_000,200_000], ids: reference),
            frames: [], motionControls: [:], endpointImages: .init(status: "unavailable", renderer: nil, camera: nil, images: [], receipt: nil, reason: "Synthetic graph snapshot fixture"), comparison: reference)
        return LiminalPointAsset(packageURL: root.appendingPathComponent("synthetic-asset"), manifestSHA256: digest,
            manifest: manifest, artIDs: Array(UInt32(0)..<UInt32(50_000)), finish: nil, surfaceLight: nil)
    }
}

@MainActor private final class GraphSourceNoCalls: AssistantClient {
    private(set) var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.stopped }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; throw AssistantFailure.stopped
    }
    func disconnect() {}
}
