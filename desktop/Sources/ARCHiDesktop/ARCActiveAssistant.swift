import Foundation

enum ARCActiveAssistantCommand: String, Equatable, Sendable {
    case solve, propose
}

/// Dispatch only an entire user-authored command. Source text, history and model
/// output are never inspected for commands by this parser.
enum ARCActiveAssistant {
    enum Selection: Equatable {
        case command(ARCActiveAssistantCommand)
        case invalid
    }

    static func select(_ question: String) -> Selection? {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch text {
        case "/arc solve", "solve this arc puzzle", "solve the loaded arc task": return .command(.solve)
        case "/arc propose": return .command(.propose)
        default:
            // Mistyped explicit commands fail locally, including extra arguments.
            // A mention inside ordinary prose or a quoted command stays prose.
            if text == "/arc" || text.hasPrefix("/arc ") || text.hasPrefix("/arc\t") || text.hasPrefix("/arc\n") {
                return .invalid
            }
            return nil
        }
    }

    static let commandHelp = "Use /arc solve for native rule search or /arc propose for one local Qwen proposal. Share standard ARC train/test JSON, or load an ARC task first."
}

enum ARCActiveAssistantResult: Equatable, Sendable {
    case symbolic(ARCSolverRun)
    case proposal(ARCQwenProposalResult)

    var predictions: [ARCGrid]? {
        switch self {
        case .symbolic(let run): run.predictions
        case .proposal(let result): result.predictions
        }
    }

    var description: String {
        switch self {
        case .symbolic(let run):
            switch run.outcome {
            case .predicted: "The native rules agree on a prediction."
            case .ambiguous: "ARC abstained because fitting rules disagree or cannot predict every test input."
            case .noMatch: "ARC abstained because no rule in its bounded catalog fits all training examples."
            case .budgetExhausted: "ARC abstained because its work limit was reached."
            }
        case .proposal(let result):
            switch result.status {
            case .predicted: "Qwen's proposed rule passed every training example."
            case .abstained: "Local Qwen abstained."
            case .trainingMismatch: "Qwen's proposed rule did not fit every training example."
            case .trainingUndefined: "The proposed rule could not process a training example."
            case .predictionUndefined: "The proposed rule could not process every test input."
            case .budgetExhausted: "The proposed rule reached its native work limit."
            }
        }
    }
}

/// Transient assistant presentation of the same ARC execution and checker
/// receipt used by the ARC workspace. Never a model lane or retained lesson.
struct ARCActiveAssistantAnswer: Equatable, Sendable {
    let command: ARCActiveAssistantCommand
    let taskID: String?
    let evidenceID: String?
    let inputName: String?
    let inputDigest: String?
    let status: String
    let result: ARCActiveAssistantResult?
    let summary: ARCCapabilitiesSummary?
    let error: String?
    let isWorking: Bool
    var cancelled = false

    var predictions: [ARCGrid]? { result?.predictions }

    var replyText: String {
        if let error { return error }
        if cancelled { return "I stopped working on this. You can return to it when you're ready." }
        if isWorking { return "I'm looking for a pattern in the examples you shared." }
        let message: String
        switch result {
        case .symbolic(let run):
            switch run.outcome {
            case .predicted: message = "I found a pattern that fits your examples. The matching rules agree on the result."
            case .ambiguous: message = "The examples support different results, so I haven't chosen one. Another example or constraint could help narrow it down."
            case .noMatch: message = "I haven't found a pattern that explains all the examples with the methods available to me. You can share another example or try another approach."
            case .budgetExhausted: message = "I reached the work limit before I could settle on a result. I've paused here."
            }
        case .proposal(let proposal):
            switch proposal.status {
            case .predicted: message = "The proposed pattern fits the examples you shared. Here is the result it suggests."
            case .abstained: message = "I don't have a useful pattern to suggest yet. Another example or constraint may help."
            case .trainingMismatch, .trainingUndefined: message = "The proposed pattern doesn't explain every example, so I haven't used it to give you an answer."
            case .predictionUndefined: message = "The pattern fits the examples but cannot produce every requested result. I need another approach."
            case .budgetExhausted: message = "I reached the work limit while checking the proposed pattern. I've paused here."
            }
        case nil: message = status
        }
        guard predictions != nil, let counts = summary?.counts else { return message }
        if counts.incorrect > 0 || counts.invalid > 0 || counts.missing > 0 {
            return message + " The supplied answers do not all agree with this result, so it needs review."
        }
        if counts.unscored > 0 { return message + " Some results have no supplied answer to confirm them yet." }
        return counts.totalExamples > 0 ? message + " It also matches the supplied answers." : message
    }
}

/// Companion ownership wraps the existing ARC store's ownership, not its
/// executor. The last event also preserves accounting identity during Stop.
@MainActor
final class ARCActiveAssistantOwnership {
    let id = UUID()
    let command: ARCActiveAssistantCommand
    let ticket: ContextTicket
    let document: ARCSolverDocument
    var lastEvent: ARCCapabilitiesEvent?

    init(command: ARCActiveAssistantCommand, ticket: ContextTicket, document: ARCSolverDocument) {
        self.command = command
        self.ticket = ticket
        self.document = document
    }
}
