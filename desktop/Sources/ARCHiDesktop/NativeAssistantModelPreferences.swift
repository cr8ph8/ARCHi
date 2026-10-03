import Foundation

/// Local model assignments belong to this Mac, not to a companion's identity.
/// This record has no route, endpoint, reader, or permission fields.
@MainActor
struct NativeAssistantModelPreferences {
    static let key = "assistant.models.preference.v1"
    static let schema = "archi-local-model-preferences/v1"
    static let pendingKey = "assistant.models.next-launch.v1"

    struct Selection: Equatable, Sendable {
        let reasoningModel: String
        let compactModel: String
        let workPreference: LocalWorkPreference
    }

    static var initialSelection: Selection {
        Selection(reasoningModel: QwenAssistant.defaultModel,
                  compactModel: HamptonReasonsAssistant.defaultContextModel,
                  workPreference: .automatic)
    }

    let defaults: UserDefaults

    /// A one-time partial update. Later unrelated selections are preserved.
    struct Update: Equatable {
        var reasoning: String?
        var compact: String?
        var work: LocalWorkPreference?
        var changesSettings: Bool { reasoning != nil || compact != nil || work != nil }

        func applying(to current: Selection) -> Selection {
            Selection(reasoningModel: reasoning ?? current.reasoningModel,
                      compactModel: compact ?? current.compactModel,
                      workPreference: work ?? current.workPreference)
        }
    }

    func queueForNextLaunch(_ update: Update) -> Bool {
        let previous = pendingUpdate()
        let combined = Update(reasoning: update.reasoning ?? previous?.reasoning,
                              compact: update.compact ?? previous?.compact,
                              work: update.work ?? previous?.work)
        return writePending(combined)
    }

    /// A newer immediate change supersedes only the same queued fields.
    func removeQueuedOverrides(for update: Update) -> Bool {
        guard let previous = pendingUpdate() else { return true }
        let remaining = Update(reasoning: update.reasoning == nil ? previous.reasoning : nil,
                               compact: update.compact == nil ? previous.compact : nil,
                               work: update.work == nil ? previous.work : nil)
        if remaining.changesSettings { return writePending(remaining) }
        defaults.removeObject(forKey: Self.pendingKey)
        return defaults.synchronize()
    }

    private func writePending(_ update: Update) -> Bool {
        var record: [String: String] = ["schema": "archi-local-model-next-launch/v1"]
        record["reasoning"] = update.reasoning
        record["compact"] = update.compact
        record["work"] = update.work?.rawValue
        guard Self.decodePending(record) != nil else { return false }
        defaults.set(record, forKey: Self.pendingKey)
        return defaults.synchronize() && pendingUpdate() == update
    }

    func pendingUpdate() -> Update? {
        guard let record = defaults.dictionary(forKey: Self.pendingKey) else { return nil }
        return Self.decodePending(record)
    }

    /// Called by the one native owner before constructing its assistant clients.
    /// It does not open a companion profile or alter delivery/reader permissions.
    @discardableResult
    func activateQueuedUpdate() -> Bool {
        guard let update = pendingUpdate() else { return false }
        let selection = update.applying(to: load())
        save(selection)
        guard defaults.synchronize(), load() == selection else { return false }
        defaults.removeObject(forKey: Self.pendingKey)
        return defaults.synchronize()
    }

    private static func decodePending(_ record: [String: Any]) -> Update? {
        guard record["schema"] as? String == "archi-local-model-next-launch/v1",
              Set(record.keys).isSubset(of: ["schema", "reasoning", "compact", "work"]) else { return nil }
        for key in ["reasoning", "compact"] where record[key] != nil {
            guard let value = record[key] as? String,
                  LocalModelCatalog.supportedModels.contains(value) else { return nil }
        }
        if record["work"] != nil {
            guard let work = record["work"] as? String, LocalWorkPreference(rawValue: work) != nil else { return nil }
        }
        let update = Update(reasoning: record["reasoning"] as? String,
                            compact: record["compact"] as? String,
                            work: (record["work"] as? String).flatMap(LocalWorkPreference.init(rawValue:)))
        return update.changesSettings ? update : nil
    }

    func load() -> Selection {
        guard let record = defaults.dictionary(forKey: Self.key),
              record["schema"] as? String == Self.schema else { return Self.initialSelection }
        return Self.validated(reasoningModel: record["reasoningModel"] as? String,
                              compactModel: record["compactModel"] as? String,
                              workPreference: (record["workPreference"] as? String).flatMap(LocalWorkPreference.init(rawValue:)))
    }

    func save(_ selection: Selection) {
        let selection = Self.validated(reasoningModel: selection.reasoningModel,
                                       compactModel: selection.compactModel,
                                       workPreference: selection.workPreference)
        defaults.set(["schema": Self.schema,
                      "reasoningModel": selection.reasoningModel,
                      "compactModel": selection.compactModel,
                      "workPreference": selection.workPreference.rawValue], forKey: Self.key)
    }

    private static func validated(reasoningModel: String?, compactModel: String?,
                                  workPreference: LocalWorkPreference?) -> Selection {
        let initial = initialSelection
        return Selection(
            reasoningModel: reasoningModel.flatMap { LocalModelCatalog.supportedModels.contains($0) ? $0 : nil } ?? initial.reasoningModel,
            compactModel: compactModel.flatMap { LocalModelCatalog.supportedModels.contains($0) ? $0 : nil } ?? initial.compactModel,
            workPreference: workPreference ?? initial.workPreference)
    }
}
