import Foundation

/// A local lexical match or an explicitly reviewed one-hop link, not a
/// probability, truth assessment or semantic entailment result. A page body is
/// authored interpretation; only a section's
/// anchor identifies the exact bytes displayed in `text` as a source quotation.
struct KnowledgeRetrievalHit: Encodable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Equatable, Sendable { case page, section }
    let id: String
    let kind: Kind
    let title: String
    let text: String
    let sourceTitle: String?
    let score: Int
    let matchedTerms: [String]
    let pageBinding: KnowledgePageBinding?
    let anchor: KnowledgeAnchor?
    let supportingAnchors: [KnowledgeAnchor]
    /// A related page has no lexical score. Preserve the reviewed declaration,
    /// including its direction and exact endpoints, for inspection and recheck.
    let viaLink: KnowledgePageLink?

    init(id: String, kind: Kind, title: String, text: String, sourceTitle: String?, score: Int,
         matchedTerms: [String], pageBinding: KnowledgePageBinding?, anchor: KnowledgeAnchor?,
         supportingAnchors: [KnowledgeAnchor], viaLink: KnowledgePageLink? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.text = text; self.sourceTitle = sourceTitle
        self.score = score; self.matchedTerms = matchedTerms; self.pageBinding = pageBinding
        self.anchor = anchor; self.supportingAnchors = supportingAnchors; self.viaLink = viaLink
    }
}

struct KnowledgeRetrievalResult: Equatable, Sendable {
    let hits: [KnowledgeRetrievalHit]
    let queryTerms: [String]
    /// Positive lexical matches before the result-count and encoded-byte caps.
    let matchingCount: Int
    let contextUTF8Bytes: Int
    let searchedSourceCount: Int
    let searchedPageCount: Int
    let excludedSourceCount: Int
    /// Counts unavailable latest identities, not superseded historical versions.
    let excludedPageCount: Int
    /// Distinct one-hop suggestions from admitted lexical pages, before caps.
    /// These are reviewed relationships, not additional lexical matches.
    var relatedCount: Int = 0
    var omittedHitCount: Int { matchingCount + relatedCount - hits.count }
    var isPartial: Bool { omittedHitCount > 0 }
}

/// Read projection of the existing kept-source and knowledge-page owners.
/// Callers supply the current library snapshot and must recheck that owner when
/// opening, selecting or sending a result. This type performs no I/O or writes.
enum KnowledgeRetrieval {
    static let version = "native-knowledge-lexical-retrieval/v2"
    static let maximumQueryUTF8Bytes = 512
    static let maximumQueryTerms = 32
    static let maximumResults = 12
    static let maximumContextUTF8Bytes = 16_384
    static let maximumIndexedSections = 2_048
    // Mirrors the library's bounds without introducing an actor-owned store.
    private static let maximumSources = 8
    private static let maximumSourceTextBytes = 400_000
    private static let maximumPageVersions = 64
    private static let maximumLinkVersions = 128

    static func search(query: String, sources: [ReadingSourceSnapshot], pages: [KnowledgePage],
                       links: [KnowledgePageLink] = [],
                       libraryIsCurrent: Bool, maximumResults: Int = KnowledgeRetrieval.maximumResults,
                       pagesOnly: Bool = false) throws -> KnowledgeRetrievalResult {
        guard libraryIsCurrent else { throw KnowledgeRetrievalError.unavailableLibrary }
        let unsupportedControls = CharacterSet.controlCharacters.subtracting(.whitespacesAndNewlines)
        guard query.utf8.count <= maximumQueryUTF8Bytes,
              !query.unicodeScalars.contains(where: unsupportedControls.contains) else {
            throw KnowledgeRetrievalError.invalidQuery
        }
        let queryTerms = DocumentReadingPlan.terms(in: query)
        guard queryTerms.count <= maximumQueryTerms else { throw KnowledgeRetrievalError.invalidQuery }
        guard (1...Self.maximumResults).contains(maximumResults) else { throw KnowledgeRetrievalError.invalidResultLimit }
        guard sources.count <= Self.maximumSources else { throw KnowledgeRetrievalError.sourceLimit }
        var sourceBytes = 0
        for source in sources {
            guard source.text.utf8.count <= maximumSourceTextBytes - sourceBytes else {
                throw KnowledgeRetrievalError.sourceLimit
            }
            sourceBytes += source.text.utf8.count
        }
        guard pages.count <= maximumPageVersions else { throw KnowledgeRetrievalError.pageLimit }
        guard links.count <= maximumLinkVersions else { throw KnowledgeRetrievalError.linkLimit }
        if queryTerms.isEmpty {
            return KnowledgeRetrievalResult(hits: [], queryTerms: [], matchingCount: 0, contextUTF8Bytes: 2,
                searchedSourceCount: 0, searchedPageCount: 0, excludedSourceCount: 0, excludedPageCount: 0)
        }

        // Reconcile identities before matching; conflicting copies cannot leave
        // a stale but apparently useful source or reviewed historical page.
        let sourceGroups = Dictionary(grouping: sources) { UUID(uuidString: $0.id) }
        var currentSources: [String: Source] = [:]
        for (identity, group) in sourceGroups {
            guard identity != nil, group.count == 1, let source = group.first,
                  source.isValid, source.binding.isValid,
                  ReadingSourceLineage.availability(of: source.binding, in: sources) == nil else { continue }
            currentSources[source.id.lowercased()] = Source(snapshot: source, binding: source.binding)
        }
        let excludedSources = sources.count - currentSources.count
        let pageGroups = Dictionary(grouping: pages) { UUID(uuidString: $0.id) }
        var currentPages: [UUID: (page: KnowledgePage, quotes: [String])] = [:]
        var excludedPages = 0
        for (identity, versions) in pageGroups {
            guard let identity, let latestRevision = versions.map(\.revision).max() else {
                excludedPages += versions.count
                continue
            }
            let latest = versions.filter { $0.revision == latestRevision }
            guard latest.count == 1, let page = latest.first,
                  page.isValid, page.state == .reviewed else {
                excludedPages += 1
                continue
            }
            let quotes = page.anchors.compactMap { quote(for: $0, sources: currentSources) }
            guard quotes.count == page.anchors.count else { excludedPages += 1; continue }
            currentPages[identity] = (page, quotes)
        }
        // A child's own passages can remain current after its linked person is
        // corrected or withdrawn. Require that exact reviewed person as well;
        // lexical matching must not bypass the library's dependency rule.
        let eligiblePages = currentPages.values.filter { item in
            guard let binding = item.page.relationship?.person else { return true }
            guard let identity = UUID(uuidString: binding.id), let person = currentPages[identity]?.page,
                  person.binding == binding, person.relationship?.kind == .person else {
                excludedPages += 1
                return false
            }
            return true
        }

        var candidates: [KnowledgeRetrievalHit] = []
        var indexedCount = 0
        for source in currentSources.values.sorted(by: { $0.snapshot.id < $1.snapshot.id }) {
            let sections = DocumentReadingPlan.index(source.snapshot.text, sourceDigest: source.binding.digest,
                sourceID: source.snapshot.id, sourceTitle: source.snapshot.title, revision: source.snapshot.revision)
            guard sections.count <= maximumIndexedSections - indexedCount else { throw KnowledgeRetrievalError.sectionLimit }
            indexedCount += sections.count
            let sourceTerms = DocumentReadingPlan.terms(in: source.snapshot.title)
            for section in sections {
                let match = match(query: queryTerms, title: section.title, text: section.text, sourceTerms: sourceTerms)
                guard match.score > 0 else { continue }
                let anchor = KnowledgeAnchor(source: source.binding, location: section.location,
                    length: section.length, quoteDigest: section.sha256)
                guard anchor.isValid else { continue }
                candidates.append(KnowledgeRetrievalHit(id: section.id, kind: .section,
                    title: section.title, text: section.text, sourceTitle: section.sourceTitle,
                    score: match.score, matchedTerms: match.terms, pageBinding: nil,
                    anchor: anchor, supportingAnchors: []))
            }
        }
        for (page, quotes) in eligiblePages {
            let supportTerms = quotes.reduce(into: Set<String>()) { $0.formUnion(DocumentReadingPlan.terms(in: $1)) }
            let match = match(query: queryTerms, title: page.title, text: page.body, supportTerms: supportTerms)
            guard match.score > 0 else { continue }
            candidates.append(KnowledgeRetrievalHit(id: "knowledge-page-" + page.binding.digest, kind: .page,
                title: page.title, text: page.body, sourceTitle: nil,
                score: match.score, matchedTerms: match.terms, pageBinding: page.binding,
                anchor: nil, supportingAnchors: page.anchors))
        }
        // Apply requested record kind before the shared result/byte caps. A
        // full page quota must not be consumed by discarded source passages.
        if pagesOnly { candidates.removeAll { $0.kind != .page } }
        candidates.sort(by: precedes)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var hits: [KnowledgeRetrievalHit] = []
        var bytes = 2 // The empty encoded context is [].
        for candidate in candidates {
            guard hits.count < maximumResults else { break }
            // Include escaping, titles, IDs, ranges, digests and other metadata.
            // A whole hit may be omitted; quoted source text is never clipped.
            let nextBytes = try encoder.encode(hits + [candidate]).count
            guard nextBytes <= maximumContextUTF8Bytes else { continue }
            hits.append(candidate)
            bytes = nextBytes
        }

        // Expand from the lexical roots that actually fit, never from a dropped
        // root or a newly discovered neighbor. Keep every lexical candidate
        // ahead of related suggestions, including candidates omitted by size.
        let roots = hits.compactMap(\.pageBinding)
        let currentLinks = KnowledgePageLink.current(links: links, pages: eligiblePages.map(\.page))
            .sorted { $0.identity < $1.identity }
        let pagesByID = Dictionary(uniqueKeysWithValues: eligiblePages.compactMap { item in
            UUID(uuidString: item.page.id).map { ($0, item.page) }
        })
        var seenPages = Set(candidates.compactMap { $0.pageBinding.flatMap { UUID(uuidString: $0.id) } })
        var related: [KnowledgeRetrievalHit] = []
        for root in roots {
            for link in currentLinks {
                let neighbor: KnowledgePageBinding
                if link.from == root { neighbor = link.to }
                else if link.to == root { neighbor = link.from }
                else { continue }
                guard let identity = UUID(uuidString: neighbor.id), let page = pagesByID[identity],
                      page.binding == neighbor, seenPages.insert(identity).inserted else { continue }
                related.append(KnowledgeRetrievalHit(id: "knowledge-page-" + page.binding.digest,
                    kind: .page, title: page.title, text: page.body, sourceTitle: nil,
                    score: 0, matchedTerms: [], pageBinding: page.binding, anchor: nil,
                    supportingAnchors: page.anchors, viaLink: link))
            }
        }
        for candidate in related {
            guard hits.count < maximumResults else { break }
            // The link's full declaration and endpoint bindings consume the
            // same encoded budget as page text and source anchors.
            let nextBytes = try encoder.encode(hits + [candidate]).count
            guard nextBytes <= maximumContextUTF8Bytes else { continue }
            hits.append(candidate)
            bytes = nextBytes
        }
        return KnowledgeRetrievalResult(hits: hits, queryTerms: queryTerms.sorted(), matchingCount: candidates.count,
            contextUTF8Bytes: bytes, searchedSourceCount: currentSources.count,
            searchedPageCount: eligiblePages.count, excludedSourceCount: excludedSources, excludedPageCount: excludedPages,
            relatedCount: related.count)
    }

    private struct Source {
        let snapshot: ReadingSourceSnapshot
        let binding: ReadingSourceBinding
    }

    private static func quote(for anchor: KnowledgeAnchor, sources: [String: Source]) -> String? {
        guard anchor.isValid, let source = sources[anchor.source.id.lowercased()],
              source.binding == anchor.source else { return nil }
        let units = Array(source.snapshot.text.utf16)
        guard anchor.location < units.count, anchor.length <= units.count - anchor.location else { return nil }
        let end = anchor.location + anchor.length
        func splitsSurrogate(at offset: Int) -> Bool {
            offset > 0 && offset < units.count
                && (0xD800...0xDBFF).contains(units[offset - 1]) && (0xDC00...0xDFFF).contains(units[offset])
        }
        guard !splitsSurrogate(at: anchor.location), !splitsSurrogate(at: end) else { return nil }
        let text = String(decoding: units[anchor.location..<end], as: UTF16.self)
        return LessonSource.digest(of: text) == anchor.quoteDigest ? text : nil
    }

    /// Same title/body/source-title weights as DocumentReadingPlan (8/2/4).
    /// A page's exact supporting quotation contributes a separate weight of 1.
    /// Distinct term presence counts once per field; repetition earns no bonus.
    private static func match(query: Set<String>, title: String, text: String,
                              sourceTerms: Set<String> = [], supportTerms: Set<String> = []) -> (score: Int, terms: [String]) {
        let titleMatches = query.intersection(DocumentReadingPlan.terms(in: title))
        let textMatches = query.intersection(DocumentReadingPlan.terms(in: text))
        let sourceMatches = query.intersection(sourceTerms)
        let supportMatches = query.intersection(supportTerms)
        return (titleMatches.count * 8 + textMatches.count * 2 + sourceMatches.count * 4 + supportMatches.count,
            titleMatches.union(textMatches).union(sourceMatches).union(supportMatches).sorted())
    }

    private static func precedes(_ left: KnowledgeRetrievalHit, _ right: KnowledgeRetrievalHit) -> Bool {
        if left.score != right.score { return left.score > right.score }
        if left.matchedTerms.count != right.matchedTerms.count { return left.matchedTerms.count > right.matchedTerms.count }
        if left.kind != right.kind { return left.kind == .page }
        let leftSource = (left.pageBinding?.id ?? left.anchor?.source.id ?? "").lowercased()
        let rightSource = (right.pageBinding?.id ?? right.anchor?.source.id ?? "").lowercased()
        if leftSource != rightSource { return leftSource < rightSource }
        if left.anchor?.location != right.anchor?.location { return (left.anchor?.location ?? 0) < (right.anchor?.location ?? 0) }
        return left.id < right.id
    }
}

enum KnowledgeRetrievalError: LocalizedError, Equatable {
    case unavailableLibrary, invalidQuery, invalidResultLimit, sourceLimit, pageLimit, linkLimit, sectionLimit
    var errorDescription: String? {
        switch self {
        case .unavailableLibrary: "The kept-source library changed or needs recovery. Reopen it before searching."
        case .invalidQuery: "Use a search of at most 512 UTF-8 bytes and 32 distinct terms, without unsupported control characters."
        case .invalidResultLimit: "Request between 1 and 12 search results."
        case .sourceLimit: "The search exceeds the kept-source limit of 8 copies and 400,000 text bytes."
        case .pageLimit: "The search exceeds the library limit of 64 knowledge-page versions."
        case .linkLimit: "The search exceeds the library limit of 128 knowledge-link versions."
        case .sectionLimit: "The sources contain more than 2,048 indexed sections. Search a smaller source set."
        }
    }
}
