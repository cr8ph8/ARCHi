import Foundation
import XCTest
@testable import ARCHiDesktop

final class ARCWorkspaceRoutingTests: XCTestCase {
    @MainActor
    func testExactReceiptUsageAndGraphNavigationLeavesOwnersUnchanged() throws {
        let fixture = try ARCWorkspaceRoutingFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        let first = store.arcCapabilities.runSyntheticDemonstration()
        store.recordARCEvaluation(first)
        let evidenceID = try XCTUnwrap(first.evidenceID)
        var other = try XCTUnwrap(JSONSerialization.jsonObject(with: ARCCapabilitiesEvaluator.syntheticBundle) as? [String: Any])
        other["evaluations"] = []
        store.recordARCEvaluation(store.arcCapabilities.evaluate(data: try JSONSerialization.data(withJSONObject: other)))
        XCTAssertNotEqual(store.arcCapabilities.records.first?.id, evidenceID)
        let files = try fixture.files()
        let preferences = store.preferences
        let history = store.evolution.history
        let revision = store.evolution.revision
        let position = store.position

        XCTAssertTrue(store.openARCUsage(taskID: first.taskID))
        XCTAssertEqual(store.section, .steward)
        XCTAssertEqual(store.selectedStewardTaskID, first.taskID)
        XCTAssertNil(store.workspaceRoutingNotice)
        XCTAssertTrue(store.openARCGraph(evidenceID: evidenceID))
        XCTAssertEqual(store.section, .nodeLab)
        let graph = store.companionGraphSnapshot()
        let node = try XCTUnwrap(graph.nodes.first { $0.id == store.selectedGraphNodeID })
        XCTAssertEqual(node.kind, .evaluation)
        XCTAssertEqual(node.target, .arcEvidence(proposalHash: evidenceID))
        let accounting = try XCTUnwrap(graph.nodes.first { $0.target == .stewardTask(taskID: first.taskID) })
        store.openGraphTarget(try XCTUnwrap(accounting.target))
        XCTAssertEqual(store.section, .steward)
        XCTAssertEqual(store.selectedStewardTaskID, first.taskID)
        XCTAssertTrue(store.canOpenARCEvidenceForUsage(taskID: first.taskID))
        XCTAssertTrue(store.openARCEvidenceForUsage(taskID: first.taskID))
        XCTAssertEqual(store.section, .capabilities)
        XCTAssertEqual(store.arcCapabilities.selectedRecordID, evidenceID)

        XCTAssertEqual(try fixture.files(), files)
        XCTAssertEqual(store.preferences, preferences)
        XCTAssertEqual(store.evolution.history, history)
        XCTAssertEqual(store.evolution.revision, revision)
        XCTAssertEqual(store.position, position)
        fixture.assertNoInference()
        let reopened = fixture.reopen()
        XCTAssertNil(reopened.selectedStewardTaskID)
        XCTAssertNil(reopened.selectedGraphNodeID)
        XCTAssertNil(reopened.workspaceRoutingNotice)
        XCTAssertNil(reopened.arcCapabilities.selectedRecordID)
    }

    @MainActor
    func testSharedJournalHashMatchCannotOpenAnotherProfilesReceipt() throws {
        let fixture = try ARCWorkspaceRoutingFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        let event = store.arcCapabilities.runSyntheticDemonstration()
        store.recordARCEvaluation(event)
        let unrelatedID = UUID().uuidString
        try store.tokenSteward.recordEvaluation(taskID: unrelatedID, evidenceID: event.evidenceID, passed: event.passed,
            startedAt: event.startedAt, finishedAt: event.finishedAt, sourceStatus: event.sourceStatus, error: nil)
        XCTAssertTrue(store.openARCEvidenceForUsage(taskID: event.taskID))
        let files = try fixture.files()
        XCTAssertFalse(store.canOpenARCEvidenceForUsage(taskID: unrelatedID))
        XCTAssertFalse(store.openARCEvidenceForUsage(taskID: unrelatedID))
        XCTAssertNil(store.arcCapabilities.selectedRecordID)
        XCTAssertNotNil(store.arcCapabilities.selectionNotice)
        XCTAssertNotNil(store.workspaceRoutingNotice)
        XCTAssertEqual(store.section, .capabilities)
        XCTAssertEqual(try fixture.files(), files)
        fixture.assertNoInference()
    }

    @MainActor
    func testOriginalTaskStillRequiresMatchingCheckedEvidenceAndOutcome() throws {
        for wrongEvidence in [false, true] {
            let fixture = try ARCWorkspaceRoutingFixture()
            defer { fixture.cleanUp() }
            let store = fixture.store
            let event = store.arcCapabilities.runSyntheticDemonstration()
            let passed = try XCTUnwrap(event.passed)
            try store.tokenSteward.recordEvaluation(taskID: event.taskID,
                evidenceID: wrongEvidence ? "sha256:" + String(repeating: "f", count: 64) : event.evidenceID,
                passed: wrongEvidence ? passed : !passed, startedAt: event.startedAt, finishedAt: event.finishedAt,
                sourceStatus: event.sourceStatus, error: nil)
            XCTAssertFalse(store.canOpenARCEvidenceForUsage(taskID: event.taskID))
            XCTAssertFalse(store.openARCEvidenceForUsage(taskID: event.taskID))
            XCTAssertNil(store.arcCapabilities.selectedRecordID)
        }
    }

    @MainActor
    func testMissingTargetsClearOldFocusWithoutSelectingReplacement() throws {
        let fixture = try ARCWorkspaceRoutingFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        let event = store.arcCapabilities.runSyntheticDemonstration()
        store.recordARCEvaluation(event)
        let evidenceID = try XCTUnwrap(event.evidenceID)
        XCTAssertTrue(store.openARCUsage(taskID: event.taskID))
        XCTAssertTrue(store.openARCGraph(evidenceID: evidenceID))
        XCTAssertTrue(store.openARCEvidenceForUsage(taskID: event.taskID))
        let files = try fixture.files()
        let absentTask = UUID().uuidString
        XCTAssertFalse(store.openARCUsage(taskID: absentTask))
        XCTAssertEqual(store.section, .steward)
        XCTAssertNil(store.selectedStewardTaskID)
        XCTAssertNotNil(store.workspaceRoutingNotice)
        XCTAssertFalse(store.openARCGraph(evidenceID: "sha256:" + String(repeating: "0", count: 64)))
        XCTAssertEqual(store.section, .nodeLab)
        XCTAssertNil(store.selectedGraphNodeID)
        XCTAssertNotNil(store.workspaceRoutingNotice)
        XCTAssertFalse(store.openARCEvidenceForUsage(taskID: absentTask))
        XCTAssertNil(store.arcCapabilities.selectedRecordID)
        XCTAssertEqual(try fixture.files(), files)
        store.open(.home)
        XCTAssertNil(store.workspaceRoutingNotice, "A routing warning must not follow unrelated navigation.")
        fixture.assertNoInference()
    }

    @MainActor
    func testUnavailableJournalDoesNotOpenStaleAccountingOrReverseLink() throws {
        let fixture = try ARCWorkspaceRoutingFixture()
        defer { fixture.cleanUp() }
        let event = fixture.store.arcCapabilities.runSyntheticDemonstration()
        fixture.store.recordARCEvaluation(event)
        try Data("preserve unavailable journal".utf8).write(to: fixture.journal)
        let reopened = fixture.reopen()
        let files = try fixture.files()
        XCTAssertNotNil(reopened.tokenSteward.loadError)
        XCTAssertFalse(reopened.openARCUsage(taskID: event.taskID))
        XCTAssertNil(reopened.selectedStewardTaskID)
        XCTAssertFalse(reopened.canOpenARCEvidenceForUsage(taskID: event.taskID))
        XCTAssertTrue(reopened.openARCGraph(evidenceID: try XCTUnwrap(event.evidenceID)),
                      "Independent retained ARC evidence remains available.")
        XCTAssertEqual(try fixture.files(), files)
        fixture.assertNoInference()
    }

    @MainActor
    func testCurrentReplayUsageKeepsItsOwnTaskAndRequiresLiveProfileProvenance() async throws {
        let fixture = try ARCWorkspaceRoutingFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        try store.arcCapabilities.loadSolverSample()
        store.arcCapabilities.startSolving(onEvaluation: store.recordARCEvaluation)
        try await finishRun(store.arcCapabilities)
        let record = try XCTUnwrap(store.arcCapabilities.records.first)
        let originalTaskID = record.taskID
        XCTAssertEqual(store.arcCapabilities.solverReview?.taskID, originalTaskID)
        store.arcCapabilities.replaySolver(recordID: record.id, onEvaluation: store.recordARCEvaluation)
        try await finishRun(store.arcCapabilities)
        let current = try XCTUnwrap(store.arcCapabilities.solverReview)
        XCTAssertNil(current.error)
        XCTAssertEqual(current.replayMatched, true)
        XCTAssertNotEqual(current.taskID, originalTaskID)
        XCTAssertEqual(store.arcCapabilities.records.count, 1)
        XCTAssertEqual(store.tokenSteward.tasks.count, 2)
        let files = try fixture.files()
        XCTAssertTrue(store.openARCUsage(taskID: current.taskID))
        XCTAssertEqual(store.selectedStewardTaskID, current.taskID)
        XCTAssertTrue(store.canOpenARCEvidenceForUsage(taskID: current.taskID))
        XCTAssertTrue(store.openARCEvidenceForUsage(taskID: current.taskID))
        XCTAssertEqual(store.arcCapabilities.selectedRecordID, record.id)
        XCTAssertTrue(store.canOpenARCEvidenceForUsage(taskID: originalTaskID))
        let graph = store.companionGraphSnapshot()
        XCTAssertTrue(graph.nodes.contains { $0.target == .stewardTask(taskID: originalTaskID) })
        XCTAssertFalse(graph.nodes.contains { $0.target == .stewardTask(taskID: current.taskID) })
        XCTAssertEqual(try fixture.files(), files)

        // Without this run's live provenance, a shared-journal hash cannot establish profile ownership.
        try store.arcCapabilities.loadSolverSample()
        XCTAssertFalse(store.canOpenARCEvidenceForUsage(taskID: current.taskID))
        XCTAssertTrue(store.canOpenARCEvidenceForUsage(taskID: originalTaskID))
        let reopened = fixture.reopen()
        XCTAssertFalse(reopened.canOpenARCEvidenceForUsage(taskID: current.taskID))
        XCTAssertTrue(reopened.canOpenARCEvidenceForUsage(taskID: originalTaskID))
        fixture.assertNoInference()
        await store.shutdownAssistant()
    }

    func testExactOlderTaskIsVisibleBeyondRecentTwentyWithoutDuplicatesOrFallback() throws {
        let tasks = (0..<25).map { index in
            TokenStewardTask(id: "task-\(index)", route: "arc-evaluation",
                startedAt: Date(timeIntervalSince1970: Double(25 - index)), lanes: [])
        }
        let selected = TokenStewardPresentation.visibleTasks(tasks, selectedTaskID: tasks[24].id)
        XCTAssertEqual(selected.count, 21)
        XCTAssertEqual(selected.first?.id, tasks[24].id)
        XCTAssertEqual(Array(selected.dropFirst()), Array(tasks.prefix(20)))
        XCTAssertEqual(Set(selected.map(\.id)).count, selected.count)
        XCTAssertEqual(TokenStewardPresentation.visibleTasks(tasks, selectedTaskID: tasks[3].id), Array(tasks.prefix(20)))
        XCTAssertEqual(TokenStewardPresentation.visibleTasks(tasks, selectedTaskID: "missing"), Array(tasks.prefix(20)))
        XCTAssertEqual(TokenStewardPresentation.visibleTasks(tasks, selectedTaskID: nil), Array(tasks.prefix(20)))
        XCTAssertEqual(tasks.count, 25)
    }

    @MainActor
    private func finishRun(_ store: ARCCapabilitiesStore) async throws {
        for _ in 0..<500 where store.isSolving { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(store.isSolving)
        XCTAssertNil(store.solverReview?.error)
    }
}

@MainActor
private final class ARCWorkspaceRoutingFixture {
    let directory: URL
    let profile: URL
    let store: CompanionStore
    let client = ARCWorkspaceRoutingNoDispatchClient()
    var journal: URL { profile.deletingPathExtension().appendingPathExtension("steward.json") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-arc-routing-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        profile = directory.appendingPathComponent("preferences.json")
        try NativePreferenceDocument().encoded().write(to: profile)
        let client = client
        store = CompanionStore(preferenceURL: profile, assistant: client, assistantFactory: { _, _ in client }, allowsPlay: false)
    }

    func reopen() -> CompanionStore {
        let client = client
        return CompanionStore(preferenceURL: profile, assistant: client, assistantFactory: { _, _ in client }, allowsPlay: false)
    }

    func files() throws -> [String: Data] {
        Dictionary(uniqueKeysWithValues: try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    }

    func assertNoInference() {
        XCTAssertEqual(client.calls, 0)
        XCTAssertTrue(store.tokenSteward.observations.isEmpty)
        XCTAssertTrue(store.tokenSteward.reservations.isEmpty)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: directory) }
}

@MainActor
private final class ARCWorkspaceRoutingNoDispatchClient: AssistantClient {
    var calls = 0
    func connect() async throws { calls += 1; XCTFail("ARC navigation cannot connect a model") }
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; XCTFail("ARC navigation cannot invoke inference")
    }
}
