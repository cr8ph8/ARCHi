import SwiftUI

/// A local declaration editor. Opening or cancelling the sheet never changes a
/// source, and the store rechecks the exact source version when saving.
@MainActor
struct ReadingSourceProvenanceEditor: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject private var library: ReadingSourceLibrary
    @State private var openingOwner: ReadingSourceLibrary
    let source: ReadingSourceSnapshot
    @Environment(\.dismiss) private var dismiss
    @State private var origin: ReadingSourceOrigin
    @State private var acquisition: ReadingSourceAcquisition
    @State private var attribution: String
    @State private var parents: [ReadingSourceParent]
    @State private var error: String?

    init(store: CompanionStore, source: ReadingSourceSnapshot) {
        self.store = store
        self.source = source
        _library = ObservedObject(wrappedValue: store.readingSources)
        _openingOwner = State(initialValue: store.readingSources)
        _origin = State(initialValue: source.provenance?.origin ?? .unknown)
        _acquisition = State(initialValue: source.provenance?.acquisition ?? .unknown)
        _attribution = State(initialValue: source.provenance?.attribution ?? "")
        _parents = State(initialValue: source.provenance?.parents ?? [])
    }

    private var unavailableReason: String? {
        if store.readingSources !== openingOwner { return "The active profile changed. Cancel and reopen this source in the current profile." }
        if store.profileRecoveryBlock != nil { return "Finish profile recovery before editing source details." }
        if store.isShuttingDown { return "ARCHi is closing. Reopen before changing this source." }
        if store.isWorking { return "Wait for the current request to finish before saving." }
        if !library.isCurrentOnDisk { return "The reading library changed or needs recovery. Reopen ARCHi before saving." }
        if !library.sources.contains(source) { return "This copy changed while the editor was open. Cancel and reopen its source details." }
        if attribution.utf8.count > 240 { return "Shorten the source note to 240 UTF-8 bytes or fewer." }
        if parents.count > 4 { return "Keep up to four original copies." }
        if acquisition == .derivedCopy && parents.isEmpty { return "Attach at least one original for a derived copy." }
        if parents.contains(where: { parentUnavailableReason($0) != nil }) {
            return "An attached original is unavailable. Remove it explicitly, then choose a current copy if appropriate."
        }
        return nil
    }

    private var availableParents: [ReadingSourceSnapshot] {
        library.sources.filter { candidate in
            candidate.id != source.id
                && !parents.contains(where: { $0.id == candidate.id })
                && library.availability(of: candidate.binding) == nil
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Source details").font(.title2.weight(.medium))
            Text(source.title + " · v\(source.revision)")
                .font(.callout).lineLimit(2).textSelection(.enabled)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Record what you know about this copy. These are your declarations; they do not verify authorship or whether the content is true. Unknown is a valid choice.")
                        .font(.callout).foregroundStyle(.secondary)
                    Picker("Content created by", selection: $origin) {
                        ForEach(ReadingSourceOrigin.allCases, id: \.title) { value in
                            Text(value.title).tag(value)
                        }
                    }.accessibilityIdentifier("source-origin.origin")
                    Picker("How this copy arrived", selection: $acquisition) {
                        ForEach(ReadingSourceAcquisition.allCases, id: \.title) { value in
                            Text(value.title).tag(value)
                        }
                    }.accessibilityIdentifier("source-origin.acquisition")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Source note (optional)").font(.headline)
                        TextField("Author, publisher, model, or other known context", text: $attribution, axis: .vertical)
                            .lineLimit(2...3).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("source-origin.attribution")
                        Text("\(attribution.utf8.count)/240 UTF-8 bytes")
                            .font(.caption).foregroundStyle(attribution.utf8.count > 240 ? Color.orange : Color.secondary)
                    }
                    Divider()
                    originalCopies
                    Text("Saving an edit creates a new source version. Notes and methods that depend on this copy need fresh review.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let reason = unavailableReason {
                        Text(reason).font(.callout).foregroundStyle(.orange)
                            .accessibilityIdentifier("source-origin.unavailable")
                    }
                    if let error {
                        Text(error).font(.callout).foregroundStyle(.red)
                            .accessibilityIdentifier("source-origin.error")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("source-origin.cancel")
                Spacer()
                Button("Save source details", action: save)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(unavailableReason != nil)
                    .accessibilityIdentifier("source-origin.save")
            }
        }.padding(22).frame(width: 520, height: 620)
    }

    private var originalCopies: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Original copies · \(parents.count)/4").font(.headline)
            Text("If this content was adapted, summarized, or generated from kept copies, attach those exact versions. A link records derivation; it does not make the result independently verified.")
                .font(.caption).foregroundStyle(.secondary)
            if parents.isEmpty {
                Text("No originals attached.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(parents) { parent in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(parentTitle(parent)).font(.callout).lineLimit(2)
                        if let reason = parentUnavailableReason(parent) {
                            Text(reason).font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Spacer(minLength: 4)
                    Button("Remove") {
                        parents.removeAll { $0.id == parent.id }
                        error = nil
                    }.buttonStyle(.borderless)
                        .accessibilityLabel("Remove original \(parentTitle(parent))")
                        .accessibilityIdentifier("source-origin.parent.\(parent.id).remove")
                }.accessibilityIdentifier("source-origin.parent.\(parent.id)")
            }
            if !availableParents.isEmpty {
                Text("Attach a current copy").font(.subheadline.weight(.medium))
                ForEach(availableParents) { candidate in
                    HStack {
                        Text(candidate.title + " · v\(candidate.revision)").font(.callout).lineLimit(2)
                        Spacer(minLength: 4)
                        Button("Attach") {
                            guard parents.count < 4,
                                  !parents.contains(where: { $0.id == candidate.id }),
                                  library.availability(of: candidate.binding) == nil else { return }
                            parents.append(ReadingSourceParent(binding: candidate.binding))
                            error = nil
                        }.buttonStyle(.borderless)
                            .disabled(parents.count >= 4 || store.isWorking || store.isShuttingDown || !library.isCurrentOnDisk)
                            .accessibilityLabel("Attach original \(candidate.title)")
                            .accessibilityIdentifier("source-origin.parent.\(candidate.id)")
                    }
                }
            } else {
                Text("No other current copies are available to attach.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func parentUnavailableReason(_ parent: ReadingSourceParent) -> String? {
        guard let current = library.sources.first(where: { parent.matches($0.binding) }) else {
            return "This exact original version changed or is no longer kept."
        }
        return library.availability(of: current.binding)
    }

    private func parentTitle(_ parent: ReadingSourceParent) -> String {
        let title = library.sources.first { $0.id == parent.id }?.title
            ?? "Copy no longer kept (\(parent.id.prefix(8)))"
        return title + " · v\(parent.revision)"
    }

    private func save() {
        guard unavailableReason == nil else { return }
        do {
            try store.declareReadingSourceProvenance(source: source, origin: origin,
                acquisition: acquisition, attribution: attribution, parents: parents)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
