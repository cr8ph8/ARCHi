import Foundation
import SwiftUI

extension CompanionStore {
    /// Rebuild from retained evidence, rather than incrementing a second score
    /// store whenever SwiftUI reevaluates. Latest eight matching attempts bound
    /// the feedback window; withdrawn judgments never become positive evidence.
    var documentQ2EDecision: HamptonQ2EDecision {
        let records = Array(documentWork.records.filter {
            $0.mustBeShorter == documentRequirements.mustBeShorter
                && $0.preserveNumbersAndLinks == documentRequirements.preserveNumbersAndLinks
        }.prefix(8))
        let outcomes = HamptonMethodOutcomes(records: records)
        let corrections = records.filter {
            ($0.state == .blocked && $0.checks.contains { !$0.passed }) || $0.procedureUseRejected == true
                || $0.feedback.map { $0.verdict != .helpful } == true
        }.count
        let alternatives = documentProcedures.latestProcedures.filter {
            $0.matches(requirements: documentRequirements) && documentProcedureUnavailable($0.binding) == nil
        }.count + 1 // ordinary, checked revision remains an available approach
        let sourceID = WorkingCopyEditReceipt.digest(sharedText)
        let previous = records.compactMap(\.q2eDecision).first { $0.contextID == sourceID }
        var strategyResults: [String: HamptonQ2EStrategyEvidence] = [:]
        for lane in [HamptonQ2ELane.retain, .expand, .repair] {
            let attributed = records.filter { $0.q2eDecision?.lane == lane }
            let measured = HamptonMethodOutcomes(records: attributed)
            let negative = attributed.filter {
                ($0.state == .blocked && $0.checks.contains { !$0.passed }) || $0.procedureUseRejected == true
                    || $0.feedback.map { $0.verdict != .helpful } == true
            }.count
            strategyResults[lane.rawValue] = HamptonQ2EStrategyEvidence(helpful: measured.helpful, corrections: negative)
        }
        let prerequisites = profileRecoveryBlock == nil && documentWork.isCurrentOnDisk
            && documentProcedures.loadError == nil && sourceName != nil
            && textSelection?.matches(text: sharedText, sourceRevision: sourceRevision) == true
            && pendingDocumentReceipt == nil
        return HamptonQ2EController.decide(domain: "document-revision", contextID: sourceID,
            signals: HamptonQ2ESignals(observations: outcomes.attempts,
                retainedSupport: outcomes.helpful, contradictions: corrections,
                unchangedSteps: 0, availableAlternatives: alternatives,
                remainingBudget: 1, totalBudget: 1, prerequisitesSatisfied: prerequisites,
                strategyResults: strategyResults), previous: previous)
    }

    /// Preparing is reversible and sends nothing. Send freezes the current
    /// decision, includes its fixed guidance only locally, and journals it before
    /// generation; later Apply/feedback changes the next projection.
    func prepareAdaptiveDocumentWork() {
        guard !isWorking, !isShuttingDown else { return }
        let decision = documentQ2EDecision
        guard decision.lane != .stop else { return }
        requestsRevision = true
        if decision.lane == .retain,
           let method = orderedDocumentProcedures.first(where: { canPrepareDocumentProcedure($0) }),
           (outcomes(for: method)?.helpful ?? 0) > 0,
           prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = prepareDocumentProcedure(method.binding)
            return
        }
        clearPreparedDocumentProcedure()
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
            Button("Prepare next step") { store.prepareAdaptiveDocumentWork() }
                .disabled(decision.lane == .stop || store.isWorking)
                .accessibilityIdentifier("work.q2e.prepare")
            DisclosureGroup("Why this approach") {
                Text("\(decision.signals.observations) recent matching attempts · \(decision.signals.retainedSupport) helpful · \(decision.signals.contradictions) needing correction")
                Text("One proposed revision per Send. Your review, Apply and feedback guide the next approach. This does not train model weights.")
                    .foregroundStyle(.secondary)
            }.accessibilityIdentifier("work.q2e.reason")
        }.font(.caption2).padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WorkspaceTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}
