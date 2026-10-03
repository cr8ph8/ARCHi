import Foundation

@MainActor
extension CompanionStore {
    /// The user explicitly saves the editable instruction, whether written by
    /// hand or drafted locally. The reviewed page remains source provenance;
    /// neither saving nor generating a candidate establishes its usefulness.
    @discardableResult
    func keepKnowledgeProcedure(page: KnowledgePage, title: String, instruction: String,
                                requirements: DocumentWorkRequirements,
                                onSaved: ((DocumentProcedureUse) -> Void)? = nil) -> Bool {
        guard canKeepDocumentProcedure, !hasOpenKnowledgeDraft,
              documentWork.isCurrentOnDisk, knowledgeDependenciesAreCurrent([page.binding]) else {
            knowledgePageMessage = "Review the current page and finish any open work before saving a method."
            return false
        }
        do {
            let saved = try documentProcedures.keepCandidate(from: page, title: title, instruction: instruction,
                requirements: requirements, knowledgeIsCurrent: { knowledgeDependenciesAreCurrent([$0]) })
            knowledgePageMessage = "Candidate saved in Document methods. Choose it for a selected passage to try it locally; no work was sent or credited."
            onSaved?(saved.binding)
            return true
        } catch {
            knowledgePageMessage = "Candidate was not saved: \(error.localizedDescription)"
            return false
        }
    }

    var preparedDocumentProcedureKnowledge: KnowledgePageBinding? {
        preparedDocumentProcedure.flatMap { documentProcedures.procedure(matching: $0)?.knowledgeOrigin }
    }

    /// This assesses current source support, separately from historical feedback
    /// or counterexamples. No record or token cost is erased on withdrawal.
    func documentProcedureKnowledgeUnavailable(use: DocumentProcedureUse) -> Bool {
        guard documentProcedures.loadError == nil, documentProcedures.isCurrentOnDisk,
              let method = documentProcedures.procedure(matching: use) else { return true }
        guard let origin = method.knowledgeOrigin else { return false }
        return !knowledgeDependenciesAreCurrent([origin])
    }
}
