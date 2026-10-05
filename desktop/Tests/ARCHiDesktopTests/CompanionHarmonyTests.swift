import Foundation
import XCTest
@testable import ARCHiDesktop

final class CompanionHarmonyTests: XCTestCase {
    func testExpressionsSharePentatonicPitchSetAndResolveToCWhileRestIsSilent() throws {
        XCTAssertNil(HarmonyCue.forMode(.rest))
        let modes = KinLightMode.allCases.filter { $0 != .rest }
        let cues = try modes.map { try XCTUnwrap(HarmonyCue.forMode($0)) }
        XCTAssertEqual(cues.count, 6)
        XCTAssertEqual(Set(cues.map(\.midiNotes)).count, cues.count)
        for (mode, cue) in zip(modes, cues) {
            XCTAssertEqual(cue.mode, mode)
            XCTAssertFalse(cue.title.isEmpty)
            XCTAssertEqual(cue.midiNotes.count, 3)
            XCTAssertEqual(cue.noteNames.count, 3)
            XCTAssertTrue(cue.midiNotes.allSatisfy { [0, 2, 4, 7, 9].contains($0 % 12) })
            XCTAssertEqual(try XCTUnwrap(cue.midiNotes.last) % 12, 0)
            XCTAssertTrue(try XCTUnwrap(cue.noteNames.last).hasPrefix("C"))
        }
        XCTAssertEqual(HarmonyCue.forMode(.core)?.noteNames, ["C4", "E4", "C4"])
        XCTAssertEqual(HarmonyCue.forMode(.hold)?.noteNames, ["A3", "D4", "C4"])
    }

    func testEqualTemperamentTuningAndInvalidMIDIBounds() throws {
        XCTAssertEqual(try XCTUnwrap(HarmonySynth.frequency(forMIDINote: 69)), 440, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(HarmonySynth.frequency(forMIDINote: 60)), 261.6255653005986, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(HarmonySynth.frequency(forMIDINote: 62)), 293.6647679174076, accuracy: 1e-9)
        for note in 0...115 {
            let first = try XCTUnwrap(HarmonySynth.frequency(forMIDINote: note))
            let octave = try XCTUnwrap(HarmonySynth.frequency(forMIDINote: note + 12))
            XCTAssertEqual(octave, first * 2, accuracy: 1e-9)
        }
        XCTAssertNil(HarmonySynth.frequency(forMIDINote: -1))
        XCTAssertNil(HarmonySynth.frequency(forMIDINote: 128))
        XCTAssertNil(HarmonySynth.frequency(forMIDINote: Int.min))
        XCTAssertNil(HarmonySynth.frequency(forMIDINote: Int.max))
    }

    func testWAVContainerLengthPeakAndByteDeterminism() throws {
        var uniqueAudio = Set<Data>()
        for mode in KinLightMode.allCases where mode != .rest {
            let cue = try XCTUnwrap(HarmonyCue.forMode(mode))
            let first = try XCTUnwrap(HarmonySynth.wav(for: cue))
            XCTAssertEqual(first, HarmonySynth.wav(for: cue))
            uniqueAudio.insert(first)
            let audio = try decode(first)
            XCTAssertEqual(audio.sampleRate, 22_050)
            XCTAssertEqual(audio.channels, 1)
            XCTAssertEqual(audio.bitsPerSample, 16)
            XCTAssertGreaterThan(audio.samples.count, audio.sampleRate / 2)
            XCTAssertLessThan(Double(audio.samples.count) / Double(audio.sampleRate), 1.5)
            XCTAssertLessThan(first.count, 67_000)
            let peak = audio.samples.map { abs(Double($0)) / 32767 }.max() ?? 0
            XCTAssertGreaterThan(peak, 0.10, "The motif must contain audible synthesized content")
            XCTAssertLessThanOrEqual(peak, 0.22)
            let maximumStep = zip(audio.samples, audio.samples.dropFirst()).map { a, b in
                abs(Double(b) - Double(a)) / 32767
            }.max() ?? 0
            XCTAssertLessThan(maximumStep, 0.055, "No hard sample jump at a note boundary")
        }
        XCTAssertEqual(uniqueAudio.count, 6)
    }

    func testNotesAreSequentialWithSilentGapsAndSoftAttackRelease() throws {
        let rate = HarmonySynth.sampleRate
        for mode in KinLightMode.allCases where mode != .rest {
            let cue = try XCTUnwrap(HarmonyCue.forMode(mode))
            let audio = try decode(XCTUnwrap(HarmonySynth.wav(for: cue)))
            let lead = frames(HarmonySynth.leadSilenceDuration)
            let gap = frames(HarmonySynth.gapDuration)
            XCTAssertTrue(audio.samples.prefix(lead).allSatisfy { $0 == 0 })
            var start = lead
            for (index, duration) in HarmonySynth.noteDurations.enumerated() {
                let count = frames(duration)
                let samples = Array(audio.samples[start..<(start + count)])
                XCTAssertEqual(samples.first, 0)
                XCTAssertEqual(samples.last, 0)
                let edge = Int(Double(rate) * 0.004)
                let body = Array(samples[Int(Double(rate) * 0.035)..<Int(Double(rate) * 0.115)])
                XCTAssertGreaterThan(rms(body), 0.08)
                XCTAssertLessThan(rms(Array(samples.prefix(edge))), rms(body) * 0.15)
                XCTAssertLessThan(rms(Array(samples.suffix(edge))), rms(body) * 0.025)
                start += count
                if index < HarmonySynth.noteDurations.count - 1 {
                    XCTAssertTrue(audio.samples[start..<(start + gap)].allSatisfy { $0 == 0 },
                                  "The next melody note must not overlap the previous note")
                    start += gap
                }
            }
            XCTAssertTrue(audio.samples[start...].allSatisfy { $0 == 0 })
        }
    }

    func testEachSynthesizedNoteHasItsDeclaredFundamental() throws {
        let candidates = [57, 60, 62, 64, 67, 69, 72]
        for mode in KinLightMode.allCases where mode != .rest {
            let cue = try XCTUnwrap(HarmonyCue.forMode(mode))
            let audio = try decode(XCTUnwrap(HarmonySynth.wav(for: cue)))
            var noteStart = frames(HarmonySynth.leadSilenceDuration)
            for (index, expectedNote) in cue.midiNotes.enumerated() {
                let start = noteStart + frames(0.035)
                let samples = Array(audio.samples[start..<(start + frames(0.08))])
                let powers = try candidates.map { candidate in
                    (candidate, spectralPower(samples, frequency: try XCTUnwrap(HarmonySynth.frequency(forMIDINote: candidate)),
                                              sampleRate: audio.sampleRate))
                }
                XCTAssertEqual(powers.max(by: { $0.1 < $1.1 })?.0, expectedNote,
                               "The WAV content must match the advertised motif, not just its metadata")
                let expectedPower = try XCTUnwrap(powers.first(where: { $0.0 == expectedNote })?.1)
                let competitor = powers.filter { $0.0 != expectedNote }.map(\.1).max() ?? 0
                XCTAssertGreaterThan(expectedPower, competitor * 2)
                noteStart += frames(HarmonySynth.noteDurations[index]) + frames(HarmonySynth.gapDuration)
            }
        }
    }

    func testSeedlightScoreIsEightBarsInTheSameKeyAndEndsOnTheRoot() throws {
        XCTAssertEqual(HarmonyTheme.title, "Seedlight")
        XCTAssertEqual(HarmonyTheme.keyName, HarmonyCue.keyName)
        XCTAssertEqual(HarmonyTheme.bpm, 84)
        XCTAssertEqual(HarmonyTheme.beatsPerBar, 4)
        XCTAssertEqual(HarmonyTheme.score.count, 8)
        for bar in HarmonyTheme.score {
            XCTAssertEqual(bar.melody.map(\.beats).reduce(0, +), 4)
            XCTAssertTrue(bar.melody.allSatisfy { $0.beats > 0 })
            XCTAssertTrue((bar.melody.map(\.midiNote) + [bar.bassMIDINote]).allSatisfy {
                [0, 2, 4, 7, 9].contains($0 % 12)
            })
        }
        XCTAssertEqual(HarmonyTheme.score.map(\.bassMIDINote), [48, 48, 45, 48, 48, 43, 48, 48])
        XCTAssertEqual(HarmonyTheme.score.last?.melody.last, HarmonyTheme.Note(60, 3))
        XCTAssertEqual(HarmonyTheme.scoreDuration, 32 * 60 / 84, accuracy: 1e-10)
    }

    func testThemeWAVHasBoundedMixSoftEndsAndDeterministicLength() throws {
        let data = try XCTUnwrap(HarmonySynth.themeWAV())
        XCTAssertEqual(data, HarmonySynth.themeWAV())
        let audio = try decode(data)
        XCTAssertEqual(audio.sampleRate, 22_050)
        XCTAssertEqual(audio.channels, 1)
        XCTAssertEqual(audio.bitsPerSample, 16)
        let duration = Double(audio.samples.count) / Double(audio.sampleRate)
        XCTAssertGreaterThan(duration, 23)
        XCTAssertLessThan(duration, 24)
        XCTAssertEqual(duration, HarmonyTheme.duration, accuracy: 1 / Double(audio.sampleRate))
        XCTAssertLessThan(data.count, 1_100_000)
        let peak = audio.samples.map { abs(Double($0)) / 32767 }.max() ?? 0
        XCTAssertGreaterThan(peak, 0.08)
        XCTAssertLessThanOrEqual(peak, 0.22)
        XCTAssertTrue(audio.samples.prefix(frames(HarmonyTheme.leadSilenceDuration)).allSatisfy { $0 == 0 })
        XCTAssertTrue(audio.samples.suffix(frames(HarmonyTheme.tailSilenceDuration)).allSatisfy { $0 == 0 })
        let maximumStep = zip(audio.samples, audio.samples.dropFirst()).map { a, b in
            abs(Double(b) - Double(a)) / 32767
        }.max() ?? 0
        XCTAssertLessThan(maximumStep, 0.04)
        XCTAssertGreaterThan(audio.samples.filter { $0 != 0 }.count, audio.samples.count / 2)

        // The final sustained note is audibly C4 after the last bass root ends.
        let finalNoteTime = HarmonyTheme.leadSilenceDuration + 29 * HarmonyTheme.secondsPerBeat + 0.6
        let start = frames(finalNoteTime)
        let ending = Array(audio.samples[start..<(start + frames(0.1))])
        let tonicPower = spectralPower(ending, frequency: try XCTUnwrap(HarmonySynth.frequency(forMIDINote: 60)),
                                       sampleRate: audio.sampleRate)
        XCTAssertGreaterThan(tonicPower, 0.0004)
        for candidate in [62, 64, 67, 69] {
            let alternative = spectralPower(ending, frequency: try XCTUnwrap(HarmonySynth.frequency(forMIDINote: candidate)),
                                            sampleRate: audio.sampleRate)
            XCTAssertGreaterThan(tonicPower, alternative * 3)
        }
    }

    func testRecordNotesMatchCataloguePitchWithBoundedWAVAndSoftSilentEnds() throws {
        let candidates = Set(CompanionGraphKind.allCases.map { CompanionResonance.forKind($0).midiNote })
        for kind in CompanionGraphKind.allCases {
            let data = try XCTUnwrap(HarmonySynth.resonanceWAV(for: kind))
            XCTAssertEqual(data, HarmonySynth.resonanceWAV(for: kind))
            let audio = try decode(data)
            XCTAssertEqual(audio.sampleRate, HarmonySynth.sampleRate)
            XCTAssertEqual(audio.channels, 1)
            XCTAssertEqual(audio.bitsPerSample, 16)
            XCTAssertLessThan(data.count, 27_000)
            let duration = Double(audio.samples.count) / Double(audio.sampleRate)
            XCTAssertGreaterThan(duration, 0.4)
            XCTAssertLessThan(duration, 0.6)
            let peak = audio.samples.map { abs(Double($0)) / 32767 }.max() ?? 0
            XCTAssertGreaterThan(peak, 0.1)
            XCTAssertLessThanOrEqual(peak, HarmonySynth.maximumAmplitude + 1 / 32767.0)
            let lead = frames(HarmonySynth.leadSilenceDuration)
            let count = frames(HarmonySynth.resonanceNoteDuration)
            XCTAssertTrue(audio.samples.prefix(lead + 1).allSatisfy { $0 == 0 })
            XCTAssertTrue(audio.samples[(lead + count - 1)...].allSatisfy { $0 == 0 })
            let body = Array(audio.samples[(lead + frames(0.08))..<(lead + frames(0.24))])
            XCTAssertLessThan(rms(Array(audio.samples[lead..<(lead + frames(0.004))])), rms(body) * 0.15)
            XCTAssertLessThan(rms(Array(audio.samples[(lead + count - frames(0.004))..<(lead + count)])), rms(body) * 0.03)
            let powers = try candidates.map { note in
                (note, spectralPower(body, frequency: try XCTUnwrap(HarmonySynth.frequency(forMIDINote: note)),
                                     sampleRate: audio.sampleRate))
            }
            let expected = CompanionResonance.forKind(kind).midiNote
            XCTAssertEqual(powers.max(by: { $0.1 < $1.1 })?.0, expected)
            let expectedPower = try XCTUnwrap(powers.first { $0.0 == expected }?.1)
            XCTAssertGreaterThan(expectedPower, (powers.filter { $0.0 != expected }.map(\.1).max() ?? 0) * 2)
        }
    }

    func testExportRequestedHarmonySamples() throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_HARMONY_EXPORT_DIR"], !path.isEmpty else {
            throw XCTSkip("Set ARCHI_HARMONY_EXPORT_DIR to retain local listening samples")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for mode in KinLightMode.allCases where mode != .rest {
            let cue = try XCTUnwrap(HarmonyCue.forMode(mode))
            let data = try XCTUnwrap(HarmonySynth.wav(for: cue))
            try data.write(to: directory.appendingPathComponent("kin-\(mode.rawValue).wav"), options: .atomic)
        }
        let theme = try XCTUnwrap(HarmonySynth.themeWAV())
        try theme.write(to: directory.appendingPathComponent("seedlight-theme.wav"), options: .atomic)
    }

    private struct PCM {
        let sampleRate: Int
        let channels: Int
        let bitsPerSample: Int
        let samples: [Int16]
    }

    private func decode(_ data: Data) throws -> PCM {
        let bytes = Array(data)
        XCTAssertGreaterThanOrEqual(bytes.count, 44)
        guard bytes.count >= 44 else { throw DecodeFailure.shortHeader }
        func text(_ range: Range<Int>) -> String { String(decoding: bytes[range], as: UTF8.self) }
        func u16(_ offset: Int) -> UInt16 { UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8 }
        func u32(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        }
        XCTAssertEqual(text(0..<4), "RIFF")
        XCTAssertEqual(text(8..<12), "WAVE")
        XCTAssertEqual(text(12..<16), "fmt ")
        XCTAssertEqual(text(36..<40), "data")
        XCTAssertEqual(Int(u32(4)), bytes.count - 8)
        XCTAssertEqual(u32(16), 16)
        XCTAssertEqual(u16(20), 1)
        XCTAssertEqual(u16(32), 2)
        XCTAssertEqual(u32(28), u32(24) * 2)
        XCTAssertEqual(Int(u32(40)), bytes.count - 44)
        XCTAssertEqual((bytes.count - 44) % 2, 0)
        guard (bytes.count - 44) % 2 == 0 else { throw DecodeFailure.unalignedPCM }
        let samples = stride(from: 44, to: bytes.count, by: 2).map { Int16(bitPattern: u16($0)) }
        return PCM(sampleRate: Int(u32(24)), channels: Int(u16(22)), bitsPerSample: Int(u16(34)), samples: samples)
    }

    private func frames(_ duration: TimeInterval) -> Int { Int((duration * Double(HarmonySynth.sampleRate)).rounded(.down)) }
    private func rms(_ samples: [Int16]) -> Double {
        sqrt(samples.map { pow(Double($0) / 32767, 2) }.reduce(0, +) / Double(max(1, samples.count)))
    }
    private func spectralPower(_ samples: [Int16], frequency: Double, sampleRate: Int) -> Double {
        var real = 0.0, imaginary = 0.0
        for (index, sample) in samples.enumerated() {
            let angle = 2 * Double.pi * frequency * Double(index) / Double(sampleRate)
            let value = Double(sample) / 32767
            real += value * cos(angle)
            imaginary += value * sin(angle)
        }
        return (real * real + imaginary * imaginary) / Double(samples.count * samples.count)
    }
    private enum DecodeFailure: Error { case shortHeader, unalignedPCM }
}
