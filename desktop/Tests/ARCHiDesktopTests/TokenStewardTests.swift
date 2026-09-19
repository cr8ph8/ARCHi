import XCTest
import Darwin
@testable import ARCHiDesktop

final class TokenStewardTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_789_560_000)

    @MainActor
    func testOpeningAndRefreshingMissingJournalDoesNotCreateProfileArtifacts() throws {
        let url = try journalURL().deletingLastPathComponent().appendingPathComponent("new-profile/usage.json")
        let folder = url.deletingLastPathComponent()
        let store = TokenStewardStore(url: url)
        try store.refresh()
        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.summary.taskCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try store.refresh()
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)

        try store.preflight(requestID: "explicit-dispatch", route: .local)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let reopened = TokenStewardStore(url: url)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.tasks.map(\.id), ["explicit-dispatch"])
    }

    @MainActor
    func testCompareHasOneTaskAndIndependentAttemptsAndOutcomes() throws {
        let store = TokenStewardStore(now: { self.date })
        try store.preflight(requestID: "compare", route: .compare)
        try store.recordDispatch(requestID: "compare", provider: .qwen)
        try store.recordDispatch(requestID: "compare", provider: .codex)
        var local = receipt("compare", route: .compare, provider: .qwen)
        local.localInvocationReceipts = [invocation("select", role: .memorySelection), invocation("answer")]
        try store.recordLane(local)
        XCTAssertEqual(store.summary.taskCount, 1)
        XCTAssertEqual(store.summary.openTaskCount, 1, "A delivered sibling cannot close Compare")
        XCTAssertEqual(store.summary.localAttemptCount, 2)
        XCTAssertEqual(store.summary.subscriptionRequestCount, 1)
        XCTAssertNil(store.summary.inputTokens, "Pending Codex usage is unavailable")
        try store.recordUseful(requestID: "compare")
        var cloud = receipt("compare", route: .compare, provider: .codex)
        cloud.state = .failed
        try store.recordLane(cloud)
        XCTAssertEqual(store.summary.openTaskCount, 0)
        XCTAssertEqual(store.summary.deliveredTaskCount, 1)
        XCTAssertEqual(store.summary.usefulTaskCount, 1)
        XCTAssertEqual(store.summary.checkedSuccessfulTaskCount, 0)
        XCTAssertEqual(store.summary.knownAPIChargeNanoUSD, 0)
        XCTAssertNil(store.summary.apiCostPerUsefulTaskNanoUSD)
        XCTAssertEqual(store.observations.filter { $0.resource == .subscription }.count, 1)
        try store.recordLane(local)
        XCTAssertEqual(store.summary.localAttemptCount, 2)
    }

    @MainActor
    func testUnknownCountersNeverBecomeZeroOrCompleteCost() throws {
        let store = TokenStewardStore(now: { self.date })
        var local = receipt("local")
        var attempt = invocation("answer")
        attempt.metrics = LocalInferenceMetrics(inputTokens: 12)
        local.localInvocationReceipts = [attempt]
        try store.recordLane(local)
        XCTAssertEqual(store.summary.inputTokens, 12)
        XCTAssertNil(store.summary.outputTokens)
        XCTAssertEqual(store.summary.missingOutputCount, 1)
        XCTAssertEqual(store.summary.knownOutputTokens, 0, "Known subset is separate from total")
        XCTAssertNil(store.summary.closedAPITaskChargeNanoUSD)
    }

    @MainActor
    func testInterruptedLocalLaneStaysOpenAcrossRestartWithoutInventedGenerate() throws {
        let url = try journalURL()
        let store = TokenStewardStore(url: url, now: { self.date })
        try store.preflight(requestID: "interrupted", route: .local)
        try store.recordDispatch(requestID: "interrupted", provider: .qwen)
        let reloaded = TokenStewardStore(url: url)
        XCTAssertNil(reloaded.loadError)
        XCTAssertEqual(reloaded.summary.openTaskCount, 1)
        XCTAssertEqual(reloaded.summary.localAttemptCount, 0)
        XCTAssertEqual(reloaded.summary.unmeasuredLocalLaneCount, 1)
        XCTAssertNil(reloaded.summary.inputTokens)
    }

    @MainActor
    func testStoppedLaneCannotBeRevivedByLateAnswer() throws {
        let store = TokenStewardStore(now: { self.date })
        var stopped = receipt("stop")
        stopped.state = .cancelled
        var attempted = invocation("answer")
        attempted.outcome = .cancelled
        attempted.metrics = nil
        stopped.localInvocationReceipts = [attempted]
        try store.recordLane(stopped)
        var late = stopped
        late.state = .complete
        XCTAssertThrowsError(try store.recordLane(late))
        XCTAssertThrowsError(try store.recordUseful(requestID: "stop"))
        XCTAssertEqual(store.tasks.first?.lanes.first?.state, "cancelled")
        XCTAssertEqual(store.summary.localAttemptCount, 1)
        XCTAssertEqual(store.summary.deliveredTaskCount, 0)
    }

    @MainActor
    func testExplicitCheckedEvidenceDoesNotFollowDeliveredOrUseful() throws {
        let store = TokenStewardStore(now: { self.date })
        try store.recordLane(receipt("checked"))
        try store.recordUseful(requestID: "checked")
        XCTAssertEqual(store.summary.checkedSuccessfulTaskCount, 0)
        try store.recordChecked(requestID: "checked", evidenceID: "independent-check-v1", passed: false)
        try store.recordChecked(requestID: "checked", evidenceID: "independent-check-v2", passed: true)
        XCTAssertEqual(store.summary.checkedSuccessfulTaskCount, 1)
        XCTAssertEqual(store.tasks.first?.outcomes.count, 3)
        XCTAssertThrowsError(try store.recordChecked(requestID: "checked", evidenceID: "independent-check-v2", passed: false))
    }

    @MainActor
    func testAPIRequiresBudgetButLocalAndSubscriptionDoNot() throws {
        let store = TokenStewardStore()
        try store.preflight(requestID: "local", route: .local)
        try store.preflight(requestID: "subscription", route: .codex)
        XCTAssertThrowsError(try reserve(store, "paid")) { XCTAssertEqual($0 as? TokenStewardError, .budgetUnset) }
        XCTAssertEqual(store.summary.taskCount, 2)
        XCTAssertTrue(store.reservations.isEmpty)
    }

    @MainActor
    func testSeparateStoresSerializeReservationsAgainstLatestJournal() throws {
        let url = try journalURL()
        let first = TokenStewardStore(url: url, now: { self.date })
        let second = TokenStewardStore(url: url, now: { self.date })
        try first.configureBudget(budget(daily: 1_000))
        try reserve(first, "first", amount: 600)
        XCTAssertThrowsError(try reserve(second, "second", amount: 600)) { XCTAssertEqual($0 as? TokenStewardError, .budgetExceeded) }
        try second.refresh()
        XCTAssertEqual(second.summary.reservedNanoUSD, 600)
        XCTAssertEqual(second.reservations.count, 1)
    }

    @MainActor
    func testConflictingReconciliationCannotOverwriteFirstWriter() throws {
        let url = try journalURL()
        let first = TokenStewardStore(url: url, now: { self.date })
        let second = TokenStewardStore(url: url, now: { self.date })
        let event = observation("invoice")
        try first.importObservations([event])
        try first.reconcile(observationID: event.id, amountNanoUSD: 900, sourceID: "bill-A")
        XCTAssertThrowsError(try second.reconcile(observationID: event.id, amountNanoUSD: 100, sourceID: "bill-B"))
        try second.refresh()
        XCTAssertEqual(second.summary.knownAPIChargeNanoUSD, 900)
        XCTAssertEqual(second.billingFacts.count, 1)
    }

    @MainActor
    func testImmutableReimportAfterBillingEnrichmentIsIdempotent() throws {
        let store = TokenStewardStore()
        let event = observation("immutable")
        try store.importObservations([event])
        try store.reconcile(observationID: event.id, amountNanoUSD: 77, sourceID: "bill")
        let revision = store.revision
        try store.importObservations([event])
        try store.reconcile(observationID: event.id, amountNanoUSD: 77, sourceID: "bill")
        XCTAssertEqual(store.revision, revision)
        XCTAssertEqual(store.observations, [event])
        XCTAssertEqual(store.billingFacts.count, 1)
        XCTAssertEqual(store.summary.knownAPIChargeNanoUSD, 77)
    }

    @MainActor
    func testConflictingBatchRollsBackAllImports() throws {
        let store = TokenStewardStore()
        try store.importObservations([observation("same")])
        let conflict = observation("same", input: 999)
        XCTAssertThrowsError(try store.importObservations([observation("new"), conflict]))
        XCTAssertEqual(store.observations.map(\.id), ["same"])
    }

    @MainActor
    func testEarlierMonthUnresolvedChargeRemainsVisibleAndBlocks() throws {
        let store = TokenStewardStore(now: { self.date })
        try store.configureBudget(budget())
        let priorMonth = date.addingTimeInterval(-45 * 86_400)
        try store.importObservations([observation("old", at: priorMonth)])
        XCTAssertEqual(store.summary.unresolvedAPIObservationCount, 1)
        XCTAssertEqual(store.unresolvedObservations.first?.observedAt, priorMonth)
        XCTAssertThrowsError(try reserve(store, "next")) { XCTAssertEqual($0 as? TokenStewardError, .unresolvedCharges) }
    }

    @MainActor
    func testUnknownSettlementAndEstimateRetainHoldUntilFinalCharge() throws {
        let store = TokenStewardStore(now: { self.date })
        try store.configureBudget(budget())
        try reserve(store, "one", amount: 600)
        try store.markAPISent(reservationID: "hold-one")
        let event = observation("one", task: "one", input: 12, output: nil)
        try store.settleAPI(observation: event, reservationID: "hold-one")
        try store.recordEstimate(observationID: "one", amountNanoUSD: 50, sourceID: "partial-estimate")
        XCTAssertEqual(store.summary.reservedNanoUSD, 600)
        XCTAssertEqual(store.summary.estimatedAPIChargeNanoUSD, 50)
        XCTAssertEqual(store.summary.unresolvedAPIObservationCount, 1)
        XCTAssertNil(store.summary.outputTokens)
        XCTAssertThrowsError(try reserve(store, "blocked"))
        try store.reconcile(observationID: "one", amountNanoUSD: 90, sourceID: "final-provider-bill")
        XCTAssertEqual(store.summary.reservedNanoUSD, 0)
        XCTAssertEqual(store.summary.knownAPIChargeNanoUSD, 90)
        XCTAssertEqual(store.summary.estimatedAPIChargeNanoUSD, 0)
        XCTAssertEqual(store.observations.first?.outputTokens, nil, "Billing does not fabricate usage")
    }

    @MainActor
    func testStopAfterDispatchCannotReleaseHoldAndSurvivesRestart() throws {
        let url = try journalURL()
        let store = TokenStewardStore(url: url, now: { self.date })
        try store.configureBudget(budget())
        try reserve(store, "sent", amount: 600)
        try store.markAPISent(reservationID: "hold-sent")
        XCTAssertThrowsError(try store.markAPISent(reservationID: "hold-sent"), "A dispatch permit cannot be reused")
        XCTAssertThrowsError(try store.cancelUnsent(reservationID: "hold-sent"))
        try store.finishAPITask(taskID: "sent", outcome: "cancelled")
        let reloaded = TokenStewardStore(url: url)
        XCTAssertEqual(reloaded.summary.reservedNanoUSD, 600)
        XCTAssertEqual(reloaded.reservations.first?.state, .sent)
        XCTAssertEqual(reloaded.tasks.first?.lanes.first?.state, "cancelled")
        XCTAssertEqual(reloaded.summary.closedAPITaskCount, 1)
        XCTAssertNil(reloaded.summary.closedAPITaskChargeNanoUSD)
    }

    @MainActor
    func testNeverSentCancellationReleasesOnlyItsOwnHold() throws {
        let store = TokenStewardStore()
        try store.configureBudget(budget())
        try reserve(store, "unsent", amount: 600)
        try store.cancelUnsent(reservationID: "hold-unsent")
        try store.cancelUnsent(reservationID: "hold-unsent")
        XCTAssertEqual(store.summary.reservedNanoUSD, 0)
        XCTAssertThrowsError(try store.markAPISent(reservationID: "hold-unsent"))
        XCTAssertThrowsError(try reserve(store, "unsent", amount: 600))
    }

    @MainActor
    func testChargeAboveReservedMaximumIsRetainedAndBlocksFutureOverspend() throws {
        let store = TokenStewardStore(now: { self.date })
        try store.configureBudget(budget(daily: 1_000))
        try reserve(store, "over", amount: 100)
        try store.markAPISent(reservationID: "hold-over")
        try store.settleAPI(observation: observation("over", task: "over"), reservationID: "hold-over", finalChargeNanoUSD: 1_200, sourceID: "invoice")
        XCTAssertEqual(store.summary.knownAPIChargeNanoUSD, 1_200)
        XCTAssertEqual(store.summary.reservedNanoUSD, 0)
        XCTAssertThrowsError(try reserve(store, "next", amount: 1))
    }

    @MainActor
    func testDisabledOrReducedBudgetBlocksReservedButUnsentDispatch() throws {
        let store = TokenStewardStore()
        try store.configureBudget(budget())
        try reserve(store, "first", amount: 600)
        try store.configureBudget(nil)
        XCTAssertThrowsError(try store.markAPISent(reservationID: "hold-first"))
        try store.configureBudget(budget(daily: 500))
        XCTAssertThrowsError(try store.markAPISent(reservationID: "hold-first"))
        XCTAssertEqual(store.reservations.first?.state, .reserved)
    }

    @MainActor
    func testTaskEconomicsCountLifetimeFailedRetriesAndOneUsefulTask() throws {
        let store = TokenStewardStore(now: { self.date })
        try store.configureBudget(budget())
        try reserve(store, "useful", amount: 100)
        try store.markAPISent(reservationID: "hold-useful")
        try store.settleAPI(observation: observation("attempt1", task: "useful", outcome: "failed"), reservationID: "hold-useful", finalChargeNanoUSD: 100, sourceID: "bill1")
        try store.reserveAPI(taskID: "useful", reservationID: "retry", maximumNanoUSD: 200, provider: "provider", accountID: "account")
        try store.markAPISent(reservationID: "retry")
        try store.settleAPI(observation: observation("attempt2", task: "useful"), reservationID: "retry", finalChargeNanoUSD: 200, sourceID: "bill2")
        XCTAssertEqual(store.summary.openTaskCount, 1, "Receipt ordering cannot decide final task outcome")
        try store.finishAPITask(taskID: "useful", outcome: "complete")
        try store.recordUseful(requestID: "useful")
        try reserve(store, "failed", amount: 50)
        try store.markAPISent(reservationID: "hold-failed")
        try store.settleAPI(observation: observation("failed", task: "failed", outcome: "failed"), reservationID: "hold-failed", finalChargeNanoUSD: 50, sourceID: "bill3")
        try store.finishAPITask(taskID: "failed", outcome: "failed")
        try store.recordLane(receipt("local"))
        try store.recordUseful(requestID: "local")
        XCTAssertEqual(store.summary.closedAPITaskCount, 2)
        XCTAssertEqual(store.summary.usefulClosedAPITaskCount, 1)
        XCTAssertEqual(store.summary.closedAPITaskChargeNanoUSD, 350)
        XCTAssertEqual(store.summary.apiCostPerUsefulTaskNanoUSD, 350)
        XCTAssertEqual(store.summary.usefulTaskCount, 2, "Local feedback is still visible, outside API denominator")
    }

    @MainActor
    func testUnresolvedClosedTaskPreventsMisleadingCostPerUsefulTask() throws {
        let store = TokenStewardStore()
        try store.configureBudget(budget())
        try reserve(store, "unknown", amount: 100)
        try store.markAPISent(reservationID: "hold-unknown")
        try store.settleAPI(observation: observation("unknown", task: "unknown"), reservationID: "hold-unknown")
        try store.finishAPITask(taskID: "unknown", outcome: "complete")
        try store.recordUseful(requestID: "unknown")
        XCTAssertNil(store.summary.apiCostPerUsefulTaskNanoUSD)
        XCTAssertNil(store.summary.closedAPITaskChargeNanoUSD)
        XCTAssertEqual(store.summary.usefulClosedAPITaskCount, 1)
    }

    @MainActor
    func testARCChecksStayOutsideAssistanceAndCostDenominators() throws {
        let store = TokenStewardStore()
        try store.recordEvaluation(taskID: "arc", evidenceID: "sha256:synthetic", passed: true,
            startedAt: date, finishedAt: date.addingTimeInterval(2), sourceStatus: "synthetic-fixture", error: nil)
        try store.recordEvaluation(taskID: "bad-arc", evidenceID: nil, passed: nil,
            startedAt: date, finishedAt: date.addingTimeInterval(1), sourceStatus: nil, error: "Rejected input")
        XCTAssertEqual(store.summary.evaluationTaskCount, 2)
        XCTAssertEqual(store.summary.syntheticCheckedTaskCount, 1)
        XCTAssertEqual(store.summary.deliveredTaskCount, 0)
        XCTAssertEqual(store.summary.checkedSuccessfulTaskCount, 0)
        XCTAssertEqual(store.summary.localAttemptCount, 0)
        XCTAssertEqual(store.summary.subscriptionRequestCount, 0)
        XCTAssertThrowsError(try store.recordUseful(requestID: "arc"))
        XCTAssertEqual(store.tasks.first(where: { $0.id == "bad-arc" })?.lanes.first?.state, "failed")
    }

    @MainActor
    func testMalformedJournalFailsClosedWithoutOverwritingWork() throws {
        let url = try journalURL()
        let invalid = Data("not-a-journal".utf8)
        try invalid.write(to: url)
        let store = TokenStewardStore(url: url)
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.preflight(requestID: "new", route: .local))
        XCTAssertThrowsError(try store.configureBudget(budget()))
        XCTAssertEqual(try Data(contentsOf: url), invalid)
    }

    @MainActor
    func testProcessLockPreventsConflictingWriterRatherThanLosingEvidence() throws {
        let url = try journalURL()
        let store = TokenStewardStore(url: url)
        let fd = open(url.appendingPathExtension("lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { flock(fd, LOCK_UN); close(fd) }
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        XCTAssertThrowsError(try store.preflight(requestID: "locked", route: .local))
        XCTAssertTrue(store.tasks.isEmpty)
        XCTAssertEqual(flock(fd, LOCK_UN), 0)
        try store.preflight(requestID: "retry", route: .local)
        XCTAssertEqual(store.tasks.count, 1)
    }

    @MainActor
    func testPrivateJournalAndExportContainNoPromptContent() throws {
        let url = try journalURL()
        let store = TokenStewardStore(url: url)
        try store.recordLane(receipt("safe"))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let exported = String(decoding: try store.exportData(), as: UTF8.self)
        XCTAssertFalse(exported.contains("replyText"))
        XCTAssertFalse(exported.contains("prompt"))
        XCTAssertTrue(exported.contains("inputDigest"))
    }

    @MainActor
    func testMeasurementSubsetsAndOverflowRejectWithoutPartialAdmission() throws {
        let store = TokenStewardStore()
        let invalid = TokenStewardObservation(id: "bad", taskID: "task", provider: "provider", resource: .api,
            observedAt: date, outcome: "complete", inputTokens: 2, outputTokens: 2,
            cacheReadTokens: 2, cacheWriteTokens: 1, reasoningTokens: 3)
        XCTAssertThrowsError(try store.importObservations([invalid]))
        XCTAssertTrue(store.observations.isEmpty)
        try store.importObservations([observation("huge", input: Int64.max, output: 0)])
        XCTAssertThrowsError(try store.importObservations([observation("overflow", input: 1, output: 0)]))
        XCTAssertEqual(store.observations.count, 1)
        XCTAssertThrowsError(try store.configureBudget(TokenStewardBudget(dailyNanoUSD: -1, monthlyNanoUSD: 1, timeZoneID: "UTC")))
        XCTAssertThrowsError(try store.configureBudget(TokenStewardBudget(dailyNanoUSD: 1, monthlyNanoUSD: 1, timeZoneID: "made-up")))
    }

    @MainActor
    func testZeroCeilingIsAnExplicitSpendingBlock() throws {
        let store = TokenStewardStore()
        try store.configureBudget(TokenStewardBudget(dailyNanoUSD: 0, monthlyNanoUSD: 0, timeZoneID: "UTC"))
        XCTAssertThrowsError(try reserve(store, "blocked")) { XCTAssertEqual($0 as? TokenStewardError, .budgetExceeded) }
    }

    @MainActor
    func testTwoAPIProvidersAndAccountsRetainOneApplicationTask() throws {
        let store = TokenStewardStore(now: { self.date })
        try store.configureBudget(budget())
        try reserve(store, "shared", amount: 100)
        try store.reserveAPI(taskID: "shared", reservationID: "second-provider", maximumNanoUSD: 200,
            provider: "provider-B", accountID: "account-B")
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.tasks.first?.lanes.count, 2)
        XCTAssertEqual(store.reservations.count, 2)
        try store.markAPISent(reservationID: "hold-shared")
        try store.markAPISent(reservationID: "second-provider")
        try store.settleAPI(observation: observation("one", task: "shared"), reservationID: "hold-shared", finalChargeNanoUSD: 100, sourceID: "bill-A")
        let other = TokenStewardObservation(id: "two", taskID: "shared", provider: "provider-B", accountID: "account-B",
            resource: .api, observedAt: date, outcome: "complete")
        try store.settleAPI(observation: other, reservationID: "second-provider", finalChargeNanoUSD: 200, sourceID: "bill-B")
        try store.finishAPITask(taskID: "shared", outcome: "complete")
        try store.recordUseful(requestID: "shared")
        XCTAssertEqual(store.summary.closedAPITaskCount, 1)
        XCTAssertEqual(store.summary.apiCostPerUsefulTaskNanoUSD, 300)
    }

    @MainActor
    func testImportedARCChecksAreNotCountedAsSynthetic() throws {
        let store = TokenStewardStore()
        try store.recordEvaluation(taskID: "import", evidenceID: "sha256:import", passed: true,
            startedAt: date, finishedAt: date.addingTimeInterval(1), sourceStatus: "user-imported", error: nil)
        XCTAssertEqual(store.summary.syntheticCheckedTaskCount, 0)
        XCTAssertEqual(store.summary.evaluationTaskCount, 1)
    }

    @MainActor
    func testUnobservedRetryHoldKeepsLifetimeCostUnavailable() throws {
        let store = TokenStewardStore(now: { self.date })
        try store.configureBudget(budget())
        try reserve(store, "retry", amount: 100)
        try store.markAPISent(reservationID: "hold-retry")
        try store.settleAPI(observation: observation("charged", task: "retry"), reservationID: "hold-retry", finalChargeNanoUSD: 100, sourceID: "bill")
        try store.reserveAPI(taskID: "retry", reservationID: "unknown-retry", maximumNanoUSD: 200, provider: "provider", accountID: "account")
        try store.markAPISent(reservationID: "unknown-retry")
        try store.finishAPITask(taskID: "retry", outcome: "complete")
        try store.recordUseful(requestID: "retry")
        XCTAssertEqual(store.summary.closedAPITaskCount, 1)
        XCTAssertEqual(store.summary.usefulClosedAPITaskCount, 1)
        XCTAssertNil(store.summary.closedAPITaskChargeNanoUSD)
        XCTAssertNil(store.summary.apiCostPerUsefulTaskNanoUSD)
    }

    @MainActor
    func testOneObservationCannotReleaseTwoDistinctDispatchHolds() throws {
        let store = TokenStewardStore()
        try store.configureBudget(budget())
        try reserve(store, "task", amount: 100)
        try store.reserveAPI(taskID: "task", reservationID: "second", maximumNanoUSD: 100, provider: "provider", accountID: "account")
        try store.markAPISent(reservationID: "hold-task")
        try store.markAPISent(reservationID: "second")
        let event = observation("unique-send", task: "task")
        try store.settleAPI(observation: event, reservationID: "hold-task", finalChargeNanoUSD: 80, sourceID: "bill")
        XCTAssertThrowsError(try store.settleAPI(observation: event, reservationID: "second", finalChargeNanoUSD: 80, sourceID: "bill"))
        XCTAssertEqual(store.summary.reservedNanoUSD, 100)
        XCTAssertEqual(store.summary.knownAPIChargeNanoUSD, 80)
    }

    @MainActor
    func testCorruptTaskLaneAndOutcomeRejectReload() throws {
        let url = try journalURL()
        let store = TokenStewardStore(url: url)
        try store.recordLane(receipt("task"))
        try store.recordUseful(requestID: "task")
        let good = try store.exportData()
        for corruption in ["lane", "duplicate", "outcome", "route"] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: good) as? [String: Any])
            var tasks = try XCTUnwrap(object["tasks"] as? [[String: Any]])
            var lanes = try XCTUnwrap(tasks[0]["lanes"] as? [[String: Any]])
            switch corruption {
            case "lane": lanes[0]["state"] = "trusted-by-magic"
            case "duplicate": lanes.append(lanes[0])
            case "route": tasks[0]["route"] = "invented-route"
            default:
                var outcomes = try XCTUnwrap(tasks[0]["outcomes"] as? [[String: Any]])
                outcomes[0]["revision"] = Int.max
                tasks[0]["outcomes"] = outcomes
            }
            tasks[0]["lanes"] = lanes; object["tasks"] = tasks
            let bad = try JSONSerialization.data(withJSONObject: object)
            try bad.write(to: url)
            let reloaded = TokenStewardStore(url: url)
            XCTAssertNotNil(reloaded.loadError, corruption)
            XCTAssertThrowsError(try reloaded.configureBudget(budget()), corruption)
            XCTAssertEqual(try Data(contentsOf: url), bad)
        }
    }

    @MainActor
    func testCorruptReservationLinkageFailsClosed() throws {
        let url = try journalURL()
        let store = TokenStewardStore(url: url)
        try store.configureBudget(budget())
        try reserve(store, "task")
        try store.markAPISent(reservationID: "hold-task")
        try store.settleAPI(observation: observation("send", task: "task"), reservationID: "hold-task", finalChargeNanoUSD: 50, sourceID: "bill")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: store.exportData()) as? [String: Any])
        var reservations = try XCTUnwrap(object["reservations"] as? [[String: Any]])
        reservations[0]["accountID"] = "unrelated-account"
        object["reservations"] = reservations
        let bad = try JSONSerialization.data(withJSONObject: object)
        try bad.write(to: url)
        let reloaded = TokenStewardStore(url: url)
        XCTAssertNotNil(reloaded.loadError)
        XCTAssertThrowsError(try reserve(reloaded, "new"))
        XCTAssertEqual(try Data(contentsOf: url), bad)
    }

    @MainActor
    func testLiveSubprocessHoldingLockBlocksWriterUntilRelease() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else { throw XCTSkip("System Python unavailable for process contention fixture") }
        let url = try journalURL()
        let store = TokenStewardStore(url: url)
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", "import fcntl,sys\nf=open(sys.argv[1],'a')\nfcntl.flock(f,fcntl.LOCK_EX)\nprint('R',flush=True)\nsys.stdin.buffer.read(1)\n", url.appendingPathExtension("lock").path]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        defer { try? input.fileHandleForWriting.close(); if process.isRunning { process.terminate() }; process.waitUntilExit() }
        var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, 5_000) > 0 else { XCTFail("Lock fixture did not become ready"); return }
        XCTAssertEqual(try output.fileHandleForReading.read(upToCount: 1), Data("R".utf8))
        XCTAssertThrowsError(try store.preflight(requestID: "blocked-by-process", route: .local))
        XCTAssertTrue(store.tasks.isEmpty)
        try input.fileHandleForWriting.write(contentsOf: Data([1]))
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        try store.preflight(requestID: "after-release", route: .local)
        XCTAssertEqual(store.tasks.count, 1)
    }

    private func journalURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-steward-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("steward.json")
    }

    private func budget(daily: Int64 = 10_000) -> TokenStewardBudget {
        TokenStewardBudget(dailyNanoUSD: daily, monthlyNanoUSD: 100_000, timeZoneID: "America/Los_Angeles")
    }

    @MainActor
    private func reserve(_ store: TokenStewardStore, _ id: String, amount: Int64 = 100) throws {
        try store.reserveAPI(taskID: id, reservationID: "hold-\(id)", maximumNanoUSD: amount, provider: "provider", accountID: "account")
    }

    private func observation(_ id: String, task: String = "task", at: Date? = nil,
                             outcome: String = "complete", input: Int64? = 10, output: Int64? = 5) -> TokenStewardObservation {
        TokenStewardObservation(id: id, taskID: task, provider: "provider", accountID: "account",
            resource: .api, observedAt: at ?? date, outcome: outcome, inputTokens: input, outputTokens: output)
    }

    private func invocation(_ id: String, role: LocalModelRole = .reasoning) -> HamptonInvocationReceipt {
        HamptonInvocationReceipt(id: id, role: role, inputDigest: "input", systemDigest: "system", schemaDigest: "schema",
            outcome: .completed, elapsedMilliseconds: 250, metrics: LocalInferenceMetrics(inputTokens: 10, outputTokens: 5))
    }

    private func receipt(_ id: String, route: AssistantRoute = .local, provider: AssistantProvider = .qwen) -> AssistantLaneReceipt {
        AssistantLaneReceipt(requestID: id, route: route, provider: provider,
            context: ContextTicket(generation: 0, placement: 0, source: 0, selection: 0), inputDigest: "input-digest",
            inputContract: "native-assistant-input/v2", deadline: date.addingTimeInterval(60), modelIdentity: "fixture",
            state: .complete, requestStarted: true,
            localInvocationReceipts: provider == .qwen ? [invocation("answer")] : nil, elapsedMilliseconds: 250)
    }
}
