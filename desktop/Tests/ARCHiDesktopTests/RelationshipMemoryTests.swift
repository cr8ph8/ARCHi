import Foundation
import CryptoKit
import XCTest
@testable import ARCHiDesktop

@MainActor
final class RelationshipMemoryTests: XCTestCase {
    func testOrdinaryBindingsRemainByteStableAndTypedHistoryUsesExistingBackupOwner() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let library = ReadingSourceLibrary(url: fixture.url)
        let anchor = try keepAnchor(in: library, text: "Alex told me about a film.")
        let ordinary = try library.saveKnowledgePage(title: "Note", body: "A source-backed note.", kind: .claim, anchors: [anchor])
        let reviewed = try library.reviewKnowledgePage(id: ordinary.id, expectedRevision: ordinary.revision)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let legacyBytes = try encoder.encode(LegacyPage(reviewed))
        XCTAssertEqual(try encoder.encode(reviewed), legacyBytes,
            "Absent relationship metadata must not change old binding bytes.")
        let oldBinding = reviewed.binding
        XCTAssertEqual(oldBinding.digest, SHA256.hash(data: legacyBytes).map { String(format: "%02x", $0) }.joined())
        XCTAssertEqual(try fixture.archive()["schema"] as? String, "archi-reading-sources/v2")
        let original = try Data(contentsOf: fixture.url)
        XCTAssertNil(ReadingSourceLibrary(url: fixture.url).loadError)
        XCTAssertEqual(try Data(contentsOf: fixture.url), original)

        let person = try library.saveRelationshipPage(title: "Alex", body: "The person I met at the workshop.",
            metadata: .init(kind: .person), anchors: [anchor])
        XCTAssertEqual(person.state, .draft)
        XCTAssertEqual(try fixture.archive()["schema"] as? String, "archi-reading-sources/v3")
        XCTAssertEqual(library.knowledgePages.first { $0 == reviewed }?.binding, oldBinding)
        let bytes = try Data(contentsOf: fixture.url)
        let reopened = ReadingSourceLibrary(url: fixture.url)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.knowledgePages, library.knowledgePages)
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)

        let backupURL = fixture.root.appendingPathComponent("relationships.archibackup")
        let summary = try DesktopProfileBackup.create(profile: .custom, preferenceURL: fixture.preferences,
            archiveURL: backupURL)
        XCTAssertEqual(summary.knowledgePageVersionCount, 3)
        let destination = fixture.root.appendingPathComponent("restored/preferences.json")
        let preview = try DesktopProfileBackup.preview(archiveURL: backupURL, profile: .custom, preferenceURL: destination)
        _ = try DesktopProfileBackup.restore(preview, rollbackDirectory: fixture.root.appendingPathComponent("rollback"))
        let restoredURL = destination.deletingPathExtension().appendingPathExtension("reading-sources.json")
        XCTAssertEqual(try Data(contentsOf: restoredURL), bytes)
        XCTAssertEqual(ReadingSourceLibrary(url: restoredURL).knowledgePages, library.knowledgePages)
    }

    func testSameNamesStaySeparateAndCorrectedPersonRequiresExplicitRebinding() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let library = ReadingSourceLibrary(url: fixture.url)
        let personAnchor = try keepAnchor(in: library, text: "Alex from the workshop; Alex from the cafe.")
        let encounterAnchor = try keepAnchor(in: library, text: "We discussed the animation workshop.")
        let first = try reviewedPerson(in: library, anchor: personAnchor)
        let second = try reviewedPerson(in: library, anchor: personAnchor)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.title, second.title)
        let draft = try library.saveRelationshipPage(title: "Workshop conversation", body: "We discussed animation.",
            metadata: .init(kind: .encounter, person: first.binding), anchors: [encounterAnchor])
        let encounter = try library.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        XCTAssertEqual(encounter.relationship?.person, first.binding)
        XCTAssertNil(encounter.relationship?.occurredAt)
        XCTAssertNil(library.availability(of: encounter))

        let corrected = try library.saveRelationshipPage(id: first.id, expectedRevision: first.revision,
            title: first.title, body: "Clarified which workshop we met at.", metadata: .init(kind: .person), anchors: [personAnchor])
        XCTAssertNotNil(library.availability(of: encounter))
        XCTAssertNil(library.availability(of: second))
        XCTAssertThrowsError(try library.reviewKnowledgePage(id: encounter.id, expectedRevision: encounter.revision))
        let search = try KnowledgeRetrieval.search(query: "animation", sources: library.sources,
            pages: library.knowledgePages, libraryIsCurrent: library.isCurrentOnDisk)
        XCTAssertFalse(search.hits.contains { $0.pageBinding == encounter.binding })
        let current = try library.reviewKnowledgePage(id: corrected.id, expectedRevision: corrected.revision)
        XCTAssertNotNil(library.availability(of: encounter), "Reviewing the corrected person does not silently rebind old encounters.")
        let rebound = try library.saveRelationshipPage(id: encounter.id, expectedRevision: encounter.revision,
            title: encounter.title, body: encounter.body,
            metadata: .init(kind: .encounter, person: current.binding), anchors: encounter.anchors)
        XCTAssertEqual(rebound.state, .draft)
        let reviewed = try library.reviewKnowledgePage(id: rebound.id, expectedRevision: rebound.revision)
        XCTAssertNil(library.availability(of: reviewed))
        _ = try library.withdrawKnowledgePage(id: current.id, expectedRevision: current.revision)
        XCTAssertNotNil(library.availability(of: reviewed), "Person withdrawal invalidates linked records even when every source remains available.")
        XCTAssertNotNil(library.quote(for: personAnchor))
        XCTAssertNotNil(library.quote(for: encounterAnchor))
        XCTAssertNil(ReadingSourceLibrary(url: fixture.url).loadError, "Historical links remain valid history after correction.")
    }

    func testPersonSourceLossAndWithdrawalExcludeLinkedRecordsButAllowTheirWithdrawal() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let library = ReadingSourceLibrary(url: fixture.url)
        let personAnchor = try keepAnchor(in: library, text: "I met Alex at a workshop.")
        let encounterAnchor = try keepAnchor(in: library, text: "We discussed animation on a later visit.")
        let person = try reviewedPerson(in: library, anchor: personAnchor)
        let draft = try library.saveRelationshipPage(title: "Animation encounter", body: "A later discussion.",
            metadata: .init(kind: .encounter, person: person.binding), anchors: [encounterAnchor])
        let encounter = try library.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        try library.forget(id: personAnchor.source.id)
        XCTAssertNotNil(library.quote(for: encounterAnchor), "The child's own source is still available.")
        XCTAssertNotNil(library.availability(of: encounter))
        var hits = try KnowledgeRetrieval.search(query: "animation", sources: library.sources,
            pages: library.knowledgePages, libraryIsCurrent: true).hits
        XCTAssertFalse(hits.contains { $0.pageBinding == encounter.binding })
        _ = try library.withdrawKnowledgePage(id: person.id, expectedRevision: person.revision)
        hits = try KnowledgeRetrieval.search(query: "animation", sources: library.sources,
            pages: library.knowledgePages, libraryIsCurrent: true).hits
        XCTAssertFalse(hits.contains { $0.pageBinding == encounter.binding })
        XCTAssertEqual(try library.withdrawKnowledgePage(id: encounter.id, expectedRevision: encounter.revision).state, .withdrawn)
        XCTAssertNil(ReadingSourceLibrary(url: fixture.url).loadError)
    }

    func testRecordedCompletionCreatesDraftAndContextKeepsUserAttribution() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let library = ReadingSourceLibrary(url: fixture.url)
        let anchor = try keepAnchor(in: library, text: "I offered Alex my sound-design checklist.")
        let person = try reviewedPerson(in: library, anchor: anchor)
        let draft = try library.saveRelationshipPage(title: "Checklist", body: "My offer to send the checklist.",
            metadata: .init(kind: .commitment, person: person.binding, commitmentStatus: .pending), anchors: [anchor])
        let pending = try library.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        let completed = try library.markRelationshipCommitment(id: pending.id, expectedRevision: pending.revision, status: .completed)
        XCTAssertEqual(completed.state, .draft)
        XCTAssertNil(completed.review)
        XCTAssertNotNil(library.availability(of: completed))
        XCTAssertEqual(completed.relationship?.commitmentStatus, .completed)
        XCTAssertEqual(completed.relationship?.attribution, .userReported)
        XCTAssertNil(completed.relationship?.dueAt)
        XCTAssertNil(KnowledgePageContext.make(page: completed, quotes: [try XCTUnwrap(library.quote(for: anchor))]))
        XCTAssertThrowsError(try library.markRelationshipCommitment(id: completed.id, expectedRevision: pending.revision, status: .cancelled))
        let reviewed = try library.reviewKnowledgePage(id: completed.id, expectedRevision: completed.revision)
        let context = try XCTUnwrap(KnowledgePageContext.make(page: reviewed, quotes: [try XCTUnwrap(library.quote(for: anchor))]))
        let text = String(decoding: try JSONEncoder().encode(context.modelInput), as: UTF8.self)
        XCTAssertTrue(text.contains("userReported"))
        XCTAssertTrue(text.contains("unknown-not-established-by-this-record"))
        XCTAssertTrue(text.contains(person.binding.digest))
        XCTAssertTrue(library.markdown(for: reviewed).contains("Due date: Unknown"))
        XCTAssertTrue(library.markdown(for: reviewed).contains("Completed (user reported)"))
        let edited = try library.saveKnowledgePage(id: reviewed.id, expectedRevision: reviewed.revision,
            title: reviewed.title, body: "My clarified offer.", kind: .claim, anchors: reviewed.anchors)
        XCTAssertEqual(edited.relationship, reviewed.relationship, "An ordinary page edit cannot strip typed metadata.")
        XCTAssertThrowsError(try library.saveKnowledgePage(id: edited.id, expectedRevision: edited.revision,
            title: edited.title, body: edited.body, kind: .concept, anchors: edited.anchors))
        XCTAssertThrowsError(try library.saveRelationshipPage(id: edited.id, expectedRevision: edited.revision,
            title: edited.title, body: edited.body, metadata: .init(kind: .person), anchors: edited.anchors))
    }

    func testMalformedMetadataAndForgedPersonLinksFailBeforeWritingAndOnRecovery() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let library = ReadingSourceLibrary(url: fixture.url)
        let anchor = try keepAnchor(in: library, text: "A reported encounter.")
        let person = try reviewedPerson(in: library, anchor: anchor)
        let bytes = try Data(contentsOf: fixture.url)
        let forged = KnowledgePageBinding(id: UUID().uuidString, revision: 2, digest: String(repeating: "a", count: 64))
        let invalid: [RelationshipMemoryMetadata] = [
            .init(kind: .person, person: person.binding), .init(kind: .person, dueAt: Date()),
            .init(kind: .encounter), .init(kind: .encounter, person: forged),
            .init(kind: .encounter, person: person.binding, occurredAt: .distantFuture),
            .init(kind: .commitment, person: person.binding),
            .init(kind: .commitment, person: person.binding, occurredAt: Date(), commitmentStatus: .pending)
        ]
        for metadata in invalid {
            XCTAssertThrowsError(try library.saveRelationshipPage(title: "Rejected", body: "A user note.", metadata: metadata, anchors: [anchor]))
            XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
        }
        let child = try library.saveRelationshipPage(title: "Encounter", body: "A user note.",
            metadata: .init(kind: .encounter, person: person.binding), anchors: [anchor])
        let base = try fixture.archive()
        var corruptions: [[String: Any]] = []
        var changed = base; changed["schema"] = "archi-reading-sources/v2"; corruptions.append(changed)
        var pages = try XCTUnwrap(base["knowledgePages"] as? [[String: Any]])
        let childIndex = try XCTUnwrap(pages.firstIndex { ($0["id"] as? String) == child.id })
        for badField in ["inferredTrust": true, "occurredAt": NSNull()] as [String: Any] {
            var altered = pages
            var metadata = try XCTUnwrap(altered[childIndex]["relationship"] as? [String: Any])
            metadata[badField.key] = badField.value; altered[childIndex]["relationship"] = metadata
            changed = base; changed["knowledgePages"] = altered; corruptions.append(changed)
        }
        var metadata = try XCTUnwrap(pages[childIndex]["relationship"] as? [String: Any])
        metadata["person"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(forged))
        pages[childIndex]["relationship"] = metadata
        changed = base; changed["knowledgePages"] = pages; corruptions.append(changed)
        for object in corruptions {
            let corrupt = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            try corrupt.write(to: fixture.url)
            let reopened = ReadingSourceLibrary(url: fixture.url)
            XCTAssertNotNil(reopened.loadError)
            XCTAssertThrowsError(try reopened.keep(title: "No replacement", text: "Preserve invalid history"))
            XCTAssertEqual(try Data(contentsOf: fixture.url), corrupt)
        }
    }

    private func keepAnchor(in library: ReadingSourceLibrary, text: String) throws -> KnowledgeAnchor {
        let source = try library.keep(title: "User-kept note", text: text)
        return try library.makeAnchor(sourceID: source.id, range: NSRange(location: 0, length: text.utf16.count))
    }

    private func reviewedPerson(in library: ReadingSourceLibrary, anchor: KnowledgeAnchor) throws -> KnowledgePage {
        let draft = try library.saveRelationshipPage(title: "Alex", body: "A person I chose to remember.",
            metadata: .init(kind: .person), anchors: [anchor])
        return try library.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
    }

    /// The pre-relationship schema, used to compare the actual encoded bytes.
    private struct LegacyPage: Encodable {
        let id: String; let revision: UInt64; let title: String; let body: String
        let kind: KnowledgePageKind; let anchors: [KnowledgeAnchor]; let state: KnowledgePageState
        let createdAt: Date; let updatedAt: Date; let review: KnowledgePageReview?
        init(_ page: KnowledgePage) {
            id = page.id; revision = page.revision; title = page.title; body = page.body; kind = page.kind
            anchors = page.anchors; state = page.state; createdAt = page.createdAt; updatedAt = page.updatedAt; review = page.review
        }
    }

    private struct Fixture {
        let root: URL
        var preferences: URL { root.appendingPathComponent("preferences.json") }
        var url: URL { preferences.deletingPathExtension().appendingPathExtension("reading-sources.json") }
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("archi-relationship-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        func clean() { try? FileManager.default.removeItem(at: root) }
        func archive() throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        }
    }
}
