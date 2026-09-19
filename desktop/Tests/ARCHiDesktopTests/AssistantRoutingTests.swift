import XCTest
@testable import ARCHiDesktop

final class AssistantRoutingTests: XCTestCase {
    @MainActor
    func testRouteChoiceRetainsIdleConnectionsAndLocalSendNeverCallsCodex() async throws {
        let fixture = RoutingFixture()
        let subject = fixture.store
        defer { fixture.drain() }
        XCTAssertEqual(subject.route, .local)
        subject.prompt = "An unsent local question."
        subject.share(text: "Keep this copy local.", name: "notes.txt")

        subject.setAssistantRoute(.codex)
        subject.setAssistantRoute(.compare)
        subject.setAssistantRoute(.local)
        XCTAssertEqual(fixture.factory.calls.map(\.provider), [.codex])
        XCTAssertEqual(fixture.local.connectCount, 0)
        XCTAssertEqual(fixture.cloud.connectCount, 0)
        XCTAssertTrue(fixture.local.replies.isEmpty)
        XCTAssertTrue(fixture.cloud.replies.isEmpty)
        try await connectBoth(fixture)
        let localDisconnects = fixture.local.disconnectCount
        let cloudDisconnects = fixture.cloud.disconnectCount
        subject.setAssistantRoute(.compare)
        subject.setAssistantRoute(.codex)
        subject.setAssistantRoute(.local)
        XCTAssertEqual(subject.connection(for: .qwen), .ready)
        XCTAssertEqual(subject.connection(for: .codex), .ready)
        XCTAssertEqual(fixture.local.disconnectCount, localDisconnects)
        XCTAssertEqual(fixture.cloud.disconnectCount, cloudDisconnects)
        XCTAssertEqual(fixture.local.shutdownCount, 0)
        XCTAssertEqual(fixture.cloud.shutdownCount, 0)
        XCTAssertEqual(subject.prompt, "An unsent local question.")
        XCTAssertEqual(subject.sharedText, "Keep this copy local.")

        subject.submit()
        try await waitUntil("Only the local lane should receive this Send") { fixture.local.replies.count == 1 }
        XCTAssertTrue(fixture.cloud.replies.isEmpty)
        fixture.local.emit(0, text: "The local answer.")
        fixture.local.resolveReply(0)
        try await waitUntil("The local answer should complete") { !subject.isWorking }
        XCTAssertEqual(subject.reply, "The local answer.")
        XCTAssertTrue(fixture.cloud.replies.isEmpty)
        XCTAssertEqual(subject.connection(for: .codex), .ready)
        XCTAssertEqual(fixture.factory.calls.count, 1, "Route changes must reuse owned clients")
    }

    @MainActor
    func testCompareSendsNeitherRequestUntilBothConnectionsAreReady() async throws {
        for readyProvider in [AssistantProvider.qwen, .codex] {
            let fixture = RoutingFixture()
            let subject = fixture.store
            defer { fixture.drain() }
            try await connect(subject, provider: readyProvider, client: fixture.client(readyProvider))
            subject.setAssistantRoute(.compare)
            subject.prompt = "Compare only when both destinations are ready."
            subject.submit()
            await Task.yield()
            XCTAssertFalse(subject.isWorking)
            XCTAssertTrue(fixture.local.replies.isEmpty)
            XCTAssertTrue(fixture.cloud.replies.isEmpty)
            XCTAssertEqual(subject.connection(for: readyProvider), .ready)
            XCTAssertEqual(fixture.client(readyProvider).connectCount, 1)
            XCTAssertEqual(fixture.client(readyProvider == .qwen ? .codex : .qwen).connectCount, 0)
        }
    }

    @MainActor
    func testCompareCapturesOneExactCurrentRequestBeforeEitherLaneRuns() async throws {
        let fixture = RoutingFixture()
        let store = fixture.store
        defer { fixture.drain() }
        try await connectBoth(fixture)
        store.setAssistantRoute(.compare)
        store.placed(at: CGPoint(x: -180, y: 470))
        store.share(text: "First.\nCafé is the selected passage.", name: "current.txt")
        store.selectText(range: NSRange(location: 7, length: 4), sourceRevision: store.sourceRevision)
        store.preferences.tone = "Warm"
        store.preferences.replyLength = 0.8
        store.evolution.confirmRole(.muse)
        store.evolution.confirmHelpStyle(.stepByStep)
        store.prompt = "Explain this exact passage."
        let sourceRevision = store.sourceRevision, placementRevision = store.placementRevision
        let selection = store.textSelection
        store.submit()
        // Draft edits must not change either already-submitted request.
        store.prompt = "A later, unsent draft."
        store.preferences.tone = "Direct"
        store.evolution.confirmRole(.beacon)
        store.evolution.revoke(.helpStyle)
        try await waitForReplies(fixture)
        let local = fixture.local.replies[0].request
        let cloud = fixture.cloud.replies[0].request
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(JSONValue.self, from: Data(local.input.utf8)),
                       try decoder.decode(JSONValue.self, from: Data(cloud.input.utf8)))
        for request in [local, cloud] {
            XCTAssertEqual(request.prompt, "Explain this exact passage.")
            XCTAssertEqual(request.sourceName, "current.txt")
            XCTAssertEqual(request.sourceText, "First.\nCafé is the selected passage.")
            XCTAssertEqual(request.sourceRevision, sourceRevision)
            XCTAssertEqual(request.placementRevision, placementRevision)
            XCTAssertEqual(request.selection, selection)
            XCTAssertEqual(request.tone, "Warm")
            XCTAssertEqual(request.replyLength, 0.8)
            XCTAssertEqual(request.settings.role, .muse)
            XCTAssertEqual(request.settings.helpStyle, .stepByStep)
            XCTAssertTrue(request.hasValidSelection)
        }
        fixture.local.emit(0, text: "Local answer.")
        fixture.cloud.emit(0, text: "Codex answer.")
        fixture.local.resolveReply(0)
        fixture.cloud.resolveReply(0)
        try await waitUntil("Both captured requests should finish") { !store.isWorking }
        for provider in [AssistantProvider.qwen, .codex] {
            let receipt = try XCTUnwrap(store.compareResults[provider]?.receipt)
            XCTAssertEqual(receipt.settings, local.settings)
            XCTAssertEqual(receipt.inputContract, "native-assistant-input/v4")
            XCTAssertTrue(receipt.requestStarted)
            XCTAssertNotNil(receipt.elapsedMilliseconds)
        }
        XCTAssertEqual(store.nextReplySettings.role, .beacon)
        XCTAssertNil(store.nextReplySettings.helpStyle)
        store.submit()
        try await waitUntil("Next Send captures updated preferences") { fixture.local.replies.count == 2 && fixture.cloud.replies.count == 2 }
        XCTAssertEqual(fixture.local.replies[1].request.settings, store.nextReplySettings)
        XCTAssertEqual(fixture.cloud.replies[1].request.settings, store.nextReplySettings)
    }

    @MainActor
    func testInterleavedStreamsAndCompletionStayInTheirOwnLanes() async throws {
        let fixture = RoutingFixture()
        let store = fixture.store
        defer { fixture.drain() }
        try await beginCompare(fixture)
        XCTAssertEqual(store.assistantActivity, .working)
        fixture.local.emit(0, text: "Local partial")
        XCTAssertEqual(store.assistantActivity, .responding)
        fixture.cloud.emit(0, text: "Codex partial")
        fixture.local.emit(0, text: "Local complete answer")
        XCTAssertEqual(store.compareResults[.qwen]?.text, "Local complete answer")
        XCTAssertEqual(store.compareResults[.codex]?.text, "Codex partial")
        XCTAssertEqual(store.compareResults[.qwen]?.state, .pending)
        XCTAssertEqual(store.compareResults[.codex]?.state, .pending)
        fixture.local.resolveReply(0)
        try await waitUntil("The local lane should independently complete") { store.compareResults[.qwen]?.state == .complete }
        let localStatus = store.compareResults[.qwen]?.status
        XCTAssertTrue(store.isWorking, "Codex is still pending")
        XCTAssertEqual(store.compareResults[.codex]?.state, .pending)
        fixture.cloud.emit(0, text: "Codex complete answer")
        XCTAssertEqual(store.compareResults[.qwen]?.text, "Local complete answer")
        XCTAssertEqual(store.compareResults[.qwen]?.status, localStatus)
        fixture.cloud.resolveReply(0)
        try await waitUntil("The last lane should end aggregate work") { !store.isWorking }
        XCTAssertEqual(store.compareResults[.qwen]?.state, .complete)
        XCTAssertEqual(store.compareResults[.codex]?.state, .complete)
        XCTAssertEqual(store.compareResults[.codex]?.text, "Codex complete answer")
        XCTAssertEqual(store.assistantActivity, .ready)
    }

    @MainActor
    func testEitherLaneFailurePreservesTheOtherPendingAndCompletedAnswer() async throws {
        for failingProvider in [AssistantProvider.qwen, .codex] {
            let fixture = RoutingFixture()
            let store = fixture.store
            defer { fixture.drain() }
            try await beginCompare(fixture)
            let survivingProvider: AssistantProvider = failingProvider == .qwen ? .codex : .qwen
            let failing = fixture.client(failingProvider), surviving = fixture.client(survivingProvider)
            surviving.emit(0, text: "Surviving partial")
            failing.emit(0, text: "Incomplete failed lane")
            let disconnects = surviving.disconnectCount
            failing.resolveReply(0, result: .failure(AssistantFailure.timedOut))
            try await waitUntil("Only the failing lane should fail") { store.compareResults[failingProvider]?.state == .failed }
            XCTAssertTrue(store.isWorking)
            XCTAssertEqual(store.assistantActivity, .responding)
            XCTAssertEqual(store.compareResults[survivingProvider]?.state, .pending)
            XCTAssertEqual(store.compareResults[survivingProvider]?.text, "Surviving partial")
            XCTAssertEqual(store.connection(for: survivingProvider), .ready)
            XCTAssertEqual(surviving.disconnectCount, disconnects)
            surviving.emit(0, text: "Surviving complete answer")
            surviving.resolveReply(0)
            try await waitUntil("The survivor should still complete") { !store.isWorking }
            XCTAssertEqual(store.compareResults[failingProvider]?.state, .failed)
            XCTAssertEqual(store.compareResults[survivingProvider]?.state, .complete)
            XCTAssertEqual(store.compareResults[survivingProvider]?.text, "Surviving complete answer")
            XCTAssertEqual(surviving.disconnectCount, disconnects)
            XCTAssertEqual(store.assistantActivity, .ready)
        }
    }

    @MainActor
    func testGlobalInvalidationsCancelBothLanesAndRejectLateTextAndFailure() async throws {
        for invalidation in ["placement", "source", "selection", "stop", "route"] {
            let fixture = RoutingFixture()
            let store = fixture.store
            defer { fixture.drain() }
            store.share(text: "First. Second.", name: "source.txt")
            try await beginCompare(fixture)
            let ticket = store.contextTicket()
            fixture.local.emit(0, text: "Old local partial")
            fixture.cloud.emit(0, text: "Old Codex partial")
            switch invalidation {
            case "placement": store.placed(at: CGPoint(x: 710, y: -110))
            case "source": store.share(text: "Replacement source.", name: "replacement.txt")
            case "selection": store.selectText(range: NSRange(location: 0, length: 6), sourceRevision: store.sourceRevision)
            case "stop": store.cancelWork()
            default: store.setAssistantRoute(.local)
            }
            XCTAssertFalse(store.isWorking, invalidation)
            XCTAssertFalse(store.isCurrent(ticket, requireVisible: false), invalidation)
            let results = snapshot(store), reply = store.reply, status = store.status
            let activity = store.assistantActivity
            XCTAssertTrue([AssistantActivity.stopped, .idle].contains(activity), invalidation)
            let localMessage = store.message(for: .qwen), cloudMessage = store.message(for: .codex)
            fixture.local.emit(0, text: "Stale local text")
            fixture.cloud.emit(0, text: "Stale Codex text")
            fixture.local.resolveReply(0)
            fixture.cloud.resolveReply(0, result: .failure(AssistantFailure.protocolError))
            try await waitUntil("Cancelled continuations should drain") {
                fixture.local.finishedReplies.contains(0) && fixture.cloud.finishedReplies.contains(0)
            }
            await Task.yield()
            XCTAssertEqual(snapshot(store), results, invalidation)
            XCTAssertEqual(store.reply, reply, invalidation)
            XCTAssertEqual(store.status, status, invalidation)
            XCTAssertEqual(store.assistantActivity, activity, invalidation)
            XCTAssertEqual(store.message(for: .qwen), localMessage, invalidation)
            XCTAssertEqual(store.message(for: .codex), cloudMessage, invalidation)
            XCTAssertFalse(store.isWorking, invalidation)
        }
    }

    @MainActor
    func testDisconnectAndReconnectFenceOnlyThatLaneWhileCodexContinues() async throws {
        let fixture = RoutingFixture()
        let store = fixture.store
        defer { fixture.drain() }
        try await beginCompare(fixture)
        let ticket = store.contextTicket(), cloudDisconnects = fixture.cloud.disconnectCount
        fixture.cloud.emit(0, text: "Codex remains active")
        store.disconnectAssistant(provider: .qwen)
        XCTAssertTrue(store.isWorking)
        XCTAssertTrue(store.isCurrent(ticket, requireVisible: false))
        XCTAssertEqual(store.compareResults[.qwen]?.state, .cancelled)
        XCTAssertEqual(store.compareResults[.codex]?.state, .pending)
        XCTAssertEqual(store.connection(for: .codex), .ready)
        XCTAssertEqual(fixture.cloud.disconnectCount, cloudDisconnects)

        store.connectAssistant(provider: .qwen)
        try await waitUntil("The first reconnect should start") { fixture.local.connectCount == 2 }
        store.disconnectAssistant(provider: .qwen)
        store.connectAssistant(provider: .qwen)
        try await waitUntil("A second reconnect should replace the first") { fixture.local.connectCount == 3 }
        fixture.local.resolveConnection(2)
        try await waitUntil("The newest local connection should be ready") { store.connection(for: .qwen) == .ready }
        let message = store.message(for: .qwen), results = snapshot(store)
        fixture.local.resolveConnection(1, result: .failure(AssistantFailure.signedOut))
        fixture.local.emit(0, text: "Stale pre-disconnect local text")
        fixture.local.resolveReply(0, result: .failure(AssistantFailure.turnFailed))
        try await waitUntil("The superseded connection and reply should drain") {
            fixture.local.finishedConnections.contains(1) && fixture.local.finishedReplies.contains(0)
        }
        await Task.yield()
        XCTAssertEqual(store.connection(for: .qwen), .ready)
        XCTAssertEqual(store.message(for: .qwen), message)
        XCTAssertEqual(snapshot(store), results)
        XCTAssertTrue(store.isCurrent(ticket, requireVisible: false))
        XCTAssertEqual(fixture.cloud.disconnectCount, cloudDisconnects)
        fixture.cloud.emit(0, text: "Codex finishes after local reconnect")
        fixture.cloud.resolveReply(0)
        try await waitUntil("Codex should finish independently") { !store.isWorking }
        XCTAssertEqual(store.compareResults[.codex]?.state, .complete)
        XCTAssertEqual(store.compareResults[.codex]?.text, "Codex finishes after local reconnect")
        XCTAssertEqual(store.connection(for: .qwen), .ready)
    }

    @MainActor
    func testLocalModelAndContextChangesPreserveActiveCodex() async throws {
        for change in ["model", "clear context", "disable context"] {
            let fixture = RoutingFixture()
            let store = fixture.store
            defer { fixture.drain() }
            store.setSessionContextEnabled(true)
            try await beginCompare(fixture)
            fixture.cloud.emit(0, text: "Independent Codex answer")
            let ticket = store.contextTicket(), cloudDisconnects = fixture.cloud.disconnectCount
            let cloudMessage = store.message(for: .codex)
            switch change {
            case "model":
                let alternative = try XCTUnwrap(QwenAssistant.supportedModels.first { $0 != store.qwenModel })
                store.selectQwenModel(alternative)
                XCTAssertEqual(fixture.factory.calls.last?.provider, .qwen)
                XCTAssertEqual(fixture.factory.calls.last?.model, alternative)
                let replacement = try XCTUnwrap(fixture.factory.localReplacements.last)
                XCTAssertEqual(replacement.connectCount, 0)
                XCTAssertTrue(replacement.replies.isEmpty)
                try await waitUntil("The old local model should retire") { fixture.local.shutdownCount == 1 }
                fixture.local.resolveShutdown(0)
            case "clear context": store.clearSessionContext()
            default: store.setSessionContextEnabled(false)
            }
            XCTAssertTrue(store.isWorking, change)
            XCTAssertTrue(store.isCurrent(ticket, requireVisible: false), change)
            XCTAssertEqual(store.connection(for: .codex), .ready, change)
            XCTAssertEqual(store.message(for: .codex), cloudMessage, change)
            XCTAssertEqual(store.compareResults[.codex]?.text, "Independent Codex answer", change)
            XCTAssertEqual(store.compareResults[.codex]?.state, .pending, change)
            XCTAssertEqual(fixture.cloud.disconnectCount, cloudDisconnects, change)
            XCTAssertEqual(fixture.cloud.shutdownCount, 0, change)
            fixture.local.emit(0, text: "Obsolete local answer")
            fixture.local.resolveReply(0, result: .failure(AssistantFailure.turnFailed))
            try await waitUntil("The obsolete local request should drain") { fixture.local.finishedReplies.contains(0) }
            await Task.yield()
            XCTAssertTrue(store.isWorking, change)
            XCTAssertEqual(store.compareResults[.codex]?.text, "Independent Codex answer", change)
            fixture.cloud.resolveReply(0)
            try await waitUntil("Codex should finish after the local change") { !store.isWorking }
            XCTAssertEqual(store.compareResults[.codex]?.state, .complete, change)
            XCTAssertEqual(fixture.cloud.disconnectCount, cloudDisconnects, change)
        }
    }

    @MainActor
    func testPreferenceOnlyChangesAlterDigestAndKeepSubmittedReceipt() async throws {
        let fixture = RoutingFixture()
        let store = fixture.store
        defer { fixture.drain() }
        try await connectBoth(fixture)
        store.prompt = "One unchanged question."
        store.submit()
        try await waitUntil("First Local request") { fixture.local.replies.count == 1 }
        fixture.local.emit(0, text: "First answer")
        fixture.local.resolveReply(0)
        try await waitUntil("First answer done") { !store.isWorking }
        let first = try XCTUnwrap(store.compareResults[.qwen]?.receipt)
        XCTAssertNil(first.settings?.role)
        store.evolution.confirmRole(.keeper)
        XCTAssertEqual(store.compareResults[.qwen]?.receipt, first)
        store.submit()
        try await waitUntil("Second Local request") { fixture.local.replies.count == 2 }
        let second = try XCTUnwrap(store.compareResults[.qwen]?.receipt)
        XCTAssertNotEqual(first.inputDigest, second.inputDigest)
        fixture.local.emit(1, text: "Second answer")
        fixture.local.resolveReply(1)
        try await waitUntil("Second answer done") { !store.isWorking }
        store.evolution.confirmHelpStyle(.reflective)
        store.submit()
        try await waitUntil("Third Local request") { fixture.local.replies.count == 3 }
        XCTAssertNotEqual(store.compareResults[.qwen]?.receipt?.inputDigest, second.inputDigest)
        XCTAssertTrue(fixture.cloud.replies.isEmpty)
    }

    @MainActor
    func testFailureAndCompletedSiblingActivityPreserveCharacterAndPlacement() async throws {
        let fixture = RoutingFixture()
        let store = fixture.store
        defer { fixture.drain() }
        XCTAssertEqual(store.assistantActivity, .idle)
        try await beginCompare(fixture)
        let placement = store.placementRevision, origin = store.evolution.origin, history = store.evolution.history
        fixture.local.emit(0, text: "Answer available")
        fixture.local.resolveReply(0)
        try await waitUntil("First answer") { store.compareResults[.qwen]?.state == .complete }
        XCTAssertEqual(store.assistantActivity, .working, "A completed sibling is not live streaming")
        fixture.cloud.resolveReply(0, result: .failure(AssistantFailure.turnFailed))
        try await waitUntil("Other lane failed") { !store.isWorking }
        XCTAssertEqual(store.assistantActivity, .ready)
        XCTAssertEqual(store.placementRevision, placement)
        XCTAssertEqual(store.evolution.origin, origin)
        XCTAssertEqual(store.evolution.history, history)
        XCTAssertTrue(store.assistantAccessibilityValue.contains("Answer ready"))
        store.setAssistantRoute(.local)
        store.submit()
        try await waitUntil("Local retry") { fixture.local.replies.count == 2 }
        fixture.local.resolveReply(1, result: .failure(AssistantFailure.turnFailed))
        try await waitUntil("Local failure") { !store.isWorking }
        XCTAssertEqual(store.assistantActivity, .failed)
    }

    @MainActor
    func testShutdownWaitsForBothOwnedClientsAndRetiredLocalClient() async throws {
        let fixture = RoutingFixture()
        let store = fixture.store
        defer { fixture.drain() }
        try await connectBoth(fixture)
        let alternative = try XCTUnwrap(QwenAssistant.supportedModels.first { $0 != store.qwenModel })
        store.selectQwenModel(alternative)
        let replacement = try XCTUnwrap(fixture.factory.localReplacements.last)
        try await waitUntil("The retired local client should have pending cleanup") { fixture.local.shutdownCount == 1 }
        var finished = false
        let shutdown = Task { @MainActor in
            await store.shutdownAssistant()
            finished = true
        }
        try await waitUntil("Final shutdown should reach an owned client") {
            replacement.shutdownCount > 0 || fixture.cloud.shutdownCount > 0
        }
        XCTAssertTrue(store.isShuttingDown)
        XCTAssertFalse(finished)
        let factoryCalls = fixture.factory.calls.count
        let connections = fixture.local.connectCount + fixture.cloud.connectCount + replacement.connectCount
        store.setAssistantRoute(.compare)
        store.connectAssistant(provider: .qwen)
        store.connectAssistant(provider: .codex)
        store.prompt = "Do not send while shutting down."
        store.submit()
        XCTAssertEqual(fixture.factory.calls.count, factoryCalls)
        XCTAssertEqual(fixture.local.connectCount + fixture.cloud.connectCount + replacement.connectCount, connections)
        XCTAssertTrue(fixture.local.replies.isEmpty)
        XCTAssertTrue(fixture.cloud.replies.isEmpty)
        XCTAssertTrue(replacement.replies.isEmpty)

        // Cleanup may be concurrent or sequential; every owned client must be awaited.
        for _ in 0..<2 {
            try await waitUntil("An owned client should expose its shutdown continuation") {
                replacement.hasPendingShutdown || fixture.cloud.hasPendingShutdown
            }
            XCTAssertFalse(finished)
            if replacement.hasPendingShutdown { replacement.resolveShutdown(0) }
            else { fixture.cloud.resolveShutdown(0) }
        }
        try await waitUntil("Both current clients should finish cleanup") {
            replacement.finishedShutdowns.contains(0) && fixture.cloud.finishedShutdowns.contains(0)
        }
        await Task.yield()
        XCTAssertFalse(finished, "The retired local client is still owned until its shutdown completes")
        fixture.local.resolveShutdown(0)
        try await waitUntil("All current and retired clients should be drained") { finished }
        await shutdown.value
        XCTAssertEqual(fixture.local.shutdownCount, 1)
        XCTAssertEqual(fixture.cloud.shutdownCount, 1)
        XCTAssertEqual(replacement.shutdownCount, 1)
        XCTAssertFalse(store.isWorking)
    }

    @MainActor
    private func connect(_ store: CompanionStore, provider: AssistantProvider,
                         client: RoutingControlledClient) async throws {
        let index = client.connectCount
        store.connectAssistant(provider: provider)
        try await waitUntil("Explicit connection should reach its destination") { client.connectCount == index + 1 }
        client.resolveConnection(index)
        try await waitUntil("Explicit connection should become ready") { store.connection(for: provider) == .ready }
    }

    @MainActor
    private func connectBoth(_ fixture: RoutingFixture) async throws {
        try await connect(fixture.store, provider: .qwen, client: fixture.local)
        try await connect(fixture.store, provider: .codex, client: fixture.cloud)
    }

    @MainActor
    private func beginCompare(_ fixture: RoutingFixture) async throws {
        try await connectBoth(fixture)
        fixture.store.setAssistantRoute(.compare)
        fixture.store.prompt = "Give two independently labeled answers."
        fixture.store.submit()
        try await waitForReplies(fixture)
    }

    @MainActor
    private func waitForReplies(_ fixture: RoutingFixture) async throws {
        try await waitUntil("Both explicit compare lanes should receive one request") {
            fixture.local.replies.count == 1 && fixture.cloud.replies.count == 1
        }
    }

    @MainActor
    private func snapshot(_ store: CompanionStore) -> [AssistantProvider: [String]] {
        store.compareResults.mapValues { [$0.text, $0.status, String(describing: $0.state)] }
    }

    @MainActor
    private func waitUntil(_ message: String, file: StaticString = #filePath, line: UInt = #line,
                           _ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail(message, file: file, line: line)
        throw RoutingTestFailure.waitTimedOut
    }
}

private enum RoutingTestFailure: Error { case waitTimedOut }

@MainActor
private final class RoutingFixture {
    let local = RoutingControlledClient()
    let factory = RoutingClientFactory()
    var cloud: RoutingControlledClient { factory.cloud }
    lazy var store = CompanionStore(preferenceURL: URL(fileURLWithPath: "/dev/null/unused"),
        assistant: local, provider: .qwen,
        assistantFactory: { [factory] provider, model in factory.make(provider, model) },
        tokenSteward: TokenStewardStore())

    func client(_ provider: AssistantProvider) -> RoutingControlledClient { provider == .qwen ? local : cloud }

    func drain() {
        store.disconnectAssistant(provider: .qwen)
        store.disconnectAssistant(provider: .codex)
        local.drain()
        cloud.drain()
        factory.localReplacements.forEach { $0.drain() }
    }
}

@MainActor
private final class RoutingClientFactory {
    struct Call { let provider: AssistantProvider; let model: String }
    let cloud = RoutingControlledClient()
    private(set) var calls: [Call] = []
    private(set) var localReplacements: [RoutingControlledClient] = []

    func make(_ provider: AssistantProvider, _ model: String) -> RoutingControlledClient {
        calls.append(Call(provider: provider, model: model))
        if provider == .codex { return cloud }
        let client = RoutingControlledClient()
        localReplacements.append(client)
        return client
    }
}

/// Cancellation leaves callbacks available to expose stale-result and cross-client races.
/// Cleanup drains existing continuations and prevents future tasks from suspending.
@MainActor
private final class RoutingControlledClient: AssistantClient {
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
    var hasPendingShutdown: Bool { !pendingShutdowns.isEmpty }

    func connect() async throws {
        let index = connectCount
        connectCount += 1
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
        let index = shutdownCount
        shutdownCount += 1
        if !draining { await withCheckedContinuation { pendingShutdowns[index] = $0 } }
        disconnect()
        finishedShutdowns.insert(index)
    }

    func emit(_ index: Int, text: String) { replies[index].onEvent(.text(text)) }

    func resolveConnection(_ index: Int, result: Result<Void, any Error> = .success(())) {
        guard let pending = pendingConnections.removeValue(forKey: index) else { XCTFail("Connection was not pending"); return }
        pending.resume(with: result)
    }

    func resolveReply(_ index: Int, result: Result<Void, any Error> = .success(())) {
        guard let pending = pendingReplies.removeValue(forKey: index) else { XCTFail("Reply was not pending"); return }
        pending.resume(with: result)
    }

    func resolveShutdown(_ index: Int) {
        guard let pending = pendingShutdowns.removeValue(forKey: index) else { XCTFail("Shutdown was not pending"); return }
        pending.resume()
    }

    func drain() {
        draining = true
        let work = Array(pendingConnections.values) + Array(pendingReplies.values)
        let shutdowns = Array(pendingShutdowns.values)
        pendingConnections.removeAll()
        pendingReplies.removeAll()
        pendingShutdowns.removeAll()
        work.forEach { $0.resume(throwing: AssistantFailure.stopped) }
        shutdowns.forEach { $0.resume() }
    }
}
