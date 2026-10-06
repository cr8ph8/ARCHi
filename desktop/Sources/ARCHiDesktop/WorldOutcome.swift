import Darwin
import Foundation

/// Facts from an explicit solo input in Unity. This is neither a native command
/// nor skill, learning, rendering, physics-contact or saved-growth evidence.
struct WorldActionOutcome: Codable, Equatable, Identifiable, Sendable {
    let sequence: Int
    let actionID: String
    let boutID: String
    let presentationRevision: Int
    let atUnix: Double
    let action: String
    let rivalAction: String
    let field: String
    let round: Int
    let integrityBefore: Int
    let integrityAfter: Int
    let rivalIntegrityBefore: Int
    let rivalIntegrityAfter: Int
    let sparkBefore: Int
    let sparkAfter: Int
    let rivalSparkBefore: Int
    let rivalSparkAfter: Int
    let damageDealt: Int
    let damageTaken: Int
    let absorbed: Int
    let complete: Bool
    let winner: String
    var id: String { actionID }

    func isValid(revision: Int, observedAt: Double) -> Bool {
        let moves = ["pulse", "guard", "signature"]
        guard sequence > 0, UUID(uuidString: actionID) != nil, UUID(uuidString: boutID) != nil,
              presentationRevision > 0, presentationRevision <= revision,
              atUnix.isFinite, atUnix > 0, atUnix <= observedAt,
              moves.contains(action), moves.contains(rivalAction), ["guardian", "scout"].contains(field),
              (1...20).contains(round), (1...36).contains(integrityBefore), (1...36).contains(rivalIntegrityBefore),
              (0...36).contains(integrityAfter), (0...36).contains(rivalIntegrityAfter),
              (0...3).contains(sparkBefore), (0...3).contains(sparkAfter),
              (0...3).contains(rivalSparkBefore), (0...3).contains(rivalSparkAfter),
              (0...10).contains(damageDealt), (0...10).contains(damageTaken), (0...7).contains(absorbed),
              integrityAfter == max(0, integrityBefore - damageTaken),
              rivalIntegrityAfter == max(0, rivalIntegrityBefore - damageDealt),
              sparkAfter == sparkBefore - (action == "signature" ? 1 : 0),
              rivalSparkAfter == rivalSparkBefore - (rivalAction == "signature" ? 1 : 0),
              ["", "one", "two", "draw"].contains(winner), complete == !winner.isEmpty,
              complete == (integrityAfter == 0 || rivalIntegrityAfter == 0 || round == 20) else { return false }
        let expectedWinner: String
        if integrityAfter == 0 && rivalIntegrityAfter == 0 { expectedWinner = "draw" }
        else if integrityAfter == 0 { expectedWinner = "two" }
        else if rivalIntegrityAfter == 0 { expectedWinner = "one" }
        else if round == 20 {
            if integrityAfter != rivalIntegrityAfter { expectedWinner = integrityAfter > rivalIntegrityAfter ? "one" : "two" }
            else if sparkAfter != rivalSparkAfter { expectedWinner = sparkAfter > rivalSparkAfter ? "one" : "two" }
            else { expectedWinner = "draw" }
        } else { expectedWinner = "" }
        return winner == expectedWinner
    }
}

struct WorldOutcomeBatch: Equatable, Sendable {
    let outcomes: [WorldActionOutcome]
    /// Explicitly report evicted outcomes; this ring is never a complete log.
    let missingCount: Int
}

enum WorldOutcomeError: Error, Equatable {
    case invalidFile, oversized, invalidEnvelope, invalidAction, stalePresentation, sequenceRegression
}

/// Independent of the rendering ACK. The header is a fresh observation; its
/// bounded ring retains immutable solo facts across area/mode changes.
struct WorldOutcomeSnapshot: Codable, Equatable, Sendable {
    static let maximumBytes = 32_768
    static let maximumOutcomes = 32
    static let pathExtension = "world-outcomes"
    let schemaVersion: Int
    let sessionID: String
    let originDigest: String
    let sessionKind: String
    let revision: Int
    let updatedAtUnix: Double
    let currentArea: String
    /// solo, paired, or unavailable. Paired gameplay emits no outcome in v1.
    let mode: String
    let firstSequence: Int
    let lastSequence: Int
    let outcomes: [WorldActionOutcome]

    func validate(matching snapshots: [UnityPresentationSnapshot], now: Date) throws {
        guard schemaVersion == 1, UUID(uuidString: sessionID) != nil,
              revision > 0, updatedAtUnix.isFinite, updatedAtUnix > 0,
              ["companion", "localPractice"].contains(sessionKind),
              ["companion", "arena"].contains(currentArea),
              ["solo", "paired", "unavailable"].contains(mode),
              (mode == "unavailable" || currentArea == "arena"),
              firstSequence >= 0, lastSequence >= 0, outcomes.count <= Self.maximumOutcomes else {
            throw WorldOutcomeError.invalidEnvelope
        }
        let age = now.timeIntervalSince1970 - updatedAtUnix
        guard age.isFinite, (-5...5).contains(age), snapshots.contains(where: {
            $0.sessionID == sessionID && $0.revision == revision && $0.originDigest == originDigest
                && ($0.sessionKind ?? "companion") == sessionKind
        }) else { throw WorldOutcomeError.stalePresentation }
        if outcomes.isEmpty {
            guard firstSequence == 0, lastSequence == 0 else { throw WorldOutcomeError.invalidEnvelope }
            return
        }
        guard firstSequence > 0, lastSequence >= firstSequence,
              lastSequence - firstSequence == outcomes.count - 1,
              outcomes.first?.sequence == firstSequence, outcomes.last?.sequence == lastSequence,
              Set(outcomes.compactMap { UUID(uuidString: $0.actionID) }).count == outcomes.count else {
            throw WorldOutcomeError.invalidEnvelope
        }
        var lastTime = 0.0, lastRevision = 0
        for (index, outcome) in outcomes.enumerated() {
            guard outcome.sequence == firstSequence + index,
                  outcome.isValid(revision: revision, observedAt: updatedAtUnix),
                  outcome.atUnix >= lastTime, outcome.presentationRevision >= lastRevision else {
                throw WorldOutcomeError.invalidAction
            }
            lastTime = outcome.atUnix; lastRevision = outcome.presentationRevision
        }
    }

    /// Call only after validation. A per-session native consumer owns the cursor
    /// and must preserve consumed IDs/facts; a restart is not silently complete.
    func batch(after consumedSequence: Int) throws -> WorldOutcomeBatch {
        guard consumedSequence >= 0, consumedSequence <= lastSequence else {
            throw WorldOutcomeError.sequenceRegression
        }
        let missing = firstSequence > consumedSequence ? max(0, firstSequence - consumedSequence - 1) : 0
        return WorldOutcomeBatch(outcomes: outcomes.filter { $0.sequence > consumedSequence }, missingCount: missing)
    }

    static func read(from presentationURL: URL, matching snapshots: [UnityPresentationSnapshot],
                     now: Date = Date()) throws -> Self {
        guard presentationURL.isFileURL else { throw WorldOutcomeError.invalidFile }
        let url = presentationURL.appendingPathExtension(pathExtension)
        let descriptor = url.path.withCString { Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) }
        guard descriptor >= 0 else { throw WorldOutcomeError.invalidFile }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw WorldOutcomeError.invalidFile
        }
        guard info.st_size > 0, info.st_size <= maximumBytes else { throw WorldOutcomeError.oversized }
        let data = try file.read(upToCount: maximumBytes + 1) ?? Data()
        guard !data.isEmpty, data.count <= maximumBytes else { throw WorldOutcomeError.oversized }
        let snapshot = try JSONDecoder().decode(Self.self, from: data)
        try snapshot.validate(matching: snapshots, now: now)
        return snapshot
    }
}
