import Foundation
import XCTest
@testable import ARCHiDesktop

final class HamptonMethodResourceOutcomesTests: XCTestCase {
    func testChargesEveryMeasuredAttemptIncludingContextAndFailedRecovery() throws {
        let method = procedure("Method")
        var evidence = bundle(method, costs: [100, 300], helpful: [0])
        let request = evidence.records[1].requestID
        evidence.observations += [observation(request, id: "failed", tokens: 200, outcome: "failed"),
                                  observation(request, id: "memory", tokens: 50, role: .memoryReminder)]
        let result = try XCTUnwrap(resource(method, evidence))
        XCTAssertEqual(result.totalTokens, 650)
        XCTAssertEqual(result.recordedUses, 2)
        XCTAssertEqual(result.localAttempts, 4)
        XCTAssertEqual(result.helpfulResults, 1)
        // Re-reading and identical duplicate document records do not add cost.
        evidence.records.append(evidence.records[0])
        XCTAssertEqual(resource(method, evidence), result)
    }

    func testIncompleteLegacyImportedAndMalformedAccountingRemainUnknown() {
        let method = procedure("Method")
        let original = bundle(method, costs: [100], helpful: [0])
        var missing = original
        missing.observations = [observation(missing.records[0].requestID, tokens: nil)]
        XCTAssertNil(resource(method, missing))
        var legacy = original
        legacy.observations[0].modelDigest = nil
        XCTAssertNil(resource(method, legacy))
        var unmeasured = original
        unmeasured.tasks[0].lanes[0].localAttemptsMeasured = false
        XCTAssertNil(resource(method, unmeasured))
        var pending = original
        pending.tasks[0].lanes[0].state = "pending"
        XCTAssertNil(resource(method, pending))
        var imported = original
        imported.observations = [observation(imported.records[0].requestID, tokens: 100, account: "external-import")]
        XCTAssertNil(resource(method, imported))
        var unresolved = original
        unresolved.observations.append(observation(unresolved.records[0].requestID, id: "failed", tokens: nil, outcome: "failed"))
        XCTAssertNil(resource(method, unresolved), "A failed unmeasured retry cannot be discarded.")
        var overlap = original
        overlap.observations = [observation(overlap.records[0].requestID, tokens: 100, cacheRead: 70, cacheWrite: 70)]
        XCTAssertNil(resource(method, overlap))
        var overflow = original
        overflow.observations += [observation(overflow.records[0].requestID, id: "huge", tokens: Int64.max)]
        XCTAssertNil(resource(method, overflow))
    }

    func testExactProcedureVersionAndLaneOwnershipPreventPooling() throws {
        let method = procedure("Method")
        var evidence = bundle(method, costs: [100], helpful: [0])
        let changedVersion = DocumentProcedureUse(id: method.id, revision: 2, digest: hex("f"))
        XCTAssertNil(HamptonMethodResourceOutcomes(procedure: changedVersion, records: evidence.records,
            tasks: evidence.tasks, observations: evidence.observations))
        var impostor = evidence.records[0]
        impostor.id = "another-record"
        impostor.procedureUse = changedVersion
        evidence.records.append(impostor)
        XCTAssertNil(resource(method, evidence), "One lane cannot be claimed by another version under a new record ID.")
        evidence = bundle(method, costs: [100], helpful: [0])
        evidence.observations.append(evidence.observations[0])
        XCTAssertNil(resource(method, evidence), "Duplicate attempt identities cannot double count tokens.")
    }

    func testCostRefinesOnlyWholeQualifiedQualityCohort() throws {
        let expensive = procedure("Expensive"), cheap = procedure("Cheap"), strongest = procedure("Strongest")
        let first = bundle(expensive, costs: [500], helpful: [0])
        let second = bundle(cheap, costs: [100], helpful: [0])
        let best = bundle(strongest, costs: [900, 900], helpful: [0, 1])
        let qualities = [expensive.binding: quality(expensive, first), cheap.binding: quality(cheap, second),
                         strongest.binding: quality(strongest, best)]
        let costs = [expensive.binding: try XCTUnwrap(resource(expensive, first)),
                     cheap.binding: try XCTUnwrap(resource(cheap, second)),
                     strongest.binding: try XCTUnwrap(resource(strongest, best))]
        let ordered = [strongest, expensive, cheap]
        XCTAssertEqual(HamptonMethodResourceOutcomes.refineEqualQualityOrder(ordered,
            outcomes: qualities, resources: costs).map(\.id), [strongest.id, cheap.id, expensive.id])
        let unknown = procedure("Unknown")
        let unknownEvidence = bundle(unknown, costs: [100], helpful: [0])
        var extendedQuality = qualities
        extendedQuality[unknown.binding] = quality(unknown, unknownEvidence)
        let withUnknown = [strongest, expensive, unknown, cheap]
        XCTAssertEqual(HamptonMethodResourceOutcomes.refineEqualQualityOrder(withUnknown,
            outcomes: extendedQuality, resources: costs), withUnknown)
    }

    func testMismatchedSourceOrModelPreservesWholeCohortOrder() throws {
        let first = procedure("First"), second = procedure("Second")
        let a = bundle(first, costs: [500], helpful: [0])
        var b = bundle(second, costs: [100], helpful: [0])
        let qualities = [first.binding: quality(first, a), second.binding: quality(second, b)]
        b.records[0].sourceDigest = hex("e")
        var costs = [first.binding: try XCTUnwrap(resource(first, a)), second.binding: try XCTUnwrap(resource(second, b))]
        XCTAssertEqual(HamptonMethodResourceOutcomes.refineEqualQualityOrder([first, second],
            outcomes: qualities, resources: costs), [first, second])
        b = bundle(second, costs: [100], helpful: [0])
        b.observations[0].modelDigest = hex("f")
        costs[second.binding] = try XCTUnwrap(resource(second, b))
        XCTAssertEqual(HamptonMethodResourceOutcomes.refineEqualQualityOrder([first, second],
            outcomes: qualities, resources: costs), [first, second])
    }

    func testEqualBetaQualityUsesTokensPerHelpfulResultRatherThanTotal() throws {
        let first = procedure("First"), second = procedure("Second")
        let a = bundle(first, costs: [25, 25, 25, 25], helpful: [0])
        let b = bundle(second, costs: [50, 50, 50, 50], helpful: [0, 1, 2], corrected: [3])
        let qualities = [first.binding: quality(first, a), second.binding: quality(second, b)]
        XCTAssertFalse(HamptonMethodOutcomes.rankBefore(lhs: qualities[first.binding]!, rhs: qualities[second.binding]!))
        XCTAssertFalse(HamptonMethodOutcomes.rankBefore(lhs: qualities[second.binding]!, rhs: qualities[first.binding]!))
        let costs = [first.binding: try XCTUnwrap(resource(first, a)), second.binding: try XCTUnwrap(resource(second, b))]
        XCTAssertEqual(HamptonMethodResourceOutcomes.refineEqualQualityOrder([first, second],
            outcomes: qualities, resources: costs).map(\.id), [second.id, first.id])
    }

    private struct Evidence {
        var records: [DocumentWorkRecord]
        var tasks: [TokenStewardTask]
        var observations: [TokenStewardObservation]
    }

    private func procedure(_ title: String) -> DocumentProcedure {
        DocumentProcedure(id: UUID().uuidString, revision: 1, title: title, instruction: "Preserve meaning.",
            mustBeShorter: false, preserveNumbersAndLinks: true, originRecordID: UUID().uuidString,
            originFeedbackID: UUID().uuidString, createdAt: Date(timeIntervalSince1970: 900), withdrawn: false)
    }

    private func bundle(_ method: DocumentProcedure, costs: [Int64], helpful: Set<Int>,
                        corrected: Set<Int> = []) -> Evidence {
        var result = Evidence(records: [], tasks: [], observations: [])
        for (index, cost) in costs.enumerated() {
            let request = UUID().uuidString
            var record = DocumentWorkRecord(id: request + "-qwen", requestID: request,
                provider: AssistantProvider.qwen.rawValue, targetID: UUID().uuidString,
                sourceDigest: hex("a"), sourceRevision: 1, selectionStart: 0, selectionLength: 12,
                preserveNumbersAndLinks: true, createdAt: Date(timeIntervalSince1970: 1_000),
                updatedAt: Date(timeIntervalSince1970: 1_002), state: .applied,
                proposedDigest: hex("b"), expectedAfterDigest: hex("b"), actualAfterDigest: hex("b"),
                afterRevision: 2, checks: [.init(id: "source", title: "Exact source", passed: true)],
                learning: DocumentWorkLearningContext(requestBinding: .init(inputDigest: hex("c"), contextDigest: hex("d"))),
                procedureUse: method.binding)
            if helpful.contains(index) || corrected.contains(index) {
                record.feedback = DocumentWorkFeedback(revision: 1,
                    verdict: helpful.contains(index) ? .helpful : .needsCorrection,
                    recordedAt: Date(timeIntervalSince1970: 1_001))
            }
            if corrected.contains(index) { record.procedureUseRejected = true }
            result.records.append(record)
            result.tasks.append(TokenStewardTask(id: request, route: AssistantRoute.automatic.rawValue,
                startedAt: record.createdAt, lanes: [.init(provider: AssistantProvider.qwen.name,
                    dispatched: true, state: "complete", localAttemptsMeasured: true)]))
            result.observations.append(observation(request, tokens: cost))
        }
        return result
    }

    private func observation(_ request: String, id: String = "answer", tokens: Int64?,
                             outcome: String = "completed", role: LocalModelRole = .reasoning,
                             account: String = "native", cacheRead: Int64? = nil,
                             cacheWrite: Int64? = nil) -> TokenStewardObservation {
        let identity = [request, AssistantProvider.qwen.name, id].map { "\($0.utf8.count):\($0)" }.joined()
        return TokenStewardObservation(id: identity, taskID: request, provider: AssistantProvider.qwen.name,
            accountID: account, resource: .localInference, observedAt: Date(timeIntervalSince1970: 1_000),
            model: "qwen-fixture", modelDigest: hex("9"), role: role.rawValue, outcome: outcome,
            inputDigest: hex("c"), inputTokens: tokens, outputTokens: tokens == nil ? nil : 0,
            cacheReadTokens: cacheRead, cacheWriteTokens: cacheWrite)
    }

    private func resource(_ method: DocumentProcedure, _ evidence: Evidence) -> HamptonMethodResourceOutcomes? {
        HamptonMethodResourceOutcomes(procedure: method.binding, records: evidence.records,
            tasks: evidence.tasks, observations: evidence.observations)
    }
    private func quality(_ method: DocumentProcedure, _ evidence: Evidence) -> HamptonMethodOutcomes {
        HamptonMethodOutcomes(procedure: method.binding, records: evidence.records)
    }
    private func hex(_ character: Character) -> String { String(repeating: String(character), count: 64) }
}
