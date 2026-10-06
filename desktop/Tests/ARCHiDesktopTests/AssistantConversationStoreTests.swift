import XCTest
@testable import ARCHiDesktop

final class AssistantConversationStoreTests: XCTestCase {
    @MainActor
    func testCompletedLocalExchangeIsCapturedAtNextSendAndNeverSentToCodex() async throws {
        let f = ConversationStoreFixture(); defer { f.cleanUp() }
        try await f.answer("My synthetic codeword is Meadow.", "Your codeword is Meadow.")
        XCTAssertEqual(f.store.localConversation.exchanges.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.path))
        f.store.setAssistantRoute(.compare)
        f.store.connectAssistant(provider: .codex)
        try await ready { f.store.connection(for: .codex) == .ready }
        f.store.prompt = "Repeat that word."
        f.store.submit()
        try await ready { f.local.requests.count == 2 && f.cloud.requests.count == 1 }
        let local = f.local.requests[1], external = f.cloud.requests[0]
        XCTAssertEqual(local.localConversation.first?.answer, "Your codeword is Meadow.")
        XCTAssertEqual(local.localConversation.first?.question, "My synthetic codeword is Meadow.")
        XCTAssertTrue(external.localConversation.isEmpty)
        // JSON object key order is immaterial; the public request values must
        // match while only the local lane receives conversation context.
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: Data(local.input.utf8)),
                       try JSONDecoder().decode(JSONValue.self, from: Data(external.input.utf8)))
        XCTAssertFalse(external.codexInput.contains("Meadow"))
        let receipt = try XCTUnwrap(f.store.compareResults[.qwen]?.receipt)
        XCTAssertEqual(receipt.localConversationCount, 1)
        XCTAssertEqual(receipt.localConversationDigest, local.localConversationDigest)
        f.local.complete(1, "Meadow")
        try await ready { f.store.compareResults[.qwen]?.state == .complete }
        XCTAssertEqual(f.store.localConversation.exchanges.count, 2)
        XCTAssertEqual(f.store.compareResults[.qwen]?.receipt?.localConversationCount, 1)
        f.cloud.complete(0, "I need the word.")
        try await ready { !f.store.isWorking }
        XCTAssertEqual(f.store.localConversation.exchanges.count, 2)
    }

    @MainActor
    func testPartialFailureAndStoppedLateReplyNeverAppend() async throws {
        let f = ConversationStoreFixture(); defer { f.cleanUp() }
        try await f.answer("Start.", "An accepted answer.")
        let previous = f.store.localConversation.exchanges
        f.store.prompt = "Continue."; f.store.submit()
        try await ready { f.local.requests.count == 2 }
        f.local.emit(1, "Partial output")
        XCTAssertEqual(f.store.localConversation.exchanges, previous)
        f.local.fail(1)
        try await ready { !f.store.isWorking }
        XCTAssertEqual(f.store.localConversation.exchanges, previous)
        f.store.setAssistantRoute(.automatic)
        f.store.submit()
        try await ready { f.local.requests.count == 3 }
        f.store.cancelWork()
        f.local.complete(2, "Late stopped answer")
        await Task.yield()
        XCTAssertEqual(f.store.localConversation.exchanges, previous)
        XCTAssertNotEqual(f.store.compareResults[.qwen]?.state, .complete)
    }

    @MainActor
    func testSourceSelectionAndHideClearContextAndFenceLateAppend() async throws {
        for mutation in 0..<3 {
            let local = ConversationReadingRoleClient()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-reading-conversation-\(UUID().uuidString)")
            let store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"),
                assistant: HamptonReasonsAssistant(reasoner: local, contextSelector: local))
            defer {
                store.disconnectAssistant(); local.drain()
                try? FileManager.default.removeItem(at: directory)
            }
            store.share(text: "Meadow is the chosen name.", name: "synthetic.txt")
            store.setAssistantRoute(.automatic)
            store.prompt = "What is the name?"; store.submit()
            try await ready { local.requests.count == 1 }
            local.complete(0, "Meadow")
            try await ready { store.compareResults[.qwen]?.state == .complete }
            XCTAssertEqual(store.localConversation.exchanges.count, 1)
            store.prompt = "Shorter?"; store.submit()
            try await ready { local.requests.count == 2 }
            switch mutation {
            case 0: store.share(text: "A different copy.", name: "other.txt")
            case 1: store.selectText(range: NSRange(location: 0, length: 6), sourceRevision: store.sourceRevision)
            default: store.hideCompanion()
            }
            XCTAssertTrue(store.localConversation.exchanges.isEmpty)
            local.complete(1, "Late Meadow")
            try await ready { local.finished.contains(1) }
            await Task.yield()
            XCTAssertTrue(store.localConversation.exchanges.isEmpty)
            XCTAssertNotEqual(store.compareResults[.qwen]?.state, .complete)
        }
    }

    @MainActor
    func testNewConversationStopsOnlyLocalCompareLaneWithoutChangingDraftOrLessons() async throws {
        let f = ConversationStoreFixture(); defer { f.cleanUp() }
        try await f.answer("Remember this for the visit.", "A temporary exchange.")
        f.store.setAssistantRoute(.compare)
        f.store.connectAssistant(provider: .codex)
        try await ready { f.store.connection(for: .codex) == .ready }
        f.store.prompt = "Current draft stays."; f.store.submit()
        try await ready { f.local.requests.count == 2 && f.cloud.requests.count == 1 }
        f.store.startNewLocalConversation()
        XCTAssertEqual(f.store.prompt, "Current draft stays.")
        XCTAssertEqual(f.store.route, .compare)
        XCTAssertTrue(f.store.localConversation.exchanges.isEmpty)
        XCTAssertEqual(f.store.compareResults[.codex]?.state, .pending)
        f.local.complete(1, "Stale local")
        f.cloud.complete(0, "Independent Codex answer")
        try await ready { !f.store.isWorking }
        XCTAssertTrue(f.store.localConversation.exchanges.isEmpty)
        XCTAssertEqual(f.store.compareResults[.codex]?.state, .complete)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.path))
    }

    @MainActor
    func testWithdrawnLessonClearsTransitiveHistoryAndRestartDoesNotRestoreConversation() async throws {
        let f = ConversationStoreFixture(); defer { f.cleanUp() }
        f.store.beginLessonCorrection()
        var draft = try XCTUnwrap(f.store.lessonDraft)
        draft.topic = "drawing"; draft.text = "Start with a blue pencil."
        XCTAssertTrue(f.store.keepLesson(draft))
        let lesson = try XCTUnwrap(f.store.keptLessons.first)
        try await f.answer("Help with drawing.", "Use a blue pencil.")
        try await f.answer("What tool was that?", "Blue pencil.")
        XCTAssertEqual(f.store.localConversation.exchanges.count, 2)
        let saved = try Data(contentsOf: f.url)
        let reopened = CompanionStore(preferenceURL: f.url, assistant: ConversationStoreClient())
        XCTAssertTrue(reopened.localConversation.exchanges.isEmpty)
        XCTAssertEqual(reopened.keptLessons, [lesson])
        XCTAssertEqual(try Data(contentsOf: f.url), saved)
        reopened.disconnectAssistant()
        XCTAssertTrue(f.store.withdrawLesson(id: lesson.id, expectedRevision: f.store.lessonRevision))
        XCTAssertTrue(f.store.localConversation.exchanges.isEmpty,
            "Later answers can repeat a lesson without citing it; all conversation must be revoked.")
        XCTAssertTrue(f.store.keptLessons.isEmpty)
    }

    @MainActor
    func testModelContextResetAndOptOutClearConversationWithoutInference() async throws {
        for mutation in 0..<3 {
            let f = ConversationStoreFixture(); defer { f.cleanUp() }
            try await f.answer("A task.", "An answer.")
            switch mutation {
            case 0: f.store.selectQwenModel("qwen3:8b")
            case 1: f.store.setSessionContextEnabled(true)
            default: f.store.setLocalConversationEnabled(false)
            }
            XCTAssertTrue(f.store.localConversation.exchanges.isEmpty)
            XCTAssertEqual(f.local.requests.count, 1)
            XCTAssertTrue(f.cloud.requests.isEmpty)
        }
    }

    @MainActor
    func testLessonExpiryRemovesTransitiveConversationBeforeSendAndDuringPendingReply() async throws {
        for expireDuringReply in [false, true] {
            let f = ConversationStoreFixture(); defer { f.cleanUp() }
            f.store.beginLessonCorrection()
            var lesson = try XCTUnwrap(f.store.lessonDraft)
            lesson.topic = "drawing"; lesson.text = "Start with blue pencil."
            lesson.expiresAt = f.clock.now.addingTimeInterval(10)
            XCTAssertTrue(f.store.keepLesson(lesson))
            try await f.answer("Help with drawing.", "Use blue pencil.")
            if !expireDuringReply {
                try await f.answer("What tool was that?", "Blue pencil.")
                f.clock.now = f.clock.now.addingTimeInterval(11)
                XCTAssertTrue(f.store.nextReplyConversation.isEmpty)
            }
            let index = f.local.requests.count
            f.store.prompt = "Which tool?"; f.store.submit()
            try await ready { f.local.requests.count == index + 1 }
            if expireDuringReply {
                XCTAssertEqual(f.local.requests[index].localConversation.count, 1)
                f.clock.now = f.clock.now.addingTimeInterval(11)
            } else {
                XCTAssertTrue(f.local.requests[index].localConversation.isEmpty)
                XCTAssertTrue(f.local.requests[index].localLessons.isEmpty)
            }
            f.local.complete(index, "Current reply.")
            try await ready { !f.store.isWorking }
            XCTAssertFalse(f.store.localConversation.exchanges.contains { $0.answer.contains("pencil") })
            if expireDuringReply { XCTAssertTrue(f.store.localConversation.exchanges.isEmpty) }
        }
    }

    @MainActor
    func testOversizedAnswerStaysVisibleWithoutPretendingItWasRetained() async throws {
        let f = ConversationStoreFixture(); defer { f.cleanUp() }
        try await f.answer("An earlier task.", "An earlier answer.")
        try await f.answer("A task.", String(repeating: "x", count: 9000))
        XCTAssertEqual(f.store.compareResults[.qwen]?.state, .complete)
        XCTAssertEqual(f.store.compareResults[.qwen]?.text.count, 9000)
        XCTAssertTrue(f.store.localConversation.exchanges.isEmpty)
        XCTAssertTrue(f.store.localConversationNotice.contains("not retained"))
    }

    @MainActor
    func testShutdownErasesConversationAndDoesNotPersistIt() async throws {
        let f = ConversationStoreFixture(); defer { f.cleanUp() }
        try await f.answer("For this visit.", "Temporary only.")
        await f.store.shutdownAssistant()
        XCTAssertTrue(f.store.localConversation.exchanges.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.path))
    }
}

@MainActor
private func ready(_ condition: () -> Bool) async throws {
    for _ in 0..<500 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(2))
    }
    XCTFail("Expected native request-owner state was not reached")
    throw AssistantFailure.timedOut
}

@MainActor
private final class ConversationStoreFixture {
    let local = ConversationStoreClient()
    let cloud = ConversationStoreClient()
    let clock = ConversationClock()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("archi-conversation-\(UUID().uuidString)").appendingPathComponent("preferences.json")
    lazy var store = CompanionStore(preferenceURL: url, assistant: local,
        assistantFactory: { [local, cloud] provider, _ in provider == .qwen ? local : cloud },
        wallClock: { [clock] in clock.now })

    func answer(_ question: String, _ answer: String) async throws {
        store.setAssistantRoute(.automatic)
        store.prompt = question
        let index = local.requests.count
        store.submit()
        try await ready { self.local.requests.count == index + 1 }
        local.complete(index, answer)
        try await ready { self.store.compareResults[.qwen]?.state == .complete }
    }
    func cleanUp() {
        store.disconnectAssistant(); local.drain(); cloud.drain()
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

@MainActor
private final class ConversationClock { var now = Date() }

/// Shared-document replies pass through the production Hampton reading owner;
/// raw text alone cannot fabricate its validated proposal snapshot.
@MainActor
private final class ConversationReadingRoleClient: LocalRoleClient {
    var requests: [LocalRoleRequest] = []
    var finished: Set<Int> = []
    private var pending: [Int: CheckedContinuation<String, any Error>] = [:]
    func connect() async throws {}
    func disconnect() {}
    func shutdown() async { drain() }
    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
        let index = requests.count; requests.append(request)
        defer { finished.insert(index) }
        let answer = try await withCheckedThrowingContinuation { pending[index] = $0 }
        let payload: [String: JSONValue] = ["schema": .string("archi-reason-proposal/v1"),
            "requestID": .string(request.id), "kind": .string("ANSWER"), "answer": .string(answer),
            "uncertainty": .string(""), "sourceIDs": .array([]), "memoryIDs": .array([])]
        return LocalRoleResult(requestID: request.id, role: request.role,
            text: String(decoding: try JSONEncoder().encode(payload), as: UTF8.self),
            model: QwenModelMetadata(name: "reading-fixture", family: "qwen", parameterSize: "fixture",
                quantization: "fixture", digest: "fixture-only"), elapsedMilliseconds: 0)
    }
    func complete(_ index: Int, _ answer: String) { pending.removeValue(forKey: index)?.resume(returning: answer) }
    func drain() {
        let all = Array(pending.values); pending.removeAll()
        all.forEach { $0.resume(throwing: AssistantFailure.stopped) }
    }
}

@MainActor
private final class ConversationStoreClient: AssistantClient {
    var requests: [AssistantRequest] = []
    private var events: [@MainActor (AssistantEvent) -> Void] = []
    private var pending: [Int: CheckedContinuation<Void, any Error>] = [:]
    func connect() async throws {}
    func disconnect() {}
    func shutdown() async { drain() }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        let index = requests.count; requests.append(request); events.append(onEvent)
        try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func emit(_ index: Int, _ text: String) { events[index](.text(text)) }
    func complete(_ index: Int, _ text: String) { emit(index, text); pending.removeValue(forKey: index)?.resume() }
    func fail(_ index: Int) { pending.removeValue(forKey: index)?.resume(throwing: AssistantFailure.protocolError) }
    func drain() {
        let all = Array(pending.values); pending.removeAll()
        all.forEach { $0.resume(throwing: AssistantFailure.stopped) }
    }
}
