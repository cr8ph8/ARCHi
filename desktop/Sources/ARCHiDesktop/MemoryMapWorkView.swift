import SwiftUI

/// Entry points to existing work and review owners. No progress is inferred from
/// opening the map, preparing an instruction or looking at particles.
@MainActor
struct MemoryMapWorkView: View {
    @ObservedObject var store: CompanionStore
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Work from memory").font(.headline)
            Text("Use a method on a passage, inspect the change, then review what happened.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Open document work", systemImage: "doc.text") {
                dismiss(); store.open(.context)
            }.accessibilityIdentifier("memory-map.work.open-document")
            Text("To author a new method, select a reviewed Concept in the map and choose Create a method. A saved candidate starts without a usefulness claim.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let outcome = store.currentDocumentOutcome {
                        DocumentOutcomeView(store: store, record: outcome).id(outcome.id)
                    }
                    DocumentReviewQueueView(store: store)
                    DisclosureGroup("Find and inspect saved methods") {
                        DocumentProcedureLibraryView(store: store).padding(.top, 8)
                    }.font(.caption)
                }
            }.frame(maxHeight: 420)
        }
        .padding(18).frame(width: 390)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("memory-map.work-panel")
    }
}

@MainActor
struct KnowledgeMapMethodSheet: View {
    @ObservedObject var store: CompanionStore
    let selection: KnowledgeMapMethodSelection
    let dismiss: (DocumentProcedureUse?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("From concept to method").font(.headline)
            // Keep authored fields mounted when support changes. They remain
            // copyable, but Save rechecks the captured owners and stays blocked.
            let page = selection.page
                Text("\(page.title) · Concept v\(page.revision)").font(.subheadline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        DisclosureGroup("Review the source concept") {
                            Text(page.body).textSelection(.enabled).font(.caption)
                            Text("The map retains the source passages and this exact concept version.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        KnowledgeProcedureCandidateView(store: store, page: page, startsExpanded: true,
                            saveCandidate: { title, instruction, requirements in
                                store.keepKnowledgeMapMethod(selection, title: title,
                                    instruction: instruction, requirements: requirements)
                            }, saveIssue: store.knowledgePageForMethodSelection(selection) == nil
                                ? "The concept or its sources changed. Your draft remains here to copy; reopen the current reviewed concept before saving."
                                : nil,
                            onSaved: { dismiss($0) })
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 490)
            HStack {
                Spacer()
                Button("Close") { dismiss(nil) }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("memory-map.method.close")
            }
        }
        .padding(20).frame(width: 540)
        .accessibilityIdentifier("memory-map.method-sheet")
    }
}
