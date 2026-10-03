import SwiftUI

/// A navigation handoff from the map. Preparation remains an explicit preview
/// against the document's live selection; the existing Send/Apply owners follow.
@MainActor
struct DocumentMethodWorkSelectionView: View {
    @ObservedObject var store: CompanionStore
    let selection: DocumentMethodInspectionSelection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Method to try", systemImage: "arrow.triangle.branch").fontWeight(.medium)
                Spacer()
                Button { store.clearDocumentMethodToTry() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).accessibilityLabel("Dismiss method to try")
            }
            if let method = store.methodForInspection(selection) {
                Text("\(method.title) · v\(method.revision)").fontWeight(.medium)
                Text("Select a passage, choose Rewrite or Shorten, and match this method’s checks. Preview lets you inspect any replacement of your current instruction.")
                    .foregroundStyle(.secondary)
                Text((method.mustBeShorter ? "Shorter text" : "Flexible length") + " · "
                    + (method.preserveNumbersAndLinks ? "Exact numbers and links" : "No exact-token requirement"))
                    .foregroundStyle(.secondary)
                if let issue = store.documentProcedureUnavailable(method.binding) {
                    Text(issue).foregroundStyle(.orange)
                }
                DocumentMethodPreviewButton(store: store, procedure: method,
                    title: "Preview for selected passage…", accessibilityID: "document.method-to-try.preview")
                Text("Only Send starts work. Review the proposed edit before Apply, then record whether it helped.")
                    .foregroundStyle(.secondary)
            } else {
                Text("The exact method or its profile changed. Reopen it from the memory map. Your current document and request were not replaced.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption).padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkspaceTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("document.method-to-try")
    }
}
