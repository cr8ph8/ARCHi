import Foundation

extension CompanionStore {
    /// Reads only current, matching kept lessons. Polarity never participates in
    /// retrieval eligibility. A method revision requires a new explicit relation.
    func documentMethodMemoryInfluence(_ procedure: DocumentProcedure) -> ContextualMemoryInfluence.Evaluation? {
        guard procedure.matches(requirements: documentRequirements),
              documentProcedureUnavailable(procedure.binding) == nil else { return nil }
        let targetID = LessonMemoryInfluence.targetID(for: procedure.binding)
        let targetRelations = memoryInfluences.filter { $0.procedure == procedure.binding }
        guard !targetRelations.isEmpty else {
            return try? ContextualMemoryInfluence.evaluate(inputs: [],
                scope: LessonMemoryInfluence.scope, targetID: targetID)
        }
        let snapshots = matchingLessons(question: prompt, taskScope: .passageRevision)
        var seenOrigins = Set<String>()
        var inputs: [ContextualMemoryInfluence.Input] = []
        // Preserve the existing retained order when several lessons came from
        // one source/request. Copies do not become independent evidence votes.
        for snapshot in snapshots {
            guard let reference = EvolutionLessonUse.make(snapshot: snapshot),
                  let relation = targetRelations.first(where: { $0.source == reference }),
                  let lesson = currentKeptLesson(matching: snapshot) else { continue }
            let originID = Self.memoryInfluenceOriginID(for: lesson)
            guard seenOrigins.insert(originID).inserted else { continue }
            inputs.append(.init(sourceID: snapshot.id, sourceRevision: snapshot.revision,
                sourceDigest: reference.snapshotDigest, originID: originID,
                assessment: relation.assessment, contextMatch: 1, eligible: true))
        }
        return try? ContextualMemoryInfluence.evaluate(inputs: inputs,
            scope: LessonMemoryInfluence.scope, targetID: targetID)
    }

    private static func memoryInfluenceOriginID(for lesson: KeptLesson) -> String {
        if let source = lesson.source { return "source:" + source.digest }
        if let origin = lesson.origin { return "request:" + origin.requestID.lowercased() }
        return "lesson:" + lesson.id.lowercased()
    }

    /// Resource evidence supplies the stable baseline. Signed influence refines
    /// only whole cohorts with equal reviewed outcome quality; unknown history
    /// and unavailable methods cannot be promoted into an eligible cohort.
    func refineDocumentMethodOrderWithMemory(_ ordered: [DocumentProcedure],
        outcomes: [DocumentProcedureUse: HamptonMethodOutcomes]) -> [DocumentProcedure] {
        guard !memoryInfluences.isEmpty else { return ordered }
        let scores = Dictionary(uniqueKeysWithValues: ordered.compactMap { method in
            documentMethodMemoryInfluence(method).map { (method.binding, $0.influence) }
        })
        var result = ordered
        var start = 0
        while start < ordered.count {
            guard let quality = outcomes[ordered[start].binding], scores[ordered[start].binding] != nil else {
                start += 1
                continue
            }
            var end = start + 1
            while end < ordered.count, let next = outcomes[ordered[end].binding],
                  scores[ordered[end].binding] != nil,
                  !HamptonMethodOutcomes.rankBefore(lhs: quality, rhs: next),
                  !HamptonMethodOutcomes.rankBefore(lhs: next, rhs: quality) { end += 1 }
            let ranked = ordered[start..<end].enumerated().sorted { left, right in
                let a = scores[left.element.binding] ?? 0
                let b = scores[right.element.binding] ?? 0
                return a == b ? left.offset < right.offset : a > b
            }.map(\.element)
            result.replaceSubrange(start..<end, with: ranked)
            start = end
        }
        return result
    }
}
