import XCTest
@testable import ARCHiDesktop

final class HamptonARCTrainingOrderTests: XCTestCase {
    func testStartsWithNoObservationsAndStableInputOrder() throws {
        let state = try HamptonARCTrainingOrder(exampleCount: 4)
        XCTAssertEqual(state.order, [0, 1, 2, 3])
        XCTAssertEqual(state.observationCount, 0)
        XCTAssertEqual(state.order, state.order)
        XCTAssertEqual(state.observationCount, 0, "Reading a schedule cannot invent feedback.")
    }

    func testObservedCounterexampleMovesAheadOfPreviouslyPassingExamples() throws {
        var state = try HamptonARCTrainingOrder(exampleCount: 4)
        try state.observe(index: 0, falsified: false)
        try state.observe(index: 1, falsified: false)
        try state.observe(index: 2, falsified: true)
        XCTAssertEqual(state.order, [2, 3, 0, 1])
        XCTAssertEqual(state.observationCount, 3)
    }

    func testEqualPosteriorFractionsUseStableIndexEvenWithDifferentObservationCounts() throws {
        var state = try HamptonARCTrainingOrder(exampleCount: 2)
        try state.observe(index: 0, falsified: true)
        try state.observe(index: 0, falsified: false)
        XCTAssertEqual(state.order, [0, 1], "Two balanced observations tie the untouched Beta(1,1) prior exactly.")
        try state.observe(index: 0, falsified: false)
        XCTAssertEqual(state.order, [1, 0])
    }

    func testFreshRunsAndValueCopiesDoNotInheritOrShareFeedback() throws {
        var first = try HamptonARCTrainingOrder(exampleCount: 3)
        let copy = first
        try first.observe(index: 2, falsified: true)
        XCTAssertEqual(first.order, [2, 0, 1])
        XCTAssertEqual(copy.order, [0, 1, 2])
        let nextTask = try HamptonARCTrainingOrder(exampleCount: 3)
        XCTAssertEqual(nextTask, copy)
        XCTAssertEqual(nextTask.observationCount, 0)
    }

    func testInvalidIndicesAndObservationOverflowPreservePreviousState() throws {
        XCTAssertThrowsError(try HamptonARCTrainingOrder(exampleCount: 0))
        XCTAssertThrowsError(try HamptonARCTrainingOrder(exampleCount: 21))
        var state = try HamptonARCTrainingOrder(exampleCount: 2)
        let initial = state
        XCTAssertThrowsError(try state.observe(index: -1, falsified: true))
        XCTAssertThrowsError(try state.observe(index: 2, falsified: true))
        XCTAssertEqual(state, initial)
        for _ in 0..<HamptonARCTrainingOrder.maximumObservationsPerExample {
            try state.observe(index: 1, falsified: true)
        }
        let saturated = state
        XCTAssertThrowsError(try state.observe(index: 1, falsified: false))
        XCTAssertEqual(state, saturated)
        XCTAssertEqual(state.observationCount, 1_500)
        XCTAssertEqual(state.order, [1, 0])
    }

    func testReplayedObservedFeedbackReconstructsTheSameSchedule() throws {
        let events: [(Int, Bool)] = [(0, false), (1, true), (1, false), (2, false), (0, true), (1, true)]
        var first = try HamptonARCTrainingOrder(exampleCount: 3)
        var replay = try HamptonARCTrainingOrder(exampleCount: 3)
        for (index, falsified) in events { try first.observe(index: index, falsified: falsified) }
        for (index, falsified) in events { try replay.observe(index: index, falsified: falsified) }
        XCTAssertEqual(first, replay)
        XCTAssertEqual(first.order, replay.order)
        XCTAssertEqual(first.observationCount, events.count)
    }

    func testMatchedAblationUsesFewerChecksWithIdenticalCompleteCandidateDecisions() throws {
        // Controlled comparison outcomes, not a claim about an ARC dataset:
        // 150 rules fail only example 20; the final 20 rules pass every example.
        let rejected = Array(repeating: true, count: 19) + [false]
        let accepted = Array(repeating: true, count: 20)
        let matrix = Array(repeating: rejected, count: 150) + Array(repeating: accepted, count: 20)
        let fixed = try evaluate(matrix, adaptive: false)
        let adaptive = try evaluate(matrix, adaptive: true)
        XCTAssertTrue(fixed.complete)
        XCTAssertTrue(adaptive.complete)
        XCTAssertEqual(fixed.fittingCandidates, Array(150..<170))
        XCTAssertEqual(adaptive.fittingCandidates, fixed.fittingCandidates)
        XCTAssertEqual(fixed.comparisons, 3_400)
        XCTAssertEqual(adaptive.comparisons, 569)

        let boundedFixed = try evaluate(matrix, adaptive: false, budget: 1_000)
        let boundedAdaptive = try evaluate(matrix, adaptive: true, budget: 1_000)
        XCTAssertFalse(boundedFixed.complete, "An incomplete catalog must remain an abstention in the solver.")
        XCTAssertTrue(boundedAdaptive.complete)
        XCTAssertEqual(boundedAdaptive.fittingCandidates, fixed.fittingCandidates)
    }

    func testEveryCandidateMustStillPassEveryExampleAcrossAllFiveBitPatterns() throws {
        let matrix = (0..<32).map { bits in (0..<5).map { bits & (1 << $0) != 0 } }
        let fixed = try evaluate(matrix, adaptive: false)
        let adaptive = try evaluate(matrix, adaptive: true)
        XCTAssertEqual(fixed.fittingCandidates, [31])
        XCTAssertEqual(adaptive.fittingCandidates, [31])
        XCTAssertTrue(adaptive.complete)
        XCTAssertLessThanOrEqual(adaptive.comparisons, matrix.count * matrix[0].count)
    }

    func testNativeSolverAblationPreservesPredictionsAndAllFitsWhileReducingWork() throws {
        // Nineteen non-discriminating demonstrations precede one asymmetric
        // rectangle. Both arms receive these exact grids and the same catalog.
        let symmetric = Array(repeating: Array(repeating: 1, count: 10), count: 10)
        var training = Array(repeating: ARCTrainingPair(input: symmetric, output: symmetric), count: 19)
        training.append(.init(input: [[1, 0, 1], [1, 1, 0]], output: [[1, 1], [1, 0], [0, 1]]))
        let input = ARCSolverInput(training: training, testInputs: [[[3, 4, 3], [3, 3, 4]]])
        let fixed = try ARCSymbolicSolver.solve(input,
            configuration: .init(maxCellOperations: 20_000_000, trainingOrder: .fixed))
        let adaptive = try ARCSymbolicSolver.solve(input,
            configuration: .init(maxCellOperations: 20_000_000, trainingOrder: .adaptive))
        XCTAssertEqual(fixed.outcome, .predicted)
        XCTAssertEqual(adaptive.outcome, fixed.outcome)
        XCTAssertEqual(adaptive.predictions, fixed.predictions)
        XCTAssertEqual(adaptive.predictions, [[[3, 3], [3, 4], [4, 3]]])
        XCTAssertEqual(adaptive.programIDs, fixed.programIDs)
        XCTAssertEqual(adaptive.matchingPrograms, fixed.matchingPrograms)
        XCTAssertEqual(fixed.attemptedPrograms, ARCSymbolicSolver.catalogProgramCount)
        XCTAssertEqual(adaptive.attemptedPrograms, fixed.attemptedPrograms)
        XCTAssertFalse(fixed.traceTruncated)
        XCTAssertFalse(adaptive.traceTruncated)
        let fixedChecks = fixed.trace.reduce(0) { $0 + $1.checkedTrainingIndices.count }
        let adaptiveChecks = adaptive.trace.reduce(0) { $0 + $1.checkedTrainingIndices.count }
        XCTAssertLessThan(adaptiveChecks, fixedChecks)
        XCTAssertLessThan(adaptive.cellOperations, fixed.cellOperations)
        XCTAssertEqual(fixed.trace.first { $0.programID == "rotate90" }?.checkedTrainingIndices.first, 0)
        XCTAssertEqual(adaptive.trace.first { $0.programID == "rotate90" }?.checkedTrainingIndices.first, 19)
        for entry in adaptive.trace {
            XCTAssertEqual(Set(entry.checkedTrainingIndices).count, entry.checkedTrainingIndices.count)
            if entry.status == .matched {
                XCTAssertEqual(Set(entry.checkedTrainingIndices), Set(0..<20), "Scheduling never excuses an unchecked training pair.")
            }
        }
    }

    private struct VerificationResult {
        let fittingCandidates: [Int]
        let comparisons: Int
        let complete: Bool
    }

    /// Test-only candidate/example truth table. Both arms share all observations,
    /// candidates, exact-match decisions, and budget; only example order differs.
    private func evaluate(_ matrix: [[Bool]], adaptive: Bool, budget: Int = 30_000) throws -> VerificationResult {
        var state = try HamptonARCTrainingOrder(exampleCount: matrix[0].count)
        var fitting: [Int] = []
        var comparisons = 0
        for (candidateIndex, outcomes) in matrix.enumerated() {
            let order = adaptive ? state.order : Array(outcomes.indices)
            var fits = true
            for exampleIndex in order {
                guard comparisons < budget else {
                    return .init(fittingCandidates: fitting, comparisons: comparisons, complete: false)
                }
                comparisons += 1
                let falsified = !outcomes[exampleIndex]
                if adaptive { try state.observe(index: exampleIndex, falsified: falsified) }
                if falsified { fits = false; break }
            }
            if fits { fitting.append(candidateIndex) }
        }
        return .init(fittingCandidates: fitting, comparisons: comparisons, complete: true)
    }
}
