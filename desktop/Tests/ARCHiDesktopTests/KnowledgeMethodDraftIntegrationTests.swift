import Foundation
import XCTest
@testable import ARCHiDesktop

/// Production request ownership and Hampton admission with in-process role
/// clients only. No model, child process, external request or personal profile.
@MainActor
final class KnowledgeMethodDraftIntegrationTests: XCTestCase {
    func testReviewedConceptDraftCapturesExactContextWithoutEditingOrSavingWork() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        fixture.store.setAssistantRoute(.codex)
        fixture.store.share(text: Fixture.unrelatedText, name: "unrelated-copy.txt")
        fixture.store.selectText(range: NSRange(location: 0, length: Fixture.unrelatedText.utf16.count),
            sourceRevision: fixture.store.sourceRevision)
        fixture.store.prompt = "Unsent private chat draft that must stay in the editor."
        fixture.store.documentRequirements = .init(mustBeShorter: false, preserveNumbersAndLinks: true)
        let priorPrompt = fixture.store.prompt
        let priorRevision = fixture.store.sourceRevision
        let priorSelection = fixture.store.textSelection
        let priorRequirements = fixture.store.documentRequirements
        let page = try fixture.page()
        let requirements = DocumentWorkRequirements(mustBeShorter: true, preserveNumbersAndLinks: false)
        let context = try XCTUnwrap(KnowledgePageContext.make(page: page, quotes: [Fixture.passage]))

        XCTAssertTrue(fixture.store.canDraftKnowledgeMethod(page: page))
        XCTAssertTrue(fixture.store.draftKnowledgeMethod(page: page, requirements: requirements))
        try await fixture.wait { !fixture.store.isWorking }

        let draft = try XCTUnwrap(fixture.store.currentKnowledgeMethodDraft(for: page), fixture.store.status)
        let sent = try XCTUnwrap(fixture.reasoner.requests.first)
        let sentContext = try XCTUnwrap(sent.input["context"])
        let receipt = try XCTUnwrap(fixture.store.compareResults[.qwen]?.receipt)
        let target = try KnowledgeMethodDraftRequest(context: context, requirements: requirements, requestID: draft.requestID)
        XCTAssertEqual(fixture.reasoner.requests.map(\.role), [.reasoning])
        XCTAssertTrue(fixture.selector.requests.isEmpty)
        XCTAssertEqual(sentContext["localKnowledge"], context.modelInput)
        XCTAssertEqual(sentContext["question"]?.string, target.prompt)
        XCTAssertEqual(sentContext["source"], .null)
        XCTAssertEqual(sentContext["selection"], .null)
        XCTAssertNil(sentContext["revisionTarget"])
        XCTAssertNil(sentContext["localProfile"])
        XCTAssertNil(sentContext["localConversation"])
        XCTAssertNil(sentContext["companion"])
        XCTAssertEqual(sent.input["memories"]?.array, [])
        let input = String(decoding: try JSONEncoder().encode(sent.input), as: UTF8.self)
        XCTAssertFalse(input.contains(Fixture.unrelatedText))
        XCTAssertFalse(input.contains(priorPrompt))
        XCTAssertEqual(draft.instruction, Fixture.instruction)
        XCTAssertEqual(draft.requirements, requirements)
        XCTAssertEqual(draft.binding, page.binding)
        XCTAssertEqual(receipt.requestID, draft.requestID)
        XCTAssertEqual(receipt.state, .complete)
        XCTAssertEqual(receipt.knowledgeDependencies, [page.binding])
        XCTAssertEqual(receipt.readingDependencies, page.anchors.map(\.source))
        XCTAssertEqual(receipt.knowledgeContextDigest, context.digest)
        XCTAssertEqual(receipt.localInvocations, [.reasoning])
        XCTAssertTrue(fixture.store.isCurrentReplyContext(receipt))
        XCTAssertEqual(fixture.store.sharedText, Fixture.unrelatedText)
        XCTAssertEqual(fixture.store.sourceRevision, priorRevision)
        XCTAssertEqual(fixture.store.textSelection, priorSelection)
        XCTAssertEqual(fixture.store.prompt, priorPrompt)
        XCTAssertEqual(fixture.store.documentRequirements, priorRequirements)
        XCTAssertEqual(fixture.store.route, .codex)
        XCTAssertEqual(fixture.store.assistantProvider, .codex)
        XCTAssertEqual(fixture.store.connectionState, fixture.store.connection(for: .codex))
        XCTAssertEqual(fixture.store.connectionState, .disconnected)
        XCTAssertEqual(fixture.store.connection(for: .qwen), .ready)
        fixture.assertNoSavedWork()

        let task = try XCTUnwrap(fixture.store.tokenSteward.tasks.first)
        XCTAssertEqual(fixture.store.tokenSteward.tasks.count, 1)
        XCTAssertEqual(task.id, draft.requestID)
        XCTAssertEqual(task.lanes.map(\.provider), [AssistantProvider.qwen.name])
        XCTAssertEqual(task.lanes.first?.state, "complete")
        XCTAssertEqual(task.lanes.first?.dispatched, true)
        XCTAssertTrue(task.outcomes.isEmpty)
        XCTAssertFalse(task.userUseful)
        XCTAssertNil(task.documentReading)
        let observation = try XCTUnwrap(fixture.store.tokenSteward.observations.first)
        XCTAssertEqual(observation.taskID, draft.requestID)
        XCTAssertEqual(observation.resource, .localInference)
        XCTAssertEqual(observation.role, LocalModelRole.reasoning.rawValue)
        XCTAssertEqual(observation.modelDigest, fixture.reasoner.model.digest)
        XCTAssertEqual(fixture.external.calls, 0)
        XCTAssertEqual(fixture.external.connections, 0)

        // Keeping is a distinct explicit action; even then it creates only an
        // untested candidate, without an applied document outcome or usefulness.
        XCTAssertTrue(fixture.store.keepKnowledgeProcedure(page: page, title: "My chosen method name",
            instruction: draft.instruction, requirements: draft.requirements))
        let kept = try XCTUnwrap(fixture.store.documentProcedures.latestProcedures.first)
        XCTAssertEqual(kept.title, "My chosen method name")
        XCTAssertEqual(kept.instruction, draft.instruction)
        XCTAssertEqual(kept.knowledgeOrigin, page.binding)
        XCTAssertTrue(fixture.store.documentWork.records.isEmpty)
        XCTAssertTrue(fixture.store.evolution.usefulReceipts.isEmpty)
        XCTAssertTrue(fixture.store.keptLessons.isEmpty)
        XCTAssertTrue(fixture.store.tokenSteward.tasks.allSatisfy { $0.outcomes.isEmpty })
        fixture.store.discardKnowledgeMethodDraft()
        XCTAssertNil(fixture.store.currentKnowledgeMethodDraft(for: page))
        XCTAssertEqual(fixture.store.route, .codex)
        XCTAssertEqual(fixture.store.assistantProvider, .codex)
        XCTAssertEqual(fixture.store.connectionState, fixture.store.connection(for: .codex))
        XCTAssertEqual(fixture.store.connectionState, .disconnected)
    }

    func testEnabledSessionContextAndEarlierDialogueAreNeitherReadNorExtendedByDrafting() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        fixture.store.setLocalConversationEnabled(true)
        fixture.store.setSessionContextEnabled(true)
        fixture.store.prompt = "Remember this synthetic context for the next ordinary question."
        fixture.store.submit()
        try await fixture.wait { !fixture.store.isWorking }
        let records = fixture.assistant.snapshot.records
        let conversation = fixture.store.nextReplyConversation
        XCTAssertFalse(records.isEmpty)
        XCTAssertFalse(conversation.isEmpty)
        let selectorCalls = fixture.selector.requests.count
        let selectorConnections = fixture.selector.connections
        let reasonerCalls = fixture.reasoner.requests.count
        let priorPrompt = "Another unsent chat draft."
        fixture.store.prompt = priorPrompt
        let page = try fixture.page()

        XCTAssertTrue(fixture.store.draftKnowledgeMethod(page: page, requirements: .init()))
        try await fixture.wait { !fixture.store.isWorking }
        XCTAssertNotNil(fixture.store.currentKnowledgeMethodDraft(for: page))
        XCTAssertEqual(fixture.reasoner.requests.count, reasonerCalls + 1)
        XCTAssertEqual(fixture.selector.requests.count, selectorCalls)
        XCTAssertEqual(fixture.selector.connections, selectorConnections)
        XCTAssertTrue(fixture.store.sessionContextEnabled)
        XCTAssertEqual(fixture.assistant.snapshot.records, records)
        XCTAssertEqual(fixture.store.nextReplyConversation, conversation)
        XCTAssertEqual(fixture.store.prompt, priorPrompt)
        let sent = try XCTUnwrap(fixture.reasoner.requests.last)
        XCTAssertEqual(sent.input["memories"]?.array, [])
        XCTAssertNil(sent.input["context"]?["localConversation"])
        XCTAssertEqual(fixture.assistant.snapshot.localConversationCount, 0)
        XCTAssertEqual(fixture.assistant.snapshot.evidence?.contextEnabled, false)
        fixture.assertNoSavedWork()
        XCTAssertEqual(fixture.external.calls, 0)
    }

    func testSourceReplacementBlocksBothDelayedAdmissionAndLaterDraftRetrieval() async throws {
        for replaceBeforeCompletion in [true, false] {
            let fixture = Fixture()
            defer { fixture.clean() }
            let page = try fixture.page()
            fixture.reasoner.pauseGeneration = replaceBeforeCompletion
            XCTAssertTrue(fixture.store.draftKnowledgeMethod(page: page, requirements: .init()))
            if replaceBeforeCompletion {
                try await fixture.wait { fixture.reasoner.hasPendingGeneration }
                XCTAssertTrue(fixture.store.isDraftingKnowledgeMethod)
            } else {
                try await fixture.wait { !fixture.store.isWorking }
                XCTAssertNotNil(fixture.store.currentKnowledgeMethodDraft(for: page))
            }
            let receipt = try XCTUnwrap(fixture.store.compareResults[.qwen]?.receipt)
            let other = ReadingSourceLibrary(url: fixture.readingURL)
            let source = try XCTUnwrap(other.sources.first)
            _ = try other.replace(id: source.id, title: source.title,
                text: "A replacement synthetic source no longer contains the captured passage.")
            XCTAssertFalse(fixture.store.readingSources.isCurrentOnDisk)
            if replaceBeforeCompletion {
                try fixture.reasoner.resolve()
                try await fixture.wait { fixture.reasoner.finishedGenerations == 1 && !fixture.store.isWorking }
                XCTAssertNotEqual(fixture.store.compareResults[.qwen]?.state, .complete)
                XCTAssertNil(fixture.store.knowledgeMethodDraft)
                // Rejected content still incurred the completed local inference.
                let finalReceipt = try XCTUnwrap(fixture.store.compareResults[.qwen]?.receipt)
                XCTAssertEqual(finalReceipt.localInvocationReceipts?.last?.metrics?.inputTokens, 321)
                XCTAssertEqual(finalReceipt.localInvocationReceipts?.last?.metrics?.outputTokens, 37)
                let observation = try XCTUnwrap(fixture.store.tokenSteward.observations.first {
                    $0.taskID == receipt.requestID && $0.role == LocalModelRole.reasoning.rawValue
                })
                XCTAssertEqual(observation.inputTokens, 321)
                XCTAssertEqual(observation.outputTokens, 37)
                XCTAssertEqual(observation.resource, .localInference)
                XCTAssertEqual(observation.modelDigest, fixture.reasoner.model.digest)
            }
            XCTAssertNil(fixture.store.currentKnowledgeMethodDraft(for: page))
            XCTAssertFalse(fixture.store.isCurrentReplyContext(receipt))
            XCTAssertFalse(fixture.store.canDraftKnowledgeMethod(page: page))
            fixture.assertNoSavedWork()
            XCTAssertEqual(fixture.external.calls, 0)
            XCTAssertEqual(fixture.external.connections, 0)
        }
    }

    func testCancellationAndLocalFailureNeverDispatchAnExternalFallback() async throws {
        for cancel in [true, false] {
            let fixture = Fixture()
            defer { fixture.clean() }
            fixture.store.setAssistantRoute(.native)
            let page = try fixture.page()
            fixture.reasoner.pauseGeneration = true
            XCTAssertTrue(fixture.store.draftKnowledgeMethod(page: page, requirements: .init()))
            try await fixture.wait { fixture.reasoner.hasPendingGeneration }
            if cancel {
                fixture.store.cancelWork()
                try fixture.reasoner.resolve() // Deliberately deliver success after Stop.
            } else {
                fixture.reasoner.fail(QwenFailure.unavailable)
            }
            try await fixture.wait { fixture.reasoner.finishedGenerations == 1 && !fixture.store.isWorking }
            XCTAssertFalse(fixture.store.isDraftingKnowledgeMethod)
            XCTAssertNil(fixture.store.currentKnowledgeMethodDraft(for: page))
            XCTAssertNil(fixture.store.knowledgeMethodDraft)
            XCTAssertEqual(fixture.store.compareResults[.qwen]?.state, cancel ? .cancelled : .failed)
            XCTAssertNil(fixture.store.compareResults[.codex])
            XCTAssertEqual(fixture.reasoner.requests.count, 1)
            XCTAssertTrue(fixture.selector.requests.isEmpty)
            XCTAssertEqual(fixture.external.calls, 0)
            XCTAssertEqual(fixture.external.connections, 0)
            XCTAssertTrue(fixture.store.tokenSteward.tasks.allSatisfy { task in
                task.outcomes.isEmpty && task.lanes.allSatisfy { $0.provider == AssistantProvider.qwen.name }
            })
            fixture.assertNoSavedWork()
        }
    }

    @MainActor
    private final class Fixture {
        static let passage = "A direct polite request can preserve an action while removing introductory padding."
        static let instruction = "Shorten the selected request by removing introductory padding while preserving its action."
        static let unrelatedText = "An unrelated private working copy with invoice 742 and a Friday deadline."
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-method-draft-integration-\(UUID())")
        let reasoner = MethodDraftRoleClient(name: "draft-reasoner-fixture")
        let selector = MethodDraftRoleClient(name: "draft-selector-fixture")
        let external = MethodDraftExternalClient()
        var preference: URL { directory.appendingPathComponent("preferences.json") }
        var readingURL: URL { preference.deletingPathExtension().appendingPathExtension("reading-sources.json") }
        lazy var assistant = HamptonReasonsAssistant(reasoner: reasoner, contextSelector: selector)
        lazy var store: CompanionStore = {
            let store = CompanionStore(preferenceURL: preference, assistant: assistant,
                assistantFactory: { [assistant, external] provider, _ in
                    if provider == .qwen { return assistant }
                    return external
                },
                allowsPlay: false, tokenSteward: TokenStewardStore())
            store.setAssistantRoute(.automatic)
            store.setLocalWorkPreference(.reasoning)
            return store
        }()

        func page() throws -> KnowledgePage {
            let source = try store.readingSources.keep(title: "Synthetic source", text: Self.passage)
            let anchor = try store.readingSources.makeAnchor(sourceID: source.id,
                range: NSRange(location: 0, length: source.text.utf16.count))
            let draft = try store.readingSources.saveKnowledgePage(title: "Concise requests",
                body: "Synthetic interpretation: remove introductory padding while keeping the requested action.",
                kind: .concept, anchors: [anchor])
            return try store.readingSources.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        }

        func assertNoSavedWork(file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertTrue(store.documentProcedures.latestProcedures.isEmpty, file: file, line: line)
            XCTAssertTrue(store.documentWork.records.isEmpty, file: file, line: line)
            XCTAssertTrue(store.evolution.usefulReceipts.isEmpty, file: file, line: line)
            XCTAssertTrue(store.keptLessons.isEmpty, file: file, line: line)
            XCTAssertTrue(store.tokenSteward.tasks.allSatisfy { $0.outcomes.isEmpty }, file: file, line: line)
        }

        func wait(_ condition: @MainActor () -> Bool) async throws {
            for _ in 0..<400 {
                if condition() { return }
                try await Task.sleep(for: .milliseconds(5))
            }
            XCTFail("Timed out: \(store.status) | \(store.knowledgeMethodDraftMessage ?? "none")")
            throw AssistantFailure.timedOut
        }

        func clean() {
            store.cancelWork(); store.disconnectAssistant()
            assistant.onSnapshot = nil
            reasoner.fail(QwenFailure.stopped); selector.fail(QwenFailure.stopped)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

/// Disconnect leaves held generation available so late transport completion
/// exercises production ownership checks instead of a cooperative fake.
@MainActor
private final class MethodDraftRoleClient: LocalRoleClient {
    let model: QwenModelMetadata
    private(set) var requests: [LocalRoleRequest] = []
    private(set) var connections = 0
    private(set) var finishedGenerations = 0
    var pauseGeneration = false
    private var pending: (LocalRoleRequest, CheckedContinuation<LocalRoleResult, Error>)?
    var hasPendingGeneration: Bool { pending != nil }

    init(name: String) {
        model = QwenModelMetadata(name: name, family: "fixture", parameterSize: "fixture",
            quantization: "fixture", digest: String(repeating: "a", count: 64))
    }

    func connect() async throws { connections += 1 }
    func disconnect() {}
    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
        requests.append(request)
        defer { finishedGenerations += 1 }
        if pauseGeneration {
            return try await withCheckedThrowingContinuation { pending = (request, $0) }
        }
        return try result(for: request)
    }
    func resolve() throws {
        guard let held = pending else { throw AssistantFailure.unavailable }
        let result = try result(for: held.0)
        pending = nil
        held.1.resume(returning: result)
    }
    func fail(_ error: Error) {
        let held = pending
        pending = nil
        held?.1.resume(throwing: error)
    }

    private func result(for request: LocalRoleRequest) throws -> LocalRoleResult {
        func ids(_ field: String) -> [String] {
            request.input[field]?.array?.compactMap { $0["id"]?.string } ?? []
        }
        var payload: [String: JSONValue] = ["requestID": .string(request.id)]
        switch request.role {
        case .memorySelection:
            payload["schema"] = .string("archi-session-selection/v1")
            payload["candidateIDs"] = .array(ids("candidates").prefix(1).map(JSONValue.string))
        case .memoryReminder:
            let memories = Array(ids("memories").prefix(3))
            payload["schema"] = .string("archi-session-reminder/v1")
            payload["decision"] = .string(memories.isEmpty ? "NONE" : "SELECT")
            payload["memoryIDs"] = .array(memories.map(JSONValue.string))
        case .reasoning:
            let isMethod = request.input["context"]?["localKnowledge"] != nil
            payload["schema"] = .string("archi-reason-proposal/v1")
            payload["kind"] = .string("ANSWER")
            payload["answer"] = .string(isMethod
                ? "Shorten the selected request by removing introductory padding while preserving its action."
                : "Earlier synthetic reply.")
            payload["uncertainty"] = .string("")
            payload["sourceIDs"] = .array(ids("sources").filter { !isMethod || $0.hasPrefix("knowledge-") }.map(JSONValue.string))
            payload["memoryIDs"] = .array(ids("memories").map(JSONValue.string))
        }
        return LocalRoleResult(requestID: request.id, role: request.role,
            text: String(decoding: try JSONEncoder().encode(JSONValue.object(payload)), as: UTF8.self),
            model: model, elapsedMilliseconds: 7,
            metrics: LocalInferenceMetrics(inputTokens: 321, outputTokens: 37))
    }
}

@MainActor
private final class MethodDraftExternalClient: AssistantClient {
    private(set) var calls = 0
    private(set) var connections = 0
    func connect() async throws { connections += 1 }
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1
        throw AssistantFailure.unavailable
    }
}
