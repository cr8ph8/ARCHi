import Foundation

/// An explicit assessment of one kept lesson's relationship to an exact saved
/// document-method version. The lesson and method owners retain their sources.
struct LessonMemoryInfluence: Codable, Equatable, Sendable {
    static let scope = "archi.document-method"
    static let maximumPerLesson = 16
    static let maximumRecords = 64

    let source: EvolutionLessonUse
    let procedure: DocumentProcedureUse
    let assessment: ContextualMemoryInfluence.Assessment

    static func targetID(for procedure: DocumentProcedureUse) -> String {
        "method:\(procedure.id):r\(procedure.revision):\(procedure.digest)"
    }

    var isValid: Bool {
        UUID(uuidString: source.lessonID) != nil && source.lessonRevision > 0
            && PracticeEvolutionReference.isDigest(source.snapshotDigest)
            && procedure.isValid && assessment.isValid && assessment.scope == Self.scope
            && assessment.targetID == Self.targetID(for: procedure)
    }

    static func valid(_ values: [Self]?) -> Bool {
        guard let values else { return true }
        let identities = values.map {
            "\($0.source.lessonID):\($0.source.lessonRevision):\($0.source.snapshotDigest):\(targetID(for: $0.procedure))"
        }
        return values.count <= maximumRecords && values.allSatisfy(\.isValid)
            && Set(identities).count == values.count
            && Dictionary(grouping: values, by: { $0.source.lessonID }).values.allSatisfy { $0.count <= maximumPerLesson }
    }

    init(source: EvolutionLessonUse, procedure: DocumentProcedureUse, assessment: ContextualMemoryInfluence.Assessment) {
        self.source = source
        self.procedure = procedure
        self.assessment = assessment
    }

    private enum CodingKeys: String, CodingKey { case source, procedure, assessment }
    private struct InputKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let all = try decoder.container(keyedBy: InputKey.self)
        guard Set(all.allKeys.map(\.stringValue)) == ["source", "procedure", "assessment"] else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Unsupported lesson influence fields."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        source = try values.decode(EvolutionLessonUse.self, forKey: .source)
        procedure = try values.decode(DocumentProcedureUse.self, forKey: .procedure)
        assessment = try values.decode(ContextualMemoryInfluence.Assessment.self, forKey: .assessment)
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Invalid exact-target lesson influence."))
        }
    }
}
