import AppKit
import XCTest
@testable import ARCHiDesktop

final class UnityArenaConnectionTests: XCTestCase {
    @MainActor func testLivePrimarySeedLooksFollowTheSameIndividual() async throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_UNITY_PLAYER_TEST_APP"] else {
            throw XCTSkip("Set ARCHI_UNITY_PLAYER_TEST_APP for the two Seed look handoff.")
        }
        let fixture = try ArenaConnectionFixture(kin: true)
        defer { fixture.clean() }
        let store = fixture.store, connection = fixture.store.unityPresentation
        let identity = store.activeQiMon
        let bytes = try Data(contentsOf: fixture.profile)
        let player = URL(fileURLWithPath: path)
        XCTAssertTrue(UnityPresentationConnection.supportsSeedAppearances(player))
        XCTAssertTrue(connection.selectPlayer(player))
        store.chooseSeedAppearance(.archiLight)
        await connection.openArena(store: store)
        try await waitForLiveArea(connection, .arena)
        XCTAssertEqual(connection.lastSnapshot?.seedAssetSHA256, CompanionVisualAsset.lightSeedDigest)
        XCTAssertEqual(connection.lastSnapshot?.seedAppearance, "archiLight")
        store.chooseSeedAppearance(.kinParticles)
        connection.refresh(store: store)
        try await waitForLiveArea(connection, .arena)
        XCTAssertEqual(connection.lastSnapshot?.seedAssetSHA256, CompanionVisualAsset.kinSeedDigest)
        XCTAssertEqual(store.activeQiMon, identity)
        XCTAssertEqual(try Data(contentsOf: fixture.profile), bytes)
        XCTAssertEqual(fixture.assistant.calls, 0)
        await store.shutdownAssistant()
    }

    @MainActor func testLivePlayerRoutesCompanionAndArenaWithinOneNativeSession() async throws {
        try await exerciseLivePlayer(hasKIN: true)
    }

    @MainActor func testLiveFirstRunPlayerUsesIdentityFreeLocalRosterPractice() async throws {
        try await exerciseLivePlayer(hasKIN: false)
    }

    @MainActor private func exerciseLivePlayer(hasKIN: Bool) async throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_UNITY_PLAYER_TEST_APP"] else {
            throw XCTSkip("Set ARCHI_UNITY_PLAYER_TEST_APP for disposable native Arena handoff.")
        }
        let fixture = try ArenaConnectionFixture(kin: hasKIN)
        defer { fixture.clean() }
        let connection = fixture.store.unityPresentation
        let before = try Data(contentsOf: fixture.profile)
        XCTAssertNil(UnityPresentationSnapshot.capture(store: fixture.store, sessionID: UUID(), revision: 1,
            active: true, now: Date(), systemReduceMotion: false, destination: .arena, localPractice: true))
        XCTAssertNil(UnityPresentationSnapshot.capture(store: fixture.store, sessionID: UUID(), revision: 1,
            active: true, now: Date(), systemReduceMotion: false, destinationRevision: 1, localPractice: true))
        XCTAssertTrue(connection.selectPlayer(URL(fileURLWithPath: path)))
        await connection.openArena(store: fixture.store)
        try await waitForLiveArea(connection, .arena)
        let url = try XCTUnwrap(connection.snapshotURL), first = try XCTUnwrap(connection.lastSnapshot)
        defer { connection.stop(); try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertEqual(connection.isLocalPractice, !hasKIN)
        fixture.store.preferences.quiet = true
        try connection.publish(store: fixture.store)
        try await waitForLiveArea(connection, .arena)
        XCTAssertTrue(try XCTUnwrap(connection.lastSnapshot).quiet)
        if hasKIN {
            await connection.open(store: fixture.store, destination: .companion)
            try await waitForLiveArea(connection, .companion)
            await connection.openArena(store: fixture.store)
            try await waitForLiveArea(connection, .arena)
        } else {
            await connection.open(store: fixture.store)
            XCTAssertTrue(connection.isSharing); XCTAssertTrue(connection.status.contains("saved KIN"))
            XCTAssertNil(fixture.store.activeQiMon)
        }
        XCTAssertEqual(connection.snapshotURL, url); XCTAssertEqual(connection.lastSnapshot?.sessionID, first.sessionID)
        XCTAssertEqual(connection.lastSnapshot?.originDigest, first.originDigest)
        connection.stop()
        let retired = try JSONDecoder().decode(UnityPresentationSnapshot.self, from: Data(contentsOf: url))
        XCTAssertFalse(retired.active); XCTAssertFalse(retired.visible)
        XCTAssertEqual(try Data(contentsOf: fixture.profile), before)
        XCTAssertEqual(fixture.assistant.calls, 0)
        await fixture.store.shutdownAssistant()
    }

    @MainActor private func waitForLiveArea(_ connection: UnityPresentationConnection, _ area: UnityPresentationDestination) async throws {
        for _ in 0..<80 {
            connection.readAcknowledgment()
            if connection.hasRenderAcknowledgment && connection.destination == area { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("Unity did not acknowledge the requested area: \(area.rawValue). \(connection.status)")
        throw CocoaError(.executableLoad)
    }

    @MainActor func testFirstRunArenaPublishesNoIdentityAndRetiresWithoutSaving() async throws {
        let fixture = try ArenaConnectionFixture(kin: false)
        defer { fixture.clean() }
        let connection = fixture.store.unityPresentation
        let before = try Data(contentsOf: fixture.profile)
        try connection.beginPublishing(store: fixture.store, directory: fixture.directory, destination: .arena)
        let first = try XCTUnwrap(connection.lastSnapshot)
        XCTAssertTrue(connection.isSharing); XCTAssertTrue(connection.isLocalPractice)
        XCTAssertEqual(connection.destination, .arena)
        XCTAssertEqual(first.sessionKind, "localPractice"); XCTAssertEqual(first.destination, "arena")
        XCTAssertEqual(first.destinationRevision, 1)
        XCTAssertEqual(first.originDigest, ""); XCTAssertEqual(first.displayName, "Local roster practice")
        XCTAssertEqual(first.body, "none"); XCTAssertEqual(first.appearance, "none"); XCTAssertEqual(first.cursor, "none")
        XCTAssertEqual(first.seedAssetSHA256, ""); XCTAssertEqual(first.bodyAssetSHA256, "")
        XCTAssertFalse(first.equippedFocusStaff); XCTAssertNil(first.staffPalette); XCTAssertNil(first.staffCrown)
        fixture.store.preferences.reduceMotion = true
        try connection.publish(store: fixture.store, systemReduceMotion: false)
        XCTAssertTrue(try XCTUnwrap(connection.lastSnapshot).reduceMotion)
        XCTAssertEqual(connection.lastSnapshot?.destinationRevision, 1, "Heartbeats cannot make a new navigation request")
        let url = try XCTUnwrap(connection.snapshotURL)
        connection.stop()
        let retired = try JSONDecoder().decode(UnityPresentationSnapshot.self, from: Data(contentsOf: url))
        XCTAssertEqual(retired.sessionKind, "localPractice"); XCTAssertEqual(retired.cursor, "none")
        XCTAssertFalse(retired.active); XCTAssertFalse(retired.visible); XCTAssertEqual(retired.activity, "stopped")
        XCTAssertNil(fixture.store.activeQiMon)
        XCTAssertEqual(try Data(contentsOf: fixture.profile), before)
        XCTAssertEqual(fixture.assistant.calls, 0)
        await fixture.store.shutdownAssistant()
    }

    @MainActor func testRepeatedOpenChangesRouteWithinPendingOwnerAndACKTracksReturn() async throws {
        let fixture = try ArenaConnectionFixture(kin: true)
        defer { fixture.clean() }
        let launcher = ArenaDeferredLaunch()
        defer { launcher.fail() }
        let connection = UnityPresentationConnection(launchApplication: { _, _ in try await launcher.launch() })
        defer { connection.stop() }
        XCTAssertTrue(connection.selectPlayer(fixture.player))
        let opening = Task { await connection.open(store: fixture.store) }
        for _ in 0..<500 { if launcher.pending { break }; await Task.yield() }
        XCTAssertTrue(launcher.pending)
        let url = try XCTUnwrap(connection.snapshotURL)
        defer { connection.stop(); try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = try XCTUnwrap(connection.lastSnapshot)
        await connection.openArena(store: fixture.store)
        let arena = try XCTUnwrap(connection.lastSnapshot)
        XCTAssertEqual(launcher.calls, 1, "An Arena route must reuse the in-flight player launch")
        XCTAssertEqual(arena.sessionID, first.sessionID); XCTAssertEqual(connection.snapshotURL, url)
        XCTAssertEqual(arena.originDigest, first.originDigest); XCTAssertEqual(arena.body, first.body)
        XCTAssertEqual(arena.destination, "arena"); XCTAssertGreaterThan(try XCTUnwrap(arena.destinationRevision), try XCTUnwrap(first.destinationRevision))
        try ack(first, area: "companion").write(to: url.appendingPathExtension("ack"))
        connection.readAcknowledgment(); XCTAssertFalse(connection.hasRenderAcknowledgment)
        try ack(arena, area: "arena").write(to: url.appendingPathExtension("ack"))
        connection.readAcknowledgment(); XCTAssertTrue(connection.hasRenderAcknowledgment); XCTAssertEqual(connection.destination, .arena)
        try ack(arena, area: "companion").write(to: url.appendingPathExtension("ack"))
        connection.readAcknowledgment(); XCTAssertEqual(connection.destination, .companion)
        try connection.publish(store: fixture.store)
        XCTAssertEqual(connection.lastSnapshot?.destinationRevision, arena.destinationRevision)
        XCTAssertEqual(connection.destination, .companion, "A heartbeat respects Return to companion in Unity")
        await connection.openArena(store: fixture.store)
        XCTAssertEqual(connection.destination, .arena)
        XCTAssertGreaterThan(try XCTUnwrap(connection.lastSnapshot?.destinationRevision), try XCTUnwrap(arena.destinationRevision))
        await connection.open(store: fixture.store, destination: .companion)
        XCTAssertEqual(connection.lastSnapshot?.destination, "companion"); XCTAssertEqual(launcher.calls, 1)
        let status = connection.status
        connection.stop(); launcher.fail(); await opening.value
        XCTAssertFalse(connection.isSharing); XCTAssertNotEqual(connection.status, status)
        XCTAssertEqual(fixture.assistant.calls, 0)
        await fixture.store.shutdownAssistant()
    }

    @MainActor func testArenaACKRequiresExactRouteKindRevisionAndValidCurrentArea() async throws {
        let fixture = try ArenaConnectionFixture(kin: false)
        defer { fixture.clean() }
        let connection = fixture.store.unityPresentation
        try connection.beginPublishing(store: fixture.store, directory: fixture.directory, destination: .arena)
        let snapshot = try XCTUnwrap(connection.lastSnapshot)
        let url = try XCTUnwrap(connection.snapshotURL).appendingPathExtension("ack")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: ack(snapshot, area: "arena")) as? [String: Any])
        for (key, invalid) in [("sessionKind", "companion" as Any), ("destination", "companion" as Any),
                               ("destinationRevision", 0 as Any), ("currentArea", "marketplace" as Any)] {
            var changed = object; changed[key] = invalid
            try JSONSerialization.data(withJSONObject: changed).write(to: url)
            connection.readAcknowledgment(); XCTAssertFalse(connection.hasRenderAcknowledgment, key)
        }
        object["currentArea"] = nil
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        connection.readAcknowledgment(); XCTAssertFalse(connection.hasRenderAcknowledgment)
        try ack(snapshot, area: "arena", time: Date().addingTimeInterval(-6)).write(to: url)
        connection.readAcknowledgment(); XCTAssertFalse(connection.hasRenderAcknowledgment)
        try ack(snapshot, area: "arena").write(to: url)
        connection.readAcknowledgment(); XCTAssertTrue(connection.hasRenderAcknowledgment)
        var wrongSeed = try XCTUnwrap(JSONSerialization.jsonObject(with: ack(snapshot, area: "arena")) as? [String: Any])
        wrongSeed["seedAppearance"] = "archiLight"
        try JSONSerialization.data(withJSONObject: wrongSeed).write(to: url)
        connection.readAcknowledgment(); XCTAssertFalse(connection.hasRenderAcknowledgment)
        try ack(snapshot, area: "arena").write(to: url)
        connection.readAcknowledgment(); XCTAssertTrue(connection.hasRenderAcknowledgment)
        connection.stop(); connection.readAcknowledgment()
        XCTAssertFalse(connection.hasRenderAcknowledgment, "An old ACK cannot revive stopped sharing")
        await fixture.store.shutdownAssistant()
    }

    @MainActor func testOldPlayerCannotStartArenaAndFirstRunCannotOpenCompanion() async throws {
        let fixture = try ArenaConnectionFixture(kin: false, arenaVersion: nil)
        defer { fixture.clean() }
        let connection = fixture.store.unityPresentation
        XCTAssertTrue(UnityPresentationConnection.isCompatiblePlayer(fixture.player))
        XCTAssertFalse(UnityPresentationConnection.supportsArena(fixture.player))
        XCTAssertTrue(connection.selectPlayer(fixture.player))
        await connection.openArena(store: fixture.store)
        XCTAssertFalse(connection.isSharing); XCTAssertNil(connection.snapshotURL)
        XCTAssertTrue(connection.status.contains("Arena support"))
        await connection.open(store: fixture.store)
        XCTAssertFalse(connection.isSharing); XCTAssertTrue(connection.status.contains("saved KIN"))
        XCTAssertNil(fixture.store.activeQiMon); XCTAssertEqual(fixture.assistant.calls, 0)
        await fixture.store.shutdownAssistant()
    }

    @MainActor func testUnsupportedNativeSeedStyleCannotClaimVisualAcknowledgment() async throws {
        let fixture = try ArenaConnectionFixture(kin: true)
        defer { fixture.clean() }
        let connection = fixture.store.unityPresentation
        XCTAssertTrue(connection.selectPlayer(fixture.player))
        let profile = try Data(contentsOf: fixture.profile)
        fixture.store.preferences.seedAppearance = .archiLight
        XCTAssertNotNil(UnityPresentationSnapshot.capture(store: fixture.store, sessionID: UUID(), revision: 1,
            active: true, now: Date(), systemReduceMotion: false))
        XCTAssertThrowsError(try connection.beginPublishing(store: fixture.store, directory: fixture.directory, destination: .arena))
        XCTAssertFalse(connection.isSharing)
        fixture.store.preferences.seedAppearance = .kinParticles
        try connection.beginPublishing(store: fixture.store, directory: fixture.directory, destination: .arena)
        let url = try XCTUnwrap(connection.snapshotURL)
        fixture.store.preferences.seedAppearance = .archiLight
        connection.refresh(store: fixture.store)
        XCTAssertFalse(connection.isSharing); XCTAssertFalse(connection.hasRenderAcknowledgment)
        XCTAssertTrue(connection.status.contains("KIN particle Seed"))
        let retired = try JSONDecoder().decode(UnityPresentationSnapshot.self, from: Data(contentsOf: url))
        XCTAssertFalse(retired.active); XCTAssertFalse(retired.visible)
        XCTAssertEqual(try Data(contentsOf: fixture.profile), profile)
        XCTAssertEqual(fixture.assistant.calls, 0)
        await fixture.store.shutdownAssistant()
    }

    private func ack(_ snapshot: UnityPresentationSnapshot, area: String, time: Date = Date()) throws -> Data {
        var object: [String: Any] = ["schemaVersion": 1, "sessionID": snapshot.sessionID, "originDigest": snapshot.originDigest,
            "revision": snapshot.revision, "updatedAtUnix": time.timeIntervalSince1970, "active": snapshot.active,
            "body": snapshot.body, "appearance": snapshot.appearance, "renderer": "unity-companion", "currentArea": area]
        object["sessionKind"] = snapshot.sessionKind; object["destination"] = snapshot.destination
        object["destinationRevision"] = snapshot.destinationRevision
        object["staffPalette"] = snapshot.staffPalette; object["staffCrown"] = snapshot.staffCrown
        return try JSONSerialization.data(withJSONObject: object)
    }
}

@MainActor private struct ArenaConnectionFixture {
    let directory: URL, profile: URL, player: URL
    let store: CompanionStore
    let assistant: ArenaNoProvider
    init(kin: Bool, arenaVersion: Int? = 1) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("unity-arena-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        profile = directory.appendingPathComponent("profile.json")
        let identity = kin ? LocalQiMon(character: .kin, originDigest: String(repeating: "d", count: 64), welcomedAt: Date()) : nil
        try NativePreferenceDocument(preferences: CompanionPreferences(), qiMon: identity).encoded().write(to: profile)
        assistant = ArenaNoProvider()
        store = CompanionStore(preferenceURL: profile, assistant: assistant, allowsPlay: false)
        player = directory.appendingPathComponent("Fixture.app")
        let contents = player.appendingPathComponent("Contents"), bin = contents.appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": "local.archi.unityport", "CFBundleExecutable": "Fixture",
            "CFBundlePackageType": "APPL", "ARCHiNativePresentationProtocol": 1, "ARCHiNativeStaffRecipeVersion": 1]
        info["ARCHiNativeArenaProtocol"] = arenaVersion
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: bin.appendingPathComponent("Fixture"))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: bin.appendingPathComponent("Fixture").path)
    }
    func clean() { store.unityPresentation.stop(); try? FileManager.default.removeItem(at: directory) }
}
@MainActor private final class ArenaNoProvider: AssistantClient {
    var calls = 0
    func connect() async throws { calls += 1 }
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws { calls += 1 }
}
@MainActor private final class ArenaDeferredLaunch {
    private var continuation: CheckedContinuation<NSRunningApplication, any Error>?
    var calls = 0
    var pending: Bool { continuation != nil }
    func launch() async throws -> NSRunningApplication {
        calls += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func fail() { let old = continuation; continuation = nil; old?.resume(throwing: CocoaError(.executableLoad)) }
}
