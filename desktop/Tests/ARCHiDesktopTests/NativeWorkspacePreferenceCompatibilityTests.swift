import Foundation
import XCTest
@testable import ARCHiDesktop

final class NativeWorkspacePreferenceCompatibilityTests: XCTestCase {
    func testEveryThemeSurvivesStrictNativeEnvelopeAndBarePreferenceDecoding() throws {
        for appearance in WorkspaceAppearance.allCases {
            var preferences = CompanionPreferences()
            preferences.workspaceAppearance = appearance
            let document = NativePreferenceDocument(preferences: preferences)
            XCTAssertEqual(try NativePreferenceDocument.decode(document.encoded()).preferences, preferences)
            XCTAssertEqual(try NativePreferenceDocument.decode(JSONEncoder().encode(preferences)).preferences, preferences)
        }
    }

    func testLegacyNativeProfileKeepsDefaultWhileUnknownThemeAndUnknownFieldsRemainRejected() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(CompanionPreferences())) as? [String: Any])
        object.removeValue(forKey: "workspaceAppearance")
        XCTAssertEqual(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: object)).preferences?.workspaceAppearance, .system)
        object["workspaceAppearance"] = "unknown"
        XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: object)))
        object["workspaceAppearance"] = "dark"
        object["unknownPreference"] = true
        XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: object)))
    }
}
