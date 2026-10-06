import Foundation

/// Read-only presentation of the existing request owner's send conditions.
/// Both workspace composers explain the same next action without owning a request.
struct AssistantComposerState {
    let blockedReason: String?
    let sendDisclosure: String
    var canSend: Bool { blockedReason == nil }

    @MainActor
    init(store: CompanionStore) {
        if store.isShuttingDown {
            blockedReason = "ARCHi is closing."
        } else if store.voiceInput.isActive {
            blockedReason = "Finish or cancel dictation before sending."
        } else if store.isWorking {
            blockedReason = "Stop the current reply before sending another."
        } else if !store.arcCommandSelected && store.requestsRevision && store.textSelection == nil {
            blockedReason = "Select the passage to revise."
        } else if !store.arcCommandSelected && !store.canShareDesktopInterestWithRoute {
            blockedReason = "Allow this window copy for your external route before sending."
        } else if let reason = store.nextAssistantBlockedReason {
            blockedReason = reason
        } else if !store.canBeginReply {
            blockedReason = store.route == .compare
                ? "Connect both assistants to send." : "Connect \(store.assistantProvider.name) to send."
        } else if store.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blockedReason = "Write a message to send."
        } else {
            blockedReason = nil
        }

        if let disclosure = store.nextExecutionSelection.nativeDisclosure {
            sendDisclosure = disclosure
        } else if let blockedReason, !store.isWorking {
            sendDisclosure = blockedReason
        } else {
            let selection = store.isWorking ? store.replySourceSelection : store.textSelection
            let payload = store.sourceName == nil ? "Message"
                : selection == nil ? "Message and full copy" : "Message, full copy and selected passage"
            let localPayload = store.sourceName == nil ? "Your message stays" : "\(payload) stay"
            switch store.route {
            case .native:
                if let reason = store.nextAssistantFallbackBlockedReason {
                    sendDisclosure = "Qwen first. " + reason
                } else {
                    sendDisclosure = "Qwen first. After a connection, generation or timeout failure, one Codex fallback may receive \(payload.lowercased()) and reply settings. Lessons, personal context and conversation stay local."
                }
            case .local:
                sendDisclosure = "\(localPayload) on this Mac."
            case .codex:
                sendDisclosure = "External reference: \(payload.lowercased()) and reply settings go to Codex."
            case .compare:
                sendDisclosure = "Second opinion: \(payload.lowercased()) and reply settings go to both. Lessons stay local."
            case .automatic:
                sendDisclosure = "\(localPayload) on this Mac. Qwen connects when needed; a local failure stays local."
            }
        }
    }
}
