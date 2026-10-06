import Foundation

enum ReadingSourceOrigin: String, Codable, CaseIterable, Sendable {
    case unknown, human, model, mixed
    var title: String {
        switch self { case .unknown: "Unknown"; case .human: "Human authored"
        case .model: "AI generated"; case .mixed: "Human and AI" }
    }
}

enum ReadingSourceAcquisition: String, Codable, CaseIterable, Sendable {
    case unknown, userCopy, externalPublication, derivedCopy
    var title: String {
        switch self { case .unknown: "Unknown"; case .userCopy: "Provided copy"
        case .externalPublication: "External publication"; case .derivedCopy: "Derived from kept sources" }
    }
}

/// Flat, text-free parent identity. No recursively embedded source records.
struct ReadingSourceParent: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let revision: UInt64
    let digest: String
    let provenanceDigest: String?

    init(binding: ReadingSourceBinding) {
        id = binding.id; revision = binding.revision; digest = binding.digest
        provenanceDigest = binding.provenance?.digest
    }
    var isValid: Bool {
        UUID(uuidString: id) != nil && revision > 0 && DocumentReadingTrace.isDigest(digest)
            && (provenanceDigest.map(DocumentReadingTrace.isDigest) ?? true)
    }
    func matches(_ binding: ReadingSourceBinding) -> Bool {
        id == binding.id && revision == binding.revision && digest == binding.digest
            && provenanceDigest == binding.provenance?.digest
    }
    private enum CodingKeys: String, CodingKey { case id, revision, digest, provenanceDigest }
    init(from decoder: Decoder) throws {
        try SourceProvenanceKeys.require(["id", "revision", "digest"], optional: ["provenanceDigest"], in: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); revision = try c.decode(UInt64.self, forKey: .revision)
        digest = try c.decode(String.self, forKey: .digest)
        provenanceDigest = c.contains(.provenanceDigest) ? try c.decode(String.self, forKey: .provenanceDigest) : nil
        guard isValid else { throw SourceProvenanceKeys.invalid(decoder) }
    }
}

/// Explicit local declaration, not detected authorship or factual verification.
/// Free-text attribution stays in the source owner, outside task receipts.
struct ReadingSourceProvenance: Codable, Equatable, Sendable {
    let origin: ReadingSourceOrigin
    let acquisition: ReadingSourceAcquisition
    let attribution: String
    let parents: [ReadingSourceParent]
    let declaredAt: Date
    let reviewState: String

    init(origin: ReadingSourceOrigin, acquisition: ReadingSourceAcquisition,
         attribution: String = "", parents: [ReadingSourceParent] = [], declaredAt: Date = Date()) {
        self.origin = origin; self.acquisition = acquisition; self.attribution = attribution
        self.parents = parents; self.declaredAt = declaredAt; reviewState = "user-declared-not-verified"
    }
    var isValid: Bool {
        attribution.utf8.count <= 240
            && !attribution.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && ReadingSourceProvenanceReceipt.validParents(parents)
            && KnowledgePage.validDate(declaredAt) && reviewState == "user-declared-not-verified"
            && (acquisition != .derivedCopy || !parents.isEmpty)
    }
    var receipt: ReadingSourceProvenanceReceipt {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let digest = (try? encoder.encode(self)).map { LessonSource.digest(of: String(decoding: $0, as: UTF8.self)) } ?? "unavailable"
        return .init(origin: origin, acquisition: acquisition, parents: parents, digest: digest)
    }
    private enum CodingKeys: String, CodingKey { case origin, acquisition, attribution, parents, declaredAt, reviewState }
    init(from decoder: Decoder) throws {
        try SourceProvenanceKeys.require(["origin", "acquisition", "attribution", "parents", "declaredAt", "reviewState"], in: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        origin = try c.decode(ReadingSourceOrigin.self, forKey: .origin)
        acquisition = try c.decode(ReadingSourceAcquisition.self, forKey: .acquisition)
        attribution = try c.decode(String.self, forKey: .attribution)
        parents = try c.decode([ReadingSourceParent].self, forKey: .parents)
        declaredAt = try c.decode(Date.self, forKey: .declaredAt)
        reviewState = try c.decode(String.self, forKey: .reviewState)
        guard isValid else { throw SourceProvenanceKeys.invalid(decoder) }
    }
}

struct ReadingSourceProvenanceReceipt: Codable, Equatable, Sendable {
    let origin: ReadingSourceOrigin
    let acquisition: ReadingSourceAcquisition
    let parents: [ReadingSourceParent]
    let digest: String
    var isValid: Bool {
        DocumentReadingTrace.isDigest(digest) && Self.validParents(parents)
            && (acquisition != .derivedCopy || !parents.isEmpty)
    }
    static func validParents(_ parents: [ReadingSourceParent]) -> Bool {
        parents.count <= 4 && parents.allSatisfy(\.isValid)
            && Set(parents.compactMap { UUID(uuidString: $0.id) }).count == parents.count
    }
    var modelInput: JSONValue {
        .object(["origin": .string(origin.rawValue), "acquisition": .string(acquisition.rawValue),
                 "review": .string("user-declared-not-verified"), "metadataSHA256": .string(digest),
                 "parentCount": .number(Double(parents.count))])
    }
    init(origin: ReadingSourceOrigin, acquisition: ReadingSourceAcquisition, parents: [ReadingSourceParent], digest: String) {
        self.origin = origin; self.acquisition = acquisition; self.parents = parents; self.digest = digest
    }
    private enum CodingKeys: String, CodingKey { case origin, acquisition, parents, digest }
    init(from decoder: Decoder) throws {
        try SourceProvenanceKeys.require(["origin", "acquisition", "parents", "digest"], in: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        origin = try c.decode(ReadingSourceOrigin.self, forKey: .origin)
        acquisition = try c.decode(ReadingSourceAcquisition.self, forKey: .acquisition)
        parents = try c.decode([ReadingSourceParent].self, forKey: .parents)
        digest = try c.decode(String.self, forKey: .digest)
        guard isValid else { throw SourceProvenanceKeys.invalid(decoder) }
    }
}

/// Resolve the complete bounded kept-source graph, not just the immediate quote.
enum ReadingSourceLineage {
    static func availability(of binding: ReadingSourceBinding, in sources: [ReadingSourceSnapshot]) -> String? {
        guard sources.count <= 8 else { return "The source library exceeds its supported size." }
        func visit(_ target: ReadingSourceBinding, path: Set<String>) -> String? {
            let matches = sources.filter { UUID(uuidString: $0.id) == UUID(uuidString: target.id) }
            guard target.isValid, matches.count == 1, let source = matches.first,
                  source.isValid, source.binding == target else {
                return "This source or one of its parents changed or was forgotten. Review the derivation before reuse."
            }
            let id = source.id.lowercased()
            guard !path.contains(id), path.count < 8 else { return "This source has a circular derivation." }
            for parent in source.provenance?.parents ?? [] {
                guard let current = sources.first(where: { parent.matches($0.binding) }) else {
                    return "A parent source changed or was forgotten. Review the derivation before reuse."
                }
                if let reason = visit(current.binding, path: path.union([id])) { return reason }
            }
            return nil
        }
        return visit(binding, path: [])
    }
}

struct SourceProvenanceKeys: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
    static func require(_ required: Set<String>, optional: Set<String> = [], in decoder: Decoder) throws {
        let keys = Set(try decoder.container(keyedBy: Self.self).allKeys.map(\.stringValue))
        guard required.isSubset(of: keys), keys.isSubset(of: required.union(optional)) else { throw invalid(decoder) }
    }
    static func invalid(_ decoder: Decoder) -> DecodingError {
        .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid source provenance fields."))
    }
}
