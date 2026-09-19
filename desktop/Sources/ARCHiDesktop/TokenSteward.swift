import Foundation
import Combine
import Darwin

enum TokenStewardError: Error, LocalizedError, Equatable {
    case unavailable(String), invalid(String), conflict(String), missingTask, budgetUnset, unresolvedCharges, budgetExceeded

    var errorDescription: String? {
        switch self {
        case .unavailable(let detail): "Token Steward could not retain accounting: \(detail)"
        case .invalid(let detail): "Token Steward rejected \(detail)."
        case .conflict(let detail): "Token Steward found conflicting \(detail). Existing evidence was preserved."
        case .missingTask: "Token Steward requires an application task before dispatch."
        case .budgetUnset: "Set an explicit API budget before a paid request. Local and subscription routes remain separate."
        case .unresolvedCharges: "An earlier API charge is unresolved. Reconcile it before reserving more spending."
        case .budgetExceeded: "This API reservation would exceed the configured budget."
        }
    }
}

/// User-declared ceilings only. No default price, plan entitlement or allowance.
struct TokenStewardBudget: Codable, Equatable, Sendable {
    let dailyNanoUSD: Int64
    let monthlyNanoUSD: Int64
    let timeZoneID: String
}

enum TokenStewardResource: String, Codable, Sendable { case localInference, subscription, api }

/// Immutable transport observation. Billing enrichment lives in a separate log.
/// Counts are inclusive: cache counts are subsets of input, reasoning of output.
/// This journal retains identifiers and measurements, never prompts or replies.
struct TokenStewardObservation: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let taskID: String
    let provider: String
    let accountID: String
    let resource: TokenStewardResource
    let observedAt: Date
    let model: String?
    let role: String?
    let outcome: String
    let inputDigest: String?
    let inputTokens: Int64?
    let outputTokens: Int64?
    let cacheReadTokens: Int64?
    let cacheWriteTokens: Int64?
    let reasoningTokens: Int64?
    let elapsedMilliseconds: Int64?

    init(id: String, taskID: String, provider: String, accountID: String = "native",
         resource: TokenStewardResource, observedAt: Date, model: String? = nil,
         role: String? = nil, outcome: String, inputDigest: String? = nil,
         inputTokens: Int64? = nil, outputTokens: Int64? = nil,
         cacheReadTokens: Int64? = nil, cacheWriteTokens: Int64? = nil,
         reasoningTokens: Int64? = nil, elapsedMilliseconds: Int64? = nil) {
        self.id = id; self.taskID = taskID; self.provider = provider; self.accountID = accountID
        self.resource = resource; self.observedAt = observedAt; self.model = model; self.role = role
        self.outcome = outcome; self.inputDigest = inputDigest; self.inputTokens = inputTokens
        self.outputTokens = outputTokens; self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens; self.reasoningTokens = reasoningTokens
        self.elapsedMilliseconds = elapsedMilliseconds
    }
}

struct TokenStewardLane: Codable, Equatable, Identifiable, Sendable {
    var id: String { provider }
    let provider: String
    var dispatched = false
    var state = "pending"
    var admission: String? = nil
    var elapsedMilliseconds: Int? = nil
    /// False means a crash or older receipt did not provide individual attempts.
    var localAttemptsMeasured = false
}

struct TokenStewardOutcome: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case userUseful, checked }
    let revision: Int
    let kind: Kind
    let value: Bool
    let evidenceID: String
    let recordedAt: Date
}

struct TokenStewardTask: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let route: String
    let startedAt: Date
    var lanes: [TokenStewardLane]
    var outcomes: [TokenStewardOutcome] = []
    /// Optional additions keep legacy tasks readable without inventing reading evidence.
    var documentReading: DocumentReadingTrace? = nil
    var documentReadingResult: DocumentReadingResult? = nil
    var isClosed: Bool { !lanes.isEmpty && lanes.allSatisfy { $0.state != "pending" } }
    var delivered: Bool { lanes.contains { $0.state == "complete" } }
    var userUseful: Bool { outcomes.last { $0.kind == .userUseful }?.value == true }
    var checkedSuccessful: Bool { outcomes.last { $0.kind == .checked }?.value == true }
    var elapsedMilliseconds: Int? { lanes.compactMap(\.elapsedMilliseconds).max() }
}

struct TokenStewardReservation: Codable, Equatable, Identifiable, Sendable {
    enum State: String, Codable, Sendable { case reserved, sent, settled, released }
    let id: String
    let taskID: String
    let provider: String
    let accountID: String
    let maximumNanoUSD: Int64
    let reservedAt: Date
    var state: State = .reserved
    var observationID: String? = nil
    var isActive: Bool { state == .reserved || state == .sent }
}

struct TokenStewardBillingFact: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case estimate, finalCharge }
    let observationID: String
    let sourceID: String
    let kind: Kind
    let amountNanoUSD: Int64
    let recordedAt: Date
}

struct TokenStewardSummary: Equatable {
    var accountingAvailable = true
    var taskCount = 0
    var openTaskCount = 0
    var deliveredTaskCount = 0
    var usefulTaskCount = 0
    var checkedSuccessfulTaskCount = 0
    var evaluationTaskCount = 0
    var interactiveSessionCount = 0
    var syntheticCheckedTaskCount = 0
    var localAttemptCount = 0
    var unmeasuredLocalLaneCount = 0
    var subscriptionRequestCount = 0
    var inputTokens: Int64? = nil
    var outputTokens: Int64? = nil
    var knownInputTokens: Int64 = 0
    var knownOutputTokens: Int64 = 0
    var missingInputCount = 0
    var missingOutputCount = 0
    var knownAPIChargeNanoUSD: Int64 = 0
    var estimatedAPIChargeNanoUSD: Int64 = 0
    var reservedNanoUSD: Int64 = 0
    /// All-time count, deliberately independent of any monthly display filter.
    var unresolvedAPIObservationCount = 0
    /// Lifetime API cost of closed API tasks / user-useful closed API tasks.
    /// Nil while any closed API task charge is unresolved or denominator is zero.
    var apiCostPerUsefulTaskNanoUSD: Int64? = nil
    var closedAPITaskCount = 0
    var usefulClosedAPITaskCount = 0
    var closedAPITaskChargeNanoUSD: Int64? = nil
}

/// One serialized, durable journal. Every write reloads while holding an advisory
/// process lock, validates, writes atomically, then updates published presentation.
/// A bad/unreadable journal is never silently replaced with an empty budget.
@MainActor
final class TokenStewardStore: ObservableObject {
    private struct Journal: Codable, Equatable {
        var schema = "archi-token-steward/v1"
        var revision = 0
        var budget: TokenStewardBudget? = nil
        var tasks: [TokenStewardTask] = []
        var observations: [TokenStewardObservation] = []
        var reservations: [TokenStewardReservation] = []
        var billing: [TokenStewardBillingFact] = []
    }

    private let url: URL?
    private let now: () -> Date
    private var journal = Journal()
    private var cachedSummary: TokenStewardSummary? = nil
    @Published private(set) var loadError: String? = nil
    @Published private(set) var revision = 0

    var budget: TokenStewardBudget? { journal.budget }
    var tasks: [TokenStewardTask] { journal.tasks.sorted { $0.startedAt > $1.startedAt } }
    var observations: [TokenStewardObservation] { journal.observations }
    var reservations: [TokenStewardReservation] { journal.reservations }
    var billingFacts: [TokenStewardBillingFact] { journal.billing }
    var unresolvedObservations: [TokenStewardObservation] {
        journal.observations.filter { $0.resource == .api && Self.finalCharge($0.id, in: journal) == nil }
    }

    init(url: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.url = url; self.now = now
        do { try refresh() } catch { loadError = error.localizedDescription }
    }

    func refresh() throws {
        do {
            // Writers atomically replace complete journals. Reading that snapshot
            // needs no writer lock and must not create a profile directory or
            // lock file merely because the app was opened.
            journal = try readJournal()
            cachedSummary = nil
            revision = journal.revision
            loadError = nil
        } catch { loadError = error.localizedDescription; throw error }
    }

    func preflight(requestID: String, route: AssistantRoute) throws {
        let date = now()
        try transaction { state in
            try Self.registerTask(id: requestID, route: route.rawValue,
                providers: route.providers.map(\.name), date: date, in: &state)
        }
    }

    /// Retain the frozen reading decision before Qwen dispatch. Replaying an
    /// identical retained trace is harmless; a changed trace or first late write
    /// fails without replacing the existing task's provenance.
    func recordDocumentReading(requestID: String, trace: DocumentReadingTrace) throws {
        try transaction { state in
            guard trace.isValid else { throw TokenStewardError.invalid("document reading trace") }
            guard let index = state.tasks.firstIndex(where: { $0.id == requestID }) else {
                throw TokenStewardError.missingTask
            }
            let task = state.tasks[index]
            guard Self.permitsDocumentReading(task),
                  let lane = task.lanes.first(where: { $0.provider == AssistantProvider.qwen.name }) else {
                throw TokenStewardError.invalid("document reading route")
            }
            if let existing = task.documentReading {
                guard existing == trace else { throw TokenStewardError.conflict("immutable document reading trace") }
                return
            }
            guard lane.state == "pending", !lane.dispatched else {
                throw TokenStewardError.conflict("document reading trace after Qwen dispatch")
            }
            state.tasks[index].documentReading = trace
        }
    }

    /// Bind the returned result while Qwen is dispatched and still pending in
    /// this journal, before the owning lane receipt makes it terminal.
    func recordDocumentReadingResult(requestID: String, result: DocumentReadingResult) throws {
        try transaction { state in
            guard let index = state.tasks.firstIndex(where: { $0.id == requestID }) else {
                throw TokenStewardError.missingTask
            }
            let task = state.tasks[index]
            guard Self.permitsDocumentReading(task), let trace = task.documentReading,
                  result.isValid(for: trace),
                  let lane = task.lanes.first(where: { $0.provider == AssistantProvider.qwen.name }) else {
                throw TokenStewardError.invalid("document reading result provenance")
            }
            if let existing = task.documentReadingResult {
                guard existing == result else { throw TokenStewardError.conflict("immutable document reading result") }
                return
            }
            guard lane.state == "pending", lane.dispatched else {
                throw TokenStewardError.conflict("document reading result outside the pending Qwen dispatch")
            }
            state.tasks[index].documentReadingResult = result
        }
    }

    /// Explicit review of this retained Qwen answer. Unknown, failed, cloud-only,
    /// clarification and abstention outcomes never become strategy corrections.
    /// Repeated verdicts are idempotent; a reversal gets its own evidence event.
    func recordDocumentReadingFeedback(requestID: String, useful: Bool) throws {
        let date = now()
        try transaction { state in
            guard let index = state.tasks.firstIndex(where: { $0.id == requestID }) else {
                throw TokenStewardError.missingTask
            }
            let task = state.tasks[index]
            guard Self.permitsDocumentReadingFeedback(task) else {
                throw TokenStewardError.invalid("document reading feedback without a completed Qwen answer")
            }
            if let previous = task.outcomes.last(where: {
                $0.kind == .userUseful && $0.evidenceID.hasPrefix(DocumentReadingTrace.feedbackEvidencePrefix)
            }), previous.value == useful { return }
            state.tasks[index].outcomes.append(TokenStewardOutcome(revision: state.revision + 1,
                kind: .userUseful, value: useful,
                evidenceID: DocumentReadingTrace.feedbackEvidencePrefix + UUID().uuidString,
                recordedAt: date))
        }
    }

    /// A native request earns at most one external fallback lane after its
    /// local lane has failed. Local success never leaves an unused cloud lane.
    /// Admission alone is not dispatch; persist dispatch before entering Codex.
    func registerFallback(requestID: String) throws {
        try transaction { state in
            guard let task = state.tasks.firstIndex(where: { $0.id == requestID }) else {
                throw TokenStewardError.missingTask
            }
            guard state.tasks[task].route == "native",
                  state.tasks[task].lanes.first(where: { $0.provider == AssistantProvider.qwen.name })?.state == "failed" else {
                throw TokenStewardError.conflict("fallback requires a failed native local lane")
            }
            if let existing = state.tasks[task].lanes.first(where: { $0.provider == AssistantProvider.codex.name }) {
                guard existing.state == "pending", !existing.dispatched else {
                    throw TokenStewardError.conflict("fallback already attempted")
                }
                return
            }
            state.tasks[task].lanes.append(TokenStewardLane(provider: AssistantProvider.codex.name))
        }
    }

    /// Persist before reply entry; this is a lane dispatch, not a local generate
    /// count or proof of HTTP acceptance. A crash leaves a visible open task.
    func recordDispatch(requestID: String, provider: AssistantProvider) throws {
        try transaction { state in
            guard let task = state.tasks.firstIndex(where: { $0.id == requestID }),
                  let lane = state.tasks[task].lanes.firstIndex(where: { $0.provider == provider.name })
            else { throw TokenStewardError.missingTask }
            guard state.tasks[task].lanes[lane].state == "pending" else {
                throw TokenStewardError.conflict("dispatch after a terminal lane")
            }
            state.tasks[task].lanes[lane].dispatched = true
        }
    }

    /// Import only the owner-finalized lane. Live previews are not immutable
    /// transport evidence. Replay is idempotent; changed terminal evidence fails.
    func recordLane(_ receipt: AssistantLaneReceipt) throws {
        guard receipt.state != .pending else { return }
        let date = now()
        try transaction { state in
            if receipt.route.rawValue == "native" {
                if let task = state.tasks.first(where: { $0.id == receipt.requestID }) {
                    guard task.route == "native" else { throw TokenStewardError.conflict("application task identity") }
                } else {
                    guard receipt.provider == .qwen else { throw TokenStewardError.missingTask }
                    try Self.registerTask(id: receipt.requestID, route: "native",
                        providers: [AssistantProvider.qwen.name], date: date, in: &state)
                }
            } else {
                try Self.registerTask(id: receipt.requestID, route: receipt.route.rawValue,
                    providers: receipt.route.providers.map(\.name), date: date, in: &state)
            }
            guard let taskIndex = state.tasks.firstIndex(where: { $0.id == receipt.requestID }),
                  let laneIndex = state.tasks[taskIndex].lanes.firstIndex(where: { $0.provider == receipt.provider.name }) else {
                throw TokenStewardError.missingTask
            }
            let oldLane = state.tasks[taskIndex].lanes[laneIndex]
            let measured = receipt.localInvocationReceipts != nil
            let lane = TokenStewardLane(provider: receipt.provider.name,
                dispatched: receipt.requestStarted || oldLane.dispatched,
                state: receipt.state.rawValue, admission: receipt.admissionOutcome?.status.rawValue,
                elapsedMilliseconds: receipt.elapsedMilliseconds, localAttemptsMeasured: measured)
            guard oldLane.state == "pending" || oldLane == lane else {
                throw TokenStewardError.conflict("terminal lane outcome")
            }
            // Stable application-owned start time makes receipt replay independent
            // of import time and preserves task lifecycle accounting across months.
            let observedAt = state.tasks[taskIndex].startedAt
            if receipt.provider == .qwen {
                for invocation in receipt.localInvocationReceipts ?? [] {
                    let metrics = invocation.metrics
                    let observation = TokenStewardObservation(
                        id: Self.nativeObservationID(receipt.requestID, receipt.provider.name, invocation.id),
                        taskID: receipt.requestID, provider: receipt.provider.name,
                        resource: .localInference, observedAt: observedAt,
                        model: invocation.model?.name ?? receipt.modelIdentity, role: invocation.role.rawValue,
                        outcome: invocation.outcome.rawValue, inputDigest: invocation.inputDigest,
                        inputTokens: metrics?.inputTokens.flatMap(Int64.init(exactly:)),
                        outputTokens: metrics?.outputTokens.flatMap(Int64.init(exactly:)),
                        elapsedMilliseconds: invocation.elapsedMilliseconds.flatMap(Int64.init(exactly:)))
                    try Self.importObservation(observation, into: &state)
                }
            } else if lane.dispatched {
                try Self.importObservation(TokenStewardObservation(
                    id: Self.nativeObservationID(receipt.requestID, receipt.provider.name, "request"),
                    taskID: receipt.requestID, provider: receipt.provider.name,
                    resource: .subscription, observedAt: observedAt, model: receipt.modelIdentity,
                    outcome: receipt.state.rawValue, inputDigest: receipt.inputDigest,
                    elapsedMilliseconds: receipt.elapsedMilliseconds.flatMap(Int64.init(exactly:))), into: &state)
            }
            state.tasks[taskIndex].lanes[laneIndex] = lane
        }
    }

    func recordUseful(requestID: String) throws {
        try recordOutcome(requestID: requestID, kind: .userUseful, value: true, evidenceID: "explicit-user-feedback")
    }

    /// One stable explicit review event. Reversals use a new event ID; retries
    /// reuse it. This remains user judgment, never a checker result.
    func recordUserFeedback(requestID: String, evidenceID: String, useful: Bool) throws {
        try recordOutcome(requestID: requestID, kind: .userUseful, value: useful, evidenceID: evidenceID)
    }

    /// Evidence must come from the caller's independent checker; this function
    /// records its provenance and never grants a capability or evolution state.
    func recordChecked(requestID: String, evidenceID: String, passed: Bool) throws {
        try recordOutcome(requestID: requestID, kind: .checked, value: passed, evidenceID: evidenceID)
    }

    /// Evaluation does not grant useful-answer or capability state. A local Qwen
    /// proposal additionally records its one observed inference, without billing.
    func recordEvaluation(taskID: String, evidenceID: String?, passed: Bool?,
                          startedAt: Date, finishedAt: Date, sourceStatus: String?, error: String?,
                          localSolver: Bool = false, cancelled: Bool = false,
                          proposalInference: ARCQwenProposalInference? = nil, proposalInProgress: Bool = false) throws {
        guard startedAt.timeIntervalSince1970.isFinite, finishedAt.timeIntervalSince1970.isFinite,
              finishedAt >= startedAt, finishedAt.timeIntervalSince(startedAt) <= Double(Int.max / 1000)
        else { throw TokenStewardError.invalid("evaluation duration") }
        guard !cancelled || (evidenceID == nil && passed == nil) else { throw TokenStewardError.invalid("cancelled evaluation evidence") }
        guard !(localSolver && proposalInference != nil),
              !proposalInProgress || (proposalInference != nil && evidenceID == nil && passed == nil && error == nil && !cancelled)
        else { throw TokenStewardError.invalid("proposal evaluation phase") }
        if let inference = proposalInference {
            guard QwenAssistant.supportedModels.contains(inference.model),
                  ["not-started", "dispatched", "complete", "failed", "cancelled"].contains(inference.outcome),
                  inference.inputTokens.map({ $0 >= 0 }) != false,
                  inference.outputTokens.map({ $0 >= 0 }) != false,
                  inference.elapsedMilliseconds.map({ $0 >= 0 }) != false,
                  inference.attempted || (inference.inputTokens == nil && inference.outputTokens == nil && inference.elapsedMilliseconds == nil)
            else { throw TokenStewardError.invalid("local proposal observation") }
        }
        let provider = proposalInference != nil ? ARCQwenProposalInference.provider
            : (localSolver ? "ARC local symbolic solver + checker" : "ARC deterministic checker")
        try transaction { state in
            try Self.registerTask(id: taskID, route: "arc-evaluation", providers: [provider], date: startedAt, in: &state)
            let index = state.tasks.firstIndex { $0.id == taskID }!
            let oldLane = state.tasks[index].lanes[0]
            let lane = TokenStewardLane(provider: provider,
                dispatched: proposalInference?.attempted ?? true,
                state: proposalInProgress ? "pending" : (cancelled ? "cancelled" : (error == nil && passed != nil ? "complete" : "failed")),
                admission: sourceStatus,
                elapsedMilliseconds: proposalInProgress ? nil : Int(finishedAt.timeIntervalSince(startedAt) * 1000),
                localAttemptsMeasured: proposalInference != nil && !proposalInProgress)
            guard state.tasks[index].startedAt == startedAt,
                  !oldLane.dispatched || lane.dispatched,
                  oldLane.state == "pending" || oldLane == lane
            else { throw TokenStewardError.conflict("evaluation receipt") }
            if !proposalInProgress, let inference = proposalInference, inference.attempted {
                try Self.importObservation(TokenStewardObservation(
                    id: Self.nativeObservationID(taskID, provider, "proposal"), taskID: taskID, provider: provider,
                    resource: .localInference, observedAt: startedAt,
                    model: inference.model, role: "ARC_PROPOSAL", outcome: inference.outcome,
                    inputDigest: inference.inputDigest,
                    inputTokens: inference.inputTokens.flatMap(Int64.init(exactly:)),
                    outputTokens: inference.outputTokens.flatMap(Int64.init(exactly:)),
                    elapsedMilliseconds: inference.elapsedMilliseconds.flatMap(Int64.init(exactly:))), into: &state)
            }
            state.tasks[index].lanes[0] = lane
            if !proposalInProgress, error == nil, let passed, let evidenceID {
                try Self.validateID(evidenceID)
                if let old = state.tasks[index].outcomes.first(where: { $0.kind == .checked }) {
                    guard old.evidenceID == evidenceID, old.value == passed else { throw TokenStewardError.conflict("evaluation evidence") }
                } else {
                    state.tasks[index].outcomes.append(TokenStewardOutcome(revision: state.revision + 1,
                        kind: .checked, value: passed, evidenceID: evidenceID, recordedAt: finishedAt))
                }
            }
        }
    }

    /// Interactive environment execution is neither an assistant answer nor an
    /// exact static-grid evaluation. No model use, billing or useful-work award.
    func recordInteractiveARC(_ summary: ARC3SessionSummary) throws {
        let outcomes = ["complete", "budget-exhausted", "stopped", "failed", "profile-reset"]
        guard summary.startedAt.timeIntervalSince1970.isFinite,
              summary.finishedAt.timeIntervalSince1970.isFinite,
              summary.finishedAt >= summary.startedAt,
              summary.finishedAt.timeIntervalSince(summary.startedAt) < Double(Int.max / 1000),
              (0...64).contains(summary.dispatches), (0...64).contains(summary.attemptedDispatches),
              (0...summary.attemptedDispatches).contains(summary.unreconciledDispatches), outcomes.contains(summary.outcome)
        else { throw TokenStewardError.invalid("interactive ARC episode") }
        try Self.validateID(summary.gameID)
        let provider = "ARC3 offline environment"
        let lane = TokenStewardLane(provider: provider, dispatched: summary.dispatches > 0 || summary.attemptedDispatches > 0,
            state: summary.outcome == "failed" ? "failed" : (["stopped", "profile-reset"].contains(summary.outcome) ? "cancelled" : "complete"),
            admission: "\(summary.outcome) · \(summary.dispatches) confirmed · \(summary.attemptedDispatches) attempted · \(summary.unreconciledDispatches) uncertain · \(summary.lastState ?? "unknown")",
            elapsedMilliseconds: Int(summary.finishedAt.timeIntervalSince(summary.startedAt) * 1000))
        try transaction { state in
            try Self.registerTask(id: summary.sessionID, route: "arc-interactive", providers: [provider], date: summary.startedAt, in: &state)
            let index = state.tasks.firstIndex { $0.id == summary.sessionID }!
            let old = state.tasks[index].lanes[0]
            guard state.tasks[index].startedAt == summary.startedAt,
                  old.state == "pending" || old == lane else { throw TokenStewardError.conflict("interactive ARC receipt") }
            state.tasks[index].lanes[0] = lane
        }
    }

    private func recordOutcome(requestID: String, kind: TokenStewardOutcome.Kind, value: Bool, evidenceID: String) throws {
        let date = now()
        try transaction { state in
            try Self.validateID(evidenceID)
            guard !evidenceID.hasPrefix(DocumentReadingTrace.feedbackEvidencePrefix) else {
                throw TokenStewardError.invalid("reserved document reading feedback identity")
            }
            guard let index = state.tasks.firstIndex(where: { $0.id == requestID }) else { throw TokenStewardError.missingTask }
            guard !["arc-evaluation", "arc-interactive"].contains(state.tasks[index].route) else { throw TokenStewardError.invalid("assistance outcome on a synthetic evaluation") }
            if kind == .userUseful && !state.tasks[index].delivered { throw TokenStewardError.invalid("usefulness without a delivered answer") }
            if let old = state.tasks[index].outcomes.last(where: { $0.kind == kind }),
               old.evidenceID == evidenceID, old.value == value { return }
            if state.tasks[index].outcomes.contains(where: { $0.kind == kind && $0.evidenceID == evidenceID }) {
                throw TokenStewardError.conflict("outcome evidence")
            }
            state.tasks[index].outcomes.append(TokenStewardOutcome(revision: state.revision + 1,
                kind: kind, value: value, evidenceID: evidenceID, recordedAt: date))
        }
    }

    func configureBudget(_ budget: TokenStewardBudget?) throws {
        if let budget {
            guard budget.dailyNanoUSD >= 0, budget.monthlyNanoUSD >= 0,
                  budget.dailyNanoUSD <= budget.monthlyNanoUSD, TimeZone(identifier: budget.timeZoneID) != nil
            else { throw TokenStewardError.invalid("API ceilings or timezone") }
        }
        try transaction { $0.budget = budget }
    }

    /// Adapter seam for a future paid transport. Existing local/subscription
    /// preflight does not call this or invent an API charge.
    func reserveAPI(taskID: String, reservationID: String, maximumNanoUSD: Int64,
                    provider: String, accountID: String) throws {
        let date = now()
        try transaction { state in
            try Self.validateID(reservationID); try Self.validateID(provider); try Self.validateID(accountID)
            guard maximumNanoUSD > 0 else { throw TokenStewardError.invalid("API maximum") }
            guard state.tasks.first(where: { $0.id == taskID })?.isClosed != true else {
                throw TokenStewardError.conflict("reservation after final task outcome")
            }
            if let existing = state.reservations.first(where: { $0.id == reservationID }) {
                guard existing.taskID == taskID, existing.maximumNanoUSD == maximumNanoUSD,
                      existing.provider == provider, existing.accountID == accountID, existing.state == .reserved
                else { throw TokenStewardError.conflict("reservation identity or replay after dispatch") }
                return
            }
            guard let budget = state.budget else { throw TokenStewardError.budgetUnset }
            guard !state.observations.contains(where: { $0.resource == .api && Self.finalCharge($0.id, in: state) == nil })
            else { throw TokenStewardError.unresolvedCharges }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: budget.timeZoneID)!
            let activeHolds = try Self.sum(state.reservations.filter(\.isActive).map(\.maximumNanoUSD))
            let daily = try Self.charges(in: .day, at: date, calendar: calendar, state: state)
            let monthly = try Self.charges(in: .month, at: date, calendar: calendar, state: state)
            guard try Self.sum([daily, activeHolds, maximumNanoUSD]) <= budget.dailyNanoUSD,
                  try Self.sum([monthly, activeHolds, maximumNanoUSD]) <= budget.monthlyNanoUSD
            else { throw TokenStewardError.budgetExceeded }
            if let index = state.tasks.firstIndex(where: { $0.id == taskID }) {
                guard state.tasks[index].route == "api" else { throw TokenStewardError.conflict("API task route") }
                if !state.tasks[index].lanes.contains(where: { $0.provider == provider }) {
                    state.tasks[index].lanes.append(TokenStewardLane(provider: provider))
                }
            } else {
                try Self.registerTask(id: taskID, route: "api", providers: [provider], date: date, in: &state)
            }
            state.reservations.append(TokenStewardReservation(id: reservationID, taskID: taskID,
                provider: provider, accountID: accountID, maximumNanoUSD: maximumNanoUSD, reservedAt: date))
        }
    }

    /// Must commit immediately before entering the transport. On uncertainty or
    /// cancellation after this call the hold remains; Stop is not billing proof.
    func markAPISent(reservationID: String) throws {
        let date = now()
        try transaction { state in
            guard let index = state.reservations.firstIndex(where: { $0.id == reservationID }) else { throw TokenStewardError.invalid("unknown reservation") }
            guard state.reservations[index].state == .reserved
            else { throw TokenStewardError.conflict("repeated or closed reservation dispatch") }
            if state.reservations[index].state == .reserved {
                guard let budget = state.budget else { throw TokenStewardError.budgetUnset }
                guard !state.observations.contains(where: { $0.resource == .api && Self.finalCharge($0.id, in: state) == nil })
                else { throw TokenStewardError.unresolvedCharges }
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: budget.timeZoneID)!
                let holds = try Self.sum(state.reservations.filter(\.isActive).map(\.maximumNanoUSD))
                guard try Self.sum([Self.charges(in: .day, at: date, calendar: calendar, state: state), holds]) <= budget.dailyNanoUSD,
                      try Self.sum([Self.charges(in: .month, at: date, calendar: calendar, state: state), holds]) <= budget.monthlyNanoUSD
                else { throw TokenStewardError.budgetExceeded }
            }
            state.reservations[index].state = .sent
            if let task = state.tasks.firstIndex(where: { $0.id == state.reservations[index].taskID }),
               let lane = state.tasks[task].lanes.firstIndex(where: { $0.provider == state.reservations[index].provider }) {
                state.tasks[task].lanes[lane].dispatched = true
            }
        }
    }

    /// Only the never-dispatched reservation state proves an unsent cancellation.
    func cancelUnsent(reservationID: String) throws {
        try transaction { state in
            guard let index = state.reservations.firstIndex(where: { $0.id == reservationID }) else { throw TokenStewardError.invalid("unknown reservation") }
            if state.reservations[index].state == .released { return }
            guard state.reservations[index].state == .reserved else { throw TokenStewardError.conflict("release after transport dispatch") }
            state.reservations[index].state = .released
        }
    }

    /// Atomic observation + optional final charge + reservation transition. A
    /// partial/unknown charge never releases the hold. Actual charges above the
    /// declared maximum are retained truthfully and reduce future affordability.
    func settleAPI(observation: TokenStewardObservation, reservationID: String,
                   finalChargeNanoUSD: Int64? = nil, sourceID: String? = nil) throws {
        let date = now()
        try transaction { state in
            guard let index = state.reservations.firstIndex(where: { $0.id == reservationID }) else { throw TokenStewardError.invalid("unknown reservation") }
            let reservation = state.reservations[index]
            guard reservation.state == .sent || reservation.state == .settled,
                  observation.resource == .api, observation.taskID == reservation.taskID,
                  observation.provider == reservation.provider, observation.accountID == reservation.accountID,
                  reservation.observationID == nil || reservation.observationID == observation.id,
                  !state.reservations.contains(where: { $0.id != reservationID && $0.observationID == observation.id })
            else { throw TokenStewardError.conflict("reservation settlement") }
            try Self.importObservation(observation, into: &state)
            state.reservations[index].observationID = observation.id
            if let amount = finalChargeNanoUSD {
                guard let sourceID else { throw TokenStewardError.invalid("charge without source identity") }
                try Self.addBilling(observationID: observation.id, amount: amount, sourceID: sourceID,
                    kind: .finalCharge, date: date, in: &state)
            }
            if Self.finalCharge(observation.id, in: state) != nil { state.reservations[index].state = .settled }
        }
    }

    /// The application decides when retries are over; transport event order is
    /// never a final task outcome. Unknown charges may outlive a closed task.
    func finishAPITask(taskID: String, outcome: String) throws {
        guard ["complete", "failed", "cancelled"].contains(outcome) else { throw TokenStewardError.invalid("final task outcome") }
        try transaction { state in
            guard let task = state.tasks.firstIndex(where: { $0.id == taskID }), state.tasks[task].route == "api" else { throw TokenStewardError.missingTask }
            guard !state.reservations.contains(where: { $0.taskID == taskID && $0.state == .reserved }) else { throw TokenStewardError.conflict("task closure before dispatch decision") }
            guard state.tasks[task].lanes.allSatisfy({ $0.state == "pending" || $0.state == outcome }) else { throw TokenStewardError.conflict("final task outcome") }
            for lane in state.tasks[task].lanes.indices { state.tasks[task].lanes[lane].state = outcome }
        }
    }

    /// Imports are all-or-nothing; immutable identity does not include later bills.
    func importObservations(_ observations: [TokenStewardObservation]) throws {
        try transaction { state in
            for observation in observations { try Self.importObservation(observation, into: &state) }
        }
    }

    func reconcile(observationID: String, amountNanoUSD: Int64, sourceID: String) throws {
        let date = now()
        try transaction { state in
            try Self.addBilling(observationID: observationID, amount: amountNanoUSD, sourceID: sourceID,
                kind: .finalCharge, date: date, in: &state)
            for index in state.reservations.indices where state.reservations[index].observationID == observationID {
                state.reservations[index].state = .settled
            }
        }
    }

    func recordEstimate(observationID: String, amountNanoUSD: Int64, sourceID: String) throws {
        let date = now()
        try transaction { state in
            try Self.addBilling(observationID: observationID, amount: amountNanoUSD, sourceID: sourceID,
                kind: .estimate, date: date, in: &state)
        }
    }

    func exportData() throws -> Data {
        try refresh()
        return try Self.encoder().encode(journal)
    }

    /// Export a separate private snapshot, never the active journal or its lock.
    /// Replacing either would bypass the normal cooperating-writer transaction.
    func export(to destination: URL) throws {
        guard destination.isFileURL else { throw TokenStewardError.invalid("non-file export destination") }
        if let url {
            for protected in [url, url.appendingPathExtension("lock")] {
                let samePath = destination.resolvingSymlinksInPath().standardizedFileURL.path
                    == protected.resolvingSymlinksInPath().standardizedFileURL.path
                let destinationAttributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
                let protectedAttributes = try? FileManager.default.attributesOfItem(atPath: protected.path)
                let sameFile: Bool
                if let device = destinationAttributes?[.systemNumber] as? NSNumber,
                   let inode = destinationAttributes?[.systemFileNumber] as? NSNumber,
                   let protectedDevice = protectedAttributes?[.systemNumber] as? NSNumber,
                   let protectedInode = protectedAttributes?[.systemFileNumber] as? NSNumber {
                    sameFile = device == protectedDevice && inode == protectedInode
                } else { sameFile = false }
                guard !samePath && !sameFile else {
                    throw TokenStewardError.invalid("an export over the active usage journal or its lock; choose a separate file")
                }
            }
        }
        let data = try exportData()
        try Self.writeAtomically(data, to: destination)
    }

    var summary: TokenStewardSummary {
        guard loadError == nil else {
            var unavailable = TokenStewardSummary()
            unavailable.accountingAvailable = false
            return unavailable
        }
        if let cachedSummary { return cachedSummary }
        var result = TokenStewardSummary()
        result.taskCount = journal.tasks.count
        result.openTaskCount = journal.tasks.filter { !$0.isClosed }.count
        let assistance = journal.tasks.filter { !["arc-evaluation", "arc-interactive"].contains($0.route) }
        result.deliveredTaskCount = assistance.filter(\.delivered).count
        result.usefulTaskCount = assistance.filter(\.userUseful).count
        result.checkedSuccessfulTaskCount = assistance.filter(\.checkedSuccessful).count
        result.interactiveSessionCount = journal.tasks.filter { $0.route == "arc-interactive" }.count
        result.evaluationTaskCount = journal.tasks.filter { $0.route == "arc-evaluation" }.count
        result.syntheticCheckedTaskCount = journal.tasks.filter {
            $0.route == "arc-evaluation" && $0.checkedSuccessful && $0.lanes.first?.admission == "synthetic-fixture"
        }.count
        result.localAttemptCount = journal.observations.filter { $0.resource == .localInference }.count
        result.unmeasuredLocalLaneCount = journal.tasks.flatMap(\.lanes).filter {
            [AssistantProvider.qwen.name, ARCQwenProposalInference.provider].contains($0.provider) && $0.dispatched && !$0.localAttemptsMeasured
        }.count
        // Durable dispatch counts include an interrupted request with no receipt.
        result.subscriptionRequestCount = journal.tasks.flatMap(\.lanes).filter {
            $0.provider == AssistantProvider.codex.name && $0.dispatched
        }.count
        result.missingInputCount = journal.observations.filter { $0.inputTokens == nil }.count
        result.missingOutputCount = journal.observations.filter { $0.outputTokens == nil }.count
        // Transactions and reload validate these totals. Keep a defensive
        // unavailable state rather than presenting overflow as a real quantity.
        guard let knownInput = try? Self.sum(journal.observations.compactMap(\.inputTokens)),
              let knownOutput = try? Self.sum(journal.observations.compactMap(\.outputTokens)) else {
            result.accountingAvailable = false
            return result
        }
        result.knownInputTokens = knownInput
        result.knownOutputTokens = knownOutput
        let unobservedSubscription = result.subscriptionRequestCount - journal.observations.filter { $0.resource == .subscription }.count
        result.missingInputCount += max(0, unobservedSubscription)
        result.missingOutputCount += max(0, unobservedSubscription)
        if result.missingInputCount == 0, result.unmeasuredLocalLaneCount == 0, !journal.observations.isEmpty {
            result.inputTokens = result.knownInputTokens
        }
        if result.missingOutputCount == 0, result.unmeasuredLocalLaneCount == 0, !journal.observations.isEmpty {
            result.outputTokens = result.knownOutputTokens
        }
        let api = journal.observations.filter { $0.resource == .api }
        guard let knownCharge = try? Self.sum(api.compactMap { Self.finalCharge($0.id, in: journal) }),
              let estimatedCharge = try? Self.sum(api.compactMap({ observation in
            guard Self.finalCharge(observation.id, in: journal) == nil else { return nil }
            return journal.billing.last { $0.observationID == observation.id && $0.kind == .estimate }?.amountNanoUSD
        })), let reserved = try? Self.sum(journal.reservations.filter(\.isActive).map(\.maximumNanoUSD)) else {
            result.accountingAvailable = false
            return result
        }
        result.knownAPIChargeNanoUSD = knownCharge
        result.estimatedAPIChargeNanoUSD = estimatedCharge
        result.reservedNanoUSD = reserved
        result.unresolvedAPIObservationCount = unresolvedObservations.count
        let apiTaskIDs = Set(api.map(\.taskID) + journal.reservations.filter { $0.state != .released }.map(\.taskID))
        let closedAPITasks = journal.tasks.filter { $0.isClosed && apiTaskIDs.contains($0.id) }
        let ids = Set(closedAPITasks.map(\.id))
        let charges = api.filter { ids.contains($0.taskID) }
        let usefulCount = closedAPITasks.filter(\.userUseful).count
        result.closedAPITaskCount = closedAPITasks.count
        result.usefulClosedAPITaskCount = usefulCount
        let unresolvedHolds = journal.reservations.contains { ids.contains($0.taskID) && $0.isActive }
        if !closedAPITasks.isEmpty, !unresolvedHolds, charges.allSatisfy({ Self.finalCharge($0.id, in: journal) != nil }),
           let total = try? Self.sum(charges.compactMap { Self.finalCharge($0.id, in: journal) }) {
            result.closedAPITaskChargeNanoUSD = total
            if usefulCount > 0 { result.apiCostPerUsefulTaskNanoUSD = total / Int64(usefulCount) }
        }
        cachedSummary = result
        return result
    }

    private static func registerTask(id: String, route: String, providers: [String], date: Date, in state: inout Journal) throws {
        try validateID(id)
        guard !providers.isEmpty, Set(providers).count == providers.count else { throw TokenStewardError.invalid("task providers") }
        if let old = state.tasks.first(where: { $0.id == id }) {
            guard old.route == route, Set(old.lanes.map(\.provider)) == Set(providers) else { throw TokenStewardError.conflict("application task identity") }
        } else {
            state.tasks.append(TokenStewardTask(id: id, route: route, startedAt: date,
                lanes: providers.map { TokenStewardLane(provider: $0) }))
        }
    }

    private static func permitsDocumentReading(_ task: TokenStewardTask) -> Bool {
        ["native", "local", "automatic", "compare"].contains(task.route)
            && task.lanes.contains { $0.provider == AssistantProvider.qwen.name }
    }

    private static func permitsDocumentReadingFeedback(_ task: TokenStewardTask) -> Bool {
        guard permitsDocumentReading(task), let trace = task.documentReading,
              let result = task.documentReadingResult, result.isValid(for: trace), result.kind == "ANSWER" else {
            return false
        }
        return task.lanes.contains {
            $0.provider == AssistantProvider.qwen.name && $0.dispatched && $0.state == "complete"
        }
    }

    private static func nativeObservationID(_ task: String, _ provider: String, _ attempt: String) -> String {
        // Length prefixes avoid collisions from user/imported separators.
        [task, provider, attempt].map { "\($0.utf8.count):\($0)" }.joined()
    }

    private static func importObservation(_ observation: TokenStewardObservation, into state: inout Journal) throws {
        try validateID(observation.id); try validateID(observation.taskID)
        try validateID(observation.provider); try validateID(observation.accountID)
        guard observation.observedAt.timeIntervalSince1970.isFinite,
              [observation.inputTokens, observation.outputTokens, observation.cacheReadTokens,
               observation.cacheWriteTokens, observation.reasoningTokens, observation.elapsedMilliseconds]
                .compactMap({ $0 }).allSatisfy({ $0 >= 0 })
        else { throw TokenStewardError.invalid("observation measurements") }
        if let input = observation.inputTokens {
            guard try sum([observation.cacheReadTokens ?? 0, observation.cacheWriteTokens ?? 0]) <= input
            else { throw TokenStewardError.invalid("cache counts exceeding inclusive input") }
        }
        if let output = observation.outputTokens, let reasoning = observation.reasoningTokens, reasoning > output {
            throw TokenStewardError.invalid("reasoning count exceeding inclusive output")
        }
        if let old = state.observations.first(where: { $0.id == observation.id }) {
            guard old == observation else { throw TokenStewardError.conflict("immutable observation") }
            return
        }
        state.observations.append(observation)
    }

    private static func addBilling(observationID: String, amount: Int64, sourceID: String,
                                   kind: TokenStewardBillingFact.Kind, date: Date, in state: inout Journal) throws {
        try validateID(sourceID)
        guard amount >= 0, state.observations.contains(where: { $0.id == observationID && $0.resource == .api })
        else { throw TokenStewardError.invalid("API billing evidence") }
        if let old = state.billing.first(where: { $0.observationID == observationID && $0.sourceID == sourceID && $0.kind == kind }) {
            guard old.amountNanoUSD == amount else { throw TokenStewardError.conflict("billing source") }
            return
        }
        if kind == .finalCharge, let existing = finalCharge(observationID, in: state), existing != amount {
            throw TokenStewardError.conflict("final charge reconciliation")
        }
        state.billing.append(TokenStewardBillingFact(observationID: observationID, sourceID: sourceID,
            kind: kind, amountNanoUSD: amount, recordedAt: date))
    }

    private static func finalCharge(_ id: String, in state: Journal) -> Int64? {
        state.billing.first { $0.observationID == id && $0.kind == .finalCharge }?.amountNanoUSD
    }

    private static func charges(in component: Calendar.Component, at date: Date, calendar: Calendar, state: Journal) throws -> Int64 {
        try sum(state.observations.filter {
            $0.resource == .api && calendar.isDate($0.observedAt, equalTo: date, toGranularity: component)
        }.compactMap { finalCharge($0.id, in: state) })
    }

    private static func sum(_ values: [Int64]) throws -> Int64 {
        try values.reduce(0) { total, value in
            let (next, overflow) = total.addingReportingOverflow(value)
            guard value >= 0, !overflow else { throw TokenStewardError.invalid("overflowing accounting total") }
            return next
        }
    }

    private static func validateID(_ id: String) throws {
        guard !id.isEmpty, id.utf8.count <= 2048, !id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { throw TokenStewardError.invalid("evidence identity") }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private func readJournal() throws -> Journal {
        guard let url else { return journal }
        guard FileManager.default.fileExists(atPath: url.path) else { return Journal() }
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFREG else {
            throw TokenStewardError.invalid("non-regular journal")
        }
        let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
        guard bytes.count <= 32 * 1024 * 1024 else { throw TokenStewardError.invalid("oversized journal") }
        let result = try JSONDecoder().decode(Journal.self, from: bytes)
        guard result.schema == "archi-token-steward/v1", result.revision >= 0,
              Set(result.tasks.map(\.id)).count == result.tasks.count,
              Set(result.observations.map(\.id)).count == result.observations.count,
              Set(result.reservations.map(\.id)).count == result.reservations.count
        else { throw TokenStewardError.invalid("journal schema or duplicate identities") }
        // Re-validate persisted observation and billing invariants, not just JSON.
        var checked = Journal()
        for observation in result.observations { try Self.importObservation(observation, into: &checked) }
        for fact in result.billing {
            try Self.addBilling(observationID: fact.observationID, amount: fact.amountNanoUSD,
                sourceID: fact.sourceID, kind: fact.kind, date: fact.recordedAt, in: &checked)
        }
        if let budget = result.budget {
            guard budget.dailyNanoUSD >= 0, budget.monthlyNanoUSD >= budget.dailyNanoUSD,
                  TimeZone(identifier: budget.timeZoneID) != nil else { throw TokenStewardError.invalid("saved budget") }
        }
        guard result.reservations.allSatisfy({ $0.maximumNanoUSD > 0 }) else { throw TokenStewardError.invalid("saved reservation") }
        try Self.validateTotals(result)
        for reservation in result.reservations {
            guard result.tasks.contains(where: { $0.id == reservation.taskID && $0.route == "api" }),
                  reservation.state != .settled || reservation.observationID.flatMap({ Self.finalCharge($0, in: result) }) != nil
            else { throw TokenStewardError.invalid("orphaned reservation") }
        }
        try Self.validateStructure(result)
        return result
    }

    private func transaction(_ update: (inout Journal) throws -> Void) throws {
        do {
            try withLock {
                let original: Journal
                do { original = try readJournal() } catch { loadError = error.localizedDescription; throw error }
                var next = original
                guard next.revision < Int.max else { throw TokenStewardError.invalid("journal revision overflow") }
                try update(&next)
                try Self.validateTotals(next)
                if next != original {
                    guard next.revision < Int.max else { throw TokenStewardError.invalid("journal revision overflow") }
                    next.revision += 1
                    try Self.validateStructure(next)
                    if let url {
                        let bytes = try Self.encoder().encode(next)
                        guard bytes.count <= 32 * 1024 * 1024 else { throw TokenStewardError.invalid("full journal") }
                        try Self.writeAtomically(bytes, to: url)
                    }
                }
                journal = next; cachedSummary = nil; revision = next.revision; loadError = nil
            }
        } catch {
            // A policy rejection is not a broken journal. Disk/schema errors are.
            if !(error is TokenStewardError) { loadError = error.localizedDescription }
            throw error
        }
    }

    private static func validateStructure(_ state: Journal) throws {
        let states: Set<String> = ["pending", "complete", "failed", "cancelled"]
        for task in state.tasks {
            try validateID(task.id)
            guard task.startedAt.timeIntervalSince1970.isFinite, !task.lanes.isEmpty,
                  Set(task.lanes.map(\.provider)).count == task.lanes.count else {
                throw TokenStewardError.invalid("task identity, date or duplicate lanes")
            }
            let providers = Set(task.lanes.map(\.provider))
            switch task.route {
            case "local", "automatic":
                guard providers == [AssistantProvider.qwen.name] else { throw TokenStewardError.invalid("local task lanes") }
            case "native":
                guard providers == [AssistantProvider.qwen.name]
                    || providers == [AssistantProvider.qwen.name, AssistantProvider.codex.name] else {
                    throw TokenStewardError.invalid("native task lanes")
                }
                if providers.contains(AssistantProvider.codex.name) {
                    guard task.lanes.first(where: { $0.provider == AssistantProvider.qwen.name })?.state == "failed" else {
                        throw TokenStewardError.invalid("native fallback without local failure")
                    }
                }
            case "codex":
                guard providers == [AssistantProvider.codex.name] else { throw TokenStewardError.invalid("subscription task lanes") }
            case "compare":
                guard providers == [AssistantProvider.qwen.name, AssistantProvider.codex.name] else { throw TokenStewardError.invalid("Compare task lanes") }
            case "arc-evaluation":
                guard providers == ["ARC deterministic checker"] || providers == ["ARC local symbolic solver + checker"] || providers == [ARCQwenProposalInference.provider] else { throw TokenStewardError.invalid("evaluation task lanes") }
            case "arc-interactive":
                guard providers == ["ARC3 offline environment"], task.outcomes.isEmpty else { throw TokenStewardError.invalid("interactive ARC task") }
            case "api": break
            default: throw TokenStewardError.invalid("task route")
            }
            if let trace = task.documentReading {
                guard trace.isValid, permitsDocumentReading(task) else {
                    throw TokenStewardError.invalid("saved document reading trace or route")
                }
            }
            if let result = task.documentReadingResult {
                guard let trace = task.documentReading, result.isValid(for: trace),
                      task.lanes.contains(where: { $0.provider == AssistantProvider.qwen.name && $0.dispatched }) else {
                    throw TokenStewardError.invalid("saved document reading result provenance")
                }
            }
            for lane in task.lanes {
                try validateID(lane.provider)
                guard states.contains(lane.state), lane.elapsedMilliseconds.map({ $0 >= 0 }) != false,
                      !lane.localAttemptsMeasured || [AssistantProvider.qwen.name, ARCQwenProposalInference.provider].contains(lane.provider) else {
                    throw TokenStewardError.invalid("lane state or measurement")
                }
                if let admission = lane.admission {
                    try validateID(admission)
                    if !["arc-evaluation", "arc-interactive"].contains(task.route), !["accepted", "rejected", "stopped"].contains(admission) {
                        throw TokenStewardError.invalid("lane admission status")
                    }
                }
            }
            var priorRevision = 0
            var outcomeKeys: Set<String> = []
            for outcome in task.outcomes {
                try validateID(outcome.evidenceID)
                if outcome.evidenceID.hasPrefix(DocumentReadingTrace.feedbackEvidencePrefix) {
                    let eventID = String(outcome.evidenceID.dropFirst(DocumentReadingTrace.feedbackEvidencePrefix.count))
                    guard UUID(uuidString: eventID) != nil, outcome.kind == .userUseful,
                          permitsDocumentReadingFeedback(task) else {
                        throw TokenStewardError.invalid("saved document reading feedback provenance")
                    }
                }
                guard outcome.revision > priorRevision, outcome.revision <= state.revision,
                      outcome.recordedAt.timeIntervalSince1970.isFinite,
                      outcomeKeys.insert(outcome.kind.rawValue + ":" + outcome.evidenceID).inserted,
                      outcome.kind != .userUseful || (task.route != "arc-evaluation" && task.delivered),
                      task.route != "arc-evaluation" || (outcome.kind == .checked && task.isClosed && task.delivered)
                else { throw TokenStewardError.invalid("outcome order, source or task category") }
                priorRevision = outcome.revision
            }
        }
        var heldObservations: Set<String> = []
        for reservation in state.reservations {
            try validateID(reservation.id); try validateID(reservation.provider); try validateID(reservation.accountID)
            guard reservation.reservedAt.timeIntervalSince1970.isFinite, reservation.maximumNanoUSD > 0,
                  let task = state.tasks.first(where: { $0.id == reservation.taskID }), task.route == "api",
                  task.lanes.contains(where: { $0.provider == reservation.provider }),
                  !(task.isClosed && reservation.state == .reserved) else {
                throw TokenStewardError.invalid("reservation task or lifecycle")
            }
            if let id = reservation.observationID {
                guard reservation.state == .sent || reservation.state == .settled,
                      heldObservations.insert(id).inserted,
                      let observation = state.observations.first(where: { $0.id == id }), observation.resource == .api,
                      observation.taskID == reservation.taskID, observation.provider == reservation.provider,
                      observation.accountID == reservation.accountID,
                      reservation.state != .settled || finalCharge(id, in: state) != nil
                else { throw TokenStewardError.invalid("reservation and observation linkage") }
            } else if reservation.state == .settled {
                throw TokenStewardError.invalid("settled reservation without observation")
            }
        }
        var billingKeys: Set<String> = []
        for fact in state.billing {
            let key = [fact.observationID, fact.sourceID, fact.kind.rawValue].map { "\($0.utf8.count):\($0)" }.joined()
            guard fact.recordedAt.timeIntervalSince1970.isFinite, billingKeys.insert(key).inserted else {
                throw TokenStewardError.invalid("billing chronology or duplicate source")
            }
        }
    }

    private static func validateTotals(_ state: Journal) throws {
        _ = try sum(state.reservations.filter(\.isActive).map(\.maximumNanoUSD))
        _ = try sum(state.observations.compactMap(\.inputTokens))
        _ = try sum(state.observations.compactMap(\.outputTokens))
        _ = try sum(state.observations.compactMap { finalCharge($0.id, in: state) })
        _ = try sum(state.observations.compactMap { observation in
            guard finalCharge(observation.id, in: state) == nil else { return nil }
            return state.billing.last { $0.observationID == observation.id && $0.kind == .estimate }?.amountNanoUSD
        })
    }

    private static func writeAtomically(_ bytes: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".steward-\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw TokenStewardError.unavailable("private journal write") }
        defer { close(descriptor); unlink(temporary.path) }
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw TokenStewardError.unavailable("complete journal write") }
                offset += count
            }
        }
        guard fsync(descriptor) == 0, rename(temporary.path, url.path) == 0 else {
            throw TokenStewardError.unavailable("atomic journal commit")
        }
        let directory = open(url.deletingLastPathComponent().path, O_RDONLY)
        guard directory >= 0 else { throw TokenStewardError.unavailable("journal directory sync") }
        defer { close(directory) }
        guard fsync(directory) == 0 else { throw TokenStewardError.unavailable("journal directory sync") }
    }

    private func withLock<T>(_ operation: () throws -> T) throws -> T {
        guard let url else { return try operation() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lockPath = url.appendingPathExtension("lock").path
        let descriptor = open(lockPath, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw TokenStewardError.unavailable("accounting lock") }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw TokenStewardError.unavailable("another process is recording accounting; retry") }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }
}
