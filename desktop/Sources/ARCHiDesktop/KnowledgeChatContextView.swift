import SwiftUI

@MainActor
struct KnowledgeChatContextView: View {
    @ObservedObject var store: CompanionStore
    var body: some View {
        if !store.selectedKnowledgePages.isEmpty {
            WorkspaceCard(inset: 12) {
                HStack {
                    Label("Knowledge for this local chat", systemImage: "books.vertical")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Button("Choose pages") { store.open(.memory) }
                    Button("Detach") { store.detachKnowledgePages() }
                        .accessibilityIdentifier("knowledge.chat.detach")
                }
                ForEach(store.selectedKnowledgePages, id: \.id) { binding in
                    Text((store.readingSources.knowledgePages.first { $0.binding == binding }?.title ?? "Unavailable page") + " · v\(binding.revision)")
                        .font(.system(size: 12)).lineLimit(2)
                }
                Text("Send uses these authored pages and their exact passages with Qwen on this Mac. Your shared document stays unchanged and is not included. External fallback is disabled.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if let issue = store.selectedKnowledgePageIssue {
                    Text(issue).font(.system(size: 11)).foregroundStyle(.orange)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("knowledge.chat.context")
        }
        if let message = store.nextReplyKnowledgeOmissionMessage {
            WorkspaceCard(inset: 12) {
                Label("Some saved lessons will stay out of this reply", systemImage: "info.circle")
                    .font(.system(size: 12, weight: .medium))
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("knowledge.chat.lesson-omissions")
        }
    }
}
