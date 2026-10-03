import Foundation

/// Typed presentation only. Status text, graph proximity and animation never
/// decide whether a source, method, or outcome is eligible for use.
enum CompanionGraphPresentationState: String, Sendable {
    case recorded, reviewed, candidate, historical, needsReview, unavailable, withdrawn, corrected

    var symbol: String {
        switch self {
        case .recorded: "doc.text"
        case .reviewed: "checkmark.circle"
        case .candidate: "pencil.circle"
        case .historical: "clock.arrow.circlepath"
        case .needsReview: "exclamationmark.triangle"
        case .unavailable: "questionmark.diamond"
        case .withdrawn: "minus.circle"
        case .corrected: "arrow.uturn.backward.circle"
        }
    }

    var needsAttention: Bool {
        switch self {
        case .needsReview, .unavailable, .withdrawn, .corrected: true
        default: false
        }
    }
}

enum CompanionGraphRelationship: String, Sendable {
    case recorded, sourcePassage, derivedFrom, supports, contradicts, dependsOn
    case supersedes, authoredFrom, retainedFrom, usedMethod

    var symbol: String {
        switch self {
        case .recorded: "arrow.right"
        case .sourcePassage: "text.quote"
        case .derivedFrom, .authoredFrom: "arrow.triangle.branch"
        case .supports: "plus.circle"
        case .contradicts: "exclamationmark.bubble"
        case .dependsOn: "link"
        case .supersedes: "arrow.triangle.swap"
        case .retainedFrom: "bookmark"
        case .usedMethod: "arrow.turn.down.right"
        }
    }

    /// Line patterns supplement the label and direction, independently of color.
    var dash: [Double] {
        switch self {
        case .contradicts: [2, 3]
        case .dependsOn: [7, 3]
        case .supersedes: [7, 3, 2, 3]
        default: []
        }
    }

    init(declaration: KnowledgePageLinkKind) {
        switch declaration {
        case .supports: self = .supports
        case .contradicts: self = .contradicts
        case .dependsOn: self = .dependsOn
        }
    }
}

enum CompanionGraphEvidenceStage: String, Sendable {
    case prepared, dispatched, checked, ownerReviewed, correction, withdrawn, historical, unknown, adaptation

    var title: String {
        switch self {
        case .prepared: "Prepared"
        case .dispatched: "Dispatched"
        case .checked: "Mechanical checks"
        case .ownerReviewed: "Owner review"
        case .correction: "Correction retained"
        case .withdrawn: "Withdrawn"
        case .historical: "Recorded version"
        case .unknown: "Evidence unavailable"
        case .adaptation: "Hampton controller receipt"
        }
    }

    var symbol: String {
        switch self {
        case .prepared: "doc.badge.clock"
        case .dispatched: "arrow.up.right.circle"
        case .checked: "checklist"
        case .ownerReviewed: "person.crop.circle.badge.checkmark"
        case .correction: "arrow.uturn.backward.circle"
        case .withdrawn: "minus.circle"
        case .historical: "clock.arrow.circlepath"
        case .unknown: "questionmark.diamond"
        case .adaptation: "slider.horizontal.3"
        }
    }
}

struct CompanionGraphEvidence: Identifiable, Equatable, Sendable {
    let id: String
    let stage: CompanionGraphEvidenceStage
    let summary: String
    var reference: String? = nil
    var relatedNodeID: String? = nil
}
