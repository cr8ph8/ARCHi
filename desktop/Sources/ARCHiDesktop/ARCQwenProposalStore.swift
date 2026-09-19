import Foundation

/// The identity comes from successful local transport verification, before the
/// terminal response is parsed. Fake clients can supply this seam in focused tests.
@MainActor
protocol ARCQwenProposalClient: LocalRoleClient {
    var metadata: QwenModelMetadata? { get }
}
extension QwenAssistant: ARCQwenProposalClient {}

/// Metadata only: never retains a prompt, response text or guessed billing.
struct ARCQwenProposalInference: Sendable, Equatable {
    static let provider = "ARC local Qwen proposal + checker"
    let model: String
    var attempted = false
    var inputDigest: String?
    var inputTokens: Int?
    var outputTokens: Int?
    var elapsedMilliseconds: Int?
    var outcome = "not-started"
}

struct ARCQwenProposalReview: Sendable {
    let taskID: String
    let document: ARCSolverDocument
    let result: ARCQwenProposalResult?
    let inference: ARCQwenProposalInference
    let elapsedMilliseconds: Int
    let evidenceID: String?
    let error: String?
}

@MainActor
extension ARCCapabilitiesStore {
    func startQwenProposal(model: String, onEvaluation: @escaping @MainActor (ARCCapabilitiesEvent) -> Void) {
        guard let document = prepareQwenProposal() else { return }
        guard QwenAssistant.supportedModels.contains(model) else {
            updateQwenProposal(status: QwenFailure.unsupportedModel.localizedDescription, review: nil, isProposing: false)
            return
        }
        let owner = ARCQwenProposalSession(store: self, document: document, model: model,
            client: qwenProposalClientFactory(model), onEvaluation: onEvaluation)
        qwenProposalOwner = owner
        updateQwenProposal(status: "Connecting to local \(model)…", review: nil, isProposing: true)
        owner.start()
    }

    func stopQwenProposal() { stopQwenProposal(reason: "Stopped.") }

    func stopQwenProposal(reason: String) { qwenProposalOwner?.cancel(reason: reason) }
}

/// Synchronous retirement owns cancellation. The async client and bounded rule
/// worker can finish late, but cannot retain evidence or report a second terminal event.
@MainActor
final class ARCQwenProposalSession {
    let id = UUID()
    private weak var store: ARCCapabilitiesStore?
    private let document: ARCSolverDocument
    private let client: any ARCQwenProposalClient
    private let startedAt = Date()
    private let onEvaluation: @MainActor (ARCCapabilitiesEvent) -> Void
    private var inference: ARCQwenProposalInference
    private var task: Task<Void, Never>?
    private var worker: Task<(ARCQwenProposalResult, String), Error>?

    init(store: ARCCapabilitiesStore, document: ARCSolverDocument, model: String,
         client: any ARCQwenProposalClient, onEvaluation: @escaping @MainActor (ARCCapabilitiesEvent) -> Void) {
        self.store = store
        self.document = document
        self.client = client
        self.onEvaluation = onEvaluation
        self.inference = ARCQwenProposalInference(model: model)
    }

    private var ownsRequest: Bool { store?.qwenProposalOwner?.id == id }

    func start() {
        reportProgress()
        guard ownsRequest else { return }
        task = Task { [weak self] in
            guard let self else { return }
            await self.run()
        }
    }

    private func run() async {
        do {
            guard ownsRequest, !Task.isCancelled else { return }
            // Request construction is target-isolated and may reject an input
            // before any local model call. There is one generation, no retries.
            let input = document.input
            let request = try ARCQwenProposalEngine.request(input: input, requestID: id.uuidString)
            inference.inputDigest = request.input["inputDigest"]?.string
            try await client.connect()
            guard ownsRequest, !Task.isCancelled else { return }
            guard let verifiedModel = client.metadata, verifiedModel.name == inference.model else {
                throw QwenFailure.modelChanged
            }
            inference.attempted = true
            inference.outcome = "dispatched"
            reportProgress()
            guard ownsRequest, !Task.isCancelled else { return }
            store?.updateQwenProposal(status: "Local Qwen is proposing one bounded rule…", review: nil, isProposing: true)
            let response = try await client.generate(request)
            guard ownsRequest, !Task.isCancelled else { return }
            // Retain actual terminal telemetry before schema/training validation;
            // a malformed or rejected proposal still consumed this local attempt.
            inference.outcome = "complete"
            inference.inputTokens = response.metrics?.inputTokens.flatMap { $0 >= 0 ? $0 : nil }
            inference.outputTokens = response.metrics?.outputTokens.flatMap { $0 >= 0 ? $0 : nil }
            inference.elapsedMilliseconds = response.elapsedMilliseconds >= 0 ? response.elapsedMilliseconds : nil
            client.disconnect()
            store?.updateQwenProposal(status: "Checking the proposed rule against every training example…", review: nil, isProposing: true)
            let work = Task.detached(priority: .userInitiated) {
                let result = try ARCQwenProposalEngine.evaluate(response, request: request, input: input,
                    expectedModel: verifiedModel, isCancelled: { Task.isCancelled })
                let codeHash = try ARCQwenProposalEngine.executableHash(isCancelled: { Task.isCancelled })
                return (result, codeHash)
            }
            worker = work
            let (result, codeHash) = try await work.value
            guard ownsRequest, !Task.isCancelled, !work.isCancelled, let store else { return }
            let bundle = try ARCQwenProposalEngine.bundle(document: document, result: result,
                codeHash: codeHash, model: verifiedModel)
            guard var event = store.retainQwenProposal(bundle: bundle, ownerID: id, startedAt: startedAt) else { return }
            event.proposalInference = inference
            let status: String
            if let error = event.error { status = "Proposal could not be retained: \(error)" }
            else if result.status == .predicted { status = "Local Qwen proposal checked and retained. It is not a certified capability." }
            else { status = "Proposal abstained or failed a bounded check. No test prediction was admitted." }
            finish(event: event, result: result, status: status)
        } catch {
            guard ownsRequest else { return }
            let cancelled = error is CancellationError || (error as? QwenFailure) == .stopped
            if inference.outcome != "complete" { inference.outcome = cancelled ? "cancelled" : "failed" }
            let message = cancelled ? "Stopped. Previous evidence is unchanged." : "Local Qwen proposal failed: \(error.localizedDescription)"
            finish(event: terminalEvent(error: message, cancelled: cancelled), result: nil, status: message)
        }
    }

    func cancel(reason: String) {
        guard ownsRequest else { return }
        if inference.outcome != "complete" { inference.outcome = "cancelled" }
        let event = terminalEvent(error: reason + " Previous evidence is unchanged.", cancelled: true)
        // Retire before cancellation/disconnect can resume any suspended work.
        let current = store
        current?.qwenProposalOwner = nil
        task?.cancel()
        worker?.cancel()
        task = nil
        worker = nil
        client.disconnect()
        current?.updateQwenProposal(status: event.error ?? reason, review: nil, isProposing: false)
        onEvaluation(event)
    }

    private func reportProgress() {
        guard ownsRequest else { return }
        var event = ARCCapabilitiesEvent(taskID: id.uuidString, evidenceID: nil, passed: nil,
            startedAt: startedAt, finishedAt: max(startedAt, Date()), sourceStatus: nil, error: nil)
        event.proposalInference = inference
        event.proposalInProgress = true
        onEvaluation(event)
    }

    private func terminalEvent(error: String, cancelled: Bool) -> ARCCapabilitiesEvent {
        var event = ARCCapabilitiesEvent(taskID: id.uuidString, evidenceID: nil, passed: nil,
            startedAt: startedAt, finishedAt: max(startedAt, Date()),
            sourceStatus: document.isSynthetic ? "synthetic-fixture" : "unverified-offline-snapshot",
            error: error, cancelled: cancelled)
        event.proposalInference = inference
        return event
    }

    private func finish(event: ARCCapabilitiesEvent, result: ARCQwenProposalResult?, status: String) {
        guard ownsRequest, let store else { return }
        store.qwenProposalOwner = nil
        task = nil
        worker = nil
        client.disconnect()
        let seconds = max(0, event.finishedAt.timeIntervalSince(startedAt))
        let elapsed = seconds < Double(Int.max / 1000) ? Int(seconds * 1000) : Int.max
        store.updateQwenProposal(status: status,
            review: ARCQwenProposalReview(taskID: id.uuidString, document: document, result: result,
                inference: inference, elapsedMilliseconds: elapsed, evidenceID: event.evidenceID, error: event.error),
            isProposing: false)
        onEvaluation(event)
    }
}
