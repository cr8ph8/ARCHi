import Foundation

enum AssistantRoute: String, CaseIterable, Identifiable, Sendable {
    case native, local, codex, compare, automatic
    var id: String { rawValue }
    var title: String {
        switch self { case .native: "ARCHi · Qwen first"; case .local: "Local Qwen · manual"; case .codex: "Codex · external reference"; case .compare: "Compare · external reference"; case .automatic: "Local Qwen · auto-connect" }
    }
    var disclosure: String {
        switch self {
        case .native: "ARCHi manages Qwen on this Mac. Send tries local Qwen first; a connection, generation or timeout failure can use one Codex request through your existing account. Your message, shared copy and reply settings may then leave this Mac. Kept lessons, personal context and recent Qwen conversation stay local. Choose Local Qwen auto-connect to keep all requests local."
        case .local: "Your message and shared copy go only to Qwen on this Mac."
        case .codex: "Optional reference or alternative. Send shares your message, full shared copy and reply settings with Codex through ChatGPT. Kept lessons, session excerpts and recent Qwen conversation stay local."
        case .compare: "Deliberate second opinion. Send shares your message, full shared copy and reply settings with Qwen and external Codex. Kept lessons, session excerpts and recent Qwen conversation stay with Qwen."
        case .automatic: "Send connects Qwen on this Mac when needed. If local work cannot finish, it stops here. External help requires choosing Codex or Compare and sending again."
        }
    }
    var providers: [AssistantProvider] {
        switch self { case .native, .local, .automatic: [.qwen]; case .codex: [.codex]; case .compare: [.qwen, .codex] }
    }
    var connectsAutomatically: Bool { self == .automatic || self == .native }
    var primaryProvider: AssistantProvider { self == .codex ? .codex : .qwen }
}

enum AssistantLaneState: String, Equatable, Sendable { case pending, complete, failed, cancelled }

/// Local presentation evidence captured by Point and explain. These native
/// rectangles are not model input and do not authorize a movement or edit.
struct AssistantPointingSnapshot: Equatable {
    let geometry: SelectedPassageGeometry
    let environment: SpatialEnvironment
    let candidate: SpatialPlacementCandidate
    let gesture: FocusGestureConfiguration
}

/// A receipt identifies the dispatched current input and its outcome, not the
/// semantic truth of either answer. Local role inputs have separate receipts.
struct AssistantLaneReceipt: Equatable, Sendable {
    let requestID: String
    let route: AssistantRoute
    let provider: AssistantProvider
    let context: ContextTicket
    let inputDigest: String
    var sourceDigest: String? = nil
    let inputContract: String
    let deadline: Date
    var modelIdentity: String?
    var state: AssistantLaneState
    var settings: AssistantSettingsSnapshot? = nil
    var requestStarted = false
    var localInvocations: [LocalModelRole]? = nil
    /// Operation-local accounting captured with this answer, including attempts
    /// that never produced an admissible role result. Never a durable memory.
    var localInvocationReceipts: [HamptonInvocationReceipt]? = nil
    var evidence: AssistantEvidenceReceipt? = nil
    var localLessonOmissions: [AssistantEvidenceOmission] = []
    var elapsedMilliseconds: Int? = nil
    var localLessons: [LessonSnapshot] = []
    var localLessonDigest: String? = nil
    var localProfileDigest: String? = nil
    var localProfileRevision: UInt64? = nil
    var localConversationCount = 0
    var localConversationBytes = 0
    var localConversationDigest: String? = nil
    var localConversationOmittedCount = 0
    var usedLessonIDs: [String] = []
    var pointing: AssistantPointingSnapshot? = nil
    var routingReason: String? = nil
    var admissionOutcome: HamptonAdmissionOutcome? = nil
    /// Ephemeral source excerpts for the current answer. The usage journal
    /// retains only the matching trace/result digests, never these texts.
    var documentReading: DocumentReadingPlan? = nil
    var readingControl: HamptonQ2EDecision? = nil
    var readingResult: DocumentReadingResult? = nil
}

struct AssistantLaneResult: Equatable, Sendable {
    var text: String
    var status: String
    var state: AssistantLaneState
    var receipt: AssistantLaneReceipt?
    var revision: PassageRevisionProposal? = nil
}
