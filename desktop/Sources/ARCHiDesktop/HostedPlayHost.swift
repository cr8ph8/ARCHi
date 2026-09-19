import AppKit
import SwiftUI
import WebKit
import UniformTypeIdentifiers
import CryptoKit

enum HostedPlayState: String { case idle, starting, ready, unavailable, stopped }

struct HostedPlayDownloadReceipt: Equatable {
    let filename: String
    let byteCount: Int
    let sha256: String
}

typealias HostedPlayAppearanceRenderer = @MainActor (CompanionForm, EvolutionFamily?, CompanionVisualTreatment,
    CompanionAppearanceRecipe?, CompanionNaturalVariation?, CompanionEquipment, CompanionSeedColor) -> Data?

@MainActor
final class HostedPlayHost: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {
    let profile: HostedPlayProfile
    let assetDirectory: URL?
    @Published private(set) var state: HostedPlayState = .idle
    @Published private(set) var status = "Open Habitat to start the bundled game."
    @Published private(set) var webView: WKWebView?
    @Published private(set) var projection: HostedPlayProjection? {
        didSet {
            // Presentation ownership is separate from match authority. A late
            // popover dismissal must not close a later rehearsal in this match.
            if projection?.arena?.whatIf == nil {
                whatIfPresentationID = nil
            } else if oldValue?.arena?.whatIf == nil || oldValue?.sessionId != projection?.sessionId
                        || oldValue?.arena?.battleId != projection?.arena?.battleId {
                whatIfPresentationID = UUID()
            }
            reconcileCoaching()
            if let origin = projection?.originDigest { onJourneyOriginChanged?(origin) }
            onJourneyProjectionChanged?(projection)
        }
    }
    @Published private(set) var whatIfPresentationID: UUID?
    @Published private(set) var coaching = HostedArenaCoaching()
    @Published private(set) var lastDownload: HostedPlayDownloadReceipt?
    @Published private(set) var transferStatus = "Use Continuity in the game to review or download a Journey copy."
    @Published private(set) var rejectedMessageCount = 0
    @Published private(set) var rejectedNavigationCount = 0
    @Published private(set) var arenaCommandPending = false
    @Published private(set) var arenaStatus = ""
    private var arenaCommand: Task<Void, Never>?
    private var arenaCommandID: UUID?
    private var server: HostedPlayAssetServer?
    private var task: Task<Void, Never>?
    private var visibilityDelivery: Task<Void, Never>?
    private var readyTimeout: Task<Void, Never>?
    private var lifecycle = UUID()
    private var projectionGate = HostedPlayProjectionGate()
    var sessionID: UUID { projectionGate.sessionID }
    private var visibilitySequence = 0
    private var visibilityRevision = 0
    private var appearanceSequence = 0
    private var appearance: (id: String, label: String, png: String, reduceMotion: Bool)?
    private(set) var appearanceDeliveryDiagnostics: [String] = []
    private let appearanceRenderer: HostedPlayAppearanceRenderer
    private var retryAppearanceAfterReady: (@MainActor () -> Void)?
    var onVisibilityChanged: ((Bool) -> Void)?
    var onJourneyOriginChanged: ((String) -> Void)?
    var onJourneyProjectionChanged: ((HostedPlayProjection?) -> Void)?
    private(set) var isVisible = false
    private var isShutDown = false
    private var isStopping = false
    private var panel: NSSavePanel?
    private var panelID: UUID?
    private var pendingOpen: (@MainActor @Sendable ([URL]?) -> Void)?
    private var pendingSave: (@MainActor @Sendable (URL?) -> Void)?
    private struct Download {
        let item: WKDownload
        let session: UUID
        let visibility: Int
        let directory: URL
        let staged: URL
        var destination: URL?
        var approvedDestination: HostedPlayDestinationStamp?
        var observation: NSKeyValueObservation?
    }
    private var downloads: [ObjectIdentifier: Download] = [:]
    static let maximumArchiveBytes = 2 * 1024 * 1024

    init(profile: HostedPlayProfile = .current, assetDirectory: URL? = Bundle.main.resourceURL?.appendingPathComponent("Play"),
         appearanceRenderer: @escaping HostedPlayAppearanceRenderer = { form, family, treatment, recipe, natural, equipment, seedColor in
             CompanionPresenceArt.png(form: form, family: family, treatment: treatment, recipe: recipe,
                naturalVariation: natural, equipment: equipment, seedColor: seedColor)
         }) {
        self.profile = profile; self.assetDirectory = assetDirectory; self.appearanceRenderer = appearanceRenderer
        super.init()
    }

    func start() {
        guard !isShutDown, !isStopping, state == .idle || state == .unavailable else { return }
        let epoch = UUID(); lifecycle = epoch
        state = .starting; status = "Starting the bundled Habitat…"
        task = Task { [weak self] in
            guard let self else { return }
            await self.releaseCurrentPage()
            guard !Task.isCancelled, !self.isShutDown, self.lifecycle == epoch else { return }
            do {
                guard let directory = self.assetDirectory else { throw HostedPlayError.missingAssets }
                let assets = try HostedPlayAssets(directory: directory)
                let server = HostedPlayAssetServer(assets: assets, port: self.profile.port)
                server.onFailure = { [weak self] message in
                    guard let self, self.lifecycle == epoch, !self.isShutDown else { return }
                    self.retireFailedPage(message)
                }
                self.server = server
                let origin = try await server.start()
                let rules = try await self.contentRules()
                guard !Task.isCancelled, !self.isShutDown, self.lifecycle == epoch else { return }
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: self.profile.dataStoreIdentifier)
                configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
                configuration.mediaTypesRequiringUserActionForPlayback = .all
                configuration.userContentController.add(rules)
                configuration.userContentController.add(HostedPlayWeakMessageHandler(self), name: "archiJourneyProjection")
                self.installBootstrap(configuration.userContentController)
                let view = WKWebView(frame: .zero, configuration: configuration)
                view.navigationDelegate = self; view.uiDelegate = self
                view.allowsBackForwardNavigationGestures = false
                view.setAccessibilityIdentifier("hosted-play-webview")
                self.webView = view
                self.armReadyTimeout(epoch: epoch)
                view.load(URLRequest(url: origin))
            } catch {
                guard self.lifecycle == epoch, !self.isShutDown else { return }
                self.retireFailedPage(error.localizedDescription)
                await self.server?.shutdown(); self.server = nil
            }
        }
    }

    func retry() { guard state == .unavailable else { return }; start() }

    private var coachingContext: HostedArenaCoaching.Context? {
        guard !isShutDown, !isStopping, state == .ready, isVisible, !arenaCommandPending,
              let projection, projection.visible, projection.readiness == .ready,
              projection.mode == .battle, let journey = projection.revision,
              let arena = projection.arena, arena.phase == .planning, arena.whatIf == nil,
              let battleID = arena.battleId else { return nil }
        return .init(sessionID: sessionID, visibilityRevision: visibilityRevision,
            journeyRevision: journey, arenaRevision: arena.revision, battleID: battleID)
    }

    var coachingChoices: [HostedArenaProjection.Action] {
        HostedArenaCoaching.legalChoices(from: projection?.arena?.actions ?? [])
    }

    var canBeginCoaching: Bool { coachingContext != nil && !coachingChoices.isEmpty && coaching.session == nil }

    private func reconcileCoaching() {
        guard coaching.session != nil else { return }
        coaching.reconcile(context: coachingContext, choices: coachingChoices)
    }

    @discardableResult func beginCoaching() -> UUID? {
        reconcileCoaching()
        guard canBeginCoaching, let context = coachingContext else { return nil }
        return coaching.begin(context: context, choices: coachingChoices)
    }

    @discardableResult func offerCoaching(sessionID: UUID, actionID: String, reason: String) -> Bool {
        reconcileCoaching()
        guard let context = coachingContext else { return false }
        return coaching.offer(sessionID: sessionID, actionID: actionID, reason: reason,
            context: context, choices: coachingChoices)
    }

    /// Returns a legal selection for the existing native draft. No game intent
    /// is sent; the player must still use the ordinary Play control.
    func acceptCoaching(sessionID: UUID) -> HostedArenaProjection.Action? {
        reconcileCoaching()
        guard let context = coachingContext else { return nil }
        return coaching.accept(sessionID: sessionID, context: context, choices: coachingChoices)
    }

    func dismissCoaching(sessionID: UUID) { coaching.dismiss(sessionID: sessionID) }

    /// The action ID names an existing legal game intent. Swift never resolves a
    /// turn, chooses the partner's move, or writes game history.
    func performArenaAction(_ action: HostedArenaProjection.Action, revision: String) {
        guard !isShutDown, !isStopping, state == .ready, isVisible, !arenaCommandPending,
              let projection, projection.visible, [2, 3, 4].contains(projection.version),
              let arena = projection.arena, arena.revision == revision, arena.actions.contains(action),
              let view = webView, HostedPlayNavigation.allowsDocument(view.url, profile: profile) else { return }
        // A keyboard shortcut must not play a turn while someone is composing
        // or considering advice. Leaving remains available and retires advice.
        reconcileCoaching()
        guard coaching.session == nil || action.id == "leave" else { return }
        coaching.reset()
        let commandID = UUID(), session = sessionID, visibility = visibilityRevision
        arenaCommandID = commandID; arenaCommandPending = true; arenaStatus = ""
        let payload: [String: Any] = ["version": 1, "host": "archi-desktop", "sessionId": session.uuidString,
            "commandId": commandID.uuidString, "visibilitySequence": visibilitySequence,
            "expectedRevision": revision, "actionId": action.id]
        arenaCommand = Task { [weak self, weak view] in
            guard let self, let view, !Task.isCancelled, self.arenaCommandID == commandID,
                  self.sessionID == session, self.visibilityRevision == visibility, self.isVisible else { return }
            do {
                let accepted = try await view.callAsyncJavaScript(
                    "if (window.__ARCHI_DESKTOP_HOST__) return await window.__ARCHI_DESKTOP_HOST__.performArenaAction(message); return false;",
                    arguments: ["message": payload], in: nil, contentWorld: .page) as? Bool ?? false
                guard !Task.isCancelled, self.arenaCommandID == commandID, self.sessionID == session,
                      self.visibilityRevision == visibility, self.isVisible else { return }
                self.arenaStatus = accepted ? "" : "Practice changed. Choose from its current controls."
            } catch {
                guard !Task.isCancelled, self.arenaCommandID == commandID, self.sessionID == session else { return }
                self.arenaStatus = "The action could not be confirmed. Check the current practice before trying again."
            }
            guard self.arenaCommandID == commandID else { return }
            self.arenaCommandPending = false; self.arenaCommandID = nil; self.arenaCommand = nil
        }
    }

    private func retireArenaCommand() {
        coaching.reset()
        arenaCommandID = nil; arenaCommand?.cancel(); arenaCommand = nil
        arenaCommandPending = false; arenaStatus = ""
    }

    func updateAppearance(form: CompanionForm, family: EvolutionFamily?, reduceMotion: Bool,
                          treatment: CompanionVisualTreatment = .original,
                          expressionPNG: Data? = nil, expressionRevision: UInt64 = 0,
                          recipe: CompanionAppearanceRecipe? = nil, naturalVariation: CompanionNaturalVariation? = nil,
                          equipment: CompanionEquipment = .empty, seedColor: CompanionSeedColor = .original) {
        let usingExpression = expressionPNG != nil && !reduceMotion
        let id = CompanionVisualAsset.appearanceID(form: form, family: family, treatment: treatment,
            recipe: recipe, naturalVariation: naturalVariation, equipment: equipment, seedColor: seedColor)
            + (usingExpression ? "-expression-\(expressionRevision)" : "")
        // A newer request, including a return to the last successfully drawn
        // appearance, retires a previous failed request's one readiness retry.
        retryAppearanceAfterReady = nil
        guard appearance?.id != id || appearance?.reduceMotion != reduceMotion else { return }
        guard let bytes = usingExpression ? expressionPNG : appearanceRenderer(form, family, treatment, recipe, naturalVariation, equipment, seedColor), bytes.count < 1_400_000 else {
            recordAppearanceDelivery("render-unavailable id=\(id)")
            // ImageRenderer may be unavailable before AppKit finishes starting.
            // Retain the latest requested inputs for one later ready transition;
            // this never spins, changes the Journey, or starts a second host.
            retryAppearanceAfterReady = { [weak self] in
                self?.updateAppearance(form: form, family: family, reduceMotion: reduceMotion,
                    treatment: treatment, expressionPNG: expressionPNG, expressionRevision: expressionRevision,
                    recipe: recipe, naturalVariation: naturalVariation, equipment: equipment, seedColor: seedColor)
            }
            return
        }
        let label = CompanionVisualAsset.label(form: form, family: family, treatment: treatment,
            recipe: recipe, naturalVariation: naturalVariation, equipment: equipment, seedColor: seedColor)
        appearance = (id, label, "data:image/png;base64," + bytes.base64EncodedString(), reduceMotion)
        sendAppearance()
    }

    private func sendAppearance() {
        // Document navigation can finish while the module's asynchronous Journey
        // bootstrap is still running. Send only after its validated ready event.
        guard state == .ready, projectionGate.isActive, projection?.readiness == .ready,
              let view = webView, let appearance, HostedPlayNavigation.allowsDocument(view.url, profile: profile) else {
            recordAppearanceDelivery("deferred state=\(state.rawValue) view=\(webView != nil) image=\(appearance != nil)")
            return
        }
        appearanceSequence += 1
        let sequence = appearanceSequence
        let session = sessionID
        recordAppearanceDelivery("scheduled state=\(state.rawValue) sequence=\(sequence) id=\(appearance.id)")
        let payload: [String: Any] = ["version": 1, "host": "archi-desktop", "sessionId": session.uuidString,
            "sequence": appearanceSequence, "id": appearance.id, "label": appearance.label,
            "png": appearance.png, "reduceMotion": appearance.reduceMotion]
        Task { [weak self, weak view] in
            guard let self, let view, self.webView === view, self.sessionID == session,
                  self.appearance?.id == appearance.id, !self.isShutDown else { return }
            do {
                let accepted = try await view.callAsyncJavaScript("if (window.__ARCHI_DESKTOP_HOST__) return window.__ARCHI_DESKTOP_HOST__.setAppearance(message); return false;",
                    arguments: ["message": payload], in: nil, contentWorld: .page) as? Bool ?? false
                guard self.webView === view, self.sessionID == session, !self.isShutDown else { return }
                self.recordAppearanceDelivery("ack=\(accepted) sequence=\(sequence) id=\(appearance.id)")
            } catch {
                guard self.webView === view, self.sessionID == session, !self.isShutDown else { return }
                self.recordAppearanceDelivery("error sequence=\(sequence) \(String(error.localizedDescription.prefix(180)))")
            }
        }
    }

    private func recordAppearanceDelivery(_ message: String) {
        appearanceDeliveryDiagnostics.append(message)
        if appearanceDeliveryDiagnostics.count > 16 { appearanceDeliveryDiagnostics.removeFirst() }
    }

    func setVisible(_ visible: Bool) {
        guard !isShutDown, (!isStopping || !visible), visible != isVisible else { return }
        isVisible = visible
        onVisibilityChanged?(visible)
        visibilityRevision += 1
        if !visible {
            retireArenaCommand()
            cancelPanels()
            for id in Array(downloads.keys) { cancelDownload(id, message: "Download cancelled when Habitat was hidden.") }
        }
        sendVisibility()
    }

    func shutdown() async {
        guard !isShutDown, !isStopping else { return }
        isStopping = true
        setVisible(false)
        if let delivery = visibilityDelivery {
            await withCheckedContinuation { continuation in
                let completion = HostedPlayVisibilityCompletion(continuation)
                Task { await delivery.value; completion.finish() }
                Task { try? await Task.sleep(for: .seconds(2)); completion.finish() }
            }
        }
        isShutDown = true; lifecycle = UUID()
        retryAppearanceAfterReady = nil
        task?.cancel(); task = nil
        await releaseCurrentPage()
        state = .stopped; status = "Habitat stopped. Its on-device history is retained."
    }

    private func releaseCurrentPage() async {
        retireArenaCommand()
        readyTimeout?.cancel(); readyTimeout = nil
        visibilityDelivery?.cancel(); visibilityDelivery = nil
        projectionGate.retire()
        cancelPanels()
        for id in Array(downloads.keys) { cancelDownload(id, message: "Download cancelled before completion.") }
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "archiJourneyProjection")
        webView?.navigationDelegate = nil; webView?.uiDelegate = nil
        webView = nil; projection = nil
        let currentServer = server; server = nil
        await currentServer?.shutdown()
    }

    private func installBootstrap(_ controller: WKUserContentController) {
        retireArenaCommand()
        for id in Array(downloads.keys) { cancelDownload(id, message: "Download cancelled when the Habitat page changed.") }
        projectionGate.begin(); visibilitySequence = 0; appearanceSequence = 0; projection = nil
        let payload: [String: Any] = ["version": 1, "host": "archi-desktop", "sessionId": sessionID.uuidString, "visible": isVisible]
        let bytes = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let json = String(decoding: bytes, as: UTF8.self)
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(source: "Object.defineProperty(window, '__ARCHI_DESKTOP_BOOTSTRAP__', {value: Object.freeze(\(json)), writable:false, configurable:false});",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    private func sendVisibility() {
        guard let view = webView, HostedPlayNavigation.allowsDocument(view.url, profile: profile) else { return }
        visibilitySequence += 1
        let payload: [String: Any] = ["version": 1, "host": "archi-desktop", "sessionId": sessionID.uuidString,
                                    "sequence": visibilitySequence, "visible": isVisible && projectionGate.isActive]
        let session = sessionID
        visibilityDelivery = Task { [weak self, weak view] in
            guard !Task.isCancelled, let self, let view, self.webView === view,
                  self.sessionID == session, !self.isShutDown else { return }
            _ = try? await view.callAsyncJavaScript("if (window.__ARCHI_DESKTOP_HOST__) return window.__ARCHI_DESKTOP_HOST__.setVisibility(message); return false;",
                arguments: ["message": payload], in: nil, contentWorld: .page)
        }
    }

    private func armReadyTimeout(epoch: UUID) {
        readyTimeout?.cancel()
        readyTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, self.lifecycle == epoch, self.state == .starting else { return }
            self.retireFailedPage("The bundled game did not report readiness. Retry reloads this Habitat; saved history stays on this device.")
        }
    }

    private func contentRules() async throws -> WKContentRuleList {
        let allowed = "^http://127\\.0\\.0\\.1:\(profile.port)/"
        let rules: [[String: Any]] = [
            ["trigger": ["url-filter": ".*"], "action": ["type": "block"]],
            ["trigger": ["url-filter": allowed], "action": ["type": "ignore-previous-rules"]],
            ["trigger": ["url-filter": "^blob:http://127\\.0\\.0\\.1:\(profile.port)/"], "action": ["type": "ignore-previous-rules"]],
            ["trigger": ["url-filter": "^data:image/", "resource-type": ["image"]], "action": ["type": "ignore-previous-rules"]]
        ]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: rules), as: UTF8.self)
        return try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "archi-hosted-play-\(profile.rawValue)-v1", encodedContentRuleList: json) { list, error in
                if let list { continuation.resume(returning: list) }
                else { continuation.resume(throwing: error ?? HostedPlayError.invalidAssets) }
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !isShutDown, message.name == "archiJourneyProjection", message.frameInfo.isMainFrame,
              message.webView === webView,
              message.frameInfo.securityOrigin.protocol == "http",
              message.frameInfo.securityOrigin.host == "127.0.0.1",
              message.frameInfo.securityOrigin.port == Int(profile.port),
              HostedPlayNavigation.allowsDocument(message.frameInfo.request.url, profile: profile) else {
            rejectedMessageCount += 1; return
        }
        do {
            let value = try projectionGate.receive(message.body)
            projection = value
            if value.readiness == .ready {
                let becameReady = state != .ready
                readyTimeout?.cancel(); readyTimeout = nil
                state = .ready
                status = value.storage == .localBrowser ? "Habitat ready · history saved on this device" : "Habitat ready · session history only"
                if becameReady {
                    recordAppearanceDelivery("ready-projection sequence=\(value.sequence) image=\(appearance != nil)")
                    if let retry = retryAppearanceAfterReady {
                        retryAppearanceAfterReady = nil
                        retry()
                    } else { sendAppearance() }
                }
            }
        } catch { rejectedMessageCount += 1 }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard !isShutDown, state != .unavailable, webView === self.webView else { decisionHandler(.cancel); return }
        if navigationAction.shouldPerformDownload,
           navigationAction.sourceFrame.isMainFrame,
           HostedPlayNavigation.allowsDocument(navigationAction.sourceFrame.request.url, profile: profile),
           HostedPlayNavigation.allowsDownload(navigationAction.request.url, profile: profile) {
            decisionHandler(.download); return
        }
        guard navigationAction.targetFrame?.isMainFrame == true,
              HostedPlayNavigation.allowsDocument(navigationAction.request.url, profile: profile) else {
            rejectedNavigationCount += 1; decisionHandler(.cancel); return
        }
        // Each full navigation gets a new capability-free page token. Hash-only
        // movement within the document leaves its current projection intact.
        let old = webView.url, next = navigationAction.request.url
        if HostedPlayNavigation.requiresNewSession(from: old, to: next, isReload: navigationAction.navigationType == .reload) {
            cancelPanels()
            installBootstrap(webView.configuration.userContentController)
            state = .starting; armReadyTimeout(epoch: lifecycle)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        guard navigationResponse.isForMainFrame, HostedPlayNavigation.allowsDocument(navigationResponse.response.url, profile: profile),
              navigationResponse.canShowMIMEType else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { sendVisibility(); sendAppearance() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failedPage(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failedPage(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        failedPage(HostedPlayError.stopped)
    }
    private func failedPage(_ error: Error) {
        guard !isShutDown, (error as NSError).code != NSURLErrorCancelled else { return }
        retireFailedPage("Habitat is unavailable. \(String(error.localizedDescription.prefix(240)))")
    }
    private func retireFailedPage(_ message: String) {
        retireArenaCommand()
        projectionGate.retire(); projection = nil
        readyTimeout?.cancel(); readyTimeout = nil; cancelPanels()
        for id in Array(downloads.keys) { cancelDownload(id, message: "Download cancelled because Habitat became unavailable.") }
        webView?.stopLoading()
        sendVisibility()
        state = .unavailable; status = message
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        rejectedNavigationCount += 1; return nil
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) { decisionHandler(.deny) }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        guard isVisible, !isShutDown, frame.isMainFrame,
              HostedPlayNavigation.allowsDocument(frame.request.url, profile: profile), let window = webView.window else {
            completionHandler(nil); return
        }
        cancelPanels()
        let panel = NSOpenPanel(), id = UUID(), session = sessionID, visibility = visibilityRevision
        panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = "Choose a Journey copy to review in Habitat. Choosing a file does not replace your Journey."
        self.panel = panel; panelID = id; pendingOpen = completionHandler
        panel.beginSheetModal(for: window) { [weak self, weak panel] result in
            guard let self, self.panelID == id else { return }
            let callback = self.pendingOpen
            self.panel = nil; self.panelID = nil; self.pendingOpen = nil
            guard result == .OK, self.isVisible, self.sessionID == session, self.visibilityRevision == visibility, let url = panel?.url,
                  self.isBoundedJSONFile(url) else { callback?(nil); return }
            self.transferStatus = "Copy selected for web review · no Journey replaced by the native host"
            callback?([url])
        }
    }

    private func cancelPanels() {
        let open = pendingOpen, save = pendingSave, panel = panel
        pendingOpen = nil; pendingSave = nil; panelID = nil; self.panel = nil
        panel?.cancel(nil); open?(nil); save?(nil)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { register(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { register(download) }

    private func register(_ download: WKDownload) {
        guard !isShutDown, isVisible else { download.cancel { _ in }; return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-play-download-\(UUID().uuidString)", isDirectory: true)
        let id = ObjectIdentifier(download)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false) }
        catch { download.cancel { _ in }; transferStatus = "Could not prepare a temporary download."; return }
        downloads[id] = Download(item: download, session: sessionID, visibility: visibilityRevision, directory: directory, staged: directory.appendingPathComponent("copy.json"))
        downloads[id]?.observation = download.progress.observe(\.completedUnitCount, options: [.new]) { [weak self] progress, _ in
            let count = progress.completedUnitCount
            Task { @MainActor in
                if count > Self.maximumArchiveBytes { self?.cancelDownload(id, message: "Copy exceeded the 2 MB limit. Nothing was saved.") }
            }
        }
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping @MainActor @Sendable (URL?) -> Void) {
        let id = ObjectIdentifier(download)
        guard isVisible, let record = downloads[id], record.session == sessionID, record.visibility == visibilityRevision,
              HostedPlayNavigation.allowsDownload(response.url, profile: profile),
              response.expectedContentLength <= Self.maximumArchiveBytes, let window = webView?.window else {
            completionHandler(nil); cancelDownload(id, message: "Download cancelled."); return
        }
        cancelPanels()
        let panel = NSSavePanel(), panelID = UUID()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = String(URL(fileURLWithPath: suggestedFilename).lastPathComponent.prefix(160))
        panel.message = "Save a Journey copy. Your current Habitat stays unchanged."
        self.panel = panel; self.panelID = panelID; pendingSave = completionHandler
        panel.beginSheetModal(for: window) { [weak self, weak panel] result in
            guard let self, self.panelID == panelID else { return }
            let callback = self.pendingSave
            self.panel = nil; self.panelID = nil; self.pendingSave = nil
            guard result == .OK, self.isVisible, record.session == self.sessionID, record.visibility == self.visibilityRevision,
                  let destination = panel?.url, destination.pathExtension.lowercased() == "json",
                  let approved = try? HostedPlayTransfer.captureDestination(destination), self.downloads[id] != nil else {
                callback?(nil); self.cancelDownload(id, message: "Download cancelled. Nothing was saved."); return
            }
            self.downloads[id]?.destination = destination
            self.downloads[id]?.approvedDestination = approved
            self.transferStatus = "Saving Journey copy…"
            // WebKit requires a nonexistent destination. Download to our own
            // staging file, then atomically replace the user-approved final file.
            callback?(record.staged)
        }
    }

    func download(_ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest, decisionHandler: @escaping @MainActor @Sendable (WKDownload.RedirectPolicy) -> Void) { decisionHandler(.cancel) }
    func download(_ download: WKDownload, didReceive challenge: URLAuthenticationChallenge,
                  completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) { completionHandler(.cancelAuthenticationChallenge, nil) }

    func downloadDidFinish(_ download: WKDownload) {
        let id = ObjectIdentifier(download)
        guard let record = downloads[id], let destination = record.destination,
              let approved = record.approvedDestination else { cleanupDownload(id); return }
        guard !isShutDown, isVisible, record.session == sessionID, record.visibility == visibilityRevision else {
            cancelDownload(id, message: "Download cancelled because its Habitat session changed."); return
        }
        do {
            guard isBoundedJSONFile(record.staged) else { throw HostedPlayError.invalidDownload }
            let receipt = try HostedPlayTransfer.finish(source: record.staged, destination: destination, approved: approved)
            lastDownload = receipt
            transferStatus = "Copy saved · \(receipt.byteCount) bytes read back and verified. Journey admission remains in the game."
        } catch { transferStatus = "The copy was not verified as saved. \(String(error.localizedDescription.prefix(200)))" }
        cleanupDownload(id)
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard downloads[ObjectIdentifier(download)] != nil else { return }
        transferStatus = "Download did not finish. \(String(error.localizedDescription.prefix(200)))"
        cleanupDownload(ObjectIdentifier(download))
    }
    private func cancelDownload(_ id: ObjectIdentifier, message: String) {
        downloads[id]?.item.cancel { _ in }
        cleanupDownload(id); transferStatus = message
    }
    private func cleanupDownload(_ id: ObjectIdentifier) {
        guard let record = downloads.removeValue(forKey: id) else { return }
        record.observation?.invalidate()
        try? FileManager.default.removeItem(at: record.directory)
    }
    private func isBoundedJSONFile(_ url: URL) -> Bool {
        guard url.isFileURL, url.pathExtension.lowercased() == "json",
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let count = values.fileSize, count > 0, count <= Self.maximumArchiveBytes else { return false }
        return true
    }
}

@MainActor
private final class HostedPlayVisibilityCompletion {
    private var continuation: CheckedContinuation<Void, Never>?
    init(_ continuation: CheckedContinuation<Void, Never>) { self.continuation = continuation }
    func finish() {
        let pending = continuation; continuation = nil
        pending?.resume()
    }
}

@MainActor
private final class HostedPlayWeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var host: HostedPlayHost?
    init(_ host: HostedPlayHost) { self.host = host }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        host?.userContentController(userContentController, didReceive: message)
    }
}

struct HostedPlayWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> HostedPlayViewContainer {
        let container = HostedPlayViewContainer(frame: .zero)
        container.wantsLayer = true
        container.install(webView)
        return container
    }
    func updateNSView(_ nsView: HostedPlayViewContainer, context: Context) { nsView.install(webView) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HostedPlayViewContainer, context: Context) -> CGSize? {
        HostedPlayViewContainer.proposedSize(proposal)
    }
    static func dismantleNSView(_ nsView: HostedPlayViewContainer, coordinator: ()) { nsView.detach() }
    // The host retains this view across sidebar changes. Only explicit retry or
    // app shutdown releases it, so leaving Play does not create another game.
}

/// The viewport is sized by the workspace, independently of WebKit's document
/// fitting size. Without this boundary a tall document can inflate the entire
/// SwiftUI split view and push native headers and footers outside the window.
@MainActor
final class HostedPlayViewContainer: NSView {
    private(set) var webView: WKWebView?
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    static func proposedSize(_ proposal: ProposedViewSize) -> CGSize {
        func finite(_ value: CGFloat?, fallback: CGFloat) -> CGFloat {
            guard let value, value.isFinite else { return fallback }
            return max(0, value)
        }
        // Honor zero-size minimum probes as well as finite available space.
        // Unspecified/infinite probes get a finite ideal, never document height.
        return CGSize(width: finite(proposal.width, fallback: 640), height: finite(proposal.height, fallback: 420))
    }

    func install(_ next: WKWebView) {
        guard webView !== next || next.superview !== self else { return }
        detach()
        webView = next
        next.frame = bounds
        next.autoresizingMask = [.width, .height]
        addSubview(next)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    func detach() {
        // A retained WebKit view can already belong to SwiftUI's replacement
        // wrapper when the previous wrapper is dismantled.
        if webView?.superview === self { webView?.removeFromSuperview() }
        webView = nil
    }

    override func layout() {
        super.layout()
        if let webView, webView.superview === self, webView.frame != bounds { webView.frame = bounds }
    }
}
