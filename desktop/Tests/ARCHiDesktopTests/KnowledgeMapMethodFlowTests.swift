import Foundation
import XCTest
@testable import ARCHiDesktop

/// Disposable, explicitly scripted fixtures only. These exercise native owners,
/// not a model, personal profile, or Patrick's review of an actual outcome.
@MainActor
final class KnowledgeMapMethodFlowTests: XCTestCase {
    func testCurrentReviewedConceptSavesExactCandidateWithoutDispatchOrOutcome() throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let page = try fixture.page()
        let node = try fixture.node(for: page)
        let beforeOpening = try fixture.files()

        let selection = try XCTUnwrap(fixture.store.beginKnowledgeMapMethod(node: node))
        XCTAssertEqual(fixture.store.knowledgePageForMethodSelection(selection), page)
        XCTAssertEqual(try fixture.files(), beforeOpening, "Opening authoring must not save anything.")
        let binding = try XCTUnwrap(fixture.store.keepKnowledgeMapMethod(selection,
            title: "Attribute the claim", instruction: "Keep the source attribution beside each claim.",
            requirements: .init()))
        let method = try XCTUnwrap(fixture.store.documentProcedures.procedure(matching: binding))

        XCTAssertEqual(method.knowledgeOrigin, page.binding)
        XCTAssertEqual(method.revision, 1)
        XCTAssertTrue(method.originRecordID.isEmpty)
        XCTAssertTrue(method.originFeedbackID.isEmpty)
        XCTAssertEqual(fixture.store.readingSources.latestKnowledgePages, [page], "Saving cannot create another page review.")
        XCTAssertEqual(fixture.store.memoryMapSnapshot().nodes.first { $0.id == DocumentMethodGraph.nodeID(binding) }?.target,
                       .documentMethod(binding))
        XCTAssertNil(fixture.store.preparedDocumentProcedure)
        fixture.assertNoWorkOrCredit()

        let reopened = fixture.reopen()
        defer { reopened.disconnectAssistant() }
        XCTAssertEqual(reopened.documentProcedures.procedure(matching: binding), method)
    }

    func testChangedConceptOrSupportingSourceRejectsCapturedSelectionWithoutSubstitution() throws {
        for change in ["concept", "source", "external source"] {
            let fixture = Fixture()
            defer { fixture.clean() }
            let page = try fixture.page()
            let node = try fixture.node(for: page)
            let selection = try XCTUnwrap(fixture.store.beginKnowledgeMapMethod(node: node))
            let sourceID = try XCTUnwrap(page.anchors.first?.source.id)
            if change == "concept" {
                let draft = try fixture.store.readingSources.saveKnowledgePage(id: page.id,
                    expectedRevision: page.revision, title: page.title, body: "A changed interpretation.",
                    kind: .concept, anchors: page.anchors)
                _ = try fixture.store.readingSources.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
            } else if change == "source" {
                try fixture.store.readingSources.replace(id: sourceID, title: "Changed fixture source", text: "Different support.")
            } else {
                let other = ReadingSourceLibrary(url: fixture.sourceURL)
                try other.replace(id: sourceID, title: "External fixture correction", text: "Different support.")
            }
            let beforeSaving = try fixture.files()

            XCTAssertNil(fixture.store.knowledgePageForMethodSelection(selection), change)
            XCTAssertNil(fixture.store.beginKnowledgeMapMethod(node: node), change)
            XCTAssertNil(fixture.store.keepKnowledgeMapMethod(selection, title: "Stale candidate",
                instruction: "This must not be saved.", requirements: .init()), change)
            XCTAssertTrue(fixture.store.documentProcedures.procedures.isEmpty, change)
            XCTAssertEqual(try fixture.files(), beforeSaving, change)
            fixture.assertNoWorkOrCredit()
        }
    }

    func testSelectionCannotCrossReopenedProfileOwners() throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let page = try fixture.page()
        let node = try fixture.node(for: page)
        let selection = try XCTUnwrap(fixture.store.beginKnowledgeMapMethod(node: node))
        let reopened = fixture.reopen()
        defer { reopened.disconnectAssistant() }
        let before = try fixture.files()

        XCTAssertEqual(reopened.readingSources.latestKnowledgePages, [page])
        XCTAssertNil(reopened.knowledgePageForMethodSelection(selection), "Identical bytes do not make an old owner context current.")
        XCTAssertNil(reopened.keepKnowledgeMapMethod(selection, title: "Wrong owner",
            instruction: "This must not be saved.", requirements: .init()))
        XCTAssertTrue(reopened.documentProcedures.procedures.isEmpty)
        XCTAssertEqual(try fixture.files(), before)
        XCTAssertNotNil(reopened.beginKnowledgeMapMethod(node: node), "A new visit may capture the reopened owners.")
        fixture.assertNoWorkOrCredit()
    }

    func testSaveCallbackRunsOnlyAfterSuccessfulOwnerSaveWithExactBinding() throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let page = try fixture.page()
        var callbacks: [DocumentProcedureUse] = []

        XCTAssertFalse(fixture.store.keepKnowledgeProcedure(page: page, title: "",
            instruction: "Keep attribution.", requirements: .init(), onSaved: { callbacks.append($0) }))
        XCTAssertTrue(callbacks.isEmpty)
        XCTAssertTrue(fixture.store.documentProcedures.procedures.isEmpty)

        XCTAssertTrue(fixture.store.keepKnowledgeProcedure(page: page, title: "Attribute the claim",
            instruction: "Keep attribution.", requirements: .init(), onSaved: { binding in
                XCTAssertNotNil(fixture.store.documentProcedures.procedure(matching: binding))
                callbacks.append(binding)
            }))
        let method = try XCTUnwrap(fixture.store.documentProcedures.latestProcedures.first)
        XCTAssertEqual(callbacks, [method.binding])

        let other = DocumentProcedureLibrary(url: fixture.methodURL)
        try other.withdraw(binding: method.binding)
        let beforeFailedSave = try fixture.files()
        XCTAssertFalse(fixture.store.keepKnowledgeProcedure(page: page, title: "Another candidate",
            instruction: "Keep the qualification too.", requirements: .init(), onSaved: { callbacks.append($0) }))
        XCTAssertEqual(callbacks, [method.binding], "A changed on-disk method owner must not report a successful save.")
        XCTAssertEqual(try fixture.files(), beforeFailedSave)
        fixture.assertNoWorkOrCredit()
    }

    func testReturnToMapKeepsHistoricalAndWithdrawnVersionsExactAndRejectsMissingVersion() throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let page = try fixture.page()
        let first = try fixture.method(from: page)
        let support = try fixture.scriptedAppliedRecord(using: first.binding)
        let second = try fixture.store.documentProcedures.revise(binding: first.binding, title: first.title,
            instruction: "Keep the source attribution and qualification beside each claim.",
            changeNote: "Retain the qualification.", from: support, records: fixture.store.documentWork.records,
            knowledgeIsCurrent: { fixture.store.knowledgeDependenciesAreCurrent([$0]) })
        try fixture.store.documentProcedures.withdraw(binding: second.binding)
        let beforeNavigation = try fixture.files()

        XCTAssertTrue(fixture.store.openDocumentMethodMap(first.binding))
        XCTAssertEqual(fixture.store.section, .nodeLab)
        XCTAssertEqual(fixture.store.selectedGraphNodeID, DocumentMethodGraph.nodeID(first.binding))
        XCTAssertTrue(fixture.store.openDocumentMethodMap(second.binding), "Withdrawal affects reuse, not retained navigation.")
        XCTAssertEqual(fixture.store.selectedGraphNodeID, DocumentMethodGraph.nodeID(second.binding))

        let missing = DocumentProcedureUse(id: first.id, revision: first.revision, digest: String(repeating: "f", count: 64))
        XCTAssertFalse(fixture.store.openDocumentMethodMap(missing))
        XCTAssertEqual(fixture.store.selectedGraphNodeID, DocumentMethodGraph.nodeID(second.binding), "Failure cannot select another version.")
        XCTAssertNotNil(fixture.store.workspaceRoutingNotice)
        XCTAssertNil(fixture.store.preparedDocumentProcedure)
        XCTAssertEqual(try fixture.files(), beforeNavigation)
        XCTAssertEqual(fixture.client.calls, 0)
    }

    func testCreatingAndOpeningAnotherMethodPreservesExistingDraftAndWorkingCopy() throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let page = try fixture.page()
        let existing = try fixture.method(from: page)
        let text = "Local sample: Keep the 3 qualifications and https://example.invalid/source beside the claim."
        fixture.store.share(text: text, name: "local-method-work-sample.txt")
        fixture.store.selectText(range: NSRange(location: 0, length: text.utf16.count),
            sourceRevision: fixture.store.sourceRevision)
        fixture.store.preparePassageRevision()
        XCTAssertTrue(fixture.store.prepareDocumentProcedure(existing.binding))
        fixture.store.prompt = "My unsent draft must remain exactly as written."
        let prompt = fixture.store.prompt
        let revision = fixture.store.sourceRevision
        let selection = fixture.store.textSelection
        let requirements = fixture.store.documentRequirements
        fixture.store.openMemoryMap()

        let authoring = try XCTUnwrap(fixture.store.beginKnowledgeMapMethod(node: try fixture.node(for: page)))
        let saved = try XCTUnwrap(fixture.store.keepKnowledgeMapMethod(authoring, title: "Second candidate",
            instruction: "Keep each qualification beside its attributed claim.", requirements: .init()))
        XCTAssertTrue(fixture.store.openDocumentMethodMap(saved))

        XCTAssertNotEqual(saved, existing.binding)
        XCTAssertEqual(fixture.store.prompt, prompt)
        XCTAssertEqual(fixture.store.sharedText, text)
        XCTAssertEqual(fixture.store.sourceName, "local-method-work-sample.txt")
        XCTAssertEqual(fixture.store.sourceRevision, revision)
        XCTAssertEqual(fixture.store.textSelection, selection)
        XCTAssertEqual(fixture.store.documentRequirements, requirements)
        XCTAssertTrue(fixture.store.requestsRevision)
        XCTAssertEqual(fixture.store.preparedDocumentProcedure, existing.binding)
        XCTAssertTrue(fixture.store.selectedKnowledgePages.isEmpty)
        fixture.assertNoWorkOrCredit()
    }

    func testMapHandoffPreservesDraftUntilFreshPassagePreviewConfirmsExactMethod() throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let page = try fixture.page()
        let method = try fixture.method(from: page)
        let text = "Local handoff sample: Retain the claim's source and qualifications."
        fixture.store.open(.context)
        fixture.store.share(text: text, name: "local-handoff-sample.txt")
        fixture.store.selectText(range: NSRange(location: 0, length: text.utf16.count),
            sourceRevision: fixture.store.sourceRevision)
        XCTAssertNotNil(fixture.store.textSelection)
        fixture.store.prompt = "Keep my unsent instruction until I confirm the method preview."
        let draft = fixture.store.prompt
        let revision = fixture.store.sourceRevision

        XCTAssertTrue(fixture.store.openDocumentMethodMap(method.binding))
        XCTAssertNil(fixture.store.textSelection, "Leaving document work retires its live passage geometry.")
        fixture.store.openGraphTarget(.documentMethod(method.binding))
        let inspection = try XCTUnwrap(fixture.store.inspectedDocumentMethod)
        let beforeHandoff = try fixture.files()

        XCTAssertTrue(fixture.store.beginDocumentMethodWork(inspection))
        XCTAssertEqual(fixture.store.section, .context)
        XCTAssertEqual(fixture.store.documentMethodToTry?.id, inspection.id)
        XCTAssertEqual(fixture.store.documentMethodToTry?.binding, method.binding)
        XCTAssertNil(fixture.store.inspectedDocumentMethod)
        XCTAssertEqual(fixture.store.prompt, draft)
        XCTAssertNil(fixture.store.textSelection)
        XCTAssertNil(fixture.store.preparedDocumentProcedure)
        XCTAssertNil(fixture.store.previewDocumentMethod(method.binding), "Handoff cannot reuse the retired passage.")

        fixture.store.selectText(range: NSRange(location: 0, length: text.utf16.count), sourceRevision: revision)
        fixture.store.requestsRevision = true
        let preview = try XCTUnwrap(fixture.store.previewDocumentMethod(method.binding))
        XCTAssertEqual(preview.originalPrompt, draft)
        XCTAssertEqual(preview.procedure.binding, method.binding)
        XCTAssertEqual(fixture.store.prompt, draft, "Opening the preview must preserve the draft.")
        XCTAssertNil(fixture.store.preparedDocumentProcedure)
        XCTAssertTrue(fixture.store.applyDocumentMethodPreview(preview))
        XCTAssertEqual(fixture.store.preparedDocumentProcedure, method.binding)
        XCTAssertEqual(fixture.store.prompt, method.instruction)
        XCTAssertTrue(fixture.store.preparedProcedureMatchesCurrentDraft(question: method.instruction))
        XCTAssertEqual(fixture.store.sharedText, text)
        XCTAssertEqual(fixture.store.sourceRevision, revision)
        XCTAssertEqual(fixture.store.readingSources.latestKnowledgePages, [page])
        XCTAssertEqual(try fixture.files(), beforeHandoff, "Handoff and preparation are transient.")
        fixture.assertNoWorkOrCredit()

        fixture.store.clearDocumentMethodToTry()
        XCTAssertNil(fixture.store.documentMethodToTry)
        XCTAssertEqual(fixture.store.preparedDocumentProcedure, method.binding, "Dismissing the handoff is separate from detaching the prepared method.")
        XCTAssertEqual(fixture.store.prompt, method.instruction)
        XCTAssertEqual(try fixture.files(), beforeHandoff)
    }

    func testUnavailableHandoffNeverReplacesPreviouslyChosenMethod() throws {
        for failure in ["stale source", "reopened owner", "historical", "withdrawn"] {
            let fixture = Fixture()
            defer { fixture.clean() }
            let retained = try fixture.method(from: fixture.page())
            let candidatePage = try fixture.page()
            let candidate = try fixture.method(from: candidatePage)
            fixture.store.openGraphTarget(.documentMethod(retained.binding))
            let retainedSelection = try XCTUnwrap(fixture.store.inspectedDocumentMethod)
            XCTAssertTrue(fixture.store.beginDocumentMethodWork(retainedSelection))
            fixture.store.prompt = "Preserve this unsent draft."
            fixture.store.openGraphTarget(.documentMethod(candidate.binding))
            var rejectedSelection = try XCTUnwrap(fixture.store.inspectedDocumentMethod)

            switch failure {
            case "stale source":
                let sourceID = try XCTUnwrap(candidatePage.anchors.first?.source.id)
                try fixture.store.readingSources.replace(id: sourceID, title: "Corrected fixture source", text: "Different support.")
            case "reopened owner":
                let reopened = fixture.reopen()
                defer { reopened.disconnectAssistant() }
                reopened.openGraphTarget(.documentMethod(candidate.binding))
                rejectedSelection = try XCTUnwrap(reopened.inspectedDocumentMethod)
            case "historical":
                let support = try fixture.scriptedAppliedRecord(using: candidate.binding)
                _ = try fixture.store.documentProcedures.revise(binding: candidate.binding, title: candidate.title,
                    instruction: "Keep both attribution and qualifications.", changeNote: "Retain qualifications.",
                    from: support, records: fixture.store.documentWork.records,
                    knowledgeIsCurrent: { fixture.store.knowledgeDependenciesAreCurrent([$0]) })
            default:
                try fixture.store.documentProcedures.withdraw(binding: candidate.binding)
            }
            let before = try fixture.files()
            let records = fixture.store.documentWork.records
            let selectedNode = fixture.store.selectedGraphNodeID
            let section = fixture.store.section

            XCTAssertFalse(fixture.store.beginDocumentMethodWork(rejectedSelection), failure)
            XCTAssertEqual(fixture.store.documentMethodToTry?.id, retainedSelection.id, failure)
            XCTAssertEqual(fixture.store.documentMethodToTry?.binding, retained.binding, failure)
            XCTAssertEqual(fixture.store.selectedGraphNodeID, selectedNode, failure)
            XCTAssertEqual(fixture.store.section, section, failure)
            XCTAssertEqual(fixture.store.prompt, "Preserve this unsent draft.", failure)
            XCTAssertNil(fixture.store.preparedDocumentProcedure, failure)
            XCTAssertEqual(fixture.store.documentWork.records, records, failure)
            XCTAssertTrue(fixture.store.tokenSteward.tasks.isEmpty, failure)
            XCTAssertTrue(fixture.store.evolution.usefulReceipts.isEmpty, failure)
            XCTAssertEqual(fixture.client.calls, 0, failure)
            XCTAssertEqual(fixture.client.connections, 0, failure)
            XCTAssertEqual(try fixture.files(), before, failure)

            fixture.store.clearDocumentMethodToTry()
            XCTAssertNil(fixture.store.documentMethodToTry, failure)
            XCTAssertEqual(fixture.store.prompt, "Preserve this unsent draft.", failure)
            XCTAssertEqual(try fixture.files(), before, failure)
        }
    }

    @MainActor
    private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-map-method-flow-\(UUID())")
        let client = KnowledgeMapMethodNoModelClient()
        var preference: URL { directory.appendingPathComponent("preferences.json") }
        var sourceURL: URL { preference.deletingPathExtension().appendingPathExtension("reading-sources.json") }
        var methodURL: URL { preference.deletingPathExtension().appendingPathExtension("document-procedures.json") }
        lazy var store = reopen()

        func reopen() -> CompanionStore {
            CompanionStore(preferenceURL: preference, assistant: client,
                assistantFactory: { [client] _, _ in client }, allowsPlay: false, tokenSteward: TokenStewardStore())
        }

        func page() throws -> KnowledgePage {
            let source = try store.readingSources.keep(title: "Local fixture source",
                text: "Keep a claim's attribution and qualifications visible beside that claim.")
            let anchor = try store.readingSources.makeAnchor(sourceID: source.id,
                range: NSRange(location: 0, length: source.text.utf16.count))
            let draft = try store.readingSources.saveKnowledgePage(title: "Attribution fixture",
                body: "A scripted concept used only to exercise native lifecycle checks.", kind: .concept, anchors: [anchor])
            return try store.readingSources.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        }

        func node(for page: KnowledgePage) throws -> CompanionGraphNode {
            try XCTUnwrap(store.memoryMapSnapshot().nodes.first { $0.id == KnowledgePageGraph.nodeID(page.binding) })
        }

        func method(from page: KnowledgePage) throws -> DocumentProcedure {
            let selection = try XCTUnwrap(store.beginKnowledgeMapMethod(node: try node(for: page)))
            let binding = try XCTUnwrap(store.keepKnowledgeMapMethod(selection, title: "Attribute the claim",
                instruction: "Keep attribution beside the claim.", requirements: .init()))
            return try XCTUnwrap(store.documentProcedures.procedure(matching: binding))
        }

        /// Scripted support solely for the historical-navigation case. It is
        /// unrelated to an actual request, Patrick's profile, or owner acceptance.
        func scriptedAppliedRecord(using method: DocumentProcedureUse) throws -> DocumentWorkRecord {
            let request = UUID().uuidString
            let date = Date()
            func digest(_ value: Character) -> String { String(repeating: value, count: 64) }
            var record = DocumentWorkRecord(id: request + "-Qwen", requestID: request, provider: "Qwen",
                targetID: UUID().uuidString, sourceDigest: digest("a"), sourceRevision: 1,
                selectionStart: 0, selectionLength: 12, preserveNumbersAndLinks: true,
                createdAt: date, updatedAt: date.addingTimeInterval(20), state: .applying,
                proposedDigest: digest("b"), expectedAfterDigest: digest("c"), actualAfterDigest: digest("c"), afterRevision: 2,
                checks: [.init(id: "source", title: "Scripted exact source", passed: true)],
                learning: .init(requestBinding: .init(inputDigest: digest("d"), contextDigest: digest("e")), suppliedLessons: []),
                procedureUse: method)
            try store.documentWork.save(record)
            record.state = .applied
            record.feedback = .init(revision: 1, verdict: .helpful, recordedAt: date.addingTimeInterval(10))
            try store.documentWork.save(record)
            return record
        }

        func assertNoWorkOrCredit(file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertFalse(store.isWorking, file: file, line: line)
            XCTAssertEqual(client.calls, 0, file: file, line: line)
            XCTAssertEqual(client.connections, 0, file: file, line: line)
            XCTAssertTrue(store.documentWork.records.isEmpty, file: file, line: line)
            XCTAssertTrue(store.tokenSteward.tasks.isEmpty, file: file, line: line)
            XCTAssertTrue(store.evolution.usefulReceipts.isEmpty, file: file, line: line)
            XCTAssertTrue(store.keptLessons.isEmpty, file: file, line: line)
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
private final class KnowledgeMapMethodNoModelClient: AssistantClient {
    private(set) var calls = 0
    private(set) var connections = 0
    func connect() async throws {
        connections += 1
        XCTFail("Method authoring and navigation must not connect an assistant.")
    }
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1
        XCTFail("Method authoring and navigation must not dispatch a model.")
    }
}
