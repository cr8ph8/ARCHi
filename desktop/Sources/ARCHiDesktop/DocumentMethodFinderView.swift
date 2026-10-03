import SwiftUI

/// Search text and previews belong to this view only. The existing procedure
/// owner decides what can be reused and validates it again on confirmation.
@MainActor
struct DocumentMethodFinderView: View {
    @ObservedObject var store: CompanionStore
    @State private var query = ""
    @State private var result: DocumentMethodSearchResult?
    @State private var message: String?

    private let maximumQueryBytes = DocumentMethodSearch.maximumQueryUTF8Bytes
    private var queryIsValid: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && query.utf8.count <= maximumQueryBytes
    }
    private var currentRequestFits: Bool {
        !store.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && store.prompt.utf8.count <= maximumQueryBytes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Find a saved method", systemImage: "magnifyingglass")
                .fontWeight(.medium)
            Text("Describe what you want to do. This search stays in this view and is never saved or sent.")
                .foregroundStyle(.secondary)
            HStack(alignment: .top) {
                TextField("For example, summarize project status", text: $query, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Purpose for finding a saved method")
                    .accessibilityIdentifier("document.method-finder.query")
                Button("Find", action: search)
                    .disabled(!queryIsValid || store.isShuttingDown)
                    .accessibilityIdentifier("document.method-finder.search")
            }
            Button("Use current request") {
                guard currentRequestFits else { return }
                query = store.prompt
                clearResults()
            }
            .buttonStyle(.borderless)
            .disabled(!currentRequestFits || store.isShuttingDown)
            .help("Copy the current request into this local search, up to 512 UTF-8 bytes.")
            .accessibilityIdentifier("document.method-finder.use-request")
            if query.utf8.count > maximumQueryBytes {
                Text("Shorten the search to 512 UTF-8 bytes or fewer (currently \(query.utf8.count)).")
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("document.method-finder.query-limit")
            }
            Text("Word matches are hints. Every method still needs matching checks and current sources. Reviewed outcomes, then comparable local usage, order ties.")
                .foregroundStyle(.secondary)
            if let result {
                results(result)
            }
            if let message {
                Text(message).foregroundStyle(.orange)
                    .accessibilityIdentifier("document.method-finder.message")
            }
        }
        .font(.caption)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("document.method-finder")
        .onChange(of: query) { _, _ in clearResults() }
        .onChange(of: ObjectIdentifier(store.documentProcedures)) { _, _ in reset() }
        .onChange(of: store.activeQiMon) { _, _ in reset() }
        .onChange(of: store.sourceRevision) { _, _ in clearResults() }
        .onChange(of: store.documentRequirements) { _, _ in clearResults() }
        .onChange(of: store.documentProcedures.procedures) { _, _ in clearResults() }
        .onChange(of: store.documentWork.records) { _, _ in clearResults() }
        .onChange(of: store.readingSources.sources) { _, _ in clearResults() }
        .onChange(of: store.readingSources.knowledgePages) { _, _ in clearResults() }
        .onChange(of: store.profileRecoveryBlock) { _, _ in clearResults() }
    }

    private func results(_ result: DocumentMethodSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if result.hits.isEmpty {
                Text("No matching saved methods for these checks. Try different words or browse Saved procedures below.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("document.method-finder.no-matches")
            } else {
                Text("\(min(result.hits.count, 5)) of \(result.matchingCount) word matches")
                    .foregroundStyle(.secondary)
                ForEach(Array(result.hits.prefix(5)), id: \.procedure.binding) { hit in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(hit.procedure.title) · v\(hit.procedure.revision)")
                            .fontWeight(.medium)
                        Text("Matched: \(hit.matchedTerms.joined(separator: ", "))")
                            .foregroundStyle(.secondary)
                        if let outcomes = store.outcomes(for: hit.procedure) {
                            Text("\(outcomes.helpful) Helpful · \(outcomes.awaitingReview) awaiting review")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Outcome history is unavailable.").foregroundStyle(.secondary)
                        }
                        DisclosureGroup("Review instruction…") {
                            Text(hit.procedure.instruction).textSelection(.enabled)
                                .padding(.top, 3)
                        }
                        Text((hit.procedure.mustBeShorter ? "Shorter text" : "Flexible length") + " · "
                             + (hit.procedure.preserveNumbersAndLinks ? "Exact numbers and links" : "No exact-token requirement"))
                            .foregroundStyle(.secondary)
                        DocumentMethodPreviewButton(store: store, procedure: hit.procedure,
                            title: "Preview for this passage…",
                            accessibilityID: "document.method-finder.preview.\(hit.procedure.id).\(hit.procedure.revision)")
                            .buttonStyle(.borderless)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("document.method-finder.hit.\(hit.procedure.id).\(hit.procedure.revision)")
                }
                if result.omittedCount > 0 {
                    Text("\(result.omittedCount) more matches. Narrow the search to find them.")
                        .foregroundStyle(.secondary)
                }
                Text("Select a passage in Revise mode with matching checks to preview a method.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func search() {
        guard queryIsValid, !store.isShuttingDown else { return }
        do {
            result = try store.findDocumentMethods(query: query)
            message = nil
        } catch {
            result = nil
            message = error.localizedDescription
        }
    }

    private func clearResults() {
        result = nil
        message = nil
    }

    private func reset() {
        query = ""
        clearResults()
    }
}

/// Shared by search hits and the full library so neither can replace a draft
/// before the user has reviewed the exact instruction and current draft.
@MainActor
struct DocumentMethodPreviewButton: View {
    @ObservedObject var store: CompanionStore
    let procedure: DocumentProcedure
    let title: String
    let accessibilityID: String
    @State private var presentation: DocumentMethodPreviewPresentation?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(title) {
                guard let preview = store.previewDocumentMethod(procedure.binding) else {
                    message = store.documentProcedureUnavailable(procedure.binding)
                        ?? "Finish current work, then select a passage in Revise mode with this method’s checks."
                    return
                }
                message = nil
                presentation = DocumentMethodPreviewPresentation(preview: preview)
            }
            .disabled(!store.canPrepareDocumentProcedure(procedure))
            .accessibilityIdentifier(accessibilityID)
            if let message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
        }
        .sheet(item: $presentation) { item in
            DocumentMethodPreviewSheet(store: store, preview: item.preview) {
                presentation = nil
            }
        }
        .onChange(of: ObjectIdentifier(store.documentProcedures)) { _, _ in clear() }
        .onChange(of: store.activeQiMon) { _, _ in clear() }
        .onChange(of: store.sourceRevision) { _, _ in clear() }
    }

    private func clear() {
        presentation = nil
        message = nil
    }
}

private struct DocumentMethodPreviewPresentation: Identifiable {
    let preview: DocumentMethodPreview
    var id: UUID { preview.id }
}

@MainActor
private struct DocumentMethodPreviewSheet: View {
    @ObservedObject var store: CompanionStore
    let preview: DocumentMethodPreview
    let dismiss: () -> Void
    @State private var actionIssue: String?

    private var replacesDraft: Bool {
        !preview.originalPrompt.isEmpty
            && !preview.originalPrompt.utf8.elementsEqual(preview.procedure.instruction.utf8)
    }
    private var issue: String? {
        store.documentMethodPreviewIssue(preview) ?? actionIssue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review saved method").font(.headline)
            Text("\(preview.procedure.title) · v\(preview.procedure.revision)")
                .fontWeight(.medium)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Saved instruction").font(.subheadline.weight(.medium))
                    Text(preview.procedure.instruction)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("document.method-preview.instruction")
                    Text((preview.procedure.mustBeShorter ? "Shorter text" : "Flexible length") + " · "
                         + (preview.procedure.preserveNumbersAndLinks ? "Exact numbers and links" : "No exact-token requirement"))
                        .font(.caption).foregroundStyle(.secondary)
                    if replacesDraft {
                        Divider()
                        Text("Current draft to be replaced").font(.subheadline.weight(.medium))
                        Text(preview.originalPrompt)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("document.method-preview.current-draft")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 340)
            Text("This prepares the request. Review it, then Send when ready. Opening or canceling this preview leaves your draft unchanged.")
                .font(.caption).foregroundStyle(.secondary)
            if let issue {
                Text(issue).font(.caption).foregroundStyle(.orange)
                    .accessibilityIdentifier("document.method-preview.issue")
            }
            HStack {
                Spacer()
                Button("Cancel", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("document.method-preview.cancel")
                Button(replacesDraft ? "Replace draft with method" : "Use this method") {
                    if store.applyDocumentMethodPreview(preview) {
                        dismiss()
                    } else {
                        actionIssue = store.documentMethodPreviewIssue(preview)
                            ?? store.documentWorkMessage
                            ?? "The method could not be prepared. Close this preview and check the current passage."
                    }
                }
                .disabled(issue != nil)
                .accessibilityIdentifier("document.method-preview.confirm")
            }
        }
        .padding(20)
        .frame(width: 540)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("document.method-preview")
    }
}
