import Foundation

struct HamptonReasonProposal: Equatable, Sendable {
    enum Kind: String, Sendable { case answer = "ANSWER", clarify = "CLARIFY", abstain = "ABSTAIN" }
    let kind: Kind
    let answer: String
    let uncertainty: String
    let sourceIDs: [String]
    let memoryIDs: [String]
}

enum HamptonProposalValidationError: Error, Equatable {
    case oversized, malformedJSON, duplicateKey, wrongRole, wrongRequest
    case invalidShape, invalidText, unknownReference, repeatedReference, inconsistentDecision
}

/// Validates structure and exact reference membership only. A valid proposal is
/// neither semantic truth nor permission to change memory, policy, or actions.
enum HamptonProposalValidator {
    static let maximumRawBytes = 16 * 1024

    static func schema(for role: LocalModelRole, requestID: String, sourceIDs: [String] = [],
                       memoryIDs: [String] = [], candidateIDs: [String] = []) -> JSONValue {
        var properties: [String: JSONValue] = [
            "schema": constant(schemaName(role)), "requestID": constant(requestID)
        ]
        switch role {
        case .memorySelection:
            properties["candidateIDs"] = references(candidateIDs, maximum: 4)
        case .memoryReminder:
            // Keep generation constraints in one closed object: some local
            // schema lowerers omit parent requirements around partial branches.
            // parseReminder independently enforces NONE/SELECT cardinality.
            properties["decision"] = memoryIDs.isEmpty ? constant("NONE") : stringEnum(["NONE", "SELECT"])
            properties["memoryIDs"] = references(memoryIDs, maximum: 3)
        case .reasoning:
            properties["kind"] = stringEnum(["ANSWER", "CLARIFY", "ABSTAIN"])
            properties["answer"] = .object(["type": .string("string"), "minLength": .number(1), "maxLength": .number(1200)])
            properties["uncertainty"] = .object(["type": .string("string"), "maxLength": .number(320)])
            properties["sourceIDs"] = references(sourceIDs, maximum: 3)
            properties["memoryIDs"] = references(memoryIDs, maximum: 3)
        }
        return .object([
            "type": .string("object"), "additionalProperties": .bool(false),
            "properties": .object(properties),
            "required": .array(properties.keys.sorted().map(JSONValue.string))
        ])
    }

    static func parseReason(_ result: LocalRoleResult, request: LocalRoleRequest,
                            allowedSourceIDs: Set<String>, allowedMemoryIDs: Set<String>) throws -> HamptonReasonProposal {
        let object = try payload(result, request: request, role: .reasoning,
            keys: ["schema", "requestID", "kind", "answer", "uncertainty", "sourceIDs", "memoryIDs"])
        guard let rawKind = object["kind"]?.string, let kind = HamptonReasonProposal.Kind(rawValue: rawKind),
              let answer = object["answer"]?.string, let uncertainty = object["uncertainty"]?.string else {
            throw HamptonProposalValidationError.invalidShape
        }
        // JSON Schema lengths are Unicode code-point lengths, not grapheme counts.
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              answer.unicodeScalars.count <= 1200, uncertainty.unicodeScalars.count <= 320 else {
            throw HamptonProposalValidationError.invalidText
        }
        return HamptonReasonProposal(kind: kind, answer: answer, uncertainty: uncertainty,
            sourceIDs: try identifiers(object["sourceIDs"], allowed: allowedSourceIDs, maximum: 3),
            memoryIDs: try identifiers(object["memoryIDs"], allowed: allowedMemoryIDs, maximum: 3))
    }

    static func parseSelection(_ result: LocalRoleResult, request: LocalRoleRequest,
                               allowedCandidateIDs: Set<String>) throws -> [String] {
        let object = try payload(result, request: request, role: .memorySelection,
            keys: ["schema", "requestID", "candidateIDs"])
        return try identifiers(object["candidateIDs"], allowed: allowedCandidateIDs, maximum: 4)
    }

    static func parseReminder(_ result: LocalRoleResult, request: LocalRoleRequest,
                              allowedMemoryIDs: Set<String>) throws -> [String] {
        let object = try payload(result, request: request, role: .memoryReminder,
            keys: ["schema", "requestID", "decision", "memoryIDs"])
        guard let decision = object["decision"]?.string, ["NONE", "SELECT"].contains(decision) else {
            throw HamptonProposalValidationError.invalidShape
        }
        let selected = try identifiers(object["memoryIDs"], allowed: allowedMemoryIDs, maximum: 3)
        guard (decision == "NONE" && selected.isEmpty) || (decision == "SELECT" && !selected.isEmpty) else {
            throw HamptonProposalValidationError.inconsistentDecision
        }
        return selected
    }

    private static func payload(_ result: LocalRoleResult, request: LocalRoleRequest, role: LocalModelRole,
                                keys: Set<String>) throws -> [String: JSONValue] {
        guard request.role == role, result.role == role else { throw HamptonProposalValidationError.wrongRole }
        guard exact(result.requestID, request.id) else { throw HamptonProposalValidationError.wrongRequest }
        let data = Data(result.text.utf8)
        guard data.count <= maximumRawBytes else { throw HamptonProposalValidationError.oversized }
        // Foundation's normal dictionary decoding can silently keep one duplicate
        // value. Scan every object's decoded keys before creating any dictionary.
        var scanner = UniqueJSONKeys(bytes: Array(data))
        try scanner.validate()
        let value: JSONValue
        do { value = try JSONDecoder().decode(JSONValue.self, from: data) }
        catch { throw HamptonProposalValidationError.malformedJSON }
        guard let object = value.object, Set(object.keys) == keys,
              let schema = object["schema"]?.string, schema == schemaName(role),
              let requestID = object["requestID"]?.string else { throw HamptonProposalValidationError.invalidShape }
        guard exact(requestID, request.id) else { throw HamptonProposalValidationError.wrongRequest }
        return object
    }

    private static func identifiers(_ value: JSONValue?, allowed: Set<String>, maximum: Int) throws -> [String] {
        guard let entries = value?.array, entries.count <= maximum else { throw HamptonProposalValidationError.invalidShape }
        var ids: [String] = []
        for entry in entries {
            guard let id = entry.string else { throw HamptonProposalValidationError.invalidShape }
            guard allowed.contains(where: { exact($0, id) }) else { throw HamptonProposalValidationError.unknownReference }
            guard !ids.contains(where: { exact($0, id) }) else { throw HamptonProposalValidationError.repeatedReference }
            ids.append(id)
        }
        return ids
    }

    private static func exact(_ first: String, _ second: String) -> Bool { first.utf8.elementsEqual(second.utf8) }

    private static func schemaName(_ role: LocalModelRole) -> String {
        switch role {
        case .memorySelection: "archi-session-selection/v1"
        case .memoryReminder: "archi-session-reminder/v1"
        case .reasoning: "archi-reason-proposal/v1"
        }
    }

    private static func constant(_ value: String) -> JSONValue {
        .object(["type": .string("string"), "const": .string(value)])
    }

    private static func stringEnum(_ values: [String]) -> JSONValue {
        .object(["type": .string("string"), "enum": .array(values.map(JSONValue.string))])
    }

    private static func references(_ values: [String], maximum: Int) -> JSONValue {
        let allowed = Array(Set(values)).sorted()
        let items: JSONValue = allowed.isEmpty ? .object(["type": .string("string")]) : stringEnum(allowed)
        return .object(["type": .string("array"), "items": items, "uniqueItems": .bool(true),
                        "maxItems": .number(Double(allowed.isEmpty ? 0 : maximum))])
    }
}

/// Bounded lexical walk; JSONDecoder remains responsible for complete value
/// syntax. String keys are decoded so escaped duplicates cannot bypass checks.
struct UniqueJSONKeys {
    let bytes: [UInt8]
    // Optional telemetry may deliberately treat duplicate root fields as
    // unavailable accounting. Identity, content and nested fields remain strict.
    private let allowingDuplicateTopLevelKeys: Set<String>
    private var index = 0

    init(bytes: [UInt8], allowingDuplicateTopLevelKeys: Set<String> = []) {
        self.bytes = bytes
        self.allowingDuplicateTopLevelKeys = allowingDuplicateTopLevelKeys
    }

    mutating func validate() throws {
        try value(depth: 0)
        whitespace()
        guard index == bytes.count else { throw HamptonProposalValidationError.malformedJSON }
    }

    private mutating func value(depth: Int) throws {
        whitespace()
        guard depth <= 32, index < bytes.count else { throw HamptonProposalValidationError.malformedJSON }
        switch bytes[index] {
        case 123: // {
            index += 1
            whitespace()
            if take(125) { return }
            var keys = Set<String>()
            while true {
                whitespace()
                let key = try string()
                guard keys.insert(key).inserted || (depth == 0 && allowingDuplicateTopLevelKeys.contains(key)) else {
                    throw HamptonProposalValidationError.duplicateKey
                }
                whitespace()
                guard take(58) else { throw HamptonProposalValidationError.malformedJSON }
                try value(depth: depth + 1)
                whitespace()
                if take(125) { return }
                guard take(44) else { throw HamptonProposalValidationError.malformedJSON }
            }
        case 91: // [
            index += 1
            whitespace()
            if take(93) { return }
            while true {
                try value(depth: depth + 1)
                whitespace()
                if take(93) { return }
                guard take(44) else { throw HamptonProposalValidationError.malformedJSON }
            }
        case 34:
            _ = try string()
        default:
            let start = index
            while index < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
            guard index > start else { throw HamptonProposalValidationError.malformedJSON }
        }
    }

    private mutating func string() throws -> String {
        let start = index
        guard take(34) else { throw HamptonProposalValidationError.malformedJSON }
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 34 {
                do { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) }
                catch { throw HamptonProposalValidationError.malformedJSON }
            }
            if byte == 92 {
                guard index < bytes.count else { throw HamptonProposalValidationError.malformedJSON }
                index += 1
            } else if byte < 32 { throw HamptonProposalValidationError.malformedJSON }
        }
        throw HamptonProposalValidationError.malformedJSON
    }

    private mutating func whitespace() {
        while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }

    private mutating func take(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }
}
