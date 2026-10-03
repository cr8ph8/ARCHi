import CryptoKit
import Darwin
import Foundation

/// Session-only activation reader for the existing local reasoning lane. No
/// discovery, executable configuration, model installation, or external fallback.
@MainActor
final class GGUFRepresentationClient: LocalRoleClient {
    static var bundledWorkerURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("RepresentationBridge/archi-gguf-shadow")
    }
    static var bundledWorkerAvailable: Bool {
        bundledWorkerURL.map { FileManager.default.isExecutableFile(atPath: $0.path) } ?? false
    }
    let representationAccess: LocalRepresentationAccess = .activationReadOnly
    let representationConfiguration: LocalRepresentationConfiguration
    let model: String
    let reader: GGUFReaderArtifact
    private var metadata: QwenModelMetadata?
    private var generation: UInt64 = 0
    private var disposed = false
    private var busy = false
    private var transport: GGUFShadowTransport?

    init(model: String, reader: GGUFReaderArtifact) {
        self.model = model
        self.reader = reader
        representationConfiguration = .init(mode: .shadow, basis: reader.basis)
    }

    func connect() async throws {
        guard !disposed else { throw QwenFailure.stopped }
        disconnect()
        let owner = generation
        do {
            let local = try resolveModel()
            let id = UUID().uuidString
            let readiness = LocalRoleRequest(id: id, role: .reasoning,
                input: .object(["requestID": .string(id)]),
                outputSchema: .object(["type": .string("object")]))
            let payload = try makePayload(readiness, modelPath: local.url)
            let response = try await exchange(payload, validateOnly: true)
            try require(owner)
            try validateIdentity(response, request: readiness, payload: payload, status: "validated")
            guard response["text"] == nil, response["samples"] == nil else {
                throw LocalRepresentationContractError.mismatched
            }
            metadata = local.metadata
        } catch {
            try rethrow(error, owner: owner)
        }
    }

    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
        guard !disposed, let installed = metadata else { throw LocalRepresentationContractError.unavailable }
        guard !busy else { throw LocalRepresentationContractError.unavailable }
        let owner = generation
        busy = true
        defer { if generation == owner { busy = false } }
        let started = ContinuousClock.now
        do {
            guard UUID(uuidString: request.id) != nil,
                  request.input["requestID"]?.string == request.id,
                  request.outputSchema.object != nil else { throw LocalRepresentationContractError.mismatched }
            let local = try resolveModel()
            guard local.metadata == installed else { throw LocalRepresentationContractError.mismatched }
            let payload = try makePayload(request, modelPath: local.url)
            let response = try await exchange(payload, validateOnly: false)
            try require(owner)
            try validateIdentity(response, request: request, payload: payload, status: "ok")
            guard response["stop_reason"]?.string == "eos",
                  let text = response["text"]?.string, !text.isEmpty, text.utf8.count <= 256 * 1024,
                  let outputDigest = response["output_digest"]?.string,
                  outputDigest == GGUFReaderArtifact.digest(Data(text.utf8)),
                  let rawSamples = response["samples"]?.array,
                  !rawSamples.isEmpty, rawSamples.count <= 1024 else {
                throw LocalRepresentationContractError.mismatched
            }
            if reader.tokenRule == "prompt-last" {
                guard rawSamples.count == 1,
                      Self.integer(rawSamples[0]["decode_index"], maximum: 32_767) == 0,
                      let inputTokens = Self.integer(response["input_tokens"], maximum: 8192), inputTokens > 0,
                      Self.integer(rawSamples[0]["token_position"], maximum: 32_767) == inputTokens - 1 else {
                    throw LocalRepresentationContractError.mismatched
                }
            }
            var previousIndex = -1
            let samples = try rawSamples.map { sample -> LocalRepresentationAssay.Sample in
                guard let index = Self.integer(sample["decode_index"], maximum: 32_767), index > previousIndex,
                      Self.integer(sample["token_position"], maximum: 32_767) != nil,
                      sample["layer"]?.string == reader.layer,
                      let raw = sample["raw_scores"]?.array, raw.count == 1,
                      let coordinates = sample["coordinates"]?.array, coordinates.count == 1,
                      let score = raw[0].ggufNumber, score.isFinite,
                      let coordinate = coordinates[0].ggufNumber, coordinate.isFinite,
                      (0...1).contains(coordinate) else { throw LocalRepresentationContractError.mismatched }
                previousIndex = index
                return .init(tokenIndex: index, rawScore: score, coordinate: coordinate)
            }
            let assay = LocalRepresentationAssay(schemaVersion: "archi-representation-assay/v1",
                requestID: request.id, inputDigest: payload["input_digest"]!.string!,
                systemDigest: payload["system_digest"]!.string!, schemaDigest: payload["schema_digest"]!.string!,
                outputDigest: outputDigest, basis: reader.basis, mode: .shadow, phase: "unsteered", samples: samples)
            let duration = started.duration(to: .now).components
            let elapsed = max(0, Int(duration.seconds * 1000 + duration.attoseconds / 1_000_000_000_000_000))
            let inputTokens = Self.integer(response["input_tokens"], maximum: 8192)
            let outputTokens = Self.integer(response["output_tokens"], maximum: 1024)
            let metrics = inputTokens == nil && outputTokens == nil ? nil
                : LocalInferenceMetrics(inputTokens: inputTokens, outputTokens: outputTokens)
            return LocalRoleResult(requestID: request.id, role: request.role, text: text,
                model: installed, elapsedMilliseconds: elapsed, metrics: metrics, representationAssay: assay)
        } catch {
            try rethrow(error, owner: owner)
            throw LocalRepresentationContractError.unavailable
        }
    }

    func disconnect() {
        generation &+= 1
        metadata = nil
        busy = false
        transport?.stop()
        transport = nil
    }

    func shutdown() async { disposed = true; disconnect() }

    private func require(_ owner: UInt64) throws {
        guard !disposed, generation == owner, !Task.isCancelled else { throw QwenFailure.stopped }
    }

    private func rethrow(_ error: any Error, owner: UInt64) throws {
        if Task.isCancelled || disposed || generation != owner || (error as? QwenFailure) == .stopped {
            throw QwenFailure.stopped
        }
        if let contract = error as? LocalRepresentationContractError { throw contract }
        throw LocalRepresentationContractError.unavailable
    }

    private func exchange(_ payload: JSONValue, validateOnly: Bool) async throws -> JSONValue {
        guard let executable = Self.bundledWorkerURL else { throw LocalRepresentationContractError.unavailable }
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw LocalRepresentationContractError.unavailable
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        guard data.count <= 1024 * 1024 else { throw LocalRepresentationContractError.mismatched }
        let worker = GGUFShadowTransport(executable: executable, validateOnly: validateOnly,
            timeout: validateOnly ? 15 : 180)
        transport = worker
        defer { if transport === worker { transport = nil }; worker.stop() }
        let response = try await worker.request(data)
        return try JSONDecoder().decode(JSONValue.self, from: response)
    }

    private func makePayload(_ request: LocalRoleRequest, modelPath: URL) throws -> JSONValue {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let input = try encoder.encode(request.input), schema = try encoder.encode(request.outputSchema)
        let system = Data(request.systemInstruction.utf8)
        guard input.count <= 160 * 1024, system.count <= 64 * 1024, schema.count <= 64 * 1024 else {
            throw LocalRepresentationContractError.mismatched
        }
        let inputText = String(decoding: input, as: UTF8.self)
        let schemaText = String(decoding: schema, as: UTF8.self)
        let prompt = reader.prompt(system: request.systemInstruction, input: inputText, schema: schemaText)
        let basisBytes = try encoder.encode(reader.wireBasis)
        return .object([
            "schema": .string("archi-gguf-shadow-request/v1"), "request_id": .string(request.id),
            "role": .string(request.role.rawValue), "model_name": .string(model),
            "model_digest": .string(reader.modelDigest), "model_blob_digest": .string(reader.modelBlobDigest),
            "model_path": .string(modelPath.path), "input": .string(inputText),
            "system": .string(request.systemInstruction), "response_schema": .string(schemaText),
            "input_digest": .string(GGUFReaderArtifact.digest(input)),
            "system_digest": .string(GGUFReaderArtifact.digest(system)),
            "schema_digest": .string(GGUFReaderArtifact.digest(schema)),
            "prompt": .string(prompt), "prompt_digest": .string(GGUFReaderArtifact.digest(Data(prompt.utf8))),
            "mode": .string("shadow"), "max_input_tokens": .number(8192), "max_new_tokens": .number(1024),
            "deadline_ms": .number(180_000), "basis": reader.wireBasis,
            "basis_payload": .string(String(decoding: basisBytes, as: UTF8.self)),
            "basis_payload_digest": .string(GGUFReaderArtifact.digest(basisBytes)),
            "reader_artifact_digest": .string(reader.importedArtifactDigest)
        ])
    }

    private func validateIdentity(_ response: JSONValue, request: LocalRoleRequest,
                                  payload: JSONValue, status: String) throws {
        guard response["schema"]?.string == "archi-gguf-shadow-result/v1",
              response["status"]?.string == status,
              response["request_id"]?.string == request.id, response["role"]?.string == request.role.rawValue,
              response["mode"]?.string == "shadow",
              ["model_name", "model_digest", "model_blob_digest", "input_digest", "system_digest", "schema_digest", "prompt_digest",
               "basis_payload_digest", "reader_artifact_digest"]
                .allSatisfy({ response[$0] == payload[$0] }),
              let returnedBasis = response["basis"], let expectedBasis = reader.wireBasis.object,
              ["namespace", "model_digest", "model_blob_digest", "tokenizer_digest", "template_digest",
               "backend_revision", "precision", "basis_digest", "reader_digest", "calibration_digest", "layer", "names",
               "token_rule", "measurement_scope"]
                .allSatisfy({ returnedBasis[$0] == expectedBasis[$0] }) else {
            throw LocalRepresentationContractError.mismatched
        }
    }

    /// Reads only the named model's manifest/config. The worker hashes the actual
    /// large GGUF before loading; readiness never loads or generates with it.
    private func resolveModel() throws -> (url: URL, metadata: QwenModelMetadata) {
        guard model == reader.modelName, QwenAssistant.supportedModels.contains(model),
              reader.basis.isValid else { throw LocalRepresentationContractError.unavailable }
        let components = model.split(separator: ":")
        guard components.count == 2 else { throw LocalRepresentationContractError.unavailable }
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ollama/models", isDirectory: true)
        let manifestURL = root.appendingPathComponent("manifests/registry.ollama.ai/library")
            .appendingPathComponent(String(components[0])).appendingPathComponent(String(components[1]))
        let manifestData = try Self.smallFile(manifestURL, maximum: 256 * 1024)
        guard GGUFReaderArtifact.digest(manifestData) == reader.modelDigest,
              let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let layers = manifest["layers"] as? [[String: Any]], layers.count <= 32,
              let config = manifest["config"] as? [String: Any],
              let configDigest = config["digest"] as? String,
              configDigest.hasPrefix("sha256:"), LocalRepresentationBasis.digest(String(configDigest.dropFirst(7))) else {
            throw LocalRepresentationContractError.mismatched
        }
        let modelLayers = layers.filter { $0["mediaType"] as? String == "application/vnd.ollama.image.model" }
        guard modelLayers.count == 1,
              modelLayers[0]["digest"] as? String == "sha256:" + reader.modelBlobDigest,
              let expectedSize = modelLayers[0]["size"] as? NSNumber,
              expectedSize.int64Value > 0, expectedSize.int64Value <= 32 * 1024 * 1024 * 1024 else {
            throw LocalRepresentationContractError.mismatched
        }
        let modelURL = root.appendingPathComponent("blobs/sha256-" + reader.modelBlobDigest)
        let resource = try modelURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard resource.isRegularFile == true, resource.isSymbolicLink != true,
              resource.fileSize.map(Int64.init) == expectedSize.int64Value else { throw LocalRepresentationContractError.mismatched }
        let configURL = root.appendingPathComponent("blobs/sha256-" + configDigest.dropFirst(7))
        let configData = try Self.smallFile(configURL, maximum: 32 * 1024)
        guard GGUFReaderArtifact.digest(configData) == String(configDigest.dropFirst(7)),
              let info = try JSONSerialization.jsonObject(with: configData) as? [String: Any],
              info["model_format"] as? String == "gguf",
              info["file_type"] as? String == "Q4_K_M",
              let family = info["model_family"] as? String,
              family == (model == QwenAssistant.defaultModel ? "qwen35" : "qwen3"),
              let size = info["model_type"] as? String, !size.isEmpty, size.utf8.count <= 80 else {
            throw LocalRepresentationContractError.mismatched
        }
        return (modelURL, QwenModelMetadata(name: model, family: family, parameterSize: size,
            quantization: "Q4_K_M", digest: reader.modelDigest))
    }

    private static func smallFile(_ url: URL, maximum: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= maximum else { throw LocalRepresentationContractError.unavailable }
        let data = try Data(contentsOf: url)
        guard data.count <= maximum else { throw LocalRepresentationContractError.unavailable }
        return data
    }

    private static func integer(_ value: JSONValue?, maximum: Int) -> Int? {
        guard let number = value?.ggufNumber, number.isFinite, number >= 0,
              number <= Double(maximum), number.rounded(.towardZero) == number else { return nil }
        return Int(number)
    }
}

private extension JSONValue {
    var ggufNumber: Double? { if case .number(let value) = self { value } else { nil } }
}

/// A single exchange with one owned child. Pipes are nonblocking, every buffer
/// is bounded, and Stop terminates only this Process, including partial output.
final class GGUFShadowTransport: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ARCHi.Representation.transport", qos: .userInitiated)
    private let lock = NSLock()
    private let executable: URL
    private let arguments: [String]
    private let timeout: TimeInterval
    private var retired = false
    private var process: Process?

    convenience init(executable: URL, validateOnly: Bool, timeout: TimeInterval) {
        self.init(executable: executable, arguments: validateOnly ? ["--validate-only"] : [], timeout: timeout)
    }

    init(executable: URL, arguments: [String], timeout: TimeInterval) {
        self.executable = executable; self.arguments = arguments; self.timeout = timeout
    }

    func request(_ data: Data) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    do { continuation.resume(returning: try exchange(data)) }
                    catch { stop(); continuation.resume(throwing: error) }
                }
            }
        } onCancel: { self.stop() }
    }

    func stop() {
        lock.lock(); retired = true; let child = process; lock.unlock()
        guard let child, child.isRunning else { return }
        child.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.75) {
            if child.isRunning { Darwin.kill(child.processIdentifier, SIGKILL) }
        }
    }

    private func check(_ deadline: TimeInterval) throws {
        lock.lock(); let stopped = retired; lock.unlock()
        guard !stopped, ProcessInfo.processInfo.systemUptime < deadline else {
            throw LocalRepresentationContractError.unavailable
        }
    }

    private func exchange(_ original: Data) throws -> Data {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let child = Process(), input = Pipe(), output = Pipe(), errors = Pipe()
        child.executableURL = executable
        child.arguments = arguments
        child.currentDirectoryURL = executable.deletingLastPathComponent()
        child.environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8"]
        child.standardInput = input; child.standardOutput = output; child.standardError = errors
        lock.lock()
        guard !retired else { lock.unlock(); throw LocalRepresentationContractError.unavailable }
        do { try child.run(); process = child; lock.unlock() }
        catch { lock.unlock(); throw error }
        defer {
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            try? errors.fileHandleForReading.close()
            stop()
        }
        let writeFD = input.fileHandleForWriting.fileDescriptor
        let outFD = output.fileHandleForReading.fileDescriptor, errFD = errors.fileHandleForReading.fileDescriptor
        for fd in [writeFD, outFD, errFD] {
            let flags = fcntl(fd, F_GETFL)
            guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else {
                throw LocalRepresentationContractError.unavailable
            }
        }
        // Prevent a closed child stdin from delivering SIGPIPE to the app.
        _ = fcntl(writeFD, F_SETNOSIGPIPE, 1)
        var request = original; request.append(10)
        var offset = 0, stdout = Data(), stderrCount = 0
        var inputClosed = false, stdoutClosed = false, stderrClosed = false
        while true {
            try check(deadline)
            var descriptors = [
                pollfd(fd: inputClosed ? -1 : writeFD, events: Int16(POLLOUT), revents: 0),
                pollfd(fd: stdoutClosed ? -1 : outFD, events: Int16(POLLIN), revents: 0),
                pollfd(fd: stderrClosed ? -1 : errFD, events: Int16(POLLIN), revents: 0)
            ]
            let ready = Darwin.poll(&descriptors, nfds_t(descriptors.count), 100)
            if ready < 0 && errno == EINTR { continue }
            guard ready >= 0 else { throw LocalRepresentationContractError.unavailable }
            if !inputClosed, descriptors[0].revents != 0 {
                let count = request.withUnsafeBytes { buffer in
                    Darwin.write(writeFD, buffer.baseAddress!.advanced(by: offset), min(8192, request.count - offset))
                }
                if count > 0 { offset += count }
                else if count < 0 && errno != EAGAIN && errno != EINTR { throw LocalRepresentationContractError.unavailable }
                if offset == request.count { try input.fileHandleForWriting.close(); inputClosed = true }
            }
            for index in [1, 2] where descriptors[index].revents != 0 {
                var buffer = [UInt8](repeating: 0, count: 8192)
                let count = Darwin.read(descriptors[index].fd, &buffer, buffer.count)
                if count < 0 && (errno == EAGAIN || errno == EINTR) { continue }
                guard count >= 0 else { throw LocalRepresentationContractError.unavailable }
                if count == 0 {
                    if index == 1 { stdoutClosed = true } else { stderrClosed = true }
                } else if index == 1 {
                    stdout.append(contentsOf: buffer.prefix(count))
                    guard stdout.count <= 1024 * 1024 else { throw LocalRepresentationContractError.unavailable }
                } else {
                    stderrCount += count
                    guard stderrCount <= 128 * 1024 else { throw LocalRepresentationContractError.unavailable }
                }
            }
            if stdoutClosed && stderrClosed && !child.isRunning {
                guard inputClosed, child.terminationReason == .exit, child.terminationStatus == 0,
                      let newline = stdout.firstIndex(of: 10),
                      stdout.dropFirst(newline + 1).allSatisfy({ [9, 10, 13, 32].contains($0) }) else {
                    throw LocalRepresentationContractError.mismatched
                }
                return Data(stdout[..<newline])
            }
        }
    }

    deinit { stop() }
}
