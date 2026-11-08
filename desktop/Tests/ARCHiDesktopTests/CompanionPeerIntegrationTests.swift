import XCTest
@testable import ARCHiDesktop

/// Exercises peer admission against the Store's live graph and lifecycle owners.
/// Pure protocol and malformed-input cases belong to RepresentationPeerTests.
final class CompanionPeerIntegrationTests: XCTestCase {
    @MainActor
    func testAcceptingLiveGraphReportPreservesModelsFilesAndNativeState() async throws {
        let lesson = KeptLesson(topic: "planning", text: "Use the reviewed three-step outline.",
                                createdAt: PeerIntegrationFixture.instant)
        let fixture = try PeerIntegrationFixture(lessons: [lesson])
        defer { fixture.cleanUp() }
        let store = fixture.store
        let sourceURL = fixture.directory.appendingPathComponent("planning.txt")
        try Data("The planning review is Friday.".utf8).write(to: sourceURL)
        XCTAssertTrue(store.importWorkingCopy(from: sourceURL))
        store.placed(at: CGPoint(x: 120, y: 240))
        store.prompt = "Help with planning."
        try await connect(store)
        store.submit()
        try await waitUntil { !store.isWorking }
        XCTAssertEqual(store.compareResults[.qwen]?.state, .complete)

        let graph = store.companionGraphSnapshot(at: fixture.now)
        XCTAssertTrue(graph.nodes.contains { $0.kind == .request })
        XCTAssertTrue(graph.nodes.contains { $0.kind == .answer })
        XCTAssertTrue(graph.nodes.contains { $0.kind == .lesson })
        let files = try fixture.files()
        let calls = fixture.calls
        let position = store.position
        let context = store.contextTicket()
        let preferences = store.preferences
        let lanes = store.compareResults
        let activity = store.activity
        let lessonRevision = store.lessonRevision
        let evolutionRevision = store.evolution.revision
        let evolutionHistory = store.evolution.history
        let usefulReceipts = store.evolution.usefulReceipts
        let inspector = store.hamptonSnapshot
        let sharedText = store.sharedText
        let sourceName = store.sourceName
        let notice = store.workingCopyNotice

        store.preparePeerInspection()
        let candidate = try XCTUnwrap(store.peerLab.inspection.candidate)
        XCTAssertEqual(candidate.nodeCount, graph.nodes.count)
        XCTAssertEqual(candidate.edgeCount, graph.edges.count)
        XCTAssertEqual(candidate.truncatedCount, graph.truncatedCount)
        XCTAssertEqual(candidate.unresolvedEdgeCount, 0)
        XCTAssertTrue(store.peerLab.inspection.reports.isEmpty)
        store.admitPeerInspection()

        XCTAssertEqual(store.peerLab.lastDecision?.decision, .commit)
        XCTAssertEqual(store.peerLab.inspection.reports, [candidate])
        XCTAssertNil(store.peerLab.inspection.candidate)
        XCTAssertEqual(store.companionGraphSnapshot(at: fixture.now), graph)
        XCTAssertEqual(fixture.calls, calls, "Peer inspection must not initiate model or connection work")
        XCTAssertEqual(try fixture.files(), files, "A session report must not rewrite documents or preferences")
        XCTAssertEqual(store.position, position)
        XCTAssertEqual(store.contextTicket(), context)
        XCTAssertEqual(store.preferences, preferences)
        XCTAssertEqual(store.compareResults, lanes)
        XCTAssertEqual(store.activity, activity)
        XCTAssertEqual(store.keptLessons, [lesson])
        XCTAssertEqual(store.lessonRevision, lessonRevision)
        XCTAssertEqual(store.evolution.revision, evolutionRevision)
        XCTAssertEqual(store.evolution.history, evolutionHistory)
        XCTAssertEqual(store.evolution.usefulReceipts, usefulReceipts)
        XCTAssertEqual(store.hamptonSnapshot, inspector)
        XCTAssertEqual(store.sharedText, sharedText)
        XCTAssertEqual(store.sourceName, sourceName)
        XCTAssertEqual(store.workingCopyNotice, notice)
    }

    @MainActor
    func testReplacingSameNamedSourceCancelsPendingCandidate() throws {
        let fixture = try PeerIntegrationFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.share(text: "First reviewed copy.", name: "planning.txt")
        store.preparePeerInspection()
        let old = try XCTUnwrap(store.peerLab.inspection.candidate)
        let oldRevision = store.sourceRevision

        store.share(text: "Replacement reviewed copy.", name: "planning.txt")

        XCTAssertGreaterThan(store.sourceRevision, oldRevision)
        XCTAssertNil(store.peerLab.inspection.candidate)
        XCTAssertEqual(store.peerLab.inspection.currentAttempt?.progress, .cancelled)
        store.admitPeerInspection()
        XCTAssertNotEqual(store.peerLab.lastDecision?.decision, .commit)
        XCTAssertTrue(store.peerLab.inspection.reports.isEmpty)

        store.preparePeerInspection()
        let fresh = try XCTUnwrap(store.peerLab.inspection.candidate)
        XCTAssertNotEqual(fresh.sourceDigest, old.sourceDigest)
        XCTAssertNotEqual(fresh.contextDigest, old.contextDigest)
        store.admitPeerInspection()
        XCTAssertEqual(store.peerLab.lastDecision?.decision, .commit)
        XCTAssertEqual(store.peerLab.inspection.reports, [fresh])
    }

    @MainActor
    func testCompletedRequestChangesGraphAndRefusesEarlierCandidate() async throws {
        let fixture = try PeerIntegrationFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        fixture.reasoner.hold = true
        store.prompt = "Keep this request pending until its graph is inspected."
        try await connect(store)
        store.submit()
        try await waitUntil { fixture.reasoner.isPending }
        store.preparePeerInspection()
        let pending = try XCTUnwrap(store.peerLab.inspection.candidate)
        let ticket = store.contextTicket()

        fixture.reasoner.resolve()
        try await waitUntil { !store.isWorking }

        XCTAssertEqual(store.compareResults[.qwen]?.state, .complete)
        XCTAssertEqual(store.contextTicket(), ticket, "Completion changes the graph within the same request context")
        XCTAssertNotEqual(store.peerInspectionInput().contextDigest, pending.contextDigest)
        store.admitPeerInspection()
        XCTAssertEqual(store.peerLab.lastDecision?.decision, .escalate)
        XCTAssertTrue(store.peerLab.inspection.reports.isEmpty)

        store.preparePeerInspection()
        let fresh = try XCTUnwrap(store.peerLab.inspection.candidate)
        store.admitPeerInspection()
        XCTAssertEqual(store.peerLab.lastDecision?.decision, .commit)
        XCTAssertEqual(store.peerLab.inspection.reports, [fresh])
    }

    @MainActor
    func testPermitExpiresAtDeadlineUsingInjectedMonotonicTime() throws {
        let fixture = try PeerIntegrationFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.share(text: "A stable source during the permit window.", name: "planning.txt")
        store.preparePeerInspection()
        let attempt = try XCTUnwrap(store.peerLab.inspection.currentAttempt)
        let digest = store.peerInspectionInput().contextDigest
        XCTAssertGreaterThan(attempt.permitExpiresAt, fixture.clock.now)

        fixture.clock.now = attempt.permitExpiresAt
        XCTAssertEqual(store.peerInspectionInput().contextDigest, digest)
        store.admitPeerInspection()

        XCTAssertEqual(store.peerLab.lastDecision?.decision, .escalate)
        XCTAssertEqual(store.peerLab.inspection.currentAttempt?.progress, .escalated)
        XCTAssertNil(store.peerLab.inspection.candidate)
        XCTAssertTrue(store.peerLab.inspection.reports.isEmpty)
    }

    @MainActor
    func testStopCancelsPendingInspectionWithoutAcceptance() throws {
        let fixture = try PeerIntegrationFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.preparePeerInspection()
        XCTAssertNotNil(store.peerLab.inspection.candidate)

        store.cancelWork()

        XCTAssertNil(store.peerLab.inspection.candidate)
        XCTAssertEqual(store.peerLab.inspection.currentAttempt?.progress, .cancelled)
        store.admitPeerInspection()
        XCTAssertNotEqual(store.peerLab.lastDecision?.decision, .commit)
        XCTAssertTrue(store.peerLab.inspection.reports.isEmpty)
        XCTAssertEqual(fixture.calls, [0, 0, 0, 0, 0, 0])
    }

    @MainActor
    func testStartingNewLocalConversationCancelsPendingInspection() throws {
        let fixture = try PeerIntegrationFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.preparePeerInspection()
        XCTAssertNotNil(store.peerLab.inspection.candidate)

        store.startNewLocalConversation()

        XCTAssertNil(store.peerLab.inspection.candidate)
        XCTAssertEqual(store.peerLab.inspection.currentAttempt?.progress, .cancelled)
        store.admitPeerInspection()
        XCTAssertNotEqual(store.peerLab.lastDecision?.decision, .commit)
        XCTAssertTrue(store.peerLab.inspection.reports.isEmpty)
    }

    @MainActor
    func testShutdownCancelsCandidateAndRefusesFurtherPreparationOrAdmission() async throws {
        let fixture = try PeerIntegrationFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.preparePeerInspection()
        let attemptID = try XCTUnwrap(store.peerLab.inspection.currentAttempt?.id)

        await store.shutdownAssistant()

        XCTAssertNil(store.peerLab.inspection.candidate)
        XCTAssertEqual(store.peerLab.inspection.currentAttempt?.progress, .cancelled)
        let history = store.peerLab.inspection.history
        let calls = fixture.calls
        store.preparePeerInspection()
        store.admitPeerInspection()
        XCTAssertEqual(store.peerLab.inspection.currentAttempt?.id, attemptID)
        XCTAssertEqual(store.peerLab.inspection.history, history)
        XCTAssertNil(store.peerLab.inspection.candidate)
        XCTAssertTrue(store.peerLab.inspection.reports.isEmpty)
        XCTAssertEqual(fixture.calls, calls)
    }

    @MainActor
    private func connect(_ store: CompanionStore) async throws {
        store.connectAssistant()
        try await waitUntil { store.connectionState == .ready }
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("The in-process peer fixture did not finish within its bounded wait")
        throw PeerIntegrationFailure.waitTimedOut
    }
}

private enum PeerIntegrationFailure: Error { case waitTimedOut }

@MainActor
private final class PeerIntegrationClock {
    var now: TimeInterval = 100
}

@MainActor
private final class PeerIntegrationFixture {
    static let instant = Date(timeIntervalSince1970: 1_500_000_000)
    let now = PeerIntegrationFixture.instant
    let clock = PeerIntegrationClock()
    let reasoner = PeerIntegrationRoleClient()
    let selector = PeerIntegrationRoleClient()
    let codex = PeerIntegrationCodexClient()
    let store: CompanionStore
    let directory: URL

    init(lessons: [KeptLesson] = []) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("archi-peer-integration-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let profile = directory.appendingPathComponent("preferences.json")
        try NativePreferenceDocument(lessons: lessons).encoded().write(to: profile)
        let local = HamptonReasonsAssistant(reasoner: reasoner, contextSelector: selector)
        let external = codex
        let instant = now
        let inspectionClock = clock
        store = CompanionStore(
            preferenceURL: profile,
            assistant: local,
            assistantFactory: { provider, _ in
                if provider == .qwen { return local }
                return external
            },
            monotonicTime: { inspectionClock.now },
            wallClock: { instant },
            allowsPlay: false
        )
    }

    var calls: [Int] {
        [reasoner.requests.count, selector.requests.count, codex.requests.count,
         reasoner.connectCount, selector.connectCount, codex.connectCount]
    }

    func files() throws -> [String: Data] {
        let urls = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        var result: [String: Data] = [:]
        while let url = urls?.nextObject() as? URL {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[String(url.path.dropFirst(directory.path.count))] = try Data(contentsOf: url)
            }
        }
        return result
    }

    func cleanUp() {
        store.disconnectAssistant(provider: .qwen)
        store.disconnectAssistant(provider: .codex)
        reasoner.drain()
        selector.drain()
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class PeerIntegrationRoleClient: LocalRoleClient {
    var hold = false
    private(set) var requests: [LocalRoleRequest] = []
    private(set) var connectCount = 0
    private var pending: CheckedContinuation<Void, Error>?
    var isPending: Bool { pending != nil }

    func connect() async throws { connectCount += 1 }
    func disconnect() {}
    func shutdown() async {}

    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
        requests.append(request)
        if hold { try await withCheckedThrowingContinuation { pending = $0 } }
        let payload: JSONValue
        switch request.role {
        case .reasoning:
            let ids: (String) -> [JSONValue] = { key in
                let identifiers = request.input[key]?.array?.compactMap { $0["id"]?.string } ?? []
                return identifiers.map(JSONValue.string)
            }
            payload = .object([
                "requestID": .string(request.id), "schema": .string("archi-reason-proposal/v1"),
                "kind": .string("ANSWER"), "answer": .string("Controlled peer fixture answer."),
                "uncertainty": .string(""), "sourceIDs": .array(ids("sources")),
                "memoryIDs": .array(ids("memories"))
            ])
        case .memorySelection:
            payload = .object([
                "requestID": .string(request.id), "schema": .string("archi-session-selection/v1"),
                "candidateIDs": .array([])
            ])
        case .memoryReminder:
            payload = .object([
                "requestID": .string(request.id), "schema": .string("archi-session-reminder/v1"),
                "decision": .string("NONE"), "memoryIDs": .array([])
            ])
        }
        return LocalRoleResult(
            requestID: request.id, role: request.role,
            text: String(decoding: try JSONEncoder().encode(payload), as: UTF8.self),
            model: QwenModelMetadata(name: "peer-fixture", family: "fixture", parameterSize: "fixture",
                                    quantization: "fixture", digest: String(repeating: "d", count: 64)),
            elapsedMilliseconds: 7,
            metrics: LocalInferenceMetrics(inputTokens: 20, outputTokens: 5, totalNanoseconds: 7_000_000)
        )
    }

    func resolve() {
        let continuation = pending
        pending = nil
        continuation?.resume()
    }

    func drain() {
        let continuation = pending
        pending = nil
        continuation?.resume(throwing: QwenFailure.stopped)
    }
}

@MainActor
private final class PeerIntegrationCodexClient: AssistantClient {
    private(set) var requests: [AssistantRequest] = []
    private(set) var connectCount = 0
    func connect() async throws { connectCount += 1 }
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        requests.append(request)
        onEvent(.text("Controlled external peer answer."))
    }
}
