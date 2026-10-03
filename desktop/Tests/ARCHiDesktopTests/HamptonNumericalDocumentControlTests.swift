import XCTest
@testable import ARCHiDesktop

/// Synthetic owner records exercise the production adapter and request surface.
/// No model, network, user profile, or ARC puzzle execution is involved.
final class HamptonNumericalDocumentControlTests: XCTestCase {
    private let source = "A short synthetic passage for a local revision."
    private let requirements = DocumentWorkRequirements(preserveNumbersAndLinks: true)

    func testAttributedOutcomesChangeTheActualLocalRequestApproach() throws {
        let projection = HamptonQ2EOutcomeAdapter(records: mixedOutcomes(), requirements: requirements)
        let old = decide(projection, numerical: false)
        let next = decide(projection)
        XCTAssertTrue(old.isValid)
        XCTAssertTrue(next.isValid)
        XCTAssertEqual(old.version, HamptonQ2EController.version)
        XCTAssertEqual(next.version, HamptonQ2EController.numericalVersion)
        XCTAssertEqual(old.lane, .retain)
        XCTAssertEqual(next.lane, .expand)
        XCTAssertEqual(old.pressures, next.pressures, "The five existing pressures retain their definitions.")
        let numerical = try XCTUnwrap(next.numericalControl)
        XCTAssertEqual(numerical.final, [0.375, 0.625, 0.5])
        XCTAssertEqual(try XCTUnwrap(numerical.laneAdjustments["retain"]), -0.078125, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(numerical.laneAdjustments["expand"]), 0.078125, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(next.laneWeights["retain"]), 0.321875, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(next.laneWeights["expand"]), 0.359375, accuracy: 1e-12)

        let oldRequest = try request(control: old)
        let nextRequest = try request(control: next)
        XCTAssertTrue(nextRequest.hasValidLocalControl)
        let before = try object(oldRequest.localInput)
        let after = try object(nextRequest.localInput)
        let beforeControl = try XCTUnwrap(before["workControl"] as? [String: Any])
        let afterControl = try XCTUnwrap(after["workControl"] as? [String: Any])
        XCTAssertEqual(beforeControl["lane"] as? String, "retain")
        XCTAssertEqual(afterControl["lane"] as? String, "expand")
        XCTAssertNotEqual(beforeControl["instruction"] as? String, afterControl["instruction"] as? String)
        XCTAssertEqual(Set(afterControl.keys), ["version", "lane", "instruction"],
            "Only authored approach guidance reaches the model; numerical state and evidence stay native.")
        XCTAssertEqual(oldRequest.codexInput, nextRequest.codexInput)
        XCTAssertNil(try object(nextRequest.codexInput)["workControl"])
    }

    func testReplayIsIdempotentAndIgnoresUnattributedOrUnknownOutcomes() throws {
        let records = mixedOutcomes()
        let original = HamptonQ2EOutcomeAdapter(records: records, requirements: requirements)
        let reordered = HamptonQ2EOutcomeAdapter(records: [records[1], records[0], records[1]], requirements: requirements)
        let frozen = decide(original)
        XCTAssertEqual(decide(reordered), frozen, "Reordering or identical duplicate input is not another experience.")
        XCTAssertEqual(decide(original), frozen, "Repeated UI evaluation cannot advance numerical state.")
        XCTAssertEqual(try XCTUnwrap(frozen.numericalControl).steps.map(\.recordID), records.map(\.id))

        var unknown = record(at: 1_003, lane: .expand, verdict: nil)
        unknown.q2eDecision = attributedDecision(lane: .expand)
        var unattributed = record(at: 1_004, lane: .retain, verdict: .helpful)
        unattributed.q2eDecision = nil
        var external = record(at: 1_006, lane: .expand, verdict: .helpful)
        external.provider = AssistantProvider.codex.rawValue
        external.id = external.requestID + "-" + AssistantProvider.codex.rawValue
        let withoutAssumptions = HamptonQ2EOutcomeAdapter(records: [unknown, unattributed, external], requirements: requirements)
        let trace = try XCTUnwrap(decide(withoutAssumptions).numericalControl)
        XCTAssertTrue(trace.steps.isEmpty)
        XCTAssertEqual(trace.initial, trace.final)
        XCTAssertTrue(trace.laneAdjustments.values.allSatisfy { $0 == 0 })
        XCTAssertEqual(withoutAssumptions.evidence.support, 2,
            "An old or external helpful judgment may support the existing aggregate without inventing native strategy evidence.")
    }

    func testWithdrawalReplacesPositiveInfluenceWhileFrozenHistorySurvives() throws {
        let records = mixedOutcomes()
        let frozen = decide(HamptonQ2EOutcomeAdapter(records: records, requirements: requirements))
        let frozenBytes = try JSONEncoder().encode(frozen)
        let oldTrace = try XCTUnwrap(frozen.numericalControl)
        for verdict in [DocumentWorkFeedback.Verdict.needsCorrection, .withdrawn] {
            var revised = records
            revised[1].feedback = DocumentWorkFeedback(revision: 2, verdict: verdict,
                recordedAt: Date(timeIntervalSince1970: 1_005))
            revised[1].updatedAt = Date(timeIntervalSince1970: 1_005)
            let current = decide(HamptonQ2EOutcomeAdapter(records: revised, requirements: requirements))
            let trace = try XCTUnwrap(current.numericalControl)
            XCTAssertTrue(current.isValid)
            XCTAssertEqual(current.signals.retainedSupport, 0)
            XCTAssertEqual(trace.steps.count, oldTrace.steps.count, "A changed judgment is not an extra observation.")
            XCTAssertEqual(trace.steps.last?.disposition, .correction)
            XCTAssertLessThan(trace.final[1], trace.initial[1])
            XCTAssertNotEqual(trace.steps.last?.recordDigest, oldTrace.steps.last?.recordDigest)
            XCTAssertEqual(current.lane, .repair)
        }
        let restored = try JSONDecoder().decode(HamptonQ2EDecision.self, from: frozenBytes)
        XCTAssertEqual(restored, frozen)
        XCTAssertTrue(restored.isValid, "Historical Send decisions remain valid for their frozen evidence.")
    }

    func testReceiptTamperingAndMissingReplayAreRejected() throws {
        let decision = decide(HamptonQ2EOutcomeAdapter(records: mixedOutcomes(), requirements: requirements))
        XCTAssertTrue(decision.isValid)
        XCTAssertTrue(try rejectsChange(decision) { object in
            var trace = object["numericalControl"] as! [String: Any]
            trace["final"] = [0.99, 0.99, 0.99]
            object["numericalControl"] = trace
        })
        XCTAssertTrue(try rejectsChange(decision) { object in
            var trace = object["numericalControl"] as! [String: Any]
            trace["laneAdjustments"] = ["retain": 0.5, "expand": 0.5, "repair": 0.5]
            object["numericalControl"] = trace
        })
        XCTAssertTrue(try rejectsChange(decision) { $0.removeValue(forKey: "numericalControl") })
        XCTAssertTrue(try rejectsChange(decision) { $0["version"] = HamptonQ2EController.version },
            "A v3 receipt cannot be smuggled into the older policy contract.")
    }

    @MainActor
    func testV2JournalLoadsWithoutRewriteOrInventedNumericalHistory() throws {
        let projection = HamptonQ2EOutcomeAdapter(records: mixedOutcomes(), requirements: requirements)
        let legacy = decide(projection, numerical: false)
        XCTAssertTrue(legacy.isValid)
        XCTAssertNil(legacy.numericalControl)
        XCTAssertNil(try object(String(decoding: JSONEncoder().encode(legacy), as: UTF8.self))["numericalControl"])
        var completed = record(at: 2_000, lane: .retain, verdict: .helpful)
        completed.q2eDecision = legacy
        struct Archive: Encodable { let schema = "archi-document-work/v1"; let records: [DocumentWorkRecord] }
        let bytes = try JSONEncoder().encode(Archive(records: [completed]))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("document-work.json")
        try bytes.write(to: url)
        let journal = DocumentWorkJournal(url: url)
        XCTAssertNil(journal.loadError)
        XCTAssertEqual(journal.records.first?.q2eDecision, legacy)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        let nextProjection = HamptonQ2EOutcomeAdapter(records: journal.records, requirements: requirements)
        let next = HamptonQ2EController.decide(domain: "document-revision", contextID: digest,
            signals: nextProjection.signals(alternatives: 3, prerequisitesSatisfied: true),
            previous: legacy, outcomeEvidence: nextProjection.evidence)
        XCTAssertTrue(next.isValid)
        XCTAssertEqual(next.version, HamptonQ2EController.numericalVersion)
        XCTAssertEqual(next.predecessor?.decisionDigest, legacy.bindingDigest)
        XCTAssertEqual(next.numericalControl?.steps.count, 1,
            "Only the current attributed review is replayed; the old frozen history is not recursively counted.")
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testNumericalPreferencesCannotBypassPrerequisitesOrRequiredRepair() throws {
        let projection = HamptonQ2EOutcomeAdapter(records: mixedOutcomes(), requirements: requirements)
        let stopped = HamptonQ2EController.decide(domain: "document-revision", contextID: digest,
            signals: projection.signals(alternatives: 3, prerequisitesSatisfied: false), outcomeEvidence: projection.evidence)
        XCTAssertTrue(stopped.isValid)
        XCTAssertEqual(stopped.lane, .stop)
        let noAlternative = HamptonQ2EController.decide(domain: "document-revision", contextID: digest,
            signals: projection.signals(alternatives: 0, prerequisitesSatisfied: true), outcomeEvidence: projection.evidence)
        XCTAssertTrue(noAlternative.isValid)
        XCTAssertEqual(noAlternative.lane, .stop)
        let corrective = [record(at: 1_000, lane: .retain, verdict: .needsCorrection),
                          record(at: 1_002, lane: .expand, verdict: .needsCorrection),
                          record(at: 1_004, lane: .repair, verdict: .helpful)]
        let repairing = decide(HamptonQ2EOutcomeAdapter(records: corrective, requirements: requirements))
        XCTAssertTrue(repairing.isValid)
        XCTAssertEqual(repairing.pressures["verifierPressure"], 0.4)
        XCTAssertEqual(repairing.lane, .repair)
    }

    private var digest: String { WorkingCopyEditReceipt.digest(source) }
    private func mixedOutcomes() -> [DocumentWorkRecord] {
        [record(at: 1_000, lane: .retain, verdict: .needsCorrection),
         record(at: 1_002, lane: .expand, verdict: .helpful)]
    }
    private func decide(_ projection: HamptonQ2EOutcomeAdapter, numerical: Bool = true) -> HamptonQ2EDecision {
        HamptonQ2EController.decide(domain: "document-revision", contextID: digest,
            signals: projection.signals(alternatives: 1, prerequisitesSatisfied: true),
            outcomeEvidence: projection.evidence, useNumericalControl: numerical)
    }
    private func attributedDecision(lane: HamptonQ2ELane) -> HamptonQ2EDecision {
        let support = lane == .retain ? 1 : 0
        let corrections = lane == .repair ? 2 : 0
        return HamptonQ2EController.decide(domain: "document-revision", contextID: digest,
            signals: HamptonQ2ESignals(observations: support + corrections, retainedSupport: support,
                contradictions: corrections, unchangedSteps: 0, availableAlternatives: 1,
                remainingBudget: 1, totalBudget: 1), useNumericalControl: false)
    }
    private func record(at timestamp: Double, lane: HamptonQ2ELane,
                        verdict: DocumentWorkFeedback.Verdict?) -> DocumentWorkRecord {
        let id = UUID().uuidString
        let after = WorkingCopyEditReceipt.digest("An applied local revision.")
        let reviewTime = Date(timeIntervalSince1970: timestamp + 0.5)
        return DocumentWorkRecord(id: id + "-" + AssistantProvider.qwen.rawValue,
            requestID: id, provider: AssistantProvider.qwen.rawValue, targetID: UUID().uuidString,
            sourceDigest: digest, sourceRevision: 1, selectionStart: 0, selectionLength: 12,
            preserveNumbersAndLinks: true,
            createdAt: Date(timeIntervalSince1970: timestamp), updatedAt: reviewTime,
            state: .applied, proposedDigest: after, expectedAfterDigest: after, actualAfterDigest: after,
            afterRevision: 2, checks: [.init(id: "source", title: "Exact source binding", passed: true)],
            learning: DocumentWorkLearningContext(requestBinding: EvolutionRequestBinding(inputDigest: digest, contextDigest: after)),
            feedback: verdict.map { DocumentWorkFeedback(revision: 1, verdict: $0, recordedAt: reviewTime) },
            q2eDecision: attributedDecision(lane: lane))
    }
    private func request(control: HamptonQ2EDecision) throws -> AssistantRequest {
        let selection = try XCTUnwrap(DocumentSelection(range: NSRange(location: 0, length: 12), text: source, sourceRevision: 1))
        let target = try XCTUnwrap(RevisionTarget(text: source, sourceRevision: 1, selection: selection,
            id: "AF4C7EE3-CBD5-4E8D-924F-8F8028994F0E", requirements: requirements))
        return AssistantRequest(prompt: "Make this clearer.", sourceName: "fixture.txt", sourceText: source,
            sourceRevision: 1, placementRevision: 0, tone: "Warm", replyLength: 0.5,
            selection: selection, revisionTarget: target, localControl: control)
    }
    private func object(_ string: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(string.utf8)) as? [String: Any])
    }
    private func rejectsChange(_ decision: HamptonQ2EDecision,
                               update: (inout [String: Any]) -> Void) throws -> Bool {
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decision)) as? [String: Any])
        update(&value)
        let bytes = try JSONSerialization.data(withJSONObject: value)
        do { return !(try JSONDecoder().decode(HamptonQ2EDecision.self, from: bytes)).isValid }
        catch { return true }
    }
}
