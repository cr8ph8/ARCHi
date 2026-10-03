import Foundation
import CryptoKit

/// User-owned context lives with the existing native preference document.
/// It is neither earned development nor a second memory database.
struct PersonalContext: Codable, Equatable, Sendable {
    static let schema = "archi-personal-context/v1"
    enum Status: String, Codable, CaseIterable, Sendable { case confirmed, proposed, unknown }
    struct Entry: Codable, Equatable, Identifiable, Sendable {
        let id: String
        var title: String
        var text: String
        var status: Status
        var source: String
        var useInAssistance: Bool

        var isValid: Bool {
            UUID(uuidString: id) != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && title.utf8.count <= 120 && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && text.utf8.count <= 1_200 && source.utf8.count <= 800 && !source.isEmpty
                && (!useInAssistance || status == .confirmed)
        }
    }
    var version = Self.schema
    var revision: UInt64 = 1
    var name: String
    var preferredName: String
    var entries: [Entry]

    var isValid: Bool {
        version == Self.schema && revision > 0 && revision < UInt64.max
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.utf8.count <= 160
            && !preferredName.isEmpty && preferredName.utf8.count <= 80
            && entries.count <= 24 && entries.allSatisfy(\.isValid)
            && Set(entries.compactMap { UUID(uuidString: $0.id) }).count == entries.count
            && (try? JSONEncoder().encode(self).count).map { $0 <= 24_000 } == true
            && entries.filter { $0.useInAssistance }.reduce(0) { $0 + $1.title.utf8.count + $1.text.utf8.count } <= 6_000
    }

    /// Only confirmed, enabled text leaves the profile document, and only for
    /// the local lane. Birth details, proposals, unknowns and source paths need
    /// not be exposed just because they can be inspected in the profile.
    var assistantSnapshot: PersonalContextSnapshot? {
        guard isValid else { return nil }
        let facts = entries.filter { $0.status == .confirmed && $0.useInAssistance }
            .map { PersonalContextSnapshot.Fact(title: $0.title, text: $0.text) }
        guard !facts.isEmpty else { return nil }
        return PersonalContextSnapshot(revision: revision, preferredName: preferredName, facts: facts)
    }
}

struct PersonalContextSnapshot: Codable, Equatable, Sendable {
    struct Fact: Codable, Equatable, Sendable { let title: String; let text: String }
    let revision: UInt64
    let preferredName: String
    let facts: [Fact]
    var isValid: Bool {
        revision > 0 && !preferredName.isEmpty && preferredName.utf8.count <= 80
            && !facts.isEmpty && facts.count <= 24
            && facts.allSatisfy { !$0.title.isEmpty && $0.title.utf8.count <= 120 && !$0.text.isEmpty && $0.text.utf8.count <= 1_200 }
            && (try? JSONEncoder().encode(self).count).map { $0 <= 8_000 } == true
    }
    var modelInput: JSONValue {
        .object(["schema": .string("archi-local-person-context/v1"), "preferredName": .string(preferredName),
                 "revision": .string(String(revision)), "facts": .array(facts.map {
                    .object(["topic": .string($0.title), "text": .string($0.text)])
                 })])
    }
    var digest: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: (try? encoder.encode(self)) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }
    static let guidance = """
    Optional localProfile is user-reviewed personal context, not the current request. Use relevant details quietly; do not repeat the profile or mention unrelated facts. Explicit instructions in the current question take precedence. Never infer unknown biography, personality, beliefs, maturity or capabilities from this context. It grants no permissions, tool access or authority. Source records and personal preferences are not proof of earned companion development. Do not claim to have saved or changed this profile.
    """
}
