import Foundation
import XCTest
@testable import ARCHiDesktop

/// Synthetic local files and uncooperative in-process clients only.
@MainActor
final class CoreMemoryFreshnessTests: XCTestCase {
    func testExternalProfileForgetBlocksNextPrivateDispatchWithoutOverwriting() async throws {
        let f = Fixture(); defer { f.clean() }
        try f.seedProfile()
        let writer = f.otherStore(); defer { writer.disconnectAssistant() }
        XCTAssertTrue(writer.updatePersonalContext(nil, expected: writer.personalContext))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.path))

        f.send()
        await Task.yield()
        XCTAssertFalse(f.store.isWorking)
        XCTAssertEqual(f.local.connectCount, 0)
        XCTAssertTrue(f.local.requests.isEmpty)
        XCTAssertEqual(f.cloud.connectCount, 0)
        XCTAssertTrue(f.store.status.contains("changed outside this session"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.path))
    }

    func testExternalLessonWithdrawalWhileConnectingRejectsDispatchAndFallback() async throws {
        let f = Fixture(); defer { f.clean() }
        try f.seedLesson()
        let writer = f.otherStore(); defer { writer.disconnectAssistant() }
        let lesson = try XCTUnwrap(writer.keptLessons.first)
        f.local.holdConnection = true
        f.send()
        try await wait { f.local.connectCount == 1 }
        XCTAssertTrue(writer.withdrawLesson(id: lesson.id, expectedRevision: writer.lessonRevision))
        f.local.resolveConnection()
        try await wait { !f.store.isWorking }
        XCTAssertTrue(f.local.requests.isEmpty)
        XCTAssertEqual(f.cloud.connectCount, 0)
        XCTAssertTrue(f.store.nextReplyLessons.isEmpty)
        XCTAssertTrue(f.store.nextReplyConversation.isEmpty)
    }

    func testExternalProfileForgetRejectsLateEventsCompletionAndFailure() async throws {
        for finish in [Finish.event, .completion, .failure] {
            let f = Fixture(); defer { f.clean() }
            try f.seedProfile()
            let writer = f.otherStore(); defer { writer.disconnectAssistant() }
            f.send()
            try await wait { f.local.requests.count == 1 }
            XCTAssertNotNil(f.local.requests[0].localProfile)
            XCTAssertTrue(writer.updatePersonalContext(nil, expected: writer.personalContext))

            switch finish {
            case .event:
                f.local.emit("Revoked synthetic profile answer")
                f.local.resolveReply()
            case .completion: f.local.resolveReply()
            case .failure: f.local.resolveReply(.failure(AssistantFailure.timedOut))
            }
            try await wait { !f.store.isWorking }
            XCTAssertNotEqual(f.store.compareResults[.qwen]?.state, .complete)
            XCTAssertFalse(f.store.reply.contains("Revoked synthetic profile answer"))
            XCTAssertTrue(f.store.nextReplyConversation.isEmpty)
            XCTAssertEqual(f.cloud.connectCount, 0)
            XCTAssertTrue(f.cloud.requests.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.path))
        }
    }

    func testExternalLessonWithdrawalRevokesCompletedReceiptAndFollowup() async throws {
        let f = Fixture(); defer { f.clean() }
        try f.seedLesson()
        let writer = f.otherStore(); defer { writer.disconnectAssistant() }
        f.send()
        try await wait { f.local.requests.count == 1 }
        XCTAssertEqual(f.local.requests[0].localLessons.count, 1)
        f.local.emit("Use the synthetic blue pencil.")
        f.local.resolveReply()
        try await wait { !f.store.isWorking }
        let receipt = try XCTUnwrap(f.store.compareResults[.qwen]?.receipt)
        XCTAssertTrue(f.store.isCurrentReplyContext(receipt))
        XCTAssertFalse(f.store.nextReplyConversation.isEmpty)

        let lesson = try XCTUnwrap(writer.keptLessons.first)
        XCTAssertTrue(writer.withdrawLesson(id: lesson.id, expectedRevision: writer.lessonRevision))
        XCTAssertFalse(f.store.isCurrentReplyContext(receipt))
        XCTAssertTrue(f.store.nextReplyConversation.isEmpty)
        XCTAssertTrue(f.store.nextReplyLessons.isEmpty)
        XCTAssertNil(f.store.evolutionFeedbackReceipt(provider: .qwen, requestID: receipt.requestID))
        f.store.beginLessonCorrection(for: .qwen)
        XCTAssertNil(f.store.lessonDraft)
        f.send()
        await Task.yield()
        XCTAssertEqual(f.local.requests.count, 1)
        XCTAssertTrue(f.store.localConversation.exchanges.isEmpty)
        XCTAssertEqual(f.cloud.connectCount, 0)
    }

    func testUnchangedSavedMemoryCompletesAndRetainsFollowup() async throws {
        let f = Fixture(); defer { f.clean() }
        try f.seedProfile()
        try f.seedLesson()
        let saved = try Data(contentsOf: f.url)
        f.send()
        try await wait { f.local.requests.count == 1 }
        XCTAssertNotNil(f.local.requests[0].localProfile)
        XCTAssertEqual(f.local.requests[0].localLessons.count, 1)
        f.local.emit("The current synthetic answer.")
        f.local.resolveReply()
        try await wait { !f.store.isWorking }
        XCTAssertEqual(f.store.compareResults[.qwen]?.state, .complete)
        let receipt = try XCTUnwrap(f.store.compareResults[.qwen]?.receipt)
        XCTAssertTrue(f.store.isCurrentReplyContext(receipt))
        XCTAssertEqual(f.store.nextReplyConversation.count, 1)
        XCTAssertEqual(f.cloud.connectCount, 0)
        XCTAssertEqual(try Data(contentsOf: f.url), saved)
    }

    private enum Finish { case event, completion, failure }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Expected memory request-owner state was not reached")
        throw AssistantFailure.timedOut
    }

    @MainActor
    private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-core-memory-\(UUID())")
        let local = CoreMemoryClient()
        let cloud = CoreMemoryClient()
        var url: URL { directory.appendingPathComponent("preferences.json") }
        lazy var store = CompanionStore(preferenceURL: url, assistant: local,
            assistantFactory: { [local, cloud] provider, _ in provider == .qwen ? local : cloud }, allowsPlay: false)

        func seedProfile() throws {
            let profile = PersonalContext(name: "Synthetic Person", preferredName: "Synthetic", entries: [
                .init(id: UUID().uuidString, title: "Working style", text: "Use the synthetic blue pencil.",
                      status: .confirmed, source: "Synthetic fixture", useInAssistance: true)
            ])
            XCTAssertTrue(store.updatePersonalContext(profile, expected: nil))
        }

        func seedLesson() throws {
            store.beginLessonCorrection()
            var draft = try XCTUnwrap(store.lessonDraft)
            draft.topic = "drawing"; draft.text = "Start with a synthetic blue pencil."
            XCTAssertTrue(store.keepLesson(draft), store.lessonMessage)
        }

        func otherStore() -> CompanionStore {
            CompanionStore(preferenceURL: url, assistant: CoreMemoryClient(), allowsPlay: false)
        }

        func send() {
            store.setAssistantRoute(.native)
            store.setLocalConversationEnabled(true)
            store.prompt = "Help with drawing."
            store.submit()
        }

        func clean() {
            store.cancelWork(); store.disconnectAssistant()
            local.drain(); cloud.drain()
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

@MainActor
private final class CoreMemoryClient: AssistantClient {
    var holdConnection = false
    private(set) var connectCount = 0
    private(set) var requests: [AssistantRequest] = []
    private var connection: CheckedContinuation<Void, any Error>?
    private var answer: CheckedContinuation<Void, any Error>?
    private var event: (@MainActor (AssistantEvent) -> Void)?

    func connect() async throws {
        connectCount += 1
        if holdConnection { try await withCheckedThrowingContinuation { connection = $0 } }
    }

    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        requests.append(request); event = onEvent
        try await withCheckedThrowingContinuation { answer = $0 }
    }

    // Late callbacks deliberately survive disconnect to exercise owner admission.
    func disconnect() {}
    func shutdown() async {}
    func emit(_ text: String) { event?(.text(text)) }
    func resolveConnection() { let pending = connection; connection = nil; pending?.resume() }
    func resolveReply(_ result: Result<Void, any Error> = .success(())) {
        let pending = answer; answer = nil; pending?.resume(with: result)
    }
    func drain() {
        let pending = connection; connection = nil; pending?.resume(throwing: AssistantFailure.stopped)
        resolveReply(.failure(AssistantFailure.stopped))
    }
}
