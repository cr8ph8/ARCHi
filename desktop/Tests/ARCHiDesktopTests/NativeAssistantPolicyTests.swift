import XCTest
@testable import ARCHiDesktop

final class NativeAssistantPolicyTests: XCTestCase {
    func testFallbackDoesNotConvertValidationOrCancellationIntoExternalPermission() {
        for error: any Error in [QwenFailure.unavailable, QwenFailure.modelUnavailable,
            QwenFailure.timedOut, QwenFailure.generationFailed, LocalQwenRuntimeFailure.notInstalled,
            LocalQwenRuntimeFailure.startFailed, LocalQwenRuntimeFailure.timedOut, HamptonAssistantFailure.timedOut] {
            XCTAssertTrue(NativeAssistantFallback.isEligible(error))
        }
        for error: any Error in [QwenFailure.stopped, QwenFailure.modelChanged, QwenFailure.invalidResponse,
            QwenFailure.contextLimit, QwenFailure.nonLocalModel, HamptonAssistantFailure.invalidProposal,
            HamptonAssistantFailure.contextLimit, CancellationError(), CocoaError(.fileWriteNoPermission)] {
            XCTAssertFalse(NativeAssistantFallback.isEligible(error))
        }
    }

    func testLocalOnlyChoiceSurvivesReloadAndUnknownSavedChoiceStaysLocal() throws {
        let name = "ARCHiNativeRouteTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preference = NativeAssistantRoutePreference(defaults: defaults)
        XCTAssertEqual(preference.load(), .native)
        preference.save(.automatic)
        XCTAssertEqual(NativeAssistantRoutePreference(defaults: defaults).load(), .automatic)
        preference.save(.local)
        XCTAssertEqual(preference.load(), .local)
        defaults.set("future-unknown-route", forKey: NativeAssistantRoutePreference.key)
        XCTAssertEqual(preference.load(), .automatic)
        defaults.set(123, forKey: NativeAssistantRoutePreference.key)
        XCTAssertEqual(preference.load(), .automatic)
    }
}
