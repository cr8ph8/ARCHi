import SwiftUI

@MainActor
struct PlayWorkspace: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject var host: HostedPlayHost
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Assistant").font(.system(size: 10)).foregroundStyle(.secondary)
                AssistantTaskCue(activity: store.assistantActivity, quiet: store.preferences.quiet, reduceMotion: store.preferences.reduceMotion)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).frame(height: 26)
            .accessibilityIdentifier("hosted-assistant-activity")
            HostedPracticePanel(host: host, evolution: store.evolution) { store.open(.evolution) }
            ZStack {
                if let view = host.webView {
                    HostedPlayWebView(webView: view)
                        .accessibilityLabel("Habitat and QiMon arena")
                }
                if host.state != .ready {
                    VStack(spacing: 14) {
                        if host.state == .starting { ProgressView() }
                        else { Image(systemName: "leaf").font(.system(size: 30, weight: .light)) }
                        Text(host.state == .unavailable ? "Habitat is unavailable" : "Your Habitat lives here")
                            .font(.system(size: 19, weight: .medium, design: .rounded))
                        Text(host.status).font(.system(size: 12)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).frame(maxWidth: 390)
                        if host.state == .unavailable {
                            Button("Retry Habitat") { host.retry() }
                                .buttonStyle(.borderedProminent).accessibilityIdentifier("hosted-play-retry")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            HStack(spacing: 12) {
                Text(host.transferStatus).lineLimit(1)
                    .accessibilityIdentifier("hosted-play-transfer-status")
                Spacer(minLength: 8)
                Menu("Habitat options") {
                    Text(host.status)
                    if let count = host.projection?.eventCount { Text("\(count) Journey events") }
                }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityIdentifier("hosted-play-options")
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
            .padding(.horizontal, 18).padding(.vertical, 7)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            updateAppearance()
            host.setVisible(NSApp.isActive && !NSApp.isHidden)
            host.start()
        }
        .onDisappear { host.setVisible(false) }
        .onChange(of: store.preferences) { _, _ in updateAppearance() }
        .onChange(of: store.activeQiMon) { _, _ in updateAppearance() }
        .onChange(of: store.evolution.revision) { _, _ in updateAppearance() }
        .onChange(of: store.reactor.frameRevision) { _, _ in updateAppearance() }
        .onChange(of: systemReduceMotion) { _, _ in updateAppearance() }
    }

    private func updateAppearance() {
        host.updateAppearance(form: store.presentationForm, family: store.presentationFamily,
            reduceMotion: store.preferences.reduceMotion || store.preferences.quiet || systemReduceMotion,
            treatment: store.preferences.visualTreatment,
            expressionPNG: store.reactorReferenceMatchesCurrentAppearance ? store.reactor.framePNG : nil,
            expressionRevision: store.reactor.frameRevision,
            recipe: store.presentationRecipe, naturalVariation: store.presentationNaturalVariation,
            equipment: store.preferences.equipment, seedColor: store.preferences.seedColor)
    }
}
