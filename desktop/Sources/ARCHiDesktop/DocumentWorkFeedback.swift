import Foundation

/// Captured from the completed request, before Apply clears the visible lane.
/// References contain no document, question, response or lesson text.
struct DocumentWorkLearningContext: Codable, Equatable, Sendable {
    let requestBinding: EvolutionRequestBinding
    let usedLessons: [EvolutionLessonUse]

    init(requestBinding: EvolutionRequestBinding, usedLessons: [EvolutionLessonUse] = []) {
        self.requestBinding = requestBinding
        self.usedLessons = usedLessons
    }

    var isValid: Bool {
        requestBinding.isValid && usedLessons.count <= 16
            && Set(usedLessons.map(\.lessonID)).count == usedLessons.count
            && usedLessons.allSatisfy {
                UUID(uuidString: $0.lessonID) != nil && $0.lessonRevision > 0
                    && PracticeEvolutionReference.isDigest($0.snapshotDigest)
            }
    }

    private enum CodingKeys: String, CodingKey { case requestBinding, usedLessons }

    init(from decoder: Decoder) throws {
        try DocumentWorkFeedbackKeys.require(["requestBinding", "usedLessons"], in: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        requestBinding = try values.decode(EvolutionRequestBinding.self, forKey: .requestBinding)
        usedLessons = try values.decode([EvolutionLessonUse].self, forKey: .usedLessons)
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

    static func require(_ keys: Set<String>, in decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Self.self)
        guard Set(values.allKeys.map(\.stringValue)) == keys else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Unsupported document feedback fields."))
        }
    }
}
