import Foundation

/// Short original motifs for existing light expressions. They share one fixed
/// C-major pentatonic set; no microphone, music analysis, or model is involved.
struct HarmonyCue: Equatable, Sendable {
    static let keyName = "C major pentatonic"
    static let pitchClasses: Set<Int> = [0, 2, 4, 7, 9]

    let mode: KinLightMode
    let title: String
    let noteNames: [String]
    let midiNotes: [Int]

    private init(mode: KinLightMode, midiNotes: [Int]) {
        self.mode = mode
        self.title = "\(mode.title) motif"
        self.midiNotes = midiNotes
        self.noteNames = midiNotes.map { note in
            let pitch: String
            switch note % 12 {
            case 0: pitch = "C"
            case 2: pitch = "D"
            case 4: pitch = "E"
            case 7: pitch = "G"
            case 9: pitch = "A"
            default: pitch = "?"
            }
            return "\(pitch)\(note / 12 - 1)"
        }
    }

    /// Rest is silence, not a repeated tonic. Other cues resolve to C4 or C5.
    static func forMode(_ mode: KinLightMode) -> Self? {
        let notes: [Int]
        switch mode {
        case .rest: return nil
        case .core: notes = [60, 64, 60]       // C4 E4 C4 · home
        case .orbit: notes = [62, 67, 60]      // D4 G4 C4 · gather
        case .focus: notes = [64, 62, 60]      // E4 D4 C4 · settle
        case .pulse: notes = [67, 69, 72]      // G4 A4 C5 · respond
        case .delight: notes = [64, 67, 72]    // E4 G4 C5 · open
        case .hold: notes = [57, 62, 60]       // A3 D4 C4 · gentle hold
        }
        return Self(mode: mode, midiNotes: notes)
    }
}

/// An original, fixed eight-bar theme. This reviewable score has no imported
/// recordings, looping player, adaptive key detection, or background music.
enum HarmonyTheme {
    struct Note: Equatable, Sendable {
        let midiNote: Int
        let beats: Int
        init(_ midiNote: Int, _ beats: Int = 1) {
            self.midiNote = midiNote
            self.beats = beats
        }
    }

    struct Bar: Equatable, Sendable {
        let melody: [Note]
        let bassMIDINote: Int
    }

    static let title = "Seedlight"
    static let keyName = HarmonyCue.keyName
    static let bpm = 84
    static let beatsPerBar = 4
    static let score: [Bar] = [
        Bar(melody: [Note(60), Note(64), Note(67), Note(64)], bassMIDINote: 48),
        Bar(melody: [Note(62), Note(67), Note(64), Note(60)], bassMIDINote: 48),
        Bar(melody: [Note(69), Note(67), Note(64), Note(60)], bassMIDINote: 45),
        Bar(melody: [Note(64), Note(62), Note(60, 2)], bassMIDINote: 48),
        Bar(melody: [Note(72), Note(69), Note(67), Note(64)], bassMIDINote: 48),
        Bar(melody: [Note(67), Note(69), Note(72), Note(67)], bassMIDINote: 43),
        Bar(melody: [Note(64), Note(67), Note(62), Note(64)], bassMIDINote: 48),
        Bar(melody: [Note(62), Note(60, 3)], bassMIDINote: 48)
    ]
    static let leadSilenceDuration: TimeInterval = 0.04
    static let tailSilenceDuration: TimeInterval = 0.45
    static let secondsPerBeat: TimeInterval = 60 / Double(bpm)
    static let scoreDuration = Double(score.count * beatsPerBar) * secondsPerBeat
    static let duration = leadSilenceDuration + scoreDuration + tailSilenceDuration
}

/// Provider-free, mono 16-bit PCM synthesis. Playback and user volume belong to
/// the desktop owner; constructing bytes never accesses an audio device.
enum HarmonySynth {
    static let sampleRate = 22_050
    static let maximumAmplitude = 0.20
    static let noteDurations: [TimeInterval] = [0.20, 0.20, 0.34]
    static let gapDuration: TimeInterval = 0.025
    static let leadSilenceDuration: TimeInterval = 0.015
    static let tailSilenceDuration: TimeInterval = 0.035
    static let attackDuration: TimeInterval = 0.018
    static let releaseDuration: TimeInterval = 0.065
    static let maximumDuration: TimeInterval = 1.5
    static let resonanceNoteDuration: TimeInterval = 0.46

    static func frequency(forMIDINote note: Int) -> Double? {
        guard (0...127).contains(note) else { return nil }
        return 440 * pow(2, Double(note - 69) / 12)
    }

    static func wav(for cue: HarmonyCue) -> Data? {
        // The catalogue is intentionally closed. A future editable motif needs
        // its own bounds instead of inheriting this fixed cue's assumptions.
        guard HarmonyCue.forMode(cue.mode) == cue,
              cue.midiNotes.count == noteDurations.count,
              cue.midiNotes.allSatisfy({ HarmonyCue.pitchClasses.contains($0 % 12) }),
              cue.midiNotes.last.map({ $0 % 12 == 0 }) == true else { return nil }
        let lead = frames(leadSilenceDuration)
        let tail = frames(tailSilenceDuration)
        let gap = frames(gapDuration)
        let noteFrames = noteDurations.map(frames)
        let frameCount = lead + tail + noteFrames.reduce(0, +) + gap * (noteFrames.count - 1)
        guard frameCount > 0, frameCount < frames(maximumDuration),
              noteFrames.allSatisfy({ $0 > 1 }) else { return nil }
        var samples = [Int16](repeating: 0, count: frameCount)
        var start = lead
        for (index, note) in cue.midiNotes.enumerated() {
            guard let frequency = frequency(forMIDINote: note),
                  frequency * 2 < Double(sampleRate) / 2 else { return nil }
            let count = noteFrames[index]
            for frame in 0..<count {
                let time = Double(frame) / Double(sampleRate)
                // A restrained octave harmonic gives the sine a warmer edge.
                // Weights total one, so the signal cannot exceed the peak cap.
                let wave = warmWave(time: time, frequency: frequency)
                let value = maximumAmplitude * envelope(frame: frame, count: count) * wave
                let bounded = min(max(value, -maximumAmplitude), maximumAmplitude)
                samples[start + frame] = Int16((bounded * Double(Int16.max)).rounded())
            }
            start += count + (index == noteFrames.count - 1 ? 0 : gap)
        }

        return encodeWAV(samples)
    }

    /// One artistic record note from the shared resonance catalogue. Selection
    /// and hover never call this; the audio owner requires an explicit request.
    static func resonanceWAV(for kind: CompanionGraphKind) -> Data? {
        let note = CompanionResonance.forKind(kind).midiNote
        guard HarmonyCue.pitchClasses.contains(note % 12),
              let frequency = frequency(forMIDINote: note),
              frequency * 2 < Double(sampleRate) / 2 else { return nil }
        let lead = frames(leadSilenceDuration), count = frames(resonanceNoteDuration)
        let frameCount = lead + count + frames(tailSilenceDuration)
        guard count > 1, frameCount < frames(maximumDuration) else { return nil }
        var samples = [Int16](repeating: 0, count: frameCount)
        for frame in 0..<count {
            let time = Double(frame) / Double(sampleRate)
            let value = maximumAmplitude * envelope(frame: frame, count: count)
                * warmWave(time: time, frequency: frequency)
            guard value.isFinite, abs(value) <= maximumAmplitude else { return nil }
            samples[lead + frame] = Int16((value * Double(Int16.max)).rounded())
        }
        return encodeWAV(samples)
    }

    /// The complete theme is an explicit one-shot song, separate from the
    /// sub-1.5-second expression cues. Melody and bass have fixed headroom.
    static func themeWAV() -> Data? {
        let score = HarmonyTheme.score
        guard score.count == 8,
              HarmonyTheme.duration > 0, HarmonyTheme.duration < 30,
              score.allSatisfy({ bar in
                  bar.melody.reduce(0, { $0 + $1.beats }) == HarmonyTheme.beatsPerBar
                      && HarmonyCue.pitchClasses.contains(bar.bassMIDINote % 12)
                      && bar.melody.allSatisfy { $0.beats > 0 && HarmonyCue.pitchClasses.contains($0.midiNote % 12) }
              }), score.last?.melody.last?.midiNote == 60 else { return nil }

        let count = frames(HarmonyTheme.duration)
        let lead = frames(HarmonyTheme.leadSilenceDuration)
        let scoreEnd = lead + frames(HarmonyTheme.scoreDuration)
        var mix = [Double](repeating: 0, count: count)
        for (barIndex, bar) in score.enumerated() {
            let barBeat = barIndex * HarmonyTheme.beatsPerBar
            let bassStart = lead + frames(Double(barBeat) * HarmonyTheme.secondsPerBeat)
            // One quiet root per bar, leaving space after it instead of a drone.
            guard addThemeNote(bar.bassMIDINote, start: bassStart,
                               count: frames(1.6 * HarmonyTheme.secondsPerBeat),
                               amplitude: 0.035, to: &mix) else { return nil }
            var beat = barBeat
            for note in bar.melody {
                // Absolute beat positions avoid cumulative rounding drift.
                let start = lead + frames(Double(beat) * HarmonyTheme.secondsPerBeat)
                let end = lead + frames(Double(beat + note.beats) * HarmonyTheme.secondsPerBeat)
                guard addThemeNote(note.midiNote, start: start, count: end - start - frames(0.035),
                                   amplitude: 0.14, to: &mix) else { return nil }
                beat += note.beats
            }
        }

        // At most one melody and one bass voice overlap: 0.14 + 0.035 < 0.22.
        // Fade the whole piece as well as every note. Reject instead of clipping
        // if a future score/voice edit breaks the promised signal bound.
        var samples = [Int16](repeating: 0, count: count)
        for frame in mix.indices {
            let attack = max(0, min(1, Double(frame - lead) / Double(frames(0.06))))
            let release = max(0, min(1, Double(scoreEnd - 1 - frame) / Double(frames(0.22))))
            let fade = cosineEdge(attack) * cosineEdge(release)
            let value = mix[frame] * fade
            guard value.isFinite, abs(value) <= 0.22 else { return nil }
            samples[frame] = Int16((value * Double(Int16.max)).rounded())
        }
        return encodeWAV(samples)
    }

    private static func addThemeNote(_ note: Int, start: Int, count: Int,
                                     amplitude: Double, to mix: inout [Double]) -> Bool {
        guard let frequency = frequency(forMIDINote: note), frequency * 2 < Double(sampleRate) / 2,
              start >= 0, count > 1, start + count <= mix.count else { return false }
        for frame in 0..<count {
            let time = Double(frame) / Double(sampleRate)
            // A gentle decay keeps long melody notes and bass roots bell-like.
            let decay = 0.65 + 0.35 * exp(-time * 2.2)
            mix[start + frame] += amplitude * decay * envelope(frame: frame, count: count)
                * warmWave(time: time, frequency: frequency)
        }
        return true
    }

    private static func warmWave(time: TimeInterval, frequency: Double) -> Double {
        let angle = 2 * Double.pi * frequency * time
        return 0.84 * sin(angle) + 0.16 * sin(angle * 2)
    }

    private static func encodeWAV(_ samples: [Int16]) -> Data {
        let dataBytes = samples.count * MemoryLayout<Int16>.size
        var data = Data()
        data.reserveCapacity(44 + dataBytes)
        data.append(contentsOf: "RIFF".utf8)
        append32(UInt32(36 + dataBytes), to: &data)
        data.append(contentsOf: "WAVEfmt ".utf8)
        append32(16, to: &data)                         // PCM format chunk bytes
        append16(1, to: &data)                          // integer PCM
        append16(1, to: &data)                          // mono
        append32(UInt32(sampleRate), to: &data)
        append32(UInt32(sampleRate * 2), to: &data)     // bytes per second
        append16(2, to: &data)                          // block alignment
        append16(16, to: &data)                         // bits per sample
        data.append(contentsOf: "data".utf8)
        append32(UInt32(dataBytes), to: &data)
        for sample in samples { append16(UInt16(bitPattern: sample), to: &data) }
        return data
    }

    private static func frames(_ duration: TimeInterval) -> Int {
        Int((duration * Double(sampleRate)).rounded(.down))
    }

    private static func envelope(frame: Int, count: Int) -> Double {
        guard frame > 0, frame < count - 1 else { return 0 }
        let time = Double(frame) / Double(sampleRate)
        let remaining = Double(count - 1 - frame) / Double(sampleRate)
        let attack = min(1, time / attackDuration)
        let release = min(1, remaining / releaseDuration)
        // Raised-cosine edges have zero slope at silence and full sustain.
        return cosineEdge(attack) * cosineEdge(release)
    }

    private static func cosineEdge(_ fraction: Double) -> Double { 0.5 - 0.5 * cos(.pi * fraction) }

    private static func append16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    private static func append32(_ value: UInt32, to data: inout Data) {
        for shift in stride(from: 0, through: 24, by: 8) {
            data.append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }
}
