import Foundation

/// Addressable representations of an explicitly named object. Sharing an object
/// ID does not establish physical equivalence, perception, or model introspection.
enum RepresentationKind: String, CaseIterable, Codable, Sendable {
    case pixels, particles, node, neural, splats

    var title: String {
        switch self {
        case .pixels: "Pixels"
        case .particles: "Particles"
        case .node: "Nodes"
        case .neural: "Neurons"
        case .splats: "Splats"
        }
    }
}

struct RepresentationObjectReference: Codable, Equatable, Hashable, Sendable {
    let semanticObjectID: String
    let artifactID: String
    let revision: String

    var isWellFormed: Bool {
        [semanticObjectID, artifactID, revision].allSatisfy(PeerFieldValidation.identifier)
    }
}

struct PixelRegion: Codable, Equatable, Hashable, Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    func fits(width frameWidth: Int, height frameHeight: Int) -> Bool {
        x >= 0 && y >= 0 && width > 0 && height > 0 && x <= frameWidth && y <= frameHeight
            && width <= frameWidth - x && height <= frameHeight - y
    }
}

struct PixelFrameReference: Codable, Equatable, Hashable, Sendable {
    let object: RepresentationObjectReference
    let frameIndex: Int
    let frameWidth: Int
    let frameHeight: Int
    var region: PixelRegion? = nil
}

struct ParticleEmitterReference: Codable, Equatable, Hashable, Sendable {
    let object: RepresentationObjectReference
    let emitterID: String
    let checkpointID: String
}

struct SemanticNodeReference: Codable, Equatable, Hashable, Sendable {
    let object: RepresentationObjectReference
    let graphID: String
    let nodeID: String
    /// An edit reference is a proposal against object.revision, never an edit command.
    var proposedEditID: String? = nil
}

/// Only an explicit capture can name an activation. This is not hidden reasoning.
struct NeuralActivationReference: Codable, Equatable, Hashable, Sendable {
    let layerID: String
    let tensorArtifactID: String
    let captureID: String
}

struct NeuralCheckpointReference: Codable, Equatable, Hashable, Sendable {
    let object: RepresentationObjectReference
    let modelID: String
    let checkpointID: String
    var activation: NeuralActivationReference? = nil
}

struct RepresentationFrameSegment: Codable, Equatable, Hashable, Sendable {
    let startFrame: Int
    let endFrameExclusive: Int
}

struct SplatSetReference: Codable, Equatable, Hashable, Sendable {
    let object: RepresentationObjectReference
    let setID: String
    var segment: RepresentationFrameSegment? = nil
}

enum RepresentationReference: Codable, Equatable, Hashable, Sendable {
    case pixels(PixelFrameReference)
    case particles(ParticleEmitterReference)
    case node(SemanticNodeReference)
    case neural(NeuralCheckpointReference)
    case splats(SplatSetReference)

    var kind: RepresentationKind {
        switch self {
        case .pixels: .pixels
        case .particles: .particles
        case .node: .node
        case .neural: .neural
        case .splats: .splats
        }
    }

    var object: RepresentationObjectReference {
        switch self {
        case .pixels(let value): value.object
        case .particles(let value): value.object
        case .node(let value): value.object
        case .neural(let value): value.object
        case .splats(let value): value.object
        }
    }

    var semanticObjectID: String { object.semanticObjectID }
    var artifactID: String { object.artifactID }
    var revision: String { object.revision }

    var isWellFormed: Bool {
        guard object.isWellFormed else { return false }
        switch self {
        case .pixels(let value):
            return value.frameIndex >= 0 && (1...1_000_000).contains(value.frameWidth)
                && (1...1_000_000).contains(value.frameHeight)
                && (value.region?.fits(width: value.frameWidth, height: value.frameHeight) ?? true)
        case .particles(let value):
            return PeerFieldValidation.identifier(value.emitterID) && PeerFieldValidation.identifier(value.checkpointID)
        case .node(let value):
            return PeerFieldValidation.identifier(value.graphID) && PeerFieldValidation.identifier(value.nodeID)
                && (value.proposedEditID.map(PeerFieldValidation.identifier) ?? true)
        case .neural(let value):
            guard PeerFieldValidation.identifier(value.modelID), PeerFieldValidation.identifier(value.checkpointID) else { return false }
            guard let activation = value.activation else { return true }
            return [activation.layerID, activation.tensorArtifactID, activation.captureID].allSatisfy(PeerFieldValidation.identifier)
        case .splats(let value):
            guard PeerFieldValidation.identifier(value.setID) else { return false }
            guard let segment = value.segment else { return true }
            return segment.startFrame >= 0 && segment.endFrameExclusive > segment.startFrame
        }
    }
}

enum PeerDataOrigin: String, Codable, CaseIterable, Sendable {
    case simulation, localSnapshot, remoteClaim
}

/// A reference is a claim about evidence, not verification that its artifact exists.
struct PeerEvidenceReference: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let artifactID: String
    let revision: String
    let contentDigest: String
    let producerPeerID: String
    let origin: PeerDataOrigin

    var isWellFormed: Bool {
        [id, artifactID, revision, producerPeerID].allSatisfy(PeerFieldValidation.identifier)
            && PeerFieldValidation.sha256Digest(contentDigest)
    }
}

struct RepresentationEvidenceLink: Identifiable, Codable, Equatable, Sendable {
    enum Relation: String, Codable, Sendable {
        case derivedFrom, rendersTo, annotates, sampledFrom, proposesEditTo
    }

    let id: String
    let from: RepresentationReference
    let to: RepresentationReference
    let relation: Relation
    let evidenceIDs: [String]
}

/// A peer's reported activity is separate from locally observed contact freshness.
enum PeerReportedStatus: String, Codable, CaseIterable, Sendable {
    case ready, working, quiet, unknown
}

struct PeerObservationIdentity: Codable, Equatable, Hashable, Sendable {
    let sessionID: String
    let originPeerID: String
    let observationID: String
}

struct PeerObservation: Identifiable, Codable, Equatable, Sendable {
    let sessionID: String
    let originPeerID: String
    let eventID: String
    /// Unique within the declared session and origin, not an authentication claim.
    let observationID: String
    let sequence: UInt64
    let semanticObjectID: String
    let origin: PeerDataOrigin
    let status: PeerReportedStatus
    let representations: [RepresentationReference]
    let evidence: [PeerEvidenceReference]
    var links: [RepresentationEvidenceLink] = []

    var id: PeerObservationIdentity {
        .init(sessionID: sessionID, originPeerID: originPeerID, observationID: observationID)
    }
}

/// Relays change delivery identity and routing only. They preserve the observation.
/// These IDs scope this in-process protocol; they are not authenticated identities.
struct PeerEnvelope: Codable, Equatable, Sendable {
    var protocolVersion: Int = 1
    let sessionID: String
    let deliveryID: String
    let senderPeerID: String
    let recipientPeerID: String
    let observation: PeerObservation
    let ttl: TimeInterval
}

enum PeerReceiptDisposition: String, Codable, Sendable {
    case accepted, duplicateDelivery, duplicateObservation, conflict, rejected, capacity, invalidTime
}

struct PeerReceipt: Identifiable, Codable, Equatable, Sendable {
    let id: UInt64
    let deliveryID: String
    let observationID: String
    let senderPeerID: String
    let disposition: PeerReceiptDisposition
    let detail: String
    let receivedAt: TimeInterval?
}

enum PeerCheckStatus: String, Codable, CaseIterable, Sendable {
    case pass = "PASS"
    case fail = "FAIL"
    case skipped = "SKIPPED"
    case error = "ERROR"
}

enum PeerDecision: String, Codable, CaseIterable, Sendable {
    case commit = "COMMIT"
    case damp = "DAMP"
    case escalate = "ESCALATE"
    case reject = "REJECT"
}

struct PeerCheckResult: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let status: PeerCheckStatus
    let detail: String
    var required: Bool = true
}

enum PeerFieldValidation {
    static func identifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    static func sha256Digest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }

    static func time(_ value: TimeInterval, after previous: TimeInterval?) -> Bool {
        value.isFinite && value >= 0 && (previous.map { value >= $0 } ?? true)
    }

    static func diagnosticID(_ value: String) -> String {
        String(decoding: value.utf8.prefix(256), as: UTF8.self)
            .components(separatedBy: .controlCharacters).joined()
    }
}

enum PeerCanonicalEncoding {
    static func data<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(value)
    }

    /// Diagnostic fingerprint only. Admission also compares exact registered input
    /// and the native owner's source/context digests; this is not cryptography.
    static func fingerprint<T: Encodable>(_ value: T) -> String? {
        guard let data = data(value) else { return nil }
        var value: UInt64 = 14_695_981_039_346_656_037
        for byte in data { value = (value ^ UInt64(byte)) &* 1_099_511_628_211 }
        let hex = String(value, radix: 16)
        return "fnv1a64:" + String(repeating: "0", count: 16 - hex.count) + hex
    }
}
