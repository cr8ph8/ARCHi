import SwiftUI

/// A reviewed concept can inspire an explicitly authored or accepted method.
/// A local draft stays separate until accepted; saving neither sends nor applies work.
@MainActor
struct KnowledgeProcedureCandidateView: View {
    @ObservedObject var store: CompanionStore
    let page: KnowledgePage
    private let saveCandidate: ((String, String, DocumentWorkRequirements) -> DocumentProcedureUse?)?
    private let onSaved: ((DocumentProcedureUse) -> Void)?
    private let saveIssue: String?
    @State private var expanded = false
    @State private var title: String
    @State private var instruction = ""
    @State private var requirements = DocumentWorkRequirements()
    @State private var saveMessage: String?

    init(store: CompanionStore, page: KnowledgePage, startsExpanded: Bool = false,
         saveCandidate: ((String, String, DocumentWorkRequirements) -> DocumentProcedureUse?)? = nil,
         saveIssue: String? = nil,
         onSaved: ((DocumentProcedureUse) -> Void)? = nil) {
        self.store = store
        self.page = page
        self.saveCandidate = saveCandidate
        self.onSaved = onSaved
        self.saveIssue = saveIssue
        _expanded = State(initialValue: startsExpanded)
        _title = State(initialValue: page.title)
    }

    private var identifier: String { "\(page.id).\(page.revision)" }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedInstruction: String { instruction.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var ownsMethodDraft: Bool { store.knowledgeMethodDraftPage == page.binding }
    private var isDraftingThisMethod: Bool { ownsMethodDraft && store.isDraftingKnowledgeMethod }
    private var textIssue: String? {
        if trimmedTitle.count > 80 {
            return "Shorten the method name to 80 characters or fewer."
        }
        if trimmedInstruction.count > 1_200 {
            return "Shorten the instruction to 1,200 characters or fewer."
        }
        if trimmedTitle.utf8.count > 320 || trimmedInstruction.utf8.count > 4_800 {
            return "Shorten the name or instruction; it exceeds the saved-method size limit."
        }
        let unsupported = CharacterSet.controlCharacters.subtracting(.newlines)
        if (trimmedTitle + trimmedInstruction).unicodeScalars.contains(where: unsupported.contains) {
            return "Remove unsupported control characters before saving."
        }
        return nil
    }
    private var canSave: Bool {
        saveIssue == nil && store.canKeepDocumentProcedure
            && page.state == .reviewed && page.kind == .concept
            && store.readingSources.availability(of: page) == nil
            && !trimmedTitle.isEmpty && !trimmedInstruction.isEmpty && textIssue == nil
    }

    var body: some View {
        DisclosureGroup("Create a document method candidate", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Write an instruction worth trying on a selected passage. Saving keeps your method and a link to this reviewed concept on this Mac.")
                    .foregroundStyle(.secondary)
                TextField("Method name", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("knowledge.procedure-name.\(identifier)")
                TextField("Instruction for a later selected passage", text: $instruction, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(3...8)
                    .accessibilityIdentifier("knowledge.procedure-instruction.\(identifier)")
                Toggle("Require shorter text", isOn: $requirements.mustBeShorter)
                    .accessibilityIdentifier("knowledge.procedure-shorter.\(identifier)")
                Toggle("Keep exact numbers and links", isOn: $requirements.preserveNumbersAndLinks)
                    .accessibilityIdentifier("knowledge.procedure-exact-tokens.\(identifier)")
                methodDraftControls
                Text("Untested candidate · no demonstrated usefulness yet. Choose it for a passage, review the proposed edit, then record the applied outcome.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("knowledge.procedure-candidate-status.\(identifier)")
                Text("Saving keeps only the instruction you choose and a link to this concept. It sends nothing and gives no usefulness credit. Methods from knowledge pages run locally on this Mac.")
                    .foregroundStyle(.secondary)
                if let textIssue {
                    Text(textIssue).foregroundStyle(.orange)
                        .accessibilityIdentifier("knowledge.procedure-text-issue.\(identifier)")
                }
                if let saveIssue {
                    Text(saveIssue).foregroundStyle(.orange)
                        .accessibilityIdentifier("knowledge.procedure-context-issue.\(identifier)")
                }
                if let unavailable = store.readingSources.availability(of: page) {
                    Text(unavailable).foregroundStyle(.orange)
                        .accessibilityIdentifier("knowledge.procedure-availability.\(identifier)")
                }
                Button("Save candidate") {
                    guard canSave else { return }
                    var saved: DocumentProcedureUse?
                    if let saveCandidate {
                        saved = saveCandidate(title, instruction, requirements)
                    } else {
                        _ = store.keepKnowledgeProcedure(page: page, title: title,
                            instruction: instruction, requirements: requirements, onSaved: { saved = $0 })
                    }
                    if let saved {
                        title = ""
                        instruction = ""
                        requirements = DocumentWorkRequirements()
                        if ownsMethodDraft { store.discardKnowledgeMethodDraft() }
                        onSaved?(saved)
                    }
                    saveMessage = store.knowledgePageMessage
                }
                .buttonStyle(.bordered).disabled(!canSave)
                .accessibilityIdentifier("knowledge.save-procedure.\(identifier)")
                if let saveMessage {
                    Text(saveMessage).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("knowledge.procedure-save-status.\(identifier)")
                }
            }.padding(.top, 6)
        }
        .font(.system(size: 11))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("knowledge.procedure-candidate.\(identifier)")
    }

    private var methodDraftControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Draft locally asks Qwen on this Mac to use this reviewed concept, its exact linked passages, and the requirements above. No external fallback is used.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("knowledge.procedure-draft-disclosure.\(identifier)")
            if isDraftingThisMethod {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Drafting a method locally")
                    Text("Drafting locally… Your editor remains available.")
                    Spacer()
                    Button("Stop") { store.cancelWork() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("knowledge.stop-procedure-draft.\(identifier)")
                }
                .accessibilityIdentifier("knowledge.procedure-drafting.\(identifier)")
            } else {
                Button("Draft locally") {
                    saveMessage = nil
                    store.draftKnowledgeMethod(page: page, requirements: requirements)
                }
                .buttonStyle(.bordered)
                .disabled(saveIssue != nil || !store.canDraftKnowledgeMethod(page: page))
                .accessibilityIdentifier("knowledge.draft-procedure.\(identifier)")
            }
            if ownsMethodDraft, let message = store.knowledgeMethodDraftMessage {
                Text(message).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("knowledge.procedure-draft-status.\(identifier)")
            }
            if saveIssue == nil, let draft = store.currentKnowledgeMethodDraft(for: page) {
                draftPreview(draft)
            }
        }
        .padding(.vertical, 4)
    }

    private func draftPreview(_ draft: KnowledgeMethodDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local draft for review").fontWeight(.medium)
            Text(draft.instruction)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("knowledge.procedure-draft-preview.\(identifier)")
            if !draft.uncertainty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Model's caveat: \(draft.uncertainty)")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("knowledge.procedure-draft-caveat.\(identifier)")
            }
            Text("Linked to this concept, revision \(draft.binding.revision). Source references do not prove the method works.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Draft requirements: \(draft.requirements.mustBeShorter ? "shorter text required" : "shorter text optional"); \(draft.requirements.preserveNumbersAndLinks ? "keep exact numbers and links" : "exact numbers and links not required").")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("knowledge.procedure-draft-requirements.\(identifier)")
            Text("Using this draft replaces the instruction and both requirements above. Your method name stays as written. Review the editor, then save when ready.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(trimmedInstruction.isEmpty ? "Use this draft" : "Replace instruction with draft") {
                    guard let current = store.currentKnowledgeMethodDraft(for: page),
                          current.requestID == draft.requestID else { return }
                    instruction = current.instruction
                    requirements = current.requirements
                    saveMessage = nil
                }
                .accessibilityIdentifier("knowledge.use-procedure-draft.\(identifier)")
                Button("Discard draft") { store.discardKnowledgeMethodDraft() }
                    .accessibilityIdentifier("knowledge.discard-procedure-draft.\(identifier)")
            }.buttonStyle(.bordered)
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("knowledge.procedure-draft.\(identifier)")
    }
}
