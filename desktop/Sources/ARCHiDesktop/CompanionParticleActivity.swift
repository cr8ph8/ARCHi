import Foundation

/// Disposable rings over existing records. Request references include provenance;
/// they do not assert that a model received every passage, cited it or learned it.
struct CompanionParticleActivity: Equatable {
    let preparedNodeIDs: Set<String>
    let requestNodeIDs: Set<String>
    static let empty = Self(preparedNodeIDs: [], requestNodeIDs: [])

    /// Resolve full targets, not a separately recreated graph key. In particular,
    /// page node IDs alone do not encode their digest, and source IDs alone omit
    /// both version and declared provenance.
    static func nodeIDs(in graph: CompanionGraphSnapshot, pages: [KnowledgePageBinding] = [],
                        sources: [ReadingSourceBinding] = [], methods: [DocumentProcedureUse] = []) -> Set<String> {
        Set(graph.nodes.compactMap { node in
            switch node.target {
            case let .knowledgePage(binding): pages.contains(binding) ? node.id : nil
            case let .readingSource(parent): sources.contains(where: parent.matches) ? node.id : nil
            case let .documentMethod(binding): methods.contains(binding) ? node.id : nil
            default: nil
            }
        })
    }
}

@MainActor
extension CompanionStore {
    /// Drawing reuses the bounded scene projection. Context, request receipts
    /// and method ownership still pass through their existing current checks;
    /// this never authorizes a selection, attachment or outcome admission.
    func desktopParticlePresentationActivity(in scene: CompanionParticleScene,
        atUptime now: Double = ProcessInfo.processInfo.systemUptime) -> CompanionParticleActivity {
        guard !isShuttingDown, profileRecoveryBlock == nil,
              scene.sessionID == liminalStructureSessionID,
              let current = desktopParticlePresentationScene(atUptime: now),
              scene.motionID == current.motionID else { return .empty }
        return particleActivity(in: current.graph, memoryNodeIDs: Set(current.graph.nodes.map(\.id)))
    }

    /// Reuses the native request/context owners without changing selection,
    /// attachments, source files, dispatch or reviewed development.
    func companionParticleActivity(in scene: CompanionParticleScene) -> CompanionParticleActivity {
        guard !isShuttingDown, profileRecoveryBlock == nil,
              let current = companionParticleScene(),
              scene.isCurrent(graph: current.graph, originDigest: current.originDigest,
                              sessionID: current.sessionID) else { return .empty }
        return particleActivity(in: current.graph, memoryNodeIDs: Set(current.graph.nodes.map(\.id)))
    }

    /// The map also belongs to profiles without a personal particle scene.
    /// Validate its captured scope and owner before projecting the same activity.
    func companionParticleActivity(in graph: CompanionGraphSnapshot, sessionID: String,
                                   memoryOnly: Bool) -> CompanionParticleActivity {
        guard !isShuttingDown, profileRecoveryBlock == nil,
              sessionID == liminalStructureSessionID else { return .empty }
        let current = memoryOnly ? memoryMapSnapshot() : companionGraphSnapshot()
        guard LiminalKnowledgeBindings.digest(graph) == LiminalKnowledgeBindings.digest(current) else { return .empty }
        let memoryNodeIDs = Set((memoryOnly ? current : memoryMapSnapshot()).nodes.map(\.id))
        return particleActivity(in: current, memoryNodeIDs: memoryNodeIDs)
    }

    private func particleActivity(in graph: CompanionGraphSnapshot, memoryNodeIDs: Set<String>) -> CompanionParticleActivity {
        // All activity also contains historical request-reference aliases. They
        // can share a binding with current memory without being a new occurrence
        // of the current request. Only the native memory anchors receive rings.
        var pages: [KnowledgePageBinding] = [], sources: [ReadingSourceBinding] = []
        if let context = currentKnowledgeContext {
            pages = context.bindings
            sources = context.readingSources
        } else if selectedKnowledgePages.isEmpty, !requestsRevision,
                  sourceName != nil, !sharedText.isEmpty {
            let references = currentReadingReferences
            if references.count == selectedReadingSourceIDs.count, readingReferencesAreCurrent(references) {
                sources = references.map(\.binding)
            }
        }
        let preparedMethod = preparedDocumentProcedure.flatMap { use -> DocumentProcedureUse? in
            preparedProcedureMatchesCurrentDraft(question: prompt) && particleMethodIsCurrent(use) ? use : nil
        }
        let prepared = CompanionParticleActivity.nodeIDs(in: graph, pages: pages, sources: sources,
            methods: preparedMethod.map { [$0] } ?? []).intersection(memoryNodeIDs)

        var requested: Set<String> = []
        if let receipt = currentParticleActivityReceipt {
            let record = documentRecord(requestID: receipt.requestID, provider: .qwen)
            let method = record?.procedureUse
            // An external method/history correction cannot keep an old approach
            // lit merely because its source-page bindings still match.
            if (record == nil || documentWork.isCurrentOnDisk),
               method.map(particleMethodIsCurrent) ?? true {
                requested = CompanionParticleActivity.nodeIDs(in: graph,
                    pages: receipt.knowledgeDependencies ?? [], sources: receipt.readingDependencies ?? [],
                    methods: method.map { [$0] } ?? []).intersection(memoryNodeIDs)
            }
        }
        return .init(preparedNodeIDs: prepared.subtracting(requested), requestNodeIDs: requested)
    }

    private func particleMethodIsCurrent(_ use: DocumentProcedureUse) -> Bool {
        documentProcedures.isCurrentOnDisk && documentWork.isCurrentOnDisk
            && documentProcedureUnavailable(use) == nil
    }
}
