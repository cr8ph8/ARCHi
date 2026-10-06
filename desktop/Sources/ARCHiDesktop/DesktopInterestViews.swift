import AppKit
import SwiftUI
import ARCHiSpatial

@MainActor
struct DesktopInterestCard: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject var session: DesktopInterestSession
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorScheme) private var colorScheme

    init(store: CompanionStore) { self.store = store; self.session = store.desktopInterest }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Object of interest", systemImage: "viewfinder")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? KinLightPalette(mode: .focus).highlight : KinLightPalette(mode: .focus).shadow)
            DesktopInterestStatusCue(cue: session.cue)
            if let targetName = session.cue.targetName {
                Text(targetName)
                    .font(.system(size: 12, weight: .medium)).lineLimit(2)
            }
            Text(session.message).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("interest.status")
            if session.phase == .targeted || session.phase == .review {
                Button(session.attracting ? "Release particles" : session.markedArea == nil
                    ? "Attract particles to this window" : "Attract particles to marked area", systemImage: "sparkles") {
                    if session.attracting { session.stopAttraction() }
                    else { _ = session.startAttraction() }
                }
                .disabled(session.areaMarking != nil || store.preferences.quiet || store.preferences.reduceMotion || systemReduceMotion || !store.memoryParticleMotionEnabled)
                .accessibilityIdentifier("interest.attract")
                HStack {
                    if session.areaMarking != nil {
                        Button("Cancel marking", role: .cancel) { session.cancelMarkingArea() }
                            .accessibilityIdentifier("interest.cancel-marking")
                    } else {
                        Button("Mark an area…", systemImage: "rectangle.dashed") { _ = session.beginMarkingArea() }
                            .accessibilityIdentifier("interest.mark-area")
                    }
                    if session.markedArea != nil {
                        Button("Use whole window") { session.useWholeWindow() }
                            .accessibilityIdentifier("interest.whole-window")
                    }
                }.buttonStyle(.bordered).controlSize(.small)
                Text(session.markedArea == nil ? "Follows the selected window’s outline locally. This does not read its contents."
                    : "The marked area follows this window’s size and position. This does not identify or read what is inside.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let capture = session.capture, session.phase == .review {
                Text(capture.method).font(.system(size: 10)).foregroundStyle(.secondary)
                ScrollView {
                    Text(capture.text).font(.system(size: 12)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                .frame(height: 130).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("interest.snapshot")
                Text("\(capture.text.utf8.count.formatted()) bytes · captured \(capture.capturedAt.formatted(date: .omitted, time: .shortened)) · local copy")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Button("Use in Work together", systemImage: "doc.text") { store.useDesktopInterestCapture() }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("interest.use")
            }
            HStack {
                switch session.phase {
                case .targeted:
                    Button("Read this window", systemImage: "text.viewfinder") { session.read() }
                        .accessibilityIdentifier("interest.read")
                case .aiming:
                    Button("Choose highlighted window") { session.finishAim() }
                        .disabled(session.target == nil).accessibilityIdentifier("interest.choose")
                case .reading:
                    if session.cue.animates(quiet: store.preferences.quiet, reduceMotion: store.preferences.reduceMotion,
                                           systemReduceMotion: systemReduceMotion) {
                        ProgressView().controlSize(.small).accessibilityLabel("Reading selected window locally")
                    } else {
                        Label("Reading locally…", systemImage: "text.viewfinder").font(.system(size: 11))
                    }
                case .idle, .failed, .review:
                    Button("Point at a window", systemImage: "scope") { store.beginDesktopInterest() }
                        .accessibilityIdentifier("interest.begin")
                }
                Spacer(minLength: 0)
                if session.phase != .idle {
                    Button(session.phase == .reading ? "Stop" : "Clear") { session.cancel() }
                        .accessibilityIdentifier("interest.clear")
                }
            }.buttonStyle(.bordered).controlSize(.small)
            if session.phase == .failed {
                HStack {
                    Button("Accessibility settings") { openPrivacy("Privacy_Accessibility") }
                    Button("Screen Recording settings") { openPrivacy("Privacy_ScreenCapture") }
                }.buttonStyle(.link).font(.system(size: 10))
            }
            Text("Reads app text or visible text with local OCR. Images are not saved or sent. Original apps are not edited.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain).accessibilityIdentifier("interest.card")
    }

    private func openPrivacy(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor) {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The card and the click-through outline describe the same acquisition state.
struct DesktopInterestStatusCue: View {
    let cue: DesktopInterestCue

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(cue.title, systemImage: cue.symbol).font(.system(size: 11, weight: .semibold))
            Text(cue.scope).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cue.accessibilityLabel)
        .accessibilityIdentifier("interest.scope")
    }
}

@MainActor
struct DesktopInterestSharingNotice: View {
    @ObservedObject var store: CompanionStore
    var body: some View {
        if let source = store.desktopInterestSource {
            VStack(alignment: .leading, spacing: 5) {
                Label("Window snapshot · " + source.method, systemImage: "viewfinder")
                    .font(.system(size: 11, weight: .medium))
                Text("Captured \(source.capturedAt.formatted(date: .abbreviated, time: .shortened)). The original window can change; this copy does not refresh automatically.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                if store.route == .native && !hasExternalPermission {
                    Text("This copy stays local. Send can try Qwen now; Codex fallback needs permission for this exact copy.")
                        .font(.system(size: 11))
                    Button("Allow this copy for Codex fallback") { store.allowDesktopInterestWithExternalRoute() }
                        .buttonStyle(.bordered).controlSize(.small).accessibilityIdentifier("interest.allow-external")
                        .disabled(store.isWorking || store.isShuttingDown)
                } else if (store.route == .codex || store.route == .compare) && !hasExternalPermission {
                    Text("This copy is local. Your selected route includes Codex.").font(.system(size: 11))
                    Button("Allow this copy with \(store.route.title)") { store.allowDesktopInterestWithExternalRoute() }
                        .buttonStyle(.bordered).controlSize(.small).accessibilityIdentifier("interest.allow-external")
                        .disabled(store.isWorking || store.isShuttingDown)
                } else {
                    Text(sharingDisclosure)
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .contain).accessibilityIdentifier("interest.sharing")
        }
    }

    private var hasExternalPermission: Bool {
        store.desktopInterestExternalDigest == LessonSource.digest(of: store.sharedText)
    }

    private var sharingDisclosure: String {
        switch store.route {
        case .native:
            "External sharing is allowed for this exact copy. Send tries Qwen first; one Codex fallback may receive this copy if Qwen is unavailable or times out."
        case .local, .automatic:
            hasExternalPermission
                ? "Only Local Qwen receives this copy with the selected route. External sharing permission is retained for this exact copy."
                : "Only Local Qwen receives this copy when you press Send. External sharing is not allowed."
        case .codex, .compare:
            "External sharing is allowed for this exact copy. Codex receives it when you press Send."
        }
    }
}

/// Click-through native outline. A rectangle is a selection cue, not a captured
/// image or a claim that the model has already observed this window.
@MainActor
final class DesktopInterestOutline {
    private let panel: DesktopInterestSelectionPanel
    private let host = NSHostingView(rootView: DesktopInterestOverlayView(cue: .init(phase: .idle, target: nil), animated: false))
    private var lastCue: DesktopInterestCue?
    private var lastAnimated = false
    private var lastAttraction: DesktopParticleAttraction?
    private var markingID: UUID?
    init() {
        panel = DesktopInterestSelectionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "ARCHi selected window"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = true; panel.level = .floating
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        host.sizingOptions = []
        panel.contentView = host
    }

    func hide() {
        finishMarkingPresentation()
        panel.orderOut(nil)
        // Release the active TimelineView as well as hiding its window.
        host.rootView = DesktopInterestOverlayView(cue: .init(phase: .idle, target: nil), animated: false)
        lastCue = nil; lastAnimated = false; lastAttraction = nil
    }

    func showMarking(_ marking: DesktopInterestSession.AreaMarking,
                     onCommit: @escaping (ImageRegionRect) -> Void, onCancel: @escaping () -> Void) {
        guard markingID != marking.id else { return }
        hide()
        markingID = marking.id
        let selection = DesktopInterestAreaSelectionView(frame: .zero)
        selection.commit = { [weak self] region in
            self?.finishMarkingPresentation(); onCommit(region)
        }
        selection.cancel = { [weak self] in
            self?.finishMarkingPresentation(); onCancel()
        }
        panel.selectingArea = true
        panel.cancelSelection = { [weak selection] in selection?.cancel?() }
        panel.ignoresMouseEvents = false
        panel.contentView = selection
        panel.setFrame(marking.target.frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(selection)
    }

    private func finishMarkingPresentation() {
        guard markingID != nil else { return }
        markingID = nil
        panel.selectingArea = false
        panel.cancelSelection = nil
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
        panel.contentView = host
        lastCue = nil; lastAttraction = nil
    }

    func show(cue: DesktopInterestCue, quiet: Bool, reduceMotion: Bool, systemReduceMotion: Bool,
              attraction: DesktopParticleAttraction? = nil, motion: CompanionParticleMotion? = nil,
              markedFrame: CGRect? = nil) {
        finishMarkingPresentation()
        guard let outline = markedFrame ?? cue.outlineFrame else { hide(); return }
        let frame = attraction?.overlay ?? outline
        let animated = cue.animates(quiet: quiet, reduceMotion: reduceMotion, systemReduceMotion: systemReduceMotion)
        if cue != lastCue || animated != lastAnimated || attraction != lastAttraction {
            host.rootView = DesktopInterestOverlayView(cue: cue, animated: animated, attraction: attraction, motion: motion)
            lastCue = cue; lastAnimated = animated; lastAttraction = attraction
        }
        if panel.frame != frame { panel.setFrame(frame, display: true, animate: false) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
}

/// The existing outline accepts events only during an explicit area gesture.
/// Clicking elsewhere relinquishes capture; no global mouse or keyboard hook.
@MainActor private final class DesktopInterestSelectionPanel: NSPanel {
    var selectingArea = false
    var cancelSelection: (() -> Void)?
    override var canBecomeKey: Bool { selectingArea }
    override func resignKey() {
        super.resignKey()
        if selectingArea { cancelSelection?() }
    }
}

@MainActor private final class DesktopInterestAreaSelectionView: NSView {
    var commit: ((ImageRegionRect) -> Void)?
    var cancel: (() -> Void)?
    private var start: CGPoint?
    private var selection: ImageRegionRect?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Mark an area inside the selected window. Drag to select. Escape cancels. No content is read.")
        setAccessibilityIdentifier("interest.area-selection")
        let button = NSButton(title: "Cancel marking", target: self, action: #selector(cancelMarking))
        button.bezelStyle = .rounded
        button.frame = CGRect(x: 12, y: 44, width: 136, height: 28)
        button.setAccessibilityIdentifier("interest.area-selection.cancel")
        addSubview(button)
        let center = NSButton(title: "Use center area", target: self, action: #selector(selectCenterArea))
        center.bezelStyle = .rounded
        center.frame = CGRect(x: 154, y: 44, width: 140, height: 28)
        center.setAccessibilityIdentifier("interest.area-selection.center")
        center.setAccessibilityHelp("Select the middle half of this window without dragging. Return also selects this area.")
        addSubview(center)
    }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.18).setFill(); bounds.fill()
        let frame = selection?.displayed(in: bounds) ?? bounds.insetBy(dx: 2, dy: 2)
        NSColor.systemCyan.withAlphaComponent(0.16).setFill(); frame.fill()
        NSColor.systemCyan.setStroke()
        let path = NSBezierPath(rect: frame); path.lineWidth = 2
        path.setLineDash([7, 4], count: 2, phase: 0); path.stroke()
        let text = "Drag to mark an area · Escape cancels · No content read"
        let caption = CGRect(x: 10, y: 8, width: max(0, bounds.width - 20), height: 30)
        NSColor.black.withAlphaComponent(0.86).setFill(); caption.fill()
        (text as NSString).draw(in: caption.insetBy(dx: 6, dy: 6), withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white
        ])
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        start = convert(event.locationInWindow, from: nil); selection = nil; needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        selection = ImageRegionRect.selection(from: start, to: convert(event.locationInWindow, from: nil), in: bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        self.start = nil
        guard let region = ImageRegionRect.selection(from: start, to: convert(event.locationInWindow, from: nil), in: bounds) else {
            selection = nil; needsDisplay = true; return
        }
        commit?(region)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancel?() }
        else if event.keyCode == 36 { selectCenterArea() }
        else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) { cancel?() }
    @objc private func cancelMarking() { cancel?() }
    @objc private func selectCenterArea() {
        if let center = ImageRegionRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5) { commit?(center) }
    }
}

struct DesktopParticleAttraction: Equatable {
    let scene: CompanionParticleScene
    let overlay: CGRect
    let origin: CGRect
    let target: CGRect
    let pointsPerUnit: Double
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.scene.motionID == rhs.scene.motionID && lhs.overlay == rhs.overlay
            && lhs.origin == rhs.origin && lhs.target == rhs.target && lhs.pointsPerUnit == rhs.pointsPerUnit
    }
}

private struct DesktopInterestOverlayView: View {
    let cue: DesktopInterestCue
    let animated: Bool
    var attraction: DesktopParticleAttraction?
    var motion: CompanionParticleMotion?
    var body: some View {
        if let attraction {
            ZStack(alignment: .topLeading) {
                DesktopInterestOutlineView(cue: cue, animated: false)
                    .frame(width: attraction.target.width, height: attraction.target.height)
                    .offset(x: attraction.target.minX, y: attraction.target.minY)
                KnowledgeParticleView(field: attraction.scene.field, nodes: attraction.scene.graph.nodes, selectedID: nil,
                    spread: 1, pulses: true, reduceMotion: false, tint: .cyan, showsLabels: false,
                    compact: true, interactive: false, growthByRecordID: attraction.scene.growthByRecordID,
                    regionTarget: attraction.target, usesPhysicalAttraction: true, presentationOrigin: attraction.origin,
                    attractionPointsPerUnit: attraction.pointsPerUnit,
                    motionSceneDigest: attraction.scene.motionID, onSelect: { _ in })
                    .environment(\.companionParticleMotion, motion)
            }.allowsHitTesting(false).accessibilityHidden(true)
        } else { DesktopInterestOutlineView(cue: cue, animated: animated) }
    }
}

struct DesktopInterestOutlineView: View {
    let cue: DesktopInterestCue
    let animated: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        let moving = animated && !systemReduceMotion
        let palette = KinLightPalette(mode: .focus)
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !moving)) { time in
            GeometryReader { geometry in
                let opacity = DesktopInterestCue.opacity(at: time.date.timeIntervalSinceReferenceDate, animated: moving)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(palette.accent.opacity(0.22 * opacity), lineWidth: 7).padding(4)
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(palette.highlight.opacity(opacity), style: StrokeStyle(lineWidth: 2,
                            dash: cue.phase == .aiming ? [7, 5] : [])).padding(4)
                    if geometry.size.width >= 180 && geometry.size.height >= 70 {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("ARCHi · " + cue.title, systemImage: cue.symbol)
                                .font(.system(size: 11, weight: .semibold))
                            Text(cue.scope).font(.system(size: 10))
                        }
                        .lineLimit(1).foregroundStyle(palette.highlight)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 7))
                        .padding(10)
                    }
                }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
