import Foundation
import XCTest
@testable import ARCHiDesktop

/// In-process clients only: exercises the native owner without loading a model.
@MainActor
final class KnowledgeChatIntegrationTests: XCTestCase {
    func testExplicitPageChatPreservesDocumentAndKeepsAttributableChatOnlyLesson() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let page = try fixture.page()
        fixture.store.share(text: "Private working document stays here.", name: "working.txt")
        fixture.store.selectText(range: NSRange(location: 0, length: 7), sourceRevision: fixture.store.sourceRevision)
        fixture.store.preparePassageRevision()
        let original = fixture.store.sharedText
        fixture.store.useKnowledgePageInChat(page)
        XCTAssertFalse(fixture.store.requestsRevision)
        XCTAssertEqual(fixture.store.sharedText, original)
        fixture.store.setLocalConversationEnabled(true)
        fixture.store.prompt = "Explain the reviewed claim."
        XCTAssertNil(fixture.store.nextAssistantBlockedReason)
        fixture.store.submit()
        try await fixture.wait { fixture.local.request != nil }
        let request = try XCTUnwrap(fixture.local.request)
        XCTAssertEqual(request.localKnowledge?.bindings, [page.binding])
        XCTAssertTrue(request.hasValidLocalKnowledge)
        XCTAssertNil(request.sourceName)
        XCTAssertTrue(request.sourceText.isEmpty)
        XCTAssertNil(request.selection)
        XCTAssertNil(request.localReading)
        fixture.local.complete()
        try await fixture.wait { !fixture.store.isWorking }
        XCTAssertEqual(fixture.store.compareResults[.qwen]?.state, .complete, fixture.store.status)
        let receipt = try XCTUnwrap(fixture.store.compareResults[.qwen]?.receipt)
        XCTAssertEqual(receipt.knowledgeDependencies, [page.binding])
        XCTAssertEqual(receipt.knowledgeContextDigest, request.localKnowledge?.digest)
        XCTAssertEqual(receipt.sourceContext?.excerpts.map(\.id), request.localKnowledge?.sourceIDs)
        XCTAssertEqual(receipt.sourceContext?.excerpts.first?.text, page.body)
        XCTAssertTrue(fixture.store.isCurrentReplyContext(receipt))
        XCTAssertFalse(fixture.store.nextReplyConversation.isEmpty)
        XCTAssertTrue(fixture.store.keptLessons.isEmpty)
        XCTAssertNil(fixture.store.evolutionFeedbackReceipt(provider: .qwen, requestID: receipt.requestID))
        XCTAssertTrue(fixture.store.evolution.usefulReceipts.isEmpty)

        fixture.store.beginLessonCorrection(for: .qwen)
        var draft = try XCTUnwrap(fixture.store.lessonDraft)
        XCTAssertEqual(draft.taskScope, .conversation)
        draft.topic = "Attribution"; draft.text = "Keep claims linked to their source passages."
        var unsupported = draft; unsupported.taskScope = .documentQuestion
        XCTAssertFalse(fixture.store.keepLesson(unsupported))
        XCTAssertTrue(fixture.store.keepLesson(draft), fixture.store.lessonMessage)
        let lesson = try XCTUnwrap(fixture.store.keptLessons.first)
        XCTAssertEqual(lesson.origin?.knowledgePages, [page.binding])
        XCTAssertEqual(lesson.taskScope, .conversation)
        XCTAssertEqual(try NativePreferenceDocument.decode(Data(contentsOf: fixture.preference)).lessons, [lesson])
        XCTAssertTrue(fixture.store.matchingLessons(question: "Explain", taskScope: .documentQuestion).isEmpty)
        fixture.store.withdrawKnowledgePage(page)
        XCTAssertFalse(fixture.store.isCurrentReplyContext(receipt))
        XCTAssertTrue(fixture.store.nextReplyConversation.isEmpty)
        XCTAssertTrue(fixture.store.nextReplyLessons.isEmpty)
        XCTAssertNotNil(fixture.store.selectedKnowledgePageIssue)
        XCTAssertEqual(fixture.store.sharedText, original)
        XCTAssertEqual(fixture.external.calls, 0)
    }

    func testExternalRoutesAndFallbackCannotSendPageContext() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        fixture.store.useKnowledgePageInChat(try fixture.page())
        fixture.store.prompt = "Explain this claim."
        for route in [AssistantRoute.codex, .compare] {
            fixture.store.setAssistantRoute(route)
            XCTAssertNotNil(fixture.store.nextAssistantBlockedReason)
            fixture.store.submit()
            XCTAssertFalse(fixture.store.isWorking)
        }
        XCTAssertEqual(fixture.local.calls, 0)
        XCTAssertEqual(fixture.external.calls, 0)
        fixture.store.setAssistantRoute(.native)
        XCTAssertNotNil(fixture.store.nextAssistantFallbackBlockedReason)
        fixture.store.submit()
        try await fixture.wait { fixture.local.request != nil }
        fixture.local.fail()
        try await fixture.wait { !fixture.store.isWorking }
        XCTAssertNotEqual(fixture.store.compareResults[.qwen]?.state, .complete)
        XCTAssertEqual(fixture.external.calls, 0)
    }

    func testExternalPageWithdrawalDiscardsInflightOutputAndBlocksReuse() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let page = try fixture.page()
        fixture.store.useKnowledgePageInChat(page)
        fixture.store.setLocalConversationEnabled(true)
        fixture.store.prompt = "Explain the current page."
        fixture.store.submit()
        try await fixture.wait { fixture.local.request != nil }
        let other = ReadingSourceLibrary(url: fixture.preference.deletingPathExtension().appendingPathExtension("reading-sources.json"))
        _ = try other.withdrawKnowledgePage(id: page.id, expectedRevision: page.revision)
        fixture.local.complete()
        try await fixture.wait { !fixture.store.isWorking }
        XCTAssertNotEqual(fixture.store.compareResults[.qwen]?.state, .complete)
        XCTAssertFalse(fixture.store.compareResults[.qwen]?.text.contains("Synthetic local answer") ?? false)
        XCTAssertTrue(fixture.store.nextReplyConversation.isEmpty)
        XCTAssertNotNil(fixture.store.selectedKnowledgePageIssue)
        fixture.store.submit()
        XCTAssertEqual(fixture.local.calls, 1)
        XCTAssertEqual(fixture.store.selectedKnowledgePages, [page.binding], "No silent upgrade to another revision.")
        XCTAssertEqual(fixture.external.calls, 0)
    }

    func testPageDerivedLessonsRespectDependencyCapacityBeforeDispatch() throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        for index in 0..<5 {
            let page = try fixture.page()
            fixture.store.beginLessonCorrection()
            var draft = try XCTUnwrap(fixture.store.lessonDraft)
            draft.topic = "Context \(index)"; draft.text = "Check the source behind this claim."
            draft.taskScope = .conversation
            draft.origin = LessonOrigin(requestID: UUID().uuidString, inputDigest: String(repeating: "a", count: 64),
                readingSources: page.anchors.map(\.source), knowledgePages: [page.binding])
            XCTAssertTrue(fixture.store.keepLesson(draft), fixture.store.lessonMessage)
        }
        XCTAssertEqual(fixture.store.keptLessons.count, 5)
        XCTAssertEqual(fixture.store.nextReplyLessons.count, 4)
        XCTAssertNotNil(fixture.store.nextReplyKnowledgeOmissionMessage)
        XCTAssertNotNil(fixture.store.nextAssistantFallbackBlockedReason)
        XCTAssertEqual(fixture.local.calls, 0)
    }

    @MainActor
    private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-knowledge-chat-\(UUID())")
        let local = KnowledgeChatClient()
        let external = KnowledgeChatClient()
        var preference: URL { directory.appendingPathComponent("preferences.json") }
        lazy var store = CompanionStore(preferenceURL: preference, assistant: local,
            assistantFactory: { [local, external] provider, _ in provider == .qwen ? local : external },
            allowsPlay: false, tokenSteward: TokenStewardStore())
        func page() throws -> KnowledgePage {
            let source = try store.readingSources.keep(title: "Source notes", text: "Evidence supports inspection, not automatic acceptance.")
            let anchor = try store.readingSources.makeAnchor(sourceID: source.id, range: NSRange(location: 0, length: source.text.utf16.count))
            let page = try store.readingSources.saveKnowledgePage(title: "Attribution", body: "Keep the supporting passage beside a claim.", kind: .claim, anchors: [anchor])
            return try store.readingSources.reviewKnowledgePage(id: page.id, expectedRevision: page.revision)
        }
        func wait(_ condition: @MainActor () -> Bool) async throws {
            for _ in 0..<400 {
                if condition() { return }
                try await Task.sleep(for: .milliseconds(5))
            }
            XCTFail("Timed out: \(store.status)")
            throw AssistantFailure.timedOut
        }
        func clean() {
            store.cancelWork(); store.disconnectAssistant(); local.resolve(); external.resolve()
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

@MainActor
private final class KnowledgeChatClient: AssistantClient {
    var request: AssistantRequest?
    var calls = 0
    private var handler: (@MainActor (AssistantEvent) -> Void)?
    private var continuation: CheckedContinuation<Void, Error>?
    func connect() async throws {}
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; self.request = request; handler = onEvent
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func complete() { handler?(.text("Synthetic local answer with attributable context.")); resolve() }
    func fail() { let pending = continuation; continuation = nil; pending?.resume(throwing: AssistantFailure.timedOut) }
    func resolve() { let pending = continuation; continuation = nil; pending?.resume() }
}
