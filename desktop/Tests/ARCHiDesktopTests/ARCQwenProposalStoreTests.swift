import Foundation
import XCTest
@testable import ARCHiDesktop

final class ARCQwenProposalStoreTests: XCTestCase {
    @MainActor
    func testCheckedProposalRetainsIndependentEvidenceAndExactLocalAccounting() async throws {
        let fixture = try ProposalStoreFixture()
        defer { fixture.cleanUp() }
        try fixture.store.loadSolverSample()
        fixture.start()
        try await waitUntil { !fixture.store.isProposing }
        let review = try XCTUnwrap(fixture.store.qwenProposalReview)
        let record = try XCTUnwrap(fixture.store.records.first)
        XCTAssertNil(review.error)
        XCTAssertEqual(review.result?.status, .predicted)
        XCTAssertEqual(review.result?.trainingPassed, 2)
        XCTAssertEqual(review.result?.predictions, [[[2, 7], [8, 0], [3, 1]]])
        XCTAssertEqual(review.evidenceID, record.id)
        XCTAssertEqual(review.taskID, record.taskID)
        XCTAssertTrue(record.summary.allExact)
        XCTAssertNil(record.solverEvidence, "A single Qwen program must not acquire catalog-consensus evidence.")
        XCTAssertEqual(fixture.client.requests.count, 1)
        let request = try XCTUnwrap(fixture.client.requests.first)
        let tests = try XCTUnwrap(request.input["input"]?["testInputs"]?.array)
        XCTAssertEqual(tests, [
            .array([
                .array([.number(7), .number(0), .number(1)]),
                .array([.number(2), .number(8), .number(3)])
            ])
        ])
        XCTAssertNil(request.input["targets"], "Checker targets cannot enter the model request.")
        XCTAssertNil(request.input["input"]?["targets"])
        XCTAssertNotNil(request.systemInstructionOverride)
        XCTAssertEqual(fixture.events.filter { !$0.proposalInProgress }.count, 1)
        XCTAssertTrue(fixture.accountingErrors.isEmpty, fixture.accountingErrors.joined(separator: "; "))
        let observation = try XCTUnwrap(fixture.steward.observations.first)
        XCTAssertEqual(observation.taskID, review.taskID)
        XCTAssertEqual(observation.provider, ARCQwenProposalInference.provider)
        XCTAssertEqual(observation.resource, .localInference)
        XCTAssertEqual(observation.model, QwenAssistant.defaultModel)
        XCTAssertEqual(observation.role, "ARC_PROPOSAL")
        XCTAssertEqual(observation.inputDigest, review.document.inputDigest)
        XCTAssertEqual(observation.inputTokens, 123)
        XCTAssertEqual(observation.outputTokens, 45)
        XCTAssertEqual(observation.elapsedMilliseconds, 17)
        XCTAssertEqual(fixture.steward.summary.localAttemptCount, 1)
        XCTAssertEqual(fixture.steward.summary.usefulTaskCount, 0)
        XCTAssertEqual(fixture.steward.summary.deliveredTaskCount, 0)
        XCTAssertTrue(fixture.steward.billingFacts.isEmpty)
        XCTAssertTrue(fixture.steward.reservations.isEmpty)

        let final = try XCTUnwrap(fixture.events.last)
        let revision = fixture.steward.revision
        try fixture.record(final)
        XCTAssertEqual(fixture.steward.revision, revision, "Receipt retry is idempotent.")
        let reopened = ARCCapabilitiesStore(storageURL: fixture.archive)
        XCTAssertNil(reopened.lastError)
        XCTAssertEqual(reopened.records.first?.id, record.id)
        XCTAssertEqual(reopened.records.first?.taskID, review.taskID)
        XCTAssertNil(reopened.records.first?.solverEvidence)
        let reopenedSteward = TokenStewardStore(url: fixture.journal)
        XCTAssertNil(reopenedSteward.loadError)
        XCTAssertEqual(reopenedSteward.observations, [observation])

        // Repeating the same explicit proposal joins its own accounting task to
        // the retained receipt without rewriting the original evidence owner.
        fixture.start()
        try await waitUntil { !fixture.store.isProposing }
        let repeated = try XCTUnwrap(fixture.store.qwenProposalReview)
        XCTAssertNil(repeated.error)
        XCTAssertEqual(repeated.evidenceID, record.id)
        XCTAssertNotEqual(repeated.taskID, record.taskID)
        XCTAssertEqual(fixture.store.records.count, 1)
        XCTAssertEqual(fixture.store.records.first?.taskID, record.taskID)
        XCTAssertEqual(fixture.steward.summary.localAttemptCount, 2)
        XCTAssertEqual(fixture.client.requests.count, 2)
        XCTAssertTrue(fixture.accountingErrors.isEmpty, fixture.accountingErrors.joined(separator: "; "))
    }

    @MainActor
    func testMalformedTerminalKeepsObservedUsageWithoutAdmittingEvidence() async throws {
        let fixture = try ProposalStoreFixture(mode: .malformed)
        defer { fixture.cleanUp() }
        try fixture.store.loadSolverSample()
        fixture.start()
        try await waitUntil { !fixture.store.isProposing }
        XCTAssertTrue(fixture.store.records.isEmpty)
        XCTAssertNil(fixture.store.qwenProposalReview?.result)
        XCTAssertNil(fixture.store.qwenProposalReview?.evidenceID)
        XCTAssertNotNil(fixture.store.qwenProposalReview?.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.archive.path))
        XCTAssertEqual(fixture.events.filter { !$0.proposalInProgress }.count, 1)
        XCTAssertEqual(fixture.client.requests.count, 1, "Malformed output does not trigger a retry.")
        XCTAssertTrue(fixture.accountingErrors.isEmpty, fixture.accountingErrors.joined(separator: "; "))
        let observation = try XCTUnwrap(fixture.steward.observations.first)
        XCTAssertEqual(observation.outcome, "complete", "Transport completed even though proposal parsing failed.")
        XCTAssertEqual(observation.inputTokens, 123)
        XCTAssertEqual(observation.outputTokens, 45)
        XCTAssertEqual(fixture.steward.tasks.first?.lanes.first?.state, "failed")
        XCTAssertEqual(fixture.steward.tasks.first?.outcomes.count, 0)
        XCTAssertEqual(fixture.steward.summary.localAttemptCount, 1)
        XCTAssertEqual(fixture.steward.summary.checkedSuccessfulTaskCount, 0)
    }

    @MainActor
    func testTaskReplacementRetiresOwnerAndLateClientCompletionCannotCommit() async throws {
        let fixture = try ProposalStoreFixture(mode: .suspended)
        defer { fixture.cleanUp() }
        try fixture.store.loadSolverSample()
        fixture.start()
        try await waitUntil { fixture.client.hasPendingResponse }
        XCTAssertEqual(fixture.steward.summary.unmeasuredLocalLaneCount, 1)
        XCTAssertEqual(fixture.steward.summary.localAttemptCount, 0)
        let oldTask = try XCTUnwrap(fixture.events.first?.taskID)
        let replacement = Data(#"{"train":[{"input":[[1]],"output":[[1]]}],"test":[{"input":[[9]],"output":[[9]]}]}"#.utf8)
        try fixture.store.loadSolverTask(data: replacement, name: "replacement.json")
        XCTAssertFalse(fixture.store.isProposing)
        XCTAssertNil(fixture.store.qwenProposalReview)
        XCTAssertEqual(fixture.store.solverDocument?.name, "replacement.json")
        let status = fixture.store.qwenProposalStatus
        let final = try XCTUnwrap(fixture.events.last)
        XCTAssertTrue(final.cancelled)
        XCTAssertEqual(final.taskID, oldTask)
        XCTAssertNil(final.evidenceID)
        XCTAssertEqual(fixture.events.filter { !$0.proposalInProgress }.count, 1)
        XCTAssertEqual(fixture.steward.summary.localAttemptCount, 1)
        XCTAssertNil(fixture.steward.observations.first?.inputTokens, "A cancelled pending response has unknown token counts.")
        let retainedJournal = try Data(contentsOf: fixture.journal)

        fixture.client.resumeResponse()
        try await waitUntil { fixture.client.didReturnResponse }
        for _ in 0..<5 { await Task.yield() }
        XCTAssertTrue(fixture.store.records.isEmpty)
        XCTAssertNil(fixture.store.qwenProposalReview)
        XCTAssertEqual(fixture.store.qwenProposalStatus, status)
        XCTAssertEqual(fixture.events.filter { !$0.proposalInProgress }.count, 1)
        XCTAssertEqual(try Data(contentsOf: fixture.journal), retainedJournal)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.archive.path))
        XCTAssertGreaterThan(fixture.client.disconnectCount, 0)
        XCTAssertTrue(fixture.accountingErrors.isEmpty, fixture.accountingErrors.joined(separator: "; "))
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "The bounded fake-client operation did not finish.")
    }
}

@MainActor
private final class ProposalStoreFixture {
    let directory: URL
    let archive: URL
    let journal: URL
    let client: ProposalStoreClient
    let store: ARCCapabilitiesStore
    let steward: TokenStewardStore
    var events: [ARCCapabilitiesEvent] = []
    var accountingErrors: [String] = []

    init(mode: ProposalStoreClient.Mode = .valid) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-qwen-proposal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        archive = directory.appendingPathComponent("arc.json")
        journal = directory.appendingPathComponent("steward.json")
        let client = ProposalStoreClient(mode: mode)
        self.client = client
        store = ARCCapabilitiesStore(storageURL: archive, qwenProposalClientFactory: { _ in client })
        steward = TokenStewardStore(url: journal)
    }

    func start() {
        store.startQwenProposal(model: QwenAssistant.defaultModel) { [weak self] event in
            guard let self else { return }
            events.append(event)
            do { try record(event) } catch { accountingErrors.append(error.localizedDescription) }
        }
    }

    func record(_ event: ARCCapabilitiesEvent) throws {
        try steward.recordEvaluation(taskID: event.taskID, evidenceID: event.evidenceID, passed: event.passed,
            startedAt: event.startedAt, finishedAt: event.finishedAt, sourceStatus: event.sourceStatus,
            error: event.error, localSolver: event.localSolver, cancelled: event.cancelled,
            proposalInference: event.proposalInference, proposalInProgress: event.proposalInProgress)
    }

    func cleanUp() {
        store.stopQwenProposal()
        client.resumeResponse()
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class ProposalStoreClient: ARCQwenProposalClient {
    enum Mode { case valid, malformed, suspended }
    let identity = QwenModelMetadata(name: QwenAssistant.defaultModel, family: "qwen35", parameterSize: "9B",
        quantization: "Q4_K_M", digest: String(repeating: "a", count: 64))
    var metadata: QwenModelMetadata?
    let mode: Mode
    var requests: [LocalRoleRequest] = []
    var disconnectCount = 0
    var didReturnResponse = false
    private var pending: CheckedContinuation<Void, Never>?
    var hasPendingResponse: Bool { pending != nil }

    init(mode: Mode) { self.mode = mode }
    func connect() async throws { metadata = identity }
    func disconnect() { disconnectCount += 1; metadata = nil }
    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
        requests.append(request)
        if mode == .suspended {
            // Deliberately ignores cancellation to exercise store ownership.
            await withCheckedContinuation { pending = $0 }
        }
        let object: [String: Any] = ["requestID": request.id,
            "inputDigest": request.input["inputDigest"]?.string ?? "missing",
            "decision": "PROPOSE", "steps": ["rotate90"], "learnPalette": false]
        let text = mode == .malformed ? "{not a proposal}" : String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        didReturnResponse = true
        return LocalRoleResult(requestID: request.id, role: .reasoning, text: text, model: identity,
            elapsedMilliseconds: 17, metrics: LocalInferenceMetrics(inputTokens: 123, outputTokens: 45))
    }
    func resumeResponse() {
        let continuation = pending
        pending = nil
        continuation?.resume()
    }
}
