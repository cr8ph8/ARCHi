import Foundation
import Testing
@testable import ARCHiDesktop

@MainActor
struct SeedColorPreferenceTests {
    @Test func restingCueDoesNotMislabelPersonalBaseColor() {
        #expect(KinLightExpression.resting.label == "Resting")
        #expect(KinLightExpression(mode: .focus).label.contains("Clear teal"))
    }
    @Test func versionSixKeepsPersonalContextAndDefaultsToAuthoredColor() throws {
        var document = NativePreferenceDocument(preferences: CompanionPreferences())
        document.personalContext = PersonalContext(name: "Synthetic Person", preferredName: "Tester", entries: [])
        var json = try #require(JSONSerialization.jsonObject(with: document.encoded()) as? [String: Any])
        json["schema"] = "archi-native-preferences/v6"
        var preferences = try #require(json["preferences"] as? [String: Any])
        preferences.removeValue(forKey: "seedColor")
        json["preferences"] = preferences
        let migrated = try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: json))
        #expect(migrated.preferences?.seedColor == .original)
        #expect(migrated.personalContext == document.personalContext)
        #expect(migrated.schema == NativePreferenceDocument.currentSchema)
    }

    @Test func everyColorRoundTripsAndUnknownColorIsRejected() throws {
        for color in CompanionSeedColor.allCases {
            var preferences = CompanionPreferences(); preferences.seedColor = color
            let document = NativePreferenceDocument(preferences: preferences)
            #expect(try NativePreferenceDocument.decode(document.encoded()).preferences?.seedColor == color)
        }
        var json = try #require(JSONSerialization.jsonObject(with: NativePreferenceDocument(preferences: CompanionPreferences()).encoded()) as? [String: Any])
        var preferences = try #require(json["preferences"] as? [String: Any])
        preferences["seedColor"] = "unrecognized"
        json["preferences"] = preferences
        let bytes = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: (any Error).self) { try NativePreferenceDocument.decode(bytes) }
    }

    @Test func colorChangePreservesIdentityGrowthAndOtherProfileAcrossReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("seed-color-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let kinURL = root.appendingPathComponent("kin.json"), hamptonURL = root.appendingPathComponent("hampton.json")
        let kin = LocalQiMon(character: .kin, originDigest: String(repeating: "a", count: 64), welcomedAt: Date())
        let hampton = LocalQiMon(character: .hampton, originDigest: String(repeating: "b", count: 64), welcomedAt: Date())
        try NativePreferenceDocument(preferences: CompanionPreferences(), qiMon: kin).encoded().write(to: kinURL)
        var preferences = CompanionPreferences(); preferences.seedAppearance = .hamptonLiminal
        try NativePreferenceDocument(preferences: preferences, qiMon: hampton).encoded().write(to: hamptonURL)
        let kinBytes = try Data(contentsOf: kinURL)
        let store = CompanionStore(preferenceURL: hamptonURL, allowsPlay: false)
        let history = store.evolution.history
        for color in CompanionSeedColor.allCases {
            store.chooseSeedColor(color)
            #expect(store.activeQiMon == hampton)
            #expect(store.evolution.history == history)
            #expect(store.evolution.kinGrowthRecord == nil)
        }
        store.chooseSeedColor(.garnet)
        store.rememberPreferences = true
        store.savePreferences()
        let reopened = CompanionStore(preferenceURL: hamptonURL, allowsPlay: false)
        #expect(reopened.preferences.seedColor == .garnet)
        #expect(reopened.activeQiMon == hampton)
        #expect(reopened.cursorPresentationForm == .hamptonSeed)
        #expect(try Data(contentsOf: kinURL) == kinBytes)
    }

    @Test func unsupportedUnityColorCannotSilentlyDisplayOriginal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("seed-color-unity-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("preferences.json")
        let kin = LocalQiMon(character: .kin, originDigest: String(repeating: "c", count: 64), welcomedAt: Date())
        try NativePreferenceDocument(preferences: CompanionPreferences(), qiMon: kin).encoded().write(to: url)
        let store = CompanionStore(preferenceURL: url, allowsPlay: false)
        #expect(store.unityPresentationUnavailableReason == nil)
        store.chooseSeedColor(.garnet)
        #expect(store.unityPresentationUnavailableReason(for: nil) != nil)
        #expect(UnityPresentationSnapshot.capture(store: store, sessionID: UUID(), revision: 1, active: true,
                                                  now: Date(), systemReduceMotion: false)?.seedColor == "garnet")
        store.chooseSeedColor(.original)
        #expect(store.unityPresentationUnavailableReason == nil)
    }
}
