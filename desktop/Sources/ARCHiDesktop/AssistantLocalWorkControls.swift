import SwiftUI

@MainActor
struct AssistantLocalWorkControls: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local work").font(.system(size: 12, weight: .semibold))
            Picker("Local work", selection: Binding(get: { store.localWorkPreference }, set: { store.setLocalWorkPreference($0) })) {
                ForEach(LocalWorkPreference.allCases) { preference in Text(preference.title).tag(preference) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("assistant.local-work")
            .disabled(store.isShuttingDown)
            Text(explanation).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Compact: \(store.qwenContextModel) · Reasoning: \(store.qwenModel)")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            Text("Native tools handle explicit supported actions. Document work and local measurements always use Reasoning. External delivery follows Send to. Work and model choices are kept on this Mac, separate from your companion.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var explanation: String {
        switch store.localWorkPreference {
        case .automatic: "Auto uses Compact for simple greetings and thanks, and Reasoning for other questions."
        case .compact: "Compact handles short conversation requests. Longer prompts use Reasoning; a compact model availability failure retries locally."
        case .reasoning: "Reasoning handles each local reply. Optional excerpt selection still uses the compact model."
        }
    }
}
