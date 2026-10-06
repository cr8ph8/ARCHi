import XCTest
@testable import ARCHiDesktop

/// Temporary, synthetic files exercise the boundary between independently
/// retained ARC evidence and application-owned accounting. No client connects.
final class StewardARCRecoveryTests: XCTestCase {
    @MainActor
    func testRepeatedEvidenceRechecksCorruptArchiveBeforeReportingSuccess() throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanUp() }
        let first = fixture.store.arcCapabilities.runSyntheticDemonstration()
        fixture.store.recordARCEvaluation(first)
        XCTAssertNil(first.error)
        let corrupt = Data("preserve this corrupt ARC archive".utf8)
        try corrupt.write(to: fixture.archive)

        let repeated = fixture.store.arcCapabilities.runSyntheticDemonstration()
        fixture.store.recordARCEvaluation(repeated)

        XCTAssertNotNil(repeated.error, "A cached duplicate must not bypass the saved archive check")
        XCTAssertNil(repeated.evidenceID)
        XCTAssertNil(repeated.passed)
        XCTAssertEqual(try Data(contentsOf: fixture.archive), corrupt)
        let failed = try XCTUnwrap(fixture.store.tokenSteward.tasks.first { $0.id == repeated.taskID })
        XCTAssertEqual(failed.lanes.first?.state, "failed")
        XCTAssertTrue(failed.outcomes.isEmpty)
        XCTAssertEqual(fixture.store.arcCapabilities.records.count, 1, "Keep the already reviewed in-memory evidence visible")
        fixture.assertNoDispatchOrCharges()
    }

    @MainActor
    func testRepeatedEvidenceRejectsRemovedArchiveWithoutRecreatingIt() throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanUp() }
        XCTAssertNil(fixture.store.arcCapabilities.runSyntheticDemonstration().error)
        try FileManager.default.removeItem(at: fixture.archive)

        let repeated = fixture.store.arcCapabilities.runSyntheticDemonstration()

        XCTAssertNotNil(repeated.error, "An external deletion must not become a successful retained evaluation")
        XCTAssertNil(repeated.evidenceID)
        XCTAssertNil(repeated.passed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.archive.path))
        XCTAssertEqual(fixture.store.arcCapabilities.records.count, 1)
        fixture.assertNoDispatchOrCharges()
    }

    @MainActor
    func testRepeatedEvidenceRejectsChangedValidArchiveUntilReopen() throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanUp() }
        XCTAssertNil(fixture.store.arcCapabilities.runSyntheticDemonstration().error)
        var archive = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.archive)) as? [String: Any])
        var records = try XCTUnwrap(archive["records"] as? [[String: Any]])
        let date = try XCTUnwrap(records[0]["recordedAt"] as? Double)
        records[0]["recordedAt"] = date + 1
        archive["records"] = records
        let changed = try JSONSerialization.data(withJSONObject: archive, options: [.sortedKeys])
        try changed.write(to: fixture.archive)

        let repeated = fixture.store.arcCapabilities.runSyntheticDemonstration()

        XCTAssertNotNil(repeated.error, "A duplicate must obey the same stale-session rule as new evidence")
        XCTAssertNil(repeated.evidenceID)
        XCTAssertEqual(try Data(contentsOf: fixture.archive), changed)
        let reopened = ARCCapabilitiesStore(storageURL: fixture.archive)
        XCTAssertNil(reopened.lastError)
        XCTAssertNil(reopened.runSyntheticDemonstration().error)
        XCTAssertEqual(reopened.records.count, 1)
        fixture.assertNoDispatchOrCharges()
    }

    @MainActor
    func testUnreadableJournalMakesAccountingUnavailableAndExportFailsClosed() throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanUp() }
        let corrupt = Data("preserve this corrupt usage journal".utf8)
        try corrupt.write(to: fixture.journal)
        let reopened = TokenStewardStore(url: fixture.journal)

        XCTAssertNotNil(reopened.loadError)
        XCTAssertFalse(reopened.summary.accountingAvailable, "An unreadable journal is unknown accounting, not measured zero")
        XCTAssertThrowsError(try reopened.exportData())
        XCTAssertEqual(try Data(contentsOf: fixture.journal), corrupt)
        fixture.assertNoDispatchOrCharges()
    }

    @MainActor
    func testFailedRefreshHidesCachedTotalsAndRepairRestoresThem() throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanUp() }
        let event = fixture.store.arcCapabilities.runSyntheticDemonstration()
        fixture.store.recordARCEvaluation(event)
        let steward = fixture.store.tokenSteward
        let expected = steward.summary // Populate the presentation cache before failure.
        let saved = try steward.exportData()
        let corrupt = Data("not a journal".utf8)
        try corrupt.write(to: fixture.journal)

        XCTAssertThrowsError(try steward.refresh())
        XCTAssertFalse(steward.summary.accountingAvailable, "A cached summary cannot remain current after a failed refresh")
        XCTAssertEqual(steward.tasks.map(\.id), [event.taskID], "Retain the last known in-memory evidence for recovery")
        XCTAssertThrowsError(try steward.exportData())
        XCTAssertEqual(try Data(contentsOf: fixture.journal), corrupt)

        try saved.write(to: fixture.journal)
        try steward.refresh()
        XCTAssertNil(steward.loadError)
        XCTAssertEqual(steward.summary, expected)
        fixture.assertNoDispatchOrCharges()
    }

    @MainActor
    func testReopenAndExportRetainDistinctEvaluationTasksForOneEvidenceRecord() throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanUp() }
        let first = fixture.store.arcCapabilities.runSyntheticDemonstration()
        fixture.store.recordARCEvaluation(first)
        fixture.store.recordARCEvaluation(first)
        let second = fixture.store.arcCapabilities.runSyntheticDemonstration()
        fixture.store.recordARCEvaluation(second)
        XCTAssertNil(first.error)
        XCTAssertNil(second.error)
        XCTAssertNotEqual(first.taskID, second.taskID)
        XCTAssertEqual(first.evidenceID, second.evidenceID)
        let expectedIDs = Set([first.taskID, second.taskID])
        let originalJournal = try Data(contentsOf: fixture.journal)
        let originalArchive = try Data(contentsOf: fixture.archive)

        let reopened = fixture.reopen()
        XCTAssertNil(reopened.arcCapabilities.lastError)
        XCTAssertNil(reopened.tokenSteward.loadError)
        XCTAssertEqual(reopened.arcCapabilities.records.count, 1)
        XCTAssertEqual(reopened.arcCapabilities.records.first?.taskID, first.taskID)
        XCTAssertEqual(Set(reopened.tokenSteward.tasks.map(\.id)), expectedIDs)
        XCTAssertEqual(reopened.tokenSteward.summary.evaluationTaskCount, 2)
        XCTAssertEqual(reopened.tokenSteward.summary.deliveredTaskCount, 0)
        XCTAssertEqual(reopened.tokenSteward.summary.checkedSuccessfulTaskCount, 0)
        XCTAssertEqual(reopened.tokenSteward.summary.usefulTaskCount, 0)
        XCTAssertEqual(try Data(contentsOf: fixture.journal), originalJournal)
        XCTAssertEqual(try Data(contentsOf: fixture.archive), originalArchive)

        let exportedURL = fixture.directory.appendingPathComponent("exported-usage.json")
        try reopened.tokenSteward.exportData().write(to: exportedURL, options: .atomic)
        let exported = TokenStewardStore(url: exportedURL)
        XCTAssertNil(exported.loadError)
        XCTAssertEqual(exported.tasks, reopened.tokenSteward.tasks)
        XCTAssertEqual(exported.summary, reopened.tokenSteward.summary)
        XCTAssertTrue(exported.observations.isEmpty)
        XCTAssertTrue(exported.reservations.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture.journal), originalJournal)
        fixture.assertNoDispatchOrCharges()
    }

    @MainActor
    func testRetainedARCEventRetriesAfterJournalRepairWithoutDuplicateAccounting() throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanUp() }
        let first = fixture.store.arcCapabilities.runSyntheticDemonstration()
        fixture.store.recordARCEvaluation(first)
        let savedJournal = try Data(contentsOf: fixture.journal)
        let savedArchive = try Data(contentsOf: fixture.archive)
        let corrupt = Data("journal temporarily unavailable".utf8)
        try corrupt.write(to: fixture.journal)

        let second = fixture.store.arcCapabilities.runSyntheticDemonstration()
        XCTAssertNil(second.error, "ARC retains evidence independently of usage accounting")
        fixture.store.recordARCEvaluation(second)
        XCTAssertNotNil(fixture.store.stewardMessage)
        XCTAssertEqual(try Data(contentsOf: fixture.journal), corrupt)
        XCTAssertEqual(try Data(contentsOf: fixture.archive), savedArchive)

        try savedJournal.write(to: fixture.journal)
        fixture.store.retryStewardAccounting()
        fixture.store.retryStewardAccounting()
        XCTAssertNil(fixture.store.stewardMessage)
        XCTAssertEqual(Set(fixture.store.tokenSteward.tasks.map(\.id)), Set([first.taskID, second.taskID]))
        XCTAssertEqual(fixture.store.tokenSteward.summary.evaluationTaskCount, 2)
        let reopened = fixture.reopen()
        XCTAssertEqual(reopened.arcCapabilities.records.count, 1)
        XCTAssertEqual(reopened.tokenSteward.tasks, fixture.store.tokenSteward.tasks)
        XCTAssertEqual(try Data(contentsOf: fixture.archive), savedArchive)
        fixture.assertNoDispatchOrCharges()
    }

    @MainActor
    func testRestartDoesNotInventAccountingForEventLostBeforeJournalCommit() throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanUp() }
        let first = fixture.store.arcCapabilities.runSyntheticDemonstration()
        fixture.store.recordARCEvaluation(first)
        let savedJournal = try Data(contentsOf: fixture.journal)
        let savedArchive = try Data(contentsOf: fixture.archive)
        try Data("journal write unavailable".utf8).write(to: fixture.journal)
        let uncommitted = fixture.store.arcCapabilities.runSyntheticDemonstration()
        fixture.store.recordARCEvaluation(uncommitted)
        XCTAssertNotNil(fixture.store.stewardMessage)

        // A replacement application owner cannot recover another process's
        // in-memory retry. Restoring valid saved bytes must not fabricate it.
        try savedJournal.write(to: fixture.journal)
        let restarted = fixture.reopen()
        restarted.retryStewardAccounting()
        XCTAssertNil(restarted.stewardMessage)
        XCTAssertEqual(restarted.arcCapabilities.records.count, 1)
        XCTAssertEqual(restarted.tokenSteward.tasks.map(\.id), [first.taskID])
        XCTAssertFalse(restarted.tokenSteward.tasks.contains { $0.id == uncommitted.taskID })
        XCTAssertEqual(try Data(contentsOf: fixture.journal), savedJournal)
        XCTAssertEqual(try Data(contentsOf: fixture.archive), savedArchive)

        let explicitlyRepeated = restarted.arcCapabilities.runSyntheticDemonstration()
        restarted.recordARCEvaluation(explicitlyRepeated)
        XCTAssertNotEqual(explicitlyRepeated.taskID, uncommitted.taskID)
        XCTAssertEqual(Set(restarted.tokenSteward.tasks.map(\.id)), Set([first.taskID, explicitlyRepeated.taskID]))
        XCTAssertEqual(restarted.arcCapabilities.records.count, 1)
        fixture.assertNoDispatchOrCharges()
    }
}

@MainActor
private final class RecoveryFixture {
    let directory: URL
    let profile: URL
    let client = RecoveryNoDispatchClient()
    let store: CompanionStore
    var journal: URL { profile.deletingPathExtension().appendingPathExtension("steward.json") }
    var archive: URL { profile.deletingPathExtension().appendingPathExtension("arc.json") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-steward-arc-recovery-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        profile = directory.appendingPathComponent("preferences.json")
        try NativePreferenceDocument().encoded().write(to: profile)
        let noDispatch = client
        store = CompanionStore(preferenceURL: profile, assistant: noDispatch,
            assistantFactory: { _, _ in noDispatch }, allowsPlay: false)
    }

    func reopen() -> CompanionStore {
        let noDispatch = client
        return CompanionStore(preferenceURL: profile, assistant: noDispatch,
            assistantFactory: { _, _ in noDispatch }, allowsPlay: false)
    }

    func assertNoDispatchOrCharges(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(client.connectCount, 0, file: file, line: line)
        XCTAssertEqual(client.requestCount, 0, file: file, line: line)
        XCTAssertTrue(store.tokenSteward.observations.isEmpty, file: file, line: line)
        XCTAssertTrue(store.tokenSteward.reservations.isEmpty, file: file, line: line)
        XCTAssertNil(store.tokenSteward.budget, file: file, line: line)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: directory) }
}

@MainActor
private final class RecoveryNoDispatchClient: AssistantClient {
    private(set) var connectCount = 0
    private(set) var requestCount = 0
    func connect() async throws { connectCount += 1; throw AssistantFailure.stopped }
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        requestCount += 1
        throw AssistantFailure.stopped
    }
}
