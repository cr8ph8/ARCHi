import XCTest
@testable import ARCHiDesktop

@MainActor
final class LocalModelSettingsCommandTests: XCTestCase {
    func testArgumentsRejectRemoteUnsupportedDuplicateAndPermissionInputs() throws {
        XCTAssertEqual(try LocalModelSettingsCommand.parse([]), .init())
        XCTAssertEqual(try LocalModelSettingsCommand.parse(["--compact", "qwen3:1.7b", "--work", "automatic"]),
                       .init(compact: "qwen3:1.7b", work: .automatic))
        for invalid in [["--compact"], ["--compact", "https://example.com/model"],
                        ["--compact", "qwen3:1.7b", "--compact", "qwen3:8b"],
                        ["--route", "native"], ["--work", "codex"], ["--reader", "enable"]] {
            XCTAssertThrowsError(try LocalModelSettingsCommand.parse(invalid))
        }
    }

    func testSettingsRequireStoppedOwnerAndVerifiedIdentityBeforeWriting() async throws {
        let name = "LocalModelSettingsCommandTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let update = try LocalModelSettingsCommand.parse(["--compact", "qwen3:1.7b"])
        var verified = false
        do {
            _ = try await LocalModelSettingsCommand.apply(update, defaults: defaults, isRunning: { true },
                                                         verify: { _ in verified = true })
            XCTFail("Active owner must stop the write")
        } catch { XCTAssertFalse(verified) }
        do {
            _ = try await LocalModelSettingsCommand.apply(update, defaults: defaults, isRunning: { false },
                                                         verify: { _ in throw QwenFailure.nonLocalModel })
            XCTFail("Unverified identity must stop the write")
        } catch { XCTAssertNil(defaults.object(forKey: NativeAssistantModelPreferences.key)) }
        var running = false
        do {
            _ = try await LocalModelSettingsCommand.apply(update, defaults: defaults, isRunning: { running },
                                                         verify: { _ in running = true })
            XCTFail("A newly opened owner must stop the write")
        } catch { XCTAssertNil(defaults.object(forKey: NativeAssistantModelPreferences.key)) }
    }

    func testReadOnlyAndSuccessfulUpdatePreserveOtherSettings() async throws {
        let name = "LocalModelSettingsCommandTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("native", forKey: NativeAssistantRoutePreference.key)
        defaults.set("unchanged", forKey: "unrelated-setting")
        let before = try await LocalModelSettingsCommand.apply(.init(), defaults: defaults, isRunning: { true },
                                                              verify: { _ in XCTFail("Reading must not connect") })
        var verified: [String] = []
        let selected = try await LocalModelSettingsCommand.apply(.init(compact: "qwen3:1.7b"), defaults: defaults,
            isRunning: { false }, verify: { verified.append($0) })
        XCTAssertEqual(verified, ["qwen3:1.7b"])
        XCTAssertEqual(selected.reasoningModel, before.reasoningModel)
        XCTAssertEqual(selected.workPreference, before.workPreference)
        XCTAssertEqual(selected.compactModel, "qwen3:1.7b")
        XCTAssertEqual(NativeAssistantModelPreferences(defaults: defaults).load(), selected)
        XCTAssertEqual(defaults.string(forKey: NativeAssistantRoutePreference.key), "native")
        XCTAssertEqual(defaults.string(forKey: "unrelated-setting"), "unchanged")
    }

    func testNextLaunchUpdateLeavesActiveSettingsAloneThenAppliesOnce() async throws {
        let name = "LocalModelSettingsCommandTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = NativeAssistantModelPreferences(defaults: defaults)
        defaults.set("automatic", forKey: NativeAssistantRoutePreference.key)
        let before = preferences.load()
        _ = try await LocalModelSettingsCommand.apply(.init(compact: "qwen3:1.7b"), defaults: defaults,
            nextLaunch: true, isRunning: { true }, verify: { XCTAssertEqual($0, "qwen3:1.7b") })
        XCTAssertEqual(preferences.load(), before)
        // A later unrelated model choice must survive the deferred partial update.
        preferences.save(.init(reasoningModel: "qwen3:8b", compactModel: before.compactModel, workPreference: .reasoning))
        XCTAssertTrue(preferences.activateQueuedUpdate())
        XCTAssertEqual(preferences.load(), .init(reasoningModel: "qwen3:8b", compactModel: "qwen3:1.7b", workPreference: .reasoning))
        XCTAssertFalse(preferences.activateQueuedUpdate())
        XCTAssertNil(defaults.object(forKey: NativeAssistantModelPreferences.pendingKey))
        XCTAssertEqual(defaults.string(forKey: NativeAssistantRoutePreference.key), "automatic")
        defaults.set(["schema": "archi-local-model-next-launch/v1", "compact": "qwen3:1.7b", "route": "native"],
                     forKey: NativeAssistantModelPreferences.pendingKey)
        XCTAssertFalse(preferences.activateQueuedUpdate())
        XCTAssertEqual(defaults.string(forKey: NativeAssistantRoutePreference.key), "automatic")
    }

    func testPartialQueuesMergeAndNewerImmediateFieldsSupersedeOnlyTheirOverrides() async throws {
        let name = "LocalModelSettingsCommandTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = NativeAssistantModelPreferences(defaults: defaults)
        XCTAssertTrue(preferences.queueForNextLaunch(.init(compact: "qwen3:1.7b")))
        XCTAssertTrue(preferences.queueForNextLaunch(.init(work: .reasoning)))
        XCTAssertEqual(preferences.pendingUpdate(), .init(compact: "qwen3:1.7b", work: .reasoning))
        _ = try await LocalModelSettingsCommand.apply(.init(compact: "qwen3:8b"), defaults: defaults,
                                                     isRunning: { false }, verify: { _ in })
        XCTAssertEqual(preferences.pendingUpdate(), .init(work: .reasoning))
        XCTAssertTrue(preferences.activateQueuedUpdate())
        XCTAssertEqual(preferences.load().compactModel, "qwen3:8b")
        XCTAssertEqual(preferences.load().workPreference, .reasoning)
    }
}
