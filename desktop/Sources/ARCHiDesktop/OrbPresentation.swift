import Foundation
import Combine
@preconcurrency import AVFoundation

/// Rendering belongs to the existing Unity session. Selecting an orb never changes a saved body or identity.
struct UnityOrbPresentation: Codable, Equatable, Sendable {
    enum Theme: String, Codable, CaseIterable, Identifiable, Sendable {
        case room, fantasy, voxel, neon
        var id: String { rawValue }
        var title: String {
            switch self { case .room: "Studio"; case .fantasy: "Lantern room"; case .voxel: "Voxel room"; case .neon: "Neon room" }
        }
    }
    enum Anchor: String, Codable, CaseIterable, Identifiable, Sendable {
        case world, follow
        var id: String { rawValue }
        var title: String { self == .world ? "Stay in place" : "Near me" }
    }
    var schemaVersion = 1
    var theme: Theme = .room
    var anchor: Anchor = .world
    var listening = false
    var speaking = false
    var isValid: Bool { schemaVersion == 1 }
}

enum OrbCommand: Equatable {
    case theme(UnityOrbPresentation.Theme), anchor(UnityOrbPresentation.Anchor)
    case assistant, memory, qimon, arena, pause, resume

    /// A closed local vocabulary. Unknown requests continue through ARCHi's ordinary assistant routing.
    static func parse(_ text: String) -> Self? {
        guard text.utf8.count <= 512 else { return nil }
        let value = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        switch value {
        case "show memories", "open memories", "show my memories": return .memory
        case "open qimon", "play qimon", "show qimon": return .qimon
        case "open arena", "start practice", "open practice": return .arena
        case "ask archi", "open assistant": return .assistant
        case "orb stay here", "stay here", "anchor orb": return .anchor(.world)
        case "orb follow me", "follow me": return .anchor(.follow)
        case "pause orb", "stop orb", "pause motion": return .pause
        case "resume orb", "resume motion": return .resume
        case "make this room minecraft", "make the room minecraft", "make this room voxel", "voxel room": return .theme(.voxel)
        case "make this room fantasy", "make the room fantasy", "fantasy room", "lantern room": return .theme(.fantasy)
        case "make this room cyberpunk", "make this room neon", "make the room neon", "neon room": return .theme(.neon)
        case "restore room", "restore the room", "studio room": return .theme(.room)
        default: return nil
        }
    }
}

struct UnityOrbActionRequest: Decodable {
    let schemaVersion: Int
    let sessionID, originDigest, action: String
    let value: String?
    let revision, sequence: Int
    let updatedAtUnix: Double

    func resolve(matching snapshots: [UnityPresentationSnapshot], after prior: Int, now: Date) -> OrbCommand? {
        guard schemaVersion == 1, sequence > prior, sequence > 0, revision > 0,
              updatedAtUnix.isFinite, now.timeIntervalSince1970.isFinite,
              abs(now.timeIntervalSince1970 - updatedAtUnix) <= 5,
              let latest = snapshots.first, latest.orb != nil, latest.active, latest.visible,
              latest.sessionKind != "localPractice", (latest.destination ?? "companion") == "companion",
              snapshots.contains(where: { $0.hasSamePresentation(as: latest) && $0.sessionID == sessionID
                  && $0.originDigest == originDigest && $0.revision == revision }) else { return nil }
        switch action {
        case "theme": return value.flatMap(UnityOrbPresentation.Theme.init(rawValue:)).map(OrbCommand.theme)
        case "anchor": return value.flatMap(UnityOrbPresentation.Anchor.init(rawValue:)).map(OrbCommand.anchor)
        case "assistant": return value == nil || value == "" ? .assistant : nil
        case "memory": return value == nil || value == "" ? .memory : nil
        case "qimon": return value == nil || value == "" ? .qimon : nil
        case "arena": return value == nil || value == "" ? .arena : nil
        default: return nil
        }
    }
}

/// Native, explicit speech playback. Only playback state crosses the presentation boundary, never reply text.
@MainActor
final class OrbSpeechPlayback: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    var changed: (@MainActor () -> Void)?
    private let synthesizer = AVSpeechSynthesizer()
    private var current: ObjectIdentifier?

    override init() { super.init(); synthesizer.delegate = self }
    func speak(_ text: String) {
        stop()
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 32_000 else { return }
        let utterance = AVSpeechUtterance(string: value)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        current = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
    }
    func stop() {
        current = nil
        synthesizer.stopSpeaking(at: .immediate)
        if isSpeaking { isSpeaking = false; changed?() }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.current == identifier else { return }
            self.isSpeaking = true; self.changed?()
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { finish(utterance) }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { finish(utterance) }
    nonisolated private func finish(_ utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.current == identifier else { return }
            self.current = nil; self.isSpeaking = false; self.changed?()
        }
    }
}
