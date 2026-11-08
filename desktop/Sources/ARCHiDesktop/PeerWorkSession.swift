import Foundation

/// Deliberately excludes source text, node titles, prompts and model output.
struct PeerGraphNode: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let kind: String
    let status: String
}

struct PeerGraphEdge: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let sourceID: String
    let targetID: String
}

struct PeerInspectionInput: Codable, Equatable, Sendable {
    let graphID: String
    let sourceID: String
    let sourceDigest: String
    let contextDigest: String
    let nodes: [PeerGraphNode]
    let edges: [PeerGraphEdge]
    var truncatedCount: Int = 0
}

struct PeerWorkLimits: Equatable, Sendable {
    var maxNodes = 512
    var maxEdges = 1_024
    var maxInputBytes = 262_144
    var maxReports = 16
    var maxHistory = 96
    var maxPermitDuration: TimeInterval = 300

    var isValid: Bool {
        (1...4_096).contains(maxNodes) && (1...8_192).contains(maxEdges)
            && (256...2_097_152).contains(maxInputBytes) && (1...128).contains(maxReports)
            && (1...1_024).contains(maxHistory) && maxPermitDuration.isFinite
            && maxPermitDuration > 0 && maxPermitDuration <= 3_600
    }
}

struct PeerAttemptBinding: Codable, Equatable, Sendable {
    let sessionID: String
    let taskID: String
    let attemptID: String
    let epoch: UInt64
    let sourceID: String
    let sourceDigest: String
    let contextDigest: String
    let inputFingerprint: String
}

enum PeerTaskProgress: String, Codable, Sendable {
    case prepared, candidateReady, committed, damped, rejected, escalated, cancelled

    var isTerminal: Bool {
        switch self {
        case .prepared, .candidateReady: false
        case .committed, .damped, .rejected, .escalated, .cancelled: true
        }
    }
}

struct PeerWorkAttempt: Identifiable, Codable, Equatable, Sendable {
    let binding: PeerAttemptBinding
    let preparedAt: TimeInterval
    let permitExpiresAt: TimeInterval
    var progress: PeerTaskProgress

    var id: String { binding.attemptID }
    var epoch: UInt64 { binding.epoch }
    var sourceID: String { binding.sourceID }
    var sourceDigest: String { binding.sourceDigest }
    var contextDigest: String { binding.contextDigest }

    func permitIsValid(at now: TimeInterval) -> Bool {
        !progress.isTerminal && PeerFieldValidation.time(now, after: preparedAt) && now < permitExpiresAt
    }
}

struct PeerInspectionReport: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let binding: PeerAttemptBinding
    let inspectedAt: TimeInterval
    let graphID: String
    let nodeCount: Int
    let edgeCount: Int
    let unresolvedEdgeCount: Int
    let unresolvedEdgeIDs: [String]
    let duplicateNodeCount: Int
    let duplicateEdgeCount: Int
    let truncatedCount: Int
    let kindCounts: [String: Int]
    let statusCounts: [String: Int]
    let checks: [PeerCheckResult]

    var attemptID: String { binding.attemptID }
    var contextDigest: String { binding.contextDigest }
    var sourceDigest: String { binding.sourceDigest }
    var scopeDescription: String {
        if truncatedCount > 0 {
            return "Inspected the supplied projection only: \(nodeCount) nodes, \(edgeCount) edges; \(truncatedCount) items were omitted upstream. Unseen items were not checked."
        }
        return "Inspected only the supplied projection of \(nodeCount) nodes and \(edgeCount) edges. This verifies references and counts, not semantic truth or unseen project data."
    }
}

struct PeerAdmissionRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UInt64
    let attemptID: String?
    let epoch: UInt64?
    let decision: PeerDecision
    let detail: String
    let at: TimeInterval?
    let reportID: String?
    let checks: [PeerCheckResult]

}

enum PeerWorkError: Error, LocalizedError, Equatable, Sendable {
    case invalidTime, invalidConfiguration, invalidPermit, invalidInput, epochExhausted

    var errorDescription: String? {
        switch self {
        case .invalidTime: "Local monotonic time must be finite, nonnegative and nondecreasing."
        case .invalidConfiguration: "The read-only session has an invalid bounded configuration."
        case .invalidPermit: "The inspection permit duration is outside its bounded range."
        case .invalidInput: "The projection must have bounded IDs, kinds, statuses, edges and valid SHA-256 source/context digests."
        case .epochExhausted: "This session has exhausted its attempt sequence; start a new session."
        }
    }
}

enum PeerAdmissionPolicy {
    static func evaluate(_ checks: [PeerCheckResult]) -> PeerDecision {
        guard !checks.isEmpty, checks.contains(where: \.required),
              Set(checks.map(\.id)).count == checks.count else { return .escalate }
        if checks.contains(where: { $0.status == .fail }) { return .reject }
        if checks.contains(where: { $0.status == .skipped || $0.status == .error }) { return .escalate }
        return checks.allSatisfy { $0.status == .pass } ? .commit : .escalate
    }
}

/// A deterministic in-process worker. It receives only the explicitly provided
/// metadata projection and has no file, model, transport or editing capability.
enum PeerReadOnlyGraphInspector {
    static func inspect(input: PeerInspectionInput, binding: PeerAttemptBinding, now: TimeInterval) -> PeerInspectionReport {
        let nodeIDs = Set(input.nodes.map(\.id))
        let edgeIDs = Set(input.edges.map(\.id))
        let duplicateNodes = input.nodes.count - nodeIDs.count
        let duplicateEdges = input.edges.count - edgeIDs.count
        let unresolved = input.edges.filter { !nodeIDs.contains($0.sourceID) || !nodeIDs.contains($0.targetID) }.map(\.id).sorted()
        var kindCounts: [String: Int] = [:]
        var statusCounts: [String: Int] = [:]
        for node in input.nodes {
            kindCounts[node.kind, default: 0] += 1
            statusCounts[node.status, default: 0] += 1
        }
        let bound = input.sourceID == binding.sourceID && input.sourceDigest == binding.sourceDigest
            && input.contextDigest == binding.contextDigest && PeerCanonicalEncoding.fingerprint(input) == binding.inputFingerprint
        let checks: [PeerCheckResult] = [
            .init(id: "snapshot-binding", status: bound ? .pass : .fail,
                  detail: bound ? "The report is bound to the registered input, source and context." : "The supplied input does not match the registered attempt."),
            .init(id: "node-identifiers", status: duplicateNodes == 0 ? .pass : .fail,
                  detail: duplicateNodes == 0 ? "All \(input.nodes.count) supplied node IDs are unique." : "The supplied nodes contain \(duplicateNodes) duplicate IDs."),
            .init(id: "edge-identifiers", status: duplicateEdges == 0 ? .pass : .fail,
                  detail: duplicateEdges == 0 ? "All \(input.edges.count) supplied edge IDs are unique." : "The supplied edges contain \(duplicateEdges) duplicate IDs."),
            .init(id: "reference-integrity", status: duplicateNodes > 0 ? .skipped : unresolved.isEmpty ? .pass : .fail,
                  detail: duplicateNodes > 0 ? "Unique endpoint resolution was not checked because node IDs repeat."
                    : unresolved.isEmpty ? "Every supplied edge resolves to supplied node IDs." : "\(unresolved.count) supplied edges have missing endpoints."),
            .init(id: "inspection-scope", status: .pass,
                  detail: "Only the supplied projection was checked. Upstream omitted-item count: \(input.truncatedCount)."),
            .init(id: "read-only-operation", status: .pass,
                  detail: "The worker counted metadata and checked references in process; it has no edit or persistence operation.")
        ]
        return .init(id: "inspection-report-\(binding.epoch)", binding: binding, inspectedAt: now, graphID: input.graphID,
            nodeCount: input.nodes.count, edgeCount: input.edges.count, unresolvedEdgeCount: unresolved.count,
            unresolvedEdgeIDs: unresolved, duplicateNodeCount: duplicateNodes, duplicateEdgeCount: duplicateEdges,
            truncatedCount: input.truncatedCount, kindCounts: kindCounts, statusCounts: statusCounts, checks: checks)
    }
}

/// Explicit local authority for one inspection attempt at a time. Gossip is not
/// an input to this authority. COMMIT appends only to this session's report list.
struct PeerWorkSession: Sendable {
    let sessionID: String
    let limits: PeerWorkLimits
    private(set) var currentAttempt: PeerWorkAttempt?
    private(set) var candidate: PeerInspectionReport?
    private(set) var reports: [PeerInspectionReport] = []
    private(set) var history: [PeerAdmissionRecord] = []
    private(set) var lastError: String?
    private(set) var now: TimeInterval?
    private var registeredInput: PeerInspectionInput?
    private var epoch: UInt64 = 0
    private var historySequence: UInt64 = 0

    init(sessionID: String, limits: PeerWorkLimits = .init()) {
        self.sessionID = sessionID
        self.limits = limits
    }

    /// Calling prepare is explicit authorization for this one read-only input.
    /// It supersedes any unfinished attempt, and never runs the worker itself.
    @discardableResult
    mutating func prepare(input: PeerInspectionInput, now proposedTime: TimeInterval,
                          permitDuration: TimeInterval = 60) throws -> PeerWorkAttempt {
        guard PeerFieldValidation.time(proposedTime, after: now) else { throw refuse(.invalidTime) }
        now = proposedTime
        guard limits.isValid, PeerFieldValidation.identifier(sessionID) else { throw refuse(.invalidConfiguration) }
        guard permitDuration.isFinite, permitDuration > 0, permitDuration <= limits.maxPermitDuration,
              (proposedTime + permitDuration).isFinite else { throw refuse(.invalidPermit) }
        guard validInput(input), let fingerprint = PeerCanonicalEncoding.fingerprint(input) else { throw refuse(.invalidInput) }
        guard epoch < .max else { throw refuse(.epochExhausted) }
        if let previous = currentAttempt, !previous.progress.isTerminal {
            _ = append(.escalate, "A newly prepared attempt superseded the unfinished attempt.", at: proposedTime,
                attempt: previous, checks: candidate?.checks ?? [])
        }
        epoch += 1
        let binding = PeerAttemptBinding(sessionID: sessionID, taskID: "inspect-graph-projection",
            attemptID: "inspection-attempt-\(epoch)", epoch: epoch, sourceID: input.sourceID,
            sourceDigest: input.sourceDigest, contextDigest: input.contextDigest, inputFingerprint: fingerprint)
        let attempt = PeerWorkAttempt(binding: binding, preparedAt: proposedTime,
            permitExpiresAt: proposedTime + permitDuration, progress: .prepared)
        registeredInput = input
        currentAttempt = attempt
        candidate = nil
        lastError = nil
        return attempt
    }

    @discardableResult
    mutating func execute(now proposedTime: TimeInterval) -> PeerInspectionReport? {
        guard PeerFieldValidation.time(proposedTime, after: now) else {
            lastError = PeerWorkError.invalidTime.localizedDescription
            return nil
        }
        now = proposedTime
        guard var attempt = currentAttempt, !attempt.progress.isTerminal, let input = registeredInput else {
            lastError = "There is no active, locally authorized inspection attempt."
            return nil
        }
        guard attempt.permitIsValid(at: proposedTime) else {
            _ = finish(.escalate, "The local inspection permit expired before execution.", at: proposedTime, progress: .escalated)
            return nil
        }
        if let candidate {
            lastError = nil
            return candidate
        }
        let report = PeerReadOnlyGraphInspector.inspect(input: input, binding: attempt.binding, now: proposedTime)
        candidate = report
        attempt.progress = .candidateReady
        currentAttempt = attempt
        lastError = nil
        return report
    }

    /// Admission rechecks the current native owner's context and the exact locally
    /// produced report. This cannot apply an edit or authorize a remote peer.
    @discardableResult
    mutating func admit(currentContextDigest: String, now proposedTime: TimeInterval) -> PeerAdmissionRecord {
        guard PeerFieldValidation.time(proposedTime, after: now) else {
            lastError = PeerWorkError.invalidTime.localizedDescription
            return append(.escalate, PeerWorkError.invalidTime.localizedDescription, at: nil,
                attempt: currentAttempt, checks: [.init(id: "local-clock", status: .error, detail: "The local clock value is invalid.")])
        }
        now = proposedTime
        guard let attempt = currentAttempt else {
            return append(.escalate, "Prepare a local read-only attempt before admission.", at: proposedTime, attempt: nil)
        }
        guard !attempt.progress.isTerminal else {
            return append(.escalate, "This attempt is terminal; replay cannot admit another report.", at: proposedTime, attempt: attempt)
        }
        guard attempt.permitIsValid(at: proposedTime) else {
            return finish(.escalate, "The local inspection permit has expired.", at: proposedTime, progress: .escalated)
        }
        guard PeerFieldValidation.sha256Digest(currentContextDigest), currentContextDigest == attempt.contextDigest else {
            return finish(.escalate, "The native graph context changed; prepare a new inspection of the current projection.",
                at: proposedTime, progress: .escalated)
        }
        guard let input = registeredInput, let report = candidate, attempt.progress == .candidateReady else {
            return finish(.escalate, "The required worker checks have not run; no report was admitted.", at: proposedTime,
                progress: .escalated, checks: [.init(id: "worker-execution", status: .skipped, detail: "No candidate report is available.")])
        }
        guard report.binding == attempt.binding, input.sourceID == attempt.sourceID,
              input.sourceDigest == attempt.sourceDigest, input.contextDigest == attempt.contextDigest,
              PeerCanonicalEncoding.fingerprint(input) == attempt.binding.inputFingerprint,
              report.inspectedAt >= attempt.preparedAt, report.inspectedAt <= proposedTime,
              report.inspectedAt < attempt.permitExpiresAt,
              report == PeerReadOnlyGraphInspector.inspect(input: input, binding: attempt.binding, now: report.inspectedAt) else {
            return finish(.reject, "Candidate, source, attempt or evidence bindings do not match the registered inspection.",
                at: proposedTime, progress: .rejected,
                checks: [.init(id: "admission-binding", status: .fail, detail: "Exact registered bindings did not match.")])
        }
        let decision = PeerAdmissionPolicy.evaluate(report.checks)
        switch decision {
        case .commit:
            reports.append(report)
            if reports.count > limits.maxReports { reports.removeFirst(reports.count - limits.maxReports) }
            return finish(.commit, "All required checks passed for the current projection. Its report was added to this session only.",
                at: proposedTime, progress: .committed, checks: report.checks, reportID: report.id)
        case .reject:
            return finish(.reject, "A required inspection check failed; no report was admitted.", at: proposedTime,
                progress: .rejected, checks: report.checks)
        case .escalate:
            return finish(.escalate, "A check was skipped or could not complete; prepare a new valid inspection before admission.",
                at: proposedTime, progress: .escalated, checks: report.checks)
        case .damp:
            return finish(.damp, "The candidate was held without admission.", at: proposedTime, progress: .damped, checks: report.checks)
        }
    }

    /// An explicit hold is distinct from failure and does not append a report.
    @discardableResult
    mutating func damp(now proposedTime: TimeInterval) -> PeerAdmissionRecord? {
        guard PeerFieldValidation.time(proposedTime, after: now),
              let attempt = currentAttempt, !attempt.progress.isTerminal, candidate != nil else { return nil }
        now = proposedTime
        guard attempt.permitIsValid(at: proposedTime) else {
            return finish(.escalate, "The local inspection permit expired before the candidate was held.", at: proposedTime, progress: .escalated)
        }
        return finish(.damp, "The candidate was held without admission. A new attempt is required to reconsider it.", at: proposedTime, progress: .damped)
    }

    /// Cancelling idle or terminal work is deliberately a no-op, including history.
    @discardableResult
    mutating func cancel(now proposedTime: TimeInterval) -> PeerAdmissionRecord? {
        guard let attempt = currentAttempt, !attempt.progress.isTerminal else { return nil }
        guard PeerFieldValidation.time(proposedTime, after: now) else {
            return finish(.escalate, "The local inspection was cancelled while its clock was invalid; its candidate cannot be admitted.",
                at: nil, progress: .cancelled,
                checks: [.init(id: "local-clock", status: .error, detail: "Cancellation fenced the attempt without accepting an invalid timestamp.")])
        }
        now = proposedTime
        return finish(.escalate, "The local inspection attempt was cancelled; its candidate cannot be admitted.", at: proposedTime, progress: .cancelled)
    }

    private func validInput(_ input: PeerInspectionInput) -> Bool {
        guard PeerFieldValidation.identifier(input.graphID), PeerFieldValidation.identifier(input.sourceID),
              PeerFieldValidation.sha256Digest(input.sourceDigest), PeerFieldValidation.sha256Digest(input.contextDigest),
              input.truncatedCount >= 0, input.nodes.count <= limits.maxNodes, input.edges.count <= limits.maxEdges,
              input.nodes.allSatisfy({ [ $0.id, $0.kind, $0.status ].allSatisfy(PeerFieldValidation.identifier) }),
              input.edges.allSatisfy({ [ $0.id, $0.sourceID, $0.targetID ].allSatisfy(PeerFieldValidation.identifier) }),
              let bytes = PeerCanonicalEncoding.data(input), bytes.count <= limits.maxInputBytes else { return false }
        return true
    }

    private mutating func refuse(_ error: PeerWorkError) -> PeerWorkError {
        lastError = error.localizedDescription
        return error
    }

    private mutating func finish(_ decision: PeerDecision, _ detail: String, at time: TimeInterval?,
                                 progress: PeerTaskProgress, checks: [PeerCheckResult]? = nil,
                                 reportID: String? = nil) -> PeerAdmissionRecord {
        let checks = checks ?? candidate?.checks ?? []
        let attempt = currentAttempt
        currentAttempt?.progress = progress
        candidate = nil
        registeredInput = nil
        lastError = decision == .commit || decision == .damp ? nil : detail
        return append(decision, detail, at: time, attempt: attempt, checks: checks, reportID: reportID)
    }

    private mutating func append(_ decision: PeerDecision, _ detail: String, at time: TimeInterval?,
                                 attempt: PeerWorkAttempt?, checks: [PeerCheckResult] = [], reportID: String? = nil) -> PeerAdmissionRecord {
        if historySequence < .max { historySequence += 1 }
        let record = PeerAdmissionRecord(id: historySequence, attemptID: attempt?.id, epoch: attempt?.epoch,
            decision: decision, detail: detail, at: time, reportID: reportID, checks: checks)
        history.append(record)
        let maximum = min(1_024, max(1, limits.maxHistory))
        if history.count > maximum { history.removeFirst(history.count - maximum) }
        return record
    }
}
