import Foundation
import SwiftUI

struct DocumentReadingPreview: Equatable {
    let plan: DocumentReadingPlan
    let control: HamptonQ2EDecision
    let sourceRevision: UInt64
}

extension CompanionStore {
    /// A view of the existing task/outcome journal. Unknown replies and generic
    /// usefulness never acquire a section-retrieval judgment by implication.
    func prepareReading(question: String, text: String, selection: DocumentSelection?) -> DocumentReadingPreview? {
        guard let initial = DocumentReadingPlan.make(text: text, question: question,
            selection: selection, lane: .expand, references: currentReadingReferences) else { return nil }
        guard currentReadingReferences.count == selectedReadingSourceIDs.count,
              readingReferencesAreCurrent(currentReadingReferences) else { return nil }
        // Preparing is an explicit local action. Refresh the owner once here;
        // the journal rechecks the frozen projection under its dispatch lock.
        do { try tokenSteward.refresh() } catch {
            documentReadingMessage = "The reading history could not be loaded. Nothing was sent."
            return nil
        }
        let evidence = HamptonReadingOutcomeAdapter.project(tasks: tokenSteward.tasks, sourceDigest: initial.sourceDigest)
        guard evidence.isValid, evidence.reconciliationIssue == nil else {
            documentReadingMessage = "The reading history needs review before its feedback can guide another answer. Nothing was sent."
            return nil
        }
        let previous = tokenSteward.tasks.first {
            $0.id == evidence.bindings.first?.taskID
        }?.documentReading?.control
        let control = HamptonQ2EController.decide(domain: "document-reading", contextID: initial.sourceDigest,
            signals: HamptonQ2ESignals(observations: evidence.observations, retainedSupport: evidence.support,
                contradictions: evidence.corrections, unchangedSteps: 0,
                availableAlternatives: min(initial.totalSections, 4096), remainingBudget: 1, totalBudget: 1,
                prerequisitesSatisfied: profileRecoveryBlock == nil && tokenSteward.loadError == nil,
                strategyResults: evidence.strategyResults), previous: previous, readingEvidence: evidence)
        guard control.isValid, control.lane != .stop else { return nil }
        let preferred = evidence.preferredSectionIDs(for: initial.questionDigest)
        guard let plan = DocumentReadingPlan.make(text: text, question: question, selection: selection,
            lane: control.lane, preferredSectionIDs: preferred, references: currentReadingReferences) else { return nil }
        return DocumentReadingPreview(plan: plan, control: control, sourceRevision: sourceRevision)
    }

    var currentReadingPreview: DocumentReadingPreview? {
        guard let preview = documentReadingPreview, preview.sourceRevision == sourceRevision,
              !requestsRevision, sourceName != nil,
              preview.control.readingEvidence == HamptonReadingOutcomeAdapter.project(
                tasks: tokenSteward.tasks, sourceDigest: preview.plan.sourceDigest),
              readingReferencesAreCurrent(preview.plan.references),
              preview.plan.matches(text: sharedText, question: prompt, selection: textSelection, references: currentReadingReferences) else { return nil }
        return preview
    }

    func previewDocumentReading() {
        guard !isWorking, !isShuttingDown, sourceName != nil else { return }
        documentReadingMessage = nil
        documentReadingPreview = prepareReading(question: prompt, text: sharedText, selection: textSelection)
        if documentReadingMessage != nil { return }
        documentReadingMessage = documentReadingPreview == nil
            ? "Write a question and choose a smaller passage if needed. The reading context could not fit; nothing was sent."
            : "Passages prepared locally. Send captures the current source and question again."
    }

    func canReviewReading(_ receipt: AssistantLaneReceipt) -> Bool {
        guard !isShuttingDown, profileRecoveryBlock == nil, receipt.provider == .qwen,
              isCurrentReplyContext(receipt),
              receipt.state == .complete, let result = receipt.readingResult, result.kind == "ANSWER",
              let plan = receipt.documentReading, let lane = compareResults[.qwen],
              lane.state == .complete, lane.receipt?.requestID == receipt.requestID,
              LessonSource.digest(of: lane.text) == result.answerDigest,
              receipt.context.source == sourceRevision, plan.primarySourceDigest == LessonSource.digest(of: sharedText),
              plan.references == currentReadingReferences, readingReferencesAreCurrent(plan.references),
              let task = tokenSteward.tasks.first(where: { $0.id == receipt.requestID }),
              task.documentReading?.planDigest == plan.digest, task.documentReadingResult == result,
              task.lanes.contains(where: { $0.provider == AssistantProvider.qwen.name && $0.dispatched && $0.state == "complete" })
        else { return false }
        return tokenSteward.loadError == nil
    }

    func reviewReading(_ receipt: AssistantLaneReceipt, useful: Bool) {
        guard canReviewReading(receipt) else { return }
        do {
            try tokenSteward.recordDocumentReadingFeedback(requestID: receipt.requestID, useful: useful)
            if !useful { invalidateCorrectedReadingContinuation() }
            documentReadingPreview = nil
            documentReadingMessage = useful ? "Helpful reading recorded for this source." : "Correction recorded. Earlier generated answers were removed from follow-up context. The next reading will reconsider its passage choices."
        } catch { documentReadingMessage = error.localizedDescription }
    }
}

@MainActor
struct DocumentReadingTools: View {
    @ObservedObject var store: CompanionStore
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Read with context", systemImage: "text.book.closed").font(.caption.weight(.medium))
            Text("Ask about a document or meeting notes. ARCHi finds passages locally before the next Qwen reply.")
                .foregroundStyle(.secondary)
            ReadingSourceLibraryView(store: store)
            Button("Find relevant passages") { store.previewDocumentReading() }
                .disabled(store.isWorking || store.sourceName == nil || store.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("work.reading.prepare")
            if let preview = store.currentReadingPreview {
                Text(preview.control.lane.title)
                if let evidence = preview.control.readingEvidence {
                    Text("\(evidence.support) helpful · \(evidence.corrections) needing correction · \(evidence.observations - evidence.support - evidence.corrections) unreviewed. Your feedback guides the next passage choice for this source.")
                        .foregroundStyle(.secondary)
                }
                DocumentReadingSections(plan: preview.plan, citedIDs: nil)
            }
            if let message = store.documentReadingMessage { Text(message).foregroundStyle(.secondary) }
            Text(store.selectedReadingSourceIDs.isEmpty
                 ? "Local Qwen uses selected excerpts. An external route still uses the shared copy described by your route settings."
                 : "Selected kept copies stay local. Local Qwen uses bounded excerpts across these sources.")
                .foregroundStyle(.secondary)
        }.font(.caption2).padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(WorkspaceTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("work.reading.context")
    }
}

struct DocumentReadingSections: View {
    let plan: DocumentReadingPlan
    let citedIDs: [String]?
    var body: some View {
        DisclosureGroup("\(plan.sections.count) of \(plan.totalSections) source sections · \(plan.isPartial ? "partial context" : "full context")") {
            ForEach(plan.sections, id: \.id) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.sourceTitle + " · " + section.title + (citedIDs?.contains(section.id) == true ? " · cited" : " · prepared"))
                        .font(.caption.weight(.medium))
                    Text(section.text).font(.caption2).textSelection(.enabled)
                    Text("Source range \(section.location)–\(section.location + section.length) · \(section.sha256.prefix(10))")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }
            if plan.totalSources > 1 {
                Text("\(plan.totalSources) sources considered · \(plan.omittedSourceIDs.count) sources have no supplied passage.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text("Citations identify supplied text. They do not verify the answer. \(plan.isPartial ? "Other sections were not included in this reply." : "")")
                .font(.caption2).foregroundStyle(.secondary)
        }.accessibilityIdentifier("work.reading.sections")
    }
}

@MainActor
struct DocumentReadingFeedback: View {
    @ObservedObject var store: CompanionStore
    let provider: AssistantProvider
    var body: some View {
        if let receipt = store.compareResults[provider]?.receipt {
            VStack(alignment: .leading, spacing: 6) {
                AssistantSourceEvidenceView(receipt: receipt)
                if receipt.readingResult?.kind == "ANSWER" {
                    HStack {
                        Button("Helpful") { store.reviewReading(receipt, useful: true) }
                            .accessibilityIdentifier("work.reading.helpful")
                        Button("Needs correction") { store.reviewReading(receipt, useful: false) }
                            .accessibilityIdentifier("work.reading.correct")
                    }.disabled(!store.canReviewReading(receipt))
                    if let task = store.tokenSteward.tasks.first(where: { $0.id == receipt.requestID }),
                       let verdict = task.outcomes.last(where: { $0.kind == .userUseful && $0.evidenceID.hasPrefix("document-reading:") }) {
                        Text(verdict.value ? "You marked this reading helpful." : "You marked this reading for correction.")
                    }
                }
            }.font(.caption2).buttonStyle(.borderless)
        }
    }
}
