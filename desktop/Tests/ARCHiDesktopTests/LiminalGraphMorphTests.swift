import XCTest
import simd
@testable import ARCHiDesktop

final class LiminalGraphMorphTests: XCTestCase {
    private let origin = String(repeating: "a", count: 64)
    private let manifest = String(repeating: "b", count: 64)
    private let viewport = CGSize(width: 720, height: 480)

    private func node(_ id: String, kind: CompanionGraphKind = .knowledge) -> CompanionGraphNode {
        .init(id: id, title: "Synthetic \(id)", subtitle: "Current version", kind: kind,
              status: "Recorded", details: [.init(label: "Source", value: "Version 1")], target: .memory)
    }
    private var full: CompanionGraphSnapshot {
        .init(nodes: [node("root", kind: .companion), node("memory-a"), node("memory-b"), node("activity", kind: .request)],
              edges: [.init(id: "edge-a", source: "memory-a", target: "root", label: "Retained by"),
                      .init(id: "edge-b", source: "memory-b", target: "memory-a", label: "Supports"),
                      .init(id: "edge-c", source: "activity", target: "root", label: "Requested by")], truncatedCount: 0)
    }
    private var map: CompanionGraphSnapshot {
        .init(nodes: Array(full.nodes.prefix(3)), edges: Array(full.edges.prefix(2)), truncatedCount: 0)
    }
    private func sidecar(_ graph: CompanionGraphSnapshot? = nil, asset: LiminalPointAsset? = nil) throws -> LiminalKnowledgeBindings.Sidecar {
        let asset = asset ?? makeAsset()
        var allocator = try LiminalKnowledgeBindings(manifestSHA256: asset.manifestSHA256, lowDetailIDs: asset.lowDetailIDs)
        return try allocator.project(graph ?? full, sessionID: "00000000-0000-4000-8000-000000000001", originDigest: origin)
    }
    private func make(_ asset: LiminalPointAsset? = nil, sidecar: LiminalKnowledgeBindings.Sidecar? = nil,
                      fullGraph: CompanionGraphSnapshot? = nil, mapGraph: CompanionGraphSnapshot? = nil,
                      field: KnowledgeParticleField? = nil, viewport: CGSize? = nil,
                      visible: Set<String>? = nil, focus: Set<String>? = nil, owner: String? = nil) throws -> LiminalGraphMorph? {
        let asset = asset ?? makeAsset(), map = mapGraph ?? self.map
        return LiminalGraphMorph.make(asset: asset, bindings: try sidecar ?? self.sidecar(fullGraph, asset: asset),
            fullGraph: fullGraph ?? full, mapGraph: map, field: field ?? KnowledgeParticleField(snapshot: map),
            originDigest: owner ?? origin, viewport: viewport ?? self.viewport,
            visibleNodeIDs: visible ?? Set(map.nodes.map(\.id)), focusIDs: focus)
    }

    func testExactMapAnchorsAndBoundedClustersKeepActualArtIDsAtEveryLOD() throws {
        let asset = makeAsset(), bindings = try sidecar(asset: asset)
        let morph = try XCTUnwrap(make(asset, sidecar: bindings))
        XCTAssertEqual(morph.anchors.count, 3)
        XCTAssertEqual(morph.mapTargetsByRank.count, 3 * 32)
        XCTAssertEqual(Set(morph.anchorArtIDsByNodeID.keys), Set(map.nodes.map(\.id)))
        let field = KnowledgeParticleField(snapshot: map)
        let frame = KnowledgeParticleField.framing(particles: field.particles, spread: 1, reduceMotion: true)
        let expected = KnowledgeParticleField.displayPositions(particles: field.particles, frame: frame,
            spread: 1, reduceMotion: true, width: viewport.width, height: viewport.height)
        for binding in bindings.bindings where expected[binding.nodeID] != nil {
            let anchor = try XCTUnwrap(morph.anchors.first { $0.nodeID == binding.nodeID })
            XCTAssertEqual(anchor.artID, binding.anchorID)
            XCTAssertEqual(asset.artIDs[anchor.rank], binding.anchorID)
            let point = try XCTUnwrap(expected[binding.nodeID])
            XCTAssertEqual(anchor.mapPoint, CGPoint(x: point.x, y: point.y))
            XCTAssertEqual(morph.mapTargetsByRank[anchor.rank], SIMD4(anchor.mapClip.x, anchor.mapClip.y, 1, 0))
            for id in binding.particleIDs {
                let rank = try XCTUnwrap(asset.artIDs.firstIndex(of: id))
                let target = try XCTUnwrap(morph.mapTargetsByRank[rank])
                let displayed = LiminalGraphMorph.screenPosition(clip: SIMD2(target.x, target.y), viewport: viewport)
                XCTAssertLessThanOrEqual(hypot(displayed.x - anchor.mapPoint.x, displayed.y - anchor.mapPoint.y), 6.0001)
            }
        }
        let low = morph.mapTargets(count: 50_000), high = morph.mapTargets(count: 200_000)
        XCTAssertEqual(low.count, 50_000)
        XCTAssertEqual(Array(high.prefix(low.count)), low)
        XCTAssertTrue(high.dropFirst(50_000).allSatisfy { $0 == .zero })
        XCTAssertTrue(morph.mapTargets(count: -1).isEmpty)
        XCTAssertTrue(morph.mapTargets(count: 200_001).isEmpty)
        XCTAssertTrue(morph.mapTargets(count: 1).isEmpty)
    }

    func testFilteringOnlyChangesMembershipAndNeverRebindsOrMovesRecords() throws {
        let asset = makeAsset(), bindings = try sidecar(asset: asset)
        let all = try XCTUnwrap(make(asset, sidecar: bindings))
        let filtered = try XCTUnwrap(make(asset, sidecar: bindings, visible: ["memory-a"]))
        XCTAssertEqual(all.mapPoints, filtered.mapPoints)
        XCTAssertEqual(all.anchorArtIDsByNodeID, filtered.anchorArtIDsByNodeID)
        XCTAssertNotEqual(all.digest, filtered.digest)
        for anchor in filtered.anchors {
            XCTAssertEqual(anchor.isVisible, anchor.nodeID == "memory-a")
            let bound = try XCTUnwrap(bindings.bindings.first { $0.nodeID == anchor.nodeID })
            for id in bound.particleIDs {
                let rank = try XCTUnwrap(asset.artIDs.firstIndex(of: id))
                let a = try XCTUnwrap(all.mapTargetsByRank[rank]), b = try XCTUnwrap(filtered.mapTargetsByRank[rank])
                XCTAssertEqual(a.x, b.x); XCTAssertEqual(a.y, b.y)
                XCTAssertEqual(b.z, anchor.isVisible ? 1 : -1)
            }
        }
        let activity = try XCTUnwrap(bindings.bindings.first { $0.nodeID == "activity" })
        XCTAssertNil(filtered.mapTargetsByRank[try XCTUnwrap(asset.artIDs.firstIndex(of: activity.anchorID))])
        XCTAssertNil(try make(asset, sidecar: bindings, visible: ["missing-record"]))
    }

    func testFullGraphAndMemorySubsetHaveSeparateDigestsButExactCurrentRecords() throws {
        let bindings = try sidecar()
        let morph = try XCTUnwrap(make(sidecar: bindings))
        XCTAssertEqual(morph.graphDigest, bindings.graphDigest)
        XCTAssertEqual(morph.mapGraphDigest, LiminalKnowledgeBindings.digest(map))
        XCTAssertNotEqual(morph.graphDigest, morph.mapGraphDigest)
        var records = full.nodes
        records[1].presentationState = .corrected
        records[1].evidenceTrail = [.init(id: "revision-2", stage: .correction, summary: "Changed source")]
        let revisedFull = CompanionGraphSnapshot(nodes: records, edges: full.edges, truncatedCount: 0)
        XCTAssertNil(try make(sidecar: bindings, fullGraph: revisedFull))
        let revisedBindings = try sidecar(revisedFull)
        XCTAssertNil(try make(sidecar: revisedBindings, fullGraph: revisedFull), "Old map metadata must not borrow current sidecar authority")
        let revisedMap = CompanionGraphSnapshot(nodes: Array(records.prefix(3)), edges: map.edges, truncatedCount: 0)
        let current = try XCTUnwrap(make(sidecar: revisedBindings, fullGraph: revisedFull, mapGraph: revisedMap))
        XCTAssertEqual(current.anchorArtIDsByNodeID, morph.anchorArtIDsByNodeID)
        XCTAssertEqual(current.mapPoints, morph.mapPoints)
        XCTAssertNotEqual(current.digest, morph.digest)
        let removed = CompanionGraphSnapshot(nodes: Array(full.nodes.dropFirst()), edges: [], truncatedCount: 0)
        XCTAssertNil(try make(fullGraph: removed))
        let inventedEdge = CompanionGraphSnapshot(nodes: map.nodes,
            edges: [.init(id: "edge-a", source: "memory-a", target: "root", label: "Invented meaning")], truncatedCount: 0)
        XCTAssertNil(try make(mapGraph: inventedEdge))
    }

    func testMalformedSidecarsAndMissingClustersFailClosed() throws {
        let bindings = try sidecar()
        func altered(schema: Int = 1, session: String? = nil, owner: String? = nil,
                     digest: String? = nil, asset: String? = nil,
                     records: [LiminalKnowledgeBindings.Binding]? = nil) -> LiminalKnowledgeBindings.Sidecar {
            .init(schemaVersion: schema, sessionID: session ?? bindings.sessionID, originDigest: owner ?? bindings.originDigest,
                  manifestSHA256: asset ?? bindings.manifestSHA256, graphDigest: digest ?? bindings.graphDigest,
                  bindings: records ?? bindings.bindings)
        }
        let a = bindings.bindings[0], b = bindings.bindings[1]
        for bad in [altered(schema: 2), altered(session: "wrong"), altered(owner: String(repeating: "c", count: 64)),
                    altered(digest: String(repeating: "c", count: 64)), altered(asset: String(repeating: "c", count: 64)),
                    altered(records: []), altered(records: [a, a]),
                    altered(records: [a, .init(nodeID: b.nodeID, anchorID: a.anchorID, particleIDs: a.particleIDs)]),
                    altered(records: [.init(nodeID: "phantom", anchorID: a.anchorID, particleIDs: a.particleIDs)]),
                    altered(records: [.init(nodeID: a.nodeID, anchorID: a.anchorID, particleIDs: Array(a.particleIDs.prefix(31)))]),
                    altered(records: [.init(nodeID: a.nodeID, anchorID: 799_999, particleIDs: a.particleIDs)])] {
            XCTAssertNil(try make(sidecar: bad))
        }
        XCTAssertNil(try make(owner: "missing-owner"))
        XCTAssertNil(try make(makeAsset(ids: [1, 1]), sidecar: bindings))
    }

    func testTopologyViewportAndFocusValidationPreservesStableLayout() throws {
        let mismatched = KnowledgeParticleField(snapshot: .init(nodes: Array(map.nodes.prefix(2)), edges: [], truncatedCount: 0))
        XCTAssertNil(try make(field: mismatched))
        for size in [CGSize.zero, CGSize(width: CGFloat.nan, height: 480), CGSize(width: 720, height: CGFloat.infinity),
                     CGSize(width: 65_537, height: 480)] {
            XCTAssertNil(try make(viewport: size))
        }
        XCTAssertNil(try make(focus: ["absent"]))
        let focus: Set<String> = ["memory-a", "memory-b"]
        let morph = try XCTUnwrap(make(focus: focus)), field = KnowledgeParticleField(snapshot: map)
        let frame = KnowledgeParticleField.framing(particles: field.particles, spread: 1, reduceMotion: true, focusIDs: focus)
        let points = KnowledgeParticleField.displayPositions(particles: field.particles, frame: frame,
            spread: 1, reduceMotion: true, width: viewport.width, height: viewport.height)
        XCTAssertEqual(morph.mapPoints["memory-a"], points["memory-a"].map { CGPoint(x: $0.x, y: $0.y) })
        let reordered = CompanionGraphSnapshot(nodes: map.nodes.reversed(), edges: map.edges.reversed(), truncatedCount: 0)
        XCTAssertEqual(try make(mapGraph: reordered)?.digest, try make()?.digest)
    }

    func testEndpointExactBoundedInterpolationAndNonfiniteProgress() throws {
        let a = SIMD2<Float>(-0.8, 0.6), b = SIMD2<Float>(0.7, -0.4)
        XCTAssertEqual(LiminalGraphMorph.interpolate(map: a, body: b, progress: 0), a)
        XCTAssertEqual(LiminalGraphMorph.interpolate(map: a, body: b, progress: 1), b)
        XCTAssertEqual(LiminalGraphMorph.interpolate(map: a, body: b, progress: 0.5), (a + b) * 0.5)
        XCTAssertEqual(LiminalGraphMorph.interpolate(map: a, body: b, progress: -.infinity), a)
        XCTAssertEqual(LiminalGraphMorph.interpolate(map: a, body: b, progress: .nan), a)
        XCTAssertEqual(LiminalGraphMorph.interpolate(map: a, body: b, progress: -1), a)
        XCTAssertEqual(LiminalGraphMorph.interpolate(map: a, body: b, progress: 2), b)
        XCTAssertNil(LiminalGraphMorph.interpolate(map: SIMD2(.nan, 1), body: b, progress: 0.5))
        for index in 0...100 {
            let p = try XCTUnwrap(LiminalGraphMorph.interpolate(map: a, body: b, progress: Double(index) / 100))
            XCTAssertTrue((-0.8...0.7).contains(p.x))
            XCTAssertTrue((-0.4...0.6).contains(p.y))
        }
    }

    func testCPUOverlayUsesDisplayedBeastFrameFinishAndMatchingMetalProjection() throws {
        let asset = makeAsset(), bindings = try sidecar(asset: asset)
        let morph = try XCTUnwrap(make(asset, sidecar: bindings))
        let frame = makeFrame()
        let start = morph.anchorPositions(asset: asset, frame: frame, progress: 0)
        let end = morph.anchorPositions(asset: asset, frame: frame, progress: 1)
        let middle = morph.anchorPositions(asset: asset, frame: frame, progress: 0.5)
        for anchor in morph.anchors {
            let source = try XCTUnwrap(frame.sample(at: anchor.rank))
            let clip = try XCTUnwrap(LiminalGraphMorph.bodyClipPosition(position: source.position,
                asset: asset, frame: 24, viewport: viewport))
            let expected = LiminalGraphMorph.screenPosition(clip: clip, viewport: viewport)
            XCTAssertEqual(try XCTUnwrap(start[anchor.nodeID]).x, anchor.mapPoint.x, accuracy: 0.0001)
            XCTAssertEqual(try XCTUnwrap(start[anchor.nodeID]).y, anchor.mapPoint.y, accuracy: 0.0001)
            XCTAssertEqual(end[anchor.nodeID], expected)
            XCTAssertEqual(try XCTUnwrap(middle[anchor.nodeID]).x, (anchor.mapPoint.x + expected.x) * 0.5, accuracy: 0.0001)
            XCTAssertEqual(try XCTUnwrap(middle[anchor.nodeID]).y, (anchor.mapPoint.y + expected.y) * 0.5, accuracy: 0.0001)
        }
        let first = try XCTUnwrap(morph.anchors.first)
        var annotations = Data(repeating: 0, count: 50_000 * 16)
        let gold = packed([1, 0, 0]) + uintData(1)
        annotations.replaceSubrange(first.rank * 16..<(first.rank + 1) * 16, with: gold)
        let finish = LiminalPointFinish(digest: String(repeating: "d", count: 64), annotations: annotations)
        let refined = makeAsset(finish: finish)
        let refinedMorph = try XCTUnwrap(make(refined, sidecar: bindings))
        let displayed = finish.display(try XCTUnwrap(frame.sample(at: first.rank)), rank: first.rank, frame: 24)
        let expected = LiminalGraphMorph.screenPosition(clip: try XCTUnwrap(LiminalGraphMorph.bodyClipPosition(
            position: displayed.position, asset: refined, frame: 24, viewport: viewport)), viewport: viewport)
        XCTAssertEqual(refinedMorph.anchorPositions(asset: refined, frame: frame, progress: 1)[first.nodeID], expected)
        XCTAssertNotEqual(morph.digest, refinedMorph.digest)
        XCTAssertTrue(morph.anchorPositions(asset: refined, frame: frame, progress: 1).isEmpty)
        XCTAssertTrue(morph.anchorPositions(asset: asset,
            frame: .init(frame: 25, pointCount: frame.pointCount, data: frame.data), progress: 1).isEmpty)
        XCTAssertTrue(morph.anchorPositions(asset: asset, frame: .init(frame: 24, pointCount: 50_000, data: Data()), progress: 1).isEmpty)
        let filtered = try XCTUnwrap(make(asset, sidecar: bindings, visible: ["memory-a"]))
        XCTAssertEqual(Set(filtered.anchorPositions(asset: asset, frame: frame, progress: 0.4).keys), ["memory-a"])
    }

    func testProjectionMatchesAspectAndScreenAxisConventionsWithoutBreathing() throws {
        let asset = makeAsset()
        let centered = try XCTUnwrap(LiminalGraphMorph.bodyClipPosition(position: asset.center, asset: asset, frame: 24, viewport: viewport))
        XCTAssertEqual(centered, .zero)
        let point = SIMD3<Float>(asset.span * 0.25, asset.span * 0.25, 0)
        let clip = try XCTUnwrap(LiminalGraphMorph.bodyClipPosition(position: point, asset: asset, frame: 24, viewport: viewport))
        XCTAssertEqual(clip.x, 0.5 * 480 / 720, accuracy: 0.000001)
        XCTAssertEqual(clip.y, 0.5, accuracy: 0.000001)
        let screen = LiminalGraphMorph.screenPosition(clip: clip, viewport: viewport)
        XCTAssertLessThan(screen.y, viewport.height / 2)
        let returned = try XCTUnwrap(LiminalGraphMorph.clipPosition(point: screen, viewport: viewport))
        XCTAssertEqual(returned.x, clip.x, accuracy: 0.000001)
        XCTAssertEqual(returned.y, clip.y, accuracy: 0.000001)
        XCTAssertNil(LiminalGraphMorph.bodyClipPosition(position: SIMD3(.nan, 0, 0), asset: asset, frame: 24, viewport: viewport))
    }

    func testEmptyGraphHasNoInventedBindingsOrMapParticles() throws {
        let empty = CompanionGraphSnapshot.empty
        let morph = try XCTUnwrap(make(fullGraph: empty, mapGraph: empty))
        XCTAssertTrue(morph.anchors.isEmpty)
        XCTAssertTrue(morph.mapPoints.isEmpty)
        XCTAssertTrue(morph.mapTargets(count: 50_000).allSatisfy { $0 == .zero })
    }

    @MainActor func testCurrentNativeStoreMemoryAndActivityProjectionsCanShareBindings() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("liminal-morph-owner-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preferences.json"), now = Date()
        let workingText = "A separate active working copy, not a saved memory."
        let lesson = KeptLesson(topic: "Attribution", text: "Retain the exact source version.",
            source: .init(name: "working.txt", digest: LessonSource.digest(of: workingText)))
        try NativePreferenceDocument(lessons: [lesson], qiMon: .init(character: .hampton,
            originDigest: origin, welcomedAt: now)).encoded().write(to: url)
        let client = LiminalGraphMorphNoCalls()
        let store = CompanionStore(preferenceURL: url, assistant: client,
            assistantFactory: { _, _ in client }, wallClock: { now }, allowsPlay: false)
        let source = try store.readingSources.keep(title: "Synthetic retained source", text: "A source-bound memory.")
        let anchor = try store.readingSources.makeAnchor(sourceID: source.id,
            range: NSRange(location: 0, length: source.text.utf16.count))
        let page = try store.readingSources.saveKnowledgePage(title: "Synthetic concept", body: "Inspect its evidence.",
            kind: .concept, anchors: [anchor])
        _ = try store.readingSources.reviewKnowledgePage(id: page.id, expectedRevision: page.revision)
        store.sourceName = "working.txt"
        store.sharedText = workingText
        let memory = store.memoryMapSnapshot(at: now), activity = store.companionGraphSnapshot(at: now)
        XCTAssertGreaterThan(activity.nodes.count, memory.nodes.count)
        XCTAssertEqual(memory.nodes.first { $0.id == "companion-archi" }, activity.nodes.first { $0.id == "companion-archi" })
        XCTAssertEqual(memory.nodes.first { $0.kind == .lesson }?.status, "Waiting for shared copy")
        XCTAssertEqual(activity.nodes.first { $0.kind == .lesson }?.status, "Current")
        let bytes = try Data(contentsOf: url)
        let asset = makeAsset(), binding = try sidecar(activity, asset: asset)
        let morph = try XCTUnwrap(make(asset, sidecar: binding, fullGraph: activity, mapGraph: memory))
        XCTAssertEqual(Set(morph.anchors.map(\.nodeID)), Set(memory.nodes.map(\.id)))
        XCTAssertEqual(memory.nodes.first { $0.kind == .lesson }?.status, "Waiting for shared copy",
                       "A visual correspondence cannot promote the map's source availability")
        for changedLabel in ["Your kept words", "Bound source"] {
            let changedNodes = activity.nodes.map { record -> CompanionGraphNode in
                guard record.kind == .lesson else { return record }
                return .init(id: record.id, title: record.title, subtitle: record.subtitle, kind: record.kind,
                    status: record.status, details: record.details.map { $0.label == changedLabel
                        ? .init(label: $0.label, value: "Changed but reusing the old ID") : $0 }, target: record.target,
                    presentationState: record.presentationState, evidenceTrail: record.evidenceTrail)
            }
            let changed = CompanionGraphSnapshot(nodes: changedNodes, edges: activity.edges, truncatedCount: activity.truncatedCount)
            XCTAssertNil(try make(asset, sidecar: sidecar(changed, asset: asset), fullGraph: changed, mapGraph: memory))
        }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(client.calls, 0)
        await store.shutdownAssistant()
    }

    /// In-memory geometry only, never represented as a qualified Houdini export.
    private func makeAsset(finish: LiminalPointFinish? = nil, ids: [UInt32]? = nil) -> LiminalPointAsset {
        let reference = LiminalPointAsset.FileReference(file: "synthetic.bin", sha256: manifest, bytes: 32)
        let m = LiminalPointAsset.Manifest(schema: "archi-liminal-point-asset/v2", assetID: "liminal-v008",
            source: .init(hipSHA256: LiminalPointAsset.sourceSHA256, houdiniVersion: "synthetic", node: LiminalPointAsset.sourceNode, originalUnchanged: true, dependencies: []),
            pointCount: 800_000, runtimePointCount: 200_000,
            encoding: .init(byteOrder: "little", float: "ieee754-binary32", masterStride: 100, cohortStride: 8, idStride: 4, sampleStride: 32),
            coordinates: .init(space: "houdini-sop-local", handedness: "right", upAxis: "+Y", units: "authored-scene-units", nativeMapping: [1,1,1], unityMapping: [1,1,-1], objectToWorldRowMajor: [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]),
            appearance: .init(colorSpace: "linear-rec709", radiusAttribute: "pscale", emissionAttribute: "heat", emissionRule: "Cd*heat"),
            timeline: .init(fps: 24, firstFrame: 1, lastFrame: 120, interpolation: "nearest-half-up", poseFrames: ["standing":24,"curled":66,"orb":108]),
            bounds: .init(min: [-3,-3,-3], max: [3,3,3], maximumRadius: 0.01, maximumEmission: 8),
            master: reference, cohorts: reference, lod: .init(algorithm: "sha256-rank-v1", counts: [50_000,100_000,200_000], ids: reference),
            frames: [], motionControls: [:], endpointImages: .init(status: "unavailable", renderer: nil, camera: nil, images: [], receipt: nil, reason: "Synthetic geometry fixture"), comparison: reference)
        return .init(packageURL: URL(fileURLWithPath: "/synthetic-not-an-installed-asset"), manifestSHA256: manifest,
                     manifest: m, artIDs: ids ?? Array(UInt32(0)..<UInt32(50_000)), finish: finish, surfaceLight: nil)
    }
    private func makeFrame() -> LiminalPointAsset.Frame {
        let point = packed([1, 2, 0.5, 0.2, 0.1, 0.05, 0.001, 1])
        var bytes = Data(capacity: 50_000 * 32)
        for _ in 0..<50_000 { bytes.append(point) }
        return .init(frame: 24, pointCount: 50_000, data: bytes)
    }
    private func packed(_ values: [Float]) -> Data { values.reduce(into: Data()) { $0.append(uintData($1.bitPattern)) } }
    private func uintData(_ value: UInt32) -> Data {
        var little = value.littleEndian
        return withUnsafeBytes(of: &little) { Data($0) }
    }
}

@MainActor private final class LiminalGraphMorphNoCalls: AssistantClient {
    private(set) var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.configuration }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; throw AssistantFailure.configuration
    }
    func disconnect() {}
}
