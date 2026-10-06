import Foundation
import XCTest
@testable import ARCHiDesktop

@MainActor
final class DocumentReviewQueueTests: XCTestCase {
    func testOrdinaryAndExactMethodOutcomesShareOldestFirstQueue() throws {
        let ordinary = record(created: 1_000)
        var methodUse = record(created: 2_000, method: method())
        methodUse.mustBeShorter = true
        var latest = record(created: 3_000)
        latest.preserveNumbersAndLinks = false
        let input = [latest, methodUse, ordinary]
        let queue = try XCTUnwrap(DocumentReviewQueue(records: input, historyIsCurrent: true,
            reviewableRecordIDs: Set(input.map(\.id)), currentOutcomeID: nil))
        XCTAssertEqual(queue.records, [ordinary, methodUse, latest])
        XCTAssertNil(queue.records.first?.procedureUse)
        XCTAssertEqual(queue.records[1].procedureUse, methodUse.procedureUse)
        XCTAssertEqual(queue.blockedCount, 0)
        XCTAssertTrue(queue.records.allSatisfy { $0.feedback == nil })
    }

    func testSameTimeTiesUseRecordIdentityRatherThanInputOrUpdateOrder() throws {
        var first = record(id: "a", created: 1_000)
        let second = record(id: "z", created: 1_000)
        first.updatedAt = second.updatedAt.addingTimeInterval(100)
        let queue = try XCTUnwrap(DocumentReviewQueue(records: [second, first], historyIsCurrent: true,
            reviewableRecordIDs: [first.id, second.id], currentOutcomeID: nil))
        XCTAssertEqual(queue.records, [first, second])
    }

    func testExactDuplicatesDeduplicateAndCurrentOutcomeIsNotCountedTwice() throws {
        let current = record(created: 3_000)
        let older = record(created: 1_000)
        let blocked = record(created: 2_000, method: method())
        let queue = try XCTUnwrap(DocumentReviewQueue(records: [current, older, blocked, older, blocked],
            historyIsCurrent: true, reviewableRecordIDs: [current.id, older.id], currentOutcomeID: current.id))
        XCTAssertEqual(queue.records, [older])
        XCTAssertEqual(queue.blockedCount, 1)
        let currentIneligible = try XCTUnwrap(DocumentReviewQueue(records: [current, older, blocked],
            historyIsCurrent: true, reviewableRecordIDs: [older.id], currentOutcomeID: current.id))
        XCTAssertEqual(currentIneligible, queue, "The current outcome is excluded from both displayed and blocked counts.")
    }

    func testStaleOversizedAndConflictingWholeScopesFailBeforeFiltering() throws {
        let valid = record()
        XCTAssertNil(DocumentReviewQueue(records: [valid], historyIsCurrent: false,
            reviewableRecordIDs: [valid.id], currentOutcomeID: nil))
        var excluded = record(state: .ready)
        var conflict = excluded
        conflict.detail = "Conflicting duplicate outside the awaiting-review scope."
        XCTAssertNil(DocumentReviewQueue(records: [valid, excluded, conflict], historyIsCurrent: true,
            reviewableRecordIDs: [valid.id], currentOutcomeID: nil))
        let oversized = (0..<65).map { record(id: "excluded-\($0)", state: .ready) }
        XCTAssertNil(DocumentReviewQueue(records: oversized, historyIsCurrent: true,
            reviewableRecordIDs: [], currentOutcomeID: nil))
        let maximum = Array(oversized.prefix(64))
        XCTAssertNotNil(DocumentReviewQueue(records: maximum + [maximum[0]], historyIsCurrent: true,
            reviewableRecordIDs: [], currentOutcomeID: nil), "The bound counts unique identities, not identical snapshots.")
        excluded.id = valid.id
        XCTAssertNil(DocumentReviewQueue(records: [valid, excluded], historyIsCurrent: true,
            reviewableRecordIDs: [], currentOutcomeID: valid.id), "Excluding the current outcome cannot hide a conflicting identity.")
    }

    func testIncompleteEvidenceNonAppliedWorkAndPriorVerdictsAreNotAwaitingReview() throws {
        var missingLearning = record(); missingLearning.learning = nil
        var mismatchedDigest = record(); mismatchedDigest.actualAfterDigest = hex("f")
        var missingProposedDigest = record(); missingProposedDigest.proposedDigest = nil
        var failedCheck = record(); failedCheck.checks[0].passed = false
        var noChecks = record(); noChecks.checks = []
        var noRevision = record(); noRevision.afterRevision = nil
        var counterexample = record(method: method()); counterexample.procedureUseRejected = true
        let nonApplied: [DocumentWorkRecord.State] = [.proposing, .ready, .blocked, .applying,
                                                     .undoing, .undone, .dismissed, .cancelled, .failed]
        let reviewed = [DocumentWorkFeedback.Verdict.helpful, .needsCorrection, .withdrawn].map { verdict in
            var value = record()
            value.feedback = .init(revision: 1, verdict: verdict, recordedAt: value.createdAt.addingTimeInterval(10))
            return value
        }
        let input = [missingLearning, mismatchedDigest, missingProposedDigest, failedCheck, noChecks,
                     noRevision, counterexample] + nonApplied.map { record(state: $0) } + reviewed
        let queue = try XCTUnwrap(DocumentReviewQueue(records: input, historyIsCurrent: true,
            reviewableRecordIDs: Set(input.map(\.id)), currentOutcomeID: nil))
        XCTAssertTrue(queue.records.isEmpty)
        XCTAssertEqual(queue.blockedCount, 0, "Incomplete evidence is not a strict pending review blocked only by current eligibility.")
    }

    func testOwnerEligibilityControlsActionableAndBlockedCountsWithoutChangingHistory() throws {
        let ordinary = record()
        let dependent = record(method: method())
        let input = [ordinary, dependent]
        let available = try XCTUnwrap(DocumentReviewQueue(records: input, historyIsCurrent: true,
            reviewableRecordIDs: [ordinary.id, dependent.id], currentOutcomeID: nil))
        XCTAssertEqual(available.records.count, 2)
        let withdrawnDependency = try XCTUnwrap(DocumentReviewQueue(records: input, historyIsCurrent: true,
            reviewableRecordIDs: [ordinary.id], currentOutcomeID: nil))
        XCTAssertEqual(withdrawnDependency.records, [ordinary])
        XCTAssertEqual(withdrawnDependency.blockedCount, 1)
        let blocked = try XCTUnwrap(DocumentReviewQueue(records: input, historyIsCurrent: true,
            reviewableRecordIDs: [], currentOutcomeID: nil))
        XCTAssertTrue(blocked.records.isEmpty)
        XCTAssertEqual(blocked.blockedCount, 2)
        XCTAssertEqual(input, [ordinary, dependent])
        XCTAssertNil(dependent.feedback)
        XCTAssertEqual(dependent.state, .applied)
    }

    func testReloadProjectsPendingReviewsWithoutReplayingOrWriting() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-review-queue-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("work.json")
        let journal = DocumentWorkJournal(url: url)
        var ordinary = record(state: .applying, created: 1_000)
        try journal.save(ordinary)
        ordinary.state = .applied
        try journal.save(ordinary)
        var methodUse = record(state: .applying, created: 2_000, method: method())
        try journal.save(methodUse)
        methodUse.state = .applied
        try journal.save(methodUse)
        let bytes = try Data(contentsOf: url)
        let reopened = DocumentWorkJournal(url: url)
        XCTAssertNil(reopened.loadError)
        let eligible = Set([ordinary.id, methodUse.id])
        let first = try XCTUnwrap(DocumentReviewQueue(records: reopened.records,
            historyIsCurrent: reopened.isCurrentOnDisk, reviewableRecordIDs: eligible, currentOutcomeID: nil))
        let second = DocumentReviewQueue(records: reopened.records,
            historyIsCurrent: reopened.isCurrentOnDisk, reviewableRecordIDs: eligible, currentOutcomeID: nil)
        XCTAssertEqual(first.records, [ordinary, methodUse])
        XCTAssertEqual(second, first)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertTrue(reopened.records.allSatisfy { $0.feedback == nil && $0.state == .applied })
    }

    private func method() -> DocumentProcedureUse {
        .init(id: UUID().uuidString, revision: 1, digest: hex("e"))
    }

    private func hex(_ value: Character) -> String { String(repeating: String(value), count: 64) }

    private func record(id: String? = nil, state: DocumentWorkRecord.State = .applied,
                        created: TimeInterval = 1_000, method: DocumentProcedureUse? = nil) -> DocumentWorkRecord {
        let request = UUID().uuidString
        let date = Date(timeIntervalSince1970: created)
        return DocumentWorkRecord(id: id ?? request + "-Qwen", requestID: request, provider: "Qwen",
            targetID: UUID().uuidString, sourceDigest: hex("a"), sourceRevision: 1,
            selectionStart: 0, selectionLength: 12, preserveNumbersAndLinks: true,
            createdAt: date, updatedAt: date.addingTimeInterval(20), state: state,
            proposedDigest: hex("b"), expectedAfterDigest: hex("c"), actualAfterDigest: hex("c"), afterRevision: 2,
            checks: [.init(id: "source", title: "Exact source", passed: true)],
            learning: .init(requestBinding: .init(inputDigest: hex("d"), contextDigest: hex("e")), suppliedLessons: []),
            procedureUse: method)
    }
}
