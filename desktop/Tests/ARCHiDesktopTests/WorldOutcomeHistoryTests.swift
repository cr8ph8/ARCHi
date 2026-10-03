import Foundation
import XCTest
@testable import ARCHiDesktop

final class WorldOutcomeHistoryTests: XCTestCase {
    private let session = "E6F6D810-016B-4DDA-ADFD-A149CE61C453"
    private let bout = "D50F4D87-5019-4B95-A23C-65CF6623A865"

    func testPollingIsIdempotentAndOnlyNewFactsAppendAcrossModeChanges() throws {
        var history = WorldOutcomeHistory()
        try history.ingest(snapshot([]))
        XCTAssertEqual(history.consumedSequence, 0)
        let first = event(1), second = event(2), third = event(3)
        try history.ingest(snapshot([first, second]))
        let retained = history
        try history.ingest(snapshot([first, second], mode: "paired"))
        XCTAssertEqual(history, retained)
        try history.ingest(snapshot([second, third]))
        XCTAssertEqual(history.outcomes, [first, second, third])
        XCTAssertEqual(history.consumedSequence, 3)
        XCTAssertEqual(history.missingCount, 0)
    }

    func testOverlappingRewriteAtUnchangedCursorRejectsWholePoll() throws {
        let original = event(1)
        var history = WorldOutcomeHistory()
        try history.ingest(snapshot([original]))
        let before = history
        let changed = event(1, actionID: original.actionID, damage: 4)
        XCTAssertThrowsError(try history.ingest(snapshot([changed]))) {
            XCTAssertEqual($0 as? WorldOutcomeHistoryError, .rewrittenOutcome)
        }
        XCTAssertEqual(history, before)
        XCTAssertThrowsError(try history.ingest(snapshot([changed, event(2)])))
        XCTAssertEqual(history, before, "A rejected poll cannot advance cursor or append its otherwise new fact.")
    }

    func testActionIdentityCannotBeReusedAtAnotherSequence() throws {
        let first = event(1, actionID: "ABCDEF01-016B-4DDA-ADFD-A149CE61C453")
        var history = WorldOutcomeHistory()
        try history.ingest(snapshot([first]))
        let before = history
        // Each single-entry incoming snapshot is internally unique and valid.
        XCTAssertThrowsError(try history.ingest(snapshot([event(2, actionID: first.actionID)]))) {
            XCTAssertEqual($0 as? WorldOutcomeHistoryError, .duplicateActionID)
        }
        XCTAssertEqual(history, before)
        XCTAssertThrowsError(try history.ingest(snapshot([event(2, actionID: first.actionID.lowercased())]))) {
            XCTAssertEqual($0 as? WorldOutcomeHistoryError, .duplicateActionID)
        }
        XCTAssertEqual(history, before, "UUID letter case does not create a new action identity.")
        let second = event(2)
        try history.ingest(snapshot([second]))
        let afterSecond = history
        XCTAssertThrowsError(try history.ingest(snapshot([event(4, actionID: first.actionID)])))
        XCTAssertEqual(history, afterSecond, "An invalid new identity must not increase the missing count.")
    }

    func testSessionBindingAndBackwardsCursorRequireExplicitReset() throws {
        var history = WorldOutcomeHistory()
        // Even an empty first observation binds the consumer's session.
        try history.ingest(snapshot([]))
        XCTAssertThrowsError(try history.ingest(snapshot([], sessionID: UUID().uuidString))) {
            XCTAssertEqual($0 as? WorldOutcomeHistoryError, .changedSession)
        }
        try history.ingest(snapshot([event(2)]))
        let before = history
        XCTAssertThrowsError(try history.ingest(snapshot([event(1)]))) {
            XCTAssertEqual($0 as? WorldOutcomeError, .sequenceRegression)
        }
        XCTAssertThrowsError(try history.ingest(snapshot([])))
        XCTAssertThrowsError(try history.ingest(snapshot([event(2)], originDigest: String(repeating: "b", count: 64))))
        XCTAssertThrowsError(try history.ingest(snapshot([event(2)], kind: "localPractice")))
        XCTAssertEqual(history, before)
        history.reset()
        XCTAssertEqual(history, WorldOutcomeHistory())
        let newFirst = event(1)
        try history.ingest(snapshot([newFirst], sessionID: UUID().uuidString))
        XCTAssertEqual(history.outcomes, [newFirst])
        XCTAssertEqual(history.missingCount, 0)
    }

    func testGapsCountOnceWhileLocallyEvictedConsumedFactsAreNotMissing() throws {
        var history = WorldOutcomeHistory()
        let firstRing = (5...36).map { event($0) }
        try history.ingest(snapshot(firstRing))
        XCTAssertEqual(history.outcomes.count, 32)
        XCTAssertEqual(history.missingCount, 4)
        let nextRing = Array(firstRing.dropFirst()) + [event(37)]
        try history.ingest(snapshot(nextRing))
        XCTAssertEqual(history.outcomes, nextRing)
        XCTAssertEqual(history.missingCount, 4)
        let afterGap = [event(40), event(41)]
        try history.ingest(snapshot(afterGap))
        XCTAssertEqual(history.consumedSequence, 41)
        XCTAssertEqual(history.missingCount, 6)
        XCTAssertEqual(history.outcomes.count, 32)
        XCTAssertEqual(Array(history.outcomes.suffix(2)), afterGap)
        let beforeRepeat = history
        try history.ingest(snapshot(afterGap))
        XCTAssertEqual(history, beforeRepeat)
    }

    func testLargeSequenceGapDoesNotOverflowOrInventObservedEvents() throws {
        var history = WorldOutcomeHistory()
        let first = event(Int.max - 2)
        try history.ingest(snapshot([first]))
        XCTAssertEqual(history.missingCount, Int.max - 3)
        let last = event(Int.max)
        try history.ingest(snapshot([last]))
        XCTAssertEqual(history.missingCount, Int.max - 2)
        XCTAssertEqual(history.consumedSequence, Int.max)
        XCTAssertEqual(history.outcomes, [first, last])
        let before = history
        try history.ingest(snapshot([last]))
        XCTAssertEqual(history, before)
    }

    private func event(_ sequence: Int, actionID: String = UUID().uuidString, damage: Int = 3) -> WorldActionOutcome {
        .init(sequence: sequence, actionID: actionID, boutID: bout, presentationRevision: 1,
              atUnix: 100, action: "pulse", rivalAction: "pulse", field: "guardian", round: 1,
              integrityBefore: 30, integrityAfter: 27, rivalIntegrityBefore: 30, rivalIntegrityAfter: 30 - damage,
              sparkBefore: 3, sparkAfter: 3, rivalSparkBefore: 3, rivalSparkAfter: 3,
              damageDealt: damage, damageTaken: 3, absorbed: 0, complete: false, winner: "")
    }

    private func snapshot(_ outcomes: [WorldActionOutcome], sessionID: String? = nil,
                          originDigest: String = String(repeating: "a", count: 64),
                          kind: String = "companion", mode: String = "solo") -> WorldOutcomeSnapshot {
        .init(schemaVersion: 1, sessionID: sessionID ?? session, originDigest: originDigest,
              sessionKind: kind, revision: 1, updatedAtUnix: 101, currentArea: "arena", mode: mode,
              firstSequence: outcomes.first?.sequence ?? 0, lastSequence: outcomes.last?.sequence ?? 0,
              outcomes: outcomes)
    }
}
