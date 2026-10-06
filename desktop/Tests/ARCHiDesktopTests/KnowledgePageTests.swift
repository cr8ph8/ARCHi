import Foundation
import XCTest
@testable import ARCHiDesktop

@MainActor
final class KnowledgePageTests: XCTestCase {
    func testLegacySourcesMigrateOnlyOnWriteAndExplicitPageLifecyclePreservesHistory() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let source = ReadingSourceSnapshot(id: UUID().uuidString, title: "Notes", revision: 1, text: "Measured result.")
        let legacy = try JSONSerialization.data(withJSONObject: ["schema": "archi-reading-sources/v1",
            "sources": [JSONSerialization.jsonObject(with: JSONEncoder().encode(source))]], options: [.sortedKeys])
        try legacy.write(to: fixture.url)
        let library = ReadingSourceLibrary(url: fixture.url)
        XCTAssertNil(library.loadError)
        XCTAssertTrue(library.knowledgePages.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture.url), legacy)
        let anchor = try library.makeAnchor(sourceID: source.id, range: NSRange(location: 0, length: source.text.utf16.count))
        let draft = try library.saveKnowledgePage(title: "Result", body: "My interpretation needs review.", kind: .claim, anchors: [anchor])
        XCTAssertEqual(draft.state, .draft)
        XCTAssertNil(draft.review)
        XCTAssertNotNil(library.availability(of: draft))
        let archive = try fixture.archive()
        XCTAssertEqual(archive["schema"] as? String, "archi-reading-sources/v2")
        XCTAssertEqual(library.sources, [source])
        let reviewed = try library.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        XCTAssertEqual(reviewed.revision, 2)
        XCTAssertEqual(reviewed.state, .reviewed)
        XCTAssertNotNil(reviewed.review)
        XCTAssertNil(library.availability(of: reviewed))
        XCTAssertNotNil(library.availability(of: draft))
        XCTAssertThrowsError(try library.withdrawKnowledgePage(id: reviewed.id, expectedRevision: 1))
        let revised = try library.saveKnowledgePage(id: reviewed.id, expectedRevision: reviewed.revision,
            title: "Result clarified", body: "A revised user-authored interpretation.", kind: .concept, anchors: [anchor])
        XCTAssertEqual(revised.state, .draft)
        XCTAssertEqual(revised.revision, 3)
        XCTAssertNil(revised.review)
        let withdrawn = try library.withdrawKnowledgePage(id: revised.id, expectedRevision: revised.revision)
        XCTAssertEqual(withdrawn.state, .withdrawn)
        XCTAssertEqual(withdrawn.revision, 4)
        XCTAssertNotEqual(withdrawn.review?.id, reviewed.review?.id)
        XCTAssertEqual(library.knowledgePages, [draft, reviewed, revised, withdrawn])
        let bytes = try Data(contentsOf: fixture.url)
        let reopened = ReadingSourceLibrary(url: fixture.url)
        XCTAssertEqual(reopened.knowledgePages, library.knowledgePages)
        XCTAssertEqual(reopened.sources, [source])
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
    }

    func testReplacementAndForgetInvalidateExactAnchorsWithoutCopyingSourceText() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let library = ReadingSourceLibrary(url: fixture.url)
        let source = try library.keep(title: "Source", text: "Original evidence.")
        let anchor = try library.makeAnchor(sourceID: source.id, range: NSRange(location: 0, length: 8))
        let draft = try library.saveKnowledgePage(title: "Concept", body: "My own note.", kind: .concept, anchors: [anchor])
        let reviewed = try library.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        XCTAssertEqual(library.quote(for: anchor), "Original")
        XCTAssertTrue(library.markdown(for: reviewed).contains("> Original"))
        let pageObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(reviewed)) as? [String: Any])
        XCTAssertNil(pageObject["sourceText"])
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(reviewed), as: UTF8.self).contains("Original evidence."))
        let replacement = try library.replace(id: source.id, title: "Source", text: "Updated evidence.")
        XCTAssertNil(library.quote(for: anchor))
        XCTAssertNotNil(library.availability(of: reviewed))
        XCTAssertFalse(library.markdown(for: reviewed).contains("> Original"))
        XCTAssertThrowsError(try library.reviewKnowledgePage(id: reviewed.id, expectedRevision: reviewed.revision))
        XCTAssertThrowsError(try library.saveKnowledgePage(id: reviewed.id, expectedRevision: reviewed.revision,
            title: "Concept", body: "New note.", kind: .concept, anchors: [anchor]))
        let updatedAnchor = try library.makeAnchor(sourceID: replacement.id, range: NSRange(location: 0, length: 7))
        let refreshed = try library.saveKnowledgePage(id: reviewed.id, expectedRevision: reviewed.revision,
            title: "Concept", body: "New note.", kind: .concept, anchors: [updatedAnchor])
        let approved = try library.reviewKnowledgePage(id: refreshed.id, expectedRevision: refreshed.revision)
        XCTAssertNil(library.availability(of: approved))
        try library.forget(id: source.id)
        XCTAssertNil(library.quote(for: updatedAnchor))
        XCTAssertNotNil(library.availability(of: approved))
        XCTAssertEqual(library.knowledgePages.count, 4)
        XCTAssertEqual(library.knowledgePages[1].anchors, [anchor])
        XCTAssertEqual(try library.withdrawKnowledgePage(id: approved.id, expectedRevision: approved.revision).state, .withdrawn,
            "Missing sources must not prevent explicit withdrawal.")
    }

    func testAnchorRangesAndNoteBoundsFailClosed() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let library = ReadingSourceLibrary(url: fixture.url)
        let source = try library.keep(title: "Unicode", text: "A😀B e\u{301}")
        let emoji = try library.makeAnchor(sourceID: source.id, range: NSRange(location: 1, length: 2))
        XCTAssertEqual(library.quote(for: emoji), "😀")
        for range in [NSRange(location: 1, length: 1), NSRange(location: 2, length: 1),
                      NSRange(location: 0, length: 0), NSRange(location: Int.max, length: 1)] {
            XCTAssertThrowsError(try library.makeAnchor(sourceID: source.id, range: range))
        }
        let altered = KnowledgeAnchor(source: emoji.source, location: emoji.location, length: emoji.length,
            quoteDigest: String(repeating: "0", count: 64))
        XCTAssertNil(library.quote(for: altered))
        XCTAssertThrowsError(try library.saveKnowledgePage(title: "Empty", body: " \n", kind: .claim, anchors: [emoji]))
        XCTAssertThrowsError(try library.saveKnowledgePage(title: "Missing", body: "Note", kind: .claim, anchors: []))
        XCTAssertThrowsError(try library.saveKnowledgePage(title: "Duplicate", body: "Note", kind: .claim, anchors: [emoji, emoji]))
        XCTAssertThrowsError(try library.saveKnowledgePage(title: "Wrong digest", body: "Note", kind: .claim, anchors: [altered]))
        XCTAssertThrowsError(try library.saveKnowledgePage(title: "Large", body: String(repeating: "a", count: 8_193), kind: .claim, anchors: [emoji]))
        let page = try library.saveKnowledgePage(title: "Café", body: String(repeating: "a", count: 8_192), kind: .claim, anchors: [emoji])
        XCTAssertTrue(page.isValid)
        let canonicallyEqualTitle = KnowledgePage(id: page.id, revision: page.revision, title: "Cafe\u{301}",
            body: page.body, kind: page.kind, anchors: page.anchors, state: page.state,
            createdAt: page.createdAt, updatedAt: page.updatedAt)
        XCTAssertNotEqual(canonicallyEqualTitle, page, "Exact retained page matching must preserve original UTF-8 bytes.")
        XCTAssertEqual(library.markdown(for: canonicallyEqualTitle), "Page version unavailable.")
    }

    func testAnotherWriterCannotReviewOrOverwriteStaleSourcesOrPages() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let owner = ReadingSourceLibrary(url: fixture.url)
        let source = try owner.keep(title: "Source", text: "Evidence")
        let anchor = try owner.makeAnchor(sourceID: source.id, range: NSRange(location: 0, length: 8))
        let draft = try owner.saveKnowledgePage(title: "Note", body: "Interpretation", kind: .claim, anchors: [anchor])
        let stale = ReadingSourceLibrary(url: fixture.url)
        _ = try owner.replace(id: source.id, title: "Source", text: "Changed")
        let bytes = try Data(contentsOf: fixture.url)
        XCTAssertNil(stale.quote(for: anchor))
        XCTAssertNotNil(stale.availability(of: draft))
        XCTAssertThrowsError(try stale.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision))
        XCTAssertThrowsError(try stale.saveKnowledgePage(title: "Other", body: "Note", kind: .claim, anchors: [anchor]))
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
    }

    func testMalformedUnknownAndForgedHistoryArchivesRemainUntouched() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let library = ReadingSourceLibrary(url: fixture.url)
        let source = try library.keep(title: "Source", text: "Evidence")
        let anchor = try library.makeAnchor(sourceID: source.id, range: NSRange(location: 0, length: 8))
        let draft = try library.saveKnowledgePage(title: "Claim", body: "My interpretation.", kind: .claim, anchors: [anchor])
        let reviewed = try library.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        let base = try fixture.archive()
        var corruptions: [[String: Any]] = []
        var changed = base; changed["schema"] = "future-unknown-schema"; corruptions.append(changed)
        changed = base; changed["unexpected"] = true; corruptions.append(changed)
        var pages = try XCTUnwrap(base["knowledgePages"] as? [[String: Any]])
        pages[1]["revision"] = 5
        changed = base; changed["knowledgePages"] = pages; corruptions.append(changed)
        pages = try XCTUnwrap(base["knowledgePages"] as? [[String: Any]])
        pages[1]["body"] = "Changed after review without a draft."
        changed = base; changed["knowledgePages"] = pages; corruptions.append(changed)
        var forged = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(reviewed)) as? [String: Any])
        forged["revision"] = 1
        changed = base; changed["knowledgePages"] = [forged]; corruptions.append(changed)
        pages = try XCTUnwrap(base["knowledgePages"] as? [[String: Any]])
        var anchors = try XCTUnwrap(pages[0]["anchors"] as? [[String: Any]])
        var binding = try XCTUnwrap(anchors[0]["source"] as? [String: Any])
        binding["originalPath"] = "/must/not/be/admitted"
        anchors[0]["source"] = binding; pages[0]["anchors"] = anchors
        changed = base; changed["knowledgePages"] = pages; corruptions.append(changed)
        var bytesToReject = try corruptions.map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
        let valid = try JSONSerialization.data(withJSONObject: base, options: [.sortedKeys])
        bytesToReject.append(Data(("{\"schema\":\"archi-reading-sources/v2\"," + String(String(decoding: valid, as: UTF8.self).dropFirst())).utf8))
        for bytes in bytesToReject {
            try bytes.write(to: fixture.url, options: .atomic)
            let blocked = ReadingSourceLibrary(url: fixture.url)
            XCTAssertNotNil(blocked.loadError)
            XCTAssertFalse(blocked.isCurrentOnDisk)
            XCTAssertThrowsError(try blocked.keep(title: "New", text: "Do not replace damaged history"))
            XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
        }
    }

    func testReservedCapacityAlwaysAllowsWithdrawalAndPreservesAllVersions() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let library = ReadingSourceLibrary(url: fixture.url)
        let source = try library.keep(title: "Source", text: "Evidence")
        let anchor = try library.makeAnchor(sourceID: source.id, range: NSRange(location: 0, length: 8))
        var page = try library.saveKnowledgePage(title: "Note", body: "Revision 1", kind: .concept, anchors: [anchor])
        for revision in 2...63 {
            page = try library.saveKnowledgePage(id: page.id, expectedRevision: page.revision,
                title: "Note", body: "Revision \(revision)", kind: .concept, anchors: [anchor])
        }
        XCTAssertEqual(library.knowledgePages.count, 63)
        let bytes = try Data(contentsOf: fixture.url)
        XCTAssertThrowsError(try library.reviewKnowledgePage(id: page.id, expectedRevision: page.revision))
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
        let withdrawn = try library.withdrawKnowledgePage(id: page.id, expectedRevision: page.revision)
        XCTAssertEqual(withdrawn.revision, 64)
        XCTAssertEqual(withdrawn.state, .withdrawn)
        XCTAssertEqual(library.knowledgePages.count, 64)
        XCTAssertEqual(library.knowledgePages.first?.body, "Revision 1")
        let reopened = ReadingSourceLibrary(url: fixture.url)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.knowledgePages, library.knowledgePages)
    }

    private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-knowledge-pages-\(UUID())")
        var url: URL { directory.appendingPathComponent("reading-sources.json") }
        init() throws { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        func archive() throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        }
        func clean() { try? FileManager.default.removeItem(at: directory) }
    }
}
