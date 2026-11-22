import AppKit
import SwiftUI

@main
struct ARCHiDesktopMain {
    @MainActor
    static func main() async {
        if Bundle.main.bundleIdentifier == "com.quotient.archi.desktop.memory-demo" {
            guard let index = CommandLine.arguments.firstIndex(of: "--session"),
                  CommandLine.arguments.indices.contains(index + 1),
                  let session = UUID(uuidString: CommandLine.arguments[index + 1]) else {
                print("Launch the disposable session with script/memory_demo/run.py.")
                exit(2)
            }
            LessonMemoryDemo.run(session: session)
            return
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
        runDesktop()
    }

    @MainActor
    private static func runDesktop() {
        let app = NSApplication.shared
        let delegate = DesktopDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class DesktopDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let playHost = HostedPlayHost()
    let store: CompanionStore = {
        if Bundle.main.bundleIdentifier == "com.quotient.archi.desktop.review" {
            let reviewPreferences = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ARCHiDesktopReview/preferences.json")
            return CompanionStore(preferenceURL: reviewPreferences, allowsPlay: false)
        }
        return CompanionStore(allowsPlay: false)
    }()
    private var companion: CompanionPanelController?
    private var workspace: NSWindow?
    private var statusItem: NSStatusItem?
    private var reactorControl: ReactorControlServer?
    private var harmony: CompanionHarmonyPlayer?
    private var expressionObservers: [NSObjectProtocol] = []
    private var isReviewingQuit = false
    private var terminationInProgress = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
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
        let control = ReactorControlServer(profile: Bundle.main.bundleIdentifier == "com.quotient.archi.desktop.review" ? .review : .preview) { [weak store] request in
            store?.reactor.control(request) ?? ["ok": false, "error": "ARCHi is closing."]
        }
        do { try control.start(); reactorControl = control }
        catch { /* The native UI remains usable if another profile owns its local control socket. */ }
        expressionObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self, weak store] _ in
                Task { @MainActor in
                    store?.voiceInput.cancel()
                    store?.desktopInterest.cancel(reason: "Mac is sleeping. Point again when ready.")
                    self?.harmony?.suspend()
                    store?.stopKinLightPreview()
                    store?.reactor.stop(reason: "Mac is sleeping. Local artwork restored.")
                }
            })
        expressionObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.harmony?.resume() }
            })
        expressionObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak store] _ in
                Task { @MainActor in store?.refreshReactorReference() }
            })
        showWorkspace(.assistant)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) { store.disconnectAssistant() }

    func applicationDidHide(_ notification: Notification) {
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
        isReviewingQuit = true
        let canQuit = store.confirmQuitRetainingWork()
        isReviewingQuit = false
        guard canQuit else { return .terminateCancel }
        terminationInProgress = true
        store.voiceInput.cancel()
        harmony?.suspend()
        reactorControl?.stop(); reactorControl = nil
        Task { [store, playHost] in
            // Retire answer ownership first, before waiting for presentation cleanup.
            // A late model callback must not publish into the closing session.
            await store.shutdownAssistant()
            await store.reactor.shutdown()
            await playHost.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        store.showCompanion()
        showWorkspace(store.section)
        return true
    }

    func showWorkspace(_ section: WorkspaceSection) {
        store.section = section == .play && !store.allowsPlay ? .assistant : section
        if workspace == nil {
            let window = WorkspaceWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 750),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = Bundle.main.bundleIdentifier == "com.quotient.archi.desktop.review"
                ? "ARCHi · Development Review" : "ARCHi · Desktop Preview"
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(calibratedRed: 0.97, green: 0.96, blue: 0.95, alpha: 1)
            window.contentView = WorkspaceView.makeHostingView(store: store, playHost: playHost)
            WorkspaceView.applyWindowMinimum(to: window)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            workspace = window
        }
        workspace?.makeKeyAndOrderFront(nil)
        // NavigationSplitView installs native window chrome during attachment.
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

    @objc private func openAssistant() { showWorkspace(.assistant) }
    @objc private func openMarketplace() { showWorkspace(.marketplace) }
    @objc private func openAppearance() { showWorkspace(.appearance) }
    @objc private func openEvolution() { showWorkspace(.evolution) }
    @objc private func openNodeLab() { showWorkspace(.nodeLab) }
    @objc private func openSettings() { showWorkspace(.rhythm) }
    @objc private func showCompanion() { store.showCompanion() }
    @objc private func hideCompanion() { store.hideCompanion() }
    @objc private func stopWork() { store.cancelWork(); store.reactor.stop() }

    @objc private func showAbout() {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "ARCHi",
            .credits: NSAttributedString(string: "A personal desktop companion by Quotient Intelligent.\nIdeas × Insight × Impact.")
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
        windowMenu.addItem(item("Assistant", #selector(openAssistant), key: "1"))
        windowMenu.addItem(item("Appearance", #selector(openAppearance), key: "2"))
        windowMenu.addItem(item("Evolution", #selector(openEvolution), key: "3"))
        windowMenu.addItem(item("Node Lab", #selector(openNodeLab), key: "4"))
        windowMenu.addItem(item("Marketplace", #selector(openMarketplace), key: "5"))
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
        quick.addItem(item("Show ARCHi", #selector(showCompanion)))
        quick.addItem(item("Open assistant", #selector(openAssistant)))
        quick.addItem(item("Open Node Lab", #selector(openNodeLab)))
        quick.addItem(item("Marketplace", #selector(openMarketplace)))
        quick.addItem(item("Appearance", #selector(openAppearance)))
        quick.addItem(item("Settings…", #selector(openSettings)))
        quick.addItem(.separator())
        quick.addItem(NSMenuItem(title: "Quit ARCHi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        status.menu = quick
        statusItem = status
    }
}
