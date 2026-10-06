import CryptoKit
import Foundation

/// An explicitly imported, in-memory reader. Declared lineage is not proof of
/// scientific qualification; importedArtifactDigest identifies the bytes read.
struct GGUFReaderArtifact: Sendable {
    static let schemaVersion = "archi-gguf-reader/v2"
    static let legacySchemaVersion = "archi-gguf-reader/v1"
    static let promptFinalMeasurementScope = "synthetic-record-field-support/prompt-final/v1"
    static let backendRevision = "llama.cpp:161755f29"
    static let maximumBytes = 512 * 1024
    static let hiddenWidth = 4096
    // This pinned backend does not automatically adopt future Ollama choices.
    static let supportedModels = ["qwen3.5:9b", "qwen3:8b"]

    let modelName: String
    let modelDigest: String
    let modelBlobDigest: String
    let basis: LocalRepresentationBasis
    let directions: [[Double]]
    let center: [Double]
    let scoreOffset: [Double]
    let scoreScale: [Double]
    let provenance: String
    let importedArtifactDigest: String
    let measurementScope: String?
    let calibrationSummary: GGUFReaderCalibrationSummary?

    var readerName: String { basis.readerName }
    var layer: String { basis.layer }
    var tokenRule: String { basis.tokenRule }
    var hasLimitedShadowReport: Bool { calibrationSummary != nil }
    /// Neither legacy imports nor the v2 synthetic prompt-final report qualify
    /// ordinary reply measurements. A passing narrow report cannot widen scope.
    var canMeasureGeneralReplies: Bool { false }
    var displayName: String { "\(readerName) · \(modelName) · \(layer)" }

    /// This deliberately pins one explicit no-thinking ChatML rendering. It is
    /// separate from Ollama's mutable template and is part of the reader basis.
    static let template = "<|im_start|>system\n{{system}}<|im_end|>\n<|im_start|>user\n{{input}}"
        + "\n\nReturn exactly one JSON object matching this schema:\n{{schema}}"
        + "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
    static var templateDigest: String { digest(Data(template.utf8)) }

    static func load(from url: URL) throws -> Self {
        guard url.isFileURL else { throw LocalRepresentationContractError.unavailable }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= maximumBytes else {
            throw LocalRepresentationContractError.unavailable
        }
        let bytes = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try decode(bytes)
    }

    static func decode(_ bytes: Data) throws -> Self {
        guard !bytes.isEmpty, bytes.count <= maximumBytes, hasUniqueKeys(bytes, maximumDepth: 4),
              let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let version = object["schemaVersion"] as? String,
              [schemaVersion, legacySchemaVersion].contains(version) else {
            throw LocalRepresentationContractError.mismatched
        }
        var allowedKeys = Set([
                "schemaVersion", "modelName", "modelDigest", "modelBlobDigest", "namespace",
                "tokenizerDigest", "templateDigest", "backendRevision", "precision", "layer",
                "readerName", "basisDigest", "readerDigest", "calibrationDigest", "directions",
                "center", "scoreOffset", "scoreScale", "provenance"
              ])
        if version == schemaVersion { allowedKeys.formUnion(["tokenRule", "measurementScope", "calibrationReport"]) }
        guard Set(object.keys) == allowedKeys else { throw LocalRepresentationContractError.mismatched }
        let value = try JSONDecoder().decode(Payload.self, from: bytes)
        guard value.schemaVersion == version,
              supportedModels.contains(value.modelName),
              value.backendRevision == backendRevision, value.precision == "Q4_K_M",
              LocalRepresentationBasis.digest(value.modelDigest),
              LocalRepresentationBasis.digest(value.modelBlobDigest),
              value.tokenizerDigest == value.modelBlobDigest,
              value.templateDigest == templateDigest,
              value.layer.hasPrefix("l_out-"),
              let layerNumber = Int(value.layer.dropFirst(6)),
              (0..<(value.modelName == "qwen3.5:9b" ? 32 : 36)).contains(layerNumber),
              value.layer == "l_out-\(layerNumber)",
              value.readerName.utf8.count <= 128,
              !value.provenance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.provenance.utf8.count <= 1600,
              value.directions.count == 1, value.directions[0].count == hiddenWidth,
              value.center.count == hiddenWidth, value.scoreOffset.count == 1,
              value.scoreScale.count == 1,
              (value.directions[0] + value.center + value.scoreOffset + value.scoreScale)
                .allSatisfy({ $0.isFinite && abs($0) <= 1.0e6 }),
              value.scoreScale[0] >= 1.0e-12,
              abs(value.directions[0].reduce(0) { $0 + $1 * $1 } - 1) <= 1.0e-5 else {
            throw LocalRepresentationContractError.mismatched
        }
        let summary: GGUFReaderCalibrationSummary?
        let tokenRule: String
        if version == schemaVersion {
            guard value.tokenRule == "prompt-last", value.measurementScope == promptFinalMeasurementScope,
                  value.namespace == "hampton.experimental.synthetic-record-field-support.v1",
                  value.readerName == "synthetic-record-field-support",
                  let report = value.calibrationReport else { throw GGUFReaderArtifactError.invalidCalibrationReport }
            summary = try GGUFReaderQualification.validate(report,
                digest: value.calibrationDigest, modelName: value.modelName,
                modelDigest: value.modelDigest, modelBlobDigest: value.modelBlobDigest,
                templateDigest: value.templateDigest, backendRevision: value.backendRevision,
                layer: value.layer, readerDigest: value.readerDigest,
                directions: value.directions, center: value.center,
                scoreOffset: value.scoreOffset, scoreScale: value.scoreScale)
            tokenRule = "prompt-last"
        } else {
            summary = nil
            tokenRule = "last"
        }
        var basis = LocalRepresentationBasis(namespace: value.namespace, modelDigest: value.modelDigest,
            tokenizerDigest: value.tokenizerDigest, templateDigest: value.templateDigest,
            backendRevision: value.backendRevision, precision: value.precision, layer: value.layer,
            tokenRule: tokenRule, readerName: value.readerName, basisDigest: value.basisDigest,
            readerDigest: value.readerDigest, calibrationDigest: value.calibrationDigest)
        basis.artifactDigest = digest(bytes)
        basis.measurementScope = value.measurementScope
        guard basis.isValid else { throw LocalRepresentationContractError.mismatched }
        return Self(modelName: value.modelName, modelDigest: value.modelDigest,
            modelBlobDigest: value.modelBlobDigest, basis: basis, directions: value.directions,
            center: value.center, scoreOffset: value.scoreOffset, scoreScale: value.scoreScale,
            provenance: value.provenance, importedArtifactDigest: digest(bytes),
            measurementScope: value.measurementScope, calibrationSummary: summary)
    }

    func prompt(system: String, input: String, schema: String) -> String {
        // Assemble pieces rather than substituting into user-supplied strings.
        "<|im_start|>system\n" + system + "<|im_end|>\n<|im_start|>user\n" + input
            + "\n\nReturn exactly one JSON object matching this schema:\n" + schema
            + "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
    }

    var wireBasis: JSONValue {
        var value: [String: JSONValue] = [
            "namespace": .string(basis.namespace), "model_digest": .string(modelDigest),
            "model_blob_digest": .string(modelBlobDigest), "tokenizer_digest": .string(basis.tokenizerDigest),
            "template_digest": .string(basis.templateDigest), "backend_revision": .string(basis.backendRevision),
            "precision": .string(basis.precision), "basis_digest": .string(basis.basisDigest),
            "token_rule": .string(tokenRule),
            "reader_digest": .string(basis.readerDigest), "calibration_digest": .string(basis.calibrationDigest),
            "layer": .string(layer), "names": .array([.string(readerName)]),
            "directions": .array(directions.map { .array($0.map(JSONValue.number)) }),
            "center": .array(center.map(JSONValue.number)),
            "score_offset": .array(scoreOffset.map(JSONValue.number)),
            "score_scale": .array(scoreScale.map(JSONValue.number))
        ]
        if let measurementScope { value["measurement_scope"] = .string(measurementScope) }
        return .object(value)
    }

    static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    /// Foundation otherwise accepts duplicate object keys. Reject duplicate
    /// decoded key spellings at every depth before parsing bounded JSON.
    static func hasUniqueKeys(_ data: Data, maximumDepth: Int) -> Bool {
        struct Frame {
            let isObject: Bool
            var awaitingKey: Bool
            var keys: Set<String> = []
        }
        let bytes = Array(data)
        var index = 0
        var frames: [Frame] = []
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 34 {
                let start = index
                index += 1
                while index < bytes.count && bytes[index] != 34 {
                    if bytes[index] == 92 { index += 1 }
                    index += 1
                }
                guard index < bytes.count else { return false }
                if let last = frames.indices.last, frames[last].isObject, frames[last].awaitingKey {
                    guard let key = try? JSONDecoder().decode(String.self, from: Data(bytes[start...index])),
                          frames[last].keys.insert(key).inserted else { return false }
                    frames[last].awaitingKey = false
                }
            } else if byte == 123 || byte == 91 {
                frames.append(Frame(isObject: byte == 123, awaitingKey: byte == 123))
                guard frames.count <= maximumDepth else { return false }
            } else if byte == 125 || byte == 93 {
                guard let last = frames.popLast(), last.isObject == (byte == 125) else { return false }
            } else if byte == 44, let last = frames.indices.last, frames[last].isObject {
                frames[last].awaitingKey = true
            }
            index += 1
        }
        return frames.isEmpty
    }

    private struct Payload: Decodable {
        let schemaVersion: String
        let modelName: String
        let modelDigest: String
        let modelBlobDigest: String
        let namespace: String
        let tokenizerDigest: String
        let templateDigest: String
        let backendRevision: String
        let precision: String
        let layer: String
        let readerName: String
        let basisDigest: String
        let readerDigest: String
        let calibrationDigest: String
        let directions: [[Double]]
        let center: [Double]
        let scoreOffset: [Double]
        let scoreScale: [Double]
        let provenance: String
        let tokenRule: String?
        let measurementScope: String?
        let calibrationReport: String?
    }

}

struct GGUFReaderCalibrationSummary: Sendable {
    let fitCount: Int
    let calibrationCount: Int
    let holdoutCount: Int
    let holdoutCorrect: Int
    let holdoutAccuracy: Double

    var summary: String {
        "Supplied limited shadow report: \(fitCount) fit, \(calibrationCount) calibration, \(holdoutCorrect)/\(holdoutCount) held-out synthetic cases."
    }
}

enum GGUFReaderArtifactError: Error, LocalizedError {
    case invalidCalibrationReport
    var errorDescription: String? {
        "This reader's report does not match the required passing synthetic prompt-final calibration scope or its exact recorded digest. It was not imported."
    }
}
