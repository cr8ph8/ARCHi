import Foundation
import XCTest
@testable import ARCHiDesktop

/// Production owners with suspended in-process clients. No model or personal profile.
@MainActor
final class CompanionParticleActivityTests: XCTestCase {
    func testDesktopPresentationActivityReusesSceneButStillRechecksSourceContext() throws {
        let fixture = try ActivityFixture()
        defer { fixture.clean() }
        let (source, page) = try fixture.page()
        let store = fixture.store
        XCTAssertTrue(store.useKnowledgePageInChat(page, openAssistant: false))
        let scene = try XCTUnwrap(store.desktopParticlePresentationScene(atUptime: 100))
        XCTAssertEqual(store.desktopParticlePresentationActivity(in: scene, atUptime: 100.01).preparedNodeIDs,
            try fixture.ids(page: page, source: source, in: scene))

        let other = ReadingSourceLibrary(url: fixture.profile.deletingPathExtension().appendingPathExtension("reading-sources.json"))
        try other.replace(id: source.id, title: source.title, text: "A corrected synthetic supporting passage.")
        let files = try fixture.files()
        // The drawing cache remains reusable, but invalid request context may
        // not keep a prepared ring lit for those now-stale source bindings.
        XCTAssertEqual(store.desktopParticlePresentationActivity(in: scene, atUptime: 100.18), .empty)
        XCTAssertEqual(store.particleSceneCache, scene)
        XCTAssertEqual(store.desktopParticleSceneCheck?.uptime, 100)
        XCTAssertEqual(store.selectedKnowledgePages, [page.binding])
        XCTAssertEqual(store.desktopParticlePresentationActivity(in: scene, atUptime: 102), .empty)
        XCTAssertNotEqual(store.particleSceneCache?.motionID, scene.motionID)
        XCTAssertEqual(try fixture.files(), files)
        XCTAssertEqual(fixture.local.calls, 0)
    }

    func testDesktopPresentationActivityRejectsPreviousSessionAndRecoveryImmediately() throws {
        let fixture = try ActivityFixture()
        defer { fixture.clean() }
        let (_, page) = try fixture.page()
        let store = fixture.store
        XCTAssertTrue(store.useKnowledgePageInChat(page, openAssistant: false))
        let scene = try XCTUnwrap(store.desktopParticlePresentationScene(atUptime: 100))
        let files = try fixture.files()
        try store.admitRestoredProfile()
        let currentPage = try XCTUnwrap(store.readingSources.latestKnowledgePages.first)
        XCTAssertTrue(store.useKnowledgePageInChat(currentPage, openAssistant: false))
        let current = try XCTUnwrap(store.desktopParticlePresentationScene(atUptime: 100.01))
        XCTAssertEqual(current.digest, scene.digest)
        XCTAssertNotEqual(current.sessionID, scene.sessionID)
        XCTAssertFalse(store.desktopParticlePresentationActivity(in: current, atUptime: 100.02).preparedNodeIDs.isEmpty)
        XCTAssertEqual(store.desktopParticlePresentationActivity(in: scene, atUptime: 100.02), .empty)
        store.blockProfileForRecovery("Synthetic recovery boundary")
        XCTAssertEqual(store.desktopParticlePresentationActivity(in: current, atUptime: 100.03), .empty)
        XCTAssertEqual(try fixture.files(), files)
        XCTAssertEqual(fixture.local.calls, 0)
    }

    func testPreparedPageAndSourcesPreserveSelectionDraftAndFilesWithoutDispatch() throws {
        let fixture = try ActivityFixture()
        defer { fixture.clean() }
        let (source, page) = try fixture.page()
        let store = fixture.store
        store.prompt = "An unsent question."
        XCTAssertTrue(store.useKnowledgePageInChat(page, openAssistant: false))
        let scene = try XCTUnwrap(store.companionParticleScene())
        XCTAssertTrue(store.selectMemoryParticle("companion-archi", in: scene))
        let selection = store.memoryParticleSelection, files = try fixture.files()
        let result = store.companionParticleActivity(in: scene)

        XCTAssertEqual(result.preparedNodeIDs, try fixture.ids(page: page, source: source, in: scene))
        XCTAssertTrue(result.requestNodeIDs.isEmpty)
        XCTAssertEqual(store.memoryParticleSelection, selection)
        XCTAssertEqual(store.selectedGraphNodeID, "companion-archi")
        XCTAssertEqual(store.prompt, "An unsent question.")
        XCTAssertEqual(store.selectedKnowledgePages, [page.binding])
        XCTAssertEqual(try fixture.files(), files)
        XCTAssertEqual(fixture.local.calls, 0)
        XCTAssertTrue(store.tokenSteward.tasks.isEmpty)
        XCTAssertTrue(store.evolution.usefulReceipts.isEmpty)
    }

    func testSelectedReadingSourceIsPreparedOnlyForDocumentQuestion() throws {
        let fixture = try ActivityFixture()
        defer { fixture.clean() }
        let (source, _) = try fixture.page()
        let store = fixture.store
        store.selectReadingSource(source.id, selected: true)
        XCTAssertEqual(store.companionParticleActivity(in: try XCTUnwrap(store.companionParticleScene())), .empty)
        store.share(text: ActivityFixture.passage, name: "working.txt")
        store.selectReadingSource(source.id, selected: true)
        let scene = try XCTUnwrap(store.companionParticleScene())
        let id = try fixture.sourceID(source, in: scene)
        XCTAssertEqual(store.companionParticleActivity(in: scene).preparedNodeIDs, [id])
        store.selectText(range: NSRange(location: 0, length: ActivityFixture.passage.utf16.count), sourceRevision: store.sourceRevision)
        store.preparePassageRevision()
        XCTAssertTrue(store.companionParticleActivity(in: try XCTUnwrap(store.companionParticleScene())).preparedNodeIDs.isEmpty)
        XCTAssertEqual(fixture.local.calls, 0)
    }

    func testOwnedRequestStartsOnlyAfterConnectionAndReturnsToPreparedOnCompletion() async throws {
        let fixture = try ActivityFixture()
        defer { fixture.clean() }
        let (source, page) = try fixture.page()
        let store = fixture.store
        XCTAssertTrue(store.useKnowledgePageInChat(page, openAssistant: false))
        store.prompt = "Explain the selected note."
        fixture.local.holdConnection = true
        store.submit()
        try await fixture.wait { fixture.local.connectionPending }
        var scene = try XCTUnwrap(store.companionParticleScene())
        XCTAssertNil(store.currentParticleActivityReceipt)
        XCTAssertTrue(store.companionParticleActivity(in: scene).requestNodeIDs.isEmpty)
        XCTAssertEqual(store.companionParticleActivity(in: scene).preparedNodeIDs, try fixture.ids(page: page, source: source, in: scene))

        fixture.local.releaseConnection()
        try await fixture.wait { fixture.local.calls == 1 }
        scene = try XCTUnwrap(store.companionParticleScene())
        XCTAssertTrue(store.selectMemoryParticle("companion-archi", in: scene))
        let selection = store.memoryParticleSelection, files = try fixture.files()
        let request = try XCTUnwrap(store.currentParticleActivityReceipt)
        XCTAssertEqual(store.tokenSteward.tasks.first?.id, request.requestID)
        XCTAssertEqual(store.tokenSteward.tasks.first?.requestProvenance?.knowledgeDependencies, [page.binding])
        let activity = store.companionParticleActivity(in: scene)
        XCTAssertEqual(activity.requestNodeIDs, try fixture.ids(page: page, source: source, in: scene))
        XCTAssertTrue(activity.preparedNodeIDs.isEmpty, "Active references must not be counted twice.")
        XCTAssertEqual(store.memoryParticleSelection, selection)
        XCTAssertEqual(try fixture.files(), files)

        fixture.local.complete()
        try await fixture.wait { !store.isWorking }
        scene = try XCTUnwrap(store.companionParticleScene())
        XCTAssertNil(store.currentParticleActivityReceipt)
        XCTAssertTrue(store.companionParticleActivity(in: scene).requestNodeIDs.isEmpty)
        XCTAssertEqual(store.companionParticleActivity(in: scene).preparedNodeIDs, try fixture.ids(page: page, source: source, in: scene))
        XCTAssertTrue(store.evolution.usefulReceipts.isEmpty)

        XCTAssertEqual(fixture.local.calls, 1)
    }

    func testCancellationFailureAndExternalRouteDoNotRetainRequestRings() async throws {
        for cancel in [true, false] {
            let fixture = try ActivityFixture()
            defer { fixture.clean() }
            let (_, page) = try fixture.page()
            let store = fixture.store
            XCTAssertTrue(store.useKnowledgePageInChat(page))
            store.prompt = "Explain the selected note."
            store.submit()
            try await fixture.wait { fixture.local.calls == 1 }
            XCTAssertFalse(store.companionParticleActivity(in: try XCTUnwrap(store.companionParticleScene())).requestNodeIDs.isEmpty)
            if cancel { store.cancelWork(); fixture.local.resolve() } else { fixture.local.fail() }
            try await fixture.wait { !store.isWorking }
            XCTAssertNil(store.currentParticleActivityReceipt)
            XCTAssertTrue(store.companionParticleActivity(in: try XCTUnwrap(store.companionParticleScene())).requestNodeIDs.isEmpty)
            store.setAssistantRoute(.codex)
            store.submit()
            XCTAssertEqual(fixture.external.calls, 0, "Selected local pages cannot be sent through an external lane.")
            XCTAssertNil(store.currentParticleActivityReceipt)
        }
    }

    func testCapturedMethodSurvivesDraftDetachButExternalMethodChangeRetiresItsActivity() async throws {
        let fixture = try ActivityFixture()
        defer { fixture.clean() }
        let (source, page) = try fixture.page()
        let method = try fixture.method(page)
        let store = fixture.store
        try fixture.prepare(method)
        var scene = try XCTUnwrap(store.companionParticleScene())
        XCTAssertEqual(store.companionParticleActivity(in: scene).preparedNodeIDs, [DocumentMethodGraph.nodeID(method.binding)])
        let instruction = store.prompt
        store.prompt = "A different unsent instruction."
        XCTAssertTrue(store.companionParticleActivity(in: scene).preparedNodeIDs.isEmpty)
        store.prompt = instruction
        store.submit()
        try await fixture.wait { fixture.local.calls == 1 }
        let receipt = try XCTUnwrap(store.currentParticleActivityReceipt)
        XCTAssertEqual(store.documentRecord(requestID: receipt.requestID, provider: .qwen)?.procedureUse, method.binding)
        store.clearPreparedDocumentProcedure()
        scene = try XCTUnwrap(store.companionParticleScene())
        let expected = try fixture.ids(page: page, source: source, in: scene).union([DocumentMethodGraph.nodeID(method.binding)])
        XCTAssertEqual(store.companionParticleActivity(in: scene).requestNodeIDs, expected)
        XCTAssertFalse(try XCTUnwrap(fixture.local.request).localInput.contains(page.body),
            "A provenance ring must not claim the origin page body was sent to the model.")

        let other = DocumentProcedureLibrary(url: fixture.profile.deletingPathExtension().appendingPathExtension("document-procedures.json"))
        try other.withdraw(binding: method.binding)
        scene = try XCTUnwrap(store.companionParticleScene())
        XCTAssertTrue(store.companionParticleActivity(in: scene).requestNodeIDs.isEmpty)
        XCTAssertTrue(store.evolution.usefulReceipts.isEmpty)
    }

    func testExternalSourceCorrectionClearsActivityWithoutSubstitutingCurrentVersion() async throws {
        let fixture = try ActivityFixture()
        defer { fixture.clean() }
        let (source, page) = try fixture.page()
        let store = fixture.store
        XCTAssertTrue(store.useKnowledgePageInChat(page))
        store.prompt = "Explain the selected note."
        store.submit()
        try await fixture.wait { fixture.local.calls == 1 }
        let oldScene = try XCTUnwrap(store.companionParticleScene())
        XCTAssertFalse(store.companionParticleActivity(in: oldScene).requestNodeIDs.isEmpty)
        let other = ReadingSourceLibrary(url: fixture.profile.deletingPathExtension().appendingPathExtension("reading-sources.json"))
        _ = try other.replace(id: source.id, title: source.title, text: "A corrected synthetic supporting passage.")
        let files = try fixture.files()
        XCTAssertNil(store.currentParticleActivityReceipt)
        XCTAssertEqual(store.companionParticleActivity(in: oldScene), .empty)
        XCTAssertEqual(store.companionParticleActivity(in: try XCTUnwrap(store.companionParticleScene())), .empty)
        XCTAssertEqual(store.selectedKnowledgePages, [page.binding], "Presentation does not silently replace an attachment.")
        XCTAssertEqual(try fixture.files(), files)
    }

    func testTargetProjectionRequiresPageDigestSourceProvenanceAndMethodDigest() throws {
        let fixture = try ActivityFixture()
        defer { fixture.clean() }
        let (source, page) = try fixture.page()
        let method = try fixture.method(page)
        let graph = try XCTUnwrap(fixture.store.companionParticleScene()).graph
        let wrongPage = KnowledgePageBinding(id: page.id, revision: page.revision, digest: String(repeating: "f", count: 64))
        XCTAssertEqual(KnowledgePageGraph.nodeID(wrongPage), KnowledgePageGraph.nodeID(page.binding))
        let wrongSource = ReadingSourceBinding(id: source.id, revision: source.revision, digest: source.binding.digest,
            provenance: .init(origin: .model, acquisition: .userCopy, parents: [], digest: String(repeating: "e", count: 64)))
        let wrongMethod = DocumentProcedureUse(id: method.id, revision: method.revision, digest: String(repeating: "d", count: 64))
        XCTAssertTrue(CompanionParticleActivity.nodeIDs(in: graph, pages: [wrongPage], sources: [wrongSource], methods: [wrongMethod]).isEmpty)
        XCTAssertTrue(CompanionParticleActivity.nodeIDs(in: .init(nodes: [], edges: [], truncatedCount: graph.nodes.count),
            pages: [page.binding], sources: [source.binding], methods: [method.binding]).isEmpty)
    }

    func testSameProfileReloadAndRecoveryRetireOldSceneAndActivityWithoutWriting() throws {
        let fixture = try ActivityFixture()
        defer { fixture.clean() }
        let (_, page) = try fixture.page()
        let store = fixture.store
        XCTAssertTrue(store.useKnowledgePageInChat(page))
        let oldScene = try XCTUnwrap(store.companionParticleScene())
        let files = try fixture.files()
        try store.admitRestoredProfile()
        let currentPage = try XCTUnwrap(store.readingSources.latestKnowledgePages.first)
        XCTAssertTrue(store.useKnowledgePageInChat(currentPage))
        let current = try XCTUnwrap(store.companionParticleScene())
        XCTAssertEqual(oldScene.originDigest, current.originDigest)
        XCTAssertNotEqual(oldScene.sessionID, current.sessionID)
        XCTAssertEqual(store.companionParticleActivity(in: oldScene), .empty)
        XCTAssertFalse(store.companionParticleActivity(in: current).preparedNodeIDs.isEmpty)
        store.blockProfileForRecovery("Synthetic recovery boundary")
        XCTAssertEqual(store.companionParticleActivity(in: current), .empty)
        XCTAssertEqual(try fixture.files(), files)
        XCTAssertEqual(fixture.local.calls, 0)
    }

    func testGenericProfileMapProjectsPreparedAndRequestReferencesInExactScope() async throws {
        let fixture = try ActivityFixture(personalIdentity: false)
        defer { fixture.clean() }
        let (source, page) = try fixture.page()
        let store = fixture.store
        XCTAssertNil(store.companionParticleScene())
        store.share(text: ActivityFixture.passage, name: "working.txt")
        XCTAssertTrue(store.useKnowledgePageInChat(page, openAssistant: false))
        let sessionID = store.liminalStructureSessionID
        let graph = store.memoryMapSnapshot()
        let sourceID = try XCTUnwrap(graph.nodes.first { $0.target == .readingSource(.init(binding: source.binding)) }).id
        let expected: Set<String> = [KnowledgePageGraph.nodeID(page.binding), sourceID]
        let files = try fixture.files()

        XCTAssertEqual(store.companionParticleActivity(in: graph, sessionID: sessionID, memoryOnly: true).preparedNodeIDs, expected)
        XCTAssertEqual(store.companionParticleActivity(in: graph, sessionID: sessionID, memoryOnly: false), .empty,
            "A working copy makes the all-activity scope different from the memory map.")
        XCTAssertEqual(store.companionParticleActivity(in: store.companionGraphSnapshot(), sessionID: sessionID, memoryOnly: false).preparedNodeIDs, expected)
        XCTAssertEqual(try fixture.files(), files)

        store.prompt = "Explain the selected note."
        store.submit()
        try await fixture.wait { fixture.local.calls == 1 }
        let active = store.companionParticleActivity(in: store.memoryMapSnapshot(), sessionID: sessionID, memoryOnly: true)
        XCTAssertEqual(active.requestNodeIDs, expected)
        XCTAssertTrue(active.preparedNodeIDs.isEmpty)
        let fullGraph = store.companionGraphSnapshot()
        let aliases = fullGraph.nodes.filter {
            $0.status == "Historical reference" &&
            ($0.target == .knowledgePage(page.binding) || $0.target == .readingSource(.init(binding: source.binding)))
        }
        XCTAssertEqual(aliases.count, 2, "All activity retains separate exact page/source references from Usage.")
        XCTAssertEqual(Set(aliases.map(\.title)), ["Captured source version", "Captured page version"])
        let aliasIDs = Set(aliases.map(\.id))
        let fullActivity = store.companionParticleActivity(in: fullGraph, sessionID: sessionID, memoryOnly: false)
        XCTAssertEqual(fullActivity.requestNodeIDs, expected, "One ring per canonical memory record, without request-history aliases.")
        XCTAssertTrue(fullActivity.requestNodeIDs.isDisjoint(with: aliasIDs))
        XCTAssertEqual(store.readingSources.sources, [source])
        XCTAssertEqual(store.readingSources.latestKnowledgePages, [page])
        fixture.local.complete()
        try await fixture.wait { !store.isWorking }
        let completed = store.companionParticleActivity(in: store.memoryMapSnapshot(), sessionID: sessionID, memoryOnly: true)
        XCTAssertTrue(completed.requestNodeIDs.isEmpty)
        XCTAssertEqual(completed.preparedNodeIDs, expected)
        let afterCompletion = store.companionParticleActivity(in: store.companionGraphSnapshot(), sessionID: sessionID, memoryOnly: false)
        XCTAssertEqual(afterCompletion.preparedNodeIDs, expected)
        XCTAssertTrue(afterCompletion.requestNodeIDs.isEmpty)
        XCTAssertTrue(afterCompletion.preparedNodeIDs.isDisjoint(with: aliasIDs), "Old request references do not become prepared-memory anchors.")
        XCTAssertNil(store.companionParticleScene())
    }

    func testGenericProfileReloadRejectsIdenticalGraphFromPreviousOwner() throws {
        let fixture = try ActivityFixture(personalIdentity: false)
        defer { fixture.clean() }
        let (_, page) = try fixture.page()
        let store = fixture.store
        XCTAssertTrue(store.useKnowledgePageInChat(page, openAssistant: false))
        let graph = store.memoryMapSnapshot(), sessionID = store.liminalStructureSessionID
        let files = try fixture.files()
        XCTAssertFalse(store.companionParticleActivity(in: graph, sessionID: sessionID, memoryOnly: true).preparedNodeIDs.isEmpty)
        try store.admitRestoredProfile()
        let currentPage = try XCTUnwrap(store.readingSources.latestKnowledgePages.first)
        XCTAssertTrue(store.useKnowledgePageInChat(currentPage, openAssistant: false))
        XCTAssertEqual(LiminalKnowledgeBindings.digest(graph), LiminalKnowledgeBindings.digest(store.memoryMapSnapshot()))
        XCTAssertNotEqual(sessionID, store.liminalStructureSessionID)
        XCTAssertEqual(store.companionParticleActivity(in: graph, sessionID: sessionID, memoryOnly: true), .empty)
        XCTAssertFalse(store.companionParticleActivity(in: graph, sessionID: store.liminalStructureSessionID, memoryOnly: true).preparedNodeIDs.isEmpty)
        store.blockProfileForRecovery("Synthetic recovery boundary")
        XCTAssertEqual(store.companionParticleActivity(in: graph, sessionID: store.liminalStructureSessionID, memoryOnly: true), .empty)
        XCTAssertEqual(try fixture.files(), files)
        XCTAssertEqual(fixture.local.calls, 0)
    }
}

@MainActor
private final class ActivityFixture {
    static let passage = "I would like to ask you if you would please close the door."
    let root: URL
    let profile: URL
    let local = ParticleActivityClient()
    let external = ParticleActivityClient()
    let store: CompanionStore

    init(personalIdentity: Bool = true) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("archi-particle-activity-\(UUID())")
        profile = root.appendingPathComponent("preferences.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let identity = personalIdentity ? LocalQiMon(character: .hampton, originDigest: String(repeating: "a", count: 64), welcomedAt: Date()) : nil
        try NativePreferenceDocument(qiMon: identity).encoded().write(to: profile)
        let local = local, external = external
        store = CompanionStore(preferenceURL: profile, assistant: local,
            assistantFactory: { provider, _ in provider == .qwen ? local : external },
            allowsPlay: false, tokenSteward: TokenStewardStore(url: root.appendingPathComponent("usage.json")))
    }

    func page() throws -> (ReadingSourceSnapshot, KnowledgePage) {
        let source = try store.readingSources.keep(title: "Synthetic source", text: "A concise request preserves its action.")
        let anchor = try store.readingSources.makeAnchor(sourceID: source.id, range: NSRange(location: 0, length: source.text.utf16.count))
        let draft = try store.readingSources.saveKnowledgePage(title: "Concise request", body: "Synthetic interpretation of the source.", kind: .concept, anchors: [anchor])
        return (source, try store.readingSources.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision))
    }

    func method(_ page: KnowledgePage) throws -> DocumentProcedure {
        XCTAssertTrue(store.keepKnowledgeProcedure(page: page, title: "Concise request", instruction: "Shorten the selected request.",
            requirements: .init(mustBeShorter: true, preserveNumbersAndLinks: false)))
        return try XCTUnwrap(store.documentProcedures.latestProcedures.first)
    }

    func prepare(_ method: DocumentProcedure) throws {
        store.setAssistantRoute(.automatic)
        store.setLocalWorkPreference(.reasoning)
        store.share(text: Self.passage, name: "synthetic.txt")
        store.selectText(range: NSRange(location: 0, length: Self.passage.utf16.count), sourceRevision: store.sourceRevision)
        store.preparePassageRevision(shorten: true)
        store.documentRequirements.preserveNumbersAndLinks = false
        XCTAssertTrue(store.prepareDocumentProcedure(method.binding))
    }

    func sourceID(_ source: ReadingSourceSnapshot, in scene: CompanionParticleScene) throws -> String {
        try XCTUnwrap(scene.graph.nodes.first { $0.target == .readingSource(.init(binding: source.binding)) }).id
    }

    func ids(page: KnowledgePage, source: ReadingSourceSnapshot, in scene: CompanionParticleScene) throws -> Set<String> {
        [KnowledgePageGraph.nodeID(page.binding), try sourceID(source, in: scene)]
    }

    func files() throws -> [String: Data] {
        let entries = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
        var result: [String: Data] = [:]
        for case let file as URL in entries where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            result[String(file.path.dropFirst(root.path.count))] = try Data(contentsOf: file)
        }
        return result
    }

    func wait(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Synthetic request did not reach the expected owner state: \(store.status)")
        throw AssistantFailure.timedOut
    }

    func clean() {
        store.cancelWork(); store.disconnectAssistant(); local.resolve(); external.resolve()
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private final class ParticleActivityClient: AssistantClient {
    var holdConnection = false
    var connectionPending: Bool { connectionContinuation != nil }
    private(set) var calls = 0
    private(set) var request: AssistantRequest?
    private var connectionContinuation: CheckedContinuation<Void, Error>?
    private var continuation: CheckedContinuation<Void, Error>?
    private var handler: (@MainActor (AssistantEvent) -> Void)?

    func connect() async throws {
        if holdConnection { try await withCheckedThrowingContinuation { connectionContinuation = $0 } }
    }
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; self.request = request; handler = onEvent
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func releaseConnection() { let pending = connectionContinuation; connectionContinuation = nil; pending?.resume() }
    func complete() { handler?(.text("Synthetic answer.")); resolve() }
    func fail() { let pending = continuation; continuation = nil; pending?.resume(throwing: AssistantFailure.timedOut) }
    func resolve() { releaseConnection(); let pending = continuation; continuation = nil; pending?.resume() }
}
