import Foundation

enum RecordLookupField: String, CaseIterable, Sendable {
    case location, owner, deadline, color, material, status
    case destination, size, quantity, category, label, priority
}

enum RecordLookupSourceKind: Equatable, Sendable {
    case kept, sample
}

enum RecordLookupError: LocalizedError, Equatable {
    case invalidSource, header, malformedRow, recordID, field, value, duplicate, recordCount, rowLimit, unknownRecord

    var errorDescription: String? {
        switch self {
        case .invalidSource: "Choose a current kept table of at most 8 KB."
        case .header: "Start the table with record | field | value."
        case .malformedRow: "Use exactly three cells per row, separated by |. Leave out prose, blank rows and Markdown separators."
        case .recordID: "Use record IDs beginning with a letter, followed by letters, digits, - or _. Keep each ID within 32 characters."
        case .field: "Use one of the listed field names, exactly as shown."
        case .value: "Each value needs 1–96 printable ASCII characters, with no |, = or reserved model markers."
        case .duplicate: "A record has the same field more than once. Keep one unambiguous value for each record and field."
        case .recordCount: "This lookup needs exactly two distinct record IDs."
        case .rowLimit: "Use at most 12 fields per record, 24 data rows in total."
        case .unknownRecord: "Choose one of the two record IDs in this source."
        }
    }
}

/// Exact table cells only. No prose extraction, person inference or persistence.
/// Padding around cells and line endings are normalized for the optional model;
/// the original kept source bytes remain identified by sourceBinding.digest.
struct RecordLookupTable: Equatable, Sendable {
    struct Row: Equatable, Sendable {
        let recordID: String
        let field: RecordLookupField
        let value: String
    }

    static let maximumSourceBytes = 8_192
    static let example = "record | field | value\nR1 | location | north\nR2 | owner | workshop"
    let sourceBinding: ReadingSourceBinding
    let sourceTitle: String
    let sourceKind: RecordLookupSourceKind
    let recordIDs: [String]
    let rows: [Row]

    init(source: ReadingSourceSnapshot, kind: RecordLookupSourceKind = .kept) throws {
        guard source.isValid, source.binding.isValid, source.text.utf8.count <= Self.maximumSourceBytes else {
            throw RecordLookupError.invalidSource
        }
        let padding = CharacterSet(charactersIn: " \t")
        var lines = source.text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n").map { $0.trimmingCharacters(in: padding) }
        while lines.first == "" { lines.removeFirst() }
        while lines.last == "" { lines.removeLast() }
        func cells(_ line: String) -> [String] {
            line.components(separatedBy: "|").map { $0.trimmingCharacters(in: padding) }
        }
        guard let first = lines.first, cells(first) == ["record", "field", "value"] else {
            throw RecordLookupError.header
        }
        guard lines.count <= 25 else { throw RecordLookupError.rowLimit }
        var parsed: [Row] = [], identifiers: [String] = [], seen = Set<String>()
        for line in lines.dropFirst() {
            let parts = cells(line)
            guard parts.count == 3 else { throw RecordLookupError.malformedRow }
            let id = parts[0]
            guard id.range(of: "\\A[A-Za-z][A-Za-z0-9_-]{0,31}\\z", options: .regularExpression) != nil else {
                throw RecordLookupError.recordID
            }
            guard let field = RecordLookupField(rawValue: parts[1]) else { throw RecordLookupError.field }
            let value = parts[2]
            guard (1...96).contains(value.utf8.count), value.utf8.allSatisfy({ (32...126).contains($0) }),
                  !["=", "<|", "|>", "<think>", "</think>"].contains(where: value.contains) else {
                throw RecordLookupError.value
            }
            guard seen.insert(id + "|" + field.rawValue).inserted else { throw RecordLookupError.duplicate }
            if !identifiers.contains(id) { identifiers.append(id) }
            parsed.append(Row(recordID: id, field: field, value: value))
        }
        guard identifiers.count == 2 else { throw RecordLookupError.recordCount }
        sourceBinding = source.binding
        sourceTitle = source.title
        sourceKind = kind
        recordIDs = identifiers
        rows = parsed
    }

    var normalizedTable: String {
        (["record | field | value"] + rows.map { "\($0.recordID) | \($0.field.rawValue) | \($0.value)" }).joined(separator: "\n")
    }

    func query(recordID: String, field: RecordLookupField) throws -> RecordLookupQuery {
        guard recordIDs.contains(recordID) else { throw RecordLookupError.unknownRecord }
        return RecordLookupQuery(sourceBinding: sourceBinding, sourceTitle: sourceTitle, sourceKind: sourceKind,
            recordID: recordID, field: field,
            value: rows.first { $0.recordID == recordID && $0.field == field }?.value,
            input: normalizedTable + "\n\nWhich \(field.rawValue) is listed for \(recordID)?")
    }
}

struct RecordLookupQuery: Equatable, Sendable {
    static let system = "Read the supplied project records. Answer only the exact record and field asked for. Use only those records. If that field is absent for that record, answer NEED_SOURCE. Return one JSON object."
    static let schema = #"{"additionalProperties":false,"properties":{"answer":{"type":"string"}},"required":["answer"],"type":"object"}"#
    let sourceBinding: ReadingSourceBinding
    let sourceTitle: String
    let sourceKind: RecordLookupSourceKind
    let recordID: String
    let field: RecordLookupField
    /// nil is an absent exact field, never an inferred answer.
    let value: String?
    let input: String
    var answer: String { value ?? "NEED_SOURCE" }
}

/// Transient request context. Changing source bytes, version, fixture mode,
/// query or companion invalidates a completed measurement's display eligibility.
struct RecordLookupMeasurementContext: Equatable, Sendable {
    let query: RecordLookupQuery
    let companionOrigin: String?

    func matches(table: RecordLookupTable?, recordID: String, field: RecordLookupField,
                 companionOrigin: String?) -> Bool {
        guard let table, let current = try? table.query(recordID: recordID, field: field) else { return false }
        return self.companionOrigin == companionOrigin && current == query
    }
}
