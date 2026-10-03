import AppKit
import ApplicationServices
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class ArenaEntryTests: XCTestCase {
    @MainActor func testNativeHomePlayButtonOpensActualArenaWithCurrentLookAndOutfit() async throws {
        guard let directory = ProcessInfo.processInfo.environment["ARCHI_ARENA_ENTRY_RENDER_DIR"],
              let player = ProcessInfo.processInfo.environment["ARCHI_UNITY_PLAYER_TEST_APP"] else {
            throw XCTSkip("Set Arena entry output and qualified player for the native Home button check.")
        }
        let output = URL(fileURLWithPath: directory).appendingPathComponent("home-direct-play")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let fixture = try ArenaEntryFixture()
        defer { fixture.clean() }
        let store = fixture.store, owner = store.unityPresentation
        let before = try Data(contentsOf: fixture.profile)
        store.preferences.quiet = true; store.preferences.reduceMotion = true
        store.preferences.seedAppearance = .archiLight
        store.preferences.equipment = CompanionEquipment(hand: .focusStaff,
            design: CompanionItemPackage(title: "Synthetic rose staff", creator: "Test", summary: "Local test", palette: .rose, crown: .star))
        XCTAssertTrue(owner.selectPlayer(URL(fileURLWithPath: player)))
        let playerPath = URL(fileURLWithPath: player).standardizedFileURL.resolvingSymlinksInPath().path
        let previousPlayerPIDs = Set(NSWorkspace.shared.runningApplications.filter {
            $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path == playerPath
        }.map(\.processIdentifier))
        let play = HostedPlayHost(profile: .acceptance, assetDirectory: nil)
        let app = NSApplication.shared, priorPolicy = app.activationPolicy()
        let priorApp = NSWorkspace.shared.frontmostApplication
        _ = app.setActivationPolicy(.accessory); app.finishLaunching()
        let window = WorkspaceWindow(contentRect: NSRect(x: 70, y: 70, width: 1100, height: 780),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.title = "ARCHi · disposable Arena entry"
        let hosting = WorkspaceView.makeHostingView(store: store, playHost: play)
        window.contentView = hosting; window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        defer {
            owner.stop(); window.contentView = nil; window.close()
            _ = app.setActivationPolicy(priorPolicy)
            if priorApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier { priorApp?.activate(options: []) }
        }
        await initializeAccessibility()
        let action = try await accessible("home.play-arena", in: window)
        XCTAssertFalse(owner.isSharing, "Home remains passive before the real native button press")
        try capture(hosting, to: output.appendingPathComponent("01-home-play.png"))
        try press(action)
        for _ in 0..<150 {
            owner.readAcknowledgment()
            if owner.hasRenderAcknowledgment && owner.destination == .arena { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(store.section, .unity)
        XCTAssertTrue(owner.hasRenderAcknowledgment, owner.status)
        XCTAssertEqual(owner.destination, .arena)
        XCTAssertEqual(owner.lastSnapshot?.originDigest, store.activeQiMon?.originDigest)
        XCTAssertEqual(owner.lastSnapshot?.seedAppearance, "archiLight")
        XCTAssertEqual(owner.lastSnapshot?.staffPalette, "rose")
        XCTAssertEqual(owner.lastSnapshot?.staffCrown, "star")
        XCTAssertEqual(try Data(contentsOf: fixture.profile), before)
        let launchedPlayers = NSWorkspace.shared.runningApplications.filter {
            $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path == playerPath
                && !previousPlayerPIDs.contains($0.processIdentifier)
        }
        XCTAssertEqual(launchedPlayers.count, 1, "The explicit action owns one fresh player instance")
        let launchedPlayer = try XCTUnwrap(launchedPlayers.first)
        _ = try await accessible("unity-area.open-arena", in: window)
        try capture(hosting, to: output.appendingPathComponent("02-arena-connected.png"))
        var receipt: [String: Any] = ["schema": "archi-home-arena-entry/v1", "nativeButton": "home.play-arena",
            "nativePressPerformed": true, "area": owner.destination.rawValue,
            "renderAcknowledged": owner.hasRenderAcknowledgment, "seedAppearance": owner.lastSnapshot?.seedAppearance ?? "",
            "staffPalette": owner.lastSnapshot?.staffPalette ?? "", "staffCrown": owner.lastSnapshot?.staffCrown ?? "",
            "savedProfileUnchanged": try Data(contentsOf: fixture.profile) == before, "player": player,
            "ownedPlayerPID": launchedPlayer.processIdentifier]
        owner.stop(); await fixture.store.shutdownAssistant()
        for _ in 0..<100 {
            if launchedPlayer.isTerminated { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(launchedPlayer.isTerminated, "The fixture closes only its own player")
        receipt["ownedPlayerTerminated"] = launchedPlayer.isTerminated
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("receipt.json"))
    }

    @MainActor func testNativeUnavailableArenaRevealsSetupWithoutLaunching() async throws {
        guard let directory = ProcessInfo.processInfo.environment["ARCHI_ARENA_ENTRY_RENDER_DIR"] else {
            throw XCTSkip("Set Arena entry output for the native unavailable recovery check.")
        }
        let output = URL(fileURLWithPath: directory).appendingPathComponent("unavailable")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let fixture = try ArenaEntryFixture(hasCompanion: false)
        defer { fixture.clean() }
        let owner = UnityPresentationConnection(bundledResourceURL: nil, fallbackPlayers: [])
        let app = NSApplication.shared, priorPolicy = app.activationPolicy()
        let priorApp = NSWorkspace.shared.frontmostApplication
        _ = app.setActivationPolicy(.accessory); app.finishLaunching()
        let window = NSPanel(contentRect: NSRect(x: 80, y: 80, width: 630, height: 780),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.title = "ARCHi · disposable Arena setup"
        let hosting = NSHostingView(rootView: UnityWorkspace(store: fixture.store, connection: owner)
            .frame(width: 630, height: 780).background(WorkspaceTheme.background).preferredColorScheme(.light))
        window.contentView = hosting; window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
        defer {
            window.contentView = nil; window.close(); _ = app.setActivationPolicy(priorPolicy)
            if priorApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier { priorApp?.activate(options: []) }
        }
        await initializeAccessibility()
        let action = try await accessible("unity-area.open-arena", in: window)
        try capture(hosting, to: output.appendingPathComponent("01-setup-offer.png"))
        try press(action)
        try await Task.sleep(for: .milliseconds(250))
        try capture(hosting, to: output.appendingPathComponent("02-after-setup-press.png"))
        let visibleIDs = identifiedNodes(window).keys.sorted()
        try JSONEncoder().encode(visibleIDs).write(to: output.appendingPathComponent("setup-accessibility-identifiers.json"))
        _ = try await accessible("unity-area.choose-player", in: window)
        try capture(hosting, to: output.appendingPathComponent("02-advanced-recovery.png"))
        XCTAssertFalse(owner.isSharing)
        XCTAssertNil(owner.snapshotURL)
        XCTAssertNil(fixture.store.activeQiMon)
        await fixture.store.shutdownAssistant()
    }

    @MainActor func testIncludedArenaIsDiscoveredBeforeFallbackWithoutLaunchingOrSaving() async throws {
        let fixture = try ArenaEntryFixture()
        defer { fixture.clean() }
        let included = try fixture.player(name: "UnityCompanion", directory: "Resources")
        let fallback = try fixture.player(name: "Fallback")
        let owner = UnityPresentationConnection(bundledResourceURL: included.deletingLastPathComponent(), fallbackPlayers: [fallback])
        let before = try Data(contentsOf: fixture.profile)
        XCTAssertEqual(owner.includedPlayer?.path, included.path)
        XCTAssertEqual(owner.availablePlayer?.path, included.path)
        XCTAssertEqual(ArenaEntryState(store: fixture.store, connection: owner).availability, .ready)
        XCTAssertFalse(owner.isSharing)
        XCTAssertNil(owner.snapshotURL)
        XCTAssertEqual(try Data(contentsOf: fixture.profile), before)
        await fixture.store.shutdownAssistant()
    }

    @MainActor func testUnavailableEntryOpensArenaPageWithRecoveryAndDoesNotLaunch() async throws {
        let fixture = try ArenaEntryFixture()
        defer { fixture.clean() }
        let owner = UnityPresentationConnection(launchApplication: { _, _ in
            XCTFail("An unavailable Arena must not launch")
            throw CocoaError(.executableLoad)
        }, bundledResourceURL: nil, fallbackPlayers: [])
        let before = try Data(contentsOf: fixture.profile)
        var opened: [WorkspaceSection] = []
        fixture.store.onOpenWorkspace = { opened.append($0) }
        let state = ArenaEntryState(store: fixture.store, connection: owner)
        XCTAssertEqual(state.availability, .unavailable)
        XCTAssertEqual(state.actionTitle, "Set up Arena")
        XCTAssertFalse(state.canEnter)
        await ArenaEntryAction.open(store: fixture.store, connection: owner)
        XCTAssertEqual(opened, [.unity])
        XCTAssertEqual(fixture.store.section, .unity)
        XCTAssertFalse(owner.isSharing)
        XCTAssertNil(owner.snapshotURL)
        XCTAssertEqual(try Data(contentsOf: fixture.profile), before)
        await fixture.store.shutdownAssistant()
    }

    @MainActor func testLookOutfitAndArenaCapabilitiesUseOneEntryGate() async throws {
        let fixture = try ArenaEntryFixture()
        defer { fixture.clean() }
        let oldArena = try fixture.player(name: "NoArena", arena: nil)
        let oldLook = try fixture.player(name: "OldLook", seed: nil)
        let oldOutfit = try fixture.player(name: "OldOutfit", recipe: nil)
        let current = try fixture.player(name: "Current")
        let owner = UnityPresentationConnection(bundledResourceURL: nil, fallbackPlayers: [])
        for (player, look, outfit) in [(oldArena, CompanionSeedAppearance.kinParticles, false),
                                      (oldLook, .archiLight, false), (oldOutfit, .kinParticles, true)] {
            XCTAssertTrue(owner.selectPlayer(player))
            fixture.store.preferences.seedAppearance = look
            fixture.store.preferences.equipment = outfit ? CompanionEquipment(hand: .focusStaff, design: .creatorDefault) : CompanionEquipment()
            let state = ArenaEntryState(store: fixture.store, connection: owner)
            XCTAssertEqual(state.availability, .updateRequired)
            XCTAssertFalse(state.canEnter)
            await ArenaEntryAction.open(store: fixture.store, connection: owner)
            XCTAssertFalse(owner.isSharing)
        }
        XCTAssertTrue(owner.selectPlayer(current))
        XCTAssertTrue(ArenaEntryState(store: fixture.store, connection: owner).canEnter)
        await fixture.store.shutdownAssistant()
    }

    @MainActor func testRepeatedExplicitEntryReusesPendingSessionAndKeepsProfile() async throws {
        let fixture = try ArenaEntryFixture()
        defer { fixture.clean() }
        let deferred = ArenaEntryDeferredLaunch()
        let owner = UnityPresentationConnection(launchApplication: { _, _ in try await deferred.launch() },
            bundledResourceURL: nil, fallbackPlayers: [])
        defer { owner.stop(); deferred.fail() }
        XCTAssertTrue(owner.selectPlayer(try fixture.player(name: "Pending")))
        let before = try Data(contentsOf: fixture.profile)
        let first = Task { await ArenaEntryAction.open(store: fixture.store, connection: owner) }
        for _ in 0..<500 { if deferred.pending { break }; await Task.yield() }
        XCTAssertTrue(owner.isOpening)
        let session = try XCTUnwrap(owner.lastSnapshot?.sessionID)
        await ArenaEntryAction.open(store: fixture.store, connection: owner)
        XCTAssertEqual(deferred.calls, 1)
        XCTAssertEqual(owner.lastSnapshot?.sessionID, session)
        XCTAssertEqual(owner.destination, .arena)
        owner.stop(); deferred.fail(); await first.value
        XCTAssertFalse(owner.isOpening)
        XCTAssertFalse(owner.isSharing)
        XCTAssertEqual(try Data(contentsOf: fixture.profile), before)
        await fixture.store.shutdownAssistant()
    }

    @MainActor func testHiddenEntryExplicitlyShowsCompanionAndPreservesSavedProfile() async throws {
        let fixture = try ArenaEntryFixture()
        defer { fixture.clean() }
        var launches = 0, shows = 0
        let owner = UnityPresentationConnection(launchApplication: { _, _ in
            launches += 1; throw CocoaError(.executableLoad)
        }, bundledResourceURL: nil, fallbackPlayers: [])
        XCTAssertTrue(owner.selectPlayer(try fixture.player(name: "Hidden")))
        fixture.store.isVisible = false
        fixture.store.onShowCompanion = { shows += 1 }
        let before = try Data(contentsOf: fixture.profile)
        let state = ArenaEntryState(store: fixture.store, connection: owner)
        XCTAssertEqual(state.availability, .hidden)
        XCTAssertEqual(state.actionTitle, "Show & play")
        await ArenaEntryAction.open(store: fixture.store, connection: owner)
        XCTAssertTrue(fixture.store.isVisible)
        XCTAssertEqual(shows, 1)
        XCTAssertEqual(launches, 1)
        XCTAssertEqual(try Data(contentsOf: fixture.profile), before)
        await fixture.store.shutdownAssistant()
    }

    @MainActor func testFirstRunPracticeIgnoresUnusedLookAndOutfitCapabilities() async throws {
        let fixture = try ArenaEntryFixture(hasCompanion: false)
        defer { fixture.clean() }
        var launches = 0
        let owner = UnityPresentationConnection(launchApplication: { _, _ in
            launches += 1; throw CocoaError(.executableLoad)
        }, bundledResourceURL: nil, fallbackPlayers: [])
        XCTAssertTrue(owner.selectPlayer(try fixture.player(name: "Roster", seed: nil, recipe: nil)))
        fixture.store.preferences.seedAppearance = .archiLight
        fixture.store.preferences.equipment = CompanionEquipment(hand: .focusStaff, design: .creatorDefault)
        let before = try Data(contentsOf: fixture.profile)
        XCTAssertTrue(ArenaEntryState(store: fixture.store, connection: owner).canEnter)
        await ArenaEntryAction.open(store: fixture.store, connection: owner)
        XCTAssertEqual(launches, 1)
        XCTAssertNil(fixture.store.activeQiMon)
        XCTAssertTrue(owner.isLocalPractice)
        XCTAssertEqual(owner.lastSnapshot?.originDigest, "")
        XCTAssertNil(owner.lastSnapshot?.staffPalette)
        XCTAssertEqual(try Data(contentsOf: fixture.profile), before)
        await fixture.store.shutdownAssistant()
    }

    @MainActor func testFailedLaunchProvidesRetryWithoutClaimingAnOpenArena() async throws {
        let fixture = try ArenaEntryFixture()
        defer { fixture.clean() }
        var launches = 0
        let owner = UnityPresentationConnection(launchApplication: { _, _ in
            launches += 1; throw CocoaError(.executableLoad)
        }, bundledResourceURL: nil, fallbackPlayers: [])
        XCTAssertTrue(owner.selectPlayer(try fixture.player(name: "Failure")))
        await ArenaEntryAction.open(store: fixture.store, connection: owner)
        let state = ArenaEntryState(store: fixture.store, connection: owner)
        XCTAssertEqual(state.availability, .retry)
        XCTAssertEqual(state.actionTitle, "Try again")
        XCTAssertFalse(owner.isSharing)
        XCTAssertFalse(owner.isOpening)
        XCTAssertFalse(UnityWorkspaceState(connection: owner).isFollowing)
        await ArenaEntryAction.open(store: fixture.store, connection: owner)
        XCTAssertEqual(launches, 2)
        await fixture.store.shutdownAssistant()
    }

    @MainActor private func initializeAccessibility() async {
        let pid = ProcessInfo.processInfo.processIdentifier
        _ = await Task.detached {
            let app = AXUIElementCreateApplication(pid)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows).rawValue
        }.value
    }

    @MainActor private func accessible(_ identifier: String, in window: NSWindow) async throws -> NSObject {
        for _ in 0..<160 {
            if let node = identifiedNodes(window)[identifier] { return node }
            try await Task.sleep(for: .milliseconds(50))
        }
        return try XCTUnwrap(identifiedNodes(window)[identifier], "Native action missing: \(identifier)")
    }

    @MainActor private func identifiedNodes(_ root: NSObject) -> [String: NSObject] {
        var result: [String: NSObject] = [:], seen = Set<ObjectIdentifier>()
        func visit(_ object: NSObject, depth: Int) {
            guard depth < 40, seen.count < 4000, seen.insert(ObjectIdentifier(object)).inserted else { return }
            func value(_ name: String) -> Any? {
                let selector = NSSelectorFromString(name)
                return object.responds(to: selector) ? object.perform(selector)?.takeUnretainedValue() : nil
            }
            let attributes = object.accessibilityAttributeNames()
            let id = value("accessibilityIdentifier") as? String
                ?? (attributes.contains(.identifier) ? object.accessibilityAttributeValue(.identifier) as? String : nil)
            if let id, result[id] == nil { result[id] = object }
            let children = (value("accessibilityChildren") as? [Any] ?? [])
                + (attributes.contains(.children) ? object.accessibilityAttributeValue(.children) as? [Any] ?? [] : [])
            for child in children { if let child = child as? NSObject { visit(child, depth: depth + 1) } }
            if let window = object as? NSWindow, let view = window.contentView {
                visit(view, depth: depth + 1)
                if let frame = view.superview { visit(frame, depth: depth + 1) }
            }
            if let view = object as? NSView { for child in view.subviews { visit(child, depth: depth + 1) } }
        }
        visit(root, depth: 0); return result
    }

    @MainActor private func press(_ object: NSObject) throws {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard object.responds(to: selector) else { XCTFail("A native Press action is required"); throw CocoaError(.featureUnsupported) }
        if let control = object as? NSAccessibilityProtocol { XCTAssertTrue(control.accessibilityPerformPress()) }
        else {
            let action = unsafeBitCast(object.method(for: selector), to: (@convention(c) (AnyObject, Selector) -> Bool).self)
            XCTAssertTrue(action(object, selector))
        }
    }

    @MainActor private func capture(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }
}

@MainActor private struct ArenaEntryFixture {
    let directory: URL, profile: URL
    let store: CompanionStore
    init(hasCompanion: Bool = true) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-consumer-arena-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        profile = directory.appendingPathComponent("profile.json")
        let kin = hasCompanion ? LocalQiMon(character: .kin, originDigest: String(repeating: "b", count: 64), welcomedAt: Date()) : nil
        try NativePreferenceDocument(preferences: CompanionPreferences(), qiMon: kin).encoded().write(to: profile)
        store = CompanionStore(preferenceURL: profile, assistant: ArenaEntryNoProvider(), allowsPlay: false)
    }
    func player(name: String, directory folder: String = "Apps", arena: Int? = 1, seed: Int? = 1, recipe: Int? = 1) throws -> URL {
        let app = directory.appendingPathComponent(folder).appendingPathComponent(name + ".app")
        let contents = app.appendingPathComponent("Contents"), bin = contents.appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": "local.archi.unityport", "CFBundleExecutable": name,
            "CFBundlePackageType": "APPL", "ARCHiNativePresentationProtocol": 1]
        info["ARCHiNativeArenaProtocol"] = arena; info["ARCHiSeedAppearanceVersion"] = seed
        info["ARCHiNativeStaffRecipeVersion"] = recipe
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let exe = bin.appendingPathComponent(name)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: exe)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: exe.path)
        return app
    }
    func clean() { store.unityPresentation.stop(); try? FileManager.default.removeItem(at: directory) }
}

@MainActor private final class ArenaEntryDeferredLaunch {
    private var continuation: CheckedContinuation<NSRunningApplication, any Error>?
    var calls = 0
    var pending: Bool { continuation != nil }
    func launch() async throws -> NSRunningApplication {
        calls += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func fail() { let old = continuation; continuation = nil; old?.resume(throwing: CocoaError(.executableLoad)) }
}

@MainActor private final class ArenaEntryNoProvider: AssistantClient {
    func connect() async throws { XCTFail("Entry must not connect a provider") }
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        XCTFail("Entry must not call a provider")
    }
}
