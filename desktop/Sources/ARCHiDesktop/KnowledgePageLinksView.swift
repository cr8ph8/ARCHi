import SwiftUI

struct KnowledgeLinkDraft: Identifiable {
    let id = UUID()
    let page: KnowledgePage
    let prior: KnowledgePageLink?
}

/// Connections share the reading library's review, revision and recovery owner.
/// Local editor state never becomes a retained connection until Save succeeds.
@MainActor
struct KnowledgePageLinksView: View {
    @ObservedObject var store: CompanionStore
    let page: KnowledgePage
    private var connections: [KnowledgePageLink] {
        store.readingSources.latestKnowledgeLinks.filter {
            $0.from.id == page.id || $0.to.id == page.id
        }.sorted { $0.identity < $1.identity }
    }
    private var canEdit: Bool { !store.isWorking && !store.isShuttingDown && !store.hasOpenKnowledgeDraft }

    var body: some View {
        DisclosureGroup("Connections · \(connections.count)") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Describe how one page relates to another. Review records your interpretation of their linked passages. A changed page needs a new connection review.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Connect a page…", systemImage: "link") { store.knowledgePageMessage = nil; store.knowledgeLinkDraft = KnowledgeLinkDraft(page: page, prior: nil) }
                    .disabled(!canEdit || store.readingSources.availability(of: page) != nil)
                    .accessibilityIdentifier("knowledge.link.new.\(page.id)")
                if store.readingSources.availability(of: page) != nil {
                    Text("Review this page and its current passages to add a connection.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(connections) { connection in
                    VStack(alignment: .leading, spacing: 7) {
                        endpoint(connection.from)
                        Label(connection.kind.title, systemImage: "arrow.down").font(.caption.bold())
                        endpoint(connection.to)
                        Text(connection.rationale).font(.caption).textSelection(.enabled)
                        Text("Your declaration · \(connection.state.title) · link v\(connection.revision)")
                            .font(.caption2).foregroundStyle(.secondary)
                        if let issue = store.readingSources.availability(of: connection) {
                            Text(issue).font(.caption).foregroundStyle(.orange)
                        }
                        HStack {
                            if connection.state == .draft {
                                Button("Mark link reviewed") { store.reviewKnowledgeLink(connection) }
                                    .accessibilityIdentifier("knowledge.link.review.\(connection.id)")
                            }
                            if connection.state != .withdrawn {
                                Button("Revise link…") { store.knowledgePageMessage = nil; store.knowledgeLinkDraft = KnowledgeLinkDraft(page: page, prior: connection) }
                                    .accessibilityIdentifier("knowledge.link.revise.\(connection.id)")
                                Button("Withdraw link", role: .destructive) { store.withdrawKnowledgeLink(connection) }
                                    .accessibilityIdentifier("knowledge.link.withdraw.\(connection.id)")
                            }
                        }.buttonStyle(.borderless).font(.caption).disabled(!canEdit)
                        history(connection)
                    }.padding(10).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                }
            }.padding(.vertical, 8)
        }
        .accessibilityIdentifier("knowledge.links.\(page.id)")
    }

    private func endpoint(_ binding: KnowledgePageBinding) -> some View {
        let retained = store.readingSources.knowledgePages.first { $0.binding == binding }
        return HStack {
            Text("\(retained?.title ?? "Unavailable page") · v\(binding.revision)").font(.caption)
            Spacer()
            Button("Open page") {
                guard store.knowledgeDependenciesAreCurrent([binding]) else {
                    store.knowledgePageMessage = "This endpoint changed. Revise the connection and choose its current reviewed page."; return
                }
                store.selectedKnowledgePageID = binding.id
            }.buttonStyle(.borderless).font(.caption)
                .disabled(!store.knowledgeDependenciesAreCurrent([binding]))
        }
    }

    @ViewBuilder private func history(_ link: KnowledgePageLink) -> some View {
        let earlier = store.readingSources.knowledgeLinks.filter { $0.id == link.id && $0.revision < link.revision }
            .sorted { $0.revision > $1.revision }
        if !earlier.isEmpty {
            DisclosureGroup("Link history · \(earlier.count) earlier versions") {
                ForEach(earlier, id: \.revision) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("v\(item.revision) · \(item.state.title) · \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        Text("\(title(item.from)) → \(item.kind.title) → \(title(item.to))")
                        Text(item.rationale).textSelection(.enabled)
                    }.font(.caption2).foregroundStyle(.secondary).padding(.vertical, 4)
                }
            }.font(.caption)
        }
    }

    private func title(_ binding: KnowledgePageBinding) -> String {
        let name = store.readingSources.knowledgePages.first { $0.binding == binding }?.title ?? "Unavailable page"
        return "\(name) v\(binding.revision)"
    }
}

@MainActor
struct KnowledgePageLinkEditor: View {
    @ObservedObject var store: CompanionStore
    let prior: KnowledgePageLink?
    @State private var fromDigest: String
    @State private var toDigest: String
    @State private var kind: KnowledgePageLinkKind
    @State private var rationale: String

    init(store: CompanionStore, page: KnowledgePage, prior: KnowledgePageLink?) {
        self.store = store; self.prior = prior
        _fromDigest = State(initialValue: (prior?.from ?? page.binding).digest)
        _toDigest = State(initialValue: prior?.to.digest ?? "")
        _kind = State(initialValue: prior?.kind ?? .supports)
        _rationale = State(initialValue: prior?.rationale ?? "")
    }

    private var pages: [KnowledgePage] {
        store.readingSources.latestKnowledgePages.filter { store.readingSources.availability(of: $0) == nil }
            .sorted { $0.title == $1.title ? $0.id < $1.id : $0.title < $1.title }
    }
    private var from: KnowledgePage? { pages.first { $0.binding.digest == fromDigest } }
    private var to: KnowledgePage? { pages.first { $0.binding.digest == toDigest } }
    private var canSave: Bool {
        from != nil && to != nil && from?.id != to?.id
            && !rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && rationale.utf8.count <= KnowledgePageLink.maximumRationaleBytes
            && !store.isWorking && !store.isShuttingDown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(prior == nil ? "Connect knowledge pages" : "Revise connection").font(.title2)
            Text("Choose the direction, then explain the connection using the pages' passages. Saving creates a draft; reviewing is a separate step.")
                .font(.callout).foregroundStyle(.secondary)
            Picker("From page", selection: $fromDigest) {
                if from == nil { Text("Choose a current reviewed page").tag(fromDigest) }
                ForEach(pages, id: \.id) { page in Text("\(page.title) · v\(page.revision)").tag(page.binding.digest) }
            }.accessibilityIdentifier("knowledge.link.from")
            Picker("Connection", selection: $kind) {
                ForEach(KnowledgePageLinkKind.allCases, id: \.self) { value in Text(value.title).tag(value) }
            }.accessibilityIdentifier("knowledge.link.kind")
            Picker("To page", selection: $toDigest) {
                if to == nil { Text("Choose a current reviewed page").tag(toDigest) }
                ForEach(pages, id: \.id) { page in Text("\(page.title) · v\(page.revision)").tag(page.binding.digest) }
            }.accessibilityIdentifier("knowledge.link.to")
            if let from, let to, from.id != to.id {
                Text("\(from.title) \(kind.title.lowercased()) \(to.title)").font(.headline)
                DisclosureGroup("Inspect both pages and passages") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach([from, to], id: \.id) { page in
                                Text("\(page.title) · v\(page.revision)").font(.headline)
                                Text(page.body).font(.caption).textSelection(.enabled)
                                KnowledgePageEvidence(store: store, anchors: page.anchors)
                            }
                        }
                    }.frame(maxHeight: 170)
                }.font(.caption)
            }
            Text("Why are these pages connected?").font(.callout)
            TextEditor(text: $rationale).font(.body).frame(minHeight: 90, maxHeight: 140)
                .accessibilityIdentifier("knowledge.link.rationale")
            Text("\(rationale.utf8.count) / \(KnowledgePageLink.maximumRationaleBytes) bytes · your interpretation")
                .font(.caption).foregroundStyle(.secondary)
            if let message = store.knowledgePageMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Cancel") { store.knowledgeLinkDraft = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save draft") {
                    guard let from, let to else { return }
                    if store.saveKnowledgeLink(prior: prior, from: from.binding, to: to.binding,
                                               kind: kind, rationale: rationale) { store.knowledgeLinkDraft = nil }
                }.disabled(!canSave).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("knowledge.link.save")
            }
        }.padding(24).frame(width: 560)
    }
}
