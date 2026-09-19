import XCTest
@testable import ARCHiDesktop

final class AssistantStoreTests: XCTestCase {
    @MainActor
    func testExplicitConnectionStreamsReplyWithTheExactSharedContext() async throws {
        let client = ControlledAssistantClient()
        let store = makeStore(client)
        defer { store.disconnectAssistant(); client.resumeAllPending() }

        XCTAssertEqual(client.connectCount, 0)
        XCTAssertTrue(client.replies.isEmpty)
        store.connectAssistant()
        XCTAssertEqual(store.connectionState, .connecting)
        try await waitUntil("The connection should reach the client") { client.connectCount == 1 }
        XCTAssertTrue(client.replies.isEmpty, "Connecting must not submit a draft or document")
        client.resolveConnection(0)
        try await waitUntil("The completed connection should become ready") { store.connectionState == .ready }

        store.share(text: "One line.\nA second line with café.", name: "notes.txt")
        store.placed(at: CGPoint(x: 320, y: -40))
        store.preferences.tone = "Warm"
        store.preferences.replyLength = 0.75
        store.prompt = "What needs another look?"
        let sourceRevision = store.sourceRevision
        let placementRevision = store.placementRevision
        store.submit()
        XCTAssertTrue(store.isWorking)
        try await waitUntil("Send should deliver one request") { client.replies.count == 1 }

        let request = try XCTUnwrap(client.replies.first?.request)
        XCTAssertEqual(request.prompt, "What needs another look?")
        XCTAssertEqual(request.sourceName, "notes.txt")
        XCTAssertEqual(request.sourceText, "One line.\nA second line with café.")
        XCTAssertEqual(request.sourceRevision, sourceRevision)
        XCTAssertEqual(request.placementRevision, placementRevision)
        XCTAssertEqual(request.tone, "Warm")
        XCTAssertEqual(request.replyLength, 0.75)

        client.emit(0, text: "The second")
        XCTAssertEqual(store.reply, "The second")
        client.emit(0, text: "The second line needs another look.")
        XCTAssertEqual(store.reply, "The second line needs another look.")
        client.resolveReply(0)
        try await waitUntil("Finishing the stream should finish the work") { !store.isWorking }
        XCTAssertEqual(store.connectionState, .ready)
        XCTAssertEqual(store.status, "Reply ready · shared copy revision \(sourceRevision)")
        XCTAssertEqual(store.sharedText, request.sourceText)
    }

    @MainActor
    func testMovingCompanionCancelsReplyAndRejectsLateTextAndFailure() async throws {
        let client = ControlledAssistantClient()
        let store = makeStore(client)
        defer { store.disconnectAssistant(); client.resumeAllPending() }
        try await connect(store, client)
        store.prompt = "Look at this paragraph."
        store.submit()
        try await waitUntil("The reply should start") { client.replies.count == 1 }
        client.emit(0, text: "A partial observation")

        let destination = CGPoint(x: -160, y: 510)
        store.placed(at: destination)
        let stoppedReply = store.reply
        let stoppedStatus = store.status
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.connectionState, .disconnected)
        XCTAssertNotEqual(stoppedReply, "A partial observation")
        XCTAssertGreaterThan(client.disconnectCount, 0)

        client.emit(0, text: "Late text about the old location")
        client.resolveReply(0, result: .failure(AssistantFailure.turnFailed))
        try await waitUntil("The cancelled reply continuation should drain") { client.finishedReplies.contains(0) }
        await Task.yield()
        XCTAssertEqual(store.position, destination)
        XCTAssertEqual(store.reply, stoppedReply)
        XCTAssertEqual(store.status, stoppedStatus)
        XCTAssertEqual(store.connectionState, .disconnected)
    }

    @MainActor
    func testHiddenCompanionCanSendTextAndAcceptAReplyInTheWorkspace() async throws {
        let client = ControlledAssistantClient()
        let store = makeStore(client)
        defer { store.disconnectAssistant(); client.resumeAllPending() }
        store.hideCompanion()
        try await connect(store, client)
        store.prompt = "Help me think through this idea."
        store.submit()
        try await waitUntil("A hidden body must not prevent workspace text requests") { client.replies.count == 1 }
        let ticket = store.contextTicket()
        XCTAssertFalse(store.isCurrent(ticket))
        XCTAssertTrue(store.isCurrent(ticket, requireVisible: false))

        client.emit(0, text: "Here is a way to begin.")
        XCTAssertEqual(store.reply, "Here is a way to begin.")
        client.resolveReply(0)
        try await waitUntil("The workspace reply should finish while the body remains hidden") { !store.isWorking }
        XCTAssertFalse(store.isVisible)
        XCTAssertEqual(store.status, "Reply ready")
        XCTAssertEqual(store.connectionState, .ready)
    }

    @MainActor
    func testCancelledConnectionCannotBecomeReadyAfterLateSuccess() async throws {
        let client = ControlledAssistantClient()
        let store = makeStore(client)
        defer { store.disconnectAssistant(); client.resumeAllPending() }
        store.connectAssistant()
        try await waitUntil("The first connection should start") { client.connectCount == 1 }
        store.disconnectAssistant()
        let disconnectedMessage = store.connectionMessage
        let disconnectedStatus = store.status
        client.resolveConnection(0)
        try await waitUntil("The cancelled connection continuation should drain") { client.finishedConnections.contains(0) }
        await Task.yield()

        XCTAssertEqual(store.connectionState, .disconnected)
        XCTAssertEqual(store.connectionMessage, disconnectedMessage)
        XCTAssertEqual(store.status, disconnectedStatus)
        XCTAssertTrue(client.replies.isEmpty)
    }

    @MainActor
    func testLateCancelledConnectionFailureCannotOverwriteAReplacementConnection() async throws {
        let client = ControlledAssistantClient()
        let store = makeStore(client)
        defer { store.disconnectAssistant(); client.resumeAllPending() }
        store.connectAssistant()
        try await waitUntil("The first connection should start") { client.connectCount == 1 }
        store.disconnectAssistant()
        store.connectAssistant()
        try await waitUntil("A replacement connection should start") { client.connectCount == 2 }
        client.resolveConnection(1)
        try await waitUntil("The replacement connection should become ready") { store.connectionState == .ready }
        let readyMessage = store.connectionMessage
        let readyStatus = store.status

        client.resolveConnection(0, result: .failure(AssistantFailure.signedOut))
        try await waitUntil("The old failure should drain") { client.finishedConnections.contains(0) }
        await Task.yield()
        XCTAssertEqual(store.connectionState, .ready)
        XCTAssertEqual(store.connectionMessage, readyMessage)
        XCTAssertEqual(store.status, readyStatus)
    }

    @MainActor
    func testReplacingSourceClearsOldReplyAndLateFailureCannotOverwriteNewWork() async throws {
        let client = ControlledAssistantClient()
        let store = makeStore(client)
        defer { store.disconnectAssistant(); client.resumeAllPending() }
        try await connect(store, client)
        store.share(text: "First source", name: "first.txt")
        store.prompt = "Review this."
        store.submit()
        try await waitUntil("The old-source reply should start") { client.replies.count == 1 }
        client.emit(0, text: "About the first source")

        store.share(text: "Replacement source", name: "replacement.txt")
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.connectionState, .disconnected)
        XCTAssertNotEqual(store.reply, "About the first source")
        try await connect(store, client)
        store.prompt = "Review the replacement."
        store.submit()
        try await waitUntil("The new-source reply should start") { client.replies.count == 2 }
        client.emit(1, text: "About the replacement")
        let currentStatus = store.status

        client.emit(0, text: "Stale first-source text")
        client.resolveReply(0, result: .failure(AssistantFailure.turnFailed))
        try await waitUntil("The old-source failure should drain") { client.finishedReplies.contains(0) }
        await Task.yield()
        XCTAssertTrue(store.isWorking)
        XCTAssertEqual(store.connectionState, .ready)
        XCTAssertEqual(store.reply, "About the replacement")
        XCTAssertEqual(store.status, currentStatus)
        XCTAssertEqual(store.sharedText, "Replacement source")
        XCTAssertEqual(store.sourceName, "replacement.txt")

        client.resolveReply(1)
        try await waitUntil("The replacement reply should finish") { !store.isWorking }
        XCTAssertEqual(store.reply, "About the replacement")
    }

    @MainActor
    func testDisconnectClearsPartialReplyAndLateFailureCannotRestoreIt() async throws {
        let client = ControlledAssistantClient()
        let store = makeStore(client)
        defer { store.disconnectAssistant(); client.resumeAllPending() }
        try await connect(store, client)
        store.share(text: "Keep this local copy", name: "retained.txt")
        store.prompt = "Review the copy."
        store.submit()
        try await waitUntil("The reply should start") { client.replies.count == 1 }
        client.emit(0, text: "Partial reply to remove")
        store.disconnectAssistant()
        let disconnectedReply = store.reply
        let disconnectedMessage = store.connectionMessage
        XCTAssertNotEqual(disconnectedReply, "Partial reply to remove")
        XCTAssertFalse(store.isWorking)

        client.emit(0, text: "Late partial reply")
        client.resolveReply(0, result: .failure(AssistantFailure.protocolError))
        try await waitUntil("The disconnected stream should drain") { client.finishedReplies.contains(0) }
        await Task.yield()
        XCTAssertEqual(store.connectionState, .disconnected)
        XCTAssertEqual(store.reply, disconnectedReply)
        XCTAssertEqual(store.connectionMessage, disconnectedMessage)
        XCTAssertEqual(store.status, "Codex disconnected")
        XCTAssertEqual(store.sharedText, "Keep this local copy")
    }

    @MainActor
    func testCurrentReplyFailureEndsWorkAndSurfacesTheConnectionFailure() async throws {
        let client = ControlledAssistantClient()
        let store = makeStore(client)
        defer { store.disconnectAssistant(); client.resumeAllPending() }
        try await connect(store, client)
        store.prompt = "A request that fails."
        store.submit()
        try await waitUntil("The reply should start") { client.replies.count == 1 }
        client.emit(0, text: "Incomplete")
        client.resolveReply(0, result: .failure(AssistantFailure.timedOut))
        try await waitUntil("An active failure should be reported") { store.connectionState == .failed }
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.reply, AssistantFailure.timedOut.localizedDescription,
                       "The answer area must expose the actionable failure instead of hiding it in Connections.")
        XCTAssertEqual(store.connectionMessage, AssistantFailure.timedOut.localizedDescription)
        XCTAssertEqual(store.status, store.connectionMessage)
    }

    @MainActor
    func testSelectingAndPreparingQuestionNeverSendsUntilSubmit() async throws {
        let client = ControlledAssistantClient()
        let store = makeStore(client)
        defer { store.disconnectAssistant(); client.resumeAllPending() }
        try await connect(store, client)
        store.share(text: "First.\nSecond.\nSecond.", name: "selection.txt")
        let range = NSRange(location: 15, length: 7)
        store.selectText(range: range, sourceRevision: store.sourceRevision)
        store.askAboutSelection()
        XCTAssertTrue(client.replies.isEmpty)
        XCTAssertEqual(store.textSelection?.quote, "Second.")
        let selected = store.textSelection
        store.submit()
        try await waitUntil("Selection should be sent explicitly") { client.replies.count == 1 }
        XCTAssertEqual(client.replies[0].request.selection, selected)
        XCTAssertEqual(client.replies[0].request.sourceText, store.sharedText)
        client.emit(0, text: "An answer about the second occurrence.")
        client.resolveReply(0)
        try await waitUntil("The scoped answer should complete") { !store.isWorking }
        XCTAssertEqual(store.replySourceSelection, selected)
        store.prompt = String(repeating: "a", count: 16_001)
        store.submit()
        XCTAssertEqual(client.replies.count, 1)
        XCTAssertEqual(store.replySourceSelection, selected)
        XCTAssertEqual(store.reply, "An answer about the second occurrence.")
        store.invalidateTextSelection(reason: "Document scrolled.")
        XCTAssertNil(store.textSelection)
        XCTAssertNil(store.replySourceSelection)
        XCTAssertNotEqual(store.reply, "An answer about the second occurrence.")
        XCTAssertEqual(store.connectionState, .ready)
    }

    @MainActor
    func testChangingSelectionRejectsLateOldReplyAtSameSourceRevision() async throws {
        let client = ControlledAssistantClient()
        let store = makeStore(client)
        defer { store.disconnectAssistant(); client.resumeAllPending() }
        try await connect(store, client)
        store.share(text: "First.\nSecond.", name: "selection.txt")
        store.selectText(range: NSRange(location: 0, length: 6), sourceRevision: store.sourceRevision)
        store.askAboutSelection()
        store.submit()
        try await waitUntil("The first selection reply should begin") { client.replies.count == 1 }
        let oldTicket = store.contextTicket()
        store.selectText(range: NSRange(location: 7, length: 7), sourceRevision: store.sourceRevision)
        let currentReply = store.reply
        XCTAssertFalse(store.isCurrent(oldTicket, requireVisible: false))
        client.emit(0, text: "A late answer about First.")
        client.resolveReply(0)
        try await waitUntil("Old continuation should drain") { client.finishedReplies.contains(0) }
        await Task.yield()
        XCTAssertEqual(store.textSelection?.quote, "Second.")
        XCTAssertEqual(store.reply, currentReply)
        XCTAssertNil(store.replySourceSelection)
        XCTAssertFalse(store.isWorking)
    }

    @MainActor
    func testStaleNativeSelectionCallbackCannotAffectNewDocument() {
        let client = ControlledAssistantClient()
        let store = makeStore(client)
        store.share(text: "First source", name: "first.txt")
        let oldRevision = store.sourceRevision
        store.share(text: "New source", name: "second.txt")
        store.selectText(range: NSRange(location: 0, length: 3), sourceRevision: store.sourceRevision)
        let current = store.textSelection
        let ticket = store.contextTicket()
        store.selectText(range: NSRange(location: 0, length: 0), sourceRevision: oldRevision)
        store.selectText(range: NSRange(location: 0, length: 5), sourceRevision: oldRevision)
        XCTAssertEqual(store.textSelection, current)
        XCTAssertTrue(store.isCurrent(ticket))
        store.selectText(range: NSRange(location: NSNotFound, length: 3), sourceRevision: store.sourceRevision)
        XCTAssertEqual(store.textSelection, current)
        store.placed(at: CGPoint(x: 90, y: 70))
        XCTAssertNil(store.textSelection)
        XCTAssertEqual(store.sharedText, "New source")
        XCTAssertTrue(client.replies.isEmpty)
    }

    @MainActor
    func testFirstSelectionCancelsAnUnscopedReplyWithoutLeavingWorkRunning() async throws {
        let client = ControlledAssistantClient()
        let store = makeStore(client)
        defer { store.disconnectAssistant(); client.resumeAllPending() }
        try await connect(store, client)
        store.share(text: "First. Second.", name: "source.txt")
        store.prompt = "Explain the document."
        store.submit()
        try await waitUntil("Unscoped reply should begin") { client.replies.count == 1 }
        store.selectText(range: NSRange(location: 0, length: 6), sourceRevision: store.sourceRevision)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.connectionState, .disconnected)
        let reply = store.reply
        client.emit(0, text: "Obsolete whole-document answer")
        client.resolveReply(0)
        try await waitUntil("Obsolete reply should drain") { client.finishedReplies.contains(0) }
        await Task.yield()
        XCTAssertEqual(store.reply, reply)
        XCTAssertEqual(store.textSelection?.quote, "First.")
    }

    @MainActor
    private func makeStore(_ client: ControlledAssistantClient) -> CompanionStore {
        CompanionStore(preferenceURL: URL(fileURLWithPath: "/dev/null/unused"), assistant: client, provider: .codex,
            tokenSteward: TokenStewardStore())
    }

    @MainActor
    private func connect(_ store: CompanionStore, _ client: ControlledAssistantClient) async throws {
        let index = client.connectCount
        store.connectAssistant()
        try await waitUntil("The explicit connection should start") { client.connectCount == index + 1 }
        client.resolveConnection(index)
        try await waitUntil("The explicit connection should become ready") { store.connectionState == .ready }
    }

    @MainActor
    private func waitUntil(_ message: String, file: StaticString = #filePath, line: UInt = #line,
                           _ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail(message, file: file, line: line)
        throw ControlledTestFailure.waitTimedOut
    }
}

private enum ControlledTestFailure: Error { case waitTimedOut }

/// Disconnect deliberately leaves continuations and event handlers available.
/// Tests can therefore deliver the late output that a cancelled transport must resist.
@MainActor
private final class ControlledAssistantClient: AssistantClient {
    struct CapturedReply {
        let request: AssistantRequest
        let onEvent: @MainActor (AssistantEvent) -> Void
    }

    private(set) var connectCount = 0
    private(set) var disconnectCount = 0
    private(set) var replies: [CapturedReply] = []
    private(set) var finishedConnections = Set<Int>()
    private(set) var finishedReplies = Set<Int>()
    private var pendingConnections: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var pendingReplies: [Int: CheckedContinuation<Void, any Error>] = [:]

    func connect() async throws {
        let index = connectCount
        connectCount += 1
        defer { finishedConnections.insert(index) }
        try await withCheckedThrowingContinuation { pendingConnections[index] = $0 }
    }

    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        let index = replies.count
        replies.append(CapturedReply(request: request, onEvent: onEvent))
        defer { finishedReplies.insert(index) }
        try await withCheckedThrowingContinuation { pendingReplies[index] = $0 }
    }

    func disconnect() { disconnectCount += 1 }

    func emit(_ index: Int, text: String) { replies[index].onEvent(.text(text)) }

    func resolveConnection(_ index: Int, result: Result<Void, any Error> = .success(())) {
        guard let continuation = pendingConnections.removeValue(forKey: index) else {
            XCTFail("Connection \(index) was not pending")
            return
        }
        continuation.resume(with: result)
    }

    func resolveReply(_ index: Int, result: Result<Void, any Error> = .success(())) {
        guard let continuation = pendingReplies.removeValue(forKey: index) else {
            XCTFail("Reply \(index) was not pending")
            return
        }
        continuation.resume(with: result)
    }

    func resumeAllPending() {
        let connections = Array(pendingConnections.values)
        let work = Array(pendingReplies.values)
        pendingConnections.removeAll()
        pendingReplies.removeAll()
        for continuation in connections + work { continuation.resume(throwing: AssistantFailure.stopped) }
    }
}
