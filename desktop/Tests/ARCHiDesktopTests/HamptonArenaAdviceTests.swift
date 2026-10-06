import Foundation
import XCTest
@testable import ARCHiDesktop

/// Disposable rule facts only. No player, model, network or personal profile.
final class HamptonArenaAdviceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let session = "D736AF64-BAB8-4D3B-ABEF-4383210632ED"
    private let bout = "ABCDEF01-016B-4DDA-ADFD-A149CE61C453"
    private let origin = String(repeating: "a", count: 64)

    func testActualIntegrityExchangeDrivesBoundedPreferenceWithoutDoubleReward() throws {
        let positive = event(1, dealt: 10, taken: 0)
        let receipt = try XCTUnwrap(HamptonArenaNumericalControl.replay(outcomes: [positive], field: "guardian"))
        XCTAssertTrue(receipt.isValid)
        XCTAssertEqual(receipt.initial, [0.5, 0.5, 0.5])
        XCTAssertEqual(receipt.final, [0.625, 0.5, 0.5])
        XCTAssertEqual(receipt.rankedMoves.first?.move, "pulse")
        XCTAssertEqual(receipt.rankedMoves.first?.score, 0.5625)
        XCTAssertEqual(receipt.steps[0].observedValue, 1)
        XCTAssertEqual(receipt.steps[0].coupling.spectralNormUpperBound, 0.5)
        XCTAssertLessThanOrEqual(receipt.steps[0].candidate.potentialCandidate, receipt.steps[0].candidate.potentialPrevious)
        XCTAssertEqual(receipt.steps[0].candidate.effectiveDelta, [0.125, 0, 0])

        let overkill = event(1, rivalIntegrity: 2, dealt: 10, taken: 0)
        let actualLoss = try XCTUnwrap(HamptonArenaNumericalControl.replay(outcomes: [overkill], field: "guardian"))
        XCTAssertEqual(actualLoss.steps[0].observedValue, 0.6, accuracy: 1e-12)
        XCTAssertEqual(actualLoss.final[0], 0.53125, accuracy: 1e-12,
                       "Ten nominal damage removing two integrity cannot earn ten integrity of exchange or a second win reward.")
        let blocked = event(1, action: "guard", dealt: 0, taken: 0, absorbed: 7)
        let neutral = try XCTUnwrap(HamptonArenaNumericalControl.replay(outcomes: [blocked], field: "guardian"))
        XCTAssertEqual(neutral.initial, neutral.final, "Absorption is shown separately and is not duplicated as integrity damage.")
    }

    func testReplayIsDeterministicFieldScopedAndUsesDeclaredTieOrder() throws {
        let neutral = event(1)
        let otherField = event(2, field: "scout", action: "signature", dealt: 10, taken: 0)
        let receipt = try XCTUnwrap(HamptonArenaNumericalControl.replay(outcomes: [neutral, otherField], field: "guardian"))
        XCTAssertEqual(receipt.outcomes, [neutral])
        XCTAssertEqual(receipt.rankedMoves.map(\.move), ["guard", "pulse", "signature"])
        XCTAssertEqual(receipt.rankedMoves.map(\.observationCount), [0, 1, 0])
        XCTAssertEqual(HamptonArenaNumericalControl.replay(outcomes: [otherField, neutral], field: "guardian"), receipt)
        XCTAssertEqual(HamptonArenaNumericalControl.replay(outcomes: [neutral, otherField], field: "guardian"), receipt)
        let empty = try XCTUnwrap(HamptonArenaNumericalControl.replay(outcomes: [], field: "guardian"))
        XCTAssertEqual(empty.initial, empty.final)
        XCTAssertTrue(empty.steps.isEmpty)
        XCTAssertEqual(empty.rankedMoves.map(\.observationCount), [0, 0, 0])
    }

    func testWindowReplacementRebuildsRatherThanAccumulatingPriorInfluence() throws {
        let positive = event(1, dealt: 10, taken: 0)
        let negative = event(2, dealt: 0, taken: 10)
        let both = try XCTUnwrap(HamptonArenaNumericalControl.replay(outcomes: [positive, negative], field: "guardian"))
        let retained = try XCTUnwrap(HamptonArenaNumericalControl.replay(outcomes: [negative], field: "guardian"))
        XCTAssertEqual(both.final[0], 0.5)
        XCTAssertEqual(retained.final[0], 0.375)
        XCTAssertEqual(retained.steps.count, 1)
        XCTAssertEqual(retained.rankedMoves.first?.move, "guard")
        XCTAssertEqual(HamptonArenaNumericalControl.replay(outcomes: [negative], field: "guardian"), retained)
    }

    func testMalformedOversizedRepeatedAndNonfiniteEvidenceFailsBeforeScopeFiltering() throws {
        let first = event(1)
        XCTAssertNil(HamptonArenaNumericalControl.replay(outcomes: (1...33).map { event($0) }, field: "guardian"))
        XCTAssertNil(HamptonArenaNumericalControl.replay(outcomes: [first, first], field: "guardian"))
        let reusedID = try altered(event(2)) { $0["actionID"] = first.actionID.lowercased() }
        XCTAssertNil(HamptonArenaNumericalControl.replay(outcomes: [first, reusedID], field: "guardian"))
        XCTAssertNil(HamptonArenaNumericalControl.replay(outcomes: [event(1, time: .infinity)], field: "guardian"))
        XCTAssertNil(HamptonArenaNumericalControl.replay(outcomes: [first], field: "unknown"))
        for (key, value) in [("integrityAfter", 35 as Any), ("round", 21 as Any), ("action", "unknown" as Any),
                             ("sparkAfter", 4 as Any), ("complete", true as Any), ("winner", "one" as Any)] {
            let malformed = try altered(event(2, field: "scout")) { $0[key] = value }
            XCTAssertNil(HamptonArenaNumericalControl.replay(outcomes: [first, malformed], field: "guardian"), key)
        }
        let terminal = event(1, boutID: bout, rivalIntegrity: 3, dealt: 3, taken: 0)
        let afterTerminal = event(2, boutID: bout.lowercased())
        XCTAssertNil(HamptonArenaNumericalControl.replay(outcomes: [terminal, afterTerminal], field: "guardian"))
    }

    func testAdviceMasksDepletedSignatureAndRejectsEmptyTerminalOrStaleContext() throws {
        let lastSpark = event(1, action: "signature", spark: 1, dealt: 10, taken: 0)
        let value = snapshot([lastSpark])
        let history = try history(value)
        let advice = try XCTUnwrap(ArenaMoveAdvice(history: history, snapshot: value, preparedAt: now))
        XCTAssertEqual(advice.receipt.rankedMoves.first?.move, "signature")
        XCTAssertEqual(advice.rankedMoves.map(\.move), ["guard", "pulse"])
        XCTAssertEqual(advice.selectedMove, "guard")
        XCTAssertTrue(advice.isValid)
        XCTAssertNil(ArenaMoveAdvice(history: history, snapshot: value, preparedAt: now.addingTimeInterval(6)))
        XCTAssertNil(ArenaMoveAdvice(history: history, snapshot: value, preparedAt: Date(timeIntervalSince1970: .infinity)))
        let empty = snapshot([])
        XCTAssertNil(ArenaMoveAdvice(history: try self.history(empty), snapshot: empty, preparedAt: now))
        let terminal = snapshot([event(1, rivalIntegrity: 3, dealt: 3, taken: 0)])
        XCTAssertNil(ArenaMoveAdvice(history: try self.history(terminal), snapshot: terminal, preparedAt: now))
        for changed in [snapshot([lastSpark], mode: "paired"), snapshot([lastSpark], mode: "unavailable", area: "companion"),
                        snapshot([lastSpark], sessionID: UUID().uuidString), snapshot([lastSpark], originDigest: String(repeating: "b", count: 64))] {
            XCTAssertNil(ArenaMoveAdvice(history: history, snapshot: changed, preparedAt: now))
        }
    }

    func testFrozenAdviceRoundTripsAndTamperedReceiptsCannotTrack() throws {
        let fixture = try prepared()
        let data = try JSONEncoder().encode(fixture.advice)
        let restored = try JSONDecoder().decode(ArenaMoveAdvice.self, from: data)
        XCTAssertEqual(restored, fixture.advice)
        XCTAssertEqual(restored.bindingDigest, fixture.advice.bindingDigest)
        XCTAssertTrue(restored.isValid)
        let exported = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(exported.contains("originDigest"))
        XCTAssertFalse(exported.contains(origin))
        let wrongMove = try altered(restored) { $0["selectedMove"] = "signature" }
        XCTAssertFalse(wrongMove.isValid)
        XCTAssertEqual(ArenaAdviceTracking(advice: wrongMove).status, .unlinked)
        let wrongNumerics = try altered(restored) { object in
            var receipt = object["receipt"] as! [String: Any]
            receipt["final"] = [1, 1, 1]
            object["receipt"] = receipt
        }
        XCTAssertFalse(wrongNumerics.isValid)
        XCTAssertEqual(ArenaAdviceTracking(advice: wrongNumerics).status, .unlinked)
    }

    func testTrackingLinksTheExactNextMatchingMoveOnceWithoutMutatingAdvice() throws {
        let fixture = try prepared()
        var tracking = ArenaAdviceTracking(advice: fixture.advice)
        tracking.observe(history: fixture.history, snapshot: fixture.snapshot, now: now)
        XCTAssertEqual(tracking.status, .pending)
        XCTAssertNil(tracking.outcome)
        let next = next(after: fixture.advice.baseOutcome, move: fixture.advice.selectedMove,
                        boutID: bout.lowercased())
        let third = self.next(after: next, move: "guard", time: now.timeIntervalSince1970 + 0.75)
        let observed = snapshot([fixture.advice.baseOutcome, next, third], at: now.addingTimeInterval(1))
        var history = fixture.history
        try history.ingest(observed)
        tracking.observe(history: history, snapshot: observed, now: now.addingTimeInterval(1))
        XCTAssertEqual(tracking.status, .matched)
        XCTAssertEqual(tracking.outcome, next, "Attribution uses the exact next action, not the latest action in a batch.")
        XCTAssertEqual(tracking.advice, fixture.advice)
        let resolved = tracking
        tracking.observe(history: history, snapshot: observed, now: now.addingTimeInterval(2))
        tracking.invalidate(reason: "Later disconnection does not rewrite an observed match.")
        XCTAssertEqual(tracking, resolved)
    }

    func testDifferentManualActionIsRecordedWithoutCreditingTheSuggestedMove() throws {
        let fixture = try prepared()
        XCTAssertEqual(fixture.advice.selectedMove, "pulse")
        let next = next(after: fixture.advice.baseOutcome, move: "guard")
        var history = fixture.history
        let value = snapshot([fixture.advice.baseOutcome, next], at: now.addingTimeInterval(1))
        try history.ingest(value)
        var tracking = ArenaAdviceTracking(advice: fixture.advice)
        tracking.observe(history: history, snapshot: value, now: now.addingTimeInterval(1))
        XCTAssertEqual(tracking.status, .differentAction)
        XCTAssertEqual(tracking.outcome?.action, "guard")
        XCTAssertEqual(tracking.advice.selectedMove, "pulse")
    }

    func testWrongBoutRoundFieldBeforeStateOrPreexistingActionCannotLink() throws {
        let fixture = try prepared()
        let validNext = next(after: fixture.advice.baseOutcome, move: "pulse")
        let changes: [(String, Any)] = [("boutID", UUID().uuidString), ("round", 3), ("field", "scout"),
                                      ("atUnix", now.timeIntervalSince1970 - 0.25)]
        var mismatches = try changes.map { key, value in try altered(validNext) { $0[key] = value } }
        mismatches.append(next(after: fixture.advice.baseOutcome, move: "pulse", integrity: 34))
        mismatches.append(next(after: fixture.advice.baseOutcome, move: "pulse", spark: 2))
        for mismatch in mismatches {
            let value = snapshot([fixture.advice.baseOutcome, mismatch], at: now.addingTimeInterval(1))
            var history = fixture.history
            try history.ingest(value)
            var tracking = ArenaAdviceTracking(advice: fixture.advice)
            tracking.observe(history: history, snapshot: value, now: now.addingTimeInterval(1))
            XCTAssertEqual(tracking.status, .unlinked)
            XCTAssertNil(tracking.outcome)
        }
    }

    func testLaterPollCannotCreditAnActionResolvedBeforeAdviceWasPrepared() throws {
        let fixture = try prepared()
        let alreadyResolved = next(after: fixture.advice.baseOutcome, move: fixture.advice.selectedMove,
                                   time: now.timeIntervalSince1970 - 0.25)
        let laterPoll = snapshot([fixture.advice.baseOutcome, alreadyResolved], at: now.addingTimeInterval(1))
        // The wire facts and next-round state are valid; only their attribution
        // to guidance prepared after this action is invalid.
        let verifiedHistory = try history(laterPoll)
        var tracking = ArenaAdviceTracking(advice: fixture.advice)
        tracking.observe(history: verifiedHistory, snapshot: laterPoll, now: now.addingTimeInterval(1))
        XCTAssertEqual(tracking.status, .unlinked)
        XCTAssertNil(tracking.outcome)
        XCTAssertTrue(try XCTUnwrap(tracking.reason).contains("preceded preparation"))
    }

    func testGapSessionChangeModeChangeStalenessAndExplicitEndInvalidatePendingAdvice() throws {
        let fixture = try prepared()
        let skipped = event(3, boutID: bout, round: 3, time: now.timeIntervalSince1970 + 0.5)
        let gap = snapshot([skipped], at: now.addingTimeInterval(1))
        var history = fixture.history
        try history.ingest(gap)
        var tracking = ArenaAdviceTracking(advice: fixture.advice)
        tracking.observe(history: history, snapshot: gap, now: now.addingTimeInterval(1))
        XCTAssertEqual(tracking.status, .unlinked)
        XCTAssertNil(tracking.outcome)

        for changed in [snapshot([fixture.advice.baseOutcome], mode: "paired"),
                        snapshot([fixture.advice.baseOutcome], mode: "unavailable", area: "companion"),
                        snapshot([fixture.advice.baseOutcome], sessionID: UUID().uuidString),
                        snapshot([fixture.advice.baseOutcome], originDigest: String(repeating: "b", count: 64))] {
            var candidate = ArenaAdviceTracking(advice: fixture.advice)
            candidate.observe(history: fixture.history, snapshot: changed, now: now)
            XCTAssertEqual(candidate.status, .unlinked)
        }
        var stale = ArenaAdviceTracking(advice: fixture.advice)
        stale.observe(history: fixture.history, snapshot: fixture.snapshot, now: now.addingTimeInterval(6))
        XCTAssertEqual(stale.status, .unlinked)
        var ended = ArenaAdviceTracking(advice: fixture.advice)
        ended.invalidate(reason: "Session ended.")
        ended.observe(history: fixture.history, snapshot: fixture.snapshot, now: now)
        XCTAssertEqual(ended.status, .unlinked)
        XCTAssertNil(ended.outcome)
    }

    private func prepared() throws -> (advice: ArenaMoveAdvice, history: WorldOutcomeHistory, snapshot: WorldOutcomeSnapshot) {
        let value = snapshot([event(1, boutID: bout, dealt: 7, taken: 4)])
        let history = try history(value)
        return (try XCTUnwrap(ArenaMoveAdvice(history: history, snapshot: value, preparedAt: now)), history, value)
    }

    private func next(after base: WorldActionOutcome, move: String, boutID: String? = nil,
                      integrity: Int? = nil, spark: Int? = nil, time: Double? = nil) -> WorldActionOutcome {
        event(base.sequence + 1, boutID: boutID ?? base.boutID, action: move, round: base.round + 1,
              integrity: integrity ?? base.integrityAfter, rivalIntegrity: base.rivalIntegrityAfter,
              spark: spark ?? base.sparkAfter, rivalSpark: base.rivalSparkAfter,
              dealt: move == "guard" ? 0 : 7, taken: move == "guard" ? 0 : 4,
              absorbed: move == "guard" ? 7 : 0, time: time ?? now.timeIntervalSince1970 + 0.5)
    }

    private func event(_ sequence: Int, boutID: String = UUID().uuidString, field: String = "guardian",
                       action: String = "pulse", round: Int = 1, integrity: Int = 36, rivalIntegrity: Int = 36,
                       spark: Int = 3, rivalSpark: Int = 3, dealt: Int = 3, taken: Int = 3, absorbed: Int = 0,
                       time: Double? = nil) -> WorldActionOutcome {
        let after = max(0, integrity - taken), rivalAfter = max(0, rivalIntegrity - dealt)
        let afterSpark = spark - (action == "signature" ? 1 : 0)
        let winner: String
        if after == 0 && rivalAfter == 0 { winner = "draw" }
        else if after == 0 { winner = "two" }
        else if rivalAfter == 0 { winner = "one" }
        else if round == 20 {
            winner = after == rivalAfter ? (afterSpark == rivalSpark ? "draw" : afterSpark > rivalSpark ? "one" : "two")
                : (after > rivalAfter ? "one" : "two")
        } else { winner = "" }
        return .init(sequence: sequence, actionID: UUID().uuidString, boutID: boutID, presentationRevision: 7,
                     atUnix: time ?? now.timeIntervalSince1970 - 0.5, action: action, rivalAction: "pulse",
                     field: field, round: round, integrityBefore: integrity, integrityAfter: after,
                     rivalIntegrityBefore: rivalIntegrity, rivalIntegrityAfter: rivalAfter,
                     sparkBefore: spark, sparkAfter: afterSpark, rivalSparkBefore: rivalSpark, rivalSparkAfter: rivalSpark,
                     damageDealt: dealt, damageTaken: taken, absorbed: absorbed, complete: !winner.isEmpty, winner: winner)
    }

    private func snapshot(_ outcomes: [WorldActionOutcome], at: Date? = nil, mode: String = "solo",
                          area: String = "arena", sessionID: String? = nil, originDigest: String? = nil) -> WorldOutcomeSnapshot {
        .init(schemaVersion: 1, sessionID: sessionID ?? session, originDigest: originDigest ?? origin, sessionKind: "companion",
              revision: 7, updatedAtUnix: (at ?? now).timeIntervalSince1970, currentArea: area, mode: mode,
              firstSequence: outcomes.first?.sequence ?? 0, lastSequence: outcomes.last?.sequence ?? 0, outcomes: outcomes)
    }

    private func history(_ value: WorldOutcomeSnapshot) throws -> WorldOutcomeHistory {
        let presentation = UnityPresentationSnapshot(schemaVersion: 1, sessionID: value.sessionID, revision: 7,
            originDigest: value.originDigest, displayName: "Fixture", body: "seed", appearance: "kin", cursor: "seed",
            seedAssetSHA256: String(repeating: "b", count: 64), bodyAssetSHA256: String(repeating: "b", count: 64),
            activity: "idle", lightMode: "rest", quiet: false, reduceMotion: false, visible: true,
            equippedFocusStaff: false, staffPalette: nil, staffCrown: nil, active: true,
            updatedAtUnix: value.updatedAtUnix, sessionKind: "companion", destination: "arena", destinationRevision: 1)
        try value.validate(matching: [presentation], now: Date(timeIntervalSince1970: value.updatedAtUnix))
        var history = WorldOutcomeHistory()
        try history.ingest(value)
        return history
    }

    private func altered<T: Codable>(_ value: T, _ edit: (inout [String: Any]) -> Void) throws -> T {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        edit(&object)
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
