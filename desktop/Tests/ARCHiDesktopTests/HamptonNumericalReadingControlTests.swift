import XCTest
@testable import ARCHiDesktop

/// Disposable native owner records only: no model, paid request, user profile,
/// or puzzle execution. These checks cover the reading consumer and its journal.
final class HamptonNumericalReadingControlTests: XCTestCase {
    private let source = (1...8).map { "# Topic \($0)\nDetail for topic \($0).\n" }.joined(separator: "\n")
    private let question = "Explain this document."
    private let date = Date(timeIntervalSince1970: 1_000)

    func testProjectionDeduplicatesTasksAndUsesOnlyTheLatestReadingReview() throws {
        var reviewed = try task("reviewed", at: 1_000, lane: .retain, useful: true)
        reviewed.outcomes.append(review(2, useful: false, at: 1_002))
        reviewed.outcomes.append(TokenStewardOutcome(revision: 3, kind: .userUseful, value: true,
            evidenceID: "ordinary-feedback", recordedAt: Date(timeIntervalSince1970: 1_003)))
        var unknown = try task("unknown", at: 1_004, lane: .expand, useful: nil)
        unknown.outcomes.append(TokenStewardOutcome(revision: 4, kind: .checked, value: true,
            evidenceID: "independent-check", recordedAt: Date(timeIntervalSince1970: 1_005)))
        let projection = project([unknown, reviewed, reviewed])
        XCTAssertTrue(projection.isValid)
        XCTAssertNil(projection.reconciliationIssue)
        XCTAssertEqual(projection.observations, 2)
        XCTAssertEqual(projection.support, 0)
        XCTAssertEqual(projection.corrections, 1)
        XCTAssertEqual(projection.unknown, 1)
        XCTAssertEqual(projection, project([reviewed, unknown]))
        XCTAssertEqual(projection.bindings.first(where: { $0.taskID == "reviewed" })?.review?.revision, 2)
        let numerical = try XCTUnwrap(HamptonReadingNumericalControl.replay(evidence: projection))
        XCTAssertEqual(numerical.steps.map(\.taskID), ["reviewed"])
        XCTAssertFalse(numerical.steps[0].useful)
        let encoded = try object(projection)
        let binding = try XCTUnwrap((encoded["bindings"] as? [[String: Any]])?.first)
        XCTAssertNil(binding["control"], "The next task must not recursively copy earlier decisions.")
        XCTAssertNil(binding["documentReading"])
    }

    func testProjectionScopesCompletedAnswersAndFailsClosedOnConflicts() throws {
        let retained = try task("retained", at: 1_000, lane: .retain, useful: true)
        var pending = try task("pending", at: 1_001, lane: .expand, useful: nil)
        pending.lanes[0].state = "pending"
        var clarification = try task("clarify", at: 1_002, lane: .expand, useful: nil)
        clarification.documentReadingResult = DocumentReadingResult(answerDigest: digest("uncertain"), kind: "CLARIFY", citedSectionIDs: [])
        var foreign = try task("other-source", at: 1_003, lane: .retain, useful: true, text: "A different document.")
        foreign.outcomes = [review(4, useful: true, at: 1_004)]
        XCTAssertEqual(project([retained, pending, clarification, foreign]).bindings.map(\.taskID), ["retained"])
        XCTAssertTrue(HamptonReadingOutcomeAdapter.project(tasks: [retained], sourceDigest: sourceDigest,
            excludingRequestID: "retained").bindings.isEmpty)
        var changed = retained
        changed.outcomes.append(review(2, useful: false, at: 1_002))
        let conflict = project([retained, changed])
        XCTAssertTrue(conflict.isValid, "The bounded failure projection remains representable.")
        XCTAssertNotNil(conflict.reconciliationIssue)
        XCTAssertTrue(conflict.bindings.isEmpty)
        XCTAssertNil(HamptonReadingNumericalControl.replay(evidence: conflict))
        XCTAssertEqual(decide(conflict, prerequisites: false).lane, .stop)
    }

    func testNumericalReplayIsBoundedIdempotentAndReplacesReversedEvidence() throws {
        let first = try task("retain-correction", at: 1_000, lane: .retain, useful: false)
        var second = try task("expand-helpful", at: 1_002, lane: .expand, useful: true)
        let evidence = project([first, second])
        let decision = decide(evidence)
        XCTAssertTrue(decision.isValid)
        XCTAssertEqual(decision.version, HamptonQ2EController.readingNumericalVersion)
        let priorPolicy = HamptonQ2EController.decide(domain: "document-reading", contextID: sourceDigest,
            signals: decision.signals, useNumericalControl: false)
        XCTAssertTrue(priorPolicy.isValid)
        XCTAssertEqual(priorPolicy.lane, .retain)
        XCTAssertEqual(decision.lane, .expand,
            "The numerical adaptation changes the actual approach beyond the existing count-based policy.")
        XCTAssertEqual(priorPolicy.pressures, decision.pressures)
        let receipt = try XCTUnwrap(decision.readingNumericalControl)
        XCTAssertEqual(receipt, HamptonReadingNumericalControl.replay(evidence: evidence))
        XCTAssertEqual(receipt.final, [0.375, 0.625, 0.5])
        XCTAssertEqual(receipt.steps.map(\.taskID), [first.id, second.id])
        for step in receipt.steps {
            XCTAssertTrue(step.candidate.accepted)
            XCTAssertLessThanOrEqual(step.candidate.potentialCandidate, step.candidate.potentialPrevious + 1e-12)
            XCTAssertLessThanOrEqual(sqrt(step.candidate.effectiveDelta.reduce(0) { $0 + $1 * $1 }), 0.125 + 1e-12)
        }
        second.outcomes.append(review(3, useful: false, at: 1_005))
        let reversed = decide(project([second, first]))
        XCTAssertTrue(reversed.isValid)
        XCTAssertEqual(reversed.readingNumericalControl?.steps.count, 2)
        XCTAssertLessThan(try XCTUnwrap(reversed.readingNumericalControl).final[1], 0.5)
        XCTAssertNotEqual(reversed.readingNumericalControl?.steps.last?.bindingDigest, receipt.steps.last?.bindingDigest)
        XCTAssertTrue(try JSONDecoder().decode(HamptonQ2EDecision.self, from: JSONEncoder().encode(decision)).isValid,
            "A review reversal changes future context while preserving the frozen historical decision.")
    }

    func testForgedNumericalStateMissingReplayAndVersionDowngradeAreRejected() throws {
        let decision = decide(project([try task("helpful", at: 1_000, lane: .retain, useful: true)]))
        XCTAssertTrue(decision.isValid)
        XCTAssertTrue(try rejectsChange(decision) { value in
            var receipt = value["readingNumericalControl"] as! [String: Any]
            receipt["final"] = [0.99, 0.99, 0.99]
            value["readingNumericalControl"] = receipt
        })
        XCTAssertTrue(try rejectsChange(decision) { $0.removeValue(forKey: "readingNumericalControl") })
        XCTAssertTrue(try rejectsChange(decision) { $0.removeValue(forKey: "readingEvidence") })
        XCTAssertTrue(try rejectsChange(decision) { $0["version"] = HamptonQ2EController.version })
    }

    @MainActor
    func testLegacyReadingJournalLoadsWithoutInventedNumericalHistory() throws {
        let url = try journalURL()
        let store = TokenStewardStore(url: url, now: { self.date })
        try retainAnswer(in: store, id: "legacy", useful: true)
        let bytes = try Data(contentsOf: url)
        let reopened = TokenStewardStore(url: url, now: { self.date })
        XCTAssertNil(reopened.loadError)
        let old = try XCTUnwrap(reopened.tasks.first?.documentReading?.control)
        XCTAssertEqual(old.version, HamptonQ2EController.version)
        XCTAssertTrue(old.isValid)
        XCTAssertNil(old.readingEvidence)
        XCTAssertNil(old.readingNumericalControl)
        let next = decide(project(reopened.tasks))
        XCTAssertTrue(next.isValid)
        XCTAssertEqual(next.readingNumericalControl?.steps.count, 1)
        XCTAssertEqual(try Data(contentsOf: url), bytes, "Projection is read-only; it does not migrate the owner journal.")
    }

    func testReviewReversalChangesRetainedSourceSpansAndRejectsSubstitutedPlan() throws {
        let tail = (source as NSString).range(of: "Detail for topic 8.")
        let selection = try XCTUnwrap(DocumentSelection(range: tail, text: source, sourceRevision: 1))
        let priorPlan = try XCTUnwrap(DocumentReadingPlan.make(text: source, question: question,
            selection: selection, lane: .expand))
        let tailID = try XCTUnwrap(priorPlan.sections.first(where: { $0.text.contains("Detail for topic 8.") })?.id)
        var previous = try task("tail-work", at: 1_000, lane: .retain, useful: true)
        previous.documentReading = DocumentReadingTrace(sourceDigest: sourceDigest, questionDigest: digest(question),
            planDigest: priorPlan.digest, sectionIDs: [tailID], control: legacyControl(.retain))
        previous.documentReadingResult = DocumentReadingResult(answerDigest: digest("answer"), kind: "ANSWER", citedSectionIDs: [tailID])
        let supportedEvidence = project([previous])
        let supported = decide(supportedEvidence, alternatives: 8)
        XCTAssertEqual(supported.lane, .retain)
        let supportedPlan = try plan(for: supported)
        XCTAssertTrue(supportedPlan.sourceIDs.contains(tailID))
        XCTAssertTrue(request(plan: supportedPlan, control: supported).hasValidLocalControl)

        previous.outcomes.append(review(2, useful: false, at: 1_002))
        let correctedEvidence = project([previous])
        XCTAssertTrue(correctedEvidence.preferredSectionIDs(for: digest(question)).isEmpty)
        let corrected = decide(correctedEvidence, alternatives: 8)
        let correctedPlan = try plan(for: corrected)
        XCTAssertNotEqual(correctedPlan.sourceIDs, supportedPlan.sourceIDs,
            "Adaptation must alter the source context the local model will actually receive.")
        XCTAssertFalse(correctedPlan.sourceIDs.contains(tailID))
        XCTAssertTrue(request(plan: correctedPlan, control: corrected).hasValidLocalControl)
        XCTAssertFalse(request(plan: supportedPlan, control: corrected).hasValidLocalControl,
            "Exact source spans can still be stale relative to the current reading policy.")
        // JSON object key order is not part of the external-provider contract.
        let originalInput = try JSONSerialization.jsonObject(with: Data(
            request(plan: supportedPlan, control: supported).codexInput.utf8)) as? NSDictionary
        let correctedInput = try JSONSerialization.jsonObject(with: Data(
            request(plan: correctedPlan, control: corrected).codexInput.utf8)) as? NSDictionary
        XCTAssertEqual(try XCTUnwrap(originalInput), try XCTUnwrap(correctedInput))
    }

    func testNumericalPreferencesDoNotBypassPrerequisitesOrRequiredRepair() throws {
        let evidence = project([try task("retain", at: 1_000, lane: .retain, useful: true)])
        let stopped = decide(evidence, prerequisites: false)
        XCTAssertTrue(stopped.isValid)
        XCTAssertEqual(stopped.lane, .stop)
        XCTAssertEqual(decide(evidence, alternatives: 0).lane, .stop)
        let corrections = project([try task("bad-a", at: 1_000, lane: .retain, useful: false),
                                   try task("bad-b", at: 1_002, lane: .expand, useful: false)])
        let repaired = decide(corrections)
        XCTAssertTrue(repaired.isValid)
        XCTAssertEqual(repaired.lane, .repair)
    }

    @MainActor
    func testTraceWriteRechecksReadingEvidenceAgainstAnotherJournalWriter() throws {
        let url = try journalURL()
        let first = TokenStewardStore(url: url, now: { self.date })
        try retainAnswer(in: first, id: "reviewed", useful: true)
        let second = TokenStewardStore(url: url, now: { self.date })
        let frozen = try trace(for: decide(project(second.tasks)))
        try second.preflight(requestID: "candidate", route: .local)
        try first.recordDocumentReadingFeedback(requestID: "reviewed", useful: false)
        let bytes = try Data(contentsOf: url)
        XCTAssertThrowsError(try second.recordDocumentReading(requestID: "candidate", trace: frozen))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        try second.refresh()
        XCTAssertNil(second.tasks.first(where: { $0.id == "candidate" })?.documentReading)
        let current = try trace(for: decide(project(second.tasks)))
        try second.recordDocumentReading(requestID: "candidate", trace: current)
        XCTAssertEqual(second.tasks.first(where: { $0.id == "candidate" })?.documentReading, current)
    }

    @MainActor
    func testDispatchRechecksEvidenceAfterTraceWasRetained() throws {
        let url = try journalURL()
        let first = TokenStewardStore(url: url, now: { self.date })
        try retainAnswer(in: first, id: "reviewed", useful: true)
        let second = TokenStewardStore(url: url, now: { self.date })
        let frozen = try trace(for: decide(project(second.tasks)))
        try second.preflight(requestID: "candidate", route: .local)
        try second.recordDocumentReading(requestID: "candidate", trace: frozen)
        try first.recordDocumentReadingFeedback(requestID: "reviewed", useful: false)
        let bytes = try Data(contentsOf: url)
        XCTAssertThrowsError(try second.recordDispatch(requestID: "candidate", provider: .qwen))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        try second.refresh()
        let pending = try XCTUnwrap(second.tasks.first(where: { $0.id == "candidate" }))
        XCTAssertEqual(pending.documentReading, frozen, "Failure preserves the original Send provenance.")
        XCTAssertFalse(pending.lanes[0].dispatched)
    }

    private var sourceDigest: String { digest(source) }
    private func digest(_ value: String) -> String { LessonSource.digest(of: value) }
    private func project(_ tasks: [TokenStewardTask]) -> HamptonReadingOutcomeEvidence {
        HamptonReadingOutcomeAdapter.project(tasks: tasks, sourceDigest: sourceDigest)
    }
    private func decide(_ evidence: HamptonReadingOutcomeEvidence, alternatives: Int = 1,
                        prerequisites: Bool = true) -> HamptonQ2EDecision {
        HamptonQ2EController.decide(domain: "document-reading", contextID: evidence.sourceDigest,
            signals: HamptonQ2ESignals(observations: evidence.observations, retainedSupport: evidence.support,
                contradictions: evidence.corrections, unchangedSteps: 0, availableAlternatives: alternatives,
                remainingBudget: 1, totalBudget: 1, prerequisitesSatisfied: prerequisites,
                strategyResults: evidence.strategyResults), readingEvidence: evidence)
    }
    private func legacyControl(_ lane: HamptonQ2ELane, source: String? = nil) -> HamptonQ2EDecision {
        let support = lane == .retain ? 1 : 0
        let corrections = lane == .repair ? 2 : 0
        return HamptonQ2EController.decide(domain: "document-reading", contextID: source ?? sourceDigest,
            signals: HamptonQ2ESignals(observations: support + corrections, retainedSupport: support,
                contradictions: corrections, unchangedSteps: 0, availableAlternatives: 1,
                remainingBudget: 1, totalBudget: 1), useNumericalControl: false)
    }
    private func review(_ revision: Int, useful: Bool, at: Double, event: Int? = nil) -> TokenStewardOutcome {
        TokenStewardOutcome(revision: revision, kind: .userUseful, value: useful,
            evidenceID: DocumentReadingTrace.feedbackEvidencePrefix + String(format: "00000000-0000-4000-8000-%012d", event ?? revision),
            recordedAt: Date(timeIntervalSince1970: at))
    }
    private func task(_ id: String, at: Double, lane: HamptonQ2ELane, useful: Bool?, text: String? = nil) throws -> TokenStewardTask {
        let plan = try XCTUnwrap(DocumentReadingPlan.make(text: text ?? source, question: question, selection: nil, lane: lane))
        let trace = DocumentReadingTrace(sourceDigest: plan.sourceDigest, questionDigest: plan.questionDigest,
            planDigest: plan.digest, sectionIDs: plan.sourceIDs, control: legacyControl(lane, source: plan.sourceDigest))
        return TokenStewardTask(id: id, route: AssistantRoute.local.rawValue, startedAt: Date(timeIntervalSince1970: at),
            lanes: [TokenStewardLane(provider: AssistantProvider.qwen.name, dispatched: true, state: "complete")],
            outcomes: useful.map { [review(1, useful: $0, at: at + 0.5, event: Int(at))] } ?? [],
            documentReading: trace,
            documentReadingResult: DocumentReadingResult(answerDigest: digest("answer"), kind: "ANSWER", citedSectionIDs: plan.sourceIDs))
    }
    private func plan(for decision: HamptonQ2EDecision) throws -> DocumentReadingPlan {
        try XCTUnwrap(DocumentReadingPlan.make(text: source, question: question, selection: nil, lane: decision.lane,
            preferredSectionIDs: decision.readingEvidence?.preferredSectionIDs(for: digest(question)) ?? []))
    }
    private func trace(for decision: HamptonQ2EDecision) throws -> DocumentReadingTrace {
        let plan = try plan(for: decision)
        return DocumentReadingTrace(sourceDigest: plan.sourceDigest, questionDigest: plan.questionDigest,
            planDigest: plan.digest, sectionIDs: plan.sourceIDs, control: decision)
    }
    private func request(plan: DocumentReadingPlan, control: HamptonQ2EDecision) -> AssistantRequest {
        AssistantRequest(prompt: question, sourceName: "reading-fixture.txt", sourceText: source,
            sourceRevision: 1, placementRevision: 0, tone: "Warm", replyLength: 0.5,
            localControl: control, localReading: plan)
    }
    @MainActor
    private func retainAnswer(in store: TokenStewardStore, id: String, useful: Bool) throws {
        let trace = try trace(for: legacyControl(.retain))
        try store.preflight(requestID: id, route: .local)
        try store.recordDocumentReading(requestID: id, trace: trace)
        try store.recordDispatch(requestID: id, provider: .qwen)
        try store.recordDocumentReadingResult(requestID: id,
            result: DocumentReadingResult(answerDigest: digest("answer"), kind: "ANSWER", citedSectionIDs: trace.sectionIDs))
        try store.recordLane(AssistantLaneReceipt(requestID: id, route: .local, provider: .qwen,
            context: ContextTicket(generation: 0, placement: 0, source: 0, selection: 0), inputDigest: digest("input"),
            inputContract: "native-assistant-input/v2", deadline: date.addingTimeInterval(60), modelIdentity: "fixture",
            state: .complete, requestStarted: true, elapsedMilliseconds: 10))
        try store.recordDocumentReadingFeedback(requestID: id, useful: useful)
    }
    private func journalURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-reading-control-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("steward.json")
    }
    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }
    private func rejectsChange(_ decision: HamptonQ2EDecision, update: (inout [String: Any]) -> Void) throws -> Bool {
        var value = try object(decision)
        update(&value)
        do {
            let data = try JSONSerialization.data(withJSONObject: value)
            return !(try JSONDecoder().decode(HamptonQ2EDecision.self, from: data)).isValid
        } catch { return true }
    }
}
