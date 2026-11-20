import SwiftUI
import WebKit

/// The page receives the same bounded projection as Node Lab. There is no
/// script-message handler, provider, file URL or state-writing capability.
@MainActor
struct SeedDiveWorkspace: View {
    @ObservedObject var store: CompanionStore
    @State private var unavailable = false

    var body: some View {
        VStack(spacing: 0) {
            if unavailable {
                ContentUnavailableView("Seed view unavailable", systemImage: "circle.dotted",
                    description: Text("Open Node Lab to inspect the same local records."))
                Button("Reload seed view") { unavailable = false }
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { clock in
                    SeedDivePage(snapshot: store.companionGraphSnapshot(at: clock.date),
                        still: store.preferences.reduceMotion || store.preferences.quiet,
                        failed: { unavailable = true })
                }
            }
            HStack {
                Button("Open Node Lab") { store.open(.nodeLab) }
                Spacer()
                if store.isWorking {
                    Button("Stop request", systemImage: "stop.fill") { store.cancelWork() }
                }
                Button("Return to companion") { store.open(.appearance) }
            }.font(.caption).padding(.horizontal, 18).padding(.vertical, 9)
        }.accessibilityIdentifier("seed-dive.workspace")
    }
}

@MainActor
struct SeedDivePage: NSViewRepresentable {
    let snapshot: CompanionGraphSnapshot
    let still: Bool
    let failed: () -> Void

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
        context.coordinator.update(snapshot: snapshot, still: still, in: view)
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
        private var still = false
        private var generation = 0

        init(failed: @escaping () -> Void) { self.failed = failed }

        func update(snapshot: CompanionGraphSnapshot, still: Bool, in view: WKWebView) {
            guard self.snapshot != snapshot || self.still != still else { return }
            self.snapshot = snapshot
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
            // Hide the preceding frame while a removed or withdrawn record is being replaced.
            view.isHidden = true
            let nodes: [[String: Any]] = snapshot.nodes.map { node in
                ["id": node.id, "kind": node.kind.rawValue, "title": node.title, "status": node.status,
                 "subtitle": node.subtitle, "details": node.details.map { ["label": $0.label, "value": $0.value] }]
            }
            let edges = snapshot.edges.map { ["source": $0.source, "target": $0.target, "label": $0.label] }
            let payload: [String: Any] = ["nodes": nodes, "edges": edges, "truncatedCount": snapshot.truncatedCount]
            view.callAsyncJavaScript("window.seedDive.replace(snapshot, still); return true;",
                arguments: ["snapshot": payload, "still": still], in: nil, in: .page) { [weak self, weak view] result in
                    guard let self, self.active, self.generation == version else { return }
                    switch result {
                    case .success: view?.isHidden = false
                    case .failure: self.reportFailure()
                    }
                }
        }
    }
}
