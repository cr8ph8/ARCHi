import AppKit
import SwiftUI

/// Exact, selectable source text. AppKit owns native selection and layout; the
/// store owns whether that selection still belongs to the current shared copy.
@MainActor
struct SharedDocumentView: NSViewRepresentable {
    @ObservedObject var store: CompanionStore

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }
    func makeNSView(context: Context) -> NSScrollView { context.coordinator.makeView() }
    func updateNSView(_ nsView: NSScrollView, context: Context) { context.coordinator.render() }
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) { coordinator.dismantle() }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let store: CompanionStore
        private let observerID = UUID()
        private weak var scrollView: DocumentScrollView?
        private weak var textView: SharedDocumentTextView?
        private weak var observedWindow: NSWindow?
        private var observedClips: [WeakClip] = []
        private var clipOrigins: [ObjectIdentifier: CGPoint] = [:]
        private var sourceRevision: UInt64?
        private var renderedText = ""
        private var highlightedRange: NSRange?
        private var lastScreenFrame: CGRect?
        private var lastViewportSize: CGSize?
        private var lastWindowFrame: CGRect?
        private var completedInitialLayout = false
        private var nativeSelectionSuspended = false
        private var applying = false
        private var detached = false
        private static let highlight = NSColor(calibratedRed: 1, green: 0.83, blue: 0.38, alpha: 1)

        init(store: CompanionStore) { self.store = store }

        func makeView() -> NSScrollView {
            let scroll = DocumentScrollView(frame: CGRect(x: 0, y: 0, width: 480, height: 320))
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = false
            scroll.autohidesScrollers = true
            scroll.borderType = .noBorder
            scroll.drawsBackground = true
            scroll.backgroundColor = .textBackgroundColor
            let text = SharedDocumentTextView(frame: scroll.contentView.bounds)
            text.isEditable = false
            text.isSelectable = true
            text.isRichText = false
            text.importsGraphics = false
            text.isVerticallyResizable = true
            text.isHorizontallyResizable = false
            text.autoresizingMask = [.width]
            text.minSize = CGSize(width: 0, height: scroll.contentSize.height)
            text.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            text.textContainer?.widthTracksTextView = true
            text.textContainer?.containerSize = CGSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            text.textContainerInset = CGSize(width: 14, height: 14)
            text.font = .systemFont(ofSize: 14)
            text.textColor = .textColor
            text.backgroundColor = .textBackgroundColor
            text.drawsBackground = true
            text.usesFindPanel = true
            text.isAutomaticLinkDetectionEnabled = false
            text.isAutomaticDataDetectionEnabled = false
            text.isAutomaticTextReplacementEnabled = false
            text.isAutomaticQuoteSubstitutionEnabled = false
            text.isAutomaticDashSubstitutionEnabled = false
            text.isContinuousSpellCheckingEnabled = false
            text.isGrammarCheckingEnabled = false
            text.selectedTextAttributes = [.backgroundColor: Self.highlight, .foregroundColor: NSColor.black]
            text.setAccessibilityLabel("Shared document text")
            text.setAccessibilityHelp("Read-only shared copy. Select a passage with the mouse or keyboard to ask about it. Scrolling or moving the window clears its location reference.")
            text.identifier = NSUserInterfaceItemIdentifier("shared-document-text")
            text.delegate = self
            text.focusChanged = { [weak self] active in self?.textFocusChanged(active) }
            scroll.documentView = text
            scroll.geometryChanged = { [weak self] layoutPass in self?.inspectGeometry(layoutPass: layoutPass) }
            scroll.willDetach = { [weak self] in self?.invalidate(reason: "Document view moved out of its window.") }
            scrollView = scroll
            textView = text
            store.selectedPassageObserverID = observerID
            store.onObserveSelectedPassage = { [weak self] in self?.observeSelectedPassage() }
            refreshObservers()
            render()
            return scroll
        }

        func render() {
            guard !detached, let scroll = scrollView, let text = textView else { return }
            applying = true
            let changedSource = sourceRevision != store.sourceRevision || !renderedText.utf8.elementsEqual(store.sharedText.utf8)
            if changedSource {
                removeHighlight()
                sourceRevision = store.sourceRevision
                renderedText = store.sharedText
                text.string = renderedText
                text.font = .systemFont(ofSize: 14)
                text.textColor = .textColor
                text.setSelectedRange(NSRange(location: 0, length: 0))
                text.minSize = CGSize(width: 0, height: scroll.contentSize.height)
                text.sizeToFit()
            }
            let selected = store.textSelection.flatMap {
                $0.matches(text: renderedText, sourceRevision: store.sourceRevision) ? $0.range : nil
            }
            if let selected, !nativeSelectionSuspended {
                if text.selectedRange() != selected { text.setSelectedRange(selected) }
            } else if text.selectedRange().length != 0 {
                // Preserve a user's insertion position so Shift+Arrow works after
                // a click; an empty range need not force the caret to character 0.
                text.setSelectedRange(NSRange(location: min(text.selectedRange().location, renderedText.utf16.count), length: 0))
            }
            if highlightedRange != selected {
                removeHighlight()
                if let selected {
                    text.layoutManager?.addTemporaryAttributes([.backgroundColor: Self.highlight, .foregroundColor: NSColor.black], forCharacterRange: selected)
                    highlightedRange = selected
                }
                text.needsDisplay = true
            }
            applying = false
            if changedSource { resetGeometryBaseline() }
            inspectGeometry()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !applying, !detached, !nativeSelectionSuspended, let text = textView,
                  store.selectedPassageObserverID == observerID,
                  notification.object as? NSTextView === text,
                  let sourceRevision, sourceRevision == store.sourceRevision else { return }
            store.selectText(range: text.selectedRange(), sourceRevision: sourceRevision)
        }

        /// The source range stays in the store when focus moves to the question.
        /// Clearing only AppKit's native range prevents its inactive gray selection
        /// from obscuring our temporary warm highlight. Render keeps it cleared
        /// through streamed reply updates and restores it on keyboard focus return.
        func textFocusChanged(_ active: Bool) {
            guard !detached, store.selectedPassageObserverID == observerID else { return }
            nativeSelectionSuspended = !active
            render()
        }

        /// Synchronously reads native layout. The public store callback always
        /// requires the key window; tests may relax only that focus requirement.
        /// This observes no pixels and never scrolls to make a target eligible.
        func observeSelectedPassage(requireKeyWindow: Bool = true) -> SelectedPassageGeometry? {
            guard !applying, !detached, store.selectedPassageObserverID == observerID,
                  let scroll = scrollView, let text = textView,
                  let window = text.window, window === scroll.window,
                  window.isVisible, !window.isMiniaturized, !NSApp.isHidden,
                  !requireKeyWindow || window.isKeyWindow,
                  window.windowNumber > 0,
                  let revision = sourceRevision, revision == store.sourceRevision,
                  let selection = store.textSelection,
                  selection.matches(text: renderedText, sourceRevision: revision),
                  renderedText.utf8.elementsEqual(store.sharedText.utf8),
                  renderedText.utf8.elementsEqual(text.string.utf8),
                  let manager = text.layoutManager, let container = text.textContainer else { return nil }
            var ancestor: NSView? = text
            while let view = ancestor {
                guard !view.isHidden, view.alphaValue > 0 else { return nil }
                ancestor = view.superview
            }
            let ticket = store.contextTicket()
            scroll.layoutSubtreeIfNeeded()
            text.layoutSubtreeIfNeeded()
            manager.ensureLayout(for: container)
            inspectGeometry()
            // Layout may retire geometry-bound work. The source range itself
            // remains current unless its bytes, revision or selection changed.
            guard store.isCurrent(ticket, requireVisible: false), store.textSelection == selection,
                  sourceRevision == revision, window === text.window,
                  window.isVisible, !window.isMiniaturized,
                  !requireKeyWindow || window.isKeyWindow else { return nil }

            let clipInText = text.convert(scroll.contentView.bounds, from: scroll.contentView)
            let localViewport = text.visibleRect.intersection(clipInText)
            guard Self.valid(localViewport) else { return nil }
            let rawViewport = window.convertToScreen(text.convert(localViewport, to: nil))
            guard Self.valid(rawViewport) else { return nil }
            let glyphs = manager.glyphRange(forCharacterRange: selection.range, actualCharacterRange: nil)
            guard glyphs.location != NSNotFound, glyphs.length > 0 else { return nil }
            let origin = text.textContainerOrigin
            var rectangles: [CGRect] = []
            var clipped = false
            manager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: glyphs, in: container) { rect, stop in
                let inText = rect.offsetBy(dx: origin.x, dy: origin.y)
                let onScreen = window.convertToScreen(text.convert(inText, to: nil))
                guard Self.valid(onScreen), rawViewport.contains(onScreen) else {
                    clipped = true
                    stop.pointee = true
                    return
                }
                rectangles.append(onScreen)
            }
            guard !clipped, !rectangles.isEmpty else { return nil }
            // A single placement preview belongs to one physical display. A
            // passage split across displays needs a new, wholly visible selection.
            var screens = NSScreen.screens
            if let preferred = window.screen {
                screens.removeAll { $0 === preferred }
                screens.insert(preferred, at: 0)
            }
            guard let screen = screens.first(where: { display in rectangles.allSatisfy { display.visibleFrame.contains($0) } }),
                  let identifier = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  identifier.uint32Value != 0 else { return nil }
            let viewport = rawViewport.intersection(screen.visibleFrame)
            guard Self.valid(viewport), rectangles.allSatisfy({ viewport.contains($0) && window.frame.contains($0) }),
                  store.isCurrent(ticket, requireVisible: false), store.textSelection == selection else { return nil }
            return SelectedPassageGeometry(selection: selection, rects: rectangles, viewport: viewport,
                windowFrame: window.frame, windowNumber: window.windowNumber,
                screenID: identifier.uint32Value, screenFrame: screen.frame)
        }

        private static func valid(_ rect: CGRect) -> Bool {
            !rect.isInfinite && !rect.isNull && rect.minX.isFinite && rect.minY.isFinite && rect.maxX.isFinite && rect.maxY.isFinite
                && rect.width > 0 && rect.height > 0
        }

        func dismantle() {
            guard !detached else { return }
            if store.selectedPassageObserverID == observerID {
                invalidate(reason: "Document view closed. Select the passage again when you return.")
                store.onObserveSelectedPassage = nil
                store.selectedPassageObserverID = nil
            } else {
                removeHighlight()
            }
            detached = true
            textView?.delegate = nil
            textView?.focusChanged = nil
            scrollView?.geometryChanged = nil
            scrollView?.willDetach = nil
            NotificationCenter.default.removeObserver(self)
            observedClips = []
            clipOrigins = [:]
            observedWindow = nil
        }

        private func removeHighlight() {
            if let range = highlightedRange, let manager = textView?.layoutManager {
                manager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
                manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
            }
            highlightedRange = nil
        }

        private func invalidate(reason: String) {
            guard !applying, !detached, store.selectedPassageObserverID == observerID,
                  sourceRevision == store.sourceRevision else { return }
            applying = true
            removeHighlight()
            if let text = textView, text.selectedRange().length > 0 {
                text.setSelectedRange(NSRange(location: min(text.selectedRange().location, text.string.utf16.count), length: 0))
            }
            textView?.needsDisplay = true
            store.invalidateTextSelection(reason: reason)
            applying = false
        }

        private func invalidateGeometry(reason: String) {
            guard !applying, !detached, store.selectedPassageObserverID == observerID,
                  sourceRevision == store.sourceRevision else { return }
            applying = true
            store.invalidateDocumentGeometry(reason: reason)
            applying = false
        }

        private func resetGeometryBaseline() {
            lastViewportSize = scrollView?.contentView.bounds.size
            lastScreenFrame = screenFrame()
            for reference in observedClips {
                if let clip = reference.value { clipOrigins[ObjectIdentifier(clip)] = clip.bounds.origin }
            }
        }

        private func screenFrame() -> CGRect? {
            guard let scroll = scrollView, let window = scroll.window, scroll.bounds.width > 0, scroll.bounds.height > 0 else { return nil }
            return window.convertToScreen(scroll.convert(scroll.bounds, to: nil))
        }

        private func inspectGeometry(layoutPass: Bool = false) {
            guard !applying, !detached, let scroll = scrollView else { return }
            refreshObservers()
            let size = scroll.contentView.bounds.size
            let currentFrame = screenFrame()
            if !completedInitialLayout {
                lastViewportSize = size
                lastScreenFrame = currentFrame
                completedInitialLayout = layoutPass && size.width > 0 && size.height > 0
                return
            }
            let resized = lastViewportSize.map { $0 != size } ?? false
            let moved = lastScreenFrame.flatMap { previous in currentFrame.map { $0 != previous } } ?? false
            lastViewportSize = size
            lastScreenFrame = currentFrame
            if resized || moved { invalidateGeometry(reason: "Document layout moved. Preview pointing again.") }
        }

        private func refreshObservers() {
            guard let scroll = scrollView else { return }
            var clips = [scroll.contentView]
            var ancestor = scroll.superview
            while let view = ancestor {
                if let clip = view as? NSClipView, !clips.contains(where: { $0 === clip }) { clips.append(clip) }
                ancestor = view.superview
            }
            if observedClips.compactMap({ $0.value }).map(ObjectIdentifier.init) != clips.map(ObjectIdentifier.init) {
                NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
                observedClips = clips.map(WeakClip.init)
                clipOrigins = [:]
                for clip in clips {
                    clip.postsBoundsChangedNotifications = true
                    clipOrigins[ObjectIdentifier(clip)] = clip.bounds.origin
                    NotificationCenter.default.addObserver(self, selector: #selector(clipBoundsChanged), name: NSView.boundsDidChangeNotification, object: clip)
                }
            }
            if observedWindow !== scroll.window {
                NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: nil)
                NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: nil)
                observedWindow = scroll.window
                lastWindowFrame = scroll.window?.frame
                if let window = scroll.window {
                    NotificationCenter.default.addObserver(self, selector: #selector(windowGeometryChanged), name: NSWindow.didMoveNotification, object: window)
                    NotificationCenter.default.addObserver(self, selector: #selector(windowGeometryChanged), name: NSWindow.didResizeNotification, object: window)
                }
            }
        }

        @objc private func clipBoundsChanged(_ notification: Notification) {
            guard let clip = notification.object as? NSClipView else { return }
            let id = ObjectIdentifier(clip)
            let previous = clipOrigins[id]
            clipOrigins[id] = clip.bounds.origin
            if completedInitialLayout, let previous, previous != clip.bounds.origin { invalidateGeometry(reason: "Document scrolled. Preview pointing again.") }
            inspectGeometry()
        }

        @objc private func windowGeometryChanged(_ notification: Notification) {
            guard let window = observedWindow, notification.object as? NSWindow === window else { return }
            let changed = lastWindowFrame.map { $0 != window.frame } ?? false
            lastWindowFrame = window.frame
            if completedInitialLayout && changed { invalidateGeometry(reason: "Window moved or resized. Preview pointing again.") }
            inspectGeometry()
        }
    }
}

@MainActor
private final class SharedDocumentTextView: NSTextView {
    var focusChanged: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { focusChanged?(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { focusChanged?(false) }
        return accepted
    }
}

@MainActor
private final class WeakClip {
    weak var value: NSClipView?
    init(_ value: NSClipView) { self.value = value }
}

@MainActor
private final class DocumentScrollView: NSScrollView {
    var geometryChanged: ((Bool) -> Void)?
    var willDetach: (() -> Void)?
    override func layout() { super.layout(); geometryChanged?(true) }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); geometryChanged?(false) }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); geometryChanged?(false) }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let window, window !== newWindow { willDetach?() }
        super.viewWillMove(toWindow: newWindow)
    }
}
