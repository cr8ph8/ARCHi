import Foundation
import CryptoKit

/// Derived navigation over the existing source library. Edges record attribution
/// and reviewed user declarations, not certified entailment or development.
@MainActor
enum KnowledgePageGraph {
    /// The page owner admits a unique content binding for each retained revision.
    /// Reusers must still resolve the exact binding before choosing this node.
    static func nodeID(_ binding: KnowledgePageBinding) -> String {
        key(["knowledge", binding.id, String(binding.revision)])
    }

    static func append(to base: CompanionGraphSnapshot, library: ReadingSourceLibrary) -> CompanionGraphSnapshot {
        var nodes = base.nodes, edges = base.edges, truncated = base.truncatedCount
        var ids = Set(nodes.map(\.id)), edgeIDs = Set(edges.map(\.id))
        let sources = library.sources
        let sourcesAreCurrent = library.isCurrentOnDisk
        func add(_ node: CompanionGraphNode) -> Bool {
            if ids.contains(node.id) { return true }
            guard nodes.count < CompanionGraph.maximumNodes else { truncated += 1; return false }
            nodes.append(node); ids.insert(node.id); return true
        }
        func link(_ from: String, _ to: String, _ label: String,
                  relationship: CompanionGraphRelationship = .recorded,
                  rationale: String? = nil, reference: String? = nil) {
            // Separate reviewed declarations retain their own identity and reason.
            let id = reference ?? key(["edge", from, to, label])
            guard !edgeIDs.contains(id) else { return }
            guard ids.contains(from), ids.contains(to), edges.count < CompanionGraph.maximumEdges else {
                truncated += 1; return
            }
            edges.append(.init(id: id, source: from, target: to, label: label,
                relationship: relationship, rationale: rationale, reference: reference)); edgeIDs.insert(id)
        }
        func addSource(_ identity: ReadingSourceParent, provenance: ReadingSourceProvenanceReceipt? = nil) -> String? {
            let id = sourceKey(identity)
            let retained = sources.first { identity.matches($0.binding) }
            let declaration = retained?.binding.provenance ?? provenance
            let issue: String?
            if !sourcesAreCurrent {
                issue = "The source library changed or needs recovery. Reopen before using this source."
            } else if let retained {
                issue = ReadingSourceLineage.availability(of: retained.binding, in: sources)
            } else {
                issue = "This exact source version changed or is no longer kept. A newer copy does not replace this reference."
            }
            let details: [CompanionGraphDetail] = [
                .init(label: "Source ID", value: identity.id),
                .init(label: "Revision", value: String(identity.revision)),
                .init(label: "Digest", value: identity.digest),
                .init(label: "Provenance digest", value: identity.provenanceDigest ?? "No declaration retained"),
                .init(label: "Declared origin", value: declaration?.origin.title ?? "Unknown"),
                .init(label: "Acquisition", value: declaration?.acquisition.title ?? "Unknown"),
                .init(label: "Parent copies", value: declaration.map { "\($0.parents.count) declared" } ?? "No parent metadata in this reference"),
                .init(label: "State", value: issue ?? "Exact retained source version and its derivation parents are current."),
                .init(label: "Meaning", value: "Origin and derivation are user declarations, not verified authorship or factual support.")]
            guard add(.init(id: id, title: retained?.title ?? "Unavailable source version",
                subtitle: "Source v\(identity.revision)", kind: .source,
                status: issue == nil ? "Retained source" : "Needs source review",
                details: details, target: .memory,
                presentationState: issue == nil ? .recorded : .unavailable)) else { return nil }
            return id
        }
        func addSource(_ binding: ReadingSourceBinding) -> String? {
            guard let id = addSource(.init(binding: binding), provenance: binding.provenance) else { return nil }
            for parent in binding.provenance?.parents ?? [] {
                guard let parentID = addSource(parent) else { continue }
                link(id, parentID, "derived from", relationship: .derivedFrom)
            }
            return id
        }
        for page in library.latestKnowledgePages.sorted(by: { $0.id < $1.id }) {
            let id = nodeID(page.binding)
            let issue = library.availability(of: page)
            let stale = !page.anchors.allSatisfy { library.quote(for: $0) != nil }
            let status = page.state == .withdrawn ? "Withdrawn" : stale ? "Needs source review" : issue == nil ? "Reviewed · current sources" : page.state.title
            let presentation: CompanionGraphPresentationState = page.state == .withdrawn ? .withdrawn
                : page.state == .draft ? .candidate : (stale || issue != nil) ? .needsReview : .reviewed
            guard add(.init(id: id, title: page.title, subtitle: "\(page.kind.title) · v\(page.revision)",
                kind: .knowledge, status: status,
                details: [.init(label: "Your note", value: page.body),
                    .init(label: "Page review", value: page.state.title),
                    .init(label: "Availability", value: issue ?? "Source passages are current. User review is not factual certification."),
                    .init(label: "Page ID", value: page.id),
                    .init(label: "Revision", value: String(page.revision)),
                    .init(label: "Digest", value: page.binding.digest),
                    .init(label: "Meaning", value: "This authored page is not automatically supplied to a model or counted as learning.")],
                target: .knowledgePage(id: page.id), presentationState: presentation)) else { continue }
            if ids.contains("companion-archi") { link("companion-archi", id, "authored memory") }
            for anchor in page.anchors {
                guard let sourceID = addSource(anchor.source) else { continue }
                link(id, sourceID, "source passage", relationship: .sourcePassage)
            }
        }
        // Only exact current reviewed connections enter the graph. Old endpoints
        // remain inspectable in page history, never silently rebound to new pages.
        for connection in library.latestKnowledgeLinks.sorted(by: { $0.identity < $1.identity }) {
            guard library.availability(of: connection) == nil else { continue }
            link(nodeID(connection.from), nodeID(connection.to),
                 "declared " + connection.kind.title.lowercased(),
                 relationship: .init(declaration: connection.kind),
                 rationale: connection.rationale, reference: connection.identity)
        }
        // Kept sources have their own identity even before a page cites them.
        // Reuse exactly the same version key as passage and parent references.
        for source in sources.sorted(by: { sourceKey(.init(binding: $0.binding)) < sourceKey(.init(binding: $1.binding)) }) {
            guard let sourceID = addSource(source.binding) else { continue }
            if ids.contains("companion-archi") { link("companion-archi", sourceID, "kept source") }
        }
        return .init(nodes: nodes, edges: edges, truncatedCount: truncated)
    }

    private static func sourceKey(_ identity: ReadingSourceParent) -> String {
        key(["knowledge-source", identity.id, String(identity.revision), identity.digest, identity.provenanceDigest ?? ""])
    }

    private static func key(_ parts: [String]) -> String {
        let bytes = Data(parts.map { "\($0.utf8.count):\($0)" }.joined().utf8)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
