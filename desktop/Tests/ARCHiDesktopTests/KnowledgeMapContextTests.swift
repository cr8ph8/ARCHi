import Foundation
import XCTest
@testable import ARCHiDesktop

/// Preparation only: no model, network or provider connection is required.
@MainActor
final class KnowledgeMapContextTests: XCTestCase {
    func testPrepareOnMapPreservesDraftAndDocumentWithExactLocalContextWithoutWriting() throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let page = try fixture.page()
        fixture.store.share(text: "Private working document stays here.", name: "working.txt")
        fixture.store.selectText(range: NSRange(location: 0, length: 7), sourceRevision: fixture.store.sourceRevision)
        fixture.store.preparePassageRevision()
        fixture.store.prompt = "My unsent question about this page."
        fixture.store.setAssistantRoute(.codex)
        fixture.store.openMemoryMap()
        let originalDocument = fixture.store.sharedText
        let originalPrompt = fixture.store.prompt
        let files = try fixture.files()

        XCTAssertTrue(fixture.store.useKnowledgePageInChat(page, openAssistant: false))

        XCTAssertEqual(fixture.store.section, .nodeLab)
        XCTAssertEqual(fixture.store.prompt, originalPrompt)
        XCTAssertEqual(fixture.store.sharedText, originalDocument)
        XCTAssertFalse(fixture.store.requestsRevision)
        XCTAssertEqual(fixture.store.selectedKnowledgePages, [page.binding])
        XCTAssertEqual(fixture.store.currentKnowledgeContext?.bindings, [page.binding])
        XCTAssertEqual(fixture.store.currentKnowledgeContext?.pages, [page])
        XCTAssertEqual(fixture.store.route, .automatic)
        XCTAssertEqual(fixture.store.assistantProvider, .qwen)
        XCTAssertNotNil(fixture.store.nextAssistantFallbackBlockedReason)
        XCTAssertTrue(fixture.store.knowledgePageMessage?.contains("not sent") == true)
        XCTAssertFalse(fixture.store.isWorking)
        XCTAssertEqual(fixture.client.calls, 0)
        XCTAssertEqual(try fixture.files(), files, "Preparing local context must not write profile or library files.")
    }

    func testDefaultPreparationStillOpensAssistant() throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let page = try fixture.page()
        fixture.store.openMemoryMap()

        XCTAssertTrue(fixture.store.useKnowledgePageInChat(page))

        XCTAssertEqual(fixture.store.section, .assistant)
        XCTAssertEqual(fixture.store.selectedKnowledgePages, [page.binding])
        XCTAssertEqual(fixture.client.calls, 0)
    }

    func testOldPageAfterRevisionIsRefusedWithoutSubstitution() throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let page = try fixture.page()
        let revised = try fixture.store.readingSources.saveKnowledgePage(id: page.id,
            expectedRevision: page.revision, title: page.title, body: "A revised claim.",
            kind: page.kind, anchors: page.anchors)
        let current = try fixture.store.readingSources.reviewKnowledgePage(id: revised.id,
            expectedRevision: revised.revision)
        XCTAssertNotEqual(current.binding, page.binding)
        fixture.store.openMemoryMap()
        fixture.store.prompt = "Keep this unsent draft."
        let files = try fixture.files()

        XCTAssertFalse(fixture.store.useKnowledgePageInChat(page, openAssistant: false))

        XCTAssertTrue(fixture.store.selectedKnowledgePages.isEmpty)
        XCTAssertNil(fixture.store.currentKnowledgeContext)
        XCTAssertTrue(fixture.store.knowledgePageMessage?.contains("Historical version") == true)
        XCTAssertEqual(fixture.store.section, .nodeLab)
        XCTAssertEqual(fixture.store.prompt, "Keep this unsent draft.")
        XCTAssertEqual(fixture.client.calls, 0)
        XCTAssertEqual(try fixture.files(), files)
    }

    func testWithdrawnPageIsRefusedWithoutAttaching() throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let page = try fixture.page()
        let withdrawn = try fixture.store.readingSources.withdrawKnowledgePage(id: page.id,
            expectedRevision: page.revision)
        fixture.store.openMemoryMap()
        let files = try fixture.files()

        XCTAssertFalse(fixture.store.useKnowledgePageInChat(withdrawn, openAssistant: false))

        XCTAssertTrue(fixture.store.selectedKnowledgePages.isEmpty)
        XCTAssertTrue(fixture.store.knowledgePageMessage?.contains("withdrew") == true)
        XCTAssertEqual(fixture.store.section, .nodeLab)
        XCTAssertEqual(fixture.client.calls, 0)
        XCTAssertEqual(try fixture.files(), files)
    }

    func testChangedSupportingSourceIsRefusedWithoutReplacingExistingSelection() throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let retained = try fixture.page()
        let changed = try fixture.page()
        fixture.store.openMemoryMap()
        XCTAssertTrue(fixture.store.useKnowledgePageInChat(retained, openAssistant: false))
        let sourceID = try XCTUnwrap(changed.anchors.first?.source.id)
        try fixture.store.readingSources.replace(id: sourceID, title: "Changed source", text: "New source version.")
        let files = try fixture.files()

        XCTAssertFalse(fixture.store.useKnowledgePageInChat(changed, openAssistant: false))

        XCTAssertEqual(fixture.store.selectedKnowledgePages, [retained.binding])
        XCTAssertTrue(fixture.store.knowledgePageMessage?.contains("supporting source changed") == true)
        XCTAssertEqual(fixture.store.section, .nodeLab)
        XCTAssertEqual(fixture.client.calls, 0)
        XCTAssertEqual(try fixture.files(), files)
    }

    func testExternalLibraryChangeIsRefusedWithoutAttaching() throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let page = try fixture.page()
        let other = ReadingSourceLibrary(url: fixture.preference.deletingPathExtension().appendingPathExtension("reading-sources.json"))
        _ = try other.withdrawKnowledgePage(id: page.id, expectedRevision: page.revision)
        fixture.store.openMemoryMap()
        let files = try fixture.files()

        XCTAssertFalse(fixture.store.useKnowledgePageInChat(page, openAssistant: false))

        XCTAssertFalse(fixture.store.readingSources.isCurrentOnDisk)
        XCTAssertTrue(fixture.store.selectedKnowledgePages.isEmpty)
        XCTAssertTrue(fixture.store.knowledgePageMessage?.contains("library changed") == true)
        XCTAssertEqual(fixture.store.section, .nodeLab)
        XCTAssertEqual(fixture.client.calls, 0)
        XCTAssertEqual(try fixture.files(), files)
    }

    func testFifthPageIsRefusedWithoutChangingFourSelectedBindings() throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let pages = try (0..<5).map { _ in try fixture.page() }
        fixture.store.openMemoryMap()
        for page in pages.prefix(4) {
            XCTAssertTrue(fixture.store.useKnowledgePageInChat(page, openAssistant: false))
        }
        let selected = fixture.store.selectedKnowledgePages

        XCTAssertFalse(fixture.store.useKnowledgePageInChat(pages[4], openAssistant: false))

        XCTAssertEqual(fixture.store.selectedKnowledgePages, selected)
        XCTAssertEqual(selected, pages.prefix(4).map(\.binding))
        XCTAssertEqual(fixture.store.knowledgePageMessage, "Use up to four pages at once.")
        XCTAssertEqual(fixture.store.section, .nodeLab)
        XCTAssertEqual(fixture.client.calls, 0)
    }

    @MainActor
    private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-map-context-\(UUID())")
        let client = KnowledgeMapNoModelClient()
        var preference: URL { directory.appendingPathComponent("preferences.json") }
        lazy var store = CompanionStore(preferenceURL: preference, assistant: client,
            assistantFactory: { [client] _, _ in client }, allowsPlay: false, tokenSteward: TokenStewardStore())

        func page() throws -> KnowledgePage {
            let source = try store.readingSources.keep(title: "Source notes", text: "Evidence supports inspection, not automatic acceptance.")
            let anchor = try store.readingSources.makeAnchor(sourceID: source.id,
                range: NSRange(location: 0, length: source.text.utf16.count))
            let draft = try store.readingSources.saveKnowledgePage(title: "Attribution",
                body: "Keep the supporting passage beside a claim.", kind: .claim, anchors: [anchor])
            return try store.readingSources.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        }

        func files() throws -> [String: Data] {
            guard let enumerator = FileManager.default.enumerator(at: directory,
                includingPropertiesForKeys: [.isRegularFileKey]) else { return [:] }
            var result: [String: Data] = [:]
            for case let url as URL in enumerator {
                if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                    result[url.path] = try Data(contentsOf: url)
                }
            }
            return result
        }

        func clean() {
            store.cancelWork()
            store.disconnectAssistant()
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

@MainActor
private final class KnowledgeMapNoModelClient: AssistantClient {
    var calls = 0
    func connect() async throws {}
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1
        XCTFail("Preparing map context must not dispatch a model.")
    }
}
