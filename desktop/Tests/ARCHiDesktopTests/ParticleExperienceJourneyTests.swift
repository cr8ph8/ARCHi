import Foundation
import XCTest
@testable import ARCHiDesktop

/// The complete local owner path, with an in-process role response passing through
/// HamptonReasonsAssistant validation. No profile, model process or network is used.
@MainActor
final class ParticleExperienceJourneyTests: XCTestCase {
    func testKeepRequestCitationReviewReopenAndRevokeShareOneGrowthRecord() async throws {
        let fixture = try ParticleJourneyFixture()
        defer { fixture.clean() }
        let store = fixture.store
        let lesson = try fixture.keepLesson()
        let snapshot = LessonSnapshot(lesson: lesson)
        let nodeID = CompanionGraph.lessonNodeID(lesson)
        let retained = try fixture.projection()
        let contentID = try fixture.assertGrowth(retained, nodeID: nodeID, applications: 0)
        let preferenceBytes = try Data(contentsOf: fixture.preferenceURL)

        fixture.reasoner.hold = true
        try await fixture.start()
        try await fixture.wait { fixture.reasoner.hasPending }
        let request = try XCTUnwrap(fixture.reasoner.requests.first)
        XCTAssertEqual(request.role, .reasoning)
        XCTAssertEqual(request.input["memories"]?.array, [snapshot.modelInput],
            "The real request builder must send this exact kept revision.")
        let pending = try XCTUnwrap(store.compareResults[.qwen]?.receipt)
        XCTAssertEqual(pending.localLessons, [snapshot])
        XCTAssertFalse(store.confirmLessonHelped(provider: .qwen, requestID: pending.requestID, snapshot: snapshot))
        XCTAssertEqual(try fixture.assertGrowth(fixture.projection(), nodeID: nodeID, applications: 0), contentID)
        fixture.reasoner.release()
        let firstLane = try await fixture.completed()
        let first = try XCTUnwrap(firstLane.receipt)
        XCTAssertEqual(store.reviewableEvolutionLessons(provider: .qwen, requestID: first.requestID), [snapshot])
        XCTAssertTrue(store.evolution.usefulReceipts.isEmpty, "Validated model citation is not reviewed usefulness.")
        XCTAssertEqual(try fixture.assertGrowth(fixture.projection(), nodeID: nodeID, applications: 0), contentID)

        XCTAssertTrue(store.confirmLessonHelped(provider: .qwen, requestID: first.requestID, snapshot: snapshot))
        let reviewed = try fixture.projection()
        XCTAssertEqual(try fixture.assertGrowth(reviewed, nodeID: nodeID, applications: 1), contentID)
        XCTAssertEqual(reviewed.structure.nodes.first?.anchorID, retained.structure.nodes.first?.anchorID,
            "Reviewed use strengthens the retained record's existing artwork anchor.")
        XCTAssertFalse(store.confirmLessonHelped(provider: .qwen, requestID: first.requestID, snapshot: snapshot))
        XCTAssertEqual(store.evolution.usefulReceipts.count, 1)

        // A newly completed retry has its own history receipt, but identical input
        // and exact lesson support cannot inflate the application count.
        let secondLane = try await fixture.answer()
        let second = try XCTUnwrap(secondLane.receipt)
        XCTAssertNotEqual(second.requestID, first.requestID)
        XCTAssertEqual(second.inputDigest, first.inputDigest)
        XCTAssertTrue(store.confirmLessonHelped(provider: .qwen, requestID: second.requestID, snapshot: snapshot))
        XCTAssertEqual(store.evolution.usefulReceipts.count, 2)
        XCTAssertEqual(try fixture.assertGrowth(fixture.projection(), nodeID: nodeID, applications: 1), contentID)
        XCTAssertEqual(try Data(contentsOf: fixture.preferenceURL), preferenceBytes)
        try fixture.assertPhysicsOnly(nodeID: nodeID)

        XCTAssertTrue(store.evolution.save(), store.evolution.status)
        let reopened = fixture.reopen()
        XCTAssertTrue(reopened.evolution.load(), reopened.evolution.status)
        XCTAssertEqual(reopened.keptLessons, [lesson])
        XCTAssertEqual(reopened.evolution.usefulReceipts, store.evolution.usefulReceipts)
        let loaded = try fixture.projection(in: reopened)
        XCTAssertNotEqual(loaded.scene.sessionID, reviewed.scene.sessionID)
        XCTAssertEqual(try fixture.assertGrowth(loaded, nodeID: nodeID, applications: 1), contentID)
        XCTAssertTrue(reopened.reviewableEvolutionLessons(provider: .qwen, requestID: first.requestID).isEmpty,
            "Loading evidence cannot fabricate a completed live answer.")
        XCTAssertFalse(reopened.particleMotion.grab(nodeID: nodeID, offset: .init(x: 0.1, y: 0),
            sceneDigest: reviewed.scene.motionID))

        reopened.evolution.withdrawLessonUse(requestID: try XCTUnwrap(UUID(uuidString: first.requestID)))
        XCTAssertEqual(try fixture.assertGrowth(fixture.projection(in: reopened), nodeID: nodeID, applications: 1), contentID)
        reopened.evolution.withdrawLessonUse(requestID: try XCTUnwrap(UUID(uuidString: second.requestID)))
        XCTAssertEqual(try fixture.assertGrowth(fixture.projection(in: reopened), nodeID: nodeID, applications: 0), contentID)
        XCTAssertEqual(reopened.keptLessons, [lesson], "Revoking use preserves the retained lesson.")
        XCTAssertTrue(reopened.evolution.save(), reopened.evolution.status)
        let revoked = fixture.reopen()
        XCTAssertTrue(revoked.evolution.load(), revoked.evolution.status)
        XCTAssertEqual(try fixture.assertGrowth(fixture.projection(in: revoked), nodeID: nodeID, applications: 0), contentID)
        XCTAssertTrue(revoked.evolution.usefulReceipts.allSatisfy { $0.lessonUse == nil })
        XCTAssertEqual(fixture.reasoner.requests.count, 2, "Review, replay, physics, reopen and revoke add no inference.")
        await reopened.shutdownAssistant()
        await revoked.shutdownAssistant()
    }

    func testLessonCorrectionAndWithdrawalRetireExactGrowthAndStaleGestures() async throws {
        for withdraw in [false, true] {
            let fixture = try ParticleJourneyFixture()
            defer { fixture.clean() }
            let store = fixture.store, lesson = try fixture.keepLesson()
            let snapshot = LessonSnapshot(lesson: lesson), oldID = CompanionGraph.lessonNodeID(lesson)
            let lane = try await fixture.answer()
            let receipt = try XCTUnwrap(lane.receipt)
            XCTAssertTrue(store.confirmLessonHelped(provider: .qwen, requestID: receipt.requestID, snapshot: snapshot))
            let old = try fixture.projection()
            let oldContent = try fixture.assertGrowth(old, nodeID: oldID, applications: 1)
            XCTAssertTrue(store.particleMotion.grab(nodeID: oldID, offset: .init(x: 0.1, y: 0), sceneDigest: old.scene.motionID))
            if withdraw {
                XCTAssertTrue(store.withdrawLesson(id: lesson.id, expectedRevision: store.lessonRevision))
            } else {
                store.beginLessonCorrection(revisingID: lesson.id)
                var draft = try XCTUnwrap(store.lessonDraft)
                draft.text = "Start with the corrected decision and one next step."
                XCTAssertTrue(store.keepLesson(draft), store.lessonMessage)
            }
            let current = try fixture.projection()
            XCTAssertNil(current.scene.growthByRecordID[oldID])
            XCTAssertFalse(current.structure.nodes.contains { $0.contentID == oldContent })
            XCTAssertNil(store.particleMotion.snapshot(sceneDigest: current.scene.motionID).offsets[oldID])
            XCTAssertFalse(store.particleMotion.grab(nodeID: oldID, offset: .init(x: 0.1, y: 0), sceneDigest: old.scene.motionID))
            XCTAssertFalse(store.confirmLessonHelped(provider: .qwen, requestID: receipt.requestID, snapshot: snapshot))
            if !withdraw {
                let revised = try XCTUnwrap(store.keptLessons.first)
                XCTAssertEqual(revised.id, lesson.id)
                XCTAssertEqual(revised.revision, lesson.revision + 1)
                XCTAssertNotEqual(try fixture.assertGrowth(current, nodeID: CompanionGraph.lessonNodeID(revised), applications: 0), oldContent)
            }
            XCTAssertEqual(store.evolution.usefulReceipts.count, 1, "Historical feedback is retained without restoring its old support.")
            XCTAssertEqual(fixture.reasoner.requests.count, 1)
        }
    }

    func testRetainedSourceCorrectionAndForgetInvalidatePageDerivedLessonGrowth() async throws {
        for forget in [false, true] {
            let fixture = try ParticleJourneyFixture()
            defer { fixture.clean() }
            let store = fixture.store
            let source = try store.readingSources.keep(title: "Decision source", text: "Cedar was selected; confirm the owner next.")
            let anchor = try store.readingSources.makeAnchor(sourceID: source.id,
                range: NSRange(location: 0, length: source.text.utf16.count))
            let draft = try store.readingSources.saveKnowledgePage(title: "Decision record", body: "Cedar was selected.",
                kind: .concept, anchors: [anchor])
            let page = try store.readingSources.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
            XCTAssertTrue(store.useKnowledgePageInChat(page, openAssistant: false))
            store.prompt = "Explain this decision record."
            let acquisitionLane = try await fixture.answer()
            let acquisition = try XCTUnwrap(acquisitionLane.receipt)
            XCTAssertEqual(acquisition.knowledgeDependencies, [page.binding])
            let lesson = try fixture.keepLesson(fromReply: true)
            XCTAssertEqual(lesson.origin?.requestID, acquisition.requestID)
            XCTAssertEqual(lesson.origin?.knowledgePages, [page.binding])
            store.detachKnowledgePages()
            let snapshot = LessonSnapshot(lesson: lesson), nodeID = CompanionGraph.lessonNodeID(lesson)
            let useLane = try await fixture.answer()
            let use = try XCTUnwrap(useLane.receipt)
            XCTAssertNotEqual(use.requestID, acquisition.requestID)
            XCTAssertEqual(use.knowledgeDependencies, [page.binding])
            XCTAssertFalse(store.confirmLessonHelped(provider: .qwen, requestID: use.requestID, snapshot: snapshot),
                "Page-backed requests currently have no evolution feedback admission path.")
            let prior = try fixture.projection()
            let contentID = try fixture.assertGrowth(prior, nodeID: nodeID, applications: 0)
            XCTAssertTrue(store.evolution.usefulReceipts.isEmpty)
            let pageID = KnowledgePageGraph.nodeID(page.binding)
            XCTAssertNotNil(prior.scene.growthByRecordID[pageID])

            if forget { try store.readingSources.forget(id: source.id) }
            else { try store.readingSources.replace(id: source.id, title: source.title, text: "Birch replaces the earlier decision.") }
            let files = try fixture.files()
            let current = try fixture.projection()
            XCTAssertNotNil(store.readingSources.availability(of: page))
            XCTAssertNil(store.currentKeptLesson(matching: snapshot))
            XCTAssertNil(current.scene.growthByRecordID[nodeID])
            XCTAssertNil(current.scene.growthByRecordID[pageID])
            XCTAssertFalse(current.structure.nodes.contains { $0.contentID == contentID })
            XCTAssertTrue(current.structure.nodes.isEmpty)
            XCTAssertFalse(store.confirmLessonHelped(provider: .qwen, requestID: use.requestID, snapshot: snapshot))
            XCTAssertEqual(store.keptLessons, [lesson], "A stale source makes support unavailable without erasing authored lessons.")
            XCTAssertEqual(try fixture.files(), files, "Source revalidation and projection are read-only.")
            XCTAssertEqual(fixture.reasoner.requests.count, 2)
        }
    }
}

@MainActor private final class ParticleJourneyFixture {
    struct Projection {
        let scene: CompanionParticleScene
        let sidecar: LiminalKnowledgeBindings.Sidecar
        let structure: LiminalPointStructure
    }
    var now: Date { Date() }
    let root: URL
    let preferenceURL: URL
    let reasoner = ParticleJourneyRoleClient()
    let selector = ParticleJourneyRoleClient()
    let store: CompanionStore
    private lazy var asset = makeAsset()

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("archi-particle-journey-\(UUID())")
        preferenceURL = root.appendingPathComponent("preferences.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let origin = String(repeating: "a", count: 64)
        let identity = LocalQiMon(character: .kin, originDigest: origin, welcomedAt: Date())
        try NativePreferenceDocument(qiMon: identity).encoded().write(to: preferenceURL)
        let local = HamptonReasonsAssistant(reasoner: reasoner, contextSelector: selector)
        store = CompanionStore(preferenceURL: preferenceURL, assistant: local,
            assistantFactory: { _, _ in local }, wallClock: { Date() }, allowsPlay: false)
        store.evolution.observeJourneyOrigin(origin)
        XCTAssertTrue(store.connectLiminalLearningStudy())
    }

    func reopen() -> CompanionStore {
        let local = HamptonReasonsAssistant(reasoner: reasoner, contextSelector: selector)
        return CompanionStore(preferenceURL: preferenceURL, assistant: local,
            assistantFactory: { _, _ in local }, wallClock: { Date() }, allowsPlay: false)
    }

    func keepLesson(fromReply: Bool = false) throws -> KeptLesson {
        store.beginLessonCorrection(for: fromReply ? .qwen : nil)
        var draft = try XCTUnwrap(store.lessonDraft)
        draft.topic = "meeting notes"
        draft.text = "Start with the decision, then give two concrete next steps."
        XCTAssertTrue(store.keepLesson(draft), store.lessonMessage)
        store.prompt = "Help organize these meeting notes."
        return try XCTUnwrap(store.keptLessons.last)
    }

    func start() async throws {
        store.setAssistantRoute(.local)
        if store.connection(for: .qwen) != .ready { store.connectAssistant(provider: .qwen) }
        try await wait { self.store.connection(for: .qwen) == .ready }
        store.submit()
        XCTAssertTrue(store.isWorking, store.status)
    }

    func completed() async throws -> AssistantLaneResult {
        try await wait { !self.store.isWorking }
        let lane = try XCTUnwrap(store.compareResults[.qwen])
        XCTAssertEqual(lane.state, .complete, lane.status)
        return lane
    }

    func answer() async throws -> AssistantLaneResult {
        try await start()
        return try await completed()
    }

    func wait(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("The in-process particle journey did not reach its expected state.")
        throw NSError(domain: "ParticleExperienceJourneyTests", code: 1)
    }

    func projection(in owner: CompanionStore? = nil) throws -> Projection {
        let owner = owner ?? store
        let scene = try XCTUnwrap(owner.companionParticleScene(at: now))
        let body = try XCTUnwrap(owner.liminalKnowledgePresentation(asset: asset, at: now, forMemoryMap: true))
        return Projection(scene: scene, sidecar: body.sidecar, structure: try XCTUnwrap(body.structure))
    }

    @discardableResult
    func assertGrowth(_ projection: Projection, nodeID: String, applications: Int,
                      file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let growth = try XCTUnwrap(projection.scene.growthByRecordID[nodeID], file: file, line: line)
        let binding = try XCTUnwrap(projection.sidecar.bindings.first { $0.nodeID == nodeID }, file: file, line: line)
        let motif = try XCTUnwrap(projection.structure.nodes.first { $0.contentID == growth.contentID }, file: file, line: line)
        XCTAssertEqual(growth.applications, applications, file: file, line: line)
        XCTAssertEqual(growth.reviewedApplicationCount, applications, file: file, line: line)
        XCTAssertEqual(motif.applications, applications, file: file, line: line)
        XCTAssertEqual(motif.anchorID, binding.anchorID, "Liminal growth belongs to this exact inspected native record.", file: file, line: line)
        XCTAssertEqual(projection.scene.graph.nodes.filter { $0.id == nodeID }.count, 1, file: file, line: line)
        XCTAssertEqual(projection.scene.field.particles.filter { $0.nodeID == nodeID }.count, 1, file: file, line: line)
        return growth.contentID
    }

    func assertPhysicsOnly(nodeID: String) throws {
        let before = try projection(), bytes = try files()
        let lessons = store.keptLessons, receipts = store.evolution.usefulReceipts
        let calls = reasoner.requests.count, scene = before.scene, motion = store.particleMotion
        XCTAssertTrue(store.selectMemoryParticle(nodeID, in: scene))
        XCTAssertTrue(motion.grab(nodeID: nodeID, offset: .init(x: 0.14, y: -0.08), sceneDigest: scene.motionID))
        let grabbed = motion.snapshot(sceneDigest: scene.motionID)
        XCTAssertGreaterThan(try XCTUnwrap(grabbed.offsets[nodeID]).length, 0.1)
        motion.release(nodeID: nodeID, sceneDigest: scene.motionID)
        _ = motion.sample(sceneDigest: scene.motionID, time: 10, active: true, reduceMotion: false)
        let moving = motion.sample(sceneDigest: scene.motionID, time: 10.05, active: true, reduceMotion: false)
        XCTAssertNotEqual(moving.offsets[nodeID], grabbed.offsets[nodeID])
        XCTAssertEqual(motion.sample(sceneDigest: scene.motionID, time: 10.05, active: true, reduceMotion: false), moving,
            "The map and avatar sampling the same tick share one physics frame.")
        XCTAssertEqual(motion.snapshot(sceneDigest: scene.motionID), moving)
        XCTAssertEqual(motion.sample(sceneDigest: scene.motionID, time: 11, active: true, reduceMotion: true), moving)
        XCTAssertEqual(motion.sample(sceneDigest: scene.motionID, time: 12, active: false, reduceMotion: false), moving)
        let after = try projection()
        XCTAssertEqual(after.scene, before.scene)
        XCTAssertEqual(after.structure, before.structure)
        XCTAssertEqual(store.keptLessons, lessons)
        XCTAssertEqual(store.evolution.usefulReceipts, receipts)
        XCTAssertEqual(try files(), bytes, "Particle gestures, integration and projections cannot write any owner journal.")
        XCTAssertEqual(reasoner.requests.count, calls)
    }

    func files() throws -> [String: Data] {
        let entries = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
        var result: [String: Data] = [:]
        for case let file as URL in entries where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            result[String(file.path.dropFirst(root.path.count))] = try Data(contentsOf: file)
        }
        return result
    }

    func clean() {
        store.cancelWork()
        reasoner.release()
        store.disconnectAssistant()
        XCTAssertTrue(selector.requests.isEmpty, "Optional context inference remains disabled.")
        try? FileManager.default.removeItem(at: root)
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
            frames: [], motionControls: [:], endpointImages: .init(status: "unavailable", renderer: nil, camera: nil, images: [], receipt: nil, reason: "Synthetic binding fixture"), comparison: reference)
        return LiminalPointAsset(packageURL: root.appendingPathComponent("synthetic-asset"), manifestSHA256: digest,
            manifest: manifest, artIDs: Array(UInt32(0)..<UInt32(50_000)), finish: nil, surfaceLight: nil)
    }
}

@MainActor private final class ParticleJourneyRoleClient: LocalRoleClient {
    private(set) var requests: [LocalRoleRequest] = []
    var hold = false
    private var pending: CheckedContinuation<Void, Never>?
    var hasPending: Bool { pending != nil }
    func connect() async throws {}
    func disconnect() {}
    func release() {
        hold = false
        let continuation = pending
        pending = nil
        continuation?.resume()
    }
    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
        requests.append(request)
        let memories = request.input["memories"]?.array?.compactMap { $0["id"]?.string } ?? []
        let sources = request.input["sources"]?.array?.compactMap { $0["id"]?.string } ?? []
        if hold { await withCheckedContinuation { pending = $0 } }
        let output: JSONValue = .object([
            "requestID": .string(request.id), "schema": .string("archi-reason-proposal/v1"),
            "kind": .string("ANSWER"), "answer": .string("A checked synthetic decision and next step."),
            "uncertainty": .string(""), "sourceIDs": .array(sources.map(JSONValue.string)),
            "memoryIDs": .array(memories.map(JSONValue.string))
        ])
        return LocalRoleResult(requestID: request.id, role: request.role,
            text: String(decoding: try JSONEncoder().encode(output), as: UTF8.self),
            model: QwenModelMetadata(name: "particle-journey-fixture", family: "fixture", parameterSize: "fixture",
                quantization: "fixture", digest: String(repeating: "a", count: 64)), elapsedMilliseconds: 1)
    }
}
