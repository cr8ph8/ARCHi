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
            selection: selection, lane: .expand) else { return nil }
        let records = Array(tokenSteward.tasks.filter {
            $0.documentReading?.sourceDigest == initial.sourceDigest
                && $0.documentReadingResult?.kind == "ANSWER"
                && $0.lanes.contains { $0.provider == AssistantProvider.qwen.name && $0.dispatched && $0.state == "complete" }
        }.prefix(8))
        func verdict(_ task: TokenStewardTask) -> Bool? {
            task.outcomes.last { $0.kind == .userUseful && $0.evidenceID.hasPrefix("document-reading:") }?.value
        }
        let positive = records.filter { verdict($0) == true }
        let negative = records.filter { verdict($0) == false }
        var strategies: [String: HamptonQ2EStrategyEvidence] = [:]
        for lane in [HamptonQ2ELane.retain, .expand, .repair] {
            strategies[lane.rawValue] = HamptonQ2EStrategyEvidence(
                helpful: positive.filter { $0.documentReading?.control.lane == lane }.count,
                corrections: negative.filter { $0.documentReading?.control.lane == lane }.count)
        }
        let control = HamptonQ2EController.decide(domain: "document-reading", contextID: initial.sourceDigest,
            signals: HamptonQ2ESignals(observations: records.count, retainedSupport: positive.count,
                contradictions: negative.count, unchangedSteps: 0,
                availableAlternatives: min(initial.totalSections, 4096), remainingBudget: 1, totalBudget: 1,
                prerequisitesSatisfied: profileRecoveryBlock == nil && tokenSteward.loadError == nil,
                strategyResults: strategies), previous: records.first?.documentReading?.control)
        let preferred = positive.first { $0.documentReading?.questionDigest == initial.questionDigest }?
            .documentReading?.sectionIDs ?? []
        guard let plan = DocumentReadingPlan.make(text: text, question: question, selection: selection,
            lane: control.lane, preferredSectionIDs: preferred) else { return nil }
        return DocumentReadingPreview(plan: plan, control: control, sourceRevision: sourceRevision)
    }

    var currentReadingPreview: DocumentReadingPreview? {
        guard let preview = documentReadingPreview, preview.sourceRevision == sourceRevision,
              !requestsRevision, sourceName != nil,
              preview.plan.matches(text: sharedText, question: prompt, selection: textSelection) else { return nil }
        return preview
    }

    func previewDocumentReading() {
        guard !isWorking, !isShuttingDown, sourceName != nil else { return }
        documentReadingPreview = prepareReading(question: prompt, text: sharedText, selection: textSelection)
        documentReadingMessage = documentReadingPreview == nil
            ? "Write a question and choose a smaller passage if needed. The reading context could not fit; nothing was sent."
            : "Passages prepared locally. Send captures the current source and question again."
    }

    func canReviewReading(_ receipt: AssistantLaneReceipt) -> Bool {
        guard !isShuttingDown, profileRecoveryBlock == nil, receipt.provider == .qwen,
              isCurrent(receipt.context, requireVisible: false),
              receipt.state == .complete, let result = receipt.readingResult, result.kind == "ANSWER",
              let plan = receipt.documentReading, let lane = compareResults[.qwen],
              lane.state == .complete, lane.receipt?.requestID == receipt.requestID,
              LessonSource.digest(of: lane.text) == result.answerDigest,
              receipt.context.source == sourceRevision, plan.sourceDigest == LessonSource.digest(of: sharedText),
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
            documentReadingPreview = nil
            documentReadingMessage = useful ? "Helpful reading recorded for this source." : "Correction recorded. The next reading will reconsider its passage choices."
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
            Button("Find relevant passages") { store.previewDocumentReading() }
                .disabled(store.isWorking || store.sourceName == nil || store.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("work.reading.prepare")
            if let preview = store.currentReadingPreview {
                Text(preview.control.lane.title)
                DocumentReadingSections(plan: preview.plan, citedIDs: nil)
            }
            if let message = store.documentReadingMessage { Text(message).foregroundStyle(.secondary) }
            Text("Local Qwen uses selected excerpts. An external route still uses the shared copy described by your route settings.")
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
                    Text(section.title + (citedIDs?.contains(section.id) == true ? " · cited" : " · supplied"))
                        .font(.caption.weight(.medium))
                    Text(section.text).font(.caption2).textSelection(.enabled)
                    Text("Source range \(section.location)–\(section.location + section.length) · \(section.sha256.prefix(10))")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
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
        if let receipt = store.compareResults[provider]?.receipt, let plan = receipt.documentReading {
            VStack(alignment: .leading, spacing: 6) {
                DocumentReadingSections(plan: plan, citedIDs: receipt.readingResult?.citedSectionIDs)
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
