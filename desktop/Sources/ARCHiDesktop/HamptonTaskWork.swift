import SwiftUI

/// Read projections of the existing owners. No second memory or outcome store.
extension CompanionStore {
    var currentDocumentOutcomes: HamptonMethodOutcomes? {
        guard profileRecoveryBlock == nil, documentWork.isCurrentOnDisk else { return nil }
        return HamptonMethodOutcomes(records: documentWork.records.filter {
            $0.mustBeShorter == documentRequirements.mustBeShorter
                && $0.preserveNumbersAndLinks == documentRequirements.preserveNumbersAndLinks
        })
    }

    func outcomes(for procedure: DocumentProcedure) -> HamptonMethodOutcomes? {
        guard profileRecoveryBlock == nil, documentWork.isCurrentOnDisk else { return nil }
        return HamptonMethodOutcomes(procedure: procedure.binding, records: documentWork.records)
    }

    /// Prefer available methods for this requirement set, then observed helpful
    /// use. The bounded critic ranks suggestions only; selection stays explicit.
    var orderedDocumentProcedures: [DocumentProcedure] {
        let entries = documentProcedures.latestProcedures.enumerated().map { index, method in
            (index: index, method: method,
             matching: method.matches(requirements: documentRequirements) && documentProcedureUnavailable(method.binding) == nil,
             outcomes: outcomes(for: method))
        }
        return entries.sorted { lhs, rhs in
            if lhs.matching != rhs.matching { return lhs.matching }
            if lhs.matching, let left = lhs.outcomes, let right = rhs.outcomes {
                if HamptonMethodOutcomes.rankBefore(lhs: left, rhs: right) { return true }
                if HamptonMethodOutcomes.rankBefore(lhs: right, rhs: left) { return false }
            }
            return lhs.index < rhs.index
        }.map(\.method)
    }

    func beginLessonForCurrentTask() {
        guard !isShuttingDown else { return }
        guard lessonDraft == nil else { open(.memory); return }
        let scope = currentTaskScope
        beginLessonCorrection()
        lessonDraft?.taskScope = scope
    }
}

@MainActor
struct HamptonTaskWorkCard: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("For this work · \(store.currentTaskScope.title)", systemImage: "sparkle.magnifyingglass")
                .font(.caption.weight(.medium))
            if store.route == .codex {
                Text("Kept lessons stay on this Mac.").foregroundStyle(.secondary)
            } else {
                Text("\(store.nextReplyLessons.count) matching lesson(s) prepared for local Qwen.")
                    .foregroundStyle(.secondary)
            }
            Button("Teach this activity", systemImage: "bookmark") { store.beginLessonForCurrentTask() }
                .buttonStyle(.borderless).accessibilityIdentifier("task-context.teach")
            DisclosureGroup("Revision experience") {
                if let outcomes = store.currentDocumentOutcomes {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(outcomes.helpful) helpful · \(outcomes.needsCorrection) corrected or withdrawn · \(outcomes.awaitingReview) awaiting review")
                        Text("\(outcomes.attempts) recorded attempts · \(outcomes.undone) undone")
                        Text("Matches the current length and exact-token requirements. Each assistant attempt is counted separately. Saved methods use their own version’s outcomes for ordering.")
                            .foregroundStyle(.secondary)
                    }.padding(.top, 4)
                } else {
                    Text("History needs recovery before outcomes can be shown.").foregroundStyle(.secondary)
                }
            }.accessibilityIdentifier("task-context.outcomes")
        }
        .font(.caption2)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkspaceTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("task-context.card")
    }
}
