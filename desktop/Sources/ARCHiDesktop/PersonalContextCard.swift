import SwiftUI

@MainActor
struct PersonalContextCard: View {
    @ObservedObject var store: CompanionStore
    @State private var editing: PersonalContext.Entry?
    @State private var editingBaseline: PersonalContext?
    @State private var saveError: String?
    @State private var forget = false
    @State private var forgetBaseline: PersonalContext?
    @State private var expanded = false
    @State private var search = ""
    @State private var filter = PersonalContextFilter.all

    var body: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 16) {
                if let profile = store.personalContext {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 20) { identity(profile); Spacer(minLength: 12); addButton(profile) }
                        VStack(alignment: .leading, spacing: 12) { identity(profile); addButton(profile) }
                    }
                    Text("Personal context you can inspect and change. Choose which confirmed details help with local replies.")
                        .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        count(profile, matching: .local, label: "Local replies", icon: "desktopcomputer")
                        count(profile, matching: .reference, label: "Reference", icon: "bookmark")
                        count(profile, matching: .open, label: "Open details", icon: "questionmark.circle")
                    }
                    if !store.marketplaceOutfitReadable {
                        Label("Showing the last loaded context. Reopen after resolving profile recovery to make changes.", systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("personal-context.unavailable")
                    }
                    DisclosureGroup(isExpanded: $expanded) {
                        details(profile).padding(.top, 12)
                            .accessibilityElement(children: .contain)
                    } label: {
                        Text("Review personal details").font(.subheadline.weight(.medium))
                    }.accessibilityIdentifier("personal-context.details")
                    Text("Local Qwen only. Codex and other external routes receive no personal-profile details. This context grants no access and does not count as earned growth.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Label("Personal context", systemImage: "person.text.rectangle").font(.headline)
                    Text(store.marketplaceOutfitReadable
                         ? "No personal context is saved for this companion. Each profile keeps its own context and history."
                         : "Personal context is unavailable while this profile needs recovery. Saved files have been preserved.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let saveError, editing == nil {
                    Text(saveError).font(.caption).foregroundStyle(.red).accessibilityIdentifier("personal-context.save-error")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("personal-context.card")
        .sheet(item: $editing) { entry in
            PersonalContextEntryEditor(entry: entry, baseline: editingBaseline,
                canRemove: editingBaseline?.entries.contains(where: { $0.id == entry.id }) == true,
                saveError: $saveError,
                onKeep: { changed in save(changed, replacing: entry.id) },
                onRemove: { save(nil, replacing: entry.id) })
                .onAppear { store.hasPersonalContextDraft = true }
                .onDisappear { store.hasPersonalContextDraft = false }
        }
        .confirmationDialog("Forget all personal context for this companion?", isPresented: $forget) {
            Button("Forget personal context", role: .destructive) {
                if store.updatePersonalContext(nil, expected: forgetBaseline) { saveError = nil }
                else { saveError = store.status }
            }.accessibilityIdentifier("personal-context.forget-confirm")
        } message: {
            Text("This removes the profile's personal details and clears old local replies. Your companion identity, appearance and earned history remain.")
        }
    }

    private func identity(_ profile: PersonalContext) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("About \(profile.preferredName)", systemImage: "person.text.rectangle")
                .font(.title3.weight(.semibold)).accessibilityIdentifier("personal-context.identity")
            Text(profile.name).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("personal-context.name")
            Label("Private · this profile", systemImage: "lock").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func addButton(_ profile: PersonalContext) -> some View {
        Button("Add a detail", systemImage: "plus") {
            beginEditing(.init(id: UUID().uuidString, title: "", text: "", status: .proposed,
                               source: "Added in ARCHi", useInAssistance: false), in: profile)
        }
        .buttonStyle(WorkspaceActionStyle(prominent: true))
        .disabled(profile.entries.count >= 24 || !store.marketplaceOutfitReadable)
        .help(profile.entries.count >= 24 ? "This profile holds 24 details. Remove a detail before adding another." : "Add a source-qualified personal detail.")
        .accessibilityIdentifier("personal-context.add")
    }

    private func count(_ profile: PersonalContext, matching category: PersonalContextFilter, label: String, icon: String) -> some View {
        Button { filter = category; expanded = true } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(profile.entries.filter(category.includes).count)").font(.title3.weight(.semibold)).monospacedDigit()
                Label(label, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            .background(WorkspaceTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(profile.entries.filter(category.includes).count) \(label.lowercased())")
        .accessibilityHint("Expand and filter personal details.")
        .accessibilityIdentifier("personal-context.count.\(category.rawValue)")
    }

    private func details(_ profile: PersonalContext) -> some View {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = profile.entries.filter { entry in
            filter.includes(entry) && (query.isEmpty
                || [entry.title, entry.text, entry.source, entry.status.rawValue].contains { $0.localizedCaseInsensitiveContains(query) })
        }
        return VStack(alignment: .leading, spacing: 12) {
            TextField("Search details or sources", text: $search)
                .textFieldStyle(.roundedBorder).accessibilityLabel("Search personal details")
                .accessibilityIdentifier("personal-context.search")
            Picker("Show", selection: $filter) {
                ForEach(PersonalContextFilter.allCases, id: \.self) { value in Text(value.title).tag(value) }
            }.pickerStyle(.segmented).accessibilityIdentifier("personal-context.filter")
            if matching.isEmpty {
                Text(profile.entries.isEmpty ? "Add a detail when you have something you want ARCHi to know. Unknowns can stay unknown."
                     : "No details match this search and filter.")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12)
                    .accessibilityIdentifier("personal-context.empty")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(matching) { entry in
                            PersonalContextDetailRow(entry: entry, canEdit: store.marketplaceOutfitReadable) { beginEditing(entry, in: profile) }
                            if entry.id != matching.last?.id { Divider() }
                        }
                    }.padding(.trailing, 6)
                }
                .frame(height: min(CGFloat(matching.count) * 148, 380))
                .accessibilityIdentifier("personal-context.rows")
            }
            HStack(alignment: .firstTextBaseline) {
                Text("\(matching.count) of \(profile.entries.count) details").font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("personal-context.results")
                Spacer()
                Button("Forget personal context", role: .destructive) { forgetBaseline = profile; forget = true }
                    .buttonStyle(.borderless).disabled(!store.marketplaceOutfitReadable)
                    .accessibilityIdentifier("personal-context.forget")
            }
        }
    }

    private func beginEditing(_ entry: PersonalContext.Entry, in profile: PersonalContext) {
        saveError = nil; editingBaseline = profile; editing = entry
    }

    private func save(_ changed: PersonalContext.Entry?, replacing id: String) {
        guard var next = editingBaseline else { return }
        if let index = next.entries.firstIndex(where: { $0.id == id }) {
            if let changed { next.entries[index] = changed } else { next.entries.remove(at: index) }
        } else if let changed { next.entries.append(changed) }
        if store.updatePersonalContext(next, expected: editingBaseline) { saveError = nil; editing = nil }
        else { saveError = store.status }
    }
}

private enum PersonalContextFilter: String, CaseIterable {
    case all, local, reference, open
    var title: String {
        switch self { case .all: "All"; case .local: "Local replies"; case .reference: "Reference"; case .open: "Open details" }
    }
    func includes(_ entry: PersonalContext.Entry) -> Bool {
        switch self {
        case .all: true
        case .local: entry.status == .confirmed && entry.useInAssistance
        case .reference: entry.status == .confirmed && !entry.useInAssistance
        case .open: entry.status != .confirmed
        }
    }
}

private struct PersonalContextDetailRow: View {
    let entry: PersonalContext.Entry
    let canEdit: Bool
    let onEdit: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.title).font(.subheadline.weight(.semibold)).accessibilityIdentifier("personal-context.row.\(entry.id).title")
                Spacer(minLength: 8)
                Button("Edit", action: onEdit).buttonStyle(.borderless).disabled(!canEdit)
                    .accessibilityLabel("Edit \(entry.title)").accessibilityIdentifier("personal-context.row.\(entry.id).edit")
            }
            Label(statusText, systemImage: statusIcon).font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("personal-context.row.\(entry.id).status")
            Text(entry.text).font(.subheadline).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("personal-context.row.\(entry.id).text")
            DisclosureGroup("Source") {
                Text(entry.source).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    .accessibilityIdentifier("personal-context.row.\(entry.id).source-text")
            }.font(.caption).accessibilityIdentifier("personal-context.row.\(entry.id).source")
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("personal-context.row.\(entry.id)")
    }
    private var statusText: String {
        switch entry.status {
        case .confirmed: entry.useInAssistance ? "Confirmed · available to local replies" : "Confirmed · profile reference only"
        case .proposed: "Proposed · awaiting review · not used in replies"
        case .unknown: "Unknown · left open · not used in replies"
        }
    }
    private var statusIcon: String {
        switch entry.status { case .confirmed: "checkmark.circle"; case .proposed: "pencil.circle"; case .unknown: "questionmark.circle" }
    }
}

@MainActor
private struct PersonalContextEntryEditor: View {
    @State var entry: PersonalContext.Entry
    let baseline: PersonalContext?
    let canRemove: Bool
    @Binding var saveError: String?
    let onKeep: (PersonalContext.Entry) -> Void
    let onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(canRemove ? "Review a personal detail" : "Add a personal detail").font(.title2)
            TextField("Topic", text: $entry.title).accessibilityIdentifier("personal-context.editor.topic")
            TextEditor(text: $entry.text).frame(height: 110).border(.secondary.opacity(0.25))
                .accessibilityLabel("Personal detail").accessibilityIdentifier("personal-context.editor.text")
            TextField("Source", text: $entry.source, axis: .vertical).lineLimit(1...3)
                .accessibilityIdentifier("personal-context.editor.source")
            Text("Keep the original source or update it explicitly. Saving does not rewrite attribution.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Status", selection: $entry.status) {
                ForEach(PersonalContext.Status.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }.accessibilityIdentifier("personal-context.editor.status")
            Toggle("Use in local Qwen replies", isOn: $entry.useInAssistance).disabled(entry.status != .confirmed)
                .accessibilityIdentifier("personal-context.editor.local-use")
            Text("Only confirmed details can guide local replies. Proposed and unknown details remain available for your review. Your current question takes precedence.")
                .font(.caption).foregroundStyle(.secondary)
            if let issue = validationIssue {
                Label(issue, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("personal-context.editor.validation")
            }
            if let saveError {
                Text(saveError).font(.caption).foregroundStyle(.red).accessibilityIdentifier("personal-context.editor.save-error")
            }
            HStack {
                if canRemove {
                    Button("Remove detail", role: .destructive, action: onRemove).accessibilityIdentifier("personal-context.editor.remove")
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("personal-context.editor.cancel")
                Button(canRemove ? "Save detail" : "Add detail") { onKeep(entry) }
                    .keyboardShortcut(.defaultAction).disabled(validationIssue != nil).accessibilityIdentifier("personal-context.editor.save")
            }
        }.padding(24).frame(width: 540)
        .onChange(of: entry.status) { _, value in if value != .confirmed { entry.useInAssistance = false } }
    }

    private var validationIssue: String? {
        if entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add a topic for this detail." }
        if entry.title.utf8.count > 120 { return "The topic exceeds 120 UTF-8 bytes. Shorten it before saving." }
        if entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add the detail, including what remains unknown when appropriate." }
        if entry.text.utf8.count > 1_200 { return "The detail exceeds 1,200 UTF-8 bytes. Shorten it before saving." }
        if entry.source.isEmpty { return "Add a source or describe where this detail came from." }
        if entry.source.utf8.count > 800 { return "The source exceeds 800 UTF-8 bytes. Edit it explicitly; ARCHi will not truncate it." }
        guard entry.isValid, var next = baseline else { return "This detail needs correction before it can be saved." }
        if let index = next.entries.firstIndex(where: { $0.id == entry.id }) { next.entries[index] = entry }
        else { next.entries.append(entry) }
        if next.entries.filter({ $0.useInAssistance }).reduce(0, { $0 + $1.title.utf8.count + $1.text.utf8.count }) > 6_000 {
            return "Local reply context is full. Keep this detail as a reference or shorten the enabled details."
        }
        return next.isValid ? nil : "This profile is at its saved-context limit or needs correction. Review it before saving."
    }
}
