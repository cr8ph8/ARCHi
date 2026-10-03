import XCTest
@testable import ARCHiDesktop

final class KnowledgeRetrievalTests: XCTestCase {
    func testStructureAwareSectionsRetainExactUnicodeSourceAnchors() throws {
        let source = source(text: "# Guide\nA café 🙂 introduction.\n## Cooling\nKeep the cooling fan clear.\n## Storage\nKeep dry.\n")
        let result = try search("cooling", sources: [source])
        let hit = try XCTUnwrap(result.hits.first)
        XCTAssertEqual(hit.kind, .section)
        XCTAssertEqual(hit.title, "Guide › Cooling")
        XCTAssertEqual(hit.sourceTitle, source.title)
        XCTAssertEqual(hit.score, 10)
        XCTAssertEqual(hit.matchedTerms, ["cooling"])
        XCTAssertNil(hit.pageBinding)
        let anchor = try XCTUnwrap(hit.anchor)
        XCTAssertEqual(anchor.source, source.binding)
        XCTAssertTrue(hit.text.utf8.elementsEqual((source.text as NSString).substring(with: anchor.range).utf8))
        XCTAssertEqual(anchor.quoteDigest, LessonSource.digest(of: hit.text))
        XCTAssertEqual(hit.id, DocumentReadingPlan.index(source.text, sourceDigest: source.digest,
            sourceID: source.id, sourceTitle: source.title, revision: source.revision).first { $0.location == anchor.location }?.id)
        let changed = ReadingSourceSnapshot(id: source.id, title: source.title, revision: 2, text: source.text)
        XCTAssertNotEqual(try search("cooling", sources: [changed]).hits.first?.id, hit.id)
    }

    func testFenceHeadingsStayInsideTheirRealSection() throws {
        let source = source(text: "# Guide\n```markdown\n# not-a-heading needle\n```\n## End\nDone.\n")
        let hit = try XCTUnwrap(search("needle", sources: [source]).hits.first)
        XCTAssertEqual(hit.title, "Guide")
        XCTAssertTrue(hit.text.contains("# not-a-heading needle"))
    }

    func testReviewedPageMatchesLexicallyWithoutInventingBodySourceSpan() throws {
        let source = source(text: "Keep an accurate résumé with exact dates.")
        let page = page(source: source, title: "Résumé practice", body: "Describe the work clearly.")
        let result = try search("RESUME", sources: [source], pages: [page])
        let hit = try XCTUnwrap(result.hits.first { $0.kind == .page })
        XCTAssertEqual(hit.pageBinding, page.binding)
        XCTAssertEqual(hit.text, page.body)
        XCTAssertNil(hit.anchor, "An authored note is not a verbatim source span.")
        XCTAssertEqual(hit.supportingAnchors, page.anchors)
        XCTAssertEqual(hit.matchedTerms, ["resume"])
        XCTAssertEqual(hit.score, 9, "Title presence plus one supporting-quotation match, not confidence.")
        XCTAssertTrue(try search("curriculum vitae", sources: [source], pages: [page]).hits.isEmpty,
            "No semantic or synonym expansion is claimed.")
        XCTAssertTrue(try search("the and of", sources: [source], pages: [page]).hits.isEmpty)
    }

    func testLatestWithdrawalDraftAndChangedSupportExcludeEarlierReviewedPages() throws {
        let source = source(text: "Clear instructions support careful work.")
        let reviewed = page(source: source)
        let withdrawn = page(source: source, revision: 3, state: .withdrawn)
        let result = try search("clear", sources: [source], pages: [reviewed, withdrawn])
        XCTAssertFalse(result.hits.contains { $0.kind == .page })
        XCTAssertEqual(result.excludedPageCount, 1)
        let draft = page(source: source, revision: 3, state: .draft)
        XCTAssertFalse(try search("clear", sources: [source], pages: [reviewed, draft]).hits.contains { $0.kind == .page })
        let replacement = ReadingSourceSnapshot(id: source.id, title: source.title, revision: 2, text: source.text)
        XCTAssertFalse(try search("clear", sources: [replacement], pages: [reviewed]).hits.contains { $0.kind == .page })
        XCTAssertTrue(try search("clear", sources: [], pages: [reviewed]).hits.isEmpty)
    }

    func testConflictingIdentitiesAndInvalidLatestVersionFailClosed() throws {
        let source = source(text: "Clear instructions.")
        let reviewed = page(source: source)
        let duplicate = ReadingSourceSnapshot(id: source.id.lowercased(), title: source.title, revision: 2, text: "Clear but different.")
        let result = try search("clear", sources: [source, duplicate], pages: [reviewed])
        XCTAssertTrue(result.hits.isEmpty)
        XCTAssertEqual(result.excludedSourceCount, 2)
        XCTAssertEqual(result.excludedPageCount, 1)
        let invalid = page(source: source, revision: 3, body: "")
        XCTAssertFalse(try search("clear", sources: [source], pages: [reviewed, invalid]).hits.contains { $0.kind == .page })
        XCTAssertFalse(try search("clear", sources: [source], pages: [reviewed, reviewed]).hits.contains { $0.kind == .page })
        XCTAssertThrowsError(try KnowledgeRetrieval.search(query: "clear", sources: [source], pages: [reviewed], libraryIsCurrent: false)) {
            XCTAssertEqual($0 as? KnowledgeRetrievalError, .unavailableLibrary)
        }
    }

    func testMalformedQuotationAndSplitSurrogateCannotSupportPageHit() throws {
        let source = source(text: "🙂 Clear instructions.")
        let wrongQuote = KnowledgeAnchor(source: source.binding, location: 0, length: source.text.utf16.count,
            quoteDigest: LessonSource.digest(of: "Different text"))
        let split = KnowledgeAnchor(source: source.binding, location: 1, length: 1,
            quoteDigest: LessonSource.digest(of: "�"))
        for anchor in [wrongQuote, split] {
            let page = page(source: source, anchor: anchor)
            XCTAssertFalse(try search("clear", sources: [source], pages: [page]).hits.contains { $0.kind == .page })
        }
    }

    func testRankingIsStableAcrossInputOrderAndResultLimitReportsOmissions() throws {
        let first = source(id: "00000000-0000-0000-0000-000000000001", text: "# Clear\nClear work.\n## More\nClear prose.")
        let second = source(id: "00000000-0000-0000-0000-000000000002", text: "# Clear\nClear work.")
        let firstPage = page(source: first, id: "00000000-0000-0000-0000-000000000003")
        let secondPage = page(source: second, id: "00000000-0000-0000-0000-000000000004")
        let forward = try search("clear", sources: [first, second], pages: [firstPage, secondPage])
        let reverse = try search("clear", sources: [second, first], pages: [secondPage, firstPage])
        XCTAssertEqual(forward, reverse)
        let limited = try KnowledgeRetrieval.search(query: "clear", sources: [first, second], pages: [firstPage, secondPage],
            libraryIsCurrent: true, maximumResults: 2)
        XCTAssertEqual(limited.hits, Array(forward.hits.prefix(2)))
        XCTAssertEqual(limited.omittedHitCount, forward.matchingCount - 2)
        XCTAssertTrue(limited.isPartial)
    }

    func testPageOnlySearchAppliesKindFilterBeforeMixedResultQuota() throws {
        let source = source(text: (1...6).map { "# Needle \($0)\nNeedle source passage \($0).\n" }.joined())
        let reviewed = page(source: source, title: "Reviewed interpretation", body: "A concise interpretation of the cited evidence.")
        let mixed = try KnowledgeRetrieval.search(query: "needle", sources: [source], pages: [reviewed],
            libraryIsCurrent: true, maximumResults: 6)
        XCTAssertEqual(mixed.hits.count, 6)
        XCTAssertTrue(mixed.hits.allSatisfy { $0.kind == .section },
                      "Higher-ranked source passages consume the ordinary mixed quota.")
        XCTAssertEqual(mixed.omittedHitCount, 1)
        let explicitMixed = try KnowledgeRetrieval.search(query: "needle", sources: [source], pages: [reviewed],
            libraryIsCurrent: true, maximumResults: 6, pagesOnly: false)
        XCTAssertEqual(explicitMixed, mixed, "Existing callers retain mixed retrieval by default.")

        let pageOnly = try KnowledgeRetrieval.search(query: "needle", sources: [source], pages: [reviewed],
            libraryIsCurrent: true, maximumResults: 6, pagesOnly: true)
        XCTAssertEqual(pageOnly.hits.count, 1)
        XCTAssertEqual(pageOnly.hits.first?.pageBinding, reviewed.binding)
        XCTAssertEqual(pageOnly.hits.first?.supportingAnchors, reviewed.anchors)
        XCTAssertEqual(pageOnly.matchingCount, 1)
        XCTAssertEqual(pageOnly.omittedHitCount, 0)

        let changed = ReadingSourceSnapshot(id: source.id, title: source.title, revision: 2, text: source.text)
        XCTAssertTrue(try KnowledgeRetrieval.search(query: "needle", sources: [changed], pages: [reviewed],
            libraryIsCurrent: true, maximumResults: 6, pagesOnly: true).hits.isEmpty,
            "Restricting result kind must not bypass exact supporting-source validation.")
    }

    func testEncodedContextCapOmitsWholeOversizedPageWithoutClippingSourceText() throws {
        let source = source(text: "Needle is the exact source word.")
        let page = page(source: source, title: "Needle", body: String(repeating: "\"", count: 8_100) + " needle")
        let result = try search("needle", sources: [source], pages: [page])
        XCTAssertEqual(result.matchingCount, 2)
        XCTAssertEqual(result.hits.count, 1)
        XCTAssertEqual(result.hits.first?.kind, .section)
        XCTAssertEqual(result.hits.first?.text, source.text)
        XCTAssertEqual(result.omittedHitCount, 1)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(result.contextUTF8Bytes, try encoder.encode(result.hits).count)
        XCTAssertLessThanOrEqual(result.contextUTF8Bytes, KnowledgeRetrieval.maximumContextUTF8Bytes)
    }

    func testQueryAndCorpusBoundsAreExplicit() throws {
        for query in [String(repeating: "a", count: 513), (0...32).map { "term\($0)" }.joined(separator: " "), "clear\u{0000}"] {
            XCTAssertThrowsError(try search(query, sources: [])) {
                XCTAssertEqual($0 as? KnowledgeRetrievalError, .invalidQuery)
            }
        }
        for limit in [0, 13] {
            XCTAssertThrowsError(try KnowledgeRetrieval.search(query: "clear", sources: [], pages: [],
                libraryIsCurrent: true, maximumResults: limit)) {
                XCTAssertEqual($0 as? KnowledgeRetrievalError, .invalidResultLimit)
            }
        }
        XCTAssertThrowsError(try search("clear", sources: Array(repeating: source(), count: 9))) {
            XCTAssertEqual($0 as? KnowledgeRetrievalError, .sourceLimit)
        }
        let source = source()
        XCTAssertThrowsError(try search("clear", sources: [source], pages: Array(repeating: page(source: source), count: 65))) {
            XCTAssertEqual($0 as? KnowledgeRetrievalError, .pageLimit)
        }
        let manySections = self.source(text: (0...2_048).map { "# Clear \($0)\n" }.joined())
        XCTAssertThrowsError(try search("clear", sources: [manySections])) {
            XCTAssertEqual($0 as? KnowledgeRetrievalError, .sectionLimit)
        }
    }

    private func search(_ query: String, sources: [ReadingSourceSnapshot], pages: [KnowledgePage] = []) throws -> KnowledgeRetrievalResult {
        try KnowledgeRetrieval.search(query: query, sources: sources, pages: pages, libraryIsCurrent: true)
    }

    private func source(id: String = "A8E4747B-46F4-4B74-AD46-E95B50DF5530", text: String = "Clear instructions.") -> ReadingSourceSnapshot {
        ReadingSourceSnapshot(id: id, title: "Kept guide", revision: 1, text: text)
    }

    private func page(source: ReadingSourceSnapshot, id: String = "1ED40F42-9149-4732-A39A-4C61A60ED1E6",
                      revision: UInt64 = 2, state: KnowledgePageState = .reviewed, title: String = "Clear methods",
                      body: String = "Clear wording can help a reader.", anchor: KnowledgeAnchor? = nil) -> KnowledgePage {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let updated = date.addingTimeInterval(Double(revision))
        let support = anchor ?? KnowledgeAnchor(source: source.binding, location: 0, length: source.text.utf16.count,
            quoteDigest: LessonSource.digest(of: source.text))
        return KnowledgePage(id: id, revision: revision, title: title, body: body, kind: .concept, anchors: [support],
            state: state, createdAt: date, updatedAt: updated,
            review: state == .draft ? nil : .init(id: "C84CC416-6484-4C79-A841-973F64187522", state: state, recordedAt: updated))
    }
}
