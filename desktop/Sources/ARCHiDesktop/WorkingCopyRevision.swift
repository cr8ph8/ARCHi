import Foundation
import CryptoKit

/// A proposed edit names one occurrence in one exact app-owned working copy.
/// Neither model text nor a later selection can move this target.
struct RevisionTarget: Equatable, Sendable {
    let id: String
    let sourceDigest: String
    let selection: DocumentSelection
    let requirements: DocumentWorkRequirements

    init?(text: String, sourceRevision: UInt64, selection: DocumentSelection, id: String = UUID().uuidString, requirements: DocumentWorkRequirements = .init()) {
        guard UUID(uuidString: id) != nil, text.utf8.count <= WorkingCopyEditReceipt.maximumSourceBytes,
              selection.matches(text: text, sourceRevision: sourceRevision) else { return nil }
        self.id = id
        self.sourceDigest = WorkingCopyEditReceipt.digest(text)
        self.selection = selection
        self.requirements = requirements
    }

    func matches(text: String, sourceRevision: UInt64) -> Bool {
        text.utf8.count <= WorkingCopyEditReceipt.maximumSourceBytes
            && WorkingCopyEditReceipt.digest(text) == sourceDigest
            && selection.matches(text: text, sourceRevision: sourceRevision)
    }

    var input: JSONValue {
        .object(["id": .string(id), "sourceDigest": .string(sourceDigest), "selection": selection.input, "requirements": requirements.input])
    }
}

enum RevisionDecision: String, Sendable {
    case propose = "PROPOSE", clarify = "CLARIFY", abstain = "ABSTAIN"
}

struct PassageRevisionProposal: Equatable, Sendable {
    let target: RevisionTarget
    let decision: RevisionDecision
    let replacement: String
    let explanation: String
    let sourceIDs: [String]
    let memoryIDs: [String]
}

/// A closed text proposal contract. Passing these checks does not apply an edit
/// or establish semantic correctness; the native owner still previews and applies.
enum PassageRevisionValidator {
    static let schemaName = "native-passage-revision/v1"
    static let maximumReplacementScalars = 8_000
    static let maximumExplanationScalars = 600
    // Includes worst-case escaped surrogate pairs for the bounded replacement.
    static let maximumRawBytes = 128 * 1024
    static let maximumReferences = 32

    static func schema(target: RevisionTarget, sourceIDs: [String], memoryIDs: [String]) -> JSONValue {
        let properties: [String: JSONValue] = [
            "schema": constant(schemaName),
            "targetID": constant(target.id),
            "decision": .object(["type": .string("string"), "enum": .array([
                RevisionDecision.propose, .clarify, .abstain].map { .string($0.rawValue) })]),
            "replacement": .object(["type": .string("string"), "maxLength": .number(Double(maximumReplacementScalars))]),
            "explanation": .object(["type": .string("string"), "minLength": .number(1), "maxLength": .number(Double(maximumExplanationScalars))]),
            "sourceIDs": references(sourceIDs), "memoryIDs": references(memoryIDs)
        ]
        return .object(["type": .string("object"), "additionalProperties": .bool(false),
            "properties": .object(properties), "required": .array(properties.keys.sorted().map(JSONValue.string))])
    }

    static func parse(_ raw: String, target: RevisionTarget, sourceIDs: [String], memoryIDs: [String]) throws -> PassageRevisionProposal {
        let data = Data(raw.utf8)
        guard data.count <= maximumRawBytes else { throw HamptonProposalValidationError.oversized }
        var scanner = UniqueJSONKeys(bytes: Array(data))
        try scanner.validate()
        let value: JSONValue
        do { value = try JSONDecoder().decode(JSONValue.self, from: data) }
        catch { throw HamptonProposalValidationError.malformedJSON }
        guard let object = value.object,
              Set(object.keys) == ["schema", "targetID", "decision", "replacement", "explanation", "sourceIDs", "memoryIDs"],
              object["schema"]?.string == schemaName,
              let targetID = object["targetID"]?.string,
              let decisionText = object["decision"]?.string, let decision = RevisionDecision(rawValue: decisionText),
              let replacement = object["replacement"]?.string,
              let explanation = object["explanation"]?.string else { throw HamptonProposalValidationError.invalidShape }
        guard exact(targetID, target.id) else { throw HamptonProposalValidationError.wrongRequest }
        try validateText(decision: decision, replacement: replacement, explanation: explanation, target: target)
        return PassageRevisionProposal(target: target, decision: decision, replacement: replacement, explanation: explanation,
            sourceIDs: try identifiers(object["sourceIDs"], allowed: sourceIDs),
            memoryIDs: try identifiers(object["memoryIDs"], allowed: memoryIDs))
    }

    static func validateText(decision: RevisionDecision, replacement: String, explanation: String, target: RevisionTarget) throws {
        guard replacement.unicodeScalars.count <= maximumReplacementScalars,
              !explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              explanation.unicodeScalars.count <= maximumExplanationScalars else { throw HamptonProposalValidationError.invalidText }
        if decision == .propose {
            guard !replacement.isEmpty, !exact(replacement, target.selection.quote) else {
                throw HamptonProposalValidationError.invalidText
            }
        } else if !replacement.isEmpty { throw HamptonProposalValidationError.inconsistentDecision }
    }

    private static func identifiers(_ value: JSONValue?, allowed: [String]) throws -> [String] {
        guard let values = value?.array, values.count <= maximumReferences else { throw HamptonProposalValidationError.invalidShape }
        var output: [String] = []
        for value in values {
            guard let id = value.string else { throw HamptonProposalValidationError.invalidShape }
            guard allowed.contains(where: { exact($0, id) }) else { throw HamptonProposalValidationError.unknownReference }
            guard !output.contains(where: { exact($0, id) }) else { throw HamptonProposalValidationError.repeatedReference }
            output.append(id)
        }
        return output
    }

    private static func references(_ values: [String]) -> JSONValue {
        let allowed = values.reduce(into: [String]()) { list, value in
            if !list.contains(where: { exact($0, value) }) { list.append(value) }
        }.sorted()
        let items: JSONValue = allowed.isEmpty ? .object(["type": .string("string")])
            : .object(["type": .string("string"), "enum": .array(allowed.map(JSONValue.string))])
        return .object(["type": .string("array"), "items": items, "uniqueItems": .bool(true),
            "maxItems": .number(Double(min(maximumReferences, allowed.count)))])
    }

    private static func constant(_ value: String) -> JSONValue {
        .object(["type": .string("string"), "const": .string(value)])
    }

    private static func exact(_ first: String, _ second: String) -> Bool { first.utf8.elementsEqual(second.utf8) }
}

enum WorkingCopyRevisionError: LocalizedError, Equatable {
    case staleTarget, noProposedEdit, sourceTooLarge, exhaustedRevision
    var errorDescription: String? {
        switch self {
        case .staleTarget: "The working copy or selected passage changed. Preview a new revision."
        case .noProposedEdit: "This response does not contain a proposed passage revision."
        case .sourceTooLarge: "The revised working copy exceeds the 100 KB limit."
        case .exhaustedRevision: "This working copy cannot reserve revisions for Apply and Undo. Open a fresh copy."
        }
    }
}

/// A single app-owned undo receipt. Restoring the prior bytes is permitted only
/// while the resulting copy and its revision are still exactly current.
struct WorkingCopyEditReceipt: Equatable, Sendable {
    static let maximumSourceBytes = 100_000
    let before: String
    let afterDigest: String
    let afterRevision: UInt64
    var documentWorkID: String? = nil

    func canUndo(text: String, revision: UInt64) -> Bool {
        before.utf8.count <= Self.maximumSourceBytes && text.utf8.count <= Self.maximumSourceBytes
            && revision < UInt64.max && revision == afterRevision && Self.digest(text) == afterDigest
    }

    static func applying(proposal: PassageRevisionProposal, to text: String, sourceRevision: UInt64) throws -> String {
        guard proposal.decision == .propose else { throw WorkingCopyRevisionError.noProposedEdit }
        guard proposal.target.matches(text: text, sourceRevision: sourceRevision) else { throw WorkingCopyRevisionError.staleTarget }
        guard sourceRevision < UInt64.max - 1 else { throw WorkingCopyRevisionError.exhaustedRevision }
        try PassageRevisionValidator.validateText(decision: proposal.decision, replacement: proposal.replacement,
            explanation: proposal.explanation, target: proposal.target)
        let updated = (text as NSString).replacingCharacters(in: proposal.target.selection.range, with: proposal.replacement)
        guard updated.utf8.count <= maximumSourceBytes else { throw WorkingCopyRevisionError.sourceTooLarge }
        return updated
    }

    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
