import SwiftUI

/// Procedure text is deliberately authored and reviewed here, never silently
/// extracted from a model reply or the shared document.
@MainActor
struct KeepDocumentProcedureView: View {
    @ObservedObject var store: CompanionStore
    let record: DocumentWorkRecord
    @State private var title = ""
    @State private var instruction = ""

    var body: some View {
        if record.state == .applied, record.feedback?.verdict == .helpful, store.canReviewDocument(record) {
            DisclosureGroup("Keep a procedure from this work") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Describe the method worth trying again. Keep saves only this name, instruction, requirements and review references on this Mac.")
                        .foregroundStyle(.secondary)
                    TextField("Procedure name", text: $title)
                        .accessibilityIdentifier("document.procedure-name")
                    TextField("Instruction for a later selected passage", text: $instruction, axis: .vertical)
                        .lineLimit(3...8).accessibilityIdentifier("document.procedure-instruction")
                    Text(record.mustBeShorter ? "Requires shorter text" : "No shorter-text requirement")
                    Text(record.preserveNumbersAndLinks ? "Keeps exact numbers and links" : "No exact-token requirement")
                    Text("Review the passage → request this method → check the proposed edit → Apply → review the outcome.")
                        .foregroundStyle(.secondary)
                    Text("This is a candidate method you author. The earlier result supports review; it does not prove the new instruction will work elsewhere.")
                        .foregroundStyle(.secondary)
                    Button("Keep procedure") {
                        if store.keepDocumentProcedure(recordID: record.id, title: title, instruction: instruction) {
                            title = ""; instruction = ""
                        }
                    }
                    .disabled(!store.canKeepDocumentProcedure || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("document.keep-procedure")
                }.padding(.top, 6)
            }.font(.caption2).accessibilityIdentifier("document.procedure-review.\(record.id)")
        }
    }
}

@MainActor
struct DocumentProcedureLibraryView: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        DisclosureGroup("Saved procedures (\(store.documentProcedures.latestProcedures.count))") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Keep a method after helpful applied work. Available methods matching these requirements appear first, ordered by their recorded outcomes. Choose a method explicitly for each new passage.")
                    .foregroundStyle(.secondary)
                if let error = store.documentProcedures.loadError { Text(error).foregroundStyle(.orange) }
                ForEach(store.orderedDocumentProcedures) { procedure in
                    DocumentProcedureLibraryRow(store: store, procedure: procedure)
                        .id(procedure.binding)
                }
            }.padding(.top, 6)
        }.font(.caption).accessibilityIdentifier("document.procedures")
    }
}

@MainActor
private struct DocumentProcedureLibraryRow: View {
    @ObservedObject var store: CompanionStore
    let procedure: DocumentProcedure
    @State private var isEditing = false
    @State private var title = ""
    @State private var instruction = ""
    @State private var changeNote = ""
    @State private var supportRecordID = ""
    @State private var saveError: String?

    private var identifier: String { "\(procedure.id).\(procedure.revision)" }
    private var previousVersions: [DocumentProcedure] {
        store.documentProcedures.versions(of: procedure.id).filter { $0.revision < procedure.revision }
    }
    private func canSave(with record: DocumentWorkRecord?) -> Bool {
        store.canKeepDocumentProcedure && record != nil
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !changeNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            DocumentProcedureVersionDetails(store: store, procedure: procedure)
            HStack {
                Button("Use for this passage") { _ = store.prepareDocumentProcedure(procedure.binding) }
                    .disabled(!store.canPrepareDocumentProcedure(procedure))
                    .accessibilityIdentifier("document.use-procedure.\(identifier)")
                Button("Edit method") {
                    title = procedure.title
                    instruction = procedure.instruction
                    changeNote = ""
                    supportRecordID = ""
                    saveError = nil
                    isEditing = true
                }
                .disabled(isEditing || !store.canKeepDocumentProcedure)
                .accessibilityIdentifier("document.edit-procedure.\(identifier)")
                Button("Withdraw") { store.withdrawDocumentProcedure(procedure.binding) }
                    .disabled(procedure.withdrawn)
                    .accessibilityIdentifier("document.withdraw-procedure.\(identifier)")
            }.buttonStyle(.borderless)
            if isEditing { revisionEditor }
            if !previousVersions.isEmpty {
                DisclosureGroup("Previous versions (\(previousVersions.count))") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Earlier instructions and their uses retain their original version.")
                            .foregroundStyle(.secondary)
                        ForEach(previousVersions, id: \.binding) { version in
                            VStack(alignment: .leading, spacing: 5) {
                                DocumentProcedureVersionDetails(store: store, procedure: version, isHistorical: true)
                                Button("Withdraw v\(version.revision)") {
                                    store.withdrawDocumentProcedure(version.binding)
                                }
                                .buttonStyle(.borderless)
                                .disabled(version.withdrawn)
                                .accessibilityIdentifier("document.withdraw-procedure.\(version.id).\(version.revision)")
                            }
                            .accessibilityIdentifier("document.procedure-version.\(version.id).\(version.revision)")
                        }
                    }.padding(.top, 5)
                }
                .accessibilityIdentifier("document.procedure-history.\(identifier)")
            }
        }
        .padding(.vertical, 5)
        .accessibilityIdentifier("document.procedure-row.\(identifier)")
    }

    private var revisionEditor: some View {
        let supportRecords = store.revisionSourceRecords(for: procedure.binding)
        let selectedSupport = supportRecords.first { $0.id == supportRecordID }
        return VStack(alignment: .leading, spacing: 8) {
            Text("New version candidate").fontWeight(.medium)
            Text("Revise v\(procedure.revision) with a helpful applied edit as support. Saving keeps earlier versions and their uses unchanged.")
                .foregroundStyle(.secondary)
            TextField("Procedure name", text: $title)
                .accessibilityIdentifier("document.revision-name.\(identifier)")
            TextField("Instruction for a later selected passage", text: $instruction, axis: .vertical)
                .lineLimit(3...8)
                .accessibilityIdentifier("document.revision-instruction.\(identifier)")
            TextField("What changed, and why? (required)", text: $changeNote, axis: .vertical)
                .lineLimit(2...5)
                .accessibilityIdentifier("document.revision-note.\(identifier)")
            if supportRecords.isEmpty {
                Text("No helpful applied edit is eligible yet. Finish a corrective edit and review it as helpful in Document work history, then return here.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("document.revision-no-support.\(identifier)")
            } else {
                Picker("Supporting edit", selection: $supportRecordID) {
                    Text("Choose a helpful applied edit").tag("")
                    ForEach(supportRecords) { record in
                        Text("\(record.provider) · \(record.updatedAt.formatted(date: .abbreviated, time: .shortened)) · \(record.id.prefix(8))")
                            .tag(record.id)
                    }
                }
                .accessibilityIdentifier("document.revision-support.\(identifier)")
                if let record = selectedSupport {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("New version requirements")
                        Text(record.mustBeShorter ? "Requires shorter text" : "No shorter-text requirement")
                        Text(record.preserveNumbersAndLinks ? "Keeps exact numbers and links" : "No exact-token requirement")
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("document.revision-requirements.\(identifier)")
                }
            }
            Text("The supporting result does not prove this new instruction will work elsewhere. Save keeps the candidate on this Mac; choose it for a passage when you are ready to try it.")
                .foregroundStyle(.secondary)
            if let saveError { Text(saveError).foregroundStyle(.orange) }
            HStack {
                Button("Save new version") {
                    if store.reviseDocumentProcedure(procedure.binding, title: title, instruction: instruction,
                                                     changeNote: changeNote, recordID: supportRecordID) {
                        isEditing = false
                    } else {
                        saveError = store.documentWorkMessage ?? "The new version was not saved. Review its supporting edit and try again."
                    }
                }
                .disabled(!canSave(with: selectedSupport))
                .accessibilityIdentifier("document.save-procedure-revision.\(identifier)")
                Button("Cancel") { isEditing = false }
                    .accessibilityIdentifier("document.cancel-procedure-revision.\(identifier)")
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("document.procedure-revision-editor.\(identifier)")
        .onChange(of: supportRecords.map(\.id)) { _, ids in
            if !ids.contains(supportRecordID) { supportRecordID = "" }
        }
    }
}

@MainActor
private struct DocumentProcedureVersionDetails: View {
    @ObservedObject var store: CompanionStore
    let procedure: DocumentProcedure
    var isHistorical = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(procedure.title) · v\(procedure.revision)").fontWeight(.medium)
            Text(procedure.instruction).textSelection(.enabled)
            if let outcomes = store.outcomes(for: procedure) {
                Text("This version · \(outcomes.helpful) helpful · \(outcomes.needsCorrection) corrected or withdrawn · \(outcomes.awaitingReview) awaiting review")
                    .foregroundStyle(.secondary)
            }
            Text((procedure.mustBeShorter ? "Shorter text" : "Flexible length") + " · "
                 + (procedure.preserveNumbersAndLinks ? "Exact numbers and links" : "No exact-token requirement"))
                .foregroundStyle(.secondary)
            if let prior = procedure.supersedes {
                Text("Revises \(store.documentProcedures.procedure(matching: prior)?.title ?? prior.id) · v\(prior.revision)")
                    .foregroundStyle(.secondary)
            }
            if let note = procedure.revisionNote {
                Text("Change: \(note)").textSelection(.enabled).foregroundStyle(.secondary)
            }
            if procedure.withdrawn {
                Text("Withdrawn · history retained").foregroundStyle(.secondary)
            } else if let reason = store.documentProcedureUnavailable(procedure.binding) {
                Text(reason).foregroundStyle(.orange)
            } else if isHistorical {
                Text("Earlier candidate · retained for history").foregroundStyle(.secondary)
            } else {
                Text("Candidate · available for a matching passage").foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
struct PreparedDocumentProcedureView: View {
    @ObservedObject var store: CompanionStore
    var body: some View {
        if let use = store.preparedDocumentProcedure {
            VStack(alignment: .leading, spacing: 4) {
                Text("Procedure: \(store.documentProcedures.procedure(matching: use)?.title ?? "Unavailable") · v\(use.revision)")
                    .fontWeight(.medium)
                if let reason = store.documentProcedureUnavailable(use) {
                    Text(reason).foregroundStyle(.orange)
                } else if !store.preparedProcedureMatchesCurrentDraft(question: store.prompt) {
                    Text("The draft, passage or requirements changed. Choose the procedure again, or detach it to send a new instruction.")
                        .foregroundStyle(.orange)
                }
                Button("Detach procedure") { store.clearPreparedDocumentProcedure() }
                    .buttonStyle(.borderless).accessibilityIdentifier("document.detach-procedure")
            }.font(.caption2).accessibilityIdentifier("document.prepared-procedure")
        }
    }
}
