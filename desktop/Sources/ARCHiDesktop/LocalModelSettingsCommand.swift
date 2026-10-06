import AppKit

/// Device settings can be maintained without opening a second companion session.
/// This command has no prompt, profile, external route, or reader-setting input.
@MainActor
enum LocalModelSettingsCommand {
    typealias Update = NativeAssistantModelPreferences.Update

    enum Failure: Error, LocalizedError {
        case arguments, running, persistence
        var errorDescription: String? {
            switch self {
            case .arguments:
                "Use --local-model-settings [--next-launch] [--reasoning LOCAL_TAG] [--compact LOCAL_TAG] [--work automatic|compact|reasoning]. Duplicate or unsupported values are rejected."
            case .running:
                "ARCHi is open. Settings were not changed; quit normally before changing model assignments."
            case .persistence:
                "The model settings could not be confirmed on disk."
            }
        }
    }

    static func parse(_ arguments: [String]) throws -> Update {
        guard arguments.count.isMultiple(of: 2) else { throw Failure.arguments }
        var result = Update()
        var seen = Set<String>()
        for index in stride(from: 0, to: arguments.count, by: 2) {
            let flag = arguments[index], value = arguments[index + 1]
            guard seen.insert(flag).inserted else { throw Failure.arguments }
            switch flag {
            case "--reasoning", "--compact":
                guard LocalModelCatalog.supportedModels.contains(value) else { throw Failure.arguments }
                if flag == "--reasoning" { result.reasoning = value } else { result.compact = value }
            case "--work":
                guard let work = LocalWorkPreference(rawValue: value) else { throw Failure.arguments }
                result.work = work
            default: throw Failure.arguments
            }
        }
        return result
    }

    static func apply(_ update: Update, defaults: UserDefaults, nextLaunch: Bool = false,
                      isRunning: () -> Bool,
                      verify: (String) async throws -> Void) async throws -> NativeAssistantModelPreferences.Selection {
        let preferences = NativeAssistantModelPreferences(defaults: defaults)
        let before = preferences.load()
        guard update.changesSettings else {
            guard !nextLaunch else { throw Failure.arguments }
            return before
        }
        guard nextLaunch || !isRunning() else { throw Failure.running }
        // Validate installed identities via the existing loopback adapter before
        // saving. connect() reads metadata only; it never generates or pulls.
        for model in Set([update.reasoning, update.compact].compactMap { $0 }).sorted() {
            try await verify(model)
        }
        try Task.checkCancellation()
        if nextLaunch {
            guard preferences.queueForNextLaunch(update) else { throw Failure.persistence }
            return before
        }
        guard !isRunning() else { throw Failure.running }
        let selected = update.applying(to: before)
        preferences.save(selected)
        guard defaults.synchronize(), preferences.load() == selected,
              preferences.removeQueuedOverrides(for: update) else { throw Failure.persistence }
        return selected
    }

    static func run(arguments: [String]) async -> Int32 {
        do {
            let nextLaunch = arguments.first == "--next-launch"
            let update = try parse(nextLaunch ? Array(arguments.dropFirst()) : arguments)
            // A bundled CLI shares the app's standard domain. Foundation rejects
            // adding one's own bundle identifier as a named suite. Unbundled
            // development executables need the explicit application domain.
            let deviceDefaults = Bundle.main.bundleIdentifier == DesktopApplicationIdentity.bundleIdentifier
                ? UserDefaults.standard : UserDefaults(suiteName: DesktopApplicationIdentity.bundleIdentifier)
            guard let defaults = deviceDefaults else {
                throw Failure.persistence
            }
            let selection = try await apply(update, defaults: defaults, nextLaunch: nextLaunch, isRunning: {
                let identifiers = [DesktopApplicationIdentity.bundleIdentifier,
                                   DesktopApplicationIdentity.legacyPreviewIdentifier]
                return identifiers.contains { identifier in
                    NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                        .contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
                }
            }, verify: { model in
                let client = QwenAssistant(model: model)
                defer { client.disconnect() }
                try await client.connect()
            })
            let pending = NativeAssistantModelPreferences(defaults: defaults).pendingUpdate()
            var result: [String: Any] = [
                "schema": "archi-local-model-settings-receipt/v1",
                "result": "PASS", "updated": update.changesSettings && !nextLaunch,
                "queuedForNextLaunch": update.changesSettings && nextLaunch,
                "selectionScope": "Saved device settings; not a live session observation",
                "reasoningModel": selection.reasoningModel,
                "compactModel": selection.compactModel,
                "workPreference": selection.workPreference.rawValue,
                "deliveryRoute": NativeAssistantRoutePreference(defaults: defaults).load().rawValue,
                "deliveryPermissionChanged": false, "profileRead": false,
                "generationRequests": 0, "externalRequests": 0
            ]
            if let pending {
                let next = pending.applying(to: selection)
                result["nextLaunch"] = ["reasoningModel": next.reasoningModel,
                                        "compactModel": next.compactModel,
                                        "workPreference": next.workPreference.rawValue]
            }
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            return 0
        } catch {
            let data = try? JSONSerialization.data(withJSONObject: ["result": "STOPPED", "reason": error.localizedDescription],
                                                  options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data ?? Data(), as: UTF8.self))
            return 2
        }
    }
}
