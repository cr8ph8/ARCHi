import XCTest
@testable import ARCHiDesktop

/// Exercises the Store's live projection boundary with controlled in-process clients.
/// Domain formatting and malformed-graph cases belong to CompanionGraph's own tests.
final class CompanionGraphIntegrationTests: XCTestCase {
    @MainActor
    func testOpeningAndReadingGraphAddsNoCallsWritesPlacementOrEvolution() async throws {
        let lesson = KeptLesson(topic: "planning", text: "Use the reviewed three-step outline.",
                                createdAt: GraphStoreFixture.instant)
        let fixture = try GraphStoreFixture(lessons: [lesson])
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.share(text: "The planning review is Friday.", name: "graph-planning.txt")
        store.placed(at: CGPoint(x: 120, y: 240))
        store.prompt = "Help with planning."
        try await connect(store)
        store.submit()
        try await waitUntil { !store.isWorking }
        XCTAssertEqual(store.compareResults[.qwen]?.state, .complete)

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
        store.open(.nodeLab)
        let first = store.companionGraphSnapshot(at: fixture.now)
        XCTAssertTrue(first.nodes.contains { $0.kind == .request })
        XCTAssertTrue(first.nodes.contains { $0.kind == .answer })
        XCTAssertTrue(first.nodes.contains { $0.kind == .lesson })
        for _ in 0..<20 {
            XCTAssertEqual(store.companionGraphSnapshot(at: fixture.now), first)
        }
        XCTAssertEqual(fixture.calls, calls, "Inspection must not initiate model or connection work")
        XCTAssertEqual(try fixture.files(), files, "Inspection must not create another saved graph or rewrite existing preferences")
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
    }

    @MainActor
    func testStoppedLateCompletionCannotReviveTheInspectedGraph() async throws {
        let fixture = try GraphStoreFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        fixture.reasoner.hold = true
        store.prompt = "Keep this controlled request pending."
        try await connect(store)
        store.submit()
        try await waitUntil { fixture.reasoner.isPending }
        XCTAssertTrue(store.companionGraphSnapshot(at: fixture.now).nodes.contains { $0.kind == .request })

        store.cancelWork()
        let stopped = store.companionGraphSnapshot(at: fixture.now)
        let lane = try XCTUnwrap(store.compareResults[.qwen])
        XCTAssertEqual(lane.state, .cancelled)
        let files = try fixture.files()
        let context = store.contextTicket()
        let evolutionRevision = store.evolution.revision
        let reply = store.reply
        let status = store.status
        fixture.reasoner.resolve()
        try await waitUntil { fixture.reasoner.finished == 1 }
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(store.companionGraphSnapshot(at: fixture.now), stopped)
        XCTAssertEqual(store.compareResults[.qwen], lane)
        XCTAssertEqual(store.reply, reply)
        XCTAssertEqual(store.status, status)
        XCTAssertEqual(store.contextTicket(), context)
        XCTAssertEqual(store.evolution.revision, evolutionRevision)
        XCTAssertEqual(try fixture.files(), files)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(fixture.reasoner.requests.count, 1)
        XCTAssertTrue(fixture.selector.requests.isEmpty)
        XCTAssertTrue(fixture.codex.requests.isEmpty)
    }

    @MainActor
    func testRemovingSharedSourceAndWithdrawingLessonRemovesTheirLiveGraphContent() async throws {
        let lessonText = "Private graph fixture guidance: amber notebook."
        let lesson = KeptLesson(topic: "planning", text: lessonText, createdAt: GraphStoreFixture.instant)
        let fixture = try GraphStoreFixture(lessons: [lesson])
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.share(text: "Private fixture copy for the planning review.", name: "private-graph-copy.txt")
        store.prompt = "Help with planning."
        try await connect(store)
        store.submit()
        try await waitUntil { !store.isWorking }
        let current = store.companionGraphSnapshot(at: fixture.now)
        XCTAssertTrue(current.nodes.contains { $0.kind == .source })
        XCTAssertTrue(current.nodes.contains { $0.kind == .lesson })
        let beforeStopFiles = try fixture.files()
        let calls = fixture.calls

        store.stopSharing()
        let sourceRemoved = store.companionGraphSnapshot(at: fixture.now)
        XCTAssertFalse(sourceRemoved.nodes.contains { $0.kind == .source })
        XCTAssertFalse(graphText(sourceRemoved).contains("private-graph-copy.txt"))
        XCTAssertTrue(store.compareResults.isEmpty)
        XCTAssertEqual(store.keptLessons, [lesson], "Stopping document sharing does not withdraw an independently kept lesson")
        XCTAssertEqual(try fixture.files(), beforeStopFiles)

        XCTAssertTrue(store.withdrawLesson(id: lesson.id, expectedRevision: store.lessonRevision))
        let afterWithdrawalFiles = try fixture.files()
        let afterWithdrawalRevision = store.lessonRevision
        let withdrawn = store.companionGraphSnapshot(at: fixture.now)
        XCTAssertFalse(withdrawn.nodes.contains { $0.kind == .lesson })
        XCTAssertFalse(graphText(withdrawn).contains(lessonText))
        XCTAssertFalse(graphText(withdrawn).contains("private-graph-copy.txt"))
        XCTAssertTrue(store.keptLessons.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profile.path),
                       "Withdrawing the final retained value removes the empty preference file")
        XCTAssertEqual(store.companionGraphSnapshot(at: fixture.now), withdrawn)
        XCTAssertEqual(store.lessonRevision, afterWithdrawalRevision)
        XCTAssertEqual(try fixture.files(), afterWithdrawalFiles, "Reading the withdrawn graph adds no second persistence operation")
        XCTAssertEqual(fixture.calls, calls)
    }

    @MainActor
    func testCompareGraphKeepsProviderLanesDistinctDuringLocalLessonWithdrawal() async throws {
        let privateText = "Private local planning preference: blue index cards."
        let lesson = KeptLesson(topic: "planning", text: privateText, createdAt: GraphStoreFixture.instant)
        let fixture = try GraphStoreFixture(lessons: [lesson])
        defer { fixture.cleanUp() }
        let store = fixture.store
        fixture.reasoner.hold = true
        fixture.codex.hold = true
        store.setAssistantRoute(.compare)
        store.prompt = "Help with planning."
        try await connect(store)
        store.submit()
        try await waitUntil { fixture.reasoner.isPending && fixture.codex.isPending }
        let local = try XCTUnwrap(store.compareResults[.qwen]?.receipt)
        let external = try XCTUnwrap(store.compareResults[.codex]?.receipt)
        XCTAssertEqual(local.requestID, external.requestID, "Compare deliberately shares its request identifier across provider lanes")
        let pending = store.companionGraphSnapshot(at: fixture.now)
        let requests = pending.nodes.filter { $0.kind == .request }
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(Set(requests.map(\.id)).count, 2, "The graph must namespace shared request IDs by provider")
        XCTAssertEqual(Set(requests.flatMap { node in node.details.filter { $0.label == "Provider" }.map(\.value) }),
                       Set([AssistantProvider.qwen.name, AssistantProvider.codex.name]))
        let externalInput = try XCTUnwrap(fixture.codex.requests.first)
        XCTAssertTrue(externalInput.localLessons.isEmpty)
        XCTAssertFalse(externalInput.input.contains(privateText))

        XCTAssertTrue(store.withdrawLesson(id: lesson.id, expectedRevision: store.lessonRevision))
        XCTAssertNil(store.compareResults[.qwen])
        XCTAssertEqual(store.compareResults[.codex]?.receipt, external)
        let localRemoved = store.companionGraphSnapshot(at: fixture.now)
        XCTAssertEqual(localRemoved.nodes.filter { $0.kind == .request }.count, 1)
        XCTAssertFalse(graphText(localRemoved).contains(privateText))
        let files = try fixture.files()
        fixture.reasoner.resolve()
        try await waitUntil { fixture.reasoner.finished == 1 }
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(store.companionGraphSnapshot(at: fixture.now), localRemoved,
                       "The revoked local completion cannot reinsert its request or lesson into the graph")
        XCTAssertEqual(store.compareResults[.codex]?.receipt, external)
        XCTAssertEqual(try fixture.files(), files, "The revoked local completion cannot rewrite retained state")

        fixture.codex.resolve()
        try await waitUntil { !store.isWorking }
        XCTAssertEqual(store.compareResults[.codex]?.state, .complete)
        XCTAssertNil(store.compareResults[.qwen])
        let completed = store.companionGraphSnapshot(at: fixture.now)
        XCTAssertEqual(completed.nodes.filter { $0.kind == .request }.count, 1)
        XCTAssertTrue(completed.nodes.contains { $0.kind == .answer })
        XCTAssertFalse(graphText(completed).contains(privateText))
        let completedFiles = try fixture.files()
        let journalSuffix = "/preferences.steward.json"
        XCTAssertEqual(completedFiles.filter { !$0.key.hasSuffix(journalSuffix) },
                       files.filter { !$0.key.hasSuffix(journalSuffix) },
                       "Only the surviving provider's usage journal may change when its answer completes")
        let journalURL = fixture.profile.deletingPathExtension().appendingPathExtension("steward.json")
        let retainedUsage = TokenStewardStore(url: journalURL)
        let task = try XCTUnwrap(retainedUsage.tasks.first)
        XCTAssertNil(retainedUsage.loadError)
        XCTAssertEqual(retainedUsage.tasks.count, 1)
        XCTAssertEqual(task.lanes.first { $0.provider == AssistantProvider.qwen.name }?.state, "cancelled")
        XCTAssertEqual(task.lanes.first { $0.provider == AssistantProvider.codex.name }?.state, "complete")
        XCTAssertFalse(String(decoding: try Data(contentsOf: journalURL), as: UTF8.self).contains(privateText))
        XCTAssertEqual(store.companionGraphSnapshot(at: fixture.now), completed)
        XCTAssertEqual(try fixture.files(), completedFiles, "Reading the completed graph adds no persistence")
        XCTAssertEqual(fixture.reasoner.requests.count, 1)
        XCTAssertEqual(fixture.codex.requests.count, 1)
        XCTAssertTrue(fixture.selector.requests.isEmpty)
    }

    private func graphText(_ snapshot: CompanionGraphSnapshot) -> String {
        snapshot.nodes.map { node in
            ([node.title, node.subtitle, node.status] + node.details.map(\.value)).joined(separator: "\n")
        }.joined(separator: "\n")
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
        XCTFail("The in-process graph fixture did not finish within its bounded wait")
        throw GraphFixtureFailure.waitTimedOut
    }
}

private enum GraphFixtureFailure: Error { case waitTimedOut }

@MainActor
private final class GraphStoreFixture {
    static let instant = Date(timeIntervalSince1970: 1_500_000_000)
    let now = GraphStoreFixture.instant
    let reasoner = GraphRoleClient()
    let selector = GraphRoleClient()
    let codex = GraphCodexClient()
    let store: CompanionStore
    let directory: URL
    let profile: URL

    init(lessons: [KeptLesson] = []) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-graph-integration-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        profile = directory.appendingPathComponent("preferences.json")
        try NativePreferenceDocument(lessons: lessons).encoded().write(to: profile)
        let local = HamptonReasonsAssistant(reasoner: reasoner, contextSelector: selector)
        let external = codex
        let instant = now
        store = CompanionStore(preferenceURL: profile, assistant: local,
            assistantFactory: { provider, _ in
                if provider == .qwen { return local }
                return external
            },
            wallClock: { instant }, allowsPlay: false)
    }

    var calls: [Int] {
        [reasoner.requests.count, selector.requests.count, codex.requests.count,
         reasoner.connectCount, selector.connectCount, codex.connectCount]
    }

    /// Only this fixture's disposable directory is inspected, never a user's profile.
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
        reasoner.drain(); selector.drain(); codex.drain()
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class GraphRoleClient: LocalRoleClient {
    var hold = false
    private(set) var requests: [LocalRoleRequest] = []
    private(set) var connectCount = 0
    private(set) var finished = 0
    private var pending: CheckedContinuation<Void, Error>?
    var isPending: Bool { pending != nil }
    func connect() async throws { connectCount += 1 }
    func disconnect() {}
    func shutdown() async {}

    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
        requests.append(request)
        defer { finished += 1 }
        if hold { try await withCheckedThrowingContinuation { pending = $0 } }
        let payload: JSONValue
        switch request.role {
        case .reasoning:
            let ids: (String) -> [JSONValue] = { key in
                let identifiers = request.input[key]?.array?.compactMap { $0["id"]?.string } ?? []
                return identifiers.map(JSONValue.string)
            }
            payload = .object(["requestID": .string(request.id), "schema": .string("archi-reason-proposal/v1"),
                "kind": .string("ANSWER"), "answer": .string("Controlled graph fixture answer."), "uncertainty": .string(""),
                "sourceIDs": .array(ids("sources")), "memoryIDs": .array(ids("memories"))])
        case .memorySelection:
            payload = .object(["requestID": .string(request.id), "schema": .string("archi-session-selection/v1"), "candidateIDs": .array([])])
        case .memoryReminder:
            payload = .object(["requestID": .string(request.id), "schema": .string("archi-session-reminder/v1"),
                "decision": .string("NONE"), "memoryIDs": .array([])])
        }
        return LocalRoleResult(requestID: request.id, role: request.role,
            text: String(decoding: try JSONEncoder().encode(payload), as: UTF8.self),
            model: QwenModelMetadata(name: "graph-fixture", family: "fixture", parameterSize: "fixture",
                quantization: "fixture", digest: String(repeating: "d", count: 64)),
            elapsedMilliseconds: 7, metrics: LocalInferenceMetrics(inputTokens: 20, outputTokens: 5, totalNanoseconds: 7_000_000))
    }

    /// Intentionally completes after cancellation to exercise the real ownership fences.
    func resolve() { let continuation = pending; pending = nil; continuation?.resume() }
    func drain() { let continuation = pending; pending = nil; continuation?.resume(throwing: QwenFailure.stopped) }
}

@MainActor
private final class GraphCodexClient: AssistantClient {
    var hold = false
    private(set) var requests: [AssistantRequest] = []
    private(set) var connectCount = 0
    private var pending: CheckedContinuation<Void, Error>?
    var isPending: Bool { pending != nil }
    func connect() async throws { connectCount += 1 }
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        requests.append(request)
        if hold { try await withCheckedThrowingContinuation { pending = $0 } }
        onEvent(.text("Controlled external graph answer."))
    }
    func resolve() { let continuation = pending; pending = nil; continuation?.resume() }
    func drain() { let continuation = pending; pending = nil; continuation?.resume(throwing: AssistantFailure.stopped) }
}
