import Foundation

enum KnowledgePageKind: String, Codable, CaseIterable, Sendable {
    case claim, concept
    var title: String { rawValue.capitalized }
}

enum KnowledgePageState: String, Codable, CaseIterable, Sendable {
    case draft, reviewed, withdrawn
    var title: String { rawValue.capitalized }
}

/// A pointer into one exact kept source version. Source prose stays in its owner.
struct KnowledgeAnchor: Codable, Equatable, Identifiable, Sendable {
    let source: ReadingSourceBinding
    let location: Int
    let length: Int
    let quoteDigest: String

    var range: NSRange { NSRange(location: location, length: length) }
    var id: String { "\(source.id):\(source.revision):\(source.digest):\(location):\(length):\(quoteDigest)" }
    var isValid: Bool {
        source.isValid && location >= 0 && location < 100_000
            && length > 0 && length <= 100_000 - location
            && DocumentReadingTrace.isDigest(quoteDigest)
    }

    init(source: ReadingSourceBinding, location: Int, length: Int, quoteDigest: String) {
        self.source = source; self.location = location; self.length = length; self.quoteDigest = quoteDigest
    }

    private enum CodingKeys: String, CodingKey { case source, location, length, quoteDigest }
    init(from decoder: Decoder) throws {
        try KnowledgePageKeys.require(["source", "location", "length", "quoteDigest"], in: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let sourceDecoder = try values.superDecoder(forKey: .source)
        try KnowledgePageKeys.require(["id", "revision", "digest"], optional: ["provenance"], in: sourceDecoder)
        source = try ReadingSourceBinding(from: sourceDecoder)
        location = try values.decode(Int.self, forKey: .location)
        length = try values.decode(Int.self, forKey: .length)
        quoteDigest = try values.decode(String.self, forKey: .quoteDigest)
        guard isValid else { throw KnowledgePageKeys.invalid(decoder, "Invalid exact source anchor.") }
    }
}

/// Explicit user review, bound by the containing immutable page revision.
/// Reviewed means the user reviewed this note, not that its claim was proved.
struct KnowledgePageReview: Codable, Equatable, Sendable {
    let id: String
    let state: KnowledgePageState
    let recordedAt: Date
    var isValid: Bool {
        UUID(uuidString: id) != nil && state != .draft && KnowledgePage.validDate(recordedAt)
    }

    init(id: String = UUID().uuidString, state: KnowledgePageState, recordedAt: Date) {
        self.id = id; self.state = state; self.recordedAt = recordedAt
    }
    private enum CodingKeys: String, CodingKey { case id, state, recordedAt }
    init(from decoder: Decoder) throws {
        try KnowledgePageKeys.require(["id", "state", "recordedAt"], in: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        state = try values.decode(KnowledgePageState.self, forKey: .state)
        recordedAt = try values.decode(Date.self, forKey: .recordedAt)
        guard isValid else { throw KnowledgePageKeys.invalid(decoder, "Invalid page review event.") }
    }
}

/// An explicitly authored note with directed source-version dependencies.
/// Every edit, review, and withdrawal appends a revision in the existing library.
struct KnowledgePage: Codable, Equatable, Identifiable, Sendable {
    static let maximumBodyBytes = 8_192
    let id: String
    let revision: UInt64
    let title: String
    let body: String
    let kind: KnowledgePageKind
    let anchors: [KnowledgeAnchor]
    let state: KnowledgePageState
    let createdAt: Date
    let updatedAt: Date
    let review: KnowledgePageReview?
    let relationship: RelationshipMemoryMetadata?

    var isValid: Bool {
        UUID(uuidString: id) != nil && revision > 0
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.utf8.count <= 240
            && !title.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && body.utf8.count <= Self.maximumBodyBytes
            && (1...4).contains(anchors.count) && anchors.allSatisfy(\.isValid)
            && Set(anchors.map(\.id)).count == anchors.count
            && (relationship.map { $0.isValid && kind == .claim && $0.person?.id.lowercased() != id.lowercased() } ?? true)
            && Self.validDate(createdAt) && Self.validDate(updatedAt) && updatedAt >= createdAt
            && (state == .draft ? review == nil
                : review?.isValid == true && review?.state == state && review?.recordedAt == updatedAt)
    }

    init(id: String, revision: UInt64, title: String, body: String, kind: KnowledgePageKind,
         anchors: [KnowledgeAnchor], state: KnowledgePageState, createdAt: Date, updatedAt: Date,
         review: KnowledgePageReview? = nil, relationship: RelationshipMemoryMetadata? = nil) {
        self.id = id; self.revision = revision; self.title = title; self.body = body
        self.kind = kind; self.anchors = anchors; self.state = state
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.review = review
        self.relationship = relationship
    }

    static func validDate(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite && date > .distantPast && date < .distantFuture
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id.utf8.elementsEqual(rhs.id.utf8) && lhs.revision == rhs.revision
            && lhs.title.utf8.elementsEqual(rhs.title.utf8) && lhs.body.utf8.elementsEqual(rhs.body.utf8)
            && lhs.kind == rhs.kind && lhs.anchors == rhs.anchors && lhs.state == rhs.state
            && lhs.createdAt == rhs.createdAt && lhs.updatedAt == rhs.updatedAt && lhs.review == rhs.review
            && lhs.relationship == rhs.relationship
    }

    private enum CodingKeys: String, CodingKey {
        case id, revision, title, body, kind, anchors, state, createdAt, updatedAt, review, relationship
    }
    init(from decoder: Decoder) throws {
        try KnowledgePageKeys.require(["id", "revision", "title", "body", "kind", "anchors", "state", "createdAt", "updatedAt"],
            optional: ["review", "relationship"], in: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        revision = try values.decode(UInt64.self, forKey: .revision)
        title = try values.decode(String.self, forKey: .title)
        body = try values.decode(String.self, forKey: .body)
        kind = try values.decode(KnowledgePageKind.self, forKey: .kind)
        anchors = try values.decode([KnowledgeAnchor].self, forKey: .anchors)
        state = try values.decode(KnowledgePageState.self, forKey: .state)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        review = values.contains(.review) ? try values.decode(KnowledgePageReview.self, forKey: .review) : nil
        relationship = values.contains(.relationship) ? try values.decode(RelationshipMemoryMetadata.self, forKey: .relationship) : nil
        guard isValid else { throw KnowledgePageKeys.invalid(decoder, "Invalid knowledge page.") }
    }
}

private struct KnowledgePageKeys: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
    static func require(_ required: Set<String>, optional: Set<String> = [], in decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Self.self)
        let actual = Set(values.allKeys.map(\.stringValue))
        guard required.isSubset(of: actual), actual.isSubset(of: required.union(optional)) else {
            throw invalid(decoder, "Unsupported knowledge page fields.")
        }
    }
    static func invalid(_ decoder: Decoder, _ message: String) -> DecodingError {
        .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: message))
    }
}
