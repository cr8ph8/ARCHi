import Foundation

/// Work allocation is independent of the destination's permission to go external.
/// This is a deterministic application router, not a model-weight mixture.
enum LocalWorkPreference: String, CaseIterable, Identifiable, Sendable {
    case automatic, compact, reasoning
    var id: String { rawValue }
    var title: String {
        switch self { case .automatic: "Auto"; case .compact: "Compact"; case .reasoning: "Reasoning" }
    }
}

struct LocalExpertDecision: Equatable, Sendable {
    enum Target: Equatable, Sendable { case compact, reasoning }
    let target: Target
    let reason: String
}

enum LocalExpertPolicy {
    static let version = "local-expert-policy/v1"

    static func decide(request: AssistantRequest, preference: LocalWorkPreference,
                       measurements: Bool) -> LocalExpertDecision {
        decide(prompt: request.prompt,
               requiresReasoning: request.revisionTarget != nil || request.localControl != nil || request.localReading != nil || request.localKnowledge != nil || request.localConceptDraft != nil
                   || request.sourceName != nil || !request.sourceText.isEmpty || request.selection != nil,
               preference: preference, measurements: measurements)
    }

    /// The composer can use current input facts without manufacturing a request
    /// or preparing reading/control state. Execution delegates to this same rule.
    static func decide(prompt: String, requiresReasoning: Bool, preference: LocalWorkPreference,
                       measurements: Bool) -> LocalExpertDecision {
        if measurements {
            return .init(target: .reasoning, reason: "Measurements require the reader-bound reasoning model.")
        }
        if requiresReasoning {
            return .init(target: .reasoning, reason: "Shared material and document work use the reasoning model.")
        }
        if preference == .reasoning {
            return .init(target: .reasoning, reason: "Reasoning is selected in your local work settings.")
        }
        if preference == .compact && prompt.utf8.count <= 1_500 {
            return .init(target: .compact, reason: "Compact was selected for this short conversation request.")
        }
        // A short prompt can still ask a difficult question. Auto only selects
        // compact for these exact social phrases, never inferred task difficulty.
        let greeting = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        if preference == .automatic && ["hi", "hello", "hey", "thanks", "thank you", "good morning", "good evening"].contains(greeting) {
            return .init(target: .compact, reason: "A simple greeting or thanks uses the compact model.")
        }
        return .init(target: .reasoning, reason: "Open-ended or longer work uses the reasoning model.")
    }
}
