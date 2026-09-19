import Foundation

/// Device-level delivery preference, separate from companion identity. A user's
/// local-only choice must survive restart and profile switching.
struct NativeAssistantRoutePreference {
    static let key = "assistant.route.preference.v1"
    let defaults: UserDefaults

    func load() -> AssistantRoute {
        guard let value = defaults.object(forKey: Self.key) else { return .native }
        // An unreadable saved choice cannot newly authorize external delivery.
        guard let raw = value as? String, let route = AssistantRoute(rawValue: raw) else { return .automatic }
        return route
    }

    func save(_ route: AssistantRoute) { defaults.set(route.rawValue, forKey: Self.key) }
}
