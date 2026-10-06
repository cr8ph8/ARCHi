import Foundation
import XCTest
@testable import ARCHiDesktop

/// Disposable native records only. Inspection must retain exact source history
/// without preparing work, sending a request or changing the existing owners.
@MainActor
final class KnowledgeRecordInspectionTests: XCTestCase {
    func testHistoricalGraphPageOpensExactRetainedVersionAfterRevision() throws {
        let fixture = Fixture(); defer { fixture.clean() }
        let original = try fixture.page()
        let draft = try fixture.store.readingSources.saveKnowledgePage(id: original.id,
            expectedRevision: original.revision, title: "Later concept", body: "A later interpretation.",
            kind: .concept, anchors: original.anchors)
        let current = try fixture.store.readingSources.reviewKnowledgePage(id: draft.id,
            expectedRevision: draft.revision)
        let before = try fixture.files()
        let section = fixture.store.section

        fixture.store.openGraphTarget(.knowledgePage(original.binding))
        let selection = try XCTUnwrap(fixture.store.inspectedKnowledgeRecord)
        assertPage(fixture.store.knowledgeRecordForInspection(selection), equals: original)
        XCTAssertNotEqual(original.binding, current.binding)
        XCTAssertEqual(fixture.store.readingSources.latestKnowledgePages, [current])
        XCTAssertEqual(fixture.store.section, section, "Inspecting a record does not leave the current workspace.")
        XCTAssertTrue(fixture.store.selectedKnowledgePages.isEmpty)
        XCTAssertNil(fixture.store.selectedKnowledgePageID, "A historical route must not expand the latest page by ID.")
        XCTAssertEqual(try fixture.files(), before)
        fixture.assertNoWorkOrCredit()
    }

    func testWithdrawnPageAndPageWithMissingSourceRemainExactInspectableRecords() throws {
        let fixture = Fixture(); defer { fixture.clean() }
        let reviewed = try fixture.page()
        let withdrawn = try fixture.store.readingSources.withdrawKnowledgePage(id: reviewed.id,
            expectedRevision: reviewed.revision)
        try fixture.store.readingSources.forget(id: XCTUnwrap(reviewed.anchors.first?.source.id))
        let before = try fixture.files()

        for page in [reviewed, withdrawn] {
            fixture.store.inspectKnowledgeRecord(.page(page.binding))
            let selection = try XCTUnwrap(fixture.store.inspectedKnowledgeRecord)
            assertPage(fixture.store.knowledgeRecordForInspection(selection), equals: page)
            XCTAssertNotNil(fixture.store.readingSources.availability(of: page),
                "Inspection must remain separate from eligibility for new work.")
        }
        XCTAssertTrue(fixture.store.readingSources.sources.isEmpty)
        XCTAssertTrue(fixture.store.selectedKnowledgePages.isEmpty)
        XCTAssertEqual(try fixture.files(), before)
        fixture.assertNoWorkOrCredit()
    }

    func testSourceReplacementProvenanceCorrectionAndForgetNeverSubstituteLatestCopy() throws {
        for change in ["text", "provenance", "forget"] {
            let fixture = Fixture(); defer { fixture.clean() }
            let source = try fixture.source()
            let reference = ReadingSourceParent(binding: source.binding)
            fixture.store.openGraphTarget(.readingSource(reference))
            let selection = try XCTUnwrap(fixture.store.inspectedKnowledgeRecord)
            assertSource(fixture.store.knowledgeRecordForInspection(selection), equals: source)
            var current: ReadingSourceSnapshot?
            switch change {
            case "text":
                current = try fixture.store.readingSources.replace(id: source.id,
                    title: "Replacement copy", text: "A different source passage.")
            case "provenance":
                current = try fixture.store.readingSources.declareProvenance(source: source,
                    origin: .mixed, acquisition: .userCopy, attribution: "Corrected fixture declaration", parents: [])
                XCTAssertEqual(current?.digest, source.digest, "Equal text must not hide changed provenance.")
            default:
                try fixture.store.readingSources.forget(id: source.id)
            }
            let before = try fixture.files()

            assertUnavailable(fixture.store.knowledgeRecordForInspection(selection), change)
            fixture.store.openGraphTarget(.readingSource(reference))
            assertUnavailable(fixture.store.knowledgeRecordForInspection(
                try XCTUnwrap(fixture.store.inspectedKnowledgeRecord)), change)
            if let current {
                fixture.store.openGraphTarget(.readingSource(.init(binding: current.binding)))
                assertSource(fixture.store.knowledgeRecordForInspection(
                    try XCTUnwrap(fixture.store.inspectedKnowledgeRecord)), equals: current)
            }
            XCTAssertTrue(fixture.store.selectedReadingSourceIDs.isEmpty, change)
            XCTAssertEqual(try fixture.files(), before, change)
            fixture.assertNoWorkOrCredit()
        }
    }

    func testInvalidMissingAndMismatchedBindingsCannotResolveExistingRecords() throws {
        let fixture = Fixture(); defer { fixture.clean() }
        let page = try fixture.page()
        let source = try XCTUnwrap(fixture.store.readingSources.sources.first)
        let falseDigest = String(repeating: "f", count: 64)
        let pageBindings = [
            KnowledgePageBinding(id: "invalid", revision: page.revision, digest: page.binding.digest),
            KnowledgePageBinding(id: page.id, revision: 0, digest: page.binding.digest),
            KnowledgePageBinding(id: page.id, revision: page.revision, digest: "invalid"),
            KnowledgePageBinding(id: page.id, revision: page.revision, digest: falseDigest),
            KnowledgePageBinding(id: page.id, revision: page.revision + 1, digest: page.binding.digest),
            KnowledgePageBinding(id: UUID().uuidString, revision: page.revision, digest: page.binding.digest)
        ]
        let sourceBindings = [
            ReadingSourceBinding(id: "invalid", revision: source.revision, digest: source.digest),
            ReadingSourceBinding(id: source.id, revision: 0, digest: source.digest),
            ReadingSourceBinding(id: source.id, revision: source.revision, digest: "invalid"),
            ReadingSourceBinding(id: source.id, revision: source.revision, digest: falseDigest),
            ReadingSourceBinding(id: source.id, revision: source.revision + 1, digest: source.digest),
            ReadingSourceBinding(id: UUID().uuidString, revision: source.revision, digest: source.digest),
            ReadingSourceBinding(id: source.id, revision: source.revision, digest: source.digest),
            ReadingSourceBinding(id: source.id, revision: source.revision, digest: source.digest,
                provenance: .init(origin: .human, acquisition: .userCopy, parents: [], digest: falseDigest))
        ]
        let references: [KnowledgeRecordReference] = pageBindings.map { .page($0) }
            + sourceBindings.map { .source(.init(binding: $0)) }
        let before = try fixture.files()
        for reference in references {
            let selection = KnowledgeRecordInspectionSelection(reference: reference,
                sourceOwner: ObjectIdentifier(fixture.store.readingSources))
            assertUnavailable(fixture.store.knowledgeRecordForInspection(selection))
        }
        XCTAssertNil(fixture.store.inspectedKnowledgeRecord)
        XCTAssertEqual(try fixture.files(), before)
        fixture.assertNoWorkOrCredit()
    }

    func testExternalLibraryChangeAndReopenedOwnersRejectCapturedInspection() throws {
        let fixture = Fixture(); defer { fixture.clean() }
        let page = try fixture.page()
        let source = try XCTUnwrap(fixture.store.readingSources.sources.first)
        let references: [KnowledgeRecordReference] = [.page(page.binding), .source(.init(binding: source.binding))]
        let selections = references.map {
            KnowledgeRecordInspectionSelection(reference: $0, sourceOwner: ObjectIdentifier(fixture.store.readingSources))
        }
        let reopenedBeforeChange = fixture.reopen()
        defer { reopenedBeforeChange.disconnectAssistant() }
        for selection in selections {
            assertUnavailable(reopenedBeforeChange.knowledgeRecordForInspection(selection),
                "Identical records cannot transfer an inspection across profile owners.")
        }

        let external = ReadingSourceLibrary(url: fixture.sourceURL)
        _ = try external.keep(title: "External fixture source", text: "Another explicit retained copy.")
        let before = try fixture.files()
        for selection in selections {
            assertUnavailable(fixture.store.knowledgeRecordForInspection(selection),
                "A stale owner cannot return its former page or source text.")
        }

        let reopened = fixture.reopen()
        defer { reopened.disconnectAssistant() }
        for selection in selections {
            assertUnavailable(reopened.knowledgeRecordForInspection(selection))
        }
        reopened.inspectKnowledgeRecord(.page(page.binding))
        assertPage(reopened.knowledgeRecordForInspection(try XCTUnwrap(reopened.inspectedKnowledgeRecord)), equals: page)
        reopened.inspectKnowledgeRecord(.source(.init(binding: source.binding)))
        assertSource(reopened.knowledgeRecordForInspection(try XCTUnwrap(reopened.inspectedKnowledgeRecord)), equals: source)
        XCTAssertEqual(try fixture.files(), before)
        fixture.assertNoWorkOrCredit()
    }

    func testGraphInspectionPreservesWorkingDraftAttachmentsSelectionAndOwnerBytes() throws {
        let fixture = Fixture(); defer { fixture.clean() }
        let page = try fixture.page()
        let source = try XCTUnwrap(fixture.store.readingSources.sources.first)
        let store = fixture.store
        store.share(text: "Working passage with 3 attributed claims.", name: "inspection-fixture.txt")
        store.selectReadingSource(source.id, selected: true)
        XCTAssertTrue(store.useKnowledgePageInChat(page, openAssistant: false))
        store.selectText(range: NSRange(location: 0, length: 15), sourceRevision: store.sourceRevision)
        store.prompt = "Preserve this unsent question exactly."
        let graphNodeID = KnowledgePageGraph.nodeID(page.binding)
        XCTAssertTrue(store.selectGraphRecord(graphNodeID, in: store.companionGraphSnapshot(), particleScene: nil))
        store.selectedKnowledgePageID = page.id
        let section = store.section
        let prompt = store.prompt
        let sharedText = store.sharedText
        let sourceName = store.sourceName
        let sourceRevision = store.sourceRevision
        let selection = store.textSelection
        let context = store.contextTicket()
        let pages = store.selectedKnowledgePages
        let sources = store.selectedReadingSourceIDs
        let requirements = store.documentRequirements
        let prepared = store.preparedDocumentProcedure
        let preferences = store.preferences
        let activity = store.activity
        let evolutionRevision = store.evolution.revision
        let evolutionHistory = store.evolution.history
        let hampton = store.hamptonSnapshot
        let before = try fixture.files()

        store.openGraphTarget(.knowledgePage(page.binding))
        assertPage(store.knowledgeRecordForInspection(try XCTUnwrap(store.inspectedKnowledgeRecord)), equals: page)
        store.openGraphTarget(.readingSource(.init(binding: source.binding)))
        assertSource(store.knowledgeRecordForInspection(try XCTUnwrap(store.inspectedKnowledgeRecord)), equals: source)

        XCTAssertEqual(store.section, section)
        XCTAssertEqual(store.prompt, prompt)
        XCTAssertEqual(store.sharedText, sharedText)
        XCTAssertEqual(store.sourceName, sourceName)
        XCTAssertEqual(store.sourceRevision, sourceRevision)
        XCTAssertEqual(store.textSelection, selection)
        XCTAssertEqual(store.contextTicket(), context)
        XCTAssertEqual(store.selectedKnowledgePages, pages)
        XCTAssertEqual(store.selectedReadingSourceIDs, sources)
        XCTAssertEqual(store.selectedGraphNodeID, graphNodeID)
        XCTAssertEqual(store.selectedKnowledgePageID, page.id)
        XCTAssertEqual(store.documentRequirements, requirements)
        XCTAssertEqual(store.preparedDocumentProcedure, prepared)
        XCTAssertEqual(store.preferences, preferences)
        XCTAssertEqual(store.activity, activity)
        XCTAssertEqual(store.evolution.revision, evolutionRevision)
        XCTAssertEqual(store.evolution.history, evolutionHistory)
        XCTAssertEqual(store.hamptonSnapshot, hampton)
        XCTAssertEqual(try fixture.files(), before)
        fixture.assertNoWorkOrCredit()
    }

    func testOpenPageAndConnectionDraftsBlockInspectionWithoutReplacingDrafts() throws {
        for draftKind in ["page", "connection"] {
            let fixture = Fixture(); defer { fixture.clean() }
            let page = try fixture.page()
            if draftKind == "page" {
                fixture.store.beginKnowledgePage(page)
            } else {
                fixture.store.knowledgeLinkDraft = KnowledgeLinkDraft(page: page, prior: nil)
            }
            let pageDraftID = fixture.store.knowledgePageDraft?.id
            let linkDraftID = fixture.store.knowledgeLinkDraft?.id
            let section = fixture.store.section
            let before = try fixture.files()

            fixture.store.inspectKnowledgeRecord(.page(page.binding))
            XCTAssertNil(fixture.store.inspectedKnowledgeRecord, draftKind)
            XCTAssertNotNil(fixture.store.workspaceRoutingNotice, draftKind)
            XCTAssertEqual(fixture.store.knowledgePageDraft?.id, pageDraftID, draftKind)
            XCTAssertEqual(fixture.store.knowledgeLinkDraft?.id, linkDraftID, draftKind)
            XCTAssertEqual(fixture.store.section, section, draftKind)
            XCTAssertEqual(try fixture.files(), before, draftKind)
            fixture.assertNoWorkOrCredit()
        }
    }

    func testRecoveryAndShutdownBlockNewInspectionAndInvalidateExistingSelection() async throws {
        for condition in ["recovery", "shutdown"] {
            let fixture = Fixture(); defer { fixture.clean() }
            let page = try fixture.page()
            fixture.store.inspectKnowledgeRecord(.page(page.binding))
            let selection = try XCTUnwrap(fixture.store.inspectedKnowledgeRecord)
            if condition == "recovery" {
                fixture.store.blockProfileForRecovery("Synthetic inspection recovery block")
            } else {
                await fixture.store.shutdownAssistant()
            }
            fixture.store.inspectedKnowledgeRecord = nil
            let before = try fixture.files()
            let section = fixture.store.section

            assertUnavailable(fixture.store.knowledgeRecordForInspection(selection), condition)
            fixture.store.inspectKnowledgeRecord(.page(page.binding))
            XCTAssertNil(fixture.store.inspectedKnowledgeRecord, condition)
            XCTAssertNotNil(fixture.store.workspaceRoutingNotice, condition)
            XCTAssertEqual(fixture.store.section, section, condition)
            XCTAssertEqual(try fixture.files(), before, condition)
            fixture.assertNoWorkOrCredit()
        }
    }

    private func assertPage(_ result: KnowledgeRecordInspection, equals page: KnowledgePage,
                            file: StaticString = #filePath, line: UInt = #line) {
        guard case .page(let actual) = result else {
            XCTFail("Expected the exact retained page.", file: file, line: line); return
        }
        XCTAssertEqual(actual, page, file: file, line: line)
    }

    private func assertSource(_ result: KnowledgeRecordInspection, equals source: ReadingSourceSnapshot,
                              file: StaticString = #filePath, line: UInt = #line) {
        guard case .source(let actual) = result else {
            XCTFail("Expected the exact retained source.", file: file, line: line); return
        }
        XCTAssertEqual(actual, source, file: file, line: line)
    }

    private func assertUnavailable(_ result: KnowledgeRecordInspection, _ message: String = "",
                                  file: StaticString = #filePath, line: UInt = #line) {
        guard case .unavailable(let reason) = result else {
            XCTFail("Expected an unavailable exact reference. " + message, file: file, line: line); return
        }
        XCTAssertFalse(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, file: file, line: line)
    }

    @MainActor
    private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-record-inspection-\(UUID())")
        let client = KnowledgeRecordInspectionNoModelClient()
        var preference: URL { directory.appendingPathComponent("preferences.json") }
        var sourceURL: URL { preference.deletingPathExtension().appendingPathExtension("reading-sources.json") }
        lazy var store = reopen()

        func reopen() -> CompanionStore {
            CompanionStore(preferenceURL: preference, assistant: client,
                assistantFactory: { [client] _, _ in client }, allowsPlay: false, tokenSteward: TokenStewardStore())
        }

        func source() throws -> ReadingSourceSnapshot {
            try store.readingSources.keep(title: "Inspection fixture source",
                text: "Keep attribution beside the claim and preserve its qualifications.",
                provenance: .init(origin: .human, acquisition: .userCopy, attribution: "Scripted test fixture"))
        }

        func page() throws -> KnowledgePage {
            let source = try source()
            let anchor = try store.readingSources.makeAnchor(sourceID: source.id,
                range: NSRange(location: 0, length: source.text.utf16.count))
            let draft = try store.readingSources.saveKnowledgePage(title: "Original fixture concept",
                body: "The first retained interpretation.", kind: .concept, anchors: [anchor])
            return try store.readingSources.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        }

        func assertNoWorkOrCredit(file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertFalse(store.isWorking, file: file, line: line)
            XCTAssertEqual(client.calls, 0, file: file, line: line)
            XCTAssertEqual(client.connections, 0, file: file, line: line)
            XCTAssertTrue(store.documentWork.records.isEmpty, file: file, line: line)
            XCTAssertTrue(store.documentProcedures.procedures.isEmpty, file: file, line: line)
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
private final class KnowledgeRecordInspectionNoModelClient: AssistantClient {
    private(set) var calls = 0
    private(set) var connections = 0
    func connect() async throws {
        connections += 1
        XCTFail("Record inspection must not connect an assistant.")
    }
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1
        XCTFail("Record inspection must not dispatch a model.")
    }
}
