import Foundation

/// Product wording shared by existing chat surfaces. This owns no conversation,
/// provider, profile or persistence state; each companion keeps its own name.
enum AskARCHiBrand {
    static let title = "Ask ARCHi"

    static func companionLine(name: String?) -> String {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return "Your companion"
        }
        return "With \(name)"
    }
}
