import Foundation

/// Stack R2 L07: a content-minimal projection of existing native evidence owners.
/// A recorded answer is generated material, not a verified assertion. Directed
/// dependencies let a later correction remove its future influence without
/// deleting the accounting record or rewriting a user's chosen companion body.
enum HamptonMemoryDependencies {
    static let version = "hampton-native-memory-dependencies/v1"

    struct ReadingDependency: Equatable, Sendable {
        let requestID: UUID
        let sourceDigest: String
        let answerDigest: String
        let reviewID: String
        let reviewRevision: Int
        let useful: Bool
    }

    /// The reading review namespace is independent of generic Useful feedback.
    /// A generic positive judgment cannot erase a specific reading correction.
    static func readings(tasks: [TokenStewardTask]) -> [ReadingDependency] {
        tasks.compactMap { task in
            guard let requestID = UUID(uuidString: task.id),
                  let trace = task.documentReading, let answer = task.documentReadingResult,
                  answer.kind == "ANSWER", DocumentReadingTrace.isDigest(trace.sourceDigest),
                  DocumentReadingTrace.isDigest(answer.answerDigest),
                  let review = task.outcomes.last(where: {
                      $0.kind == .userUseful && $0.evidenceID.hasPrefix(DocumentReadingTrace.feedbackEvidencePrefix)
                  }) else { return nil }
            return ReadingDependency(requestID: requestID, sourceDigest: trace.sourceDigest,
                answerDigest: answer.answerDigest, reviewID: review.evidenceID,
                reviewRevision: review.revision, useful: review.value)
        }
    }

    static func correctedReadings(tasks: [TokenStewardTask]) -> Set<UUID> {
        Set(readings(tasks: tasks).filter { !$0.useful }.map(\.requestID))
    }

    /// Traverse retained derivation edges. A descendant's positive review does
    /// not erase a correction to an answer that its reasoning consumed.
    static func invalidatedReadings(tasks: [TokenStewardTask]) -> Set<UUID> {
        descendants(of: correctedReadings(tasks: tasks), tasks: tasks)
    }

    /// Development credit is withdrawn durably. A later reading preference
    /// reversal cannot silently revive an older saved reward; use a fresh answer.
    static func withdrawnDevelopmentReadings(tasks: [TokenStewardTask]) -> Set<UUID> {
        let roots = Set(tasks.filter { task in
            task.outcomes.contains {
                $0.kind == .userUseful && !$0.value
                    && $0.evidenceID.hasPrefix(DocumentReadingTrace.feedbackEvidencePrefix)
            }
        }.compactMap { UUID(uuidString: $0.id) })
        return descendants(of: roots, tasks: tasks)
    }

    private static func descendants(of roots: Set<UUID>, tasks: [TokenStewardTask]) -> Set<UUID> {
        var invalid = roots
        var children: [UUID: Set<UUID>] = [:]
        for task in tasks {
            guard let child = UUID(uuidString: task.id) else { continue }
            for parent in task.documentReading?.conversationRequestIDs ?? [] {
                guard let id = UUID(uuidString: parent) else { continue }
                children[id, default: []].insert(child)
            }
        }
        var pending = Array(invalid)
        while let parent = pending.popLast() {
            for child in children[parent] ?? [] where invalid.insert(child).inserted {
                pending.append(child)
            }
        }
        return invalid
    }

    /// Parents must already be completed local readings earlier in the journal.
    /// This binds ownership and makes missing edges and cycles inadmissible.
    static func validParents(_ trace: DocumentReadingTrace, before requestID: String,
                             tasks: [TokenStewardTask]) -> Bool {
        guard let ids = trace.conversationRequestIDs else { return true }
        guard trace.isValid, let index = tasks.firstIndex(where: { $0.id == requestID }) else { return false }
        let eligible = Set(tasks.prefix(index).filter { task in
            task.documentReadingResult?.kind == "ANSWER" && task.lanes.contains {
                $0.provider == AssistantProvider.qwen.name && $0.dispatched && $0.state == "complete"
            }
        }.compactMap { UUID(uuidString: $0.id) })
        return Set(ids.compactMap(UUID.init(uuidString:))).isSubset(of: eligible)
    }

}
