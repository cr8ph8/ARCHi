import Foundation
import XCTest
@testable import ARCHiDesktop

final class ARCCostAwareIntegrationTests: XCTestCase {
    private let codeHash = "sha256:" + String(repeating: "a", count: 64)

    func testAllModesKeepCompleteFitsAndPredictionsWithUnequalSizeExamples() throws {
        let symmetric = Array(repeating: Array(repeating: 1, count: 10), count: 10)
        let input = ARCSolverInput(training: [
            .init(input: symmetric, output: symmetric),
            .init(input: [[1, 0, 1], [1, 1, 0]], output: [[1, 1], [1, 0], [0, 1]])
        ], testInputs: [[[3, 4, 3], [3, 3, 4]]])
        let fixed = try ARCSymbolicSolver.solve(input, configuration: .init(maxCellOperations: 20_000_000, trainingOrder: .fixed))
        let legacy = try ARCSymbolicSolver.solve(input, configuration: .init(maxCellOperations: 20_000_000, trainingOrder: .adaptive))
        let current = try ARCSymbolicSolver.solve(input, configuration: .init(maxCellOperations: 20_000_000))
        XCTAssertEqual(current.outcome, .predicted)
        XCTAssertEqual(current.predictions, fixed.predictions)
        XCTAssertEqual(current.predictions, legacy.predictions)
        XCTAssertEqual(current.programIDs, fixed.programIDs)
        XCTAssertEqual(current.programIDs, legacy.programIDs)
        XCTAssertEqual(current.attemptedPrograms, ARCSymbolicSolver.catalogProgramCount)
        XCTAssertTrue(current.trace.contains { $0.checkedTrainingIndices.first == 1 })
        XCTAssertTrue(legacy.trace.allSatisfy { $0.checkedTrainingCellOperations == nil })
        var measured = 0
        for entry in current.trace {
            let costs = try XCTUnwrap(entry.checkedTrainingCellOperations)
            XCTAssertEqual(costs.count, entry.checkedTrainingIndices.count)
            XCTAssertTrue(costs.allSatisfy { $0 >= 0 })
            measured += costs.reduce(0, +)
            if entry.status == .matched { XCTAssertEqual(Set(entry.checkedTrainingIndices), [0, 1]) }
        }
        XCTAssertGreaterThan(measured, 0)
        XCTAssertLessThanOrEqual(measured, current.cellOperations)
    }

    func testLegacyRecordsRemainCostFreeAndReplayTheirOriginalVersions() throws {
        for objects in [false, true] {
            for order in [ARCSolverConfiguration.TrainingOrder.fixed, .adaptive] {
                let configuration = ARCSolverConfiguration(trainingOrder: order, includeObjectRules: objects)
                let (document, evidence) = try fixture(configuration)
                XCTAssertEqual(evidence.run.solverVersion, objects ? "archi-arc-symbolic-v3" : "archi-arc-symbolic-v2")
                XCTAssertTrue(configuration.identity.hasPrefix(objects ? "arc-symbolic-config-v3:" : "arc-symbolic-config-v2:"))
                let encoded = try JSONEncoder().encode(evidence)
                XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("checkedTrainingCellOperations"))
                let loaded = try JSONDecoder().decode(ARCSolverEvidence.self, from: encoded)
                XCTAssertEqual(try ARCSymbolicSolver.solve(document.input, configuration: loaded.configuration), loaded.run)
                XCTAssertNoThrow(try loaded.validate(bundle: document.bundle(run: loaded.run, codeHash: codeHash)))
            }
        }
        // Pre-object-rule configuration decoding still chooses the historical catalog.
        let old = Data(#"{"maxProgramAttempts":1500,"maxCellOperations":2000000,"maxTraceEntries":1500,"trainingOrder":"adaptive"}"#.utf8)
        let decoded = try JSONDecoder().decode(ARCSolverConfiguration.self, from: old)
        XCTAssertFalse(decoded.includeObjectRules)
        XCTAssertEqual(decoded.trainingOrder, .adaptive)
    }

    func testCostEvidenceRoundTripsAndRejectsMissingOrMalformedMeasurements() throws {
        let (document, evidence) = try fixture(.standard)
        let bundle = try document.bundle(run: evidence.run, codeHash: codeHash)
        let bytes = try JSONEncoder().encode(evidence)
        XCTAssertEqual(try JSONDecoder().decode(ARCSolverEvidence.self, from: bytes), evidence)
        XCTAssertNoThrow(try evidence.validate(bundle: bundle))
        for badCost in [nil, [], [-1], [Int.max], [20_000_001]] as [[Int]?] {
            var root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            var run = try XCTUnwrap(root["run"] as? [String: Any])
            var trace = try XCTUnwrap(run["trace"] as? [[String: Any]])
            trace[0]["checkedTrainingCellOperations"] = badCost
            run["trace"] = trace; root["run"] = run
            let forged = try JSONDecoder().decode(ARCSolverEvidence.self, from: JSONSerialization.data(withJSONObject: root))
            XCTAssertThrowsError(try forged.validate(bundle: bundle))
        }
    }

    func testCostBudgetsAndTruncatedTracesRemainValidAbstentions() throws {
        for budget in [0, 1, 30, 31, 40, 77, 78, 100, 500] {
            for traceLimit in [0, 1, 1_500] {
                let (document, evidence) = try fixture(.init(maxCellOperations: budget, maxTraceEntries: traceLimit))
                XCTAssertEqual(evidence.run.outcome, .budgetExhausted)
                XCTAssertNil(evidence.run.predictions)
                XCTAssertNoThrow(try evidence.validate(bundle: document.bundle(run: evidence.run, codeHash: codeHash)))
            }
        }
    }

    func testMeasuredScheduleReplaysAndAnswerKeyCannotInfluenceIt() throws {
        let (document, evidence) = try fixture(.standard)
        XCTAssertEqual(ARCSolverConfiguration.standard.trainingOrder, .costAware)
        XCTAssertEqual(evidence.run.solverVersion, "archi-arc-symbolic-v4")
        XCTAssertEqual(try ARCSymbolicSolver.solve(document.input), evidence.run)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: ARCSolverDocument.sample) as? [String: Any])
        var tests = try XCTUnwrap(root["test"] as? [[String: Any]])
        tests[0]["output"] = [[0]]; root["test"] = tests
        let other = try ARCSolverDocument.parse(JSONSerialization.data(withJSONObject: root), name: "Changed answer key")
        XCTAssertEqual(try ARCSymbolicSolver.solve(other.input), evidence.run)
        XCTAssertThrowsError(try ARCSymbolicSolver.solve(document.input, isCancelled: { true })) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }

    private func fixture(_ configuration: ARCSolverConfiguration) throws -> (ARCSolverDocument, ARCSolverEvidence) {
        let document = try ARCSolverDocument.parse(ARCSolverDocument.sample, name: "Cost-aware synthetic fixture", isSynthetic: true)
        let run = try ARCSymbolicSolver.solve(document.input, configuration: configuration)
        return (document, .init(run: run, configuration: configuration, inputDigest: document.inputDigest,
                                codeHash: codeHash, elapsedMilliseconds: 0))
    }
}
