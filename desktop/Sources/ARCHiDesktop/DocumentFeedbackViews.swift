import SwiftUI

@MainActor
struct DocumentFeedbackControls: View {
    @ObservedObject var store: CompanionStore
    let record: DocumentWorkRecord

    var body: some View {
        if store.canReviewDocument(record) || store.canManageDocumentFeedback(record) {
            VStack(alignment: .leading, spacing: 7) {
                Text(record.feedback.map { title($0.verdict) } ?? "Did this change help your work?")
                    .font(.caption.weight(.medium))
                if store.canReviewDocument(record) {
                    ViewThatFits(in: .horizontal) {
                        HStack { reviewButtons }
                        VStack(alignment: .leading) { reviewButtons }
                    }
                } else {
                    Text("The latest document operation is unverified. You can sync or withdraw your earlier review; new learning is unavailable.")
                        .foregroundStyle(.secondary)
                }
                if record.feedback != nil {
                    HStack {
                        Text(store.documentFeedbackUsageCurrent(record) ? "Review saved · Usage updated" : "Review saved · Usage needs sync")
                            .font(.caption2).foregroundStyle(.secondary)
                        if !store.documentFeedbackUsageCurrent(record) {
                            Button("Retry sync") { store.syncDocumentFeedback(id: record.id) }
                        }
                    }
                    Button("Withdraw review") { _ = store.reviewDocument(id: record.id, verdict: .withdrawn) }
                        .disabled(record.feedback?.verdict == .withdrawn)
                }
                if store.canReviewDocument(record), record.feedback?.verdict == .helpful {
                    Button("Add to learning review") { _ = store.addDocumentToLearningReview(id: record.id) }
                        .accessibilityIdentifier("document.learning.\(record.id)")
                    let lessons = store.documentReviewLessons(record)
                    if !lessons.isEmpty {
                        DisclosureGroup("Did a kept lesson help?") {
                            ForEach(lessons, id: \.modelID) { lesson in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(lesson.topic).fontWeight(.medium)
                                    Text(lesson.text).textSelection(.enabled)
                                    Button("This lesson helped") {
                                        _ = store.addDocumentToLearningReview(id: record.id, lesson: lesson)
                                    }
                                }.padding(.vertical, 5)
                            }
                        }
                    }
                    Button("Review and save evolution") { store.open(.evolution) }
                    Text("Learning review stays in this session until Save evolution. Your Seed and kept appearance stay the same.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else if store.canReviewDocument(record), record.feedback?.verdict == .needsCorrection {
                    Button("Write a correction to keep") { store.beginDocumentCorrection(id: record.id) }
                        .accessibilityIdentifier("document.correction.\(record.id)")
                    Text("Write the guidance yourself and choose when it applies. Keep saves it to local Memory.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }.font(.caption2).buttonStyle(.borderless)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("document.feedback.\(record.id)")
        } else if [.applied, .undone].contains(record.state), record.learning == nil {
            Text("Historical outcome · learning references were not captured for this record.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var reviewButtons: some View {
        Button("Helpful", systemImage: "hand.thumbsup") { _ = store.reviewDocument(id: record.id, verdict: .helpful) }
            .disabled(record.feedback?.verdict == .helpful)
            .accessibilityIdentifier("document.helpful.\(record.id)")
        Button("Needs correction", systemImage: "pencil") { _ = store.reviewDocument(id: record.id, verdict: .needsCorrection) }
            .disabled(record.feedback?.verdict == .needsCorrection)
            .accessibilityIdentifier("document.needs-correction.\(record.id)")
    }

    private func title(_ verdict: DocumentWorkFeedback.Verdict) -> String {
        switch verdict {
        case .helpful: "You marked this change helpful"
        case .needsCorrection: "You marked this change for correction"
        case .withdrawn: "You withdrew this review"
        }
    }
}
