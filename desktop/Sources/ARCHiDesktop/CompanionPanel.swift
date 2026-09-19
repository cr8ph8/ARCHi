import AppKit
import Combine
import SwiftUI

/// Screen-space geometry stays independent of rendering and is also used after a
/// display is unplugged. AppKit points may have negative origins on other displays.
enum CompanionPlacement {
    static func clamped(_ frame: CGRect, to screens: [CGRect], pointer: CGPoint? = nil) -> CGRect {
        let usable = screens.filter { !$0.isEmpty && !$0.isInfinite && !$0.isNull }
        guard !usable.isEmpty else { return frame }
        let point = pointer ?? CGPoint(x: frame.midX, y: frame.midY)
        let screen = usable.first(where: { $0.contains(point) }) ?? usable.min {
            squaredDistance(point, to: $0) < squaredDistance(point, to: $1)
        }!
        let margin = min(8, min(screen.width, screen.height) / 10)
        let area = screen.insetBy(dx: margin, dy: margin)
        let width = min(frame.width, area.width)
        let height = min(frame.height, area.height)
        return CGRect(
            x: min(max(frame.minX, area.minX), area.maxX - width),
            y: min(max(frame.minY, area.minY), area.maxY - height),
            width: width, height: height
        )
    }

    private static func squaredDistance(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}

/// Each delivered event retains its pointer position. Reading mouseLocation
/// instead would sample the current cursor, possibly after queued down/drag/up
/// events have already occurred. Quartz's unflipped location uses AppKit's
/// global coordinates and is independent of the window's later movement.
@MainActor
enum CompanionPointerLocation {
    static func screenPoint(for event: NSEvent) -> CGPoint? {
        if let quartz = event.cgEvent {
            let point = quartz.unflippedLocation
            if point.x.isFinite && point.y.isFinite { return point }
        }
        let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        return point.x.isFinite && point.y.isFinite ? point : nil
    }
}

/// Tracks pointer displacement from the original native frame, never an inferred
/// rendering position. A release can establish a drag even if intermediate
/// movement events were coalesced. Once dragged, returning to the origin is not
/// a click and must not open chat.
struct CompanionPointerGesture {
    enum Release: Equatable { case click, moved(CGRect), cancelled }
    private var origin: CGPoint?
    private var frame: CGRect?
    private var dragged = false

    mutating func begin(at point: CGPoint?, frame: CGRect?) {
        cancel()
        guard let point, let frame, point.x.isFinite, point.y.isFinite,
              [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite),
              !frame.isEmpty, !frame.isNull else { return }
        origin = point; self.frame = frame
    }

    mutating func move(to point: CGPoint?) -> CGRect? {
        guard let point, point.x.isFinite, point.y.isFinite, let origin, let frame else { return nil }
        let dx = point.x - origin.x, dy = point.y - origin.y
        guard dx.isFinite, dy.isFinite, dragged || hypot(dx, dy) >= 3 else { return nil }
        dragged = true
        return frame.offsetBy(dx: dx, dy: dy)
    }

    mutating func release(at point: CGPoint?) -> Release {
        defer { cancel() }
        guard origin != nil, let point, point.x.isFinite, point.y.isFinite else { return .cancelled }
        if let moved = move(to: point) { return .moved(moved) }
        return dragged ? .cancelled : .click
    }

    mutating func cancel() { origin = nil; frame = nil; dragged = false }
}

private final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The small AppKit boundary owns only the floating window, input routing, and
/// screen coordinates. It never derives placement from a generated image.
@MainActor
final class CompanionPanelController: NSObject, NSWindowDelegate {
    let window: NSPanel
    private let store: CompanionStore
    private var subscriptions = Set<AnyCancellable>()
    private var interaction: CompanionInteractionView!
    private var scale: CGFloat = 1
    private var previewWindow: NSPanel?
    private var presentedInHabitat = false
    private var chatBubble: CompanionChatBubbleController?
    private let interestOutline = DesktopInterestOutline()
    private var interestTracking: Task<Void, Never>?
    var chatWindow: NSPanel? { chatBubble?.window }

    init(store: CompanionStore) {
        self.store = store
        window = CompanionPanel(
            contentRect: CGRect(x: 0, y: 0, width: 128, height: 154),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        super.init()
        window.title = "ARCHi desktop companion"
        window.identifier = NSUserInterfaceItemIdentifier("archi.companion")
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self

        interaction = CompanionInteractionView(store: store)
        interaction.move = { [weak self] proposed, pointer in self?.move(to: proposed, pointer: pointer) }
        interaction.openChat = { [weak self] in self?.showChatBubble() }
        interaction.finishPoint = { [weak self] in
            guard let self, self.store.desktopInterest.phase == .aiming else { return }
            self.refreshInterestTarget()
            self.store.desktopInterest.finishAim()
            self.showChatBubble()
        }
        window.contentView = interaction
        applyPreferences(store.preferences)
        centerOnMainScreen()
        store.onObserveSpatialEnvironment = { [weak self] in self?.observeEnvironment() }
        store.onMoveCompanion = { [weak self] frame in self?.move(to: frame) }
        store.onPresentPlacementPreview = { [weak self] preview in self?.presentPreview(preview) }
        store.$preferences.dropFirst().sink { [weak self] value in
            self?.applyPreferences(value)
        }.store(in: &subscriptions)
        store.$keptQiMon.combineLatest(store.$qiMonJourneyOrigin)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                guard let self else { return }
                self.interaction.setAccessibilityValue(self.store.cursorAccessibilityValue)
            }.store(in: &subscriptions)
        store.evolution.$revision.sink { [weak self] _ in
            guard let self else { return }
            self.interaction.setAccessibilityValue(self.store.cursorAccessibilityValue)
        }.store(in: &subscriptions)
        store.$compareResults.combineLatest(store.$isWorking)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.interaction.setAccessibilityValue(self.store.cursorAccessibilityValue)
            }.store(in: &subscriptions)
        store.$focusGesturePlayback.sink { [weak self] playback in
            guard let self else { return }
            self.interaction.setAccessibilityValue(
                self.store.cursorAccessibilityValue(for: self.store.preferences, gesture: playback))
        }.store(in: &subscriptions)
        store.$kinLightPreview.combineLatest(store.$spatialPreview, store.$isVisible)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                guard let self else { return }
                self.interaction.setAccessibilityValue(self.store.cursorAccessibilityValue)
            }.store(in: &subscriptions)
        store.$isVisible.combineLatest(store.$isShuttingDown).sink { [weak self] visible, shuttingDown in
            if !visible || shuttingDown {
                self?.interaction.cancelPointerGesture()
                self?.dismissChatBubble()
                self?.store.desktopInterest.cancel()
            }
        }.store(in: &subscriptions)
        store.desktopInterest.$phase.receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            // Read the owned session after delivery. An earlier queued phase
            // must not restart tracking after Stop or a newer acquisition.
            let phase = self.store.desktopInterest.phase
            self.refreshInterestPresentation()
            self.interestTracking?.cancel(); self.interestTracking = nil
            guard phase == .aiming || phase == .targeted || phase == .reading else {
                self.interestOutline.hide(); return
            }
            self.interestTracking = Task { [weak self] in
                while !Task.isCancelled {
                    guard self != nil else { return }
                    self?.refreshInterestTarget()
                    try? await Task.sleep(for: .milliseconds(180))
                }
            }
        }.store(in: &subscriptions)
        store.desktopInterest.$target.combineLatest(store.desktopInterest.$message)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                self?.refreshInterestPresentation()
            }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                self?.refreshInterestPresentation()
            }.store(in: &subscriptions)
        store.$section.removeDuplicates().dropFirst().sink { [weak self] _ in
            self?.dismissChatBubble()
        }.store(in: &subscriptions)
        NotificationCenter.default.addObserver(
            self, selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    deinit {
        interestTracking?.cancel()
        let outline = interestOutline
        Task { @MainActor in outline.hide() }
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func show() {
        recoverPlacement()
        store.isVisible = true
        // A passive appearance must not activate ARCHi or steal the user's typing.
        if !presentedInHabitat { window.orderFrontRegardless() }
    }

    /// Handoff only changes which surface draws ARCHi, retaining desktop position
    /// and the user's show/hide preference for when they return.
    func setPresentedInHabitat(_ active: Bool) {
        guard active != presentedInHabitat else { return }
        presentedInHabitat = active
        if active {
            interaction.cancelPointerGesture(); dismissChatBubble()
            store.desktopInterest.cancel(reason: "ARCHi moved to Habitat. Point again on the desktop.")
            interestOutline.hide(); window.orderOut(nil)
        }
        else if store.isVisible { window.orderFrontRegardless() }
    }

    func hide() {
        interaction.cancelPointerGesture()
        dismissChatBubble()
        store.invalidatePlacementPreview(reason: "Companion hidden. Preview again when shown.")
        store.isVisible = false
        window.orderOut(nil)
    }

    func showChatBubble() {
        guard store.isVisible, !store.isShuttingDown, !presentedInHabitat, window.isVisible else { return }
        if store.desktopInterest.phase == .aiming {
            refreshInterestTarget()
            store.desktopInterest.finishAim()
        }
        if chatBubble == nil { chatBubble = CompanionChatBubbleController(store: store, companionWindow: window) }
        if chatBubble?.show() != true { store.open(.assistant) }
    }

    func dismissChatBubble() { chatBubble?.dismiss() }

    func centerOnMainScreen() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        move(to: CGRect(
            x: area.midX - window.frame.width / 2,
            y: area.midY - window.frame.height / 2,
            width: window.frame.width, height: window.frame.height
        ))
    }

    func windowDidMove(_ notification: Notification) { publishPlacement() }

    private func applyPreferences(_ preferences: CompanionPreferences) {
        let nextScale = CGFloat(preferences.size.isFinite ? min(1.6, max(0.65, preferences.size)) : 1)
        if scale != nextScale || window.frame.size != CGSize(width: 128 * nextScale, height: 154 * nextScale) {
            scale = nextScale
            let current = window.frame
            move(to: CGRect(
                x: current.midX - 64 * scale, y: current.midY - 77 * scale,
                width: 128 * scale, height: 154 * scale
            ), forceInvalidation: true)
        }
        // Published preferences arrive before the stored property is replaced.
        // Use that incoming value so the spoken body never trails the drawing.
        interaction.setAccessibilityValue(store.cursorAccessibilityValue(for: preferences))
        refreshInterestPresentation(preferences: preferences)
    }

    private func move(to proposed: CGRect, pointer: CGPoint? = nil, forceInvalidation: Bool = false) {
        let frame = CompanionPlacement.clamped(proposed, to: NSScreen.screens.map(\.visibleFrame), pointer: pointer)
        window.setFrame(frame, display: true, animate: false)
        // Publish the frame AppKit actually accepted, synchronously with user input.
        publishPlacement(force: forceInvalidation)
    }

    private func publishPlacement(force: Bool = false) {
        let actual = CGPoint(x: window.frame.midX, y: window.frame.midY)
        if force || actual != store.position { store.placed(at: actual) }
        chatBubble?.followCompanion()
    }

    private func recoverPlacement() { move(to: window.frame) }
    private func refreshInterestTarget() {
        let session = store.desktopInterest
        guard window.isVisible, window.isOnActiveSpace, store.isVisible, !store.isShuttingDown else {
            session.cancel(); interestOutline.hide(); return
        }
        if session.phase == .aiming {
            session.hover(at: CGPoint(x: window.frame.midX, y: window.frame.midY + window.frame.height * 0.12))
        } else { session.refreshBoundary() }
        refreshInterestPresentation()
    }

    private func refreshInterestPresentation(preferences incoming: CompanionPreferences? = nil) {
        let preferences = incoming ?? store.preferences
        interaction.setAccessibilityValue(store.cursorAccessibilityValue(for: preferences))
        guard !presentedInHabitat, window.isVisible, window.isOnActiveSpace,
              store.isVisible, !store.isShuttingDown else { interestOutline.hide(); return }
        interestOutline.show(cue: store.desktopInterest.cue, quiet: preferences.quiet,
            reduceMotion: preferences.reduceMotion,
            systemReduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
    @objc private func displaysChanged(_ notification: Notification) {
        interaction.cancelPointerGesture()
        store.desktopInterest.cancel(reason: "Display layout changed. Point at the window again.")
        store.invalidatePlacementPreview(reason: "Display layout changed. Preview again.")
        recoverPlacement()
    }

    @objc private func activeSpaceChanged(_ notification: Notification) {
        interaction.cancelPointerGesture()
        store.desktopInterest.cancel(reason: "Desktop space changed. Point again.")
        dismissChatBubble()
        store.invalidateTextSelection(reason: "Desktop space changed. Select the passage again.")
    }

    private func observeEnvironment() -> SpatialEnvironment? {
        guard window.isVisible, window.isOnActiveSpace else { return nil }
        let displays = NSScreen.screens.compactMap { screen -> SpatialDisplay? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return SpatialDisplay(id: number.uint32Value, frame: screen.frame, visibleFrame: screen.visibleFrame)
        }.sorted { $0.id < $1.id }
        guard !displays.isEmpty else { return nil }
        return SpatialEnvironment(companionFrame: window.frame, displays: displays)
    }

    private func presentPreview(_ preview: SpatialPreview?) {
        guard let preview else { previewWindow?.orderOut(nil); return }
        if previewWindow == nil {
            let panel = PlacementGhostPanel(contentRect: preview.candidate.frame,
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "ARCHi placement preview"
            panel.identifier = NSUserInterfaceItemIdentifier("archi.placementPreview")
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            panel.ignoresMouseEvents = true
            panel.level = .floating
            panel.hidesOnDeactivate = true
            panel.collectionBehavior = [.fullScreenAuxiliary]
            previewWindow = panel
        }
        previewWindow?.contentView = NSHostingView(rootView: PlacementGhostBody(
            form: store.cursorPresentationForm, family: store.presentationFamily, treatment: store.preferences.visualTreatment,
            staysPut: preview.candidate.staysPut, recipe: store.presentationRecipe,
            naturalVariation: store.presentationNaturalVariation, equipment: store.preferences.equipment, seedColor: store.preferences.seedColor))
        previewWindow?.setFrame(preview.candidate.frame, display: true, animate: false)
        previewWindow?.orderFrontRegardless()
    }
}

private final class PlacementGhostPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct PlacementGhostBody: View {
    let form: CompanionForm
    let family: EvolutionFamily?
    let treatment: CompanionVisualTreatment
    let staysPut: Bool
    let recipe: CompanionAppearanceRecipe?
    let naturalVariation: CompanionNaturalVariation?
    let equipment: CompanionEquipment
    let seedColor: CompanionSeedColor
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                CompanionPresenceArt(form: form, family: family, size: geometry.size.width * 0.80, reduceMotion: true,
                    treatment: treatment, recipe: recipe, naturalVariation: naturalVariation, equipment: equipment, seedColor: seedColor)
                    .opacity(staysPut ? 0 : 0.34).frame(maxHeight: .infinity)
                Text(staysPut ? "STAY HERE" : "PREVIEW")
                    .font(.system(size: 9, weight: .semibold)).tracking(1)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule()).padding(.bottom, 5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(
                Color.purple.opacity(0.75), style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(staysPut ? "Preview: keep ARCHi here" : "Preview of ARCHi’s proposed position")
    }
}

struct FloatingCompanionBody: View {
    @ObservedObject var store: CompanionStore
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height * 128 / 154)
            VStack(spacing: 0) {
                LiveCompanionPresence(store: store, size: size * 0.89, role: .cursor)
                    .overlay {
                        if let playback = store.focusGesturePlayback,
                           playback.purpose != .preview,
                           playback.spatialPreviewID == store.spatialPreview?.id,
                           store.preferences.equipment.supportsPointing {
                            FocusStaffGestureOverlay(playback: playback, size: size * 0.89,
                                reduceMotion: store.preferences.quiet || store.preferences.reduceMotion || systemReduceMotion)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) {
                        if store.assistantActivity != .idle {
                            AssistantTaskCue(activity: store.assistantActivity, quiet: store.preferences.quiet,
                                reduceMotion: store.preferences.reduceMotion, showsLabel: size >= 110)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.regularMaterial, in: Capsule())
                                .padding(.top, 2)
                        }
                    }
                HStack(spacing: 4) {
                    if store.preferences.quiet && size >= 120 { Image(systemName: "moon.fill").font(.system(size: 8)) }
                    Text("ARCHi").font(.system(size: size < 110 ? 10 : 11, weight: .semibold, design: .rounded))
                    Spacer(minLength: 24)
                }
                .foregroundStyle(.white)
                .padding(.leading, size < 110 ? 10 : 12)
                .frame(height: 30)
                .background(.black.opacity(0.72), in: Capsule())
                .padding(.horizontal, 13)
                .padding(.bottom, 4)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Native event routing ensures the drag origin is measured in desktop points,
/// including while the nonactivating window moves underneath the mouse.
@MainActor
private final class CompanionInteractionView: NSView {
    private let store: CompanionStore
    private let menuButton = NSButton()
    private var pointerGesture = CompanionPointerGesture()
    var move: ((CGRect, CGPoint?) -> Void)?
    var openChat: (() -> Void)?
    var finishPoint: (() -> Void)?

    init(store: CompanionStore) {
        self.store = store
        super.init(frame: CGRect(x: 0, y: 0, width: 128, height: 154))
        let hosting = NSHostingView(rootView: FloatingCompanionBody(store: store))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor), hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor), hosting.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        menuButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "ARCHi menu")
        menuButton.contentTintColor = .white
        menuButton.isBordered = false
        menuButton.target = self
        menuButton.action = #selector(openMenu)
        menuButton.toolTip = "ARCHi menu · right-click anywhere on ARCHi"
        menuButton.setAccessibilityLabel("ARCHi menu")
        menuButton.identifier = NSUserInterfaceItemIdentifier("archi.quickMenu")
        addSubview(menuButton)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("ARCHi desktop companion")
        setAccessibilityHelp("Drag to place ARCHi. Click to open the attached chat bubble. Arrow keys move when focused; Escape hides. Right-click for the menu.")
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "Open ARCHi menu", target: self, selector: #selector(accessibilityMenu)),
            NSAccessibilityCustomAction(name: "Move ARCHi left", target: self, selector: #selector(accessibilityLeft)),
            NSAccessibilityCustomAction(name: "Move ARCHi right", target: self, selector: #selector(accessibilityRight)),
            NSAccessibilityCustomAction(name: "Move ARCHi up", target: self, selector: #selector(accessibilityUp)),
            NSAccessibilityCustomAction(name: "Move ARCHi down", target: self, selector: #selector(accessibilityDown))
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        menuButton.frame = CGRect(x: bounds.maxX - 42, y: 5, width: 26, height: 28)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if menuButton.frame.contains(local) { return menuButton }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        store.invalidatePlacementPreview(reason: "You took control of ARCHi. Preview cleared.")
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        window?.makeKey()
        window?.makeFirstResponder(self)
        pointerGesture.begin(at: CompanionPointerLocation.screenPoint(for: event), frame: window?.frame)
    }

    func cancelPointerGesture() { pointerGesture.cancel() }

    override func mouseDragged(with event: NSEvent) {
        guard store.isVisible, !store.isShuttingDown, window?.isVisible == true else {
            pointerGesture.cancel(); return
        }
        let pointer = CompanionPointerLocation.screenPoint(for: event)
        if let proposed = pointerGesture.move(to: pointer) { move?(proposed, pointer) }
    }

    override func mouseUp(with event: NSEvent) {
        guard store.isVisible, !store.isShuttingDown, window?.isVisible == true else {
            pointerGesture.cancel(); return
        }
        let pointer = CompanionPointerLocation.screenPoint(for: event)
        switch pointerGesture.release(at: pointer) {
        case .click: openChat?()
        case .moved(let proposed): move?(proposed, pointer); finishPoint?()
        case .cancelled: break
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        pointerGesture.cancel()
        NSMenu.popUpContextMenu(quickMenu(), with: event, for: self)
    }

    override func keyDown(with event: NSEvent) {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 20 : 4
        switch event.keyCode {
        case 123: nudge(dx: -step, dy: 0)
        case 124: nudge(dx: step, dy: 0)
        case 125: nudge(dx: 0, dy: -step)
        case 126: nudge(dx: 0, dy: step)
        case 53:
            if store.desktopInterest.phase != .idle { store.desktopInterest.cancel() }
            else { store.hideCompanion() }
        case 36, 76: openChat?()
        case 49: openMenu()
        default: super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard let openChat else { return false }; openChat(); return true
    }

    private func nudge(dx: CGFloat, dy: CGFloat) {
        guard let current = window?.frame else { return }
        move?(current.offsetBy(dx: dx, dy: dy), nil)
    }

    private func quickMenu() -> NSMenu {
        let menu = NSMenu(title: "ARCHi")
        func add(_ title: String, _ selector: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            return item
        }
        _ = add("Ask ARCHi…", #selector(ask))
        _ = add("Point at a window…", #selector(pointAtWindow))
        _ = add("Work together…", #selector(context))
        menu.addItem(.separator())
        _ = add("Appearance…", #selector(openAppearance))
        _ = add("Test marketplace…", #selector(openMarketplace))
        let quiet = add("Quiet mode", #selector(toggleQuiet))
        quiet.state = store.preferences.quiet ? .on : .off
        _ = add("Settings…", #selector(settings))
        menu.addItem(.separator())
        _ = add("Hide ARCHi", #selector(hide))
        _ = add("Quit ARCHi", #selector(quit))
        return menu
    }

    @objc private func openMenu() { quickMenu().popUp(positioning: nil, at: NSPoint(x: bounds.maxX - 18, y: 36), in: self) }
    @objc private func ask() { openChat?() }
    @objc private func context() { store.open(.context) }
    @objc private func pointAtWindow() { store.beginDesktopInterest() }
    @objc private func openAppearance() { store.open(.appearance) }
    @objc private func openMarketplace() { store.open(.marketplace) }
    @objc private func toggleQuiet() { store.preferences.quiet.toggle() }
    @objc private func settings() { store.open(.rhythm) }
    @objc private func hide() { store.hideCompanion() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func accessibilityMenu() -> Bool { openMenu(); return true }
    @objc private func accessibilityLeft() -> Bool { nudge(dx: -20, dy: 0); return true }
    @objc private func accessibilityRight() -> Bool { nudge(dx: 20, dy: 0); return true }
    @objc private func accessibilityUp() -> Bool { nudge(dx: 0, dy: 20); return true }
    @objc private func accessibilityDown() -> Bool { nudge(dx: 0, dy: -20); return true }
}
