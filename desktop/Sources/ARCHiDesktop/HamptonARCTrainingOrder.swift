import Foundation

enum HamptonARCTrainingOrderError: Error, Equatable {
    case invalidExampleCount
    case invalidExampleIndex
    case observationLimitExceeded
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
    static let version = "hampton-arc-training-order-v1-beta11"

    private var checks: [Int]
    private var falsifications: [Int]

    init(exampleCount: Int) throws {
        guard (1...Self.maximumExamples).contains(exampleCount) else {
            throw HamptonARCTrainingOrderError.invalidExampleCount
        }
        checks = Array(repeating: 0, count: exampleCount)
        falsifications = Array(repeating: 0, count: exampleCount)
    }

    var observationCount: Int { checks.reduce(0, +) }

    /// Descending Beta(1,1) posterior mean: (falsifications + 1) / (checks + 2).
    /// Bounded integer cross-products avoid floating-point/platform tie drift.
    /// This is a scheduling heuristic, not calibrated confidence or authority.
    var order: [Int] {
        checks.indices.sorted { lhs, rhs in
            let left = (falsifications[lhs] + 1) * (checks[rhs] + 2)
            let right = (falsifications[rhs] + 1) * (checks[lhs] + 2)
            return left == right ? lhs < rhs : left > right
        }
    }

    mutating func observe(index: Int, falsified: Bool) throws {
        guard checks.indices.contains(index) else {
            throw HamptonARCTrainingOrderError.invalidExampleIndex
        }
        guard checks[index] < Self.maximumObservationsPerExample else {
            throw HamptonARCTrainingOrderError.observationLimitExceeded
        }
        checks[index] += 1
        if falsified { falsifications[index] += 1 }
    }
}
