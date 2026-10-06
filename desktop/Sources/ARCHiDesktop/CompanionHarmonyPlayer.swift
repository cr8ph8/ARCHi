import AppKit
import AVFoundation
import Combine

/// One desktop voice over the existing expression owner. No model, microphone,
/// remote audio, game event stream, or queued soundtrack participates.
@MainActor
final class CompanionHarmonyPlayer {
    private weak var store: CompanionStore?
    private var subscription: AnyCancellable?
    private var gate = CompanionHarmonyGate()
    private var player: AVAudioPlayer?
    private var suspended = false
    private var playbackFailure: String?
    private var themeTask: Task<Void, Never>?
    private var activeThemeID: UUID?
    private var lastThemeRequest: UUID?
    private var resonanceGate = CompanionResonancePlaybackGate()
    private var resonanceTask: Task<Void, Never>?
    private var activeResonance: CompanionResonancePlaybackRequest?

    init(store: CompanionStore) {
        self.store = store
        refresh()
        // @Published emits before assignment; evaluate the completed state on
        // the main run loop, after request ownership and its results settle.
        subscription = store.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.refresh()
        }
    }

    func suspend() {
        suspended = true
        stopResonance()
        store?.stopResonancePlayback()
        stopTheme()
        store?.stopHarmonyTheme()
        player?.stop(); player = nil
        gate.reset()
    }

    func resume() {
        guard suspended else { return }
        suspended = false
        refresh() // Baseline only: never replay work completed while hidden.
    }

    private func refresh() {
        guard let store else { player?.stop(); player = nil; return }
        let settings = store.preferences
        let volume = settings.musicalVolume.isFinite ? min(1, max(0, settings.musicalVolume)) : 0
        let visible = !suspended && !(NSApp?.isHidden ?? false) && store.isVisible
            && !store.isShuttingDown && store.activeQiMon != nil && store.section != .play
        let snapshot = CompanionHarmonySnapshot(expression: store.kinLightExpression,
            enabled: settings.musicalCues && volume > 0,
            quiet: settings.quiet, visible: visible, previewID: store.kinLightPreview?.id)
        let decision = gate.update(snapshot: snapshot, now: ProcessInfo.processInfo.systemUptime)
        let resonance = store.resonancePlaybackRequest
        let resonanceContext = resonance.map { store.resonancePlaybackContext(for: $0, visible: visible) }
        let resonanceDecision = resonanceGate.update(request: resonance, context: resonanceContext)
        if let resonance, resonanceContext?.permits(resonance) != true { store.stopResonancePlayback() }
        switch resonanceDecision {
        case .play(let request):
            stopResonance()
            stopTheme()
            beginResonance(request)
            return
        case .stop:
            stopResonance()
        case .none: break
        }
        if activeResonance != nil {
            player?.volume = Float(volume)
            return
        }
        if let activeThemeID {
            if store.harmonyThemeRequest != activeThemeID || !visible || settings.quiet
                || !snapshot.enabled || store.isWorking || store.kinLightPreview != nil || decision != .none {
                stopTheme()
            } else {
                player?.volume = Float(volume)
                return
            }
        }
        if let id = store.harmonyThemeRequest, id != lastThemeRequest {
            lastThemeRequest = id
            if visible && snapshot.enabled && !settings.quiet && !store.isWorking {
                beginTheme(id: id)
                return
            }
            store.stopHarmonyTheme()
        }
        switch decision {
        case .none:
            player?.volume = Float(volume)
        case .stop:
            player?.stop(); player = nil
            playbackFailure = nil
        case .play(let mode):
            player?.stop(); player = nil
            guard let cue = HarmonyCue.forMode(mode), let bytes = HarmonySynth.wav(for: cue) else { return }
            do {
                let next = try AVAudioPlayer(data: bytes, fileTypeHint: AVFileType.wav.rawValue)
                next.volume = Float(volume)
                guard next.prepareToPlay(), next.play() else {
                    playbackFailure = "Sound could not start. Check your Mac’s audio output."
                    setMessage(playbackFailure!)
                    return
                }
                player = next
                playbackFailure = nil
            } catch {
                playbackFailure = "Sound could not start. Your light abilities still work."
                setMessage(playbackFailure!)
                return
            }
        }
        setMessage(!settings.musicalCues ? "Musical cues are off."
            : settings.quiet ? "Quiet mode silences musical cues."
            : volume == 0 ? "Volume is muted."
            : playbackFailure ?? "C major pentatonic · One short phrase at a time.")
    }

    private func stopTheme() {
        guard let id = activeThemeID else { return }
        themeTask?.cancel(); themeTask = nil
        activeThemeID = nil
        player?.stop(); player = nil
        if store?.harmonyThemeRequest == id { store?.stopHarmonyTheme() }
    }

    private func stopResonance() {
        guard let request = activeResonance else { return }
        resonanceTask?.cancel(); resonanceTask = nil
        activeResonance = nil
        resonanceGate.finish(request.id)
        player?.stop(); player = nil
        if store?.resonancePlaybackRequest?.id == request.id { store?.stopResonancePlayback() }
    }

    private func beginResonance(_ request: CompanionResonancePlaybackRequest) {
        player?.stop(); player = nil
        activeResonance = request
        playbackFailure = nil
        resonanceTask = Task { [weak self] in
            let bytes = await Task.detached(priority: .userInitiated) {
                HarmonySynth.resonanceWAV(for: request.kind)
            }.value
            guard !Task.isCancelled, let self else { return }
            guard let store = self.store, self.activeResonance == request,
                  store.resonancePlaybackRequest == request,
                  store.resonancePlaybackContext(for: request,
                    visible: !self.suspended && !(NSApp?.isHidden ?? false)).permits(request) else {
                self.stopResonance()
                return
            }
            do {
                guard let bytes else { throw CocoaError(.fileReadCorruptFile) }
                let next = try AVAudioPlayer(data: bytes, fileTypeHint: AVFileType.wav.rawValue)
                next.volume = Float(min(1, store.preferences.musicalVolume))
                guard next.prepareToPlay(), store.resonancePlaybackRequest == request,
                      store.resonancePlaybackContext(for: request,
                        visible: !self.suspended && !(NSApp?.isHidden ?? false)).permits(request),
                      next.play() else { throw CocoaError(.fileReadUnknown) }
                self.player = next
                let note = CompanionResonance.forKind(request.kind)
                self.setMessage("Playing \(note.noteName) · \(request.kind.title) record note")
                try? await Task.sleep(for: .seconds(next.duration + 0.05))
                guard !Task.isCancelled, self.activeResonance == request else { return }
                self.stopResonance()
                self.setMessage("Record note finished.")
            } catch {
                self.stopResonance()
                self.playbackFailure = "The record note could not play. Check your Mac’s audio output."
                self.setMessage(self.playbackFailure!)
            }
        }
    }

    private func beginTheme(id: UUID) {
        player?.stop(); player = nil
        activeThemeID = id
        playbackFailure = nil
        setMessage("Preparing Seedlight…")
        themeTask = Task { [weak self] in
            // Bounded composition stays off the UI thread. Stop owns the UUID,
            // so a late synthesis result cannot start audio in a new context.
            let bytes = await Task.detached(priority: .userInitiated) { HarmonySynth.themeWAV() }.value
            guard !Task.isCancelled, let self, let store = self.store,
                  self.activeThemeID == id, store.harmonyThemeRequest == id,
                  !self.suspended, !(NSApp?.isHidden ?? false), store.isVisible,
                  !store.isShuttingDown, store.section != .play, store.activeQiMon != nil,
                  store.preferences.musicalCues, !store.preferences.quiet,
                  store.preferences.musicalVolume.isFinite, store.preferences.musicalVolume > 0,
                  !store.isWorking else { return }
            do {
                guard let bytes else { throw CocoaError(.fileReadCorruptFile) }
                let next = try AVAudioPlayer(data: bytes, fileTypeHint: AVFileType.wav.rawValue)
                next.volume = Float(min(1, store.preferences.musicalVolume))
                guard next.prepareToPlay(), next.play() else { throw CocoaError(.fileReadUnknown) }
                self.player = next
                self.setMessage("Playing Seedlight · C major pentatonic · 84 BPM")
                try? await Task.sleep(for: .seconds(next.duration + 0.05))
                guard !Task.isCancelled, self.activeThemeID == id else { return }
                self.stopTheme()
                self.setMessage("Seedlight finished. Your companion is quiet again.")
            } catch {
                self.stopTheme()
                self.playbackFailure = "Seedlight could not play. Check your Mac’s audio output."
                self.setMessage(self.playbackFailure!)
            }
        }
    }

    private func setMessage(_ message: String) {
        guard let store, store.harmonyMessage != message else { return }
        store.harmonyMessage = message
    }
}
