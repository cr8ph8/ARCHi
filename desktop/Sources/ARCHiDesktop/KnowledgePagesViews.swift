import AppKit
import SwiftUI

/// Presentation identity only. Editable text stays with the open editor;
/// saving and all version changes belong to CompanionStore and its library.
struct KnowledgePageDraft: Identifiable {
    let id = UUID()
    let prior: KnowledgePage?
    let proposal: KnowledgeConceptDraft?
    let relationshipKind: RelationshipMemoryKind?
    let person: KnowledgePageBinding?

    init(prior: KnowledgePage? = nil, proposal: KnowledgeConceptDraft? = nil,
         relationshipKind: RelationshipMemoryKind? = nil, person: KnowledgePageBinding? = nil) {
        self.prior = prior; self.proposal = proposal
        self.relationshipKind = prior?.relationship?.kind ?? relationshipKind
        self.person = prior?.relationship?.person ?? person
    }
}

@MainActor
struct KnowledgePagesCard: View {
    @ObservedObject var store: CompanionStore
    @State private var query = ""
    @State private var copyMessage: String?

    private var pages: [KnowledgePage] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.readingSources.latestKnowledgePages.filter {
            search.isEmpty || [$0.title, $0.body, $0.kind.rawValue, $0.state.rawValue]
                .contains { $0.localizedStandardContains(search) }
        }.sorted { $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        WorkspaceCard {
            HStack {
                Label("Knowledge pages", systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                Spacer()
                Button("New page…", systemImage: "plus") { store.beginKnowledgePage(nil) }
                    .buttonStyle(.bordered)
                    .disabled(store.readingSources.sources.isEmpty || store.readingSources.loadError != nil)
                    .accessibilityIdentifier("knowledge.new")
            }
            Text("Keep claims and concepts beside the exact passages you used. Pages begin as drafts. Review records your check of the linked passages; factual verification remains separate.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3).padding(.vertical, 8)
            if store.readingSources.sources.isEmpty {
                Text("Keep a reading copy before creating a page.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    Button("Open Work together") { store.section = .context }
                        .accessibilityIdentifier("knowledge.open-work")
                    Button("Add text file…") { store.importReadingSource() }
                        .accessibilityIdentifier("knowledge.import-source")
                }.buttonStyle(.bordered).controlSize(.small)
                if let message = store.documentReadingMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error = store.readingSources.loadError {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange)
                    .accessibilityIdentifier("knowledge.library-error")
            }
            KnowledgeRetrievalView(store: store).padding(.vertical, 8)
            if !store.readingSources.latestKnowledgePages.isEmpty {
                TextField("Find a page", text: $query).textFieldStyle(.roundedBorder)
                    .padding(.vertical, 6).accessibilityIdentifier("knowledge.search")
                if pages.isEmpty {
                    Text("No matching pages.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach(pages, id: \.id) { page in
                    Divider().padding(.vertical, 5)
                    pageRow(page)
                }
            } else {
                Text("No pages saved. Creating a page does not automatically teach a lesson or change your companion.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 8)
            }
            if let message = store.knowledgePageMessage {
                Text(message).font(.system(size: 11)).foregroundStyle(WorkspaceTheme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("knowledge.status")
            }
            if let copyMessage {
                Text(copyMessage).font(.system(size: 11)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("knowledge.copy-status")
            }
        }
        .disabled(store.isShuttingDown)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("knowledge.pages")
        .onChange(of: store.selectedKnowledgePageID) { _, id in
            if let id, !pages.contains(where: { $0.id == id }) { query = "" }
        }
        .sheet(item: $store.knowledgePageDraft) { draft in
            KnowledgePageEditor(store: store, draft: draft).interactiveDismissDisabled()
        }
        .sheet(item: $store.knowledgeLinkDraft) { draft in
            KnowledgePageLinkEditor(store: store, page: draft.page, prior: draft.prior).interactiveDismissDisabled()
        }
    }

    private func pageRow(_ page: KnowledgePage) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { store.selectedKnowledgePageID == page.id },
            set: { store.selectedKnowledgePageID = $0 ? page.id : nil })) {
            VStack(alignment: .leading, spacing: 10) {
                Text(page.body).font(.system(size: 13)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let relationship = page.relationship {
                    Text(relationship.markdownLines.joined(separator: "\n"))
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let unavailable = store.readingSources.availability(of: page) {
                    Text(unavailable).font(.system(size: 11)).foregroundStyle(.orange)
                        .accessibilityIdentifier("knowledge.availability.\(page.id)")
                }
                KnowledgePageEvidence(store: store, anchors: page.anchors)
                KnowledgePageLinksView(store: store, page: page)
                HStack {
                    Button("Use in local chat") { store.useKnowledgePageInChat(page) }
                        .disabled(store.readingSources.availability(of: page) != nil)
                        .accessibilityIdentifier("knowledge.use.\(page.id)")
                    Button("Revise…") { store.beginKnowledgePage(page) }
                        .accessibilityIdentifier("knowledge.revise.\(page.id)")
                    if page.state == .draft {
                        Button("Mark reviewed") { store.reviewKnowledgePage(page) }
                            .disabled(!page.anchors.allSatisfy { store.readingSources.quote(for: $0) != nil })
                            .accessibilityIdentifier("knowledge.review.\(page.id)")
                    }
                    if page.state != .withdrawn {
                        Button("Withdraw", role: .destructive) { store.withdrawKnowledgePage(page) }
                            .accessibilityIdentifier("knowledge.withdraw.\(page.id)")
                    }
                    Button("Copy Markdown") { copyMarkdown(page) }
                        .accessibilityIdentifier("knowledge.copy.\(page.id)")
                }.buttonStyle(.borderless).font(.system(size: 11))
                if page.state == .reviewed, page.kind == .concept {
                    KnowledgeProcedureCandidateView(store: store, page: page)
                        .id("\(page.id).\(page.revision).\(page.binding.digest)")
                }
                history(for: page)
            }.padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(page.title).font(.system(size: 13, weight: .medium))
                Text("\(page.relationship?.kind.title ?? page.kind.rawValue.capitalized) · \(page.state.rawValue.capitalized) · v\(page.revision) · \(page.anchors.count) linked passages")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.accessibilityIdentifier("knowledge.page.\(page.id)")
    }

    @ViewBuilder private func history(for page: KnowledgePage) -> some View {
        let earlier = store.readingSources.knowledgePages.filter { $0.id == page.id && $0.revision < page.revision }
            .sorted { $0.revision > $1.revision }
        if !earlier.isEmpty {
            DisclosureGroup("History · \(earlier.count) earlier versions") {
                ForEach(earlier, id: \.revision) { prior in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("v\(prior.revision) · \(prior.state.rawValue.capitalized) · \(prior.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        Text(prior.title).font(.system(size: 12, weight: .medium))
                        Text(prior.body).font(.system(size: 12)).textSelection(.enabled)
                        if let relationship = prior.relationship {
                            Text(relationship.markdownLines.joined(separator: "\n"))
                                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        KnowledgePageEvidence(store: store, anchors: prior.anchors)
                    }.padding(.vertical, 6)
                }
            }.font(.system(size: 11)).accessibilityIdentifier("knowledge.history.\(page.id)")
        }
    }

    private func copyMarkdown(_ page: KnowledgePage) {
        let markdown = store.readingSources.markdown(for: page)
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(markdown, forType: .string) {
            copyMessage = "Copied \(page.title), version \(page.revision), as Markdown."
        } else { copyMessage = "The page could not be copied. Try again." }
    }
}

@MainActor
struct KnowledgePageEvidence: View {
    @ObservedObject var store: CompanionStore
    let anchors: [KnowledgeAnchor]
    var numberOffset = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(anchors.enumerated()), id: \.element.id) { offset, anchor in
                let source = store.readingSources.sources.first { $0.binding == anchor.source }
                DisclosureGroup("Passage \(offset + numberOffset + 1) · \(source?.title ?? "Unavailable kept copy") · v\(anchor.source.revision)") {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(anchor.source.provenance.map { "\($0.origin.title) · \($0.acquisition.title) · \($0.parents.count) parent copies · declared, not verified" }
                            ?? "Origin unknown · no source declaration")
                            .font(.caption2).foregroundStyle(.secondary)
                        if let quote = store.readingSources.quote(for: anchor) {
                            Text(quote).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("This exact passage is unavailable. Its kept copy or a derivation parent changed or was removed.")
                                .foregroundStyle(.orange)
                        }
                        Text("Position \(anchor.location + 1) · \(anchor.length) UTF-16 units")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.padding(.top, 5)
                }.font(.system(size: 11))
                    .accessibilityIdentifier("knowledge.passage.\(anchor.id)")
            }
        }
    }
}

@MainActor
private struct KnowledgePageEditor: View {
    @ObservedObject var store: CompanionStore
    let draft: KnowledgePageDraft
    @State private var title: String
    @State private var pageBody: String
    @State private var kind: KnowledgePageKind
    @State private var anchors: [KnowledgeAnchor]
    @State private var sourceID: String?
    @State private var quote = ""
    @State private var occurrence: Int?
    @State private var anchorMessage: String?
    @State private var personBinding: KnowledgePageBinding?
    @State private var includesDate: Bool
    @State private var relationshipDate: Date
    @State private var commitmentStatus: RelationshipCommitmentStatus

    init(store: CompanionStore, draft: KnowledgePageDraft) {
        self.store = store; self.draft = draft
        _title = State(initialValue: draft.prior?.title ?? draft.proposal?.title ?? "")
        _pageBody = State(initialValue: draft.prior?.body ?? draft.proposal?.body ?? "")
        _kind = State(initialValue: draft.prior?.kind ?? (draft.proposal == nil ? .claim : .concept))
        _anchors = State(initialValue: draft.prior?.anchors ?? draft.proposal?.anchors ?? [])
        _personBinding = State(initialValue: draft.person)
        let date = draft.prior?.relationship?.occurredAt ?? draft.prior?.relationship?.dueAt
        _includesDate = State(initialValue: date != nil)
        _relationshipDate = State(initialValue: date ?? Date())
        _commitmentStatus = State(initialValue: draft.prior?.relationship?.commitmentStatus ?? .pending)
    }

    private var source: ReadingSourceSnapshot? {
        store.readingSources.sources.first { $0.id == sourceID }
    }
    private var matches: KnowledgeQuoteMatches {
        KnowledgeQuoteMatches.find(quote, in: source?.text ?? "")
    }
    private var chosenRange: NSRange? {
        guard !matches.tooMany else { return nil }
        if matches.ranges.count == 1 { return matches.ranges[0] }
        return matches.ranges.first { $0.location == occurrence }
    }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && title.trimmingCharacters(in: .whitespacesAndNewlines).utf8.count <= 240
            && !pageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && pageBody.utf8.count <= KnowledgePage.maximumBodyBytes
            && (1...4).contains(anchors.count)
            && anchors.allSatisfy { store.readingSources.quote(for: $0) != nil }
            && store.readingSources.loadError == nil
            && (draft.relationshipKind == nil || relationshipMetadata?.isValid == true)
            && (draft.relationshipKind == nil || draft.relationshipKind == .person || currentPerson != nil)
    }

    private var people: [KnowledgePage] {
        store.readingSources.latestKnowledgePages.filter {
            $0.relationship?.kind == .person && store.readingSources.availability(of: $0) == nil
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    private var currentPerson: KnowledgePage? { people.first { $0.binding == personBinding } }
    private var relationshipMetadata: RelationshipMemoryMetadata? {
        guard let type = draft.relationshipKind else { return nil }
        return RelationshipMemoryMetadata(kind: type, person: type == .person ? nil : personBinding,
            occurredAt: type == .encounter && includesDate ? relationshipDate : nil,
            dueAt: type == .commitment && includesDate ? relationshipDate : nil,
            commitmentStatus: type == .commitment ? commitmentStatus : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.relationshipKind.map { "\(draft.prior == nil ? "Add" : "Revise") \($0.title.lowercased())" }
                 ?? (draft.prior == nil ? "Create a knowledge page" : "Revise this page"))
                .font(.system(size: 22, weight: .medium, design: .rounded))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(draft.relationshipKind == nil
                         ? "Write your interpretation and link one to four exact passages from kept reading copies. Saving creates a draft for review."
                         : "Record what you know in your own words and link the note it came from. Dates can stay unknown. Saving creates a draft for your review.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    TextField("Page title", text: $title).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("knowledge.editor.title")
                    if title.trimmingCharacters(in: .whitespacesAndNewlines).utf8.count > 240 {
                        Text("Shorten the title to 240 UTF-8 bytes or fewer.")
                            .font(.system(size: 11)).foregroundStyle(.orange)
                    }
                    if draft.relationshipKind != nil { relationshipFields }
                    else { Picker("Page type", selection: $kind) {
                        ForEach(KnowledgePageKind.allCases, id: \.rawValue) { value in
                            Text(value.rawValue.capitalized).tag(value)
                        }
                    }.pickerStyle(.segmented).accessibilityIdentifier("knowledge.editor.kind") }
                    TextEditor(text: $pageBody).frame(height: 130)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
                        .accessibilityLabel("Page text").accessibilityIdentifier("knowledge.editor.body")
                    if pageBody.utf8.count > KnowledgePage.maximumBodyBytes {
                        Text("Shorten the page to 8 KB or fewer before saving.")
                            .font(.system(size: 11)).foregroundStyle(.orange)
                    }
                    Divider()
                    attachedPassages
                    passagePicker
                    if let message = anchorMessage {
                        Text(message).font(.system(size: 11)).foregroundStyle(.orange)
                            .accessibilityIdentifier("knowledge.editor.passage-status")
                    }
                    if let message = store.knowledgePageMessage {
                        Text(message).font(.system(size: 11)).foregroundStyle(WorkspaceTheme.accent)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("knowledge.editor.status")
                    }
                    if !store.readingSources.isCurrentOnDisk {
                        Text("The reading library changed or needs recovery. Your draft stays open; saving requires current kept copies.")
                            .font(.system(size: 11)).foregroundStyle(.orange)
                    }
                }.padding(2)
            }.frame(maxHeight: 510)
            Divider()
            HStack {
                Button("Cancel") { store.knowledgePageDraft = nil }
                    .keyboardShortcut(.cancelAction).accessibilityIdentifier("knowledge.editor.cancel")
                Spacer()
                Button("Save draft") {
                    if let metadata = relationshipMetadata {
                        _ = store.saveRelationshipPage(prior: draft.prior, title: title, body: pageBody,
                                                       metadata: metadata, anchors: anchors)
                    } else {
                        _ = store.saveKnowledgePage(prior: draft.prior, title: title, body: pageBody, kind: kind, anchors: anchors)
                    }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(!canSave || store.isShuttingDown)
                .accessibilityIdentifier("knowledge.editor.save")
            }
        }
        .padding(24).frame(width: 590)
        .interactiveDismissDisabled()
        .onChange(of: quote) { _, _ in occurrence = nil; anchorMessage = nil }
        .onChange(of: sourceID) { _, _ in occurrence = nil; anchorMessage = nil }
        .onChange(of: source?.binding) { _, _ in occurrence = nil }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("knowledge.editor")
    }

    @ViewBuilder private var relationshipFields: some View {
        if let type = draft.relationshipKind {
            Text("\(type.title) · recorded by you").font(.caption).foregroundStyle(.secondary)
            if type != .person {
                Picker("Person", selection: Binding<String>(
                    get: { currentPerson?.id ?? "" },
                    set: { id in personBinding = people.first { $0.id == id }?.binding })) {
                    Text("Choose a reviewed person").tag("")
                    ForEach(people, id: \.id) { person in
                        Text("\(person.title) · \(person.id.prefix(6)) · v\(person.revision)").tag(person.id)
                    }
                }.accessibilityIdentifier("relationship.editor.person")
                if personBinding != nil && currentPerson == nil {
                    Text("The linked person changed. Check the current record and explicitly select it again.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Toggle(type == .encounter ? "Record an encounter date" : "Record a due date", isOn: $includesDate)
                    .accessibilityIdentifier("relationship.editor.has-date")
                if includesDate {
                    DatePicker(type == .encounter ? "Encounter date" : "Due date", selection: $relationshipDate,
                               displayedComponents: [.date])
                }
            }
            if type == .commitment {
                Picker("Status you report", selection: $commitmentStatus) {
                    ForEach(RelationshipCommitmentStatus.allCases, id: \.rawValue) { status in
                        Text(status.title).tag(status)
                    }
                }
                Text("Completion records your report. ARCHi does not send messages or verify that the action happened.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var attachedPassages: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Linked passages · \(anchors.count) / 4").font(.system(size: 12, weight: .medium))
            if anchors.isEmpty {
                Text("Add a passage to preserve the source behind this page.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(Array(anchors.enumerated()), id: \.element.id) { offset, anchor in
                HStack(alignment: .top) {
                    KnowledgePageEvidence(store: store, anchors: [anchor], numberOffset: offset)
                    Spacer(minLength: 8)
                    Button("Remove") { anchors.removeAll { $0.id == anchor.id } }
                        .buttonStyle(.borderless).font(.system(size: 11))
                        .accessibilityIdentifier("knowledge.editor.remove.\(anchor.id)")
                }
            }
        }
    }

    private var passagePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Kept copy", selection: $sourceID) {
                Text("Choose a kept copy").tag(String?.none)
                ForEach(store.readingSources.sources) { source in
                    Text("\(source.title) · v\(source.revision)").tag(Optional(source.id))
                }
            }.accessibilityIdentifier("knowledge.editor.source")
            if let source {
                DisclosureGroup("Inspect kept copy") {
                    ScrollView { Text(source.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 160).font(.system(size: 11))
                }.accessibilityIdentifier("knowledge.editor.inspect-source")
                Text("Paste the exact passage to link").font(.system(size: 11, weight: .medium))
                TextEditor(text: $quote).frame(height: 75)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
                    .accessibilityLabel("Exact source passage").accessibilityIdentifier("knowledge.editor.quote")
                if matches.tooMany {
                    Text("This text appears more than 32 times. Paste a longer passage to choose its location.")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                } else if matches.ranges.count > 1 {
                    Picker("Occurrence", selection: $occurrence) {
                        Text("Choose a location").tag(Int?.none)
                        ForEach(matches.ranges, id: \.location) { range in
                            Text("Starts at UTF-16 position \(range.location + 1)").tag(Optional(range.location))
                        }
                    }.accessibilityIdentifier("knowledge.editor.occurrence")
                } else if !quote.isEmpty && matches.ranges.isEmpty {
                    Text("No exact match in this kept copy. Include the original spacing and punctuation.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else if let range = chosenRange {
                    Text("Exact match at UTF-16 position \(range.location + 1).")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Add passage") {
                        if let range = chosenRange { addPassage(sourceID: source.id, range: range) }
                    }
                    .disabled(chosenRange == nil || anchors.count >= 4)
                    .accessibilityIdentifier("knowledge.editor.add-passage")
                    Button("Use entire kept copy") {
                        addPassage(sourceID: source.id, range: NSRange(location: 0, length: source.text.utf16.count))
                    }
                    .disabled(anchors.count >= 4)
                    .accessibilityIdentifier("knowledge.editor.add-whole-source")
                }.buttonStyle(.bordered).controlSize(.small)
            }
            Button("Add text file…") { store.importReadingSource() }
                .buttonStyle(.borderless).font(.system(size: 11))
                .accessibilityIdentifier("knowledge.editor.import-source")
            if let message = store.documentReadingMessage {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private func addPassage(sourceID: String, range: NSRange) {
        guard anchors.count < 4 else { anchorMessage = "Link up to four passages to one page."; return }
        do {
            let anchor = try store.readingSources.makeAnchor(sourceID: sourceID, range: range)
            guard !anchors.contains(where: { $0.id == anchor.id }) else {
                anchorMessage = "This exact passage is already linked."; return
            }
            anchors.append(anchor)
            quote = ""; occurrence = nil; anchorMessage = nil
        } catch { anchorMessage = error.localizedDescription }
    }
}

/// Literal matches retain exact UTF-16 offsets, including repeated passages.
/// More than 32 matches requires a longer quote instead of silently selecting
/// the first occurrence or presenting an unbounded menu.
private struct KnowledgeQuoteMatches {
    let ranges: [NSRange]
    let tooMany: Bool

    static func find(_ quote: String, in text: String) -> Self {
        guard !quote.isEmpty, quote.utf16.count <= text.utf16.count else { return .init(ranges: [], tooMany: false) }
        let source = text as NSString
        var cursor = 0
        var ranges: [NSRange] = []
        while cursor < source.length {
            let range = source.range(of: quote, options: .literal, range: NSRange(location: cursor, length: source.length - cursor))
            guard range.location != NSNotFound else { break }
            if Range(range, in: text) != nil {
                ranges.append(range)
                if ranges.count > 32 { return .init(ranges: [], tooMany: true) }
            }
            cursor = range.location + 1
        }
        return .init(ranges: ranges, tooMany: false)
    }
}
