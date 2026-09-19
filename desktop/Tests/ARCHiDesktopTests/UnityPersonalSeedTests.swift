import AppKit
import XCTest
@testable import ARCHiDesktop

final class UnityPersonalSeedTests: XCTestCase {
    @MainActor func testEverySeedColorCapturesIdentityAndActualSourceArt() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try store(root), before = try Data(contentsOf: root.appendingPathComponent("preferences.json"))
        defer { store.unityPresentation.stop() }
        for look in CompanionSeedAppearance.allCases {
            for color in CompanionSeedColor.allCases {
                store.chooseSeedAppearance(look); store.chooseSeedColor(color)
                let value = try snapshot(store)
                XCTAssertEqual(value.originDigest, store.activeQiMon?.originDigest)
                XCTAssertEqual(value.body, "seed"); XCTAssertEqual(value.cursor, "seed")
                XCTAssertEqual(value.seedColor ?? "original", color.rawValue)
                let expected = look == .hamptonLiminal ? (color == .garnet ? CompanionVisualAsset.hamptonGarnetDigest : CompanionVisualAsset.hamptonSeedDigest)
                    : look == .archiLight ? CompanionVisualAsset.lightSeedDigest : CompanionVisualAsset.kinSeedDigest
                XCTAssertEqual(value.seedAssetSHA256, expected); XCTAssertEqual(value.bodyAssetSHA256, expected)
                XCTAssertFalse(String(decoding: try JSONEncoder().encode(value), as: UTF8.self).contains("PRIVATE"))
            }
        }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("preferences.json")), before)
        await store.shutdownAssistant()
    }

    @MainActor func testOldPlayerBlocksPersonalSeedButUpdatedPlayerCanEnter() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try store(root)
        let old = try player(root, name: "Old", personal: false)
        let current = try player(root, name: "Current", personal: true)
        var launches = 0
        let connection = UnityPresentationConnection(launchApplication: { _, _ in
            launches += 1; throw NSError(domain: "No actual launch expected", code: 1)
        }, bundledResourceURL: nil, fallbackPlayers: [old])
        XCTAssertFalse(ArenaEntryState(store: store, connection: connection).canEnter)
        await connection.openArena(store: store)
        XCTAssertEqual(launches, 0); XCTAssertFalse(connection.isSharing)
        XCTAssertTrue(connection.selectPlayer(current))
        XCTAssertTrue(ArenaEntryState(store: store, connection: connection).canEnter)
        try connection.beginPublishing(store: store, directory: root, destination: .arena)
        XCTAssertEqual(connection.lastSnapshot?.seedColor, "garnet")
        XCTAssertEqual(connection.lastSnapshot?.seedAppearance, "hamptonLiminal")
        connection.stop(); await store.shutdownAssistant()
    }

    @MainActor func testPersonalAcknowledgmentRequiresColorAndSourceDigests() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try store(root), now = Date()
        let value = try snapshot(store, now: now)
        var object: [String: Any] = ["schemaVersion": 1, "sessionID": value.sessionID,
            "originDigest": value.originDigest, "revision": value.revision, "updatedAtUnix": now.timeIntervalSince1970,
            "active": value.active, "body": value.body, "appearance": value.appearance,
            "renderer": "unity-companion", "seedAppearance": "hamptonLiminal", "seedColor": "garnet",
            "seedAssetSHA256": value.seedAssetSHA256, "bodyAssetSHA256": value.bodyAssetSHA256]
        func matches(_ fields: [String: Any], _ target: UnityPresentationSnapshot) throws -> Bool {
            try JSONDecoder().decode(UnityPresentationAcknowledgment.self, from: JSONSerialization.data(withJSONObject: fields)).matches(target, now: now)
        }
        XCTAssertTrue(try matches(object, value))
        for key in ["seedColor", "seedAssetSHA256", "bodyAssetSHA256"] {
            var wrong = object; wrong.removeValue(forKey: key); XCTAssertFalse(try matches(wrong, value))
            wrong[key] = "unknown"; XCTAssertFalse(try matches(wrong, value))
        }
        store.chooseSeedColor(.violet)
        let changed = try snapshot(store, now: now)
        XCTAssertFalse(value.hasSamePresentation(as: changed))
        object["sessionID"] = changed.sessionID
        XCTAssertFalse(try matches(object, changed))
        await store.shutdownAssistant()
    }

    @MainActor func testLivePersonalSeedArenaHandoff() async throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_UNITY_PERSONAL_PLAYER"] else {
            throw XCTSkip("Opt-in disposable real-player handoff")
        }
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try store(root), connection = store.unityPresentation
        let before = try Data(contentsOf: root.appendingPathComponent("preferences.json"))
        defer { connection.stop() }
        XCTAssertTrue(connection.selectPlayer(URL(fileURLWithPath: path)))
        await connection.openArena(store: store)
        for color in [CompanionSeedColor.garnet, .violet, .original] {
            store.chooseSeedColor(color); connection.refresh(store: store)
            let deadline = Date().addingTimeInterval(20)
            while Date() < deadline {
                connection.readAcknowledgment()
                if connection.hasRenderAcknowledgment { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertTrue(connection.hasRenderAcknowledgment, connection.status)
            XCTAssertEqual(connection.lastSnapshot?.seedColor ?? "original", color.rawValue)
            XCTAssertEqual(connection.lastSnapshot?.destination, "arena")
        }
        connection.stop()
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("preferences.json")), before)
        await store.shutdownAssistant()
    }

    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("archi-personal-arena-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); return root
    }
    @MainActor private func store(_ root: URL) throws -> CompanionStore {
        var preferences = CompanionPreferences(); preferences.seedAppearance = .hamptonLiminal; preferences.seedColor = .garnet
        preferences.quiet = true; preferences.reduceMotion = true
        let kin = LocalQiMon(character: .hampton, originDigest: String(repeating: "d", count: 64), welcomedAt: Date())
        let url = root.appendingPathComponent("preferences.json")
        try NativePreferenceDocument(preferences: preferences, qiMon: kin).encoded().write(to: url)
        let store = CompanionStore(preferenceURL: url, allowsPlay: false)
        store.prompt = "PRIVATE QUESTION"; store.sharedText = "PRIVATE DOCUMENT"
        return store
    }
    @MainActor private func snapshot(_ store: CompanionStore, now: Date = Date()) throws -> UnityPresentationSnapshot {
        try XCTUnwrap(UnityPresentationSnapshot.capture(store: store, sessionID: UUID(), revision: 1, active: true, now: now, systemReduceMotion: false))
    }
    private func player(_ root: URL, name: String, personal: Bool) throws -> URL {
        let app = root.appendingPathComponent(name + ".app"), contents = app.appendingPathComponent("Contents")
        let binary = contents.appendingPathComponent("MacOS/fixture")
        try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        var plist: [String: Any] = ["CFBundleIdentifier": "local.archi.unityport", "CFBundleExecutable": "fixture", "CFBundlePackageType": "APPL",
            "ARCHiNativePresentationProtocol": 1, "ARCHiNativeArenaProtocol": 1, "ARCHiSeedAppearanceVersion": 1]
        if personal { plist["ARCHiPersonalSeedVersion"] = 1 }
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }
}
