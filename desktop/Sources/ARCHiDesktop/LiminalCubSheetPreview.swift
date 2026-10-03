import SwiftUI

/// A local reference preview. Reads the existing store; never chooses or saves a form.
@MainActor
struct LiminalCubSheetPreview: View {
    @ObservedObject var store: CompanionStore
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false

    private var moving: Bool {
        LiminalCubSpriteClip.motionAllowed(expression: store.kinLightExpression,
            reduceMotion: store.preferences.reduceMotion, systemReduceMotion: systemReduceMotion,
            quiet: store.preferences.quiet, visible: visible && scenePhase == .active)
    }

    var body: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cub motion study").font(.headline)
                Text("Idle frames from your reference sheet, with its original background. Liminal’s activity and motion settings guide this preview.")
                    .font(.callout).foregroundStyle(.secondary)
                if let asset = LiminalCubSheetAsset.bundled {
                    TimelineView(.animation(minimumInterval: 1 / 24, paused: !moving)) { clock in
                        let frame = asset.clip.frameIndex(at: clock.date.timeIntervalSinceReferenceDate,
                                                        animating: moving)
                        LiminalCubSheetFrame(asset: asset, frameIndex: frame)
                            .frame(width: 232, height: 216)
                            .accessibilityLabel("Liminal cub reference, idle frame \(frame + 1) of 8")
                    }
                    .frame(maxWidth: .infinity)
                    Label(store.kinLightExpression.label, systemImage: moving ? "play.circle" : "pause.circle")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Reference-sheet preview · 8 idle frames · background retained")
                        .font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Show original reference sheet") {
                        Image(nsImage: asset.image).resizable().interpolation(.high).scaledToFit()
                            .frame(maxHeight: 600)
                            .accessibilityLabel("Original supplied Liminal cub reference sheet")
                    }
                    .font(.caption)
                    .accessibilityIdentifier("liminal-cub-study.reference-sheet")
                } else {
                    HamptonLiminalSeedArt(size: 180, reduceMotion: true, seedColor: store.preferences.seedColor)
                        .frame(maxWidth: .infinity)
                    Text("Reference sheet unavailable. Showing your retained Seed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Your retained Seed, identity and saved development stay unchanged.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .accessibilityIdentifier("liminal-cub-study.card")
    }
}

/// Draws only an authenticated source rectangle. No cropped asset is generated.
@MainActor
struct LiminalCubSheetFrame: View {
    let asset: LiminalCubSheetAsset.Asset
    let frameIndex: Int

    var body: some View {
        Canvas { context, size in
            let clip = asset.clip
            guard clip.isValid else { return }
            let frame = clip.frames[min(clip.frames.count - 1, max(0, frameIndex))]
            let scale = min(size.width / CGFloat(clip.canvasWidth), size.height / CGFloat(clip.canvasHeight))
            let left = (size.width - CGFloat(frame.width) * scale) / 2
            let top = (size.height - CGFloat(clip.canvasHeight) * scale) / 2
                + CGFloat(clip.canvasHeight - frame.height) * scale
            let viewport = CGRect(x: left, y: top, width: CGFloat(frame.width) * scale,
                                  height: CGFloat(frame.height) * scale)
            context.clip(to: Path(viewport))
            context.draw(Image(nsImage: asset.image), in: CGRect(
                x: left - CGFloat(frame.x) * scale, y: top - CGFloat(frame.y) * scale,
                width: CGFloat(clip.pixelWidth) * scale, height: CGFloat(clip.pixelHeight) * scale))
        }
    }
}
