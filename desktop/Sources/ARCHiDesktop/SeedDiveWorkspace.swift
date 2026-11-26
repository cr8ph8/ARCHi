import SwiftUI
import WebKit

/// The page receives the same bounded projection as Node Lab. There is no
/// script-message handler, provider, file URL or state-writing capability.
@MainActor
struct SeedDiveWorkspace: View {
    @ObservedObject var store: CompanionStore
    var showsDesktopNavigation = true
    @State private var unavailable = false

    var body: some View {
        VStack(spacing: 0) {
            if unavailable {
                ContentUnavailableView("Seed view unavailable", systemImage: "circle.dotted",
                    description: Text("Open Node Lab to inspect the same local records."))
                Button("Reload seed view") { unavailable = false }
            } else {
                // Store publications deliver current request/receipt transitions.
                // The clock only refreshes time-based expiry; unchanged values are
                // not resent and it never manufactures activity or model work.
                TimelineView(.periodic(from: .now, by: 1)) { clock in
                    let graph = store.companionGraphSnapshot(at: clock.date)
                    SeedDivePage(snapshot: graph, telemetry: store.seedTelemetrySnapshot(graph: graph),
                        still: store.preferences.reduceMotion || store.preferences.quiet,
                        failed: { unavailable = true })
                }
            }
            HStack {
                Button("Review kept lessons") { store.open(.memory) }
                    .accessibilityIdentifier("seed-review-lessons")
                if showsDesktopNavigation {
                    Button("Open Node Lab") { store.open(.nodeLab) }
                }
                Spacer()
                if store.isWorking {
                    Button("Stop request", systemImage: "stop.fill") { store.cancelWork() }
                }
                if showsDesktopNavigation {
                    Button("Return to companion") { store.open(.appearance) }
                }
            }.font(.caption).padding(.horizontal, 18).padding(.vertical, 9)
        }.accessibilityIdentifier("seed-dive.workspace")
    }
}

@MainActor
struct SeedDivePage: NSViewRepresentable {
    let snapshot: CompanionGraphSnapshot
    let telemetry: SeedTelemetrySnapshot?
    let still: Bool
    let failed: () -> Void

    init(snapshot: CompanionGraphSnapshot, telemetry: SeedTelemetrySnapshot? = nil,
         still: Bool, failed: @escaping () -> Void) {
        self.snapshot = snapshot
        self.telemetry = telemetry
        self.still = still
        self.failed = failed
    }

    static var pageURL: URL? {
        if Bundle.main.bundleURL.pathExtension == "app" {
            return Bundle.main.resourceURL?.appendingPathComponent("SeedDive/interior.html")
        }
        return Bundle.module.url(forResource: "interior", withExtension: "html", subdirectory: "SeedDive")
    }

    func makeCoordinator() -> Coordinator { Coordinator(failed: failed) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        if let url = Self.pageURL, let page = try? String(contentsOf: url, encoding: .utf8) {
            view.loadHTMLString(page, baseURL: nil)
        } else {
            context.coordinator.reportFailure()
        }
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.update(snapshot: snapshot, telemetry: telemetry, still: still, in: view)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.active = false
        view.navigationDelegate = nil
        view.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let failed: () -> Void
        var active = true
        private var ready = false
        private var snapshot: CompanionGraphSnapshot?
        private var telemetry: SeedTelemetrySnapshot?
        private var still = false
        private var generation = 0

        init(failed: @escaping () -> Void) { self.failed = failed }

        func update(snapshot: CompanionGraphSnapshot, telemetry: SeedTelemetrySnapshot?,
                    still: Bool, in view: WKWebView) {
            guard self.snapshot != snapshot || self.telemetry != telemetry || self.still != still else { return }
            if let previous = self.snapshot,
               SeedDiveReplacementPolicy.requiresFence(previous: previous, next: snapshot,
                    previousContextID: self.telemetry?.contextID, nextContextID: telemetry?.contextID) {
                // Do not expose withdrawn text while the replacement crosses the
                // native-to-page boundary. Later additive updates cannot unhide
                // this fence; only the latest successful delivery can do that.
                view.isHidden = true
            }
            self.snapshot = snapshot
            self.telemetry = telemetry
            self.still = still
            present(in: view)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            let allowed = !ready && navigationAction.targetFrame?.isMainFrame == true
                && navigationAction.request.url?.absoluteString == "about:blank"
            decisionHandler(allowed ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            present(in: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { reportFailure() }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { reportFailure() }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { reportFailure() }

        func reportFailure() {
            Task { @MainActor [weak self] in
                guard let self, self.active else { return }
                self.failed()
            }
        }

        private func present(in view: WKWebView) {
            guard ready, active, let snapshot else { return }
            generation += 1
            let version = generation
            let nodes: [[String: Any]] = snapshot.nodes.map { node in
                ["id": node.id, "kind": node.kind.rawValue, "title": node.title, "status": node.status,
                 "subtitle": node.subtitle, "details": node.details.map { ["label": $0.label, "value": $0.value] }]
            }
            let edges = snapshot.edges.map { ["source": $0.source, "target": $0.target, "label": $0.label] }
            var payload: [String: Any] = ["nodes": nodes, "edges": edges, "truncatedCount": snapshot.truncatedCount]
            if let telemetry {
                do {
                    payload.merge(try telemetry.webPayload()) { _, current in current }
                } catch {
                    view.isHidden = true
                    reportFailure()
                    return
                }
            }
            view.callAsyncJavaScript("window.seedDive.replace(snapshot, still); return true;",
                arguments: ["snapshot": payload, "still": still], in: nil, in: .page) { [weak self, weak view] result in
                    guard let self, self.active, self.generation == version else { return }
                    switch result {
                    case .success: view?.isHidden = false
                    case .failure:
                        view?.isHidden = true
                        self.reportFailure()
                    }
                }
        }
    }
}
