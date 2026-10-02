import Foundation
import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

@MainActor
final class DocumentMethodGraphTests: XCTestCase {
    func testMemoryIncludesExactMethodsAndSupportWithoutAddingEveryAttempt() throws {
        let fixture = Fixture(); defer { fixture.clean() }
        let origin = try fixture.record()
        let method = try fixture.keep(origin)
        let reuse = try fixture.record(using: method.binding)
        let before = try fixture.bytes()
        let graph = fixture.store.memoryMapSnapshot()
        let node = try XCTUnwrap(graph.nodes.first { $0.id == DocumentMethodGraph.nodeID(method.binding) })
        XCTAssertEqual(node.kind, .method)
        XCTAssertEqual(node.target, .documentMethod(method.binding))
        XCTAssertTrue(node.details.contains { $0.label == "Outcome" && $0.value.hasPrefix("1 Helpful") })
        XCTAssertTrue(graph.edges.contains {
            $0.source == node.id && $0.target == DocumentWorkGraph.nodeID(recordID: origin.id)
                && $0.label == "kept from reviewed edit"
        })
        XCTAssertFalse(graph.nodes.contains { $0.id == DocumentWorkGraph.nodeID(recordID: reuse.id) })
        XCTAssertFalse(graph.nodes.contains { [.request, .invocation, .accounting].contains($0.kind) })
        let activity = fixture.store.companionGraphSnapshot()
        XCTAssertTrue(activity.edges.contains {
            $0.source == DocumentWorkGraph.nodeID(recordID: reuse.id) && $0.target == node.id
                && $0.label == "used exact method version"
        })
        XCTAssertEqual(try fixture.bytes(), before)
    }

    func testRestartInspectionKeepsExactVersionAndDoesNotPrepareOrWrite() async throws {
        let fixture = Fixture(); defer { fixture.clean() }
        let method = try fixture.keep(fixture.record())
        let reopened = fixture.reopen()
        defer { reopened.disconnectAssistant() }
        reopened.prompt = "Keep my draft."
        let before = try fixture.bytes()
        reopened.openGraphTarget(.documentMethod(method.binding))
        let selection = try XCTUnwrap(reopened.inspectedDocumentMethod)
        XCTAssertEqual(reopened.section, .nodeLab)
        XCTAssertEqual(reopened.methodForInspection(selection), method)
        XCTAssertNil(fixture.store.methodForInspection(selection), "A selection cannot cross profile owners.")
        XCTAssertNil(reopened.preparedDocumentProcedure)
        XCTAssertEqual(reopened.prompt, "Keep my draft.")
        XCTAssertFalse(reopened.isWorking)
        XCTAssertTrue(reopened.sharedText.isEmpty)
        XCTAssertEqual(try fixture.bytes(), before)
        XCTAssertEqual(reopened.memoryMapSnapshot().nodes.first { $0.kind == .method }?.id,
                       DocumentMethodGraph.nodeID(method.binding))
        try await renderIfRequested(store: reopened, selection: selection)
        XCTAssertEqual(try fixture.bytes(), before)
    }

    func testStaleMethodOrJournalOwnersCannotPresentCurrentOutcomesOrInspection() throws {
        let fixture = Fixture(); defer { fixture.clean() }
        let method = try fixture.keep(fixture.record())
        fixture.store.openGraphTarget(.documentMethod(method.binding))
        let selection = try XCTUnwrap(fixture.store.inspectedDocumentMethod)
        let other = DocumentProcedureLibrary(url: fixture.methodURL)
        try other.withdraw(binding: method.binding)
        let before = try fixture.bytes()
        let node = try XCTUnwrap(fixture.store.memoryMapSnapshot().nodes.first { $0.kind == .method })
        XCTAssertEqual(node.status, "History needs review")
        XCTAssertTrue(node.details.contains { $0.label == "Outcome" && $0.value == "Outcome history is unavailable." })
        XCTAssertNil(fixture.store.methodForInspection(selection))
        XCTAssertEqual(try fixture.bytes(), before)

        let reopened = fixture.reopen()
        defer { reopened.disconnectAssistant() }
        XCTAssertEqual(reopened.memoryMapSnapshot().nodes.first { $0.kind == .method }?.status, "Withdrawn")
        let otherJournal = DocumentWorkJournal(url: fixture.journalURL)
        var record = try XCTUnwrap(otherJournal.records.first)
        record.detail = "Receipt changed in another owner."
        record.updatedAt = record.updatedAt.addingTimeInterval(1)
        try otherJournal.save(record)
        XCTAssertEqual(reopened.memoryMapSnapshot().nodes.first { $0.kind == .method }?.status, "History needs review")
    }

    func testCorrectionAndSupersessionPreserveEarlierMethodIdentity() throws {
        let fixture = Fixture(); defer { fixture.clean() }
        let first = try fixture.keep(fixture.record())
        let support = try fixture.record(using: first.binding)
        let next = try fixture.store.documentProcedures.revise(binding: first.binding, title: first.title,
            instruction: "Preserve qualifications while using plain words.", changeNote: "Retain the qualifications.",
            from: support, records: fixture.store.documentWork.records)
        let graph = fixture.store.memoryMapSnapshot()
        XCTAssertEqual(graph.nodes.first { $0.id == DocumentMethodGraph.nodeID(first.binding) }?.status, "Earlier version")
        XCTAssertTrue(graph.edges.contains {
            $0.source == DocumentMethodGraph.nodeID(next.binding) && $0.target == DocumentMethodGraph.nodeID(first.binding)
                && $0.label == "supersedes version"
        })
        fixture.store.openGraphTarget(.documentMethod(first.binding))
        XCTAssertEqual(fixture.store.methodForInspection(try XCTUnwrap(fixture.store.inspectedDocumentMethod)), first)
        _ = try fixture.record(using: first.binding, verdict: .needsCorrection)
        let corrected = fixture.store.memoryMapSnapshot()
        XCTAssertEqual(corrected.nodes.first { $0.id == DocumentMethodGraph.nodeID(first.binding) }?.status, "Unavailable for reuse")
        XCTAssertTrue(corrected.nodes.contains { $0.id == DocumentMethodGraph.nodeID(next.binding) })
    }

    func testConceptSourceLossRetainsOriginLinkAndUnavailableMethod() throws {
        let fixture = Fixture(); defer { fixture.clean() }
        let library = fixture.store.readingSources
        let source = try library.keep(title: "Synthetic source", text: "Keep claims attributed.")
        let anchor = try library.makeAnchor(sourceID: source.id, range: NSRange(location: 0, length: source.text.utf16.count))
        let draft = try library.saveKnowledgePage(title: "Attribution", body: "Keep the original source.", kind: .concept, anchors: [anchor])
        let page = try library.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        XCTAssertTrue(fixture.store.keepKnowledgeProcedure(page: page, title: "Attribute claims", instruction: "Keep attribution.",
            requirements: .init(mustBeShorter: false, preserveNumbersAndLinks: true)))
        let method = try XCTUnwrap(fixture.store.documentProcedures.latestProcedures.first)
        let before = fixture.store.memoryMapSnapshot()
        let origin = try XCTUnwrap(before.nodes.first { $0.target == .knowledgePage(id: page.id) })
        XCTAssertTrue(before.edges.contains { $0.source == DocumentMethodGraph.nodeID(method.binding) && $0.target == origin.id })
        try library.forget(id: source.id)
        let after = fixture.store.memoryMapSnapshot()
        XCTAssertEqual(after.nodes.first { $0.kind == .method }?.status, "Unavailable for reuse")
        XCTAssertTrue(after.edges.contains { $0.source == DocumentMethodGraph.nodeID(method.binding) && $0.target == origin.id })
    }

    func testActivityMethodOriginDoesNotReuseOlderCapturedPageReference() throws {
        let fixture = Fixture(); defer { fixture.clean() }
        let library = fixture.store.readingSources
        let source = try library.keep(title: "Synthetic source", text: "Keep claims attributed.")
        let anchor = try library.makeAnchor(sourceID: source.id,
            range: NSRange(location: 0, length: source.text.utf16.count))
        let firstDraft = try library.saveKnowledgePage(title: "Earlier attribution", body: "Retain attribution.",
            kind: .concept, anchors: [anchor])
        let earlier = try library.reviewKnowledgePage(id: firstDraft.id, expectedRevision: firstDraft.revision)
        let taskID = UUID().uuidString
        try fixture.store.tokenSteward.preflight(requestID: taskID, route: .automatic)
        try fixture.store.tokenSteward.recordRequestProvenance(requestID: taskID,
            provenance: .init(inputDigest: fixture.hex("a"), knowledgeDependencies: [earlier.binding]))

        let nextDraft = try library.saveKnowledgePage(id: earlier.id, expectedRevision: earlier.revision,
            title: "Current attribution", body: "Keep the original source and attribution.", kind: .concept, anchors: [anchor])
        let current = try library.reviewKnowledgePage(id: nextDraft.id, expectedRevision: nextDraft.revision)
        XCTAssertNotEqual(earlier.binding, current.binding)
        XCTAssertTrue(fixture.store.keepKnowledgeProcedure(page: current, title: "Attribute claims",
            instruction: "Keep attribution.", requirements: .init()))
        let method = try XCTUnwrap(fixture.store.documentProcedures.latestProcedures.first)
        let graph = fixture.store.companionGraphSnapshot()
        let captured = try XCTUnwrap(graph.nodes.first {
            $0.target == .knowledgePage(id: earlier.id) && $0.status == "Historical reference"
                && $0.details.contains(.init(label: "Revision", value: String(earlier.revision)))
        })
        let origin = try XCTUnwrap(graph.nodes.first { $0.id == KnowledgePageGraph.nodeID(current.binding) })
        XCTAssertEqual(origin.title, current.title)
        XCTAssertNotEqual(captured.id, origin.id)
        XCTAssertTrue(graph.edges.contains {
            $0.source == DocumentMethodGraph.nodeID(method.binding) && $0.target == origin.id
                && $0.label == "authored from concept"
        })
        XCTAssertFalse(graph.edges.contains {
            $0.source == DocumentMethodGraph.nodeID(method.binding) && $0.target == captured.id
        })
    }

    private func renderIfRequested(store: CompanionStore, selection: DocumentMethodInspectionSelection) async throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_METHOD_GRAPH_RENDER_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await render(DocumentMethodInspectionView(store: store, selection: selection),
            to: directory.appendingPathComponent("method-inspector-fixture.png"), size: NSSize(width: 600, height: 660))
        try await render(CompanionGraphView(snapshot: store.memoryMapSnapshot(), onOpen: { _ in },
            initialSelectionID: DocumentMethodGraph.nodeID(selection.binding), reduceMotion: true),
            to: directory.appendingPathComponent("method-memory-map-fixture.png"), size: NSSize(width: 1100, height: 780))
    }

    private func render<Content: View>(_ content: Content, to url: URL, size: NSSize) async throws {
        let view = VStack(alignment: .leading, spacing: 8) {
            Text("Disposable fixture · scripted records").font(.caption.weight(.semibold)).padding(.horizontal, 16)
            content
        }
        .padding(.vertical, 12).frame(width: size.width, height: size.height)
        .background(Color(nsColor: .windowBackgroundColor))
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: view)
        let panel = NSPanel(contentRect: NSRect(origin: NSPoint(x: 100, y: 100), size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        defer { panel.contentView = nil; panel.close() }
        hosting.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(140))
        hosting.layoutSubtreeIfNeeded()
        XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(panel.isKeyWindow)
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-method-graph-\(UUID())")
        var preferenceURL: URL { directory.appendingPathComponent("preferences.json") }
        var methodURL: URL { directory.appendingPathComponent("preferences.document-procedures.json") }
        var journalURL: URL { directory.appendingPathComponent("preferences.document-work.json") }
        lazy var store = reopen()

        func reopen() -> CompanionStore {
            CompanionStore(preferenceURL: preferenceURL, allowsPlay: false, tokenSteward: TokenStewardStore())
        }

        func record(using method: DocumentProcedureUse? = nil,
                    verdict: DocumentWorkFeedback.Verdict = .helpful) throws -> DocumentWorkRecord {
            let request = UUID().uuidString
            let date = Date()
            var record = DocumentWorkRecord(id: request + "-Qwen", requestID: request, provider: "Qwen",
                targetID: UUID().uuidString, sourceDigest: hex("a"), sourceRevision: 1,
                selectionStart: 0, selectionLength: 12, preserveNumbersAndLinks: true,
                createdAt: date, updatedAt: date.addingTimeInterval(20), state: .applying,
                proposedDigest: hex("b"), expectedAfterDigest: hex("c"), actualAfterDigest: hex("c"), afterRevision: 2,
                checks: [.init(id: "source", title: "Exact source", passed: true)],
                learning: .init(requestBinding: .init(inputDigest: hex("d"), contextDigest: hex("e")), suppliedLessons: []),
                procedureUse: method)
            try store.documentWork.save(record)
            record.state = .applied
            record.feedback = .init(revision: 1, verdict: verdict, recordedAt: date.addingTimeInterval(10))
            if method != nil && verdict != .helpful { record.procedureUseRejected = true }
            try store.documentWork.save(record)
            return record
        }

        func keep(_ record: DocumentWorkRecord) throws -> DocumentProcedure {
            try store.documentProcedures.keep(from: record, title: "Plain revision", instruction: "Use plain words.",
                records: store.documentWork.records)
        }

        func bytes() throws -> [Data] { try [methodURL, journalURL].map { try Data(contentsOf: $0) } }
        func hex(_ character: Character) -> String { String(repeating: character, count: 64) }
        func clean() { store.disconnectAssistant(); try? FileManager.default.removeItem(at: directory) }
    }
}
