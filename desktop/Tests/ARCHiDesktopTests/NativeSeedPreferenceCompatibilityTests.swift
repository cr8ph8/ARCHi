import Foundation
import XCTest
@testable import ARCHiDesktop

final class NativeSeedPreferenceCompatibilityTests: XCTestCase {
    @MainActor
    func testEachSavedSeedChoiceReopensWithTheSameIndividualWithoutRewritingTheProfile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("seed-profile-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let kin = LocalQiMon(character: .kin, originDigest: String(repeating: "a", count: 64), welcomedAt: Date())
        for appearance in CompanionSeedAppearance.allCases {
            var preferences = CompanionPreferences()
            preferences.seedAppearance = appearance
            let original = try NativePreferenceDocument(preferences: preferences, qiMon: kin).encoded()
            let url = directory.appendingPathComponent(appearance.rawValue + ".json")
            try original.write(to: url)
            let store = CompanionStore(preferenceURL: url, allowsPlay: false)
            XCTAssertEqual(store.preferences.seedAppearance, appearance)
            XCTAssertEqual(store.activeQiMon?.originDigest, kin.originDigest)
            XCTAssertEqual(try Data(contentsOf: url), original)
            XCTAssertFalse(store.unityPresentation.isSharing)
            await store.shutdownAssistant()
        }
    }

    func testOlderProfilesKeepTheirSeedDefaultAndUnknownSeedValuesAreRejected() throws {
        let original = try NativePreferenceDocument(preferences: CompanionPreferences()).encoded()
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var preferences = try XCTUnwrap(document["preferences"] as? [String: Any])
        preferences.removeValue(forKey: "seedAppearance")
        document["preferences"] = preferences
        let legacy = try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: document))
        XCTAssertEqual(legacy.preferences?.seedAppearance, .kinParticles)
        preferences["seedAppearance"] = "unrecognized-light"
        document["preferences"] = preferences
        XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: document)))
    }
}
