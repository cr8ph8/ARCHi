import Foundation

/// Native numerical mechanisms from the Hampton/RepE reference, sections 4.2–4.4.
/// Domain owners supply named coordinates and attributable inputs. These routines
/// return bounded numerical candidates; they do not establish truth, authorize
/// actions, read activations, or mutate companion state.
enum HamptonNumericalDynamics {
    static let version = "hampton-numerical-dynamics/v1"
    private static let maximumDimension = 64

    enum Failure: Error, Equatable, Sendable {
        case invalidInput(String)
        case nonFiniteArithmetic(String)
        case notPositiveDefinite(String)
        case couplingBoundExceeded
    }

    struct Configuration: Codable, Equatable, Sendable {
        let learningRate: Double
        let deltaMax: Double
        let target: [Double]
        let potentialMatrix: [[Double]]
        let allowedIncrease: Double
        let maxBacktracks: Int

        init(learningRate: Double, deltaMax: Double, target: [Double], potentialMatrix: [[Double]],
             allowedIncrease: Double = 0, maxBacktracks: Int = 24) {
            self.learningRate = learningRate; self.deltaMax = deltaMax
            self.target = target; self.potentialMatrix = potentialMatrix
            self.allowedIncrease = allowedIncrease; self.maxBacktracks = maxBacktracks
        }
    }

    enum CandidateStatus: String, Codable, Sendable {
        case accepted = "ACCEPTED_CANDIDATE"
        case damped = "DAMPED_CANDIDATE"
        case rejectedUnchanged = "REJECTED_UNCHANGED"
    }

    struct QuotientCandidate: Codable, Equatable, Sendable {
        let coordinates: [String]
        let previous: [Double]
        let candidate: [Double]
        let requestedDelta: [Double]
        let cappedDelta: [Double]
        let effectiveDelta: [Double]
        let accepted: Bool
        let status: CandidateStatus
        let normScale: Double
        let backtracks: Int
        let potentialPrevious: Double
        let potentialCandidate: Double
    }

    struct CouplingConfiguration: Codable, Equatable, Sendable {
        let sourceCoordinates: [String]
        let destinationCoordinates: [String]
        /// M[source,destination]. Values are authored policy unless a separate
        /// evidence contract establishes how they were learned.
        let matrix: [[Double]]
        let spectralNormBound: Double
    }

    struct CouplingProposal: Codable, Equatable, Sendable {
        let sourceCoordinates: [String]
        let destinationCoordinates: [String]
        let effectiveDelta: [Double]
        let destinationDelta: [Double]
        /// Conservative min(Frobenius, sqrt(one-norm * infinity-norm)) bound.
        /// This is not an SVD measurement of the exact spectral norm.
        let spectralNormUpperBound: Double
    }

    /// q' = clip(q + 2^-b normcap(eta (L I - E)), 0, 1).
    /// P and target are fixed for all attempts. Every complete finite candidate,
    /// including clipping, must satisfy V(q') <= V(q) + allowedIncrease.
    static func boundedQuotientCandidate(
        coordinates: [String], previous: [Double], innovation: [Double],
        learningMatrix: [[Double]], error: [Double], configuration: Configuration
    ) throws -> QuotientCandidate {
        try validateCoordinates(coordinates)
        try validateVector(previous, count: coordinates.count, name: "previous")
        try validateVector(innovation, name: "innovation")
        try validateVector(error, count: previous.count, name: "error")
        try validateVector(configuration.target, count: previous.count, name: "target")
        try validateMatrix(learningMatrix, rows: previous.count, columns: innovation.count, name: "learning matrix")
        guard previous.allSatisfy({ (0...1).contains($0) }),
              (0...64).contains(configuration.maxBacktracks) else {
            throw Failure.invalidInput("previous range or backtracking count")
        }
        try nonnegative(configuration.learningRate, "learning rate")
        try nonnegative(configuration.deltaMax, "delta cap")
        try nonnegative(configuration.allowedIncrease, "allowed increase")
        let (_, factor) = try positiveDefinite(configuration.potentialMatrix, count: previous.count, name: "potential")
        let before = try potential(previous, target: configuration.target, factor: factor)
        let ceiling = try finite(before + configuration.allowedIncrease, "potential ceiling")
        let learned = try multiply(learningMatrix, innovation)
        let requested = try zip(learned, error).map {
            try finite(configuration.learningRate * finite($0 - $1, "learning error"), "requested delta")
        }
        let (capped, scale) = capNorm(requested, limit: configuration.deltaMax)
        for backtracks in 0...configuration.maxBacktracks {
            let step = pow(0.5, Double(backtracks))
            let candidate = zip(previous, capped).map { min(1, max(0, $0 + step * $1)) }
            let effective = zip(candidate, previous).map(-)
            // Floating-point addition/clipping can alter the effective norm.
            guard withinNorm(effective, limit: configuration.deltaMax) else { continue }
            guard let after = try? potential(candidate, target: configuration.target, factor: factor),
                  after <= ceiling else { continue }
            return QuotientCandidate(coordinates: coordinates, previous: previous, candidate: candidate,
                requestedDelta: requested, cappedDelta: capped, effectiveDelta: effective,
                accepted: true, status: backtracks > 0 || scale < 1 ? .damped : .accepted,
                normScale: scale, backtracks: backtracks, potentialPrevious: before, potentialCandidate: after)
        }
        return QuotientCandidate(coordinates: coordinates, previous: previous, candidate: previous,
            requestedDelta: requested, cappedDelta: capped, effectiveDelta: Array(repeating: 0, count: previous.count),
            accepted: false, status: .rejectedUnchanged, normScale: scale,
            backtracks: configuration.maxBacktracks, potentialPrevious: before, potentialCandidate: before)
    }

    /// Continuous field -gain G^-1 P(q-target). A favorable field direction does
    /// not approve a finite step: submit the entire resulting update above.
    static func intelligenceForce(previous: [Double], target: [Double], potentialMatrix: [[Double]],
                                  metricMatrix: [[Double]], gain: Double) throws -> [Double] {
        try validateVector(previous, name: "previous")
        try validateVector(target, count: previous.count, name: "target")
        try nonnegative(gain, "force gain")
        let (potential, _) = try positiveDefinite(potentialMatrix, count: previous.count, name: "potential")
        let (_, metricFactor) = try positiveDefinite(metricMatrix, count: previous.count, name: "metric")
        let displacement = try zip(previous, target).map { try finite($0 - $1, "force displacement") }
        let gradient = try multiply(potential, displacement)
        let solution = try solveCholesky(metricFactor, gradient)
        return try solution.map { try finite(-gain * $0, "force") }
    }

    static func quadraticPotential(previous: [Double], target: [Double], potentialMatrix: [[Double]]) throws -> Double {
        try validateVector(previous, name: "previous")
        try validateVector(target, count: previous.count, name: "target")
        let (_, factor) = try positiveDefinite(potentialMatrix, count: previous.count, name: "potential")
        return try potential(previous, target: target, factor: factor)
    }

    /// Delta z = M^T (candidate - previous). Coordinate identity and ordering
    /// must match. Rejected candidates couple to zero. Numeric receipt checks
    /// are not authentication; the native owner must recompute persisted input.
    static func couple(candidate: QuotientCandidate, configuration: CouplingConfiguration) throws -> CouplingProposal {
        try validateCoordinates(candidate.coordinates)
        try validateCoordinates(configuration.sourceCoordinates)
        try validateCoordinates(configuration.destinationCoordinates)
        guard candidate.coordinates == configuration.sourceCoordinates else {
            throw Failure.invalidInput("coupling source coordinate identity")
        }
        let count = candidate.coordinates.count
        try validateVector(candidate.previous, count: count, name: "previous")
        try validateVector(candidate.candidate, count: count, name: "candidate")
        try validateVector(candidate.effectiveDelta, count: count, name: "effective delta")
        guard candidate.previous.allSatisfy({ (0...1).contains($0) }),
              candidate.candidate.allSatisfy({ (0...1).contains($0) }),
              candidate.accepted == (candidate.status != .rejectedUnchanged),
              candidate.accepted || candidate.previous == candidate.candidate else {
            throw Failure.invalidInput("candidate receipt state")
        }
        let effective = zip(candidate.candidate, candidate.previous).map(-)
        guard effective == candidate.effectiveDelta else { throw Failure.invalidInput("candidate effective delta") }
        try nonnegative(configuration.spectralNormBound, "coupling bound")
        try validateMatrix(configuration.matrix, rows: count, columns: configuration.destinationCoordinates.count,
                           name: "coupling matrix")
        let upperBound = try operatorNormUpperBound(configuration.matrix)
        guard upperBound <= configuration.spectralNormBound else { throw Failure.couplingBoundExceeded }
        let destination = try multiply(transpose(configuration.matrix), effective)
        return CouplingProposal(sourceCoordinates: configuration.sourceCoordinates,
            destinationCoordinates: configuration.destinationCoordinates, effectiveDelta: effective,
            destinationDelta: destination, spectralNormUpperBound: upperBound)
    }

    private static func finite(_ value: Double, _ name: String) throws -> Double {
        guard value.isFinite else { throw Failure.nonFiniteArithmetic(name) }
        return value
    }

    private static func nonnegative(_ value: Double, _ name: String) throws {
        guard value.isFinite, value >= 0 else { throw Failure.invalidInput(name) }
    }

    private static func validateCoordinates(_ names: [String]) throws {
        guard (1...maximumDimension).contains(names.count), Set(names).count == names.count,
              names.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 96
                  && $0.trimmingCharacters(in: .whitespacesAndNewlines) == $0
                  && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }) else {
            throw Failure.invalidInput("coordinate identifiers")
        }
    }

    private static func validateVector(_ vector: [Double], count: Int? = nil, name: String) throws {
        guard (1...maximumDimension).contains(vector.count), count == nil || count == vector.count,
              vector.allSatisfy(\.isFinite) else { throw Failure.invalidInput(name) }
    }

    private static func validateMatrix(_ matrix: [[Double]], rows: Int, columns: Int, name: String) throws {
        guard (1...maximumDimension).contains(rows), (1...maximumDimension).contains(columns), matrix.count == rows,
              matrix.allSatisfy({ $0.count == columns && $0.allSatisfy(\.isFinite) }) else {
            throw Failure.invalidInput(name)
        }
    }

    private static func transpose(_ matrix: [[Double]]) -> [[Double]] {
        (0..<matrix[0].count).map { column in matrix.map { $0[column] } }
    }

    private static func multiply(_ matrix: [[Double]], _ vector: [Double]) throws -> [Double] {
        try matrix.map { row in
            var total = 0.0
            for (left, right) in zip(row, vector) {
                total = try finite(total + finite(left * right, "matrix product"), "matrix sum")
            }
            return total
        }
    }

    /// Scale before squaring, so a finite large vector can still be norm-capped.
    private static func normParts(_ vector: [Double]) -> (Double, Double) {
        let peak = vector.map(abs).max() ?? 0
        guard peak > 0 else { return (0, 0) }
        let squared = vector.reduce(0.0) { result, value in result + pow(value / peak, 2) }
        return (peak, sqrt(squared))
    }

    private static func withinNorm(_ vector: [Double], limit: Double) -> Bool {
        let (peak, length) = normParts(vector)
        return peak == 0 || peak <= limit / length
    }

    private static func capNorm(_ vector: [Double], limit: Double) -> ([Double], Double) {
        let (peak, length) = normParts(vector)
        guard peak > 0, peak > limit / length else { return (vector, 1) }
        let scale = (limit / peak) / length
        return (vector.map { $0 * scale }, scale)
    }

    /// Symmetrize only within arithmetic tolerance; reject indefinite matrices.
    private static func positiveDefinite(_ input: [[Double]], count: Int, name: String) throws -> ([[Double]], [[Double]]) {
        try validateMatrix(input, rows: count, columns: count, name: name)
        var matrix = input
        for i in 0..<count {
            for j in 0..<count {
                let left = input[i][j], right = input[j][i]
                guard abs(left - right) <= 1e-12 + 1e-10 * max(abs(left), abs(right)) else {
                    throw Failure.invalidInput("asymmetric \(name)")
                }
                matrix[i][j] = left * 0.5 + right * 0.5
            }
        }
        var factor = Array(repeating: Array(repeating: 0.0, count: count), count: count)
        for i in 0..<count {
            for j in 0...i {
                var remainder = matrix[i][j]
                for k in 0..<j {
                    remainder = try finite(remainder - finite(factor[i][k] * factor[j][k], "Cholesky product"), "Cholesky sum")
                }
                if i == j {
                    guard remainder > 0 else { throw Failure.notPositiveDefinite(name) }
                    factor[i][j] = sqrt(remainder)
                } else {
                    factor[i][j] = try finite(remainder / factor[j][j], "Cholesky division")
                }
            }
        }
        return (matrix, factor)
    }

    private static func potential(_ vector: [Double], target: [Double], factor: [[Double]]) throws -> Double {
        let displacement = try zip(vector, target).map { try finite($0 - $1, "potential displacement") }
        let transformed = try multiply(transpose(factor), displacement)
        var result = 0.0
        for value in transformed {
            result = try finite(result + finite((value * 0.5) * value, "potential square"), "potential sum")
        }
        return result
    }

    private static func solveCholesky(_ lower: [[Double]], _ right: [Double]) throws -> [Double] {
        var intermediate = Array(repeating: 0.0, count: right.count)
        for i in right.indices {
            var residual = right[i]
            for j in 0..<i { residual = try finite(residual - finite(lower[i][j] * intermediate[j], "forward product"), "forward sum") }
            intermediate[i] = try finite(residual / lower[i][i], "forward solve")
        }
        var solution = Array(repeating: 0.0, count: right.count)
        for i in right.indices.reversed() {
            var residual = intermediate[i]
            for j in (i + 1)..<right.count { residual = try finite(residual - finite(lower[j][i] * solution[j], "backward product"), "backward sum") }
            solution[i] = try finite(residual / lower[i][i], "backward solve")
        }
        return solution
    }

    /// A conservative rectangular spectral-norm bound avoids convergence- or
    /// starting-vector-dependent underestimation from power iteration. Unknown
    /// and over-bound coupling is rejected, never silently rescaled. A matrix
    /// can be rejected even when its true spectral norm would fit the bound.
    private static func operatorNormUpperBound(_ matrix: [[Double]]) throws -> Double {
        let peak = matrix.flatMap { $0 }.map(abs).max() ?? 0
        guard peak > 0 else { return 0 }
        let normalized = matrix.map { $0.map { abs($0) / peak } }
        let frobenius = sqrt(normalized.flatMap { $0 }.reduce(0) { $0 + $1 * $1 })
        let infinityNorm = normalized.map { $0.reduce(0, +) }.max() ?? 0
        let oneNorm = transpose(normalized).map { $0.reduce(0, +) }.max() ?? 0
        return try finite(peak * min(frobenius, sqrt(oneNorm * infinityNorm)), "coupling norm bound")
    }
}
