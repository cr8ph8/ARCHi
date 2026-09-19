import Foundation

struct QwenModelMetadata: Equatable, Sendable {
    let name: String
    let family: String
    let parameterSize: String
    let quantization: String
    let digest: String
}

enum QwenFailure: Error, LocalizedError, Equatable {
    case unavailable, unsupportedModel, modelUnavailable, nonLocalModel, modelChanged
    case invalidResponse, contextLimit, outputLimit, timedOut, stopped, generationFailed, busy

    var errorDescription: String? {
        switch self {
        case .unavailable: "Could not reach Ollama on this Mac at 127.0.0.1:11434. Start Ollama and connect again."
        case .unsupportedModel: "Choose a supported local Qwen model. No model was downloaded or contacted remotely."
        case .modelUnavailable: "The selected Qwen model is not installed in local Ollama. Choose an installed model."
        case .nonLocalModel: "This model could not be verified as a local Qwen completion model. Nothing was sent."
        case .modelChanged: "The installed Qwen model changed. Connect again before sending your question."
        case .invalidResponse: "Local Qwen returned an unexpected response. The reply was stopped."
        case .contextLimit: "The question, shared copy and local context exceed the Qwen request limit of 24 KB. Use a shorter question or document, or start a new conversation; nothing was sent."
        case .outputLimit: "Local Qwen reached the reply limit. Ask for a shorter answer."
        case .timedOut: "Local Qwen did not finish in time. Connect again to retry."
        case .stopped: "The local response was stopped."
        case .generationFailed: "Local Qwen could not complete this reply. Connect again to retry."
        case .busy: "Wait for the current local request to finish."
        }
    }
}

/// One explicit text request to local Ollama. No downloads, credentials, tool
/// executor, configurable remote endpoint, or cloud fallback are provided.
@MainActor
final class QwenAssistant: AssistantClient, LocalRoleClient {
    static let defaultModel = "qwen3.5:9b"
    static let supportedModels = [defaultModel, "qwen3:8b"]
    static let maximumInputBytes = 24_000
    private(set) var metadata: QwenModelMetadata?
    let model: String
    private let configuration: URLSessionConfiguration
    private let runtime: (any LocalQwenRuntimeManaging)?
    private var session: URLSession?
    private var generation: UInt64 = 0
    private var busy = false
    private let redirects = QwenRedirectPolicy()

    init(model: String = defaultModel, configuration: URLSessionConfiguration = .ephemeral,
         runtime: (any LocalQwenRuntimeManaging)? = nil) {
        self.model = model
        self.configuration = configuration.copy() as! URLSessionConfiguration
        self.runtime = runtime
    }

    func connect() async throws {
        disconnect()
        guard Self.supportedModels.contains(model) else { throw QwenFailure.unsupportedModel }
        let owner = generation
        let connection = beginSession()
        defer { finishSession(connection, owner: owner) }
        do {
            let verified = try await withTaskCancellationHandler {
                try await runtime?.ensureRunning()
                try requireOwner(owner)
                return try await verifyModel(using: connection, owner: owner)
            } onCancel: {
                Task { @MainActor [weak self] in self?.cancel(owner: owner) }
            }
            try requireOwner(owner)
            metadata = verified
        } catch {
            if owner == generation { disconnect() }
            throw Self.failure(error)
        }
    }

    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        guard request.hasValidSelection, request.hasValidRevisionTarget else { throw QwenFailure.invalidResponse }
        guard request.hasValidLocalLessons, request.hasValidLocalConversation, request.hasValidLocalProfile,
              request.hasValidLocalControl else { throw QwenFailure.invalidResponse }
        guard metadata != nil else { throw QwenFailure.unavailable }
        guard !busy else { throw QwenFailure.busy }
        let input = request.localInput
        let system = (request.revisionTarget == nil ? AssistantInstructions.groundedText : AssistantInstructions.passageRevisionText)
            + (request.localReading == nil ? "" : "\n" + AssistantInstructions.documentReadingText)
            + (request.localLessons.isEmpty ? "" : "\n" + LocalLessonGuidance.text)
            + (request.localConversation.isEmpty ? "" : "\n" + LocalConversationGuidance.text)
        guard !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              input.utf8.count + system.utf8.count <= Self.maximumInputBytes else {
            throw QwenFailure.contextLimit
        }
        if let target = request.revisionTarget {
            let memoryIDs = request.localLessons.map(\.modelID)
            let result = try await generateText(system: system, input: input,
                format: PassageRevisionValidator.schema(target: target, sourceIDs: request.localSourceIDs, memoryIDs: memoryIDs))
            try requireOwner(result.owner)
            let proposal: PassageRevisionProposal
            do { proposal = try PassageRevisionValidator.parse(result.text, target: target, sourceIDs: request.localSourceIDs, memoryIDs: memoryIDs) }
            catch { throw QwenFailure.invalidResponse }
            try requireOwner(result.owner)
            onEvent(.revision(proposal))
        } else {
            _ = try await generateText(system: system, input: input,
                                      format: nil, onText: { onEvent(.text($0)) })
        }
    }

    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
        guard UUID(uuidString: request.id) != nil,
              request.input["requestID"]?.string == request.id,
              request.outputSchema.object != nil else { throw QwenFailure.invalidResponse }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let input: String
        do {
            input = String(decoding: try encoder.encode(request.input), as: UTF8.self)
        } catch { throw QwenFailure.invalidResponse }
        let result = try await generateText(system: request.systemInstruction, input: input,
                                            format: request.outputSchema)
        try requireOwner(result.owner)
        // Transport completion does not validate the role's JSON or promote it
        // to memory/answer state. That remains the receiving role validator's job.
        return LocalRoleResult(requestID: request.id, role: request.role, text: result.text,
                               model: result.metadata, elapsedMilliseconds: result.elapsedMilliseconds,
                               metrics: result.metrics)
    }

    /// Both conversational and structured calls use the same verified, bounded
    /// local stream. A role caller supplies no text observer, keeping partial
    /// JSON private until the terminal event and request ownership are checked.
    private func generateText(system: String, input: String, format: JSONValue?,
                              onText: (@MainActor (String) -> Void)? = nil) async throws
        -> (text: String, metadata: QwenModelMetadata, elapsedMilliseconds: Int, owner: UInt64,
            metrics: LocalInferenceMetrics?) {
        guard let installed = metadata else { throw QwenFailure.unavailable }
        guard !busy else { throw QwenFailure.busy }
        var payload: [String: JSONValue] = [
            "model": .string(model), "stream": .bool(true), "think": .bool(false),
            "messages": .array([
                .object(["role": .string("system"), "content": .string(system)]),
                .object(["role": .string("user"), "content": .string(input)])
            ]),
            "options": .object(["num_ctx": .number(32_768), "num_predict": .number(4096)]),
            "keep_alive": .string("5m")
        ]
        if let format {
            payload["format"] = format
            payload["options"] = .object([
                "num_ctx": .number(Double(HamptonInvocationPolicy.contextTokens)),
                "num_predict": .number(Double(HamptonInvocationPolicy.outputTokens)),
                "temperature": .number(HamptonInvocationPolicy.temperature)
            ])
        }
        let httpRequest: URLRequest
        do { httpRequest = try makeRequest(path: "api/chat", body: payload) }
        catch { throw Self.failure(error) }
        // The wire budget includes schemas, lessons, and JSON-in-message
        // escaping for both conversational and structured local requests.
        guard let body = httpRequest.httpBody, body.count <= Self.maximumInputBytes else {
            throw QwenFailure.contextLimit
        }
        let started = ContinuousClock.now
        generation &+= 1
        let owner = generation
        let connection = beginSession()
        defer { finishSession(connection, owner: owner) }
        do {
            return try await withTaskCancellationHandler {
                // Recheck before sending text in case a model alias was replaced.
                let current = try await verifyModel(using: connection, owner: owner)
                guard current == installed else { throw QwenFailure.modelChanged }
                try requireOwner(owner)
                let (bytes, response) = try await connection.bytes(for: httpRequest, delegate: redirects)
                try requireOwner(owner)
                try Self.validate(response, for: httpRequest)
                var stream = QwenReplyStream(model: model)
                var line = Data()
                var total = 0
                for try await byte in bytes {
                    try requireOwner(owner)
                    total += 1
                    guard total <= 1_048_576 else { throw QwenFailure.outputLimit }
                    if byte == 10 {
                        if !line.isEmpty, let text = try stream.consume(line) { onText?(text) }
                        line.removeAll(keepingCapacity: true)
                    } else {
                        line.append(byte)
                        guard line.count <= 131_072 else { throw QwenFailure.outputLimit }
                    }
                }
                if !line.isEmpty, let text = try stream.consume(line) {
                    try requireOwner(owner)
                    onText?(text)
                }
                try requireOwner(owner)
                try stream.finish()
                let duration = started.duration(to: .now).components
                let milliseconds = max(0, duration.seconds * 1_000 + duration.attoseconds / 1_000_000_000_000_000)
                return (stream.text, current, Int(milliseconds), owner, stream.metrics)
            } onCancel: {
                Task { @MainActor [weak self] in self?.cancel(owner: owner) }
            }
        } catch {
            if owner == generation { disconnect() }
            throw Self.failure(error)
        }
    }

    func disconnect() {
        generation &+= 1
        session?.invalidateAndCancel()
        session = nil
        metadata = nil
        busy = false
    }

    func shutdown() async { disconnect() }

    private func beginSession() -> URLSession {
        let config = configuration.copy() as! URLSessionConfiguration
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = [:]
        config.connectionProxyDictionary = ["HTTPEnable": 0, "HTTPSEnable": 0, "SOCKSEnable": 0]
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 180
        config.httpMaximumConnectionsPerHost = 1
        let connection = URLSession(configuration: config)
        session = connection
        busy = true
        return connection
    }

    private func finishSession(_ connection: URLSession, owner: UInt64) {
        connection.finishTasksAndInvalidate()
        guard owner == generation else { return }
        session = nil
        busy = false
    }

    private func cancel(owner: UInt64) {
        guard owner == generation else { return }
        disconnect()
    }

    private func requireOwner(_ owner: UInt64) throws {
        guard owner == generation, !Task.isCancelled else { throw QwenFailure.stopped }
    }

    private func verifyModel(using connection: URLSession, owner: UInt64) async throws -> QwenModelMetadata {
        let tags = try await json(path: "api/tags", using: connection, owner: owner)
        guard let models = tags["models"]?.array, models.count <= 512 else { throw QwenFailure.invalidResponse }
        let matches = models.filter { $0["name"]?.string == model && $0["model"]?.string == model }
        guard matches.count == 1, let tag = matches.first else { throw QwenFailure.modelUnavailable }
        let expectedFamily = model == Self.defaultModel ? "qwen35" : "qwen3"
        guard Self.isLocal(tag), tag["details"]?["format"]?.string == "gguf",
              tag["details"]?["family"]?.string == expectedFamily,
              let digest = tag["digest"]?.string,
              digest.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil else { throw QwenFailure.nonLocalModel }
        let info = try await json(path: "api/show", body: ["model": .string(model), "verbose": .bool(false)],
                                  using: connection, owner: owner)
        guard Self.isLocal(info), info["details"]?["format"]?.string == "gguf",
              info["details"]?["family"]?.string == expectedFamily,
              info["model_info"]?["general.architecture"]?.string == expectedFamily,
              info["capabilities"]?.array?.contains(.string("completion")) == true,
              info["messages"] == nil || info["messages"]?.array?.isEmpty == true,
              let size = info["details"]?["parameter_size"]?.string, size.utf8.count <= 80,
              let quantization = info["details"]?["quantization_level"]?.string, quantization.utf8.count <= 80 else {
            throw QwenFailure.nonLocalModel
        }
        return QwenModelMetadata(name: model, family: expectedFamily, parameterSize: size,
                                 quantization: quantization, digest: digest)
    }

    private func json(path: String, body: [String: JSONValue]? = nil,
                      using connection: URLSession, owner: UInt64) async throws -> JSONValue {
        let request = try makeRequest(path: path, body: body)
        let (bytes, response) = try await connection.bytes(for: request, delegate: redirects)
        try requireOwner(owner)
        try Self.validate(response, for: request)
        var data = Data()
        for try await byte in bytes {
            try requireOwner(owner)
            data.append(byte)
            guard data.count <= 1_048_576 else { throw QwenFailure.invalidResponse }
        }
        try requireOwner(owner)
        do { return try JSONDecoder().decode(JSONValue.self, from: data) }
        catch { throw QwenFailure.invalidResponse }
    }

    private func makeRequest(path: String, body: [String: JSONValue]?) throws -> URLRequest {
        let url = URL(string: "http://127.0.0.1:11434/\(path)")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, application/x-ndjson", forHTTPHeaderField: "Accept")
        if let body { request.httpBody = try JSONEncoder().encode(JSONValue.object(body)) }
        return request
    }

    private static func validate(_ response: URLResponse, for request: URLRequest) throws {
        guard let http = response as? HTTPURLResponse, http.url == request.url else { throw QwenFailure.invalidResponse }
        guard http.statusCode == 200 else {
            if (300..<400).contains(http.statusCode) { throw QwenFailure.nonLocalModel }
            throw QwenFailure.generationFailed
        }
    }

    private static func isLocal(_ value: JSONValue) -> Bool {
        ["remote_host", "remote_model"].allSatisfy { value[$0] == nil || value[$0]?.string == "" }
    }

    private static func failure(_ error: Error) -> Error {
        if let failure = error as? QwenFailure { return failure }
        if error is LocalQwenRuntimeFailure { return error }
        if error is CancellationError { return QwenFailure.stopped }
        if let url = error as? URLError {
            if url.code == .cancelled { return QwenFailure.stopped }
            if url.code == .timedOut { return QwenFailure.timedOut }
            return QwenFailure.unavailable
        }
        return QwenFailure.invalidResponse
    }
}

/// Deny every redirect before URLSession can contact its destination.
final class QwenRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct QwenReplyStream {
    let model: String
    private(set) var text = ""
    private(set) var done = false
    private(set) var metrics: LocalInferenceMetrics?
    private var events = 0

    init(model: String) { self.model = model }

    mutating func consume(_ data: Data) throws -> String? {
        guard data.count <= 131_072 else { throw QwenFailure.outputLimit }
        if data.allSatisfy({ $0 == 13 || $0 == 32 || $0 == 9 }) { return nil }
        guard !done, events < 4096 else { throw QwenFailure.invalidResponse }
        events += 1
        let event: QwenChatStreamEvent
        do { event = try QwenChatStreamEvent(data: data) }
        catch { throw QwenFailure.invalidResponse }
        let value = event.value
        guard value["error"] == nil, value["model"]?.string == model,
              ["remote_host", "remote_model"].allSatisfy({ value[$0] == nil || value[$0]?.string == "" }),
              let finished = value["done"]?.bool,
              let message = value["message"], message["role"]?.string == "assistant",
              let content = message["content"]?.string,
              message["thinking"] == nil || message["thinking"]?.string == "",
              message["tool_calls"] == nil || message["tool_calls"]?.array?.isEmpty == true,
              message["images"] == nil || message["images"]?.array?.isEmpty == true else { throw QwenFailure.invalidResponse }
        guard text.utf8.count + content.utf8.count <= 100_000 else { throw QwenFailure.outputLimit }
        if finished {
            guard value["done_reason"]?.string == "stop" else { throw QwenFailure.outputLimit }
            done = true
            metrics = event.metrics
        }
        text += content
        return content.isEmpty ? nil : text
    }

    func finish() throws {
        guard done, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw QwenFailure.invalidResponse }
    }
}
