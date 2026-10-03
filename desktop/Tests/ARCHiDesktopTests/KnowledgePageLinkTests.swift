import Foundation
import XCTest
@testable import ARCHiDesktop

@MainActor
final class KnowledgePageLinkTests: XCTestCase {
    func testExplicitLinkLifecycleRetainsExactVersionsAcrossRestart() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let library = ReadingSourceLibrary(url: fixture.url)
        let pages = try fixture.pages(in: library)
        let before = try fixture.archive()
        XCTAssertEqual(before["schema"] as? String, "archi-reading-sources/v2")
        XCTAssertNil(before["knowledgeLinks"])

        let draft = try library.saveKnowledgeLink(from: pages.from.binding, to: pages.to.binding,
            kind: .supports, rationale: "The two retained passages describe the same observation.")
        XCTAssertEqual(draft.state, .draft)
        XCTAssertNil(draft.review)
        XCTAssertNotNil(library.availability(of: draft))
        XCTAssertEqual(try fixture.archive()["schema"] as? String, "archi-reading-sources/v5")
        let reviewed = try library.reviewKnowledgeLink(id: draft.id, expectedRevision: draft.revision)
        XCTAssertNil(library.availability(of: reviewed))
        XCTAssertEqual(KnowledgePageLink.current(links: library.knowledgeLinks, pages: [pages.from, pages.to]), [reviewed])
        XCTAssertNotEqual(draft.identity, reviewed.identity)
        XCTAssertThrowsError(try library.reviewKnowledgeLink(id: draft.id, expectedRevision: draft.revision))

        let revised = try library.saveKnowledgeLink(id: reviewed.id, expectedRevision: reviewed.revision,
            from: pages.from.binding, to: pages.to.binding, kind: .contradicts,
            rationale: "Correction: these notes describe incompatible outcomes.")
        XCTAssertEqual(revised.revision, 3)
        XCTAssertNil(revised.review)
        XCTAssertNotNil(library.availability(of: reviewed))
        let approved = try library.reviewKnowledgeLink(id: revised.id, expectedRevision: revised.revision)
        let withdrawn = try library.withdrawKnowledgeLink(id: approved.id, expectedRevision: approved.revision)
        XCTAssertEqual(withdrawn.revision, 5)
        XCTAssertNotNil(library.availability(of: withdrawn))
        XCTAssertTrue(KnowledgePageLink.current(links: library.knowledgeLinks, pages: [pages.from, pages.to]).isEmpty)
        XCTAssertThrowsError(try library.saveKnowledgeLink(id: withdrawn.id, expectedRevision: withdrawn.revision,
            from: pages.from.binding, to: pages.to.binding, kind: .supports, rationale: "Cannot revive a withdrawn declaration."))
        XCTAssertThrowsError(try library.reviewKnowledgeLink(id: withdrawn.id, expectedRevision: withdrawn.revision))
        XCTAssertEqual(try library.withdrawKnowledgeLink(id: withdrawn.id, expectedRevision: withdrawn.revision), withdrawn)
        let bytes = try Data(contentsOf: fixture.url)
        let reopened = ReadingSourceLibrary(url: fixture.url)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.knowledgeLinks, [draft, reviewed, revised, approved, withdrawn])
        XCTAssertEqual(reopened.latestKnowledgeLinks, [withdrawn])
        XCTAssertEqual(reopened.knowledgePages, library.knowledgePages)
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
    }

    func testLegacyArchivesRemainByteIdenticalUntilLinkIsSaved() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let source = ReadingSourceSnapshot(id: UUID().uuidString, title: "Legacy", revision: 1, text: "Kept evidence.")
        let row = try JSONSerialization.jsonObject(with: JSONEncoder().encode(source))
        for version in 1...4 {
            var root: [String: Any] = ["schema": "archi-reading-sources/v\(version)", "sources": [row]]
            if version > 1 { root["knowledgePages"] = [] }
            let bytes = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
            try bytes.write(to: fixture.url, options: .atomic)
            let library = ReadingSourceLibrary(url: fixture.url)
            XCTAssertNil(library.loadError, "Legacy v\(version) stays readable.")
            XCTAssertTrue(library.knowledgeLinks.isEmpty)
            XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
        }
    }

    func testCorrectedWithdrawnOrForgottenEvidenceInvalidatesLinksButAllowsWithdrawal() throws {
        for mutation in ["source correction", "page correction", "page withdrawal", "source removal"] {
            let fixture = try Fixture(); defer { fixture.clean() }
            let library = ReadingSourceLibrary(url: fixture.url)
            let pages = try fixture.pages(in: library)
            let draft = try library.saveKnowledgeLink(from: pages.from.binding, to: pages.to.binding,
                kind: .dependsOn, rationale: "The second page provides the observation used by the first.")
            let link = try library.reviewKnowledgeLink(id: draft.id, expectedRevision: draft.revision)
            switch mutation {
            case "source correction":
                _ = try library.replace(id: pages.source.id, title: "Evidence", text: "Corrected observation.")
            case "page correction":
                _ = try library.saveKnowledgePage(id: pages.to.id, expectedRevision: pages.to.revision,
                    title: pages.to.title, body: "Corrected interpretation.", kind: .concept, anchors: pages.to.anchors)
            case "page withdrawal":
                _ = try library.withdrawKnowledgePage(id: pages.to.id, expectedRevision: pages.to.revision)
            default: try library.forget(id: pages.source.id)
            }
            XCTAssertNotNil(library.availability(of: link), mutation)
            let available = library.latestKnowledgePages.filter { library.availability(of: $0) == nil }
            XCTAssertTrue(KnowledgePageLink.current(links: library.knowledgeLinks, pages: available).isEmpty, mutation)
            XCTAssertThrowsError(try library.reviewKnowledgeLink(id: link.id, expectedRevision: link.revision), mutation)
            XCTAssertThrowsError(try library.saveKnowledgeLink(from: pages.from.binding, to: pages.to.binding,
                kind: .supports, rationale: "A stale endpoint cannot establish a new link."), mutation)
            let withdrawn = try library.withdrawKnowledgeLink(id: link.id, expectedRevision: link.revision)
            XCTAssertEqual(withdrawn.state, .withdrawn)
            let reopened = ReadingSourceLibrary(url: fixture.url)
            XCTAssertNil(reopened.loadError, mutation)
            XCTAssertEqual(reopened.knowledgeLinks, [draft, link, withdrawn])
        }
    }

    func testConcurrentWriterCannotReviewWithdrawOrOverwriteStaleLinkState() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let owner = ReadingSourceLibrary(url: fixture.url)
        let pages = try fixture.pages(in: owner)
        let draft = try owner.saveKnowledgeLink(from: pages.from.binding, to: pages.to.binding,
            kind: .supports, rationale: "Explicit note.")
        let stale = ReadingSourceLibrary(url: fixture.url)
        let reviewed = try owner.reviewKnowledgeLink(id: draft.id, expectedRevision: draft.revision)
        let bytes = try Data(contentsOf: fixture.url)
        XCTAssertFalse(stale.isCurrentOnDisk)
        XCTAssertNotNil(stale.availability(of: draft))
        XCTAssertThrowsError(try stale.reviewKnowledgeLink(id: draft.id, expectedRevision: draft.revision))
        XCTAssertThrowsError(try stale.withdrawKnowledgeLink(id: draft.id, expectedRevision: draft.revision))
        XCTAssertThrowsError(try stale.saveKnowledgeLink(from: pages.from.binding, to: pages.to.binding,
            kind: .contradicts, rationale: "Do not overwrite another writer."))
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
        XCTAssertEqual(ReadingSourceLibrary(url: fixture.url).latestKnowledgeLinks, [reviewed])
    }

    func testMalformedOrFabricatedLinkHistoriesAreRejectedWithoutRepair() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let library = ReadingSourceLibrary(url: fixture.url)
        let pages = try fixture.pages(in: library)
        let draft = try library.saveKnowledgeLink(from: pages.from.binding, to: pages.to.binding,
            kind: .supports, rationale: "User-declared interpretation.")
        let reviewed = try library.reviewKnowledgeLink(id: draft.id, expectedRevision: draft.revision)
        let base = try fixture.archive()
        let original = try XCTUnwrap(base["knowledgeLinks"] as? [[String: Any]])
        var corruptions: [[String: Any]] = []
        func add(_ links: Any) { var root = base; root["knowledgeLinks"] = links; corruptions.append(root) }
        var changed = original; changed[1]["revision"] = 8; add(changed)
        changed = original; changed[1]["rationale"] = "Edited without a draft."; add(changed)
        changed = original; changed[0]["modelApproved"] = true; add(changed)
        changed = original
        var binding = try XCTUnwrap(changed[0]["to"] as? [String: Any]); binding["digest"] = String(repeating: "0", count: 64)
        changed[0]["to"] = binding; changed[1]["to"] = binding; add(changed)
        changed = [original[1]]; changed[0]["revision"] = 1; add(changed)
        add(original + [original[1]])
        add([]); add(NSNull())
        changed = original
        var review = try XCTUnwrap(changed[1]["review"] as? [String: Any])
        review["id"] = pages.from.review?.id
        changed[1]["review"] = review; add(changed)
        var oldSchema = base; oldSchema["schema"] = "archi-reading-sources/v4"; corruptions.append(oldSchema)

        let withdrawn = try library.withdrawKnowledgeLink(id: reviewed.id, expectedRevision: reviewed.revision)
        var revived = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        revived["revision"] = 4
        revived["updatedAt"] = withdrawn.updatedAt.timeIntervalSinceReferenceDate
        add(original + [try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(withdrawn)) as? [String: Any]), revived])

        for archive in corruptions {
            let bytes = try JSONSerialization.data(withJSONObject: archive, options: [.sortedKeys])
            try bytes.write(to: fixture.url, options: .atomic)
            let blocked = ReadingSourceLibrary(url: fixture.url)
            XCTAssertNotNil(blocked.loadError)
            XCTAssertFalse(blocked.isCurrentOnDisk)
            XCTAssertThrowsError(try blocked.keep(title: "Must not overwrite", text: "Invalid history remains intact."))
            XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
        }
    }

    func testBoundsAndPureProjectionRejectUnsupportedEndpointsAndConflictingReviews() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let library = ReadingSourceLibrary(url: fixture.url)
        let pages = try fixture.pages(in: library)
        for rationale in ["  \n", String(repeating: "é", count: 1_025)] {
            XCTAssertThrowsError(try library.saveKnowledgeLink(from: pages.from.binding, to: pages.to.binding,
                kind: .supports, rationale: rationale))
        }
        XCTAssertThrowsError(try library.saveKnowledgeLink(from: pages.from.binding, to: pages.from.binding,
            kind: .supports, rationale: "A page cannot link to itself."))
        let draft = try library.saveKnowledgeLink(from: pages.from.binding, to: pages.to.binding,
            kind: .supports, rationale: String(repeating: "é", count: 1_024))
        let reviewed = try library.reviewKnowledgeLink(id: draft.id, expectedRevision: draft.revision)
        let endpoints = [pages.from, pages.to]
        XCTAssertEqual(KnowledgePageLink.current(links: [reviewed, draft], pages: endpoints), [reviewed], "Projection is order independent.")
        XCTAssertTrue(KnowledgePageLink.current(links: [reviewed], pages: endpoints).isEmpty, "A standalone reviewed head cannot fabricate review lineage.")
        XCTAssertTrue(KnowledgePageLink.current(links: [draft, reviewed, reviewed], pages: endpoints).isEmpty)
        XCTAssertTrue(KnowledgePageLink.current(links: [draft, reviewed], pages: endpoints + [pages.from]).isEmpty)
        XCTAssertTrue(KnowledgePageLink.current(links: [draft, reviewed], pages: [pages.from]).isEmpty)
    }

    func testReservedCapacityAllowsWithdrawalAtLimitWithoutDroppingHistory() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let library = ReadingSourceLibrary(url: fixture.url)
        let pages = try fixture.pages(in: library)
        var link = try library.saveKnowledgeLink(from: pages.from.binding, to: pages.to.binding,
            kind: .supports, rationale: "Revision 1")
        for revision in 2..<ReadingSourceLibrary.maximumKnowledgeLinkVersions {
            link = try library.saveKnowledgeLink(id: link.id, expectedRevision: link.revision,
                from: pages.from.binding, to: pages.to.binding, kind: .supports, rationale: "Revision \(revision)")
        }
        XCTAssertEqual(library.knowledgeLinks.count, 127)
        let bytes = try Data(contentsOf: fixture.url)
        XCTAssertThrowsError(try library.reviewKnowledgeLink(id: link.id, expectedRevision: link.revision))
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
        let withdrawn = try library.withdrawKnowledgeLink(id: link.id, expectedRevision: link.revision)
        XCTAssertEqual(withdrawn.revision, 128)
        XCTAssertEqual(withdrawn.state, .withdrawn)
        XCTAssertEqual(library.knowledgeLinks.count, 128)
        XCTAssertEqual(library.knowledgeLinks.first?.rationale, "Revision 1")
        let reopened = ReadingSourceLibrary(url: fixture.url)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.knowledgeLinks, library.knowledgeLinks)
    }

    private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-knowledge-links-\(UUID())")
        var url: URL { directory.appendingPathComponent("reading-sources.json") }
        init() throws { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        func clean() { try? FileManager.default.removeItem(at: directory) }
        func archive() throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        }
        @MainActor
        func pages(in library: ReadingSourceLibrary) throws -> (source: ReadingSourceSnapshot, from: KnowledgePage, to: KnowledgePage) {
            let source = try library.keep(title: "Evidence", text: "A retained observation supporting both notes.")
            let anchor = try library.makeAnchor(sourceID: source.id, range: NSRange(location: 0, length: source.text.utf16.count))
            let first = try library.saveKnowledgePage(title: "First note", body: "An authored claim.", kind: .claim, anchors: [anchor])
            let from = try library.reviewKnowledgePage(id: first.id, expectedRevision: first.revision)
            let second = try library.saveKnowledgePage(title: "Second note", body: "A related concept.", kind: .concept, anchors: [anchor])
            let to = try library.reviewKnowledgePage(id: second.id, expectedRevision: second.revision)
            return (source, from, to)
        }
    }
}
