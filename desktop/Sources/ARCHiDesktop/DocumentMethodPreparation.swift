import Foundation

/// Visit-only preview. The owner identities prevent reuse across profile reloads;
/// the exact source, selection and draft prevent an older sheet overwriting work.
struct DocumentMethodPreview: Identifiable, Equatable {
    let id = UUID()
    let procedure: DocumentProcedure
    let originalPrompt: String
    let selection: DocumentSelection
    let sourceName: String?
    let sourceDigest: String
    let requirements: DocumentWorkRequirements
    let preparedMethod: DocumentProcedureUse?
    let companionOrigin: String?
    let methodOwner: ObjectIdentifier
    let historyOwner: ObjectIdentifier
    let sourceOwner: ObjectIdentifier
}

@MainActor
extension CompanionStore {
    /// Requirement/source availability comes before retrieval. Existing outcome
    /// and comparable-cost order is retained for equal word relevance.
    func findDocumentMethods(query: String) throws -> DocumentMethodSearchResult {
        guard !isShuttingDown, profileRecoveryBlock == nil,
              documentWork.isCurrentOnDisk, documentProcedures.isCurrentOnDisk else {
            throw DocumentProcedureError.invalid("Method history changed or needs recovery. Reopen it before finding methods.")
        }
        let eligible = orderedDocumentProcedures.filter {
            $0.matches(requirements: documentRequirements)
                && documentProcedureUnavailable($0.binding) == nil
        }
        return try DocumentMethodSearch.search(query: query, orderedEligibleMethods: eligible)
    }

    func previewDocumentMethod(_ binding: DocumentProcedureUse) -> DocumentMethodPreview? {
        guard let method = documentProcedures.procedure(matching: binding),
              canPrepareDocumentProcedure(method), pendingDocumentReceipt == nil,
              let selection = textSelection else { return nil }
        return DocumentMethodPreview(procedure: method, originalPrompt: prompt,
            selection: selection, sourceName: sourceName,
            sourceDigest: WorkingCopyEditReceipt.digest(sharedText),
            requirements: documentRequirements, preparedMethod: preparedDocumentProcedure,
            companionOrigin: activeQiMon?.originDigest,
            methodOwner: ObjectIdentifier(documentProcedures), historyOwner: ObjectIdentifier(documentWork),
            sourceOwner: ObjectIdentifier(readingSources))
    }

    func documentMethodPreviewIssue(_ preview: DocumentMethodPreview) -> String? {
        guard preview.methodOwner == ObjectIdentifier(documentProcedures),
              preview.historyOwner == ObjectIdentifier(documentWork),
              preview.sourceOwner == ObjectIdentifier(readingSources),
              preview.companionOrigin == activeQiMon?.originDigest else {
            return "The profile changed. Open a new method preview."
        }
        guard prompt.utf8.elementsEqual(preview.originalPrompt.utf8),
              preparedDocumentProcedure == preview.preparedMethod else {
            return "Your draft changed. Close this preview and review the current draft before choosing a method."
        }
        guard textSelection == preview.selection, sourceName == preview.sourceName,
              preview.selection.matches(text: sharedText, sourceRevision: sourceRevision),
              preview.sourceDigest == WorkingCopyEditReceipt.digest(sharedText),
              documentRequirements == preview.requirements else {
            return "The passage or revision checks changed. Open a new method preview."
        }
        if let reason = documentProcedureUnavailable(preview.procedure.binding) { return reason }
        guard pendingDocumentReceipt == nil, canPrepareDocumentProcedure(preview.procedure) else {
            return "Finish current work, then select a passage in Revise mode before choosing this method."
        }
        return nil
    }

    /// The one explicit replacement step. Opening, searching and cancelling the
    /// preview cannot change the draft, save a result, start a call or grant credit.
    @discardableResult
    func applyDocumentMethodPreview(_ preview: DocumentMethodPreview) -> Bool {
        guard documentMethodPreviewIssue(preview) == nil else { return false }
        return prepareDocumentProcedure(preview.procedure.binding)
    }
}
