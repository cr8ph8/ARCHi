import Foundation
import Combine

enum ARC3PredictionVerdict: String, Codable, Sendable {
    case observed, supported, refuted, inconclusive
}

struct ARC3Transition: Codable, Identifiable, Sendable {
    let id: UUID
    let beforeDigest: String
    let afterDigest: String
    let action: Int
    let x: Int?
    let y: Int?
    let predictedDigest: String?
    let verdict: ARC3PredictionVerdict
    var invalidated: Bool
    let before: ARC3Observation
    let after: ARC3Observation
    var actionName: String { action == 0 ? "RESET" : "ACTION\(action)" }
}

struct ARC3ActionAttempt: Codable, Identifiable, Sendable {
    let id: String
    let proposedAt: Date
    let baseFrameDigest: String?
    let baseDispatches: Int
    let action: Int
    let x: Int?
    let y: Int?
    let predictedDigest: String?
    /// requested precedes transport; observed requires a validated response.
    /// unreconciled retains uncertainty after cancellation or transport failure.
    var state: String
    var actualDigest: String?
    /// Optional fields keep older episode receipts decodable. The decision is
    /// the pre-dispatch proposal; outcome is populated only after validation.
    var decision: ARC3PlanDecision? = nil
    var outcome: String? = nil
}

struct ARC3SessionSummary: Sendable {
    let sessionID: String
    let gameID: String
    let startedAt: Date
    let finishedAt: Date
    let dispatches: Int
    /// complete, budget-exhausted, stopped, failed, or profile-reset.
    let outcome: String
    let receiptURL: URL?
    let lastState: String?
    let error: String?
    var attemptedDispatches = 0
    var unreconciledDispatches = 0
}

/// Task-local observations and transition predictions. This store has no Seed,
/// companion evolution, trusted skill memory, or provider authority.
@MainActor
final class ARC3SessionStore: ObservableObject {
    @Published private(set) var status = "Discover local ARC3 games to begin."
    @Published private(set) var games: [ARC3Game] = []
    @Published var selectedGameID: String?
    @Published private(set) var observation: ARC3Observation?
    @Published private(set) var transitions: [ARC3Transition] = []
    @Published private(set) var attempts: [ARC3ActionAttempt] = []
    @Published private(set) var latestPlan: ARC3PlanDecision?
    @Published private(set) var isWorking = false
    @Published private(set) var isSessionActive = false
    @Published private(set) var error: String?
    @Published private(set) var receiptURL: URL?
    @Published private(set) var runtimeRoot: URL
    var onFinished: (@MainActor (ARC3SessionSummary) -> Void)?
    var canStart: Bool { !isWorking && !isSessionActive && selectedGameID.map { id in games.contains { $0.id == id } } == true }
    private var outputDirectory: URL
    private let injectedFactory: (@Sendable (URL) -> any ARC3Transport)?
    private var transport: (any ARC3Transport)?
    private var ownerID: UUID?
    private var operation: Task<Void, Never>?
    private var startedAt: Date?
    private var initialObservation: ARC3Observation?
    private var expectedBudget = 32
    private var activeGameID: String?
    private var episodeDirectory: URL?
    private var bridgeReceiptPath: String?
    private var predictions: [String: String] = [:]

    init(runtimeRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("ARC-AGI-3-Agents"),
         outputDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ARCHi/ARC3"),
         transportFactory: (@Sendable (URL) -> any ARC3Transport)? = nil) {
        self.runtimeRoot = runtimeRoot
        self.outputDirectory = outputDirectory
        self.injectedFactory = transportFactory
    }

    func configureRuntimeRoot(_ root: URL) {
        guard !isSessionActive, !isWorking else { return }
        runtimeRoot = root.standardizedFileURL
        games = []; selectedGameID = nil; error = nil
        status = "Discover games in the selected local ARC3 workspace."
    }

    private func beginTransport() -> (UUID, any ARC3Transport) {
        let id = UUID()
        let directory = outputDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        let client = injectedFactory?(directory) ?? ARC3Runtime(runtimeRoot: runtimeRoot, outputDirectory: directory)
        ownerID = id; transport = client; episodeDirectory = directory
        return (id, client)
    }

    func discover() {
        guard !isWorking, !isSessionActive else { return }
        let (id, client) = beginTransport()
        isWorking = true; error = nil; status = "Discovering installed offline games…"
        operation = Task { [weak self] in
            do {
                let request = ARC3Request(command: "discover")
                let response = try await client.request(request)
                guard let self, self.ownerID == id, !Task.isCancelled else { return }
                try self.checkResponse(response, request: request)
                guard let entries = response.games, entries.count <= 128,
                      Set(entries.map(\.id)).count == entries.count,
                      entries.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 100 && $0.title.count <= 200 }) else {
                    throw ARC3RuntimeError.invalid("Invalid local ARC3 game inventory.")
                }
                self.games = entries
                if !entries.contains(where: { $0.id == self.selectedGameID }) { self.selectedGameID = entries.first?.id }
                self.ownerID = nil; self.transport = nil; self.operation = nil; self.isWorking = false
                client.stop()
                self.status = entries.isEmpty ? "No local ARC3 games are installed." : "\(entries.count) local ARC3 game(s) available."
            } catch {
                guard let self, self.ownerID == id else { return }
                self.fail(error)
            }
        }
    }

    func start(budget: Int = 32) {
        guard !isWorking, !isSessionActive else { return }
        guard let gameID = selectedGameID, games.contains(where: { $0.id == gameID }), (1...64).contains(budget) else {
            error = "Choose an installed game and a dispatch budget from 1 to 64."; return
        }
        let (id, client) = beginTransport()
        isWorking = true; isSessionActive = true; error = nil; status = "Starting an offline ARC3 episode…"
        observation = nil; initialObservation = nil; transitions = []; attempts = []; predictions = [:]; latestPlan = nil
        receiptURL = nil; bridgeReceiptPath = nil; startedAt = Date(); expectedBudget = budget; activeGameID = gameID
        operation = Task { [weak self] in
            do {
                guard let self, self.ownerID == id, !Task.isCancelled else { return }
                let request = ARC3Request(command: "start", gameID: gameID, budget: budget)
                self.attempts.append(ARC3ActionAttempt(id: request.id, proposedAt: Date(), baseFrameDigest: nil,
                    baseDispatches: 0, action: 0, x: nil, y: nil, predictedDigest: nil, state: "requested"))
                try self.persist(outcome: "active")
                let response = try await client.request(request)
                guard self.ownerID == id, !Task.isCancelled else { return }
                try self.checkResponse(response, request: request)
                let observed = try self.checkedObservation(response, previous: nil)
                guard observed.dispatches == 1 else { throw ARC3RuntimeError.invalid("ARC3 initial RESET count is invalid.") }
                self.observation = observed; self.initialObservation = observed
                self.markObserved(requestID: request.id, digest: observed.frameDigest, outcome: "initial-reset")
                self.retainReceipt(response)
                try self.persist(outcome: "active")
                if observed.isTerminal || observed.remainingActions == 0 {
                    try await self.closeSession(id: id, client: client, outcome: observed.isTerminal ? "complete" : "budget-exhausted")
                } else {
                    self.isWorking = false; self.operation = nil; self.status = "Offline episode ready. Choose an action or explore."
                }
            } catch {
                guard let self, self.ownerID == id else { return }
                self.fail(error)
            }
        }
    }

    func step(action: Int, x: Int? = nil, y: Int? = nil) {
        guard !isWorking, isSessionActive, let current = observation, let id = ownerID, let client = transport else { return }
        do { try validateAction(action, x: x, y: y, current: current) }
        catch { self.error = error.localizedDescription; return }
        isWorking = true; error = nil; status = "Applying one ARC3 action…"
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.perform(action: action, x: x, y: y, id: id, client: client)
                guard self.ownerID == id else { return }
                self.isWorking = false; self.operation = nil; self.status = "Observation retained. Episode paused for the next action."
            } catch { if self.ownerID == id { self.fail(error) } }
        }
    }

    func explore(maxActions: Int = 8) {
        guard !isWorking, isSessionActive, let id = ownerID, let client = transport else { return }
        guard (1...8).contains(maxActions) else { error = "Choose an exploration batch from 1 to 8 actions."; return }
        isWorking = true; error = nil; status = "Planning from observed transitions, up to \(maxActions) actions…"
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                for index in 0..<maxActions {
                    guard self.ownerID == id, !Task.isCancelled, let current = self.observation else { return }
                    let decision = ARC3Planner.plan(current: current, transitions: self.transitions,
                        previous: self.latestPlan, remainingBatch: maxActions - index, attempts: self.attempts)
                    self.latestPlan = decision
                    guard let choice = decision.action else {
                        // A planning pause keeps the episode open for explicit
                        // manual action; it never consumes an implicit RESET.
                        try self.persist(outcome: "active")
                        self.isWorking = false; self.operation = nil
                        self.status = "Planning paused. \(decision.reason)"
                        return
                    }
                    self.status = "\(choice.title) · \(decision.reason)"
                    try await self.perform(action: choice.action, x: choice.x, y: choice.y,
                        id: id, client: client, decision: decision)
                }
                guard self.ownerID == id else { return }
                self.isWorking = false; self.operation = nil
                self.status = "Planning batch complete. Episode paused; observed transitions remain task-local."
            } catch { if self.ownerID == id { self.fail(error) } }
        }
    }

    func stop(reason: String = "Stopped.") {
        guard ownerID != nil else { return }
        retire(outcome: "stopped", message: reason)
    }

    func resetForProfile(outputDirectory: URL? = nil) {
        if ownerID != nil { retire(outcome: "profile-reset", message: "Profile changed.") }
        if let outputDirectory { self.outputDirectory = outputDirectory }
        observation = nil; initialObservation = nil; transitions = []; attempts = []; predictions = [:]; latestPlan = nil
        receiptURL = nil; bridgeReceiptPath = nil; error = nil; games = []; selectedGameID = nil
        status = "Discover local ARC3 games for this profile."
    }

    private func validateAction(_ action: Int, x: Int?, y: Int?, current: ARC3Observation) throws {
        guard !current.isTerminal, current.remainingActions > 0,
              action == 0 || current.availableActions.contains(action) else {
            throw ARC3RuntimeError.invalid("That action is unavailable for the current observation.")
        }
        if action == 6 {
            guard let x, let y, (0...63).contains(x), (0...63).contains(y) else {
                throw ARC3RuntimeError.invalid("ACTION6 needs x and y coordinates from 0 to 63.")
            }
        } else if x != nil || y != nil { throw ARC3RuntimeError.invalid("Only ACTION6 accepts coordinates.") }
    }

    private func perform(action: Int, x: Int?, y: Int?, id: UUID, client: any ARC3Transport,
                         decision: ARC3PlanDecision? = nil) async throws {
        guard ownerID == id, !Task.isCancelled, let before = observation else { throw ARC3RuntimeError.stopped }
        try validateAction(action, x: x, y: y, current: before)
        if let decision {
            guard decision.controller.isValid, decision.controller.domain == "arc3",
                  decision.controller.contextID == "\(before.gameID)|level:\(before.levelsCompleted)",
                  decision.controller.lane != .stop, decision.gameID == before.gameID,
                  decision.level == before.levelsCompleted, decision.baseFrameDigest == before.frameDigest,
                  decision.baseDispatches == before.dispatches,
                  decision.action == ARC3PlannedAction(action: action, x: x, y: y) else {
                throw ARC3RuntimeError.invalid("The ARC3 plan no longer matches this observation or action.")
            }
        }
        // Freeze the expectation and source observation before dispatch. This
        // remains in the episode even if no trustworthy response ever arrives.
        let key = predictionKey(before, action: action, x: x, y: y)
        let predicted = decision?.expectedDigest ?? predictions[key]
        let request = ARC3Request(command: "step", action: action, x: x, y: y)
        attempts.append(ARC3ActionAttempt(id: request.id, proposedAt: Date(), baseFrameDigest: before.frameDigest,
            baseDispatches: before.dispatches, action: action, x: x, y: y, predictedDigest: predicted,
            state: "requested", decision: decision))
        try persist(outcome: "active")
        let response = try await client.request(request)
        guard ownerID == id, !Task.isCancelled else { return }
        try checkResponse(response, request: request)
        let after = try checkedObservation(response, previous: before)
        let outcome: String
        if action == 0 { outcome = "explicit-reset" }
        else if after.state == "WIN" { outcome = "environment-win" }
        else if after.state == "GAME_OVER" { outcome = "environment-game-over" }
        else if after.levelsCompleted > before.levelsCompleted { outcome = "environment-level-progress" }
        else if before.frameDigest == after.frameDigest { outcome = "unchanged-visible-frame" }
        else if transitions.contains(where: { $0.before.levelsCompleted == after.levelsCompleted &&
            ($0.beforeDigest == after.frameDigest || $0.afterDigest == after.frameDigest) }) {
            outcome = "revisited-visible-frame"
        } else { outcome = "new-visible-frame" }
        markObserved(requestID: request.id, digest: after.frameDigest, outcome: outcome)
        let verdict: ARC3PredictionVerdict
        if before.levelsCompleted != after.levelsCompleted || action == 0 || after.isTerminal {
            verdict = .inconclusive
        } else if let predicted {
            verdict = predicted == after.frameDigest ? .supported : .refuted
        } else { verdict = .observed }
        if action == 0 || before.levelsCompleted != after.levelsCompleted {
            predictions.removeAll(); latestPlan = nil
        }
        if verdict == .refuted || verdict == .inconclusive {
            predictions[key] = nil
            if verdict == .refuted {
                for index in transitions.indices where predictionKey(transitions[index].before, action: transitions[index].action,
                    x: transitions[index].x, y: transitions[index].y) == key { transitions[index].invalidated = true }
            }
        } else { predictions[key] = after.frameDigest }
        transitions.append(ARC3Transition(id: UUID(), beforeDigest: before.frameDigest, afterDigest: after.frameDigest,
            action: action, x: x, y: y, predictedDigest: predicted, verdict: verdict, invalidated: verdict == .refuted,
            before: before, after: after))
        observation = after; retainReceipt(response)
        try persist(outcome: "active")
        if after.isTerminal || after.remainingActions == 0 {
            try await closeSession(id: id, client: client, outcome: after.isTerminal ? "complete" : "budget-exhausted")
        }
    }

    private func predictionKey(_ observation: ARC3Observation, action: Int, x: Int?, y: Int?) -> String {
        "\(observation.gameID)|\(observation.levelsCompleted)|\(observation.frameDigest)|\(action)|\(x ?? -1)|\(y ?? -1)"
    }

    private func markObserved(requestID: String, digest: String, outcome: String) {
        guard let index = attempts.firstIndex(where: { $0.id == requestID }) else { return }
        attempts[index].state = "observed"
        attempts[index].actualDigest = digest
        attempts[index].outcome = outcome
    }

    private func checkResponse(_ response: ARC3Response, request: ARC3Request) throws {
        guard response.id == request.id, response.ok else { throw ARC3RuntimeError.invalid("ARC3 response failed validation.") }
    }

    private func checkedObservation(_ response: ARC3Response, previous: ARC3Observation?) throws -> ARC3Observation {
        guard let value = response.observation, let activeGameID else { throw ARC3RuntimeError.invalid("ARC3 observation is missing.") }
        try value.validate(gameID: activeGameID, budget: expectedBudget)
        if let previous, value.dispatches != previous.dispatches + 1 {
            throw ARC3RuntimeError.invalid("ARC3 dispatch count did not advance exactly once.")
        }
        return value
    }

    private func retainReceipt(_ response: ARC3Response) {
        guard let path = response.receiptPath, let episodeDirectory else { return }
        let candidate = URL(fileURLWithPath: path).standardizedFileURL
        if candidate.path.hasPrefix(episodeDirectory.standardizedFileURL.path + "/") { bridgeReceiptPath = candidate.path }
    }

    private func closeSession(id: UUID, client: any ARC3Transport, outcome: String) async throws {
        let request = ARC3Request(command: "close")
        let response = try await client.request(request)
        guard ownerID == id, !Task.isCancelled else { return }
        try checkResponse(response, request: request)
        retainReceipt(response)
        retire(outcome: outcome, message: outcome == "complete" ? "Episode ended: \(observation?.state ?? "unknown")." : "Session dispatch budget reached.")
    }

    private func fail(_ failure: Error) {
        error = failure.localizedDescription
        retire(outcome: "failed", message: "ARC3 stopped: \(failure.localizedDescription)")
    }

    private func retire(outcome: String, message: String) {
        guard let id = ownerID else { return }
        let client = transport
        // Retire first: cancelled or delayed responses can never publish a frame,
        // evidence record, completion callback, or state into a replacement owner.
        ownerID = nil; transport = nil
        operation?.cancel(); operation = nil
        client?.stop(); isWorking = false; isSessionActive = false; status = message
        for index in attempts.indices where attempts[index].state == "requested" {
            attempts[index].state = "unreconciled"
        }
        guard let startedAt, let activeGameID else { return }
        do { try persist(outcome: outcome) }
        catch { self.error = "Episode evidence could not be saved: \(error.localizedDescription)" }
        onFinished?(ARC3SessionSummary(sessionID: id.uuidString, gameID: activeGameID, startedAt: startedAt,
            finishedAt: max(startedAt, Date()), dispatches: observation?.dispatches ?? 0, outcome: outcome,
            receiptURL: receiptURL, lastState: observation?.state, error: error,
            attemptedDispatches: attempts.count, unreconciledDispatches: attempts.filter { $0.state == "unreconciled" }.count))
        self.startedAt = nil; self.activeGameID = nil
    }

    private struct Episode: Codable {
        let schema = "archi.arc3.native-episode.v1"
        let source = "local-public-game-observation"
        let scope = "task-local transition predictions; no companion growth or benchmark claim"
        let gameID: String
        let startedAt: Date
        let updatedAt: Date
        let outcome: String
        let initial: ARC3Observation?
        let latest: ARC3Observation?
        let transitions: [ARC3Transition]
        let attempts: [ARC3ActionAttempt]
        let latestPlan: ARC3PlanDecision?
        let bridgeReceiptPath: String?
    }

    private func persist(outcome: String) throws {
        guard let episodeDirectory, let activeGameID, let startedAt else { return }
        let episode = Episode(gameID: activeGameID, startedAt: startedAt, updatedAt: Date(), outcome: outcome,
            initial: initialObservation, latest: observation, transitions: transitions, attempts: attempts,
            latestPlan: latestPlan, bridgeReceiptPath: bridgeReceiptPath)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(episode)
        guard transitions.count <= 63, attempts.count <= 64, data.count <= 4 * 1024 * 1024 else {
            throw ARC3RuntimeError.invalid("ARC3 episode exceeds its evidence limit.")
        }
        try FileManager.default.createDirectory(at: episodeDirectory, withIntermediateDirectories: true)
        let destination = episodeDirectory.appendingPathComponent("native-episode.json")
        try data.write(to: destination, options: [.atomic])
        receiptURL = destination
    }
}
