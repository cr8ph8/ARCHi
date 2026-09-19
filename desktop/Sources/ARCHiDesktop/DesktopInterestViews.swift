import AppKit
import SwiftUI

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
    private let panel: NSPanel
    private let host = NSHostingView(rootView: DesktopInterestOutlineView(cue: .init(phase: .idle, target: nil), animated: false))
    private var lastCue: DesktopInterestCue?
    private var lastAnimated = false
    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "ARCHi selected window"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = true; panel.level = .floating
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        host.sizingOptions = []
        panel.contentView = host
    }

    func hide() {
        panel.orderOut(nil)
        // Release the active TimelineView as well as hiding its window.
        host.rootView = DesktopInterestOutlineView(cue: .init(phase: .idle, target: nil), animated: false)
        lastCue = nil; lastAnimated = false
    }

    func show(cue: DesktopInterestCue, quiet: Bool, reduceMotion: Bool, systemReduceMotion: Bool) {
        guard let frame = cue.outlineFrame else { hide(); return }
        let animated = cue.animates(quiet: quiet, reduceMotion: reduceMotion, systemReduceMotion: systemReduceMotion)
        if cue != lastCue || animated != lastAnimated {
            host.rootView = DesktopInterestOutlineView(cue: cue, animated: animated)
            lastCue = cue; lastAnimated = animated
        }
        if panel.frame != frame { panel.setFrame(frame, display: true, animate: false) }
        if !panel.isVisible { panel.orderFrontRegardless() }
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
