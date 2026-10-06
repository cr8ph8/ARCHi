import Foundation
import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

/// Exercises the existing owners with disposable profiles and in-process replies.
/// Follow-through reads a retained method; it cannot keep a new family or rate work.
@MainActor
final class DocumentMethodFollowThroughTests: XCTestCase {
    func testAppliedHelpfulMethodReuseAndRestartRetainOneExactFamily() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let applied = try await fixture.appliedEdit()
        XCTAssertEqual(fixture.store.documentMethodFollowThrough(for: applied), .newMethod)

        let origin = try fixture.review(applied, as: .helpful)
        let method = try fixture.keepProcedure(from: origin)
        XCTAssertEqual(fixture.store.documentMethodFollowThrough(for: origin), .kept([method]))

        let reused = try await fixture.appliedEdit(using: method, passage: "Another original copy.")
        XCTAssertEqual(reused.procedureUse, method.binding)
        XCTAssertNil(reused.feedback)
        XCTAssertEqual(fixture.store.documentMethodFollowThrough(for: reused), .used(method, isHistorical: false))
        let helpful = try fixture.review(reused, as: .helpful)
        XCTAssertEqual(fixture.store.documentMethodFollowThrough(for: helpful), .used(method, isHistorical: false))
        XCTAssertEqual(fixture.store.documentProcedures.procedures, [method],
            "Reviewing a use must not create a second method family.")
        XCTAssertEqual(fixture.store.outcomes(for: method)?.helpful, 1)
        try await renderOutcomeIfRequested(store: fixture.store, record: helpful)

        let journalBytes = try Data(contentsOf: fixture.journalURL)
        let methodBytes = try Data(contentsOf: fixture.procedureURL)
        let usageBytes = try Data(contentsOf: fixture.usageURL)
        let task = try XCTUnwrap(fixture.store.tokenSteward.tasks.first { $0.id == helpful.requestID })
        XCTAssertTrue(fixture.store.documentFeedbackUsageCurrent(helpful))
        let reopened = fixture.reopen()
        defer { reopened.disconnectAssistant() }
        let restored = try XCTUnwrap(reopened.documentWork.records.first { $0.id == helpful.id })
        XCTAssertEqual(restored, helpful)
        XCTAssertEqual(reopened.documentMethodFollowThrough(for: restored), .used(method, isHistorical: false))
        XCTAssertEqual(reopened.documentProcedures.procedures, [method])
        XCTAssertEqual(reopened.outcomes(for: method)?.helpful, 1)
        XCTAssertEqual(reopened.tokenSteward.tasks.first { $0.id == helpful.requestID }, task)
        XCTAssertTrue(reopened.documentFeedbackUsageCurrent(restored))
        reopened.syncDocumentFeedback(id: restored.id)
        XCTAssertEqual(reopened.tokenSteward.tasks.first { $0.id == helpful.requestID }, task,
            "Retry after reopening must not add another helpful outcome.")
        XCTAssertTrue(reopened.sharedText.isEmpty, "A retained receipt does not restore the working copy.")
        XCTAssertEqual(try Data(contentsOf: fixture.journalURL), journalBytes)
        XCTAssertEqual(try Data(contentsOf: fixture.procedureURL), methodBytes)
        XCTAssertEqual(try Data(contentsOf: fixture.usageURL), usageBytes)
        XCTAssertEqual(fixture.client.requests, 2)
    }

    func testReversedFeedbackAndLostSourceKeepTheUsedVersionInspectable() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let page = try fixture.reviewedConcept()
        let method = try fixture.keepCandidate(from: page)
        let applied = try await fixture.appliedEdit(using: method)
        let helpful = try fixture.review(applied, as: .helpful)
        XCTAssertNil(fixture.store.documentProcedureUnavailable(method.binding))
        let task = try XCTUnwrap(fixture.store.tokenSteward.tasks.first { $0.id == helpful.requestID })
        let provenance = try XCTUnwrap(task.requestProvenance)
        XCTAssertEqual(provenance.knowledgeDependencies, [page.binding])
        XCTAssertEqual(provenance.readingDependencies, page.anchors.map(\.source))
        XCTAssertEqual(provenance.inputDigest, helpful.learning?.requestBinding.inputDigest)
        let feedback = try XCTUnwrap(helpful.feedback)
        XCTAssertEqual(task.outcomes.last { $0.kind == .userUseful }?.evidenceID, "document-review-" + feedback.id)
        let reopened = fixture.reopen()
        defer { reopened.disconnectAssistant() }
        let restored = try XCTUnwrap(reopened.documentWork.records.first { $0.id == helpful.id })
        XCTAssertEqual(reopened.tokenSteward.tasks.first { $0.id == helpful.requestID }, task)
        XCTAssertEqual(restored.procedureUse, method.binding)
        XCTAssertEqual(reopened.documentProcedures.procedure(matching: method.binding)?.knowledgeOrigin, page.binding)
        XCTAssertTrue(reopened.documentFeedbackUsageCurrent(restored))
        XCTAssertNil(reopened.documentProcedureUnavailable(method.binding))

        let corrected = try fixture.review(helpful, as: .needsCorrection)
        XCTAssertEqual(corrected.procedureUseRejected, true)
        XCTAssertNotNil(fixture.store.documentProcedureUnavailable(method.binding))
        XCTAssertEqual(fixture.store.documentMethodFollowThrough(for: corrected), .used(method, isHistorical: false))
        let rereviewed = try fixture.review(corrected, as: .helpful)
        XCTAssertEqual(rereviewed.procedureUseRejected, true)
        XCTAssertEqual(fixture.store.outcomes(for: method)?.helpful, 0)

        fixture.store.withdrawKnowledgePage(page)
        XCTAssertFalse(fixture.store.knowledgeDependenciesAreCurrent([page.binding]))
        XCTAssertEqual(fixture.store.documentMethodFollowThrough(for: rereviewed), .used(method, isHistorical: false),
            "Lost source support blocks new reuse without disguising the earlier use as ordinary work.")
        XCTAssertEqual(fixture.store.documentProcedures.procedures, [method])
        XCTAssertFalse(fixture.store.canPrepareDocumentProcedure(method))
    }

    func testExternallyChangedUsageCannotClaimCurrentFeedbackOrReplayEarlierReview() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let helpful = try fixture.review(try await fixture.appliedEdit(), as: .helpful)
        XCTAssertTrue(fixture.store.documentFeedbackUsageCurrent(helpful))
        let journalBytes = try Data(contentsOf: fixture.journalURL)
        let originalEvent = try XCTUnwrap(helpful.feedback)
        let other = TokenStewardStore(url: fixture.usageURL)
        let newerEvent = "fixture-review-" + UUID().uuidString
        try other.recordUserFeedback(requestID: helpful.requestID, evidenceID: newerEvent, useful: false)
        let usageBytes = try Data(contentsOf: fixture.usageURL)

        XCTAssertTrue(fixture.store.documentWork.isCurrentOnDisk)
        XCTAssertNil(fixture.store.tokenSteward.loadError)
        XCTAssertFalse(fixture.store.tokenSteward.isCurrentOnDisk)
        XCTAssertFalse(fixture.store.documentFeedbackUsageCurrent(helpful),
            "A cached matching event cannot claim that externally changed Usage is current.")
        XCTAssertEqual(try Data(contentsOf: fixture.usageURL), usageBytes)
        XCTAssertEqual(try Data(contentsOf: fixture.journalURL), journalBytes)

        try fixture.store.tokenSteward.refresh()
        XCTAssertFalse(fixture.store.documentFeedbackUsageCurrent(helpful))
        fixture.store.syncDocumentFeedback(id: helpful.id)
        XCTAssertFalse(fixture.store.documentFeedbackUsageCurrent(helpful),
            "Retry must not replay an older helpful event over a later outcome.")
        XCTAssertEqual(fixture.store.documentWork.records.first { $0.id == helpful.id }?.feedback, originalEvent)
        XCTAssertEqual(try Data(contentsOf: fixture.usageURL), usageBytes)
        XCTAssertEqual(try Data(contentsOf: fixture.journalURL), journalBytes)

        let corrected = try fixture.review(helpful, as: .needsCorrection)
        XCTAssertEqual(corrected.feedback?.revision, originalEvent.revision + 1)
        XCTAssertTrue(fixture.store.documentFeedbackUsageCurrent(corrected))
        let outcomes = try XCTUnwrap(fixture.store.tokenSteward.tasks.first { $0.id == helpful.requestID }).outcomes
        XCTAssertEqual(outcomes.filter { $0.kind == .userUseful }.count, 3)
        XCTAssertEqual(outcomes.last { $0.kind == .userUseful }?.evidenceID,
            "document-review-" + (try XCTUnwrap(corrected.feedback).id))
    }

    func testSupersedingMethodDoesNotRetargetEarlierUseToLatestVersion() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let origin = try fixture.review(try await fixture.appliedEdit(), as: .helpful)
        let first = try fixture.keepProcedure(from: origin)
        let reused = try fixture.review(try await fixture.appliedEdit(using: first), as: .helpful)
        XCTAssertTrue(fixture.store.reviseDocumentProcedure(first.binding, title: first.title,
            instruction: "Use plain words while preserving qualifications.",
            changeNote: "Make the qualification requirement explicit.", recordID: reused.id),
            fixture.store.documentWorkMessage ?? fixture.store.status)
        let latest = try XCTUnwrap(fixture.store.documentProcedures.latestProcedures.first)
        XCTAssertEqual(latest.id, first.id)
        XCTAssertEqual(latest.revision, 2)
        XCTAssertEqual(fixture.store.documentMethodFollowThrough(for: reused), .used(first, isHistorical: true))
        XCTAssertEqual(fixture.store.documentMethodFollowThrough(for: origin), .kept([first]),
            "The original result still identifies its kept method after supersession.")
        XCTAssertEqual(fixture.store.outcomes(for: first)?.helpful, 1)
        XCTAssertEqual(fixture.store.outcomes(for: latest)?.attempts, 0)

        let correctedOrigin = try fixture.review(origin, as: .needsCorrection)
        XCTAssertNotNil(fixture.store.documentProcedureUnavailable(first.binding))
        XCTAssertEqual(fixture.store.documentMethodFollowThrough(for: correctedOrigin), .kept([first]))
        fixture.store.withdrawDocumentProcedure(first.binding)
        let withdrawn = try XCTUnwrap(fixture.store.documentProcedures.procedure(matching: first.binding))
        XCTAssertTrue(withdrawn.withdrawn)
        XCTAssertEqual(fixture.store.documentMethodFollowThrough(for: correctedOrigin), .kept([withdrawn]),
            "Feedback reversal and withdrawal preserve the source-to-method handoff.")
        XCTAssertEqual(fixture.store.documentMethodFollowThrough(for: reused), .used(withdrawn, isHistorical: true))
    }

    func testStaleRecordAndExternallyChangedJournalCannotOfferFollowThrough() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let applied = try await fixture.appliedEdit()
        let helpful = try fixture.review(applied, as: .helpful)
        assertUnavailable(fixture.store.documentMethodFollowThrough(for: applied))

        let other = DocumentWorkJournal(url: fixture.journalURL)
        var changed = try XCTUnwrap(other.records.first { $0.id == helpful.id })
        changed.detail = "Retained receipt updated by another owner."
        changed.updatedAt = changed.updatedAt.addingTimeInterval(1)
        try other.save(changed)
        let bytes = try Data(contentsOf: fixture.journalURL)
        XCTAssertFalse(fixture.store.documentWork.isCurrentOnDisk)
        assertUnavailable(fixture.store.documentMethodFollowThrough(for: helpful))
        XCTAssertEqual(try Data(contentsOf: fixture.journalURL), bytes)
    }

    func testExternallyChangedMethodLibraryCannotOfferCachedMethod() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let origin = try fixture.review(try await fixture.appliedEdit(), as: .helpful)
        let method = try fixture.keepProcedure(from: origin)
        let reused = try await fixture.appliedEdit(using: method)
        let other = DocumentProcedureLibrary(url: fixture.procedureURL)
        try other.withdraw(binding: method.binding)
        let bytes = try Data(contentsOf: fixture.procedureURL)

        XCTAssertFalse(fixture.store.documentProcedures.isCurrentOnDisk)
        assertUnavailable(fixture.store.documentMethodFollowThrough(for: reused))
        assertUnavailable(fixture.store.documentMethodFollowThrough(for: origin))
        XCTAssertEqual(try Data(contentsOf: fixture.procedureURL), bytes)
    }

    func testMissingExactBindingAfterRestartNeverBecomesNewMethod() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let origin = try fixture.review(try await fixture.appliedEdit(), as: .helpful)
        let method = try fixture.keepProcedure(from: origin)
        let reused = try await fixture.appliedEdit(using: method)
        var archive = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.procedureURL)) as? [String: Any])
        archive["procedures"] = []
        let missingMethodBytes = try JSONSerialization.data(withJSONObject: archive, options: [.sortedKeys])
        try missingMethodBytes.write(to: fixture.procedureURL, options: .atomic)

        let reopened = fixture.reopen()
        defer { reopened.disconnectAssistant() }
        let restored = try XCTUnwrap(reopened.documentWork.records.first { $0.id == reused.id })
        XCTAssertNil(reopened.documentProcedures.loadError)
        XCTAssertTrue(reopened.documentProcedures.isCurrentOnDisk)
        XCTAssertEqual(restored.procedureUse, method.binding)
        assertUnavailable(reopened.documentMethodFollowThrough(for: restored))
        XCTAssertTrue(reopened.documentProcedures.procedures.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture.procedureURL), missingMethodBytes)
    }

    private func assertUnavailable(_ state: DocumentMethodFollowThroughState,
                                   file: StaticString = #filePath, line: UInt = #line) {
        guard case .unavailable(let reason) = state else {
            XCTFail("Expected an unavailable handoff, received \(state).", file: file, line: line)
            return
        }
        XCTAssertFalse(reason.isEmpty, file: file, line: line)
    }

    private func renderOutcomeIfRequested(store: CompanionStore, record: DocumentWorkRecord) async throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_METHOD_FOLLOW_THROUGH_RENDER_DIR"],
              !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let content = VStack(alignment: .leading, spacing: 12) {
            Text("Disposable test fixture · mock reply and scripted review")
                .font(.caption.weight(.semibold))
            DocumentOutcomeView(store: store, record: record)
        }
        .padding().frame(width: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: content)
        let panel = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 520, height: 800),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        defer { panel.contentView = nil; panel.close() }
        hosting.layoutSubtreeIfNeeded()
        panel.setContentSize(NSSize(width: 520, height: ceil(hosting.fittingSize.height)))
        hosting.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(140))
        hosting.layoutSubtreeIfNeeded()
        XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(panel.isKeyWindow)
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("method-used-helpful-fixture.png"))
    }

    @MainActor private final class Clock { var now = Date(timeIntervalSince1970: 1_800_000_000) }

    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-method-follow-through-\(UUID())")
        let client = FollowThroughClient()
        let clock = Clock()
        var preferenceURL: URL { directory.appendingPathComponent("preferences.json") }
        var journalURL: URL { directory.appendingPathComponent("preferences.document-work.json") }
        var procedureURL: URL { directory.appendingPathComponent("preferences.document-procedures.json") }
        var usageURL: URL { directory.appendingPathComponent("usage.json") }
        lazy var store = CompanionStore(preferenceURL: preferenceURL, assistant: client,
            assistantFactory: { [client] _, _ in client }, wallClock: { [clock] in clock.now },
            allowsPlay: false, tokenSteward: TokenStewardStore(url: usageURL))

        func appliedEdit(using method: DocumentProcedure? = nil,
                         passage: String = "Original copy.") async throws -> DocumentWorkRecord {
            clock.now = clock.now.addingTimeInterval(1)
            store.share(text: passage, name: "fixture.txt")
            store.selectText(range: NSRange(location: 0, length: passage.utf16.count), sourceRevision: store.sourceRevision)
            store.preparePassageRevision()
            if let method {
                store.documentRequirements = .init(mustBeShorter: method.mustBeShorter,
                    preserveNumbersAndLinks: method.preserveNumbersAndLinks)
                XCTAssertTrue(store.prepareDocumentProcedure(method.binding), store.documentWorkMessage ?? store.status)
            }
            store.setAssistantRoute(.automatic)
            store.setLocalWorkPreference(.reasoning)
            client.request = nil
            store.submit()
            try await wait { self.client.request != nil }
            let proposal = try client.complete()
            try await wait { !self.store.isWorking }
            XCTAssertEqual(store.compareResults[.qwen]?.state, .complete, store.status)
            XCTAssertTrue(store.canApplyDocumentRevision(provider: .qwen, proposal: proposal), store.status)
            store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
            let record = try XCTUnwrap(store.documentWork.records.first { $0.targetID == proposal.target.id })
            XCTAssertEqual(record.state, .applied, store.documentWorkMessage ?? store.status)
            return record
        }

        func review(_ record: DocumentWorkRecord, as verdict: DocumentWorkFeedback.Verdict) throws -> DocumentWorkRecord {
            clock.now = clock.now.addingTimeInterval(1)
            XCTAssertTrue(store.reviewDocument(id: record.id, verdict: verdict), store.documentWorkMessage ?? store.status)
            return try XCTUnwrap(store.documentWork.records.first { $0.id == record.id })
        }

        func keepProcedure(from record: DocumentWorkRecord) throws -> DocumentProcedure {
            XCTAssertTrue(store.keepDocumentProcedure(recordID: record.id,
                title: "Plain revision", instruction: "Use plain words."), store.documentWorkMessage ?? store.status)
            return try XCTUnwrap(store.documentProcedures.latestProcedures.first)
        }

        func reviewedConcept() throws -> KnowledgePage {
            let source = try store.readingSources.keep(title: "Synthetic guidance", text: "Use plain words while preserving the action.")
            let anchor = try store.readingSources.makeAnchor(sourceID: source.id,
                range: NSRange(location: 0, length: source.text.utf16.count))
            let draft = try store.readingSources.saveKnowledgePage(title: "Plain requests",
                body: "A synthetic interpretation with explicit source support.", kind: .concept, anchors: [anchor])
            return try store.readingSources.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        }

        func keepCandidate(from page: KnowledgePage) throws -> DocumentProcedure {
            XCTAssertTrue(store.keepKnowledgeProcedure(page: page, title: "Plain revision", instruction: "Use plain words.",
                requirements: .init(mustBeShorter: false, preserveNumbersAndLinks: true)), store.knowledgePageMessage ?? store.status)
            return try XCTUnwrap(store.documentProcedures.latestProcedures.first)
        }

        func reopen() -> CompanionStore {
            CompanionStore(preferenceURL: preferenceURL, assistant: FollowThroughClient(),
                wallClock: { [clock] in clock.now }, allowsPlay: false, tokenSteward: TokenStewardStore(url: usageURL))
        }

        func wait(_ condition: @MainActor () -> Bool) async throws {
            for _ in 0..<400 {
                if condition() { return }
                try await Task.sleep(for: .milliseconds(5))
            }
            XCTFail("Timed out: \(store.status) | \(store.documentWorkMessage ?? "none")")
            throw AssistantFailure.timedOut
        }

        func clean() {
            store.cancelWork(); store.disconnectAssistant(); client.resolve()
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

@MainActor
private final class FollowThroughClient: AssistantClient {
    var request: AssistantRequest?
    private(set) var requests = 0
    private var handler: (@MainActor (AssistantEvent) -> Void)?
    private var continuation: CheckedContinuation<Void, Error>?
    func connect() async throws {}
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        requests += 1
        self.request = request
        handler = onEvent
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func complete() throws -> PassageRevisionProposal {
        let target = try XCTUnwrap(request?.revisionTarget)
        let proposal = PassageRevisionProposal(target: target, decision: .propose, replacement: "Clear copy.",
            explanation: "Review the proposed wording.", sourceIDs: ["selected-passage"], memoryIDs: [])
        handler?(.revision(proposal)); resolve()
        return proposal
    }
    func resolve() { let pending = continuation; continuation = nil; pending?.resume() }
}
