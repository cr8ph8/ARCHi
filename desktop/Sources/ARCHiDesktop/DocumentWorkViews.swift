import SwiftUI

struct DocumentWorkCheckView: View {
    let verification: DocumentWorkVerification
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(verification.canApply ? "Ready for your review" : "A required check needs attention",
                  systemImage: verification.canApply ? "checkmark.shield" : "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
            ForEach(verification.checks) { check in
                Label(check.title, systemImage: check.passed ? "checkmark.circle" : "xmark.circle")
                    .foregroundStyle(check.passed ? Color.secondary : Color.orange)
            }
            Text("These are mechanical checks. Review meaning, facts and usefulness before Apply.")
                .foregroundStyle(.secondary)
        }.font(.caption2).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("document.revision-checks")
    }
}

@MainActor
struct DocumentWorkHistory: View {
    @ObservedObject var store: CompanionStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HamptonTaskWorkCard(store: store)
            if store.requestsRevision { HamptonDocumentControlView(store: store) }
            else { DocumentReadingTools(store: store) }
            DocumentProcedureLibraryView(store: store)
            if let error = store.documentWorkMessage ?? store.documentWork.loadError {
                Text(error).foregroundStyle(.secondary).font(.caption)
                    .accessibilityIdentifier("document.history-error")
            }
            if store.pendingDocumentReceipt != nil {
                Button("Retry saving document receipt") { store.retryDocumentHistorySave() }
                    .accessibilityIdentifier("document.retry-receipt")
            }
            if store.documentWork.records.isEmpty {
                Text("After Apply, review whether the change helped or needs correction. Your judgment can guide kept lessons and learning review.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .accessibilityIdentifier("document.feedback-introduction")
            }
            if !store.documentWork.records.isEmpty {
                DisclosureGroup("Document work history") {
                    Text("Keeps up to 64 request and action records on this Mac. Document and reply text are not retained here. Reviewed records and procedure uses stay retained; the 64-record limit can block new work. History cannot replay an edit.")
                        .font(.caption2).foregroundStyle(.secondary)
                    ForEach(store.documentWork.records) { record in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(record.state.rawValue.capitalized).font(.caption.weight(.semibold))
                                Spacer()
                                Text(record.updatedAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(record.detail).font(.caption2).foregroundStyle(.secondary)
                            if let control = record.q2eDecision {
                                Text("Approach: \(control.lane.title) · decision \(control.revision)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            DocumentFeedbackControls(store: store, record: record)
                            if let use = record.procedureUse {
                                Text("Procedure v\(use.revision) · \(store.documentProcedures.procedure(matching: use)?.title ?? use.id)")
                                    .font(.caption2).foregroundStyle(.secondary)
                                if record.procedureUseRejected == true {
                                    Text("Counterexample retained · this procedure version is unavailable for reuse.")
                                        .font(.caption2).foregroundStyle(.orange)
                                }
                            }
                            KeepDocumentProcedureView(store: store, record: record)
                            HStack {
                                Button("Usage") { _ = store.openDocumentUsage(taskID: record.requestID) }
                                Button("Activity map") { store.open(.nodeLab) }
                            }.font(.caption2).buttonStyle(.borderless)
                        }.padding(.vertical, 5)
                    }
                }.font(.caption).accessibilityIdentifier("document.history")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
