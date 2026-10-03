import XCTest
@testable import ARCHiDesktop

final class CompanionGraphNavigationTests: XCTestCase {
    func testLocalFocusKeepsAnchorWhileFiltersNarrowOnlyDirectNeighbours() {
        let graph = fixture()
        let focused = CompanionGraphNavigation.visibleNodes(in: graph, query: "Launch", kindFilter: .request, focusID: "lesson")
        XCTAssertEqual(focused.map(\.id), ["lesson", "request"])
        XCTAssertFalse(focused.contains { $0.id == "answer" }, "A second-hop node is outside the local graph.")
        let anchorOnly = CompanionGraphNavigation.visibleNodes(in: graph, query: "unmatched", kindFilter: .answer, focusID: "lesson")
        XCTAssertEqual(anchorOnly.map(\.id), ["lesson"])
        XCTAssertEqual(CompanionGraphNavigation.retainedSelection("lesson", in: anchorOnly), "lesson")
        let filtered = CompanionGraphNavigation.visibleNodes(in: graph, query: "Launch", kindFilter: .lesson, focusID: nil)
        XCTAssertEqual(filtered.map(\.id), ["lesson", "unconnected"])
    }

    func testBacklinksAndOutgoingLinksPreserveDirectionLabelsAndStableOrder() {
        let original = fixture()
        let graph = CompanionGraphSnapshot(nodes: original.nodes, edges: original.edges + [
            .init(id: "a-reverse", source: "request", target: "lesson", label: "reviewed"),
            .init(id: "invalid", source: "missing", target: "lesson", label: "must stay unavailable")
        ], truncatedCount: 0)
        let incoming = CompanionGraphNavigation.links(for: "lesson", in: graph, direction: .incoming)
        XCTAssertEqual(incoming.map(\.id), ["a-reverse", "source-lesson"])
        XCTAssertEqual(incoming.map(\.label), ["reviewed", "source for"])
        XCTAssertTrue(incoming.allSatisfy { $0.target == "lesson" })
        let outgoing = CompanionGraphNavigation.links(for: "lesson", in: graph, direction: .outgoing)
        XCTAssertEqual(outgoing.map(\.id), ["lesson-request"])
        XCTAssertEqual(outgoing.map(\.target), ["request"])
        let reversed = CompanionGraphSnapshot(nodes: graph.nodes, edges: Array(graph.edges.reversed()), truncatedCount: 0)
        XCTAssertEqual(CompanionGraphNavigation.links(for: "lesson", in: reversed, direction: .incoming), incoming)
    }

    func testRemovedFocusFallsBackToFilteredMapAndDropsStaleSelection() {
        let original = fixture()
        let replaced = CompanionGraphSnapshot(nodes: original.nodes.filter { $0.id != "lesson" }, edges: original.edges, truncatedCount: 0)
        let visible = CompanionGraphNavigation.visibleNodes(in: replaced, query: "Meeting", kindFilter: .source, focusID: "lesson")
        XCTAssertEqual(visible.map(\.id), ["source"])
        XCTAssertNil(CompanionGraphNavigation.retainedSelection("lesson", in: visible))
        XCTAssertEqual(CompanionGraphNavigation.retainedSelection("source", in: visible), "source")
        XCTAssertTrue(CompanionGraphNavigation.links(for: "lesson", in: replaced, direction: .incoming).isEmpty)
        XCTAssertTrue(CompanionGraphNavigation.links(for: "source", in: replaced, direction: .outgoing).isEmpty)
    }

    func testFilteringHidesSelectionWithoutReplacingOrRetiringItsRecord() {
        let graph = fixture()
        let visible = CompanionGraphNavigation.visibleNodes(in: graph, query: "Meeting", kindFilter: .source, focusID: nil)
        XCTAssertEqual(CompanionGraphNavigation.selectionVisibility("lesson", in: graph, visibleNodes: visible), .hidden)
        XCTAssertEqual(CompanionGraphNavigation.retainedSelection("lesson", in: graph.nodes), "lesson")
        XCTAssertEqual(CompanionGraphNavigation.selectionVisibility("source", in: graph, visibleNodes: visible), .visible)
        XCTAssertEqual(CompanionGraphNavigation.selectionVisibility(nil, in: graph, visibleNodes: visible), .none)
        let removed = CompanionGraphSnapshot(nodes: graph.nodes.filter { $0.id != "lesson" }, edges: [], truncatedCount: 0)
        XCTAssertEqual(CompanionGraphNavigation.selectionVisibility("lesson", in: removed, visibleNodes: visible), .unavailable)
    }

    func testFocusHistoryRestoresExactSelectionAlongsideFocus() throws {
        let graph = fixture()
        let overview = CompanionGraphNavigation.Location(focusID: nil, selectedID: "source")
        let focused = CompanionGraphNavigation.Location(focusID: "lesson", selectedID: "request")
        XCTAssertEqual(CompanionGraphNavigation.retainedLocation(overview, in: graph), overview)
        XCTAssertEqual(CompanionGraphNavigation.retainedLocation(focused, in: graph), focused)
        let removedSelection = CompanionGraphSnapshot(nodes: graph.nodes.filter { $0.id != "request" }, edges: [], truncatedCount: 0)
        let retained = try XCTUnwrap(CompanionGraphNavigation.retainedLocation(focused, in: removedSelection))
        XCTAssertEqual(retained.focusID, "lesson")
        XCTAssertNil(retained.selectedID, "Back cannot substitute another record for a removed selection.")
        let removedFocus = CompanionGraphSnapshot(nodes: graph.nodes.filter { $0.id != "lesson" }, edges: [], truncatedCount: 0)
        XCTAssertNil(CompanionGraphNavigation.retainedLocation(focused, in: removedFocus))
    }

    private func fixture() -> CompanionGraphSnapshot {
        func node(_ id: String, _ title: String, _ kind: CompanionGraphKind) -> CompanionGraphNode {
            .init(id: id, title: title, subtitle: "", kind: kind, status: "", details: [], target: nil)
        }
        return .init(nodes: [node("source", "Meeting notes", .source), node("lesson", "Launch Friday", .lesson),
            node("request", "Launch question", .request), node("answer", "Launch answer", .answer),
            node("unconnected", "Launch archive", .lesson)], edges: [
                .init(id: "source-lesson", source: "source", target: "lesson", label: "source for"),
                .init(id: "lesson-request", source: "lesson", target: "request", label: "used by"),
                .init(id: "request-answer", source: "request", target: "answer", label: "returned")
            ], truncatedCount: 0)
    }
}
