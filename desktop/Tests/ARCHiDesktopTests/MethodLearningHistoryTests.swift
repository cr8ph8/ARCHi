import Foundation
import XCTest
@testable import ARCHiDesktop

@MainActor
final class MethodLearningHistoryTests: XCTestCase {
    func testOnlyExactUsesCountAndUnreviewedAppliedWorkComesFirst() throws {
        let method = binding()
        let helpful = record(method, verdict: .helpful)
        var waiting = record(method)
        waiting.updatedAt = helpful.updatedAt.addingTimeInterval(-10)
        let changedVersion = record(.init(id: method.id, revision: 2, digest: method.digest), verdict: .helpful)
        let changedDigest = record(.init(id: method.id, revision: 1, digest: hex("f")), verdict: .helpful)
        let ordinaryOrigin = record(nil, verdict: .helpful)
        let history = try XCTUnwrap(MethodLearningHistory(procedure: method,
            records: [helpful, waiting, changedVersion, changedDigest, ordinaryOrigin, helpful], historyIsCurrent: true))
        XCTAssertEqual(history.records.map(\.id), [waiting.id, helpful.id])
        XCTAssertEqual(history.outcomes.attempts, 2)
        XCTAssertEqual(history.outcomes.helpful, 1)
        XCTAssertEqual(history.outcomes.awaitingReview, 1)
        XCTAssertEqual(MethodLearningHistory.disposition(of: waiting), .awaitingReview)
    }

    func testProposalsFailuresAndIncompleteApplyNeverBecomeHelpfulOrReviewableEvidence() throws {
        let method = binding()
        var records = [DocumentWorkRecord.State.proposing, .ready, .blocked, .failed, .cancelled].map {
            record(method, state: $0)
        }
        var incomplete = record(method)
        incomplete.actualAfterDigest = hex("f")
        records.append(incomplete)
        let history = try XCTUnwrap(MethodLearningHistory(procedure: method, records: records, historyIsCurrent: true))
        XCTAssertEqual(history.outcomes.attempts, 6)
        XCTAssertEqual(history.outcomes.helpful, 0)
        XCTAssertEqual(history.outcomes.awaitingReview, 0)
        XCTAssertEqual(MethodLearningHistory.disposition(of: incomplete), .unverifiedApplied)
        XCTAssertEqual(MethodLearningHistory.disposition(of: records[1]), .other(.ready))
        XCTAssertTrue(records.allSatisfy { $0.feedback == nil })
    }

    func testCounterexampleSurvivesHelpfulReviewAndUndoDoesNotRemainHelpful() throws {
        let method = binding()
        var counterexample = record(method, verdict: .helpful)
        counterexample.procedureUseRejected = true
        let withdrawn = record(method, verdict: .withdrawn)
        let correction = record(method, verdict: .needsCorrection)
        let undone = record(method, state: .undone, verdict: .helpful)
        let history = try XCTUnwrap(MethodLearningHistory(procedure: method,
            records: [counterexample, withdrawn, correction, undone], historyIsCurrent: true))
        XCTAssertEqual(history.outcomes.helpful, 0)
        XCTAssertEqual(history.outcomes.needsCorrection, 3)
        XCTAssertEqual(history.outcomes.undone, 1)
        XCTAssertEqual(MethodLearningHistory.disposition(of: counterexample), .counterexample)
        XCTAssertEqual(MethodLearningHistory.disposition(of: withdrawn), .withdrawnReview)
        XCTAssertEqual(MethodLearningHistory.disposition(of: correction), .needsCorrection)
        XCTAssertEqual(MethodLearningHistory.disposition(of: undone), .undone)
    }

    func testStaleConflictingOrOversizedHistoryCannotLookLikeNoOutcomes() {
        let method = binding()
        let positive = record(method, verdict: .helpful)
        var conflicting = positive
        conflicting.procedureUse = binding()
        XCTAssertNil(MethodLearningHistory(procedure: method, records: [positive, conflicting], historyIsCurrent: true))
        XCTAssertNil(MethodLearningHistory(procedure: method, records: [positive], historyIsCurrent: false))
        XCTAssertNil(MethodLearningHistory(procedure: method, records: (0..<65).map { _ in record(method) }, historyIsCurrent: true))
        XCTAssertNil(MethodLearningHistory(procedure: .init(id: "invalid", revision: 0, digest: "invalid"),
            records: [], historyIsCurrent: true))
    }

    func testNextActionExplainsOwnerEligibilityWithoutRecommendingBlockedReuse() {
        func guide(reason: String? = nil, historical: Bool = false, working: Bool = false,
                   revise: Bool = true, selection: Bool = true, matches: Bool = true,
                   canPrepare: Bool = true) -> MethodLearningReuseGuidance {
            .init(unavailableReason: reason, isHistorical: historical, isWorking: working,
                  requestsRevision: revise, hasCurrentSelection: selection,
                  requirementsMatch: matches, canPrepare: canPrepare)
        }
        XCTAssertEqual(guide(reason: "Supporting source was withdrawn.", working: true),
                       .unavailable("Supporting source was withdrawn."))
        XCTAssertEqual(guide(historical: true), .historical)
        XCTAssertEqual(guide(working: true, revise: false), .finishWork)
        XCTAssertEqual(guide(revise: false, selection: false), .chooseRevise)
        XCTAssertEqual(guide(selection: false, matches: false), .selectPassage)
        XCTAssertEqual(guide(matches: false), .matchRequirements)
        XCTAssertEqual(guide(canPrepare: false), .unavailablePreparation)
        XCTAssertEqual(guide(), .ready)
    }

    func testJournalReloadAndRepeatedProjectionNeitherReviewNorReplayWork() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-method-history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("work.json")
        let method = binding()
        let journal = DocumentWorkJournal(url: url)
        var value = record(method, state: .applying)
        try journal.save(value)
        value.state = .applied
        try journal.save(value)
        let bytes = try Data(contentsOf: url)
        let reopened = DocumentWorkJournal(url: url)
        XCTAssertNil(reopened.loadError)
        let first = try XCTUnwrap(MethodLearningHistory(procedure: method, records: reopened.records,
                                                       historyIsCurrent: reopened.isCurrentOnDisk))
        let again = MethodLearningHistory(procedure: method, records: reopened.records,
                                         historyIsCurrent: reopened.isCurrentOnDisk)
        XCTAssertEqual(first, again)
        XCTAssertEqual(first.outcomes.awaitingReview, 1)
        XCTAssertEqual(first.outcomes.helpful, 0)
        XCTAssertNil(reopened.records.first?.feedback)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(first.records.first?.procedureUse, method)
    }

    private func binding() -> DocumentProcedureUse {
        .init(id: UUID().uuidString, revision: 1, digest: hex("a"))
    }

    private func hex(_ value: Character) -> String { String(repeating: String(value), count: 64) }

    private func record(_ method: DocumentProcedureUse?, state: DocumentWorkRecord.State = .applied,
                        verdict: DocumentWorkFeedback.Verdict? = nil) -> DocumentWorkRecord {
        let request = UUID().uuidString
        let created = Date(timeIntervalSince1970: 1_000)
        var value = DocumentWorkRecord(id: request + "-Qwen", requestID: request, provider: "Qwen",
            targetID: UUID().uuidString, sourceDigest: hex("a"), sourceRevision: 1,
            selectionStart: 0, selectionLength: 12, preserveNumbersAndLinks: true,
            createdAt: created, updatedAt: created.addingTimeInterval(20), state: state,
            proposedDigest: hex("b"), expectedAfterDigest: hex("c"), actualAfterDigest: hex("c"), afterRevision: 2,
            checks: [.init(id: "source", title: "Exact source", passed: true)],
            learning: .init(requestBinding: .init(inputDigest: hex("d"), contextDigest: hex("e")), suppliedLessons: []),
            procedureUse: method)
        if let verdict {
            value.feedback = .init(revision: 1, verdict: verdict, recordedAt: created.addingTimeInterval(10))
        }
        return value
    }
}
