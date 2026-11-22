import AppKit
import SwiftUI

/// A separately staged bundle with a private, one-session profile. The sheet,
/// admission decisions, persistence and reloading belong to the desktop app.
@MainActor
final class LessonMemoryDemo: NSObject, NSApplicationDelegate {
    private let store: CompanionStore
    private var window: NSWindow?
    private var shuttingDown = false

    private init(profile: URL) {
        store = CompanionStore(preferenceURL: profile, allowsPlay: false)
        super.init()
    }

    static func run(session: UUID) {
        let directory = URL(fileURLWithPath: "/private/tmp/archi-memory-demo-" + session.uuidString)
        // The launcher creates a fresh, private directory, or reuses its own
        // directory for the next launch in the same demonstration.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path),
              attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700 else { exit(2) }
        let app = NSApplication.shared
        let delegate = LessonMemoryDemo(profile: directory.appendingPathComponent("preferences.json"))
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit Memory Demo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.mainMenu = menu
        store.share(text: "INT. ARENA – DAY", name: "Screenplay A")
        let view = MemoryReview(store: store)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "ARCHi Memory Demo"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !shuttingDown else { return .terminateLater }
        shuttingDown = true
        Task {
            await store.shutdownAssistant()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

private struct MemoryReview: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Memory review").font(.largeTitle.bold())
                Text("Disposable session · " + (store.sourceName ?? "No shared copy"))
                KeptLessonsCard(store: store, changeDemoSource: {
                    store.share(text: "EXT. FOREST – NIGHT", name: "Screenplay B")
                })
            }.padding(24)
        }
    }
}
