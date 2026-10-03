import Foundation
import XCTest
@testable import ARCHiDesktop

final class HamptonNumericalDynamicsTests: XCTestCase {
    private typealias Dynamics = HamptonNumericalDynamics

    func testFullFiniteStepRejectsOvershootDespiteDownhillForceThenBacktracks() throws {
        let force = try Dynamics.intelligenceForce(previous: [0.4], target: [0.5],
            potentialMatrix: [[1]], metricMatrix: [[1]], gain: 10)
        XCTAssertGreaterThan(force[0], 0, "The continuous direction points toward the target.")
        let rejected = try Dynamics.boundedQuotientCandidate(coordinates: ["usefulness"], previous: [0.4],
            innovation: force, learningMatrix: [[1]], error: [0],
            configuration: .init(learningRate: 1, deltaMax: 2, target: [0.5],
                                 potentialMatrix: [[1]], maxBacktracks: 0))
        XCTAssertFalse(rejected.accepted)
        XCTAssertEqual(rejected.status, .rejectedUnchanged)
        XCTAssertEqual(rejected.candidate, rejected.previous)
        XCTAssertEqual(rejected.effectiveDelta, [0])
        let damped = try Dynamics.boundedQuotientCandidate(coordinates: ["usefulness"], previous: [0.4],
            innovation: force, learningMatrix: [[1]], error: [0],
            configuration: .init(learningRate: 1, deltaMax: 2, target: [0.5],
                                 potentialMatrix: [[1]], maxBacktracks: 12))
        XCTAssertTrue(damped.accepted)
        XCTAssertEqual(damped.status, .damped)
        XCTAssertEqual(damped.backtracks, 3)
        XCTAssertLessThan(damped.potentialCandidate, damped.potentialPrevious)
    }

    func testMetricForceUsesFullSPDMatrixAndDoesNotAlterInputs() throws {
        let previous = [0.8, 0.2], target = [0.2, 0.8]
        let potential = [[2.0, 0.5], [0.5, 1.0]], metric = [[2.0, 0.25], [0.25, 1.0]]
        let force = try Dynamics.intelligenceForce(previous: previous, target: target,
            potentialMatrix: potential, metricMatrix: metric, gain: 0.2)
        XCTAssertEqual(2 * force[0] + 0.25 * force[1], -0.18, accuracy: 1e-12)
        XCTAssertEqual(0.25 * force[0] + force[1], 0.06, accuracy: 1e-12)
        XCTAssertEqual(try Dynamics.quadraticPotential(previous: previous, target: target,
                                                       potentialMatrix: potential), 0.36, accuracy: 1e-12)
        XCTAssertEqual(previous, [0.8, 0.2])
    }

    func testCouplingUsesActualClippedDeltaAndExactCoordinateIdentity() throws {
        let candidate = try Dynamics.boundedQuotientCandidate(coordinates: ["usefulness"], previous: [0.95],
            innovation: [10], learningMatrix: [[1]], error: [0],
            configuration: .init(learningRate: 1, deltaMax: 1, target: [1], potentialMatrix: [[1]]))
        XCTAssertEqual(candidate.requestedDelta, [10])
        XCTAssertEqual(candidate.cappedDelta, [1])
        XCTAssertEqual(candidate.effectiveDelta[0], 0.05, accuracy: 1e-12)
        let result = try Dynamics.couple(candidate: candidate,
            configuration: .init(sourceCoordinates: ["usefulness"], destinationCoordinates: ["reuse", "explore"],
                                 matrix: [[2, -1]], spectralNormBound: 3))
        XCTAssertEqual(result.destinationDelta[0], 0.1, accuracy: 1e-12)
        XCTAssertEqual(result.destinationDelta[1], -0.05, accuracy: 1e-12)
        XCTAssertThrowsError(try Dynamics.couple(candidate: candidate,
            configuration: .init(sourceCoordinates: ["confidence"], destinationCoordinates: ["reuse"],
                                 matrix: [[1]], spectralNormBound: 1)))
        XCTAssertThrowsError(try Dynamics.couple(candidate: candidate,
            configuration: .init(sourceCoordinates: ["usefulness"], destinationCoordinates: ["reuse"],
                                 matrix: [[2]], spectralNormBound: 1)))
        var encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(candidate)) as? [String: Any])
        encoded["effectiveDelta"] = [10]
        let tampered = try JSONDecoder().decode(Dynamics.QuotientCandidate.self,
                                               from: JSONSerialization.data(withJSONObject: encoded))
        XCTAssertThrowsError(try Dynamics.couple(candidate: tampered,
            configuration: .init(sourceCoordinates: ["usefulness"], destinationCoordinates: ["reuse"],
                                 matrix: [[1]], spectralNormBound: 1)))
    }

    func testNormCapAndRectangularAuthoredCouplingStayWithinDeclaredBounds() throws {
        let coordinates = ["retainUsefulness", "expandUsefulness", "repairUsefulness"]
        let candidate = try Dynamics.boundedQuotientCandidate(coordinates: coordinates, previous: [0.5, 0.5, 0.5],
            innovation: [1e200, 1e200, 1e200], learningMatrix: [[1, 0, 0], [0, 1, 0], [0, 0, 1]],
            error: [0, 0, 0], configuration: .init(learningRate: 1, deltaMax: 0.125,
                                                  target: [1, 1, 1], potentialMatrix: [[1, 0, 0], [0, 1, 0], [0, 0, 1]]))
        XCTAssertTrue(candidate.accepted)
        XCTAssertLessThanOrEqual(sqrt(candidate.effectiveDelta.reduce(0) { $0 + $1 * $1 }), 0.125)
        let coupling = try Dynamics.couple(candidate: candidate,
            configuration: .init(sourceCoordinates: coordinates, destinationCoordinates: ["retain", "expand", "repair"],
                matrix: [[0.5, -0.125, 0], [-0.125, 0.5, 0], [0, 0, 0.5]], spectralNormBound: 0.625))
        XCTAssertEqual(coupling.spectralNormUpperBound, 0.625)
        let sourceNorm = sqrt(candidate.effectiveDelta.reduce(0) { $0 + $1 * $1 })
        let destinationNorm = sqrt(coupling.destinationDelta.reduce(0) { $0 + $1 * $1 })
        XCTAssertLessThanOrEqual(destinationNorm, 0.625 * sourceNorm + 1e-15)
    }

    func testBadDimensionsNonfiniteAndIndefiniteInputsFailBeforeAnyProposal() throws {
        let valid = Dynamics.Configuration(learningRate: 1, deltaMax: 0.1, target: [1], potentialMatrix: [[1]])
        XCTAssertThrowsError(try Dynamics.boundedQuotientCandidate(coordinates: ["support"], previous: [0.5],
            innovation: [1], learningMatrix: [[1, 2]], error: [0], configuration: valid))
        XCTAssertThrowsError(try Dynamics.boundedQuotientCandidate(coordinates: ["support"], previous: [0.5],
            innovation: [.nan], learningMatrix: [[1]], error: [0], configuration: valid))
        XCTAssertThrowsError(try Dynamics.boundedQuotientCandidate(coordinates: ["support", "support"], previous: [0.5, 0.5],
            innovation: [1], learningMatrix: [[1], [1]], error: [0, 0], configuration: valid))
        XCTAssertThrowsError(try Dynamics.quadraticPotential(previous: [0.5, 0.5], target: [0, 0],
                                                           potentialMatrix: [[1, 2], [2, 1]]))
        XCTAssertThrowsError(try Dynamics.intelligenceForce(previous: [0.5], target: [0],
            potentialMatrix: [[1]], metricMatrix: [[0]], gain: 1))
        XCTAssertThrowsError(try Dynamics.boundedQuotientCandidate(coordinates: ["support"], previous: [0.5],
            innovation: [Double.greatestFiniteMagnitude], learningMatrix: [[2]], error: [0], configuration: valid))
    }
}
