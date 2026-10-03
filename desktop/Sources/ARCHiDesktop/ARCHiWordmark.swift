import SwiftUI

/// The existing sparkle-and-circle mark is the tittle of the final lowercase i.
/// A dotless glyph avoids painting over text and keeps both themes transparent.
struct ARCHiWordmark: View {
    var pointSize: CGFloat = 24

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("ARCH").tracking(pointSize / 8)
            Text("ı")
                .overlay(alignment: .top) {
                    Image(systemName: "sparkle")
                        .font(.system(size: pointSize * 0.18, weight: .ultraLight))
                        .foregroundStyle(WorkspaceTheme.accent)
                        .frame(width: pointSize * 0.35, height: pointSize * 0.35)
                        .overlay(Circle().stroke(WorkspaceTheme.accent.opacity(0.45), lineWidth: pointSize / 48))
                        .offset(y: -pointSize * 0.025)
                        .accessibilityHidden(true)
                }
        }
        .font(.system(size: pointSize, weight: .light))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ARCHi")
        .accessibilityIdentifier("workspace.wordmark")
    }
}
