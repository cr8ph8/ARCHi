import Foundation
import CryptoKit
import XCTest
@testable import ARCHiDesktop

final class ARC3SessionTests: XCTestCase {
    @MainActor
    func testStopRetiresOwnerBeforeLateStepResponse() async throws {
        let client = ARC3FakeTransport(suspendSteps: true)
        let fixture = makeStore(client)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        var completions: [ARC3SessionSummary] = []
        fixture.store.onFinished = { completions.append($0) }
        try await start(fixture.store)
        let initial = fixture.store.observation
        fixture.store.step(action: 1)
        try await waitUntil { client.hasPending }
        XCTAssertEqual(fixture.store.attempts.last?.state, "requested")
        XCTAssertEqual(fixture.store.attempts.last?.baseFrameDigest, initial?.frameDigest)
        let pendingReceipt = try XCTUnwrap(fixture.store.receiptURL)
        let pendingJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: pendingReceipt)) as? [String: Any])
        let pendingAttempts = try XCTUnwrap(pendingJSON["attempts"] as? [[String: Any]])
        XCTAssertEqual(pendingAttempts.last?["state"] as? String, "requested", "The attempted action is persisted before its response.")
        fixture.store.stop(reason: "User stopped.")
        XCTAssertFalse(fixture.store.isWorking)
        XCTAssertFalse(fixture.store.isSessionActive)
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(completions.first?.outcome, "stopped")
        XCTAssertEqual(completions.first?.dispatches, 1)
        XCTAssertEqual(completions.first?.attemptedDispatches, 2)
        XCTAssertEqual(completions.first?.unreconciledDispatches, 1)
        XCTAssertEqual(fixture.store.attempts.last?.state, "unreconciled")
        let receipt = try XCTUnwrap(fixture.store.receiptURL)
        let stoppedBytes = try Data(contentsOf: receipt)
        client.resumePending()
        try await waitUntil { client.returnedPending }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(fixture.store.observation, initial)
        XCTAssertTrue(fixture.store.transitions.isEmpty)
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(try Data(contentsOf: receipt), stoppedBytes)
    }

    @MainActor
    func testBudgetAndTerminalCloseWithoutAnotherDispatch() async throws {
        for terminal in [false, true] {
            let client = ARC3FakeTransport(terminalAfterStep: terminal)
            let fixture = makeStore(client)
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            var outcomes: [String] = []
            fixture.store.onFinished = { outcomes.append($0.outcome) }
            try await start(fixture.store, budget: terminal ? 8 : 2)
            fixture.store.explore(maxActions: 8)
            try await waitUntil { !fixture.store.isWorking }
            XCTAssertFalse(fixture.store.isSessionActive)
            XCTAssertEqual(client.stepRequests, 1)
            XCTAssertEqual(client.closeRequests, 1)
            XCTAssertEqual(outcomes, [terminal ? "complete" : "budget-exhausted"])
            fixture.store.step(action: 1)
            XCTAssertEqual(client.stepRequests, 1)
        }
    }

    @MainActor
    func testIllegalActionAndCoordinateCannotReachTransport() async throws {
        let client = ARC3FakeTransport()
        let fixture = makeStore(client)
        defer { fixture.store.stop(); try? FileManager.default.removeItem(at: fixture.directory) }
        try await start(fixture.store)
        fixture.store.step(action: 7)
        XCTAssertNotNil(fixture.store.error)
        fixture.store.step(action: 6, x: 64, y: 1)
        XCTAssertNotNil(fixture.store.error)
        fixture.store.step(action: 1, x: 0)
        XCTAssertEqual(client.stepRequests, 0)
        XCTAssertEqual(fixture.store.observation?.dispatches, 1)
        XCTAssertTrue(fixture.store.isSessionActive)
    }

    @MainActor
    func testContradictionInvalidatesEarlierTaskLocalPrediction() async throws {
        let client = ARC3FakeTransport(frames: [1, 2, 1, 3])
        let fixture = makeStore(client)
        defer { fixture.store.stop(); try? FileManager.default.removeItem(at: fixture.directory) }
        try await start(fixture.store)
        for _ in 0..<3 {
            fixture.store.step(action: 1)
            try await waitUntil { !fixture.store.isWorking }
        }
        XCTAssertEqual(fixture.store.transitions.map(\.verdict), [.observed, .observed, .refuted])
        XCTAssertTrue(fixture.store.transitions[0].invalidated)
        XCTAssertFalse(fixture.store.transitions[1].invalidated)
        XCTAssertEqual(fixture.store.transitions[2].predictedDigest, fixture.store.transitions[0].afterDigest)
        XCTAssertNotEqual(fixture.store.transitions[2].predictedDigest, fixture.store.transitions[2].afterDigest)
        XCTAssertEqual(fixture.store.attempts.last?.predictedDigest, fixture.store.transitions[0].afterDigest)
        XCTAssertEqual(fixture.store.observation?.frame, [[3]])
    }

    @MainActor
    func testMalformedObservationFailsClosedWithoutPublishingFrame() async throws {
        let client = ARC3FakeTransport(badDigest: true)
        let fixture = makeStore(client)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.store.discover()
        try await waitUntil { !fixture.store.isWorking }
        fixture.store.start()
        try await waitUntil { !fixture.store.isWorking }
        XCTAssertFalse(fixture.store.isSessionActive)
        XCTAssertNil(fixture.store.observation)
        XCTAssertTrue(fixture.store.transitions.isEmpty)
        XCTAssertNotNil(fixture.store.error)
        XCTAssertEqual(client.stepRequests, 0)
    }

    @MainActor
    private func makeStore(_ client: ARC3FakeTransport) -> (store: ARC3SessionStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-arc3-test-\(UUID().uuidString)")
        return (ARC3SessionStore(outputDirectory: directory, transportFactory: { _ in client }), directory)
    }

    @MainActor
    private func start(_ store: ARC3SessionStore, budget: Int = 8) async throws {
        store.discover()
        try await waitUntil { !store.isWorking }
        store.start(budget: budget)
        try await waitUntil { !store.isWorking }
        XCTAssertTrue(store.isSessionActive, store.error ?? "Expected active fake session.")
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition(), "The bounded fake ARC3 operation did not finish.")
    }
}

private final class ARC3FakeTransport: ARC3Transport, @unchecked Sendable {
    private let lock = NSLock()
    private let suspendSteps: Bool
    private let terminalAfterStep: Bool
    private let frames: [Int]
    private let badDigest: Bool
    private var steps = 0
    private var closes = 0
    private var budget = 8
    private var pending: (CheckedContinuation<ARC3Response, Never>, ARC3Response)?
    private var returned = false

    init(suspendSteps: Bool = false, terminalAfterStep: Bool = false, frames: [Int] = [1, 2], badDigest: Bool = false) {
        self.suspendSteps = suspendSteps
        self.terminalAfterStep = terminalAfterStep
        self.frames = frames
        self.badDigest = badDigest
    }
    var hasPending: Bool { lock.withLock { pending != nil } }
    var returnedPending: Bool { lock.withLock { returned } }
    var stepRequests: Int { lock.withLock { steps } }
    var closeRequests: Int { lock.withLock { closes } }
    func stop() {} // Deliberately leaves a pending reply alive to test ownership.

    func request(_ request: ARC3Request) async throws -> ARC3Response {
        let response = lock.withLock { makeResponse(request) }
        if suspendSteps && request.command == "step" {
            let result = await withCheckedContinuation { continuation in
                lock.withLock { pending = (continuation, response) }
            }
            lock.withLock { returned = true }
            return result
        }
        return response
    }

    func resumePending() {
        let value = lock.withLock { let value = pending; pending = nil; return value }
        value?.0.resume(returning: value!.1)
    }

    private func makeResponse(_ request: ARC3Request) -> ARC3Response {
        if request.command == "discover" { return ARC3Response(id: request.id, ok: true, games: [ARC3Game(id: "fixture-v1", title: "Test fixture")]) }
        if request.command == "start" { budget = request.budget ?? 8; steps = 0 }
        if request.command == "step" { steps += 1 }
        if request.command == "close" { closes += 1 }
        let frame = [[frames[min(steps, frames.count - 1)]]]
        let bytes = try! JSONEncoder().encode(frame)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let won = terminalAfterStep && steps > 0
        let observation = ARC3Observation(gameID: "fixture-v1", state: won ? "WIN" : "NOT_FINISHED",
            levelsCompleted: won ? 1 : 0, winLevels: 1, availableActions: [1, 6], frame: frame,
            frameDigest: badDigest ? "bad" : digest, dispatches: steps + 1, budget: budget)
        return ARC3Response(id: request.id, ok: true, observation: observation)
    }
}
