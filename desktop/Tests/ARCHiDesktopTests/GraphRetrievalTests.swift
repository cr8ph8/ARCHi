import XCTest
@testable import ARCHiDesktop

/// Synthetic source records. The alias-to-revision relationship and receipts
/// are visible to all three arms. Expected answers live only in the evaluator.
enum GraphRetrievalFixture {
    struct Question {
        let alias: String
        let verdict: String
        let citations: [String]
        var text: String { "Did build \(alias) pass native macOS qualification?" }
    }

    static let questions: [Question] = [
        .init(alias: "Juniper", verdict: "PASS", citations: ["r17"]),
        .init(alias: "Cedar", verdict: "FAIL", citations: ["r23"]),
        .init(alias: "Aspen", verdict: "UNVERIFIED", citations: ["r34"]),
        .init(alias: "Birch", verdict: "CONFLICT", citations: ["r45", "r46"]),
        .init(alias: "Linden", verdict: "UNVERIFIED", citations: []),
        .init(alias: "Willow", verdict: "UNVERIFIED", citations: []),
        .init(alias: "Maple", verdict: "UNVERIFIED", citations: ["r71"])
    ]

    static let snapshot: CompanionGraphSnapshot = {
        var nodes: [CompanionGraphNode] = []
        var edges: [CompanionGraphEdge] = []
        func release(_ id: String, _ alias: String, _ revision: String) {
            nodes.append(.init(id: id, title: alias, subtitle: "Release register", kind: .source,
                               status: "Recorded", details: [.init(label: "Revision", value: revision)], target: nil))
        }
        func run(_ id: String, _ source: String, _ revision: String, _ platform: String, _ result: String) {
            nodes.append(.init(id: id, title: "Qualification receipt", subtitle: platform, kind: .answer,
                               status: result, details: [.init(label: "Revision", value: revision)], target: nil))
            edges.append(.init(id: "\(source)-\(id)", source: source, target: id, label: "associated run"))
        }
        release("s1", "Juniper", "b251")
        run("r17", "s1", "b251", "native macOS", "PASS")
        release("s2", "Cedar", "b312")
        run("r23", "s2", "b312", "native macOS", "FAIL")
        release("s3", "Aspen", "b481")
        run("r33", "s3", "b481", "portable Linux", "PASS")
        run("r34", "s3", "b481", "native macOS", "SKIPPED")
        release("s4", "Birch", "b590")
        run("r45", "s4", "b590", "native macOS", "PASS")
        run("r46", "s4", "b590", "native macOS", "FAIL")
        release("s5", "Linden", "b604")
        run("r53", "s5", "b603", "native macOS", "PASS")
        release("s6", "Willow", "b708")
        release("s7", "Maple", "b801")
        run("r71", "s7", "b801", "native macOS", "ERROR")
        return .init(nodes: nodes, edges: edges, truncatedCount: 0)
    }()
}

final class GraphRetrievalTests: XCTestCase {
    func testLinkedRetrievalIncludesReleaseAndRequiredRunsInCompactBudget() {
        let fixture = GraphRetrievalFixture.snapshot
        for question in GraphRetrievalFixture.questions {
            let hits = CompanionGraphRetrieval.search(fixture, query: question.text, mode: .linked)
            XCTAssertEqual(hits.first?.node.title, question.alias)
            XCTAssertTrue(Set(question.citations).isSubset(of: Set(hits.map(\.node.id))), question.alias)
            XCTAssertLessThanOrEqual(hits.count, 6)
            XCTAssertEqual(hits.count, Set(hits.map(\.node.id)).count)
        }
    }

    func testDirectedReasonAndEndpointsSurviveOnlyInCurrentScope() {
        let fixture = GraphRetrievalFixture.snapshot
        let found = CompanionGraphRetrieval.search(fixture, query: "aspen", mode: .linked)
        let via = found.first { $0.node.id == "r34" }?.via
        XCTAssertEqual(via?.source, "s3")
        XCTAssertEqual(via?.target, "r34")
        XCTAssertEqual(via?.label, "associated run")
        let reverse = CompanionGraphRetrieval.search(fixture, query: "skipped", mode: .linked)
        XCTAssertEqual(reverse.first { $0.node.id == "s3" }?.via, via)
        let filtered = CompanionGraphRetrieval.search(fixture, query: "aspen", mode: .linked, kind: .source)
        XCTAssertEqual(filtered.map(\.node.id), ["s3"])
        let removed = CompanionGraphSnapshot(nodes: fixture.nodes.filter { $0.id != "r34" },
                                            edges: fixture.edges, truncatedCount: 0)
        XCTAssertFalse(CompanionGraphRetrieval.search(removed, query: "aspen", mode: .linked)
            .contains { $0.node.id == "r34" })
    }

    func testBaselinesAndDeterministicLimits() {
        let fixture = GraphRetrievalFixture.snapshot
        let reversed = CompanionGraphSnapshot(nodes: Array(fixture.nodes.reversed()),
            edges: Array(fixture.edges.reversed()), truncatedCount: 0)
        XCTAssertEqual(CompanionGraphRetrieval.search(fixture, query: "", mode: .full).count, fixture.nodes.count)
        for mode in [CompanionGraphRetrieval.Mode.keyword, .linked] {
            XCTAssertTrue(CompanionGraphRetrieval.search(fixture, query: "?!", mode: mode).isEmpty)
            XCTAssertTrue(CompanionGraphRetrieval.search(fixture, query: "AbsentWord", mode: mode).isEmpty)
            XCTAssertTrue(CompanionGraphRetrieval.search(fixture, query: "cedar", mode: mode, limit: 0).isEmpty)
            let first = CompanionGraphRetrieval.search(fixture, query: "native macOS", mode: mode, limit: 3)
            let second = CompanionGraphRetrieval.search(reversed, query: "native macOS", mode: mode, limit: 3)
            XCTAssertEqual(first.map(\.node.id), second.map(\.node.id))
            XCTAssertLessThanOrEqual(first.count, 3)
        }
        let keywords = CompanionGraphRetrieval.search(fixture, query: "Birch", mode: .keyword)
        XCTAssertEqual(keywords.map(\.node.id), ["s4"])
    }
}
