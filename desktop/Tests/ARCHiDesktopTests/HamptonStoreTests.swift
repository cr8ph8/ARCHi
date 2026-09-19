import XCTest
@testable import ARCHiDesktop

final class HamptonStoreTests: XCTestCase {
    @MainActor
    func testNativeWrapperStartsWithContextOffAndOnlyExplicitSendGenerates() async throws {
        let factory = HamptonStoreFactory()
        let store = CompanionStore(preferenceURL: preferences,
            assistantFactory: { provider, model in factory.make(provider, model) }, tokenSteward: TokenStewardStore())
        defer { store.disconnectAssistant(); factory.drain() }
        let rig = try XCTUnwrap(factory.rigs.first)
        XCTAssertEqual(store.assistantProvider, .qwen)
        XCTAssertFalse(store.sessionContextEnabled)
        XCTAssertFalse(rig.assistant.contextEnabled)
        XCTAssertEqual(rig.reasoner.connectCount, 0)
        XCTAssertEqual(rig.selector.connectCount, 0)
        XCTAssertTrue(rig.reasoner.requests.isEmpty)
        XCTAssertTrue(rig.selector.requests.isEmpty)
        XCTAssertTrue(store.hamptonSnapshot.records.isEmpty)
        store.prompt = "An unsent draft."
        try await connect(store)
        XCTAssertEqual(rig.reasoner.connectCount, 1)
        XCTAssertEqual(rig.selector.connectCount, 0)
        XCTAssertTrue(rig.reasoner.requests.isEmpty)
        store.submit()
        try await waitUntil("An explicit Send should complete") { !store.isWorking }
        XCTAssertEqual(rig.reasoner.requests.map(\.role), [.reasoning])
        XCTAssertTrue(rig.selector.requests.isEmpty)
        XCTAssertEqual(store.reply, "Store fixture answer")
        XCTAssertEqual(store.hamptonSnapshot.proposal?.answer, store.reply)
        XCTAssertEqual(store.hamptonSnapshot.receipts.map(\.role), [.reasoning])
        XCTAssertEqual(store.compareResults[.qwen]?.receipt?.localInvocations, [.reasoning])
        XCTAssertTrue(store.hamptonSnapshot.records.isEmpty)
        XCTAssertEqual(store.hamptonSnapshot.turn, 0)
    }

    @MainActor
    func testEnablingContextIsExplicitAndInspectSnapshotIsACopy() async throws {
        let rig = HamptonStoreRig(), store = makeStore(rig)
        defer { store.disconnectAssistant(); rig.drain() }
        store.share(text: "A local shared copy.", name: "notes.txt")
        store.prompt = "Keep the explanation brief."
        store.placed(at: CGPoint(x: -200, y: 450))
        store.setSessionContextEnabled(true)
        XCTAssertTrue(store.sessionContextEnabled)
        XCTAssertTrue(rig.assistant.contextEnabled)
        XCTAssertTrue(rig.reasoner.requests.isEmpty)
        XCTAssertTrue(rig.selector.requests.isEmpty)
        XCTAssertEqual(rig.reasoner.connectCount, 0)
        XCTAssertEqual(rig.selector.connectCount, 0)
        try await connect(store)
        store.submit()
        try await waitUntil("The context-enabled turn should complete") { !store.isWorking }
        XCTAssertEqual(rig.selector.requests.map(\.role), [.memorySelection])
        XCTAssertEqual(store.hamptonSnapshot.records.map(\.text), ["Keep the explanation brief."])
        XCTAssertEqual(store.hamptonSnapshot.turn, 1)
        XCTAssertEqual(store.hamptonSnapshot.receipts.map(\.role), [.memorySelection, .reasoning])
        XCTAssertEqual(store.hamptonSnapshot.attemptedInvocations, [.memorySelection, .reasoning])
        XCTAssertEqual(store.compareResults[.qwen]?.receipt?.localInvocations, [.memorySelection, .reasoning])
        let inspected = store.hamptonSnapshot
        store.clearSessionContext()
        XCTAssertTrue(store.hamptonSnapshot.records.isEmpty)
        XCTAssertNil(store.hamptonSnapshot.proposal)
        XCTAssertEqual(inspected.records.map(\.text), ["Keep the explanation brief."])
        XCTAssertNotNil(inspected.proposal)
        XCTAssertTrue(store.sessionContextEnabled)
        XCTAssertEqual(store.prompt, "Keep the explanation brief.")
        XCTAssertEqual(store.sharedText, "A local shared copy.")
        XCTAssertEqual(store.position, CGPoint(x: -200, y: 450))
    }

    @MainActor
    func testClearingContextCancelsPendingTurnAndLateResultCannotRestoreIt() async throws {
        try await checkReset(.clear)
    }

    @MainActor
    func testDisablingContextCancelsPendingTurnAndLateResultCannotRestoreIt() async throws {
        try await checkReset(.disable)
    }

    @MainActor
    func testReplacingSharedCopyClearsBankAndRejectsOldPendingResult() async throws {
        try await checkReset(.share)
    }

    @MainActor
    func testStoppingSharingClearsBankAndRejectsOldPendingResult() async throws {
        try await checkReset(.stopSharing)
    }

    @MainActor
    func testRouteAndModelChangesFenceObsoleteSnapshotsAndPreserveUnrelatedContext() async throws {
        for change in [Replacement.provider, .reasoningModel, .contextModel] {
            let factory = HamptonStoreFactory(), old = HamptonStoreRig()
            let store = makeStore(old, factory: factory)
            defer { store.disconnectAssistant(); old.drain(); factory.drain() }
            try await seed(store)
            let oldSnapshot = store.hamptonSnapshot
            let callback = try XCTUnwrap(old.assistant.onSnapshot)
            let pending = try await suspendNextTurn(store, rig: old)
            let sourceRevision = store.sourceRevision
            switch change {
            case .provider: store.selectAssistantProvider(.codex)
            case .reasoningModel: store.selectQwenModel("qwen3:8b")
            case .contextModel:
                factory.nextContextModel = QwenAssistant.defaultModel
                store.selectQwenContextModel(QwenAssistant.defaultModel)
            }
            XCTAssertEqual(factory.providers.count, 1)
            XCTAssertFalse(store.isWorking)
            XCTAssertEqual(store.connectionState, .disconnected)
            if change == .provider {
                XCTAssertEqual(store.hamptonSnapshot.records, oldSnapshot.records,
                               "Changing routes retains the local bank without transferring it to Codex")
            } else {
                XCTAssertTrue(store.hamptonSnapshot.records.isEmpty)
            }
            XCTAssertNil(store.hamptonSnapshot.proposal)
            XCTAssertEqual(store.sharedText, "One. Two.")
            XCTAssertEqual(store.sourceRevision, sourceRevision)
            XCTAssertEqual(store.prompt, "A follow-up still in progress.")
            XCTAssertTrue(factory.rigs.allSatisfy { $0.reasoner.requests.isEmpty && $0.selector.requests.isEmpty })
            let replacementSnapshot = store.hamptonSnapshot
            callback(oldSnapshot)
            XCTAssertEqual(store.hamptonSnapshot, replacementSnapshot,
                           "An obsolete wrapper callback cannot replace the new client's inspector")
            try await connect(store)
            let currentSnapshot = store.hamptonSnapshot, status = store.status, message = store.connectionMessage
            old.reasoner.resolve(pending)
            try await waitUntil("The obsolete role result should drain") { old.reasoner.finished.contains(pending) }
            await Task.yield()
            callback(oldSnapshot)
            XCTAssertEqual(store.connectionState, .ready)
            XCTAssertEqual(store.hamptonSnapshot, currentSnapshot)
            XCTAssertEqual(store.status, status)
            XCTAssertEqual(store.connectionMessage, message)
            XCTAssertTrue(factory.rigs.allSatisfy { $0.reasoner.requests.isEmpty && $0.selector.requests.isEmpty })
            XCTAssertTrue(factory.codexClients.allSatisfy { $0.replyCount == 0 })
        }
    }

    @MainActor
    func testPlacementAndSelectionRevisionCancelPendingContextWithoutPublishingTentativeBank() async throws {
        for move in [true, false] {
            let rig = HamptonStoreRig(), store = makeStore(rig)
            defer { store.disconnectAssistant(); rig.drain() }
            try await seed(store)
            store.selectText(range: NSRange(location: 0, length: 4), sourceRevision: store.sourceRevision)
            let committedRecords = store.hamptonSnapshot.records
            let pending = try await suspendNextTurn(store, rig: rig)
            let ticket = store.contextTicket()
            if move { store.placed(at: CGPoint(x: -375, y: 512)) }
            else { store.selectText(range: NSRange(location: 5, length: 4), sourceRevision: store.sourceRevision) }
            XCTAssertFalse(store.isCurrent(ticket, requireVisible: false))
            XCTAssertFalse(store.isWorking)
            XCTAssertEqual(store.connectionState, .disconnected)
            XCTAssertNil(store.hamptonSnapshot.proposal)
            XCTAssertEqual(store.hamptonSnapshot.records, committedRecords)
            let after = store.hamptonSnapshot, reply = store.reply, status = store.status
            rig.reasoner.resolve(pending)
            try await waitUntil("The stale placement/selection result should drain") { rig.reasoner.finished.contains(pending) }
            await Task.yield()
            XCTAssertEqual(store.hamptonSnapshot, after)
            XCTAssertEqual(store.reply, reply)
            XCTAssertEqual(store.status, status)
            XCTAssertEqual(store.hamptonSnapshot.turn, 1)
            if move { XCTAssertEqual(store.position, CGPoint(x: -375, y: 512)) }
            else { XCTAssertEqual(store.textSelection?.quote, "Two.") }
        }
    }

    @MainActor
    func testCompletedUnscopedAnswerIsClearedWhenPlacementVisibilityOrSelectionChanges() async throws {
        for invalidation in ["placement", "visibility", "selection"] {
            let rig = HamptonStoreRig(), store = makeStore(rig)
            defer { store.disconnectAssistant(); rig.drain() }
            try await seed(store)
            let ticket = store.contextTicket(), records = store.hamptonSnapshot.records
            XCTAssertNil(store.replySourceSelection)
            XCTAssertNotNil(store.hamptonSnapshot.proposal)
            XCTAssertEqual(store.compareResults[.qwen]?.state, .complete)
            XCTAssertFalse(store.isWorking)
            switch invalidation {
            case "placement": store.placed(at: CGPoint(x: -375, y: 512))
            case "visibility": store.hideCompanion()
            default: store.selectText(range: NSRange(location: 0, length: 4), sourceRevision: store.sourceRevision)
            }
            XCTAssertFalse(store.isCurrent(ticket, requireVisible: false), invalidation)
            XCTAssertNil(store.hamptonSnapshot.proposal, invalidation)
            XCTAssertNotEqual(store.reply, "Store fixture answer", invalidation)
            XCTAssertEqual(store.compareResults[.qwen]?.state, .cancelled, invalidation)
            XCTAssertEqual(store.compareResults[.qwen]?.text, "", invalidation)
            XCTAssertEqual(store.hamptonSnapshot.records, records,
                           "Clearing a stale answer does not discard separately admitted local context")
            XCTAssertEqual(store.connection(for: .qwen), .ready,
                           "A completed answer needs invalidation, not an idle connection restart")
        }
    }

    @MainActor
    func testShutdownClearsInspectorAndRejectsLateResultOrSnapshot() async throws {
        let rig = HamptonStoreRig(), store = makeStore(rig)
        defer { store.disconnectAssistant(); rig.drain() }
        try await seed(store)
        let historical = store.hamptonSnapshot
        let callback = try XCTUnwrap(rig.assistant.onSnapshot)
        let pending = try await suspendNextTurn(store, rig: rig)
        await store.shutdownAssistant()
        XCTAssertTrue(store.isShuttingDown)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.connectionState, .disconnected)
        XCTAssertTrue(store.hamptonSnapshot.records.isEmpty)
        XCTAssertTrue(store.hamptonSnapshot.receipts.isEmpty)
        XCTAssertNil(store.hamptonSnapshot.proposal)
        XCTAssertEqual(rig.reasoner.shutdownCount, 1)
        XCTAssertEqual(rig.selector.shutdownCount, 1)
        let cleared = store.hamptonSnapshot, reply = store.reply, status = store.status
        callback(historical)
        rig.reasoner.resolve(pending)
        try await waitUntil("A late shutdown result should drain") { rig.reasoner.finished.contains(pending) }
        await Task.yield()
        XCTAssertEqual(store.hamptonSnapshot, cleared)
        XCTAssertEqual(store.reply, reply)
        XCTAssertEqual(store.status, status)
    }

    @MainActor
    func testDualRoutesPreserveLocalContextWithoutIncludingItInCodexInput() async throws {
        let rig = HamptonStoreRig(), factory = HamptonStoreFactory()
        let store = makeStore(rig, factory: factory)
        defer { store.disconnectAssistant(provider: .qwen); store.disconnectAssistant(provider: .codex); rig.drain(); factory.drain() }
        try await seed(store)
        let remembered = store.hamptonSnapshot.records
        store.setAssistantRoute(.codex)
        XCTAssertEqual(store.hamptonSnapshot.records, remembered)
        XCTAssertEqual(store.connection(for: .qwen), .ready)
        try await connect(store)
        let codex = try XCTUnwrap(factory.codexClients.first)
        store.setAssistantRoute(.compare)
        XCTAssertEqual(store.hamptonSnapshot.records, remembered)
        XCTAssertEqual(store.connection(for: .qwen), .ready)
        XCTAssertEqual(store.connection(for: .codex), .ready)
        store.prompt = "A new current question."
        store.submit()
        try await waitUntil("Both independent answers should complete") { !store.isWorking }
        let request = try XCTUnwrap(codex.requests.first)
        XCTAssertEqual(request.prompt, "A new current question.")
        XCTAssertEqual(request.sourceText, "One. Two.")
        XCTAssertFalse(request.input.contains("Keep the explanation brief."))
        XCTAssertFalse(request.input.contains("Store fixture answer"))
        XCTAssertEqual(store.compareResults[.qwen]?.state, .complete)
        XCTAssertEqual(store.compareResults[.codex]?.state, .complete)
        XCTAssertEqual(store.hamptonSnapshot.records.count, 2)
        XCTAssertEqual(store.compareResults[.qwen]?.receipt?.modelIdentity, "store-fixture @ fixture-only")
        XCTAssertNil(store.compareResults[.codex]?.receipt?.modelIdentity)
    }

    @MainActor
    func testCommittedLocalContextSurvivesALaterCodexFailure() async throws {
        let rig = HamptonStoreRig(), factory = HamptonStoreFactory()
        let store = makeStore(rig, factory: factory)
        defer { store.disconnectAssistant(); rig.drain(); factory.drain() }
        try await seed(store)
        store.setAssistantRoute(.compare)
        try await connect(store)
        let codex = try XCTUnwrap(factory.codexClients.first)
        codex.hold = true
        store.prompt = "Retain this current question locally."
        store.submit()
        try await waitUntil("Local admission should complete while Codex is pending") {
            store.compareResults[.qwen]?.state == .complete && codex.isPending
        }
        let admitted = store.hamptonSnapshot
        XCTAssertEqual(admitted.records.count, 2)
        codex.resolve(.failure(AssistantFailure.turnFailed))
        try await waitUntil("Codex failure should finish only its lane") { !store.isWorking }
        XCTAssertEqual(store.hamptonSnapshot, admitted)
        XCTAssertEqual(store.compareResults[.qwen]?.state, .complete)
        XCTAssertEqual(store.compareResults[.qwen]?.text, "Store fixture answer")
        XCTAssertEqual(store.compareResults[.codex]?.state, .failed)
        XCTAssertEqual(store.connection(for: .qwen), .ready)
    }

    @MainActor
    func testClearingCompletedLocalContextLeavesPendingCodexAndItsSourceTicketCurrent() async throws {
        let rig = HamptonStoreRig(), factory = HamptonStoreFactory()
        let store = makeStore(rig, factory: factory)
        defer { store.disconnectAssistant(); rig.drain(); factory.drain() }
        try await seed(store)
        store.setAssistantRoute(.compare)
        try await connect(store)
        let codex = try XCTUnwrap(factory.codexClients.first)
        codex.hold = true
        store.prompt = "Answer from the current shared copy."
        store.submit()
        let ticket = store.contextTicket()
        try await waitUntil("Local context must first be admitted") {
            store.compareResults[.qwen]?.state == .complete && codex.isPending
        }
        store.clearSessionContext()
        XCTAssertTrue(store.hamptonSnapshot.records.isEmpty)
        XCTAssertNil(store.hamptonSnapshot.proposal)
        XCTAssertEqual(store.compareResults[.qwen]?.state, .cancelled)
        XCTAssertEqual(store.compareResults[.codex]?.state, .pending)
        XCTAssertTrue(store.isCurrent(ticket, requireVisible: false))
        XCTAssertTrue(store.isWorking)
        codex.resolve(.success(()))
        try await waitUntil("Codex should complete after local-only revocation") { !store.isWorking }
        XCTAssertEqual(store.compareResults[.codex]?.state, .complete)
        XCTAssertEqual(store.compareResults[.codex]?.text, "Codex fixture answer")
        XCTAssertTrue(store.hamptonSnapshot.records.isEmpty)
    }

    private enum Reset { case clear, disable, share, stopSharing }
    private enum Replacement { case provider, reasoningModel, contextModel }

    @MainActor
    private func checkReset(_ reset: Reset) async throws {
        let rig = HamptonStoreRig(), store = makeStore(rig)
        defer { store.disconnectAssistant(); rig.drain() }
        try await seed(store)
        XCTAssertEqual(store.hamptonSnapshot.records.count, 1)
        let pending = try await suspendNextTurn(store, rig: rig)
        let ticket = store.contextTicket(), sourceRevision = store.sourceRevision
        let attempted = rig.assistant.inFlightInvocations
        switch reset {
        case .clear: store.clearSessionContext()
        case .disable: store.setSessionContextEnabled(false)
        case .share: store.share(text: "A replacement source.", name: "new.txt")
        case .stopSharing: store.stopSharing()
        }
        XCTAssertFalse(store.isWorking)
        XCTAssertFalse(store.isCurrent(ticket, requireVisible: false))
        XCTAssertEqual(attempted?.last, .reasoning, "A cancelled in-flight call still consumed an invocation")
        if reset == .clear || reset == .disable {
            XCTAssertEqual(store.compareResults[.qwen]?.receipt?.localInvocations, attempted)
            XCTAssertNotNil(store.compareResults[.qwen]?.receipt?.elapsedMilliseconds)
        } else {
            XCTAssertNil(store.compareResults[.qwen], "Replacing or revoking the source removes its old result and receipt")
        }
        XCTAssertEqual(store.connectionState, .disconnected)
        XCTAssertTrue(store.hamptonSnapshot.records.isEmpty)
        XCTAssertTrue(store.hamptonSnapshot.receipts.isEmpty)
        XCTAssertNil(store.hamptonSnapshot.proposal)
        XCTAssertEqual(store.hamptonSnapshot.turn, 0)
        XCTAssertEqual(store.sessionContextEnabled, reset != .disable)
        XCTAssertEqual(store.prompt, "A follow-up still in progress.")
        switch reset {
        case .clear, .disable:
            XCTAssertEqual(store.sharedText, "One. Two.")
            XCTAssertEqual(store.sourceRevision, sourceRevision)
        case .share:
            XCTAssertEqual(store.sharedText, "A replacement source.")
            XCTAssertEqual(store.sourceName, "new.txt")
            XCTAssertEqual(store.sourceRevision, sourceRevision + 1)
        case .stopSharing:
            XCTAssertEqual(store.sharedText, "")
            XCTAssertNil(store.sourceName)
            XCTAssertEqual(store.sourceRevision, sourceRevision + 1)
        }
        let snapshot = store.hamptonSnapshot, reply = store.reply, status = store.status
        rig.reasoner.resolve(pending)
        try await waitUntil("The cleared turn's final role should drain") { rig.reasoner.finished.contains(pending) }
        await Task.yield()
        XCTAssertEqual(store.hamptonSnapshot, snapshot)
        XCTAssertEqual(store.reply, reply)
        XCTAssertEqual(store.status, status)
        XCTAssertEqual(rig.reasoner.requests.count, 2)
    }

    @MainActor
    private func seed(_ store: CompanionStore) async throws {
        store.share(text: "One. Two.", name: "notes.txt")
        store.prompt = "Keep the explanation brief."
        store.setSessionContextEnabled(true)
        try await connect(store)
        store.submit()
        try await waitUntil("The first context turn should complete") { !store.isWorking }
        XCTAssertEqual(store.connectionState, .ready)
        XCTAssertEqual(store.hamptonSnapshot.records.map(\.text), ["Keep the explanation brief."])
        XCTAssertEqual(store.hamptonSnapshot.turn, 1)
    }

    @MainActor
    private func suspendNextTurn(_ store: CompanionStore, rig: HamptonStoreRig) async throws -> Int {
        rig.reasoner.hold = true
        store.prompt = "A follow-up still in progress."
        let index = rig.reasoner.requests.count
        store.submit()
        try await waitUntil("The next final reasoning phase should be held") { rig.reasoner.pendingIndices.contains(index) }
        XCTAssertTrue(store.isWorking)
        XCTAssertEqual(store.hamptonSnapshot.turn, 1)
        XCTAssertEqual(store.hamptonSnapshot.records.map(\.text), ["Keep the explanation brief."])
        XCTAssertNil(store.hamptonSnapshot.proposal)
        return index
    }

    @MainActor
    private var preferences: URL { URL(fileURLWithPath: "/dev/null/unused") }

    @MainActor
    private func makeStore(_ rig: HamptonStoreRig, factory: HamptonStoreFactory? = nil) -> CompanionStore {
        CompanionStore(preferenceURL: preferences, assistant: rig.assistant,
            assistantFactory: { provider, model in
                if let factory { return factory.make(provider, model) }
                XCTFail("This test should not replace its injected client")
                return HamptonStoreCodexClient()
            }, tokenSteward: TokenStewardStore())
    }

    @MainActor
    private func connect(_ store: CompanionStore) async throws {
        store.connectAssistant()
        try await waitUntil("Explicit connection should become ready") { store.connectionState == .ready }
    }

    @MainActor
    private func waitUntil(_ message: String, file: StaticString = #filePath, line: UInt = #line,
                           _ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail(message, file: file, line: line)
        throw HamptonStoreTestFailure.waitTimedOut
    }
}

private enum HamptonStoreTestFailure: Error { case waitTimedOut }

@MainActor
private final class HamptonStoreRig {
    let reasoner = HamptonStoreRoleClient()
    let selector = HamptonStoreRoleClient()
    let assistant: HamptonReasonsAssistant

    init(model: String = QwenAssistant.defaultModel,
         contextModel: String = HamptonReasonsAssistant.defaultContextModel) {
        assistant = HamptonReasonsAssistant(model: model, contextModel: contextModel,
            reasoner: reasoner, contextSelector: selector)
    }

    func drain() { reasoner.drain(); selector.drain() }
}

@MainActor
private final class HamptonStoreFactory {
    var nextContextModel = HamptonReasonsAssistant.defaultContextModel
    private(set) var providers: [AssistantProvider] = []
    private(set) var rigs: [HamptonStoreRig] = []
    private(set) var codexClients: [HamptonStoreCodexClient] = []

    func make(_ provider: AssistantProvider, _ model: String) -> any AssistantClient {
        providers.append(provider)
        if provider == .codex {
            let client = HamptonStoreCodexClient()
            codexClients.append(client)
            return client
        }
        let rig = HamptonStoreRig(model: model, contextModel: nextContextModel)
        rigs.append(rig)
        return rig.assistant
    }

    func drain() { rigs.forEach { $0.drain() }; codexClients.forEach { $0.drain() } }
}

@MainActor
private final class HamptonStoreCodexClient: AssistantClient {
    private(set) var replyCount = 0
    private(set) var requests: [AssistantRequest] = []
    var hold = false
    private var pending: CheckedContinuation<Void, any Error>?
    var isPending: Bool { pending != nil }
    func connect() async throws {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        replyCount += 1
        requests.append(request)
        if hold { try await withCheckedThrowingContinuation { pending = $0 } }
        onEvent(.text("Codex fixture answer"))
    }
    func disconnect() {}
    func resolve(_ result: Result<Void, any Error>) {
        let continuation = pending; pending = nil
        continuation?.resume(with: result)
    }
    func drain() { resolve(.failure(AssistantFailure.stopped)) }
}

/// All requests remain in-process. Disconnect deliberately leaves held results
/// pending so that the Store and wrapper must reject an obsolete valid response.
@MainActor
private final class HamptonStoreRoleClient: LocalRoleClient {
    var hold = false
    private(set) var requests: [LocalRoleRequest] = []
    private(set) var finished = Set<Int>()
    private(set) var connectCount = 0
    private(set) var disconnectCount = 0
    private(set) var shutdownCount = 0
    private var pending: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var draining = false
    var pendingIndices: Set<Int> { Set(pending.keys) }

    func connect() async throws { connectCount += 1 }
    func disconnect() { disconnectCount += 1 }
    func shutdown() async { shutdownCount += 1; disconnect() }

    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
        let index = requests.count
        requests.append(request)
        defer { finished.insert(index) }
        guard !draining else { throw QwenFailure.stopped }
        if hold { try await withCheckedThrowingContinuation { pending[index] = $0 } }
        var payload: [String: JSONValue] = ["requestID": .string(request.id)]
        switch request.role {
        case .memorySelection:
            payload["schema"] = .string("archi-session-selection/v1")
            let ids = request.input["candidates"]?.array?.prefix(1).compactMap { $0["id"]?.string } ?? []
            payload["candidateIDs"] = .array(ids.map(JSONValue.string))
        case .memoryReminder:
            payload["schema"] = .string("archi-session-reminder/v1")
            payload["decision"] = .string("NONE")
            payload["memoryIDs"] = .array([])
        case .reasoning:
            payload["schema"] = .string("archi-reason-proposal/v1")
            payload["kind"] = .string("ANSWER")
            payload["answer"] = .string("Store fixture answer")
            payload["uncertainty"] = .string("")
            payload["sourceIDs"] = .array([])
            payload["memoryIDs"] = .array([])
        }
        let text = String(decoding: try JSONEncoder().encode(JSONValue.object(payload)), as: UTF8.self)
        return LocalRoleResult(requestID: request.id, role: request.role, text: text,
            model: QwenModelMetadata(name: "store-fixture", family: "qwen", parameterSize: "fixture",
                quantization: "fixture", digest: "fixture-only"), elapsedMilliseconds: 0)
    }

    func resolve(_ index: Int) {
        guard let continuation = pending.removeValue(forKey: index) else { XCTFail("Role was not pending"); return }
        continuation.resume()
    }

    func drain() {
        draining = true
        let continuations = Array(pending.values)
        pending.removeAll()
        for continuation in continuations { continuation.resume(throwing: QwenFailure.stopped) }
    }
}
