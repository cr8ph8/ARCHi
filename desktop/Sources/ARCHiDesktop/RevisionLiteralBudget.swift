import Foundation

/// Optional, derived guidance can be removed only as one complete inventory.
/// The selected passage, requirements, question and history remain unchanged.
enum RevisionLiteralBudget {
    static func omittingInventory(in input: JSONValue) -> JSONValue? {
        guard var root = input.object else { return nil }
        let nested = root["context"]?.object != nil
        var context = nested ? root["context"]!.object! : root
        guard var target = context["revisionTarget"]?.object,
              target["literalPreservation"]?["status"]?.string == "complete" else { return nil }
        target["literalPreservation"] = .object(["status": .string("omitted-limit")])
        context["revisionTarget"] = .object(target)
        if nested { root["context"] = .object(context) } else { root = context }
        return .object(root)
    }

    static func fitting(_ input: JSONValue, fits: (JSONValue) throws -> Bool) throws -> JSONValue? {
        if try fits(input) { return input }
        guard let omitted = omittingInventory(in: input), try fits(omitted) else { return nil }
        return omitted
    }

    static func fittingText(_ input: String, fits: (String) throws -> Bool) throws -> String? {
        if try fits(input) { return input }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(input.utf8)),
              let omitted = omittingInventory(in: value) else { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let text = String(decoding: try encoder.encode(omitted), as: UTF8.self)
        return try fits(text) ? text : nil
    }

    /// Applies the existing Codex wire limit to the actual outgoing RPC, including
    /// its newline. Only a single turn/start text input may lose optional guidance.
    static func codexMessageData(_ message: JSONValue, maximumBytes: Int = 524_288) throws -> Data? {
        func encode(_ value: JSONValue) throws -> Data {
            var data = try JSONEncoder().encode(value); data.append(10)
            return data
        }
        let original = try encode(message)
        if original.count <= maximumBytes { return original }
        guard var root = message.object, root["method"]?.string == "turn/start",
              var parameters = root["params"]?.object,
              let inputs = parameters["input"]?.array, inputs.count == 1,
              var entry = inputs[0].object, entry["type"]?.string == "text",
              let text = entry["text"]?.string,
              let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)),
              let omitted = omittingInventory(in: value) else { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        entry["text"] = .string(String(decoding: try encoder.encode(omitted), as: UTF8.self))
        parameters["input"] = .array([.object(entry)])
        root["params"] = .object(parameters)
        let data = try encode(.object(root))
        return data.count <= maximumBytes ? data : nil
    }
}
