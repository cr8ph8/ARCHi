import Foundation

/// A kept body choice for the existing individual. The useful-request and lesson
/// references explain the reviewed transition; they do not recreate a lesson or
/// establish that an intelligence level was earned. There is one bounded record.
struct KinGrowthRecord: Codable, Equatable, Identifiable, Sendable {
    let version: Int
    let id: UUID
    let originDigest: String
    let active: Bool
    let receipt: EvolutionUsefulReceipt

    init(id: UUID = UUID(), originDigest: String, active: Bool, receipt: EvolutionUsefulReceipt) {
        version = receipt.requestBinding == nil ? 1 : 2
        self.id = id
        self.originDigest = originDigest
        self.active = active
        self.receipt = receipt
    }

    var isValid: Bool {
        version == (receipt.requestBinding == nil ? 1 : 2)
            && PracticeEvolutionReference.isDigest(originDigest) && Self.isValidEvidence(receipt)
    }

    static func isValidEvidence(_ receipt: EvolutionUsefulReceipt) -> Bool {
        guard receipt.hasValidEvidence, let use = receipt.lessonUse else { return false }
        return UUID(uuidString: use.lessonID) != nil && use.lessonRevision > 0
            && PracticeEvolutionReference.isDigest(use.snapshotDigest)
    }

    func settingActive(_ active: Bool) -> Self {
        Self(id: id, originDigest: originDigest, active: active, receipt: receipt)
    }

    /// Uses the complete retained reference, including its request binding. This
    /// projection is never persisted and cannot recreate the referenced lesson.
    var continuityRecord: KinGrowthContinuity<EvolutionUsefulReceipt>.Record {
        .init(id: id, originDigest: originDigest, active: active, evidence: receipt)
    }

    private enum CodingKeys: String, CodingKey { case version, id, originDigest, active, receipt }
    private struct InputKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let all = try decoder.container(keyedBy: InputKey.self)
        guard Set(all.allKeys.map(\.stringValue)) == ["version", "id", "originDigest", "active", "receipt"] else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported KIN growth fields."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        id = try values.decode(UUID.self, forKey: .id)
        originDigest = try values.decode(String.self, forKey: .originDigest)
        active = try values.decode(Bool.self, forKey: .active)
        receipt = try values.decode(EvolutionUsefulReceipt.self, forKey: .receipt)
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid KIN growth record."))
        }
    }

    func encode(to encoder: Encoder) throws {
        guard isValid else {
            throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath,
                debugDescription: "Invalid KIN growth record."))
        }
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        try values.encode(id, forKey: .id)
        try values.encode(originDigest, forKey: .originDigest)
        try values.encode(active, forKey: .active)
        try values.encode(receipt, forKey: .receipt)
    }
}

/// Ephemeral and immutable. Keeping it requires this exact current proposal and
/// receipt; CompanionStore also rechecks the active identity and kept lesson.
struct KinGrowthProposal: Equatable, Identifiable, Sendable {
    let id: UUID
    let originDigest: String
    let revision: UInt64
    let receipt: EvolutionUsefulReceipt
}
