import Foundation

typealias ARCGrid = [[Int]]

struct ARCTrainingPair: Codable, Equatable, Sendable {
    let input: ARCGrid
    let output: ARCGrid
}

/// The solver boundary deliberately has no field for a test answer.
struct ARCSolverInput: Codable, Equatable, Sendable {
    let training: [ARCTrainingPair]
    let testInputs: [ARCGrid]
}

struct ARCSolverConfiguration: Codable, Equatable, Sendable {
    enum TrainingOrder: String, Codable, Equatable, Sendable { case fixed, adaptive }
    let maxProgramAttempts: Int
    let maxCellOperations: Int
    let maxTraceEntries: Int
    let trainingOrder: TrainingOrder
    let includeObjectRules: Bool

    init(maxProgramAttempts: Int = 1_500, maxCellOperations: Int = 2_000_000, maxTraceEntries: Int = 1_500,
         trainingOrder: TrainingOrder = .adaptive, includeObjectRules: Bool = true) {
        self.maxProgramAttempts = maxProgramAttempts
        self.maxCellOperations = maxCellOperations
        self.maxTraceEntries = maxTraceEntries
        self.trainingOrder = trainingOrder
        self.includeObjectRules = includeObjectRules
    }

    static let standard = ARCSolverConfiguration()
    static let geometryBaseline = ARCSolverConfiguration(includeObjectRules: false)

    private enum CodingKeys: String, CodingKey {
        case maxProgramAttempts, maxCellOperations, maxTraceEntries, trainingOrder, includeObjectRules
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        maxProgramAttempts = try values.decode(Int.self, forKey: .maxProgramAttempts)
        maxCellOperations = try values.decode(Int.self, forKey: .maxCellOperations)
        maxTraceEntries = try values.decode(Int.self, forKey: .maxTraceEntries)
        trainingOrder = try values.decode(TrainingOrder.self, forKey: .trainingOrder)
        // Old records predate object rules and must replay their exact language.
        includeObjectRules = try values.decodeIfPresent(Bool.self, forKey: .includeObjectRules) ?? false
    }

    var identity: String {
        "arc-symbolic-config-\(includeObjectRules ? "v3" : "v2"):attempts=\(maxProgramAttempts):cells=\(maxCellOperations):trace=\(maxTraceEntries):order=\(trainingOrder.rawValue)"
    }
}

struct ARCSolverTraceEntry: Codable, Equatable, Sendable {
    enum Status: String, Codable, Equatable, Sendable {
        case trainingMismatch, trainingUndefined, redundantPalette, matched, predictionUndefined, budgetExhausted
    }

    let programID: String
    let status: Status
    let trainingExamplesChecked: Int
    /// Frozen training-pair addresses actually visited, in execution order.
    let checkedTrainingIndices: [Int]
}

struct ARCSolverRun: Codable, Equatable, Sendable {
    enum Outcome: String, Codable, Equatable, Sendable {
        case predicted, ambiguous, noMatch, budgetExhausted
    }

    let outcome: Outcome
    let predictions: [ARCGrid]?
    let attemptedPrograms: Int
    let matchingPrograms: Int
    /// Every program fitting all training pairs, including ones undefined on a test input.
    let programIDs: [String]
    let trace: [ARCSolverTraceEntry]
    let traceTruncated: Bool
    let cellOperations: Int
    let solverVersion: String
    let catalogIdentity: String
    let configurationIdentity: String
}

enum ARCSolverError: LocalizedError, Equatable {
    case invalidInput(String)
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message), .invalidConfiguration(let message): message
        }
    }
}

/// Fixed, finite program search. This is a small hypothesis language, not an ARC benchmark claim.
/// Training fits are retained only after all pairs agree. Predictions require complete search
/// and agreement among *all* fits, including rejection when any fit is undefined on a test.
enum ARCSymbolicSolver {
    static let version = "archi-arc-symbolic-v3"
    private static let geometryCatalogIdentity = "arc-dsl-v1:identity;d4;crop-nonzero;scale2,3;tile2,3;geometry-depth2;changed-palette-last-depth2;unseen-undefined"
    static let catalogIdentity = geometryCatalogIdentity + ";objects4:cropLargest,cropSmallest,keepLargest,keepSmallest;zero-background;same-color-four-connected;sort-negative-area-color-bbox"
    static var catalogProgramCount: Int { catalog.count + objectCatalog.count }
    static func version(for configuration: ARCSolverConfiguration) -> String {
        configuration.includeObjectRules ? version : "archi-arc-symbolic-v2"
    }
    static func catalogIdentity(for configuration: ARCSolverConfiguration) -> String {
        configuration.includeObjectRules ? catalogIdentity : geometryCatalogIdentity
    }
    static func catalogProgramCount(for configuration: ARCSolverConfiguration) -> Int {
        catalog.count + (configuration.includeObjectRules ? objectCatalog.count : 0)
    }

    static func solve(
        _ input: ARCSolverInput,
        configuration: ARCSolverConfiguration = .standard,
        isCancelled: @Sendable () -> Bool = { false }
    ) throws -> ARCSolverRun {
        try checkCancellation(isCancelled)
        guard (0...1_500).contains(configuration.maxProgramAttempts),
              (0...20_000_000).contains(configuration.maxCellOperations),
              (0...1_500).contains(configuration.maxTraceEntries) else {
            throw ARCSolverError.invalidConfiguration("Solver limits exceed the bounded configuration contract.")
        }
        var budget = Budget(limit: configuration.maxCellOperations)
        var attempted = 0
        var fittingIDs: [String] = []
        var trace: [ARCSolverTraceEntry] = []
        var traceTruncated = false
        var consensus: [ARCGrid]?
        var ambiguous = false

        func appendTrace(_ entry: ARCSolverTraceEntry) {
            if trace.count < configuration.maxTraceEntries { trace.append(entry) }
            else { traceTruncated = true }
        }

        func result(_ outcome: ARCSolverRun.Outcome) -> ARCSolverRun {
            ARCSolverRun(outcome: outcome, predictions: outcome == .predicted ? consensus : nil,
                attemptedPrograms: attempted, matchingPrograms: fittingIDs.count, programIDs: fittingIDs,
                trace: trace, traceTruncated: traceTruncated, cellOperations: budget.used,
                solverVersion: version(for: configuration), catalogIdentity: catalogIdentity(for: configuration), configurationIdentity: configuration.identity)
        }

        do {
            try validate(input, budget: &budget, isCancelled: isCancelled)
            var trainingOrder = try HamptonARCTrainingOrder(exampleCount: input.training.count)
            let programs = catalog + (configuration.includeObjectRules ? objectCatalog : [])
            for program in programs {
                try checkCancellation(isCancelled)
                guard attempted < configuration.maxProgramAttempts else { throw BudgetExhausted() }
                attempted += 1
                var checked = 0
                var checkedIndices: [Int] = []
                do {
                    var palette = [Int?](repeating: nil, count: 10)
                    var rejection: ARCSolverTraceEntry.Status?
                    // Freeze this candidate's order. Feedback affects only later
                    // candidates, never the pass condition or hidden test answers.
                    let indices = configuration.trainingOrder == .adaptive ? trainingOrder.order : Array(input.training.indices)
                    for index in indices {
                        let example = input.training[index]
                        try checkCancellation(isCancelled)
                        checkedIndices.append(index)
                        guard let transformed = try transform(example.input, steps: program.steps, budget: &budget, isCancelled: isCancelled) else {
                            rejection = .trainingUndefined
                            try trainingOrder.observe(index: index, falsified: true)
                            break
                        }
                        checked += 1
                        guard sameDimensions(transformed, example.output) else {
                            rejection = .trainingMismatch
                            try trainingOrder.observe(index: index, falsified: true)
                            break
                        }
                        if program.learnPalette {
                            guard try extendPalette(&palette, source: transformed, target: example.output, budget: &budget, isCancelled: isCancelled) else {
                                rejection = .trainingMismatch
                                try trainingOrder.observe(index: index, falsified: true)
                                break
                            }
                        } else if try !equal(transformed, example.output, budget: &budget, isCancelled: isCancelled) {
                            rejection = .trainingMismatch
                            try trainingOrder.observe(index: index, falsified: true)
                            break
                        }
                        try trainingOrder.observe(index: index, falsified: false)
                    }
                    if let rejection {
                        appendTrace(.init(programID: program.id, status: rejection, trainingExamplesChecked: checked, checkedTrainingIndices: checkedIndices))
                        continue
                    }
                    // Do not add a redundant partial identity palette to a geometric fit. This
                    // explicit language bias lets plain geometry handle previously unseen colors.
                    if program.learnPalette && !palette.enumerated().contains(where: { $0.element != nil && $0.element != $0.offset }) {
                        appendTrace(.init(programID: program.id, status: .redundantPalette, trainingExamplesChecked: checked, checkedTrainingIndices: checkedIndices))
                        continue
                    }
                    let id = program.id + (program.learnPalette ? paletteSuffix(palette) : "")
                    fittingIDs.append(id)
                    var predictions: [ARCGrid] = []
                    var defined = true
                    for test in input.testInputs {
                        try checkCancellation(isCancelled)
                        guard var prediction = try transform(test, steps: program.steps, budget: &budget, isCancelled: isCancelled) else {
                            defined = false
                            break
                        }
                        if program.learnPalette {
                            guard let mapped = try applyPalette(palette, to: prediction, budget: &budget, isCancelled: isCancelled) else {
                                defined = false
                                break
                            }
                            prediction = mapped
                        }
                        predictions.append(prediction)
                    }
                    if !defined { ambiguous = true }
                    else if let existing = consensus {
                        for (lhs, rhs) in zip(existing, predictions) {
                            if try !equal(lhs, rhs, budget: &budget, isCancelled: isCancelled) { ambiguous = true }
                        }
                    } else { consensus = predictions }
                    appendTrace(.init(programID: id, status: defined ? .matched : .predictionUndefined, trainingExamplesChecked: checked, checkedTrainingIndices: checkedIndices))
                } catch is BudgetExhausted {
                    appendTrace(.init(programID: program.id, status: .budgetExhausted, trainingExamplesChecked: checked, checkedTrainingIndices: checkedIndices))
                    throw BudgetExhausted()
                }
            }
            try checkCancellation(isCancelled)
            if fittingIDs.isEmpty { return result(.noMatch) }
            return result(ambiguous || consensus == nil ? .ambiguous : .predicted)
        } catch is BudgetExhausted {
            // A prefix of the language cannot establish consensus over the entire language.
            return result(.budgetExhausted)
        }
    }

    /// A separately admitted single proposal. This does not enter the catalog,
    /// establish catalog consensus, or change historical symbolic replay.
    static func evaluateProposal(
        _ input: ARCSolverInput, steps: [ARCProposalOperation], learnPalette: Bool,
        isCancelled: @Sendable () -> Bool = { false }
    ) throws -> ARCProposalEvaluation {
        try checkCancellation(isCancelled)
        guard steps.count <= 3 else { throw ARCSolverError.invalidConfiguration("A proposal supports at most three operations.") }
        let operations = try steps.map { operation -> Step in
            guard let step = Step(rawValue: operation.rawValue) else {
                throw ARCSolverError.invalidConfiguration("Unsupported proposal operation.")
            }
            return step
        }
        var budget = Budget(limit: 2_000_000), passed = 0
        func result(_ status: ARCProposalStatus, predictions: [ARCGrid]? = nil) -> ARCProposalEvaluation {
            .init(status: status, trainingPassed: passed, trainingCount: input.training.count,
                  predictions: predictions, cellOperations: budget.used)
        }
        do {
            try validate(input, budget: &budget, isCancelled: isCancelled)
            var palette = [Int?](repeating: nil, count: 10)
            var failure: ARCProposalStatus?
            // Visit every training pair, even after a rejection. Test transforms
            // remain unreachable unless the entire training set passes.
            for example in input.training {
                try checkCancellation(isCancelled)
                guard let transformed = try transform(example.input, steps: operations, budget: &budget, isCancelled: isCancelled) else {
                    failure = failure ?? .trainingUndefined
                    continue
                }
                guard sameDimensions(transformed, example.output) else {
                    failure = failure ?? .trainingMismatch
                    continue
                }
                let matches: Bool
                if learnPalette {
                    matches = try extendPalette(&palette, source: transformed, target: example.output, budget: &budget, isCancelled: isCancelled)
                } else {
                    matches = try equal(transformed, example.output, budget: &budget, isCancelled: isCancelled)
                }
                if matches { passed += 1 } else { failure = failure ?? .trainingMismatch }
            }
            if let failure { return result(failure) }
            var predictions: [ARCGrid] = []
            for test in input.testInputs {
                try checkCancellation(isCancelled)
                guard var prediction = try transform(test, steps: operations, budget: &budget, isCancelled: isCancelled) else {
                    return result(.predictionUndefined)
                }
                if learnPalette {
                    guard let mapped = try applyPalette(palette, to: prediction, budget: &budget, isCancelled: isCancelled) else {
                        return result(.predictionUndefined)
                    }
                    prediction = mapped
                }
                predictions.append(prediction)
            }
            try checkCancellation(isCancelled)
            return result(.predicted, predictions: predictions)
        } catch is BudgetExhausted {
            return result(.budgetExhausted)
        }
    }

    /// Input-only preflight for the proposal request; no candidate is executed.
    static func validateProposalInput(_ input: ARCSolverInput, isCancelled: @Sendable () -> Bool = { false }) throws {
        var budget = Budget(limit: 2_000_000)
        try validate(input, budget: &budget, isCancelled: isCancelled)
    }

    private enum Step: String, CaseIterable, Sendable {
        case rotate90, rotate180, rotate270, reflectRows, reflectColumns, transpose, antiTranspose
        case cropNonzero, scale2, scale3, tile2, tile3
        case cropLargest, cropSmallest, keepLargest, keepSmallest
        var objectOperation: ARCObjectOperators.Operation? { .init(rawValue: rawValue) }
    }

    private struct Program: Sendable {
        let steps: [Step]
        let learnPalette: Bool
        var id: String {
            let geometry = steps.isEmpty ? "identity" : steps.map(\.rawValue).joined(separator: ">")
            return geometry + (learnPalette ? ">palette" : "")
        }
    }

    private static let catalog: [Program] = {
        let primitives = Step.allCases.filter { $0.objectOperation == nil }
        var programs = [Program(steps: [], learnPalette: false)]
        programs += primitives.map { Program(steps: [$0], learnPalette: false) }
        for first in primitives {
            for second in primitives { programs.append(Program(steps: [first, second], learnPalette: false)) }
        }
        programs.append(Program(steps: [], learnPalette: true))
        programs += primitives.map { Program(steps: [$0], learnPalette: true) }
        return programs
    }()

    // Keep the historical 170 candidates in their original order. Object rules are
    // standalone extensions, not an unbounded composition expansion.
    private static let objectCatalog = Step.allCases.filter { $0.objectOperation != nil }
        .map { Program(steps: [$0], learnPalette: false) }

    private struct BudgetExhausted: Error {}

    /// Charges bounded grid reads/writes before allocation or traversal. Equality is charged
    /// for its full grid even if it could stop early, keeping accounting platform independent.
    private struct Budget {
        let limit: Int
        var used = 0
        mutating func consume(_ count: Int, isCancelled: @Sendable () -> Bool) throws {
            try checkCancellation(isCancelled)
            guard count <= limit - used else { throw BudgetExhausted() }
            used += count
        }
    }

    private static func checkCancellation(_ isCancelled: @Sendable () -> Bool) throws {
        if isCancelled() || Task<Never, Never>.isCancelled { throw CancellationError() }
    }

    private static func validate(_ input: ARCSolverInput, budget: inout Budget, isCancelled: @Sendable () -> Bool) throws {
        guard (1...20).contains(input.training.count), (1...20).contains(input.testInputs.count) else {
            throw ARCSolverError.invalidInput("Solver input requires 1–20 training pairs and 1–20 test inputs.")
        }
        for pair in input.training {
            try validate(pair.input, budget: &budget, isCancelled: isCancelled)
            try validate(pair.output, budget: &budget, isCancelled: isCancelled)
        }
        for grid in input.testInputs { try validate(grid, budget: &budget, isCancelled: isCancelled) }
    }

    private static func validate(_ grid: ARCGrid, budget: inout Budget, isCancelled: @Sendable () -> Bool) throws {
        guard (1...30).contains(grid.count), let width = grid.first?.count, (1...30).contains(width) else {
            throw ARCSolverError.invalidInput("ARC grids must have 1–30 rows and columns.")
        }
        for row in grid {
            try checkCancellation(isCancelled)
            guard row.count == width else { throw ARCSolverError.invalidInput("ARC grids must be rectangular.") }
            try budget.consume(width, isCancelled: isCancelled)
            guard row.allSatisfy({ (0...9).contains($0) }) else {
                throw ARCSolverError.invalidInput("ARC cells must be integers from 0 through 9.")
            }
        }
    }

    private static func sameDimensions(_ lhs: ARCGrid, _ rhs: ARCGrid) -> Bool {
        lhs.count == rhs.count && lhs[0].count == rhs[0].count
    }

    private static func equal(_ lhs: ARCGrid, _ rhs: ARCGrid, budget: inout Budget, isCancelled: @Sendable () -> Bool) throws -> Bool {
        guard sameDimensions(lhs, rhs) else { return false }
        try budget.consume(lhs.count * lhs[0].count * 2, isCancelled: isCancelled)
        for index in lhs.indices {
            try checkCancellation(isCancelled)
            if lhs[index] != rhs[index] { return false }
        }
        return true
    }

    private static func transform(_ grid: ARCGrid, steps: [Step], budget: inout Budget, isCancelled: @Sendable () -> Bool) throws -> ARCGrid? {
        var current = grid
        for step in steps {
            guard let next = try apply(step, to: current, budget: &budget, isCancelled: isCancelled) else { return nil }
            current = next
        }
        return current
    }

    private static func apply(_ step: Step, to grid: ARCGrid, budget: inout Budget, isCancelled: @Sendable () -> Bool) throws -> ARCGrid? {
        let height = grid.count
        let width = grid[0].count
        if let operation = step.objectOperation {
            // Fixed conservative work units for extraction, selection and rendering.
            try budget.consume(height * width * 20, isCancelled: isCancelled)
            return try ARCObjectOperators.apply(operation, to: grid, isCancelled: isCancelled)
        }
        if step == .cropNonzero {
            try budget.consume(height * width * 2, isCancelled: isCancelled)
            var minRow = height, maxRow = -1, minColumn = width, maxColumn = -1
            for row in 0..<height {
                try checkCancellation(isCancelled)
                for column in 0..<width where grid[row][column] != 0 {
                    minRow = min(minRow, row); maxRow = max(maxRow, row)
                    minColumn = min(minColumn, column); maxColumn = max(maxColumn, column)
                }
            }
            // There is no nonempty bounding box for an all-background input.
            guard maxRow >= minRow, maxColumn >= minColumn else { return nil }
            return (minRow...maxRow).map { Array(grid[$0][minColumn...maxColumn]) }
        }
        let swapsAxes = [.rotate90, .rotate270, .transpose, .antiTranspose].contains(step)
        let factor = [.scale2, .tile2].contains(step) ? 2 : ([.scale3, .tile3].contains(step) ? 3 : 1)
        let outputHeight = (swapsAxes ? width : height) * factor
        let outputWidth = (swapsAxes ? height : width) * factor
        guard outputHeight <= 30, outputWidth <= 30 else { return nil }
        try budget.consume(height * width + outputHeight * outputWidth, isCancelled: isCancelled)
        var result = Array(repeating: Array(repeating: 0, count: outputWidth), count: outputHeight)
        for row in 0..<outputHeight {
            try checkCancellation(isCancelled)
            for column in 0..<outputWidth {
                let source: (Int, Int)
                switch step {
                case .rotate90: source = (height - 1 - column, row)
                case .rotate180: source = (height - 1 - row, width - 1 - column)
                case .rotate270: source = (column, width - 1 - row)
                case .reflectRows: source = (height - 1 - row, column)
                case .reflectColumns: source = (row, width - 1 - column)
                case .transpose: source = (column, row)
                case .antiTranspose: source = (height - 1 - column, width - 1 - row)
                case .scale2, .scale3: source = (row / factor, column / factor)
                case .tile2, .tile3: source = (row % height, column % width)
                case .cropNonzero, .cropLargest, .cropSmallest, .keepLargest, .keepSmallest:
                    preconditionFailure("Object and bounding-box rules are handled above.")
                }
                result[row][column] = grid[source.0][source.1]
            }
        }
        return result
    }

    private static func extendPalette(_ palette: inout [Int?], source: ARCGrid, target: ARCGrid, budget: inout Budget, isCancelled: @Sendable () -> Bool) throws -> Bool {
        try budget.consume(source.count * source[0].count * 2, isCancelled: isCancelled)
        for row in source.indices {
            try checkCancellation(isCancelled)
            for column in source[row].indices {
                let original = source[row][column], replacement = target[row][column]
                if let existing = palette[original], existing != replacement { return false }
                palette[original] = replacement
            }
        }
        return true
    }

    private static func applyPalette(_ palette: [Int?], to grid: ARCGrid, budget: inout Budget, isCancelled: @Sendable () -> Bool) throws -> ARCGrid? {
        try budget.consume(grid.count * grid[0].count * 2, isCancelled: isCancelled)
        var result = grid
        for row in grid.indices {
            try checkCancellation(isCancelled)
            for column in grid[row].indices {
                guard let replacement = palette[grid[row][column]] else { return nil }
                result[row][column] = replacement
            }
        }
        return result
    }

    private static func paletteSuffix(_ palette: [Int?]) -> String {
        ":map=" + palette.enumerated().compactMap { color, replacement in
            replacement.map { "\(color)>\($0)" }
        }.joined(separator: ",")
    }
}
