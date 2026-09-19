import Foundation
import XCTest
@testable import ARCHiDesktop

final class ARCSymbolicSolverTests: XCTestCase {
    private var rotationTraining: [ARCTrainingPair] { [
        .init(input: [[1, 0, 1], [1, 1, 0]], output: [[1, 1], [1, 0], [0, 1]]),
        .init(input: [[2, 2, 0, 2], [0, 2, 2, 2], [2, 0, 0, 2]],
              output: [[2, 0, 2], [0, 2, 2], [0, 2, 0], [2, 2, 2]]),
    ] }

    func testRectangularRotationPredictsAllHiddenInputsIncludingNovelColors() throws {
        let input = ARCSolverInput(training: rotationTraining,
            testInputs: [[[3, 4, 3], [3, 3, 4]], [[5, 5, 6, 5], [6, 5, 5, 5]]])
        let result = try ARCSymbolicSolver.solve(input)
        XCTAssertEqual(result.outcome, .predicted)
        XCTAssertEqual(result.predictions, [[[3, 3], [3, 4], [4, 3]], [[6, 5], [5, 5], [5, 6], [5, 5]]])
        XCTAssertEqual(result.attemptedPrograms, ARCSymbolicSolver.catalogProgramCount)
        XCTAssertTrue(result.programIDs.contains("rotate90"))
        XCTAssertTrue(result.trace.filter { $0.status == .matched }.allSatisfy { $0.trainingExamplesChecked == 2 })
        XCTAssertLessThan(result.cellOperations, ARCSolverConfiguration.standard.maxCellOperations)
    }

    func testCropThenTrainingDerivedRecolor() throws {
        let result = try ARCSymbolicSolver.solve(.init(training: [
            .init(input: [[0, 0, 0, 0, 0], [0, 1, 1, 0, 0], [0, 0, 1, 2, 0], [0, 2, 1, 1, 0], [0, 0, 0, 0, 0]],
                  output: [[3, 3, 0], [0, 3, 4], [4, 3, 3]])
        ], testInputs: [[[0, 0, 0, 0], [0, 2, 1, 0], [0, 1, 0, 0], [0, 0, 0, 0]]]))
        XCTAssertEqual(result.outcome, .predicted)
        XCTAssertEqual(result.predictions, [[[4, 3], [3, 0]]])
        XCTAssertEqual(result.programIDs, ["cropNonzero>palette:map=0>0,1>3,2>4"])
    }

    func testAllFittingProgramsMustAgreeRatherThanSelectingTheFirst() throws {
        let result = try ARCSymbolicSolver.solve(.init(training: [.init(input: [[1]], output: [[1]])],
            testInputs: [[[1, 2], [3, 4]]]))
        XCTAssertEqual(result.outcome, .ambiguous)
        XCTAssertNil(result.predictions)
        XCTAssertGreaterThan(result.matchingPrograms, 1)
        XCTAssertEqual(result.attemptedPrograms, ARCSymbolicSolver.catalogProgramCount)
        XCTAssertTrue(result.programIDs.contains("identity"))
        XCTAssertTrue(result.programIDs.contains("rotate90"))
    }

    func testUnseenColorUnderChangedPaletteAbstains() throws {
        let result = try ARCSymbolicSolver.solve(.init(training: [.init(input: [[1, 1], [1, 1]], output: [[2, 2], [2, 2]])],
            testInputs: [[[3, 3], [3, 3]]]))
        XCTAssertEqual(result.outcome, .ambiguous)
        XCTAssertNil(result.predictions)
        XCTAssertGreaterThan(result.matchingPrograms, 0)
        XCTAssertTrue(result.trace.contains { $0.status == .predictionUndefined })
    }

    func testNoTrainingFitAbstains() throws {
        let result = try ARCSymbolicSolver.solve(.init(training: [.init(input: [[1, 1], [1, 1]], output: [[1, 2], [3, 4]])],
            testInputs: [[[1]]]))
        XCTAssertEqual(result.outcome, .noMatch)
        XCTAssertNil(result.predictions)
        XCTAssertEqual(result.matchingPrograms, 0)
    }

    func testSecondTrainingPairCanRejectAnOtherwiseFittingRule() throws {
        let result = try ARCSymbolicSolver.solve(.init(training: [
            .init(input: [[1]], output: [[2]]), .init(input: [[1]], output: [[3]])
        ], testInputs: [[[1]]]))
        XCTAssertEqual(result.outcome, .noMatch)
        XCTAssertTrue(result.trace.contains { $0.trainingExamplesChecked == 2 && $0.status == .trainingMismatch })
    }

    func testScaleAndTileAreDistinguishedByTrainingPattern() throws {
        let base = [[1, 2], [2, 2]]
        let inputs = [[[3, 4], [4, 4]]]
        let scaled = try ARCSymbolicSolver.solve(.init(training: [.init(input: base,
            output: [[1, 1, 2, 2], [1, 1, 2, 2], [2, 2, 2, 2], [2, 2, 2, 2]])], testInputs: inputs))
        XCTAssertEqual(scaled.outcome, .predicted)
        XCTAssertEqual(scaled.predictions, [[[3, 3, 4, 4], [3, 3, 4, 4], [4, 4, 4, 4], [4, 4, 4, 4]]])
        let tiled = try ARCSymbolicSolver.solve(.init(training: [.init(input: base,
            output: [[1, 2, 1, 2], [2, 2, 2, 2], [1, 2, 1, 2], [2, 2, 2, 2]])], testInputs: inputs))
        XCTAssertEqual(tiled.outcome, .predicted)
        XCTAssertEqual(tiled.predictions, [[[3, 4, 3, 4], [4, 4, 4, 4], [3, 4, 3, 4], [4, 4, 4, 4]]])
    }

    func testUndefinedIntermediateDimensionsForceAbstention() throws {
        let result = try ARCSymbolicSolver.solve(.init(training: [.init(input: [[1]], output: [[1, 1], [1, 1]])],
            testInputs: [Array(repeating: Array(repeating: 1, count: 16), count: 16)]))
        XCTAssertEqual(result.outcome, .ambiguous)
        XCTAssertNil(result.predictions)
        XCTAssertTrue(result.trace.contains { $0.status == .predictionUndefined })
    }

    func testProgramBudgetCannotReturnAnEarlyIdentityFit() throws {
        let result = try ARCSymbolicSolver.solve(.init(training: [.init(input: [[1]], output: [[1]])], testInputs: [[[1]]]),
            configuration: .init(maxProgramAttempts: 1))
        XCTAssertEqual(result.outcome, .budgetExhausted)
        XCTAssertEqual(result.attemptedPrograms, 1)
        XCTAssertEqual(result.matchingPrograms, 1)
        XCTAssertNil(result.predictions)
    }

    func testCellBudgetAndTraceLimitsStayBounded() throws {
        let input = ARCSolverInput(training: rotationTraining, testInputs: [[[3, 4, 3], [3, 3, 4]]])
        let limited = try ARCSymbolicSolver.solve(input, configuration: .init(maxCellOperations: 100, maxTraceEntries: 1))
        XCTAssertEqual(limited.outcome, .budgetExhausted)
        XCTAssertNil(limited.predictions)
        XCTAssertLessThanOrEqual(limited.cellOperations, 100)
        XCTAssertLessThanOrEqual(limited.trace.count, 1)
        let noTrace = try ARCSymbolicSolver.solve(input, configuration: .init(maxTraceEntries: 0))
        XCTAssertEqual(noTrace.outcome, .predicted)
        XCTAssertEqual(noTrace.trace, [])
        XCTAssertTrue(noTrace.traceTruncated)
        // Exhaustion during consensus comparison still emits only one trace entry
        // for the current candidate, with no earlier successful duplicate.
        for cells in 3...150 {
            let prefix = try ARCSymbolicSolver.solve(.init(training: [.init(input: [[1]], output: [[1]])], testInputs: [[[1]]]),
                configuration: .init(maxCellOperations: cells))
            XCTAssertEqual(prefix.outcome, .budgetExhausted)
            XCTAssertLessThanOrEqual(prefix.trace.count, prefix.attemptedPrograms)
            XCTAssertEqual(Set(prefix.trace.map(\.programID)).count, prefix.trace.count)
        }
    }

    func testCancellationBeforeAndDuringSearchThrowsWithoutPredictions() throws {
        let input = ARCSolverInput(training: rotationTraining, testInputs: [[[3, 4, 3], [3, 3, 4]]])
        XCTAssertThrowsError(try ARCSymbolicSolver.solve(input, isCancelled: { true })) { XCTAssertTrue($0 is CancellationError) }
        let probe = CancellationProbe(limit: 100)
        XCTAssertThrowsError(try ARCSymbolicSolver.solve(input, isCancelled: { probe.check() })) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertGreaterThan(probe.calls, 100)
    }

    func testSemanticReproducibilityIncludesConfigurationAndLearnedProgramIDs() throws {
        let input = ARCSolverInput(training: rotationTraining, testInputs: [[[3, 4, 3], [3, 3, 4]]])
        let first = try ARCSymbolicSolver.solve(input)
        let second = try ARCSymbolicSolver.solve(input)
        XCTAssertEqual(first, second)
        XCTAssertEqual(try JSONDecoder().decode(ARCSolverRun.self, from: JSONEncoder().encode(first)), first)
        XCTAssertEqual(first.solverVersion, ARCSymbolicSolver.version)
        XCTAssertEqual(first.catalogIdentity, ARCSymbolicSolver.catalogIdentity)
        XCTAssertEqual(first.configurationIdentity, ARCSolverConfiguration.standard.identity)
        XCTAssertEqual(ARCSymbolicSolver.catalogProgramCount, 174)
        XCTAssertEqual(Set(first.trace.map(\.programID)).count, first.trace.count)
    }

    func testMalformedGridsAndUnboundedConfigurationAreRejected() throws {
        let badGrids: [ARCGrid] = [[], [[]], [[1], [2, 3]], [[-1]], [[10]], Array(repeating: [1], count: 31), [Array(repeating: 1, count: 31)]]
        for grid in badGrids {
            XCTAssertThrowsError(try ARCSymbolicSolver.solve(.init(training: [.init(input: grid, output: [[1]])], testInputs: [[[1]]])))
            XCTAssertThrowsError(try ARCSymbolicSolver.solve(.init(training: [.init(input: [[1]], output: grid)], testInputs: [[[1]]])))
            XCTAssertThrowsError(try ARCSymbolicSolver.solve(.init(training: [.init(input: [[1]], output: [[1]])], testInputs: [grid])))
        }
        let valid = ARCSolverInput(training: [.init(input: [[1]], output: [[1]])], testInputs: [[[1]]])
        XCTAssertThrowsError(try ARCSymbolicSolver.solve(.init(training: [], testInputs: [[[1]]])))
        XCTAssertThrowsError(try ARCSymbolicSolver.solve(.init(training: valid.training, testInputs: [])))
        XCTAssertThrowsError(try ARCSymbolicSolver.solve(.init(training: Array(repeating: valid.training[0], count: 21), testInputs: valid.testInputs)))
        XCTAssertThrowsError(try ARCSymbolicSolver.solve(valid, configuration: .init(maxProgramAttempts: 1_501)))
        XCTAssertThrowsError(try ARCSymbolicSolver.solve(valid, configuration: .init(maxCellOperations: 20_000_001)))
        XCTAssertThrowsError(try ARCSymbolicSolver.solve(valid, configuration: .init(maxTraceEntries: -1)))
    }
}

private final class CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var count = 0
    init(limit: Int) { self.limit = limit }
    var calls: Int { lock.withLock { count } }
    func check() -> Bool {
        lock.withLock {
            count += 1
            return count > limit
        }
    }
}
