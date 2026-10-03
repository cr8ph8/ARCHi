import Foundation
import XCTest
@testable import ARCHiDesktop

@MainActor
final class HamptonQ2EOutcomeAdapterTests: XCTestCase {
    private let requirements = DocumentWorkRequirements(mustBeShorter: false, preserveNumbersAndLinks: true)

    func testOneProjectionDeduplicatesAndBindsSupportCorrectionAndUnknown() throws {
        var helpful = record(at: 1_000)
        helpful.feedback = review(.helpful, at: 1_001)
        helpful.updatedAt = helpful.feedback!.recordedAt
        helpful.q2eDecision = decision()
        var blocked = record(at: 1_002)
        blocked.state = .blocked
        blocked.checks[0].passed = false
        var unknown = record(at: 1_003)
        unknown.state = .failed
        unknown.learning = nil
        let projection = HamptonQ2EOutcomeAdapter(records: [helpful, blocked, unknown, helpful], requirements: requirements)
        XCTAssertTrue(projection.evidence.isValid)
        XCTAssertEqual(projection.evidence.support, 1)
        XCTAssertEqual(projection.evidence.corrections, 1)
        XCTAssertEqual(projection.evidence.unknown, 1)
        XCTAssertEqual(projection.records.map(\.id), [unknown.id, blocked.id, helpful.id])
        XCTAssertEqual(projection.evidence.bindings.map(\.recordID), projection.records.map(\.id))
        let bound = try XCTUnwrap(projection.evidence.bindings.first { $0.recordID == helpful.id })
        XCTAssertEqual(bound.sourceDigest, helpful.sourceDigest)
        XCTAssertEqual(bound.sourceRevision, helpful.sourceRevision)
        XCTAssertEqual(bound.selectionStart, helpful.selectionStart)
        XCTAssertEqual(bound.selectionLength, helpful.selectionLength)
        XCTAssertEqual(bound.learning, helpful.learning)
        XCTAssertEqual(bound.feedback, helpful.feedback)
        XCTAssertEqual(bound.decisionDigest, helpful.q2eDecision?.bindingDigest)
        XCTAssertEqual(projection.evidence.strategyResults["expand"]?.helpful, 1)
        let signals = projection.signals(alternatives: 1, prerequisitesSatisfied: true)
        let next = HamptonQ2EController.decide(domain: "document-revision", contextID: helpful.sourceDigest,
            signals: signals, previous: helpful.q2eDecision, outcomeEvidence: projection.evidence)
        XCTAssertTrue(next.isValid)
        XCTAssertEqual(next.outcomeEvidence, projection.evidence)
        XCTAssertEqual(try JSONDecoder().decode(HamptonQ2EDecision.self, from: JSONEncoder().encode(next)), next)
    }

    func testConflictMalformedEvidenceAndRepeatedFeedbackStopBeforeScoping() throws {
        var good = record(at: 1_000)
        good.feedback = review(.helpful, at: 1_001)
        good.updatedAt = good.feedback!.recordedAt
        var conflict = good
        conflict.mustBeShorter = true
        let conflicting = HamptonQ2EOutcomeAdapter(records: [good, conflict], requirements: requirements)
        XCTAssertEqual(conflicting.evidence.reconciliationIssue, "conflicting-record")
        XCTAssertTrue(conflicting.records.isEmpty, "A conflicting copy outside the requirement scope cannot leave a positive sample.")
        XCTAssertEqual(HamptonQ2EController.decide(domain: "document-revision", contextID: good.sourceDigest,
            signals: conflicting.signals(alternatives: 1, prerequisitesSatisfied: true),
            outcomeEvidence: conflicting.evidence).lane, .stop)

        var invalid = good
        invalid.sourceDigest = "not-a-digest"
        XCTAssertEqual(HamptonQ2EOutcomeAdapter(records: [invalid], requirements: requirements)
            .evidence.reconciliationIssue, "invalid-record")
        var wrongControl = good
        wrongControl.q2eDecision = HamptonQ2EController.decide(domain: "document-reading", contextID: good.sourceDigest,
            signals: emptySignals())
        XCTAssertNil(HamptonQ2EOutcomeBinding(record: wrongControl), "Malformed attribution cannot be silently dropped.")
        let differentRequirements = HamptonQ2EOutcomeAdapter(records: [],
            requirements: DocumentWorkRequirements(mustBeShorter: true, preserveNumbersAndLinks: false))
        wrongControl.q2eDecision = HamptonQ2EController.decide(domain: "document-revision", contextID: good.sourceDigest,
            signals: differentRequirements.signals(alternatives: 1, prerequisitesSatisfied: true),
            outcomeEvidence: differentRequirements.evidence)
        XCTAssertTrue(wrongControl.q2eDecision!.isValid)
        XCTAssertNil(HamptonQ2EOutcomeBinding(record: wrongControl), "A valid decision for different requirements cannot be attributed to this record.")

        var repeated = record(at: 1_000)
        repeated.feedback = good.feedback
        repeated.updatedAt = good.updatedAt
        XCTAssertEqual(HamptonQ2EOutcomeAdapter(records: [good, repeated], requirements: requirements)
            .evidence.reconciliationIssue, "repeated-feedback")
    }

    func testRevisedReviewReplacesCurrentCountsWithoutChangingFrozenDecision() throws {
        var current = record(at: 1_000)
        current.procedureUse = DocumentProcedureUse(id: UUID().uuidString, revision: 2, digest: hex("e"))
        current.feedback = review(.helpful, at: 1_001)
        current.updatedAt = current.feedback!.recordedAt
        let first = HamptonQ2EOutcomeAdapter(records: [current], requirements: requirements)
        let frozen = HamptonQ2EController.decide(domain: "document-revision", contextID: current.sourceDigest,
            signals: first.signals(alternatives: 1, prerequisitesSatisfied: true), outcomeEvidence: first.evidence)
        let frozenBytes = try JSONEncoder().encode(frozen)
        let firstBinding = try XCTUnwrap(first.evidence.bindings.first)
        XCTAssertEqual(firstBinding.procedureUse, current.procedureUse)

        for (offset, verdict) in [DocumentWorkFeedback.Verdict.needsCorrection, .withdrawn].enumerated() {
            current.feedback = review(verdict, revision: UInt64(offset + 2), at: Double(1_002 + offset))
            current.updatedAt = current.feedback!.recordedAt
            current.procedureUseRejected = true
            let revised = HamptonQ2EOutcomeAdapter(records: [current], requirements: requirements)
            XCTAssertTrue(revised.evidence.isValid)
            XCTAssertEqual(revised.evidence.support, 0)
            XCTAssertEqual(revised.evidence.corrections, 1)
            XCTAssertEqual(revised.evidence.bindings.first?.feedback, current.feedback)
            XCTAssertNotEqual(revised.evidence.bindings.first?.recordDigest, firstBinding.recordDigest)
        }
        XCTAssertEqual(frozen.outcomeEvidence?.support, 1)
        XCTAssertEqual(try JSONDecoder().decode(HamptonQ2EDecision.self, from: frozenBytes), frozen)
        XCTAssertTrue(frozen.isValid, "A historical decision records what was known at Send, not today's revised verdict.")
        current.procedureUseRejected = nil
        XCTAssertNil(HamptonQ2EOutcomeBinding(record: current), "Revised procedure feedback retains the owner's counterexample invariant.")
    }

    func testRecentWindowUsesOneExactRequirementScopedSet() {
        let records = (0..<10).map { record(at: Double(1_000 + $0)) }
        var other = record(at: 2_000)
        other.mustBeShorter = true
        let projection = HamptonQ2EOutcomeAdapter(records: records + [other, records[9]], requirements: requirements)
        XCTAssertEqual(projection.records.map(\.id), Array(records.reversed().prefix(8)).map(\.id))
        XCTAssertEqual(projection.evidence.bindings.count, 8)
        XCTAssertEqual(projection.evidence.unknown, 8, "Applied without a retained Helpful verdict remains unknown.")
        XCTAssertEqual(projection.signals(alternatives: 1, prerequisitesSatisfied: true).observations, 8)
    }

    func testNativeSchemaAndEffectiveDeltaRequireCompatibleCapturedPredecessor() throws {
        let prior = decision()
        let signals = HamptonQ2ESignals(observations: 2, retainedSupport: 1, contradictions: 1,
            unchangedSteps: 0, availableAlternatives: 2, remainingBudget: 1, totalBudget: 1)
        let next = HamptonQ2EController.decide(domain: prior.domain, contextID: prior.contextID,
            signals: signals, previous: prior)
        XCTAssertTrue(prior.isValid)
        XCTAssertTrue(next.isValid)
        XCTAssertEqual(next.coordinateSchema, HamptonQ2ECoordinateSchema.id)
        XCTAssertEqual(Set(next.pressures.keys), HamptonQ2ECoordinateSchema.names)
        XCTAssertEqual(next.pressures.count, 5)
        XCTAssertEqual(next.predecessor?.decisionDigest, prior.bindingDigest)
        XCTAssertEqual(next.revision, prior.revision + 1)
        for (name, value) in next.pressures { XCTAssertEqual(next.delta[name], value - prior.pressures[name]!) }
        let badDelta = try changed(next) { object in
            var delta = object["delta"] as! [String: Any]
            delta["support"] = 0.75 // finite and in range, but not q_next - q_previous
            object["delta"] = delta
        }
        XCTAssertFalse(badDelta.isValid)
        XCTAssertFalse((try changed(next) { object in
            var predecessor = object["predecessor"] as! [String: Any]
            predecessor["contextID"] = "different-source"
            object["predecessor"] = predecessor
        }).isValid)
        XCTAssertFalse((try changed(next) { $0["coordinateSchema"] = "archived-eighteen-coordinates" }).isValid)
        let unrelated = HamptonQ2EController.decide(domain: "document-reading", contextID: prior.contextID,
            signals: signals, previous: prior)
        XCTAssertNil(unrelated.predecessor)
        XCTAssertEqual(unrelated.revision, 1)
        XCTAssertEqual(unrelated.delta, unrelated.pressures, "Initial zero is an explicit reference, not an observed predecessor.")
    }

    func testDecisionRejectsCountsThatDoNotMatchItsFrozenOutcomeBindings() throws {
        let projection = HamptonQ2EOutcomeAdapter(records: [record(at: 1_000)], requirements: requirements)
        let inconsistent = HamptonQ2ESignals(observations: 1, retainedSupport: 1, contradictions: 0,
            unchangedSteps: 0, availableAlternatives: 1, remainingBudget: 1, totalBudget: 1,
            strategyResults: projection.evidence.strategyResults)
        let decision = HamptonQ2EController.decide(domain: "document-revision", contextID: hex("a"),
            signals: inconsistent, outcomeEvidence: projection.evidence)
        XCTAssertFalse(decision.isValid, "Unknown work cannot be turned into support by supplying a different aggregate.")
    }

    func testLegacyDecisionAndJournalRemainReadableWithoutInventedLineageOrRewrite() throws {
        let legacy = try changed(decision()) { object in
            object["version"] = HamptonQ2EController.legacyVersion
            object.removeValue(forKey: "coordinateSchema")
            object.removeValue(forKey: "predecessor")
            object.removeValue(forKey: "outcomeEvidence")
        }
        XCTAssertTrue(legacy.isValid)
        XCTAssertNil(legacy.coordinateSchema)
        XCTAssertNil(legacy.predecessor)
        XCTAssertNil(legacy.outcomeEvidence)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        XCTAssertNil(encoded["coordinateSchema"])
        XCTAssertNil(encoded["predecessor"])
        XCTAssertNil(encoded["outcomeEvidence"])
        var oldRecord = record(at: 1_000)
        oldRecord.learning = nil
        oldRecord.q2eDecision = legacy
        struct Archive: Encodable { let schema = "archi-document-work/v1"; let records: [DocumentWorkRecord] }
        let bytes = try JSONEncoder().encode(Archive(records: [oldRecord]))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("document-work.json")
        try bytes.write(to: url)
        let journal = DocumentWorkJournal(url: url)
        XCTAssertNil(journal.loadError)
        XCTAssertEqual(journal.records.first?.q2eDecision, legacy)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        let projection = HamptonQ2EOutcomeAdapter(records: journal.records, requirements: requirements)
        XCTAssertEqual(projection.evidence.unknown, 1)
        XCTAssertNil(projection.evidence.bindings.first?.learning)
        let next = HamptonQ2EController.decide(domain: legacy.domain, contextID: legacy.contextID,
            signals: projection.signals(alternatives: 1, prerequisitesSatisfied: true),
            previous: legacy, outcomeEvidence: projection.evidence)
        XCTAssertTrue(next.isValid)
        XCTAssertEqual(next.predecessor?.version, HamptonQ2EController.legacyVersion)
        XCTAssertEqual(next.predecessor?.decisionDigest, legacy.bindingDigest)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    private func hex(_ character: Character) -> String { String(repeating: String(character), count: 64) }
    private func review(_ verdict: DocumentWorkFeedback.Verdict, revision: UInt64 = 1, at: Double) -> DocumentWorkFeedback {
        DocumentWorkFeedback(revision: revision, verdict: verdict, recordedAt: Date(timeIntervalSince1970: at))
    }
    private func record(at timestamp: Double) -> DocumentWorkRecord {
        let id = UUID().uuidString
        return DocumentWorkRecord(id: id + "-Qwen", requestID: id, provider: "Qwen", targetID: UUID().uuidString,
            sourceDigest: hex("a"), sourceRevision: 1, selectionStart: 0, selectionLength: 12,
            preserveNumbersAndLinks: true,
            createdAt: Date(timeIntervalSince1970: timestamp), updatedAt: Date(timeIntervalSince1970: timestamp),
            state: .applied, proposedDigest: hex("b"), expectedAfterDigest: hex("b"), actualAfterDigest: hex("b"),
            afterRevision: 2, checks: [.init(id: "source", title: "Exact source binding", passed: true)],
            learning: DocumentWorkLearningContext(requestBinding: EvolutionRequestBinding(inputDigest: hex("c"), contextDigest: hex("d"))))
    }
    private func emptySignals() -> HamptonQ2ESignals {
        HamptonQ2ESignals(observations: 0, retainedSupport: 0, contradictions: 0, unchangedSteps: 0,
            availableAlternatives: 1, remainingBudget: 1, totalBudget: 1)
    }
    private func decision() -> HamptonQ2EDecision {
        HamptonQ2EController.decide(domain: "document-revision", contextID: hex("a"), signals: emptySignals())
    }
    private func changed(_ decision: HamptonQ2EDecision,
                         update: (inout [String: Any]) -> Void) throws -> HamptonQ2EDecision {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decision)) as? [String: Any])
        update(&object)
        return try JSONDecoder().decode(HamptonQ2EDecision.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
