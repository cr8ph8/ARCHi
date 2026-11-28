import Foundation

/// Reads only the current bounded projection, including its existing redactions.
enum CompanionGraphRetrieval {
    enum Mode: String, CaseIterable { case full, keyword, linked }

    struct Hit {
        let node: CompanionGraphNode
        let via: CompanionGraphEdge?
    }

    static func fields(_ node: CompanionGraphNode) -> [String] {
        [node.title, node.subtitle, node.status, node.kind.title] + node.details.flatMap { [$0.label, $0.value] }
    }

    private static func terms(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    /// Both compact arms have the same maximum number of records. Linked search
    /// reserves room for one-hop evidence, then backfills unused slots by rank.
    static func search(_ snapshot: CompanionGraphSnapshot, query: String, mode: Mode,
                       kind: CompanionGraphKind? = nil, limit: Int = 6) -> [Hit] {
        let nodes = snapshot.nodes.filter { kind == nil || $0.kind == kind }
        if mode == .full { return nodes.map { Hit(node: $0, via: nil) } }
        let wanted = terms(query)
        guard !wanted.isEmpty, limit > 0 else { return [] }

        let matches = nodes.map { node in
            (node, wanted.intersection(terms(fields(node).joined(separator: " "))))
        }
        var frequencies: [String: Int] = [:]
        for (_, words) in matches {
            for word in words { frequencies[word, default: 0] += 1 }
        }
        let ranked = matches.filter { !$0.1.isEmpty }.map { node, words in
            (node, words.sorted().reduce(0.0) { $0 + 1.0 / Double(frequencies[$1, default: 1]) })
        }.sorted { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0.id < rhs.0.id : lhs.1 > rhs.1
        }.map(\.0)
        if mode == .keyword { return ranked.prefix(limit).map { Hit(node: $0, via: nil) } }

        let anchors = ranked.prefix(max(1, limit / 2))
        var hits = anchors.map { Hit(node: $0, via: nil) }
        var seen = Set(anchors.map(\.id))
        let indexed = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let orderedEdges = snapshot.edges.sorted { $0.id < $1.id }
        for anchor in anchors {
            for edge in orderedEdges where edge.source == anchor.id || edge.target == anchor.id {
                guard hits.count < limit else { return hits }
                let other = edge.source == anchor.id ? edge.target : edge.source
                if let node = indexed[other], seen.insert(other).inserted {
                    hits.append(Hit(node: node, via: edge))
                }
            }
        }
        for node in ranked where hits.count < limit && seen.insert(node.id).inserted {
            hits.append(Hit(node: node, via: nil))
        }
        return hits
    }
}
