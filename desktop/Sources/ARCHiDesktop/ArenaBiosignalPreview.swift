import SwiftUI

/// A local mapping preview, not a sensor connection or a new companion/profile.
@MainActor
struct ArenaBiosignalPreview: View {
    @ObservedObject var store: CompanionStore
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var expanded = false
    @State private var value = 0.5
    @State private var quality = 1.0
    @State private var sequence: UInt64 = 0
    @State private var session = ArenaBiosignalSession(id: UUID(), participantID: UUID(), origin: .preview,
        calibration: .init(id: UUID(), featureID: "preview-fraction", low: 0, high: 1))
    @State private var sampleTime = 0.0

    private var still: Bool {
        systemReduceMotion || store.preferences.reduceMotion || store.preferences.quiet || !store.isVisible
    }

    var body: some View {
        DisclosureGroup("Brain-signal colors · preview", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text("No device connected").font(.headline)
                Text("Explore a color mapping with sample input. These sliders do not measure brain activity. Your saved look and battle controls stay the same.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 24) {
                    let effect = session.expression(now: sampleTime, visible: expanded, reduceMotion: still)
                    CompanionPresenceArt(form: store.presentationForm, family: store.presentationFamily,
                        size: 96, reduceMotion: true, treatment: store.preferences.visualTreatment,
                        recipe: store.presentationRecipe, naturalVariation: store.presentationNaturalVariation,
                        equipment: store.preferences.equipment, lightExpression: .resting, seedColor: store.preferences.seedColor)
                        .hueRotation(.degrees(effect.hueDegrees)).brightness(effect.brightness)
                        .frame(width: 112, height: 112)
                        .accessibilityLabel("Sample color preview, not a brain measurement")
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sample signal")
                        Slider(value: $value, in: 0...1).accessibilityLabel("Sample signal")
                            .accessibilityIdentifier("arena.biosignal.sample")
                        Text("Sample quality: \(Int(quality * 100))%")
                        Slider(value: $quality, in: 0...1).accessibilityLabel("Sample quality")
                            .accessibilityIdentifier("arena.biosignal.quality")
                    }
                }
                Text(still ? "Motion is reduced or the companion is hidden. Your chosen colors are retained."
                     : quality < 0.8 ? "Sample quality is low. Your chosen colors are restored."
                     : "Sample preview held for review. A future live connection will expire stale input automatically.")
                    .foregroundStyle(.secondary)
                Button("Reset preview") { reset() }.buttonStyle(.bordered)
                Text("Planned comparisons: ARCHi–ARCHi, human–human and human + ARCHi teams. No comparison result has been measured.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(.top, 12)
        }
        .font(.system(size: 12))
        .padding(20).modifier(WorkspaceSurface())
        .accessibilityIdentifier("arena.biosignal.preview")
        .onChange(of: value) { _, _ in sample() }
        .onChange(of: quality) { _, _ in sample() }
        .onChange(of: expanded) { _, open in if !open { reset() } }
        .onChange(of: store.activeQiMon?.originDigest) { _, _ in reset() }
        .onDisappear { reset() }
    }

    private func sample() {
        guard expanded else { return }
        // Deterministic manual preview clock; never labeled live or exported as an outcome.
        if sequence == 0 {
            session.receive(.init(schemaVersion: 1, sessionID: session.id, participantID: session.participantID,
                sequence: 0, acquiredAt: 0, origin: .preview, calibrationID: session.calibration.id,
                featureID: session.calibration.featureID, fraction: 0.5, quality: 1, artifactDetected: false), now: 0)
        }
        sampleTime += 1; sequence += 1
        session.receive(.init(schemaVersion: 1, sessionID: session.id, participantID: session.participantID,
            sequence: sequence, acquiredAt: sampleTime, origin: .preview,
            calibrationID: session.calibration.id, featureID: session.calibration.featureID,
            fraction: value, quality: quality, artifactDetected: false), now: sampleTime)
    }

    private func reset() {
        session.stop()
        session = .init(id: UUID(), participantID: UUID(), origin: .preview,
            calibration: .init(id: UUID(), featureID: "preview-fraction", low: 0, high: 1))
        value = 0.5; quality = 1; sampleTime = 0; sequence = 0
    }
}
