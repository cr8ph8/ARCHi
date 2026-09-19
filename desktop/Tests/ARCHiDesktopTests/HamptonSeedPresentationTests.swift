import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class HamptonSeedPresentationTests: XCTestCase {
    func testIdentityRoundTripKeepsCharacterOriginDateAndBeginning() throws {
        let identity = LocalQiMon(character: .hampton, originDigest: String(repeating: "b", count: 64),
                                  welcomedAt: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(identity.isValid)
        XCTAssertEqual(identity.displayName, "Liminal")
        XCTAssertEqual(identity.name, "Liminal")
        XCTAssertEqual(identity.dedication, "Patrick’s new QiMon")
        XCTAssertEqual(identity.currentBody, .hamptonSeed)
        XCTAssertEqual(identity.stageTitle, "Liminal Seed")
        XCTAssertEqual(try JSONDecoder().decode(LocalQiMon.self, from: JSONEncoder().encode(identity)), identity)
        let kin = LocalQiMon(character: .kin, originDigest: String(repeating: "a", count: 64), welcomedAt: identity.welcomedAt)
        XCTAssertEqual(kin.name, "KIN")
        XCTAssertEqual(kin.currentBody, .kinSeed)
        XCTAssertNotEqual(identity, kin)
    }

    @MainActor
    func testSavedHamptonReopensOwnSeedWithoutCreatingGrowthOrChangingProfile() throws {
        let fixture = try HamptonSeedFixture()
        defer { fixture.clean() }
        let bytes = try Data(contentsOf: fixture.profile)
        let store = fixture.store
        XCTAssertEqual(store.activeQiMon, fixture.identity)
        XCTAssertEqual(store.presentationTitle, "Liminal")
        XCTAssertEqual(store.presentationForm, .hamptonSeed)
        XCTAssertEqual(store.cursorPresentationForm, .hamptonSeed)
        XCTAssertEqual(store.kinBodyTitle, "Liminal Seed")
        XCTAssertTrue(store.cursorAccessibilityValue.contains("Liminal · Seed cursor"))
        XCTAssertFalse(store.cursorAccessibilityValue.contains("KIN"))
        XCTAssertFalse(store.kinGrowthControlsAvailable)
        XCTAssertTrue(store.kinGrowthEvidence.isEmpty)
        XCTAssertFalse(store.previewKinGrowth(receiptID: UUID()))
        XCTAssertFalse(store.keepKinGrowth())
        XCTAssertFalse(store.resumeKinFirstLight())
        XCTAssertNil(store.evolution.kinGrowthRecord)
        XCTAssertEqual(try Data(contentsOf: fixture.profile), bytes)
        let reopened = CompanionStore(preferenceURL: fixture.profile, allowsPlay: false)
        XCTAssertEqual(reopened.activeQiMon, fixture.identity)
        XCTAssertEqual(reopened.presentationForm, .hamptonSeed)
        XCTAssertEqual(reopened.cursorPresentationForm, .hamptonSeed)
        XCTAssertNil(reopened.evolution.kinGrowthRecord)
    }

    @MainActor
    func testVerifiedAssetHasDistinctCacheAndNativeSnapshotWithoutChangingKIN() throws {
        XCTAssertNotNil(CompanionVisualAsset.hamptonSeedImage)
        XCTAssertEqual(CompanionVisualAsset.hamptonSeedDigest, "2f8ac5d79dae36bed3e91cbd55f53b2f86d5317b464c119d9c14d37512044c18")
        XCTAssertEqual(CompanionVisualAsset.kinSeedDigest, "02066c89c597edf6b0f9d3c9f5706323cfefa8163c94b8407ec48cd7e57bf5e6")
        let identity = CompanionVisualAsset.appearanceID(form: .hamptonSeed, family: nil, treatment: .original)
        XCTAssertEqual(identity, "h1-\(CompanionVisualAsset.hamptonSeedDigest)")
        XCTAssertEqual(identity, CompanionVisualAsset.appearanceID(form: .hamptonSeed, family: nil, treatment: .protoStudy))
        XCTAssertEqual(CompanionVisualAsset.appearanceID(form: .hamptonSeed, family: nil, treatment: .original, assetAvailable: false),
                       "hampton-liminal-native-fallback-v1")
        XCTAssertEqual(CompanionVisualAsset.label(form: .hamptonSeed, family: nil, treatment: .original), "Hampton · Liminal Seed")
        let png = try XCTUnwrap(CompanionPresenceArt.png(form: .hamptonSeed, family: nil))
        XCTAssertNotEqual(png, CompanionPresenceArt.png(form: .kinSeed, family: nil))
        XCTAssertNotEqual(png, CompanionPresenceArt.png(form: .corePearl, family: nil))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(bitmap.pixelsWide, 512)
        XCTAssertEqual(bitmap.pixelsHigh, 512)
        XCTAssertTrue(bitmap.hasAlpha)
        XCTAssertLessThan(png.count, CompanionVisualAsset.maximumBytes)
        XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0.01)
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 256, y: 256)).alphaComponent, 0.9)
    }

    @MainActor
    func testAllThreeSeedChoicesRemainPresentationOnlyAndRenderAtNarrowWidth() throws {
        let fixture = try HamptonSeedFixture()
        defer { fixture.clean() }
        let store = fixture.store, original = fixture.identity
        let history = store.evolution.history
        let bytes = try Data(contentsOf: fixture.profile)
        let oldPlayer = try fixture.player(name: "Old", personal: false)
        let currentPlayer = try fixture.player(name: "Current", personal: true)
        XCTAssertEqual(CompanionSeedAppearance.allCases.count, 3)
        for choice in CompanionSeedAppearance.allCases {
            store.chooseSeedAppearance(choice)
            XCTAssertEqual(store.activeQiMon, original)
            XCTAssertEqual(store.presentationForm, choice.personalForm)
            XCTAssertEqual(store.cursorPresentationForm, choice.personalForm)
            XCTAssertEqual(store.evolution.history, history)
            XCTAssertNil(store.evolution.kinGrowthRecord)
            XCTAssertEqual(store.unityPresentationUnavailableReason(for: oldPlayer) != nil, choice == .hamptonLiminal)
            XCTAssertNil(store.unityPresentationUnavailableReason(for: currentPlayer))
            let projection = try XCTUnwrap(UnityPresentationSnapshot.capture(store: store, sessionID: UUID(), revision: 1,
                active: true, now: Date(), systemReduceMotion: false))
            XCTAssertEqual(projection.originDigest, original.originDigest)
            XCTAssertEqual(projection.displayName, "Liminal", "Selecting KIN artwork does not replace Hampton’s identity")
            XCTAssertEqual(projection.body, "seed")
            XCTAssertEqual(projection.cursor, "seed")
            XCTAssertEqual(projection.seedAppearance ?? "kinParticles", choice.rawValue)
        }
        XCTAssertEqual(try Data(contentsOf: fixture.profile), bytes)
        for dark in [false, true] {
            let renderer = ImageRenderer(content: SeedAppearanceCard(store: store).padding(20).frame(width: 630)
                .background(dark ? Color.black : Color.white).environment(\.colorScheme, dark ? .dark : .light))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.nsImage)
            XCTAssertEqual(image.size.width, 630)
            XCTAssertGreaterThan(image.size.height, 220)
            if let directory = ProcessInfo.processInfo.environment["ARCHI_HAMPTON_SEED_REVIEW_DIR"] {
                let folder = URL(fileURLWithPath: directory)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: folder.appendingPathComponent(dark ? "three-seeds-dark.png" : "three-seeds-light.png"))
            }
        }
    }

    @MainActor
    func testOldPlayerRejectsLiminalBeforeLaunchAndSupportedPlayerProjectsEverySeed() async throws {
        let fixture = try HamptonSeedFixture()
        defer { fixture.clean() }
        let bytes = try Data(contentsOf: fixture.profile)
        let history = fixture.store.evolution.history
        let oldPlayer = try fixture.player(name: "Old", personal: false)
        let currentPlayer = try fixture.player(name: "Current", personal: true)
        var launches = 0
        let connection = UnityPresentationConnection(launchApplication: { _, _ in
            launches += 1
            throw NSError(domain: "unexpected-launch", code: 1)
        }, bundledResourceURL: nil, fallbackPlayers: [])
        defer { connection.stop() }
        XCTAssertTrue(connection.selectPlayer(oldPlayer))
        XCTAssertThrowsError(try connection.beginPublishing(store: fixture.store, directory: fixture.directory))
        await connection.openArena(store: fixture.store)
        XCTAssertEqual(launches, 0)
        XCTAssertFalse(connection.isSharing)
        XCTAssertNil(connection.snapshotURL)
        XCTAssertFalse(ArenaEntryState(store: fixture.store, connection: connection).canEnter)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).contains { $0.hasPrefix("archi-unity-") })

        XCTAssertTrue(connection.selectPlayer(currentPlayer))
        for appearance in CompanionSeedAppearance.allCases {
            fixture.store.chooseSeedAppearance(appearance)
            XCTAssertTrue(ArenaEntryState(store: fixture.store, connection: connection).canEnter)
            try connection.beginPublishing(store: fixture.store, directory: fixture.directory, destination: .arena)
            XCTAssertTrue(connection.isSharing)
            let value = try XCTUnwrap(connection.lastSnapshot)
            XCTAssertEqual(value.originDigest, fixture.identity.originDigest)
            XCTAssertEqual(value.displayName, "Liminal")
            XCTAssertEqual(value.body, "seed")
            XCTAssertEqual(value.cursor, "seed")
            XCTAssertEqual(value.seedAppearance ?? "kinParticles", appearance.rawValue)
            let digest = appearance == .hamptonLiminal ? CompanionVisualAsset.hamptonSeedDigest
                : appearance == .archiLight ? CompanionVisualAsset.lightSeedDigest : CompanionVisualAsset.kinSeedDigest
            XCTAssertEqual(value.seedAssetSHA256, digest)
            XCTAssertEqual(value.bodyAssetSHA256, digest)
            XCTAssertEqual(value.destination, "arena")
            let published = try JSONDecoder().decode(UnityPresentationSnapshot.self,
                from: Data(contentsOf: XCTUnwrap(connection.snapshotURL)))
            XCTAssertEqual(published, value)
            connection.stop()
        }
        XCTAssertEqual(launches, 0, "Projection fixture never launches a real player")
        XCTAssertEqual(fixture.store.activeQiMon, fixture.identity)
        XCTAssertEqual(fixture.store.evolution.history, history)
        XCTAssertNil(fixture.store.evolution.kinGrowthRecord)
        XCTAssertEqual(try Data(contentsOf: fixture.profile), bytes)
        await fixture.store.shutdownAssistant()
    }

    @MainActor
    func testLiminalChoiceRetiresOldPlayerProjectionAndSupportedPlayerPreservesKIN() throws {
        let fixture = try HamptonSeedFixture(character: .kin)
        defer { fixture.clean() }
        let bytes = try Data(contentsOf: fixture.profile)
        let history = fixture.store.evolution.history
        let oldPlayer = try fixture.player(name: "Old", personal: false)
        let currentPlayer = try fixture.player(name: "Current", personal: true)
        let connection = UnityPresentationConnection(bundledResourceURL: nil, fallbackPlayers: [])
        defer { connection.stop() }
        XCTAssertTrue(connection.selectPlayer(oldPlayer))
        try connection.beginPublishing(store: fixture.store, directory: fixture.directory)
        XCTAssertTrue(connection.isSharing)
        XCTAssertEqual(connection.lastSnapshot?.seedAssetSHA256, CompanionVisualAsset.kinSeedDigest)
        fixture.store.chooseSeedAppearance(.hamptonLiminal)
        connection.refresh(store: fixture.store)
        XCTAssertFalse(connection.isSharing)
        XCTAssertNotNil(fixture.store.unityPresentationUnavailableReason(for: oldPlayer))
        let captured = try XCTUnwrap(UnityPresentationSnapshot.capture(store: fixture.store, sessionID: UUID(), revision: 1,
            active: true, now: Date(), systemReduceMotion: false))
        XCTAssertEqual(captured.originDigest, fixture.identity.originDigest)
        XCTAssertEqual(captured.displayName, "KIN")
        XCTAssertEqual(captured.seedAssetSHA256, CompanionVisualAsset.hamptonSeedDigest)

        XCTAssertTrue(connection.selectPlayer(currentPlayer))
        try connection.beginPublishing(store: fixture.store, directory: fixture.directory)
        XCTAssertTrue(connection.isSharing)
        XCTAssertEqual(connection.lastSnapshot?.seedAppearance, "hamptonLiminal")
        XCTAssertEqual(connection.lastSnapshot?.originDigest, fixture.identity.originDigest)
        let revision = try XCTUnwrap(connection.lastSnapshot).revision
        fixture.store.chooseSeedAppearance(.kinParticles)
        connection.refresh(store: fixture.store)
        XCTAssertTrue(connection.isSharing)
        XCTAssertGreaterThan(try XCTUnwrap(connection.lastSnapshot).revision, revision)
        XCTAssertEqual(connection.lastSnapshot?.seedAssetSHA256, CompanionVisualAsset.kinSeedDigest)
        XCTAssertEqual(connection.lastSnapshot?.displayName, "KIN")
        XCTAssertEqual(connection.lastSnapshot?.originDigest, fixture.identity.originDigest)
        XCTAssertEqual(fixture.store.activeQiMon, fixture.identity)
        XCTAssertEqual(fixture.store.evolution.history, history)
        XCTAssertNil(fixture.store.evolution.kinGrowthRecord)
        XCTAssertEqual(try Data(contentsOf: fixture.profile), bytes)
    }

}

@MainActor
private struct HamptonSeedFixture {
    let directory: URL
    let profile: URL
    let identity: LocalQiMon
    let store: CompanionStore

    init(character: LocalQiMon.Character = .hampton) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("hampton-seed-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        profile = directory.appendingPathComponent("preferences.json")
        identity = LocalQiMon(character: character, originDigest: String(repeating: character == .hampton ? "b" : "a", count: 64),
                            welcomedAt: Date(timeIntervalSince1970: 1_700_000_000))
        var preferences = CompanionPreferences()
        preferences.form = character == .hampton ? .hamptonSeed : .companion
        preferences.seedAppearance = character == .hampton ? .hamptonLiminal : .kinParticles
        preferences.reduceMotion = true
        try NativePreferenceDocument(preferences: preferences, qiMon: identity).encoded().write(to: profile)
        store = CompanionStore(preferenceURL: profile, allowsPlay: false)
    }

    func player(name: String, personal: Bool) throws -> URL {
        let app = directory.appendingPathComponent(name + ".app")
        let contents = app.appendingPathComponent("Contents")
        let binary = contents.appendingPathComponent("MacOS/fixture")
        try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        var plist: [String: Any] = ["CFBundleIdentifier": "local.archi.unityport", "CFBundleExecutable": "fixture",
            "CFBundlePackageType": "APPL", "ARCHiNativePresentationProtocol": 1,
            "ARCHiNativeArenaProtocol": 1, "ARCHiSeedAppearanceVersion": 1]
        if personal { plist["ARCHiPersonalSeedVersion"] = 1 }
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    func clean() {
        store.unityPresentation.stop()
        try? FileManager.default.removeItem(at: directory)
    }
}
