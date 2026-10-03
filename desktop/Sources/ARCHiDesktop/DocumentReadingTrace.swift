import Foundation

/// Text-free dependency on one explicitly retained source version.
struct ReadingSourceBinding: Codable, Equatable, Sendable {
    let id: String
    let revision: UInt64
    let digest: String
    let provenance: ReadingSourceProvenanceReceipt?
    init(id: String, revision: UInt64, digest: String, provenance: ReadingSourceProvenanceReceipt? = nil) {
        self.id = id; self.revision = revision; self.digest = digest; self.provenance = provenance
    }
    var isValid: Bool { UUID(uuidString: id) != nil && revision > 0 && DocumentReadingTrace.isDigest(digest)
        && (provenance?.isValid ?? true) }
    private enum CodingKeys: String, CodingKey { case id, revision, digest, provenance }
    init(from decoder: Decoder) throws {
        try SourceProvenanceKeys.require(["id", "revision", "digest"], optional: ["provenance"], in: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); revision = try c.decode(UInt64.self, forKey: .revision)
        digest = try c.decode(String.self, forKey: .digest)
        provenance = c.contains(.provenance) ? try c.decode(ReadingSourceProvenanceReceipt.self, forKey: .provenance) : nil
        guard isValid else { throw SourceProvenanceKeys.invalid(decoder) }
    }
    static func valid(_ values: [Self]?) -> Bool {
        guard let values else { return true }
        return (1...8).contains(values.count) && values.allSatisfy(\.isValid)
            && Set(values.map(\.id)).count == values.count
    }
}

extension ReadingSourceSnapshot {
    var binding: ReadingSourceBinding { ReadingSourceBinding(id: id, revision: revision, digest: digest, provenance: provenance?.receipt) }
}

/// Frozen reading provenance retained by Token Steward's existing task journal.
/// Only digests, section identities and the native decision are stored here;
/// source text, questions and answers remain outside the accounting journal.
struct DocumentReadingTrace: Codable, Equatable, Sendable {
    static let feedbackEvidencePrefix = "document-reading:"

    let sourceDigest: String
    let questionDigest: String
    let planDigest: String
    let sectionIDs: [String]
    let control: HamptonQ2EDecision
    let references: [ReadingSourceBinding]?
    /// Prior generated reading requests supplied as context; never source text.
    let conversationRequestIDs: [String]?

    init(sourceDigest: String, questionDigest: String, planDigest: String, sectionIDs: [String],
         control: HamptonQ2EDecision, references: [ReadingSourceBinding]? = nil,
         conversationRequestIDs: [String]? = nil) {
        self.sourceDigest = sourceDigest; self.questionDigest = questionDigest
        self.planDigest = planDigest; self.sectionIDs = sectionIDs; self.control = control
        self.references = references
        self.conversationRequestIDs = conversationRequestIDs
    }

    var isValid: Bool {
        (conversationRequestIDs.map { ids in
            (1...128).contains(ids.count) && ids.allSatisfy { UUID(uuidString: $0) != nil }
                && Set(ids.compactMap(UUID.init(uuidString:))).count == ids.count
        } ?? true) && (references?.count ?? 0) <= 4 && ReadingSourceBinding.valid(references) && Self.isDigest(sourceDigest) && Self.isDigest(questionDigest) && Self.isDigest(planDigest)
            && (1...6).contains(sectionIDs.count)
            && Set(sectionIDs).count == sectionIDs.count
            && sectionIDs.allSatisfy(Self.isSectionID)
            && control.isValid && control.domain == "document-reading"
            && control.contextID == sourceDigest && control.lane != .stop
    }

    static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }

    fileprivate static func isSectionID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128
            && !value.unicodeScalars.contains {
                CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
            }
    }
}

/// The exact returned answer is bound by digest before its Qwen lane closes.
/// A result is provenance, not a truth or skill certificate. Clarification and
/// abstention remain unknown for the reading strategy's useful-answer critic.
struct DocumentReadingResult: Codable, Equatable, Sendable {
    let answerDigest: String
    let kind: String
    let citedSectionIDs: [String]

    var isValid: Bool {
        DocumentReadingTrace.isDigest(answerDigest)
            && ["ANSWER", "CLARIFY", "ABSTAIN"].contains(kind)
            && citedSectionIDs.count <= 6
            && Set(citedSectionIDs).count == citedSectionIDs.count
            && citedSectionIDs.allSatisfy(DocumentReadingTrace.isSectionID)
    }

    func isValid(for trace: DocumentReadingTrace) -> Bool {
        isValid && trace.isValid && Set(citedSectionIDs).isSubset(of: Set(trace.sectionIDs))
    }
}
