import Foundation

/// Selects an existing executor without granting execution or external access.
/// Prepared procedures and pointing are assistant requests even when their text
/// happens to match a native command. Preview and dispatch share this decision.
enum AssistantExecutionSelection: Equatable {
    case assistant
    case arc(ARCActiveAssistantCommand)
    case invalidARC
    case arc3(ARC3AssistantCommand)

    static func select(question: String, hasPreparedProcedure: Bool, hasPointing: Bool) -> Self {
        guard !hasPreparedProcedure, !hasPointing else { return .assistant }
        if let command = ARC3AssistantCommand.select(question) { return .arc3(command) }
        if let selection = ARCActiveAssistant.select(question) {
            switch selection {
            case .command(let command): return .arc(command)
            case .invalid: return .invalidARC
            }
        }
        return .assistant
    }

    var isNativeCommand: Bool { self != .assistant }
    var isARC3Command: Bool {
        if case .arc3 = self { return true }
        return false
    }

    var nativeCallBudget: String? {
        switch self {
        case .assistant: return nil
        case .arc(.solve): return "0 model calls · native ARC rules and checker"
        case .arc(.propose): return "At most 1 local Qwen proposal call · no external requests"
        case .invalidARC, .arc3(.invalid): return "0 model calls · invalid command; nothing executes"
        case .arc3(.open): return "0 model calls · open local ARC3 controls; no gameplay actions"
        case .arc3(.stop): return "0 model calls · stop ARC3; no new environment actions"
        case .arc3(.explore): return "0 model calls · up to 8 local ARC3 environment actions"
        }
    }

    var nativeDisclosure: String? {
        switch self {
        case .assistant: return nil
        case .arc(.solve):
            return "ARC runs native rules on this Mac using the shared ARC JSON or your loaded task. No model or cloud request; results are independently checked."
        case .arc(.propose):
            return "One local Qwen proposal may use the shared ARC JSON or your loaded task. Native checks decide whether it fits; no external request."
        case .invalidARC:
            return "This ARC command is not recognized. Nothing executes. " + ARCActiveAssistant.commandHelp
        case .arc3(.open):
            return "Open ARC3 controls and discover installed local environments if needed. No gameplay, model call or cloud request."
        case .arc3(.stop):
            return "Stop the current ARC3 work. No new environment action, model call or cloud request."
        case .arc3(.explore):
            return "ARC3 explores the selected local environment for up to 8 actions. No model call or cloud request."
        case .arc3(.invalid):
            return "This ARC3 command is not recognized. Nothing executes. Use /arc3 open, /arc3 explore or /arc3 stop."
        }
    }
}
