import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// A local application shortcut. This owner never reads or transfers companion
/// profiles, conversations, Journey records or the game's save files.
@MainActor
final class QiMonLocalGame: ObservableObject {
    static let bundleIdentifier = "com.quotient.thedrifter.qimon.mac"
    static let selectionKey = "selectedGameBookmark.v1"
    static let applicationName = "QiMon First Signal.app"
    typealias Launch = @MainActor (URL) async throws -> String

    @Published private(set) var availableApp: URL?
    @Published private(set) var status = "Choose your local QiMon game to begin."
    @Published private(set) var isOpening = false
    private let defaults: UserDefaults
    private let candidates: [URL]
    private let launch: Launch

    init(defaults: UserDefaults = UserDefaults(suiteName: "com.quotient.archi.qimon-local-play")!,
         candidates: [URL]? = nil, launch: @escaping Launch = QiMonLocalGame.openApplication) {
        self.defaults = defaults
        self.candidates = candidates ?? Self.discoveryCandidates(in: Bundle.main.bundleURL)
        self.launch = launch
        refresh()
    }

    static func discoveryCandidates(in hostApp: URL) -> [URL] {
        [hostApp.appendingPathComponent("Contents/Resources/" + applicationName),
         hostApp.deletingLastPathComponent().appendingPathComponent(applicationName)]
    }

    /// Validate metadata from disk each time; Bundle's cached Info dictionary
    /// can outlive an app moved or replaced after a previous selection.
    static func isCompatibleApp(_ url: URL) -> Bool {
        guard url.isFileURL, url.pathExtension.lowercased() == "app" else { return false }
        let root = url.resolvingSymlinksInPath().standardizedFileURL
        let info = root.appendingPathComponent("Contents/Info.plist")
        guard let size = try? info.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              (1...65536).contains(size), let bytes = try? Data(contentsOf: info),
              let values = try? PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any],
              values["CFBundleIdentifier"] as? String == bundleIdentifier,
              values["CFBundlePackageType"] as? String == "APPL",
              let executable = values["CFBundleExecutable"] as? String,
              !executable.isEmpty, executable != ".", executable != "..",
              !executable.contains("/"), !executable.contains("\\") else { return false }
        let binaries = root.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let binary = binaries.appendingPathComponent(executable).resolvingSymlinksInPath().standardizedFileURL
        guard binary.deletingLastPathComponent() == binaries,
              FileManager.default.isExecutableFile(atPath: binary.path) else { return false }
        return true
    }

    func refresh() {
        guard !isOpening else { return }
        availableApp = nil
        if let bookmark = defaults.data(forKey: Self.selectionKey) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark,
                                 options: [.withoutUI, .withoutMounting], relativeTo: nil,
                                 bookmarkDataIsStale: &stale), Self.isCompatibleApp(url) {
                availableApp = url
                if stale, let fresh = try? url.bookmarkData(options: .minimalBookmark,
                    includingResourceValuesForKeys: nil, relativeTo: nil) {
                    defaults.set(fresh, forKey: Self.selectionKey)
                }
            } else {
                status = "The selected game is missing or incompatible. Choose its current location."
                return
            }
        } else {
            availableApp = candidates.first(where: Self.isCompatibleApp)
        }
        status = availableApp == nil ? "Choose the QiMon First Signal app on this Mac."
            : "Ready to play locally. Your adventure has its own save."
    }

    func chooseApp() {
        guard !isOpening else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose QiMon First Signal"
        panel.prompt = "Use this game"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = selectApp(url)
    }

    @discardableResult
    func selectApp(_ url: URL) -> Bool {
        guard !isOpening else { return false }
        guard Self.isCompatibleApp(url) else {
            status = "Choose a macOS QiMon First Signal game app. The current selection was kept."
            return false
        }
        do {
            let bookmark = try url.bookmarkData(options: .minimalBookmark,
                includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: Self.selectionKey)
            availableApp = url
            status = "Game selected. Play when you are ready."
            return true
        } catch {
            status = "The game location could not be remembered: \(error.localizedDescription)"
            return false
        }
    }

    func useIncludedApp() {
        guard !isOpening else { return }
        defaults.removeObject(forKey: Self.selectionKey)
        refresh()
    }

    var hasIncludedApp: Bool { candidates.contains(where: Self.isCompatibleApp) }
    var hasExplicitSelection: Bool { defaults.object(forKey: Self.selectionKey) != nil }

    func play() async {
        guard !isOpening else { return }
        refresh()
        guard let app = availableApp else { return }
        isOpening = true
        status = "Opening QiMon…"
        defer { isOpening = false }
        do { status = try await launch(app) }
        catch { status = "QiMon could not open: \(error.localizedDescription)" }
    }

    private static func openApplication(_ app: URL) async throws -> String {
        // The existing game owns its session. Never start a second process that
        // could compete for the same campaign save, even from another app copy.
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { !$0.isTerminated }) {
            running.unhide()
            running.activate(options: [.activateAllWindows])
            return "Returned to your open QiMon game."
        }
        guard isCompatibleApp(app) else { throw LaunchError.missingApp }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        return "QiMon is open in its own window. Return here whenever you like."
    }

    private enum LaunchError: LocalizedError {
        case missingApp
        var errorDescription: String? { "The selected game moved or changed. Choose the app again." }
    }
}

@MainActor
struct QiMonLocalGameCard: View {
    @StateObject private var game: QiMonLocalGame
    @StateObject private var embedded = QiMonEmbeddedGame.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsEarlierAdventure = false

    init(game: QiMonLocalGame = QiMonLocalGame()) {
        _game = StateObject(wrappedValue: game)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("QiMon: First Signal", systemImage: "gamecontroller.fill")
                .font(.system(size: 18, weight: .medium))
            Text("Explore Relay Nine with your QiMon. The Drifter is your mentor in an original world, playable here inside ARCHi.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Button { Task { await embedded.play() } } label: {
                    Label(embedded.isOpening ? "Opening…" : "Play First Signal inside ARCHi", systemImage: "play.fill")
                }
                .buttonStyle(WorkspaceActionStyle(prominent: true))
                .disabled(embedded.isOpening || embedded.directory == nil)
                .accessibilityIdentifier("qimon.embedded.play")
                Button("Choose chapter build…") { embedded.chooseFolder() }.disabled(embedded.isOpening)
                Button("Check build") { embedded.refreshLocation() }.disabled(embedded.isOpening)
            }.buttonStyle(.borderless).font(.system(size: 11))
            Text(embedded.status).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("qimon.embedded.status")
            Divider()
            DisclosureGroup("Earlier adventure", isExpanded: $showsEarlierAdventure) {
                earlierAdventure
            }
            .font(.system(size: 11, weight: .medium))
            .accessibilityIdentifier("qimon.earlier-adventure")
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .modifier(WorkspaceSurface())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("qimon.local.card")
        .onAppear { game.refresh(); embedded.refreshLocation() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { game.refresh(); embedded.refreshLocation() } }
    }

    private var earlierAdventure: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Open the preserved Unity adventure with its own save. First Signal keeps a separate journey; opening either game does not transfer progress.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Button { Task { await game.play() } } label: {
                    Label(game.isOpening ? "Opening…" : "Open earlier adventure", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(WorkspaceActionStyle())
                .disabled(game.availableApp == nil || game.isOpening)
                .accessibilityIdentifier("qimon.local.play")
                Button("Choose game…") { game.chooseApp() }
                    .disabled(game.isOpening).accessibilityIdentifier("qimon.local.choose")
                if game.hasExplicitSelection && game.hasIncludedApp {
                    Button("Use included game") { game.useIncludedApp() }
                        .disabled(game.isOpening).accessibilityIdentifier("qimon.local.included")
                } else {
                    Button("Check again") { game.refresh() }
                        .disabled(game.isOpening).accessibilityIdentifier("qimon.local.refresh")
                }
            }.buttonStyle(.borderless).font(.system(size: 11))
            Text(game.status).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("qimon.local.status")
                .help(game.availableApp?.path ?? "Choose a local game app.")
        }
        .padding(.top, 8)
    }
}
