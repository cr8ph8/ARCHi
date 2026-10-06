import SwiftUI

/// Edits one store-owned draft, allowing a visit to Work together and back
/// without giving this presentation view its own save or playback lifecycle.
@MainActor
struct FocusGestureTeachingCard: View {
    @ObservedObject var store: CompanionStore
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var staticCue: Bool {
        store.preferences.quiet || store.preferences.reduceMotion || systemReduceMotion
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Teach the staff").font(.system(size: 15, weight: .medium, design: .rounded))
            Text("When you choose Point with staff, ARCHi uses this gesture. Shape its pace, sparkle and pause.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            if store.focusGestureDraft != nil {
                draftControls
            } else {
                keptControls
            }
            if !store.focusGestureMessage.isEmpty {
                Text(store.focusGestureMessage)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("focus-gesture.status")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var keptControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text((store.effectiveFocusGesture).summary)
                .font(.system(size: 12))
                .accessibilityIdentifier("focus-gesture.kept-summary")
            HStack(spacing: 12) {
                Button(store.keptFocusGesture == nil ? "Teach gesture" : "Edit gesture") {
                    store.beginFocusGestureTeaching()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("focus-gesture.teach")
                if store.keptFocusGesture != nil {
                    Button("Forget gesture") { store.forgetFocusGesture() }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("focus-gesture.forget")
                        .help("Return to this staff design’s default gesture.")
                }
            }
            .disabled(store.isShuttingDown)
        }
    }

    private var draftControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 18) {
                preview
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Pace", selection: draftBinding(\.pace, fallback: .gentle)) {
                        ForEach(FocusGestureConfiguration.Pace.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .accessibilityIdentifier("focus-gesture.pace")
                    Picker("Sparkle", selection: draftBinding(\.sparkle, fallback: .soft)) {
                        ForEach(FocusGestureConfiguration.Sparkle.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .accessibilityIdentifier("focus-gesture.sparkle")
                    Picker("Hold", selection: draftBinding(\.hold, fallback: .brief)) {
                        ForEach(FocusGestureConfiguration.Hold.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .accessibilityIdentifier("focus-gesture.hold")
                }
                .pickerStyle(.menu).controlSize(.small)
                .font(.system(size: 12)).frame(maxWidth: 290)
                Spacer(minLength: 0)
            }
            Text(staticCue ? "Quiet or Reduce Motion is on. The gesture uses a still cue."
                 : "Preview the staff cue here. Your companion's body stays unchanged.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .accessibilityIdentifier("focus-gesture.motion-mode")
            HStack(spacing: 10) {
                Button("Preview", systemImage: "play") { store.previewFocusGesture() }
                    .accessibilityIdentifier("focus-gesture.preview")
                Button("Stop", systemImage: "stop") { store.stopFocusGesture() }
                    .disabled(store.focusGesturePlayback == nil)
                    .accessibilityIdentifier("focus-gesture.stop")
            }
            .buttonStyle(.bordered).controlSize(.small)
            Button("Practice in Work together", systemImage: "doc.text.viewfinder") { store.open(.context) }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("focus-gesture.open-practice")
                .help("Open your draft, equip the staff if needed, then select a passage and choose Practice gesture.")
            Text("Practice needs the equipped staff and a selected passage. You choose when to try it.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Divider()
            HStack(spacing: 12) {
                Button("Keep gesture") { store.keepFocusGesture() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("focus-gesture.keep")
                Button("Cancel") { store.cancelFocusGestureTeaching() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("focus-gesture.cancel")
            }
            Text("Keep saves only this gesture on this Mac. It does not save other appearance choices or send an assistant request.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(store.isShuttingDown)
    }

    private var previewEquipment: CompanionEquipment {
        store.preferences.equipment.supportsPointing ? store.preferences.equipment : CompanionEquipment(hand: .focusStaff)
    }

    private var preview: some View {
        ZStack {
            CompanionPresenceArt(form: store.presentationForm, family: store.presentationFamily,
                size: 116, reduceMotion: true, treatment: store.preferences.visualTreatment,
                recipe: store.presentationRecipe, naturalVariation: store.presentationNaturalVariation,
                equipment: previewEquipment, seedColor: store.preferences.seedColor)
            if let playback = store.focusGesturePlayback, playback.purpose == .preview {
                FocusStaffGestureOverlay(playback: playback, size: 116, reduceMotion: staticCue)
            }
        }
        .frame(width: 132, height: 132)
        .background(ArchiPalette.lilac.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current companion with \(previewEquipment.item?.title ?? "Focus Staff"), gesture preview")
        .accessibilityValue(store.focusGesturePlayback?.purpose == .preview
            ? (staticCue ? "Still cue" : "Playing preview") : "Ready to preview")
        .accessibilityIdentifier("focus-gesture.preview-art")
    }

    private func draftBinding<Value>(_ keyPath: WritableKeyPath<FocusGestureConfiguration, Value>,
                                     fallback: Value) -> Binding<Value> {
        Binding(get: { store.focusGestureDraft?[keyPath: keyPath] ?? fallback }, set: { value in
            guard var draft = store.focusGestureDraft else { return }
            draft[keyPath: keyPath] = value
            store.focusGestureDraft = draft
        })
    }
}
