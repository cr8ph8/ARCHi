import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension CompanionStore {
    var currentReadingReferences: [ReadingSourceSnapshot] {
        readingSources.sources.filter { selectedReadingSourceIDs.contains($0.id) }.sorted { $0.id < $1.id }
    }

    func readingDependenciesAreCurrent(_ dependencies: [ReadingSourceBinding]?) -> Bool {
        guard let dependencies else { return true }
        guard ReadingSourceBinding.valid(dependencies), readingSources.isCurrentOnDisk else { return false }
        return dependencies.allSatisfy { readingSources.availability(of: $0) == nil }
    }

    func readingReferencesAreCurrent(_ references: [ReadingSourceSnapshot]) -> Bool {
        if references.isEmpty { return true }
        return readingDependenciesAreCurrent(references.map(\.binding))
            && references.allSatisfy { readingSources.sources.contains($0) }
    }

    func selectReadingSource(_ id: String, selected: Bool) {
        guard !isShuttingDown, readingSources.isCurrentOnDisk,
              let source = readingSources.sources.first(where: { $0.id == id }) else { return }
        if selected, let reason = readingSources.availability(of: source.binding) {
            documentReadingMessage = reason; return
        }
        guard !selected || selectedReadingSourceIDs.contains(id) || selectedReadingSourceIDs.count < 4 else {
            documentReadingMessage = "Choose up to four kept copies for one reading."; return
        }
        guard selected != selectedReadingSourceIDs.contains(id) else { return }
        invalidateReadingContext(reason: "Reading sources changed. Earlier answers and temporary context were cleared.")
        if selected { selectedReadingSourceIDs.insert(id) } else { selectedReadingSourceIDs.remove(id) }
    }

    func keepCurrentReadingSource() {
        guard !isShuttingDown, profileRecoveryBlock == nil, let name = sourceName else { return }
        retainReadingSource(title: name, text: sharedText)
    }

    private func retainReadingSource(title: String, text: String) {
        do {
            try keepReadingSourceText(title: title, text: text)
        } catch { documentReadingMessage = error.localizedDescription }
    }

    /// Common explicit writer for pasted text and selected file copies.
    func keepReadingSourceText(title: String, text: String) throws {
        guard !isWorking, !isShuttingDown, profileRecoveryBlock == nil else {
            throw ReadingSourceLibraryError.invalid("Finish the current request or recovery before keeping a copy.")
        }
        let source = try readingSources.keep(title: title, text: text,
            provenance: ReadingSourceProvenance(origin: .unknown, acquisition: .userCopy))
        if selectedReadingSourceIDs.count < 4 { selectReadingSource(source.id, selected: true) }
        documentReadingMessage = "Copy kept on this Mac. Select it to use with the current document."
    }

    func importReadingSource() {
        guard !isShuttingDown, profileRecoveryBlock == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Keep a reading copy"
        panel.message = "Choose a UTF-8 text or Markdown file, up to 100 KB. This saves a local copy; it does not send it."
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .text, UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 100_000 else {
                documentReadingMessage = "Choose a text file no larger than 100 KB."; return
            }
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            let data = try handle.read(upToCount: 100_001) ?? Data()
            guard data.count <= 100_000, let text = String(data: data, encoding: .utf8) else {
                documentReadingMessage = "Choose a UTF-8 text file no larger than 100 KB."; return
            }
            retainReadingSource(title: url.lastPathComponent, text: text)
        } catch { documentReadingMessage = "This copy could not be read. No source was added." }
    }

    func replaceReadingSource(_ id: String) {
        guard !isShuttingDown, profileRecoveryBlock == nil, let name = sourceName else { return }
        do {
            _ = try readingSources.replace(id: id, title: name, text: sharedText)
            invalidateReadingContext(reason: "Reading copy updated. Dependent lessons and earlier answers need fresh review.")
        } catch { documentReadingMessage = error.localizedDescription }
    }

    func forgetReadingSource(_ id: String) {
        guard !isShuttingDown, profileRecoveryBlock == nil else { return }
        do {
            try readingSources.forget(id: id)
            selectedReadingSourceIDs.remove(id)
            invalidateReadingContext(reason: "Reading copy forgotten. Dependent lessons remain visible but cannot be reused.")
        } catch { documentReadingMessage = error.localizedDescription }
    }

    func declareReadingSourceProvenance(source: ReadingSourceSnapshot, origin: ReadingSourceOrigin,
                                        acquisition: ReadingSourceAcquisition, attribution: String,
                                        parents: [ReadingSourceParent]) throws {
        guard !isShuttingDown, !isWorking, profileRecoveryBlock == nil else {
            throw ReadingSourceLibraryError.invalid("Finish the current request or profile recovery before editing source details.")
        }
        let updated = try readingSources.declareProvenance(source: source, origin: origin,
            acquisition: acquisition, attribution: attribution, parents: parents)
        if updated != source {
            invalidateReadingContext(reason: "Source details updated. Dependent notes, methods and earlier answers need fresh review.")
        }
    }
}

@MainActor
struct ReadingSourceLibraryView: View {
    @ObservedObject var store: CompanionStore
    @State private var editingSource: ReadingSourceSnapshot?
    @State private var addingText = false
    var body: some View {
        DisclosureGroup("Reading library · \(store.readingSources.sources.count) kept · \(store.selectedReadingSourceIDs.count) selected") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Keep documents or meeting notes to read together. Select up to four copies alongside your current document; selections last for this visit.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Keep current copy") { store.keepCurrentReadingSource() }
                        .disabled(store.sourceName == nil || store.sharedText.isEmpty || store.isWorking)
                        .accessibilityIdentifier("work.reading.keep")
                    Button("Add text file…") { store.importReadingSource() }
                        .disabled(store.isWorking).accessibilityIdentifier("work.reading.import")
                    Button("Paste text…") { addingText = true }
                        .disabled(store.isWorking).accessibilityIdentifier("work.reading.paste")
                }
                if let error = store.readingSources.loadError { Text(error).foregroundStyle(.orange) }
                ForEach(store.readingSources.sources) { source in
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: Binding(get: { store.selectedReadingSourceIDs.contains(source.id) },
                                             set: { store.selectReadingSource(source.id, selected: $0) })) {
                            Text(source.title + " · v\(source.revision)")
                        }.toggleStyle(.checkbox)
                            .disabled(store.isWorking || (!store.selectedReadingSourceIDs.contains(source.id)
                                && store.readingSources.availability(of: source.binding) != nil))
                            .accessibilityIdentifier("work.reading.source.\(source.id)")
                        Text(source.provenance.map { "\($0.origin.title) · \($0.acquisition.title) · declared, not verified" }
                            ?? "Origin unknown · no source declaration")
                            .foregroundStyle(.secondary)
                        if let reason = store.readingSources.availability(of: source.binding) {
                            Text(reason).foregroundStyle(.orange)
                        }
                        DisclosureGroup("Inspect kept copy") { Text(source.text).textSelection(.enabled) }
                        HStack {
                            Button("Source details…") { editingSource = source }
                                .disabled(store.isWorking || store.isShuttingDown)
                                .accessibilityIdentifier("work.reading.origin.\(source.id)")
                            Button("Replace with current copy") { store.replaceReadingSource(source.id) }
                                .disabled(store.sourceName == nil || store.isWorking)
                            Button("Forget", role: .destructive) { store.forgetReadingSource(source.id) }
                                .disabled(store.isWorking)
                        }.buttonStyle(.borderless)
                    }.padding(.vertical, 3)
                }
                Text("Copies are stored as text on this Mac, outside companion recovery packages. Originals are not watched. Replacing or forgetting a source makes its dependent copies, notes and methods unavailable for reuse until reviewed. Source details record your declaration, not proof of authorship.")
                    .foregroundStyle(.secondary)
                if !store.selectedReadingSourceIDs.isEmpty {
                    Text("Selected copies use local Qwen only. External fallback is disabled for this reading.")
                        .foregroundStyle(.secondary)
                }
            }.padding(.top, 6)
        }.font(.caption2).accessibilityIdentifier("work.reading.library")
            .sheet(item: $editingSource) { source in
                ReadingSourceProvenanceEditor(store: store, source: source)
            }
            .sheet(isPresented: $addingText) { ReadingSourceTextEditor(store: store) }
    }
}

/// A direct entry path for meeting notes and text when a file is unnecessary.
/// Typing is transient. Only Keep writes through the existing source owner.
@MainActor
private struct ReadingSourceTextEditor: View {
    @ObservedObject var store: CompanionStore
    @State private var owner: ReadingSourceLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var error: String?

    init(store: CompanionStore) {
        self.store = store
        _owner = State(initialValue: store.readingSources)
    }

    private var canKeep: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.utf8.count <= 240
            && (1...100_000).contains(text.utf8.count) && store.readingSources === owner
            && owner.isCurrentOnDisk && !store.isWorking && !store.isShuttingDown && store.profileRecoveryBlock == nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keep a text copy").font(.title2)
            Text("Paste a document or meeting notes. Keep saves this copy on your Mac; it sends nothing. Authorship stays unknown until you declare it in Source details.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Title", text: $title).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("source-text.title")
            TextEditor(text: $text).font(.body).frame(minHeight: 260)
                .accessibilityLabel("Text to keep").accessibilityIdentifier("source-text.body")
            Text("\(text.utf8.count)/100,000 UTF-8 bytes · title \(title.utf8.count)/240")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.orange) }
            if store.readingSources !== owner { Text("Profile changed. Cancel and reopen for the active profile.").foregroundStyle(.orange) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("source-text.cancel")
                Spacer()
                Button("Keep copy") {
                    guard canKeep else { return }
                    do { try store.keepReadingSourceText(title: title, text: text); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!canKeep).accessibilityIdentifier("source-text.keep")
            }
        }.padding(22).frame(width: 560, height: 540)
    }
}
