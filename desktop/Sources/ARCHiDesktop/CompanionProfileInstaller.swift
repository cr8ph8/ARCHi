import Foundation

/// An explicit local setup command, using the same validated preference owner
/// as the app. The payload is user data and is never bundled with the product.
@MainActor
enum CompanionProfileInstaller {
    struct Request: Codable { let displayName: String; let document: NativePreferenceDocument }

    static func install(_ bytes: Data, profiles: CompanionProfiles) throws -> CompanionProfile {
        guard bytes.count <= NativePreferenceDocument.maximumBytes,
              let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              Set(object.keys) == ["displayName", "document"],
              let fields = object["document"] as? [String: Any] else { throw CompanionProfilesError.invalid }
        let data = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        let document = try NativePreferenceDocument.decode(data)
        guard let name = object["displayName"] as? String, document.qiMon != nil,
              document.preferences != nil else { throw CompanionProfilesError.invalid }
        let profile = CompanionProfile(id: UUID().uuidString.lowercased(), displayName: name)
        guard profile.isValid else { throw CompanionProfilesError.invalid }
        let directory = profiles.rootDirectory.appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(profile.id, isDirectory: true)
        let url = directory.appendingPathComponent("preferences.json")
        // The new UUID destination is never an existing authored profile.
        guard !FileManager.default.fileExists(atPath: directory.path) else { throw CompanionProfilesError.invalid }
        _ = try NativePreferencePersistence.write(document: document, to: url, expected: nil)
        do { try profiles.register(profile) }
        catch {
            // Registration failed: leave the validated save in place for recovery.
            // It is not selected or merged into another companion.
            throw error
        }
        return profile
    }
}
