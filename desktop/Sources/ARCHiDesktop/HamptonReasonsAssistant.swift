import Foundation
import CryptoKit

struct HamptonRoleReceipt: Identifiable, Equatable, Sendable {
    let id: String
    let role: LocalModelRole
    let model: QwenModelMetadata
    let elapsedMilliseconds: Int
    let inputDigest: String
    let outputDigest: String
    let systemDigest: String
    let schemaDigest: String
    var localConversationCount: Int = 0
    var localConversationBytes: Int = 0
    var localConversationDigest: String? = nil
    var metrics: LocalInferenceMetrics? = nil
    let policyVersion = HamptonInvocationPolicy.version
}

struct HamptonAssistantSnapshot: Equatable, Sendable {
    var records: [SessionContextRecord] = []
    var proposal: HamptonReasonProposal?
    var receipts: [HamptonRoleReceipt] = []
    var attemptedInvocations: [LocalModelRole] = []
    var elapsedMilliseconds = 0
    var phase = "Ready for a local question"
    var turn = 0
    var admissionOutcome: HamptonAdmissionOutcome? = nil
    var localConversationCount = 0
    var localConversationBytes = 0
    var localConversationDigest: String? = nil
    var localConversationOmittedCount = 0
    var invocations: [HamptonInvocationReceipt] = []
    var evidence: AssistantEvidenceReceipt? = nil
}

enum HamptonAssistantFailure: Error, LocalizedError {
    case invalidProposal, timedOut, contextLimit
    var errorDescription: String? {
        switch self {
        case .invalidProposal: "The local model returned a proposal that did not pass the response checks. No answer or new session context was accepted."
        case .timedOut: "The local workflow reached its three-minute limit. No answer or new session context was accepted."
        case .contextLimit: "The current question, shared copy and kept lessons exceed the local request budget, even without earlier conversation. Use a shorter question or shared copy. No answer or new session context was accepted."
        }
    }
}

/// A native adaptation of Hampton's memory-selector / Reasons separation.
/// Model output is proposed text or IDs. This owner alone admits a completed
/// answer and a tentative in-memory bank; it has no action or durable-write port.
@MainActor
final class HamptonReasonsAssistant: AssistantClient {
    static let defaultContextModel = "qwen3:8b"
    private(set) var snapshot = HamptonAssistantSnapshot()
    var inFlightInvocations: [LocalModelRole]? { operation == nil ? nil : snapshot.attemptedInvocations }
    var onSnapshot: (@MainActor (HamptonAssistantSnapshot) -> Void)?
    /// The native request owner may revoke a still-valid model result when its
    /// source or observed target is no longer current. Capture per operation.
    var mayAdmitResponse: (@MainActor () -> Bool)?
    private(set) var contextEnabled: Bool
    private(set) var contextModel: String
    private let reasoner: any LocalRoleClient
    private let nativeRuntime: LocalQwenRuntime?
    private var selector: any LocalRoleClient
    private var bank = HamptonSessionContext()
    private var connected = false
    private var selectorConnected = false
    private var disposed = false
    private var generation: UInt64 = 0
    private var operation: UUID?
    private var operationStarted: ContinuousClock.Instant?
    private var admissionStage: HamptonAdmissionOutcome.Stage = .inputBudget
    private var admissionRole: LocalModelRole?
    private var admissionRequestID: String?
    private var retirements: [UUID: Task<Void, Never>] = [:]

    init(model: String = QwenAssistant.defaultModel, contextModel: String = defaultContextModel,
         reasoner: (any LocalRoleClient)? = nil, contextSelector: (any LocalRoleClient)? = nil,
         contextEnabled: Bool = false, nativeRuntime: LocalQwenRuntime? = nil) {
        self.nativeRuntime = nativeRuntime
        self.reasoner = reasoner ?? QwenAssistant(model: model, runtime: nativeRuntime)
        self.selector = contextSelector ?? QwenAssistant(model: contextModel, runtime: nativeRuntime)
        self.contextModel = contextModel
        self.contextEnabled = contextEnabled
    }

    func connect() async throws {
        guard !disposed else { throw QwenFailure.stopped }
        disconnect()
        let owner = generation
        try await reasoner.connect()
        try require(owner)
        connected = true
    }

    func setContextEnabled(_ enabled: Bool) {
        guard !disposed, enabled != contextEnabled else { return }
        if operation != nil { disconnect() }
        contextEnabled = enabled
        clearSessionContext()
    }

    func setContextModel(_ model: String) {
        guard !disposed, QwenAssistant.supportedModels.contains(model), model != contextModel else { return }
        disconnect()
        let previous = selector
        selector = QwenAssistant(model: model, runtime: nativeRuntime)
        contextModel = model
        clearSessionContext()
        let id = UUID()
        retirements[id] = Task { [weak self, previous] in
            await previous.shutdown()
            self?.retirements[id] = nil
        }
    }

    func clearSessionContext() {
        if operation != nil { disconnect() }
        bank.clear()
        snapshot = HamptonAssistantSnapshot(phase: "Session context cleared")
        publish()
    }

    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        guard !disposed, connected else { throw QwenFailure.unavailable }
        guard operation == nil else { throw QwenFailure.busy }
        let id = UUID(), owner = generation, started = ContinuousClock.now
        let admissionCheck = mayAdmitResponse
        let deadline = started.advanced(by: .seconds(180))
        operation = id
        operationStarted = started
        snapshot.proposal = nil; snapshot.receipts = []
        snapshot.attemptedInvocations = []; snapshot.elapsedMilliseconds = 0
        snapshot.admissionOutcome = nil
        snapshot.localConversationCount = 0; snapshot.localConversationBytes = 0
        snapshot.localConversationDigest = nil; snapshot.localConversationOmittedCount = 0
        snapshot.invocations = []
        snapshot.evidence = AssistantEvidenceReceipt(contextEnabled: contextEnabled,
            sourceIDsAvailable: request.localSourceIDs, lessonIDsAvailable: request.localLessons.map(\.modelID),
            conversationOfferedCount: request.localConversation.count,
            conversationOfferedDigest: request.localConversationDigest,
            omissions: contextEnabled ? [] : [.init(kind: .context, reason: .disabled)])
        admissionStage = .inputBudget; admissionRole = nil; admissionRequestID = nil
        let timeout = Task { [weak self] in
            do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
            guard let self, self.generation == owner, self.operation == id else { return }
            let outcome = HamptonAdmissionOutcome(status: .rejected, stage: self.admissionStage,
                role: self.admissionRole, requestID: self.admissionRequestID, reason: .timedOut)
            self.disconnect(outcome: outcome)
            self.snapshot.phase = "Local workflow timed out"; self.publish()
        }
        defer {
            timeout.cancel()
            if generation == owner, operation == id { operation = nil; operationStarted = nil }
        }
        var tentative = bank
        var receipts: [HamptonRoleReceipt] = []
        do {
            guard request.hasValidSelection, request.hasValidRevisionTarget, request.hasValidLocalLessons,
                  request.hasValidLocalConversation, request.hasValidLocalProfile, request.hasValidLocalControl else {
                throw QwenFailure.invalidResponse
            }
            guard !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  request.prompt.utf8.count <= 16_000, request.sourceText.utf8.count <= 100_000 else {
                throw HamptonAssistantFailure.contextLimit
            }
            let lessonInputs = request.localLessons.map(\.modelInput)
            let lessonIDs = request.localLessons.map(\.modelID)
            var reminders: [SessionContextRecord] = []
            // Keep the complete current source and user-confirmed lesson snapshot
            // within the reasoning budget before any optional inference occurs.
            checkpoint(.inputBudget, role: .reasoning)
            var prepared = try prepareReasoning(request: request, memories: lessonInputs, memoryIDs: lessonIDs)
            recordConversation(prepared.request, offeredCount: request.localConversation.count)
            if contextEnabled {
                let allCandidates = tentative.beginTurn(request: request)
                snapshot.evidence?.candidates.eligibleIDs = allCandidates.map(\.id)
                snapshot.evidence?.omissions.append(contentsOf: tentative.recentOmissions)
                checkpoint(.inputBudget, role: .memorySelection)
                if let selectionRequest = try boundedRequest(.memorySelection, question: request.prompt,
                    values: allCandidates.map(Self.candidateInput), key: "candidates") {
                    let offeredCandidates = Set(selectionRequest.input["candidates"]!.array!.compactMap { $0["id"]?.string })
                    recordOffered(selectionRequest, eligibleIDs: allCandidates.map(\.id))
                    checkpoint(.connection, request: selectionRequest)
                    setPhase("Choosing temporary context…")
                    try await connectSelector(owner, operation: id)
                    checkpoint(.generation, request: selectionRequest)
                    try beginInvocation(selectionRequest, owner: owner, operation: id)
                    let selection = try await selector.generate(selectionRequest)
                    try require(owner, operation: id)
                    completeInvocation(selection, request: selectionRequest)
                    checkpoint(.validation, request: selectionRequest)
                    let selected = try HamptonProposalValidator.parseSelection(selection, request: selectionRequest,
                        allowedCandidateIDs: offeredCandidates)
                    try tentative.retain(candidateIDs: selected, candidates: allCandidates)
                    snapshot.evidence?.candidates.selectedIDs = selected
                    receipts.append(try Self.receipt(selection, request: selectionRequest))
                    snapshot.receipts = receipts
                } else { recordOptionalBudgetOmission(kind: .candidates, ids: allCandidates.map(\.id)) }

                let eligible = tentative.eligibleReminders(for: request)
                snapshot.evidence?.reminders.eligibleIDs = eligible.map(\.id)
                checkpoint(.inputBudget, role: .memoryReminder)
                if let reminderRequest = try boundedRequest(.memoryReminder, question: request.prompt,
                    values: eligible.map(Self.recordInput), key: "memories") {
                    let offeredMemories = Set(reminderRequest.input["memories"]!.array!.compactMap { $0["id"]?.string })
                    recordOffered(reminderRequest, eligibleIDs: eligible.map(\.id))
                    checkpoint(.connection, request: reminderRequest)
                    setPhase("Finding useful earlier context…")
                    try await connectSelector(owner, operation: id)
                    checkpoint(.generation, request: reminderRequest)
                    try beginInvocation(reminderRequest, owner: owner, operation: id)
                    let reminder = try await selector.generate(reminderRequest)
                    try require(owner, operation: id)
                    completeInvocation(reminder, request: reminderRequest)
                    checkpoint(.validation, request: reminderRequest)
                    let ids = try HamptonProposalValidator.parseReminder(reminder, request: reminderRequest,
                        allowedMemoryIDs: offeredMemories)
                    reminders = try tentative.useReminderIDs(ids, eligible: eligible)
                    snapshot.evidence?.reminders.selectedIDs = ids
                    receipts.append(try Self.receipt(reminder, request: reminderRequest))
                    snapshot.receipts = receipts
                } else { recordOptionalBudgetOmission(kind: .reminders, ids: eligible.map(\.id)) }
            }
            let memoryIDs = lessonIDs + reminders.map(\.id)
            checkpoint(.inputBudget, role: .reasoning)
            prepared = try prepareReasoning(request: prepared.request,
                memories: lessonInputs + reminders.map(Self.recordInput), memoryIDs: memoryIDs)
            recordConversation(prepared.request, offeredCount: request.localConversation.count)
            let reasonRequest = prepared.roleRequest
            let sourceIDs = prepared.request.localSourceIDs
            snapshot.evidence?.reasoningSourceIDsOffered = sourceIDs
            snapshot.evidence?.reasoningMemoryIDsOffered = memoryIDs
            checkpoint(.generation, request: reasonRequest)
            setPhase(request.revisionTarget == nil ? "Preparing an answer from the supplied context…" : "Preparing a passage revision for review…")
            try beginInvocation(reasonRequest, owner: owner, operation: id)
            let result = try await reasoner.generate(reasonRequest)
            try require(owner, operation: id)
            completeInvocation(result, request: reasonRequest)
            checkpoint(.validation, request: reasonRequest)
            let proposal: HamptonReasonProposal?
            let revision: PassageRevisionProposal?
            if let target = request.revisionTarget {
                guard result.role == .reasoning else { throw HamptonProposalValidationError.wrongRole }
                guard result.requestID.utf8.elementsEqual(reasonRequest.id.utf8) else { throw HamptonProposalValidationError.wrongRequest }
                revision = try PassageRevisionValidator.parse(result.text, target: target, sourceIDs: sourceIDs, memoryIDs: memoryIDs)
                proposal = nil
            } else {
                proposal = try HamptonProposalValidator.parseReason(result, request: reasonRequest,
                    allowedSourceIDs: Set(sourceIDs), allowedMemoryIDs: Set(memoryIDs))
                revision = nil
            }
            snapshot.evidence?.sourceIDsCited = proposal?.sourceIDs ?? revision?.sourceIDs ?? []
            snapshot.evidence?.memoryIDsCited = proposal?.memoryIDs ?? revision?.memoryIDs ?? []
            receipts.append(try Self.receipt(result, request: reasonRequest,
                conversation: prepared.request.localConversation))
            try require(owner, operation: id)
            checkpoint(.publication, request: reasonRequest)
            guard admissionCheck?() ?? true else {
                snapshot.admissionOutcome = HamptonAdmissionOutcome(status: .stopped, stage: .publication,
                    role: .reasoning, requestID: reasonRequest.id, reason: .staleContext)
                throw QwenFailure.stopped
            }
            try require(owner, operation: id)
            // No suspension between the final ownership check and state publication.
            if contextEnabled { bank = tentative }
            updateElapsed()
            snapshot = HamptonAssistantSnapshot(records: bank.records, proposal: proposal,
                receipts: receipts, attemptedInvocations: snapshot.attemptedInvocations,
                elapsedMilliseconds: snapshot.elapsedMilliseconds, phase: "Response checks passed", turn: bank.turn,
                admissionOutcome: HamptonAdmissionOutcome(status: .accepted, stage: .publication,
                    role: .reasoning, requestID: reasonRequest.id, reason: nil),
                localConversationCount: prepared.request.localConversation.count,
                localConversationBytes: prepared.request.localConversationUTF8Bytes,
                localConversationDigest: prepared.request.localConversationDigest,
                localConversationOmittedCount: request.localConversation.count - prepared.request.localConversation.count,
                invocations: snapshot.invocations, evidence: snapshot.evidence)
            publish()
            try require(owner, operation: id)
            if let revision { onEvent(.revision(revision)) }
            else if let proposal { onEvent(.text(proposal.answer)) }
        } catch {
            if generation == owner, operation == id {
                endPendingInvocations(cancelled: Task.isCancelled || (error as? QwenFailure) == .stopped)
                snapshot.proposal = nil; snapshot.receipts = receipts
                updateElapsed()
                if snapshot.admissionOutcome?.status != .stopped {
                    snapshot.admissionOutcome = HamptonAdmissionOutcome.failure(error, stage: admissionStage,
                        role: admissionRole, requestID: admissionRequestID)
                }
                snapshot.phase = "No new answer or context accepted"; publish()
            }
            if ContinuousClock.now >= deadline { throw HamptonAssistantFailure.timedOut }
            if error is HamptonProposalValidationError || error is SessionContextError {
                throw HamptonAssistantFailure.invalidProposal
            }
            if (error as? QwenFailure) == .contextLimit { throw HamptonAssistantFailure.contextLimit }
            throw error
        }
    }

    func disconnect() {
        let outcome = operation == nil ? nil : HamptonAdmissionOutcome(status: .stopped, stage: admissionStage,
            role: admissionRole, requestID: admissionRequestID, reason: .cancelled)
        disconnect(outcome: outcome)
    }

    private func disconnect(outcome: HamptonAdmissionOutcome?) {
        updateElapsed()
        if operation != nil { endPendingInvocations(cancelled: true) }
        if let outcome { snapshot.admissionOutcome = outcome }
        operationStarted = nil
        generation &+= 1; operation = nil; connected = false; selectorConnected = false
        reasoner.disconnect(); selector.disconnect()
        snapshot.proposal = nil; snapshot.phase = "Disconnected"; publish()
    }

    private func checkpoint(_ stage: HamptonAdmissionOutcome.Stage, request: LocalRoleRequest) {
        admissionStage = stage; admissionRole = request.role; admissionRequestID = request.id
    }

    private func checkpoint(_ stage: HamptonAdmissionOutcome.Stage, role: LocalModelRole) {
        admissionStage = stage; admissionRole = role; admissionRequestID = nil
    }

    func shutdown() async {
        disposed = true
        disconnect(); clearSessionContext()
        await reasoner.shutdown(); await selector.shutdown()
        for retirement in Array(retirements.values) { await retirement.value }
    }

    private func require(_ owner: UInt64, operation id: UUID? = nil) throws {
        guard !disposed, owner == generation, !Task.isCancelled,
              id == nil || operation == id else { throw QwenFailure.stopped }
    }

    private func connectSelector(_ owner: UInt64, operation id: UUID) async throws {
        try require(owner, operation: id)
        if !selectorConnected {
            try await selector.connect()
            try require(owner, operation: id)
            selectorConnected = true
        }
    }

    private func beginInvocation(_ request: LocalRoleRequest, owner: UInt64, operation id: UUID) throws {
        try require(owner, operation: id)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let invocation = HamptonInvocationReceipt(id: request.id, role: request.role,
            inputDigest: Self.digest(try encoder.encode(request.input)),
            systemDigest: Self.digest(Data(request.systemInstruction.utf8)),
            schemaDigest: Self.digest(try encoder.encode(request.outputSchema)))
        snapshot.attemptedInvocations.append(request.role)
        snapshot.invocations.append(invocation)
        switch request.role {
        case .memorySelection:
            snapshot.evidence?.candidates.dispatchedIDs = Self.ids(request, key: "candidates")
        case .memoryReminder:
            snapshot.evidence?.reminders.dispatchedIDs = Self.ids(request, key: "memories")
        case .reasoning:
            let conversationCount = snapshot.evidence?.conversationPreparedCount
            let conversationDigest = snapshot.evidence?.conversationPreparedDigest
            snapshot.evidence?.reasoningSourceIDsDispatched = Self.ids(request, key: "sources")
            snapshot.evidence?.reasoningMemoryIDsDispatched = Self.ids(request, key: "memories")
            snapshot.evidence?.conversationDispatchedCount = conversationCount
            snapshot.evidence?.conversationDispatchedDigest = conversationDigest
        }
        updateElapsed()
        // No observer callback between counting this invocation and entering the
        // transport. Phase/final publications and stop capture expose the count.
    }

    private func completeInvocation(_ result: LocalRoleResult, request: LocalRoleRequest) {
        guard let index = snapshot.invocations.firstIndex(where: { $0.id == request.id && $0.outcome == .dispatched }) else { return }
        snapshot.invocations[index].outcome = .completed
        snapshot.invocations[index].model = result.model
        snapshot.invocations[index].elapsedMilliseconds = result.elapsedMilliseconds
        snapshot.invocations[index].outputDigest = Self.digest(Data(result.text.utf8))
        snapshot.invocations[index].metrics = result.metrics
    }

    private func endPendingInvocations(cancelled: Bool) {
        for index in snapshot.invocations.indices where snapshot.invocations[index].outcome == .dispatched {
            snapshot.invocations[index].outcome = cancelled ? .cancelled : .failed
        }
    }

    private static func ids(_ request: LocalRoleRequest, key: String) -> [String] {
        request.input[key]?.array?.compactMap { $0["id"]?.string } ?? []
    }

    private func recordOffered(_ request: LocalRoleRequest, eligibleIDs: [String]) {
        let selecting = request.role == .memorySelection
        let offered = Self.ids(request, key: selecting ? "candidates" : "memories")
        if selecting { snapshot.evidence?.candidates.offeredIDs = offered }
        else { snapshot.evidence?.reminders.offeredIDs = offered }
        recordOptionalBudgetOmission(kind: selecting ? .candidates : .reminders,
            ids: eligibleIDs.filter { !offered.contains($0) })
    }

    private func recordOptionalBudgetOmission(kind: AssistantEvidenceOmission.Kind, ids: [String]) {
        guard !ids.isEmpty else { return }
        snapshot.evidence?.omissions.append(.init(kind: kind, reason: .budget, ids: ids, count: ids.count))
    }

    private func updateElapsed() {
        guard let operationStarted else { return }
        let components = operationStarted.duration(to: .now).components
        snapshot.elapsedMilliseconds = max(0, Int(components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000))
    }

    private func setPhase(_ phase: String) { updateElapsed(); snapshot.phase = phase; publish() }
    private func publish() { onSnapshot?(snapshot) }

    /// Mandatory current input is never cut to fit history. Drop only complete
    /// oldest exchanges, before any optional selection call, and recheck after
    /// reminders are admitted. This does not mutate the captured Send request.
    private func prepareReasoning(request: AssistantRequest, memories: [JSONValue], memoryIDs: [String]) throws
        -> (request: AssistantRequest, roleRequest: LocalRoleRequest) {
        var supplied = request
        while true {
            let current = try JSONDecoder().decode(JSONValue.self, from: Data(supplied.localContextInput.utf8))
            let sourceIDs = supplied.localSourceIDs
            let sources = sourceIDs.map { JSONValue.object(["id": .string($0), "label": .string($0)]) }
            do {
                let roleRequest = try Self.makeRequest(.reasoning,
                    fields: ["context": current, "sources": .array(sources), "memories": .array(memories)],
                    sourceIDs: sourceIDs, memoryIDs: memoryIDs, revisionTarget: supplied.revisionTarget)
                return (supplied, roleRequest)
            } catch HamptonAssistantFailure.contextLimit {
                guard !supplied.localConversation.isEmpty else { throw HamptonAssistantFailure.contextLimit }
                supplied = supplied.replacingLocalConversation(Array(supplied.localConversation.dropFirst()))
            }
        }
    }

    private func recordConversation(_ request: AssistantRequest, offeredCount: Int) {
        let omittedCount = offeredCount - request.localConversation.count
        snapshot.localConversationCount = request.localConversation.count
        snapshot.localConversationBytes = request.localConversationUTF8Bytes
        snapshot.localConversationDigest = request.localConversationDigest
        snapshot.localConversationOmittedCount = omittedCount
        if var evidence = snapshot.evidence {
            evidence.conversationPreparedCount = request.localConversation.count
            evidence.conversationPreparedDigest = request.localConversationDigest
            evidence.omissions.removeAll { $0.kind == .conversation && $0.reason == .budget }
            if omittedCount > 0 {
                evidence.omissions.append(.init(kind: .conversation, reason: .budget, count: omittedCount))
            }
            snapshot.evidence = evidence
        }
    }

    private func boundedRequest(_ role: LocalModelRole, question: String, values: [JSONValue], key: String) throws -> LocalRoleRequest? {
        var offered = values
        while !offered.isEmpty {
            let ids = offered.compactMap { $0["id"]?.string }
            do {
                return try Self.makeRequest(role, fields: ["question": .string(question), key: .array(offered)],
                    memoryIDs: role == .memoryReminder ? ids : [], candidateIDs: role == .memorySelection ? ids : [])
            } catch HamptonAssistantFailure.contextLimit {
                offered.removeLast()
            }
        }
        // No optional inference or selector connection when budgeting leaves no IDs.
        return nil
    }

    static let maximumEncodedInputBytes = 22_000

    /// Pure preflight through the same envelope builder used by inference. Optional
    /// conversation is omitted just as prepareReasoning can omit it to fit; the
    /// current question, full source, settings and confirmed lessons are never cut.
    static func fitsMandatoryReasoningInput(_ request: AssistantRequest) -> Bool {
        let supplied = request.replacingLocalConversation([])
        guard supplied.prompt.utf8.count <= 16_000, supplied.sourceText.utf8.count <= 100_000,
              let current = try? JSONDecoder().decode(JSONValue.self, from: Data(supplied.localContextInput.utf8)) else { return false }
        let sources = supplied.localSourceIDs.map { JSONValue.object(["id": .string($0), "label": .string($0)]) }
        return (try? makeRequest(.reasoning,
            fields: ["context": current, "sources": .array(sources), "memories": .array(supplied.localLessons.map(\.modelInput))],
            sourceIDs: supplied.localSourceIDs, memoryIDs: supplied.localLessons.map(\.modelID),
            revisionTarget: supplied.revisionTarget)) != nil
    }

    private static func makeRequest(_ role: LocalModelRole, fields: [String: JSONValue], sourceIDs: [String] = [],
                             memoryIDs: [String] = [], candidateIDs: [String] = [],
                             revisionTarget: RevisionTarget? = nil) throws -> LocalRoleRequest {
        let id = UUID().uuidString
        let schema = revisionTarget.map { PassageRevisionValidator.schema(target: $0, sourceIDs: sourceIDs, memoryIDs: memoryIDs) }
            ?? HamptonProposalValidator.schema(for: role, requestID: id,
                sourceIDs: sourceIDs, memoryIDs: memoryIDs, candidateIDs: candidateIDs)
        var input = fields
        input["requestID"] = .string(id)
        input["outputSchema"] = schema
        let request = LocalRoleRequest(id: id, role: role, input: .object(input), outputSchema: schema,
            systemInstructionOverride: revisionTarget == nil ? nil : AssistantInstructions.passageRevisionText + "\n" + LocalLessonGuidance.text
                + (fields["context"]?["localConversation"] == nil ? "" : "\n" + LocalConversationGuidance.text))
        // Conservative encoded envelope preflight, including JSON-in-message escaping.
        // Transport independently enforces its exact 24 KB /api/chat body bound.
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let text = String(decoding: try encoder.encode(request.input), as: UTF8.self)
        let envelope: JSONValue = .object(["system": .string(request.systemInstruction), "input": .string(text), "format": schema])
        guard try encoder.encode(envelope).count <= maximumEncodedInputBytes else { throw HamptonAssistantFailure.contextLimit }
        return request
    }

    private static func candidateInput(_ record: SessionContextCandidate) -> JSONValue {
        .object(["id": .string(record.id), "text": .string(record.text), "kind": .string(record.kind.rawValue),
                 "sourceID": .string(record.sourceID)])
    }

    private static func recordInput(_ record: SessionContextRecord) -> JSONValue {
        .object(["id": .string(record.id), "text": .string(record.text), "kind": .string(record.kind.rawValue),
                 "sourceID": .string(record.sourceID)])
    }

    private static func receipt(_ result: LocalRoleResult, request: LocalRoleRequest,
                                conversation: [AssistantConversationExchange] = []) throws -> HamptonRoleReceipt {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return HamptonRoleReceipt(id: request.id, role: request.role, model: result.model,
            elapsedMilliseconds: result.elapsedMilliseconds, inputDigest: digest(try encoder.encode(request.input)),
            outputDigest: digest(Data(result.text.utf8)), systemDigest: digest(Data(request.systemInstruction.utf8)),
            schemaDigest: digest(try encoder.encode(request.outputSchema)),
            localConversationCount: conversation.count,
            localConversationBytes: AssistantConversation.utf8ByteCount(for: conversation),
            localConversationDigest: AssistantConversation.digest(for: conversation), metrics: result.metrics)
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
