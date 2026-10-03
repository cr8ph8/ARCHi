import Foundation
import XCTest
@testable import ARCHiDesktop

/// Disposable production owners only. No generation, provider connection or
/// personal history is created by these search/preparation checks.
@MainActor
final class DocumentMethodPreparationTests: XCTestCase {
    func testFinderRequiresMatchingChecksAndCurrentSourcesWithoutChangingDraft() throws {
        let f = try Fixture(); defer { f.clean() }
        let matching = try f.method(title: "Status summary", instruction: "Summarize project status.")
        _ = try f.method(title: "Status details", instruction: "Summarize project status.", shorter: true)
        let result = try f.store.findDocumentMethods(query: "project status")
        XCTAssertEqual(result.hits.map(\.procedure.binding), [matching.binding])
        XCTAssertEqual(f.store.prompt, Fixture.draft)
        XCTAssertNil(f.store.preparedDocumentProcedure)
        f.store.withdrawKnowledgePage(f.page)
        XCTAssertTrue(try f.store.findDocumentMethods(query: "project status").hits.isEmpty)
        XCTAssertTrue(f.store.documentWork.records.isEmpty)
        XCTAssertEqual(f.client.calls, 0)
    }

    func testPreviewIsReadOnlyAndExplicitUseReplacesOnlyTheDraft() throws {
        let f = try Fixture(); defer { f.clean() }
        let method = try f.method()
        let before = f.store.sharedText
        let preview = try XCTUnwrap(f.store.previewDocumentMethod(method.binding))
        XCTAssertEqual(preview.originalPrompt, Fixture.draft)
        XCTAssertEqual(f.store.prompt, Fixture.draft)
        XCTAssertNil(f.store.preparedDocumentProcedure)
        XCTAssertNil(f.store.documentMethodPreviewIssue(preview))
        XCTAssertTrue(f.store.applyDocumentMethodPreview(preview))
        XCTAssertEqual(f.store.prompt, method.instruction)
        XCTAssertEqual(f.store.preparedDocumentProcedure, method.binding)
        XCTAssertEqual(f.store.sharedText, before)
        XCTAssertTrue(f.store.documentWork.records.isEmpty)
        XCTAssertEqual(f.client.calls, 0)
        XCTAssertFalse(f.store.applyDocumentMethodPreview(preview), "A replaced draft retires the old preview.")
    }

    func testChangedDraftPassageAndRequirementsRejectOldPreview() throws {
        let f = try Fixture(); defer { f.clean() }
        let method = try f.method()
        let preview = try XCTUnwrap(f.store.previewDocumentMethod(method.binding))
        f.store.prompt = "My newer instruction"
        XCTAssertFalse(f.store.applyDocumentMethodPreview(preview))
        XCTAssertEqual(f.store.prompt, "My newer instruction")
        f.store.prompt = Fixture.draft
        f.store.documentRequirements.mustBeShorter = true
        XCTAssertFalse(f.store.applyDocumentMethodPreview(preview))
        f.store.documentRequirements.mustBeShorter = false
        f.store.selectText(range: NSRange(location: 0, length: 7), sourceRevision: f.store.sourceRevision)
        XCTAssertFalse(f.store.applyDocumentMethodPreview(preview))
        f.selectPassage()
        f.store.share(text: Fixture.passage + " New context.", name: "example.txt")
        XCTAssertFalse(f.store.applyDocumentMethodPreview(preview))
        XCTAssertNil(f.store.preparedDocumentProcedure)
        XCTAssertEqual(f.client.calls, 0)
    }

    func testWithdrawalAndExternalArchiveChangesInvalidatePreview() throws {
        let f = try Fixture(); defer { f.clean() }
        let method = try f.method()
        let preview = try XCTUnwrap(f.store.previewDocumentMethod(method.binding))
        let outside = DocumentProcedureLibrary(url: f.procedureURL)
        try outside.withdraw(binding: method.binding)
        XCTAssertThrowsError(try f.store.findDocumentMethods(query: "status"))
        XCTAssertFalse(f.store.applyDocumentMethodPreview(preview))
        XCTAssertEqual(f.store.prompt, Fixture.draft)
        XCTAssertNil(f.store.preparedDocumentProcedure)
    }

    func testReviewedSourceWithdrawalRetiresInstructionPreview() throws {
        let f = try Fixture(); defer { f.clean() }
        let method = try f.method()
        let preview = try XCTUnwrap(f.store.previewDocumentMethod(method.binding))
        f.store.withdrawKnowledgePage(f.page)
        XCTAssertNotNil(f.store.documentMethodPreviewIssue(preview))
        XCTAssertFalse(f.store.applyDocumentMethodPreview(preview))
        XCTAssertEqual(f.store.prompt, Fixture.draft)
    }

    func testSavedMethodsSurviveRestartButOldPreviewCannotCrossOwners() throws {
        let f = try Fixture(); defer { f.clean() }
        let method = try f.method()
        let preview = try XCTUnwrap(f.store.previewDocumentMethod(method.binding))
        let bytes = try Data(contentsOf: f.procedureURL)
        let reopened = f.makeStore()
        defer { reopened.disconnectAssistant() }
        reopened.share(text: Fixture.passage, name: "example.txt")
        reopened.selectText(range: NSRange(location: 0, length: Fixture.passage.utf16.count), sourceRevision: reopened.sourceRevision)
        reopened.requestsRevision = true
        reopened.prompt = Fixture.draft
        XCTAssertEqual(try reopened.findDocumentMethods(query: "status").hits.map(\.procedure.binding), [method.binding])
        XCTAssertFalse(reopened.applyDocumentMethodPreview(preview))
        XCTAssertEqual(reopened.prompt, Fixture.draft)
        XCTAssertNotNil(reopened.previewDocumentMethod(method.binding))
        XCTAssertEqual(try Data(contentsOf: f.procedureURL), bytes)
    }

    func testGenericNextStepNeverChoosesUnrelatedHelpfulMethodAndPreservesExplicitChoice() throws {
        let f = try Fixture(); defer { f.clean() }
        let method = try f.method(title: "Poetry", instruction: "Turn this passage into rhyming poetry.")
        var record = f.helpfulRecord(method)
        let feedback = record.feedback
        record.feedback = nil; record.state = .applying
        try f.store.documentWork.save(record)
        record.state = .applied; record.feedback = feedback
        try f.store.documentWork.save(record)
        XCTAssertEqual(f.store.outcomes(for: method)?.helpful, 1)
        XCTAssertEqual(f.store.documentQ2EDecision.lane, .retain)
        f.store.prompt = ""
        f.store.prepareAdaptiveDocumentWork()
        XCTAssertNil(f.store.preparedDocumentProcedure)
        XCTAssertNotEqual(f.store.prompt, method.instruction)
        XCTAssertFalse(f.store.prompt.isEmpty)
        let preview = try XCTUnwrap(f.store.previewDocumentMethod(method.binding))
        XCTAssertTrue(f.store.applyDocumentMethodPreview(preview))
        f.store.prepareAdaptiveDocumentWork()
        XCTAssertEqual(f.store.preparedDocumentProcedure, method.binding)
        XCTAssertEqual(f.store.prompt, method.instruction)
        f.store.withdrawKnowledgePage(f.page)
        f.store.prepareAdaptiveDocumentWork()
        XCTAssertEqual(f.store.preparedDocumentProcedure, method.binding,
                       "Generic preparation must not detach a stale instruction from its source restrictions.")
        XCTAssertNotNil(f.store.documentProcedureUnavailable(method.binding))
        XCTAssertEqual(f.client.calls, 0)
    }

    @MainActor private final class Fixture {
        static let passage = "Project status: a small example to review."
        static let draft = "Explain the next project milestone clearly."
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-method-finder-\(UUID())")
        let client = NoCallsClient()
        var preference: URL { directory.appendingPathComponent("preferences.json") }
        var procedureURL: URL { preference.deletingPathExtension().appendingPathExtension("document-procedures.json") }
        lazy var store = makeStore()
        var page: KnowledgePage!

        init() throws {
            let source = try store.readingSources.keep(title: "Example guidance", text: "Describe project status and next steps clearly.")
            let anchor = try store.readingSources.makeAnchor(sourceID: source.id,
                range: NSRange(location: 0, length: source.text.utf16.count))
            let draft = try store.readingSources.saveKnowledgePage(title: "Status guidance", body: "A synthetic source for method preparation.", kind: .concept, anchors: [anchor])
            page = try store.readingSources.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
            store.share(text: Self.passage, name: "example.txt")
            selectPassage()
            store.requestsRevision = true
            store.prompt = Self.draft
        }
        func makeStore() -> CompanionStore {
            CompanionStore(preferenceURL: preference, assistant: client,
                assistantFactory: { [client] _, _ in client }, allowsPlay: false)
        }
        func selectPassage() {
            store.selectText(range: NSRange(location: 0, length: Self.passage.utf16.count), sourceRevision: store.sourceRevision)
        }
        func method(title: String = "Status summary", instruction: String = "Summarize project status and next steps.", shorter: Bool = false) throws -> DocumentProcedure {
            try store.documentProcedures.keepCandidate(from: page, title: title, instruction: instruction,
                requirements: .init(mustBeShorter: shorter, preserveNumbersAndLinks: true),
                knowledgeIsCurrent: { [store] in store.knowledgeDependenciesAreCurrent([$0]) })
        }
        func helpfulRecord(_ method: DocumentProcedure) -> DocumentWorkRecord {
            let request = UUID().uuidString, digest = String(repeating: "a", count: 64)
            let created = Date().addingTimeInterval(-60)
            return DocumentWorkRecord(id: request + "-Qwen", requestID: request, provider: "Qwen",
                targetID: UUID().uuidString, sourceDigest: digest, sourceRevision: 1,
                selectionStart: 0, selectionLength: 12, preserveNumbersAndLinks: true,
                createdAt: created, updatedAt: created.addingTimeInterval(20), state: .applied,
                proposedDigest: digest, expectedAfterDigest: digest, actualAfterDigest: digest, afterRevision: 2,
                checks: [.init(id: "source", title: "Exact source", passed: true)],
                learning: .init(requestBinding: .init(inputDigest: digest, contextDigest: digest), suppliedLessons: []),
                feedback: .init(revision: 1, verdict: .helpful, recordedAt: created.addingTimeInterval(10)), procedureUse: method.binding)
        }
        func clean() { store.disconnectAssistant(); try? FileManager.default.removeItem(at: directory) }
    }

    @MainActor private final class NoCallsClient: AssistantClient {
        private(set) var calls = 0
        func connect() async throws { XCTFail("Search must not connect.") }
        func disconnect() {}
        func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
            calls += 1; XCTFail("Search or preparation must not generate.")
            throw AssistantFailure.timedOut
        }
    }
}
