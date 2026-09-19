import XCTest
@testable import ARCHiDesktop

final class AssistantProviderStoreTests: XCTestCase {
    @MainActor
    func testDefaultAndProviderSelectionNeverConnectOrSendAndPreserveSharedDraft() async throws {
        let factory = ProviderClientFactory()
        let store = CompanionStore(preferenceURL: unusedPreferences,
            assistantFactory: { provider, model in factory.make(provider, model) }, tokenSteward: TokenStewardStore())
        defer { store.disconnectAssistant(); factory.drain() }
        XCTAssertEqual(store.assistantProvider, .qwen)
        XCTAssertEqual(factory.calls.count, 1)
        XCTAssertEqual(factory.calls[0].provider, .qwen)
        XCTAssertEqual(factory.calls[0].model, QwenAssistant.defaultModel)
        let old = factory.clients[0]
        store.share(text: "First. Second.", name: "local.txt")
        store.prompt = "Keep this unsent draft."
        store.selectText(range: NSRange(location: 0, length: 6), sourceRevision: store.sourceRevision)
        let oldTicket = store.contextTicket(), sourceRevision = store.sourceRevision
        let selection = store.textSelection

        store.selectAssistantProvider(.codex)
        XCTAssertEqual(factory.calls.count, 2)
        XCTAssertEqual(factory.calls[1].provider, .codex)
        XCTAssertEqual(store.assistantProvider, .codex)
        XCTAssertEqual(store.connectionState, .disconnected)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.textSelection, selection, "An idle route change preserves the current document selection")
        XCTAssertNil(store.replySourceSelection)
        XCTAssertFalse(store.isCurrent(oldTicket, requireVisible: false))
        XCTAssertEqual(store.sharedText, "First. Second.")
        XCTAssertEqual(store.sourceName, "local.txt")
        XCTAssertEqual(store.sourceRevision, sourceRevision)
        XCTAssertEqual(store.prompt, "Keep this unsent draft.")
        XCTAssertTrue(factory.clients.allSatisfy { $0.connectCount == 0 && $0.replies.isEmpty })
        XCTAssertEqual(old.disconnectCount, 0)
        XCTAssertEqual(old.shutdownCount, 0, "Changing routes retains the idle client")
        XCTAssertEqual(factory.clients[1].shutdownCount, 0)
        let ticket = store.contextTicket(), disconnects = factory.clients[1].disconnectCount
        store.selectAssistantProvider(.codex)
        XCTAssertEqual(factory.calls.count, 2, "Selecting the existing provider must not create another client")
        XCTAssertEqual(factory.clients[1].disconnectCount, disconnects)
        XCTAssertTrue(store.isCurrent(ticket, requireVisible: false))
        store.selectAssistantProvider(.qwen)
        XCTAssertEqual(factory.calls.count, 2, "Returning to a route reuses its original client")
        XCTAssertEqual(store.textSelection, selection)
        XCTAssertTrue(factory.clients.allSatisfy { $0.connectCount == 0 && $0.replies.isEmpty && $0.shutdownCount == 0 })
    }

    @MainActor
    func testLateConnectionSuccessFromUnselectedProviderCannotOverwriteSelectedReadyState() async throws {
        try await checkLateConnection(result: .success(()))
    }

    @MainActor
    func testLateConnectionFailureFromUnselectedProviderCannotOverwriteSelectedReadyState() async throws {
        try await checkLateConnection(result: .failure(AssistantFailure.signedOut))
    }

    @MainActor
    func testSwitchDuringStreamRejectsOldOutputAndFailureAndRetainsBothClients() async throws {
        let old = ProviderControlledClient(), factory = ProviderClientFactory()
        let store = makeStore(old, factory: factory)
        defer { store.disconnectAssistant(); old.drain(); factory.drain() }
        try await connect(store, old)
        store.share(text: "First. Second.", name: "shared.txt")
        store.prompt = "Explain this passage."
        store.selectText(range: NSRange(location: 0, length: 6), sourceRevision: store.sourceRevision)
        store.submit()
        try await waitUntil("The original provider should receive the explicit request") { old.replies.count == 1 }
        old.emit(0, text: "An old partial answer")
        let oldTicket = store.contextTicket(), sourceRevision = store.sourceRevision
        let selection = store.textSelection

        store.selectAssistantProvider(.codex)
        let current = try XCTUnwrap(factory.clients.first)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.connectionState, .disconnected)
        XCTAssertFalse(store.isCurrent(oldTicket, requireVisible: false))
        XCTAssertEqual(store.textSelection, selection)
        XCTAssertNil(store.replySourceSelection)
        XCTAssertNotEqual(store.reply, "An old partial answer")
        XCTAssertEqual(store.sharedText, "First. Second.")
        XCTAssertEqual(store.prompt, "Explain this passage.")
        XCTAssertEqual(store.sourceRevision, sourceRevision)
        XCTAssertTrue(current.replies.isEmpty)
        XCTAssertEqual(current.connectCount, 0)
        XCTAssertEqual(store.connection(for: .qwen), .disconnected)
        XCTAssertGreaterThan(old.disconnectCount, 0, "The active old reply must be disconnected")
        XCTAssertEqual(old.shutdownCount, 0, "Its client remains owned for the next local request")

        try await connect(store, current)
        store.selectText(range: NSRange(location: 7, length: 7), sourceRevision: store.sourceRevision)
        store.submit()
        try await waitUntil("Only another Send may start the replacement request") { current.replies.count == 1 }
        XCTAssertEqual(current.replies[0].request.sourceText, "First. Second.")
        XCTAssertEqual(current.replies[0].request.selection?.quote, "Second.")
        current.emit(0, text: "The current provider answer")
        let currentTicket = store.contextTicket(), reply = store.reply, status = store.status
        let message = store.connectionMessage, disconnects = current.disconnectCount
        old.emit(0, text: "Late text from the previous provider")
        old.resolveReply(0, result: .failure(AssistantFailure.turnFailed))
        try await waitUntil("The old reply continuation should drain") { old.finishedReplies.contains(0) }
        await Task.yield()

        XCTAssertTrue(store.isWorking)
        XCTAssertTrue(store.isCurrent(currentTicket, requireVisible: false))
        XCTAssertEqual(store.reply, reply)
        XCTAssertEqual(store.status, status)
        XCTAssertEqual(store.connectionMessage, message)
        XCTAssertEqual(store.connectionState, .ready)
        XCTAssertEqual(current.disconnectCount, disconnects)
        XCTAssertEqual(old.shutdownCount, 0)
        XCTAssertEqual(current.shutdownCount, 0)
        current.resolveReply(0)
        try await waitUntil("The replacement reply should still finish") { !store.isWorking }
        XCTAssertEqual(store.reply, "The current provider answer")
        store.selectAssistantProvider(.qwen)
        XCTAssertEqual(factory.calls.count, 1, "Returning to local must reuse the cancelled local client")
        XCTAssertEqual(store.connectionState, .disconnected)
        XCTAssertEqual(store.connection(for: .codex), .ready)
        XCTAssertEqual(current.disconnectCount, disconnects)
        try await connect(store, old)
        XCTAssertEqual(old.connectCount, 2)
        XCTAssertEqual(old.replies.count, 1, "Reconnecting must not resend the cancelled request")
        XCTAssertEqual(current.shutdownCount, 0)
    }

    @MainActor
    func testQwenModelNoOpsDoNotReplaceClientAndSupportedChangeRequiresFreshConnect() async throws {
        let old = ProviderControlledClient(), factory = ProviderClientFactory()
        let store = makeStore(old, factory: factory)
        defer { store.disconnectAssistant(); old.drain(); factory.drain() }
        try await connect(store, old)
        store.share(text: "Retain this copy.", name: "source.txt")
        store.prompt = "Retain this question."
        store.selectText(range: NSRange(location: 0, length: 6), sourceRevision: store.sourceRevision)
        let ticket = store.contextTicket(), selection = store.textSelection
        let disconnects = old.disconnectCount, message = store.connectionMessage
        store.selectQwenModel("unsupported-provider-test-model")
        store.selectQwenModel(QwenAssistant.defaultModel)
        store.selectAssistantProvider(.qwen)
        XCTAssertTrue(factory.calls.isEmpty)
        XCTAssertEqual(old.disconnectCount, disconnects)
        XCTAssertEqual(store.connectionState, .ready)
        XCTAssertEqual(store.connectionMessage, message)
        XCTAssertEqual(store.textSelection, selection)
        XCTAssertTrue(store.isCurrent(ticket, requireVisible: false))
        XCTAssertEqual(store.qwenModel, QwenAssistant.defaultModel)

        let model = try XCTUnwrap(QwenAssistant.supportedModels.first { $0 != QwenAssistant.defaultModel })
        store.selectQwenModel(model)
        XCTAssertEqual(factory.calls.count, 1)
        XCTAssertEqual(factory.calls[0].provider, .qwen)
        XCTAssertEqual(factory.calls[0].model, model)
        XCTAssertEqual(store.qwenModel, model)
        XCTAssertEqual(store.connectionState, .disconnected)
        XCTAssertNil(store.textSelection)
        XCTAssertEqual(store.sharedText, "Retain this copy.")
        XCTAssertEqual(store.prompt, "Retain this question.")
        XCTAssertEqual(factory.clients[0].connectCount, 0)
        XCTAssertTrue(factory.clients[0].replies.isEmpty)
        store.selectQwenModel(model)
        XCTAssertEqual(factory.calls.count, 1)
        try await waitUntil("The superseded model client should retire") { old.shutdownCount == 1 }
    }

    @MainActor
    func testQwenModelChoiceWhileCodexIsActiveDoesNotDisturbCodexAndIsUsedWhenSelected() async throws {
        let old = ProviderControlledClient(), factory = ProviderClientFactory()
        let store = makeStore(old, provider: .codex, factory: factory)
        defer { store.disconnectAssistant(); old.drain(); factory.drain() }
        try await connect(store, old)
        store.share(text: "First. Second.", name: "source.txt")
        store.prompt = "An unsent question."
        store.selectText(range: NSRange(location: 0, length: 6), sourceRevision: store.sourceRevision)
        let ticket = store.contextTicket(), selection = store.textSelection, disconnects = old.disconnectCount
        let model = try XCTUnwrap(QwenAssistant.supportedModels.first { $0 != QwenAssistant.defaultModel })
        store.selectQwenModel(model)
        XCTAssertEqual(store.assistantProvider, .codex)
        XCTAssertEqual(store.connectionState, .ready)
        XCTAssertEqual(store.qwenModel, model)
        XCTAssertTrue(factory.calls.isEmpty)
        XCTAssertEqual(old.disconnectCount, disconnects)
        XCTAssertEqual(old.shutdownCount, 0)
        XCTAssertEqual(store.textSelection, selection)
        XCTAssertTrue(store.isCurrent(ticket, requireVisible: false))
        XCTAssertTrue(old.replies.isEmpty)

        store.selectAssistantProvider(.qwen)
        XCTAssertEqual(factory.calls.count, 1)
        XCTAssertEqual(factory.calls[0].provider, .qwen)
        XCTAssertEqual(factory.calls[0].model, model)
        XCTAssertEqual(store.connectionState, .disconnected)
        XCTAssertEqual(store.sharedText, "First. Second.")
        XCTAssertEqual(store.prompt, "An unsent question.")
        XCTAssertTrue(factory.clients[0].replies.isEmpty)
        XCTAssertEqual(factory.clients[0].connectCount, 0)
        XCTAssertEqual(store.connection(for: .codex), .ready)
        XCTAssertEqual(old.disconnectCount, disconnects)
        XCTAssertEqual(old.shutdownCount, 0)
        XCTAssertEqual(store.textSelection, selection)
        store.selectAssistantProvider(.codex)
        XCTAssertEqual(store.connectionState, .ready)
        XCTAssertEqual(factory.calls.count, 1)
        XCTAssertEqual(old.connectCount, 1)
        XCTAssertEqual(old.disconnectCount, disconnects)
    }

    @MainActor
    func testFinalShutdownWaitsForCurrentAndRetiredClientsWithoutCrossShutdown() async throws {
        let old = ProviderControlledClient(), factory = ProviderClientFactory()
        let store = makeStore(old, factory: factory)
        defer { store.disconnectAssistant(); old.drain(); factory.drain() }
        store.selectAssistantProvider(.codex)
        let current = try XCTUnwrap(factory.clients.first)
        XCTAssertEqual(old.shutdownCount, 0, "The local client remains owned across the route change")
        let model = try XCTUnwrap(QwenAssistant.supportedModels.first { $0 != store.qwenModel })
        store.selectQwenModel(model)
        let replacement = try XCTUnwrap(factory.clients.last)
        XCTAssertFalse(current === replacement)
        try await waitUntil("The retired client should be waiting for its own shutdown") { old.shutdownCount == 1 }
        var finished = false
        let shutdown = Task { @MainActor in
            await store.shutdownAssistant()
            finished = true
        }
        try await waitUntil("Final shutdown should start both current client cleanups") {
            current.shutdownCount == 1 && replacement.shutdownCount == 1
        }
        XCTAssertEqual(old.shutdownCount, 1)
        XCTAssertFalse(finished)
        current.resolveShutdown(0)
        try await waitUntil("Current shutdown should complete independently") { current.finishedShutdowns.contains(0) }
        await Task.yield()
        XCTAssertFalse(finished, "The other current client still belongs to final cleanup")
        XCTAssertFalse(replacement.finishedShutdowns.contains(0))
        replacement.resolveShutdown(0)
        try await waitUntil("The replacement local client should finish independently") { replacement.finishedShutdowns.contains(0) }
        await Task.yield()
        XCTAssertFalse(finished, "A pending retired client still belongs to final cleanup")
        old.resolveShutdown(0)
        try await waitUntil("All owned cleanup should finish") { finished }
        await shutdown.value
        XCTAssertEqual(old.shutdownCount, 1)
        XCTAssertEqual(current.shutdownCount, 1)
        XCTAssertEqual(replacement.shutdownCount, 1)
        XCTAssertTrue(old.replies.isEmpty)
        XCTAssertTrue(current.replies.isEmpty)
        XCTAssertTrue(replacement.replies.isEmpty)
    }

    @MainActor
    func testShutdownInProgressCannotCreateConnectOrSendThroughAnotherClient() async throws {
        let old = ProviderControlledClient(), factory = ProviderClientFactory()
        let store = makeStore(old, factory: factory)
        defer { store.disconnectAssistant(); old.drain(); factory.drain() }
        try await connect(store, old)
        store.share(text: "Keep this local while quitting.", name: "source.txt")
        store.prompt = "Do not send during shutdown."
        let model = store.qwenModel
        let alternative = try XCTUnwrap(QwenAssistant.supportedModels.first { $0 != model })
        var finished = false
        let shutdown = Task { @MainActor in
            await store.shutdownAssistant()
            finished = true
        }
        try await waitUntil("Shutdown should reach the held client") { old.shutdownCount == 1 }
        XCTAssertTrue(store.isShuttingDown)
        XCTAssertFalse(finished)
        let ticket = store.contextTicket(), status = store.status, message = store.connectionMessage
        store.selectAssistantProvider(.codex)
        store.setAssistantRoute(.compare)
        store.selectQwenModel(alternative)
        store.connectAssistant()
        store.connectAssistant(provider: .codex)
        store.submit()
        XCTAssertTrue(factory.calls.isEmpty)
        XCTAssertEqual(store.assistantProvider, .qwen)
        XCTAssertEqual(store.qwenModel, model)
        XCTAssertEqual(old.connectCount, 1)
        XCTAssertTrue(old.replies.isEmpty)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.connectionState, .disconnected)
        XCTAssertTrue(store.isCurrent(ticket, requireVisible: false))
        XCTAssertEqual(store.status, status)
        XCTAssertEqual(store.connectionMessage, message)
        XCTAssertEqual(store.sharedText, "Keep this local while quitting.")
        XCTAssertEqual(store.prompt, "Do not send during shutdown.")
        old.resolveShutdown(0)
        try await waitUntil("The original shutdown should finish") { finished }
        await shutdown.value
        XCTAssertEqual(old.shutdownCount, 1)
        XCTAssertTrue(factory.clients.isEmpty)
    }

    @MainActor
    private func checkLateConnection(result: Result<Void, any Error>) async throws {
        let old = ProviderControlledClient(), factory = ProviderClientFactory()
        let store = makeStore(old, factory: factory)
        defer { store.disconnectAssistant(); old.drain(); factory.drain() }
        store.prompt = "Do not send this automatically."
        store.connectAssistant()
        try await waitUntil("The old connection should reach its client") { old.connectCount == 1 }
        store.selectAssistantProvider(.codex)
        let current = try XCTUnwrap(factory.clients.first)
        XCTAssertEqual(current.connectCount, 0)
        XCTAssertEqual(store.connection(for: .qwen), .connecting)
        XCTAssertEqual(old.disconnectCount, 0, "An unselected pending connection should keep running")
        try await connect(store, current)
        let message = store.connectionMessage, status = store.status, reply = store.reply
        let disconnects = current.disconnectCount
        old.resolveConnection(0, result: result)
        let expectedLocalState: AssistantConnectionState
        switch result {
        case .success: expectedLocalState = .ready
        case .failure: expectedLocalState = .failed
        }
        try await waitUntil("The unselected connection should settle only its own state") {
            old.finishedConnections.contains(0) && store.connection(for: .qwen) == expectedLocalState
        }
        await Task.yield()
        XCTAssertEqual(store.assistantProvider, .codex)
        XCTAssertEqual(store.connectionState, .ready)
        XCTAssertEqual(store.connectionMessage, message)
        XCTAssertEqual(store.status, status)
        XCTAssertEqual(store.reply, reply)
        XCTAssertEqual(store.prompt, "Do not send this automatically.")
        XCTAssertEqual(current.disconnectCount, disconnects)
        XCTAssertEqual(old.disconnectCount, 0)
        XCTAssertEqual(old.shutdownCount, 0)
        XCTAssertEqual(current.shutdownCount, 0)
        XCTAssertTrue(old.replies.isEmpty)
        XCTAssertTrue(current.replies.isEmpty)
        let localMessage = store.message(for: .qwen)
        store.selectAssistantProvider(.qwen)
        XCTAssertEqual(store.connectionState, expectedLocalState)
        XCTAssertEqual(store.connectionMessage, localMessage)
        XCTAssertEqual(store.connection(for: .codex), .ready)
        XCTAssertEqual(factory.calls.count, 1, "The settled local connection must be reused")
        XCTAssertEqual(old.connectCount, 1)
        XCTAssertEqual(current.disconnectCount, disconnects)
    }

    @MainActor
    private var unusedPreferences: URL { URL(fileURLWithPath: "/dev/null/unused") }

    @MainActor
    private func makeStore(_ initial: ProviderControlledClient, provider: AssistantProvider = .qwen,
                           factory: ProviderClientFactory) -> CompanionStore {
        CompanionStore(preferenceURL: unusedPreferences, assistant: initial, provider: provider,
            assistantFactory: { provider, model in factory.make(provider, model) }, tokenSteward: TokenStewardStore())
    }

    @MainActor
    private func connect(_ store: CompanionStore, _ client: ProviderControlledClient) async throws {
        let index = client.connectCount
        store.connectAssistant()
        try await waitUntil("The explicit connection should start") { client.connectCount == index + 1 }
        client.resolveConnection(index)
        try await waitUntil("The explicit connection should become ready") { store.connectionState == .ready }
    }

    @MainActor
    private func waitUntil(_ message: String, file: StaticString = #filePath, line: UInt = #line,
                           _ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail(message, file: file, line: line)
        throw ProviderTestFailure.waitTimedOut
    }
}

private enum ProviderTestFailure: Error { case waitTimedOut }

@MainActor
private final class ProviderClientFactory {
    struct Call { let provider: AssistantProvider; let model: String }
    private(set) var calls: [Call] = []
    private(set) var clients: [ProviderControlledClient] = []

    func make(_ provider: AssistantProvider, _ model: String) -> ProviderControlledClient {
        calls.append(Call(provider: provider, model: model))
        let client = ProviderControlledClient()
        clients.append(client)
        return client
    }

    func drain() { clients.forEach { $0.drain() } }
}

/// Disconnect leaves old callbacks available. Shutdown is independently held,
/// then disconnects only this fake when released, exposing cross-client mistakes.
@MainActor
private final class ProviderControlledClient: AssistantClient {
    struct Reply {
        let request: AssistantRequest
        let onEvent: @MainActor (AssistantEvent) -> Void
    }
    private(set) var connectCount = 0
    private(set) var disconnectCount = 0
    private(set) var shutdownCount = 0
    private(set) var replies: [Reply] = []
    private(set) var finishedConnections = Set<Int>()
    private(set) var finishedReplies = Set<Int>()
    private(set) var finishedShutdowns = Set<Int>()
    private var pendingConnections: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var pendingReplies: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var pendingShutdowns: [Int: CheckedContinuation<Void, Never>] = [:]
    private var draining = false

    func connect() async throws {
        let index = connectCount; connectCount += 1
        defer { finishedConnections.insert(index) }
        guard !draining else { throw AssistantFailure.stopped }
        try await withCheckedThrowingContinuation { pendingConnections[index] = $0 }
    }

    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        let index = replies.count
        replies.append(Reply(request: request, onEvent: onEvent))
        defer { finishedReplies.insert(index) }
        guard !draining else { throw AssistantFailure.stopped }
        try await withCheckedThrowingContinuation { pendingReplies[index] = $0 }
    }

    func disconnect() { disconnectCount += 1 }

    func shutdown() async {
        let index = shutdownCount; shutdownCount += 1
        if !draining { await withCheckedContinuation { pendingShutdowns[index] = $0 } }
        disconnect()
        finishedShutdowns.insert(index)
    }

    func emit(_ index: Int, text: String) { replies[index].onEvent(.text(text)) }

    func resolveConnection(_ index: Int, result: Result<Void, any Error> = .success(())) {
        guard let continuation = pendingConnections.removeValue(forKey: index) else { XCTFail("Connection was not pending"); return }
        continuation.resume(with: result)
    }

    func resolveReply(_ index: Int, result: Result<Void, any Error> = .success(())) {
        guard let continuation = pendingReplies.removeValue(forKey: index) else { XCTFail("Reply was not pending"); return }
        continuation.resume(with: result)
    }

    func resolveShutdown(_ index: Int) {
        guard let continuation = pendingShutdowns.removeValue(forKey: index) else { XCTFail("Shutdown was not pending"); return }
        continuation.resume()
    }

    func drain() {
        draining = true
        let connections = Array(pendingConnections.values), work = Array(pendingReplies.values)
        let shutdowns = Array(pendingShutdowns.values)
        pendingConnections.removeAll(); pendingReplies.removeAll(); pendingShutdowns.removeAll()
        for continuation in connections + work { continuation.resume(throwing: AssistantFailure.stopped) }
        for continuation in shutdowns { continuation.resume() }
    }
}
