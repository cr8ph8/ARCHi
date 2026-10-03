import Foundation
import XCTest
@testable import ARCHiDesktop

final class KnowledgeProcedureOutcomeTests: XCTestCase {
    private let requirements = DocumentWorkRequirements(mustBeShorter: false, preserveNumbersAndLinks: true)

    func testDefaultProjectionPreservesLegacyBindingsAndOmitsTheNewFlag() throws {
        let record = helpfulRecord(at: 1_000)
        let original = HamptonQ2EOutcomeAdapter(records: [record], requirements: requirements)
        let explicitDefault = HamptonQ2EOutcomeAdapter(records: [record], requirements: requirements,
            knowledgeUnavailableRecordIDs: [])
        XCTAssertEqual(original.evidence, explicitDefault.evidence)
        XCTAssertEqual(original.records, [record])
        XCTAssertEqual(original.evidence.support, 1)
        let binding = try XCTUnwrap(original.evidence.bindings.first)
        XCTAssertNil(binding.knowledgeDependencyUnavailable)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(binding)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertNil(object["knowledgeDependencyUnavailable"])
        let legacy = try JSONDecoder().decode(HamptonQ2EOutcomeBinding.self, from: bytes)
        XCTAssertEqual(legacy, binding)
        XCTAssertEqual(try encoder.encode(legacy), bytes)
        XCTAssertTrue(legacy.isValid)
    }

    func testUnavailableConceptRemovesHelpfulInfluenceButKeepsAttemptAndFrozenHistory() throws {
        let record = helpfulRecord(at: 1_000)
        let original = HamptonQ2EOutcomeAdapter(records: [record], requirements: requirements)
        let frozen = decide(original, sourceDigest: record.sourceDigest)
        let frozenBytes = try JSONEncoder().encode(frozen)
        let originalBinding = try XCTUnwrap(original.evidence.bindings.first)
        XCTAssertEqual(frozen.numericalControl?.steps.count, 1)

        let current = HamptonQ2EOutcomeAdapter(records: [record], requirements: requirements,
            knowledgeUnavailableRecordIDs: [record.id])
        XCTAssertTrue(current.evidence.isValid)
        XCTAssertEqual(current.records, [record], "Dependency loss must retain the source attempt and its Usage references.")
        XCTAssertEqual(current.evidence.bindings.count, 1)
        XCTAssertEqual(current.evidence.support, 0)
        XCTAssertEqual(current.evidence.corrections, 0)
        XCTAssertEqual(current.evidence.unknown, 1)
        XCTAssertEqual(current.signals(alternatives: 1, prerequisitesSatisfied: true).observations, 1)
        let bound = try XCTUnwrap(current.evidence.bindings.first)
        XCTAssertEqual(bound.knowledgeDependencyUnavailable, true)
        XCTAssertEqual(bound.recordDigest, originalBinding.recordDigest, "The historical record's bytes were not rewritten.")
        XCTAssertEqual(bound.requestID, originalBinding.requestID)
        XCTAssertEqual(bound.learning, originalBinding.learning)
        XCTAssertEqual(bound.feedback, originalBinding.feedback, "The user's earlier opinion remains inspectable.")
        XCTAssertEqual(bound.procedureUse, originalBinding.procedureUse)
        let recomputed = decide(current, sourceDigest: record.sourceDigest)
        XCTAssertTrue(recomputed.isValid)
        XCTAssertEqual(recomputed.signals.retainedSupport, 0)
        XCTAssertEqual(recomputed.numericalControl?.steps.count, 0)
        XCTAssertNotEqual(recomputed.bindingDigest, frozen.bindingDigest,
            "A pending Send comparison must observe changed dependency evidence.")
        XCTAssertNotEqual(recomputed, frozen)
        let restored = try JSONDecoder().decode(HamptonQ2EDecision.self, from: frozenBytes)
        XCTAssertEqual(restored, frozen)
        XCTAssertTrue(restored.isValid)
        XCTAssertEqual(restored.outcomeEvidence?.support, 1, "The earlier frozen decision remains historical evidence.")
    }

    func testUnavailableProjectionKeepsScopeWindowAndConflictValidation() throws {
        let records = (0..<10).map { helpfulRecord(at: Double(1_000 + $0)) }
        let newest = try XCTUnwrap(records.last)
        let current = HamptonQ2EOutcomeAdapter(records: records + [newest], requirements: requirements,
            knowledgeUnavailableRecordIDs: [newest.id])
        XCTAssertEqual(current.records, Array(records.reversed().prefix(8)))
        XCTAssertEqual(current.evidence.bindings.count, 8)
        XCTAssertEqual(current.evidence.support, 7)
        XCTAssertEqual(current.evidence.unknown, 1)
        XCTAssertNil(current.evidence.reconciliationIssue)
        var conflicting = newest
        conflicting.mustBeShorter = true
        let conflict = HamptonQ2EOutcomeAdapter(records: [newest, conflicting], requirements: requirements,
            knowledgeUnavailableRecordIDs: [newest.id])
        XCTAssertEqual(conflict.evidence.reconciliationIssue, "conflicting-record")
        XCTAssertTrue(conflict.records.isEmpty)
        var corrected = newest
        corrected.procedureUseRejected = true
        let binding = try XCTUnwrap(HamptonQ2EOutcomeBinding(record: corrected, knowledgeDependencyUnavailable: true))
        XCTAssertEqual(binding.disposition, .unknown, "Unavailable knowledge takes precedence over other dispositions.")
    }

    func testUnavailableFlagRequiresAProcedureAndRejectsExplicitFalseOnDecode() throws {
        var ordinary = helpfulRecord(at: 1_000)
        ordinary.procedureUse = nil
        XCTAssertNil(HamptonQ2EOutcomeBinding(record: ordinary, knowledgeDependencyUnavailable: true))
        let valid = try XCTUnwrap(HamptonQ2EOutcomeBinding(record: helpfulRecord(at: 1_000)))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any])
        object["knowledgeDependencyUnavailable"] = false
        let decoded = try JSONDecoder().decode(HamptonQ2EOutcomeBinding.self,
            from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(decoded.isValid, "The serialized flag has only two states: omitted or true.")
        XCTAssertEqual(decoded.disposition, .unknown)
    }

    private func decide(_ projection: HamptonQ2EOutcomeAdapter, sourceDigest: String) -> HamptonQ2EDecision {
        HamptonQ2EController.decide(domain: "document-revision", contextID: sourceDigest,
            signals: projection.signals(alternatives: 1, prerequisitesSatisfied: true), outcomeEvidence: projection.evidence)
    }

    private func helpfulRecord(at timestamp: Double) -> DocumentWorkRecord {
        let id = UUID().uuidString
        let source = String(repeating: "a", count: 64)
        let after = String(repeating: "b", count: 64)
        let reviewTime = Date(timeIntervalSince1970: timestamp + 0.5)
        let decision = HamptonQ2EController.decide(domain: "document-revision", contextID: source,
            signals: HamptonQ2ESignals(observations: 0, retainedSupport: 0, contradictions: 0,
                unchangedSteps: 0, availableAlternatives: 1, remainingBudget: 1, totalBudget: 1),
            useNumericalControl: false)
        return DocumentWorkRecord(id: id + "-" + AssistantProvider.qwen.rawValue, requestID: id,
            provider: AssistantProvider.qwen.rawValue, targetID: UUID().uuidString,
            sourceDigest: source, sourceRevision: 1, selectionStart: 0, selectionLength: 12,
            preserveNumbersAndLinks: true, createdAt: Date(timeIntervalSince1970: timestamp), updatedAt: reviewTime,
            state: .applied, proposedDigest: after, expectedAfterDigest: after, actualAfterDigest: after,
            afterRevision: 2, checks: [.init(id: "source", title: "Exact source binding", passed: true)],
            learning: .init(requestBinding: .init(inputDigest: source, contextDigest: after)),
            feedback: .init(revision: 1, verdict: .helpful, recordedAt: reviewTime),
            procedureUse: .init(id: UUID().uuidString, revision: 1, digest: String(repeating: "c", count: 64)),
            q2eDecision: decision)
    }
}
