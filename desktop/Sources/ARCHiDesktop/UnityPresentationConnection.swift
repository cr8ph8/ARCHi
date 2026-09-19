import AppKit
import Combine
import CryptoKit
import Darwin
import SwiftUI
import UniformTypeIdentifiers

enum UnityPresentationDestination: String, Codable {
    case companion, arena
}

/// A read-only projection. No lesson, document, prompt, reply or evolution receipt
/// crosses this boundary. Unity can acknowledge rendering, never commit growth.
struct UnityPresentationSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let sessionID: String
    let revision: Int
    let originDigest: String
    let displayName: String
    let body: String
    let appearance: String
    let cursor: String
    let seedAssetSHA256: String
    let bodyAssetSHA256: String
    let activity: String
    let lightMode: String
    let quiet: Bool
    let reduceMotion: Bool
    let visible: Bool
    let equippedFocusStaff: Bool
    /// Optional recipe fields extend protocol 1 without exporting creator text,
    /// action permissions, private context, or an executable item package.
    let staffPalette: String?
    let staffCrown: String?
    let active: Bool
    let updatedAtUnix: Double
    /// Optional route requests preserve the original companion-only wire shape.
    /// Local practice deliberately carries no companion identity or art claim.
    var sessionKind: String? = nil
    var destination: String? = nil
    var destinationRevision: Int? = nil
    var seedAppearance: String? = nil
    var seedColor: String? = nil

    func hasSamePresentation(as other: Self) -> Bool {
        sessionID == other.sessionID && originDigest == other.originDigest && body == other.body
            && appearance == other.appearance && cursor == other.cursor && displayName == other.displayName
            && seedAssetSHA256 == other.seedAssetSHA256 && bodyAssetSHA256 == other.bodyAssetSHA256
            && activity == other.activity && lightMode == other.lightMode && quiet == other.quiet
            && reduceMotion == other.reduceMotion && visible == other.visible
            && equippedFocusStaff == other.equippedFocusStaff && staffPalette == other.staffPalette
            && staffCrown == other.staffCrown && active == other.active
            && sessionKind == other.sessionKind && destination == other.destination
            && destinationRevision == other.destinationRevision && seedAppearance == other.seedAppearance && seedColor == other.seedColor
    }

    @MainActor static func capture(store: CompanionStore, sessionID: UUID, revision: Int,
                                  active: Bool, now: Date, systemReduceMotion: Bool,
                                  destination: UnityPresentationDestination? = nil,
                                  destinationRevision: Int? = nil, localPractice: Bool = false) -> Self? {
        guard (destination == nil && destinationRevision == nil)
            || (destination != nil && (destinationRevision ?? 0) > 0) else { return nil }
        if localPractice {
            guard store.activeQiMon == nil, destination == .arena, let destinationRevision, destinationRevision > 0,
                  revision > 0, now.timeIntervalSince1970.isFinite, now.timeIntervalSince1970 >= 0 else { return nil }
            return Self(schemaVersion: 1, sessionID: sessionID.uuidString, revision: revision,
                originDigest: "", displayName: "Local roster practice", body: "none", appearance: "none", cursor: "none",
                seedAssetSHA256: "", bodyAssetSHA256: "", activity: "idle", lightMode: "rest",
                quiet: store.preferences.quiet, reduceMotion: store.preferences.reduceMotion || systemReduceMotion,
                visible: store.isVisible && !store.isShuttingDown, equippedFocusStaff: false,
                staffPalette: nil, staffCrown: nil, active: active && store.isVisible && !store.isShuttingDown,
                updatedAtUnix: now.timeIntervalSince1970, sessionKind: "localPractice",
                destination: UnityPresentationDestination.arena.rawValue, destinationRevision: destinationRevision)
        }
        guard let kin = store.activeQiMon, kin.isValid, revision > 0,
              now.timeIntervalSince1970.isFinite, now.timeIntervalSince1970 >= 0 else { return nil }
        let body = store.presentationForm == .kin ? "firstLight" : "seed"
        let proto = CompanionVisualAsset.usesProto(store.preferences.visualTreatment)
        let seedDigest: String
        switch store.preferences.seedAppearance {
        case .hamptonLiminal: seedDigest = store.preferences.seedColor == .garnet ? CompanionVisualAsset.hamptonGarnetDigest : CompanionVisualAsset.hamptonSeedDigest
        case .archiLight: seedDigest = CompanionVisualAsset.lightSeedDigest
        case .kinParticles: seedDigest = CompanionVisualAsset.kinSeedDigest
        }
        return Self(schemaVersion: 1, sessionID: sessionID.uuidString, revision: revision,
                    originDigest: kin.originDigest, displayName: kin.name, body: body, appearance: proto ? "proto" : "kin", cursor: "seed",
                    seedAssetSHA256: seedDigest,
                    bodyAssetSHA256: body == "seed" ? seedDigest : (proto ? CompanionVisualAsset.protoDigest : CompanionVisualAsset.kinFirstLightDigest),
                    activity: store.assistantActivity.rawValue, lightMode: store.kinLightExpression.mode.rawValue,
                    quiet: store.preferences.quiet,
                    reduceMotion: store.preferences.reduceMotion || systemReduceMotion,
                    visible: store.isVisible && !store.isShuttingDown,
                    equippedFocusStaff: store.preferences.equipment.isValid && store.preferences.equipment.hand == .focusStaff,
                    staffPalette: store.preferences.equipment.isValid ? store.preferences.equipment.design?.palette.rawValue : nil,
                    staffCrown: store.preferences.equipment.isValid ? store.preferences.equipment.design?.crown.rawValue : nil,
                    active: active && store.isVisible && !store.isShuttingDown, updatedAtUnix: now.timeIntervalSince1970,
                    sessionKind: destination == nil ? nil : "companion", destination: destination?.rawValue,
                    destinationRevision: destinationRevision,
                    seedAppearance: store.preferences.seedAppearance == .kinParticles ? nil : store.preferences.seedAppearance.rawValue,
                    seedColor: store.preferences.seedColor == .original ? nil : store.preferences.seedColor.rawValue)
    }
}

struct UnityPresentationAcknowledgment: Codable {
    let schemaVersion: Int
    let sessionID: String
    let originDigest: String
    let revision: Int
    let updatedAtUnix: Double
    let active: Bool
    let body: String
    let appearance: String?
    let staffPalette: String?
    let staffCrown: String?
    let renderer: String
    var sessionKind: String? = nil
    var destination: String? = nil
    var destinationRevision: Int? = nil
    var currentArea: String? = nil
    var seedAppearance: String? = nil
    var seedColor: String? = nil
    var seedAssetSHA256: String? = nil
    var bodyAssetSHA256: String? = nil

    func matches(_ snapshot: UnityPresentationSnapshot, now: Date) -> Bool {
        schemaVersion == 1 && sessionID == snapshot.sessionID && originDigest == snapshot.originDigest
            && revision == snapshot.revision && body == snapshot.body && active == snapshot.active
            && (appearance ?? "kin") == snapshot.appearance
            && Self.seedStyle(seedAppearance) == Self.seedStyle(snapshot.seedAppearance)
            && (seedColor.flatMap { $0.isEmpty ? nil : $0 } ?? "original") == (snapshot.seedColor ?? "original")
            && ((snapshot.seedAppearance != "hamptonLiminal" && snapshot.seedColor == nil)
                || (seedAssetSHA256 == snapshot.seedAssetSHA256 && bodyAssetSHA256 == snapshot.bodyAssetSHA256))
            && Self.recipeField(staffPalette, matches: snapshot.staffPalette)
            && Self.recipeField(staffCrown, matches: snapshot.staffCrown)
            && (sessionKind ?? "companion") == (snapshot.sessionKind ?? "companion")
            && (destination ?? "companion") == (snapshot.destination ?? "companion")
            && (destinationRevision ?? 0) == (snapshot.destinationRevision ?? 0)
            && ((snapshot.sessionKind == nil && snapshot.destination == nil && snapshot.destinationRevision == nil) || currentArea != nil)
            && (currentArea == nil || UnityPresentationDestination(rawValue: currentArea!) != nil)
            && renderer == "unity-companion" && updatedAtUnix.isFinite
            && now.timeIntervalSince1970 - updatedAtUnix >= -5
            && now.timeIntervalSince1970 - updatedAtUnix <= 5
    }

    private static func recipeField(_ actual: String?, matches expected: String?) -> Bool {
        if let expected { return actual == expected }
        return actual == nil || actual == ""
    }

    private static func seedStyle(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "kinParticles" }
        return value
    }
}

/// Owns only an explicitly opened presentation process and an ephemeral private
/// projection file. Native CompanionStore/EvolutionStore retain all authority.
@MainActor final class UnityPresentationConnection: ObservableObject {
    typealias LaunchApplication = @MainActor (URL, NSWorkspace.OpenConfiguration) async throws -> NSRunningApplication
    static let maximumBytes = 16_384
    @Published private(set) var isSharing = false
    @Published private(set) var status = "Choose Play Arena or Open room when you are ready to begin."
    @Published private(set) var hasRenderAcknowledgment = false
    @Published private(set) var selectedPlayer: URL?
    @Published private(set) var destination: UnityPresentationDestination = .companion
    @Published private(set) var isLocalPractice = false
    @Published private(set) var isOpening = false
    @Published private(set) var lastLaunchFailure: String?
    private(set) var snapshotURL: URL?
    private(set) var lastSnapshot: UnityPresentationSnapshot?
    private var previousSnapshot: UnityPresentationSnapshot?
    private var sessionID = UUID()
    private var revision = 0
    private var originDigest: String?
    private var task: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()
    private var player: NSRunningApplication?
    private var suspended = false
    private var requestedDestination: UnityPresentationDestination?
    private var destinationRevision: Int?
    private let launchApplication: LaunchApplication
    private let bundledPlayerURL: URL?
    private let fallbackPlayers: [URL]

    init(launchApplication: LaunchApplication? = nil, bundledResourceURL: URL? = Bundle.main.resourceURL,
         fallbackPlayers: [URL]? = nil) {
        self.launchApplication = launchApplication ?? { url, configuration in
            try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
        bundledPlayerURL = bundledResourceURL?.appendingPathComponent("UnityCompanion.app")
        self.fallbackPlayers = fallbackPlayers ?? [
            URL(fileURLWithPath: "/private/tmp/archi-unity-desktop-\(getuid())/ARCHi Unity Companion.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/ARCHi Unity Companion.app"),
            URL(fileURLWithPath: "/Applications/ARCHi Unity Companion.app")]
    }

    deinit { task?.cancel() }

    static func isCompatiblePlayer(_ url: URL) -> Bool {
        guard url.isFileURL, url.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: url), bundle.bundleIdentifier == "local.archi.unityport",
              (bundle.object(forInfoDictionaryKey: "ARCHiNativePresentationProtocol") as? NSNumber)?.intValue == 1,
              let executable = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else { return false }
        return true
    }

    static func supportsStaffRecipes(_ url: URL) -> Bool {
        isCompatiblePlayer(url)
            && (Bundle(url: url)?.object(forInfoDictionaryKey: "ARCHiNativeStaffRecipeVersion") as? NSNumber)?.intValue == 1
    }

    static func supportsArena(_ url: URL) -> Bool {
        isCompatiblePlayer(url)
            && (Bundle(url: url)?.object(forInfoDictionaryKey: "ARCHiNativeArenaProtocol") as? NSNumber)?.intValue == 1
    }
    static func supportsSeedAppearances(_ url: URL) -> Bool {
        isCompatiblePlayer(url)
            && (Bundle(url: url)?.object(forInfoDictionaryKey: "ARCHiSeedAppearanceVersion") as? NSNumber)?.intValue == 1
    }

    static func supportsPersonalSeeds(_ url: URL) -> Bool {
        supportsSeedAppearances(url)
            && (Bundle(url: url)?.object(forInfoDictionaryKey: "ARCHiPersonalSeedVersion") as? NSNumber)?.intValue == 1
    }

    func choosePlayer() {
        let panel = NSOpenPanel()
        panel.title = "Connect an ARCHi Arena app"
        panel.prompt = "Use this app"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = selectPlayer(url)
    }

    @discardableResult func selectPlayer(_ url: URL) -> Bool {
        guard !isSharing, Self.isCompatiblePlayer(url) else {
            status = "Choose an ARCHi Unity companion build with desktop presentation support."
            return false
        }
        selectedPlayer = url
        lastLaunchFailure = nil
        status = "Unity companion selected. Open it when ready."
        return true
    }

    /// Read-only availability for the workspace. Resolving a candidate never
    /// launches a player or starts publishing the native companion's state.
    var availablePlayer: URL? {
        let candidates = [selectedPlayer, bundledPlayerURL] + fallbackPlayers.map(Optional.some)
        return candidates.compactMap { $0 }.first(where: Self.isCompatiblePlayer)
    }

    var includedPlayer: URL? {
        bundledPlayerURL.flatMap { Self.isCompatiblePlayer($0) ? $0 : nil }
    }

    func refreshAvailability() {
        status = availablePlayer == nil ? "Arena is not included in this copy. Connect an Arena app in Advanced."
            : "Arena is available. Play when you are ready."
    }

    func openArena(store: CompanionStore) async { await open(store: store, destination: .arena) }

    func open(store: CompanionStore, destination: UnityPresentationDestination = .companion) async {
        guard !store.isShuttingDown else { return }
        if let reason = store.unityPresentationUnavailableReason(for: availablePlayer) {
            if isSharing { stop() }
            status = reason
            return
        }
        guard let app = availablePlayer else {
            status = "Choose the ARCHi Unity companion build to connect it."
            return
        }
        guard store.activeQiMon == nil || store.preferences.seedAppearance == .kinParticles || Self.supportsSeedAppearances(app) else {
            status = PresentationError.seedAppearanceUnavailable.localizedDescription
            return
        }
        guard destination != .arena || Self.supportsArena(app) else {
            status = "Choose an updated Unity build with Arena support."
            return
        }
        guard destination != .companion || store.activeQiMon?.isValid == true else {
            status = "Companion view needs a saved KIN. Open Arena for local roster practice."
            return
        }
        if isSharing {
            if destination == .arena || requestedDestination != nil {
                requestedDestination = destination
                destinationRevision = (destinationRevision ?? 0) + 1
                self.destination = destination
                refresh(store: store)
            }
            player?.activate(options: [])
            return
        }
        guard store.activeQiMon == nil || store.preferences.equipment.design == nil || Self.supportsStaffRecipes(app) else {
            status = "This Unity build needs an update to display your staff design. Choose a newer Unity companion app."
            return
        }
        selectedPlayer = app
        lastLaunchFailure = nil
        do { try beginPublishing(store: store, destination: destination) }
        catch {
            lastLaunchFailure = error.localizedDescription
            status = "Unity could not open: \(error.localizedDescription)"
            return
        }
        let owner = sessionID
        isOpening = true
        do {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.arguments = ["-archiNativePresentation", snapshotURL!.path,
                                       "-archiNativeSession", owner.uuidString]
            let launched = try await launchApplication(app, configuration)
            guard isSharing, sessionID == owner else { launched.terminate(); return }
            isOpening = false
            player = launched
            selectedPlayer = app
        } catch {
            // Stop or a new Open retires this launch's authority on both its
            // success and failure paths. A late failure cannot stop its successor.
            guard isSharing, sessionID == owner else { return }
            stop()
            lastLaunchFailure = error.localizedDescription
            status = "Unity could not open: \(error.localizedDescription)"
        }
    }

    /// Also exercised directly with a disposable profile; this does not launch UI.
    func beginPublishing(store: CompanionStore, directory: URL? = nil,
                        destination: UnityPresentationDestination = .companion) throws {
        if let selectedPlayer, store.unityPresentationUnavailableReason(for: selectedPlayer) != nil { throw PresentationError.nativeOnlySeed }
        if store.activeQiMon != nil, store.preferences.seedAppearance == .archiLight,
           let selectedPlayer, !Self.supportsSeedAppearances(selectedPlayer) {
            throw PresentationError.seedAppearanceUnavailable
        }
        guard !isSharing, !store.isShuttingDown,
              store.activeQiMon?.isValid == true || (store.activeQiMon == nil && destination == .arena) else {
            throw PresentationError.noCompanion
        }
        isLocalPractice = store.activeQiMon == nil
        sessionID = UUID(); revision = 0; originDigest = store.activeQiMon?.originDigest
        let routes = destination == .arena || selectedPlayer.map(Self.supportsArena) == true
        requestedDestination = routes ? destination : nil
        destinationRevision = routes ? 1 : nil
        self.destination = destination
        lastSnapshot = nil; previousSnapshot = nil; hasRenderAcknowledgment = false; suspended = false
        let root = directory ?? FileManager.default.temporaryDirectory
        let folder = root.appendingPathComponent("archi-unity-\(sessionID.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        snapshotURL = folder.appendingPathComponent("presentation.json")
        isSharing = true
        do { try publish(store: store) } catch { stop(); throw error }
        store.objectWillChange.receive(on: RunLoop.main).sink { [weak self, weak store] _ in
            guard let self, let store, self.isSharing else { return }
            self.refresh(store: store)
        }.store(in: &subscriptions)
        store.evolution.objectWillChange.receive(on: RunLoop.main).sink { [weak self, weak store] _ in
            guard let self, let store, self.isSharing else { return }
            self.refresh(store: store)
        }.store(in: &subscriptions)
        store.desktopInterest.objectWillChange.receive(on: RunLoop.main).sink { [weak self, weak store] _ in
            guard let self, let store, self.isSharing else { return }
            self.refresh(store: store)
        }.store(in: &subscriptions)
        task = Task { [weak self, weak store] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, let store, self.isSharing else { return }
                if self.player?.isTerminated == true {
                    self.stop(); self.status = "Unity companion closed. Desktop KIN is still here."; return
                }
                self.refresh(store: store)
            }
        }
    }

    func refresh(store: CompanionStore) {
        guard isSharing else { return }
        if let reason = store.unityPresentationUnavailableReason(for: availablePlayer) {
            stop(); status = reason
            return
        }
        if !isLocalPractice && store.preferences.seedAppearance != .kinParticles,
           let selectedPlayer, !Self.supportsSeedAppearances(selectedPlayer) {
            stop(); status = PresentationError.seedAppearanceUnavailable.localizedDescription
            return
        }
        if !isLocalPractice, player != nil, let selectedPlayer, store.preferences.equipment.design != nil,
           !Self.supportsStaffRecipes(selectedPlayer) {
            stop()
            status = "Unity stopped because this build cannot display your new staff design. Choose an updated companion app."
            return
        }
        do { try publish(store: store) }
        catch { stop(); status = "Presentation paused. \(error.localizedDescription)" }
    }

    func setSuspended(_ suspended: Bool, store: CompanionStore) {
        self.suspended = suspended
        refresh(store: store)
    }

    func publish(store: CompanionStore, now: Date = Date(), systemReduceMotion: Bool? = nil) throws {
        guard isSharing, let snapshotURL, store.activeQiMon?.originDigest == originDigest,
              let snapshot = UnityPresentationSnapshot.capture(store: store, sessionID: sessionID,
                    revision: revision + 1, active: !suspended, now: now,
                    systemReduceMotion: systemReduceMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                    destination: requestedDestination, destinationRevision: destinationRevision, localPractice: isLocalPractice)
        else { throw PresentationError.noCompanion }
        try Self.write(snapshot, to: snapshotURL)
        previousSnapshot = lastSnapshot
        lastSnapshot = snapshot; revision = snapshot.revision
        // Compare acknowledgments with the newly published presentation. An old
        // body's ACK must not label a new body as rendered, even for one tick.
        readAcknowledgment(now: now)
        if suspended { status = "Unity presentation paused." }
        else if hasRenderAcknowledgment {
            status = isLocalPractice ? "Unity Arena · local roster practice. Nothing is saved to a companion."
                : "Unity is following your desktop companion. Seed remains your cursor."
        } else { status = "Sharing presentation with Unity; waiting for its render acknowledgment." }
    }

    func readAcknowledgment(now: Date = Date()) {
        hasRenderAcknowledgment = false
        guard isSharing, let url = snapshotURL?.appendingPathExtension("ack"),
              let data = try? Self.readAcknowledgmentData(at: url),
              let acknowledgment = try? JSONDecoder().decode(UnityPresentationAcknowledgment.self, from: data) else { return }
        guard let latest = lastSnapshot else { return }
        hasRenderAcknowledgment = [latest, previousSnapshot].compactMap { $0 }.contains {
            $0.hasSamePresentation(as: latest) && acknowledgment.matches($0, now: now)
        }
        if hasRenderAcknowledgment, let currentArea = acknowledgment.currentArea,
           let area = UnityPresentationDestination(rawValue: currentArea) { destination = area }
    }

    private static func readAcknowledgmentData(at url: URL) throws -> Data {
        // Validate the opened entry, not a cached path check followed by an
        // unbounded read. Nonblocking open also rejects swapped special files
        // without letting the Unity acknowledgment stall the native main actor.
        let descriptor = url.path.withCString { Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) }
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard info.st_mode & S_IFMT == S_IFREG else { throw PresentationError.invalidAcknowledgment }
        guard info.st_size > 0, info.st_size <= maximumBytes else { throw PresentationError.oversized }
        let data = try file.read(upToCount: maximumBytes + 1) ?? Data()
        guard !data.isEmpty, data.count <= maximumBytes else { throw PresentationError.oversized }
        return data
    }

    func stop() {
        task?.cancel(); task = nil; subscriptions.removeAll()
        if isSharing, let lastSnapshot, let snapshotURL {
            let retired = UnityPresentationSnapshot(schemaVersion: 1, sessionID: lastSnapshot.sessionID,
                revision: lastSnapshot.revision + 1, originDigest: lastSnapshot.originDigest,
                displayName: lastSnapshot.displayName, body: lastSnapshot.body, appearance: lastSnapshot.appearance, cursor: lastSnapshot.cursor,
                seedAssetSHA256: lastSnapshot.seedAssetSHA256, bodyAssetSHA256: lastSnapshot.bodyAssetSHA256,
                activity: "stopped", lightMode: "rest", quiet: true, reduceMotion: true, visible: false,
                equippedFocusStaff: lastSnapshot.equippedFocusStaff,
                staffPalette: lastSnapshot.staffPalette, staffCrown: lastSnapshot.staffCrown, active: false,
                updatedAtUnix: Date().timeIntervalSince1970, sessionKind: lastSnapshot.sessionKind,
                destination: lastSnapshot.destination, destinationRevision: lastSnapshot.destinationRevision,
                seedAppearance: lastSnapshot.seedAppearance, seedColor: lastSnapshot.seedColor)
            try? Self.write(retired, to: snapshotURL)
        }
        isSharing = false; hasRenderAcknowledgment = false; isOpening = false
        player?.terminate(); player = nil
        status = "Unity presentation stopped. Desktop KIN and saved development are unchanged."
    }

    private static func write(_ snapshot: UnityPresentationSnapshot, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        guard data.count <= maximumBytes else { throw PresentationError.oversized }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    enum PresentationError: LocalizedError {
        case noCompanion, oversized, invalidAcknowledgment, seedAppearanceUnavailable, nativeOnlySeed
        var errorDescription: String? {
            switch self {
            case .noCompanion: "The current companion identity is unavailable. Open the native profile first."
            case .nativeOnlySeed: "Update the included Arena to support your selected Seed and color."
            case .oversized: "The presentation snapshot exceeds its size limit."
            case .invalidAcknowledgment: "The presentation acknowledgment is not a regular file."
            case .seedAppearanceUnavailable: "This Unity build supports the KIN particle Seed. Choose an updated build to use ARCHi’s Ball of Light."
            }
        }
    }
}
