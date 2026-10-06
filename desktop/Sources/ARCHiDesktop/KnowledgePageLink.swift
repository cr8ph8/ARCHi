import Foundation
import CryptoKit

enum KnowledgePageLinkKind: String, Codable, CaseIterable, Sendable {
    case supports, contradicts, dependsOn

    var title: String {
        switch self {
        case .supports: return "Supports"
        case .contradicts: return "Contradicts"
        case .dependsOn: return "Depends on"
        }
    }
}

/// An explicitly authored, directed interpretation between exact page versions.
/// The endpoint pages own source anchors. Reviewing the link does not prove it.
struct KnowledgePageLink: Codable, Equatable, Identifiable, Sendable {
    static let maximumRationaleBytes = 2_048
    static let maximumVersions = 128

    let id: String
    let revision: UInt64
    let from: KnowledgePageBinding
    let to: KnowledgePageBinding
    let kind: KnowledgePageLinkKind
    let rationale: String
    let state: KnowledgePageState
    let createdAt: Date
    let updatedAt: Date
    let review: KnowledgePageReview?

    init(id: String, revision: UInt64, from: KnowledgePageBinding, to: KnowledgePageBinding,
         kind: KnowledgePageLinkKind, rationale: String, state: KnowledgePageState,
         createdAt: Date, updatedAt: Date, review: KnowledgePageReview? = nil) {
        self.id = id; self.revision = revision; self.from = from; self.to = to
        self.kind = kind; self.rationale = rationale; self.state = state
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.review = review
    }

    var isValid: Bool {
        UUID(uuidString: id) != nil && revision > 0 && from.isValid && to.isValid
            && from.id.lowercased() != to.id.lowercased()
            && !rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && rationale.utf8.count <= Self.maximumRationaleBytes
            && KnowledgePage.validDate(createdAt) && KnowledgePage.validDate(updatedAt)
            && updatedAt >= createdAt
            && (state == .draft ? review == nil
                : review?.isValid == true && review?.state == state && review?.recordedAt == updatedAt)
    }

    /// Includes the complete declaration and review, so stale selections cannot
    /// accidentally match an edited link that happens to keep its endpoints.
    var identity: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard isValid, let bytes = try? encoder.encode(self) else { return "invalid-link" }
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return "\(id):\(revision):\(digest)"
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id.utf8.elementsEqual(rhs.id.utf8) && lhs.revision == rhs.revision
            && sameContent(lhs, rhs) && lhs.state == rhs.state
            && lhs.createdAt == rhs.createdAt && lhs.updatedAt == rhs.updatedAt && lhs.review == rhs.review
    }

    static func sameContent(_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.from == rhs.from && lhs.to == rhs.to && lhs.kind == rhs.kind
            && lhs.rationale.utf8.elementsEqual(rhs.rationale.utf8)
    }

    /// Pure projection for retrieval. The caller supplies pages already checked
    /// against current source bytes and personal-relationship dependencies.
    /// Malformed or conflicting histories are excluded, never repaired here.
    static func current(links: [Self], pages: [KnowledgePage]) -> [Self] {
        guard links.count <= maximumVersions else { return [] }
        let pageGroups = Dictionary(grouping: pages, by: { $0.id.lowercased() })
        let eligiblePages = pageGroups.values.compactMap { group -> KnowledgePage? in
            guard group.count == 1, let page = group.first, page.isValid, page.state == .reviewed else { return nil }
            return page
        }
        let eligibleBindings = eligiblePages.map(\.binding)
        let linkGroups = Dictionary(grouping: links, by: { $0.id.lowercased() })
        let reviewIDs = links.compactMap { $0.review?.id.lowercased() }
        let reusedReviews = Set(Dictionary(grouping: reviewIDs, by: { $0 }).filter { $0.value.count > 1 }.keys)
        return linkGroups.values.compactMap { suppliedHistory -> Self? in
            let history = suppliedHistory.sorted { $0.revision < $1.revision }
            guard validHistory(history),
                  !history.contains(where: { $0.review.map { reusedReviews.contains($0.id.lowercased()) } ?? false }),
                  let head = history.last, head.state == .reviewed,
                  eligibleBindings.contains(head.from), eligibleBindings.contains(head.to) else { return nil }
            return head
        }.sorted { $0.identity < $1.identity }
    }

    /// Validates append-only review lineage independently of current availability.
    /// Stale endpoints remain retained history; they are excluded by `current`.
    static func validHistory(_ links: [Self], pages: [KnowledgePage]? = nil) -> Bool {
        guard links.count <= maximumVersions else { return false }
        var latest: [UUID: Self] = [:]
        var reviews = Set<UUID>()
        var historicalPages: [String: (KnowledgePageBinding, Date)] = [:]
        if let pages {
            for review in pages.compactMap(\.review) {
                guard let id = UUID(uuidString: review.id), reviews.insert(id).inserted else { return false }
            }
            for page in pages where page.isValid && page.state == .reviewed {
                let binding = page.binding
                historicalPages[binding.digest] = (binding, page.updatedAt)
            }
        }
        for link in links {
            guard link.isValid, let id = UUID(uuidString: link.id) else { return false }
            if pages != nil {
                for binding in [link.from, link.to] {
                    guard let historical = historicalPages[binding.digest], historical.0 == binding,
                          historical.1 <= link.updatedAt else { return false }
                }
            }
            if let review = link.review {
                guard let reviewID = UUID(uuidString: review.id), reviews.insert(reviewID).inserted else { return false }
            }
            if let previous = latest[id] {
                guard previous.id == link.id, previous.revision < UInt64.max,
                      link.revision == previous.revision + 1, previous.state != .withdrawn,
                      link.createdAt == previous.createdAt, link.updatedAt >= previous.updatedAt else { return false }
                switch link.state {
                case .draft: break
                case .reviewed:
                    guard previous.state == .draft, sameContent(previous, link) else { return false }
                case .withdrawn:
                    guard sameContent(previous, link) else { return false }
                }
            } else {
                guard link.revision == 1, link.state == .draft else { return false }
            }
            latest[id] = link
        }
        return true
    }

    private enum CodingKeys: String, CodingKey {
        case id, revision, from, to, kind, rationale, state, createdAt, updatedAt, review
    }
    init(from decoder: Decoder) throws {
        let allKeys = try decoder.container(keyedBy: AnyKey.self)
        let required: Set<String> = ["id", "revision", "from", "to", "kind", "rationale", "state", "createdAt", "updatedAt"]
        let actual = Set(allKeys.allKeys.map(\.stringValue))
        guard required.isSubset(of: actual), actual.isSubset(of: required.union(["review"])) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Unsupported knowledge link fields."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        revision = try values.decode(UInt64.self, forKey: .revision)
        from = try values.decode(KnowledgePageBinding.self, forKey: .from)
        to = try values.decode(KnowledgePageBinding.self, forKey: .to)
        kind = try values.decode(KnowledgePageLinkKind.self, forKey: .kind)
        rationale = try values.decode(String.self, forKey: .rationale)
        state = try values.decode(KnowledgePageState.self, forKey: .state)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        review = values.contains(.review) ? try values.decode(KnowledgePageReview.self, forKey: .review) : nil
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Invalid knowledge link declaration."))
        }
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}
