import Foundation
import CryptoKit

/// Latest observed metadata from existing native owners. This is a value
/// projection, not an event journal, a model observer, or a memory writer.
struct SeedTelemetrySnapshot: Encodable, Equatable, Sendable {
    let schemaVersion = 1
    let origin = "native"
    let contextID: String
    let telemetry: SeedTelemetry

    /// Every leaf is JSON-compatible; no dates, native handles or enum objects
    /// cross the one-way WebKit boundary.
    func webPayload() throws -> [String: Any] {
        let bytes = try JSONEncoder().encode(self)
        guard let value = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            throw CocoaError(.coderInvalidValue)
        }
        return value
    }
}

/// Redaction must cover the interval before WebKit acknowledges a replacement.
/// Additions and status-only updates keep the page visible so actual observed
/// changes can animate. A pending fence stays hidden until the latest delivery.
enum SeedDiveReplacementPolicy {
    static func requiresFence(previous: CompanionGraphSnapshot, next: CompanionGraphSnapshot,
                              previousContextID: String?, nextContextID: String?) -> Bool {
        guard previousContextID == nextContextID else { return true }
        let current = Dictionary(next.nodes.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        return previous.nodes.contains { old in
            guard let node = current[old.id] else { return true }
            return old.kind != node.kind || old.title != node.title || old.subtitle != node.subtitle
                || old.details != node.details
        }
    }
}

struct SeedTelemetry: Encodable, Equatable, Sendable {
    struct Memory: Encodable, Equatable, Sendable {
        let keptLessonCount: Int
        let temporaryRecordCount: Int
        let graphNodeCount: Int
        let graphEdgeCount: Int
        let truncatedCount: Int
    }

    struct Invocation: Encodable, Equatable, Sendable {
        let id: String
        let role: String
        let status: String
    }

    struct Admission: Encodable, Equatable, Sendable {
        let status: String
        let stage: String
        let reason: String?
    }

    struct Lane: Encodable, Equatable, Sendable {
        let id: String
        let provider: String
        let state: String
        let phase: String
        let requestID: String?
        let contextCurrent: Bool?
        let requestStarted: Bool
        let modelIdentity: String?
        let elapsedMilliseconds: Int?
        let invocations: [Invocation]
        let omittedInvocationCount: Int
        let admission: Admission?
    }

    struct Harness: Encodable, Equatable, Sendable {
        let state: String
        let lanes: [Lane]
    }

    struct Check: Encodable, Equatable, Sendable {
        let id: String
        let status: String
    }

    struct Simulation: Encodable, Equatable, Sendable {
        let origin = "synthetic"
        let round: Int
        let workerCount: Int
    }

    struct Peer: Encodable, Equatable, Sendable {
        let progress: String
        let attemptID: String?
        let candidateReady: Bool
        let acceptedReportCount: Int
        let checks: [Check]
        let omittedCheckCount: Int
        let simulation: Simulation?
    }

    struct Neural: Encodable, Equatable, Sendable {
        let available = false
        let reason = "No activation recorder is connected."
    }

    let memory: Memory
    let harness: Harness
    let peer: Peer
    let neural = Neural()
}

enum SeedTelemetryProjection {
    static let maximumInvocationsPerLane = 16
    static let maximumChecks = 16
    static let maximumIdentifierBytes = 128
    static let maximumModelIdentityBytes = 256

    /// Limits apply only to this inspection projection. Truncation never changes
    /// a receipt, a report, a source, or the corresponding native owner.
    static func build(context: ContextTicket, lessonRevision: UInt64,
                      graph: CompanionGraphSnapshot, keptLessonCount: Int,
                      temporaryRecordCount: Int, isWorking: Bool,
                      lanes: [AssistantProvider: AssistantLaneResult],
                      peerLab: CompanionPeerLabState) -> SeedTelemetrySnapshot {
        let contextParts = [context.generation, context.placement, context.source,
                            context.selection, lessonRevision].map(String.init).joined(separator: ":")
        let currentLanes = AssistantProvider.allCases.compactMap { provider -> SeedTelemetry.Lane? in
            guard let lane = lanes[provider] else { return nil }
            let receipt = lane.receipt
            let invocations = receipt?.localInvocationReceipts ?? []
            return .init(id: provider == .qwen ? "qwen" : "codex", provider: provider.name, state: lane.state.rawValue,
                phase: phase(of: lane), requestID: receipt.map { identifier($0.requestID) },
                contextCurrent: receipt.map { $0.context == context },
                requestStarted: receipt?.requestStarted ?? false,
                modelIdentity: receipt?.modelIdentity.map { text($0, limit: maximumModelIdentityBytes) },
                elapsedMilliseconds: receipt?.elapsedMilliseconds.map { max(0, $0) },
                invocations: invocations.prefix(maximumInvocationsPerLane).map {
                    .init(id: identifier($0.id), role: $0.role.rawValue, status: $0.outcome.rawValue)
                },
                omittedInvocationCount: max(0, invocations.count - maximumInvocationsPerLane),
                admission: receipt?.admissionOutcome.map {
                    .init(status: $0.status.rawValue, stage: $0.stage.rawValue, reason: $0.reason?.rawValue)
                })
        }
        // Prefer the latest actual decision over an older accepted report. A
        // rejected/cancelled attempt must never inherit a previous PASS display.
        let checks = peerLab.lastDecision?.checks
            ?? peerLab.inspection.candidate?.checks
            ?? peerLab.inspection.reports.last?.checks ?? []
        let simulation = peerLab.simulation.map {
            SeedTelemetry.Simulation(round: $0.round, workerCount: $0.peerIDs.count)
        }
        let peer = SeedTelemetry.Peer(
            progress: peerLab.inspection.currentAttempt?.progress.rawValue ?? "idle",
            attemptID: peerLab.inspection.currentAttempt.map { identifier($0.id) },
            candidateReady: peerLab.inspection.candidate != nil,
            acceptedReportCount: peerLab.inspection.reports.count,
            checks: checks.prefix(maximumChecks).map { .init(id: identifier($0.id), status: $0.status.rawValue) },
            omittedCheckCount: max(0, checks.count - maximumChecks), simulation: simulation)
        return .init(contextID: "context-" + digest(contextParts), telemetry: .init(
            memory: .init(keptLessonCount: max(0, keptLessonCount),
                temporaryRecordCount: max(0, temporaryRecordCount), graphNodeCount: graph.nodes.count,
                graphEdgeCount: graph.edges.count, truncatedCount: max(0, graph.truncatedCount)),
            harness: .init(state: isWorking ? "working" : "idle", lanes: currentLanes), peer: peer))
    }

    private static func phase(of lane: AssistantLaneResult) -> String {
        switch lane.state {
        case .complete: "Reply ready"
        case .failed: "Request failed"
        case .cancelled: "Request stopped"
        case .pending: lane.receipt?.requestStarted == true ? "Request in progress" : "Preparing request"
        }
    }

    private static func identifier(_ value: String) -> String {
        // Hash overlong IDs instead of retaining colliding truncated prefixes.
        value.utf8.count <= maximumIdentifierBytes ? value : "sha256:" + digest(value)
    }

    private static func text(_ value: String, limit: Int) -> String {
        guard value.utf8.count > limit else { return value }
        var bytes = Data(value.utf8.prefix(limit))
        while !bytes.isEmpty {
            if let prefix = String(data: bytes, encoding: .utf8) { return prefix }
            bytes.removeLast()
        }
        return ""
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
extension CompanionStore {
    /// Reads only current owner state. It never connects a provider, executes a
    /// worker, accepts a report, or saves a lesson.
    func seedTelemetrySnapshot(graph: CompanionGraphSnapshot) -> SeedTelemetrySnapshot {
        SeedTelemetryProjection.build(context: contextTicket(), lessonRevision: lessonRevision,
            graph: graph, keptLessonCount: keptLessons.count,
            temporaryRecordCount: hamptonSnapshot.records.filter {
                $0.createdTurn >= 0 && $0.createdTurn <= hamptonSnapshot.turn
                    && $0.expiresAtTurn > hamptonSnapshot.turn
            }.count,
            isWorking: isWorking, lanes: compareResults, peerLab: peerLab)
    }
}
