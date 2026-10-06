import Foundation
import XCTest
@testable import ARCHiDesktop

@MainActor
final class KnowledgePageIntegrationTests: XCTestCase {
    func testAuthoredPageReviewNavigationAndSourceWithdrawalShareOneOwner() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-page-integration-\(UUID())")
        let client = KnowledgePageNoModelClient()
        let store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"),
            assistant: client, allowsPlay: false, tokenSteward: TokenStewardStore())
        defer { store.disconnectAssistant(); try? FileManager.default.removeItem(at: directory) }
        let source = try store.readingSources.keep(title: "Mechanism notes", text: "A source supports inspection, not automatic acceptance.")
        let anchor = try store.readingSources.makeAnchor(sourceID: source.id, range: NSRange(location: 0, length: source.text.utf16.count))
        let beforeLessons = store.keptLessons
        let beforeReceipts = store.evolution.usefulReceipts
        store.beginKnowledgePage()
        XCTAssertNotNil(store.knowledgePageDraft)
        XCTAssertEqual(store.section, .memory)
        XCTAssertTrue(store.saveKnowledgePage(prior: nil, title: "Inspect before accepting", body: "Keep attribution with a claim.", kind: .concept, anchors: [anchor]))
        XCTAssertNil(store.knowledgePageDraft)
        let draft = try XCTUnwrap(store.readingSources.latestKnowledgePages.first)
        store.reviewKnowledgePage(draft)
        let page = try XCTUnwrap(store.readingSources.latestKnowledgePages.first)
        XCTAssertEqual(page.state, .reviewed)
        XCTAssertNil(store.readingSources.availability(of: page))
        let graph = store.companionGraphSnapshot()
        let node = try XCTUnwrap(graph.nodes.first { $0.kind == .knowledge })
        XCTAssertTrue(graph.edges.contains { $0.source == node.id && $0.label == "source passage" })
        store.openGraphTarget(try XCTUnwrap(node.target))
        XCTAssertEqual(store.selectedKnowledgePageID, page.id)
        XCTAssertEqual(store.section, .memory)
        try store.readingSources.forget(id: source.id)
        XCTAssertNotNil(store.readingSources.availability(of: page))
        XCTAssertNil(store.readingSources.quote(for: anchor))
        XCTAssertTrue(store.companionGraphSnapshot().nodes.contains { $0.title == "Unavailable source version" })
        XCTAssertEqual(store.keptLessons, beforeLessons)
        XCTAssertEqual(store.evolution.usefulReceipts, beforeReceipts)
        XCTAssertEqual(client.calls, 0)
    }

    func testExternalPageChangeCannotReviewStaleVersionOrDiscardOpenDraft() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-page-stale-\(UUID())")
        let preference = directory.appendingPathComponent("preferences.json")
        let client = KnowledgePageNoModelClient()
        let store = CompanionStore(preferenceURL: preference, assistant: client, allowsPlay: false, tokenSteward: TokenStewardStore())
        defer { store.disconnectAssistant(); try? FileManager.default.removeItem(at: directory) }
        let source = try store.readingSources.keep(title: "Source", text: "Evidence.")
        let anchor = try store.readingSources.makeAnchor(sourceID: source.id, range: NSRange(location: 0, length: 9))
        XCTAssertTrue(store.saveKnowledgePage(prior: nil, title: "Claim", body: "A tentative claim.", kind: .claim, anchors: [anchor]))
        let page = try XCTUnwrap(store.readingSources.latestKnowledgePages.first)
        store.beginKnowledgePage(page)
        let draftID = try XCTUnwrap(store.knowledgePageDraft?.id)
        store.section = .assistant
        XCTAssertEqual(store.section, .memory, "Navigation must preserve the editor host and its unsaved fields.")
        XCTAssertEqual(store.knowledgePageDraft?.id, draftID)
        XCTAssertNotNil(store.recoveryRestoreBlockReason)
        let other = ReadingSourceLibrary(url: preference.deletingPathExtension().appendingPathExtension("reading-sources.json"))
        _ = try other.withdrawKnowledgePage(id: page.id, expectedRevision: page.revision)
        store.reviewKnowledgePage(page)
        XCTAssertTrue(store.knowledgePageMessage?.contains("changed outside") == true)
        XCTAssertFalse(store.saveKnowledgePage(prior: page, title: "Changed", body: "More text.", kind: .claim, anchors: [anchor]))
        XCTAssertEqual(store.knowledgePageDraft?.id, draftID)
        XCTAssertEqual(other.latestKnowledgePages.first?.state, .withdrawn)
        XCTAssertEqual(client.calls, 0)
    }
}

@MainActor
private final class KnowledgePageNoModelClient: AssistantClient {
    var calls = 0
    func connect() async throws {}
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1
        XCTFail("Knowledge authoring must not dispatch a model.")
    }
}
