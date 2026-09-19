import Foundation

/// A bounded explanation of the current request's admission decision. It records
/// neither model text nor source excerpts, and accepted means structural checks
/// passed under current ownership, not that an answer is semantically true.
struct HamptonAdmissionOutcome: Equatable, Sendable {
    enum Status: String, Sendable { case accepted, rejected, stopped }
    enum Stage: String, Sendable {
        case inputBudget, connection, generation, validation, publication
        var title: String {
            switch self {
            case .inputBudget: "Request checks"
            case .connection: "Local connection"
            case .generation: "Model response"
            case .validation: "Response checks"
            case .publication: "Current-context check"
            }
        }
    }
    enum FailureReason: String, Sendable {
        case invalidInput, contextLimit, oversized, malformedJSON, duplicateKey, wrongRole, wrongRequest
        case invalidShape, invalidText, unknownReference, repeatedReference, inconsistentDecision
        case staleContext, cancelled, timedOut, unavailable, unsupportedModel, nonLocalModel, modelChanged
        case invalidResponse, outputLimit, generationFailed, internalFailure

        var explanation: String {
            switch self {
            case .invalidInput: "The supplied selection, lesson or revision input was not current and valid."
            case .contextLimit: "The request exceeded the local context budget."
            case .oversized: "The returned proposal exceeded its permitted size."
            case .malformedJSON: "The returned proposal was not valid JSON."
            case .duplicateKey: "The returned proposal repeated a JSON field."
            case .wrongRole: "The response identified a different role."
            case .wrongRequest: "The response did not match the current request."
            case .invalidShape: "The response omitted required fields or included unsupported fields."
            case .invalidText: "The response text was empty or exceeded its permitted length."
            case .unknownReference: "The response cited a source or memory that was not supplied."
            case .repeatedReference: "The response repeated a source or memory reference."
            case .inconsistentDecision: "The response decision did not agree with its selected references or content."
            case .staleContext: "The request's context was no longer current when the response was checked."
            case .cancelled: "The current request was stopped before delivery completed."
            case .timedOut: "The local workflow reached its time limit."
            case .unavailable: "The selected local model or Ollama connection was unavailable."
            case .unsupportedModel: "The selected model is not supported by this local route."
            case .nonLocalModel: "The model could not be verified for the local route."
            case .modelChanged: "The installed model changed after connection."
            case .invalidResponse: "The local transport returned an unsupported or incomplete response."
            case .outputLimit: "The model reached its reply limit."
            case .generationFailed: "The model could not complete its response."
            case .internalFailure: "The local workflow could not complete this stage."
            }
        }
    }

    let status: Status
    let stage: Stage
    let role: LocalModelRole?
    let requestID: String?
    let reason: FailureReason?

    var summary: String {
        switch status {
        case .accepted: "Response checks passed"
        case .rejected: "\(stage.title) did not pass"
        case .stopped: "Reply stopped"
        }
    }

    var detail: String {
        if let reason { return reason.explanation }
        return "Structure, reference membership and current request ownership passed. This does not verify the answer's factual accuracy."
    }

    static func failure(_ error: Error, stage: Stage, role: LocalModelRole?, requestID: String?) -> Self {
        let reason: FailureReason
        if error is CancellationError { reason = .cancelled }
        else if let validation = error as? HamptonProposalValidationError {
            switch validation {
            case .oversized: reason = .oversized
            case .malformedJSON: reason = .malformedJSON
            case .duplicateKey: reason = .duplicateKey
            case .wrongRole: reason = .wrongRole
            case .wrongRequest: reason = .wrongRequest
            case .invalidShape: reason = .invalidShape
            case .invalidText: reason = .invalidText
            case .unknownReference: reason = .unknownReference
            case .repeatedReference: reason = .repeatedReference
            case .inconsistentDecision: reason = .inconsistentDecision
            }
        } else if error is SessionContextError { reason = .staleContext }
        else if error is LocalQwenRuntimeFailure { reason = .unavailable }
        else if let qwen = error as? QwenFailure {
            switch qwen {
            case .stopped: reason = .cancelled
            case .timedOut: reason = .timedOut
            case .contextLimit: reason = .contextLimit
            case .unavailable, .modelUnavailable: reason = .unavailable
            case .unsupportedModel: reason = .unsupportedModel
            case .nonLocalModel: reason = .nonLocalModel
            case .modelChanged: reason = .modelChanged
            case .invalidResponse: reason = stage == .inputBudget ? .invalidInput : .invalidResponse
            case .outputLimit: reason = .outputLimit
            case .generationFailed: reason = .generationFailed
            case .busy: reason = .internalFailure
            }
        } else if let failure = error as? HamptonAssistantFailure {
            switch failure {
            case .contextLimit: reason = .contextLimit
            case .timedOut: reason = .timedOut
            case .invalidProposal: reason = .invalidShape
            }
        } else { reason = .internalFailure }
        return Self(status: reason == .cancelled ? .stopped : .rejected, stage: stage,
            role: role, requestID: requestID, reason: reason)
    }
}
