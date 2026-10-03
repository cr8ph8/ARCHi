import SwiftUI

@MainActor
struct PastedDocumentImportSheet: View {
    @ObservedObject var store: CompanionStore
    let context: PastedDocumentImportContext
    @Environment(\.dismiss) private var dismiss
    private var title: String { store.pastedDocumentDraft.title }
    private var content: String { store.pastedDocumentDraft.text }
    @State private var error: String?
    @State private var confirmsDiscard = false

    private var blockReason: String? { store.pastedDocumentImportBlockReason(context) }
    private var validation: String? { CompanionStore.pastedDocumentValidationMessage(text: content, title: title) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Paste text").font(.title2.weight(.medium))
            Text("Bring a draft or passage into Work together.").foregroundStyle(.secondary)
            TextField("Title (optional)", text: $store.pastedDocumentDraft.title)
                .textFieldStyle(.roundedBorder).accessibilityIdentifier("pasted-document.title")
            TextEditor(text: $store.pastedDocumentDraft.text).font(.system(size: 13))
                .frame(minHeight: 200).border(.quaternary)
                .accessibilityLabel("Text to work on").accessibilityIdentifier("pasted-document.content")
            Text("\(content.utf8.count.formatted()) / 100,000 bytes")
                .font(.caption).foregroundStyle(.secondary)
            if let message = blockReason ?? error ?? (content.isEmpty ? nil : validation) {
                Text(message).font(.callout).foregroundStyle(.orange)
                    .accessibilityIdentifier("pasted-document.notice")
            }
            Text("This copy stays in the session. Export to keep it. Send starts a request using your chosen assistant route.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") {
                    if content.isEmpty && title.isEmpty { dismiss() } else { confirmsDiscard = true }
                }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Use in Work together") {
                    if store.importPastedDocument(text: content, title: title, context: context) { dismiss() }
                    else { error = blockReason ?? "Your current copy was kept. Export it first, or review replacing it." }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(validation != nil || blockReason != nil)
                .accessibilityIdentifier("pasted-document.use")
            }
        }
        .padding(22).frame(width: 580, height: 480)
        .interactiveDismissDisabled(!content.isEmpty || !title.isEmpty)
        .confirmationDialog("Discard this pasted draft?", isPresented: $confirmsDiscard) {
            Button("Discard pasted draft", role: .destructive) {
                store.pastedDocumentDraft = PastedDocumentDraft()
                dismiss()
            }
            Button("Keep editing", role: .cancel) { }
        } message: { Text("It has not been added to your working copy or saved.") }
    }
}
