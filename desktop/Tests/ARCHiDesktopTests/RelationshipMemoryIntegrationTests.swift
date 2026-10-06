import Foundation
import XCTest
@testable import ARCHiDesktop

/// Disposable owners and transports that fail on any attempted invocation.
/// Preparation and manual relationship work must not connect or send anything.
@MainActor
final class RelationshipMemoryIntegrationTests: XCTestCase {
    func testPreparationUsesOnlyChosenRecordsPreservesComposerAndBlocksExternalRoutes() throws {
        let fixture = Fixture(); defer { fixture.clean() }
        let store = fixture.store
        let person = try fixture.record(title: "Alex", text: "CHOSEN_PERSON_NOTE", metadata: .init(kind: .person))
        let other = try fixture.record(title: "Alex", text: "OTHER_PERSON_SECRET", metadata: .init(kind: .person))
        let selected = try fixture.record(title: "Checklist", text: "CHOSEN_COMMITMENT_NOTE",
            metadata: .init(kind: .commitment, person: person.binding, commitmentStatus: .pending))
        _ = try fixture.record(title: "Other encounter", text: "UNSELECTED_ENCOUNTER_SECRET",
            metadata: .init(kind: .encounter, person: person.binding))
        store.share(text: "Unrelated shared copy.", name: "unrelated.txt")
        store.selectText(range: NSRange(location: 0, length: 9), sourceRevision: store.sourceRevision)
        store.prompt = "Help me prepare for my conversation."
        store.useKnowledgePageInChat(other)
        store.setAssistantRoute(.compare)
        store.requestsRevision = true
        let shared = store.sharedText, sourceRevision = store.sourceRevision
        let selection = store.textSelection, prompt = store.prompt
        let pageCount = store.readingSources.knowledgePages.count

        store.prepareRelationshipConversation(person: person, records: [selected])
        XCTAssertEqual(store.selectedKnowledgePages, [person.binding, selected.binding])
        XCTAssertEqual(store.route, .automatic)
        XCTAssertEqual(store.assistantProvider, .qwen)
        XCTAssertEqual(store.section, .assistant)
        XCTAssertFalse(store.requestsRevision)
        XCTAssertEqual(store.sharedText, shared)
        XCTAssertEqual(store.sourceName, "unrelated.txt")
        XCTAssertEqual(store.sourceRevision, sourceRevision)
        XCTAssertEqual(store.textSelection, selection)
        XCTAssertEqual(store.prompt, prompt)
        XCTAssertEqual(store.readingSources.knowledgePages.count, pageCount)
        let context = try XCTUnwrap(store.currentKnowledgeContext)
        XCTAssertEqual(context.bindings, [person.binding, selected.binding])
        let encoded = String(decoding: try JSONEncoder().encode(context.modelInput), as: UTF8.self)
        XCTAssertTrue(encoded.contains("CHOSEN_PERSON_NOTE"))
        XCTAssertTrue(encoded.contains("CHOSEN_COMMITMENT_NOTE"))
        for excluded in ["OTHER_PERSON_SECRET", "UNSELECTED_ENCOUNTER_SECRET", shared, prompt] {
            XCTAssertFalse(encoded.contains(excluded), excluded)
        }
        XCTAssertNil(store.nextAssistantBlockedReason)
        XCTAssertTrue(store.nextAssistantFallbackBlockedReason?.contains("external fallback is disabled") == true)
        fixture.assertNoRequestsOrLearning()

        for route in [AssistantRoute.codex, .compare] {
            store.setAssistantRoute(route)
            XCTAssertNotNil(store.nextAssistantBlockedReason)
            store.submit()
            XCTAssertTrue(store.status.contains("Nothing sent"))
            XCTAssertEqual(store.prompt, prompt)
            XCTAssertEqual(store.sharedText, shared)
            fixture.assertNoRequestsOrLearning()
        }
    }

    func testPersonCorrectionAndWrongPersonCannotReviveSelectedContext() throws {
        let fixture = Fixture(); defer { fixture.clean() }
        let store = fixture.store
        let person = try fixture.record(title: "Alex", text: "Workshop person note.", metadata: .init(kind: .person))
        let other = try fixture.record(title: "Alex", text: "Different person note.", metadata: .init(kind: .person))
        let encounter = try fixture.record(title: "Encounter", text: "We discussed animation.",
            metadata: .init(kind: .encounter, person: person.binding))
        store.prompt = "Prepare for the conversation."
        store.prepareRelationshipConversation(person: person, records: [encounter])
        let selected = store.selectedKnowledgePages
        XCTAssertNotNil(store.currentKnowledgeContext)
        store.prepareRelationshipConversation(person: other, records: [encounter])
        XCTAssertEqual(store.selectedKnowledgePages, selected, "An invalid request must not mix same-name identities.")
        XCTAssertTrue(store.knowledgePageMessage?.contains("current reviewed person") == true)

        XCTAssertTrue(store.saveRelationshipPage(prior: person, title: person.title,
            body: "Clarified how we met.", metadata: .init(kind: .person), anchors: person.anchors))
        XCTAssertFalse(store.knowledgeDependenciesAreCurrent(selected))
        XCTAssertNil(store.currentKnowledgeContext)
        XCTAssertNotNil(store.selectedKnowledgePageIssue)
        XCTAssertTrue(store.compareResults.isEmpty)
        XCTAssertTrue(store.nextReplyConversation.isEmpty)
        XCTAssertFalse(store.isWorking)
        store.submit()
        XCTAssertTrue(store.status.contains("Nothing sent"))
        let correction = try XCTUnwrap(store.readingSources.latestKnowledgePages.first { $0.id == person.id })
        store.reviewKnowledgePage(correction)
        let currentPerson = try XCTUnwrap(store.readingSources.latestKnowledgePages.first { $0.id == person.id })
        XCTAssertNil(store.readingSources.availability(of: currentPerson))
        XCTAssertNotNil(store.readingSources.availability(of: encounter))
        store.prepareRelationshipConversation(person: currentPerson, records: [encounter])
        XCTAssertNil(store.currentKnowledgeContext, "Reviewing a correction cannot silently rebind an old encounter.")
        fixture.assertNoRequestsOrLearning()
    }

    func testManualNoteAndEditorSaveUseExistingOwnerAndRequireSeparateReview() throws {
        let fixture = Fixture(); defer { fixture.clean() }
        let store = fixture.store
        let note = "I met Alex at the cafe\u{301}.\nMy exact words stay here."
        let initialLessons = store.keptLessons
        let initialReceipts = store.evolution.usefulReceipts
        XCTAssertTrue(store.keepRelationshipSource(title: "My encounter", text: note))
        XCTAssertTrue(store.readingSources.knowledgePages.isEmpty)
        let source = try XCTUnwrap(store.readingSources.sources.first)
        XCTAssertTrue(source.text.utf8.elementsEqual(note.utf8))
        XCTAssertFalse(store.keepRelationshipSource(title: "", text: "Rejected note"))
        XCTAssertEqual(store.readingSources.sources.count, 1)
        let anchor = try store.readingSources.makeAnchor(sourceID: source.id,
            range: NSRange(location: 0, length: source.text.utf16.count))
        store.beginRelationshipPage(.person)
        let editor = try XCTUnwrap(store.knowledgePageDraft)
        XCTAssertEqual(editor.relationshipKind, .person)
        XCTAssertNil(editor.person)
        XCTAssertEqual(store.section, .memory)
        XCTAssertFalse(store.saveRelationshipPage(prior: nil, title: "Alex", body: "The person I met.",
            metadata: .init(kind: .person), anchors: []))
        XCTAssertEqual(store.knowledgePageDraft?.id, editor.id)
        XCTAssertTrue(store.saveRelationshipPage(prior: nil, title: "Alex", body: "The person I met.",
            metadata: .init(kind: .person), anchors: [anchor]))
        XCTAssertNil(store.knowledgePageDraft)
        let draft = try XCTUnwrap(store.readingSources.latestKnowledgePages.first)
        XCTAssertEqual(draft.relationship?.kind, .person)
        XCTAssertEqual(draft.relationship?.attribution, .userReported)
        XCTAssertEqual(draft.state, .draft)
        XCTAssertNil(draft.review)
        XCTAssertNotNil(store.readingSources.availability(of: draft))
        XCTAssertEqual(ReadingSourceLibrary(url: fixture.readingURL).knowledgePages, store.readingSources.knowledgePages)
        XCTAssertEqual(store.keptLessons, initialLessons)
        XCTAssertEqual(store.evolution.usefulReceipts, initialReceipts)
        fixture.assertNoRequestsOrLearning()
    }

    @MainActor
    private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-relationships-integration-\(UUID())")
        let local = RelationshipNoRequestClient()
        let external = RelationshipNoRequestClient()
        var preference: URL { directory.appendingPathComponent("preferences.json") }
        var readingURL: URL { preference.deletingPathExtension().appendingPathExtension("reading-sources.json") }
        lazy var store = CompanionStore(preferenceURL: preference, assistant: local,
            assistantFactory: { [local, external] provider, _ in provider == .qwen ? local : external },
            allowsPlay: false, tokenSteward: TokenStewardStore())

        func record(title: String, text: String, metadata: RelationshipMemoryMetadata) throws -> KnowledgePage {
            let source = try store.readingSources.keep(title: title, text: text)
            let anchor = try store.readingSources.makeAnchor(sourceID: source.id,
                range: NSRange(location: 0, length: source.text.utf16.count))
            let draft = try store.readingSources.saveRelationshipPage(title: title, body: text,
                metadata: metadata, anchors: [anchor])
            return try store.readingSources.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        }

        func assertNoRequestsOrLearning(file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertEqual(local.connections, 0, file: file, line: line)
            XCTAssertEqual(external.connections, 0, file: file, line: line)
            XCTAssertEqual(local.calls, 0, file: file, line: line)
            XCTAssertEqual(external.calls, 0, file: file, line: line)
            XCTAssertTrue(store.tokenSteward.tasks.isEmpty, file: file, line: line)
            XCTAssertTrue(store.keptLessons.isEmpty, file: file, line: line)
            XCTAssertTrue(store.evolution.usefulReceipts.isEmpty, file: file, line: line)
            XCTAssertTrue(store.documentProcedures.latestProcedures.isEmpty, file: file, line: line)
            XCTAssertTrue(store.documentWork.records.isEmpty, file: file, line: line)
        }

        func clean() {
            store.cancelWork(); store.disconnectAssistant()
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

@MainActor
private final class RelationshipNoRequestClient: AssistantClient {
    var calls = 0
    var connections = 0
    func connect() async throws { connections += 1; XCTFail("Manual relationship work must not connect a provider.") }
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1
        XCTFail("Manual relationship work must not dispatch a provider.")
    }
}
