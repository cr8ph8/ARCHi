import Foundation

/// Exact excerpts already prepared for one local request. Ephemeral UI state:
/// never encoded, persisted, sent again, or resolved against a newer source.
struct AssistantSourceContext: Equatable, Sendable {
    struct Excerpt: Equatable, Sendable, Identifiable {
        enum Kind: String, Sendable { case interpretation, passage }
        let id: String
        let title: String
        let kind: Kind
        let text: String
        let detail: String
        let provenance: ReadingSourceProvenanceReceipt?
    }
    let excerpts: [Excerpt]
    let coverage: String

    static func capture(_ request: AssistantRequest, sourceTitles: [String: String] = [:]) -> Self? {
        guard !request.isKnowledgeAcquisition else { return nil }
        if let context = request.localKnowledge {
            guard request.hasValidLocalKnowledge else { return nil }
            let excerpts = context.entries.flatMap { entry in
                [Excerpt(id: entry.sourceID, title: entry.page.title, kind: .interpretation,
                    text: entry.page.body, detail: "Reviewed note · v\(entry.page.revision). Review does not certify its claims.", provenance: nil)]
                + entry.page.anchors.enumerated().map { index, anchor in
                    Excerpt(id: entry.quoteSourceID(at: index),
                        title: sourceTitles[anchor.source.id] ?? "Kept source",
                        kind: .passage, text: entry.quotes[index],
                        detail: "v\(anchor.source.revision) · range \(anchor.location)–\(anchor.location + anchor.length) · \(anchor.quoteDigest.prefix(10))",
                        provenance: anchor.source.provenance)
                }
            }
            return Self(excerpts: excerpts, coverage: "\(context.entries.count) reviewed page(s) and their exact linked passages. Other kept sources were not included by this selection.")
        }
        if let plan = request.localReading {
            guard request.hasValidLocalControl else { return nil }
            return Self(excerpts: plan.sections.map { section in
                let source = plan.references.first { $0.id == section.sourceID }
                return Excerpt(id: section.id, title: section.sourceTitle + " · " + section.title,
                    kind: .passage, text: section.text,
                    detail: (source.map { "v\($0.revision) · " } ?? "Shared copy · ")
                        + "range \(section.location)–\(section.location + section.length) · \(section.sha256.prefix(10))",
                    provenance: source?.provenance?.receipt)
            }, coverage: "\(plan.sections.count) of \(plan.totalSections) sections prepared · \(plan.isPartial ? "partial context" : "full context"). \(plan.omittedSourceIDs.count) source(s) have no prepared passage.")
        }
        return nil
    }
}

/// Citation membership is distinct from dispatch and from semantic support.
/// Only terminal checked evidence can mark a captured excerpt as cited.
struct AssistantSourceEvidence: Equatable {
    enum Delivery: String { case prepared = "Prepared only", attempted = "Sent to local client", cited = "Cited in checked reply" }
    struct Row: Equatable, Identifiable {
        let excerpt: AssistantSourceContext.Excerpt
        let delivery: Delivery
        var id: String { excerpt.id }
    }
    let rows: [Row]
    let coverage: String
    let status: String
    let unmatchedCitationCount: Int

    init?(receipt: AssistantLaneReceipt) {
        guard receipt.provider == .qwen, let context = receipt.sourceContext, !context.excerpts.isEmpty else { return nil }
        let dispatched = Set(receipt.evidence?.reasoningSourceIDsDispatched ?? [])
        let cited = receipt.state == .complete ? Set(receipt.evidence?.sourceIDsCited ?? []) : []
        rows = context.excerpts.map { excerpt in
            let attempted = receipt.requestStarted && dispatched.contains(excerpt.id)
            return Row(excerpt: excerpt, delivery: attempted ? (cited.contains(excerpt.id) ? .cited : .attempted) : .prepared)
        }
        coverage = context.coverage
        unmatchedCitationCount = cited.subtracting(Set(context.excerpts.map(\.id))).count
        switch receipt.state {
        case .pending: status = "Reply in progress; no final citations yet."
        case .failed: status = "Reply failed. Prepared or attempted text is not a completed answer."
        case .cancelled: status = "Reply stopped. No completed answer is credited."
        case .complete:
            status = receipt.evidence == nil ? "Source dispatch and citation details were not reported."
                : "\(rows.filter { $0.delivery == .cited }.count) cited · \(rows.filter { $0.delivery == .attempted }.count) sent without a citation · \(rows.filter { $0.delivery == .prepared }.count) prepared only."
        }
    }
}
