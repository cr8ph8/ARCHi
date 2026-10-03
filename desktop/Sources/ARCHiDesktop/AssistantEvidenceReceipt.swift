import Foundation

/// A transport attempt is distinct from a validated role response. Completed
/// means generate returned while still owned; it does not mean admission passed.
/// Dispatched means LocalRoleClient.generate was entered, not HTTP acceptance.
struct HamptonInvocationReceipt: Identifiable, Equatable, Sendable {
    enum Outcome: String, Sendable { case dispatched, completed, failed, cancelled }
    let id: String
    let role: LocalModelRole
    let inputDigest: String
    let systemDigest: String
    let schemaDigest: String
    var representationAccess: LocalRepresentationAccess = .notReported
    var representationConfiguration: LocalRepresentationConfiguration = .off
    var representationReceipt: LocalRepresentationReceipt = .notRecorded
    var outcome: Outcome = .dispatched
    var model: QwenModelMetadata? = nil
    var elapsedMilliseconds: Int? = nil
    var outputDigest: String? = nil
    var metrics: LocalInferenceMetrics? = nil
    let policyVersion = HamptonInvocationPolicy.version
    /// Captured configured limits, separate from optional observed token counts.
    let contextTokenLimit = HamptonInvocationPolicy.contextTokens
    let outputTokenLimit = HamptonInvocationPolicy.outputTokens
    let temperature = HamptonInvocationPolicy.temperature
}

struct AssistantEvidenceSelection: Equatable, Sendable {
    var eligibleIDs: [String] = []
    var offeredIDs: [String] = []
    var dispatchedIDs: [String] = []
    var selectedIDs: [String] = []
}

struct AssistantEvidenceOmission: Equatable, Sendable {
    enum Kind: String, Sendable { case candidates, reminders, sessionRecords, conversation, context, lessons }
    enum Reason: String, Sendable { case budget, disabled, expired, revoked, unmatched, otherSource, unavailable }
    let kind: Kind
    let reason: Reason
    var ids: [String] = []
    /// Nil means extraction did not run or a count was not available, never zero.
    var count: Int? = nil
}

/// Decision metadata only: no excerpts, questions, replies or lesson text. Offered
/// means a bounded input was prepared; dispatched is set only at generate entry.
/// Selected/cited IDs are validated model selections, not factual verification.
struct AssistantEvidenceReceipt: Equatable, Sendable {
    let version = "assistant-evidence/v1"
    let contextEnabled: Bool
    var candidates = AssistantEvidenceSelection()
    var reminders = AssistantEvidenceSelection()
    var sourceIDsAvailable: [String] = []
    var lessonIDsAvailable: [String] = []
    var reasoningSourceIDsOffered: [String] = []
    var reasoningMemoryIDsOffered: [String] = []
    var reasoningSourceIDsDispatched: [String] = []
    var reasoningMemoryIDsDispatched: [String] = []
    var sourceIDsCited: [String] = []
    var memoryIDsCited: [String] = []
    var conversationOfferedCount = 0
    var conversationOfferedDigest: String? = nil
    var conversationPreparedCount: Int? = nil
    var conversationPreparedDigest: String? = nil
    var conversationDispatchedCount: Int? = nil
    var conversationDispatchedDigest: String? = nil
    var omissions: [AssistantEvidenceOmission] = []
}
