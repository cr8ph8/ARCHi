import AppKit
import Combine
import SwiftUI

/// Product naming can change without changing the owner of the user's KIN.
/// The historical directory and bundle ID intentionally remain stable.
enum DesktopApplicationIdentity {
    static let bundleIdentifier = "com.quotient.archi.desktop.review"
    static let legacyPreviewIdentifier = "com.quotient.archi.desktop.preview"

    static func preferenceURL(applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent("ARCHiDesktopReview/preferences.json")
    }

    struct Instance: Equatable {
        let processIdentifier: pid_t
        let bundleIdentifier: String?
        let launchedAt: Date
    }

    enum LaunchDisposition: Equatable {
        case beginSession
        case reuse(pid_t)
        case reviewLegacy(pid_t)
    }

    static func launchDisposition(currentProcess: pid_t, instances: [Instance]) -> LaunchDisposition {
        // A common ordering makes two simultaneous launches agree on one owner.
        let ordered = instances.sorted {
            $0.launchedAt == $1.launchedAt
                ? $0.processIdentifier < $1.processIdentifier : $0.launchedAt < $1.launchedAt
        }
        if let owner = ordered.first(where: { $0.bundleIdentifier == bundleIdentifier }),
           owner.processIdentifier != currentProcess {
            return .reuse(owner.processIdentifier)
        }
        if let preview = ordered.first(where: {
            $0.bundleIdentifier == legacyPreviewIdentifier && $0.processIdentifier != currentProcess
        }) {
            return .reviewLegacy(preview.processIdentifier)
        }
        return .beginSession
    }

    @MainActor
    static func mayStartSession() -> Bool {
        let applications = NSWorkspace.shared.runningApplications
        let instances = applications.map {
            Instance(processIdentifier: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier,
                     launchedAt: $0.launchDate ?? .distantPast)
        }
        let disposition = launchDisposition(currentProcess: ProcessInfo.processInfo.processIdentifier,
                                            instances: instances)
        switch disposition {
        case .beginSession:
            return true
        case .reuse(let pid):
            if let application = applications.first(where: { $0.processIdentifier == pid }) {
                application.unhide()
                application.activate(options: [.activateAllWindows])
                if let url = application.bundleURL { NSWorkspace.shared.open(url) }
            }
            return false
        case .reviewLegacy(let pid):
            let alert = NSAlert()
            alert.messageText = "An older ARCHi preview is still open"
            alert.informativeText = "Save or export anything you want to keep in Desktop Preview, then quit it and open ARCHi again. ARCHi will use your existing KIN profile. This launch has not opened or changed a companion save."
            alert.addButton(withTitle: "Show Desktop Preview")
            alert.runModal()
            if let application = applications.first(where: { $0.processIdentifier == pid }) {
                application.unhide()
                application.activate(options: [.activateAllWindows])
            }
            return false
        }
    }
}

@main
struct ARCHiDesktopMain {
    @MainActor
    static func main() async {
        if let index = CommandLine.arguments.firstIndex(of: "--import-companion-profile"),
           CommandLine.arguments.indices.contains(index + 1) {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: DesktopApplicationIdentity.bundleIdentifier)
                .contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            guard !running else { print("Quit ARCHi before importing a separate companion profile."); exit(2) }
            do {
                let profiles = try CompanionProfiles()
                let bytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
                let imported = try CompanionProfileInstaller.install(bytes, profiles: profiles)
                if CommandLine.arguments.contains("--activate-imported-profile") { try profiles.select(imported.id) }
                print("Imported separate profile: \(imported.id)")
                exit(0)
            } catch { print("Profile import stopped: \(error.localizedDescription)"); exit(1) }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--starter-art-render"),
           CommandLine.arguments.indices.contains(index + 1) {
            exit(EvolutionVisualDiagnostics.renderStarterStudy(directory: URL(fileURLWithPath: CommandLine.arguments[index + 1])) ? 0 : 1)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--evolution-render"),
           CommandLine.arguments.indices.contains(index + 1) {
            exit(EvolutionVisualDiagnostics.run(directory: URL(fileURLWithPath: CommandLine.arguments[index + 1])) ? 0 : 1)
        }
        if CommandLine.arguments.contains("--routing-smoke") {
            exit(await AssistantRoutingDiagnostics.run() ? 0 : 1)
        }
        if CommandLine.arguments.contains("--automatic-assistant-smoke") {
            exit(await AutomaticAssistantDiagnostics.run() ? 0 : 1)
        }
        if CommandLine.arguments.contains("--hampton-context-smoke") || CommandLine.arguments.contains("--hampton-cancel-smoke") {
            let passed = await HamptonDiagnostics.run(cancel: CommandLine.arguments.contains("--hampton-cancel-smoke"))
            exit(passed ? 0 : 1)
        }
        if CommandLine.arguments.contains("--qwen-check") || CommandLine.arguments.contains("--qwen-selection-smoke") || CommandLine.arguments.contains("--qwen-cancel-smoke") {
            let cancel = CommandLine.arguments.contains("--qwen-cancel-smoke")
            let args = CommandLine.arguments
            var model = QwenAssistant.defaultModel
            if let index = args.firstIndex(of: "--qwen-model") {
                guard args.indices.contains(index + 1), QwenAssistant.supportedModels.contains(args[index + 1]) else {
                    print("Choose an installed supported local Qwen model with --qwen-model.")
                    exit(2)
                }
                model = args[index + 1]
            }
            let passed = await QwenDiagnostics.run(live: args.contains("--qwen-selection-smoke") || cancel, cancel: cancel, model: model)
            exit(passed ? 0 : 1)
        }
        if CommandLine.arguments.contains("--assistant-check") || CommandLine.arguments.contains("--assistant-smoke") || CommandLine.arguments.contains("--assistant-cancel-smoke") || CommandLine.arguments.contains("--assistant-selection-smoke") {
            let cancel = CommandLine.arguments.contains("--assistant-cancel-smoke")
            let selection = CommandLine.arguments.contains("--assistant-selection-smoke")
            let passed = await AssistantDiagnostics.run(live: CommandLine.arguments.contains("--assistant-smoke") || cancel || selection, cancel: cancel, selection: selection)
            exit(passed ? 0 : 1)
        }
        guard await waitForPreviousSession() else { return }
        runDesktop()
    }

    @MainActor
    private static func waitForPreviousSession() async -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--archi-restart-from-pid") else { return true }
        guard arguments.indices.contains(index + 1), let pid = pid_t(arguments[index + 1]), pid > 0,
              pid != ProcessInfo.processInfo.processIdentifier else { return false }
        for _ in 0..<300 {
            guard let previous = NSRunningApplication(processIdentifier: pid), !previous.isTerminated else { return true }
            guard previous.bundleIdentifier == DesktopApplicationIdentity.bundleIdentifier else { return false }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return false }
        }
        let alert = NSAlert()
        alert.messageText = "ARCHi is still closing the previous companion"
        alert.informativeText = "Let its current work finish closing, then open ARCHi again. No second companion session was started."
        alert.runModal()
        return false
    }

    @MainActor
    static func runDesktop(mayStartSession: @MainActor () -> Bool = DesktopApplicationIdentity.mayStartSession,
                           makeDelegate: @MainActor () throws -> DesktopDelegate = {
                               try DesktopDelegate(profiles: CompanionProfiles())
                           }) {
        // Decide ownership before constructing CompanionStore or its services.
        guard mayStartSession() else { return }
        let app = NSApplication.shared
        do {
            let delegate = try makeDelegate()
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "ARCHi could not open this companion"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

@MainActor
final class DesktopDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let playHost = HostedPlayHost()
    let store: CompanionStore
    private let profiles: CompanionProfiles
    private var pendingProfileID: String?
    private var companion: CompanionPanelController?
    private var workspace: NSWindow?
    private var statusItem: NSStatusItem?
    private var reactorControl: ReactorControlServer?
    private var harmony: CompanionHarmonyPlayer?
    private var expressionObservers: [NSObjectProtocol] = []
    private var appearanceObserver: AnyCancellable?
    private var assistantRouteObserver: AnyCancellable?
    private var isReviewingQuit = false
    private var terminationInProgress = false

    init(profiles: CompanionProfiles) throws {
        self.profiles = profiles
        self.store = CompanionStore(preferenceURL: try profiles.selectedPreferenceURL(), allowsPlay: false,
            tokenSteward: TokenStewardStore(url: profiles.accountStewardURL))
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let routePreference = NativeAssistantRoutePreference(defaults: .standard)
        store.prepareNativeAssistant(route: routePreference.load())
        assistantRouteObserver = store.$route.dropFirst().removeDuplicates()
            .sink { routePreference.save($0) }
        appearanceObserver = store.$preferences.map(\.workspaceAppearance).removeDuplicates()
            .sink { [weak self] appearance in self?.applyWorkspaceAppearance(appearance) }
        configureMenus()
        let panel = CompanionPanelController(store: store)
        companion = panel
        harmony = CompanionHarmonyPlayer(store: store)
        store.onShowCompanion = { [weak panel] in panel?.show() }
        store.onHideCompanion = { [weak panel] in panel?.hide() }
        store.onOpenWorkspace = { [weak self] section in self?.showWorkspace(section) }
        store.onBeginDesktopInterest = { [weak self] in
            self?.workspace?.orderOut(nil)
            self?.companion?.dismissChatBubble()
        }
        store.onOpenPlay = { [weak self] in self?.showWorkspace(.play) }
        playHost.onVisibilityChanged = { [weak panel] visible in panel?.setPresentedInHabitat(visible) }
        playHost.onJourneyOriginChanged = { [weak store] origin in store?.evolution.observeJourneyOrigin(origin) }
        playHost.onJourneyProjectionChanged = { [weak store] projection in store?.observeQiMonJourney(projection) }
        // Desktop-only delivery reads the validated native companion record.
        // The retained game host, web view and local server are not started.
        if store.allowsPlay { playHost.start() }
        panel.show()
        let control = ReactorControlServer(profile: .review) { [weak store] request in
            store?.reactor.control(request) ?? ["ok": false, "error": "ARCHi is closing."]
        }
        do { try control.start(); reactorControl = control }
        catch { /* The native UI remains usable if another profile owns its local control socket. */ }
        expressionObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self, weak store] _ in
                Task { @MainActor in
                    store?.voiceInput.cancel()
                    store?.desktopInterest.cancel(reason: "Mac is sleeping. Point again when ready.")
                    if let store { store.unityPresentation.setSuspended(true, store: store) }
                    self?.harmony?.suspend()
                    store?.stopKinLightPreview()
                    store?.reactor.stop(reason: "Mac is sleeping. Local artwork restored.")
                }
            })
        expressionObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.harmony?.resume()
                    if let store = self?.store { store.unityPresentation.setSuspended(false, store: store) }
                }
            })
        expressionObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak store] _ in
                Task { @MainActor in
                    store?.refreshReactorReference()
                    if let store { store.unityPresentation.refresh(store: store) }
                }
            })
        showWorkspace(.home)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func applyWorkspaceAppearance(_ appearance: WorkspaceAppearance) {
        // Scope the override to ARCHi. The companion's authored palette and
        // macOS's system preference remain unchanged.
        NSApp.appearance = appearance.appKitAppearance
        workspace?.appearance = appearance.appKitAppearance
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.unityPresentation.stop()
        store.disconnectAssistant()
        LocalQwenRuntime.shared.shutdown()
    }

    func applicationDidHide(_ notification: Notification) {
        store.unityPresentation.setSuspended(true, store: store)
        store.desktopInterest.cancel(reason: "ARCHi hidden. Point again when ready.")
        store.voiceInput.cancel()
        harmony?.suspend()
        store.stopKinLightPreview()
        store.reactor.stop(reason: "ARCHi hidden. Local artwork restored.")
        playHost.setVisible(false)
        store.invalidateTextSelection(reason: "Workspace hidden; passage reference cleared.")
    }

    func applicationDidResignActive(_ notification: Notification) {
        store.voiceInput.cancel()
        playHost.setVisible(false)
        store.invalidatePlacementPreview(reason: "Workspace is no longer active. Preview again when you return.")
    }

    func windowWillClose(_ notification: Notification) {
        store.voiceInput.cancel()
        playHost.setVisible(false)
        store.invalidateTextSelection(reason: "Workspace closed; passage reference cleared.")
    }

    func windowDidMiniaturize(_ notification: Notification) {
        store.voiceInput.cancel()
        playHost.setVisible(false)
        store.invalidateTextSelection(reason: "Workspace minimized; passage reference cleared.")
    }

    func windowDidResignKey(_ notification: Notification) {
        store.voiceInput.cancel()
        store.invalidatePlacementPreview(reason: "Workspace focus changed. Preview again when you return.")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        store.unityPresentation.setSuspended(false, store: store)
        harmony?.resume()
        updatePlayVisibility()
    }
    func windowDidDeminiaturize(_ notification: Notification) { updatePlayVisibility() }

    private func updatePlayVisibility() {
        playHost.setVisible(store.section == .play && NSApp.isActive && !NSApp.isHidden
            && workspace?.isVisible == true && workspace?.isMiniaturized == false)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationInProgress { return .terminateLater }
        guard !isReviewingQuit else { return .terminateCancel }
        if store.hasPersonalContextDraft || store.hasSeedDesignDraft {
            pendingProfileID = nil
            let alert = NSAlert()
            alert.messageText = "Finish reviewing personal context"
            alert.informativeText = "Keep or discard your personal-context or Seed design answers before closing or switching companions."
            alert.addButton(withTitle: "Return to edit")
            alert.runModal()
            return .terminateCancel
        }
        if pendingProfileID != nil, let review = profileSwitchReview {
            pendingProfileID = nil
            let alert = NSAlert()
            alert.messageText = "Keep your work before switching companions"
            alert.informativeText = review.message
            alert.addButton(withTitle: "Review")
            alert.runModal()
            showWorkspace(review.section)
            return .terminateCancel
        }
        isReviewingQuit = true
        let canQuit = store.confirmQuitRetainingWork()
        isReviewingQuit = false
        guard canQuit else { pendingProfileID = nil; return .terminateCancel }
        let restarting = pendingProfileID != nil
        if let target = pendingProfileID {
            do { try profiles.select(target) }
            catch {
                pendingProfileID = nil
                let alert = NSAlert()
                alert.messageText = "The companion could not be switched"
                alert.informativeText = error.localizedDescription
                alert.runModal()
                return .terminateCancel
            }
        }
        terminationInProgress = true
        store.voiceInput.cancel()
        harmony?.suspend()
        reactorControl?.stop(); reactorControl = nil
        Task { [store, playHost] in
            // Retire answer ownership first, before waiting for presentation cleanup.
            // A late model callback must not publish into the closing session.
            await store.shutdownAssistant()
            LocalQwenRuntime.shared.shutdown()
            await store.reactor.shutdown()
            await playHost.shutdown()
            if restarting {
                // Do not await a launch-complete callback: the new process waits
                // for this one to exit before creating its own profile owner.
                let launcher = Process()
                launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                launcher.arguments = ["-n", Bundle.main.bundleURL.path, "--args", "--archi-restart-from-pid",
                                      String(ProcessInfo.processInfo.processIdentifier)]
                launcher.standardOutput = FileHandle.nullDevice
                launcher.standardError = FileHandle.nullDevice
                do {
                    try launcher.run()
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Open ARCHi to continue with your selected companion"
                    alert.informativeText = "Your work has closed safely and the companion choice is saved. macOS could not reopen ARCHi automatically. Open ARCHi in Applications."
                    alert.runModal()
                }
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private var profileSwitchReview: (message: String, section: WorkspaceSection)? {
        if store.preferenceRetention == .changed {
            return ("Save your appearance and conversation preferences in Memories before switching. Your current companion stays open.", .memory)
        }
        if store.lessonDraft != nil { return ("Keep or discard your lesson draft before switching.", .memory) }
        if store.focusGestureDraft != nil { return ("Keep or discard your gesture draft before switching.", .appearance) }
        if store.voiceInput.phase == .review { return ("Use or discard your voice draft before switching.", .assistant) }
        if store.marketplaceCatalog.isBusy || store.marketplaceCatalog.hasPendingMutation {
            return ("Finish or reconcile the marketplace request before switching. Its pending result belongs to this session.", .marketplace)
        }
        return nil
    }

    @objc private func switchCompanionProfile(_ sender: NSMenuItem) {
        guard !terminationInProgress, !isReviewingQuit, let id = sender.representedObject as? String,
              id != profiles.selected.id else { return }
        pendingProfileID = id
        NSApp.terminate(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        store.showCompanion()
        showWorkspace(store.section)
        return true
    }

    func showWorkspace(_ section: WorkspaceSection) {
        store.section = section == .play && !store.allowsPlay ? .assistant : section
        if workspace == nil {
            let window = WorkspaceWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "ARCHi"
            window.titlebarAppearsTransparent = true
            window.backgroundColor = .windowBackgroundColor
            window.appearance = store.preferences.workspaceAppearance.appKitAppearance
            window.contentView = WorkspaceView.makeHostingView(store: store, playHost: playHost)
            WorkspaceView.applyWindowMinimum(to: window)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            workspace = window
        }
        workspace?.makeKeyAndOrderFront(nil)
        // SwiftUI installs its native split hierarchy during attachment.
        // Reapply the window-owned minimum after that first layout turn.
        if let workspace {
            DispatchQueue.main.async { [weak workspace] in
                guard let workspace else { return }
                WorkspaceView.applyWindowMinimum(to: workspace)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        updatePlayVisibility()
    }

    @objc private func openHome() { showWorkspace(.home) }
    @objc private func openAssistant() { showWorkspace(.assistant) }
    @objc private func openMarketplace() { showWorkspace(.marketplace) }
    @objc private func openUnity() { showWorkspace(.unity) }
    @objc private func openUnityArena() {
        Task { await ArenaEntryAction.open(store: store) }
    }
    @objc private func openWorkTogether() { showWorkspace(.context) }
    @objc private func openMemory() { showWorkspace(.memory) }
    @objc private func openAppearance() { showWorkspace(.appearance) }
    @objc private func openEvolution() { showWorkspace(.evolution) }
    @objc private func openNodeLab() { showWorkspace(.nodeLab) }
    @objc private func openSettings() { showWorkspace(.connections) }
    @objc private func showCompanion() { store.showCompanion() }
    @objc private func hideCompanion() { store.hideCompanion() }
    @objc private func stopWork() { store.cancelWork(); store.reactor.stop() }

    @objc private func showAbout() {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: ARCHiIdentity.name,
            .credits: NSAttributedString(string: "\(ARCHiIdentity.descriptor)\nA personal desktop companion by Quotient Intelligent.\nIdeas × Insight × Impact.")
        ]
        if let mark = QuotientBranding.mark { options[.applicationIcon] = mark }
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    @objc private func revealApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func configureMenus() {
        let menu = NSMenu()
        let appRoot = NSMenuItem()
        let appMenu = NSMenu(title: "ARCHi")
        appMenu.addItem(item("About ARCHi", #selector(showAbout)))
        appMenu.addItem(item("Show ARCHi in Finder", #selector(revealApplication)))
        let companions = NSMenuItem(title: "Companions", action: nil, keyEquivalent: "")
        let companionMenu = NSMenu(title: "Companions")
        for profile in profiles.profiles {
            let choice = item(profile.displayName, #selector(switchCompanionProfile(_:)))
            choice.representedObject = profile.id
            choice.state = profile.id == profiles.selected.id ? .on : .off
            companionMenu.addItem(choice)
        }
        companions.submenu = companionMenu
        appMenu.addItem(companions)
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings…", #selector(openSettings), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide ARCHi", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Quit ARCHi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appRoot.submenu = appMenu
        menu.addItem(appRoot)

        let editRoot = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"),
                                     ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        editRoot.submenu = edit
        menu.addItem(editRoot)

        let windowRoot = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(item(ARCHiIdentity.homeTitle, #selector(openHome), key: "0"))
        windowMenu.addItem(item("Assistant", #selector(openAssistant), key: "1"))
        windowMenu.addItem(item("Companion · Appearance", #selector(openAppearance), key: "2"))
        windowMenu.addItem(item("Companion · Growth", #selector(openEvolution), key: "3"))
        windowMenu.addItem(item("Node Lab", #selector(openNodeLab), key: "4"))
        windowMenu.addItem(item("Marketplace", #selector(openMarketplace), key: "5"))
        windowMenu.addItem(item("Arena", #selector(openUnity), key: "6"))
        windowMenu.addItem(item("Work together", #selector(openWorkTogether), key: "7"))
        windowMenu.addItem(item("What I remember", #selector(openMemory), key: "8"))
        windowMenu.addItem(item("Play Arena", #selector(openUnityArena), key: "9"))
        windowMenu.addItem(.separator())
        windowMenu.addItem(item("Show companion", #selector(showCompanion)))
        windowMenu.addItem(item("Hide companion", #selector(hideCompanion)))
        windowMenu.addItem(item("Stop current work", #selector(stopWork), key: "."))
        windowMenu.addItem(NSMenuItem(title: "Close workspace", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowRoot.submenu = windowMenu
        menu.addItem(windowRoot)
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu

        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "ARCHi")
        status.button?.toolTip = "ARCHi companion"
        let quick = NSMenu()
        quick.addItem(item("Open ARCHi Home", #selector(openHome)))
        quick.addItem(item("Show ARCHi", #selector(showCompanion)))
        quick.addItem(item("Open assistant", #selector(openAssistant)))
        quick.addItem(item("Play Arena", #selector(openUnityArena)))
        quick.addItem(item("Marketplace", #selector(openMarketplace)))
        quick.addItem(item("Settings…", #selector(openSettings)))
        quick.addItem(.separator())
        quick.addItem(NSMenuItem(title: "Quit ARCHi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        status.menu = quick
        statusItem = status
    }
}
