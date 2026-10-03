import Foundation

/// Explicit adapter support, independent of what is installed or connected.
/// Qwen3 dense sizes: https://qwenlm.github.io/blog/qwen3/
enum LocalModelCatalog {
    struct Entry: Equatable, Sendable {
        let name: String
        let family: String
        let isSmallModel: Bool
    }

    static let entries: [Entry] = [
        Entry(name: "qwen3.5:9b", family: "qwen35", isSmallModel: false),
        Entry(name: "qwen3:8b", family: "qwen3", isSmallModel: false),
        Entry(name: "qwen3:0.6b", family: "qwen3", isSmallModel: true),
        Entry(name: "qwen3:1.7b", family: "qwen3", isSmallModel: true),
        Entry(name: "qwen3:4b", family: "qwen3", isSmallModel: true)
    ]
    static let supportedModels = entries.map(\.name)
    static let smallModels = entries.filter(\.isSmallModel).map(\.name)
    static let maximumResponseBytes = 1_048_576
    static let maximumTagCount = 512

    static func family(for model: String) -> String? { entries.first { $0.name == model }?.family }
    static func isSmallModel(_ model: String) -> Bool { smallModels.contains(model) }

    /// A tag inventory is advisory. Missing capabilities are permitted here;
    /// connect always verifies completion and architecture through /api/show.
    static func installedModels(from data: Data) throws -> [QwenModelMetadata] {
        guard data.count <= maximumResponseBytes else { throw QwenFailure.invalidResponse }
        let value: JSONValue
        do { value = try JSONDecoder().decode(JSONValue.self, from: data) }
        catch { throw QwenFailure.invalidResponse }
        guard let tags = value["models"]?.array, tags.count <= maximumTagCount else {
            throw QwenFailure.invalidResponse
        }
        return entries.compactMap { entry in
            let matches = tags.filter { $0["name"]?.string == entry.name && $0["model"]?.string == entry.name }
            // Ambiguous aliases must not be advertised as a usable selection.
            guard matches.count == 1, let tag = matches.first,
                  let identity = try? tagIdentity(tag, model: entry.name),
                  let size = tag["details"]?["parameter_size"]?.string,
                  let quantization = tag["details"]?["quantization_level"]?.string,
                  validMetadataText(size), validMetadataText(quantization) else { return nil }
            return QwenModelMetadata(name: entry.name, family: identity.family,
                                     parameterSize: size, quantization: quantization, digest: identity.digest)
        }
    }

    static func tagIdentity(_ tag: JSONValue, model: String) throws -> (family: String, digest: String) {
        guard let expectedFamily = family(for: model) else { throw QwenFailure.unsupportedModel }
        guard tag["name"]?.string == model, tag["model"]?.string == model,
              isLocal(tag), tag["details"]?["format"]?.string == "gguf",
              tag["details"]?["family"]?.string == expectedFamily,
              let digest = tag["digest"]?.string,
              digest.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil else {
            throw QwenFailure.nonLocalModel
        }
        if let capabilities = tag["capabilities"] {
            guard capabilities.array?.contains(.string("completion")) == true,
                  capabilities.array?.contains(.string("cloud")) == false else { throw QwenFailure.nonLocalModel }
        }
        return (expectedFamily, digest)
    }

    /// Reject remote routing markers even when nested inside returned metadata.
    static func isLocal(_ value: JSONValue) -> Bool {
        if let object = value.object {
            guard ["remote_host", "remote_model"].allSatisfy({ object[$0] == nil || object[$0]?.string == "" }) else { return false }
            return object.values.allSatisfy(isLocal)
        }
        if let array = value.array { return array.allSatisfy(isLocal) }
        return true
    }

    private static func validMetadataText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= 80
            && !text.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}
