import Foundation
import XCTest
@testable import ARCHiDesktop

final class ARCObjectSolverIntegrationTests: XCTestCase {
    // Two training shapes with external distractors. The test changes color and
    // location; selecting the largest component must precede its bounding crop.
    private var objectTask: ARCSolverInput {
        .init(training: [
            .init(input: [[0,0,0,0,3], [0,2,2,0,0], [0,2,0,0,0], [0,0,0,0,0]],
                  output: [[2,2], [2,0]]),
            .init(input: [[4,0,0,0,0], [0,0,0,5,0], [0,0,5,5,0], [0,0,0,5,0]],
                  output: [[0,5], [5,5], [0,5]])
        ], testInputs: [[[7,7,7,0,0], [0,7,0,0,0], [0,0,0,0,8]]])
    }

    func testRecoveredObjectRuleSolvesNovelColorTaskBeyondGeometryBaseline() throws {
        let baseline = try ARCSymbolicSolver.solve(objectTask, configuration: .geometryBaseline)
        XCTAssertEqual(baseline.outcome, .noMatch)
        let upgraded = try ARCSymbolicSolver.solve(objectTask)
        XCTAssertEqual(upgraded.outcome, .predicted)
        XCTAssertEqual(upgraded.predictions, [[[7,7,7], [0,7,0]]])
        XCTAssertEqual(upgraded.programIDs, ["cropLargest"])
        XCTAssertEqual(upgraded.attemptedPrograms, 174)
        XCTAssertEqual(Array(upgraded.trace.prefix(170)), baseline.trace)
        XCTAssertEqual(upgraded.solverVersion, "archi-arc-symbolic-v3")
    }

    func testObjectWorkCannotRunPastCellOrAttemptBudget() throws {
        let baseline = try ARCSymbolicSolver.solve(objectTask, configuration: .geometryBaseline)
        for configuration in [ARCSolverConfiguration(maxProgramAttempts: 170),
                              ARCSolverConfiguration(maxCellOperations: baseline.cellOperations)] {
            let result = try ARCSymbolicSolver.solve(objectTask, configuration: configuration)
            XCTAssertEqual(result.outcome, .budgetExhausted)
            XCTAssertNil(result.predictions)
            XCTAssertLessThanOrEqual(result.cellOperations, configuration.maxCellOperations)
        }
    }

    func testObjectPredictionIsFrozenIndependentlyOfTestTarget() throws {
        let task = objectTask
        var runs: [ARCSolverRun] = []
        var exact: [Int] = []
        for target in [[[7,7,7], [0,7,0]], [[9]]] {
            let bytes = try JSONSerialization.data(withJSONObject: [
                "train": task.training.map { ["input": $0.input, "output": $0.output] },
                "test": [["input": task.testInputs[0], "output": target]]
            ])
            let document = try ARCSolverDocument.parse(bytes, name: "Synthetic object selection", isSynthetic: true)
            let run = try ARCSymbolicSolver.solve(document.input)
            let hash = "sha256:" + String(repeating: "a", count: 64)
            let bundle = try document.bundle(run: run, codeHash: hash)
            let evidence = ARCSolverEvidence(run: run, configuration: .standard, inputDigest: document.inputDigest,
                                             codeHash: hash, elapsedMilliseconds: 1)
            XCTAssertNoThrow(try evidence.validate(bundle: bundle))
            runs.append(run)
            exact.append(try ARCCapabilitiesEvaluator.evaluate(bundle).counts.exact)
        }
        XCTAssertEqual(runs[0], runs[1])
        XCTAssertEqual(exact, [1, 0])
    }
}
