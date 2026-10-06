import Foundation

/// A visit-only authoring context, not another memory or learning owner.
struct KnowledgeMapMethodSelection: Identifiable {
    let id = UUID()
    let page: KnowledgePage
    let sourceOwner: ObjectIdentifier
    let methodOwner: ObjectIdentifier
    let historyOwner: ObjectIdentifier
    let companionOrigin: String?
}

@MainActor
extension CompanionStore {
    func beginKnowledgeMapMethod(node: CompanionGraphNode) -> KnowledgeMapMethodSelection? {
        guard case .knowledgePage(let binding) = node.target,
              let page = readingSources.latestKnowledgePages.first(where: {
                  $0.binding == binding && KnowledgePageGraph.nodeID($0.binding) == node.id
              }) else { return nil }
        let selection = KnowledgeMapMethodSelection(page: page,
            sourceOwner: ObjectIdentifier(readingSources), methodOwner: ObjectIdentifier(documentProcedures),
            historyOwner: ObjectIdentifier(documentWork), companionOrigin: activeQiMon?.originDigest)
        return knowledgePageForMethodSelection(selection) == nil ? nil : selection
    }

    func knowledgePageForMethodSelection(_ selection: KnowledgeMapMethodSelection) -> KnowledgePage? {
        guard !isShuttingDown, profileRecoveryBlock == nil,
              selection.sourceOwner == ObjectIdentifier(readingSources),
              selection.methodOwner == ObjectIdentifier(documentProcedures),
              selection.historyOwner == ObjectIdentifier(documentWork),
              selection.companionOrigin == activeQiMon?.originDigest,
              documentProcedures.isCurrentOnDisk, documentWork.isCurrentOnDisk,
              selection.page.kind == .concept, selection.page.state == .reviewed,
              readingSources.latestKnowledgePages.contains(selection.page),
              knowledgeDependenciesAreCurrent([selection.page.binding]) else { return nil }
        return selection.page
    }

    /// Revalidate the captured owners and exact concept at Save, including when
    /// the sheet outlives a profile change or an external source correction.
    func keepKnowledgeMapMethod(_ selection: KnowledgeMapMethodSelection, title: String,
                                instruction: String, requirements: DocumentWorkRequirements) -> DocumentProcedureUse? {
        guard let page = knowledgePageForMethodSelection(selection) else {
            knowledgePageMessage = "This concept or its profile changed. Reopen the current concept before saving a method."
            return nil
        }
        var saved: DocumentProcedureUse?
        _ = keepKnowledgeProcedure(page: page, title: title, instruction: instruction,
            requirements: requirements, onSaved: { saved = $0 })
        return saved
    }
}
