import AppKit
import SwiftUI

/// ARCHi uses AppKit hosts rather than SwiftUI Scenes. Observe the actual host
/// so a hidden window cannot keep a particle clock running.
struct ParticlePresentationVisibility: NSViewRepresentable {
    let changed: (Bool) -> Void

    func makeNSView(context: Context) -> Probe { Probe(changed: changed) }
    func updateNSView(_ view: Probe, context: Context) {
        view.changed = changed
        view.refresh()
    }
    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.stop() }

    final class Probe: NSView {
        var changed: (Bool) -> Void
        private var observers: [NSObjectProtocol] = []
        private var reported: Bool?
        private var stopped = false

        init(changed: @escaping (Bool) -> Void) {
            self.changed = changed
            super.init(frame: .zero)
            for name in [NSWindow.didChangeOcclusionStateNotification,
                         NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                         NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.refresh() }
                })
            }
        }
        required init?(coder: NSCoder) { nil }
        override var isOpaque: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refresh() }
        override func viewDidHide() { super.viewDidHide(); refresh() }
        override func viewDidUnhide() { super.viewDidUnhide(); refresh() }
        func refresh() {
            guard !stopped else { return }
            let visible = window?.isVisible == true && window?.occlusionState.contains(.visible) == true
                && !isHiddenOrHasHiddenAncestor && !(NSApp?.isHidden ?? false)
            guard visible != reported else { return }
            reported = visible
            // Never mutate SwiftUI state from inside updateNSView.
            Task { @MainActor [weak self] in
                guard let self, !self.stopped, self.reported == visible else { return }
                self.changed(visible)
            }
        }
        func stop() {
            stopped = true
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
        }
    }
}

/// A TimelineView tick is only a scheduling token. Its wall clock never becomes
/// simulation time, and GPU acknowledgments reusing that token cannot step again.
@MainActor final class ParticlePresentationClock {
    private let uptime: () -> Double
    private var tick: Date?
    private var sampled = 0.0
    init(uptime: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) { self.uptime = uptime }
    func time(for date: Date) -> Double {
        if tick != date { tick = date; sampled = uptime() }
        return sampled
    }
}
