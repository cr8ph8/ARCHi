import SwiftUI

/// Outcome review remains in the existing CompanionStore and feedback controls.
@MainActor
struct MethodLearningView: View {
    @ObservedObject var store: CompanionStore
    let procedure: DocumentProcedure
    var isHistorical = false

    private var identifier: String { "\(procedure.id).\(procedure.revision)" }
    private var history: MethodLearningHistory? {
        MethodLearningHistory(procedure: procedure.binding, records: store.documentWork.records,
            historyIsCurrent: store.outcomes(for: procedure) != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let history {
                let outcomes = history.outcomes
                Text("This version · \(outcomes.helpful) Helpful · \(outcomes.needsCorrection) needs correction or review withdrawn · \(outcomes.awaitingReview) awaiting review")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("document.method-outcomes.\(identifier)")
                if outcomes.awaitingReview > 0 {
                    Text("Review the applied outcomes below when you can verify whether they helped your work.")
                        .foregroundStyle(.secondary)
                }
                if !history.records.isEmpty {
                    DisclosureGroup("Review uses of v\(procedure.revision) (\(history.records.count))") {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Each assistant attempt is separate. This history keeps checks and review references, not the passage or reply. Only review a result you can verify from your work.")
                                .foregroundStyle(.secondary)
                            ForEach(history.records) { record in
                                MethodLearningRecordView(store: store, record: record)
                            }
                        }.padding(.top, 5)
                    }
                    .accessibilityIdentifier("document.method-history.\(identifier)")
                }
            } else {
                Text("Outcome history is unavailable. Resolve conflicting records or profile recovery before reviewing this version.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("document.method-history-unavailable.\(identifier)")
            }
            Text(reuseGuidance.text)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("document.method-next-step.\(identifier)")
        }.font(.caption2)
    }

    private var reuseGuidance: MethodLearningReuseGuidance {
        .init(unavailableReason: store.documentProcedureUnavailable(procedure.binding),
              isHistorical: isHistorical, isWorking: store.isWorking,
              requestsRevision: store.requestsRevision,
              hasCurrentSelection: store.textSelection?.matches(text: store.sharedText, sourceRevision: store.sourceRevision) == true,
              requirementsMatch: procedure.matches(requirements: store.documentRequirements),
              canPrepare: store.canPrepareDocumentProcedure(procedure))
    }
}

@MainActor
private struct MethodLearningRecordView: View {
    @ObservedObject var store: CompanionStore
    let record: DocumentWorkRecord

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Text(record.detail).foregroundStyle(.secondary)
                if record.procedureUseRejected == true {
                    Text("This use keeps the version unavailable for reuse, even if its review later changes. A corrective result can support a new version through Edit method.")
                        .foregroundStyle(.secondary)
                }
                if store.canReviewDocument(record) || store.canManageDocumentFeedback(record) {
                    DocumentFeedbackControls(store: store, record: record)
                } else {
                    Text("No review action is available for this record. A checked proposal alone is not an applied outcome.")
                        .foregroundStyle(.secondary)
                }
                Button("Usage for this attempt") { _ = store.openDocumentUsage(taskID: record.requestID) }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("document.method-use-usage.\(record.id)")
            }.padding(.top, 4)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(MethodLearningHistory.disposition(of: record).title).fontWeight(.medium)
                Text("\(record.provider) · \(record.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(record.requestID.prefix(8))")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("document.method-use.\(record.id)")
    }
}
