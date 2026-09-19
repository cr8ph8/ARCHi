import SwiftUI

@MainActor
struct SeedDesignTestCard: View {
    @ObservedObject var store: CompanionStore
    @State private var answers: [String: String] = [:]
    @State private var baseline: PersonalContext?
    @State private var message = ""
    @State private var preferredName = ""

    var body: some View {
        WorkspaceCard {
            DisclosureGroup("Your Seed · a short design test") {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Choose what feels good to you. This guides a new design proposal; it does not measure personality or award abilities. You can leave any choice open.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    if baseline == nil {
                        TextField("What should your companion call you?", text: $preferredName)
                            .accessibilityLabel("Your preferred name")
                            .onChange(of: preferredName) { _, _ in refreshDraftState() }
                    }
                    Text("Answer at least three prompts to keep a design direction.").font(.caption).foregroundStyle(.secondary)
                    ForEach(SeedDesignTest.questions) { question in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(question.prompt).font(.system(size: 12, weight: .medium))
                            Picker(question.prompt, selection: Binding(get: { answers[question.id] ?? SeedDesignTest.unknown }, set: {
                                answers[question.id] = $0
                                refreshDraftState()
                            })) {
                                ForEach(question.choices, id: \.self) { Text($0).tag($0) }
                            }.labelsHidden().frame(maxWidth: 330)
                            .accessibilityIdentifier("seed-design.\(question.id)")
                        }
                    }
                    if let brief = SeedDesignTest.brief(answers: answers) {
                        Text(brief.decisions.isEmpty ? "Your direction is open." : brief.summary)
                            .font(.system(size: 13, weight: .medium))
                        Text("\(brief.unanswered.count) choices open · appearance and growth stay unchanged")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Keep design direction") {
                            let context = baseline ?? PersonalContext(name: preferredName, preferredName: preferredName, entries: [])
                            guard let next = SeedDesignTest.keeping(answers: answers, in: context) else {
                                message = "This direction could not be kept. Check the name and available space in your personal context, then try again."
                                return
                            }
                            if store.updatePersonalContext(next, expected: baseline) {
                                self.baseline = store.personalContext
                                store.hasSeedDesignDraft = false
                                message = "Design direction kept. Next: review a visual proposal, refine it, then explicitly choose its appearance."
                            } else { message = store.status }
                        }.disabled(!brief.isReady || (baseline == nil && preferredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                        .accessibilityIdentifier("seed-design.keep")
                    }
                    if store.hasSeedDesignDraft {
                        Button("Discard these answers") { reload() }.buttonStyle(.borderless)
                    }
                    if baseline == nil { Text("Keeping a direction creates local personal context with the name and answers you supplied.").font(.caption) }
                    if !message.isEmpty { Text(message).font(.caption).textSelection(.enabled) }
                }.padding(.top, 14)
            }
        }
        .accessibilityIdentifier("seed-design.card")
        .onAppear { reload() }
        .onDisappear { store.hasSeedDesignDraft = false }
        .onChange(of: store.personalContext) { _, value in
            if !store.hasSeedDesignDraft { baseline = value; answers = SeedDesignTest.answers(in: value) }
        }
    }

    private func reload() {
        baseline = store.personalContext
        answers = SeedDesignTest.answers(in: baseline)
        preferredName = baseline?.preferredName ?? ""
        store.hasSeedDesignDraft = false
        message = ""
    }

    private func refreshDraftState() {
        store.hasSeedDesignDraft = answers != SeedDesignTest.answers(in: baseline)
            || (baseline == nil && !preferredName.isEmpty)
        message = ""
    }
}
