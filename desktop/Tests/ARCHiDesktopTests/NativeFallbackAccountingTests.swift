import XCTest
@testable import ARCHiDesktop

final class NativeFallbackAccountingTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_789_560_000)

    @MainActor
    func testLocalSuccessClosesNativeTaskWithoutCloudLane() throws {
        let store = TokenStewardStore()
        try store.preflight(requestID: "local-success", route: .native)
        try store.recordDispatch(requestID: "local-success", provider: .qwen)
        try store.recordLane(receipt("local-success", provider: .qwen, state: .complete))

        XCTAssertEqual(store.summary.taskCount, 1)
        XCTAssertEqual(store.summary.openTaskCount, 0)
        XCTAssertEqual(store.summary.deliveredTaskCount, 1)
        XCTAssertEqual(store.summary.subscriptionRequestCount, 0)
        XCTAssertEqual(store.tasks.first?.lanes.map(\.provider), [AssistantProvider.qwen.name])
        XCTAssertThrowsError(try store.registerFallback(requestID: "local-success"))
    }

    @MainActor
    func testLocalFailureAndFallbackRemainOneTaskWithTwoLanes() throws {
        let store = TokenStewardStore()
        try store.preflight(requestID: "fallback", route: .native)
        try store.recordDispatch(requestID: "fallback", provider: .qwen)
        try store.recordLane(receipt("fallback", provider: .qwen, state: .failed))
        XCTAssertEqual(store.summary.openTaskCount, 0)

        try store.registerFallback(requestID: "fallback")
        XCTAssertEqual(store.summary.openTaskCount, 1)
        XCTAssertEqual(store.summary.subscriptionRequestCount, 0, "Admission does not imply dispatch")
        try store.recordDispatch(requestID: "fallback", provider: .codex)
        try store.recordLane(receipt("fallback", provider: .codex, state: .complete))

        XCTAssertEqual(store.summary.taskCount, 1)
        XCTAssertEqual(store.tasks.first?.lanes.count, 2)
        XCTAssertEqual(store.tasks.first?.lanes.map(\.state), ["failed", "complete"])
        XCTAssertEqual(store.summary.openTaskCount, 0)
        XCTAssertEqual(store.summary.deliveredTaskCount, 1)
        XCTAssertEqual(store.summary.subscriptionRequestCount, 1)
        XCTAssertEqual(store.observations.filter { $0.resource == .subscription }.count, 1)
        XCTAssertNil(store.summary.inputTokens, "Subscription usage remains unavailable")
        XCTAssertNil(store.summary.outputTokens)
        XCTAssertTrue(store.reservations.isEmpty, "Subscription fallback is not a paid API reservation")
    }

    @MainActor
    func testAdmissionAndReceiptReplayAreIdempotentButCannotAuthorizeAnotherAttempt() throws {
        let store = TokenStewardStore()
        try store.preflight(requestID: "replay", route: .native)
        let local = receipt("replay", provider: .qwen, state: .failed, dispatched: false)
        try store.recordLane(local)
        try store.registerFallback(requestID: "replay")
        let admittedRevision = store.revision
        try store.registerFallback(requestID: "replay")
        try store.recordLane(local)
        XCTAssertEqual(store.revision, admittedRevision)
        XCTAssertEqual(store.tasks.first?.lanes.count, 2)

        try store.recordDispatch(requestID: "replay", provider: .codex)
        XCTAssertThrowsError(try store.registerFallback(requestID: "replay"))
        let cloud = receipt("replay", provider: .codex, state: .failed)
        try store.recordLane(cloud)
        let terminalRevision = store.revision
        try store.recordLane(local)
        try store.recordLane(cloud)
        XCTAssertEqual(store.revision, terminalRevision)
        XCTAssertEqual(store.summary.subscriptionRequestCount, 1)
        XCTAssertThrowsError(try store.registerFallback(requestID: "replay"))
        XCTAssertThrowsError(try store.recordDispatch(requestID: "replay", provider: .codex))
        XCTAssertEqual(store.summary.openTaskCount, 0)
    }

    @MainActor
    func testUnregisteredCloudReceiptAndDispatchFailWithoutChangingJournal() throws {
        let store = TokenStewardStore()
        let cloud = receipt("unregistered", provider: .codex, state: .complete)
        XCTAssertThrowsError(try store.recordLane(cloud))
        XCTAssertTrue(store.tasks.isEmpty)
        try store.preflight(requestID: "unregistered", route: .native)
        try store.recordLane(receipt("unregistered", provider: .qwen, state: .failed))
        let before = store.tasks, revision = store.revision
        XCTAssertThrowsError(try store.recordDispatch(requestID: "unregistered", provider: .codex))
        XCTAssertThrowsError(try store.recordLane(cloud))
        XCTAssertEqual(store.tasks, before)
        XCTAssertEqual(store.revision, revision)
        XCTAssertEqual(store.summary.subscriptionRequestCount, 0)
    }

    @MainActor
    func testFallbackRequiresFailedNativeLaneAndPreservesLocalOnlyRoutes() throws {
        let store = TokenStewardStore()
        XCTAssertThrowsError(try store.registerFallback(requestID: "missing"))
        for state in [AssistantLaneState.pending, .complete, .cancelled] {
            let id = "native-\(state.rawValue)"
            try store.preflight(requestID: id, route: .native)
            if state != .pending { try store.recordLane(receipt(id, provider: .qwen, state: state)) }
            let before = store.tasks
            XCTAssertThrowsError(try store.registerFallback(requestID: id))
            XCTAssertEqual(store.tasks, before)
        }
        for route in [AssistantRoute.local, .automatic] {
            let id = "failed-\(route.rawValue)"
            try store.preflight(requestID: id, route: route)
            try store.recordLane(receipt(id, provider: .qwen, state: .failed, route: route))
            let before = store.tasks
            XCTAssertThrowsError(try store.registerFallback(requestID: id))
            XCTAssertEqual(store.tasks, before)
        }
        XCTAssertEqual(store.summary.subscriptionRequestCount, 0)
    }

    @MainActor
    func testFallbackJournalReopensAndRejectsTamperedLocalOutcome() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ARCHi-NativeFallback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("usage.json")
        let store = TokenStewardStore(url: url)
        try store.preflight(requestID: "restart", route: .native)
        try store.recordLane(receipt("restart", provider: .qwen, state: .failed, dispatched: false))
        try store.registerFallback(requestID: "restart")
        try store.recordDispatch(requestID: "restart", provider: .codex)
        try store.recordLane(receipt("restart", provider: .codex, state: .complete))
        let reopened = TokenStewardStore(url: url)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.tasks, store.tasks)
        XCTAssertEqual(reopened.summary.subscriptionRequestCount, 1)
        XCTAssertEqual(reopened.summary.openTaskCount, 0)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var tasks = try XCTUnwrap(json["tasks"] as? [[String: Any]])
        var lanes = try XCTUnwrap(tasks[0]["lanes"] as? [[String: Any]])
        lanes[0]["state"] = "complete"
        tasks[0]["lanes"] = lanes
        json["tasks"] = tasks
        try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]).write(to: url)
        let rejected = TokenStewardStore(url: url)
        XCTAssertNotNil(rejected.loadError)
        XCTAssertFalse(rejected.summary.accountingAvailable)
    }

    private func receipt(_ id: String, provider: AssistantProvider, state: AssistantLaneState,
                         dispatched: Bool = true, route: AssistantRoute = .native) -> AssistantLaneReceipt {
        AssistantLaneReceipt(requestID: id, route: route, provider: provider,
            context: ContextTicket(generation: 0, placement: 0, source: 0, selection: 0),
            inputDigest: "native-input-digest", inputContract: AssistantRequest.inputContract,
            deadline: date.addingTimeInterval(60), modelIdentity: "fixture", state: state,
            requestStarted: dispatched, localInvocationReceipts: provider == .qwen ? [] : nil,
            elapsedMilliseconds: 20)
    }
}
