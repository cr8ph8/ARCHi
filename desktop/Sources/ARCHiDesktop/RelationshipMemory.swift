import Foundation

enum RelationshipMemoryKind: String, Codable, CaseIterable, Sendable {
    case person, encounter, commitment
    var title: String { rawValue.capitalized }
}

enum RelationshipMemoryAttribution: String, Codable, Sendable {
    case userReported
    var title: String { "User reported" }
}

/// Completion records the user's report about this commitment. It is not an
/// independently observed external action, calendar event, or sent message.
enum RelationshipCommitmentStatus: String, Codable, CaseIterable, Sendable {
    case pending, completed, cancelled
    var title: String { rawValue.capitalized }
}

/// Typed metadata within the existing knowledge-page history, never a second
/// person profile. The containing page supplies the user's wording and exact
/// supporting source anchors. An unknown date remains nil.
struct RelationshipMemoryMetadata: Codable, Equatable, Sendable {
    let kind: RelationshipMemoryKind
    let person: KnowledgePageBinding?
    let occurredAt: Date?
    let dueAt: Date?
    let commitmentStatus: RelationshipCommitmentStatus?
    let attribution: RelationshipMemoryAttribution

    init(kind: RelationshipMemoryKind, person: KnowledgePageBinding? = nil,
         occurredAt: Date? = nil, dueAt: Date? = nil,
         commitmentStatus: RelationshipCommitmentStatus? = nil,
         attribution: RelationshipMemoryAttribution = .userReported) {
        self.kind = kind; self.person = person; self.occurredAt = occurredAt
        self.dueAt = dueAt; self.commitmentStatus = commitmentStatus; self.attribution = attribution
    }

    var isValid: Bool {
        guard occurredAt.map(KnowledgePage.validDate) ?? true,
              dueAt.map(KnowledgePage.validDate) ?? true else { return false }
        switch kind {
        case .person:
            return person == nil && occurredAt == nil && dueAt == nil && commitmentStatus == nil
        case .encounter:
            return person?.isValid == true && dueAt == nil && commitmentStatus == nil
        case .commitment:
            return person?.isValid == true && occurredAt == nil && commitmentStatus != nil
        }
    }

    func marking(_ status: RelationshipCommitmentStatus) -> Self {
        Self(kind: kind, person: person, occurredAt: occurredAt, dueAt: dueAt,
             commitmentStatus: status, attribution: attribution)
    }

    var modelInput: JSONValue {
        var fields: [String: JSONValue] = [
            "kind": .string(kind.rawValue), "attribution": .string(attribution.rawValue),
            "handling": .string("User-reported relationship record. Unknown details remain unknown. A reviewed record or completed status does not verify an external action or authorize contact, scheduling, profiling, or state changes.")
        ]
        if let person {
            fields["person"] = .object(["pageID": .string(person.id),
                "revision": .string(String(person.revision)), "pageSHA256": .string(person.digest)])
        }
        if kind == .encounter {
            fields["occurredAt"] = occurredAt.map { .string(Self.dateText($0)) } ?? .null
        }
        if kind == .commitment {
            fields["dueAt"] = dueAt.map { .string(Self.dateText($0)) } ?? .null
            fields["commitmentStatus"] = commitmentStatus.map { .string($0.rawValue) } ?? .null
            fields["externalActionVerification"] = .string("unknown-not-established-by-this-record")
        }
        return .object(fields)
    }

    var markdownLines: [String] {
        var lines = ["Relationship: \(kind.title) · \(attribution.title)"]
        if let person {
            lines += ["Person page: \(person.id) · revision \(person.revision)", "Person SHA-256: \(person.digest)"]
        }
        if kind == .encounter { lines.append("Encounter date: \(occurredAt.map(Self.dateText) ?? "Unknown")") }
        if kind == .commitment {
            lines += ["Due date: \(dueAt.map(Self.dateText) ?? "Unknown")",
                "Commitment status: \(commitmentStatus?.title ?? "Unknown") (user reported)",
                "External action verification: unknown; this record does not establish an external action."]
        }
        return lines
    }

    private static func dateText(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    private enum CodingKeys: String, CodingKey { case kind, person, occurredAt, dueAt, commitmentStatus, attribution }
    init(from decoder: Decoder) throws {
        let all = try decoder.container(keyedBy: AnyKey.self)
        let keys = Set(all.allKeys.map(\.stringValue))
        guard Set(["kind", "attribution"]).isSubset(of: keys),
              keys.isSubset(of: ["kind", "person", "occurredAt", "dueAt", "commitmentStatus", "attribution"]) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Unsupported relationship metadata fields."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = try values.decode(RelationshipMemoryKind.self, forKey: .kind)
        attribution = try values.decode(RelationshipMemoryAttribution.self, forKey: .attribution)
        person = values.contains(.person) ? try values.decode(KnowledgePageBinding.self, forKey: .person) : nil
        occurredAt = values.contains(.occurredAt) ? try values.decode(Date.self, forKey: .occurredAt) : nil
        dueAt = values.contains(.dueAt) ? try values.decode(Date.self, forKey: .dueAt) : nil
        commitmentStatus = values.contains(.commitmentStatus)
            ? try values.decode(RelationshipCommitmentStatus.self, forKey: .commitmentStatus) : nil
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Invalid relationship metadata or unknown person linkage."))
        }
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}
