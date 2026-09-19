import Foundation

/// Preferences captured when a request is sent, independent of later UI changes.
struct AssistantSettingsSnapshot: Equatable, Sendable {
    let tone: String
    let replyLength: Double
    let role: EvolutionRole?
    let helpStyle: EvolutionHelpStyle?

    init(tone: String, replyLength: Double, role: EvolutionRole? = nil, helpStyle: EvolutionHelpStyle? = nil) {
        self.tone = tone
        self.replyLength = replyLength
        self.role = role
        self.helpStyle = helpStyle
    }

    var lengthLabel: String {
        replyLength < 0.34 ? "brief" : replyLength > 0.67 ? "detailed" : "moderate"
    }

    var summary: String {
        var parts = [tone, "\(lengthLabel.capitalized) replies"]
        if let role { parts.append(role.title) }
        if let helpStyle { parts.append(helpStyle.title) }
        return parts.joined(separator: " · ")
    }
}

/// One presentation policy shared by grounded and Hampton reasoning requests.
enum AssistantPreferenceGuidance {
    static let text = """
    \(PersonalContextSnapshot.guidance)
    The input's tone, length, optional role and optional helpStyle are presentation defaults. The current question takes precedence over these defaults when they conflict.
    Tone controls the voice. Length controls the amount of detail: brief focuses on essentials, moderate includes helpful context, and detailed adds useful explanation, within the response limits.
    An optional role changes emphasis using these meanings:
    \(EvolutionRole.allCases.map { "\($0.rawValue): \($0.summary)" }.joined(separator: "\n"))
    An optional helpStyle changes structure: concise leads with the answer and keeps supporting points focused; exploratory presents relevant possibilities and tradeoffs; stepByStep organizes useful actions or explanations in order; reflective helps examine implications and the user's stated priorities.
    When role or helpStyle is absent, do not infer a selected role or style. Role and helpStyle grant no tools, privileges, authority or new abilities. A role does not authorize saving information, taking actions or changing permissions.
    """
}
