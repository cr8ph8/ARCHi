import AppKit
import Testing
@testable import ARCHiDesktop

@MainActor
struct SharedDocumentViewTests {
    private func setup(_ value: String = "A🌙 café\n" + String(repeating: "Read the exact source.\n", count: 200), store suppliedStore: CompanionStore? = nil) throws -> (CompanionStore, SharedDocumentView.Coordinator, NSScrollView, NSTextView) {
        _ = NSApplication.shared
        let store = suppliedStore ?? CompanionStore(preferenceURL: URL(fileURLWithPath: "/dev/null/unused"))
        store.share(text: value, name: "fixture.txt")
        let coordinator = SharedDocumentView.Coordinator(store: store)
        let scroll = coordinator.makeView()
        let text = try #require(scroll.documentView as? NSTextView)
        scroll.needsLayout = true
        scroll.layoutSubtreeIfNeeded()
        return (store, coordinator, scroll, text)
    }

    @Test func fullSourceAndExactUnicodeSelectionRemainNativeAndReadOnly() throws {
        let source = "A🌙 café\n" + String(repeating: "source line\n", count: 7_000)
        let (store, coordinator, scroll, text) = try setup(source)
        defer { withExtendedLifetime(scroll) { coordinator.dismantle() } }
        #expect(!text.isEditable)
        #expect(text.isSelectable)
        #expect(text.string.utf8.elementsEqual(source.utf8))
        #expect(text.identifier?.rawValue == "shared-document-text")
        text.setSelectedRange(NSRange(location: 1, length: 2))
        #expect(store.textSelection?.quote == "🌙")
        coordinator.render()
        #expect(text.selectedRange() == NSRange(location: 1, length: 2))
        let color = text.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 1, effectiveRange: nil)
        #expect(color as? NSColor != nil)
        #expect(text.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 0, effectiveRange: nil) == nil)
    }

    @Test func unchangedRenderPreservesSelectionAndCaretForKeyboardExtension() throws {
        let (store, coordinator, scroll, text) = try setup()
        defer { withExtendedLifetime(scroll) { coordinator.dismantle() } }
        text.setSelectedRange(NSRange(location: 1, length: 2))
        let selection = store.textSelection
        let ticket = store.contextTicket()
        coordinator.render()
        coordinator.render()
        #expect(store.textSelection == selection)
        #expect(store.isCurrent(ticket, requireVisible: false))
        text.setSelectedRange(NSRange(location: 5, length: 0))
        coordinator.render()
        #expect(store.textSelection == nil)
        #expect(text.selectedRange() == NSRange(location: 5, length: 0))
    }

    @Test func staleSourceDelegateCannotReplaceNewSourceSelection() throws {
        let (store, coordinator, scroll, text) = try setup("old source")
        defer { withExtendedLifetime(scroll) { coordinator.dismantle() } }
        store.share(text: "new exact source", name: "new.txt")
        store.selectText(range: NSRange(location: 4, length: 5), sourceRevision: store.sourceRevision)
        let current = store.textSelection
        text.setSelectedRange(NSRange(location: 0, length: 3))
        #expect(store.textSelection == current)
        coordinator.render()
        #expect(text.string == "new exact source")
        #expect(text.selectedRange() == NSRange(location: 4, length: 5))
    }

    @Test func actualDocumentScrollPreservesContentSelectionAndHighlight() throws {
        let (store, coordinator, scroll, text) = try setup()
        defer { coordinator.dismantle() }
        text.setSelectedRange(NSRange(location: 1, length: 2))
        coordinator.render()
        let selection = store.textSelection, ticket = store.contextTicket()
        scroll.contentView.setBoundsOrigin(CGPoint(x: 0, y: 20))
        #expect(store.textSelection == selection)
        #expect(store.isCurrent(ticket, requireVisible: false))
        #expect(text.selectedRange() == selection?.range)
        #expect(text.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 1, effectiveRange: nil) as? NSColor != nil)
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: text))
        #expect(store.textSelection == selection)
    }

    @Test func repeatedBoundsNotificationDoesNotInvalidateCurrentSelection() throws {
        let (store, coordinator, scroll, text) = try setup()
        defer { coordinator.dismantle() }
        text.setSelectedRange(NSRange(location: 1, length: 2))
        coordinator.render()
        let selection = store.textSelection
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        #expect(store.textSelection == selection)
    }

    @Test func resizePreservesContentReferenceButDismantleReleasesIt() throws {
        let (store, coordinator, scroll, text) = try setup()
        text.setSelectedRange(NSRange(location: 1, length: 2))
        coordinator.render()
        let selection = store.textSelection, ticket = store.contextTicket()
        scroll.setFrameSize(CGSize(width: 380, height: 280))
        scroll.needsLayout = true
        scroll.layoutSubtreeIfNeeded()
        #expect(store.textSelection == selection)
        #expect(store.isCurrent(ticket, requireVisible: false))
        coordinator.dismantle()
        #expect(store.textSelection == nil)
        #expect(text.delegate == nil)
        text.setSelectedRange(NSRange(location: 4, length: 3))
        #expect(store.textSelection == nil)
    }

    @Test func firstLayoutDoesNotClearAnExistingSelection() throws {
        _ = NSApplication.shared
        let store = CompanionStore(preferenceURL: URL(fileURLWithPath: "/dev/null/unused"))
        store.share(text: "Selection before mount", name: "fixture.txt")
        store.selectText(range: NSRange(location: 0, length: 9), sourceRevision: store.sourceRevision)
        let expected = store.textSelection
        let coordinator = SharedDocumentView.Coordinator(store: store)
        let scroll = coordinator.makeView()
        defer { coordinator.dismantle() }
        scroll.setFrameSize(CGSize(width: 650, height: 320))
        scroll.needsLayout = true
        scroll.layoutSubtreeIfNeeded()
        #expect(store.textSelection == expected)
    }

    @Test func focusOutKeepsWarmHighlightAndProvenanceThenFocusInRestoresNativeRange() throws {
        let (store, coordinator, scroll, text) = try setup()
        defer { withExtendedLifetime(scroll) { coordinator.dismantle() } }
        text.setSelectedRange(NSRange(location: 1, length: 2))
        coordinator.render()
        let selection = store.textSelection
        let ticket = store.contextTicket()
        // Exercise the callback directly: no window activation or user-focus side effects.
        coordinator.textFocusChanged(false)
        #expect(text.selectedRange().length == 0)
        #expect(store.textSelection == selection)
        #expect(store.isCurrent(ticket, requireVisible: false))
        #expect(text.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 1, effectiveRange: nil) as? NSColor != nil)
        #expect(text.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 1, effectiveRange: nil) as? NSColor == NSColor.black)
        coordinator.render()
        coordinator.render()
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: text))
        #expect(text.selectedRange().length == 0)
        #expect(store.textSelection == selection)
        #expect(store.isCurrent(ticket, requireVisible: false))
        coordinator.textFocusChanged(true)
        #expect(text.selectedRange() == NSRange(location: 1, length: 2))
        #expect(store.textSelection == selection)
        #expect(store.isCurrent(ticket, requireVisible: false))
    }

    @Test func focusReturnRestoresAfterScrollButCannotRestoreAnExplicitlyClearedReference() throws {
        let (store, coordinator, scroll, text) = try setup()
        defer { coordinator.dismantle() }
        text.setSelectedRange(NSRange(location: 1, length: 2))
        coordinator.render()
        coordinator.textFocusChanged(false)
        scroll.contentView.setBoundsOrigin(CGPoint(x: 0, y: 20))
        coordinator.textFocusChanged(true)
        #expect(text.selectedRange() == NSRange(location: 1, length: 2))
        coordinator.textFocusChanged(false)
        store.clearTextSelection()
        #expect(store.textSelection == nil)
        coordinator.textFocusChanged(true)
        #expect(text.selectedRange().length == 0)
        #expect(text.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 1, effectiveRange: nil) == nil)
    }

    @Test func inFlightRevisionSurvivesLayoutAndCompanionMovementWithExactSourceApply() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let client = DocumentLayoutClient()
        let source = "A🌙 café makes this paragraph much longer than necessary.\nSecond paragraph."
        let store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"),
            assistant: client, tokenSteward: TokenStewardStore())
        let (_, coordinator, scroll, text) = try setup(source, store: store)
        defer {
            coordinator.dismantle(); store.disconnectAssistant(provider: .qwen); client.resolve()
            try? FileManager.default.removeItem(at: directory)
        }
        let range = (source as NSString).range(of: "A🌙 café makes this paragraph much longer than necessary.")
        text.setSelectedRange(range)
        coordinator.render()
        coordinator.textFocusChanged(false)
        store.preparePassageRevision(shorten: true)
        store.setAssistantRoute(.local)
        store.connectAssistant()
        try await wait { store.connectionState == .ready }
        store.submit()
        try await wait { client.request != nil }
        let ticket = store.contextTicket(), selection = store.textSelection
        #expect(store.documentWork.records.count == 1, "The pending history row triggers the real layout change")
        scroll.setFrameSize(CGSize(width: 380, height: 240))
        scroll.contentView.setBoundsOrigin(CGPoint(x: 0, y: 20))
        scroll.needsLayout = true
        scroll.layoutSubtreeIfNeeded()
        coordinator.render()
        #expect(store.isWorking)
        #expect(store.textSelection == selection)
        #expect(store.isCurrent(ticket, requireVisible: false))
        #expect(store.sharedText == source)
        store.placed(at: CGPoint(x: 430, y: 220))
        #expect(store.isWorking)
        #expect(store.textSelection == selection)
        #expect(!store.isCurrent(ticket, requireVisible: false), "Old spatial coordinates expire")
        #expect(store.isCurrentContent(ticket), "The selected bytes still belong to the active request")
        let target = try #require(client.request?.revisionTarget)
        let proposal = PassageRevisionProposal(target: target, decision: .propose, replacement: "A café.",
            explanation: "Shorter wording for review.", sourceIDs: ["selected-passage"], memoryIDs: [])
        client.handler?(.revision(proposal)); client.resolve()
        try await wait { !store.isWorking }
        #expect(store.canApplyDocumentRevision(provider: .qwen, proposal: proposal))
        store.placed(at: CGPoint(x: 470, y: 230))
        #expect(store.canApplyDocumentRevision(provider: .qwen, proposal: proposal), "Movement after completion cannot revoke a content-only proposal")
        // Even a byte change that bypasses a source-revision notification must
        // fail the existing exact-source verification before Apply.
        store.sharedText = source + "Changed."
        #expect(!store.canApplyDocumentRevision(provider: .qwen, proposal: proposal))
        store.sharedText = source
        #expect(store.canApplyDocumentRevision(provider: .qwen, proposal: proposal))
        store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
        #expect(store.sharedText == "A café.\nSecond paragraph.")
        #expect(store.documentWork.records.first?.state == .applied)
    }

    @Test(arguments: [false, true])
    func geometryChangeRetiresPointingResultWithoutDroppingTheSourceRange(companionMoves: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let client = DocumentLayoutClient()
        let store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"),
            assistant: client, tokenSteward: TokenStewardStore())
        store.section = .context
        store.preferences.equipment = CompanionEquipment(hand: .focusStaff)
        let (_, coordinator, scroll, text) = try setup("A🌙 café passage.", store: store)
        defer {
            coordinator.dismantle(); store.disconnectAssistant(provider: .qwen); client.resolve()
            try? FileManager.default.removeItem(at: directory)
        }
        text.setSelectedRange(NSRange(location: 1, length: 2))
        coordinator.render()
        let selection = try #require(store.textSelection)
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let geometry = SelectedPassageGeometry(selection: selection,
            rects: [CGRect(x: 100, y: 100, width: 20, height: 20)], viewport: frame,
            windowFrame: frame, windowNumber: 1, screenID: 1, screenFrame: frame)
        let environment = SpatialEnvironment(companionFrame: CGRect(x: 500, y: 100, width: 100, height: 100),
            displays: [.init(id: 1, frame: frame, visibleFrame: frame)])
        store.onObserveSelectedPassage = { geometry }
        store.onObserveSpatialEnvironment = { environment }
        store.setAssistantRoute(.local)
        store.connectAssistant()
        try await wait { store.connectionState == .ready }
        #expect(store.pointAndExplainSelection())
        try await wait { client.request != nil }
        let ticket = store.contextTicket()
        #expect(store.compareResults[.qwen]?.receipt?.pointing != nil)
        #expect(store.spatialPreview != nil)
        #expect(store.focusGesturePlayback != nil)
        if companionMoves {
            store.placed(at: CGPoint(x: 600, y: 140))
        } else {
            scroll.setFrameSize(CGSize(width: 380, height: 240))
            scroll.needsLayout = true
            scroll.layoutSubtreeIfNeeded()
        }
        #expect(store.spatialPreview == nil)
        #expect(store.focusGesturePlayback == nil)
        #expect(store.compareResults[.qwen]?.state == .cancelled)
        #expect(store.compareResults[.qwen]?.text.isEmpty == true)
        #expect(!store.isCurrent(ticket, requireVisible: false))
        #expect(store.textSelection == selection)
        client.handler?(.text("A late answer using old pointing coordinates.")); client.resolve()
        await Task.yield()
        #expect(store.compareResults[.qwen]?.state == .cancelled)
        #expect(store.compareResults[.qwen]?.text.isEmpty == true)
    }

    private func wait(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        throw AssistantFailure.timedOut
    }
}

@MainActor
private final class DocumentLayoutClient: AssistantClient {
    var request: AssistantRequest?
    var handler: (@MainActor (AssistantEvent) -> Void)?
    private var continuation: CheckedContinuation<Void, Error>?
    func connect() async throws {}
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        self.request = request; handler = onEvent
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func resolve() { let pending = continuation; continuation = nil; pending?.resume() }
}
