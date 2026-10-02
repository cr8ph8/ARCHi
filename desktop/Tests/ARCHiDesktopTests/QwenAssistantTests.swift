import Foundation
import Testing
@testable import ARCHiDesktop

@Suite(.serialized)
@MainActor
struct QwenAssistantTests {
    @Test func directQwenIncludesExactLocalConversationWithOneGenerationAndExplicitPrecedence() async throws {
        let client = makeClient()
        defer { client.disconnect() }
        let history = [AssistantConversationExchange(question: "  Earlier \"quoted\" request.\n", answer: "Generated e\u{301} and 🙂.")]
        let request = sourceRequest().replacingLocalConversation(history)
        try await client.connect()
        try await client.reply(to: request, onEvent: { _ in })
        let chats = QwenFixtureProtocol.state.requests.filter { $0.url?.path == "/api/chat" }
        #expect(chats.count == 1)
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(chats.first?.httpBody))
        let system = try #require(body["messages"]?.array?.first?["content"]?.string)
        #expect(system.contains(LocalConversationGuidance.text))
        let content = try #require(body["messages"]?.array?.last?["content"]?.string)
        let input = try JSONDecoder().decode(JSONValue.self, from: Data(content.utf8))
        #expect(input["question"]?.string == request.prompt)
        #expect(input["localConversation"] == AssistantConversation.modelInput(for: history))
        #expect(input["localConversation"]?["exchanges"]?.array?.first?["question"]?.string?.utf8.elementsEqual(history[0].question.utf8) == true)
        #expect(input["localConversation"]?["exchanges"]?.array?.first?["answer"]?.string?.utf8.elementsEqual(history[0].answer.utf8) == true)
        #expect(input["memories"] == nil)
        #expect(body["tools"] == nil)
    }

    @Test func directQwenRejectsOversizedHistoryAndCountsValidHistoryInWireBudget() async throws {
        let client = makeClient()
        defer { client.disconnect() }
        try await client.connect()
        let malformed = sourceRequest().replacingLocalConversation(Array(repeating: .init(question: "q", answer: "a"), count: 4))
        await #expect(throws: QwenFailure.invalidResponse) { try await client.reply(to: malformed, onEvent: { _ in }) }
        let large = AssistantRequest(prompt: "Use this source.", sourceName: "fixture.txt",
            sourceText: String(repeating: "x", count: 17_000), sourceRevision: 4, placementRevision: 7,
            tone: "Warm", replyLength: 0.25,
            localConversation: [.init(question: "earlier", answer: String(repeating: "z", count: 7_000))])
        #expect(large.hasValidLocalConversation)
        await #expect(throws: QwenFailure.contextLimit) { try await client.reply(to: large, onEvent: { _ in }) }
        #expect(!QwenFixtureProtocol.state.requests.contains { $0.url?.path == "/api/chat" })
        #expect(QwenFixtureProtocol.state.requests.count == 2, "Both failures precede transport re-verification/generation")
    }

    private func revisionRequest() throws -> AssistantRequest {
        let source = sourceRequest(), selection = try #require(source.selection)
        return AssistantRequest(prompt: "Make this option more concise.", sourceName: source.sourceName,
            sourceText: source.sourceText, sourceRevision: source.sourceRevision, placementRevision: source.placementRevision,
            settings: source.settings, selection: selection,
            localLessons: [LessonSnapshot(id: UUID().uuidString, revision: 1, topic: "option", text: "Keep the moon symbol.")],
            revisionTarget: try #require(RevisionTarget(text: source.sourceText, sourceRevision: source.sourceRevision, selection: selection)))
    }

    @Test func directRevisionUsesClosedSchemaAndPublishesOnlyValidatedTerminalProposal() async throws {
        let client = makeClient(), request = try revisionRequest()
        defer { client.disconnect() }
        try await client.connect()
        var proposals: [PassageRevisionProposal] = [], texts: [String] = []
        try await client.reply(to: request) { event in
            switch event { case .text(let text): texts.append(text); case .revision(let proposal): proposals.append(proposal) }
        }
        #expect(texts.isEmpty)
        #expect(proposals.count == 1)
        #expect(proposals.first?.target == request.revisionTarget)
        #expect(proposals.first?.replacement == "B 🌙.")
        #expect(proposals.first?.memoryIDs == request.localLessons.map(\.modelID))
        let chats = QwenFixtureProtocol.state.requests.filter { $0.url?.path == "/api/chat" }
        #expect(chats.count == 1)
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(chats.first?.httpBody))
        #expect(body["format"] == PassageRevisionValidator.schema(target: try #require(request.revisionTarget),
            sourceIDs: request.sourceIDs, memoryIDs: request.localLessons.map(\.modelID)))
        #expect(body["messages"]?.array?.first?["content"]?.string?.contains(AssistantInstructions.passageRevisionText) == true)
    }

    @Test func malformedAndCancelledDirectRevisionsPublishNothing() async throws {
        let request = try revisionRequest()
        let invalid = makeClient(.revisionMalformed)
        defer { invalid.disconnect() }
        try await invalid.connect()
        await #expect(throws: QwenFailure.invalidResponse) {
            try await invalid.reply(to: request) { _ in Issue.record("Malformed revision published") }
        }
        let held = makeClient(.revisionHold)
        defer { held.disconnect() }
        try await held.connect()
        let task = Task { try await held.reply(to: request) { _ in Issue.record("Held revision published") } }
        try await waitUntil { QwenFixtureProtocol.state.requests.contains { $0.url?.path == "/api/chat" } }
        task.cancel()
        await #expect(throws: QwenFailure.stopped) { try await task.value }
    }

    @Test func connectOnlyInspectsLocalModelAndReplySendsExactGroundedText() async throws {
        let client = makeClient()
        defer { client.disconnect() }
        try await client.connect()
        #expect(client.metadata?.name == "qwen3.5:9b")
        #expect(client.metadata?.family == "qwen35")
        #expect(QwenFixtureProtocol.state.requests.map(\.url!.path) == ["/api/tags", "/api/show"])
        let request = sourceRequest()
        var outputs: [String] = []
        try await client.reply(to: request) { if case .text(let text) = $0 { outputs.append(text) } }
        #expect(outputs == ["Option ", "Option B 🌙."])
        let requests = QwenFixtureProtocol.state.requests
        #expect(requests.allSatisfy { $0.url?.host == "127.0.0.1" && $0.url?.port == 11434 })
        #expect(requests.map(\.url!.path) == ["/api/tags", "/api/show", "/api/tags", "/api/show", "/api/chat"])
        let posted = try JSONDecoder().decode(JSONValue.self, from: #require(requests.last?.httpBody))
        #expect(posted["model"] == .string(QwenAssistant.defaultModel))
        #expect(posted["stream"] == .bool(true))
        #expect(posted["think"] == .bool(false))
        #expect(posted["tools"] == nil)
        #expect(posted["options"]?["num_ctx"] == .number(32_768))
        #expect(posted["options"]?["num_predict"] == .number(4096))
        #expect(posted["messages"]?.array?.count == 2)
        #expect(posted["messages"]?.array?[0]["content"]?.string == AssistantInstructions.groundedText)
        let input = try JSONDecoder().decode(JSONValue.self, from: Data(request.input.utf8))
        let postedContent = try #require(posted["messages"]?.array?[1]["content"]?.string)
        let postedInput = try JSONDecoder().decode(JSONValue.self, from: Data(postedContent.utf8))
        #expect(postedInput == input) // JSON member order is intentionally immaterial.
        #expect(postedInput["selection"] == request.selection?.input)
        #expect(postedInput["source"]?["text"]?.string?.utf8.elementsEqual(request.sourceText.utf8) == true)
    }

    @Test func oversizedOrStaleSourceIsRejectedBeforeAnyGenerationRequest() async throws {
        let client = makeClient()
        defer { client.disconnect() }
        try await client.connect()
        var request = sourceRequest(text: String(repeating: "é", count: 20_000))
        await #expect(throws: QwenFailure.contextLimit) { try await client.reply(to: request) { _ in } }
        request = sourceRequest()
        request.selection = DocumentSelection(range: NSRange(location: 0, length: 3), text: "Old", sourceRevision: 9)
        await #expect(throws: QwenFailure.invalidResponse) { try await client.reply(to: request) { _ in } }
        #expect(QwenFixtureProtocol.state.requests.count == 2)
        #expect(client.metadata != nil)
    }

    @Test func unsupportedCloudMissingAndNonQwenModelsNeverReceiveAQuestion() async {
        for mode in [QwenFixtureMode.remoteTag, .remoteShow, .wrongFamily, .missing, .noCompletion] {
            let client = makeClient(mode)
            await #expect(throws: QwenFailure.self) { try await client.connect() }
            #expect(client.metadata == nil)
            #expect(!QwenFixtureProtocol.state.requests.contains { $0.url?.path == "/api/chat" })
            client.disconnect()
        }
        let client = makeClient(model: "qwen3-coder:480b-cloud")
        await #expect(throws: QwenFailure.unsupportedModel) { try await client.connect() }
        #expect(QwenFixtureProtocol.state.requests.isEmpty)
    }

    @Test func duplicateLocalityMetadataIsRejectedBeforeConnectionAndGeneration() async throws {
        for mode in [QwenFixtureMode.duplicateTag, .duplicateShow] {
            let client = makeClient(mode)
            defer { client.disconnect() }
            await #expect(throws: QwenFailure.invalidResponse) { try await client.connect() }
            #expect(client.metadata == nil)
            #expect(!QwenFixtureProtocol.state.requests.contains { $0.url?.path == "/api/chat" })
        }
        for mode in [QwenFixtureMode.duplicateReverifiedTag, .duplicateReverifiedShow] {
            let client = makeClient(mode)
            defer { client.disconnect() }
            try await client.connect()
            await #expect(throws: QwenFailure.invalidResponse) {
                try await client.reply(to: sourceRequest()) { _ in Issue.record("Ambiguous model received a question") }
            }
            #expect(client.metadata == nil)
            #expect(!QwenFixtureProtocol.state.requests.contains { $0.url?.path == "/api/chat" })
        }
    }

    @Test func modelDiscoveryRejectsDuplicateLocalityMetadata() async {
        QwenFixtureProtocol.state.reset(mode: .duplicateTag)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QwenFixtureProtocol.self]
        await #expect(throws: QwenFailure.invalidResponse) {
            _ = try await QwenAssistant.discoverInstalledModels(configuration: configuration)
        }
        #expect(QwenFixtureProtocol.state.requests.map(\.url!.path) == ["/api/tags"])
    }

    @Test func replacingInstalledAliasFailsReverificationBeforeSendingSource() async throws {
        let client = makeClient(.changedDigest)
        defer { client.disconnect() }
        try await client.connect()
        await #expect(throws: QwenFailure.modelChanged) { try await client.reply(to: sourceRequest()) { _ in } }
        let generationRequests = QwenFixtureProtocol.state.requests.filter { $0.url?.path == "/api/chat" }
        #expect(generationRequests.isEmpty)
    }

    @Test func disconnectFromFirstTextRejectsAlreadyBufferedLateContent() async throws {
        let client = makeClient()
        defer { client.disconnect() }
        try await client.connect()
        var outputs: [String] = []
        await #expect(throws: QwenFailure.stopped) {
            try await client.reply(to: sourceRequest()) {
                if case .text(let text) = $0 { outputs.append(text); client.disconnect() }
            }
        }
        #expect(outputs == ["Option "])
        #expect(client.metadata == nil)
        try await client.connect()
        #expect(client.metadata != nil)
    }

    @Test func taskCancellationStopsHeldResponseAndCanReconnect() async throws {
        let client = makeClient(.holdChat)
        defer { client.disconnect() }
        try await client.connect()
        var outputs: [String] = []
        let task = Task { try await client.reply(to: sourceRequest()) {
            if case .text(let text) = $0 { outputs.append(text) }
        } }
        try await waitUntil { outputs.count == 1 }
        task.cancel()
        await #expect(throws: QwenFailure.stopped) { try await task.value }
        #expect(outputs == ["Option "])
        #expect(client.metadata == nil)
        try await client.connect()
        #expect(client.metadata != nil)
    }

    @Test func canceledOldConnectionCannotClearItsReplacement() async throws {
        let client = makeClient(.holdFirstTags)
        defer { client.disconnect() }
        let old = Task { try await client.connect() }
        try await waitUntil { QwenFixtureProtocol.state.requests.count == 1 }
        client.disconnect()
        try await client.connect()
        await #expect(throws: QwenFailure.stopped) { try await old.value }
        #expect(client.metadata?.name == QwenAssistant.defaultModel)
        var text = ""
        try await client.reply(to: sourceRequest()) { if case .text(let value) = $0 { text = value } }
        #expect(text == "Option B 🌙.")
    }

    @Test func incompleteStreamsAndTimeoutsNeverFinishSuccessfully() async throws {
        for (mode, failure) in [(QwenFixtureMode.noDone, QwenFailure.invalidResponse),
                                (.truncatedAnswer, .outputLimit), (.timedOut, .timedOut),
                                (.redirectResponse, .nonLocalModel)] {
            let client = makeClient(mode)
            defer { client.disconnect() }
            if mode == .redirectResponse {
                await #expect(throws: failure) { try await client.connect() }
                #expect(QwenFixtureProtocol.state.requests.count == 1)
            } else {
                try await client.connect()
                await #expect(throws: failure) { try await client.reply(to: sourceRequest()) { _ in } }
            }
        }
    }

    @Test func redirectDelegateRefusesExternalAndLoopbackDestinations() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let origin = URL(string: "http://127.0.0.1:11434/api/chat")!
        let task = session.dataTask(with: origin) // Never resumed.
        let response = HTTPURLResponse(url: origin, statusCode: 307, httpVersion: nil, headerFields: nil)!
        let policy = HTTPNoRedirectPolicy()
        for destination in ["https://example.invalid/collect", "http://127.0.0.1:11434/another"] {
            var called = false
            policy.urlSession(session, task: task, willPerformHTTPRedirection: response,
                newRequest: URLRequest(url: URL(string: destination)!)) { request in
                    called = true
                    #expect(request == nil)
                }
            #expect(called)
        }
    }

    private func makeClient(_ mode: QwenFixtureMode = .normal, model: String = QwenAssistant.defaultModel) -> QwenAssistant {
        QwenFixtureProtocol.state.reset(mode: mode)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QwenFixtureProtocol.self]
        return QwenAssistant(model: model, configuration: configuration)
    }

    private func sourceRequest(text: String = "Option A\nOption B 🌙.") -> AssistantRequest {
        let range = (text as NSString).range(of: "Option B 🌙.")
        return AssistantRequest(prompt: "Which option is selected?", sourceName: "synthetic.txt",
            sourceText: text, sourceRevision: 1, placementRevision: 2, tone: "Calm", replyLength: 0.4,
            selection: DocumentSelection(range: range, text: text, sourceRevision: 1))
    }

    private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Fixture request did not reach its expected state")
        throw QwenFailure.timedOut
    }
}

struct QwenReplyStreamTests {
    @Test func ambiguousSecurityFieldsCannotPublishTextOrFinish() {
        let wires = [
            #"{"model":"qwen3.5:9b","mo\u0064el":"other-model","message":{"role":"assistant","content":"Answer"},"done":true,"done_reason":"stop"}"#,
            #"{"model":"qwen3.5:9b","message":{"role":"assistant","content":"Answer"},"mess\u0061ge":{"role":"tool","content":"Tool text"},"done":true,"done_reason":"stop"}"#,
            #"{"model":"qwen3.5:9b","message":{"role":"assistant","content":"Answer","thinking":"","think\u0069ng":"Private reasoning"},"done":true,"done_reason":"stop"}"#,
            #"{"model":"qwen3.5:9b","message":{"role":"assistant","content":"Answer","tool_calls":[],"tool_\u0063alls":[{}]},"done":true,"done_reason":"stop"}"#,
            #"{"model":"qwen3.5:9b","message":{"role":"assistant","content":"Answer"},"done":true,"do\u006ee":false,"done_reason":"stop"}"#,
            #"{"model":"qwen3.5:9b","remote_host":"","remote_\u0068ost":"https://ollama.com","message":{"role":"assistant","content":"Answer"},"done":true,"done_reason":"stop"}"#
        ]
        for wire in wires {
            var stream = QwenReplyStream(model: "qwen3.5:9b")
            #expect(throws: QwenFailure.invalidResponse) { try stream.consume(Data(wire.utf8)) }
            #expect(stream.text.isEmpty)
            #expect(!stream.done)
            #expect(stream.metrics == nil)
        }
    }

    @Test func duplicateMetricExceptionAppliesOnlyToTopLevelAccounting() throws {
        let valid = #"{"model":"qwen3.5:9b","message":{"role":"assistant","content":"Answer"},"done":true,"done_reason":"stop","eval_count":2,"eval_\u0063ount":3}"#
        var stream = QwenReplyStream(model: "qwen3.5:9b")
        _ = try stream.consume(Data(valid.utf8))
        try stream.finish()
        #expect(stream.text == "Answer")
        #expect(stream.metrics == LocalInferenceMetrics(malformedFields: ["eval_count"]))

        let nested = #"{"model":"qwen3.5:9b","message":{"role":"assistant","content":"Answer","eval_count":2,"eval_\u0063ount":3},"done":true,"done_reason":"stop"}"#
        var rejected = QwenReplyStream(model: "qwen3.5:9b")
        #expect(throws: QwenFailure.invalidResponse) { try rejected.consume(Data(nested.utf8)) }
        #expect(rejected.text.isEmpty)
        #expect(!rejected.done)
        #expect(rejected.metrics == nil)
    }

    @Test func metricsComeOnlyFromTheAcceptedTerminalEvent() throws {
        var stream = QwenReplyStream(model: "qwen3.5:9b")
        var early = QwenFixtureProtocol.chunk("Answer", done: false).object!
        early["prompt_eval_count"] = .number(999)
        early["eval_count"] = .number(-1)
        _ = try stream.consume(JSONEncoder().encode(JSONValue.object(early)))
        #expect(stream.metrics == nil)
        #expect(throws: QwenFailure.invalidResponse) { try stream.finish() }
        #expect(stream.metrics == nil)

        var terminal = QwenFixtureProtocol.chunk("", done: true).object!
        terminal["prompt_eval_count"] = .number(123)
        terminal["eval_count"] = .number(17)
        terminal["total_duration"] = .number(10_000_000)
        terminal["load_duration"] = .number(0)
        terminal["prompt_eval_duration"] = .number(2_000_000)
        terminal["eval_duration"] = .number(8_000_000)
        _ = try stream.consume(JSONEncoder().encode(JSONValue.object(terminal)))
        try stream.finish()
        #expect(stream.text == "Answer")
        #expect(stream.metrics == LocalInferenceMetrics(inputTokens: 123, outputTokens: 17,
            totalNanoseconds: 10_000_000, loadNanoseconds: 0,
            promptEvaluationNanoseconds: 2_000_000, evaluationNanoseconds: 8_000_000))
    }

    @Test func missingAndNullMetricsStayUnknownWhileZeroIsKnown() throws {
        var missing = QwenReplyStream(model: "qwen3.5:9b")
        _ = try missing.consume(JSONEncoder().encode(QwenFixtureProtocol.chunk("Answer", done: true)))
        try missing.finish()
        #expect(missing.metrics == nil)

        var terminal = QwenFixtureProtocol.chunk("Answer", done: true).object!
        terminal["prompt_eval_count"] = .null
        terminal["eval_count"] = .null
        var nulls = QwenReplyStream(model: "qwen3.5:9b")
        _ = try nulls.consume(JSONEncoder().encode(JSONValue.object(terminal)))
        try nulls.finish()
        #expect(nulls.metrics == nil)

        terminal["eval_count"] = .number(0)
        var zero = QwenReplyStream(model: "qwen3.5:9b")
        _ = try zero.consume(JSONEncoder().encode(JSONValue.object(terminal)))
        try zero.finish()
        #expect(zero.metrics == LocalInferenceMetrics(outputTokens: 0))
    }

    @Test func malformedOptionalMetricsNeverRejectAnOtherwiseValidAnswer() throws {
        // Raw literals include an overflowing JSON number, which cannot first be
        // represented as JSONValue.number without losing the malformed input.
        for literal in ["-1", "1.5", "\"12\"", "true", "[]", "{}",
                        "9007199254740992", "9223372036854775808", "1e309"] {
            let wire = """
            {"model":"qwen3.5:9b","message":{"role":"assistant","content":"Answer"},"done":true,"done_reason":"stop","prompt_eval_count":12,"eval_count":\(literal)}
            """
            var stream = QwenReplyStream(model: "qwen3.5:9b")
            _ = try stream.consume(Data(wire.utf8))
            try stream.finish()
            #expect(stream.text == "Answer")
            #expect(stream.metrics == LocalInferenceMetrics(inputTokens: 12, malformedFields: ["eval_count"]))
        }
    }

    @Test func metricIntegerBoundaryDoesNotRoundThroughDouble() throws {
        for literal in ["9007199254740991", "9007199254740991.5", "9007199254740990.5",
                        "0.00000000000000000000000000000000000000000000001", "12.0", "12e0"] {
            let wire = """
            {"model":"qwen3.5:9b","message":{"role":"assistant","content":"Answer"},"done":true,"done_reason":"stop","total_duration":\(literal)}
            """
            var stream = QwenReplyStream(model: "qwen3.5:9b")
            _ = try stream.consume(Data(wire.utf8))
            try stream.finish()
            if literal == "9007199254740991" {
                #expect(stream.metrics?.totalNanoseconds == 9_007_199_254_740_991)
                #expect(stream.metrics?.malformedFields.isEmpty == true)
            } else {
                #expect(stream.metrics?.totalNanoseconds == nil)
                #expect(stream.metrics?.malformedFields == ["total_duration"])
            }
        }
    }

    @Test func metricLiteralsUseTopLevelDecodedKeysAndRejectDuplicateAccounting() throws {
        let wire = #"{"model":"qwen3.5:9b","message":{"role":"assistant","content":"Quoted \"eval_count\":999 and } remain text","eval_count":999},"done":true,"done_reason":"stop","ignored":{"eval_count":888},"eval_\u0063ount":7,"prompt_eval_count":4,"prompt_eval_count":5}"#
        var stream = QwenReplyStream(model: "qwen3.5:9b")
        _ = try stream.consume(Data(wire.utf8))
        try stream.finish()
        #expect(stream.metrics == LocalInferenceMetrics(outputTokens: 7, malformedFields: ["prompt_eval_count"]))
        #expect(stream.text == "Quoted \"eval_count\":999 and } remain text")
    }

    @Test func rejectedTerminalCannotPublishMetrics() throws {
        for reason in ["length", "unknown"] {
            var terminal = QwenFixtureProtocol.chunk("Answer", done: true).object!
            terminal["done_reason"] = .string(reason)
            terminal["eval_count"] = .number(8)
            var stream = QwenReplyStream(model: "qwen3.5:9b")
            #expect(throws: QwenFailure.outputLimit) {
                try stream.consume(JSONEncoder().encode(JSONValue.object(terminal)))
            }
            #expect(stream.metrics == nil)
            #expect(!stream.done)
        }
    }

    @Test func rejectsToolsThinkingRemoteRoutingWrongModelAndPostTerminalEvents() throws {
        for mutation in ["tool_calls", "thinking", "remote_host", "model", "role"] {
            var value = QwenFixtureProtocol.chunk("Visible", done: false)
            var object = value.object!
            var message = object["message"]!.object!
            switch mutation {
            case "tool_calls": message["tool_calls"] = .array([.object(["function": .object([:])])])
            case "thinking": message["thinking"] = .string("Hidden reasoning")
            case "remote_host": object["remote_host"] = .string("https://ollama.com")
            case "model": object["model"] = .string("other-model")
            default: message["role"] = .string("tool")
            }
            object["message"] = .object(message)
            value = .object(object)
            var stream = QwenReplyStream(model: "qwen3.5:9b")
            #expect(throws: QwenFailure.invalidResponse) { try stream.consume(JSONEncoder().encode(value)) }
            #expect(stream.text.isEmpty)
        }
        var stream = QwenReplyStream(model: "qwen3.5:9b")
        _ = try stream.consume(JSONEncoder().encode(QwenFixtureProtocol.chunk("Answer", done: true)))
        try stream.finish()
        #expect(throws: QwenFailure.invalidResponse) {
            try stream.consume(JSONEncoder().encode(QwenFixtureProtocol.chunk("Late", done: false)))
        }
    }

    @Test func boundsContentAndRequiresExplicitNonemptyTerminalResult() throws {
        var stream = QwenReplyStream(model: "qwen3.5:9b")
        #expect(throws: QwenFailure.invalidResponse) { try stream.finish() }
        #expect(throws: QwenFailure.outputLimit) {
            try stream.consume(JSONEncoder().encode(QwenFixtureProtocol.chunk(String(repeating: "x", count: 100_001), done: true)))
        }
        #expect(throws: QwenFailure.invalidResponse) { try stream.consume(Data("not JSON".utf8)) }
        var empty = QwenReplyStream(model: "qwen3.5:9b")
        _ = try empty.consume(JSONEncoder().encode(QwenFixtureProtocol.chunk("", done: true)))
        #expect(throws: QwenFailure.invalidResponse) { try empty.finish() }
    }
}

private enum QwenFixtureMode: Sendable {
    case normal, remoteTag, remoteShow, wrongFamily, missing, noCompletion, changedDigest
    case duplicateTag, duplicateShow, duplicateReverifiedTag, duplicateReverifiedShow
    case holdChat, holdFirstTags, noDone, truncatedAnswer, timedOut, redirectResponse, revisionMalformed, revisionHold
}

private final class QwenFixtureState: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URLRequest] = []
    private var mode: QwenFixtureMode = .normal
    var requests: [URLRequest] { lock.withLock { stored } }
    func reset(mode: QwenFixtureMode) { lock.withLock { stored = []; self.mode = mode } }
    func record(_ request: URLRequest) -> (QwenFixtureMode, Int) {
        lock.withLock {
            stored.append(request)
            return (mode, stored.filter { $0.url?.path == "/api/tags" }.count)
        }
    }
}

private final class QwenFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let state = QwenFixtureState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            captured.httpBody = data
        }
        let (mode, tagsCount) = Self.state.record(captured)
        let path = request.url!.path
        if mode == .holdFirstTags && tagsCount == 1 && path == "/api/tags" { return }
        if mode == .timedOut && path == "/api/chat" {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return
        }
        let status = mode == .redirectResponse ? 307 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/x-ndjson", "Location": "https://example.invalid/collect"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let details: JSONValue = .object(["format": .string("gguf"), "family": .string("qwen35"),
            "parameter_size": .string("9.7B"), "quantization_level": .string("Q4_K_M")])
        if path == "/api/tags" {
            var tag: [String: JSONValue] = ["name": .string("qwen3.5:9b"), "model": .string("qwen3.5:9b"),
                "details": details, "digest": .string(String(repeating: mode == .changedDigest && tagsCount > 1 ? "b" : "a", count: 64))]
            if mode == .remoteTag { tag["remote_host"] = .string("https://ollama.com") }
            if mode == .duplicateTag || (mode == .duplicateReverifiedTag && tagsCount > 1) {
                tag["remote_host"] = .string("")
                let encoded = String(decoding: try! JSONEncoder().encode(JSONValue.object(tag)), as: UTF8.self)
                let ambiguous = String(encoded.dropLast()) + #", "remote_\u0068ost":"https://ollama.com"}"#
                send(data: Data((#"{"models":["# + ambiguous + "]}").utf8))
            } else {
                send(.object(["models": .array(mode == .missing ? [] : [.object(tag)])]))
            }
        } else if path == "/api/show" {
            var info: [String: JSONValue] = ["details": details,
                "model_info": .object(["general.architecture": .string(mode == .wrongFamily ? "llama" : "qwen35")]),
                "capabilities": .array(mode == .noCompletion ? [] : [.string("completion"), .string("thinking")])]
            if mode == .remoteShow { info["remote_model"] = .string("cloud") }
            if mode == .duplicateShow || (mode == .duplicateReverifiedShow && tagsCount > 1) {
                info["remote_model"] = .string("")
                let encoded = String(decoding: try! JSONEncoder().encode(JSONValue.object(info)), as: UTF8.self)
                let ambiguous = String(encoded.dropLast()) + #", "remote_\u006dodel":"cloud"}"#
                send(data: Data(ambiguous.utf8))
            } else {
                send(.object(info))
            }
        } else {
            if let body = captured.httpBody,
               let envelope = try? JSONDecoder().decode(JSONValue.self, from: body),
               let inputText = envelope["messages"]?.array?.last?["content"]?.string,
               let input = try? JSONDecoder().decode(JSONValue.self, from: Data(inputText.utf8)),
               let target = input["revisionTarget"]?["id"]?.string {
                let payload: JSONValue = .object(["schema": .string("native-passage-revision/v1"),
                    "targetID": .string(target), "decision": .string("PROPOSE"), "replacement": .string("B 🌙."),
                    "explanation": .string("Shortened the label."), "sourceIDs": .array([.string("selected-passage")]),
                    "memoryIDs": .array((input["memories"]?.array ?? []).compactMap { $0["id"] })])
                let raw = mode == .revisionMalformed ? "malformed JSON" : String(decoding: try! JSONEncoder().encode(payload), as: UTF8.self)
                send(Self.chunk(raw, done: false), newline: true)
                if mode == .revisionHold { return }
                send(Self.chunk("", done: true), newline: true)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            send(Self.chunk("Option ", done: false), newline: true)
            if mode == .holdChat { return }
            send(Self.chunk("B 🌙.", done: false), newline: true)
            if mode != .noDone {
                send(Self.chunk("", done: true, reason: mode == .truncatedAnswer ? "length" : "stop"), newline: true)
            }
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    private func send(_ value: JSONValue, newline: Bool = false) {
        send(data: try! JSONEncoder().encode(value), newline: newline)
    }

    private func send(data value: Data, newline: Bool = false) {
        var data = value
        if newline { data.append(10) }
        // Split inside UTF-8 as well as JSON boundaries to exercise byte framing.
        let split = data.count / 2
        client?.urlProtocol(self, didLoad: data.prefix(split))
        client?.urlProtocol(self, didLoad: data.suffix(data.count - split))
    }

    static func chunk(_ content: String, done: Bool, reason: String = "stop") -> JSONValue {
        .object(["model": .string("qwen3.5:9b"), "message": .object(["role": .string("assistant"),
            "content": .string(content)]), "done": .bool(done), "done_reason": .string(reason)])
    }
}
