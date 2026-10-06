import Foundation
import XCTest
@testable import ARCHiDesktop

final class CompanionResonancePlaybackTests: XCTestCase {
    private let origin = String(repeating: "a", count: 64)
    private let digest = String(repeating: "b", count: 64)

    func testOnlyExplicitRequestsPlayAndLatestRequestReplacesCurrentNote() {
        var gate = CompanionResonancePlaybackGate()
        let first = request(), next = request()
        let current = context()
        XCTAssertEqual(gate.update(request: nil, context: current), .none)
        XCTAssertEqual(gate.update(request: first, context: current), .play(first))
        XCTAssertEqual(gate.update(request: first, context: current), .none)
        XCTAssertEqual(gate.update(request: next, context: current), .play(next))
        gate.finish(first.id)
        XCTAssertEqual(gate.update(request: next, context: current), .none)
        XCTAssertEqual(gate.update(request: nil, context: current), .stop)
        XCTAssertEqual(gate.update(request: next, context: current), .none,
                       "The finished or cancelled request must not become a pending replay")
    }

    func testSuppressedAndInvalidRequestsAreConsumedAndCannotReplayWhenSoundReturns() {
        let blocked = [context(enabled: false), context(quiet: true), context(visible: false),
                       context(inMemoryMap: false), context(origin: String(repeating: "c", count: 64)),
                       context(digest: String(repeating: "c", count: 64)),
                       context(nodeID: "different"), context(kind: .source)]
        for state in blocked {
            var gate = CompanionResonancePlaybackGate()
            let requested = request()
            XCTAssertEqual(gate.update(request: requested, context: state), .none)
            XCTAssertEqual(gate.update(request: requested, context: context()), .none)
            XCTAssertEqual(gate.update(request: nil, context: context()), .none)
            XCTAssertEqual(gate.update(request: requested, context: context()), .none)
            let fresh = request()
            XCTAssertEqual(gate.update(request: fresh, context: context()), .play(fresh))
        }
    }

    func testActiveSoundStopsWhenAnyCurrentBindingOrAvailabilityChanges() {
        let invalid: [CompanionResonancePlaybackContext?] = [nil,
            context(enabled: false), context(quiet: true), context(visible: false), context(inMemoryMap: false),
            context(origin: String(repeating: "d", count: 64)), context(digest: String(repeating: "d", count: 64)),
            context(nodeID: "different"), context(kind: .source)]
        for state in invalid {
            var gate = CompanionResonancePlaybackGate()
            let requested = request()
            XCTAssertEqual(gate.update(request: requested, context: context()), .play(requested))
            XCTAssertEqual(gate.update(request: requested, context: state), .stop)
            XCTAssertEqual(gate.update(request: requested, context: context()), .none)
        }
    }

    @MainActor
    func testStoreRequiresSelectedCurrentRecordAndNeverSavesOrCallsAModel() throws {
        let fixture = try ResonancePlaybackFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        let scene = try XCTUnwrap(store.companionParticleScene())
        let id = fixture.nodeID
        let files = try fixture.files()
        XCTAssertFalse(store.previewResonance(nodeID: id, in: scene.graph, particleScene: scene, capturedOriginDigest: scene.originDigest))
        XCTAssertTrue(store.selectMemoryParticle(id, in: scene, openInspector: true))
        XCTAssertNil(store.resonancePlaybackRequest, "Selecting a node cannot request audio")
        XCTAssertTrue(store.canPreviewResonance(nodeID: id, in: scene.graph, particleScene: scene, capturedOriginDigest: scene.originDigest))
        XCTAssertTrue(store.previewResonance(nodeID: id, in: scene.graph, particleScene: scene, capturedOriginDigest: scene.originDigest))
        let first = try XCTUnwrap(store.resonancePlaybackRequest)
        XCTAssertEqual(first.originDigest, scene.originDigest)
        XCTAssertEqual(first.graphDigest, scene.graphDigest)
        XCTAssertEqual(first.nodeID, id)
        XCTAssertEqual(first.kind, .lesson)
        XCTAssertEqual(first.scope, .memory)
        XCTAssertTrue(store.resonancePlaybackContext(for: first, visible: true).permits(first))
        XCTAssertTrue(store.previewResonance(nodeID: id, in: scene.graph, particleScene: scene, capturedOriginDigest: scene.originDigest))
        XCTAssertNotEqual(store.resonancePlaybackRequest?.id, first.id)
        XCTAssertEqual(try fixture.files(), files)
        fixture.assertNoInferenceOrDevelopment()
    }

    @MainActor
    func testStoreConsumesRequestOnMuteQuietNavigationHideAndSelectionClear() throws {
        let fixture = try ResonancePlaybackFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        let scene = try XCTUnwrap(store.companionParticleScene())
        XCTAssertTrue(store.selectMemoryParticle(fixture.nodeID, in: scene, openInspector: true))
        func request() {
            XCTAssertTrue(store.previewResonance(nodeID: fixture.nodeID, in: scene.graph, particleScene: scene, capturedOriginDigest: scene.originDigest))
            XCTAssertNotNil(store.resonancePlaybackRequest)
        }
        request()
        store.preferences.musicalCues = false
        XCTAssertNil(store.resonancePlaybackRequest)
        XCTAssertFalse(store.previewResonance(nodeID: fixture.nodeID, in: scene.graph, particleScene: scene, capturedOriginDigest: scene.originDigest))
        store.preferences.musicalCues = true
        XCTAssertNil(store.resonancePlaybackRequest)
        request()
        store.preferences.musicalVolume = 0
        XCTAssertNil(store.resonancePlaybackRequest)
        store.preferences.musicalVolume = 0.35
        request()
        store.preferences.quiet = true
        XCTAssertNil(store.resonancePlaybackRequest)
        store.preferences.quiet = false
        request()
        store.section = .assistant
        XCTAssertNil(store.resonancePlaybackRequest)
        store.section = .nodeLab
        request()
        store.isVisible = false
        XCTAssertNil(store.resonancePlaybackRequest)
        store.isVisible = true
        request()
        XCTAssertTrue(store.selectGraphRecord(nil, in: scene.graph, particleScene: scene))
        XCTAssertNil(store.resonancePlaybackRequest)
        fixture.assertNoInferenceOrDevelopment()
    }

    @MainActor
    func testSourceRevisionAndProfileReloadRejectStaleRequestsIncludingIdenticalIDs() throws {
        let fixture = try ResonancePlaybackFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        let old = try XCTUnwrap(store.companionParticleScene())
        XCTAssertTrue(store.selectMemoryParticle(fixture.nodeID, in: old, openInspector: true))
        XCTAssertTrue(store.previewResonance(nodeID: fixture.nodeID, in: old.graph, particleScene: old, capturedOriginDigest: old.originDigest))
        let requested = try XCTUnwrap(store.resonancePlaybackRequest)
        store.beginLessonCorrection(revisingID: fixture.lesson.id)
        var draft = try XCTUnwrap(store.lessonDraft)
        draft.text = "Use this corrected synthetic note."
        XCTAssertTrue(store.keepLesson(draft))
        XCTAssertFalse(store.resonancePlaybackContext(for: requested, visible: true).permits(requested))
        XCTAssertFalse(store.previewResonance(nodeID: fixture.nodeID, in: old.graph, particleScene: old, capturedOriginDigest: old.originDigest))

        let corrected = try XCTUnwrap(store.companionParticleScene())
        let currentLesson = try XCTUnwrap(store.keptLessons.first { $0.id == fixture.lesson.id })
        let currentID = CompanionGraph.lessonNodeID(currentLesson)
        XCTAssertTrue(store.selectMemoryParticle(currentID, in: corrected, openInspector: true))
        XCTAssertTrue(store.previewResonance(nodeID: currentID, in: corrected.graph, particleScene: corrected, capturedOriginDigest: corrected.originDigest))
        // Even restoring the same identity and bytes clears transient requests.
        try store.admitRestoredProfile()
        XCTAssertNil(store.resonancePlaybackRequest)
        XCTAssertNil(store.selectedGraphNodeID)
        XCTAssertFalse(store.resonancePlaybackContext(for: requested, visible: true).permits(requested))
        fixture.assertNoInferenceOrDevelopment()
    }

    @MainActor
    func testActivityCallbackCannotRebindIdenticalRecordsToAnotherOrigin() throws {
        let fixture = try ResonancePlaybackFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        let old = try XCTUnwrap(store.companionParticleScene())
        let activity = store.companionGraphSnapshot()
        XCTAssertTrue(store.selectGraphRecord(fixture.nodeID, in: activity, particleScene: nil))
        store.section = .nodeLab
        XCTAssertTrue(store.previewResonance(nodeID: fixture.nodeID, in: activity, particleScene: nil,
                                            capturedOriginDigest: old.originDigest))
        let identity = LocalQiMon(character: .hampton, originDigest: String(repeating: "c", count: 64),
                                 welcomedAt: Date(timeIntervalSince1970: 1_789_000_000))
        var preferences = CompanionPreferences()
        preferences.musicalCues = true
        try NativePreferenceDocument(preferences: preferences, lessons: [fixture.lesson], qiMon: identity)
            .encoded().write(to: fixture.root.appendingPathComponent("preferences.json"))
        try store.admitRestoredProfile()
        XCTAssertNil(store.resonancePlaybackRequest)
        let current = try XCTUnwrap(store.companionParticleScene())
        let currentActivity = store.companionGraphSnapshot()
        XCTAssertEqual(LiminalKnowledgeBindings.digest(activity), LiminalKnowledgeBindings.digest(currentActivity))
        XCTAssertNotEqual(current.originDigest, old.originDigest)
        XCTAssertTrue(store.selectGraphRecord(fixture.nodeID, in: currentActivity, particleScene: nil))
        store.section = .nodeLab
        XCTAssertFalse(store.previewResonance(nodeID: fixture.nodeID, in: activity, particleScene: nil,
                                             capturedOriginDigest: old.originDigest))
        XCTAssertFalse(store.previewResonance(nodeID: fixture.nodeID, in: currentActivity, particleScene: nil,
                                             capturedOriginDigest: nil))
        XCTAssertNil(store.resonancePlaybackRequest)
        XCTAssertTrue(store.previewResonance(nodeID: fixture.nodeID, in: currentActivity, particleScene: nil,
                                            capturedOriginDigest: current.originDigest))
        fixture.assertNoInferenceOrDevelopment()
    }

    private func request() -> CompanionResonancePlaybackRequest {
        .init(id: UUID(), originDigest: origin, graphDigest: digest, nodeID: "record", kind: .lesson, scope: .memory)
    }

    private func context(origin: String? = nil, digest: String? = nil, nodeID: String = "record",
                         kind: CompanionGraphKind = .lesson, enabled: Bool = true,
                         quiet: Bool = false, visible: Bool = true,
                         inMemoryMap: Bool = true) -> CompanionResonancePlaybackContext {
        .init(originDigest: origin ?? self.origin, graphDigest: digest ?? self.digest,
            selectedNodeID: nodeID, selectedNodeKind: kind, enabled: enabled, quiet: quiet,
            visible: visible, inMemoryMap: inMemoryMap)
    }
}

@MainActor private final class ResonancePlaybackFixture {
    let root: URL
    let lesson: KeptLesson
    let client: ResonanceNoCalls
    let store: CompanionStore
    var nodeID: String { CompanionGraph.lessonNodeID(lesson) }

    init() throws {
        let date = Date(timeIntervalSince1970: 1_789_000_000)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-resonance-\(UUID())")
        let url = directory.appendingPathComponent("preferences.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lesson = KeptLesson(topic: "Listening", text: "Retain this synthetic example.", createdAt: date.addingTimeInterval(-10))
        let identity = LocalQiMon(character: .hampton, originDigest: String(repeating: "a", count: 64), welcomedAt: date)
        var preferences = CompanionPreferences()
        preferences.musicalCues = true
        try NativePreferenceDocument(preferences: preferences, lessons: [lesson], qiMon: identity).encoded().write(to: url)
        let client = ResonanceNoCalls()
        root = directory; self.lesson = lesson; self.client = client
        store = CompanionStore(preferenceURL: url, assistant: client, assistantFactory: { _, _ in client },
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
        XCTAssertTrue(store.evolution.usefulReceipts.isEmpty, file: file, line: line)
        XCTAssertNil(store.evolution.kinGrowthRecord, file: file, line: line)
    }
}

@MainActor private final class ResonanceNoCalls: AssistantClient {
    private(set) var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.stopped }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; throw AssistantFailure.stopped
    }
    func disconnect() {}
}
