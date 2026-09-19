import Foundation
import CryptoKit

/// An exchangeable local design recipe. Every field is data, not a permission,
/// model instruction, owner record, issued edition, or executable extension.
struct CompanionItemPackage: Codable, Equatable, Sendable, Identifiable {
    static let currentSchema = "archi-item-design/v1"
    static let maximumBytes = 4_096
    static let maximumLibraryCount = 8

    enum License: String, Codable, CaseIterable, Identifiable, Sendable {
        case mit = "MIT", cc0 = "CC0", ccBy4 = "CC-BY-4.0"
        var id: String { rawValue }
    }

    enum Palette: String, Codable, CaseIterable, Identifiable, Sendable {
        case lilac, mint, gold, rose, ice
        var id: String { rawValue }
    }

    enum Crown: String, Codable, CaseIterable, Identifiable, Sendable {
        case pearl, star, leaf
        var id: String { rawValue }
    }

    enum Action: String, Codable, CaseIterable, Identifiable, Sendable {
        case decoration, pointSelection
        var id: String { rawValue }
    }

    var schema: String
    var title: String
    var creator: String
    var summary: String
    var revision: Int
    var license: License
    var palette: Palette
    var crown: Crown
    var action: Action
    var defaultGesture: FocusGestureConfiguration

    init(title: String, creator: String, summary: String, revision: Int = 1,
         license: License = .mit, palette: Palette = .lilac, crown: Crown = .pearl,
         action: Action = .pointSelection, defaultGesture: FocusGestureConfiguration = .init(),
         schema: String = Self.currentSchema) {
        self.schema = schema
        self.title = title
        self.creator = creator
        self.summary = summary
        self.revision = revision
        self.license = license
        self.palette = palette
        self.crown = crown
        self.action = action
        self.defaultGesture = defaultGesture
    }

    static let creatorDefault = Self(title: "My Focus Staff", creator: "Local creator",
        summary: "A personal staff recipe for my companion.", palette: .mint)

    /// A local value check only. This does not authenticate attribution or grant
    /// registration, ownership, permissions, or effects, and is never serialized.
    var review: CompanionItemReview {
        let supportedSchema = schema == Self.currentSchema
        let supportedRevision = (1...999).contains(revision)
        return CompanionItemReview(checks: [
            .init(field: .schema, outcome: supportedSchema ? .pass : .fail,
                  message: supportedSchema ? "Supported recipe version." : "Use a recipe version supported by this app."),
            .init(field: .revision, outcome: supportedRevision ? .pass : .fail,
                  message: supportedRevision ? "Supported design revision." : "Choose a design revision from 1 to 999."),
            Self.reviewLabel(title, field: .title, label: "item name", maximumUTF16: 24, allowsEmpty: false),
            Self.reviewLabel(creator, field: .creator, label: "creator name", maximumUTF16: 48, allowsEmpty: false),
            Self.reviewLabel(summary, field: .summary, label: "description", maximumUTF16: 160, allowsEmpty: true),
        ])
    }

    var isValid: Bool { review.isValid }

    /// Fixed field order and UTF-8 length prefixes keep identity independent of
    /// JSON key ordering/whitespace and unambiguous across Unicode and delimiters.
    /// No claimed id/digest is decoded from a package. Invalid drafts also have a
    /// deterministic id, but validation is required before admission/registration.
    var id: String {
        let fields = [schema, title, creator, summary, String(revision), license.rawValue,
                      palette.rawValue, crown.rawValue, action.rawValue,
                      defaultGesture.pace.rawValue, defaultGesture.sparkle.rawValue,
                      defaultGesture.hold.rawValue]
        var data = Data("archi-item-design-canonical/v1\n".utf8)
        for field in fields {
            let bytes = Data(field.utf8)
            data.append(Data("\(bytes.count):".utf8))
            data.append(bytes)
            data.append(10)
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func isValidLibrary(_ packages: [Self]) -> Bool {
        packages.count <= maximumLibraryCount && packages.allSatisfy(\.isValid)
            && Set(packages.map(\.id)).count == packages.count
    }

    func encoded() throws -> Data {
        guard isValid else { throw CompanionItemPackageError.invalidPackage }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw CompanionItemPackageError.tooLarge }
        return data
    }

    /// External imports must use this entry point. The existing native profile
    /// envelope also scans its complete JSON before decoding embedded packages.
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw CompanionItemPackageError.tooLarge }
        do {
            var keys = UniqueJSONKeys(bytes: Array(data))
            try keys.validate()
            return try JSONDecoder().decode(Self.self, from: data)
        } catch let error as CompanionItemPackageError {
            throw error
        } catch {
            throw CompanionItemPackageError.invalidPackage
        }
    }

    private static func reviewLabel(_ text: String, field: CompanionItemReview.Field,
                                    label: String, maximumUTF16: Int, allowsEmpty: Bool) -> CompanionItemReview.Check {
        guard text.utf16.count <= maximumUTF16 else {
            return .init(field: field, outcome: .fail, message: "Shorten the \(label) to fit the displayed limit. Some symbols count as more than one character.")
        }
        guard !text.unicodeScalars.contains(where: { scalar in
            scalar.value < 0x20 || (0x7f...0x9f).contains(scalar.value)
                || scalar.value == 0x2028 || scalar.value == 0x2029
        }) else {
            return .init(field: field, outcome: .fail, message: "Remove line breaks or control characters from the \(label).")
        }
        guard allowsEmpty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .init(field: field, outcome: .missing, message: "Enter \(field == .title ? "an item name" : "a creator name").")
        }
        return .init(field: field, outcome: .pass, message: "The \(label) fits the supported limits.")
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schema, title, creator, summary, revision, license, palette, crown, action, defaultGesture
    }

    private struct InputKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: InputKey.self)
        guard Set(fields.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.rawValue)) else {
            throw CompanionItemPackageError.invalidPackage
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schema = try values.decode(String.self, forKey: .schema)
        title = try values.decode(String.self, forKey: .title)
        creator = try values.decode(String.self, forKey: .creator)
        summary = try values.decode(String.self, forKey: .summary)
        revision = try values.decode(Int.self, forKey: .revision)
        license = try values.decode(License.self, forKey: .license)
        palette = try values.decode(Palette.self, forKey: .palette)
        crown = try values.decode(Crown.self, forKey: .crown)
        action = try values.decode(Action.self, forKey: .action)
        defaultGesture = try values.decode(FocusGestureConfiguration.self, forKey: .defaultGesture)
        guard schema == Self.currentSchema else { throw CompanionItemPackageError.unsupportedSchema }
        guard isValid else { throw CompanionItemPackageError.invalidPackage }
    }

    func encode(to encoder: Encoder) throws {
        guard isValid else { throw CompanionItemPackageError.invalidPackage }
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schema, forKey: .schema)
        try values.encode(title, forKey: .title)
        try values.encode(creator, forKey: .creator)
        try values.encode(summary, forKey: .summary)
        try values.encode(revision, forKey: .revision)
        try values.encode(license, forKey: .license)
        try values.encode(palette, forKey: .palette)
        try values.encode(crown, forKey: .crown)
        try values.encode(action, forKey: .action)
        try values.encode(defaultGesture, forKey: .defaultGesture)
    }
}

/// Derived review information for the native editor and decoded recipe preview.
/// The strict decoder, catalog, and profile owner retain their existing roles.
struct CompanionItemReview: Equatable, Sendable {
    enum Field: String, Sendable {
        case schema, revision, title, creator, summary
    }

    enum Outcome: Equatable, Sendable {
        case pass, missing, fail
    }

    struct Check: Equatable, Sendable, Identifiable {
        let field: Field
        let outcome: Outcome
        let message: String
        var id: Field { field }
    }

    let checks: [Check]
    var issues: [Check] { checks.filter { $0.outcome != .pass } }
    var isValid: Bool { checks.allSatisfy { $0.outcome == .pass } }
    var correctionMessage: String { issues.map(\.message).joined(separator: " ") }
}

enum CompanionItemPackageError: Error, LocalizedError, Equatable {
    case invalidPackage, unsupportedSchema, tooLarge

    var errorDescription: String? {
        switch self {
        case .invalidPackage: "This item recipe contains invalid or unsupported data."
        case .unsupportedSchema: "This item recipe version is not supported."
        case .tooLarge: "Item recipe files must be no larger than 4 KB."
        }
    }
}

/// Display information from an exact local source-registry match. This is not
/// ownership, an issuer signature, a production server decision, or a capability.
enum ItemRegistrationDecision: Equatable, Sendable {
    case registered, unregistered

    var isRegistered: Bool { self == .registered }
    var label: String { isRegistered ? "Registered · local Alpha" : "Unregistered design" }
    var registryVersion: String? { isRegistered ? CompanionItemCatalog.registryVersion : nil }
    var ruleset: String? { isRegistered ? CompanionItemCatalog.ruleset : nil }
}

enum CompanionItemCatalog {
    static let registryVersion = "archi-local-alpha-registry/v1"
    static let ruleset = "archi-local-item-actions/v1"
    static let allowedCanonicalEffects: [String] = []

    static let designs: [CompanionItemPackage] = [
        .init(title: "Focus Staff", creator: "Hampton",
              summary: "A pearl of lilac light. Point gently to a selected passage.",
              palette: .lilac, crown: .pearl, action: .pointSelection),
        .init(title: "Starlight Staff", creator: "Hampton",
              summary: "A warm golden star to wear alongside your companion. Decorative only.",
              palette: .gold, crown: .star, action: .decoration,
              defaultGesture: .init(pace: .gentle, sparkle: .soft, hold: .brief)),
        .init(title: "Grove Staff", creator: "Hampton",
              summary: "A mint leaf and an unhurried point for the passage you choose.",
              palette: .mint, crown: .leaf, action: .pointSelection,
              defaultGesture: .init(pace: .unhurried, sparkle: .none, hold: .lingering)),
    ]

    /// Creator text is a declaration, never the registry key. Every field must
    /// match a bundled approved design; edited or imported claims cannot register.
    static func registeredDesign(for package: CompanionItemPackage) -> ItemRegistrationDecision {
        guard package.isValid, designs.contains(where: { $0.isValid && $0.id == package.id && $0 == package }) else {
            return .unregistered
        }
        return .registered
    }

    /// Arena is disabled, and this registry authorizes no canonical effects.
    /// Local pointing is a desktop utility, not a battle-stat modifier. Even an
    /// exact registered recipe cannot grant a canonical Arena effect this release.
    static func canonicalArenaEffects(for package: CompanionItemPackage) -> [String] {
        guard registeredDesign(for: package).isRegistered else { return [] }
        return allowedCanonicalEffects
    }
}
