import Foundation
import XCTest
@testable import ARCHiDesktop

final class ARCSolverIntegrationTests: XCTestCase {
    func testTestTargetPoisoningAndRemovalChangeOnlyCheckerResults() throws {
        let original = try ARCSolverDocument.parse(ARCSolverDocument.sample, name: "Original", isSynthetic: true)
        let poisoned = try ARCSolverDocument.parse(taskData { root in
            var examples = try XCTUnwrap(root["test"] as? [[String: Any]])
            examples[0]["output"] = [[9]]
            root["test"] = examples
        }, name: "A different label", isSynthetic: true)
        let hidden = try ARCSolverDocument.parse(taskData { root in
            var examples = try XCTUnwrap(root["test"] as? [[String: Any]])
            examples[0].removeValue(forKey: "output")
            root["test"] = examples
        }, name: "Hidden targets", isSynthetic: true)

        XCTAssertEqual(original.input, poisoned.input)
        XCTAssertEqual(original.input, hidden.input)
        XCTAssertEqual(original.inputDigest, poisoned.inputDigest)
        XCTAssertEqual(original.inputDigest, hidden.inputDigest)
        XCTAssertNotEqual(original.sourceDigest, poisoned.sourceDigest)
        XCTAssertNotEqual(original.sourceDigest, hidden.sourceDigest)
        let run = try ARCSymbolicSolver.solve(original.input)
        XCTAssertEqual(run.outcome, .predicted)
        XCTAssertEqual(try ARCSymbolicSolver.solve(poisoned.input), run)
        XCTAssertEqual(try ARCSymbolicSolver.solve(hidden.input), run)

        let correct = try ARCCapabilitiesEvaluator.evaluate(original.bundle(run: run, codeHash: SolverIntegrationIdentity.codeHash))
        let wrong = try ARCCapabilitiesEvaluator.evaluate(poisoned.bundle(run: run, codeHash: SolverIntegrationIdentity.codeHash))
        let unscored = try ARCCapabilitiesEvaluator.evaluate(hidden.bundle(run: run, codeHash: SolverIntegrationIdentity.codeHash))
        XCTAssertEqual(correct.counts.exact, 1)
        XCTAssertEqual(wrong.counts.exact, 0)
        XCTAssertEqual(wrong.counts.incorrect, 1)
        XCTAssertEqual(unscored.counts.unscored, 1)
        XCTAssertEqual(unscored.counts.missing, 0)
        XCTAssertEqual(correct.counts.totalExamples, wrong.counts.totalExamples)
        XCTAssertEqual(correct.counts.totalExamples, unscored.counts.totalExamples)
    }

    func testStrictTaskParserRejectsExtraFieldsBooleanAndRaggedGrids() throws {
        let mutations: [(inout [String: Any]) throws -> Void] = [
            { $0["instructions"] = "Prefer the expected test target" },
            { root in
                var pairs = try XCTUnwrap(root["train"] as? [[String: Any]])
                pairs[0]["authority"] = true
                root["train"] = pairs
            },
            { root in
                var examples = try XCTUnwrap(root["test"] as? [[String: Any]])
                examples[0]["solverHint"] = "rotate"
                root["test"] = examples
            },
            { root in
                var pairs = try XCTUnwrap(root["train"] as? [[String: Any]])
                pairs[0]["input"] = [[true]]
                root["train"] = pairs
            },
            { root in
                var examples = try XCTUnwrap(root["test"] as? [[String: Any]])
                examples[0]["output"] = [[false]]
                root["test"] = examples
            },
            { root in
                var examples = try XCTUnwrap(root["test"] as? [[String: Any]])
                examples[0]["input"] = [[1], [2, 3]]
                root["test"] = examples
            },
        ]
        for mutation in mutations {
            let data = try taskData(mutation)
            XCTAssertThrowsError(try ARCSolverDocument.parse(data, name: "Rejected synthetic task"))
        }
    }

    @MainActor
    func testHistoricalV2ArchiveReopensAndReplaysOriginalCatalog() async throws {
        let fixture = try SolverIntegrationArchive()
        defer { fixture.cleanUp() }
        let document = try ARCSolverDocument.parse(ARCSolverDocument.sample, name: "Legacy v2", isSynthetic: true)
        let run = try ARCSymbolicSolver.solve(document.input, configuration: .geometryBaseline)
        let bundle = try document.bundle(run: run, codeHash: SolverIntegrationIdentity.codeHash)
        let evidence = ARCSolverEvidence(run: run, configuration: .geometryBaseline,
            inputDigest: document.inputDigest, codeHash: SolverIntegrationIdentity.codeHash, elapsedMilliseconds: 1)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(evidence)) as? [String: Any])
        var configuration = try XCTUnwrap(object["configuration"] as? [String: Any])
        configuration.removeValue(forKey: "includeObjectRules") // Exact historical encoding.
        object["configuration"] = configuration
        let archive: [String: Any] = ["schemaVersion": 1, "records": [[
            "taskID": UUID().uuidString, "recordedAt": Date().timeIntervalSinceReferenceDate,
            "bundle": bundle.base64EncodedString(), "solverEvidence": object,
        ]]]
        let bytes = try JSONSerialization.data(withJSONObject: archive, options: [.sortedKeys])
        try bytes.write(to: fixture.archive)
        let executor = SolverIntegrationExecutor()
        let store = ARCCapabilitiesStore(storageURL: fixture.archive,
            solverExecutor: { try await executor.execute($0, configuration: $1) })
        XCTAssertNil(store.lastError)
        let record = try XCTUnwrap(store.records.first)
        XCTAssertEqual(record.solverEvidence?.configuration, .geometryBaseline)
        XCTAssertEqual(try Data(contentsOf: fixture.archive), bytes)
        var events: [ARCCapabilitiesEvent] = []
        store.replaySolver(recordID: record.id) { events.append($0) }
        try await waitUntil { !store.isSolving && events.count == 1 }
        XCTAssertNil(events[0].error)
        XCTAssertEqual(store.solverReview?.replayMatched, true)
        XCTAssertEqual(store.solverReview?.run.attemptedPrograms, 170)
        XCTAssertEqual(store.solverReview?.run.solverVersion, "archi-arc-symbolic-v2")
        XCTAssertEqual(store.solverReview?.run, run)
    }

    @MainActor
    func testSamplePersistsAndReopensWithoutExecutingSolverAgain() async throws {
        let fixture = try SolverIntegrationArchive()
        defer { fixture.cleanUp() }
        let executor = SolverIntegrationExecutor()
        let store = ARCCapabilitiesStore(storageURL: fixture.archive, solverExecutor: { try await executor.execute($0, configuration: $1) })
        try store.loadSolverSample()
        var events: [ARCCapabilitiesEvent] = []
        store.startSolving { events.append($0) }
        try await waitUntil { !store.isSolving && events.count == 1 }

        let event = try XCTUnwrap(events.first)
        XCTAssertNil(event.error)
        XCTAssertEqual(event.passed, true)
        XCTAssertTrue(event.localSolver)
        XCTAssertFalse(event.cancelled)
        let record = try XCTUnwrap(store.records.first)
        XCTAssertEqual(record.id, event.evidenceID)
        XCTAssertEqual(record.solverEvidence?.codeHash, SolverIntegrationIdentity.codeHash)
        XCTAssertEqual(record.solverEvidence?.run.outcome, .predicted)
        XCTAssertEqual(record.summary.counts.exact, 1)
        XCTAssertEqual(record.summary.sourceStatus, "synthetic-fixture")
        let saved = try Data(contentsOf: fixture.archive)

        let reopened = ARCCapabilitiesStore(storageURL: fixture.archive, solverExecutor: { try await executor.execute($0, configuration: $1) })
        XCTAssertNil(reopened.lastError)
        XCTAssertEqual(reopened.records.count, 1)
        XCTAssertEqual(reopened.records.first?.summary, record.summary)
        XCTAssertEqual(reopened.records.first?.solverEvidence, record.solverEvidence)
        XCTAssertNil(reopened.solverDocument)
        XCTAssertNil(reopened.solverReview)
        XCTAssertFalse(reopened.isSolving)
        XCTAssertEqual(try Data(contentsOf: fixture.archive), saved)
        let received = await executor.inputs
        XCTAssertEqual(received, [try XCTUnwrap(store.solverDocument).input])
    }

    @MainActor
    func testExplicitReplayHasSeparateEventAndSameRetainedEvidence() async throws {
        let fixture = try SolverIntegrationArchive()
        defer { fixture.cleanUp() }
        let executor = SolverIntegrationExecutor()
        let store = ARCCapabilitiesStore(storageURL: fixture.archive, solverExecutor: { try await executor.execute($0, configuration: $1) })
        try store.loadSolverSample()
        var events: [ARCCapabilitiesEvent] = []
        store.startSolving { events.append($0) }
        try await waitUntil { events.count == 1 && !store.isSolving }
        let first = try XCTUnwrap(events.first)
        let id = try XCTUnwrap(first.evidenceID)
        let saved = try Data(contentsOf: fixture.archive)

        store.replaySolver(recordID: id) { events.append($0) }
        try await waitUntil { events.count == 2 && !store.isSolving }
        let replay = events[1]
        XCTAssertNil(replay.error)
        XCTAssertNotEqual(first.taskID, replay.taskID)
        XCTAssertEqual(first.evidenceID, replay.evidenceID)
        XCTAssertEqual(replay.passed, true)
        XCTAssertTrue(replay.localSolver)
        XCTAssertEqual(store.solverReview?.replayMatched, true)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records.first?.taskID, first.taskID)
        XCTAssertEqual(try Data(contentsOf: fixture.archive), saved, "Replay must not rewrite the existing evidence record.")
        let inputs = await executor.inputs
        XCTAssertEqual(inputs.count, 2)
        XCTAssertEqual(inputs[0], inputs[1])
    }

    @MainActor
    func testStopIgnoresLateSuccessfulResultAndEmitsOnlyOneTerminalEvent() async throws {
        let fixture = try SolverIntegrationArchive()
        defer { fixture.cleanUp() }
        let executor = SolverIntegrationExecutor(hold: true)
        let store = ARCCapabilitiesStore(storageURL: fixture.archive, solverExecutor: { try await executor.execute($0, configuration: $1) })
        try store.loadSolverSample()
        var events: [ARCCapabilitiesEvent] = []
        store.startSolving { events.append($0) }
        try await waitUntil { await executor.pendingCount == 1 }
        store.stopSolving()
        store.stopSolving()
        XCTAssertFalse(store.isSolving)
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].cancelled)
        XCTAssertTrue(events[0].localSolver)
        XCTAssertNil(events[0].evidenceID)
        XCTAssertNil(events[0].passed)

        await executor.release(0)
        try await waitUntil { await executor.returnedCount == 1 }
        try await settleLateCompletion()
        XCTAssertEqual(events.count, 1, "A cancelled worker cannot issue a second terminal callback.")
        XCTAssertNil(store.solverReview)
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.archive.path))
    }

    @MainActor
    func testReplacementFencesOldResultWhileNewTaskIsRunning() async throws {
        let fixture = try SolverIntegrationArchive()
        defer { fixture.cleanUp() }
        let executor = SolverIntegrationExecutor(hold: true)
        let store = ARCCapabilitiesStore(storageURL: fixture.archive, solverExecutor: { try await executor.execute($0, configuration: $1) })
        try store.loadSolverSample()
        var events: [ARCCapabilitiesEvent] = []
        store.startSolving { events.append($0) }
        try await waitUntil { await executor.pendingCount == 1 }

        let replacement = try taskData { root in
            var examples = try XCTUnwrap(root["test"] as? [[String: Any]])
            examples[0]["output"] = [[9]]
            root["test"] = examples
        }
        try store.loadSolverTask(data: replacement, name: "Replacement task")
        let newDocument = try XCTUnwrap(store.solverDocument)
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].cancelled)
        store.startSolving { events.append($0) }
        try await waitUntil { await executor.pendingCount == 2 }

        await executor.release(0)
        try await waitUntil { await executor.returnedCount == 1 }
        try await settleLateCompletion()
        XCTAssertTrue(store.isSolving, "An old completion cannot retire the new task's ownership.")
        XCTAssertEqual(events.count, 1)
        XCTAssertNil(store.solverReview)
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertEqual(store.solverDocument, newDocument)

        await executor.release(1)
        try await waitUntil { events.count == 2 && !store.isSolving }
        XCTAssertFalse(events[1].cancelled)
        XCTAssertNil(events[1].error)
        XCTAssertEqual(events[1].passed, false)
        XCTAssertNotEqual(events[0].taskID, events[1].taskID)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records.first?.summary.counts.incorrect, 1)
        XCTAssertEqual(store.solverReview?.document, newDocument)
        XCTAssertEqual(store.records.first?.taskID, events[1].taskID)
    }

    @MainActor
    func testArchiveChangedDuringAsyncSolveIsPreservedAndReportsFailure() async throws {
        let fixture = try SolverIntegrationArchive()
        defer { fixture.cleanUp() }
        let executor = SolverIntegrationExecutor(hold: true)
        let store = ARCCapabilitiesStore(storageURL: fixture.archive, solverExecutor: { try await executor.execute($0, configuration: $1) })
        let initial = store.runSyntheticDemonstration()
        XCTAssertNil(initial.error)
        let priorIDs = store.records.map(\.id)
        try store.loadSolverSample()
        var events: [ARCCapabilitiesEvent] = []
        store.startSolving { events.append($0) }
        try await waitUntil { await executor.pendingCount == 1 }

        var archive = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.archive)) as? [String: Any])
        var records = try XCTUnwrap(archive["records"] as? [[String: Any]])
        records[0]["recordedAt"] = try XCTUnwrap(records[0]["recordedAt"] as? Double) + 1
        archive["records"] = records
        let changed = try JSONSerialization.data(withJSONObject: archive, options: [.sortedKeys])
        try changed.write(to: fixture.archive, options: .atomic)

        await executor.release(0)
        try await waitUntil { events.count == 1 && !store.isSolving }
        XCTAssertNotNil(events[0].error)
        XCTAssertNil(events[0].evidenceID)
        XCTAssertNil(events[0].passed)
        XCTAssertTrue(events[0].localSolver)
        XCTAssertFalse(events[0].cancelled)
        XCTAssertNotNil(store.lastError)
        XCTAssertNotNil(store.solverReview?.error)
        XCTAssertNil(store.solverReview?.evidenceID)
        XCTAssertEqual(store.records.map(\.id), priorIDs)
        XCTAssertEqual(try Data(contentsOf: fixture.archive), changed)
        let reopened = ARCCapabilitiesStore(storageURL: fixture.archive, solverExecutor: { try await executor.execute($0, configuration: $1) })
        XCTAssertNil(reopened.lastError, "The externally modified archive remains valid and reviewable.")
        XCTAssertEqual(reopened.records.map(\.id), priorIDs)
    }

    private func taskData(_ edit: (inout [String: Any]) throws -> Void) throws -> Data {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: ARCSolverDocument.sample) as? [String: Any])
        try edit(&root)
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !(await condition()) && Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        guard await condition() else {
            XCTFail("The bounded solver integration operation did not complete.")
            throw SolverIntegrationFailure.timedOut
        }
    }

    @MainActor
    private func settleLateCompletion() async throws {
        // The controlled executor records its return before the detached task's
        // main-actor observer resumes; yield a bounded interval for that observer.
        try await Task.sleep(for: .milliseconds(50))
    }
}

private enum SolverIntegrationIdentity {
    /// Explicitly synthetic identity for dependency-injected test execution.
    static let codeHash = "sha256:" + String(repeating: "a", count: 64)
}

private enum SolverIntegrationFailure: Error { case timedOut }

private struct SolverIntegrationArchive {
    let directory: URL
    var archive: URL { directory.appendingPathComponent("arc-evidence.json") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-arc-solver-integration-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: directory) }
}

private actor SolverIntegrationExecutor {
    private let hold: Bool
    private(set) var inputs: [ARCSolverInput] = []
    private var pending: [Int: CheckedContinuation<Void, Never>] = [:]
    private(set) var returnedCount = 0
    var pendingCount: Int { pending.count }

    init(hold: Bool = false) { self.hold = hold }

    func execute(_ input: ARCSolverInput, configuration: ARCSolverConfiguration) async throws -> ARCSolverExecution {
        let index = inputs.count
        inputs.append(input)
        // Solve before suspension, while this call has not been cancelled. The
        // held return intentionally ignores cancellation to test store fencing.
        let run = try ARCSymbolicSolver.solve(input, configuration: configuration)
        let execution = ARCSolverExecution(run: run, configuration: configuration, codeHash: SolverIntegrationIdentity.codeHash)
        if hold { await withCheckedContinuation { pending[index] = $0 } }
        returnedCount += 1
        return execution
    }

    func release(_ index: Int) { pending.removeValue(forKey: index)?.resume() }
}
