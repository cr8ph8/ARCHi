import XCTest
@testable import ARCHiDesktop

final class KnowledgePageContextTests: XCTestCase {
    func testBindingIsTextFreeStrictAndBindsTheWholePage() throws {
        let page = page()
        let binding = page.binding
        XCTAssertTrue(binding.isValid)
        let data = try JSONEncoder().encode(binding)
        XCTAssertEqual(try JSONDecoder().decode(KnowledgePageBinding.self, from: data), binding)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["id", "revision", "digest"])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(page.body))
        object["text"] = "Unexpected raw prose"
        XCTAssertThrowsError(try JSONDecoder().decode(KnowledgePageBinding.self,
            from: JSONSerialization.data(withJSONObject: object)))
        XCTAssertTrue(KnowledgePageBinding.valid(nil))
        XCTAssertFalse(KnowledgePageBinding.valid([]))
        XCTAssertFalse(KnowledgePageBinding.valid([binding, binding]))
        XCTAssertFalse(KnowledgePageBinding(id: binding.id, revision: 0, digest: binding.digest).isValid)
        let changed = KnowledgePage(id: page.id, revision: page.revision, title: page.title,
            body: page.body + " Changed interpretation.", kind: page.kind, anchors: page.anchors,
            state: page.state, createdAt: page.createdAt, updatedAt: page.updatedAt, review: page.review)
        XCTAssertNotEqual(changed.binding.digest, binding.digest)
    }

    func testExactReviewedContextRejectsWrongQuotesRangesAndOversizedEscaping() throws {
        let quote = "Exact e\u{301} and 🙂 source."
        let reviewed = page(quote: quote)
        let context = try XCTUnwrap(KnowledgePageContext.make(page: reviewed, quotes: [quote]))
        XCTAssertTrue(context.isValid)
        XCTAssertEqual(context.pages, [reviewed])
        XCTAssertEqual(context.bindings, [reviewed.binding])
        XCTAssertEqual(context.readingSources, reviewed.anchors.map(\.source))
        XCTAssertEqual(context.sourceIDs.count, 2)
        XCTAssertEqual(Set(context.sourceIDs).count, 2)
        XCTAssertLessThanOrEqual(context.utf8ByteCount, KnowledgePageContext.maximumUTF8Bytes)
        let retained = try XCTUnwrap(context.modelInput["pages"]?.array?.first?["passages"]?.array?.first?["text"]?.string)
        XCTAssertTrue(retained.utf8.elementsEqual(quote.utf8))
        XCTAssertNil(KnowledgePageContext.make(page: reviewed, quotes: ["Different source."]))
        XCTAssertNil(KnowledgePageContext.make(page: reviewed, quotes: []))
        XCTAssertNil(KnowledgePageContext.make(page: page(quote: quote, anchorLength: quote.utf16.count + 1), quotes: [quote]))
        XCTAssertNil(KnowledgePageContext.make(page: page(quote: quote, state: .draft), quotes: [quote]))
        XCTAssertNil(KnowledgePageContext.make(pages: [reviewed, reviewed], quotes: [[quote], [quote]]))
        let escaped = String(repeating: "\"", count: 9_000)
        XCTAssertNil(KnowledgePageContext.make(page: page(quote: escaped), quotes: [escaped]),
            "The cap includes escaped JSON, so an otherwise valid page is rejected whole.")
    }

    func testKnowledgeStaysLocalSurvivesConversationReplacementAndRejectsMixedScope() throws {
        let quote = "Private quotation selected for this request."
        let context = try XCTUnwrap(KnowledgePageContext.make(page: page(quote: quote), quotes: [quote]))
        let base = request()
        let local = request(knowledge: context)
        XCTAssertTrue(local.hasValidLocalKnowledge)
        XCTAssertEqual(try json(local.input), try json(base.input))
        XCTAssertEqual(try json(local.codexInput), try json(base.codexInput))
        XCTAssertFalse(local.codexInput.contains(quote))
        XCTAssertFalse(local.codexInput.contains("knowledge-page-"))
        XCTAssertTrue(local.localInput.contains(quote))
        XCTAssertEqual(try json(local.localContextInput)["localKnowledge"], context.modelInput)
        XCTAssertEqual(local.localSourceIDs, ["current-question"] + context.sourceIDs)
        let continued = local.replacingLocalConversation([.init(question: "Earlier", answer: "Earlier answer")])
        XCTAssertEqual(continued.localKnowledge, context)
        XCTAssertTrue(continued.hasValidLocalKnowledge)
        let settingsConstructor = AssistantRequest(prompt: base.prompt, sourceName: nil, sourceText: "",
            sourceRevision: 0, placementRevision: 0, settings: base.settings, localKnowledge: context)
        XCTAssertEqual(settingsConstructor.localKnowledge, context)
        let mixed = AssistantRequest(prompt: base.prompt, sourceName: "Another document", sourceText: "Unselected text",
            sourceRevision: 1, placementRevision: 0, settings: base.settings, localKnowledge: context)
        XCTAssertFalse(mixed.hasValidLocalKnowledge)
        XCTAssertEqual(mixed.localContextInput, "")
        XCTAssertFalse(mixed.codexInput.contains(quote))
    }

    private func request(knowledge: KnowledgePageContext? = nil) -> AssistantRequest {
        AssistantRequest(prompt: "Explain this selected claim.", sourceName: nil, sourceText: "",
            sourceRevision: 0, placementRevision: 0, tone: "Calm", replyLength: 0.5, localKnowledge: knowledge)
    }

    private func page(quote: String = "Exact quoted source.", anchorLength: Int? = nil,
                      state: KnowledgePageState = .reviewed) -> KnowledgePage {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let source = ReadingSourceBinding(id: "91EFB0BD-6618-4B69-B13E-AF502BC1786F", revision: 1,
            digest: LessonSource.digest(of: "Text:" + quote))
        let anchor = KnowledgeAnchor(source: source, location: 5, length: anchorLength ?? quote.utf16.count,
            quoteDigest: LessonSource.digest(of: quote))
        return KnowledgePage(id: "4BFB76B0-E15B-4F55-B54E-4BE634163301", revision: 1,
            title: "A selected claim", body: "Private authored interpretation.", kind: .claim,
            anchors: [anchor], state: state, createdAt: date, updatedAt: date,
            review: state == .draft ? nil : .init(id: "49FC1E74-0627-4F60-B0D5-3D4FBEAF5850", state: state, recordedAt: date))
    }

    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }
}
