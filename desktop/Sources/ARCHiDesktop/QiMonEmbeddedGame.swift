import AppKit
import Combine
import Foundation
import Network
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Hosts a local game inside ARCHi. Game evidence stays a projection until an
/// existing native record owner explicitly admits it; this view never does so.
@MainActor
final class QiMonEmbeddedGame: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    static let shared = QiMonEmbeddedGame()
    static let port: UInt16 = 8767
    static let origin = URL(string: "http://127.0.0.1:8767/")!
    static let dataStoreID = UUID(uuidString: "A4A19A25-351B-45B6-9D70-3B15D0A02817")!
    static let saveKey = "qimon.first-signal.chapter.v1"
    static let selectionKey = "selectedEmbeddedFolder.v1"
    @Published private(set) var status = "Play the original QiMon chapter inside ARCHi."
    @Published private(set) var summary = "No saved chapter inspected yet."
    @Published private(set) var isOpening = false
    @Published private(set) var exportAvailable = false
    @Published private(set) var webView: WKWebView?
    @Published private(set) var directory: URL?
    private let defaults: UserDefaults
    private let candidates: [URL]
    private var server: QiMonEmbeddedServer?
    private var window: NSWindow?
    private var archive: Data?

    init(defaults: UserDefaults = UserDefaults(suiteName: "com.quotient.archi.qimon-local-play")!,
         hostApplicationURL: URL = Bundle.main.bundleURL) {
        self.defaults = defaults
        candidates = Self.discoveryCandidates(in: hostApplicationURL)
        super.init()
        refreshLocation()
    }

    /// Automatic discovery is limited to the delivered app and its adjacent
    /// chapter package. Development builds elsewhere require an explicit choice.
    static func discoveryCandidates(in hostApp: URL) -> [URL] {
        [hostApp.appendingPathComponent("Contents/Resources/QiMonFirstSignalWeb"),
         hostApp.deletingLastPathComponent().appendingPathComponent("QiMonFirstSignalWeb")]
    }

    func refreshLocation() {
        guard server == nil else { return }
        if let data = defaults.data(forKey: Self.selectionKey) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale),
               QiMonEmbeddedAssets.isBuild(url) { directory = url; return }
            directory = nil
            status = "The selected chapter build moved or is incomplete. Choose its built game folder."
            return
        }
        directory = candidates.first(where: QiMonEmbeddedAssets.isBuild)
        if directory == nil { status = "Choose the First Signal build folder to play inside ARCHi." }
    }

    func chooseFolder() {
        guard server == nil, !isOpening else { status = "Close the game window and use Stop game before changing its build."; return }
        let panel = NSOpenPanel()
        panel.title = "Choose the First Signal built game folder"
        panel.prompt = "Use this build"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        guard QiMonEmbeddedAssets.isBuild(selected) else {
            status = "This folder is not a complete First Signal build. Look for index.html and qimon-build.json."
            return
        }
        do {
            let data = try selected.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(data, forKey: Self.selectionKey)
            directory = selected; status = "Build selected. Its local journey stays separate from ARCHi's companion records."
        } catch { status = "The build location could not be remembered: \(error.localizedDescription)" }
    }

    func play() async {
        guard !isOpening else { return }
        if let window, webView != nil { window.makeKeyAndOrderFront(nil); return }
        refreshLocation()
        guard let directory else { return }
        isOpening = true; status = "Opening First Signal inside ARCHi…"
        defer { isOpening = false }
        do {
            let assets = try QiMonEmbeddedAssets(root: directory)
            let managed = QiMonEmbeddedServer(assets: assets, port: Self.port)
            server = managed
            let origin = try await managed.start()
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.dataStoreID)
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            configuration.mediaTypesRequiringUserActionForPlayback = .all
            configuration.userContentController.add(QiMonEmbeddedMessageReceiver(self), name: "qimonChapter")
            configuration.userContentController.addUserScript(WKUserScript(source: Self.bridgeScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            let rules = """
            [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}},
             {"trigger":{"url-filter":"^http://127\\\\.0\\\\.0\\\\.1:8767/"},"action":{"type":"ignore-previous-rules"}}]
            """
            let rulesList = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "qimon-local-only-v1", encodedContentRuleList: rules)
            if let rulesList { configuration.userContentController.add(rulesList) }
            let view = WKWebView(frame: .zero, configuration: configuration)
            view.navigationDelegate = self
            view.allowsBackForwardNavigationGestures = false
            view.setAccessibilityIdentifier("qimon.embedded.webview")
            webView = view
            let gameWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 770),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            gameWindow.title = "QiMon: First Signal — ARCHi"
            gameWindow.minSize = NSSize(width: 820, height: 590)
            gameWindow.isReleasedWhenClosed = false
            gameWindow.contentView = NSHostingView(rootView: QiMonEmbeddedWindow(game: self))
            gameWindow.center(); gameWindow.makeKeyAndOrderFront(nil)
            window = gameWindow
            view.load(URLRequest(url: origin))
        } catch {
            await server?.shutdown(); server = nil
            status = "First Signal could not open: \(error.localizedDescription)"
        }
    }

    func stop() async {
        guard !isOpening else { return }
        isOpening = true
        defer { isOpening = false }
        window?.close(); window?.contentView = nil; window = nil
        webView?.stopLoading(); webView?.configuration.userContentController.removeScriptMessageHandler(forName: "qimonChapter")
        webView = nil
        await server?.shutdown(); server = nil
        archive = nil; exportAvailable = false; summary = "No saved chapter inspected yet."
        status = "Game stopped. Its saved journey remains on this Mac."
    }

    func inspectSave() {
        webView?.evaluateJavaScript("window.dispatchEvent(new Event('qimon:native-inspect'));", completionHandler: nil)
    }

    func exportJourney() {
        guard let archive else { status = "Save in the game, then inspect the saved journey before exporting."; return }
        let panel = NSSavePanel()
        panel.title = "Export First Signal journey"
        panel.nameFieldStringValue = "QiMon-First-Signal-Journey.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try archive.write(to: url, options: .atomic)
            status = "Journey copy exported. ARCHi's companion identity and memory were not changed."
        } catch { status = "The journey copy could not be exported: \(error.localizedDescription)" }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.webView === self.webView, message.frameInfo.isMainFrame, Self.allowsDocument(message.frameInfo.request.url),
              let body = message.body as? [String: Any], body["key"] as? String == Self.saveKey,
              let raw = body["raw"] as? String, raw.utf8.count <= 65_536,
              let data = raw.data(using: .utf8),
              let state = try? JSONDecoder().decode(QiMonEmbeddedProjection.self, from: data), state.isValid else {
            archive = nil; exportAvailable = false
            summary = "No readable saved chapter is available to inspect."
            return
        }
        archive = data; exportAvailable = true
        let partner = state.companionSummary
        let place = state.area == "city" ? "Glass Circuit" : state.area == "yard" ? "Relay Nine" : "Signal field"
        summary = "\(state.operatorName) · \(partner) · \(place) · Receiver \(state.relay.restored ? "restored" : "unrecovered") · \(state.glasses ? "AR glasses earned" : "phone view") · \(state.journal.count) journal records"
    }

    static func accepts(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "http" && url.host == "127.0.0.1" && url.port == Int(port) && url.user == nil && url.password == nil
    }
    static func allowsDocument(_ url: URL?) -> Bool {
        guard accepts(url), let path = url?.path else { return false }
        return path == "/" || path == "/index.html"
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard webView === self.webView, action.targetFrame?.isMainFrame == true, Self.allowsDocument(action.request.url) else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        status = "Playing locally inside ARCHi. Journey export is available after the game saves."
        inspectSave()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        status = "The local game page could not load: \(error.localizedDescription)"
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        status = "The game renderer stopped. Stop game, then Play again; its saved journey is retained."
    }

    private static let bridgeScript = """
    (() => {
      if (location.pathname !== '/' && location.pathname !== '/index.html') return;
      const publish = () => {
        try {
          const raw = localStorage.getItem('qimon.first-signal.chapter.v1');
          window.webkit.messageHandlers.qimonChapter.postMessage({key:'qimon.first-signal.chapter.v1',raw:raw && raw.length <= 65536 ? raw : ''});
        } catch { window.webkit.messageHandlers.qimonChapter.postMessage({key:'qimon.first-signal.chapter.v1',raw:''}); }
      };
      window.addEventListener('qimon:chapter-saved', publish);
      window.addEventListener('qimon:native-inspect', publish);
      window.addEventListener('storage', e => { if(e.key === 'qimon.first-signal.chapter.v1') publish(); });
      publish();
    })();
    """
}

private struct QiMonEmbeddedProjection: Decodable {
    struct Relay: Decodable { let restored: Bool }
    struct Journal: Decodable { let id: String; let text: String }
    /// A display projection only. The game retains lineage validation, history and growth ownership.
    struct Companion: Decodable {
        let name: String
        let stage: Int
        var isValid: Bool {
            !name.isEmpty && name.utf16.count <= 24
            && name == name.trimmingCharacters(in: .whitespacesAndNewlines)
            && name.rangeOfCharacter(from: .controlCharacters) == nil
            && (0...9_007_199_254_740_991).contains(stage)
        }
        var stageLabel: String {
            switch stage {
            case 0: return "Seed"
            case 1: return "Emergent"
            case 2: return "Resonant"
            default: return "Resonance \(stage - 1)"
            }
        }
    }
    let version: Int; let revision: Int; let operatorName: String; let starterId: String?
    // Missing or null in older chapter saves. Malformed present data fails inspection, not silently renamed.
    let companion: Companion?
    var companionSummary: String {
        if let companion { return "\(companion.name) (\(companion.stageLabel))" }
        return starterId.map { $0 == "seai" ? "SEAi" : $0.capitalized } ?? "No companion yet"
    }
    let area: String; let relay: Relay; let glasses: Bool; let journal: [Journal]
    var isValid: Bool {
        version == 1 && (0...1_000_000_000).contains(revision) && !operatorName.isEmpty && operatorName.count <= 24
        && ["yard", "field", "city"].contains(area) && (starterId == nil || ["liminal", "seai", "volt"].contains(starterId!))
        && (companion == nil || (starterId != nil && companion!.isValid))
        && journal.count <= 32 && journal.allSatisfy { !$0.id.isEmpty && $0.id.count <= 48 && $0.text.count <= 280 }
        && Set(journal.map(\.id)).count == journal.count && (!glasses || relay.restored)
        && (area != "city" || (starterId != nil && relay.restored && glasses))
    }
}

@MainActor private final class QiMonEmbeddedMessageReceiver: NSObject, WKScriptMessageHandler {
    weak var owner: QiMonEmbeddedGame?
    init(_ owner: QiMonEmbeddedGame) { self.owner = owner }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.userContentController(controller, didReceive: message)
    }
}

@MainActor private struct QiMonEmbeddedWindow: View {
    @ObservedObject var game: QiMonEmbeddedGame
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("First Signal").font(.headline)
                Spacer()
                Button("Inspect saved journey") { game.inspectSave() }
                Button("Export journey…") { game.exportJourney() }.disabled(!game.exportAvailable)
                Button("Stop game") { Task { await game.stop() } }
            }
            Text(game.summary).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if let view = game.webView { QiMonEmbeddedWebView(view: view).frame(maxWidth: .infinity, maxHeight: .infinity) }
            Text(game.status).font(.caption).foregroundStyle(.secondary)
            Text("This game keeps its own journey. Exporting creates a copy; it does not grant ARCHi memories, abilities, or rewards.")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(12).frame(minWidth: 800, minHeight: 550)
    }
}

private struct QiMonEmbeddedWebView: NSViewRepresentable {
    let view: WKWebView
    func makeNSView(context: Context) -> NSView {
        let container = NSView(); view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: container.leadingAnchor), view.trailingAnchor.constraint(equalTo: container.trailingAnchor), view.topAnchor.constraint(equalTo: container.topAnchor), view.bottomAnchor.constraint(equalTo: container.bottomAnchor)])
        return container
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct QiMonEmbeddedAssets {
    let root: URL
    static func isBuild(_ directory: URL) -> Bool { (try? Self(root: directory)) != nil }
    init(root: URL) throws {
        let resolved = root.resolvingSymlinksInPath().standardizedFileURL
        let marker = resolved.appendingPathComponent("qimon-build.json")
        guard let markerSize = try? marker.resourceValues(forKeys: [.fileSizeKey]).fileSize, markerSize <= 4096,
              let data = try? Data(contentsOf: marker), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["schema"] as? Int == 1, object["game"] as? String == "qimon-first-signal", object["entry"] as? String == "index.html",
              let indexSize = try? resolved.appendingPathComponent("index.html").resourceValues(forKeys: [.fileSizeKey]).fileSize,
              indexSize > 0, indexSize < 131_072 else { throw QiMonEmbeddedError.missingBuild }
        self.root = resolved
    }
    func response(_ data: Data, authority: String) -> Data {
        guard let request = try? HostedPlayRequest.parse(data, authority: authority),
              !request.path.split(separator: "/").contains(where: { $0.hasPrefix(".") }),
              !request.path.contains("service-worker") else { return response(status: "400 Bad Request", body: Data()) }
        let file = root.appendingPathComponent(String(request.path.dropFirst())).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"),
              let info = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), info.isRegularFile == true,
              let size = info.fileSize, size <= 64 * 1024 * 1024,
              let bytes = try? Data(contentsOf: file), bytes.count == size else { return response(status: "404 Not Found", body: Data()) }
        let types = ["html":"text/html; charset=utf-8", "js":"text/javascript; charset=utf-8", "css":"text/css; charset=utf-8", "json":"application/json", "png":"image/png", "jpg":"image/jpeg", "jpeg":"image/jpeg", "webp":"image/webp", "svg":"image/svg+xml", "woff":"font/woff", "woff2":"font/woff2", "ttf":"font/ttf", "ogg":"audio/ogg", "mp3":"audio/mpeg", "wav":"audio/wav", "wasm":"application/wasm"]
        return response(status: "200 OK", body: bytes, mime: types[file.pathExtension.lowercased()] ?? "application/octet-stream", head: request.head)
    }
    private func response(status: String, body: Data, mime: String = "text/plain", head: Bool = false) -> Data {
        let csp = "default-src 'none'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; worker-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'; media-src 'self' blob:"
        let headers = "HTTP/1.1 \(status)\r\nContent-Type: \(mime)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nCross-Origin-Resource-Policy: same-origin\r\nPermissions-Policy: camera=(), microphone=(), geolocation=(), display-capture=()\r\nContent-Security-Policy: \(csp)\r\n\r\n"
        return Data(headers.utf8) + (head ? Data() : body)
    }
}

private enum QiMonEmbeddedError: LocalizedError {
    case missingBuild, occupiedPort, stopped
    var errorDescription: String? {
        switch self {
        case .missingBuild: "The selected First Signal build is incomplete."
        case .occupiedPort: "First Signal's local port 8767 is occupied. This app will not connect to an unknown server; close the other local copy and try again."
        case .stopped: "The local game server stopped."
        }
    }
}

/// Bound exclusively to loopback. Reuses ARCHi's validated GET/HEAD parser;
/// exposes selected static files, never a shell, proxy, or native record API.
@MainActor private final class QiMonEmbeddedServer {
    let assets: QiMonEmbeddedAssets; let port: UInt16
    private var listener: NWListener?
    private var waiter: CheckedContinuation<URL, any Error>?
    private var timeout: Task<Void, Never>?
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []
    private struct Client { let connection: NWConnection; var bytes = Data(); let timeout: Task<Void, Never> }
    private var clients: [UUID: Client] = [:]
    init(assets: QiMonEmbeddedAssets, port: UInt16) { self.assets = assets; self.port = port }
    func start() async throws -> URL {
        let parameters = NWParameters.tcp; parameters.allowLocalEndpointReuse = false
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let listener = try NWListener(using: parameters); self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in Task { @MainActor in self?.accept(connection) } }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            Task { @MainActor in
                guard let self, let listener, self.listener === listener else { return }
                switch state {
                case .ready:
                    self.timeout?.cancel(); self.timeout = nil
                    self.waiter?.resume(returning: URL(string: "http://127.0.0.1:\(self.port)/")!); self.waiter = nil
                case .failed:
                    self.timeout?.cancel(); self.timeout = nil
                    self.waiter?.resume(throwing: QiMonEmbeddedError.occupiedPort); self.waiter = nil; listener.cancel()
                case .cancelled:
                    self.waiter?.resume(throwing: QiMonEmbeddedError.stopped); self.waiter = nil
                    self.listener = nil
                    for waiting in self.stopWaiters { waiting.resume() }; self.stopWaiters = []
                default: break
                }
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            waiter = continuation
            timeout = Task { [weak self, weak listener] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self, self.waiter != nil else { return }
                self.waiter?.resume(throwing: QiMonEmbeddedError.occupiedPort); self.waiter = nil; listener?.cancel()
            }
            listener.start(queue: .main)
        }
    }
    func shutdown() async {
        timeout?.cancel(); timeout = nil
        for id in Array(clients.keys) { close(id) }
        guard let listener else { return }
        await withCheckedContinuation { continuation in stopWaiters.append(continuation); listener.cancel() }
    }
    private func accept(_ connection: NWConnection) {
        guard listener != nil, clients.count < 16 else { connection.cancel(); return }
        let id = UUID()
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10)); guard !Task.isCancelled else { return }; self?.close(id)
        }
        clients[id] = Client(connection: connection, timeout: timeout)
        connection.start(queue: .main); receive(id)
    }
    private func receive(_ id: UUID) {
        guard let client = clients[id] else { return }
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 8193) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, var current = self.clients[id] else { return }
                if let data { current.bytes.append(data) }; self.clients[id] = current
                guard current.bytes.count <= 8192, error == nil else { self.close(id); return }
                if current.bytes.range(of: Data("\r\n\r\n".utf8)) != nil {
                    let response = self.assets.response(current.bytes, authority: "127.0.0.1:\(self.port)")
                    current.connection.send(content: response, completion: .contentProcessed { [weak self] _ in Task { @MainActor in self?.close(id) } })
                } else if complete { self.close(id) } else { self.receive(id) }
            }
        }
    }
    private func close(_ id: UUID) {
        guard let client = clients.removeValue(forKey: id) else { return }
        client.timeout.cancel(); client.connection.cancel()
    }
}
