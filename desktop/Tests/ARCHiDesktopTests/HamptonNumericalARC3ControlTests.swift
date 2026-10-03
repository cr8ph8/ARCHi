import CryptoKit
import XCTest
@testable import ARCHiDesktop

/// Fabricated public observations only. These checks run neither an ARC game
/// nor a model, and never touch a companion profile or official benchmark.
final class HamptonNumericalARC3ControlTests: XCTestCase {
    private let game = "numerical-fixture-v1"

    func testLevelProgressRemainsAttributedUntilAnExplicitReset() throws {
        var fixture = episode()
        append(to: &fixture, color: 2, level: 1, action: 1, lane: .expand)
        let evidence = project(fixture)
        XCTAssertTrue(evidence.isValid)
        XCTAssertNil(evidence.reconciliationIssue)
        XCTAssertEqual(evidence.observations, 1, "Frame pressure starts afresh at the new level.")
        XCTAssertEqual(evidence.retainedSupport, 0)
        XCTAssertEqual(evidence.strategyResults["expand"]?.helpful, 1,
            "Environment progress still supplies task-local approach feedback across the level boundary.")
        XCTAssertEqual(try XCTUnwrap(HamptonARC3NumericalControl.replay(evidence: evidence)).final, [0.5, 0.625, 0.5])

        append(to: &fixture, color: 1, level: 0, action: 0)
        let reset = project(fixture)
        XCTAssertTrue(reset.isValid)
        XCTAssertNil(reset.reconciliationIssue)
        XCTAssertTrue(reset.bindings.isEmpty)
        XCTAssertEqual(try XCTUnwrap(HamptonARC3NumericalControl.replay(evidence: reset)).final, [0.5, 0.5, 0.5])
    }

    func testVisibleNoveltyManualWorkAndUnreconciledTransportEarnNoUsefulness() throws {
        var fixture = episode()
        append(to: &fixture, color: 2, level: 0, action: 1, lane: .expand)
        append(to: &fixture, color: 3, level: 1, action: 1)
        fixture.attempts.append(ARC3ActionAttempt(id: UUID().uuidString, proposedAt: Date(timeIntervalSince1970: 50),
            baseFrameDigest: fixture.current.frameDigest, baseDispatches: fixture.current.dispatches,
            action: 2, x: nil, y: nil, predictedDigest: nil, state: "unreconciled"))
        let evidence = project(fixture)
        XCTAssertTrue(evidence.isValid)
        XCTAssertNil(evidence.reconciliationIssue)
        XCTAssertEqual(evidence.bindings.count, 1)
        XCTAssertNil(evidence.bindings.first?.useful, "A different visible frame is not completed game progress.")
        let numerical = try XCTUnwrap(HamptonARC3NumericalControl.replay(evidence: evidence))
        XCTAssertTrue(numerical.steps.isEmpty)
        XCTAssertEqual(numerical.final, [0.5, 0.5, 0.5])
    }

    func testInvalidatedSupportIsWithdrawnButARefutedPredictionIsCorrection() throws {
        var fixture = episode()
        append(to: &fixture, color: 2, level: 1, action: 1, lane: .expand)
        fixture.transitions[0].invalidated = true
        append(to: &fixture, color: 3, level: 1, action: 2, predictedColor: 4, lane: .retain)
        let evidence = project(fixture)
        XCTAssertTrue(evidence.isValid)
        XCTAssertNil(evidence.reconciliationIssue)
        XCTAssertEqual(evidence.bindings.filter { $0.useful == true }.count, 0)
        XCTAssertEqual(evidence.bindings.filter { $0.useful == false }.count, 1)
        let receipt = try XCTUnwrap(HamptonARC3NumericalControl.replay(evidence: evidence))
        XCTAssertEqual(receipt.steps.count, 1)
        XCTAssertEqual(receipt.final, [0.375, 0.5, 0.5])
    }

    func testConflictingAttemptOrTransitionHistoryFailsClosed() throws {
        var fixture = episode()
        append(to: &fixture, color: 2, level: 1, action: 1, lane: .expand)
        var duplicate = try XCTUnwrap(fixture.attempts.last)
        duplicate.outcome = "environment-game-over"
        fixture.attempts.append(duplicate)
        let conflict = project(fixture)
        XCTAssertNotNil(conflict.reconciliationIssue)
        XCTAssertNil(HamptonARC3NumericalControl.replay(evidence: conflict))
        XCTAssertEqual(ARC3Planner.plan(current: fixture.current, transitions: fixture.transitions,
            attempts: fixture.attempts).controller.lane, .stop)

        fixture.attempts.removeLast()
        let unique = project(fixture)
        fixture.transitions.append(try XCTUnwrap(fixture.transitions.first))
        XCTAssertEqual(project(fixture), unique, "Identical imported transitions cannot count twice.")
        fixture.transitions[fixture.transitions.count - 1].invalidated = true
        XCTAssertNotNil(project(fixture).reconciliationIssue,
            "Conflicting copies of the same transition require reconciliation.")
    }

    func testReplayIsBoundedIdempotentAndContainsNoRecursivePlan() throws {
        var fixture = episode()
        append(to: &fixture, color: 2, level: 1, action: 1, lane: .expand)
        append(to: &fixture, color: 3, level: 1, action: 2, predictedColor: 4, lane: .retain)
        let evidence = project(fixture)
        let numerical = try XCTUnwrap(HamptonARC3NumericalControl.replay(evidence: evidence))
        XCTAssertEqual(numerical, HamptonARC3NumericalControl.replay(evidence: project(fixture)))
        XCTAssertEqual(numerical.steps.count, 2)
        for step in numerical.steps {
            XCTAssertTrue(step.candidate.accepted)
            XCTAssertLessThanOrEqual(step.candidate.potentialCandidate, step.candidate.potentialPrevious + 1e-12)
            XCTAssertLessThanOrEqual(sqrt(step.candidate.effectiveDelta.reduce(0) { $0 + $1 * $1 }), 0.125 + 1e-12)
        }
        let value = try object(evidence)
        let bindings = try XCTUnwrap(value["bindings"] as? [[String: Any]])
        XCTAssertFalse(bindings.isEmpty)
        for binding in bindings {
            XCTAssertNil(binding["decision"])
            XCTAssertNil(binding["controller"])
            XCTAssertNil(binding["before"])
            XCTAssertNil(binding["after"])
        }
    }

    func testNumericalEvidenceChangesTheActionChosenByTheActivePlanner() throws {
        var fixture = episode()
        append(to: &fixture, color: 2, level: 1, action: 1, lane: .expand)
        append(to: &fixture, color: 3, level: 2, action: 1, lane: .expand)
        append(to: &fixture, color: 4, level: 3, action: 1, lane: .expand)
        append(to: &fixture, color: 5, level: 4, action: 1, lane: .expand)
        append(to: &fixture, color: 6, level: 4, action: 1)
        append(to: &fixture, color: 5, level: 4, action: 1, predictedColor: 5)
        let adapted = ARC3Planner.plan(current: fixture.current, transitions: fixture.transitions,
            attempts: fixture.attempts)
        XCTAssertTrue(adapted.controller.isValid)
        XCTAssertEqual(adapted.controller.version, HamptonQ2EController.arc3NumericalVersion)
        XCTAssertEqual(adapted.controller.lane, .expand)
        XCTAssertEqual(adapted.action?.action, 2)
        XCTAssertEqual(adapted.strategy, "untried-action")
        XCTAssertTrue(ARC3Planner.matchesCurrent(adapted, current: fixture.current,
            transitions: fixture.transitions, attempts: fixture.attempts))
        let priorPolicy = HamptonQ2EController.decide(domain: "arc3", contextID: adapted.controller.contextID,
            signals: adapted.controller.signals, useNumericalControl: false)
        XCTAssertEqual(priorPolicy.lane, .retain,
            "The finite numerical updates change the approach beyond the existing count-based multiplier.")

        for index in 1...4 { fixture.attempts[index].decision = nil }
        XCTAssertFalse(ARC3Planner.matchesCurrent(adapted, current: fixture.current,
            transitions: fixture.transitions, attempts: fixture.attempts),
            "The same visible frame cannot authorize a proposal based on stale attribution.")
        let unattributed = ARC3Planner.plan(current: fixture.current, transitions: fixture.transitions,
            attempts: fixture.attempts)
        XCTAssertTrue(unattributed.controller.isValid)
        XCTAssertEqual(adapted.controller.pressures, unattributed.controller.pressures)
        XCTAssertEqual(unattributed.controller.lane, .retain)
        XCTAssertEqual(unattributed.action?.action, 1)
        XCTAssertEqual(unattributed.strategy, "observed-route",
            "Only attributable approach feedback changes which legal action is selected.")
    }

    func testForgedReceiptMissingEvidenceAndVersionDowngradeAreRejected() throws {
        var fixture = episode()
        append(to: &fixture, color: 2, level: 1, action: 1, lane: .expand)
        let plan = ARC3Planner.plan(current: fixture.current, transitions: fixture.transitions,
            attempts: fixture.attempts)
        let decision = plan.controller
        XCTAssertTrue(decision.isValid)
        XCTAssertTrue(try rejectsChange(decision) { value in
            var receipt = value["arc3NumericalControl"] as! [String: Any]
            receipt["final"] = [0.99, 0.99, 0.99]
            value["arc3NumericalControl"] = receipt
        })
        XCTAssertTrue(try rejectsChange(decision) { $0.removeValue(forKey: "arc3Evidence") })
        XCTAssertTrue(try rejectsChange(decision) { $0.removeValue(forKey: "arc3NumericalControl") })
        XCTAssertTrue(try rejectsChange(decision) { $0["version"] = HamptonQ2EController.version })
        var substituted = try object(plan)
        substituted["action"] = ["action": 7]
        let differentAction = try JSONDecoder().decode(ARC3PlanDecision.self,
            from: JSONSerialization.data(withJSONObject: substituted))
        XCTAssertFalse(ARC3Planner.matchesCurrent(differentAction, current: fixture.current,
            transitions: fixture.transitions, attempts: fixture.attempts),
            "A legal action is still invalid when substituted into another plan.")
        let archived = try JSONDecoder().decode(ARC3PlanDecision.self, from: JSONEncoder().encode(
            try XCTUnwrap(fixture.attempts.last?.decision)))
        XCTAssertEqual(archived.controller.version, HamptonQ2EController.version)
        XCTAssertTrue(archived.controller.isValid, "Existing episode decisions retain their original interpretation.")
    }

    func testNumericalPreferencesDoNotExtendBudgetOrBatchAuthority() throws {
        var fixture = episode(budget: 2)
        append(to: &fixture, color: 2, level: 1, action: 1, lane: .expand)
        let exhausted = ARC3Planner.plan(current: fixture.current, transitions: fixture.transitions,
            attempts: fixture.attempts)
        XCTAssertTrue(exhausted.controller.isValid)
        XCTAssertEqual(exhausted.controller.lane, .stop)
        XCTAssertNil(exhausted.action)

        let fresh = episode()
        let paused = ARC3Planner.plan(current: fresh.current, transitions: fresh.transitions,
            remainingBatch: 0, attempts: fresh.attempts)
        XCTAssertEqual(paused.controller.lane, .stop)
        XCTAssertNil(paused.action)
    }

    private struct Fixture {
        var current: ARC3Observation
        var transitions: [ARC3Transition] = []
        var attempts: [ARC3ActionAttempt]
    }

    private func episode(budget: Int = 16) -> Fixture {
        let initial = observation(color: 1, level: 0, dispatches: 1, budget: budget)
        return Fixture(current: initial, attempts: [ARC3ActionAttempt(id: UUID().uuidString,
            proposedAt: Date(timeIntervalSince1970: 1), baseFrameDigest: nil, baseDispatches: 0,
            action: 0, x: nil, y: nil, predictedDigest: nil, state: "observed",
            actualDigest: initial.frameDigest, outcome: "initial-reset")])
    }

    private func append(to fixture: inout Fixture, color: Int, level: Int, action: Int,
                        predictedColor: Int? = nil, lane: HamptonQ2ELane? = nil) {
        let before = fixture.current
        let after = observation(color: color, level: level, dispatches: before.dispatches + 1, budget: before.budget)
        let prediction = predictedColor.map(frameDigest)
        let verdict: ARC3PredictionVerdict = action == 0 || level != before.levelsCompleted
            ? .inconclusive : (prediction.map { $0 == after.frameDigest ? .supported : .refuted } ?? .observed)
        let outcome: String
        if action == 0 { outcome = "explicit-reset" }
        else if level > before.levelsCompleted { outcome = "environment-level-progress" }
        else if before.frameDigest == after.frameDigest { outcome = "unchanged-visible-frame" }
        else if fixture.transitions.contains(where: { $0.before.levelsCompleted == level
            && ($0.beforeDigest == after.frameDigest || $0.afterDigest == after.frameDigest) }) {
            outcome = "revisited-visible-frame"
        } else { outcome = "new-visible-frame" }
        let proposal = lane.map { legacyPlan(before: before, action: action, lane: $0, expected: prediction) }
        fixture.attempts.append(ARC3ActionAttempt(id: UUID().uuidString,
            proposedAt: Date(timeIntervalSince1970: Double(after.dispatches)),
            baseFrameDigest: before.frameDigest, baseDispatches: before.dispatches,
            action: action, x: nil, y: nil, predictedDigest: prediction, state: "observed",
            actualDigest: after.frameDigest, decision: proposal, outcome: outcome))
        fixture.transitions.append(ARC3Transition(id: UUID(), beforeDigest: before.frameDigest,
            afterDigest: after.frameDigest, action: action, x: nil, y: nil, predictedDigest: prediction,
            verdict: verdict, invalidated: verdict == .refuted, before: before, after: after))
        fixture.current = after
    }

    private func observation(color: Int, level: Int, dispatches: Int, budget: Int) -> ARC3Observation {
        ARC3Observation(gameID: game, state: "NOT_FINISHED", levelsCompleted: level, winLevels: 8,
            availableActions: [1, 2, 3, 4, 5, 7], frame: [[color]], frameDigest: frameDigest(color), dispatches: dispatches, budget: budget)
    }

    private func frameDigest(_ color: Int) -> String {
        SHA256.hash(data: try! JSONEncoder().encode([[color]])).map { String(format: "%02x", $0) }.joined()
    }

    private func legacyPlan(before: ARC3Observation, action: Int, lane: HamptonQ2ELane,
                            expected: String?) -> ARC3PlanDecision {
        let support = lane == .retain ? 1 : 0
        let corrections = lane == .repair ? 2 : 0
        let control = HamptonQ2EController.decide(domain: "arc3", contextID: "\(game)|level:\(before.levelsCompleted)",
            signals: HamptonQ2ESignals(observations: support + corrections + 1, retainedSupport: support,
                contradictions: corrections, unchangedSteps: 0, availableAlternatives: 1,
                remainingBudget: before.remainingActions, totalBudget: before.budget), useNumericalControl: false)
        XCTAssertEqual(control.lane, lane)
        return ARC3PlanDecision(gameID: game, level: before.levelsCompleted,
            baseFrameDigest: before.frameDigest, baseDispatches: before.dispatches, controller: control,
            goal: "Fixture", strategy: "untried-action", reason: "Fixture observed approach",
            action: ARC3PlannedAction(action: action, x: nil, y: nil), expectedDigest: expected)
    }

    private func project(_ fixture: Fixture) -> HamptonARC3OutcomeEvidence {
        HamptonARC3OutcomeAdapter.project(current: fixture.current, transitions: fixture.transitions, attempts: fixture.attempts)
    }

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    private func rejectsChange(_ decision: HamptonQ2EDecision, update: (inout [String: Any]) -> Void) throws -> Bool {
        var value = try object(decision)
        update(&value)
        do {
            return !(try JSONDecoder().decode(HamptonQ2EDecision.self,
                from: JSONSerialization.data(withJSONObject: value))).isValid
        } catch { return true }
    }
}
