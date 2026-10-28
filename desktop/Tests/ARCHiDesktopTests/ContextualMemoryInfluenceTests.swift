import Foundation
import XCTest
@testable import ARCHiDesktop

final class ContextualMemoryInfluenceTests: XCTestCase {
    private typealias Influence = ContextualMemoryInfluence
    private let scope = "archi.passageRevision"
    private let target = "method:synthetic-r1"

    private func input(_ id: String, polarity: Influence.Polarity? = .attraction,
                       match: Double = 1, salience: Double = 1, confidence: Double = 1,
                       magnitude: Double = 1, origin: String? = nil, eligible: Bool = true,
                       inputScope: String? = nil, inputTarget: String? = nil) -> Influence.Input {
        Influence.Input(sourceID: id, sourceRevision: 1, sourceDigest: String(repeating: "a", count: 64),
            originID: origin ?? "origin:\(id)",
            assessment: .init(scope: inputScope ?? scope, targetID: inputTarget ?? target, polarity: polarity,
                              magnitude: magnitude, confidence: confidence, retrievalSalience: salience),
            contextMatch: match, eligible: eligible)
    }

    private func evaluate(_ inputs: [Influence.Input]) throws -> Influence.Evaluation {
        try Influence.evaluate(inputs: inputs, scope: scope, targetID: target)
    }

    func testHandCalculatedFixtureAndSignReversalPreserveRetrieval() throws {
        let support = input("M1", match: 0.82, salience: 0.65, confidence: 0.84, magnitude: 0.65)
        let caution = input("M2", polarity: .detraction, match: 0.96, salience: 0.98, confidence: 0.92, magnitude: 0.9)
        let neutral = input("M3", polarity: .neutral, match: 0.7, salience: 0.7, confidence: 0.9, magnitude: 0.45)
        let before = try evaluate([support, caution, neutral])
        XCTAssertEqual(before.positiveMass, 0.291018, accuracy: 1e-12)
        XCTAssertEqual(before.negativeMass, 0.7789824, accuracy: 1e-12)
        XCTAssertEqual(before.neutralMass, 0.19845, accuracy: 1e-12)
        XCTAssertEqual(before.influence, -0.21510913353009614, accuracy: 1e-12)
        XCTAssertEqual(before.rows[1].retrieval, 0.9408, accuracy: 1e-12)
        XCTAssertTrue(before.hasOpposingEvidence)
        let reversed = input("M2", match: 0.96, salience: 0.98, confidence: 0.92, magnitude: 0.9)
        let after = try evaluate([support, reversed, neutral])
        XCTAssertEqual(before.rows.map(\.retrieval), after.rows.map(\.retrieval))
        XCTAssertEqual(after.influence - before.influence, 2 * 0.7789824 / 2.2684504, accuracy: 1e-12)
        XCTAssertEqual(before.rows.map(\.sourceDigest), after.rows.map(\.sourceDigest))
        XCTAssertEqual(before.rows.map(\.sourceRevision), after.rows.map(\.sourceRevision))
    }

    func testZeroMagnitudeOrConfidenceRemovesInfluenceWithoutHidingMemory() throws {
        let result = try evaluate([
            input("no-magnitude", polarity: .detraction, match: 0.8, salience: 0.9, magnitude: 0),
            input("no-confidence", match: 0.8, salience: 0.9, confidence: 0),
        ])
        XCTAssertEqual(result.influence, 0)
        XCTAssertEqual(result.totalWeight, 0)
        XCTAssertTrue(result.rows.allSatisfy { abs($0.retrieval - 0.72) < 1e-12 })
    }

    func testUnknownAndAssessedNeutralRemainDistinct() throws {
        let unknown = try evaluate([input("M1", polarity: nil)])
        let neutral = try evaluate([input("M1", polarity: .neutral)])
        XCTAssertEqual(unknown.rows.first?.retrieval, neutral.rows.first?.retrieval)
        XCTAssertEqual(unknown.influence, 0)
        XCTAssertEqual(neutral.influence, 0)
        XCTAssertEqual(unknown.totalWeight, 0)
        XCTAssertEqual(neutral.totalWeight, 1)
        XCTAssertEqual(unknown.unassessedCount, 1)
        XCTAssertEqual(neutral.assessedCount, 1)
        let withNeutral = try evaluate([input("M1"), input("M2", polarity: .neutral)])
        XCTAssertEqual(withNeutral.influence, 1.0 / 3, accuracy: 1e-12)
    }

    func testBalancedOppositionDoesNotLookLikeMissingEvidence() throws {
        let result = try evaluate([input("support"), input("caution", polarity: .detraction)])
        XCTAssertEqual(result.influence, 0)
        XCTAssertEqual(result.totalWeight, 2)
        XCTAssertTrue(result.hasOpposingEvidence)
        XCTAssertFalse(try evaluate([]).hasOpposingEvidence)
    }

    func testWeakEvidenceStaysWeak() throws {
        let result = try evaluate([input("weak", match: 0.01, confidence: 0.01, magnitude: 0.01)])
        XCTAssertGreaterThan(result.influence, 0)
        XCTAssertLessThan(result.influence, 0.000001)
    }

    func testIneligibleSourcesAndDifferentContextsContributeNothing() throws {
        let result = try evaluate([
            input("withdrawn", eligible: false),
            input("other-scope", inputScope: "qimon.practice"),
            input("other-target", inputTarget: "method:other"),
        ])
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows.first?.retrieval, 0)
        XCTAssertEqual(result.influence, 0)
        XCTAssertEqual(result.assessedCount, 0)
    }

    func testDuplicateSourceAndCopiedOriginAreRejected() throws {
        XCTAssertThrowsError(try evaluate([input("same"), input("same")])) { error in
            XCTAssertEqual(error as? Influence.EvaluationError, .duplicateSource("same"))
        }
        XCTAssertThrowsError(try evaluate([input("a", origin: "shared"), input("b", origin: "shared")])) { error in
            XCTAssertEqual(error as? Influence.EvaluationError, .duplicateOrigin("shared"))
        }
        XCTAssertNoThrow(try evaluate([input("a", origin: "shared"), input("b", origin: "shared", eligible: false)]))
        XCTAssertNoThrow(try evaluate([input("same"), input("same", inputTarget: "method:other")]))
    }

    func testNonfiniteAndOutOfRangeNumbersAreRejected() {
        for value in [Double.nan, Double.infinity, -Double.infinity, -0.01, 1.01] {
            XCTAssertThrowsError(try evaluate([input("bad-match", match: value)]))
            XCTAssertThrowsError(try evaluate([input("bad-salience", salience: value)]))
            XCTAssertThrowsError(try evaluate([input("bad-confidence", confidence: value)]))
            XCTAssertThrowsError(try evaluate([input("bad-magnitude", magnitude: value)]))
        }
    }

    func testContextAndSourceBindingsAreValidated() {
        XCTAssertThrowsError(try Influence.evaluate(inputs: [], scope: " ", targetID: target))
        XCTAssertThrowsError(try evaluate([input("control\ncharacter")]))
        let valid = input("source")
        let invalid = Influence.Input(sourceID: valid.sourceID, sourceRevision: 0, sourceDigest: "unbound",
            originID: valid.originID, assessment: valid.assessment, contextMatch: 1, eligible: true)
        XCTAssertThrowsError(try evaluate([invalid]))
        XCTAssertThrowsError(try evaluate((0...Influence.maximumInputs).map { input("source-\($0)") }))
    }

    func testStrictAssessmentDecodingAndUnknownRoundTrip() throws {
        let assessment = Influence.Assessment(scope: scope, targetID: target)
        let data = try JSONEncoder().encode(assessment)
        XCTAssertEqual(try JSONDecoder().decode(Influence.Assessment.self, from: data), assessment)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["authority"] = true
        XCTAssertThrowsError(try JSONDecoder().decode(Influence.Assessment.self,
            from: JSONSerialization.data(withJSONObject: object)))
        object.removeValue(forKey: "authority")
        object["polarity"] = 2
        XCTAssertThrowsError(try JSONDecoder().decode(Influence.Assessment.self,
            from: JSONSerialization.data(withJSONObject: object)))
        object["polarity"] = NSNull()
        XCTAssertNil(try JSONDecoder().decode(Influence.Assessment.self,
            from: JSONSerialization.data(withJSONObject: object)).polarity)
    }

    func testFiniteInfluenceRemainsBoundedAcrossFullInputCapacity() throws {
        let positive = try evaluate((0..<Influence.maximumInputs).map { input("p-\($0)") })
        let negative = try evaluate((0..<Influence.maximumInputs).map { input("n-\($0)", polarity: .detraction) })
        XCTAssertEqual(positive.influence, 256.0 / 257, accuracy: 1e-12)
        XCTAssertEqual(negative.influence, -256.0 / 257, accuracy: 1e-12)
        XCTAssertLessThan(positive.influence, 1)
        XCTAssertGreaterThan(negative.influence, -1)
    }
}
