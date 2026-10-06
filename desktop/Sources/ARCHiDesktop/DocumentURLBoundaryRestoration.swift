import Foundation

/// Native, text-free provenance. Model output and its invocation digest remain
/// unchanged; this names the one separator restored in the review candidate.
struct DocumentURLBoundaryRestoration: Codable, Equatable, Sendable {
    static let currentAlgorithm = "single-url-period-separator/v1"
    let algorithm: String
    let targetID: String
    let sourceDigest: String
    let originalReplacementDigest: String
    let restoredReplacementDigest: String
    let restoredBoundaryCount: Int
    let separatorUTF8Length: Int

    var isValid: Bool {
        algorithm == Self.currentAlgorithm && UUID(uuidString: targetID) != nil
            && [sourceDigest, originalReplacementDigest, restoredReplacementDigest].allSatisfy { value in
                value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
            }
            && originalReplacementDigest != restoredReplacementDigest
            && restoredBoundaryCount == 1 && (1...32).contains(separatorUTF8Length)
    }
}

struct DocumentURLBoundaryCandidate: Equatable, Sendable {
    let proposal: PassageRevisionProposal
    let restoration: DocumentURLBoundaryRestoration
}

/// A bounded proposal-only repair, never an Apply or a relaxed URL check.
enum DocumentURLBoundaryPreservation {
    // Candidate discovery mirrors the literal grammar in DocumentWorkCapability.
    // Both original and restored proposals are checked by that unchanged owner;
    // this matcher cannot independently grant acceptance.
    private static let linkPattern = #"(?i)(?:[a-z][a-z0-9+.-]*://|mailto:|www\.)[^\s<>"']+"#

    static func restore(_ original: PassageRevisionProposal, text: String,
                        sourceRevision: UInt64) -> DocumentURLBoundaryCandidate? {
        guard original.decision == .propose, original.target.requirements.preserveNumbersAndLinks else { return nil }
        let before = DocumentWorkCapability.verify(proposal: original, text: text,
            sourceRevision: sourceRevision, requirements: original.target.requirements)
        guard before.checks.filter({ !$0.passed }).map(\.id) == ["links"],
              let expression = try? NSRegularExpression(pattern: linkPattern) else { return nil }
        let quote = original.target.selection.quote as NSString
        let candidate = original.replacement as NSString
        let sourceMatches = expression.matches(in: quote as String, range: NSRange(location: 0, length: quote.length))
        let candidateMatches = expression.matches(in: candidate as String, range: NSRange(location: 0, length: candidate.length))
        // V1 intentionally refuses repeated or multiple URLs, including mixed
        // already-correct/drifted occurrences whose intended mapping is unclear.
        guard sourceMatches.count == 1, candidateMatches.count == 1,
              let sourceRange = sourceMatches.first?.range, let candidateRange = candidateMatches.first?.range else { return nil }
        let sourceToken = quote.substring(with: sourceRange)
        guard Data(candidate.substring(with: candidateRange).utf8) == Data((sourceToken + ".").utf8) else { return nil }
        let separatorStart = NSMaxRange(sourceRange)
        var period = separatorStart
        while period < quote.length, quote.character(at: period) == 32 || quote.character(at: period) == 9 {
            period += 1
            guard period - separatorStart <= 32 else { return nil }
        }
        guard period > separatorStart, period < quote.length, quote.character(at: period) == 46 else { return nil }
        // Do not interpret punctuation runs, parenthetical syntax or a new word
        // as a terminal period. Only end-of-selection or whitespace can follow.
        if period + 1 < quote.length {
            let suffix = quote.substring(from: period + 1)
            guard suffix.unicodeScalars.first.map(CharacterSet.whitespacesAndNewlines.contains) == true else { return nil }
        }
        let separator = quote.substring(with: NSRange(location: separatorStart, length: period - separatorStart))
        let restored = candidate.replacingCharacters(in: NSRange(location: NSMaxRange(candidateRange) - 1, length: 0), with: separator)
        let proposal = PassageRevisionProposal(target: original.target, decision: original.decision,
            replacement: restored, explanation: original.explanation, sourceIDs: original.sourceIDs, memoryIDs: original.memoryIDs)
        let after = DocumentWorkCapability.verify(proposal: proposal, text: text,
            sourceRevision: sourceRevision, requirements: original.target.requirements)
        guard after.canApply else { return nil }
        let receipt = DocumentURLBoundaryRestoration(algorithm: DocumentURLBoundaryRestoration.currentAlgorithm,
            targetID: original.target.id, sourceDigest: original.target.sourceDigest,
            originalReplacementDigest: WorkingCopyEditReceipt.digest(original.replacement),
            restoredReplacementDigest: WorkingCopyEditReceipt.digest(restored),
            restoredBoundaryCount: 1, separatorUTF8Length: separator.utf8.count)
        guard receipt.isValid else { return nil }
        return DocumentURLBoundaryCandidate(proposal: proposal, restoration: receipt)
    }
}
