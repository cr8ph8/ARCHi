import Foundation
import XCTest
@testable import ARCHiDesktop

final class CompanionParticleSelectionTests: XCTestCase {
    @MainActor
    func testSeedAndMapShareExactSelectionAndExplicitClearWithoutSavingOrCallingModels() throws {
        let fixture = try ParticleSelectionFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        let scene = try XCTUnwrap(store.companionParticleScene())
        let ids = fixture.lessons.map(CompanionGraph.lessonNodeID)
        let files = try fixture.files()
        let section = store.section

        XCTAssertTrue(store.selectMemoryParticle(ids[0], in: scene))
        XCTAssertEqual(store.selectedGraphNodeID, ids[0])
        XCTAssertEqual(store.memoryParticleSelection?.selectedID(in: scene), ids[0])
        XCTAssertEqual(store.section, section, "A highlight alone must not navigate")

        XCTAssertTrue(store.selectGraphRecord(ids[1], in: scene.graph, particleScene: scene))
        XCTAssertEqual(store.selectedGraphNodeID, ids[1])
        XCTAssertEqual(store.memoryParticleSelection?.selectedID(in: scene), ids[1])
        XCTAssertTrue(store.selectGraphRecord(nil, in: scene.graph, particleScene: scene))
        XCTAssertNil(store.selectedGraphNodeID)
        XCTAssertNil(store.memoryParticleSelection)

        XCTAssertTrue(store.selectMemoryParticle(ids[0], in: scene, openInspector: true))
        XCTAssertEqual(store.section, .nodeLab)
        store.openMemoryMap()
        XCTAssertNil(store.selectedGraphNodeID)
        XCTAssertNil(store.memoryParticleSelection)
        XCTAssertEqual(try fixture.files(), files)
        fixture.assertNoInferenceOrDevelopment()
    }

    @MainActor
    func testCorrectedRecordRejectsStaleSeedAndMapCallbacksIncludingClear() throws {
        let fixture = try ParticleSelectionFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        let oldScene = try XCTUnwrap(store.companionParticleScene())
        let oldID = CompanionGraph.lessonNodeID(fixture.lessons[0])
        XCTAssertTrue(store.selectMemoryParticle(oldID, in: oldScene))

        // An actual owner revision makes the displayed old snapshot stale.
        store.beginLessonCorrection(revisingID: fixture.lessons[0].id)
        var correction = try XCTUnwrap(store.lessonDraft)
        correction.text = "Use the corrected synthetic procedure."
        XCTAssertTrue(store.keepLesson(correction))
        let currentLesson = try XCTUnwrap(store.keptLessons.first { $0.id == fixture.lessons[0].id })
        let currentID = CompanionGraph.lessonNodeID(currentLesson)
        let currentScene = try XCTUnwrap(store.companionParticleScene())
        XCTAssertNotEqual(oldID, currentID)
        XCTAssertFalse(currentScene.graph.nodes.contains { $0.id == oldID })
        XCTAssertTrue(store.selectMemoryParticle(currentID, in: currentScene))
        let currentPick = store.memoryParticleSelection
        let files = try fixture.files()

        XCTAssertFalse(store.selectGraphRecord(nil, in: oldScene.graph, particleScene: oldScene))
        XCTAssertFalse(store.selectGraphRecord(oldID, in: oldScene.graph, particleScene: oldScene))
        XCTAssertFalse(store.selectMemoryParticle(oldID, in: oldScene))
        XCTAssertFalse(store.selectGraphRecord(oldID, in: currentScene.graph, particleScene: currentScene))
        XCTAssertEqual(store.selectedGraphNodeID, currentID)
        XCTAssertEqual(store.memoryParticleSelection, currentPick)
        XCTAssertEqual(try fixture.files(), files)
        fixture.assertNoInferenceOrDevelopment()
    }

    @MainActor
    func testActivityScopeMirrorsOnlyCurrentMemoryRecordsAndRejectsMismatchedProjection() throws {
        let fixture = try ParticleSelectionFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.share(text: "An unretained synthetic working copy.", name: "Selection fixture.txt")
        let scene = try XCTUnwrap(store.companionParticleScene())
        let activity = store.companionGraphSnapshot()
        let memoryIDs = Set(scene.graph.nodes.map(\.id))
        let activityOnly = try XCTUnwrap(activity.nodes.first { !memoryIDs.contains($0.id) })
        let memoryID = CompanionGraph.lessonNodeID(fixture.lessons[0])
        XCTAssertNotEqual(LiminalKnowledgeBindings.digest(activity), scene.graphDigest)
        let files = try fixture.files()

        XCTAssertTrue(store.selectGraphRecord(memoryID, in: activity, particleScene: nil))
        XCTAssertEqual(store.memoryParticleSelection?.selectedID(in: scene), memoryID)
        XCTAssertFalse(store.selectGraphRecord(nil, in: activity, particleScene: scene))
        XCTAssertFalse(store.selectGraphRecord(nil, in: scene.graph, particleScene: nil))
        XCTAssertEqual(store.selectedGraphNodeID, memoryID)
        XCTAssertEqual(store.memoryParticleSelection?.selectedID(in: scene), memoryID)

        XCTAssertTrue(store.selectGraphRecord(activityOnly.id, in: activity, particleScene: nil))
        XCTAssertEqual(store.selectedGraphNodeID, activityOnly.id)
        XCTAssertNil(store.memoryParticleSelection, "An activity-only record must not highlight another Seed particle")
        XCTAssertTrue(store.selectGraphRecord(nil, in: activity, particleScene: nil))
        XCTAssertNil(store.selectedGraphNodeID)
        XCTAssertNil(store.memoryParticleSelection)
        XCTAssertEqual(try fixture.files(), files)
        fixture.assertNoInferenceOrDevelopment()
    }

    @MainActor
    func testMemoryMapWithoutParticleSceneSelectsMethodBesideWorkingCopyAndRejectsWrongScope() throws {
        let fixture = try ParticleSelectionFixture(withIdentity: false)
        defer { fixture.cleanUp() }
        let store = fixture.store
        let source = try store.readingSources.keep(title: "Synthetic method source", text: "Use precise verbs.")
        let anchor = try store.readingSources.makeAnchor(sourceID: source.id,
            range: NSRange(location: 0, length: source.text.utf16.count))
        let draft = try store.readingSources.saveKnowledgePage(title: "Precise revisions", body: "Prefer precise verbs.",
            kind: .concept, anchors: [anchor])
        let page = try store.readingSources.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        XCTAssertTrue(store.keepKnowledgeProcedure(page: page, title: "Precise revision", instruction: "Use precise verbs.",
            requirements: .init(mustBeShorter: false, preserveNumbersAndLinks: true)))
        let method = try XCTUnwrap(store.documentProcedures.latestProcedures.first)
        store.share(text: "An unretained synthetic working copy.", name: "Selection fixture.txt")
        XCTAssertNil(store.companionParticleScene())
        let memory = store.memoryMapSnapshot()
        let activity = store.companionGraphSnapshot()
        let methodID = DocumentMethodGraph.nodeID(method.binding)
        let memoryIDs = Set(memory.nodes.map(\.id))
        let activityOnly = try XCTUnwrap(activity.nodes.first { !memoryIDs.contains($0.id) })
        XCTAssertNotEqual(LiminalKnowledgeBindings.digest(memory), LiminalKnowledgeBindings.digest(activity))
        let files = try fixture.files()
        let section = store.section

        XCTAssertTrue(store.selectGraphRecord(methodID, in: memory, particleScene: nil, memoryOnly: true))
        XCTAssertEqual(store.selectedGraphNodeID, methodID)
        XCTAssertNil(store.memoryParticleSelection)
        XCTAssertEqual(store.section, section)
        XCTAssertFalse(store.selectGraphRecord(nil, in: memory, particleScene: nil), "All activity validates its own scope.")
        XCTAssertFalse(store.selectGraphRecord(nil, in: activity, particleScene: nil, memoryOnly: true))
        XCTAssertFalse(store.selectGraphRecord(activityOnly.id, in: memory, particleScene: nil, memoryOnly: true))
        XCTAssertEqual(store.selectedGraphNodeID, methodID)

        XCTAssertTrue(store.selectGraphRecord(nil, in: memory, particleScene: nil, memoryOnly: true))
        XCTAssertNil(store.selectedGraphNodeID)
        XCTAssertTrue(store.selectGraphRecord(activityOnly.id, in: activity, particleScene: nil))
        XCTAssertEqual(store.selectedGraphNodeID, activityOnly.id)
        XCTAssertNil(store.memoryParticleSelection)
        XCTAssertEqual(try fixture.files(), files)
        fixture.assertNoInferenceOrDevelopment()
    }

    @MainActor
    func testMemoryMapWithoutParticleSceneRejectsRevisedRecordsReloadedGraphAndRecovery() throws {
        let fixture = try ParticleSelectionFixture(withIdentity: false)
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.share(text: "An unretained working copy.", name: "Selection fixture.txt")
        let oldGraph = store.memoryMapSnapshot()
        let oldID = CompanionGraph.lessonNodeID(fixture.lessons[0])
        XCTAssertNil(store.companionParticleScene())
        XCTAssertTrue(store.selectGraphRecord(oldID, in: oldGraph, particleScene: nil, memoryOnly: true))

        store.beginLessonCorrection(revisingID: fixture.lessons[0].id)
        var correction = try XCTUnwrap(store.lessonDraft)
        correction.text = "Check the revised synthetic method."
        XCTAssertTrue(store.keepLesson(correction))
        let current = try XCTUnwrap(store.keptLessons.first { $0.id == fixture.lessons[0].id })
        let currentID = CompanionGraph.lessonNodeID(current)
        let currentGraph = store.memoryMapSnapshot()
        XCTAssertTrue(store.selectGraphRecord(currentID, in: currentGraph, particleScene: nil, memoryOnly: true))
        let files = try fixture.files()
        XCTAssertFalse(store.selectGraphRecord(nil, in: oldGraph, particleScene: nil, memoryOnly: true))
        XCTAssertFalse(store.selectGraphRecord(oldID, in: currentGraph, particleScene: nil, memoryOnly: true))
        XCTAssertEqual(store.selectedGraphNodeID, currentID)
        XCTAssertEqual(try fixture.files(), files)

        let replacement = KeptLesson(topic: "Restored profile", text: "Keep this profile's distinct saved procedure.",
            createdAt: fixture.now)
        try NativePreferenceDocument(lessons: [replacement]).encoded().write(to: fixture.url)
        try store.admitRestoredProfile()
        XCTAssertNil(store.selectedGraphNodeID)
        XCTAssertNil(store.companionParticleScene())
        let restoredGraph = store.memoryMapSnapshot()
        let restoredID = CompanionGraph.lessonNodeID(replacement)
        XCTAssertTrue(store.selectGraphRecord(restoredID, in: restoredGraph, particleScene: nil, memoryOnly: true))
        XCTAssertFalse(store.selectGraphRecord(nil, in: currentGraph, particleScene: nil, memoryOnly: true))
        XCTAssertFalse(store.selectGraphRecord(currentID, in: currentGraph, particleScene: nil, memoryOnly: true))
        XCTAssertEqual(store.selectedGraphNodeID, restoredID)
        let restoredFiles = try fixture.files()

        store.blockProfileForRecovery("Synthetic recovery block")
        XCTAssertNil(store.selectedGraphNodeID)
        XCTAssertNil(store.memoryParticleSelection)
        XCTAssertFalse(store.selectGraphRecord(restoredID, in: restoredGraph, particleScene: nil, memoryOnly: true))
        XCTAssertEqual(try fixture.files(), restoredFiles)
        fixture.assertNoInferenceOrDevelopment()
    }

    @MainActor
    func testProfileReloadRetiresIdenticalRecordIDsAndRecoveryBlocksSelection() throws {
        let fixture = try ParticleSelectionFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        let oldScene = try XCTUnwrap(store.companionParticleScene())
        let id = CompanionGraph.lessonNodeID(fixture.lessons[0])
        XCTAssertTrue(store.selectMemoryParticle(id, in: oldScene))
        let nextIdentity = LocalQiMon(character: .kin, originDigest: String(repeating: "b", count: 64),
                                     welcomedAt: fixture.now)
        try NativePreferenceDocument(lessons: fixture.lessons, qiMon: nextIdentity).encoded().write(to: fixture.url)
        try store.admitRestoredProfile()

        XCTAssertNil(store.selectedGraphNodeID)
        XCTAssertNil(store.memoryParticleSelection)
        XCTAssertFalse(store.unityPresentation.isSharing)
        XCTAssertFalse(store.unityPresentation.hasRenderAcknowledgment)
        let currentScene = try XCTUnwrap(store.companionParticleScene())
        XCTAssertNotEqual(currentScene.originDigest, oldScene.originDigest)
        XCTAssertTrue(currentScene.graph.nodes.contains { $0.id == id }, "Identical record IDs do not imply identical profile ownership")
        XCTAssertTrue(store.selectMemoryParticle(id, in: currentScene))
        let currentPick = store.memoryParticleSelection
        let files = try fixture.files()
        XCTAssertFalse(store.selectMemoryParticle(id, in: oldScene))
        XCTAssertFalse(store.selectGraphRecord(nil, in: oldScene.graph, particleScene: oldScene))
        XCTAssertEqual(store.memoryParticleSelection, currentPick)
        XCTAssertEqual(store.selectedGraphNodeID, id)

        store.blockProfileForRecovery("Synthetic recovery block")
        XCTAssertNil(store.selectedGraphNodeID)
        XCTAssertNil(store.memoryParticleSelection)
        XCTAssertFalse(store.selectMemoryParticle(id, in: currentScene))
        XCTAssertFalse(store.selectGraphRecord(id, in: currentScene.graph, particleScene: nil))
        XCTAssertEqual(try fixture.files(), files)
        fixture.assertNoInferenceOrDevelopment()
    }
}

@MainActor private final class ParticleSelectionFixture {
    let now: Date
    let root: URL
    let url: URL
    let lessons: [KeptLesson]
    let client: ParticleSelectionNoCalls
    let store: CompanionStore

    init(withIdentity: Bool = true) throws {
        let date = Date(timeIntervalSince1970: 1_789_000_000)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-particle-selection-\(UUID())")
        let profile = directory.appendingPathComponent("preferences.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let records = [
            KeptLesson(topic: "Planning", text: "Retain the synthetic procedure.", createdAt: date.addingTimeInterval(-10)),
            KeptLesson(topic: "Review", text: "Check the source version before use.", createdAt: date.addingTimeInterval(-10))
        ]
        let identity = LocalQiMon(character: .hampton, originDigest: String(repeating: "a", count: 64), welcomedAt: date)
        try NativePreferenceDocument(lessons: records, qiMon: withIdentity ? identity : nil).encoded().write(to: profile)
        let client = ParticleSelectionNoCalls()
        now = date; root = directory; url = profile; lessons = records
        self.client = client
        store = CompanionStore(preferenceURL: profile, assistant: client, assistantFactory: { _, _ in client },
                               wallClock: { date }, allowsPlay: false)
    }

    func cleanUp() {
        store.disconnectAssistant()
        try? FileManager.default.removeItem(at: root)
    }

    func files() throws -> [String: Data] {
        let entries = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
        var result: [String: Data] = [:]
        for case let file as URL in entries where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            result[String(file.path.dropFirst(root.path.count))] = try Data(contentsOf: file)
        }
        return result
    }

    func assertNoInferenceOrDevelopment(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(client.calls, 0, file: file, line: line)
        XCTAssertTrue(store.compareResults.isEmpty, file: file, line: line)
        XCTAssertTrue(store.tokenSteward.tasks.isEmpty, file: file, line: line)
        XCTAssertTrue(store.tokenSteward.observations.isEmpty, file: file, line: line)
        XCTAssertTrue(store.evolution.usefulReceipts.isEmpty, file: file, line: line)
        XCTAssertNil(store.evolution.kinGrowthRecord, file: file, line: line)
    }
}

@MainActor private final class ParticleSelectionNoCalls: AssistantClient {
    private(set) var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.stopped }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; throw AssistantFailure.stopped
    }
    func disconnect() {}
}
