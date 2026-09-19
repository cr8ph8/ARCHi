import Foundation

struct DocumentWorkRequirements: Equatable, Sendable {
    var mustBeShorter = false
    var preserveNumbersAndLinks = true

    var input: JSONValue {
        .object(["mustBeShorter": .bool(mustBeShorter),
                 "preserveNumbersAndLinks": .bool(preserveNumbersAndLinks)])
    }
}

struct DocumentWorkCheck: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let passed: Bool
}

struct DocumentWorkVerification: Equatable, Sendable {
    let checks: [DocumentWorkCheck]
    let predictedDigest: String?

    var canApply: Bool {
        predictedDigest != nil && !checks.isEmpty && checks.allSatisfy(\.passed)
    }
}

/// Mechanical constraints on one selected passage. These checks do not establish
/// factual accuracy, preserved meaning, or the quality of the proposed writing.
/// Results retain only checks and a digest; no document or prompt is persisted.
enum DocumentWorkCapability {
    private static let maximumTokens = 4_096
    // Preserve decimal digits, signs, separators, exponents and percent spelling.
    // Numeric tokens can also occur inside identifiers or URLs. No value coercion
    // is used: 1,000, 1000 and 1e3 are deliberately different tokens.
    private static let numberPattern = #"[+\-−]?\p{Nd}+(?:[.,:/]\p{Nd}+)*(?:[eE][+\-−]?\p{Nd}+)?[%‰]?"#
    // Literal URL-like tokens only, without URL normalization or resolution.
    // Trailing punctuation remains part of a token when no delimiter separates
    // it. Relative links and prose link labels are outside this mechanical check.
    private static let linkPattern = #"(?i)(?:[a-z][a-z0-9+.-]*://|mailto:|www\.)[^\s<>"']+"#

    static func verify(proposal: PassageRevisionProposal, text: String, sourceRevision: UInt64,
                       requirements: DocumentWorkRequirements) -> DocumentWorkVerification {
        guard proposal.decision == .propose else {
            let title = proposal.decision == .clarify
                ? "Clarification requested; no proposed edit to apply."
                : "Revision declined; no proposed edit to apply."
            return DocumentWorkVerification(checks: [.init(id: "proposal", title: title, passed: false)],
                                            predictedDigest: nil)
        }

        let validProposal: Bool
        do {
            try PassageRevisionValidator.validateText(decision: proposal.decision, replacement: proposal.replacement,
                                                      explanation: proposal.explanation, target: proposal.target)
            validProposal = true
        } catch { validProposal = false }
        let currentSource = proposal.target.matches(text: text, sourceRevision: sourceRevision)
        let reversibleRevision = sourceRevision < UInt64.max - 1
        // The existing owner contract constructs the sole candidate and enforces
        // source identity, UTF-16 selection bounds, size, and revision capacity.
        let candidate = try? WorkingCopyEditReceipt.applying(proposal: proposal, to: text, sourceRevision: sourceRevision)
        let sizeFits = currentSource && validProposal
            && text.utf8.count - proposal.target.selection.quote.utf8.count + proposal.replacement.utf8.count
                <= WorkingCopyEditReceipt.maximumSourceBytes
        var selectionOnly = false
        if currentSource, let candidate {
            let source = text as NSString
            let range = proposal.target.selection.range
            let expected = source.substring(to: range.location) + proposal.replacement
                + source.substring(from: range.location + range.length)
            selectionOnly = candidate.utf8.elementsEqual(expected.utf8)
        }
        var checks: [DocumentWorkCheck] = [
            .init(id: "proposal", title: "A valid PROPOSE revision is present.", passed: validProposal),
            .init(id: "source", title: "The exact source and selected occurrence are still current.", passed: currentSource),
            .init(id: "revision", title: "The working copy has revision capacity for Apply and Undo.", passed: reversibleRevision),
            .init(id: "size", title: "The resulting working copy stays within 100 KB.", passed: sizeFits),
            .init(id: "selection", title: "Only the selected occurrence changes; surrounding bytes remain exact.", passed: selectionOnly)
        ]
        if requirements.mustBeShorter {
            checks.append(.init(id: "shorter", title: "The replacement uses fewer Unicode characters.",
                                passed: validProposal && proposal.replacement.count < proposal.target.selection.quote.count))
        }
        if requirements.preserveNumbersAndLinks {
            checks.append(.init(id: "numbers", title: "Numeric tokens and their counts remain exact (mechanical check).",
                                passed: validProposal && preservesTokens(proposal, pattern: numberPattern)))
            checks.append(.init(id: "links", title: "Literal URL tokens and their counts remain exact (mechanical check).",
                                passed: validProposal && preservesTokens(proposal, pattern: linkPattern)))
        }
        return DocumentWorkVerification(checks: checks, predictedDigest: candidate.map(WorkingCopyEditReceipt.digest))
    }

    private static func preservesTokens(_ proposal: PassageRevisionProposal, pattern: String) -> Bool {
        guard let before = tokens(in: proposal.target.selection.quote, pattern: pattern),
              let after = tokens(in: proposal.replacement, pattern: pattern) else { return false }
        return before == after
    }

    /// Input bytes and match count are bounded. Exceeding either bound fails the
    /// preservation check rather than treating a partial extraction as complete.
    private static func tokens(in text: String, pattern: String) -> [Data: Int]? {
        guard text.utf8.count <= WorkingCopyEditReceipt.maximumSourceBytes,
              let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let source = text as NSString
        var result: [Data: Int] = [:]
        var count = 0
        var complete = true
        expression.enumerateMatches(in: text, range: NSRange(location: 0, length: source.length)) { match, _, stop in
            guard let match, count < maximumTokens else {
                complete = false
                stop.pointee = true
                return
            }
            count += 1
            // Data keys avoid Swift String's canonical-equivalence comparison.
            let token = Data(source.substring(with: match.range).utf8)
            result[token, default: 0] += 1
        }
        return complete ? result : nil
    }
}
