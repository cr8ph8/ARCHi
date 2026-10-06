import Foundation
import CryptoKit
import Testing
@testable import ARCHiDesktop

@MainActor
struct KeptLessonRequestTests {
    @Test func bothRequestInitializersKeepLessonsOutOfThePublicCodexContract() throws {
        let lesson = lessonFixture()
        let settings = AssistantSettingsSnapshot(tone: "Warm", replyLength: 0.5, role: .muse, helpStyle: .concise)
        let baseline = AssistantRequest(prompt: "Explain the release notes.", sourceName: nil, sourceText: "",
            sourceRevision: 0, placementRevision: 1, settings: settings)
        let captured = AssistantRequest(prompt: baseline.prompt, sourceName: nil, sourceText: "",
            sourceRevision: 0, placementRevision: 1, settings: settings, localLessons: [lesson])
        let legacy = AssistantRequest(prompt: baseline.prompt, sourceName: nil, sourceText: "",
            sourceRevision: 0, placementRevision: 1, tone: "Warm", replyLength: 0.5,
            role: .muse, helpStyle: .concise, localLessons: [lesson])
        for request in [captured, legacy] {
            #expect(try decoded(request.input) == decoded(baseline.input))
            #expect(request.localLessons == [lesson])
            #expect(request.hasValidLocalLessons)
            #expect(!request.input.contains(lesson.text))
            #expect(!request.input.contains(lesson.modelID))
            #expect(!request.input.contains("memories"))
            #expect(try decoded(request.localInput)["memories"] == .array([lesson.modelInput]))
        }
        #expect(AssistantRequest.inputContract == "native-assistant-input/v4")
        #expect(baseline.localLessons.isEmpty)
        #expect(baseline.localLessonDigest == nil)
    }

    @Test func lessonDigestBindsExactRevisionsTextOrderAndPrivateSource() throws {
        let source = LessonSource(name: "private-notes.txt", digest: String(repeating: "b", count: 64))
        let first = lessonFixture(source: source)
        let second = lessonFixture(id: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB", text: "Start with the consequence.")
        let request = lessonRequest([first, second])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode([first, second])
        let expected = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        #expect(request.localLessonDigest == expected)
        #expect(lessonRequest([first, second]).localLessonDigest == expected)
        #expect(lessonRequest([second, first]).localLessonDigest != expected)
        #expect(lessonRequest([lessonFixture(revision: 2, source: source), second]).localLessonDigest != expected)
        #expect(lessonRequest([lessonFixture(text: "Changed guidance.", source: source), second]).localLessonDigest != expected)
        #expect(lessonRequest([lessonFixture(), second]).localLessonDigest != expected)
        #expect(!request.localInput.contains(source.name), "Source provenance stays in the receipt snapshot, outside model context.")
        #expect(first.modelID == "kept-AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA-r1")
    }

    @Test func keptLessonsUseOneReasoningCallWithTemporaryContextOff() async throws {
        let rig = LessonRoleRig(contextEnabled: false)
        defer { rig.assistant.disconnect() }
        try await rig.assistant.connect()
        let lesson = lessonFixture()
        let request = lessonRequest([lesson])
        var outputs: [String] = []
        try await rig.assistant.reply(to: request) { if case .text(let value) = $0 { outputs.append(value) } }
        let reason = try #require(rig.reasoner.requests.first)
        #expect(reason.input["context"] == (try decoded(request.input)))
        #expect(reason.input["memories"] == .array([lesson.modelInput]))
        #expect(reason.outputSchema["properties"]?["memoryIDs"]?["items"]?["enum"] == .array([.string(lesson.modelID)]))
        #expect(rig.selector.connectCount == 0)
        #expect(rig.selector.requests.isEmpty)
        #expect(rig.assistant.snapshot.attemptedInvocations == [.reasoning])
        #expect(rig.assistant.snapshot.receipts.map(\.role) == [.reasoning])
        #expect(rig.assistant.snapshot.proposal?.memoryIDs == [lesson.modelID])
        #expect(rig.assistant.snapshot.records.isEmpty)
        #expect(rig.assistant.snapshot.turn == 0)
        #expect(outputs == ["A checked local answer."])
    }

    @Test func keptLessonsAndTransientReferencesShareCitationsButNotRetention() async throws {
        let rig = LessonRoleRig(contextEnabled: true)
        defer { rig.assistant.disconnect() }
        try await rig.assistant.connect()
        try await rig.assistant.reply(to: lessonRequest([], prompt: "Earlier exact user constraint.")) { _ in }
        let earlier = try #require(rig.assistant.snapshot.records.first)
        let lesson = lessonFixture()
        try await rig.assistant.reply(to: lessonRequest([lesson])) { _ in }
        let reason = try #require(rig.reasoner.requests.last)
        #expect(reason.input["memories"]?.array?.count == 2)
        #expect(rig.assistant.snapshot.proposal?.memoryIDs == [lesson.modelID, earlier.id])
        #expect(rig.assistant.snapshot.attemptedInvocations == [.memorySelection, .memoryReminder, .reasoning])
        #expect(!rig.assistant.snapshot.records.contains { $0.text == lesson.text || $0.id == lesson.modelID })
        for request in rig.selector.requests {
            let encoded = String(decoding: try JSONEncoder().encode(request.input), as: UTF8.self)
            #expect(!encoded.contains(lesson.text))
            #expect(!encoded.contains(lesson.modelID))
        }
    }

    @Test func malformedDuplicateOrOversizedLessonSnapshotsNeverInvokeModels() async throws {
        let first = lessonFixture()
        let cases: [[LessonSnapshot]] = [
            [first, first],
            [first, lessonFixture(revision: 2)],
            [first, lessonFixture(id: first.id.lowercased())],
            (0...NativePreferenceDocument.maximumLessons).map { _ in lessonFixture(id: UUID().uuidString) },
            [lessonFixture(id: "not-a-uuid")], [lessonFixture(revision: 0)],
            [lessonFixture(topic: "x")], [lessonFixture(text: " ")],
            [lessonFixture(text: String(repeating: "x", count: 601))],
            [lessonFixture(text: "e" + String(repeating: "\u{301}", count: 1_201))]
        ]
        let rig = LessonRoleRig(contextEnabled: true)
        defer { rig.assistant.disconnect() }
        try await rig.assistant.connect()
        for lessons in cases {
            let request = lessonRequest(lessons)
            #expect(!request.hasValidLocalLessons)
            await #expect(throws: QwenFailure.invalidResponse) {
                try await rig.assistant.reply(to: request) { _ in }
            }
        }
        #expect(rig.reasoner.requests.isEmpty)
        #expect(rig.selector.requests.isEmpty)
        #expect(rig.selector.connectCount == 0)
        #expect(rig.assistant.snapshot.attemptedInvocations.isEmpty)
    }

    @Test func lessonEnvelopeBudgetFailsBeforeOptionalInference() async throws {
        let rig = LessonRoleRig(contextEnabled: true)
        defer { rig.assistant.disconnect() }
        try await rig.assistant.connect()
        let lessons = (0..<NativePreferenceDocument.maximumLessons).map { _ in
            lessonFixture(id: UUID().uuidString, text: String(repeating: "\"", count: 600))
        }
        let request = lessonRequest(lessons)
        #expect(request.hasValidLocalLessons)
        #expect(request.input.utf8.count < 1_000)
        do {
            try await rig.assistant.reply(to: request) { _ in }
            Issue.record("Oversized combined lesson context must fail preflight.")
        } catch { #expect(error as? HamptonAssistantFailure == .contextLimit) }
        #expect(rig.reasoner.requests.isEmpty)
        #expect(rig.selector.requests.isEmpty)
        #expect(rig.assistant.snapshot.attemptedInvocations.isEmpty)
        #expect(rig.assistant.snapshot.records.isEmpty)
    }

    @Test func onlyActuallyCitedCurrentLessonRevisionsAreAdmitted() async throws {
        let rig = LessonRoleRig(contextEnabled: false)
        defer { rig.assistant.disconnect() }
        try await rig.assistant.connect()
        let current = lessonFixture(revision: 2)
        rig.reasoner.citations = []
        try await rig.assistant.reply(to: lessonRequest([current])) { _ in }
        #expect(rig.assistant.snapshot.proposal?.memoryIDs.isEmpty == true)
        for invalidIDs in [[lessonFixture().modelID], [current.modelID, current.modelID], ["invented-memory"]] {
            rig.reasoner.citations = invalidIDs
            do {
                try await rig.assistant.reply(to: lessonRequest([current])) { _ in }
                Issue.record("Unknown, old, or repeated lesson citations must be rejected.")
            } catch { #expect(error as? HamptonAssistantFailure == .invalidProposal) }
            #expect(rig.assistant.snapshot.proposal == nil)
            #expect(rig.assistant.snapshot.receipts.isEmpty)
            #expect(rig.assistant.snapshot.attemptedInvocations == [.reasoning])
        }
        #expect(rig.assistant.snapshot.records.isEmpty)
    }

    @Test func clearingTemporaryContextDoesNotEraseTheNextExplicitLessonSnapshot() async throws {
        let rig = LessonRoleRig(contextEnabled: true)
        defer { rig.assistant.disconnect() }
        try await rig.assistant.connect()
        try await rig.assistant.reply(to: lessonRequest([])) { _ in }
        #expect(!rig.assistant.snapshot.records.isEmpty)
        rig.assistant.setContextEnabled(false)
        let lesson = lessonFixture()
        try await rig.assistant.reply(to: lessonRequest([lesson])) { _ in }
        #expect(rig.assistant.snapshot.records.isEmpty)
        #expect(rig.assistant.snapshot.proposal?.memoryIDs == [lesson.modelID])
        #expect(rig.assistant.snapshot.attemptedInvocations == [.reasoning])
    }
}

@Suite(.serialized)
@MainActor
struct KeptLessonQwenTransportTests {
    @Test func directLocalReplyTransportsLessonsWithLocalGuidanceOnly() async throws {
        LessonWireProtocol.state.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LessonWireProtocol.self]
        let client = QwenAssistant(configuration: configuration)
        defer { client.disconnect() }
        try await client.connect()
        let lesson = lessonFixture()
        let request = lessonRequest([lesson])
        try await client.reply(to: request) { _ in }
        let chat = try #require(LessonWireProtocol.state.requests.last)
        #expect(chat.url?.path == "/api/chat")
        let payload = try JSONDecoder().decode(JSONValue.self, from: #require(chat.httpBody))
        let system = try #require(payload["messages"]?.array?[0]["content"]?.string)
        let input = try #require(payload["messages"]?.array?[1]["content"]?.string)
        #expect(system == AssistantInstructions.groundedText + "\n" + LocalLessonGuidance.text)
        #expect(try decoded(input) == decoded(request.localInput))
        #expect(try decoded(input)["memories"] == .array([lesson.modelInput]))
        #expect(!request.input.contains(lesson.text))
        #expect(LessonWireProtocol.state.requests.allSatisfy { $0.url?.host == "127.0.0.1" })
        #expect(payload["tools"] == nil)
    }

    @Test func directLocalReplyRejectsInvalidLessonsAndEscapedWireOverflowBeforeSending() async throws {
        LessonWireProtocol.state.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LessonWireProtocol.self]
        let client = QwenAssistant(configuration: configuration)
        defer { client.disconnect() }
        try await client.connect()
        let first = lessonFixture()
        await #expect(throws: QwenFailure.invalidResponse) {
            try await client.reply(to: lessonRequest([first, first])) { _ in }
        }
        let lessons = (0..<NativePreferenceDocument.maximumLessons).map { _ in
            lessonFixture(id: UUID().uuidString, text: String(repeating: "\"", count: 500))
        }
        let request = lessonRequest(lessons)
        #expect(request.hasValidLocalLessons)
        #expect(request.localInput.utf8.count + AssistantInstructions.groundedText.utf8.count
            + LocalLessonGuidance.text.utf8.count < QwenAssistant.maximumInputBytes,
            "The transport must also count the outer JSON message escaping.")
        await #expect(throws: QwenFailure.contextLimit) { try await client.reply(to: request) { _ in } }
        #expect(LessonWireProtocol.state.requests.map(\.url!.path) == ["/api/tags", "/api/show"])
    }
}

private func lessonFixture(id: String = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA", revision: UInt64 = 1,
                           topic: String = "release notes", text: String = "Describe user-facing changes before implementation details.",
                           source: LessonSource? = nil) -> LessonSnapshot {
    LessonSnapshot(id: id, revision: revision, topic: topic, text: text, source: source)
}

private func lessonRequest(_ lessons: [LessonSnapshot], prompt: String = "Explain the release notes.") -> AssistantRequest {
    AssistantRequest(prompt: prompt, sourceName: nil, sourceText: "", sourceRevision: 0, placementRevision: 1,
        tone: "Warm", replyLength: 0.5, localLessons: lessons)
}

private func decoded(_ input: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(input.utf8))
}

@MainActor
private struct LessonRoleRig {
    let reasoner: LessonRoleClient
    let selector: LessonRoleClient
    let assistant: HamptonReasonsAssistant
    init(contextEnabled: Bool) {
        reasoner = LessonRoleClient()
        selector = LessonRoleClient()
        assistant = HamptonReasonsAssistant(reasoner: reasoner, contextSelector: selector, contextEnabled: contextEnabled)
    }
}

@MainActor
private final class LessonRoleClient: LocalRoleClient {
    var requests: [LocalRoleRequest] = []
    var connectCount = 0
    var citations: [String]?
    func connect() async throws { connectCount += 1 }
    func disconnect() {}
    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
        requests.append(request)
        func ids(_ field: String) -> [String] { request.input[field]?.array?.compactMap { $0["id"]?.string } ?? [] }
        var output: [String: JSONValue] = ["requestID": .string(request.id)]
        switch request.role {
        case .memorySelection:
            output["schema"] = .string("archi-session-selection/v1")
            output["candidateIDs"] = .array(ids("candidates").prefix(1).map(JSONValue.string))
        case .memoryReminder:
            let selected = Array(ids("memories").prefix(3))
            output["schema"] = .string("archi-session-reminder/v1")
            output["decision"] = .string(selected.isEmpty ? "NONE" : "SELECT")
            output["memoryIDs"] = .array(selected.map(JSONValue.string))
        case .reasoning:
            output["schema"] = .string("archi-reason-proposal/v1")
            output["kind"] = .string("ANSWER")
            output["answer"] = .string("A checked local answer.")
            output["uncertainty"] = .string("")
            output["sourceIDs"] = .array([])
            output["memoryIDs"] = .array((citations ?? Array(ids("memories").prefix(3))).map(JSONValue.string))
        }
        return LocalRoleResult(requestID: request.id, role: request.role,
            text: String(decoding: try JSONEncoder().encode(JSONValue.object(output)), as: UTF8.self),
            model: QwenModelMetadata(name: "lesson-fixture", family: "fixture", parameterSize: "fixture",
                quantization: "fixture", digest: String(repeating: "a", count: 64)), elapsedMilliseconds: 1)
    }
}

private final class LessonWireState: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URLRequest] = []
    var requests: [URLRequest] { lock.withLock { stored } }
    func reset() { lock.withLock { stored = [] } }
    func record(_ request: URLRequest) { lock.withLock { stored.append(request) } }
}

private final class LessonWireProtocol: URLProtocol, @unchecked Sendable {
    static let state = LessonWireState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            captured.httpBody = data
        }
        Self.state.record(captured)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let details: JSONValue = .object(["format": .string("gguf"), "family": .string("qwen35"),
            "parameter_size": .string("9.7B"), "quantization_level": .string("Q4_K_M")])
        let payload: JSONValue
        switch request.url!.path {
        case "/api/tags":
            payload = .object(["models": .array([.object(["name": .string("qwen3.5:9b"), "model": .string("qwen3.5:9b"),
                "details": details, "digest": .string(String(repeating: "a", count: 64))])])])
        case "/api/show":
            payload = .object(["details": details, "model_info": .object(["general.architecture": .string("qwen35")]),
                "capabilities": .array([.string("completion")])])
        default:
            payload = .object(["model": .string("qwen3.5:9b"), "message": .object(["role": .string("assistant"),
                "content": .string("A local answer.")]), "done": .bool(true), "done_reason": .string("stop")])
        }
        var data = try! JSONEncoder().encode(payload); data.append(10)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}


@MainActor
struct PersonalContextReasoningTests {
    @Test func structuredReasonerReceivesBoundedProfileWithNoSelectorCalls() async throws {
        let rig = LessonRoleRig(contextEnabled: false)
        defer { rig.assistant.disconnect() }
        try await rig.assistant.connect()
        let snapshot = PersonalContextSnapshot(revision: 1, preferredName: "Tester",
            facts: [.init(title: "Style", text: "Start with a concrete next step.")])
        let request = AssistantRequest(prompt: "Help with this task.", sourceName: nil, sourceText: "",
            sourceRevision: 0, placementRevision: 0, tone: "Warm", replyLength: 0.45, localProfile: snapshot)
        try await rig.assistant.reply(to: request) { _ in }
        let reason = try #require(rig.reasoner.requests.first)
        #expect(reason.input["context"]?["localProfile"] == snapshot.modelInput)
        #expect(rig.reasoner.requests.count == 1)
        #expect(rig.selector.requests.isEmpty)
        #expect(!request.codexInput.contains("Start with a concrete"))
    }

    @Test func invalidProfileNeverInvokesReasoner() async throws {
        let rig = LessonRoleRig(contextEnabled: false)
        defer { rig.assistant.disconnect() }
        try await rig.assistant.connect()
        let request = AssistantRequest(prompt: "Test", sourceName: nil, sourceText: "",
            sourceRevision: 0, placementRevision: 0, tone: "Warm", replyLength: 0.45,
            localProfile: PersonalContextSnapshot(revision: 0, preferredName: "Tester", facts: []))
        await #expect(throws: QwenFailure.invalidResponse) { try await rig.assistant.reply(to: request) { _ in } }
        #expect(rig.reasoner.requests.isEmpty)
        #expect(rig.selector.requests.isEmpty)
    }
}
