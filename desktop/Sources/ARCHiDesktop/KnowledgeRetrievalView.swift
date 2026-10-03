import SwiftUI

/// Local read projection; selected passages are revalidated by the existing
/// reading owner when drafting. No retrieval result can save or review a page.
@MainActor
struct KnowledgeRetrievalView: View {
    @ObservedObject var store: CompanionStore
    @State private var query = ""
    @State private var topic = ""
    @State private var result: KnowledgeRetrievalResult?
    @State private var selected: [KnowledgeAnchor] = []
    @State private var message: String?

    var body: some View {
        DisclosureGroup("Find connections in your reading") {
            VStack(alignment: .leading, spacing: 10) {
                Text(store.readingSources.sources.isEmpty ? "Keep a reading copy with Add text file above to find passages and draft a concept here." : "Search kept copies and reviewed pages. Matching words help locate passages; they do not establish whether a claim is true.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("Search sources and concepts", text: $query).textFieldStyle(.roundedBorder)
                        .onSubmit(search).accessibilityIdentifier("knowledge.retrieval.query")
                    Button("Find", action: search).disabled(store.readingSources.sources.isEmpty || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("knowledge.retrieval.search")
                }
                if let result {
                    Text("\(result.hits.count) shown · \(result.matchingCount) word matches · \(result.relatedCount) connected pages · \(result.excludedPageCount) unavailable pages excluded")
                        .font(.caption).foregroundStyle(.secondary)
                    if result.isPartial {
                        Text("Results are bounded. Narrow the search to find omitted matches.").font(.caption).foregroundStyle(.orange)
                    }
                    ForEach(result.hits) { hit in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(hit.title).font(.system(size: 12, weight: .medium))
                            Text(hit.kind == .page ? "Reviewed interpretation" : "Source passage · \(hit.sourceTitle ?? "Kept copy")")
                                .font(.caption2).foregroundStyle(.secondary)
                            if let link = hit.viaLink {
                                Text("Connected through your reviewed link: \(endpointTitle(link.from)) → \(link.kind.title) → \(endpointTitle(link.to))")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(link.rationale).font(.caption).textSelection(.enabled)
                            }
                            DisclosureGroup("Read match") { Text(hit.text).font(.caption).textSelection(.enabled) }
                            if let anchor = hit.anchor {
                                let picked = selected.contains(anchor)
                                Button(picked ? "Remove passage" : "Use passage") {
                                    guard store.readingSources.quote(for: anchor) != nil else {
                                        message = "This passage changed. Search again."; return
                                    }
                                    if picked { selected.removeAll { $0 == anchor } }
                                    else if selected.count < 3 { selected.append(anchor) }
                                }.disabled(!picked && selected.count >= 3)
                            } else if let binding = hit.pageBinding {
                                Button("Open page") {
                                    if let link = hit.viaLink, store.readingSources.availability(of: link) != nil {
                                        message = "This connection changed or is no longer available. Search again."; return
                                    }
                                    guard store.knowledgeDependenciesAreCurrent([binding]) else {
                                        message = "This page changed or is no longer available. Search again."; return
                                    }
                                    store.selectedKnowledgePageID = binding.id
                                }
                            }
                        }.padding(10).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                if !selected.isEmpty {
                    Text("\(selected.count) selected passage(s) · exact versions remain linked").font(.caption)
                    TextField("Concept topic", text: $topic).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("knowledge.concept.topic")
                    HStack {
                        Button("Draft concept locally") { _ = store.draftKnowledgeConcept(title: topic, anchors: selected) }
                            .disabled(store.isWorking || topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("knowledge.concept.draft")
                        Button("Clear selection") { selected = [] }.disabled(store.isWorking)
                        if store.isDraftingKnowledgeConcept {
                            Button("Stop") { store.discardKnowledgeConceptDraft() }
                        }
                    }
                }
                if let draft = store.currentKnowledgeConceptDraft {
                    Text(draft.title).font(.headline)
                    Text(draft.body).font(.caption).textSelection(.enabled)
                    HStack {
                        Button("Review in editor…") { store.editKnowledgeConceptDraft() }
                            .accessibilityIdentifier("knowledge.concept.review")
                        Button("Discard") { store.discardKnowledgeConceptDraft() }
                    }
                    Text("Generated interpretation. Saving creates a draft; reviewing it is a separate action.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let status = store.knowledgeConceptDraftMessage { Text(status).font(.caption).foregroundStyle(.secondary) }
                if let message { Text(message).font(.caption).foregroundStyle(.orange) }
            }.padding(.vertical, 10)
        }.accessibilityIdentifier("knowledge.retrieval")
        .onChange(of: store.readingSources.knowledgeLinks) { _, _ in invalidateResults() }
        .onChange(of: store.readingSources.knowledgePages) { _, _ in invalidateResults() }
        .onChange(of: store.readingSources.sources) { _, _ in invalidateResults() }
    }
    private func endpointTitle(_ binding: KnowledgePageBinding) -> String {
        let title = store.readingSources.knowledgePages.first { $0.binding == binding }?.title ?? "Unavailable page"
        return "\(title) v\(binding.revision)"
    }
    private func invalidateResults() {
        if result != nil { message = "Your library changed. Search again for current pages and connections." }
        result = nil
        selected = selected.filter { store.readingSources.quote(for: $0) != nil }
    }
    private func search() {
        do {
            result = try KnowledgeRetrieval.search(query: query, sources: store.readingSources.sources,
                pages: store.readingSources.knowledgePages, links: store.readingSources.knowledgeLinks,
                libraryIsCurrent: store.readingSources.isCurrentOnDisk)
            message = nil
        } catch { result = nil; message = error.localizedDescription }
    }
}
