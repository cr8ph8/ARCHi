import Foundation
import XCTest
@testable import ARCHiDesktop

final class DesktopInterestStoreTests: XCTestCase {
    @MainActor
    func testNativeFallbackRequiresAllowanceForExactWindowBytes() async throws {
        for permission in ["none", "exact", "changed"] {
            let f = InterestStoreFixture(); defer { f.cleanUp() }
            try await f.adopt()
            f.store.setAssistantRoute(.native)
            if permission != "none" { f.store.allowDesktopInterestWithExternalRoute() }
            if permission == "changed" { f.store.sharedText += " Changed after permission." }
            f.store.prompt = "Explain the window copy."
            XCTAssertTrue(f.store.canBeginReply, "Local work needs no external allowance")
            f.store.submit()
            try await interestStoreSettle { f.local.requests.count == 1 }
            f.local.fail(0, error: QwenFailure.unavailable)
            if permission == "exact" {
                try await interestStoreSettle { f.cloud.requests.count == 1 }
                XCTAssertEqual(f.cloud.requests[0].sourceText, f.reader.text)
                f.cloud.complete(0, text: "Permitted fallback")
                try await interestStoreSettle { !f.store.isWorking }
            } else {
                try await interestStoreSettle { !f.store.isWorking }
                await interestStoreDrain()
                XCTAssertEqual(f.cloud.connects, 0)
                XCTAssertTrue(f.cloud.requests.isEmpty)
                XCTAssertTrue(f.store.status.contains("local-only"))
            }
        }
    }

    @MainActor
    func testReviewedCaptureAdoptsExactWorkingCopyAndMetadataWithoutInferenceOrPersistence() async throws {
        let f = InterestStoreFixture(); defer { f.cleanUp() }
        f.store.share(text: "Existing unchanged copy.", name: "existing.txt")
        f.store.prompt = "Keep this unsent question."
        let revision = f.store.sourceRevision
        let evolutionRevision = f.store.evolution.revision
        f.beginTarget()
        XCTAssertEqual(f.store.desktopInterest.phase, .targeted)
        XCTAssertEqual(f.reader.reads, 0)
        XCTAssertEqual(f.store.sharedText, "Existing unchanged copy.")
        f.store.desktopInterest.read()
        try await interestStoreSettle { f.store.desktopInterest.phase == .review }
        XCTAssertEqual(f.store.sharedText, "Existing unchanged copy.", "Read is a candidate until Use snapshot")
        let captured = try XCTUnwrap(f.store.desktopInterest.capture)
        XCTAssertTrue(f.store.useDesktopInterestCapture())
        XCTAssertEqual(f.store.sharedText, captured.text)
        XCTAssertEqual(f.store.sourceRevision, revision + 1)
        XCTAssertEqual(f.store.sourceName, "Window snapshot · Synthetic Editor · Synthetic document")
        XCTAssertEqual(f.store.desktopInterestSource, DesktopInterestSource(appName: captured.target.appName,
            title: captured.target.title, method: captured.method, capturedAt: captured.capturedAt,
            digest: LessonSource.digest(of: captured.text)))
        XCTAssertEqual(f.store.prompt, "Keep this unsent question.")
        XCTAssertEqual(f.store.section, .context)
        XCTAssertNil(f.store.textSelection)
        XCTAssertNil(f.store.desktopInterestExternalDigest)
        XCTAssertEqual(f.store.desktopInterest.phase, .idle)
        XCTAssertFalse(f.store.useDesktopInterestCapture(), "The same review cannot be consumed twice")
        XCTAssertEqual(f.store.evolution.revision, evolutionRevision)
        XCTAssertEqual(f.local.connects + f.cloud.connects, 0)
        XCTAssertEqual(f.local.requests.count + f.cloud.requests.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.evolutionURL.path))
    }

    @MainActor
    func testCaptureUsesExistingSelectionAndRevisionPreparationWithoutSending() async throws {
        let f = InterestStoreFixture(); defer { f.cleanUp() }
        f.reader.text = "Café 👩🏽‍💻. Repeat. Repeat. e\u{301}\r\n"
        try await f.adopt()
        let range = (f.reader.text as NSString).range(of: "Repeat.", options: .backwards)
        let revision = f.store.sourceRevision
        f.store.selectText(range: range, sourceRevision: revision)
        XCTAssertEqual(f.store.textSelection, DocumentSelection(range: range, text: f.reader.text, sourceRevision: revision))
        f.store.preparePassageExplanation()
        XCTAssertEqual(f.store.prompt, "Explain the selected passage.")
        f.store.preparePassageRevision()
        XCTAssertTrue(f.store.requestsRevision)
        XCTAssertEqual(f.store.textSelection?.range, range)
        XCTAssertEqual(f.store.sharedText, f.reader.text)
        XCTAssertEqual(f.local.requests.count + f.cloud.requests.count, 0)
        XCTAssertEqual(f.local.connects + f.cloud.connects, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.path))
    }

    @MainActor
    func testExternalRoutesRequireExplicitExactCopyAllowanceBeforeDispatch() async throws {
        for route in [AssistantRoute.codex, .compare] {
            let f = InterestStoreFixture(); defer { f.cleanUp() }
            try await f.adopt()
            f.store.setAssistantRoute(route)
            f.store.connectAssistant()
            try await interestStoreSettle { route.providers.allSatisfy { f.store.connection(for: $0) == .ready } }
            f.store.prompt = "Explain this snapshot."
            XCTAssertFalse(f.store.canShareDesktopInterestWithRoute)
            XCTAssertFalse(f.store.canBeginReply)
            f.store.submit()
            await interestStoreDrain()
            XCTAssertEqual(f.local.requests.count + f.cloud.requests.count, 0)

            f.store.allowDesktopInterestWithExternalRoute()
            XCTAssertEqual(f.store.desktopInterestExternalDigest, LessonSource.digest(of: f.reader.text))
            XCTAssertTrue(f.store.canShareDesktopInterestWithRoute)
            XCTAssertTrue(f.store.canBeginReply)
            XCTAssertEqual(f.local.requests.count + f.cloud.requests.count, 0, "Allowance itself never sends")
            f.store.submit()
            try await interestStoreSettle { f.cloud.requests.count == 1 && (route != .compare || f.local.requests.count == 1) }
            XCTAssertEqual(f.cloud.requests[0].sourceText, f.reader.text)
            XCTAssertEqual(f.cloud.requests[0].prompt, "Explain this snapshot.")
            XCTAssertTrue(f.cloud.requests[0].localLessons.isEmpty)
            XCTAssertTrue(f.cloud.requests[0].localConversation.isEmpty)
            f.cloud.complete(0, text: "Synthetic external response")
            if route == .compare { f.local.complete(0, text: "Synthetic local response") }
            try await interestStoreSettle { !f.store.isWorking }

            let sent = f.local.requests.count + f.cloud.requests.count
            f.store.sharedText += " Changed bytes."
            XCTAssertFalse(f.store.canShareDesktopInterestWithRoute)
            XCTAssertFalse(f.store.canBeginReply)
            f.store.submit()
            await interestStoreDrain()
            XCTAssertEqual(f.local.requests.count + f.cloud.requests.count, sent)
        }
    }

    @MainActor
    func testLocalRoutesNeedNoExternalAllowanceAndSourceReplacementClearsIt() async throws {
        for stopSharing in [false, true] {
            let f = InterestStoreFixture(); defer { f.cleanUp() }
            try await f.adopt()
            for route in [AssistantRoute.local, .automatic] {
                f.store.setAssistantRoute(route)
                XCTAssertTrue(f.store.canShareDesktopInterestWithRoute)
                f.store.allowDesktopInterestWithExternalRoute()
                XCTAssertNil(f.store.desktopInterestExternalDigest)
            }
            f.store.setAssistantRoute(.codex)
            XCTAssertFalse(f.store.canShareDesktopInterestWithRoute)
            f.store.allowDesktopInterestWithExternalRoute()
            XCTAssertNotNil(f.store.desktopInterestExternalDigest)
            if stopSharing { f.store.stopSharing() }
            else { f.store.share(text: f.reader.text, name: "User supplied copy.txt") }
            XCTAssertNil(f.store.desktopInterestSource)
            XCTAssertNil(f.store.desktopInterestExternalDigest)
            XCTAssertEqual(f.store.desktopInterest.phase, .idle)
            XCTAssertEqual(f.store.sharedText, stopSharing ? "" : f.reader.text)
            XCTAssertEqual(f.local.requests.count + f.cloud.requests.count, 0)
        }
    }

    @MainActor
    func testBeginningFailureAndCancellationPreserveExistingCopyAndDraft() async throws {
        for fails in [false, true] {
            let f = InterestStoreFixture(); defer { f.cleanUp() }
            f.reader.holdsRead = true
            f.store.share(text: "Old copy stays available.", name: "old.txt")
            f.store.prompt = "An unsent command remains mine."
            let revision = f.store.sourceRevision
            f.beginTarget()
            XCTAssertEqual(f.store.sharedText, "Old copy stays available.")
            XCTAssertFalse(f.store.useDesktopInterestCapture())
            f.store.desktopInterest.read()
            try await interestStoreSettle { f.reader.reads == 1 }
            if fails { f.reader.fail() }
            else { f.store.desktopInterest.cancel(); f.reader.complete() }
            try await interestStoreSettle { f.reader.returned && f.store.desktopInterest.phase != .reading }
            await interestStoreDrain()
            XCTAssertEqual(f.store.desktopInterest.phase, fails ? .failed : .idle)
            XCTAssertFalse(f.store.useDesktopInterestCapture())
            XCTAssertNil(f.store.desktopInterestSource)
            XCTAssertEqual(f.store.sharedText, "Old copy stays available.")
            XCTAssertEqual(f.store.sourceName, "old.txt")
            XCTAssertEqual(f.store.sourceRevision, revision)
            XCTAssertEqual(f.store.prompt, "An unsent command remains mine.")
            XCTAssertEqual(f.local.requests.count + f.cloud.requests.count, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.path))
        }
    }

    @MainActor
    func testHidingOrShutdownCancelsAcquisitionAndFencesLateContent() async throws {
        for action in 0..<3 {
            let f = InterestStoreFixture(); defer { f.cleanUp() }
            f.reader.holdsRead = true
            f.store.share(text: "Existing text.", name: "existing.txt")
            f.store.prompt = "Preserve the draft."
            f.beginTarget(); f.store.desktopInterest.read()
            try await interestStoreSettle { f.reader.reads == 1 }
            switch action {
            case 0: f.store.isVisible = false
            case 1: f.store.hideCompanion()
            default: await f.store.shutdownAssistant()
            }
            f.reader.complete()
            try await interestStoreSettle { f.reader.returned }
            await interestStoreDrain()
            XCTAssertEqual(f.store.desktopInterest.phase, .idle)
            XCTAssertNil(f.store.desktopInterest.capture)
            XCTAssertFalse(f.store.useDesktopInterestCapture())
            XCTAssertEqual(f.store.sharedText, "Existing text.")
            XCTAssertEqual(f.store.prompt, "Preserve the draft.")
            XCTAssertEqual(f.local.requests.count + f.cloud.requests.count, 0)
            if action == 2 {
                f.store.beginDesktopInterest()
                XCTAssertEqual(f.store.desktopInterest.phase, .idle)
            }
        }
    }

    @MainActor
    func testCapturedCopyUsesExistingExplicitLocalRewriteApplyAndUndo() async throws {
        let f = InterestStoreFixture(); defer { f.cleanUp() }
        f.reader.text = "Original passage. Keep this ending."
        try await f.adopt()
        let capturedSource = try XCTUnwrap(f.store.desktopInterestSource)
        let range = (f.reader.text as NSString).range(of: "Original passage.")
        f.store.selectText(range: range, sourceRevision: f.store.sourceRevision)
        f.store.preparePassageRevision()
        f.store.setAssistantRoute(.automatic)
        f.store.submit()
        try await interestStoreSettle { f.local.requests.count == 1 }
        let request = f.local.requests[0]
        XCTAssertEqual(request.sourceText, f.reader.text)
        XCTAssertEqual(request.selection?.range, range)
        let target = try XCTUnwrap(request.revisionTarget)
        let proposal = PassageRevisionProposal(target: target, decision: .propose, replacement: "Reviewed wording.",
            explanation: "Synthetic wording for review.", sourceIDs: ["selected-passage"], memoryIDs: [])
        f.local.completeRevision(0, proposal: proposal)
        try await interestStoreSettle { f.store.compareResults[.qwen]?.state == .complete }
        XCTAssertEqual(f.store.sharedText, f.reader.text, "Receiving a proposed revision never applies it")
        f.store.applyPassageRevision(provider: .qwen, targetID: target.id)
        XCTAssertEqual(f.store.sharedText, "Reviewed wording. Keep this ending.")
        XCTAssertEqual(f.store.desktopInterestSource, capturedSource, "Capture provenance still identifies the original snapshot")
        XCTAssertTrue(f.store.canUndoWorkingCopyEdit)
        f.store.undoWorkingCopyEdit()
        XCTAssertEqual(f.store.sharedText, f.reader.text)
        XCTAssertFalse(f.store.canUndoWorkingCopyEdit)
        XCTAssertEqual(f.cloud.requests.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.evolutionURL.path))
    }
}

@MainActor
private func interestStoreSettle(_ predicate: () -> Bool) async throws {
    for _ in 0..<500 {
        if predicate() { return }
        await Task.yield()
    }
    XCTFail("Synthetic window-interest store did not reach its expected state")
    throw AssistantFailure.timedOut
}

@MainActor
private func interestStoreDrain() async {
    for _ in 0..<20 { await Task.yield() }
}

@MainActor
private final class InterestStoreFixture {
    let local = InterestStoreAssistant(), cloud = InterestStoreAssistant()
    let reader = InterestStoreReader()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ARCHiInterestStore-\(UUID().uuidString)")
        .appendingPathComponent("preferences.json")
    var evolutionURL: URL { url.deletingPathExtension().appendingPathExtension("evolution.json") }
    lazy var store = CompanionStore(preferenceURL: url, assistant: local,
        assistantFactory: { [local, cloud] provider, _ in provider == .qwen ? local : cloud },
        allowsPlay: false, interestReader: reader)

    func beginTarget() {
        store.beginDesktopInterest()
        store.desktopInterest.hover(at: CGPoint(x: -100, y: 100))
        store.desktopInterest.finishAim()
        XCTAssertEqual(store.desktopInterest.phase, .targeted)
    }

    func adopt() async throws {
        beginTarget(); store.desktopInterest.read()
        try await interestStoreSettle { self.store.desktopInterest.phase == .review }
        XCTAssertTrue(store.useDesktopInterestCapture())
    }

    func cleanUp() {
        store.desktopInterest.cancel(); reader.drain()
        store.disconnectAssistant(); local.drain(); cloud.drain()
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

@MainActor
private final class InterestStoreReader: DesktopInterestReading {
    let window = DesktopInterestTarget(windowID: 707, processID: 8181, appName: "Synthetic Editor",
        title: "Synthetic document", frame: CGRect(x: -300, y: 20, width: 600, height: 400),
        observedAt: Date(timeIntervalSince1970: 1_800_000_000))
    var text = "A synthetic private passage."
    var holdsRead = false
    private(set) var reads = 0
    private(set) var returned = false
    private var pending: CheckedContinuation<DesktopInterestCapture, any Error>?
    func target(at point: CGPoint) -> DesktopInterestTarget? { window }
    func isCurrent(_ target: DesktopInterestTarget) -> Bool { target == window }
    func read(_ target: DesktopInterestTarget) async throws -> DesktopInterestCapture {
        reads += 1
        defer { returned = true }
        if holdsRead { return try await withCheckedThrowingContinuation { pending = $0 } }
        return snapshot
    }
    private var snapshot: DesktopInterestCapture {
        DesktopInterestCapture(target: window, text: text, method: "Synthetic local text",
            capturedAt: Date(timeIntervalSince1970: 1_800_000_010))
    }
    func complete() { let saved = pending; pending = nil; saved?.resume(returning: snapshot) }
    func fail() { let saved = pending; pending = nil; saved?.resume(throwing: DesktopInterestReadError.noReadableText) }
    func drain() { let saved = pending; pending = nil; saved?.resume(throwing: CancellationError()) }
}

@MainActor
private final class InterestStoreAssistant: AssistantClient {
    private(set) var connects = 0
    private(set) var requests: [AssistantRequest] = []
    private var events: [@MainActor (AssistantEvent) -> Void] = []
    private var pending: [Int: CheckedContinuation<Void, any Error>] = [:]
    func connect() async throws { connects += 1 }
    func disconnect() { }
    func fail(_ index: Int, error: any Error) { pending.removeValue(forKey: index)?.resume(throwing: error) }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        let index = requests.count
        requests.append(request); events.append(onEvent)
        try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func complete(_ index: Int, text: String) {
        events[index](.text(text)); pending.removeValue(forKey: index)?.resume()
    }
    func completeRevision(_ index: Int, proposal: PassageRevisionProposal) {
        events[index](.revision(proposal)); pending.removeValue(forKey: index)?.resume()
    }
    func drain() {
        let saved = Array(pending.values); pending.removeAll()
        for continuation in saved { continuation.resume(throwing: AssistantFailure.stopped) }
    }
    func shutdown() async { drain() }
}
