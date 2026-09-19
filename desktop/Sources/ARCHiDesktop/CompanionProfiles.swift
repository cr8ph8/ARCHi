import Foundation

/// The registry chooses a save owner; it contains no lessons or companion state.
/// KIN's historical root stays in place. Additional companions get UUID folders.
struct CompanionProfile: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String

    static let kin = CompanionProfile(id: "kin", displayName: "KIN")
    var isValid: Bool {
        (id == Self.kin.id || UUID(uuidString: id)?.uuidString.lowercased() == id)
            && !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && displayName.utf8.count <= 160
            && !displayName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}

struct CompanionProfilesDocument: Codable, Equatable {
    static let schemaName = "archi-companion-profiles/v1"
    var schema = Self.schemaName
    var selectedProfileID = CompanionProfile.kin.id
    var profiles: [CompanionProfile] = [.kin]

    var isValid: Bool {
        schema == Self.schemaName && (1...32).contains(profiles.count)
            && profiles.allSatisfy(\.isValid)
            && Set(profiles.map(\.id)).count == profiles.count
            && profiles.contains(.kin)
            && profiles.contains(where: { $0.id == selectedProfileID })
    }
}

enum CompanionProfilesError: LocalizedError {
    case invalid, unavailable, changed, unknownProfile, missingProfile
    var errorDescription: String? {
        switch self {
        case .invalid: "The companion list is invalid. Existing companion files have been preserved."
        case .unavailable: "The companion list could not be read or saved safely."
        case .changed: "The companion list changed outside this session. Reopen ARCHi before switching."
        case .unknownProfile: "That companion is not registered in this app."
        case .missingProfile: "That companion's saved profile is missing or invalid. The current companion is unchanged."
        }
    }
}

@MainActor
final class CompanionProfiles {
    static let maximumBytes = 32 * 1024
    let rootDirectory: URL
    var registryURL: URL { rootDirectory.appendingPathComponent("companions.json") }
    /// Paid provider entitlements and reservations belong to the account, not
    /// to an individual companion. Switching must never reset this guard.
    var accountStewardURL: URL { rootDirectory.appendingPathComponent("preferences.steward.json") }
    private(set) var document: CompanionProfilesDocument
    private var baseline: Data?

    var profiles: [CompanionProfile] { document.profiles }
    var selected: CompanionProfile { profiles.first(where: { $0.id == document.selectedProfileID })! }

    init(rootDirectory: URL? = nil) throws {
        self.rootDirectory = rootDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ARCHiDesktopReview", isDirectory: true)
        if FileManager.default.fileExists(atPath: self.rootDirectory.path) {
            try Self.requireRealDirectory(self.rootDirectory)
        }
        let url = self.rootDirectory.appendingPathComponent("companions.json")
        let bytes = try Self.readIfPresent(url)
        if let bytes {
            let object = try JSONSerialization.jsonObject(with: bytes)
            guard let fields = object as? [String: Any], Set(fields.keys) == ["schema", "selectedProfileID", "profiles"],
                  let entries = fields["profiles"] as? [[String: Any]],
                  entries.allSatisfy({ Set($0.keys) == ["id", "displayName"] }) else { throw CompanionProfilesError.invalid }
            let loaded = try JSONDecoder().decode(CompanionProfilesDocument.self, from: bytes)
            guard loaded.isValid else { throw CompanionProfilesError.invalid }
            document = loaded
        } else {
            document = CompanionProfilesDocument()
        }
        baseline = bytes
    }

    func preferenceURL(for profile: CompanionProfile) throws -> URL {
        guard profiles.contains(profile) else { throw CompanionProfilesError.unknownProfile }
        if profile.id == CompanionProfile.kin.id {
            return rootDirectory.appendingPathComponent("preferences.json")
        }
        return rootDirectory.appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(profile.id, isDirectory: true).appendingPathComponent("preferences.json")
    }

    func selectedPreferenceURL() throws -> URL {
        let url = try preferenceURL(for: selected)
        if selected.id != CompanionProfile.kin.id { try validateExistingProfile(at: url) }
        return url
    }

    /// Register only after the independent profile's save has been created and
    /// validated by its existing persistence owner. No other profile is copied.
    func register(_ profile: CompanionProfile) throws {
        guard profile.isValid, profile.id != CompanionProfile.kin.id,
              !profiles.contains(where: { $0.id == profile.id }) else { throw CompanionProfilesError.invalid }
        let url = rootDirectory.appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(profile.id, isDirectory: true).appendingPathComponent("preferences.json")
        try validateExistingProfile(at: url)
        var next = document
        next.profiles.append(profile)
        try commit(next)
    }

    func select(_ id: String) throws {
        guard let profile = profiles.first(where: { $0.id == id }) else { throw CompanionProfilesError.unknownProfile }
        let url = try preferenceURL(for: profile)
        if id != CompanionProfile.kin.id { try validateExistingProfile(at: url) }
        var next = document
        next.selectedProfileID = id
        try commit(next)
    }

    private func validateExistingProfile(at url: URL) throws {
        do {
            try Self.requireRealDirectory(url.deletingLastPathComponent())
            try Self.requireRealDirectory(url.deletingLastPathComponent().deletingLastPathComponent())
            guard try Self.readIfPresent(url, maximum: NativePreferenceDocument.maximumBytes) != nil else { throw CompanionProfilesError.missingProfile }
            let loaded = try NativePreferencePersistence.read(url)
            guard loaded.document.isValid else { throw CompanionProfilesError.missingProfile }
        } catch { throw CompanionProfilesError.missingProfile }
    }

    private func commit(_ next: CompanionProfilesDocument) throws {
        guard next.isValid else { throw CompanionProfilesError.invalid }
        guard try Self.readIfPresent(registryURL) == baseline else { throw CompanionProfilesError.changed }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try Self.requireRealDirectory(rootDirectory)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let bytes = try encoder.encode(next)
        guard bytes.count <= Self.maximumBytes else { throw CompanionProfilesError.invalid }
        guard try Self.readIfPresent(registryURL) == baseline else { throw CompanionProfilesError.changed }
        try bytes.write(to: registryURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: registryURL.path)
        document = next
        baseline = bytes
    }

    private static func requireRealDirectory(_ url: URL) throws {
        let metadata = try FileManager.default.attributesOfItem(atPath: url.path)
        guard metadata[.type] as? FileAttributeType == .typeDirectory else { throw CompanionProfilesError.unavailable }
    }

    private static func readIfPresent(_ url: URL, maximum: Int = maximumBytes) throws -> Data? {
        let metadata: [FileAttributeKey: Any]
        do { metadata = try FileManager.default.attributesOfItem(atPath: url.path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain
            && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) { return nil }
        guard metadata[.type] as? FileAttributeType == .typeRegular,
              let size = metadata[.size] as? NSNumber, size.intValue <= maximum else {
            throw CompanionProfilesError.unavailable
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
}
