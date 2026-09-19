import SwiftUI

@MainActor
struct ReactorExpressionPanel: View {
    @ObservedObject var reactor: ReactorExpressionStore
    @State private var apiKey = ""
    @State private var reviewedQuote: ReactorTrialQuote?
    @State private var showReview = false

    var body: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Reactor expression", systemImage: "sparkles.rectangle.stack")
                        .font(.system(size: 19, weight: .medium, design: .rounded))
                    Spacer()
                    Text(reactor.state.title).font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WorkspaceTheme.accent).accessibilityIdentifier("reactor-state")
                }
                Text("Bring a little motion to the same ARCHi. Preview locally, then optionally try a short hosted expression.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(alignment: .center, spacing: 18) {
                    if let image = reactor.frameImage ?? reactor.referencePNG.flatMap(NSImage.init(data:)) {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: 98, height: 98)
                            .accessibilityLabel("Selected reference: " + reactor.referenceLabel)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(reactor.referenceLabel).font(.system(size: 13, weight: .medium))
                        HStack {
                            Button("Preview locally") { reactor.startLocalPreview() }.disabled(!reactor.canPreview)
                                .accessibilityIdentifier("reactor-local-preview")
                            Button("Check Reactor") {
                                // Launch the child after the native control event completes.
                                Task { @MainActor in reactor.prepare() }
                            }.disabled(!reactor.canPrepare)
                                .accessibilityIdentifier("reactor-prepare")
                            Button("Stop", role: .cancel) { reactor.stop() }.disabled(!reactor.busy)
                                .accessibilityIdentifier("reactor-stop")
                        }.buttonStyle(.bordered)
                        Text("Local preview: no model call. Quiet or Reduce Motion keeps local artwork still.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                if let quote = reactor.quote {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Helios · one session · 15 seconds maximum")
                            .font(.system(size: 12, weight: .medium))
                        Text(String(format: "Published-rate estimate: %.0f credits · $%.4f", quote.maximumCredits, quote.maximumUSD))
                            .font(.system(size: 12)).accessibilityIdentifier("reactor-estimate")
                        SecureField("Reactor API key (used for this trial only)", text: $apiKey)
                            .textFieldStyle(.roundedBorder).accessibilityIdentifier("reactor-api-key")
                        HStack {
                            Button("Review live trial…") { reviewedQuote = quote; showReview = true }
                                .buttonStyle(.borderedProminent)
                                .disabled(!reactor.canStart || !apiKey.hasPrefix("rk_"))
                                .accessibilityIdentifier("reactor-review")
                            Text("Your key is not saved. No documents, conversations or camera feed are sent.")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }
                Text(reactor.status).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("reactor-status")
                if reactor.acceptedFrames > 0 || reactor.rejectedFrames > 0 || reactor.duration > 0 {
                    Text("\(reactor.acceptedFrames) accepted frames · \(reactor.rejectedFrames) rejected · \(reactor.duration, specifier: "%.1f")s observed")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
                DisclosureGroup("Reference, prompt and connection details") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ReactorExpressionStore.prompt).textSelection(.enabled)
                        Text("The selected body is placed on a green reference background. Accepted frames use local shape checks and transparency removal. These checks do not verify character likeness; local artwork returns on rejection or Stop.")
                        Text("MCP can check, preview locally, inspect and stop this same native connection. Paid Start stays here. Blender and Unity remain the authoring and presentation tools for this reference.")
                    }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 8)
                }
            }
        }
        .confirmationDialog("Start this Reactor trial?", isPresented: $showReview, titleVisibility: .visible) {
            if let reviewedQuote {
                Button(String(format: "Start · estimated $%.4f", reviewedQuote.maximumUSD)) {
                    let key = apiKey; apiKey = ""
                    Task { @MainActor in reactor.startLive(apiKey: key, reviewedQuote: reviewedQuote) }
                    self.reviewedQuote = nil
                }
            }
            Button("Cancel", role: .cancel) { reviewedQuote = nil }
        } message: {
            Text("Send the displayed character reference and expression prompt to Reactor/Helios. One owned session is capped at 15 seconds, including startup. Stop restores local artwork and closes the provider session. No automatic retry.")
        }
        .onDisappear { apiKey = ""; reviewedQuote = nil; showReview = false }
    }
}
