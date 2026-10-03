import XCTest
@testable import ARCHiDesktop

@MainActor
final class AssistantSourceContextTests: XCTestCase {
    func testCapturedNoteAndPassageKeepTheirMeaningAndExcludeAttribution() throws {
        let fixture = try fixture(); defer { fixture.clean() }
        let context = try XCTUnwrap(AssistantSourceContext.capture(fixture.request,
            sourceTitles: [fixture.source.id: fixture.source.title]))
        XCTAssertEqual(context.excerpts.count, 2)
        XCTAssertEqual(context.excerpts[0].kind, .interpretation)
        XCTAssertEqual(context.excerpts[0].text, fixture.page.body)
        XCTAssertEqual(context.excerpts[1].kind, .passage)
        XCTAssertEqual(context.excerpts[1].title, fixture.source.title)
        XCTAssertEqual(context.excerpts[1].text, fixture.source.text)
        XCTAssertEqual(context.excerpts[1].provenance?.origin, .model)
        XCTAssertFalse(String(reflecting: context).contains("PRIVATE-ATTRIBUTION"))
        let retained = context
        _ = try fixture.library.replace(id: fixture.source.id, title: "New title", text: "Changed text")
        XCTAssertEqual(context, retained, "A captured answer never substitutes a newer source.")
        XCTAssertEqual(context.excerpts[1].text, "A generated note needs review.")
    }

    func testPreparedAttemptedAndCitedRemainDistinct() throws {
        let fixture = try fixture(); defer { fixture.clean() }
        var receipt = try receipt(fixture)
        let ids = try XCTUnwrap(receipt.sourceContext).excerpts.map(\.id)
        var evidence = AssistantEvidenceReceipt(contextEnabled: false)
        evidence.reasoningSourceIDsOffered = ids
        evidence.sourceIDsCited = ids
        receipt.evidence = evidence
        XCTAssertTrue(try XCTUnwrap(AssistantSourceEvidence(receipt: receipt)).rows.allSatisfy { $0.delivery == .prepared })
        receipt.requestStarted = true
        receipt.evidence?.reasoningSourceIDsDispatched = [ids[1]]
        XCTAssertEqual(AssistantSourceEvidence(receipt: receipt)?.rows.map(\.delivery), [.prepared, .attempted])
        receipt.state = .complete
        XCTAssertEqual(AssistantSourceEvidence(receipt: receipt)?.rows.map(\.delivery), [.prepared, .cited])
        receipt.evidence?.sourceIDsCited = [ids[0], "foreign-reference"]
        let projection = try XCTUnwrap(AssistantSourceEvidence(receipt: receipt))
        XCTAssertEqual(projection.rows.map(\.delivery), [.prepared, .attempted])
        XCTAssertEqual(projection.unmatchedCitationCount, 1)
    }

    func testFailedCancelledOrMissingTelemetryNeverClaimsCited() throws {
        let fixture = try fixture(); defer { fixture.clean() }
        var receipt = try receipt(fixture)
        let ids = try XCTUnwrap(receipt.sourceContext).excerpts.map(\.id)
        receipt.requestStarted = true
        receipt.evidence = AssistantEvidenceReceipt(contextEnabled: true)
        receipt.evidence?.reasoningSourceIDsDispatched = ids
        receipt.evidence?.sourceIDsCited = ids
        for state in [AssistantLaneState.pending, .failed, .cancelled] {
            receipt.state = state
            XCTAssertTrue(try XCTUnwrap(AssistantSourceEvidence(receipt: receipt)).rows.allSatisfy { $0.delivery == .attempted })
        }
        receipt.state = .complete; receipt.evidence = nil
        let projection = try XCTUnwrap(AssistantSourceEvidence(receipt: receipt))
        XCTAssertTrue(projection.status.contains("not reported"))
        XCTAssertTrue(projection.rows.allSatisfy { $0.delivery == .prepared })
    }

    func testNoContextOrExternalLaneCannotExposeLocalExcerpts() throws {
        let fixture = try fixture(); defer { fixture.clean() }
        var external = try receipt(fixture, provider: .codex)
        XCTAssertNil(AssistantSourceEvidence(receipt: external))
        external.sourceContext = nil
        XCTAssertNil(AssistantSourceEvidence(receipt: external))
        let ordinary = AssistantRequest(prompt: "Hello", sourceName: nil, sourceText: "",
            sourceRevision: 1, placementRevision: 1, tone: "clear", replyLength: 0.5)
        XCTAssertNil(AssistantSourceContext.capture(ordinary))
    }

    func testReadingCaptureKeepsOnlyPreparedSpansAndUnknownOriginIsExplicit() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = CompanionStore(preferenceURL: dir.appendingPathComponent("preferences.json"), allowsPlay: false,
            tokenSteward: TokenStewardStore())
        defer { store.cancelWork(); store.disconnectAssistant() }
        let text = "# Plan\nRead the original before relying on a summary."
        store.share(text: text, name: "Plan")
        let question = "What is the plan?"
        let preview = try XCTUnwrap(store.prepareReading(question: question, text: text, selection: nil))
        let request = AssistantRequest(prompt: question, sourceName: "Plan", sourceText: text,
            sourceRevision: store.sourceRevision, placementRevision: 1, tone: "clear", replyLength: 0.5,
            localControl: preview.control, localReading: preview.plan)
        let context = try XCTUnwrap(AssistantSourceContext.capture(request))
        XCTAssertEqual(context.excerpts.map(\.id), preview.plan.sourceIDs)
        XCTAssertEqual(context.excerpts.map(\.text), preview.plan.sections.map(\.text))
        XCTAssertTrue(context.excerpts.allSatisfy { $0.provenance == nil && $0.kind == .passage })
        XCTAssertTrue(store.tokenSteward.tasks.isEmpty, "Preparing evidence makes no model request.")
    }

    private struct Fixture {
        let directory: URL
        let library: ReadingSourceLibrary
        let source: ReadingSourceSnapshot
        let page: KnowledgePage
        let request: AssistantRequest
        func clean() { try? FileManager.default.removeItem(at: directory) }
    }
    private func fixture() throws -> Fixture {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = ReadingSourceLibrary(url: dir.appendingPathComponent("reading.json"))
        let source = try library.keep(title: "Research orientation", text: "A generated note needs review.",
            provenance: .init(origin: .model, acquisition: .userCopy, attribution: "PRIVATE-ATTRIBUTION"))
        let anchor = try library.makeAnchor(sourceID: source.id, range: NSRange(location: 0, length: source.text.utf16.count))
        let draft = try library.saveKnowledgePage(title: "Review", body: "Inspect the original evidence.", kind: .claim, anchors: [anchor])
        let page = try library.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        let knowledge = try XCTUnwrap(KnowledgePageContext.make(page: page, quotes: [source.text]))
        let request = AssistantRequest(prompt: "Explain this", sourceName: nil, sourceText: "",
            sourceRevision: 1, placementRevision: 1, tone: "clear", replyLength: 0.5, localKnowledge: knowledge)
        return Fixture(directory: dir, library: library, source: source, page: page, request: request)
    }
    private func receipt(_ fixture: Fixture, provider: AssistantProvider = .qwen) throws -> AssistantLaneReceipt {
        var value = AssistantLaneReceipt(requestID: UUID().uuidString, route: .automatic, provider: provider,
            context: ContextTicket(generation: 1, placement: 1, source: 1, selection: 1), inputDigest: String(repeating: "a", count: 64),
            inputContract: AssistantRequest.inputContract, deadline: Date(), modelIdentity: nil, state: .pending)
        value.sourceContext = try XCTUnwrap(AssistantSourceContext.capture(fixture.request))
        return value
    }
}
