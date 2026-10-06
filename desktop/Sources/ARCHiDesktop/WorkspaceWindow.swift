import AppKit

/// The desktop owns its minimum independently of SwiftUI's repeated hosting
/// measurements. SwiftUI hosting may reset NSWindow's minimum to zero as
/// content changes; that must not make the message controls unreachable.
@MainActor
final class WorkspaceWindow: NSWindow {
    override var contentMinSize: NSSize {
        get { super.contentMinSize }
        set {
            super.contentMinSize = NSSize(
                width: max(880, newValue.width.isFinite ? newValue.width : 880),
                height: max(640, newValue.height.isFinite ? newValue.height : 640))
        }
    }
}
