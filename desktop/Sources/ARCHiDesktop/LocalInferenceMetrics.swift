import Foundation

/// Optional accounting from a completed local inference, not a correctness claim.
/// Ollama /api/chat documents counts as tokens and durations as nanoseconds:
/// https://docs.ollama.com/api/chat (checked 14 September 2026).
struct LocalInferenceMetrics: Equatable, Sendable {
    var inputTokens: Int? = nil
    var outputTokens: Int? = nil
    var totalNanoseconds: Int? = nil
    var loadNanoseconds: Int? = nil
    var promptEvaluationNanoseconds: Int? = nil
    var evaluationNanoseconds: Int? = nil
    var malformedFields: [String] = []
}

/// Decode optional accounting independently so even an overflowing metric cannot
/// invalidate otherwise valid message fields. All other fields keep JSONValue's
/// existing decoding and the stream's existing mandatory validation.
struct QwenChatStreamEvent {
    let value: JSONValue
    let metrics: LocalInferenceMetrics?

    private static let metricFields: Set<String> = [
        "prompt_eval_count", "eval_count", "total_duration", "load_duration",
        "prompt_eval_duration", "eval_duration"
    ]
    // Preserve exact integral accounting when values later pass through JSON's
    // Double representation. This also leaves ample headroom for per-turn sums.
    private static let maximumMetric = 9_007_199_254_740_991

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { return nil }
    }

    private struct Payload: Decodable {
        let value: JSONValue

        init(from decoder: Decoder) throws {
            let fields = try decoder.container(keyedBy: Key.self)
            var payload: [String: JSONValue] = [:]
            for key in fields.allKeys where !QwenChatStreamEvent.metricFields.contains(key.stringValue) {
                payload[key.stringValue] = try fields.decode(JSONValue.self, forKey: key)
            }
            value = .object(payload)
        }
    }

    init(data: Data) throws {
        // Ambiguous message, identity, and action fields are never safe to
        // collapse. Only optional top-level accounting keeps diagnostic-only
        // duplicate handling; the same names in nested objects stay strict.
        var keys = UniqueJSONKeys(bytes: Array(data), allowingDuplicateTopLevelKeys: Self.metricFields)
        try keys.validate()
        // JSONDecoder still validates the complete JSON and decodes every
        // non-metric field before accounting is considered.
        value = try JSONDecoder().decode(Payload.self, from: data).value
        guard value["done"] == .bool(true) else { metrics = nil; return }
        let rawValues = Self.metricValues(in: data)

        var malformed: [String] = []
        func integer(_ name: String) -> Int? {
            guard let literal = rawValues[name], !literal.elementsEqual("null".utf8) else { return nil }
            // Ollama emits decimal integer literals. Do not ask JSONDecoder for
            // a numeric conversion: Foundation can round fractional JSON numbers
            // near an integer boundary. Other numeric spellings are unavailable
            // telemetry, never a reason to reject an otherwise valid answer.
            guard !literal.isEmpty, literal.count <= 16,
                  literal.allSatisfy({ (48...57).contains($0) }),
                  let number = Int(String(decoding: literal, as: UTF8.self)),
                  number <= Self.maximumMetric else {
                malformed.append(name)
                return nil
            }
            return number
        }
        let inputTokens = integer("prompt_eval_count")
        let outputTokens = integer("eval_count")
        let totalNanoseconds = integer("total_duration")
        let loadNanoseconds = integer("load_duration")
        let promptEvaluationNanoseconds = integer("prompt_eval_duration")
        let evaluationNanoseconds = integer("eval_duration")
        if [inputTokens, outputTokens, totalNanoseconds, loadNanoseconds,
            promptEvaluationNanoseconds, evaluationNanoseconds].allSatisfy({ $0 == nil }), malformed.isEmpty {
            metrics = nil
        } else {
            metrics = LocalInferenceMetrics(inputTokens: inputTokens, outputTokens: outputTokens,
                totalNanoseconds: totalNanoseconds, loadNanoseconds: loadNanoseconds,
                promptEvaluationNanoseconds: promptEvaluationNanoseconds,
                evaluationNanoseconds: evaluationNanoseconds, malformedFields: malformed)
        }
    }

    /// Locate only top-level metric literals in JSON already checked by the
    /// decoder. Iterative container skipping avoids adding recursive parsing.
    private static func metricValues(in data: Data) -> [String: ArraySlice<UInt8>] {
        let bytes = Array(data)
        var index = 0
        var values: [String: ArraySlice<UInt8>] = [:]
        func whitespace() {
            while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
        }
        func skipString() {
            guard index < bytes.count, bytes[index] == 34 else { return }
            index += 1
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if byte == 34 { return }
                if byte == 92 { index = min(index + 1, bytes.count) }
            }
        }
        func skipValue() {
            guard index < bytes.count else { return }
            if bytes[index] == 34 { skipString(); return }
            if bytes[index] == 123 || bytes[index] == 91 {
                var depth = 1
                index += 1
                while index < bytes.count, depth > 0 {
                    if bytes[index] == 34 { skipString(); continue }
                    if bytes[index] == 123 || bytes[index] == 91 { depth += 1 }
                    if bytes[index] == 125 || bytes[index] == 93 { depth -= 1 }
                    index += 1
                }
            } else {
                while index < bytes.count, ![9, 10, 13, 32, 44, 125].contains(bytes[index]) { index += 1 }
            }
        }
        whitespace()
        guard index < bytes.count, bytes[index] == 123 else { return values }
        index += 1
        while index < bytes.count {
            whitespace()
            guard index < bytes.count, bytes[index] == 34 else { return values }
            let keyStart = index
            skipString()
            let key = try? JSONDecoder().decode(String.self, from: Data(bytes[keyStart..<index]))
            whitespace()
            guard index < bytes.count, bytes[index] == 58 else { return values }
            index += 1
            whitespace()
            let valueStart = index
            skipValue()
            if let key, metricFields.contains(key) {
                // Ambiguous duplicate accounting is diagnostic-only as well.
                values[key] = values[key] == nil ? bytes[valueStart..<index] : bytes[0..<0]
            }
            whitespace()
            guard index < bytes.count, bytes[index] == 44 else { return values }
            index += 1
        }
        return values
    }
}
