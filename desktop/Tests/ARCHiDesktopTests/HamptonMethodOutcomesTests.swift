import Foundation
import XCTest
@testable import ARCHiDesktop

final class HamptonMethodOutcomesTests: XCTestCase {
    func testDifferentRecordIDsCannotCountOneOwnerTwice() {
        let method = binding()
        let original = record(method)
        let single = HamptonMethodOutcomes(procedure: method, records: [original])
        XCTAssertNil(single.reconciliationIssue)
        XCTAssertEqual(single.helpful, 1)
        XCTAssertEqual(HamptonMethodOutcomes(procedure: method, records: [original, original]), single,
                       "An exact reread remains one owner and one review.")

        var duplicate = original
        duplicate.id = UUID().uuidString
        duplicate.feedback = feedback(.helpful)
        duplicate.updatedAt = Date(timeIntervalSince1970: 2_000)
        let ambiguous = HamptonMethodOutcomes(procedure: method, records: [original, duplicate])
        XCTAssertEqual(ambiguous.reconciliationIssue, .repeatedRequestProvider)
        XCTAssertEqual(ambiguous.attempts, 0)
        XCTAssertEqual(ambiguous.helpful, 0)
        let empty = HamptonMethodOutcomes(procedure: method, records: [])
        XCTAssertNotEqual(ambiguous, empty, "Unavailable evidence must remain distinct from no history.")
        XCTAssertEqual(HamptonMethodOutcomes(procedure: method, records: [duplicate, original]), ambiguous,
                       "A newer alias cannot acquire priority through record order or recency.")
        XCTAssertFalse(HamptonMethodOutcomes.rankBefore(lhs: ambiguous, rhs: single))
        XCTAssertFalse(HamptonMethodOutcomes.rankBefore(lhs: single, rhs: ambiguous))
    }

    func testOwnershipConflictAcrossVersionsIsRejectedBeforeFiltering() {
        let first = binding()
        let second = DocumentProcedureUse(id: first.id, revision: 2, digest: hex("b"))
        let unrelated = binding()
        let original = record(first)
        var alias = original
        alias.id = UUID().uuidString
        alias.procedureUse = second
        alias.feedback = feedback(.helpful)
        let records = [original, alias, record(unrelated)]

        for method in [first, second, unrelated] {
            let result = HamptonMethodOutcomes(procedure: method, records: records)
            XCTAssertEqual(result.reconciliationIssue, .repeatedRequestProvider)
            XCTAssertEqual(result.helpful, 0, "A filtered method cannot retain a partial positive sample.")
        }
        XCTAssertEqual(HamptonMethodOutcomes(records: records).reconciliationIssue, .repeatedRequestProvider)
    }

    func testConflictingRecordVariantCannotHideCrossVersionOwnershipInEitherOrder() {
        let first = binding()
        let second = DocumentProcedureUse(id: first.id, revision: 2, digest: hex("b"))
        let original = record(first)
        let other = record(second)
        var conflicting = original
        conflicting.requestID = other.requestID
        conflicting.procedureUse = second
        conflicting.feedback = feedback(.helpful)

        for variants in [[original, conflicting], [conflicting, original]] {
            let isolatedConflict = HamptonMethodOutcomes(records: variants)
            XCTAssertNil(isolatedConflict.reconciliationIssue,
                         "One contradictory record keeps its existing exclusion behavior.")
            XCTAssertEqual(isolatedConflict.attempts, 0)
            for records in [variants + [other], [other] + variants] {
                for method in [first, second] {
                    let result = HamptonMethodOutcomes(procedure: method, records: records)
                    XCTAssertEqual(result.reconciliationIssue, .repeatedRequestProvider)
                    XCTAssertEqual(result.helpful, 0,
                                   "No first-record choice may leave the shared owner's second version credited.")
                }
                XCTAssertEqual(HamptonMethodOutcomes(records: records).reconciliationIssue, .repeatedRequestProvider)
            }
        }
    }

    func testDistinctRequestsKeepReviewRankingAndPermanentCorrections() {
        let stronger = binding(), weaker = binding()
        var rejected = record(weaker)
        rejected.procedureUseRejected = true
        let records = [record(stronger), record(stronger), record(weaker),
                       record(weaker, verdict: .needsCorrection), rejected]
        let preferred = HamptonMethodOutcomes(procedure: stronger, records: records)
        let corrected = HamptonMethodOutcomes(procedure: weaker, records: records)
        XCTAssertNil(preferred.reconciliationIssue)
        XCTAssertNil(corrected.reconciliationIssue)
        XCTAssertEqual(preferred.helpful, 2)
        XCTAssertEqual(corrected.helpful, 1)
        XCTAssertEqual(corrected.needsCorrection, 2,
                       "A retained rejection remains negative even after a Helpful verdict.")
        XCTAssertTrue(HamptonMethodOutcomes.rankBefore(lhs: preferred, rhs: corrected))
        XCTAssertFalse(HamptonMethodOutcomes.rankBefore(lhs: corrected, rhs: preferred))

        var otherProvider = records[0]
        otherProvider.id = UUID().uuidString
        otherProvider.provider = AssistantProvider.codex.rawValue
        otherProvider.feedback = feedback(.helpful)
        let separateLane = HamptonMethodOutcomes(procedure: stronger, records: records + [otherProvider])
        XCTAssertNil(separateLane.reconciliationIssue, "Different providers remain distinct lanes of one request.")
        XCTAssertEqual(separateLane.helpful, 3)
    }

    private func binding() -> DocumentProcedureUse {
        .init(id: UUID().uuidString, revision: 1, digest: hex("a"))
    }

    private func record(_ method: DocumentProcedureUse,
                        verdict: DocumentWorkFeedback.Verdict = .helpful) -> DocumentWorkRecord {
        let request = UUID().uuidString
        return DocumentWorkRecord(id: request + "-" + AssistantProvider.qwen.rawValue,
            requestID: request, provider: AssistantProvider.qwen.rawValue, targetID: UUID().uuidString,
            sourceDigest: hex("a"), sourceRevision: 1, selectionStart: 0, selectionLength: 12,
            preserveNumbersAndLinks: true, createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_002), state: .applied,
            proposedDigest: hex("b"), expectedAfterDigest: hex("b"), actualAfterDigest: hex("b"),
            afterRevision: 2, checks: [.init(id: "source", title: "Exact source", passed: true)],
            learning: .init(requestBinding: .init(inputDigest: hex("c"), contextDigest: hex("d"))),
            feedback: feedback(verdict), procedureUse: method,
            procedureUseRejected: verdict == .helpful ? nil : true)
    }

    private func feedback(_ verdict: DocumentWorkFeedback.Verdict) -> DocumentWorkFeedback {
        .init(revision: 1, verdict: verdict, recordedAt: Date(timeIntervalSince1970: 1_001))
    }

    private func hex(_ value: Character) -> String { String(repeating: String(value), count: 64) }
}
