import Foundation
import XCTest
@testable import ARCHiDesktop

final class ArenaPracticeReportTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let session = "CF684E77-2C89-4F18-9BD2-3AF8542BC696"
    private let originDigest = String(repeating: "a", count: 64)

    func testRetainedActionAndTerminalMeasuresRoundTripWithoutProfileOrigin() throws {
        let value = snapshot([
            event(1, dealt: 7, taken: 6),
            event(2, action: "guard", dealt: 3, taken: 0, absorbed: 5),
            event(3, action: "signature", dealt: 8),
            event(4, dealt: 4, taken: 2, winner: "one"),
            event(5, action: "guard", dealt: 1, absorbed: 2, winner: "two"),
            event(6, action: "signature", dealt: 2, taken: 2, winner: "draw")
        ])
        let history = try validatedHistory(value)
        let report = try XCTUnwrap(ArenaPracticeReport(history: history, snapshot: value, capturedAt: now))
        XCTAssertEqual(report.schemaVersion, 2)
        XCTAssertEqual(report.sessionID, session)
        XCTAssertEqual(report.sessionKind, "companion")
        XCTAssertEqual(report.presentationRevision, 7)
        XCTAssertEqual(report.capturedAtUnix, now.timeIntervalSince1970)
        XCTAssertEqual(report.snapshotUpdatedAtUnix, value.updatedAtUnix)
        XCTAssertEqual(report.currentArea, "arena")
        XCTAssertEqual(report.currentMode, "solo")
        XCTAssertEqual(report.consumedSequence, 6)
        XCTAssertEqual(report.retainedCount, 6)
        XCTAssertEqual(report.missingCount, 0)
        XCTAssertEqual(report.retiredCount, 0)
        XCTAssertEqual(report.actionCounts, ["pulse": 2, "guard": 2, "signature": 2])
        XCTAssertEqual(report.damageDealt, 25)
        XCTAssertEqual(report.damageTaken, 16)
        XCTAssertEqual(report.damageAbsorbed, 7)
        XCTAssertEqual(report.observedWins, 1)
        XCTAssertEqual(report.observedLosses, 1)
        XCTAssertEqual(report.observedDraws, 1)
        XCTAssertEqual(report.outcomes, value.outcomes)
        XCTAssertTrue(report.coverageSummary.contains("6 retained actions"))
        XCTAssertTrue(report.actionSummary.contains("Guard 2"))
        XCTAssertTrue(report.outcomeSummary.contains("1 wins"))
        XCTAssertTrue(report.evidenceScope.contains("solo Unity rule outcomes"))
        XCTAssertTrue(report.limitations.contains { $0.contains("not full session totals") })
        XCTAssertTrue(report.limitations.contains { $0.contains("physics contacts") && $0.contains("general learning") })

        let data = try JSONEncoder().encode(report)
        XCTAssertEqual(try JSONDecoder().decode(ArenaPracticeReport.self, from: data), report)
        let exported = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(exported.contains("originDigest"))
        XCTAssertFalse(exported.contains(originDigest))
    }

    func testMissingAndRetiredActionsRemainSeparateFromRetainedMeasures() throws {
        let firstRing = (5...36).map { event($0) }
        var history = try validatedHistory(snapshot(firstRing))
        let nextRing = Array(firstRing.dropFirst()) + [event(37)]
        let next = snapshot(nextRing)
        try next.validate(matching: [presentation()], now: now)
        try history.ingest(next)
        let gap = snapshot([event(40), event(41)])
        try gap.validate(matching: [presentation()], now: now)
        try history.ingest(gap)
        let before = history
        let report = try XCTUnwrap(ArenaPracticeReport(history: history, snapshot: gap, capturedAt: now))
        XCTAssertEqual(report.consumedSequence, 41)
        XCTAssertEqual(report.retainedCount, 32)
        XCTAssertEqual(report.missingCount, 6)
        XCTAssertEqual(report.retiredCount, 3)
        XCTAssertEqual(report.damageDealt, 96, "Damage covers 32 retained actions, not all 35 observed actions.")
        XCTAssertEqual(report.actionCounts["pulse"], 32)
        XCTAssertFalse(report.outcomes.contains { [38, 39].contains($0.sequence) })
        XCTAssertEqual(history, before, "Creating a report cannot advance or alter the consumer.")
        try history.ingest(gap)
        XCTAssertEqual(ArenaPracticeReport(history: history, snapshot: gap, capturedAt: now), report)
    }

    func testUnboundEmptyAndMismatchedSessionOrCursorCannotExport() throws {
        let empty = snapshot([])
        XCTAssertNil(ArenaPracticeReport(history: WorldOutcomeHistory(), snapshot: empty, capturedAt: now))
        XCTAssertNil(ArenaPracticeReport(history: try validatedHistory(empty), snapshot: empty, capturedAt: now))
        let value = snapshot([event(1)])
        let history = try validatedHistory(value)
        let mismatches: [(String, Any)] = [
            ("sessionID", UUID().uuidString), ("originDigest", String(repeating: "b", count: 64)),
            ("sessionKind", "localPractice")
        ]
        for (key, replacement) in mismatches {
            let changed = try altered(value) { $0[key] = replacement }
            XCTAssertNil(ArenaPracticeReport(history: history, snapshot: changed, capturedAt: now), key)
        }
        XCTAssertNil(ArenaPracticeReport(history: history, snapshot: snapshot([event(2)]), capturedAt: now))
        XCTAssertNil(ArenaPracticeReport(history: history, snapshot: empty, capturedAt: now))
        XCTAssertNil(ArenaPracticeReport(history: history, snapshot: value,
                                       capturedAt: Date(timeIntervalSince1970: .infinity)))
    }

    func testOverlappingRewriteCannotBePresentedAsRetainedEvidence() throws {
        let value = snapshot([event(1)])
        let history = try validatedHistory(value)
        let changedAction = try altered(value.outcomes[0]) { $0["damageDealt"] = 4; $0["rivalIntegrityAfter"] = 32 }
        let rewritten = snapshot([changedAction])
        try rewritten.validate(matching: [presentation()], now: now)
        XCTAssertNil(ArenaPracticeReport(history: history, snapshot: rewritten, capturedAt: now))
        XCTAssertEqual(history.outcomes, value.outcomes)
    }

    func testRepeatedTerminalBoutCannotInflateObservedResults() throws {
        let bout = "ABCDEF01-016B-4DDA-ADFD-A149CE61C453"
        for secondWinner in ["one", "two"] {
            let value = snapshot([
                event(1, boutID: bout, winner: "one"),
                event(2, boutID: bout.lowercased(), winner: secondWinner)
            ])
            let history = try validatedHistory(value)
            XCTAssertNil(ArenaPracticeReport(history: history, snapshot: value, capturedAt: now), secondWinner)
        }
        let ordinaryThenTerminal = snapshot([event(1, boutID: bout), event(2, boutID: bout, winner: "one")])
        let history = try validatedHistory(ordinaryThenTerminal)
        let report = try XCTUnwrap(ArenaPracticeReport(history: history, snapshot: ordinaryThenTerminal, capturedAt: now))
        XCTAssertEqual(report.observedWins, 1)
        XCTAssertEqual(report.retainedCount, 2)
    }

    func testCurrentModeChangeRetainsOnlyPreviouslyObservedSoloFacts() throws {
        let value = snapshot([event(1)])
        let history = try validatedHistory(value)
        for mode in ["paired", "unavailable"] {
            let changed = try altered(value) { $0["mode"] = mode }
            try changed.validate(matching: [presentation()], now: now)
            let report = try XCTUnwrap(ArenaPracticeReport(history: history, snapshot: changed, capturedAt: now))
            XCTAssertEqual(report.currentMode, mode)
            XCTAssertEqual(report.outcomes, value.outcomes)
            XCTAssertTrue(report.evidenceScope.contains("solo"))
            XCTAssertTrue(report.limitations.contains { $0.contains("paired play contributes no outcomes") })
        }
    }

    func testLargeSequenceGapDoesNotOverflowCoverageArithmetic() throws {
        let first = snapshot([event(Int.max - 2)])
        var history = try validatedHistory(first)
        let last = snapshot([event(Int.max)])
        try last.validate(matching: [presentation()], now: now)
        try history.ingest(last)
        let report = try XCTUnwrap(ArenaPracticeReport(history: history, snapshot: last, capturedAt: now))
        XCTAssertEqual(report.consumedSequence, Int.max)
        XCTAssertEqual(report.missingCount, Int.max - 2)
        XCTAssertEqual(report.retiredCount, 0)
        XCTAssertEqual(report.retainedCount, 2)
        XCTAssertEqual(report.damageDealt, 6)
    }

    private func validatedHistory(_ value: WorldOutcomeSnapshot) throws -> WorldOutcomeHistory {
        try value.validate(matching: [presentation()], now: now)
        var history = WorldOutcomeHistory()
        try history.ingest(value)
        return history
    }

    private func event(_ sequence: Int, action: String = "pulse", boutID: String = UUID().uuidString,
                       dealt: Int = 3, taken: Int = 3, absorbed: Int = 0, winner: String = "") -> WorldActionOutcome {
        let integrityBefore = ["two", "draw"].contains(winner) ? taken : 36
        let rivalIntegrityBefore = ["one", "draw"].contains(winner) ? dealt : 36
        return .init(sequence: sequence, actionID: UUID().uuidString, boutID: boutID, presentationRevision: 7,
                     atUnix: now.timeIntervalSince1970 - 0.25, action: action, rivalAction: "pulse",
                     field: "guardian", round: 1, integrityBefore: integrityBefore,
                     integrityAfter: integrityBefore - taken, rivalIntegrityBefore: rivalIntegrityBefore,
                     rivalIntegrityAfter: rivalIntegrityBefore - dealt, sparkBefore: 3,
                     sparkAfter: action == "signature" ? 2 : 3, rivalSparkBefore: 3, rivalSparkAfter: 3,
                     damageDealt: dealt, damageTaken: taken, absorbed: absorbed,
                     complete: !winner.isEmpty, winner: winner)
    }

    private func snapshot(_ outcomes: [WorldActionOutcome]) -> WorldOutcomeSnapshot {
        .init(schemaVersion: 1, sessionID: session, originDigest: originDigest, sessionKind: "companion",
              revision: 7, updatedAtUnix: now.timeIntervalSince1970, currentArea: "arena", mode: "solo",
              firstSequence: outcomes.first?.sequence ?? 0, lastSequence: outcomes.last?.sequence ?? 0, outcomes: outcomes)
    }

    private func presentation() -> UnityPresentationSnapshot {
        .init(schemaVersion: 1, sessionID: session, revision: 7, originDigest: originDigest,
              displayName: "Fixture", body: "seed", appearance: "kin", cursor: "seed",
              seedAssetSHA256: String(repeating: "b", count: 64), bodyAssetSHA256: String(repeating: "b", count: 64),
              activity: "idle", lightMode: "rest", quiet: false, reduceMotion: false, visible: true,
              equippedFocusStaff: false, staffPalette: nil, staffCrown: nil, active: true,
              updatedAtUnix: now.timeIntervalSince1970, sessionKind: "companion", destination: "arena", destinationRevision: 1)
    }

    private func altered<T: Codable>(_ value: T, _ edit: (inout [String: Any]) -> Void) throws -> T {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        edit(&object)
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
