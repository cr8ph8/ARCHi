import XCTest
@testable import ARCHiDesktop

final class ARCSolverAccountingTests: XCTestCase {
    @MainActor
    func testSolverAccountingReopensWithoutInventedInferenceAndCancellationCannotPass() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("usage.json")
        let journal = TokenStewardStore(url: url)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for _ in 0..<2 {
            try journal.recordEvaluation(taskID: "solve", evidenceID: "sha256:fixture", passed: true,
                startedAt: start, finishedAt: start.addingTimeInterval(2), sourceStatus: "synthetic-fixture",
                error: nil, localSolver: true)
        }
        try journal.recordEvaluation(taskID: "stop", evidenceID: nil, passed: nil, startedAt: start,
            finishedAt: start.addingTimeInterval(1), sourceStatus: nil, error: "Stopped", localSolver: true, cancelled: true)
        XCTAssertThrowsError(try journal.recordEvaluation(taskID: "forged", evidenceID: "sha256:fixture", passed: true,
            startedAt: start, finishedAt: start, sourceStatus: nil, error: nil, localSolver: true, cancelled: true))
        let reopened = TokenStewardStore(url: url)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.tasks.count, 2)
        XCTAssertEqual(reopened.tasks.first { $0.id == "solve" }?.lanes.first?.elapsedMilliseconds, 2_000)
        XCTAssertEqual(reopened.tasks.first { $0.id == "stop" }?.lanes.first?.state, "cancelled")
        XCTAssertEqual(reopened.summary.evaluationTaskCount, 2)
        XCTAssertEqual(reopened.summary.syntheticCheckedTaskCount, 1)
        XCTAssertEqual(reopened.summary.localAttemptCount, 0)
        XCTAssertEqual(reopened.summary.subscriptionRequestCount, 0)
        XCTAssertEqual(reopened.summary.checkedSuccessfulTaskCount, 0)
        XCTAssertTrue(reopened.observations.isEmpty)
        XCTAssertTrue(reopened.reservations.isEmpty)
    }

    @MainActor
    func testNativeSolveJoinsGraphAndUsageWithoutChangingCompanion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let profile = directory.appendingPathComponent("preferences.json")
        try NativePreferenceDocument().encoded().write(to: profile)
        let client = SolverNoDispatchClient()
        let store = CompanionStore(preferenceURL: profile, assistant: client, assistantFactory: { _, _ in client }, allowsPlay: false)
        let preferences = store.preferences, revision = store.evolution.revision
        try store.arcCapabilities.loadSolverSample()
        store.arcCapabilities.startSolving(onEvaluation: store.recordARCEvaluation)
        for _ in 0..<500 where store.arcCapabilities.isSolving { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(store.arcCapabilities.isSolving)
        let record = try XCTUnwrap(store.arcCapabilities.records.first)
        XCTAssertTrue(record.summary.allExact)
        XCTAssertEqual(store.tokenSteward.tasks.first?.lanes.first?.provider, "ARC local symbolic solver + checker")
        let graph = store.companionGraphSnapshot(at: Date())
        XCTAssertTrue(graph.nodes.flatMap(\.details).contains { $0.value.contains("Recorded local symbolic search: \(ARCSymbolicSolver.catalogProgramCount)") })
        XCTAssertTrue(graph.nodes.flatMap(\.details).contains { $0.value.contains("CPU and energy cost is unmeasured") })
        XCTAssertTrue(graph.edges.contains { $0.label == "accounted by" })
        XCTAssertFalse(graph.nodes.contains { $0.kind == .invocation })
        XCTAssertEqual(store.preferences, preferences)
        XCTAssertEqual(store.evolution.revision, revision)
        XCTAssertEqual(client.calls, 0)
        XCTAssertFalse(record.summary.permitsStateChanges)
        await store.shutdownAssistant()
    }

    @MainActor
    func testShutdownRetiresSolverBeforeItCanPublish() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = SolverNoDispatchClient()
        let store = CompanionStore(preferenceURL: directory.appendingPathComponent("profile.json"),
            assistant: client, assistantFactory: { _, _ in client }, allowsPlay: false)
        try store.arcCapabilities.loadSolverSample()
        store.arcCapabilities.startSolving(onEvaluation: store.recordARCEvaluation)
        XCTAssertTrue(store.arcCapabilities.isSolving)
        await store.shutdownAssistant()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(store.arcCapabilities.isSolving)
        XCTAssertTrue(store.arcCapabilities.records.isEmpty)
        XCTAssertEqual(store.tokenSteward.tasks.count, 1)
        XCTAssertEqual(store.tokenSteward.tasks.first?.lanes.first?.state, "cancelled")
        XCTAssertTrue(store.tokenSteward.tasks.first?.outcomes.isEmpty == true)
    }
}

@MainActor private final class SolverNoDispatchClient: AssistantClient {
    var calls = 0
    func connect() async throws { calls += 1; XCTFail("ARC solving cannot connect a model") }
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; XCTFail("ARC solving cannot invoke inference")
    }
}
