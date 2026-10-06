import SwiftUI

/// Deterministic source lookup is independent of optional experimental measuring.
/// All view state is transient; kept sources remain owned by ReadingSourceLibrary.
@MainActor
struct RecordLookupCard: View {
    private struct SourceOwnerIdentity: Equatable {
        let store: ObjectIdentifier
        let library: ObjectIdentifier
    }
    private struct FreshnessIdentity: Equatable {
        let owner: SourceOwnerIdentity
        let source: ReadingSourceBinding
        let librarySources: [ReadingSourceBinding]
    }

    @ObservedObject var store: CompanionStore
    @State private var selectedSourceID = ""
    @State private var selectedRecordID = ""
    @State private var selectedField: RecordLookupField = .location
    @State private var sampleSource: ReadingSourceSnapshot?
    @State private var libraryCurrent = true
    @State private var measurement: RecordMeasurement?
    @State private var measurementMessage: String?
    @State private var measurementID: UUID?
    @State private var measurementTask: Task<Void, Never>?
    @State private var client = RecordMeasurementClient()

    private var source: ReadingSourceSnapshot? {
        if let sampleSource, sampleSource.id == selectedSourceID { return sampleSource }
        return store.readingSources.sources.first { $0.id == selectedSourceID }
    }
    private var isSample: Bool { sampleSource?.id == selectedSourceID && sampleSource != nil }
    private var sourceOwnerIdentity: SourceOwnerIdentity {
        SourceOwnerIdentity(store: ObjectIdentifier(store), library: ObjectIdentifier(store.readingSources))
    }
    private var freshnessIdentity: FreshnessIdentity? {
        guard !isSample, let source else { return nil }
        return FreshnessIdentity(owner: sourceOwnerIdentity, source: source.binding,
            librarySources: store.readingSources.sources.map(\.binding))
    }
    private var sourceIsCurrent: Bool {
        guard store.profileRecoveryBlock == nil else { return false }
        if isSample { return true }
        guard libraryCurrent else { return false }
        guard let source else { return selectedSourceID.isEmpty }
        return ReadingSourceLineage.availability(of: source.binding, in: store.readingSources.sources) == nil
    }
    private var table: RecordLookupTable? {
        guard sourceIsCurrent, let source else { return nil }
        return try? RecordLookupTable(source: source, kind: isSample ? .sample : .kept)
    }
    private var query: RecordLookupQuery? {
        guard let table else { return nil }
        return try? table.query(recordID: selectedRecordID, field: selectedField)
    }
    private var parseMessage: String? {
        guard let source, sourceIsCurrent else { return nil }
        do { _ = try RecordLookupTable(source: source, kind: isSample ? .sample : .kept); return nil }
        catch { return error.localizedDescription }
    }

    var body: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Record lookup", systemImage: "tablecells").font(.headline)
                Text("Look up an exact field in a table you choose.")
                    .font(.callout).foregroundStyle(.secondary)
                sourcePicker
                if !sourceIsCurrent {
                    Text("The kept table or a parent source changed, was forgotten, or needs recovery. Review the source lineage before using this table.")
                        .font(.caption).foregroundStyle(.orange)
                } else if let table {
                    queryControls(table)
                    if let query { lookupResult(query) }
                } else if let parseMessage {
                    Text(parseMessage).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("record-lookup.format-error")
                } else {
                    Text("Choose a kept table, add a text file, or try the unsaved example.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                formatHelp
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("record-lookup.card")
        .onChange(of: selectedSourceID) { _, _ in sourceChanged() }
        .onChange(of: source?.binding) { _, _ in sourceChanged() }
        .onChange(of: sourceOwnerIdentity) { _, _ in resetSelection() }
        .onChange(of: store.profileRecoveryBlock) { _, block in if block != nil { resetSelection() } }
        .onChange(of: selectedRecordID) { _, _ in clearMeasurement() }
        .onChange(of: selectedField) { _, _ in clearMeasurement() }
        .onChange(of: store.activeQiMon?.originDigest) { _, _ in clearMeasurement() }
        .onChange(of: store.isWorking) { _, working in if working { clearMeasurement() } }
        .onChange(of: store.isShuttingDown) { _, stopping in
            if stopping { clearMeasurement(); client.shutdown() }
        }
        .onDisappear { clearMeasurement() }
        .task(id: freshnessIdentity) {
            // A kept source can change on disk without a published in-app edit.
            // No library reads are needed for an empty selection or the sample.
            guard let watched = freshnessIdentity else { return }
            while !Task.isCancelled {
                guard freshnessIdentity == watched else { return }
                refreshFreshness()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Table source", selection: $selectedSourceID) {
                Text("Choose a source").tag("")
                if let sampleSource { Text("Sample records · this visit").tag(sampleSource.id) }
                ForEach(store.readingSources.sources) { source in
                    Text("\(source.title) · v\(source.revision)").tag(source.id)
                }
            }.accessibilityIdentifier("record-lookup.source")
            HStack {
                Button("Add text file…") { store.importReadingSource() }
                    .disabled(store.isWorking || store.isShuttingDown || store.profileRecoveryBlock != nil)
                    .accessibilityIdentifier("record-lookup.add-source")
                if isSample {
                    Button("Exit example") { selectedSourceID = ""; sampleSource = nil; clearMeasurement() }
                        .accessibilityIdentifier("record-lookup.exit-example")
                } else {
                    Button("Try example") {
                        clearMeasurement()
                        let sample = ReadingSourceSnapshot(id: UUID().uuidString, title: "Sample records", revision: 1,
                                                           text: RecordLookupTable.example)
                        sampleSource = sample
                        selectedSourceID = sample.id
                        selectedField = .location
                    }
                    .disabled(store.isWorking || store.isShuttingDown)
                    .accessibilityIdentifier("record-lookup.try-example")
                }
            }.buttonStyle(.borderless).font(.caption)
        }
    }

    private func queryControls(_ table: RecordLookupTable) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if isSample {
                Text("Sample records · not saved · no real-world claim")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("record-lookup.sample-notice")
            }
            HStack {
                Picker("Record", selection: $selectedRecordID) {
                    ForEach(table.recordIDs, id: \.self) { Text($0).tag($0) }
                }.accessibilityIdentifier("record-lookup.record")
                Picker("Field", selection: $selectedField) {
                    ForEach(RecordLookupField.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.accessibilityIdentifier("record-lookup.field")
            }
        }
    }

    private func lookupResult(_ query: RecordLookupQuery) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(query.value ?? "Need source").font(.title3.weight(.medium)).textSelection(.enabled)
                .accessibilityIdentifier("record-lookup.answer")
            Text(query.value == nil
                 ? "No exact \(query.field.rawValue) field is present for \(query.recordID) in this table."
                 : "Exact table value · \(query.recordID) / \(query.field.rawValue)")
                .font(.caption).foregroundStyle(.secondary)
            Text(query.sourceKind == .sample ? "Source: Sample records · this visit only"
                 : "Source: \(query.sourceTitle) · v\(query.sourceBinding.revision)")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("record-lookup.citation")
            DisclosureGroup(query.sourceKind == .sample ? "View sample table" : "View selected source") {
                if let source {
                    Text(source.text).font(.caption.monospaced()).textSelection(.enabled)
                    if query.sourceKind == .kept {
                        Text("Source ID: \(query.sourceBinding.id)\nSHA-256: \(query.sourceBinding.digest)")
                            .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }.font(.caption)
            Divider()
            measurementControls(query)
        }
    }

    private func measurementControls(_ query: RecordLookupQuery) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                if measurementTask != nil {
                    ProgressView().controlSize(.small)
                    Text("Measuring locally…").font(.caption)
                    Button("Stop") { clearMeasurement(); measurementMessage = "Measurement stopped." }
                        .accessibilityIdentifier("record-lookup.stop")
                } else {
                    Button("Measure locally with Qwen") { measure(query) }
                        .disabled(!RecordMeasurementClient.available || store.isWorking || store.isShuttingDown)
                        .accessibilityIdentifier("record-lookup.measure")
                }
            }.buttonStyle(.borderless)
            Text("Experimental everyday transfer. Only this table and question are measured locally; no answer is generated. The score is not a probability or verification of the lookup answer.")
                .font(.caption).foregroundStyle(.secondary)
            if let measurement {
                Text("Reader score: \(measurement.standardizedScore.formatted(.number.precision(.fractionLength(4))))")
                    .font(.caption.weight(.medium)).accessibilityIdentifier("record-lookup.score")
                DisclosureGroup("Measurement details") {
                    Text("Raw score: \(measurement.rawScore.formatted(.number.precision(.fractionLength(6))))")
                    Text("\(measurement.inputTokens) input tokens · \(measurement.outputTokens) generated tokens")
                    Text("Reader: \(measurement.readerDigest)\nRequest: \(measurement.requestID)")
                        .textSelection(.enabled)
                }.font(.caption2).foregroundStyle(.secondary)
            }
            if let measurementMessage {
                Text(measurementMessage).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("record-lookup.measurement-status")
            } else if !RecordMeasurementClient.available {
                Text("Local measurement is unavailable in this build. Exact table lookup remains available.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var formatHelp: some View {
        DisclosureGroup("Table format") {
            VStack(alignment: .leading, spacing: 5) {
                Text(RecordLookupTable.example).font(.caption.monospaced()).textSelection(.enabled)
                Text("Use the header and exactly two record IDs, with one row per field. Values are 1–96 printable ASCII characters; no |, = or reserved model markers. Keep up to 12 fields per record. Spaces around cells are ignored.")
                Text("Fields: " + RecordLookupField.allCases.map(\.rawValue).joined(separator: ", ") + ".")
                Text("Add a text file here, or keep your own table through Keep a note in People & follow-through. No fields are inferred from prose.")
            }.font(.caption).foregroundStyle(.secondary).padding(.top, 4)
        }.font(.caption).accessibilityIdentifier("record-lookup.format")
    }

    private func sourceChanged() {
        clearMeasurement()
        if let sampleSource, selectedSourceID != sampleSource.id { self.sampleSource = nil }
        refreshFreshness()
        selectedRecordID = table?.recordIDs.first ?? ""
    }

    private func refreshFreshness() {
        let current = store.profileRecoveryBlock == nil
            && (isSample || (source.map { store.readingSources.availability(of: $0.binding) == nil }
                ?? selectedSourceID.isEmpty))
        if !current { clearMeasurement() }
        libraryCurrent = current
    }

    private func resetSelection() {
        clearMeasurement()
        client.shutdown()
        client = RecordMeasurementClient()
        selectedSourceID = ""
        selectedRecordID = ""
        selectedField = .location
        sampleSource = nil
        libraryCurrent = store.profileRecoveryBlock == nil
    }

    private func clearMeasurement() {
        measurementID = nil
        measurementTask?.cancel()
        measurementTask = nil
        client.cancel()
        measurement = nil
        measurementMessage = nil
    }

    private func measure(_ query: RecordLookupQuery) {
        let context = RecordLookupMeasurementContext(query: query, companionOrigin: store.activeQiMon?.originDigest)
        let owner = sourceOwnerIdentity
        guard measurementTask == nil, !store.isWorking, !store.isShuttingDown,
              RecordMeasurementClient.available else { return }
        // Display uses the cached freshness value; dispatch always checks disk.
        refreshFreshness()
        guard sourceIsCurrent,
              context.matches(table: table, recordID: selectedRecordID, field: selectedField,
                              companionOrigin: store.activeQiMon?.originDigest) else { return }
        clearMeasurement()
        let identity = UUID()
        measurementID = identity
        measurementTask = Task { @MainActor in
            do {
                let result = try await client.measure(input: query.input, system: RecordLookupQuery.system, schema: RecordLookupQuery.schema)
                guard !Task.isCancelled, measurementID == identity else { return }
                guard sourceOwnerIdentity == owner else { resetSelection(); return }
                // A source may have changed outside ARCHi during the await.
                refreshFreshness()
                guard sourceIsCurrent, context.matches(table: table, recordID: selectedRecordID, field: selectedField,
                                                       companionOrigin: store.activeQiMon?.originDigest) else {
                    clearMeasurement()
                    measurementMessage = "The source or question changed. Measure the current selection when ready."
                    return
                }
                measurement = result
            } catch {
                guard !Task.isCancelled, measurementID == identity else { return }
                measurementMessage = error is CancellationError ? "Measurement stopped." : error.localizedDescription
            }
            if measurementID == identity { measurementTask = nil }
        }
    }
}
