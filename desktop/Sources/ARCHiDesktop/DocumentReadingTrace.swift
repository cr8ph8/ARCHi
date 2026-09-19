import Foundation

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

    var isValid: Bool {
        Self.isDigest(sourceDigest) && Self.isDigest(questionDigest) && Self.isDigest(planDigest)
            && (1...6).contains(sectionIDs.count)
            && Set(sectionIDs).count == sectionIDs.count
            && sectionIDs.allSatisfy(Self.isSectionID)
            && control.isValid && control.domain == "document-reading"
            && control.contextID == sourceDigest && control.lane != .stop
    }

    fileprivate static func isDigest(_ value: String) -> Bool {
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
