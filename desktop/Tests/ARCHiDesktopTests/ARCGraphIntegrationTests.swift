import XCTest
@testable import ARCHiDesktop

final class ARCGraphIntegrationTests: XCTestCase {
    @MainActor
    func testFailedImportKeepsEarlierReceiptAndAccountingStatusUnchanged() throws {
        let fixture = try ARCGraphFixture()
        defer { fixture.cleanUp() }
        let event = fixture.store.arcCapabilities.runSyntheticDemonstration()
        fixture.store.recordARCEvaluation(event)
        let original = fixture.store.companionGraphSnapshot(at: fixture.now)
        let bytes = try Data(contentsOf: fixture.archive)
        let failed = fixture.store.arcCapabilities.evaluate(data: Data("malformed input".utf8))
        fixture.store.recordARCEvaluation(failed)
        XCTAssertNotNil(failed.error)
        let graph = fixture.store.companionGraphSnapshot(at: fixture.now)
        for node in original.nodes { XCTAssertEqual(graph.nodes.first { $0.id == node.id }, node) }
        XCTAssertTrue(graph.nodes.contains { $0.id == "arc-shelf-error" && $0.status == "Review required" })
        XCTAssertEqual(try Data(contentsOf: fixture.archive), bytes)
        XCTAssertEqual(fixture.store.tokenSteward.tasks.count, 2, "Failed operation stays separately accounted")
        fixture.assertNoInference()
    }

    @MainActor
    func testRetainedReceiptNavigationIsReadOnlyAndReopensFromOwners() throws {
        let fixture = try ARCGraphFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        let event = store.arcCapabilities.runSyntheticDemonstration()
        store.recordARCEvaluation(event)
        XCTAssertNil(event.error)
        let record = try XCTUnwrap(store.arcCapabilities.records.first)
        let preferences = store.preferences, position = store.position
        let evolution = store.evolution.revision
        let history = store.evolution.history
        let files = try fixture.files()
        let graph = store.companionGraphSnapshot(at: fixture.now)
        let result = try XCTUnwrap(graph.nodes.first { $0.kind == .evaluation })
        XCTAssertEqual(result.target, .arcEvidence(proposalHash: record.id))
        XCTAssertTrue(result.details.contains(.init(label: "Bundle hash", value: record.bundleHash)))
        XCTAssertTrue(result.details.contains { $0.value.contains("Exact 1 · Incorrect 1") })
        XCTAssertEqual(graph.edges.filter { $0.label == "rescored from" }.count, 1)
        XCTAssertEqual(graph.edges.filter { $0.label == "accounted by" }.count, 1)
        XCTAssertEqual(graph.nodes.filter { $0.kind == .invocation }.count, 0)

        store.openGraphTarget(try XCTUnwrap(result.target))
        XCTAssertEqual(store.section, .capabilities)
        XCTAssertEqual(store.arcCapabilities.selectedRecordID, record.id)
        for _ in 0..<10 { XCTAssertEqual(store.companionGraphSnapshot(at: fixture.now), graph) }
        XCTAssertEqual(try fixture.files(), files)
        XCTAssertEqual(store.preferences, preferences)
        XCTAssertEqual(store.position, position)
        XCTAssertEqual(store.evolution.revision, evolution)
        XCTAssertEqual(store.evolution.history, history)
        let reopened = fixture.reopen()
        XCTAssertEqual(reopened.companionGraphSnapshot(at: fixture.now), graph)
        XCTAssertNil(reopened.arcCapabilities.selectedRecordID, "Selection is not evidence or saved state")
        fixture.assertNoInference()
    }

    @MainActor
    func testDuplicatesKeepOneEvidenceNodeAndOriginalAccountingLink() throws {
        let fixture = try ARCGraphFixture()
        defer { fixture.cleanUp() }
        let first = fixture.store.arcCapabilities.runSyntheticDemonstration()
        fixture.store.recordARCEvaluation(first)
        let before = fixture.store.companionGraphSnapshot(at: fixture.now)
        let repeated = fixture.store.arcCapabilities.runSyntheticDemonstration()
        fixture.store.recordARCEvaluation(repeated)
        XCTAssertNotEqual(first.taskID, repeated.taskID)
        XCTAssertEqual(fixture.store.tokenSteward.tasks.count, 2)
        XCTAssertEqual(fixture.store.companionGraphSnapshot(at: fixture.now), before)
        XCTAssertEqual(before.nodes.filter { $0.kind == .accounting }.count, 1)
        fixture.assertNoInference()
    }

    @MainActor
    func testUnrelatedProfilesCannotJoinByMatchingProposalHash() throws {
        let fixture = try ARCGraphFixture()
        defer { fixture.cleanUp() }
        let event = fixture.store.arcCapabilities.runSyntheticDemonstration()
        let journal = TokenStewardStore()
        try journal.recordEvaluation(taskID: UUID().uuidString, evidenceID: event.evidenceID, passed: event.passed,
            startedAt: event.startedAt, finishedAt: event.finishedAt, sourceStatus: event.sourceStatus, error: nil)
        let graph = CompanionGraph.build(receipts: [], lessons: [], source: nil, now: fixture.now,
            arcRecords: fixture.store.arcCapabilities.records, accountingTasks: journal.tasks)
        XCTAssertTrue(graph.nodes.contains { $0.status == "Accounting unavailable" })
        XCTAssertFalse(graph.edges.contains { $0.label == "accounted by" })
        XCTAssertFalse(graph.nodes.flatMap(\.details).contains { $0.value == journal.tasks[0].id })
    }

    @MainActor
    func testCorruptArchiveRemainsVisibleAsErrorWithoutReplacementOrWrites() throws {
        let fixture = try ARCGraphFixture()
        defer { fixture.cleanUp() }
        let event = fixture.store.arcCapabilities.runSyntheticDemonstration()
        fixture.store.recordARCEvaluation(event)
        let id = try XCTUnwrap(event.evidenceID)
        let corrupt = Data("preserve corrupt graph fixture".utf8)
        try corrupt.write(to: fixture.archive)
        let reopened = fixture.reopen()
        let before = try fixture.files()
        let graph = reopened.companionGraphSnapshot(at: fixture.now)
        XCTAssertEqual(graph.nodes.filter { $0.kind == .evaluation }.count, 1)
        XCTAssertEqual(graph.nodes.first { $0.kind == .evaluation }?.status, "Review required")
        reopened.openGraphTarget(.arcEvidence(proposalHash: id))
        XCTAssertNil(reopened.arcCapabilities.selectedRecordID)
        XCTAssertNotNil(reopened.arcCapabilities.selectionNotice)
        XCTAssertEqual(try fixture.files(), before)
        XCTAssertEqual(try Data(contentsOf: fixture.archive), corrupt)
        fixture.assertNoInference()
    }

    @MainActor
    func testJournalFailureDoesNotBecomeMeasuredZeroOrHideARCResult() throws {
        let fixture = try ARCGraphFixture()
        defer { fixture.cleanUp() }
        let event = fixture.store.arcCapabilities.runSyntheticDemonstration()
        fixture.store.recordARCEvaluation(event)
        try Data("unreadable usage journal".utf8).write(to: fixture.journal)
        let reopened = fixture.reopen()
        let graph = reopened.companionGraphSnapshot(at: fixture.now)
        XCTAssertEqual(graph.nodes.filter { $0.kind == .evaluation }.count, 1)
        let accounting = try XCTUnwrap(graph.nodes.first { $0.kind == .accounting })
        XCTAssertEqual(accounting.status, "Accounting unavailable")
        XCTAssertTrue(accounting.details.contains(.init(label: "Elapsed", value: "Unavailable")))
        XCTAssertFalse(graph.edges.contains { $0.label == "accounted by" })
    }

    @MainActor
    func testMissingInvalidAndUnscoredAreProjectedWithoutPromotingEvidence() throws {
        let fixture = try ARCGraphFixture()
        defer { fixture.cleanUp() }
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: ARCCapabilitiesEvaluator.syntheticBundle) as? [String: Any])
        root["evaluations"] = []
        _ = fixture.store.arcCapabilities.evaluate(data: try JSONSerialization.data(withJSONObject: root))
        var graph = fixture.store.companionGraphSnapshot(at: fixture.now)
        XCTAssertTrue(graph.nodes.flatMap(\.details).contains { $0.value.contains("Missing 2") })
        XCTAssertTrue(graph.nodes.flatMap(\.details).contains { $0.value.contains("Scoring incomplete") })

        root = try XCTUnwrap(JSONSerialization.jsonObject(with: ARCCapabilitiesEvaluator.syntheticBundle) as? [String: Any])
        var evaluations = root["evaluations"] as! [[String: Any]]
        var task = evaluations[0]["task"] as! [String: Any]
        var tests = task["test"] as! [[String: Any]]
        tests[0].removeValue(forKey: "output")
        task["test"] = tests
        evaluations[0]["task"] = task
        evaluations[0]["predictions"] = [[[2, 0, 2]], NSNull()]
        root["evaluations"] = evaluations
        var manifest = root["manifest"] as! [String: Any]
        var entries = manifest["tasks"] as! [[String: Any]]
        entries[0]["taskHash"] = try ARCCapabilitiesEvaluator.digest(task)
        manifest["tasks"] = entries
        root["manifest"] = manifest
        _ = fixture.store.arcCapabilities.evaluate(data: try JSONSerialization.data(withJSONObject: root))
        graph = fixture.store.companionGraphSnapshot(at: fixture.now)
        XCTAssertTrue(graph.nodes.flatMap(\.details).contains { $0.value.contains("Invalid 1 · Unscored 1") })
        XCTAssertTrue(graph.nodes.filter { $0.kind == .evaluation }.allSatisfy { $0.status == "Proposed · Not certified" })
    }

    @MainActor
    func testBoundedProjectionDeduplicatesEvidenceWithNoDanglingEdges() throws {
        let summary = try ARCCapabilitiesEvaluator.evaluate(ARCCapabilitiesEvaluator.syntheticBundle)
        let original = ARCCapabilitiesRecord(taskID: UUID().uuidString, recordedAt: Date(timeIntervalSince1970: 0),
            bundle: ARCCapabilitiesEvaluator.syntheticBundle, summary: summary)
        let records = Array(repeating: original, count: 80)
        let graph = CompanionGraph.build(receipts: [], lessons: [], source: nil, now: original.recordedAt, arcRecords: records)
        XCTAssertEqual(graph.nodes.filter { $0.kind == .evaluation }.count, 1)
        XCTAssertEqual(graph.truncatedCount, 64)
        XCTAssertLessThanOrEqual(graph.nodes.count, CompanionGraph.maximumNodes)
        XCTAssertTrue(graph.edges.allSatisfy { edge in graph.nodes.contains { $0.id == edge.source } && graph.nodes.contains { $0.id == edge.target } })
    }
}

@MainActor
private final class ARCGraphFixture {
    let directory: URL
    let profile: URL
    let store: CompanionStore
    let client = ARCGraphNoDispatchClient()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var archive: URL { profile.deletingPathExtension().appendingPathExtension("arc.json") }
    var journal: URL { profile.deletingPathExtension().appendingPathExtension("steward.json") }
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-arc-graph-" + UUID().uuidString)
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

@MainActor private final class ARCGraphNoDispatchClient: AssistantClient {
    var calls = 0
    func connect() async throws { calls += 1; XCTFail("Graph inspection cannot connect") }
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; XCTFail("Graph inspection cannot invoke inference")
    }
}
