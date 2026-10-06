import Foundation
import XCTest
@testable import ARCHiDesktop

@MainActor
final class KnowledgeGraphMeaningTests: XCTestCase {
    func testPageLifecycleComesFromOwnerAndProjectionDoesNotWrite() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let library = fixture.library
        let source = try fixture.source()
        let anchor = try library.makeAnchor(sourceID: source.id, range: NSRange(location: 0, length: 8))
        let draft = try library.saveKnowledgePage(title: "Reviewed and retained", body: "A title is not a review.",
            kind: .claim, anchors: [anchor])
        var graph = try fixture.snapshotWithoutWriting()
        XCTAssertEqual(try pageNode(draft, in: graph).presentationState, .candidate)
        XCTAssertEqual(try sourceNode(source.binding, in: graph).presentationState, .recorded)

        let reviewed = try library.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        graph = try fixture.snapshotWithoutWriting()
        XCTAssertEqual(try pageNode(reviewed, in: graph).presentationState, .reviewed)
        XCTAssertFalse(graph.nodes.contains { $0.id == KnowledgePageGraph.nodeID(draft.binding) })

        let withdrawn = try library.withdrawKnowledgePage(id: reviewed.id, expectedRevision: reviewed.revision)
        graph = try fixture.snapshotWithoutWriting()
        XCTAssertEqual(try pageNode(withdrawn, in: graph).presentationState, .withdrawn)
        XCTAssertFalse(graph.nodes.contains { $0.id == KnowledgePageGraph.nodeID(reviewed.binding) })
        let reopened = ReadingSourceLibrary(url: fixture.url)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(KnowledgePageGraph.append(to: .empty, library: reopened), graph)
    }

    func testSourceCorrectionKeepsExactUnavailableReferenceAndMarksReviewedPageNeedsReview() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let source = try fixture.source()
        let page = try fixture.reviewedPage(source: source, title: "An interpretation")
        let before = try fixture.snapshotWithoutWriting()
        let originalSourceID = try sourceNode(source.binding, in: before).id
        let pageID = KnowledgePageGraph.nodeID(page.binding)
        let originalLink = try XCTUnwrap(before.edges.first { $0.source == pageID && $0.target == originalSourceID })
        XCTAssertEqual(originalLink.relationship, .sourcePassage)

        let corrected = try fixture.library.replace(id: source.id, title: source.title, text: "Changed owner evidence.")
        let graph = try fixture.snapshotWithoutWriting()
        let unavailable = try sourceNode(source.binding, in: graph)
        let current = try sourceNode(corrected.binding, in: graph)
        XCTAssertEqual(try pageNode(page, in: graph).presentationState, .needsReview)
        XCTAssertEqual(unavailable.presentationState, .unavailable)
        XCTAssertEqual(current.presentationState, .recorded)
        XCTAssertEqual(unavailable.id, originalSourceID)
        XCTAssertNotEqual(unavailable.id, current.id)
        XCTAssertTrue(graph.edges.contains {
            $0.source == pageID && $0.target == originalSourceID && $0.relationship == .sourcePassage
        })
        XCTAssertFalse(graph.edges.contains { $0.source == pageID && $0.target == current.id })
    }

    func testStaleLibraryCannotPresentReviewedPagesOrSourcesAsCurrent() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let source = try fixture.source()
        let page = try fixture.reviewedPage(source: source, title: "Current at capture")
        let stale = ReadingSourceLibrary(url: fixture.url)
        _ = try fixture.library.replace(id: source.id, title: source.title, text: "A later source version.")
        XCTAssertFalse(stale.isCurrentOnDisk)
        let bytes = try Data(contentsOf: fixture.url)
        let graph = KnowledgePageGraph.append(to: .empty, library: stale)
        XCTAssertEqual(try pageNode(page, in: graph).presentationState, .needsReview)
        XCTAssertEqual(try sourceNode(source.binding, in: graph).presentationState, .unavailable)
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
    }

    func testCurrentDeclarationsCarryOwnerKindDirectionRationaleAndExactReference() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let source = try fixture.source()
        let from = try fixture.reviewedPage(source: source, title: "First page")
        let to = try fixture.reviewedPage(source: source, title: "Second page")
        let expectations: [(KnowledgePageLinkKind, CompanionGraphRelationship)] = [
            (.supports, .supports), (.contradicts, .contradicts), (.dependsOn, .dependsOn)
        ]
        var reviewed: [KnowledgePageLink] = []
        for (kind, expected) in expectations {
            let draft = try fixture.library.saveKnowledgeLink(from: from.binding, to: to.binding,
                kind: kind, rationale: "An explicitly authored \(kind.rawValue) interpretation.")
            XCTAssertFalse(try fixture.snapshotWithoutWriting().edges.contains { $0.reference == draft.identity })
            let link = try fixture.library.reviewKnowledgeLink(id: draft.id, expectedRevision: draft.revision)
            reviewed.append(link)
            let graph = try fixture.snapshotWithoutWriting()
            let edge = try XCTUnwrap(graph.edges.first { $0.id == link.identity })
            XCTAssertEqual(edge.source, KnowledgePageGraph.nodeID(from.binding))
            XCTAssertEqual(edge.target, KnowledgePageGraph.nodeID(to.binding))
            XCTAssertEqual(edge.relationship, expected)
            XCTAssertEqual(edge.rationale, link.rationale)
            XCTAssertEqual(edge.reference, link.identity)
        }
        let graph = try fixture.snapshotWithoutWriting()
        XCTAssertEqual(Set(declarations(in: graph).map(\.id)), Set(reviewed.map(\.identity)))
    }

    func testDistinctDeclarationsSurviveAndOnlyTheirOwnRevisionOrWithdrawalChangesTheEdge() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let source = try fixture.source()
        let from = try fixture.reviewedPage(source: source, title: "First page")
        let to = try fixture.reviewedPage(source: source, title: "Second page")
        let first = try fixture.reviewedLink(from: from, to: to, rationale: "First declared reason.")
        let second = try fixture.reviewedLink(from: from, to: to, rationale: "Independent declared reason.")
        var graph = try fixture.snapshotWithoutWriting()
        XCTAssertEqual(Set(declarations(in: graph).map(\.id)), Set([first.identity, second.identity]))
        XCTAssertEqual(Set(declarations(in: graph).compactMap(\.rationale)), Set([first.rationale, second.rationale]))

        let revised = try fixture.library.saveKnowledgeLink(id: first.id, expectedRevision: first.revision,
            from: from.binding, to: to.binding, kind: .supports, rationale: "A revised reason on the same endpoints.")
        graph = try fixture.snapshotWithoutWriting()
        XCTAssertEqual(declarations(in: graph).map(\.id), [second.identity], "A new draft cannot reuse an earlier review.")
        let rereviewed = try fixture.library.reviewKnowledgeLink(id: revised.id, expectedRevision: revised.revision)
        graph = try fixture.snapshotWithoutWriting()
        XCTAssertEqual(Set(declarations(in: graph).map(\.id)), Set([rereviewed.identity, second.identity]))
        XCTAssertFalse(graph.edges.contains { $0.id == first.identity })
        XCTAssertEqual(graph.edges.first { $0.id == rereviewed.identity }?.reference, rereviewed.identity)
        XCTAssertEqual(graph.edges.first { $0.id == rereviewed.identity }?.rationale, rereviewed.rationale)

        _ = try fixture.library.withdrawKnowledgeLink(id: second.id, expectedRevision: second.revision)
        graph = try fixture.snapshotWithoutWriting()
        XCTAssertEqual(declarations(in: graph).map(\.id), [rereviewed.identity])
        let reopened = ReadingSourceLibrary(url: fixture.url)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(KnowledgePageGraph.append(to: .empty, library: reopened), graph)
    }

    func testCorrectedEndpointRemovesDeclarationWithoutRebindingToNewPage() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let source = try fixture.source()
        let from = try fixture.reviewedPage(source: source, title: "First page")
        let to = try fixture.reviewedPage(source: source, title: "Second page")
        let link = try fixture.reviewedLink(from: from, to: to, rationale: "Bound to both reviewed versions.")
        let updatedDraft = try fixture.library.saveKnowledgePage(id: to.id, expectedRevision: to.revision,
            title: to.title, body: "A corrected interpretation.", kind: to.kind, anchors: to.anchors)
        let updatedPage = try fixture.library.reviewKnowledgePage(id: updatedDraft.id, expectedRevision: updatedDraft.revision)
        let graph = try fixture.snapshotWithoutWriting()
        XCTAssertEqual(try pageNode(updatedPage, in: graph).presentationState, .reviewed)
        XCTAssertTrue(declarations(in: graph).isEmpty)
        XCTAssertFalse(graph.edges.contains { $0.id == link.identity || $0.reference == link.identity })
        XCTAssertFalse(graph.edges.contains {
            $0.source == KnowledgePageGraph.nodeID(from.binding) && $0.target == KnowledgePageGraph.nodeID(updatedPage.binding)
        })
    }

    func testDerivedSourceRetainsExactParentAndTypedRelationshipAfterCorrection() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let library = fixture.library
        let parent = try fixture.source()
        let child = try library.keep(title: "Derived copy", text: "Separately retained derived text.",
            provenance: .init(origin: .mixed, acquisition: .derivedCopy, parents: [.init(binding: parent.binding)]))
        var graph = try fixture.snapshotWithoutWriting()
        let parentID = try sourceNode(parent.binding, in: graph).id
        let childID = try sourceNode(child.binding, in: graph).id
        XCTAssertTrue(graph.edges.contains {
            $0.source == childID && $0.target == parentID && $0.relationship == .derivedFrom
        })
        let corrected = try library.declareProvenance(source: parent, origin: .mixed,
            acquisition: .userCopy, attribution: "Corrected provenance declaration", parents: [])
        graph = try fixture.snapshotWithoutWriting()
        let correctedID = try sourceNode(corrected.binding, in: graph).id
        XCTAssertEqual(try sourceNode(parent.binding, in: graph).presentationState, .unavailable)
        XCTAssertEqual(try sourceNode(child.binding, in: graph).presentationState, .unavailable)
        XCTAssertEqual(try sourceNode(corrected.binding, in: graph).presentationState, .recorded)
        XCTAssertTrue(graph.edges.contains {
            $0.source == childID && $0.target == parentID && $0.relationship == .derivedFrom
        })
        XCTAssertFalse(graph.edges.contains { $0.source == childID && $0.target == correctedID })
    }

    private func pageNode(_ page: KnowledgePage, in graph: CompanionGraphSnapshot) throws -> CompanionGraphNode {
        try XCTUnwrap(graph.nodes.first { $0.id == KnowledgePageGraph.nodeID(page.binding) })
    }

    private func sourceNode(_ binding: ReadingSourceBinding, in graph: CompanionGraphSnapshot) throws -> CompanionGraphNode {
        try XCTUnwrap(graph.nodes.first {
            $0.kind == .source
                && $0.details.contains(.init(label: "Source ID", value: binding.id))
                && $0.details.contains(.init(label: "Revision", value: String(binding.revision)))
                && $0.details.contains(.init(label: "Digest", value: binding.digest))
                && $0.details.contains(.init(label: "Provenance digest", value: binding.provenance?.digest ?? "No declaration retained"))
        })
    }

    private func declarations(in graph: CompanionGraphSnapshot) -> [CompanionGraphEdge] {
        graph.edges.filter { [.supports, .contradicts, .dependsOn].contains($0.relationship) }
    }

    @MainActor
    private final class Fixture {
        let directory: URL
        let url: URL
        let library: ReadingSourceLibrary

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-knowledge-graph-meaning-\(UUID())")
            url = directory.appendingPathComponent("reading-sources.json")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            library = ReadingSourceLibrary(url: url)
        }

        func source() throws -> ReadingSourceSnapshot {
            try library.keep(title: "Owner evidence", text: "Evidence retained for an exact source reference.",
                provenance: .init(origin: .human, acquisition: .userCopy))
        }

        func reviewedPage(source: ReadingSourceSnapshot, title: String) throws -> KnowledgePage {
            let anchor = try library.makeAnchor(sourceID: source.id, range: NSRange(location: 0, length: 8))
            let draft = try library.saveKnowledgePage(title: title, body: "An explicitly authored interpretation.",
                kind: .concept, anchors: [anchor])
            return try library.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        }

        func reviewedLink(from: KnowledgePage, to: KnowledgePage, rationale: String) throws -> KnowledgePageLink {
            let draft = try library.saveKnowledgeLink(from: from.binding, to: to.binding, kind: .supports, rationale: rationale)
            return try library.reviewKnowledgeLink(id: draft.id, expectedRevision: draft.revision)
        }

        func snapshotWithoutWriting() throws -> CompanionGraphSnapshot {
            let bytes = try Data(contentsOf: url)
            let graph = KnowledgePageGraph.append(to: .empty, library: library)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
            return graph
        }

        func clean() { try? FileManager.default.removeItem(at: directory) }
    }
}
