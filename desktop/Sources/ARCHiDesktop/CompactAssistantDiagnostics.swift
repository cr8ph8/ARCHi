import Foundation

/// Explicit one-request local installation check. No profile, source document,
/// saved memory, cloud client, model pull or application window is opened.
@MainActor
enum CompactAssistantDiagnostics {
    static func run() async -> Bool {
        let model = "qwen3:1.7b"
        let client = HamptonReasonsAssistant(contextModel: model,
            reasoner: MetadataOnlyReasoner(), contextSelector: QwenAssistant(model: model), contextEnabled: false)
        client.workPreference = .automatic
        var answer = ""
        var failure: String?
        do {
            try await client.connect()
            let request = AssistantRequest(prompt: "Hello!", sourceName: nil, sourceText: "",
                sourceRevision: 0, placementRevision: 0, tone: "Warm", replyLength: 0.2)
            try await client.reply(to: request) { if case .text(let value) = $0 { answer = value } }
        } catch { failure = String(describing: error) }
        let snapshot = client.snapshot
        let passed = failure == nil && !answer.isEmpty && snapshot.expertDecision?.target == .compact
            && snapshot.invocations.count == 1 && snapshot.invocations.first?.model?.name == model
            && snapshot.admissionOutcome?.status == .accepted
        let result: JSONValue = .object([
            "result": .string(passed ? "PASS" : "FAIL"),
            "scope": .string("One synthetic greeting through the native Hampton coordinator; not model-quality qualification."),
            "answer": .string(answer), "failure": failure.map(JSONValue.string) ?? .null,
            "selectedRole": .string(snapshot.expertDecision?.target == .compact ? "compact" : "reasoning"),
            "reason": .string(snapshot.expertDecision?.reason ?? "No decision"),
            "externalCalls": .number(0), "profileRead": .bool(false),
            "attempts": .array(snapshot.invocations.map { invocation in .object([
                "role": .string(invocation.role.rawValue), "outcome": .string(invocation.outcome.rawValue),
                "model": invocation.model.map { .string($0.name) } ?? .null,
                "modelDigest": invocation.model.map { .string($0.digest) } ?? .null,
                "inputTokens": invocation.metrics?.inputTokens.map { .number(Double($0)) } ?? .null,
                "outputTokens": invocation.metrics?.outputTokens.map { .number(Double($0)) } ?? .null,
                "elapsedMilliseconds": invocation.elapsedMilliseconds.map { .number(Double($0)) } ?? .null
            ]) })
        ])
        await client.shutdown()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(result) { print(String(decoding: data, as: UTF8.self)) }
        return passed
    }
}

/// Readiness may inspect the configured larger model. Recovery cannot generate
/// with it during this one-small-model diagnostic.
@MainActor
private final class MetadataOnlyReasoner: LocalRoleClient {
    private let client = QwenAssistant()
    func connect() async throws { try await client.connect() }
    func disconnect() { client.disconnect() }
    func shutdown() async { await client.shutdown() }
    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult { throw QwenFailure.unsupportedModel }
}
