import Foundation

/// Captured from the completed request, before Apply clears the visible lane.
/// References contain no document, question, response or lesson text.
struct DocumentWorkLearningContext: Codable, Equatable, Sendable {
    let requestBinding: EvolutionRequestBinding
    let usedLessons: [EvolutionLessonUse]
    /// Exact supplied versions can influence an answer without being cited.
    /// Absence denotes older, incomplete provenance; [] explicitly records none.
    let suppliedLessons: [EvolutionLessonUse]?

    init(requestBinding: EvolutionRequestBinding, usedLessons: [EvolutionLessonUse] = [],
         suppliedLessons: [EvolutionLessonUse]? = nil) {
        self.requestBinding = requestBinding
        self.usedLessons = usedLessons
        self.suppliedLessons = suppliedLessons
    }

    var hasCompleteLessonProvenance: Bool { suppliedLessons != nil }
    /// Older records retain their known cited dependencies without claiming
    /// that those citations enumerate every lesson the model received.
    var dependencyLessons: [EvolutionLessonUse] { suppliedLessons ?? usedLessons }

    var isValid: Bool {
        requestBinding.isValid && Self.validReferences(usedLessons)
            && (suppliedLessons.map { supplied in
                Self.validReferences(supplied) && usedLessons.allSatisfy { supplied.contains($0) }
            } ?? true)
    }

    private static func validReferences(_ lessons: [EvolutionLessonUse]) -> Bool {
        lessons.count <= 16
            && Set(lessons.compactMap { UUID(uuidString: $0.lessonID) }).count == lessons.count
            && lessons.allSatisfy {
                UUID(uuidString: $0.lessonID) != nil && $0.lessonRevision > 0
                    && PracticeEvolutionReference.isDigest($0.snapshotDigest)
            }
    }

    private enum CodingKeys: String, CodingKey { case requestBinding, usedLessons, suppliedLessons }

    init(from decoder: Decoder) throws {
        try DocumentWorkFeedbackKeys.require(["requestBinding", "usedLessons"], optional: ["suppliedLessons"], in: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        requestBinding = try values.decode(EvolutionRequestBinding.self, forKey: .requestBinding)
        usedLessons = try values.decode([EvolutionLessonUse].self, forKey: .usedLessons)
        // A present null is not an assertion that no lessons were supplied.
        suppliedLessons = values.contains(.suppliedLessons)
            ? try values.decode([EvolutionLessonUse].self, forKey: .suppliedLessons) : nil
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Invalid document learning references."))
        }
    }
}

/// An explicit user's judgment of one completed edit, separate from mechanical
/// checks and from admitting evidence to the companion's evolution session.
struct DocumentWorkFeedback: Codable, Equatable, Identifiable, Sendable {
    enum Verdict: String, Codable, Sendable {
        case helpful, needsCorrection, withdrawn
    }

    let id: String
    let revision: UInt64
    let verdict: Verdict
    let recordedAt: Date

    init(id: String = UUID().uuidString, revision: UInt64, verdict: Verdict, recordedAt: Date = Date()) {
        self.id = id
        self.revision = revision
        self.verdict = verdict
        self.recordedAt = recordedAt
    }

    var isValid: Bool {
        UUID(uuidString: id) != nil && revision > 0
            && recordedAt.timeIntervalSinceReferenceDate.isFinite
            && recordedAt > .distantPast && recordedAt < .distantFuture
    }

    private enum CodingKeys: String, CodingKey { case id, revision, verdict, recordedAt }

    init(from decoder: Decoder) throws {
        try DocumentWorkFeedbackKeys.require(["id", "revision", "verdict", "recordedAt"], in: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        revision = try values.decode(UInt64.self, forKey: .revision)
        verdict = try values.decode(Verdict.self, forKey: .verdict)
        recordedAt = try values.decode(Date.self, forKey: .recordedAt)
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Invalid document feedback event."))
        }
    }
}

private struct DocumentWorkFeedbackKeys: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }

    static func require(_ keys: Set<String>, optional: Set<String> = [], in decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Self.self)
        let actual = Set(values.allKeys.map(\.stringValue))
        guard keys.isSubset(of: actual), actual.isSubset(of: keys.union(optional)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Unsupported document feedback fields."))
        }
    }
}
