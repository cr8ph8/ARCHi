import SwiftUI

/// A visit-only doorway to existing journal reviews, including ordinary edits
/// that have no saved method. Opening it neither restores nor rates any work.
@MainActor
struct DocumentReviewQueueView: View {
    @ObservedObject var store: CompanionStore
    @State private var showAll = false
    @State private var selection: DocumentReviewPresentation?
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let queue = store.documentReviewQueue {
                if queue.records.isEmpty && queue.blockedCount == 0 {
                    Label("No earlier edits awaiting review", systemImage: "checklist")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("document.review-queue.empty")
                } else {
                    Label("Applied work to review · \(queue.records.count)", systemImage: "checkmark.bubble")
                        .fontWeight(.medium)
                    Text("These earlier edits have no saved review. Review a result only when you can verify it from your work.")
                        .foregroundStyle(.secondary)
                    ForEach(showAll ? queue.records : Array(queue.records.prefix(3))) { record in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(title(for: record)).fontWeight(.medium)
                                Text("\(record.provider) · \(record.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(record.requestID.prefix(8))")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Review") {
                                // The list can outlive an external journal write.
                                guard store.documentReviewQueue?.records.contains(record) == true else {
                                    notice = "The history changed. Reopen or resolve the history notice before reviewing this edit."
                                    return
                                }
                                notice = nil
                                selection = DocumentReviewPresentation(recordID: record.id,
                                    journalOwner: ObjectIdentifier(store.documentWork))
                            }
                            .accessibilityIdentifier("document.review-queue.open.\(record.id)")
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .contain)
                    }
                    if queue.records.count > 3 {
                        Button(showAll ? "Show fewer" : "Show all \(queue.records.count) reviews") { showAll.toggle() }
                            .accessibilityIdentifier("document.review-queue.show-all")
                    }
                    if queue.blockedCount > 0 {
                        Text("\(queue.blockedCount) other applied edits need their source support restored before a new review. Their receipts remain in Document work history.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("document.review-queue.blocked")
                    }
                }
            } else {
                Text("The review queue is unavailable while work is running, a receipt needs saving, or history needs recovery. Earlier records remain in Document work history.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("document.review-queue.unavailable")
            }
            if let notice { Text(notice).foregroundStyle(.secondary) }
        }
        .font(.caption)
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("document.review-queue")
        .sheet(item: $selection) { item in
            DocumentHistoricalReviewSheet(store: store, presentation: item) { selection = nil }
        }
        .onChange(of: ObjectIdentifier(store.documentWork)) { _, _ in selection = nil; showAll = false; notice = nil }
        .onChange(of: store.activeQiMon) { _, _ in selection = nil; showAll = false; notice = nil }
        .onChange(of: store.section) { _, _ in selection = nil }
    }

    private func title(for record: DocumentWorkRecord) -> String {
        guard let use = record.procedureUse else { return "Passage edit" }
        let title = store.documentProcedures.procedure(matching: use)?.title ?? "Saved method"
        return "\(title) · v\(use.revision)"
    }
}

private struct DocumentReviewPresentation: Identifiable {
    let id = UUID()
    let recordID: String
    let journalOwner: ObjectIdentifier
}

@MainActor
private struct DocumentHistoricalReviewSheet: View {
    @ObservedObject var store: CompanionStore
    let presentation: DocumentReviewPresentation
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review an earlier edit").font(.headline)
            if presentation.journalOwner == ObjectIdentifier(store.documentWork),
               store.documentReviewQueue != nil,
               let record = store.documentWork.records.first(where: { $0.id == presentation.recordID }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(record.provider) · \(record.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.subheadline)
                        Text("This receipt records a past edit. Document and reply text were not kept here, and opening this review does not restore them. Only rate the result if you can verify it from your own work.")
                            .foregroundStyle(.secondary)
                        Text(record.detail).foregroundStyle(.secondary)
                        DisclosureGroup("Receipt details") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Request: \(record.requestID)")
                                Text("Source digest: \(record.sourceDigest)")
                                if let use = record.procedureUse {
                                    Text("Method v\(use.revision): \(store.documentProcedures.procedure(matching: use)?.title ?? use.id)")
                                }
                                Text("\(record.checks.filter(\.passed).count) of \(record.checks.count) recorded mechanical checks passed. These do not establish usefulness.")
                            }.textSelection(.enabled).font(.caption2)
                        }
                        if store.canReviewDocument(record) || store.canManageDocumentFeedback(record) {
                            DocumentFeedbackControls(store: store, record: record)
                            // Keep the sheet open after rating so the existing
                            // method and correction actions remain reachable.
                            DocumentMethodFollowThroughView(store: store, record: record)
                        } else {
                            Text("This result is no longer available for review. Its source support or operation state changed.")
                                .foregroundStyle(.orange)
                        }
                        if let message = store.documentWorkMessage {
                            Text(message).foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 440)
            } else {
                Text("The profile or history changed, or work is in progress. Close this review and reopen it from the current queue.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Done", action: dismiss).keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("document.review-queue.done")
            }
        }
        .padding(20)
        .frame(width: 540)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("document.review-queue.sheet")
    }
}
