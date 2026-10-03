import Foundation
import XCTest
@testable import ARCHiDesktop

@MainActor
final class KnowledgeSourceGraphTests: XCTestCase {
    func testKeptSourceAppearsBeforeAnyPageAndSharesItsNodeWithPassageAnchors() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let library = ReadingSourceLibrary(url: fixture.url)
        let source = try library.keep(title: "Research copy", text: "Source body stays with its owner.",
            provenance: .init(origin: .human, acquisition: .externalPublication,
                attribution: "Private free-text attribution"))
        let bytes = try Data(contentsOf: fixture.url)
        let graph = KnowledgePageGraph.append(to: .empty, library: library)
        let node = try sourceNode(source.binding, in: graph)
        XCTAssertEqual(node.title, source.title)
        XCTAssertEqual(node.status, "Retained source")
        XCTAssertEqual(node.target, .memory, "Kept sources must not navigate to an unrelated working document.")
        XCTAssertTrue(node.details.contains(.init(label: "Declared origin", value: "Human authored")))
        XCTAssertTrue(node.details.contains(.init(label: "Acquisition", value: "External publication")))
        XCTAssertFalse(strings(graph).contains(source.text))
        XCTAssertFalse(strings(graph).contains("Private free-text attribution"))
        XCTAssertEqual(library.sources, [source])
        XCTAssertTrue(library.knowledgePages.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)

        let anchor = try library.makeAnchor(sourceID: source.id, range: NSRange(location: 0, length: 6))
        _ = try library.saveKnowledgePage(title: "A concept", body: "My interpretation.", kind: .concept, anchors: [anchor])
        let linked = KnowledgePageGraph.append(to: .empty, library: library)
        XCTAssertEqual(linked.nodes.filter { $0.kind == .source }.count, 1)
        XCTAssertEqual(try sourceNode(source.binding, in: linked).id, node.id)
        XCTAssertTrue(linked.edges.contains { $0.target == node.id && $0.label == "source passage" })
        XCTAssertEqual(linked, KnowledgePageGraph.append(to: .empty, library: library))

        let full = CompanionGraphSnapshot(nodes: (0..<CompanionGraph.maximumNodes).map {
            .init(id: "existing-\($0)", title: "Existing", subtitle: "", kind: .context,
                status: "", details: [], target: nil)
        }, edges: [], truncatedCount: 3)
        let capped = KnowledgePageGraph.append(to: full, library: library)
        XCTAssertEqual(capped.nodes.count, CompanionGraph.maximumNodes)
        XCTAssertGreaterThan(capped.truncatedCount, full.truncatedCount)
        XCTAssertTrue(capped.edges.isEmpty)
    }

    func testCorrectedParentRemainsDistinctFromExactHistoricalParentAndPageBinding() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let library = ReadingSourceLibrary(url: fixture.url)
        let parent = try library.keep(title: "Original", text: "An unchanged source passage.",
            provenance: .init(origin: .human, acquisition: .userCopy))
        let child = try library.keep(title: "Derived copy", text: "Separate derived source body.",
            provenance: .init(origin: .mixed, acquisition: .derivedCopy,
                parents: [.init(binding: parent.binding)]))
        let anchor = try library.makeAnchor(sourceID: parent.id, range: NSRange(location: 0, length: 2))
        _ = try library.saveKnowledgePage(title: "Historical interpretation", body: "A note tied to the original version.",
            kind: .concept, anchors: [anchor])
        let before = KnowledgePageGraph.append(to: .empty, library: library)
        let originalNode = try sourceNode(parent.binding, in: before)
        let childNode = try sourceNode(child.binding, in: before)
        XCTAssertTrue(before.edges.contains {
            $0.source == childNode.id && $0.target == originalNode.id && $0.label == "derived from"
        })

        let corrected = try library.declareProvenance(source: parent, origin: .mixed,
            acquisition: .userCopy, attribution: "Corrected declaration", parents: [])
        XCTAssertEqual(corrected.digest, parent.digest, "A metadata correction need not change source text.")
        let bytes = try Data(contentsOf: fixture.url)
        let graph = KnowledgePageGraph.append(to: .empty, library: library)
        let missing = try sourceNode(parent.binding, in: graph)
        let current = try sourceNode(corrected.binding, in: graph)
        XCTAssertEqual(missing.id, originalNode.id)
        XCTAssertNotEqual(missing.id, current.id)
        XCTAssertEqual(missing.title, "Unavailable source version")
        XCTAssertEqual(missing.status, "Needs source review")
        XCTAssertEqual(try sourceNode(child.binding, in: graph).status, "Needs source review")
        XCTAssertEqual(current.status, "Retained source")
        XCTAssertTrue(graph.edges.contains { $0.source == childNode.id && $0.target == missing.id && $0.label == "derived from" })
        XCTAssertFalse(graph.edges.contains { $0.source == childNode.id && $0.target == current.id })
        XCTAssertTrue(graph.edges.contains { $0.target == missing.id && $0.label == "source passage" })
        XCTAssertEqual(graph.nodes.filter { $0.kind == .source }.count, 3)
        XCTAssertEqual(library.sources, [corrected, child])
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
    }

    func testStaleLibraryCannotPresentRetainedSourcesOrReviewedPagesAsCurrent() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let owner = ReadingSourceLibrary(url: fixture.url)
        let source = try owner.keep(title: "Source", text: "Original evidence.")
        let anchor = try owner.makeAnchor(sourceID: source.id, range: NSRange(location: 0, length: 8))
        let draft = try owner.saveKnowledgePage(title: "A claim", body: "User interpretation.", kind: .claim, anchors: [anchor])
        _ = try owner.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        let stale = ReadingSourceLibrary(url: fixture.url)
        let retainedPages = stale.knowledgePages
        _ = try owner.replace(id: source.id, title: "Source", text: "Corrected evidence.")
        let bytes = try Data(contentsOf: fixture.url)
        XCTAssertFalse(stale.isCurrentOnDisk)

        let graph = KnowledgePageGraph.append(to: .empty, library: stale)
        let node = try sourceNode(source.binding, in: graph)
        XCTAssertEqual(node.status, "Needs source review")
        XCTAssertTrue(node.details.contains { $0.label == "State" && $0.value.contains("library changed") })
        XCTAssertFalse(graph.nodes.contains { $0.status == "Retained source" || $0.status == "Reviewed · current sources" })
        XCTAssertFalse(strings(graph).contains(source.text))
        XCTAssertEqual(stale.sources, [source])
        XCTAssertEqual(stale.knowledgePages, retainedPages)
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
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

    private func strings(_ graph: CompanionGraphSnapshot) -> String {
        graph.nodes.flatMap { [$0.title, $0.subtitle, $0.status] + $0.details.flatMap { [$0.label, $0.value] } }.joined(separator: "\n")
    }

    private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-knowledge-source-graph-\(UUID())")
        var url: URL { directory.appendingPathComponent("reading-sources.json") }
        init() throws { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        func clean() { try? FileManager.default.removeItem(at: directory) }
    }
}
