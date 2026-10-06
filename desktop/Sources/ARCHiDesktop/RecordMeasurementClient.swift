import Foundation

/// A scalar from the frozen synthetic record task. Transfer to kept records is
/// unqualified; this is neither answer verification nor a permission signal.
struct RecordMeasurement: Equatable, Sendable {
    let rawScore: Double
    let standardizedScore: Double
    let inputTokens: Int
    let outputTokens: Int
    let readerDigest: String
    let requestID: String
}

enum RecordMeasurementError: LocalizedError, Equatable {
    case unavailable, invalidReader, invalidInput, invalidResponse, busy

    var errorDescription: String? {
        switch self {
        case .unavailable: "The bundled record reader or its exact local Qwen model is unavailable."
        case .invalidReader: "The bundled record reader does not match its frozen identity."
        case .invalidInput: "Use the bounded two-record lookup table for this measurement."
        case .invalidResponse: "The local worker did not return a matching zero-generation measurement."
        case .busy: "A record measurement is already running."
        }
    }
}

/// A separate pinned artifact, deliberately not an ordinary-reply reader import.
/// The exact byte digest is the qualification boundary; the parser additionally
/// checks the numerical and execution identities used by the worker.
struct RecordMeasurementReader: Sendable {
    static let artifactDigest = "b699deda8bc7bdd99b5e362c88d16accdd66c163222e89647086b44a680a7ac0"
    static let numericDigest = "3cd3b593f393d252eef9d63f8090a685a52e0ce3c37f94f778ad0ccea0515bef"
    static let candidateDigest = "e2e2beed1097fe8d8655242ffe51c26469e4ed77349ba77c04f14b166a0b6bd3"
    static let qualificationDigest = "f382bbae7192a14aa5b32c42e6630667c8e7b547c50092b2ef2efa162c908838"
    static let planDigest = "8db6b8144b00b856e3084335393394484c790124c5bb731f91de84e7a75de3bc"
    static let modelName = "qwen3.5:9b"
    static let modelDigest = "6488c96fa5faab64bb65cbd30d4289e20e6130ef535a93ef9a49f42eda893ea7"
    static let modelBlobDigest = "dec52a44569a2a25341c4e4d3fee25846eed4f6f0b936278e3a3c900bb99d37c"
    static let backendRevision = "llama.cpp:161755f29+archi-qwen35-text-v1"
    static let layer = "l_out-31"
    static let tokenRule = "prompt-last"
    static let measurementScope = "synthetic-record-field-support/prompt-final/ridge-v1"
    static let maximumBytes = 256 * 1024

    let directions: [[Double]]
    let center: [Double]
    let scoreOffset: [Double]
    let scoreScale: [Double]

    static var bundledURL: URL? {
        // Installed resources are copied directly. Avoid Bundle.module's trap
        // when its development resource bundle is absent in a packaged app.
        Bundle.main.resourceURL?.appendingPathComponent("RecordReader/reader.qualified.json")
    }

    static func loadBundled() throws -> Self {
        guard let url = bundledURL else { throw RecordMeasurementError.unavailable }
        return try decode(smallFile(url, maximum: maximumBytes))
    }

    static func decode(_ bytes: Data) throws -> Self {
        guard !bytes.isEmpty, bytes.count <= maximumBytes,
              GGUFReaderArtifact.digest(bytes) == artifactDigest,
              GGUFReaderArtifact.hasUniqueKeys(bytes, maximumDepth: 12) else {
            throw RecordMeasurementError.invalidReader
        }
        let value = try JSONDecoder().decode(Payload.self, from: bytes)
        let candidate = value.candidate, plan = value.plan, review = value.review
        guard value.schema == "archi-task-reader-bundle/v1", value.status == "limited-synthetic-pass",
              value.modelName == modelName, value.measurementScope == measurementScope, !value.nativeImportable,
              candidate.schema == "archi-task-reader-candidate/v1", candidate.status == "unqualified-candidate",
              candidate.numericDigest == numericDigest, candidate.planDigest == planDigest,
              candidate.modelDigest == modelDigest, candidate.modelBlobDigest == modelBlobDigest,
              candidate.backendRevision == backendRevision, candidate.layer == layer,
              candidate.tokenRule == tokenRule, candidate.measurementScope == measurementScope,
              plan.schema == "archi-task-reader-plan/v1", plan.algorithm == "grouped-ridge-reader/v1",
              plan.modelName == modelName, plan.modelDigest == modelDigest, plan.modelBlobDigest == modelBlobDigest,
              plan.backendRevision == backendRevision, plan.templateDigest == GGUFReaderArtifact.templateDigest,
              plan.precision == "Q4_K_M", plan.hiddenWidth == 4096, plan.layer == layer,
              plan.tokenRule == tokenRule, plan.measurementScope == measurementScope,
              plan.generatedTokenBudget == 0, !plan.layerSearch, !plan.heldoutRetries,
              review.schema == "archi-task-reader-review/v1", review.status == "limited-synthetic-pass",
              review.candidateDigest == candidateDigest, review.qualificationDigest == qualificationDigest,
              review.planDigest == planDigest, review.modelName == modelName,
              review.measurementScope == measurementScope else { throw RecordMeasurementError.invalidReader }
        let numeric = candidate.numeric
        guard numeric.directions.count == 1, numeric.directions[0].count == 4096,
              numeric.center.count == 4096, numeric.scoreOffset.count == 1, numeric.scoreScale.count == 1,
              (numeric.directions[0] + numeric.center + numeric.scoreOffset + numeric.scoreScale)
                .allSatisfy({ $0.isFinite && abs($0) <= 1.0e6 }),
              numeric.scoreScale[0] >= 1.0e-12,
              abs(numeric.directions[0].reduce(0) { $0 + $1 * $1 } - 1) <= 1.0e-5,
              GGUFReaderQualification.numericDigest(directions: numeric.directions, center: numeric.center,
                offsets: numeric.scoreOffset, scales: numeric.scoreScale) == numericDigest else {
            throw RecordMeasurementError.invalidReader
        }
        return Self(directions: numeric.directions, center: numeric.center,
                    scoreOffset: numeric.scoreOffset, scoreScale: numeric.scoreScale)
    }

    var wireBasis: JSONValue {
        .object(["directions": .array(directions.map { .array($0.map(JSONValue.number)) }),
                 "center": .array(center.map(JSONValue.number)),
                 "score_offset": .array(scoreOffset.map(JSONValue.number)),
                 "score_scale": .array(scoreScale.map(JSONValue.number))])
    }

    /// Only the named Ollama manifest and referenced config are read. The worker
    /// independently hashes the actual GGUF bytes before model execution.
    static func resolveModel() throws -> URL {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ollama/models")
        let manifestData = try smallFile(root.appendingPathComponent("manifests/registry.ollama.ai/library/qwen3.5/9b"),
                                         maximum: 256 * 1024)
        guard GGUFReaderArtifact.digest(manifestData) == modelDigest,
              GGUFReaderArtifact.hasUniqueKeys(manifestData, maximumDepth: 6) else { throw RecordMeasurementError.unavailable }
        let manifest = try JSONDecoder().decode(JSONValue.self, from: manifestData)
        guard let layers = manifest["layers"]?.array, layers.count <= 32,
              let configDigest = manifest["config"]?["digest"]?.string,
              configDigest.hasPrefix("sha256:"), LocalRepresentationBasis.digest(String(configDigest.dropFirst(7))) else {
            throw RecordMeasurementError.unavailable
        }
        let models = layers.filter { $0["mediaType"]?.string == "application/vnd.ollama.image.model" }
        guard models.count == 1, models[0]["digest"]?.string == "sha256:" + modelBlobDigest,
              let size = recordInteger(models[0]["size"], maximum: 32 * 1024 * 1024 * 1024), size > 0 else {
            throw RecordMeasurementError.unavailable
        }
        let modelURL = root.appendingPathComponent("blobs/sha256-" + modelBlobDigest)
        let metadata = try modelURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard metadata.isRegularFile == true, metadata.isSymbolicLink != true, metadata.fileSize == size else {
            throw RecordMeasurementError.unavailable
        }
        let config = try smallFile(root.appendingPathComponent("blobs/sha256-" + configDigest.dropFirst(7)), maximum: 32 * 1024)
        guard GGUFReaderArtifact.digest(config) == String(configDigest.dropFirst(7)),
              GGUFReaderArtifact.hasUniqueKeys(config, maximumDepth: 4) else { throw RecordMeasurementError.unavailable }
        let info = try JSONDecoder().decode(JSONValue.self, from: config)
        guard info["model_format"]?.string == "gguf", info["file_type"]?.string == "Q4_K_M",
              info["model_family"]?.string == "qwen35" else { throw RecordMeasurementError.unavailable }
        return modelURL
    }

    private static func smallFile(_ url: URL, maximum: Int) throws -> Data {
        guard url.isFileURL else { throw RecordMeasurementError.unavailable }
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true,
              let count = info.fileSize, count > 0, count <= maximum else { throw RecordMeasurementError.unavailable }
        let bytes = try Data(contentsOf: url)
        guard !bytes.isEmpty, bytes.count <= maximum else { throw RecordMeasurementError.unavailable }
        return bytes
    }

    private struct Numeric: Decodable {
        let directions: [[Double]], center: [Double], scoreOffset: [Double], scoreScale: [Double]
    }
    private struct Candidate: Decodable {
        let schema: String, status: String, numericDigest: String, planDigest: String
        let modelDigest: String, modelBlobDigest: String, backendRevision: String
        let layer: String, tokenRule: String, measurementScope: String
        let numeric: Numeric
    }
    private struct Plan: Decodable {
        let schema: String, algorithm: String, modelName: String, modelDigest: String, modelBlobDigest: String
        let backendRevision: String, templateDigest: String, precision: String, layer: String
        let tokenRule: String, measurementScope: String
        let hiddenWidth: Int, generatedTokenBudget: Int
        let layerSearch: Bool, heldoutRetries: Bool
    }
    private struct Review: Decodable {
        let schema: String, status: String, candidateDigest: String, qualificationDigest: String, planDigest: String
        let modelName: String, measurementScope: String
    }
    private struct Payload: Decodable {
        let schema: String, status: String, modelName: String, measurementScope: String
        let nativeImportable: Bool
        let candidate: Candidate, plan: Plan, review: Review
    }
}

protocol RecordMeasurementTransport: AnyObject, Sendable {
    func request(_ data: Data) async throws -> Data
    func stop()
}

extension GGUFShadowTransport: RecordMeasurementTransport {}

/// Owns only explicit record measurement subprocesses, with no reply-route,
/// memory, learned-state, external-service or general model-setting mutations.
@MainActor
final class RecordMeasurementClient {
    private static let bundledReaderAvailable = (try? RecordMeasurementReader.loadBundled()) != nil

    /// Packaging availability only. Each measurement also checks protocol support
    /// with --validate-record before the endpoint that loads the model can run.
    static var available: Bool {
        GGUFRepresentationClient.bundledWorkerAvailable && bundledReaderAvailable
    }

    private let readerLoader: () throws -> RecordMeasurementReader
    private let modelResolver: () throws -> URL
    private let workerURL: () -> URL?
    private let transportFactory: (URL, [String], TimeInterval) -> any RecordMeasurementTransport
    private var generation: UInt64 = 0
    private var disposed = false
    private var busy = false
    private var transport: (any RecordMeasurementTransport)?

    convenience init() {
        self.init(readerLoader: RecordMeasurementReader.loadBundled,
                  modelResolver: RecordMeasurementReader.resolveModel,
                  workerURL: { GGUFRepresentationClient.bundledWorkerURL },
                  transportFactory: { GGUFShadowTransport(executable: $0, arguments: $1, timeout: $2) })
    }

    /// Internal dependency seam for synthetic lifecycle tests; production always
    /// uses the pinned bundle, named local model and bundled process transport.
    init(readerLoader: @escaping () throws -> RecordMeasurementReader,
         modelResolver: @escaping () throws -> URL,
         workerURL: @escaping () -> URL?,
         transportFactory: @escaping (URL, [String], TimeInterval) -> any RecordMeasurementTransport) {
        self.readerLoader = readerLoader; self.modelResolver = modelResolver
        self.workerURL = workerURL; self.transportFactory = transportFactory
    }

    func measure(input: String, system: String, schema: String) async throws -> RecordMeasurement {
        guard !disposed, !Task.isCancelled else { throw CancellationError() }
        guard !busy else { throw RecordMeasurementError.busy }
        let owner = generation
        busy = true
        defer { if generation == owner { busy = false } }
        do {
            let reader = try readerLoader(), model = try modelResolver()
            guard let executable = workerURL() else { throw RecordMeasurementError.unavailable }
            let requestID = UUID().uuidString
            let payload = try makePayload(input: input, system: system, schema: schema,
                                          requestID: requestID, model: model, reader: reader)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let bytes = try encoder.encode(payload)
            guard bytes.count <= 512 * 1024 else { throw RecordMeasurementError.invalidInput }
            let ready = try await exchange(bytes, executable: executable, validateOnly: true, owner: owner)
            try Self.validateResponse(ready, payload: payload, reader: reader, validationOnly: true)
            try require(owner)
            // A changed or removed named local model cannot inherit preflight.
            guard try modelResolver() == model else { throw RecordMeasurementError.unavailable }
            let response = try await exchange(bytes, executable: executable, validateOnly: false, owner: owner)
            try require(owner)
            try Self.validateResponse(response, payload: payload, reader: reader, validationOnly: false)
            guard try modelResolver() == model else { throw RecordMeasurementError.unavailable }
            try require(owner)
            return RecordMeasurement(rawScore: response["raw_score"]!.recordNumber!,
                standardizedScore: response["standardized_score"]!.recordNumber!,
                inputTokens: recordInteger(response["input_tokens"], maximum: 512)!, outputTokens: 0,
                readerDigest: RecordMeasurementReader.artifactDigest, requestID: requestID)
        } catch {
            try require(owner)
            throw error
        }
    }

    func cancel() {
        generation &+= 1
        busy = false
        transport?.stop()
        transport = nil
    }

    func shutdown() { disposed = true; cancel() }

    private func require(_ owner: UInt64) throws {
        guard !disposed, generation == owner, !Task.isCancelled else { throw CancellationError() }
    }

    private func exchange(_ bytes: Data, executable: URL, validateOnly: Bool, owner: UInt64) async throws -> JSONValue {
        try require(owner)
        let worker = transportFactory(executable, [validateOnly ? "--validate-record" : "--measure-record"],
                                      validateOnly ? 15 : 180)
        transport = worker
        defer { if generation == owner { transport = nil }; worker.stop() }
        let result = try await withTaskCancellationHandler {
            try await worker.request(bytes)
        } onCancel: { worker.stop() }
        try require(owner)
        guard !result.isEmpty, result.count <= 16 * 1024,
              GGUFReaderArtifact.hasUniqueKeys(result, maximumDepth: 2) else { throw RecordMeasurementError.invalidResponse }
        return try JSONDecoder().decode(JSONValue.self, from: result)
    }

    private func makePayload(input: String, system: String, schema: String, requestID: String,
                             model: URL, reader: RecordMeasurementReader) throws -> JSONValue {
        guard !input.isEmpty, input.utf8.count <= RecordLookupTable.maximumSourceBytes + 128,
              input.utf8.allSatisfy({ $0 == 10 || (32...126).contains($0) }), !input.contains("<|"),
              input.hasPrefix("record | field | value\n"), system == RecordLookupQuery.system,
              schema == RecordLookupQuery.schema else { throw RecordMeasurementError.invalidInput }
        // The no-load worker preflight also validates the complete table/query
        // grammar before any activation may be requested.
        let prompt = "<|im_start|>system\n" + system + "<|im_end|>\n<|im_start|>user\n" + input
            + "\n\nReturn exactly one JSON object matching this schema:\n" + schema
            + "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
        return .object([
            "schema": .string("archi-record-measurement-request/v1"), "request_id": .string(requestID),
            "model_name": .string(RecordMeasurementReader.modelName),
            "model_digest": .string(RecordMeasurementReader.modelDigest),
            "model_blob_digest": .string(RecordMeasurementReader.modelBlobDigest), "model_path": .string(model.path),
            "backend_revision": .string(RecordMeasurementReader.backendRevision),
            "reader_artifact_digest": .string(RecordMeasurementReader.artifactDigest),
            "numeric_digest": .string(RecordMeasurementReader.numericDigest),
            "candidate_digest": .string(RecordMeasurementReader.candidateDigest),
            "qualification_digest": .string(RecordMeasurementReader.qualificationDigest),
            "plan_digest": .string(RecordMeasurementReader.planDigest),
            "tokenizer_digest": .string(RecordMeasurementReader.modelBlobDigest),
            "template_digest": .string(GGUFReaderArtifact.templateDigest), "precision": .string("Q4_K_M"),
            "layer": .string(RecordMeasurementReader.layer), "token_rule": .string(RecordMeasurementReader.tokenRule),
            "measurement_scope": .string(RecordMeasurementReader.measurementScope),
            "input": .string(input), "system": .string(system), "response_schema": .string(schema), "prompt": .string(prompt),
            "input_digest": .string(GGUFReaderArtifact.digest(Data(input.utf8))),
            "system_digest": .string(GGUFReaderArtifact.digest(Data(system.utf8))),
            "schema_digest": .string(GGUFReaderArtifact.digest(Data(schema.utf8))),
            "prompt_digest": .string(GGUFReaderArtifact.digest(Data(prompt.utf8))),
            "max_input_tokens": .number(512), "max_new_tokens": .number(0), "deadline_ms": .number(180_000),
            "basis": reader.wireBasis
        ])
    }

    static let echoedKeys = ["request_id", "model_name", "model_digest", "model_blob_digest", "backend_revision",
        "reader_artifact_digest", "numeric_digest", "candidate_digest", "qualification_digest", "plan_digest",
        "tokenizer_digest", "template_digest", "precision", "layer", "token_rule", "measurement_scope",
        "input_digest", "system_digest", "schema_digest", "prompt_digest"]

    static func validateResponse(_ response: JSONValue, payload: JSONValue,
                                 reader: RecordMeasurementReader, validationOnly: Bool) throws {
        let scores = ["raw_score", "standardized_score", "input_tokens", "output_tokens", "token_position"]
        let allowed = Set(echoedKeys + ["schema", "status", "backend_execution"] + (validationOnly ? [] : scores))
        guard let object = response.object, Set(object.keys) == allowed,
              response["schema"]?.string == "archi-record-measurement-result/v1",
              response["status"]?.string == (validationOnly ? "validated" : "ok"),
              response["backend_execution"]?.string == "arm64-cpu",
              echoedKeys.allSatisfy({ response[$0] != nil && response[$0] == payload[$0] }) else {
            throw RecordMeasurementError.invalidResponse
        }
        if validationOnly { return }
        guard let raw = response["raw_score"]?.recordNumber, raw.isFinite,
              let standardized = response["standardized_score"]?.recordNumber, standardized.isFinite,
              let inputTokens = recordInteger(response["input_tokens"], maximum: 512), inputTokens > 0,
              recordInteger(response["output_tokens"], maximum: 0) == 0,
              recordInteger(response["token_position"], maximum: 511) == inputTokens - 1 else {
            throw RecordMeasurementError.invalidResponse
        }
        let expected = (raw - reader.scoreOffset[0]) / reader.scoreScale[0]
        guard expected.isFinite, abs(expected - standardized) <= 1.0e-9 * max(1, abs(expected)) else {
            throw RecordMeasurementError.invalidResponse
        }
    }
}

private extension JSONValue {
    var recordNumber: Double? { if case .number(let value) = self { value } else { nil } }
}

private func recordInteger(_ value: JSONValue?, maximum: Int) -> Int? {
    guard let number = value?.recordNumber, number.isFinite, number >= 0,
          number <= Double(maximum), number.rounded(.towardZero) == number else { return nil }
    return Int(number)
}
