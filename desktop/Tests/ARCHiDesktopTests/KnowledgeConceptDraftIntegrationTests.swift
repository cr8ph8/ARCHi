import Foundation
import XCTest
@testable import ARCHiDesktop

/// Exercise the existing owner and admission with in-process transports only.
/// No model process, external service or personal profile is used.
@MainActor
final class KnowledgeConceptDraftIntegrationTests: XCTestCase {
    func testAcquisitionUsesOnlySelectedEvidenceAndExplicitEditorSaveCreatesUnreviewedDraft() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        fixture.store.setAssistantRoute(.codex)
        fixture.store.setLocalWorkPreference(.compact)
        fixture.store.share(text: Fixture.unrelatedText, name: "unrelated-copy.txt")
        fixture.store.selectText(range: NSRange(location: 0, length: Fixture.unrelatedText.utf16.count),
            sourceRevision: fixture.store.sourceRevision)
        fixture.store.prompt = "Unsent private question."
        let priorRevision = fixture.store.sourceRevision
        let priorSelection = fixture.store.textSelection
        let anchors = try fixture.anchors()
        XCTAssertTrue(fixture.store.draftKnowledgeConcept(title: "Direct requests", anchors: anchors))
        try await fixture.wait { !fixture.store.isWorking }

        let draft = try XCTUnwrap(fixture.store.currentKnowledgeConceptDraft, fixture.store.status)
        let sent = try XCTUnwrap(fixture.reasoner.requests.first)
        let context = try XCTUnwrap(sent.input["context"])
        let receipt = try XCTUnwrap(fixture.store.compareResults[.qwen]?.receipt)
        let target = try KnowledgeConceptDraftRequest(requestID: draft.requestID, title: draft.title,
            anchors: anchors, quotes: [Fixture.passage])
        XCTAssertEqual(fixture.reasoner.requests.map(\.role), [.reasoning])
        XCTAssertTrue(fixture.selector.requests.isEmpty)
        XCTAssertEqual(context["localConceptDraft"], target.modelInput)
        XCTAssertEqual(context["question"]?.string, target.prompt)
        XCTAssertEqual(context["source"], .null)
        XCTAssertEqual(context["selection"], .null)
        for key in ["revisionTarget", "localProfile", "localConversation", "companion", "localKnowledge", "localControl", "localReading"] {
            XCTAssertNil(context[key], key)
        }
        XCTAssertEqual(sent.input["memories"]?.array, [])
        let serialized = String(decoding: try JSONEncoder().encode(sent.input), as: UTF8.self)
        XCTAssertFalse(serialized.contains(Fixture.unrelatedText))
        XCTAssertFalse(serialized.contains("Unsent private question."))
        XCTAssertEqual(draft.anchors, anchors)
        XCTAssertEqual(receipt.requestID, draft.requestID)
        XCTAssertTrue(receipt.isKnowledgeAcquisition)
        XCTAssertEqual(receipt.state, .complete)
        XCTAssertEqual(receipt.readingDependencies, anchors.map(\.source))
        XCTAssertNil(receipt.knowledgeDependencies)
        XCTAssertEqual(receipt.localInvocations, [.reasoning])
        XCTAssertEqual(fixture.store.sharedText, Fixture.unrelatedText)
        XCTAssertEqual(fixture.store.sourceRevision, priorRevision)
        XCTAssertEqual(fixture.store.textSelection, priorSelection)
        XCTAssertEqual(fixture.store.prompt, "Unsent private question.")
        XCTAssertEqual(fixture.store.route, .codex)
        XCTAssertEqual(fixture.store.assistantProvider, .codex)
        XCTAssertEqual(fixture.store.connectionState, fixture.store.connection(for: .codex))
        XCTAssertEqual(fixture.external.calls, 0)
        XCTAssertEqual(fixture.external.connections, 0)
        XCTAssertTrue(fixture.store.readingSources.knowledgePages.isEmpty)
        XCTAssertNil(fixture.store.knowledgePageDraft)
        XCTAssertFalse(fixture.store.markReplyUsefulForEvolution(provider: .qwen, requestID: draft.requestID))
        fixture.store.beginLessonCorrection(for: .qwen)
        XCTAssertNil(fixture.store.lessonDraft)
        fixture.assertNoLearning()
        let task = try XCTUnwrap(fixture.store.tokenSteward.tasks.first)
        XCTAssertEqual(task.id, draft.requestID)
        XCTAssertEqual(task.lanes.map(\.provider), [AssistantProvider.qwen.name])
        XCTAssertEqual(task.lanes.first?.state, "complete")
        XCTAssertFalse(task.userUseful)
        XCTAssertNil(task.documentReading)

        fixture.store.editKnowledgeConceptDraft()
        let editor = try XCTUnwrap(fixture.store.knowledgePageDraft)
        XCTAssertNil(editor.prior)
        XCTAssertEqual(editor.proposal, draft)
        XCTAssertTrue(fixture.store.readingSources.knowledgePages.isEmpty)
        XCTAssertTrue(fixture.store.saveKnowledgePage(prior: nil, title: "My edited title",
            body: draft.body + "\nUser qualification.", kind: .concept, anchors: draft.anchors))
        let page = try XCTUnwrap(fixture.store.readingSources.latestKnowledgePages.first)
        XCTAssertEqual(page.title, "My edited title")
        XCTAssertEqual(page.state, .draft)
        XCTAssertNil(page.review)
        XCTAssertEqual(page.anchors, anchors)
        XCTAssertNil(fixture.store.knowledgePageDraft)
        XCTAssertNil(fixture.store.currentKnowledgeConceptDraft)
        fixture.assertNoLearning()
    }

    func testEnabledSessionContextAndPriorDialogueStayOutsideAcquisition() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        fixture.store.setLocalConversationEnabled(true)
        fixture.store.setSessionContextEnabled(true)
        fixture.store.prompt = "Remember this synthetic ordinary exchange."
        fixture.store.submit()
        try await fixture.wait { !fixture.store.isWorking }
        let records = fixture.assistant.snapshot.records
        let conversation = fixture.store.nextReplyConversation
        XCTAssertFalse(records.isEmpty)
        XCTAssertFalse(conversation.isEmpty)
        let selectorCalls = fixture.selector.requests.count
        let selectorConnections = fixture.selector.connections
        let reasonerCalls = fixture.reasoner.requests.count
        let anchors = try fixture.anchors()
        XCTAssertTrue(fixture.store.draftKnowledgeConcept(title: "Direct requests", anchors: anchors))
        try await fixture.wait { !fixture.store.isWorking }
        XCTAssertNotNil(fixture.store.currentKnowledgeConceptDraft)
        XCTAssertEqual(fixture.reasoner.requests.count, reasonerCalls + 1)
        XCTAssertEqual(fixture.selector.requests.count, selectorCalls)
        XCTAssertEqual(fixture.selector.connections, selectorConnections)
        XCTAssertEqual(fixture.assistant.snapshot.records, records)
        XCTAssertEqual(fixture.store.nextReplyConversation, conversation)
        XCTAssertEqual(fixture.assistant.snapshot.evidence?.contextEnabled, false)
        XCTAssertEqual(fixture.reasoner.requests.last?.input["memories"]?.array, [])
        XCTAssertNil(fixture.reasoner.requests.last?.input["context"]?["localConversation"])
        XCTAssertTrue(fixture.store.readingSources.knowledgePages.isEmpty)
        fixture.assertNoLearning()
    }

    func testChangedSourcesBlockAdmissionAndLaterEditingWithoutLosingCompletedInferenceCost() async throws {
        for replaceBeforeCompletion in [true, false] {
            let fixture = Fixture()
            defer { fixture.clean() }
            let anchors = try fixture.anchors()
            fixture.reasoner.pauseGeneration = replaceBeforeCompletion
            XCTAssertTrue(fixture.store.draftKnowledgeConcept(title: "Direct requests", anchors: anchors))
            if replaceBeforeCompletion {
                try await fixture.wait { fixture.reasoner.hasPendingGeneration }
            } else {
                try await fixture.wait { !fixture.store.isWorking }
                XCTAssertNotNil(fixture.store.currentKnowledgeConceptDraft)
            }
            let receipt = try XCTUnwrap(fixture.store.compareResults[.qwen]?.receipt)
            let other = ReadingSourceLibrary(url: fixture.readingURL)
            let source = try XCTUnwrap(other.sources.first)
            _ = try other.replace(id: source.id, title: source.title, text: "Replaced evidence.")
            if replaceBeforeCompletion {
                try fixture.reasoner.resolve()
                try await fixture.wait { fixture.reasoner.finishedGenerations == 1 && !fixture.store.isWorking }
                XCTAssertNotEqual(fixture.store.compareResults[.qwen]?.state, .complete)
                XCTAssertNil(fixture.store.knowledgeConceptDraft)
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
            XCTAssertFalse(fixture.store.isCurrentReplyContext(receipt))
            XCTAssertNil(fixture.store.currentKnowledgeConceptDraft)
            fixture.store.editKnowledgeConceptDraft()
            XCTAssertNil(fixture.store.knowledgePageDraft)
            XCTAssertFalse(fixture.store.draftKnowledgeConcept(title: "Retry", anchors: anchors))
            XCTAssertTrue(fixture.store.readingSources.knowledgePages.isEmpty)
            fixture.assertNoLearning()
            XCTAssertEqual(fixture.external.calls, 0)
        }
    }

    func testCancellationAndLocalFailureCannotAdmitLateResultsOrFallbackExternally() async throws {
        for cancel in [true, false] {
            let fixture = Fixture()
            defer { fixture.clean() }
            fixture.store.setAssistantRoute(.native)
            let anchors = try fixture.anchors()
            fixture.reasoner.pauseGeneration = true
            XCTAssertTrue(fixture.store.draftKnowledgeConcept(title: "Direct requests", anchors: anchors))
            try await fixture.wait { fixture.reasoner.hasPendingGeneration }
            if cancel {
                fixture.store.cancelWork()
                try fixture.reasoner.resolve()
            } else {
                fixture.reasoner.fail(QwenFailure.unavailable)
            }
            try await fixture.wait { fixture.reasoner.finishedGenerations == 1 && !fixture.store.isWorking }
            XCTAssertFalse(fixture.store.isDraftingKnowledgeConcept)
            XCTAssertNil(fixture.store.currentKnowledgeConceptDraft)
            XCTAssertNil(fixture.store.knowledgeConceptDraft)
            XCTAssertEqual(fixture.store.compareResults[.qwen]?.state, cancel ? .cancelled : .failed)
            XCTAssertNil(fixture.store.compareResults[.codex])
            XCTAssertEqual(fixture.reasoner.requests.count, 1)
            XCTAssertTrue(fixture.selector.requests.isEmpty)
            XCTAssertEqual(fixture.external.calls, 0)
            XCTAssertEqual(fixture.external.connections, 0)
            XCTAssertTrue(fixture.store.tokenSteward.tasks.allSatisfy {
                $0.lanes.allSatisfy { $0.provider == AssistantProvider.qwen.name }
            })
            XCTAssertTrue(fixture.store.readingSources.knowledgePages.isEmpty)
            fixture.assertNoLearning()
        }
    }

    @MainActor
    private final class Fixture {
        static let passage = "A direct polite request can preserve an action while removing introductory padding."
        static let unrelatedText = "Private invoice 742 and Friday deadline."
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-concept-draft-integration-\(UUID())")
        let reasoner = ConceptDraftRoleClient(name: "concept-reasoner-fixture")
        let selector = ConceptDraftRoleClient(name: "concept-selector-fixture")
        let external = ConceptDraftExternalClient()
        var preference: URL { directory.appendingPathComponent("preferences.json") }
        var readingURL: URL { preference.deletingPathExtension().appendingPathExtension("reading-sources.json") }
        lazy var assistant = HamptonReasonsAssistant(reasoner: reasoner, contextSelector: selector)
        lazy var store: CompanionStore = {
            let store = CompanionStore(preferenceURL: preference, assistant: assistant,
                assistantFactory: { [assistant, external] provider, _ in
                    if provider == .qwen { return assistant }
                    return external
                }, allowsPlay: false, tokenSteward: TokenStewardStore())
            store.setAssistantRoute(.automatic)
            store.setLocalWorkPreference(.reasoning)
            return store
        }()
        func anchors() throws -> [KnowledgeAnchor] {
            let source = try store.readingSources.keep(title: "Synthetic evidence", text: Self.passage)
            return [try store.readingSources.makeAnchor(sourceID: source.id,
                range: NSRange(location: 0, length: source.text.utf16.count))]
        }
        func assertNoLearning(file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertTrue(store.documentProcedures.latestProcedures.isEmpty, file: file, line: line)
            XCTAssertTrue(store.documentWork.records.isEmpty, file: file, line: line)
            XCTAssertTrue(store.evolution.usefulReceipts.isEmpty, file: file, line: line)
            XCTAssertTrue(store.keptLessons.isEmpty, file: file, line: line)
            XCTAssertTrue(store.tokenSteward.tasks.allSatisfy { $0.outcomes.isEmpty && !$0.userUseful }, file: file, line: line)
        }
        func wait(_ condition: @MainActor () -> Bool) async throws {
            for _ in 0..<400 {
                if condition() { return }
                try await Task.sleep(for: .milliseconds(5))
            }
            XCTFail("Timed out: \(store.status) | \(store.knowledgeConceptDraftMessage ?? "none")")
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
private final class ConceptDraftRoleClient: LocalRoleClient {
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
            let isConcept = request.input["context"]?["localConceptDraft"] != nil
            payload["schema"] = .string("archi-reason-proposal/v1")
            payload["kind"] = .string("ANSWER")
            payload["answer"] = .string(isConcept
                ? "Direct requests may remove introductory padding while preserving an action."
                : "Earlier synthetic reply.")
            payload["uncertainty"] = .string("")
            payload["sourceIDs"] = .array(ids("sources").filter { !isConcept || $0.hasPrefix("concept-passage-") }.map(JSONValue.string))
            payload["memoryIDs"] = .array(ids("memories").map(JSONValue.string))
        }
        return LocalRoleResult(requestID: request.id, role: request.role,
            text: String(decoding: try JSONEncoder().encode(JSONValue.object(payload)), as: UTF8.self),
            model: model, elapsedMilliseconds: 7,
            metrics: LocalInferenceMetrics(inputTokens: 321, outputTokens: 37))
    }
}

@MainActor
private final class ConceptDraftExternalClient: AssistantClient {
    private(set) var calls = 0
    private(set) var connections = 0
    func connect() async throws { connections += 1 }
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1
        throw AssistantFailure.unavailable
    }
}
