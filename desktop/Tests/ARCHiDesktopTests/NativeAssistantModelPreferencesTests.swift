import XCTest
@testable import ARCHiDesktop

@MainActor
final class NativeAssistantModelPreferencesTests: XCTestCase {
    private func withPreferences(_ body: (NativeAssistantModelPreferences, UserDefaults) throws -> Void) throws {
        let name = "ARCHiNativeModelPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(NativeAssistantModelPreferences(defaults: defaults), defaults)
    }

    func testFirstLaunchAndMalformedRecordsKeepExistingLocalDefaults() throws {
        try withPreferences { preferences, defaults in
            let expected = NativeAssistantModelPreferences.initialSelection
            XCTAssertEqual(expected.reasoningModel, "qwen3.5:9b")
            XCTAssertEqual(expected.compactModel, "qwen3:8b")
            XCTAssertEqual(expected.workPreference, .automatic)
            XCTAssertEqual(preferences.load(), expected)
            for malformed: Any in [42, "qwen3:4b", ["schema": "future-version", "reasoningModel": "qwen3:4b"], ["schema": true]] {
                defaults.set(malformed, forKey: NativeAssistantModelPreferences.key)
                XCTAssertEqual(preferences.load(), expected)
            }
        }
    }

    func testRegisteredLocalSelectionsSurviveReloadWithoutChangingDelivery() throws {
        try withPreferences { preferences, defaults in
            let route = NativeAssistantRoutePreference(defaults: defaults)
            route.save(.automatic)
            let selection = NativeAssistantModelPreferences.Selection(reasoningModel: "qwen3:8b",
                compactModel: "qwen3:1.7b", workPreference: .compact)
            preferences.save(selection)
            XCTAssertEqual(NativeAssistantModelPreferences(defaults: defaults).load(), selection)
            XCTAssertEqual(route.load(), .automatic)
            XCTAssertEqual(Set(try XCTUnwrap(defaults.dictionary(forKey: NativeAssistantModelPreferences.key)).keys),
                           Set(["schema", "reasoningModel", "compactModel", "workPreference"]))
        }
    }

    func testInvalidFieldsDefaultIndependentlyAndCannotEnableAnExternalRoute() throws {
        try withPreferences { preferences, defaults in
            let route = NativeAssistantRoutePreference(defaults: defaults)
            route.save(.automatic)
            defaults.set(["schema": NativeAssistantModelPreferences.schema,
                          "reasoningModel": "remote/qwen3:8b", "compactModel": "qwen3:4b",
                          "workPreference": "codex", "route": "native", "representationMeasurementsEnabled": true],
                         forKey: NativeAssistantModelPreferences.key)
            let selection = preferences.load()
            XCTAssertEqual(selection.reasoningModel, QwenAssistant.defaultModel)
            XCTAssertEqual(selection.compactModel, "qwen3:4b")
            XCTAssertEqual(selection.workPreference, .automatic)
            XCTAssertEqual(route.load(), .automatic)
            defaults.set(["schema": NativeAssistantModelPreferences.schema,
                          "reasoningModel": "qwen3:8b", "compactModel": 123,
                          "workPreference": ["compact"]], forKey: NativeAssistantModelPreferences.key)
            XCTAssertEqual(preferences.load(), .init(reasoningModel: "qwen3:8b",
                compactModel: HamptonReasonsAssistant.defaultContextModel, workPreference: .automatic))
        }
    }

    func testSavingUnknownModelNamesCannotPersistAnUnsupportedAssignment() throws {
        try withPreferences { preferences, _ in
            preferences.save(.init(reasoningModel: "https://models.example/qwen", compactModel: "unknown-model",
                                   workPreference: .reasoning))
            XCTAssertEqual(preferences.load(), .init(reasoningModel: QwenAssistant.defaultModel,
                compactModel: HamptonReasonsAssistant.defaultContextModel, workPreference: .reasoning))
        }
    }
}
