import XCTest
@testable import ARCHiDesktop

final class KnowledgeLinkRetrievalTests: XCTestCase {
    func testReviewedNeighborRetainsExactDeclarationAndDirectionWithoutLexicalScore() throws {
        let source = source()
        let root = page(1, source: source, title: "Aurora")
        let neighbor = page(2, source: source, title: "Alternative explanation")
        let history = link(1, from: neighbor, to: root, kind: .contradicts)
        let result = try search(pages: [root, neighbor], sources: [source], links: history)
        XCTAssertEqual(result.hits.map(\.pageBinding), [root.binding, neighbor.binding])
        XCTAssertNil(result.hits.first?.viaLink)
        let related = try XCTUnwrap(result.hits.last)
        XCTAssertEqual(related.viaLink, history.last)
        XCTAssertEqual(related.viaLink?.from, neighbor.binding, "Incoming traversal must not reverse the declaration.")
        XCTAssertEqual(related.viaLink?.to, root.binding)
        XCTAssertEqual(related.viaLink?.kind, .contradicts)
        XCTAssertEqual(related.score, 0)
        XCTAssertEqual(related.matchedTerms, [])
        XCTAssertEqual(result.matchingCount, 1)
        XCTAssertEqual(result.relatedCount, 1)
        XCTAssertEqual(result.omittedHitCount, 0)
    }

    func testExpansionStopsAfterOneHopAndCyclesDoNotDuplicatePages() throws {
        let source = source()
        let root = page(1, source: source, title: "Aurora")
        let neighbor = page(2, source: source)
        let distant = page(3, source: source)
        let links = link(1, from: root, to: neighbor) + link(2, from: neighbor, to: root)
            + link(3, from: neighbor, to: distant)
        let result = try search(pages: [root, neighbor, distant], sources: [source], links: links)
        XCTAssertEqual(result.hits.map(\.pageBinding), [root.binding, neighbor.binding])
        XCTAssertEqual(result.relatedCount, 1)
        let reordered = try search(pages: [distant, neighbor, root], sources: [source], links: Array(links.reversed()))
        XCTAssertEqual(result, reordered)
    }

    func testSourceCorrectionRemovalAndPageRevisionInvalidateOneHopSuggestion() throws {
        let source = source()
        let support = self.source(2)
        let root = page(1, source: source, title: "Aurora")
        let neighbor = page(2, source: support)
        let history = link(1, from: root, to: neighbor)
        let corrected = page(2, source: support, revision: 3)
        let correctedResult = try search(pages: [root, neighbor, corrected], sources: [source, support], links: history)
        XCTAssertEqual(correctedResult.hits.map(\.pageBinding), [root.binding])
        let replacement = ReadingSourceSnapshot(id: support.id, title: support.title, revision: 2, text: support.text)
        for sources in [[source], [source, replacement]] {
            let result = try search(pages: [root, neighbor], sources: sources, links: history)
            XCTAssertEqual(result.hits.map(\.pageBinding), [root.binding])
            XCTAssertEqual(result.relatedCount, 0)
        }
    }

    func testWithdrawnDraftConflictingAndIncompleteLinkHistoriesCannotResurrectReview() throws {
        let source = source()
        let root = page(1, source: source, title: "Aurora")
        let neighbor = page(2, source: source)
        let history = link(1, from: root, to: neighbor)
        let reviewed = try XCTUnwrap(history.last)
        let withdrawn = version(of: reviewed, revision: 3, state: .withdrawn)
        let draft = version(of: reviewed, revision: 3, state: .draft)
        for links in [[reviewed], [history[0]], history + [withdrawn], history + [draft], history + [reviewed]] {
            let result = try search(pages: [root, neighbor], sources: [source], links: links)
            XCTAssertEqual(result.hits.map(\.pageBinding), [root.binding])
            XCTAssertEqual(result.relatedCount, 0)
        }
    }

    func testDroppedLexicalRootCannotProduceOrphanRelatedHit() throws {
        let source = source()
        let oversizedRoot = page(1, source: source, title: "Aurora", body: String(repeating: "\"", count: 8_100))
        let neighbor = page(2, source: source)
        let result = try search(pages: [oversizedRoot, neighbor], sources: [source],
            links: link(1, from: oversizedRoot, to: neighbor))
        XCTAssertTrue(result.hits.isEmpty)
        XCTAssertEqual(result.matchingCount, 1)
        XCTAssertEqual(result.relatedCount, 0)
        XCTAssertEqual(result.omittedHitCount, 1)
    }

    func testLexicalHitsKeepPriorityAndOnlyAdmittedRootsExpand() throws {
        let source = source()
        let first = page(1, source: source, title: "Aurora")
        let second = page(2, source: source, title: "Aurora")
        let neighbor = page(3, source: source)
        let links = link(1, from: second, to: neighbor)
        let limited = try search(pages: [first, second, neighbor], sources: [source], links: links, maximumResults: 1)
        XCTAssertEqual(limited.hits.map(\.pageBinding), [first.binding])
        XCTAssertEqual(limited.relatedCount, 0, "The second lexical page did not enter the result budget.")
        let two = try search(pages: [first, second, neighbor], sources: [source], links: links, maximumResults: 2)
        XCTAssertEqual(two.hits.map(\.pageBinding), [first.binding, second.binding])
        XCTAssertTrue(two.hits.allSatisfy { $0.viaLink == nil })
        XCTAssertEqual(two.relatedCount, 1)
        XCTAssertEqual(two.omittedHitCount, 1)
    }

    func testLinkMetadataConsumesTheSameEncodedContextBudget() throws {
        let source = source()
        let root = page(1, source: source, title: "Aurora", body: String(repeating: "a", count: 6_750))
        let neighbor = page(2, source: source, body: String(repeating: "b", count: 6_750))
        let history = link(1, from: root, to: neighbor, rationale: String(repeating: "r", count: 2_048))
        let result = try search(pages: [root, neighbor], sources: [source], links: history)
        XCTAssertEqual(result.hits.map(\.pageBinding), [root.binding])
        XCTAssertEqual(result.relatedCount, 1)
        XCTAssertEqual(result.omittedHitCount, 1)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let hypothetical = KnowledgeRetrievalHit(id: "knowledge-page-" + neighbor.binding.digest, kind: .page,
            title: neighbor.title, text: neighbor.body, sourceTitle: nil, score: 0, matchedTerms: [],
            pageBinding: neighbor.binding, anchor: nil, supportingAnchors: neighbor.anchors)
        XCTAssertLessThanOrEqual(try encoder.encode(result.hits + [hypothetical]).count, KnowledgeRetrieval.maximumContextUTF8Bytes,
            "Without the link metadata both pages fit; omitting it from accounting would breach the cap.")
        XCTAssertEqual(result.contextUTF8Bytes, try encoder.encode(result.hits).count)
        XCTAssertLessThanOrEqual(result.contextUTF8Bytes, KnowledgeRetrieval.maximumContextUTF8Bytes)
    }

    func testUnavailableRelationshipDependencyDoesNotLeakThroughLink() throws {
        let source = source()
        let root = page(1, source: source, title: "Aurora")
        let person = page(2, source: source, relationship: .init(kind: .person))
        let encounter = page(3, source: source, relationship: .init(kind: .encounter, person: person.binding))
        let correctedPerson = page(2, source: source, revision: 3, relationship: .init(kind: .person))
        let links = link(1, from: root, to: encounter)
        let result = try search(pages: [root, person, correctedPerson, encounter], sources: [source], links: links)
        XCTAssertEqual(result.hits.map(\.pageBinding), [root.binding])
        XCTAssertEqual(result.relatedCount, 0)
    }

    func testStaleDerivedSourceParentExcludesLinkedNeighbor() throws {
        let source = source()
        let parent = self.source(2)
        let provenance = ReadingSourceProvenance(origin: .model, acquisition: .derivedCopy,
            parents: [.init(binding: parent.binding)], declaredAt: date)
        let derived = ReadingSourceSnapshot(id: id(3, prefix: "10000000"), title: "Derived copy", revision: 1,
            text: "A derived supporting passage.", provenance: provenance)
        let root = page(1, source: source, title: "Aurora")
        let neighbor = page(2, source: derived)
        let links = link(1, from: root, to: neighbor)
        let current = try search(pages: [root, neighbor], sources: [source, parent, derived], links: links)
        XCTAssertEqual(current.hits.map(\.pageBinding), [root.binding, neighbor.binding])
        let replacement = ReadingSourceSnapshot(id: parent.id, title: parent.title, revision: 2, text: parent.text)
        let stale = try search(pages: [root, neighbor], sources: [source, replacement, derived], links: links)
        XCTAssertEqual(stale.hits.map(\.pageBinding), [root.binding])
        XCTAssertEqual(stale.relatedCount, 0)
    }

    func testLinkInputHasAnExplicitHistoryLimit() throws {
        let source = source()
        let root = page(1, source: source, title: "Aurora")
        let neighbor = page(2, source: source)
        let draft = try XCTUnwrap(link(1, from: root, to: neighbor).first)
        XCTAssertThrowsError(try search(pages: [root, neighbor], sources: [source], links: Array(repeating: draft, count: 129))) {
            XCTAssertEqual($0 as? KnowledgeRetrievalError, .linkLimit)
        }
    }

    private func search(pages: [KnowledgePage], sources: [ReadingSourceSnapshot], links: [KnowledgePageLink],
                        maximumResults: Int = KnowledgeRetrieval.maximumResults) throws -> KnowledgeRetrievalResult {
        try KnowledgeRetrieval.search(query: "Aurora", sources: sources, pages: pages, links: links,
            libraryIsCurrent: true, maximumResults: maximumResults)
    }

    private func source(_ index: Int = 1) -> ReadingSourceSnapshot {
        ReadingSourceSnapshot(id: id(index, prefix: "10000000"), title: "Kept source", revision: 1,
            text: "An exact supporting passage.")
    }

    private func page(_ index: Int, source: ReadingSourceSnapshot, revision: UInt64 = 2,
                      title: String = "Related note", body: String = "Authored interpretation.",
                      relationship: RelationshipMemoryMetadata? = nil) -> KnowledgePage {
        let updated = date.addingTimeInterval(Double(revision))
        let anchor = KnowledgeAnchor(source: source.binding, location: 0, length: source.text.utf16.count,
            quoteDigest: source.digest)
        return KnowledgePage(id: id(index), revision: revision, title: title, body: body,
            kind: relationship == nil ? .concept : .claim, anchors: [anchor], state: .reviewed,
            createdAt: date, updatedAt: updated,
            review: .init(id: id(index, prefix: "30000000"), state: .reviewed, recordedAt: updated), relationship: relationship)
    }

    private func link(_ index: Int, from: KnowledgePage, to: KnowledgePage,
                      kind: KnowledgePageLinkKind = .supports, rationale: String = "User reviewed this relationship.") -> [KnowledgePageLink] {
        let created = max(from.updatedAt, to.updatedAt).addingTimeInterval(1)
        let draft = KnowledgePageLink(id: id(index, prefix: "40000000"), revision: 1,
            from: from.binding, to: to.binding, kind: kind, rationale: rationale, state: .draft,
            createdAt: created, updatedAt: created)
        return [draft, version(of: draft, revision: 2, state: .reviewed)]
    }

    private func version(of link: KnowledgePageLink, revision: UInt64, state: KnowledgePageState) -> KnowledgePageLink {
        let updated = link.createdAt.addingTimeInterval(Double(revision))
        return KnowledgePageLink(id: link.id, revision: revision, from: link.from, to: link.to,
            kind: link.kind, rationale: link.rationale, state: state, createdAt: link.createdAt, updatedAt: updated,
            review: state == .draft ? nil : .init(id: reviewID(for: link.id, revision: revision), state: state, recordedAt: updated))
    }

    private var date: Date { Date(timeIntervalSince1970: 1_800_000_000) }
    private func id(_ index: Int, prefix: String = "20000000") -> String {
        prefix + "-0000-0000-0000-" + String(format: "%012d", index)
    }
    private func reviewID(for linkID: String, revision: UInt64) -> String {
        "5000000" + String(revision) + String(linkID.dropFirst(8))
    }
}
