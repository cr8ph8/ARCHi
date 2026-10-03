import Foundation

/// An exact-word match for inspection, not a judgment that a method fits the
/// task or will work. Identity follows the full saved method version.
struct DocumentMethodSearchHit: Equatable, Sendable, Identifiable {
    let procedure: DocumentProcedure
    let matchedTerms: [String]
    let score: Int

    var id: String {
        let binding = procedure.binding
        return "\(binding.id).\(binding.revision).\(binding.digest)"
    }
}

struct DocumentMethodSearchResult: Equatable, Sendable {
    let hits: [DocumentMethodSearchHit]
    let queryTerms: [String]
    /// Positive lexical matches before the five-result cap.
    let matchingCount: Int
    var omittedCount: Int { matchingCount - hits.count }
}

/// Pure projection over methods already admitted by the native owner. The
/// caller supplies current dependency/requirement eligibility and its existing
/// outcome/resource order, then rechecks eligibility before preparing a method.
/// Searching performs no selection, request, persistence or learning update.
enum DocumentMethodSearch {
    static let maximumQueryUTF8Bytes = 512
    static let maximumQueryTerms = 32
    static let maximumMethods = 64
    static let maximumResults = 5

    // Generic revision instructions are shared by unrelated methods. Removing
    // them prevents boilerplate alone from manufacturing a task-specific match.
    private static let boilerplate: Set<String> = [
        "please", "revise", "revision", "revisions", "rewrite", "edit", "editing",
        "passage", "passages", "text", "make", "selected", "selection", "keep",
        "exact", "preserve", "preserving", "meaning", "while", "without",
        "my", "me", "help", "want", "would", "could", "can", "should", "must",
        "need", "do", "not", "following", "follow", "stated", "requirements",
        "propose", "version", "review", "one", "its", "original", "method"
    ]

    static func search(query: String, orderedEligibleMethods: [DocumentProcedure]) throws -> DocumentMethodSearchResult {
        let unsupportedControls = CharacterSet.controlCharacters.subtracting(.whitespacesAndNewlines)
        guard query.utf8.count <= maximumQueryUTF8Bytes,
              !query.unicodeScalars.contains(where: unsupportedControls.contains) else {
            throw DocumentMethodSearchError.invalidQuery
        }
        let rawTerms = DocumentReadingPlan.terms(in: query)
        guard rawTerms.count <= maximumQueryTerms else { throw DocumentMethodSearchError.invalidQuery }
        guard orderedEligibleMethods.count <= maximumMethods else { throw DocumentMethodSearchError.methodLimit }

        // Reject a partial or ambiguous supplied scope before matching, even
        // when the query is empty. UUID case cannot disguise a duplicate.
        var identities = Set<UUID>()
        for method in orderedEligibleMethods {
            guard method.isValid, method.binding.isValid, !method.withdrawn,
                  let identity = UUID(uuidString: method.id) else {
                throw DocumentMethodSearchError.invalidMethod
            }
            guard identities.insert(identity).inserted else { throw DocumentMethodSearchError.duplicateMethod }
        }

        let queryTerms = rawTerms.subtracting(boilerplate)
        guard !queryTerms.isEmpty else {
            return DocumentMethodSearchResult(hits: [], queryTerms: [], matchingCount: 0)
        }

        let candidates = orderedEligibleMethods.enumerated().compactMap { index, method -> (index: Int, hit: DocumentMethodSearchHit)? in
            let titleMatches = queryTerms.intersection(DocumentReadingPlan.terms(in: method.title))
            let instructionMatches = queryTerms.intersection(DocumentReadingPlan.terms(in: method.instruction))
            let score = titleMatches.count * 2 + instructionMatches.count
            guard score > 0 else { return nil }
            return (index, DocumentMethodSearchHit(procedure: method,
                matchedTerms: titleMatches.union(instructionMatches).sorted(), score: score))
        }.sorted { lhs, rhs in
            if lhs.hit.score != rhs.hit.score { return lhs.hit.score > rhs.hit.score }
            return lhs.index < rhs.index
        }
        return DocumentMethodSearchResult(hits: Array(candidates.prefix(maximumResults).map(\.hit)),
            queryTerms: queryTerms.sorted(), matchingCount: candidates.count)
    }
}

enum DocumentMethodSearchError: LocalizedError, Equatable {
    case invalidQuery, methodLimit, invalidMethod, duplicateMethod

    var errorDescription: String? {
        switch self {
        case .invalidQuery: "Use a task description of at most 512 UTF-8 bytes and 32 distinct terms, without unsupported control characters."
        case .methodLimit: "The method search exceeds the library limit of 64 methods."
        case .invalidMethod: "A supplied method is invalid or withdrawn. Reopen the current method library before searching."
        case .duplicateMethod: "The supplied methods contain a repeated identity. Reopen the current method library before searching."
        }
    }
}
