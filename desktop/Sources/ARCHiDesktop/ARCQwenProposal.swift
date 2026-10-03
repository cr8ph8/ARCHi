import Foundation
import CryptoKit

enum ARCProposalOperation: String, Codable, CaseIterable, Equatable, Sendable {
    case rotate90, rotate180, rotate270, reflectRows, reflectColumns, transpose, antiTranspose
    case cropNonzero, scale2, scale3, tile2, tile3
    case cropLargest, cropSmallest, keepLargest, keepSmallest
}

enum ARCProposalStatus: String, Codable, Equatable, Sendable {
    case predicted, abstained, trainingMismatch, trainingUndefined, predictionUndefined, budgetExhausted
}

struct ARCProposalEvaluation: Equatable, Sendable {
    let status: ARCProposalStatus
    let trainingPassed: Int
    let trainingCount: Int
    let predictions: [ARCGrid]?
    let cellOperations: Int
}

/// One Qwen-proposed typed program, independently executed after terminal JSON
/// validation. It is deliberately not an ARCSolverRun or catalog-consensus claim.
struct ARCQwenProposalResult: Equatable, Sendable {
    typealias Status = ARCProposalStatus
    let requestID: String
    let inputDigest: String
    let model: QwenModelMetadata
    let status: Status
    let steps: [ARCProposalOperation]
    let learnPalette: Bool
    let trainingPassed: Int
    let trainingCount: Int
    let predictions: [ARCGrid]?
    let cellOperations: Int
}

enum ARCQwenProposalError: LocalizedError, Equatable {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { text } else { nil } }
}

enum ARCQwenProposalEngine {
    static let version = "archi-local-qwen-proposal-v1"
    static let maximumResponseBytes = 8_192
    static let maximumCellOperations = 2_000_000

    private static let instruction = """
    You are ARCHi's bounded local ARC program proposer. Return exactly one JSON object matching the supplied schema. Copy requestID and inputDigest exactly. Do not return commentary, Markdown, code, tools, hidden reasoning, output grids or additional fields.
    The input contains only training input/output grid pairs and test input grids. Infer one short program from ALL training pairs. A native executor will independently verify it before applying it to test inputs. Use decision PROPOSE only for one program you expect to fit every training pair, otherwise ABSTAIN. ABSTAIN requires steps=[] and learnPalette=false. Empty steps with learnPalette=false proposes identity.
    Operations apply in listed order, with at most three steps: rotate90/180/270 are clockwise; reflectRows reverses row order, reflectColumns reverses column order; transpose and antiTranspose reflect the two diagonals; cropNonzero crops the bounding box of all nonzero cells; scale2/scale3 repeat each cell by that factor on both axes; tile2/tile3 repeat the whole grid on both axes. Object rules cropLargest/cropSmallest/keepLargest/keepSmallest use same-color four-neighbor components with zero background, ordered by (-area,color,minRow,maxRow,minColumn,maxColumn); largest selects first and smallest last. Crop copies original bounding-box pixels; keep preserves dimensions and only selected component cells. All-zero crops/object rules and grids exceeding 30 by 30 are undefined.
    learnPalette=true learns one consistent color mapping from the transformed training inputs to their outputs, applied after all steps. Colors unseen in that mapping are undefined. Colors are integers 0 through 9. You cannot change these rules, the checker, permissions, memory, files or any other state. This single proposal is not a benchmark score or consensus among all programs.
    """

    static func request(input: ARCSolverInput, requestID: String) throws -> LocalRoleRequest {
        guard UUID(uuidString: requestID) != nil else { throw invalid("The proposal request identity is invalid.") }
        try ARCSymbolicSolver.validateProposalInput(input)
        let digest = try inputDigest(input)
        let inputValue = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(input))
        let payload = JSONValue.object(["requestID": .string(requestID), "inputDigest": .string(digest), "input": inputValue])
        let schema = outputSchema(requestID: requestID, inputDigest: digest)
        // Leave room for Ollama's message escaping and transport wrapper. Its
        // existing complete-wire budget remains authoritative and may reject too.
        let bytes = try JSONEncoder().encode(payload).count + JSONEncoder().encode(schema).count + instruction.utf8.count
        guard bytes <= 20_000 else { throw invalid("This task exceeds the bounded local proposal context. No task was truncated.") }
        return .init(id: requestID, role: .reasoning, input: payload, outputSchema: schema, systemInstructionOverride: instruction)
    }

    static func evaluate(
        _ response: LocalRoleResult, request: LocalRoleRequest, input: ARCSolverInput,
        expectedModel: QwenModelMetadata, isCancelled: @Sendable () -> Bool = { false }
    ) throws -> ARCQwenProposalResult {
        try checkCancellation(isCancelled)
        let bound = try self.request(input: input, requestID: request.id)
        guard request.role == .reasoning, response.role == .reasoning,
              request.input == bound.input, request.outputSchema == bound.outputSchema,
              request.systemInstructionOverride == bound.systemInstructionOverride,
              response.requestID == request.id, response.model == expectedModel,
              validModel(expectedModel), response.elapsedMilliseconds >= 0 else {
            throw invalid("The terminal proposal does not match this request and connected model.")
        }
        // LocalRoleResult is emitted only after QwenAssistant's verified stream
        // terminates. Metadata is a binding check, not independent authentication;
        // fabricated clients are confined to fixtures, never a transport fallback.
        let bytes = Data(response.text.utf8)
        guard bytes.count <= maximumResponseBytes else { throw invalid("The local proposal exceeds its response limit.") }
        var scanner = UniqueJSONKeys(bytes: Array(bytes))
        let object: [String: JSONValue]
        do {
            try scanner.validate()
            guard let decoded = try JSONDecoder().decode(JSONValue.self, from: bytes).object else {
                throw invalid("The proposal must be one JSON object.")
            }
            object = decoded
        } catch { throw invalid("The local proposal is malformed or has repeated fields.") }
        guard Set(object.keys) == ["requestID", "inputDigest", "decision", "steps", "learnPalette"],
              object["requestID"]?.string == request.id,
              let digest = object["inputDigest"]?.string, digest == bound.input["inputDigest"]?.string,
              let decision = object["decision"]?.string, ["PROPOSE", "ABSTAIN"].contains(decision),
              let rawSteps = object["steps"]?.array, rawSteps.count <= 3,
              let palette = object["learnPalette"]?.bool else {
            throw invalid("The proposal contains an unsupported field, binding, decision or program shape.")
        }
        let steps = try rawSteps.map { value -> ARCProposalOperation in
            guard let name = value.string, let operation = ARCProposalOperation(rawValue: name) else {
                throw invalid("The proposal contains an unsupported operation.")
            }
            return operation
        }
        try checkCancellation(isCancelled)
        let evaluation: ARCProposalEvaluation
        if decision == "ABSTAIN" {
            guard steps.isEmpty, !palette else { throw invalid("An abstention cannot contain a program.") }
            evaluation = .init(status: .abstained, trainingPassed: 0, trainingCount: input.training.count,
                               predictions: nil, cellOperations: 0)
        } else {
            evaluation = try ARCSymbolicSolver.evaluateProposal(input, steps: steps, learnPalette: palette, isCancelled: isCancelled)
        }
        try checkCancellation(isCancelled)
        return .init(requestID: request.id, inputDigest: digest, model: response.model, status: evaluation.status,
                     steps: steps, learnPalette: palette, trainingPassed: evaluation.trainingPassed,
                     trainingCount: evaluation.trainingCount, predictions: evaluation.predictions, cellOperations: evaluation.cellOperations)
    }

    /// Targets enter only this checker-side operation after deterministic program
    /// execution. The existing checker schema has no symbolic evidence attached.
    static func bundle(document: ARCSolverDocument, result: ARCQwenProposalResult, codeHash: String, model: QwenModelMetadata) throws -> Data {
        let predictionShapeValid = result.status == .predicted
            ? (result.trainingPassed == result.trainingCount && result.predictions?.count == document.input.testInputs.count)
            : result.predictions == nil
        guard UUID(uuidString: result.requestID) != nil, result.inputDigest == document.inputDigest,
              result.model == model, validModel(model), validDigest(codeHash), result.steps.count <= 3,
              result.trainingCount == document.input.training.count,
              (0...result.trainingCount).contains(result.trainingPassed),
              (0...maximumCellOperations).contains(result.cellOperations), predictionShapeValid else {
            throw invalid("The proposal result cannot be bound to this task and executable.")
        }
        let task: [String: Any] = ["taskId": document.taskID,
            "train": document.input.training.map { ["input": $0.input, "output": $0.output] },
            "test": zip(document.input.testInputs, document.targets).map { input, target -> [String: Any] in
                var item: [String: Any] = ["input": input]
                if let target { item["output"] = target }
                return item
            }]
        let configurationHash = try ARCCapabilitiesEvaluator.digest([
            "lane": "single-local-proposal", "version": version,
            "decision": result.status == .abstained ? "ABSTAIN" : "PROPOSE",
            "steps": result.steps.map(\.rawValue), "learnPalette": result.learnPalette,
            "solverInput": result.inputDigest, "modelName": model.name, "modelDigest": model.digest,
            "maxSteps": 3, "maxCellOperations": maximumCellOperations
        ] as [String: Any])
        let manifest: [String: Any] = ["schemaVersion": 1,
            "manifestId": "qwen-proposal-" + String(document.sourceDigest.dropFirst(7).prefix(24)),
            "mode": document.isSynthetic ? "fixture" : "offline-dataset", "integration": "none",
            "scorerVersion": ARCCapabilitiesEvaluator.scorer,
            "source": ["label": document.name, "status": document.isSynthetic ? "synthetic-fixture" : "unverified-offline-snapshot",
                       "snapshot": "local-json-v1", "contentHash": document.sourceDigest], "split": "local-task",
            "tasks": [["taskId": document.taskID, "taskHash": try ARCCapabilitiesEvaluator.digest(task),
                       "testExamples": document.input.testInputs.count]]]
        let bundle: [String: Any] = ["schema": ARCCapabilitiesEvaluator.schema, "manifest": manifest,
            "solver": ["id": "archi-local-qwen-proposal", "version": version, "codeHash": codeHash, "configurationHash": configurationHash],
            "evaluations": [["task": task, "predictions": result.predictions ?? []]]]
        return try JSONSerialization.data(withJSONObject: bundle, options: [.sortedKeys])
    }

    static func executableHash(isCancelled: @Sendable () -> Bool = { false }) throws -> String {
        try checkCancellation(isCancelled)
        guard let executable = Bundle.main.executableURL else { throw invalid("The proposal executable could not be identified.") }
        let handle = try FileHandle(forReadingFrom: executable)
        defer { try? handle.close() }
        var digest = SHA256(), size = 0
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try checkCancellation(isCancelled)
            size += chunk.count
            guard size <= 512 * 1_048_576 else { throw invalid("The proposal executable exceeds its identity limit.") }
            digest.update(data: chunk)
        }
        guard size > 0 else { throw invalid("The proposal executable is empty.") }
        return "sha256:" + digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func inputDigest(_ input: ARCSolverInput) throws -> String {
        try ARCCapabilitiesEvaluator.digest([
            "train": input.training.map { ["input": $0.input, "output": $0.output] },
            "test": input.testInputs.map { ["input": $0] }
        ])
    }
    private static func outputSchema(requestID: String, inputDigest: String) -> JSONValue {
        let properties: [String: JSONValue] = [
            "requestID": .object(["type": .string("string"), "const": .string(requestID)]),
            "inputDigest": .object(["type": .string("string"), "const": .string(inputDigest)]),
            "decision": .object(["type": .string("string"), "enum": .array([.string("PROPOSE"), .string("ABSTAIN")])]),
            "steps": .object(["type": .string("array"), "maxItems": .number(3),
                              "items": .object(["type": .string("string"), "enum": .array(ARCProposalOperation.allCases.map { .string($0.rawValue) })])]),
            "learnPalette": .object(["type": .string("boolean")])
        ]
        return .object(["type": .string("object"), "additionalProperties": .bool(false),
                        "properties": .object(properties), "required": .array(properties.keys.sorted().map(JSONValue.string))])
    }
    private static func validModel(_ model: QwenModelMetadata) -> Bool {
        let family = ["qwen3.5:9b": "qwen35", "qwen3:8b": "qwen3"][model.name]
        return family == model.family && model.digest.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil &&
            model.parameterSize.utf8.count <= 80 && model.quantization.utf8.count <= 80
    }
    private static func validDigest(_ value: String) -> Bool {
        value.range(of: "^sha256:[0-9a-f]{64}$", options: .regularExpression) != nil
    }
    private static func checkCancellation(_ isCancelled: @Sendable () -> Bool) throws {
        if isCancelled() || Task<Never, Never>.isCancelled { throw CancellationError() }
    }
    private static func invalid(_ text: String) -> ARCQwenProposalError { .invalid(text) }
}
