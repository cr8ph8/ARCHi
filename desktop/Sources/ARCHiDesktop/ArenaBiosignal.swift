import Foundation

/// Device adapters supply measured features, never emotion labels or game actions.
/// No adapter is installed yet. Preview and recorded input stay distinct from live input.
protocol ArenaBiosignalSource: Sendable {
    func start(sessionID: UUID, participantID: UUID) async throws -> AsyncThrowingStream<ArenaBiosignalFrame, Error>
    func stop() async
}

enum ArenaBiosignalOrigin: String, Codable, Sendable { case preview, recorded, live }

struct ArenaBiosignalFrame: Codable, Sendable {
    let schemaVersion: Int
    let sessionID: UUID
    let participantID: UUID
    let sequence: UInt64
    /// Adapter translates its clock into host monotonic seconds, preserving acquisition age.
    let acquiredAt: TimeInterval
    let origin: ArenaBiosignalOrigin
    let calibrationID: UUID
    let featureID: String
    /// This v1 interface accepts a dimensionless fraction only, not raw EEG volts.
    let fraction: Double
    let quality: Double
    let artifactDetected: Bool
}

struct ArenaBiosignalCalibration: Sendable {
    let id: UUID
    let featureID: String
    let low: Double
    let high: Double
    var isValid: Bool {
        !featureID.isEmpty && featureID.utf8.count <= 80 && low.isFinite && high.isFinite
            && low >= 0 && high <= 1 && high - low >= 0.001
    }
}

/// Ephemeral offsets from the user's chosen palette. Never stored as Seed identity.
struct ArenaBiosignalExpression: Equatable, Sendable {
    let hueDegrees: Double
    let brightness: Double
    static let neutral = Self(hueDegrees: 0, brightness: 0)
}

struct ArenaBiosignalSession: Sendable {
    let id: UUID
    let participantID: UUID
    let origin: ArenaBiosignalOrigin
    let calibration: ArenaBiosignalCalibration
    private(set) var lastSequence: UInt64?
    private var lastAcquiredAt: TimeInterval?
    private var smoothed: Double?
    private var available = false
    private var retired = false
    // Presentation policy, not a medically validated quality threshold.
    static let maximumAge: TimeInterval = 2

    init(id: UUID, participantID: UUID, origin: ArenaBiosignalOrigin, calibration: ArenaBiosignalCalibration) {
        self.id = id; self.participantID = participantID; self.origin = origin; self.calibration = calibration
    }

    @discardableResult mutating func receive(_ frame: ArenaBiosignalFrame, now: TimeInterval) -> Bool {
        guard !retired, frame.sessionID == id,
              frame.participantID == participantID, frame.origin == origin,
              frame.calibrationID == calibration.id, frame.featureID == calibration.featureID else { return false }
        guard calibration.isValid, frame.schemaVersion == 1,
              frame.fraction.isFinite, (0...1).contains(frame.fraction),
              frame.quality.isFinite, (0.8...1).contains(frame.quality), !frame.artifactDetected,
              now.isFinite, now >= 0, frame.acquiredAt.isFinite, frame.acquiredAt >= 0,
              now >= frame.acquiredAt, now - frame.acquiredAt <= Self.maximumAge,
              lastSequence.map({ frame.sequence > $0 }) ?? true,
              lastAcquiredAt.map({ frame.acquiredAt > $0 }) ?? true else {
            available = false; smoothed = nil; return false
        }
        let value = min(1, max(0, (frame.fraction - calibration.low) / (calibration.high - calibration.low)))
        let dt = lastAcquiredAt.map { min(1, frame.acquiredAt - $0) } ?? 0
        // One-second smoothing. The first valid sample starts from a neutral palette.
        let previous = smoothed ?? 0.5
        smoothed = previous + (1 - exp(-dt)) * (value - previous)
        lastSequence = frame.sequence; lastAcquiredAt = frame.acquiredAt; available = true
        return true
    }

    func expression(now: TimeInterval, visible: Bool, reduceMotion: Bool) -> ArenaBiosignalExpression {
        guard visible, !reduceMotion, available, let lastAcquiredAt, let smoothed,
              now.isFinite, now >= lastAcquiredAt, now - lastAcquiredAt <= Self.maximumAge else { return .neutral }
        let centered = smoothed * 2 - 1
        return .init(hueDegrees: centered * 12, brightness: centered * 0.06)
    }

    mutating func stop() {
        retired = true; available = false; smoothed = nil
    }
}
