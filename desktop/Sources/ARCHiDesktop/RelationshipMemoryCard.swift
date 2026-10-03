import SwiftUI

/// A view over the kept-source library, not a second contacts database.
@MainActor
struct RelationshipMemoryCard: View {
    @ObservedObject var store: CompanionStore
    @State private var selectedPersonID = ""
    @State private var selectedRecords: [KnowledgePageBinding] = []
    @State private var noteTitle = ""
    @State private var noteText = ""
    @State private var noteOpen = false
    @State private var expandedHistoryIDs: Set<String> = []

    private var people: [KnowledgePage] {
        store.readingSources.latestKnowledgePages.filter { $0.relationship?.kind == .person }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    private var person: KnowledgePage? { people.first { $0.id == selectedPersonID } }
    private var related: [KnowledgePage] {
        guard let person else { return [] }
        return store.readingSources.latestKnowledgePages.filter { $0.relationship?.person?.id == person.id }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    private var chosen: [KnowledgePage] { related.filter { selectedRecords.contains($0.binding) } }

    var body: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("People & follow-through", systemImage: "person.2")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                    Spacer()
                    Button("Add person…", systemImage: "plus") { store.beginRelationshipPage(.person) }
                        .disabled(store.readingSources.sources.isEmpty)
                        .accessibilityIdentifier("relationship.new-person")
                }
                Text("Keep the context you choose: a person, what happened, and what you agreed to do. Every record links to a kept note and begins as a draft.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                noteCapture
                if let message = store.knowledgePageMessage {
                    Text(message).font(.caption).foregroundStyle(WorkspaceTheme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("relationship.status")
                }
                if people.isEmpty {
                    Text("Start by keeping a note, then add a person and link the passage that supports it.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("Person", selection: $selectedPersonID) {
                        Text("Choose a person").tag("")
                        ForEach(people, id: \.id) { page in
                            Text("\(page.title) · \(page.id.prefix(6)) · \(page.state.rawValue)").tag(page.id)
                        }
                    }.accessibilityIdentifier("relationship.person")
                    if let person { personDetail(person) }
                }
                Text("Local records only. ARCHi does not scan contacts, send follow-ups or create reminders here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(store.isShuttingDown || store.isWorking || store.readingSources.loadError != nil)
        .onChange(of: selectedPersonID) { _, _ in selectedRecords = [] }
        .onChange(of: person?.binding) { _, _ in selectedRecords = [] }
        .onChange(of: related.map(\.binding)) { _, bindings in
            selectedRecords.removeAll { !bindings.contains($0) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("relationship.memory")
    }

    private var noteCapture: some View {
        DisclosureGroup("Keep a note", isExpanded: $noteOpen) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Note title", text: $noteTitle).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("relationship.note-title")
                TextEditor(text: $noteText).frame(height: 100)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
                    .accessibilityLabel("Relationship note").accessibilityIdentifier("relationship.note-text")
                Text("Paste your own notes or a meeting excerpt you want kept. Saving keeps exactly this text as a source; it does not create facts about anyone automatically.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Keep note on this Mac") {
                    if store.keepRelationshipSource(title: noteTitle, text: noteText) {
                        noteTitle = ""; noteText = ""; noteOpen = false
                    }
                }
                .disabled(noteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || noteTitle.utf8.count > 240 || noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || noteText.utf8.count > 100_000)
                .accessibilityIdentifier("relationship.keep-note")
            }.padding(.top, 8)
        }
    }

    private func personDetail(_ person: KnowledgePage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(person.body).textSelection(.enabled).font(.callout)
            KnowledgePageEvidence(store: store, anchors: person.anchors)
            availability(person)
            recordActions(person)
            HStack {
                Button("Add encounter…") { store.beginRelationshipPage(.encounter, person: person) }
                    .accessibilityIdentifier("relationship.new-encounter")
                Button("Add commitment…") { store.beginRelationshipPage(.commitment, person: person) }
                    .accessibilityIdentifier("relationship.new-commitment")
            }.disabled(store.readingSources.availability(of: person) != nil)
            Divider()
            Text("Prepare for your next conversation").font(.headline)
            Text("Select up to three related records. Preparation uses this person and your selected records through local chat. Nothing is sent until you ask.")
                .font(.caption).foregroundStyle(.secondary)
            if related.isEmpty { Text("No encounters or commitments recorded yet.").font(.caption).foregroundStyle(.secondary) }
            ForEach(related, id: \.id) { record in relationshipRow(record) }
            Button("Prepare locally", systemImage: "text.bubble") {
                store.prepareRelationshipConversation(person: person, records: chosen)
            }
            .disabled(store.readingSources.availability(of: person) != nil || chosen.count != selectedRecords.count)
            .accessibilityIdentifier("relationship.prepare")
        }
    }

    private func relationshipRow(_ page: KnowledgePage) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle(isOn: Binding(get: { selectedRecords.contains(page.binding) }, set: { include in
                selectedRecords.removeAll { $0.id == page.id }
                if include && selectedRecords.count < 3 { selectedRecords.append(page.binding) }
            })) {
                Text("\(page.relationship?.kind.title ?? "Record"): \(page.title)")
            }
            .disabled(store.readingSources.availability(of: page) != nil
                      || (selectedRecords.count >= 3 && !selectedRecords.contains(page.binding)))
            .accessibilityIdentifier("relationship.select.\(page.id)")
            Text(page.body).font(.callout).textSelection(.enabled)
            if let metadata = page.relationship {
                if let date = metadata.occurredAt ?? metadata.dueAt {
                    Text("\(metadata.kind == .encounter ? "Encounter" : "Due"): \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let status = metadata.commitmentStatus {
                    Text("\(status.title) · reported by you").font(.caption).foregroundStyle(.secondary)
                    if page.state != .withdrawn {
                        HStack {
                            ForEach(RelationshipCommitmentStatus.allCases.filter { $0 != status }, id: \.rawValue) { next in
                                Button("Mark \(next.title.lowercased())") { store.markRelationshipCommitment(page, status: next) }
                            }
                        }.buttonStyle(.borderless).font(.caption)
                    }
                }
            }
            KnowledgePageEvidence(store: store, anchors: page.anchors)
            availability(page)
            recordActions(page)
        }.padding(.vertical, 7)
    }

    @ViewBuilder private func availability(_ page: KnowledgePage) -> some View {
        if let issue = store.readingSources.availability(of: page) {
            Text(issue).font(.caption).foregroundStyle(.orange)
        }
    }

    private func recordActions(_ page: KnowledgePage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Revise…") { store.beginKnowledgePage(page) }
                if page.state == .draft { Button("Mark reviewed") { store.reviewKnowledgePage(page) } }
                Button(expandedHistoryIDs.contains(page.id) ? "Hide history" : "Show history") {
                    if expandedHistoryIDs.contains(page.id) { expandedHistoryIDs.remove(page.id) }
                    else { expandedHistoryIDs.insert(page.id) }
                }
                .accessibilityIdentifier("relationship.history-toggle.\(page.id)")
                if page.state != .withdrawn {
                    Button("Withdraw", role: .destructive) { store.withdrawKnowledgePage(page) }
                }
            }.buttonStyle(.borderless).font(.caption)
            if expandedHistoryIDs.contains(page.id) {
                RelationshipRecordHistory(store: store, pageID: page.id)
            }
        }
    }
}

/// Read-only projection of the same library history; expanding it saves nothing.
@MainActor
private struct RelationshipRecordHistory: View {
    @ObservedObject var store: CompanionStore
    let pageID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Record history").font(.caption.bold())
            ForEach(store.readingSources.knowledgePages.filter { $0.id == pageID }
                .sorted { $0.revision > $1.revision }, id: \.revision) { version in
                VStack(alignment: .leading, spacing: 5) {
                    Text("v\(version.revision) · \(version.state.rawValue.capitalized) · \(version.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(version.title).font(.caption.bold())
                    Text(version.body).font(.caption).textSelection(.enabled)
                    if let metadata = version.relationship {
                        Text(metadata.markdownLines.joined(separator: "\n"))
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    KnowledgePageEvidence(store: store, anchors: version.anchors)
                }
            }
        }.accessibilityElement(children: .contain)
            .accessibilityIdentifier("relationship.history.\(pageID)")
    }
}
