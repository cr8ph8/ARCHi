import Foundation
import XCTest
@testable import ARCHiDesktop

/// Production-store integration with in-process clients only. No model, child
/// process, personal profile, paid request, or external connection is used.
@MainActor
final class KnowledgeProcedureIntegrationTests: XCTestCase {
    func testReviewedConceptCandidateAndPreparationPreserveCopyWithoutInventingOutcome() throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        fixture.store.share(text: Fixture.passage, name: "working.txt")
        fixture.store.selectText(range: NSRange(location: 0, length: Fixture.passage.utf16.count),
            sourceRevision: fixture.store.sourceRevision)
        let text = fixture.store.sharedText
        let revision = fixture.store.sourceRevision
        let selection = fixture.store.textSelection
        let page = try fixture.page()
        let method = try fixture.method(from: page)
        XCTAssertEqual(page.kind, .concept)
        XCTAssertEqual(page.state, .reviewed)
        XCTAssertEqual(method.knowledgeOrigin, page.binding)
        XCTAssertTrue(method.originRecordID.isEmpty)
        XCTAssertTrue(method.originFeedbackID.isEmpty)
        XCTAssertEqual(fixture.store.sharedText, text)
        XCTAssertEqual(fixture.store.sourceRevision, revision)
        XCTAssertEqual(fixture.store.textSelection, selection)
        XCTAssertTrue(fixture.store.documentWork.records.isEmpty)
        XCTAssertTrue(fixture.store.tokenSteward.tasks.isEmpty)
        XCTAssertTrue(fixture.store.evolution.usefulReceipts.isEmpty)
        XCTAssertTrue(fixture.store.keptLessons.isEmpty)
        XCTAssertNil(fixture.store.documentProcedureUnavailable(method.binding))

        fixture.store.preparePassageRevision(shorten: true)
        fixture.store.documentRequirements.preserveNumbersAndLinks = false
        XCTAssertTrue(fixture.store.prepareDocumentProcedure(method.binding))
        XCTAssertEqual(fixture.store.preparedDocumentProcedureKnowledge, page.binding)
        XCTAssertEqual(fixture.store.prompt, method.instruction)
        XCTAssertEqual(fixture.store.sharedText, text)
        XCTAssertEqual(fixture.store.sourceRevision, revision)
        XCTAssertFalse(fixture.store.isWorking)
        XCTAssertEqual(fixture.local.calls, 0)
        XCTAssertEqual(fixture.external.calls, 0)

        // A new shared copy requires a current selection before reuse. Preparing
        // that copy still cannot manufacture an applied or reviewed work record.
        let replacementSource = "I am asking whether you could please close the door."
        fixture.store.share(text: replacementSource, name: "next-copy.txt")
        XCTAssertGreaterThan(fixture.store.sourceRevision, revision)
        XCTAssertFalse(fixture.store.canPrepareDocumentProcedure(method))
        fixture.store.selectText(range: NSRange(location: 0, length: replacementSource.utf16.count),
            sourceRevision: fixture.store.sourceRevision)
        fixture.store.preparePassageRevision(shorten: true)
        fixture.store.documentRequirements.preserveNumbersAndLinks = false
        let nextRevision = fixture.store.sourceRevision
        XCTAssertTrue(fixture.store.prepareDocumentProcedure(method.binding))
        XCTAssertEqual(fixture.store.sharedText, replacementSource)
        XCTAssertEqual(fixture.store.sourceRevision, nextRevision)
        XCTAssertTrue(fixture.store.documentWork.records.isEmpty)
        XCTAssertTrue(fixture.store.tokenSteward.tasks.isEmpty)
        XCTAssertEqual(fixture.local.calls, 0)
    }

    func testRequestAndReceiptBindExactPageAndWithdrawalBlocksPendingApply() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let page = try fixture.page()
        let method = try fixture.method(from: page)
        try fixture.prepare(method)
        fixture.store.submit()
        try await fixture.wait { fixture.local.request != nil }
        let request = try XCTUnwrap(fixture.local.request)
        XCTAssertEqual(request.localProcedureKnowledge, [page.binding])
        XCTAssertTrue(request.hasValidLocalProcedureKnowledge)
        XCTAssertEqual(request.sourceText, Fixture.passage)
        XCTAssertEqual(request.sourceName, "synthetic-method.txt")
        XCTAssertNotNil(request.revisionTarget)
        XCTAssertNil(request.localKnowledge)
        XCTAssertNil(request.localReading)
        XCTAssertFalse(request.localInput.contains(page.body), "Only authored method guidance enters this revision; provenance is a native binding.")
        let continued = request.replacingLocalConversation([.init(question: "Earlier synthetic question", answer: "Earlier synthetic answer")])
        XCTAssertEqual(continued.localProcedureKnowledge, [page.binding])
        XCTAssertEqual(continued.revisionTarget, request.revisionTarget)
        XCTAssertTrue(continued.hasValidLocalProcedureKnowledge)
        let noTarget = AssistantRequest(prompt: "A plain question", sourceName: nil, sourceText: "",
            sourceRevision: 0, placementRevision: 0, settings: request.settings, localProcedureKnowledge: [page.binding])
        XCTAssertFalse(noTarget.hasValidLocalProcedureKnowledge)
        XCTAssertEqual(noTarget.localContextInput, "")
        let duplicateBinding = AssistantRequest(prompt: request.prompt, sourceName: request.sourceName,
            sourceText: request.sourceText, sourceRevision: request.sourceRevision,
            placementRevision: request.placementRevision, settings: request.settings, selection: request.selection,
            revisionTarget: request.revisionTarget, localProcedureKnowledge: [page.binding, page.binding])
        XCTAssertFalse(duplicateBinding.hasValidLocalProcedureKnowledge)

        let proposal = try fixture.local.complete()
        try await fixture.wait { !fixture.store.isWorking }
        let lane = try XCTUnwrap(fixture.store.compareResults[.qwen])
        XCTAssertEqual(lane.state, .complete, fixture.store.status)
        let receipt = try XCTUnwrap(lane.receipt)
        XCTAssertEqual(receipt.knowledgeDependencies, [page.binding])
        XCTAssertEqual(receipt.readingDependencies, page.anchors.map(\.source))
        XCTAssertTrue(fixture.store.isCurrentReplyContext(receipt))
        XCTAssertTrue(fixture.store.canApplyDocumentRevision(provider: .qwen, proposal: proposal))
        let record = try XCTUnwrap(fixture.store.documentRecord(requestID: receipt.requestID, provider: .qwen))
        XCTAssertEqual(record.procedureUse, method.binding)
        XCTAssertEqual(record.state, .ready)
        XCTAssertNil(record.feedback)
        XCTAssertEqual(fixture.store.sharedText, Fixture.passage)

        fixture.store.withdrawKnowledgePage(page)
        XCTAssertFalse(fixture.store.isCurrentReplyContext(receipt))
        XCTAssertNotNil(fixture.store.documentProcedureUnavailable(method.binding))
        XCTAssertFalse(fixture.store.canApplyDocumentRevision(provider: .qwen, proposal: proposal))
        fixture.store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
        XCTAssertEqual(fixture.store.sharedText, Fixture.passage)
        XCTAssertFalse(fixture.store.documentWork.records.contains { $0.state == .applied || $0.feedback != nil })
        XCTAssertEqual(fixture.local.calls, 1)
        XCTAssertEqual(fixture.external.calls, 0)
    }

    func testExternalRoutesDirectCodexAndNativeFallbackCannotSendMethodKnowledge() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let method = try fixture.method(from: fixture.page())
        try fixture.prepare(method)
        for route in [AssistantRoute.codex, .compare] {
            fixture.store.setAssistantRoute(route)
            XCTAssertNotNil(fixture.store.nextAssistantBlockedReason)
            fixture.store.submit()
            XCTAssertFalse(fixture.store.isWorking)
        }
        XCTAssertEqual(fixture.local.calls, 0)
        XCTAssertEqual(fixture.external.calls, 0)
        XCTAssertEqual(fixture.external.connections, 0)

        fixture.store.setAssistantRoute(.native)
        XCTAssertNotNil(fixture.store.nextAssistantFallbackBlockedReason)
        fixture.store.submit()
        try await fixture.wait { fixture.local.request != nil }
        let request = try XCTUnwrap(fixture.local.request)
        XCTAssertEqual(request.localProcedureKnowledge, [try XCTUnwrap(method.knowledgeOrigin)])
        let direct = CodexAssistant()
        do {
            try await direct.reply(to: request) { _ in XCTFail("The external client cannot emit a method-backed answer.") }
            XCTFail("The direct external client must reject method knowledge before connection state is considered.")
        } catch AssistantFailure.protocolError {
            // An unavailable error would only demonstrate an unconnected client.
        } catch {
            XCTFail("Expected protocolError before any connection check, received \(error).")
        }
        await direct.shutdown()
        fixture.local.fail()
        try await fixture.wait { !fixture.store.isWorking }
        XCTAssertNotEqual(fixture.store.compareResults[.qwen]?.state, .complete)
        XCTAssertNil(fixture.store.compareResults[.codex])
        XCTAssertEqual(fixture.local.calls, 1)
        XCTAssertEqual(fixture.external.calls, 0)
        XCTAssertEqual(fixture.external.connections, 0)
        XCTAssertEqual(fixture.store.sharedText, Fixture.passage)
    }

    func testExternalPageWithdrawalDiscardsInflightRevisionAndBlocksReuse() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let page = try fixture.page()
        let method = try fixture.method(from: page)
        try fixture.prepare(method)
        fixture.store.setLocalConversationEnabled(true)
        fixture.store.submit()
        try await fixture.wait { fixture.local.request != nil }
        let pendingReceipt = try XCTUnwrap(fixture.store.compareResults[.qwen]?.receipt)
        XCTAssertEqual(pendingReceipt.knowledgeDependencies, [page.binding])
        let other = ReadingSourceLibrary(url: fixture.preference.deletingPathExtension().appendingPathExtension("reading-sources.json"))
        _ = try other.withdrawKnowledgePage(id: page.id, expectedRevision: page.revision)
        let late = try fixture.local.complete()
        try await fixture.wait { !fixture.store.isWorking }
        XCTAssertNotEqual(fixture.store.compareResults[.qwen]?.state, .complete)
        XCTAssertNil(fixture.store.compareResults[.qwen]?.revision)
        XCTAssertFalse(fixture.store.isCurrentReplyContext(pendingReceipt))
        XCTAssertFalse(fixture.store.canApplyDocumentRevision(provider: .qwen, proposal: late))
        XCTAssertEqual(fixture.store.sharedText, Fixture.passage)
        XCTAssertTrue(fixture.store.nextReplyConversation.isEmpty)
        XCTAssertNotNil(fixture.store.documentProcedureUnavailable(method.binding))
        XCTAssertFalse(fixture.store.prepareDocumentProcedure(method.binding))
        fixture.store.submit()
        XCTAssertEqual(fixture.local.calls, 1)
        XCTAssertEqual(fixture.store.documentProcedures.procedure(matching: method.binding)?.knowledgeOrigin, page.binding)
        XCTAssertFalse(fixture.store.documentWork.records.contains { $0.state == .applied || $0.feedback != nil })
        XCTAssertEqual(fixture.external.calls, 0)
        XCTAssertEqual(fixture.external.connections, 0)
    }

    @MainActor
    private final class Fixture {
        static let passage = "I would like to ask you if you would please close the door."
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-knowledge-method-integration-\(UUID())")
        let local = KnowledgeProcedureIntegrationClient()
        let external = KnowledgeProcedureIntegrationClient()
        var preference: URL { directory.appendingPathComponent("preferences.json") }
        lazy var store = CompanionStore(preferenceURL: preference, assistant: local,
            assistantFactory: { [local, external] provider, _ in provider == .qwen ? local : external },
            allowsPlay: false, tokenSteward: TokenStewardStore())

        func page() throws -> KnowledgePage {
            let source = try store.readingSources.keep(title: "Synthetic source",
                text: "A direct polite request can preserve an action while removing introductory padding.")
            let anchor = try store.readingSources.makeAnchor(sourceID: source.id,
                range: NSRange(location: 0, length: source.text.utf16.count))
            let draft = try store.readingSources.saveKnowledgePage(title: "Concise requests",
                body: "Synthetic interpretation with its own attributable supporting passage.", kind: .concept, anchors: [anchor])
            return try store.readingSources.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        }

        func method(from page: KnowledgePage) throws -> DocumentProcedure {
            XCTAssertTrue(store.keepKnowledgeProcedure(page: page, title: "Concise requests",
                instruction: "Shorten the selected request while preserving its action.",
                requirements: .init(mustBeShorter: true, preserveNumbersAndLinks: false)), store.knowledgePageMessage ?? store.status)
            return try XCTUnwrap(store.documentProcedures.latestProcedures.first)
        }

        func prepare(_ method: DocumentProcedure) throws {
            store.setAssistantRoute(.automatic)
            store.setLocalWorkPreference(.reasoning)
            store.share(text: Self.passage, name: "synthetic-method.txt")
            store.selectText(range: NSRange(location: 0, length: Self.passage.utf16.count), sourceRevision: store.sourceRevision)
            store.preparePassageRevision(shorten: true)
            store.documentRequirements.preserveNumbersAndLinks = false
            XCTAssertTrue(store.prepareDocumentProcedure(method.binding), store.documentWorkMessage ?? store.status)
        }

        func wait(_ condition: @MainActor () -> Bool) async throws {
            for _ in 0..<400 {
                if condition() { return }
                try await Task.sleep(for: .milliseconds(5))
            }
            XCTFail("Timed out: \(store.status) | \(store.documentWorkMessage ?? "none")")
            throw AssistantFailure.timedOut
        }

        func clean() {
            store.cancelWork(); store.disconnectAssistant(); local.resolve(); external.resolve()
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

@MainActor
private final class KnowledgeProcedureIntegrationClient: AssistantClient {
    var request: AssistantRequest?
    private(set) var calls = 0
    private(set) var connections = 0
    private var handler: (@MainActor (AssistantEvent) -> Void)?
    private var continuation: CheckedContinuation<Void, Error>?

    func connect() async throws { connections += 1 }
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; self.request = request; handler = onEvent
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func complete() throws -> PassageRevisionProposal {
        let target = try XCTUnwrap(request?.revisionTarget)
        let proposal = PassageRevisionProposal(target: target, decision: .propose,
            replacement: "Please close the door.", explanation: "Review this shorter synthetic request.",
            sourceIDs: ["selected-passage"], memoryIDs: [])
        handler?(.revision(proposal)); resolve()
        return proposal
    }
    func fail() { let pending = continuation; continuation = nil; pending?.resume(throwing: AssistantFailure.timedOut) }
    func resolve() { let pending = continuation; continuation = nil; pending?.resume() }
}
