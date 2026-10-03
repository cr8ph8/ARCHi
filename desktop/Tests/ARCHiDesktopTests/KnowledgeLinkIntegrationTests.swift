import Foundation
import XCTest
@testable import ARCHiDesktop

@MainActor
final class KnowledgeLinkIntegrationTests: XCTestCase {
    func testOpenLinkDraftKeepsItsMemoryHostAndBlocksRestoreUntilCancelled() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        _ = try seed(fixture.source, label: "Unsaved connection")
        let client = KnowledgeLinkNoModelClient()
        let store = CompanionStore(preferenceURL: fixture.source, assistant: client,
            allowsPlay: false, tokenSteward: TokenStewardStore())
        defer { store.disconnectAssistant() }
        let page = try XCTUnwrap(store.readingSources.latestKnowledgePages.first)
        let before = try profileBytes(fixture.source)
        XCTAssertNil(store.recoveryRestoreBlockReason)
        store.open(.memory)
        let draft = KnowledgeLinkDraft(page: page, prior: nil)
        store.knowledgeLinkDraft = draft
        XCTAssertTrue(store.hasOpenKnowledgeDraft)

        store.section = .assistant
        XCTAssertEqual(store.section, .memory, "Direct navigation must preserve the connection editor's host.")
        store.open(.context)
        XCTAssertEqual(store.section, .memory, "The ordinary navigation route must preserve the same draft.")
        XCTAssertEqual(store.knowledgeLinkDraft?.id, draft.id)
        XCTAssertNotNil(store.recoveryRestoreBlockReason)
        store.beginKnowledgePage(page)
        XCTAssertNil(store.knowledgePageDraft, "A second editor must not displace the open connection draft.")
        XCTAssertEqual(store.knowledgeLinkDraft?.id, draft.id)
        XCTAssertEqual(try profileBytes(fixture.source), before)

        store.knowledgeLinkDraft = nil
        XCTAssertFalse(store.hasOpenKnowledgeDraft)
        XCTAssertNil(store.recoveryRestoreBlockReason)
        store.open(.assistant)
        XCTAssertEqual(store.section, .assistant)
        XCTAssertEqual(try profileBytes(fixture.source), before)
        XCTAssertEqual(client.calls, 0)
    }

    func testGraphKeepsDeclaredDirectionAndOnlyCurrentReviewedLinks() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let library = try seed(fixture.source, label: "Direction")
        let pages = library.latestKnowledgePages.sorted { $0.title < $1.title }
        let from = pages[0], to = pages[1]

        for kind in KnowledgePageLinkKind.allCases {
            let draft = try library.saveKnowledgeLink(from: from.binding, to: to.binding,
                kind: kind, rationale: "A deliberately authored \(kind.rawValue) interpretation.")
            XCTAssertTrue(declaredEdges(library).isEmpty, "A saved draft cannot create a reviewed graph connection.")
            let reviewed = try library.reviewKnowledgeLink(id: draft.id, expectedRevision: draft.revision)
            let bytes = try Data(contentsOf: libraryURL(fixture.source))
            let graph = KnowledgePageGraph.append(to: .empty, library: library)
            let edge = try XCTUnwrap(graph.edges.first { $0.label == "declared " + kind.title.lowercased() })
            XCTAssertEqual(edge.source, try pageNode(from.id, graph: graph).id)
            XCTAssertEqual(edge.target, try pageNode(to.id, graph: graph).id)
            XCTAssertFalse(graph.edges.contains {
                $0.source == edge.target && $0.target == edge.source && $0.label == edge.label
            }, "The graph must not infer the converse of the user's declaration.")
            XCTAssertEqual(declaredEdges(library).count, 1)
            XCTAssertEqual(graph, KnowledgePageGraph.append(to: .empty, library: library))
            XCTAssertEqual(try Data(contentsOf: libraryURL(fixture.source)), bytes, "Graph projection is read-only.")

            _ = try library.withdrawKnowledgeLink(id: reviewed.id, expectedRevision: reviewed.revision)
            XCTAssertTrue(declaredEdges(library).isEmpty)
            XCTAssertTrue(library.knowledgeLinks.contains(reviewed), "Withdrawal retains reviewed history.")
        }
    }

    func testPageCorrectionRequiresRebindingAndReviewBeforeGraphConnectionReturns() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let library = try seed(fixture.source, label: "Page correction")
        let pages = library.latestKnowledgePages.sorted { $0.title < $1.title }
        let from = pages[0], original = pages[1]
        let reviewed = try link(library, from: from, to: original)
        XCTAssertEqual(declaredEdges(library).count, 1)

        let correctedDraft = try library.saveKnowledgePage(id: original.id, expectedRevision: original.revision,
            title: original.title, body: "A corrected interpretation of the same retained passage.",
            kind: original.kind, anchors: original.anchors)
        XCTAssertTrue(declaredEdges(library).isEmpty)
        let corrected = try library.reviewKnowledgePage(id: correctedDraft.id, expectedRevision: correctedDraft.revision)
        XCTAssertTrue(declaredEdges(library).isEmpty, "Reviewing a newer page cannot silently rebind an old link.")
        XCTAssertNotNil(library.availability(of: reviewed))
        XCTAssertEqual(library.latestKnowledgeLinks.first?.to, original.binding)

        let revisedLink = try library.saveKnowledgeLink(id: reviewed.id, expectedRevision: reviewed.revision,
            from: from.binding, to: corrected.binding, kind: reviewed.kind, rationale: "Reconsidered after the page correction.")
        XCTAssertTrue(declaredEdges(library).isEmpty)
        let approved = try library.reviewKnowledgeLink(id: revisedLink.id, expectedRevision: revisedLink.revision)
        XCTAssertNil(library.availability(of: approved))
        let graph = KnowledgePageGraph.append(to: .empty, library: library)
        XCTAssertEqual(try XCTUnwrap(declaredEdges(library).first).target, try pageNode(corrected.id, graph: graph).id)
        XCTAssertEqual(library.knowledgeLinks.first?.to, original.binding)
    }

    func testSourceCorrectionAndStaleOwnerSuppressGraphConnectionsWithoutChangingHistory() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let library = try seed(fixture.source, label: "Source correction")
        let pages = library.latestKnowledgePages.sorted { $0.title < $1.title }
        let reviewed = try link(library, from: pages[0], to: pages[1])
        let stale = ReadingSourceLibrary(url: libraryURL(fixture.source))
        let retained = library.knowledgeLinks
        let source = try XCTUnwrap(library.sources.first)
        _ = try library.replace(id: source.id, title: source.title, text: "Corrected primary material.")
        let bytes = try Data(contentsOf: libraryURL(fixture.source))

        XCTAssertNotNil(library.availability(of: reviewed))
        XCTAssertFalse(stale.isCurrentOnDisk)
        XCTAssertTrue(declaredEdges(library).isEmpty)
        XCTAssertTrue(declaredEdges(stale).isEmpty)
        XCTAssertEqual(library.knowledgeLinks, retained)
        XCTAssertEqual(stale.knowledgeLinks, retained)
        XCTAssertEqual(try Data(contentsOf: libraryURL(fixture.source)), bytes)
        let reopened = ReadingSourceLibrary(url: libraryURL(fixture.source))
        XCTAssertNil(reopened.loadError, "Stale endpoints are valid retained history, not archive corruption.")
        XCTAssertEqual(reopened.knowledgeLinks, retained)
        XCTAssertTrue(declaredEdges(reopened).isEmpty)
    }

    func testV5LinkHistoryBackupRestoreAndUndoPreserveExactProfileBytes() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let incoming = try seed(fixture.source, label: "Incoming")
        let pages = incoming.latestKnowledgePages.sorted { $0.title < $1.title }
        let reviewed = try link(incoming, from: pages[0], to: pages[1])
        let other = try incoming.saveKnowledgeLink(from: pages[1].binding, to: pages[0].binding,
            kind: .contradicts, rationale: "An interpretation deliberately withdrawn.")
        _ = try incoming.withdrawKnowledgeLink(id: other.id, expectedRevision: other.revision)
        _ = try seed(fixture.target, label: "Earlier")
        let before = try profileBytes(fixture.target)
        let captured = try profileBytes(fixture.source)
        let readingBytes = try Data(contentsOf: libraryURL(fixture.source))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: readingBytes) as? [String: Any])
        XCTAssertEqual(object["schema"] as? String, "archi-reading-sources/v5")

        let summary = try DesktopProfileBackup.create(profile: .custom, preferenceURL: fixture.source,
            archiveURL: fixture.archive)
        XCTAssertEqual(summary.knowledgeLinkVersionCount, 4)
        XCTAssertEqual(summary.knowledgePageVersionCount, 4)
        let preview = try DesktopProfileBackup.preview(archiveURL: fixture.archive, profile: .custom,
            preferenceURL: fixture.target)
        XCTAssertEqual(preview.summary.knowledgeLinkVersionCount, 4)
        let report = try DesktopProfileBackup.restore(preview, rollbackDirectory: fixture.recovery)
        XCTAssertEqual(try profileBytes(fixture.target), captured)
        let reopened = ReadingSourceLibrary(url: libraryURL(fixture.target))
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.knowledgeLinks, incoming.knowledgeLinks)
        XCTAssertEqual(reopened.knowledgePages, incoming.knowledgePages)
        XCTAssertNil(reopened.availability(of: reviewed))
        XCTAssertEqual(declaredEdges(reopened).count, 1)
        XCTAssertTrue(reopened.latestKnowledgeLinks.contains { $0.state == .withdrawn })

        _ = try DesktopProfileBackup.undoRestore(report)
        XCTAssertEqual(try profileBytes(fixture.target), before)
        XCTAssertEqual(try profileBytes(fixture.source), captured)
        XCTAssertTrue(ReadingSourceLibrary(url: libraryURL(fixture.target)).knowledgeLinks.isEmpty)
    }

    private func seed(_ preference: URL, label: String) throws -> ReadingSourceLibrary {
        _ = try NativePreferencePersistence.write(document: NativePreferenceDocument(), to: preference, expected: nil)
        let library = ReadingSourceLibrary(url: libraryURL(preference))
        let source = try library.keep(title: label, text: "\(label) source passage 😀.",
            provenance: .init(origin: .human, acquisition: .userCopy))
        let anchor = try library.makeAnchor(sourceID: source.id, range: NSRange(location: 0, length: source.text.utf16.count))
        for suffix in ["A", "B"] {
            let draft = try library.saveKnowledgePage(title: "\(label) \(suffix)", body: "An authored interpretation \(suffix).",
                kind: .claim, anchors: [anchor])
            _ = try library.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        }
        return library
    }

    private func link(_ library: ReadingSourceLibrary, from: KnowledgePage, to: KnowledgePage) throws -> KnowledgePageLink {
        let draft = try library.saveKnowledgeLink(from: from.binding, to: to.binding, kind: .supports,
            rationale: "The first page supports the second, as explicitly interpreted by the user.")
        return try library.reviewKnowledgeLink(id: draft.id, expectedRevision: draft.revision)
    }

    private func declaredEdges(_ library: ReadingSourceLibrary) -> [CompanionGraphEdge] {
        KnowledgePageGraph.append(to: .empty, library: library).edges.filter { $0.label.hasPrefix("declared ") }
    }

    private func pageNode(_ id: String, graph: CompanionGraphSnapshot) throws -> CompanionGraphNode {
        try XCTUnwrap(graph.nodes.first { $0.target == .knowledgePage(id: id) })
    }

    private func libraryURL(_ preference: URL) -> URL {
        preference.deletingPathExtension().appendingPathExtension("reading-sources.json")
    }

    private func profileBytes(_ preference: URL) throws -> [Data?] {
        let urls = [preference] + ["evolution.json", "document-work.json", "document-procedures.json", "reading-sources.json"].map {
            preference.deletingPathExtension().appendingPathExtension($0)
        }
        return try urls.map { FileManager.default.fileExists(atPath: $0.path) ? try Data(contentsOf: $0) : nil }
    }

    private struct Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("archi-knowledge-link-integration-\(UUID())")
        var source: URL { root.appendingPathComponent("source/preferences.json") }
        var target: URL { root.appendingPathComponent("target/preferences.json") }
        var archive: URL { root.appendingPathComponent("saved.archibackup") }
        var recovery: URL { root.appendingPathComponent("Recovery") }
        init() throws {
            for url in [source, target] {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}

@MainActor
private final class KnowledgeLinkNoModelClient: AssistantClient {
    var calls = 0
    func connect() async throws {}
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1
        XCTFail("Connection authoring must not dispatch a model.")
    }
}
