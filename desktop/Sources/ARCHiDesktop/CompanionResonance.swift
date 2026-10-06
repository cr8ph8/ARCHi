import Foundation

/// Names used as a finite artistic palette. These are designed associations,
/// not measured EEG, a cognitive assessment, or visual animation frequencies.
enum CompanionBrainwaveBand: String, CaseIterable, Identifiable, Sendable {
    case delta, theta, alpha, beta, gamma

    var id: String { rawValue }
    var title: String {
        switch self {
        case .delta: "Delta"
        case .theta: "Theta"
        case .alpha: "Alpha"
        case .beta: "Beta"
        case .gamma: "Gamma"
        }
    }
}

/// A fixed presentation assignment for a record type. Neither the musical pitch
/// nor the band name is inferred from the record's content, status, or owner.
/// Real biosignal input remains in ArenaBiosignalSession under its own gates.
struct CompanionResonance: Equatable, Sendable {
    static let associationLabel = "Designed association"
    static let associationExplanation = "Notes and brainwave-band names are artistic assignments to record types. They do not measure brain activity or infer a mental state."

    let kind: CompanionGraphKind
    let midiNote: Int
    let noteName: String
    /// Audible musical pitch only. Never use this as a flashing or motion rate.
    let frequencyHz: Double
    let brainwaveBand: CompanionBrainwaveBand

    private init(kind: CompanionGraphKind, midiNote: Int, brainwaveBand: CompanionBrainwaveBand) {
        // This closed catalogue uses the existing harmony's tuning and scale.
        // An editable catalogue would need a separate validated construction path.
        let pitchNames = [0: "C", 2: "D", 4: "E", 7: "G", 9: "A"]
        guard HarmonyCue.pitchClasses.contains(midiNote % 12),
              let pitch = pitchNames[midiNote % 12],
              let frequency = HarmonySynth.frequency(forMIDINote: midiNote),
              frequency.isFinite, frequency > 0 else {
            preconditionFailure("The fixed resonance catalogue must contain valid harmony notes")
        }
        self.kind = kind
        self.midiNote = midiNote
        self.frequencyHz = frequency
        self.brainwaveBand = brainwaveBand
        self.noteName = "\(pitch)\(midiNote / 12 - 1)"
    }

    /// Explicit cases keep assignments stable when the enum gains/reorders cases.
    /// Twelve record types have distinct pitches; the five band labels are reused.
    static func forKind(_ kind: CompanionGraphKind) -> Self {
        switch kind {
        case .companion: .init(kind: kind, midiNote: 60, brainwaveBand: .alpha)
        case .source: .init(kind: kind, midiNote: 48, brainwaveBand: .delta)
        case .knowledge: .init(kind: kind, midiNote: 50, brainwaveBand: .theta)
        case .lesson: .init(kind: kind, midiNote: 52, brainwaveBand: .theta)
        case .method: .init(kind: kind, midiNote: 55, brainwaveBand: .beta)
        case .request: .init(kind: kind, midiNote: 57, brainwaveBand: .alpha)
        case .invocation: .init(kind: kind, midiNote: 62, brainwaveBand: .beta)
        case .answer: .init(kind: kind, midiNote: 64, brainwaveBand: .alpha)
        case .context: .init(kind: kind, midiNote: 67, brainwaveBand: .theta)
        case .omission: .init(kind: kind, midiNote: 69, brainwaveBand: .delta)
        case .evaluation: .init(kind: kind, midiNote: 72, brainwaveBand: .gamma)
        case .accounting: .init(kind: kind, midiNote: 74, brainwaveBand: .beta)
        }
    }

    /// Bind only to an exact, unambiguous node in the caller's current snapshot.
    /// Do not parse an arbitrary ID into a type or silently repair its identity.
    static func forNodeID(_ nodeID: String, in graph: CompanionGraphSnapshot) -> NodeAssignment? {
        guard !nodeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let matches = graph.nodes.lazy.filter { $0.id == nodeID }.prefix(2)
        guard matches.count == 1, let node = matches.first else { return nil }
        return .init(nodeID: node.id, resonance: forKind(node.kind))
    }

    /// This lightweight binding preserves the graph's record identity. Sharing a
    /// pitch or a band label never merges two records or establishes a graph edge.
    struct NodeAssignment: Identifiable, Equatable, Sendable {
        let nodeID: String
        let resonance: CompanionResonance
        var id: String { nodeID }
    }
}
