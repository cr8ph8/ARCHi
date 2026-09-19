import SwiftUI

@MainActor
struct PersonalContextCard: View {
    @ObservedObject var store: CompanionStore
    @State private var editing: PersonalContext.Entry?
    @State private var editingBaseline: PersonalContext?
    @State private var forget = false

    var body: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(store.personalContext.map { "About \($0.preferredName)" } ?? "Personal context", systemImage: "person.text.rectangle")
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                    Text("PRIVATE · THIS PROFILE").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                if let profile = store.personalContext {
                    Text("\(profile.name) · \(profile.entries.filter { $0.useInAssistance }.count) details available to local Qwen")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("Starting context helps ARCHi understand you. Shared experience and feedback develop your companion over time.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    DisclosureGroup("Review, correct or forget personal context") {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(profile.entries) { entry in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(entry.title).fontWeight(.medium)
                                        Spacer()
                                        Text(entry.status.rawValue.capitalized).foregroundStyle(.secondary)
                                        Button("Edit") { editingBaseline = profile; editing = entry }
                                            .accessibilityLabel("Edit \(entry.title)")
                                    }
                                    Text(entry.text).textSelection(.enabled)
                                    Text("Source: \(entry.source)").font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled)
                                    Text(entry.useInAssistance ? "Included in local replies" : "Profile reference only")
                                        .font(.system(size: 10)).foregroundStyle(WorkspaceTheme.accent)
                                }.font(.system(size: 12))
                                Divider()
                            }
                            HStack {
                                Button("Add a detail") {
                                    editingBaseline = profile
                                    editing = .init(id: UUID().uuidString, title: "", text: "", status: .proposed,
                                                    source: "Added by you in ARCHi", useInAssistance: false)
                                }.disabled(profile.entries.count >= 24)
                                Spacer()
                                Button("Forget personal context", role: .destructive) { forget = true }
                            }
                        }.padding(.top, 12)
                    }.accessibilityIdentifier("personal-context.details")
                    Text("Local Qwen only. Codex and other external routes receive no personal-profile details. Nothing here grants access or counts as earned growth.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Text("No personal context is saved for this companion. Each profile keeps its own context and history.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("personal-context.card")
        .sheet(item: $editing) { entry in
            PersonalContextEntryEditor(entry: entry,
                canRemove: editingBaseline?.entries.contains(where: { $0.id == entry.id }) == true,
                onKeep: { changed in save(changed, replacing: entry.id) },
                onRemove: { save(nil, replacing: entry.id) })
                .onAppear { store.hasPersonalContextDraft = true }
                .onDisappear { store.hasPersonalContextDraft = false }
        }
        .confirmationDialog("Forget all personal context for this companion?", isPresented: $forget) {
            Button("Forget personal context", role: .destructive) {
                _ = store.updatePersonalContext(nil, expected: store.personalContext)
            }
        } message: { Text("This removes the profile's personal details and clears old local replies. Your companion identity, appearance and earned history remain.") }
    }

    private func save(_ changed: PersonalContext.Entry?, replacing id: String) {
        guard var next = editingBaseline else { return }
        if let index = next.entries.firstIndex(where: { $0.id == id }) {
            if let changed { next.entries[index] = changed } else { next.entries.remove(at: index) }
        } else if let changed { next.entries.append(changed) }
        if store.updatePersonalContext(next, expected: editingBaseline) { editing = nil }
    }
}

@MainActor
private struct PersonalContextEntryEditor: View {
    @State var entry: PersonalContext.Entry
    let canRemove: Bool
    let onKeep: (PersonalContext.Entry) -> Void
    let onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review a personal detail").font(.title2)
            TextField("Topic", text: $entry.title)
            TextEditor(text: $entry.text).frame(height: 110).border(.secondary.opacity(0.25))
                .accessibilityLabel("Personal detail")
            TextField("Source", text: $entry.source)
            Picker("Status", selection: $entry.status) {
                ForEach(PersonalContext.Status.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            Toggle("Use in local Qwen replies", isOn: $entry.useInAssistance).disabled(entry.status != .confirmed)
            Text("Only confirmed details can guide replies. Your current question always takes precedence.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if canRemove { Button("Remove detail", role: .destructive, action: onRemove) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Keep correction") {
                    entry.source = String((entry.source + " · corrected by you").prefix(190))
                    onKeep(entry)
                }.keyboardShortcut(.defaultAction).disabled(!entry.isValid)
            }
        }.padding(24).frame(width: 540)
        .onChange(of: entry.status) { _, value in if value != .confirmed { entry.useInAssistance = false } }
    }
}
