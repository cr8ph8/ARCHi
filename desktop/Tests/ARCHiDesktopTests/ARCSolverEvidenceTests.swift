import Foundation
import XCTest
@testable import ARCHiDesktop

final class ARCSolverEvidenceTests: XCTestCase {
    func testCompleteAndTruncatedRealTracesValidate() throws {
        for limit in [0, 1, 2, 1_500] {
            let fixture = try makeFixture(configuration: .init(maxTraceEntries: limit))
            XCTAssertEqual(fixture.evidence.run.outcome, .predicted)
            XCTAssertEqual(fixture.evidence.run.trace.count, min(fixture.evidence.run.attemptedPrograms, limit))
            XCTAssertEqual(fixture.evidence.run.traceTruncated, fixture.evidence.run.attemptedPrograms > limit)
            XCTAssertNoThrow(try fixture.evidence.validate(bundle: fixture.bundle))
        }
    }

    func testBudgetExpiryAfterTrainingFitKeepsAnUnfinishedPredictionEntry() throws {
        // The sample needs 30 validation cell operations, then 48 operations
        // to fit rotate90 to both training pairs. Its test transform is next.
        let fixture = try makeFixture(configuration: .init(maxCellOperations: 78))
        let run = fixture.evidence.run
        XCTAssertEqual(run.outcome, .budgetExhausted)
        XCTAssertNil(run.predictions)
        XCTAssertEqual(run.programIDs, ["rotate90"])
        XCTAssertEqual(run.trace.last?.status, .budgetExhausted)
        XCTAssertEqual(run.trace.last?.programID, "rotate90")
        XCTAssertEqual(run.trace.last?.trainingExamplesChecked, fixture.document.input.training.count)
        XCTAssertFalse(run.trace.contains { $0.status == .matched || $0.status == .predictionUndefined })
        XCTAssertNoThrow(try fixture.evidence.validate(bundle: fixture.bundle),
                         "The fit is recorded before budget exhaustion during test prediction.")
        let truncated = try makeFixture(configuration: .init(maxCellOperations: 78, maxTraceEntries: 1))
        XCTAssertTrue(truncated.evidence.run.traceTruncated)
        XCTAssertNoThrow(try truncated.evidence.validate(bundle: truncated.bundle),
                         "The final budget entry may be beyond the retained trace prefix.")
        let wrongUnfinishedFit = try mutate(fixture.evidence) { $0["programIDs"] = ["reflectColumns"] }
        XCTAssertThrowsError(try wrongUnfinishedFit.validate(bundle: fixture.bundle),
                             "An unfinished fit must identify the program whose prediction exhausted the budget.")
    }

    func testValidationAndAttemptBudgetExitsHaveNoInventedTraceEntry() throws {
        for configuration in [ARCSolverConfiguration(maxCellOperations: 0),
                              ARCSolverConfiguration(maxProgramAttempts: 1)] {
            let fixture = try makeFixture(configuration: configuration)
            XCTAssertEqual(fixture.evidence.run.outcome, .budgetExhausted)
            XCTAssertEqual(fixture.evidence.run.trace.count, fixture.evidence.run.attemptedPrograms)
            XCTAssertNoThrow(try fixture.evidence.validate(bundle: fixture.bundle))
        }
    }

    func testImpossibleTraceLengthAndTruncationAreRejectedWithoutChangingPredictions() throws {
        let fixture = try makeFixture()
        let missingEntry = try mutate(fixture.evidence) { run in
            var trace = try XCTUnwrap(run["trace"] as? [[String: Any]])
            trace.removeLast()
            run["trace"] = trace
        }
        let falseTruncation = try mutate(fixture.evidence) { $0["traceTruncated"] = true }
        XCTAssertThrowsError(try missingEntry.validate(bundle: fixture.bundle))
        XCTAssertThrowsError(try falseTruncation.validate(bundle: fixture.bundle))
        let truncated = try makeFixture(configuration: .init(maxTraceEntries: 1))
        let hiddenTruncation = try mutate(truncated.evidence) { $0["traceTruncated"] = false }
        XCTAssertThrowsError(try hiddenTruncation.validate(bundle: truncated.bundle))
    }

    func testFitTraceMustAgreeWithRecordedProgramIDsAndTrainingCoverage() throws {
        let fixture = try makeFixture()
        let wrongIdentity = try mutate(fixture.evidence) { run in
            var trace = try XCTUnwrap(run["trace"] as? [[String: Any]])
            let index = try XCTUnwrap(trace.firstIndex { $0["status"] as? String == "matched" })
            trace[index]["programID"] = "invented-rule"
            run["trace"] = trace
        }
        let incompleteFit = try mutate(fixture.evidence) { run in
            var trace = try XCTUnwrap(run["trace"] as? [[String: Any]])
            let index = try XCTUnwrap(trace.firstIndex { $0["status"] as? String == "matched" })
            trace[index]["trainingExamplesChecked"] = 0
            run["trace"] = trace
        }
        XCTAssertThrowsError(try wrongIdentity.validate(bundle: fixture.bundle))
        XCTAssertThrowsError(try incompleteFit.validate(bundle: fixture.bundle))
    }

    func testPredictedRunCannotContainBudgetOrUndefinedPredictionTrace() throws {
        let fixture = try makeFixture()
        for status in ["budgetExhausted", "predictionUndefined"] {
            let forged = try mutate(fixture.evidence) { run in
                var trace = try XCTUnwrap(run["trace"] as? [[String: Any]])
                let index = try XCTUnwrap(trace.firstIndex { $0["status"] as? String == "matched" })
                trace[index]["status"] = status
                run["trace"] = trace
            }
            XCTAssertThrowsError(try forged.validate(bundle: fixture.bundle), status)
        }
    }

    func testRecordedTrainingOrderMustReplayTheDeclaredScheduler() throws {
        for order in [ARCSolverConfiguration.TrainingOrder.fixed, .adaptive] {
            let fixture = try makeFixture(configuration: .init(trainingOrder: order))
            XCTAssertNoThrow(try fixture.evidence.validate(bundle: fixture.bundle))
            for alterFirst in [true, false] {
                let forged = try mutate(fixture.evidence) { run in
                    var trace = try XCTUnwrap(run["trace"] as? [[String: Any]])
                    if alterFirst {
                        trace[0]["checkedTrainingIndices"] = [1]
                    } else {
                        let index = try XCTUnwrap(trace.firstIndex { $0["status"] as? String == "matched" })
                        let indices = try XCTUnwrap(trace[index]["checkedTrainingIndices"] as? [Int])
                        trace[index]["checkedTrainingIndices"] = Array(indices.reversed())
                    }
                    run["trace"] = trace
                }
                XCTAssertThrowsError(try forged.validate(bundle: fixture.bundle),
                    "A valid prediction cannot authenticate an impossible verification order.")
            }
        }
    }

    func testRepeatedOutOfRangeAndOverflowedTrainingVisitsAreRejected() throws {
        let fixture = try makeFixture()
        for indices in [[0, 0], [0, 2], [-1], [Int.max]] {
            let forged = try mutate(fixture.evidence) { run in
                var trace = try XCTUnwrap(run["trace"] as? [[String: Any]])
                trace[0]["checkedTrainingIndices"] = indices
                run["trace"] = trace
            }
            XCTAssertThrowsError(try forged.validate(bundle: fixture.bundle))
        }
        let overflow = try mutate(fixture.evidence) { run in
            var trace = try XCTUnwrap(run["trace"] as? [[String: Any]])
            trace[0]["trainingExamplesChecked"] = Int.max
            run["trace"] = trace
        }
        XCTAssertThrowsError(try overflow.validate(bundle: fixture.bundle))
    }

    func testNoMatchCannotRetainTrainingFitsEvenWhenBundleMatchesTheAbstention() throws {
        let fixture = try makeFixture()
        let forged = try mutate(fixture.evidence) { run in
            run["outcome"] = "noMatch"
            run.removeValue(forKey: "predictions")
        }
        let matchingBundle = try fixture.document.bundle(run: forged.run, codeHash: forged.codeHash)
        XCTAssertEqual(try ARCCapabilitiesEvaluator.evaluate(matchingBundle).counts.missing, 1)
        XCTAssertThrowsError(try forged.validate(bundle: matchingBundle))
    }

    @MainActor
    func testReopeningImpossibleRunPreservesArchiveAndRejectsTheEvidence() throws {
        let fixture = try makeFixture()
        let forged = try mutate(fixture.evidence) { run in
            run["attemptedPrograms"] = 0
            run["matchingPrograms"] = 0
            run["programIDs"] = []
            run["trace"] = []
            run["traceTruncated"] = false
            run["cellOperations"] = 0
        }
        let evidenceObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(forged))
        let archive: [String: Any] = ["schemaVersion": 1, "records": [[
            "taskID": UUID().uuidString, "recordedAt": Date().timeIntervalSinceReferenceDate,
            "bundle": fixture.bundle.base64EncodedString(), "solverEvidence": evidenceObject,
        ]]]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("arc.json")
        let bytes = try JSONSerialization.data(withJSONObject: archive, options: [.sortedKeys])
        try bytes.write(to: url, options: .atomic)

        let reopened = ARCCapabilitiesStore(storageURL: url)
        XCTAssertNotNil(reopened.lastError)
        XCTAssertTrue(reopened.records.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testConfigurationCannotRelabelOneCatalogAsAnother() throws {
        for configuration in [ARCSolverConfiguration.standard, .geometryBaseline] {
            let fixture = try makeFixture(configuration: configuration)
            XCTAssertNoThrow(try fixture.evidence.validate(bundle: fixture.bundle))
            let forged = try mutate(fixture.evidence) { run in
                let other: ARCSolverConfiguration = configuration.includeObjectRules ? .geometryBaseline : .standard
                run["catalogIdentity"] = ARCSymbolicSolver.catalogIdentity(for: other)
                run["solverVersion"] = ARCSymbolicSolver.version(for: other)
            }
            let bundle = try fixture.document.bundle(run: forged.run, codeHash: forged.codeHash)
            XCTAssertThrowsError(try forged.validate(bundle: bundle))
        }
    }

    private func makeFixture(configuration: ARCSolverConfiguration = .standard) throws ->
        (document: ARCSolverDocument, evidence: ARCSolverEvidence, bundle: Data) {
        let document = try ARCSolverDocument.parse(ARCSolverDocument.sample,
                                                   name: "Synthetic evidence validation", isSynthetic: true)
        let run = try ARCSymbolicSolver.solve(document.input, configuration: configuration)
        // Explicit test identity; this is not a measured executable digest.
        let codeHash = "sha256:" + String(repeating: "b", count: 64)
        let evidence = ARCSolverEvidence(run: run, configuration: configuration,
            inputDigest: document.inputDigest, codeHash: codeHash, elapsedMilliseconds: 1)
        return (document, evidence, try document.bundle(run: run, codeHash: codeHash))
    }

    private func mutate(_ evidence: ARCSolverEvidence,
                        _ edit: (inout [String: Any]) throws -> Void) throws -> ARCSolverEvidence {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(evidence)) as? [String: Any])
        var run = try XCTUnwrap(object["run"] as? [String: Any])
        try edit(&run)
        object["run"] = run
        return try JSONDecoder().decode(ARCSolverEvidence.self,
            from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
    }
}
