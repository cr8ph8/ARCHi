import Foundation
import XCTest
@testable import ARCHiDesktop

@MainActor
final class MemoryMapSnapshotTests: XCTestCase {
    func testEmptyProfileHasNoInventedMemoryAndDoesNotCreateAnArchive() throws {
        let fixture = Fixture(); defer { fixture.remove() }
        let snapshot = MemoryMapSnapshot.build(library: fixture.library, lessons: [])
        XCTAssertEqual(snapshot.nodes.map(\.kind), [.companion])
        XCTAssertTrue(snapshot.edges.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.url.path))
    }

    func testMemoryProjectionPreservesRecordIdentityAndInspectionWithoutActivityNodes() throws {
        let fixture = Fixture(); defer { fixture.remove() }
        let source = try fixture.library.keep(title: "Mechanism notes", text: "Keep the source of a claim.")
        let anchor = try fixture.library.makeAnchor(sourceID: source.id,
            range: NSRange(location: 0, length: source.text.utf16.count))
        let draft = try fixture.library.saveKnowledgePage(title: "Source context", body: "Inspect the original passage.",
            kind: .concept, anchors: [anchor])
        _ = try fixture.library.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        let lesson = KeptLesson(topic: "writing", text: "Keep attribution with a claim.")
        let bytes = try Data(contentsOf: fixture.url)
        let date = Date()
        let memory = MemoryMapSnapshot.build(library: fixture.library, lessons: [lesson], at: date)
        let full = KnowledgePageGraph.append(to: CompanionGraph.build(receipts: [], lessons: [lesson],
            source: CompanionGraphSource(name: "working.txt", text: "Unkept work in progress.", revision: 1), now: date),
            library: fixture.library)

        XCTAssertEqual(Set(memory.nodes.map(\.kind)), [.companion, .source, .knowledge, .lesson])
        XCTAssertEqual(memory.nodes.filter { $0.kind == .source }.count, 1,
            "The current working document must not be promoted into retained memory.")
        for node in memory.nodes where node.kind != .companion {
            XCTAssertEqual(full.nodes.first { $0.id == node.id }, node)
        }
        XCTAssertEqual(memory.nodes.first { $0.kind == .knowledge }?.target, .knowledgePage(id: draft.id))
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
    }

    func testRemovedSourceRemainsAnUnavailableReferenceAndDoesNotBecomeAKeptCopy() throws {
        let fixture = Fixture(); defer { fixture.remove() }
        let source = try fixture.library.keep(title: "Original notes", text: "Source evidence.")
        let anchor = try fixture.library.makeAnchor(sourceID: source.id,
            range: NSRange(location: 0, length: source.text.utf16.count))
        _ = try fixture.library.saveKnowledgePage(title: "A note", body: "A source-bound interpretation.",
            kind: .claim, anchors: [anchor])
        let before = MemoryMapSnapshot.build(library: fixture.library, lessons: [])
        let sourceID = try XCTUnwrap(before.nodes.first { $0.kind == .source }?.id)
        try fixture.library.forget(id: source.id)
        let after = MemoryMapSnapshot.build(library: fixture.library, lessons: [])

        XCTAssertTrue(fixture.library.sources.isEmpty)
        let reference = try XCTUnwrap(after.nodes.first { $0.id == sourceID })
        XCTAssertEqual(reference.title, "Unavailable source version")
        XCTAssertEqual(reference.status, "Needs source review")
        XCTAssertTrue(after.nodes.contains { $0.kind == .knowledge && $0.status == "Needs source review" })
        XCTAssertFalse(after.nodes.contains { $0.status == "Retained source" })
    }

    func testAStaleLibraryCannotPresentItsSourcesAsCurrent() throws {
        let fixture = Fixture(); defer { fixture.remove() }
        _ = try fixture.library.keep(title: "First copy", text: "An explicitly retained source.")
        let other = ReadingSourceLibrary(url: fixture.url)
        _ = try other.keep(title: "Second copy", text: "Saved in another session.")
        let currentBytes = try Data(contentsOf: fixture.url)
        let snapshot = MemoryMapSnapshot.build(library: fixture.library, lessons: [])

        XCTAssertFalse(fixture.library.isCurrentOnDisk)
        XCTAssertTrue(snapshot.nodes.filter { $0.kind == .source }.allSatisfy { $0.status == "Needs source review" })
        XCTAssertFalse(snapshot.nodes.contains { $0.title == "Second copy" }, "The projection does not silently reload or merge owners.")
        XCTAssertEqual(try Data(contentsOf: fixture.url), currentBytes)
    }

    @MainActor
    private struct Fixture {
        let directory: URL
        let url: URL
        let library: ReadingSourceLibrary

        init() {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-memory-map-\(UUID())")
            url = directory.appendingPathComponent("reading-sources.json")
            library = ReadingSourceLibrary(url: url)
        }

        func remove() { try? FileManager.default.removeItem(at: directory) }
    }
}
