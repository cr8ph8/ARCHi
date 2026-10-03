import Foundation
import SwiftUI

extension CompanionStore {
    /// Rebuild from retained evidence, rather than incrementing a second score
    /// store whenever SwiftUI reevaluates. Latest eight matching attempts bound
    /// the feedback window; withdrawn judgments never become positive evidence.
    var documentQ2EDecision: HamptonQ2EDecision {
        makeDocumentQ2EDecision()
    }

    /// A sibling provider lane is part of this pending task, not an observed
    /// historical outcome. Exclude it when rechecking a frozen Send decision.
    func makeDocumentQ2EDecision(excludingRequestID: String? = nil) -> HamptonQ2EDecision {
        let input = documentWork.records.filter { $0.requestID != excludingRequestID }
        let unavailable = Set(input.compactMap { record -> String? in
            guard let use = record.procedureUse, documentProcedureKnowledgeUnavailable(use: use) else { return nil }
            return record.id
        })
        let projection = HamptonQ2EOutcomeAdapter(records: input, requirements: documentRequirements,
            knowledgeUnavailableRecordIDs: unavailable)
        let records = projection.records
        let alternatives = documentProcedures.latestProcedures.filter {
            $0.matches(requirements: documentRequirements) && documentProcedureUnavailable($0.binding) == nil
        }.count + 1 // ordinary, checked revision remains an available approach
        let sourceID = WorkingCopyEditReceipt.digest(sharedText)
        let previous = records.compactMap(\.q2eDecision).first { $0.contextID == sourceID }
        let prerequisites = profileRecoveryBlock == nil && documentWork.isCurrentOnDisk
            && documentProcedures.loadError == nil && sourceName != nil
            && textSelection?.matches(text: sharedText, sourceRevision: sourceRevision) == true
            && pendingDocumentReceipt == nil
        return HamptonQ2EController.decide(domain: "document-revision", contextID: sourceID,
            signals: projection.signals(alternatives: alternatives, prerequisitesSatisfied: prerequisites),
            previous: previous, outcomeEvidence: projection.evidence)
    }

    /// Preparing is reversible and sends nothing. Send freezes the current
    /// decision, includes its fixed guidance only locally, and journals it before
    /// generation; later Apply/feedback changes the next projection.
    func prepareAdaptiveDocumentWork() {
        guard !isWorking, !isShuttingDown else { return }
        let decision = documentQ2EDecision
        guard decision.lane != .stop else { return }
        requestsRevision = true
        // A Helpful method under the same mechanical checks need not fit this
        // task. Only a method-specific preview may replace the user's draft.
        // Keep even a stale explicit binding visible: generic preparation must
        // not silently detach its source restrictions from the saved instruction.
        // The existing prepared-method UI offers an explicit Detach action.
        if preparedDocumentProcedure != nil { return }
        // Never overwrite a user's authored draft. The frozen local controller
        // guidance still adds the chosen approach to the next request.
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            switch decision.lane {
            case .repair:
                prompt = "Revise this passage with a fresh approach. Check the stated requirements carefully and propose a correction for my review."
            case .retain, .expand:
                prompt = "Revise this passage for clarity while preserving its meaning and following the stated requirements. Propose one version for my review."
            case .stop: break
            }
        }
    }
}

@MainActor
struct HamptonDocumentControlView: View {
    @ObservedObject var store: CompanionStore
    var body: some View {
        let decision = store.documentQ2EDecision
        VStack(alignment: .leading, spacing: 6) {
            Label("Next approach · \(decision.lane.title)", systemImage: "arrow.triangle.branch")
                .font(.caption.weight(.medium))
            Text(decision.lane == .stop
                 ? "Select a current passage and resolve any history recovery before preparing a revision."
                 : decision.reason).foregroundStyle(.secondary)
            if decision.lane == .retain {
                Text("Find a saved method for this task and review its instruction. Prepare next step keeps your current request; it does not choose a method for you.")
                    .foregroundStyle(.secondary)
            }
            Button("Prepare next step") { store.prepareAdaptiveDocumentWork() }
                .disabled(decision.lane == .stop || store.isWorking)
                .accessibilityIdentifier("work.q2e.prepare")
            DisclosureGroup("Why this approach") {
                Text("\(decision.signals.observations) recent matching attempts · \(decision.signals.retainedSupport) helpful · \(decision.signals.contradictions) needing correction")
                if let numerical = decision.numericalControl {
                    Text(numerical.steps.isEmpty
                         ? "Ready to adapt from reviewed approaches. Unreviewed replies do not change approach preferences."
                         : "Approach preferences reflect \(numerical.steps.count) attributed outcomes. Updating a review updates the next approach.")
                        .accessibilityIdentifier("work.q2e.adaptation")
                }
                Text("One proposed revision per Send. Your review, Apply and feedback guide the next approach. This does not train model weights.")
                    .foregroundStyle(.secondary)
            }.accessibilityIdentifier("work.q2e.reason")
        }.font(.caption2).padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WorkspaceTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}
