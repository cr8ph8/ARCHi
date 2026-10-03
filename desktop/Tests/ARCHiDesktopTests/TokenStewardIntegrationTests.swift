import XCTest
@testable import ARCHiDesktop

/// No transport leaves the process. These tests exercise the real request owner,
/// local validator and durable journal rather than importing hand-built lanes.
final class TokenStewardIntegrationTests: XCTestCase {
    @MainActor
    func testCompareSharesOneTaskAndRetainsUnknownSubscriptionTokens() async throws {
        let fixture = try StewardIntegrationFixture()
        defer { fixture.cleanUp() }
        try await beginCompare(fixture)
        fixture.reasoner.resolve(0)
        try await waitUntil { fixture.store.compareResults[.qwen]?.state == .complete }
        XCTAssertEqual(fixture.store.tokenSteward.tasks.count, 1)
        XCTAssertEqual(fixture.store.tokenSteward.summary.openTaskCount, 1)
        XCTAssertEqual(fixture.store.tokenSteward.summary.localAttemptCount, 1)
        XCTAssertEqual(fixture.store.tokenSteward.summary.subscriptionRequestCount, 1)
        XCTAssertNil(fixture.store.tokenSteward.summary.inputTokens)
        fixture.external.resolve(0)
        try await waitUntil { !fixture.store.isWorking }

        let task = try XCTUnwrap(fixture.store.tokenSteward.tasks.first)
        let localID = try XCTUnwrap(fixture.store.compareResults[.qwen]?.receipt?.requestID)
        XCTAssertEqual(task.id, localID)
        XCTAssertEqual(task.id, fixture.store.compareResults[.codex]?.receipt?.requestID)
        XCTAssertEqual(Set(task.lanes.map(\.provider)), ["Qwen", "Codex"])
        XCTAssertTrue(task.isClosed)
        XCTAssertTrue(task.delivered)
        XCTAssertFalse(task.userUseful, "Delivery is not user acceptance")
        XCTAssertEqual(fixture.store.tokenSteward.summary.deliveredTaskCount, 1)
        XCTAssertEqual(fixture.store.tokenSteward.summary.knownInputTokens, 44)
        XCTAssertEqual(fixture.store.tokenSteward.summary.knownOutputTokens, 11)
        XCTAssertEqual(fixture.store.tokenSteward.summary.missingInputCount, 1)
        XCTAssertNil(fixture.store.tokenSteward.summary.outputTokens)
        XCTAssertTrue(fixture.store.tokenSteward.reservations.isEmpty)
        XCTAssertTrue(fixture.store.tokenSteward.billingFacts.isEmpty)
        XCTAssertEqual(Set(fixture.store.tokenSteward.observations.map(\.taskID)), [task.id])
    }

    @MainActor
    func testPartialFailurePreservesIndependentOutcomeAndDoesNotImplyUsefulness() async throws {
        for failLocal in [true, false] {
            let fixture = try StewardIntegrationFixture()
            defer { fixture.cleanUp() }
            try await beginCompare(fixture)
            if failLocal {
                fixture.reasoner.resolve(0, result: .failure(QwenFailure.stopped))
                fixture.external.resolve(0)
            } else {
                fixture.reasoner.resolve(0)
                fixture.external.resolve(0, result: .failure(AssistantFailure.timedOut))
            }
            try await waitUntil { !fixture.store.isWorking }
            let task = try XCTUnwrap(fixture.store.tokenSteward.tasks.first)
            XCTAssertTrue(task.isClosed)
            XCTAssertTrue(task.delivered)
            XCTAssertEqual(task.lanes.first { $0.provider == (failLocal ? "Qwen" : "Codex") }?.state, "failed")
            XCTAssertEqual(task.lanes.first { $0.provider == (failLocal ? "Codex" : "Qwen") }?.state, "complete")
            XCTAssertEqual(fixture.store.tokenSteward.summary.localAttemptCount, 1)
            XCTAssertEqual(fixture.store.tokenSteward.summary.subscriptionRequestCount, 1)
            XCTAssertEqual(fixture.store.tokenSteward.summary.usefulTaskCount, 0)
            XCTAssertEqual(fixture.store.tokenSteward.summary.checkedSuccessfulTaskCount, 0)
        }
    }

    @MainActor
    func testStopKeepsAttemptAndLateCallbacksCannotReviveOrDoubleCount() async throws {
        let fixture = try StewardIntegrationFixture()
        defer { fixture.cleanUp() }
        try await beginCompare(fixture)
        fixture.external.emit(0, text: "INCOMPLETE_EXTERNAL_TEXT")
        fixture.store.cancelWork()
        let stopped = fixture.store.tokenSteward.tasks
        let observations = fixture.store.tokenSteward.observations
        let revision = fixture.store.tokenSteward.revision
        XCTAssertEqual(stopped.count, 1)
        XCTAssertEqual(stopped.first?.lanes.map(\.state), ["cancelled", "cancelled"])
        XCTAssertEqual(fixture.store.tokenSteward.summary.localAttemptCount, 1)
        XCTAssertEqual(fixture.store.tokenSteward.summary.subscriptionRequestCount, 1)
        XCTAssertNil(observations.first { $0.resource == .localInference }?.inputTokens)

        fixture.external.emit(0, text: "LATE_EXTERNAL_TEXT")
        fixture.external.resolve(0)
        fixture.reasoner.resolve(0)
        try await waitUntil { fixture.external.finished == 1 && fixture.reasoner.finished == 1 }
        await Task.yield()
        XCTAssertFalse(fixture.store.isWorking)
        XCTAssertEqual(fixture.store.tokenSteward.tasks, stopped)
        XCTAssertEqual(fixture.store.tokenSteward.observations, observations)
        XCTAssertEqual(fixture.store.tokenSteward.revision, revision)
        XCTAssertEqual(fixture.store.tokenSteward.summary.deliveredTaskCount, 0)
    }

    @MainActor
    func testUsefulFeedbackAndOriginalTerminalSurviveSourceResetAndReopenWithoutText() async throws {
        let fixture = try StewardIntegrationFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.share(text: "PRIVATE_DOCUMENT_SENTINEL", name: "PRIVATE_FILENAME_SENTINEL.txt")
        try await connect(store)
        store.prompt = "PRIVATE_QUESTION_SENTINEL"
        store.submit()
        try await waitUntil { fixture.reasoner.requests.count == 1 }
        fixture.reasoner.resolve(0)
        try await waitUntil { !store.isWorking }
        let requestID = try XCTUnwrap(store.compareResults[.qwen]?.receipt?.requestID)
        XCTAssertEqual(store.tokenSteward.summary.usefulTaskCount, 0)
        XCTAssertTrue(store.markReplyUsefulForEvolution(provider: .qwen, requestID: requestID))
        XCTAssertFalse(store.markReplyUsefulForEvolution(provider: .qwen, requestID: requestID), "A repeated click is not another acceptance")
        let task = try XCTUnwrap(store.tokenSteward.tasks.first)
        XCTAssertTrue(task.userUseful)
        XCTAssertEqual(task.outcomes.count, 1)

        store.share(text: "REPLACEMENT_DOCUMENT_SENTINEL", name: "replacement.txt")
        store.placed(at: CGPoint(x: 411, y: 219))
        XCTAssertEqual(store.tokenSteward.tasks.first, task, "Context invalidation must not relabel already completed historical work")
        let exported = try store.tokenSteward.exportData()
        let text = String(decoding: exported, as: UTF8.self)
        for secret in ["PRIVATE_DOCUMENT_SENTINEL", "PRIVATE_FILENAME_SENTINEL", "PRIVATE_QUESTION_SENTINEL", "PRIVATE_ANSWER_SENTINEL", "REPLACEMENT_DOCUMENT_SENTINEL"] {
            XCTAssertFalse(text.contains(secret), "The usage journal must exclude source and conversation content")
        }
        let reopened = CompanionStore(preferenceURL: fixture.profile, assistant: StewardExternalClient(), allowsPlay: false)
        XCTAssertNil(reopened.tokenSteward.loadError)
        XCTAssertEqual(reopened.tokenSteward.tasks, [task])
        XCTAssertEqual(reopened.tokenSteward.observations, store.tokenSteward.observations)
        XCTAssertEqual(reopened.tokenSteward.summary.usefulTaskCount, 1)
        XCTAssertTrue(reopened.compareResults.isEmpty, "Accounting reopen must not recreate answer UI or text")
    }

    @MainActor
    func testCorruptJournalPreservedAndBlocksActualDispatch() async throws {
        let fixture = try StewardIntegrationFixture()
        defer { fixture.cleanUp() }
        let corrupt = Data("{not valid accounting}".utf8)
        try corrupt.write(to: fixture.journal)
        try await connect(fixture.store)
        fixture.store.prompt = "Do not dispatch without accounting."
        fixture.store.submit()
        await Task.yield()
        XCTAssertFalse(fixture.store.isWorking)
        XCTAssertTrue(fixture.reasoner.requests.isEmpty)
        XCTAssertTrue(fixture.external.requests.isEmpty)
        XCTAssertNotNil(fixture.store.stewardMessage)
        XCTAssertEqual(try Data(contentsOf: fixture.journal), corrupt)
    }

    @MainActor
    func testJournalFailureBetweenPreflightAndTransportPreventsInvocationAndCanRetry() async throws {
        let fixture = try StewardIntegrationFixture()
        defer { fixture.cleanUp() }
        try await connect(fixture.store)
        fixture.store.prompt = "Prepare this local task."
        fixture.store.submit()
        let prepared = try Data(contentsOf: fixture.journal)
        try FileManager.default.removeItem(at: fixture.journal)
        try FileManager.default.createDirectory(at: fixture.journal, withIntermediateDirectories: false)
        try await waitUntil { !fixture.store.isWorking }
        XCTAssertTrue(fixture.reasoner.requests.isEmpty, "A successful preflight cannot bypass a later failed dispatch journal write")
        XCTAssertNotNil(fixture.store.stewardMessage)
        try FileManager.default.removeItem(at: fixture.journal)
        try prepared.write(to: fixture.journal)

        // Next Send reconciles the retained owner-finalized failure before making
        // a new request. No missing attempt is invented for the unsent task.
        try await connect(fixture.store)
        fixture.store.submit()
        try await waitUntil { fixture.reasoner.requests.count == 1 }
        fixture.reasoner.resolve(0)
        try await waitUntil { !fixture.store.isWorking }
        XCTAssertEqual(fixture.store.tokenSteward.tasks.count, 2)
        XCTAssertEqual(fixture.store.tokenSteward.summary.openTaskCount, 0)
        XCTAssertEqual(fixture.store.tokenSteward.summary.localAttemptCount, 1)
        XCTAssertEqual(fixture.store.tokenSteward.summary.deliveredTaskCount, 1)
        XCTAssertEqual(fixture.store.tokenSteward.tasks.flatMap(\.lanes).filter { $0.dispatched }.count, 1)
    }

    @MainActor
    func testARCRescoringUsesSeparateTaskWithoutBillingOrEvolutionMutation() throws {
        let fixture = try StewardIntegrationFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        let revision = store.evolution.revision
        let history = store.evolution.history
        let event = store.arcCapabilities.runSyntheticDemonstration()
        XCTAssertNil(event.error)
        XCTAssertEqual(event.passed, false, "The synthetic demonstration intentionally scores one of two tasks exact")
        store.recordARCEvaluation(event)
        store.recordARCEvaluation(event)
        XCTAssertEqual(store.tokenSteward.tasks.count, 1, "The same checker callback is replay safe")
        let task = try XCTUnwrap(store.tokenSteward.tasks.first)
        XCTAssertEqual(task.id, event.taskID)
        XCTAssertEqual(task.route, "arc-evaluation")
        XCTAssertFalse(task.checkedSuccessful)
        XCTAssertEqual(task.outcomes.first?.value, false)
        XCTAssertEqual(task.outcomes.first?.evidenceID, event.evidenceID)
        XCTAssertEqual(task.lanes.first?.admission, event.sourceStatus)
        XCTAssertEqual(store.tokenSteward.summary.evaluationTaskCount, 1)
        XCTAssertEqual(store.tokenSteward.summary.deliveredTaskCount, 0)
        XCTAssertEqual(store.tokenSteward.summary.usefulTaskCount, 0)
        XCTAssertEqual(store.tokenSteward.summary.checkedSuccessfulTaskCount, 0)
        XCTAssertEqual(store.tokenSteward.summary.localAttemptCount, 0)
        XCTAssertEqual(store.tokenSteward.summary.subscriptionRequestCount, 0)
        XCTAssertTrue(store.tokenSteward.observations.isEmpty)
        XCTAssertTrue(store.tokenSteward.reservations.isEmpty)
        XCTAssertEqual(store.evolution.revision, revision)
        XCTAssertEqual(store.evolution.history, history)
        XCTAssertTrue(store.evolution.usefulReceipts.isEmpty)
        XCTAssertTrue(fixture.reasoner.requests.isEmpty)
        XCTAssertTrue(fixture.external.requests.isEmpty)
    }

    func testMoneyEntryPreservesNanoDollarPrecisionAndRejectsOverflow() {
        XCTAssertEqual(TokenStewardPresentation.nanoUSD(" 1.000000001 "), 1_000_000_001)
        XCTAssertEqual(TokenStewardPresentation.nanoUSD("0.000000001"), 1)
        XCTAssertEqual(TokenStewardPresentation.nanoUSD("0"), 0)
        XCTAssertEqual(TokenStewardPresentation.nanoUSD("9223372036.854775807"), Int64.max)
        XCTAssertEqual(TokenStewardPresentation.dollars(Int64.max), "9223372036.854775807")
        for invalid in ["", "-1", "1e3", "+1", "NaN", "Infinity", "1,000", "1.0000000001", "9223372036.854775808", "9223372037", "999999999999999999999", "1.2.3", "１"] {
            XCTAssertNil(TokenStewardPresentation.nanoUSD(invalid), invalid)
        }
    }

    @MainActor
    func testOptInLiveLocalQwenPersistsMeasuredUsage() async throws {
        guard ProcessInfo.processInfo.environment["ARCHI_STEWARD_LIVE"] == "1" else {
            throw XCTSkip("Set ARCHI_STEWARD_LIVE=1 to run one bounded real local Qwen request")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-steward-live-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let profile = directory.appendingPathComponent("preferences.json")
        try NativePreferenceDocument().encoded().write(to: profile)
        let store = CompanionStore(preferenceURL: profile, allowsPlay: false)
        defer {
            store.disconnectAssistant(provider: .qwen)
            try? FileManager.default.removeItem(at: directory)
        }
        store.setAssistantRoute(.automatic)
        store.prompt = "What is 2 + 2? Reply with only the digit 4."
        store.submit()
        for _ in 0..<240 {
            if !store.isWorking { break }
            try await Task.sleep(for: .milliseconds(500))
        }
        if let outputPath = ProcessInfo.processInfo.environment["ARCHI_STEWARD_LIVE_DIR"] {
            let output = URL(fileURLWithPath: outputPath)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try store.tokenSteward.exportData().write(to: output.appendingPathComponent("local-usage-journal.json"), options: .atomic)
            let result: [String: Any] = ["schema": "archi-steward-local-demonstration/v1",
                "reply": store.reply, "state": store.compareResults[.qwen]?.state.rawValue ?? "missing",
                "localAttempts": store.tokenSteward.summary.localAttemptCount,
                "inputTokens": store.tokenSteward.summary.inputTokens as Any? ?? NSNull(),
                "outputTokens": store.tokenSteward.summary.outputTokens as Any? ?? NSNull(),
                "subscriptionRequests": store.tokenSteward.summary.subscriptionRequestCount,
                "apiReservations": store.tokenSteward.reservations.count]
            try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .prettyPrinted])
                .write(to: output.appendingPathComponent("local-result.json"), options: .atomic)
        }
        XCTAssertFalse(store.isWorking, "The real local request must finish within two minutes")
        let receipt = try XCTUnwrap(store.compareResults[.qwen]?.receipt)
        XCTAssertEqual(receipt.state, .complete)
        XCTAssertEqual(store.reply.trimmingCharacters(in: .whitespacesAndNewlines), "4")
        let attempts = try XCTUnwrap(receipt.localInvocationReceipts)
        XCTAssertFalse(attempts.isEmpty)
        XCTAssertEqual(store.tokenSteward.summary.localAttemptCount, attempts.count)
        for invocation in attempts {
            if let input = invocation.metrics?.inputTokens { XCTAssertGreaterThan(input, 0) }
            if let output = invocation.metrics?.outputTokens { XCTAssertGreaterThan(output, 0) }
        }
        XCTAssertEqual(store.tokenSteward.summary.subscriptionRequestCount, 0)
        XCTAssertTrue(store.tokenSteward.reservations.isEmpty)
        XCTAssertEqual(store.tokenSteward.tasks.first?.id, receipt.requestID)
        let reopened = TokenStewardStore(url: profile.deletingPathExtension().appendingPathExtension("steward.json"))
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.observations, store.tokenSteward.observations)
        XCTAssertEqual(reopened.summary.localAttemptCount, attempts.count)
    }

    @MainActor
    private func beginCompare(_ fixture: StewardIntegrationFixture) async throws {
        fixture.store.setAssistantRoute(.compare)
        try await connect(fixture.store)
        fixture.store.prompt = "Compare this bounded synthetic task."
        fixture.store.submit()
        try await waitUntil { fixture.reasoner.requests.count == 1 && fixture.external.requests.count == 1 }
    }

    @MainActor
    private func connect(_ store: CompanionStore) async throws {
        store.connectAssistant()
        try await waitUntil { store.connectionState == .ready }
    }

    @MainActor
    private func waitUntil(file: StaticString = #filePath, line: UInt = #line,
                           _ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("In-process Steward fixture did not reach its bounded expected state", file: file, line: line)
        throw StewardIntegrationFailure.waitTimedOut
    }
}

private enum StewardIntegrationFailure: Error { case waitTimedOut }

@MainActor
private final class StewardIntegrationFixture {
    let directory: URL
    let profile: URL
    var journal: URL { profile.deletingPathExtension().appendingPathExtension("steward.json") }
    let reasoner = StewardRoleClient()
    let selector = StewardRoleClient(hold: false)
    let external = StewardExternalClient()
    let store: CompanionStore

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-steward-integration-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        profile = directory.appendingPathComponent("preferences.json")
        try NativePreferenceDocument().encoded().write(to: profile)
        let local = HamptonReasonsAssistant(reasoner: reasoner, contextSelector: selector)
        let cloud = external
        store = CompanionStore(preferenceURL: profile, assistant: local,
            assistantFactory: { provider, _ in
                if provider == .qwen { return local }
                return cloud
            }, allowsPlay: false)
    }

    func cleanUp() {
        store.disconnectAssistant(provider: .qwen)
        store.disconnectAssistant(provider: .codex)
        reasoner.drain(); selector.drain(); external.drain()
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class StewardRoleClient: LocalRoleClient {
    let hold: Bool
    private(set) var requests: [LocalRoleRequest] = []
    private(set) var finished = 0
    private var pending: [Int: CheckedContinuation<Void, Error>] = [:]
    init(hold: Bool = true) { self.hold = hold }
    func connect() async throws {}
    func disconnect() {}
    func shutdown() async {}
    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
        let index = requests.count
        requests.append(request)
        defer { finished += 1 }
        if hold { try await withCheckedThrowingContinuation { pending[index] = $0 } }
        let payload: JSONValue
        switch request.role {
        case .reasoning:
            let sources = request.input["sources"]?.array?.compactMap { $0["id"]?.string } ?? []
            payload = .object(["requestID": .string(request.id), "schema": .string("archi-reason-proposal/v1"),
                "kind": .string("ANSWER"), "answer": .string("PRIVATE_ANSWER_SENTINEL"), "uncertainty": .string(""),
                "sourceIDs": .array(sources.map(JSONValue.string)), "memoryIDs": .array([])])
        case .memorySelection:
            payload = .object(["requestID": .string(request.id), "schema": .string("archi-session-selection/v1"), "candidateIDs": .array([])])
        case .memoryReminder:
            payload = .object(["requestID": .string(request.id), "schema": .string("archi-session-reminder/v1"), "decision": .string("NONE"), "memoryIDs": .array([])])
        }
        return LocalRoleResult(requestID: request.id, role: request.role,
            text: String(decoding: try JSONEncoder().encode(payload), as: UTF8.self),
            model: QwenModelMetadata(name: "steward-fixture", family: "fixture", parameterSize: "fixture", quantization: "fixture", digest: String(repeating: "c", count: 64)),
            elapsedMilliseconds: 12, metrics: LocalInferenceMetrics(inputTokens: 44, outputTokens: 11, totalNanoseconds: 12_000_000))
    }
    func resolve(_ index: Int, result: Result<Void, Error> = .success(())) { pending.removeValue(forKey: index)?.resume(with: result) }
    func drain() { let all = Array(pending.values); pending.removeAll(); all.forEach { $0.resume(throwing: QwenFailure.stopped) } }
}

@MainActor
private final class StewardExternalClient: AssistantClient {
    private(set) var requests: [AssistantRequest] = []
    private(set) var finished = 0
    private var pending: [Int: CheckedContinuation<Void, Error>] = [:]
    private var events: [Int: @MainActor (AssistantEvent) -> Void] = [:]
    func connect() async throws {}
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        let index = requests.count
        requests.append(request); events[index] = onEvent
        defer { finished += 1 }
        try await withCheckedThrowingContinuation { pending[index] = $0 }
        onEvent(.text("PRIVATE_EXTERNAL_ANSWER_SENTINEL"))
    }
    func emit(_ index: Int, text: String) { events[index]?(.text(text)) }
    func resolve(_ index: Int, result: Result<Void, Error> = .success(())) { pending.removeValue(forKey: index)?.resume(with: result) }
    func drain() { let all = Array(pending.values); pending.removeAll(); all.forEach { $0.resume(throwing: AssistantFailure.stopped) } }
}
