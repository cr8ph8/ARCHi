import Foundation

enum HamptonARCTrainingOrderError: Error, Equatable {
    case invalidExampleCount
    case invalidExampleIndex
    case observationLimitExceeded
    case missingCellOperations
    case invalidCellOperations
    case unexpectedCellOperations
}

/// Task-local feedback about which training examples falsify candidate programs.
///
/// Adapted from Qi Experiments' frozen-proposer / Beta-Bernoulli critic mechanism
/// (`qi_experiments/critic.py`, BetaCell and TabularBetaCritic). Here a successful
/// check means finding a counterexample, not predicting an unknown test answer.
/// It changes verification order only: it cannot add, accept, or discard a rule.
///
/// Create fresh state for every solve. Freeze `order` once per candidate and
/// observe only comparisons actually performed by the deterministic evaluator.
/// No grid, test target, task label, prior run, file, provider, or clock is read.
struct HamptonARCTrainingOrder: Equatable, Sendable {
    static let maximumExamples = 20
    static let maximumObservationsPerExample = 1_500
    static let maximumCellOperationsPerCheck = 20_000_000
    static let version = "hampton-arc-training-order-v1-beta11"
    static let costAwareVersion = "hampton-arc-training-order-v2-cost-beta11"

    private let costAware: Bool
    private var checks: [Int]
    private var falsifications: [Int]
    private var observedCellOperations: [Int64]

    init(exampleCount: Int, costAware: Bool = false) throws {
        guard (1...Self.maximumExamples).contains(exampleCount) else {
            throw HamptonARCTrainingOrderError.invalidExampleCount
        }
        self.costAware = costAware
        checks = Array(repeating: 0, count: exampleCount)
        falsifications = Array(repeating: 0, count: exampleCount)
        observedCellOperations = Array(repeating: 0, count: exampleCount)
    }

    var observationCount: Int { checks.reduce(0, +) }

    /// Descending Beta(1,1) posterior mean: (falsifications + 1) / (checks + 2).
    /// The opt-in v2 mode divides that posterior by estimated cell operations.
    /// Its estimate is ceil((observed operations + 1) / (checks + 1)), floored
    /// at one: a one-operation, one-observation prior keeps unseen checks usable.
    /// Bounded integer cross-products avoid floating-point/platform tie drift.
    /// This is a scheduling heuristic, not calibrated confidence or authority.
    var order: [Int] {
        checks.indices.sorted { lhs, rhs in
            let left = Int64(falsifications[lhs] + 1) * Int64(checks[rhs] + 2) * estimatedCost(at: rhs)
            let right = Int64(falsifications[rhs] + 1) * Int64(checks[lhs] + 2) * estimatedCost(at: lhs)
            return left == right ? lhs < rhs : left > right
        }
    }

    /// Only completed deterministic comparisons supply observations. An absent
    /// cost is unknown, not zero; rejected observations leave every counter intact.
    mutating func observe(index: Int, falsified: Bool, cellOperations: Int? = nil) throws {
        guard checks.indices.contains(index) else {
            throw HamptonARCTrainingOrderError.invalidExampleIndex
        }
        guard checks[index] < Self.maximumObservationsPerExample else {
            throw HamptonARCTrainingOrderError.observationLimitExceeded
        }
        if costAware {
            guard let cellOperations else {
                throw HamptonARCTrainingOrderError.missingCellOperations
            }
            guard (0...Self.maximumCellOperationsPerCheck).contains(cellOperations) else {
                throw HamptonARCTrainingOrderError.invalidCellOperations
            }
        } else if cellOperations != nil {
            throw HamptonARCTrainingOrderError.unexpectedCellOperations
        }
        checks[index] += 1
        if falsified { falsifications[index] += 1 }
        if let cellOperations { observedCellOperations[index] += Int64(cellOperations) }
    }

    private func estimatedCost(at index: Int) -> Int64 {
        guard costAware else { return 1 }
        let countWithPrior = Int64(checks[index] + 1)
        let totalWithPrior = observedCellOperations[index] + 1
        // Ceiling division is exact. At the bounds above, the cross-products
        // in `order` are below 4.6e13, safely inside Int64 on every platform.
        return max(1, (totalWithPrior + countWithPrior - 1) / countWithPrior)
    }
}
