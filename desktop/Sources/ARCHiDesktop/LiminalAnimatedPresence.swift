import SwiftUI

/// Traverse the authored sample timeline in either direction. These coordinates
/// are presentation only; no activity cue changes a memory or grants a form.
@MainActor
struct LiminalAnimatedPresence: View {
    let asset: LiminalPointAsset
    let progress: Double
    let reduceMotion: Bool
    var seedColor: CompanionSeedColor = .original
    var lightIntensity: Float = 1
    var lightExpression: KinLightExpression = .resting
    var structure: LiminalPointStructure? = nil
    var inspection = false
    var selectableIDs: [UInt32] = []
    var onSelectArtID: ((UInt32) -> Void)? = nil
    @State private var from = 107.0 / 119.0
    @State private var to = 107.0 / 119.0
    @State private var started = Date.distantPast
    @State private var appeared = false
    @State private var visible = false
    private var duration: Double { abs(to - from) * 119 / 24 }
    private func sample(_ date: Date) -> Double {
        guard !reduceMotion, !inspection, duration > 0 else { return to }
        let t = min(1, max(0, date.timeIntervalSince(started) / duration))
        return from + (to - from) * t
    }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !visible || reduceMotion || inspection || from == to)) { context in
            LiminalMetalView(asset: asset, progress: sample(context.date), reduceMotion: reduceMotion,
                isVisible: visible, seedColor: seedColor, lightIntensity: lightIntensity,
                lightExpression: lightExpression, inspection: inspection, structure: structure,
                selectableIDs: selectableIDs, onSelectArtID: onSelectArtID)
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .task(id: started) {
            guard !reduceMotion else { from = to; return }
            guard duration > 0 else { return }
            do {
                try await Task.sleep(for: .seconds(duration))
                try Task.checkCancellation()
                from = to
            } catch { /* A new pose or disappearing view cancels this transition. */ }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { from = to }
        }
        .onChange(of: progress, initial: true) { _, value in
            let now = Date()
            let bounded = value.isFinite ? min(1, max(0, value)) : LiminalV008Runtime.orbProgress
            from = appeared ? sample(now) : bounded
            to = bounded; started = now; appeared = true
        }
    }
}
