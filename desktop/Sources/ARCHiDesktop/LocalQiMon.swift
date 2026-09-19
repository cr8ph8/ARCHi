import Foundation

/// A name attached to the existing Journey origin. No second individual ID or
/// game-state owner is created by selecting a character presentation.
struct LocalQiMon: Codable, Equatable, Sendable {
    enum Character: String, Codable, Sendable { case kin, hampton }
    let character: Character
    let originDigest: String
    let welcomedAt: Date

    var displayName: String { character == .hampton ? "Liminal" : "KIN" }
    var name: String { displayName }
    var dedication: String { character == .hampton ? "Patrick’s new QiMon" : "Hampton’s first QiMon" }
    /// The identity records his beginning. PersonalQiMonPresentation resolves
    /// a later body through the matching explicitly kept Evolution record.
    var currentBody: CompanionForm { character == .hampton ? .hamptonSeed : .kinSeed }
    var stageTitle: String { character == .hampton ? "Liminal Seed" : "Core Seed" }
    var isValid: Bool {
        HostedArenaProjection.isDigest(originDigest)
            && welcomedAt.timeIntervalSince1970.isFinite
            && welcomedAt.timeIntervalSince1970 >= 0
    }
}

extension CompanionForm {
    var isKin: Bool { [.kin, .kinSpark, .kinSimple, .kinSeed].contains(self) }
    /// Keep legacy raw identifiers decodable without advertising a person's
    /// companion as a reusable starter skin.
    static var starterChoices: [Self] { allCases.filter { !$0.isKin } }
}
