import SwiftUI

/// Procedure text is reviewed here, never silently extracted from a model reply
/// or shared document. An optional starter uses only declared edit requirements.
@MainActor
struct KeepDocumentProcedureView: View {
    @ObservedObject var store: CompanionStore
    let record: DocumentWorkRecord
    @State private var title = ""
    @State private var instruction = ""
    @State private var expanded: Bool

    init(store: CompanionStore, record: DocumentWorkRecord, startsExpanded: Bool = false) {
        self.store = store
        self.record = record
        _expanded = State(initialValue: startsExpanded)
    }

    var body: some View {
        if record.state == .applied, record.feedback?.verdict == .helpful, store.canReviewDocument(record) {
            DisclosureGroup("Keep a procedure from this work", isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Describe the method worth trying again. Keep saves only this name, instruction, requirements and review references on this Mac.")
                        .foregroundStyle(.secondary)
                    Button("Start with this edit’s checks") {
                        title = record.mustBeShorter ? "Shorten a passage" : "Revise a passage"
                        instruction = record.mustBeShorter
                            ? "Shorten the selected passage while preserving its meaning."
                            : "Revise the selected passage while preserving its meaning."
                        if record.preserveNumbersAndLinks {
                            instruction += " Keep its numbers and links exactly as written."
                        }
                    }
                    .disabled(!title.isEmpty || !instruction.isEmpty || !store.canKeepDocumentProcedure)
                    .accessibilityIdentifier("document.procedure-starter")
                    Text("This starter uses the edit requirements only. Add what made the change useful before keeping it.")
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
                    if let reason = store.documentMethodDependencyIssue(record) {
                        Text(reason).foregroundStyle(.orange)
                            .accessibilityIdentifier("document.procedure-dependency-issue")
                    }
                    Button("Keep procedure") {
                        if store.keepDocumentProcedure(recordID: record.id, title: title, instruction: instruction) {
                            title = ""; instruction = ""
                        }
                    }
                    .disabled(!store.canKeepDocumentProcedure || store.documentMethodDependencyIssue(record) != nil
                        || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        DocumentMethodFinderView(store: store)
        DisclosureGroup("Saved procedures (\(store.documentProcedures.latestProcedures.count))") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Keep a method after helpful applied work, or author an untested candidate from a reviewed concept. Matching methods use reviewed outcomes first. Ties use comparable local usage when fully measured. Choose a method for each new passage.")
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
                DocumentMethodPreviewButton(store: store, procedure: procedure,
                    title: "Use for this passage…",
                    accessibilityID: "document.use-procedure.\(identifier)")
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
    @State private var sourceInspection: KnowledgeRecordInspectionSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(procedure.title) · v\(procedure.revision)").fontWeight(.medium)
            Text(procedure.instruction).textSelection(.enabled)
            if let origin = procedure.knowledgeOrigin {
                knowledgeOriginDetails(origin)
            }
            MethodLearningView(store: store, procedure: procedure, isHistorical: isHistorical)
            DisclosureGroup("Local usage") {
                if let usage = store.resources(for: procedure) {
                    let perHelpful = Double(usage.totalTokens) / Double(usage.helpfulResults)
                    Text("\(perHelpful.formatted(.number.precision(.fractionLength(0...1)))) observed tokens per Helpful result")
                    Text("\(usage.totalTokens.formatted()) tokens across \(usage.recordedUses) uses · \(usage.localAttempts) model calls, including retries and context preparation.")
                    Text("This describes past local work. It is not a price or a prediction of future savings.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not enough comparable local usage yet. The existing review-based order is preserved.")
                        .foregroundStyle(.secondary)
                }
            }.accessibilityIdentifier("document.procedure-usage.\(procedure.id).\(procedure.revision)")
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

    private func knowledgeOriginDetails(_ origin: KnowledgePageBinding) -> some View {
        let source = store.readingSources.knowledgePages.first { $0.binding == origin }
        let outcomes = store.outcomes(for: procedure)
        let identifier = "\(procedure.id).\(procedure.revision)"
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("From \(source?.title ?? "Unavailable knowledge page") · v\(origin.revision)")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("document.procedure-knowledge-origin.\(identifier)")
                Button("Show source") {
                    sourceInspection = .init(reference: .page(origin),
                        sourceOwner: ObjectIdentifier(store.readingSources))
                }
                .buttonStyle(.borderless)
                .disabled(store.isShuttingDown || store.hasOpenKnowledgeDraft)
                .accessibilityIdentifier("document.procedure-show-source.\(identifier)")
                .sheet(item: $sourceInspection) { selection in
                    KnowledgeRecordInspectionView(store: store, selection: selection)
                }
            }
            Text("Candidate from a reviewed concept · local use on this Mac")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("document.procedure-local-origin.\(identifier)")
            if let outcomes {
                if outcomes.attempts == 0 {
                    Text("Untested candidate · no demonstrated usefulness yet.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("document.procedure-untested.\(identifier)")
                } else if outcomes.helpful == 0 {
                    Text("No helpful applied outcome recorded for this version yet.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("document.procedure-no-helpful-outcome.\(identifier)")
                }
            } else {
                Text("Outcome history is unavailable. This candidate’s usefulness cannot be assessed yet.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("document.procedure-outcomes-unavailable.\(identifier)")
            }
        }
    }
}

@MainActor
struct DocumentMethodInspectionView: View {
    @ObservedObject var store: CompanionStore
    let selection: DocumentMethodInspectionSelection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved method version").font(.headline)
            if let method = store.methodForInspection(selection) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        DocumentProcedureVersionDetails(store: store, procedure: method,
                            isHistorical: !store.documentProcedures.latestProcedures.contains(method))
                        Text("Opening this version does not prepare a request or restore an earlier document.")
                            .foregroundStyle(.secondary)
                        if store.documentProcedures.latestProcedures.contains(method) {
                            Text("Next: open document work, select a passage with these checks, then preview this instruction there. Send, Apply and your outcome review remain separate steps.")
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("document.inspect-method.next-step")
                        }
                    }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 480)
                Button("Try in document work", systemImage: "doc.text") {
                    _ = store.beginDocumentMethodWork(selection)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isWorking || !store.documentProcedures.latestProcedures.contains(method)
                    || store.documentProcedureUnavailable(method.binding) != nil || store.hasOpenKnowledgeDraft)
                .accessibilityIdentifier("document.inspect-method.try")
            } else {
                Text("This exact version or its profile history changed. Close this inspector and reopen the current method record. No replacement version was selected.")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("document.inspect-method.unavailable")
            }
            HStack {
                Spacer()
                Button("Done") { store.inspectedDocumentMethod = nil }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20).frame(width: 560)
        .accessibilityIdentifier("document.inspect-method")
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
