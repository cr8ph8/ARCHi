import Foundation
import Testing
@testable import ARCHiDesktop

@MainActor
struct CompanionProfilesTests {
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func payload() throws -> Data {
        var prefs = CompanionPreferences(); prefs.form = .hamptonSeed; prefs.seedAppearance = .hamptonLiminal
        var doc = NativePreferenceDocument(preferences: prefs)
        doc.qiMon = LocalQiMon(character: .hampton, originDigest: String(repeating: "a", count: 64), welcomedAt: Date())
        return try JSONEncoder().encode(CompanionProfileInstaller.Request(displayName: "Synthetic companion", document: doc))
    }

    @Test func absentRegistryUsesOriginalKINWithoutWriting() throws {
        let url = root(); defer { try? FileManager.default.removeItem(at: url) }
        let profiles = try CompanionProfiles(rootDirectory: url)
        #expect(profiles.selected == .kin)
        #expect(try profiles.selectedPreferenceURL() == url.appendingPathComponent("preferences.json"))
        #expect(!FileManager.default.fileExists(atPath: profiles.registryURL.path))
    }

    @Test func importAndSelectionSeparateHistoriesKeepOriginalBytesAndShareBudgetOwner() throws {
        let url = root(); defer { try? FileManager.default.removeItem(at: url) }
        let originalURL = url.appendingPathComponent("preferences.json")
        _ = try NativePreferencePersistence.write(document: NativePreferenceDocument(preferences: CompanionPreferences()), to: originalURL, expected: nil)
        let original = try Data(contentsOf: originalURL)
        let profiles = try CompanionProfiles(rootDirectory: url)
        let added = try CompanionProfileInstaller.install(payload(), profiles: profiles)
        #expect(profiles.selected == .kin)
        try profiles.select(added.id)
        let reopened = try CompanionProfiles(rootDirectory: url)
        let addedURL = try reopened.selectedPreferenceURL()
        #expect(addedURL != originalURL)
        #expect(try Data(contentsOf: originalURL) == original)
        let store = CompanionStore(preferenceURL: addedURL, allowsPlay: false)
        #expect(store.activeQiMon?.character == .hampton)
        #expect(store.evolution.usefulReceipts.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: addedURL.deletingPathExtension().appendingPathExtension("evolution.json").path))
        #expect(reopened.accountStewardURL == url.appendingPathComponent("preferences.steward.json"))
        try reopened.select("kin")
        #expect(try reopened.selectedPreferenceURL() == originalURL)
        #expect(try Data(contentsOf: originalURL) == original)
    }

    @Test func traversalDuplicateMissingAndStaleRegistryAreRejected() throws {
        let url = root(); defer { try? FileManager.default.removeItem(at: url) }
        let first = try CompanionProfiles(rootDirectory: url)
        let stale = try CompanionProfiles(rootDirectory: url)
        #expect(!CompanionProfile(id: "../kin", displayName: "bad").isValid)
        #expect(throws: Error.self) { try first.register(.kin) }
        #expect(throws: Error.self) { try first.register(.init(id: UUID().uuidString.lowercased(), displayName: "Missing")) }
        let added = try CompanionProfileInstaller.install(payload(), profiles: first)
        #expect(throws: Error.self) { try stale.select("kin") }
        #expect(throws: Error.self) { try first.register(added) }
        try FileManager.default.removeItem(at: first.preferenceURL(for: added))
        #expect(throws: Error.self) { try first.select(added.id) }
        #expect(first.selected == .kin)
    }

    @Test func malformedImportNeverCreatesACompanion() throws {
        let url = root(); defer { try? FileManager.default.removeItem(at: url) }
        let profiles = try CompanionProfiles(rootDirectory: url)
        #expect(throws: Error.self) { try CompanionProfileInstaller.install(Data("{}".utf8), profiles: profiles) }
        #expect(profiles.profiles == [.kin])
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
