import AppKit
import XCTest
@testable import ARCHiDesktop

final class UnityPresentationTests: XCTestCase {
    @MainActor func testLiveUnityPlayerFollowsNativeProfile() async throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_UNITY_PLAYER_TEST_APP"] else {
            throw XCTSkip("Set ARCHI_UNITY_PLAYER_TEST_APP for a disposable native-to-Unity interaction check.")
        }
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let store = fixture.store, connection = store.unityPresentation
        let profile = try Data(contentsOf: fixture.preference)
        XCTAssertTrue(connection.selectPlayer(URL(fileURLWithPath: path)))
        await connection.open(store: store)
        XCTAssertTrue(connection.isSharing, connection.status)
        try await awaitAcknowledgment(connection, body: "seed")
        let request = try retainLessonUse(store)
        XCTAssertTrue(store.previewKinGrowth(receiptID: request)); XCTAssertTrue(store.keepKinGrowth())
        connection.refresh(store: store)
        try await awaitAcknowledgment(connection, body: "firstLight")
        XCTAssertEqual(store.cursorPresentationForm, .kinSeed)
        store.preferences.visualTreatment = .protoStudy
        connection.refresh(store: store)
        try await awaitAcknowledgment(connection, body: "firstLight")
        XCTAssertEqual(connection.lastSnapshot?.appearance, "proto")
        XCTAssertEqual(connection.lastSnapshot?.bodyAssetSHA256, CompanionVisualAsset.protoDigest)
        for design in CompanionItemCatalog.designs {
            store.preferences.equipment = CompanionEquipment(hand: .focusStaff, design: design)
            connection.refresh(store: store)
            try await awaitAcknowledgment(connection, body: "firstLight")
            XCTAssertEqual(connection.lastSnapshot?.staffPalette, design.palette.rawValue)
            XCTAssertEqual(connection.lastSnapshot?.staffCrown, design.crown.rawValue)
        }
        store.preferences.quiet = true
        connection.refresh(store: store)
        try await awaitAcknowledgment(connection, body: "firstLight")
        XCTAssertTrue(try XCTUnwrap(connection.lastSnapshot).quiet)
        store.returnKinToSeed(); connection.refresh(store: store)
        try await awaitAcknowledgment(connection, body: "seed")
        connection.stop()
        XCTAssertFalse(connection.isSharing)
        XCTAssertEqual(try Data(contentsOf: fixture.preference), profile)
        await store.shutdownAssistant()
    }

    @MainActor private func awaitAcknowledgment(_ connection: UnityPresentationConnection, body: String) async throws {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            connection.readAcknowledgment()
            if connection.hasRenderAcknowledgment, connection.lastSnapshot?.body == body { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("Unity did not acknowledge the native \(body) presentation: \(connection.status)")
    }

    @MainActor func testProjectionKeepsSeedCursorAndUsesOnlyKeptBody() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let store = fixture.store
        let session = UUID(), now = Date()
        func snapshot() throws -> UnityPresentationSnapshot {
            try XCTUnwrap(UnityPresentationSnapshot.capture(store: store, sessionID: session,
                revision: 1, active: true, now: now, systemReduceMotion: false))
        }
        XCTAssertEqual(try snapshot().body, "seed")
        let request = try retainLessonUse(store)
        XCTAssertTrue(store.previewKinGrowth(receiptID: request))
        XCTAssertEqual(try snapshot().body, "seed", "Preview never becomes an accepted body")
        XCTAssertTrue(store.keepKinGrowth())
        XCTAssertEqual(try snapshot().body, "firstLight")
        XCTAssertEqual(try snapshot().cursor, "seed")
        XCTAssertEqual(try snapshot().bodyAssetSHA256, CompanionVisualAsset.kinFirstLightDigest)
        XCTAssertTrue(store.evolution.save())
        let reopened = CompanionStore(preferenceURL: fixture.preference, allowsPlay: false)
        XCTAssertEqual(reopened.presentationForm, .kinSeed)
        XCTAssertTrue(reopened.evolution.load())
        XCTAssertEqual(reopened.presentationForm, .kin)
        let afterLoad = try XCTUnwrap(UnityPresentationSnapshot.capture(store: reopened, sessionID: session,
            revision: 2, active: true, now: now, systemReduceMotion: false))
        XCTAssertEqual(afterLoad.originDigest, try snapshot().originDigest)
        XCTAssertEqual(afterLoad.body, "firstLight")
        store.returnKinToSeed()
        XCTAssertEqual(try snapshot().body, "seed")
        XCTAssertEqual(try snapshot().bodyAssetSHA256, CompanionVisualAsset.kinSeedDigest)
        XCTAssertTrue(store.resumeKinFirstLight())
        XCTAssertEqual(try snapshot().body, "firstLight")
        await reopened.shutdownAssistant(); await store.shutdownAssistant()
    }

    @MainActor func testProjectionExcludesPrivateContentAndCarriesEffectiveMotionAndItem() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let store = fixture.store
        store.prompt = "PRIVATE QUESTION"
        store.sharedText = "PRIVATE DOCUMENT"
        store.sourceName = "PRIVATE SOURCE"
        store.preferences.quiet = true
        store.preferences.equipment = CompanionEquipment(hand: .focusStaff)
        let snapshot = try XCTUnwrap(UnityPresentationSnapshot.capture(store: store, sessionID: UUID(),
            revision: 2, active: true, now: Date(), systemReduceMotion: true))
        XCTAssertTrue(snapshot.quiet); XCTAssertTrue(snapshot.reduceMotion)
        XCTAssertTrue(snapshot.equippedFocusStaff); XCTAssertEqual(snapshot.lightMode, "rest")
        let data = try JSONEncoder().encode(snapshot)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains("PRIVATE"))
        XCTAssertFalse(text.contains("Begin with a short outline"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "sessionID", "revision", "originDigest", "displayName",
            "body", "appearance", "cursor", "seedAssetSHA256", "bodyAssetSHA256", "activity", "lightMode", "quiet",
            "reduceMotion", "visible", "equippedFocusStaff", "active", "updatedAtUnix"])
        XCTAssertLessThan(data.count, UnityPresentationConnection.maximumBytes)
        store.preferences.quiet = false; store.preferences.reduceMotion = true
        XCTAssertTrue(try XCTUnwrap(UnityPresentationSnapshot.capture(store: store, sessionID: UUID(),
            revision: 3, active: true, now: Date(), systemReduceMotion: false)).reduceMotion)
        await store.shutdownAssistant()
    }

    @MainActor func testPrivateAtomicPublicationStopAndShutdownDoNotChangeProfile() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let store = fixture.store, connection = store.unityPresentation
        let profile = try Data(contentsOf: fixture.preference)
        try connection.beginPublishing(store: store, directory: fixture.directory)
        let url = try XCTUnwrap(connection.snapshotURL)
        let fileMode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        let folderMode = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(fileMode?.intValue, 0o600); XCTAssertEqual(folderMode?.intValue, 0o700)
        let first = try JSONDecoder().decode(UnityPresentationSnapshot.self, from: Data(contentsOf: url))
        store.preferences.reduceMotion = true
        try connection.publish(store: store, systemReduceMotion: false)
        let second = try JSONDecoder().decode(UnityPresentationSnapshot.self, from: Data(contentsOf: url))
        XCTAssertEqual(second.sessionID, first.sessionID)
        XCTAssertGreaterThan(second.revision, first.revision)
        XCTAssertTrue(second.reduceMotion)
        XCTAssertFalse(connection.hasRenderAcknowledgment)
        await store.shutdownAssistant()
        let final = try JSONDecoder().decode(UnityPresentationSnapshot.self, from: Data(contentsOf: url))
        XCTAssertFalse(connection.isSharing); XCTAssertFalse(final.active); XCTAssertFalse(final.visible)
        XCTAssertEqual(final.activity, "stopped"); XCTAssertTrue(final.reduceMotion)
        XCTAssertGreaterThan(final.revision, second.revision)
        connection.refresh(store: store)
        XCTAssertEqual(try Data(contentsOf: fixture.preference), profile)
        XCTAssertEqual(try JSONDecoder().decode(UnityPresentationSnapshot.self, from: Data(contentsOf: url)), final)
    }

    @MainActor func testAcknowledgmentRequiresExactKnownSessionOriginRevisionBodyAndFreshTime() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let store = fixture.store, connection = store.unityPresentation
        try connection.beginPublishing(store: store, directory: fixture.directory)
        let snapshot = try XCTUnwrap(connection.lastSnapshot), now = Date()
        let url = try XCTUnwrap(connection.snapshotURL).appendingPathExtension("ack")
        let valid: [String: Any] = ["schemaVersion": 1, "sessionID": snapshot.sessionID,
            "originDigest": snapshot.originDigest, "revision": snapshot.revision,
            "updatedAtUnix": now.timeIntervalSince1970, "active": true, "body": "seed", "renderer": "unity-companion"]
        try JSONSerialization.data(withJSONObject: valid).write(to: url)
        connection.readAcknowledgment(now: now)
        XCTAssertTrue(connection.hasRenderAcknowledgment)
        for (key, wrong): (String, Any) in [("sessionID", UUID().uuidString), ("originDigest", String(repeating: "f", count: 64)),
                ("revision", 999), ("body", "firstLight"), ("renderer", "unrelated"), ("active", false),
                ("updatedAtUnix", now.timeIntervalSince1970 - 6), ("updatedAtUnix", now.timeIntervalSince1970 + 6)] {
            var changed = valid; changed[key] = wrong
            try JSONSerialization.data(withJSONObject: changed).write(to: url)
            connection.readAcknowledgment(now: now)
            XCTAssertFalse(connection.hasRenderAcknowledgment, key)
        }
        try Data(repeating: 32, count: UnityPresentationConnection.maximumBytes + 1).write(to: url)
        connection.readAcknowledgment(now: now)
        XCTAssertFalse(connection.hasRenderAcknowledgment)
        await store.shutdownAssistant()
    }

    @MainActor func testSuspendHideAndStopRetirePresentation() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let store = fixture.store, connection = store.unityPresentation
        try connection.beginPublishing(store: store, directory: fixture.directory)
        connection.setSuspended(true, store: store)
        XCTAssertFalse(try XCTUnwrap(connection.lastSnapshot).active)
        connection.setSuspended(false, store: store)
        XCTAssertTrue(try XCTUnwrap(connection.lastSnapshot).active)
        store.isVisible = false
        try connection.publish(store: store)
        XCTAssertFalse(try XCTUnwrap(connection.lastSnapshot).visible)
        // Stop remains a complete presentation boundary even when queued source
        // notifications arrive afterward; native identity/evolution is unchanged.
        connection.stop()
        store.preferences.quiet = true
        connection.refresh(store: store)
        XCTAssertFalse(connection.isSharing)
        XCTAssertEqual(store.activeQiMon?.originDigest, String(repeating: "a", count: 64))
        await store.shutdownAssistant()
    }

    @MainActor func testProtoExpressionPreservesIdentitySeedGrowthAndExplicitPreferenceSave() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let store = fixture.store
        let profile = try Data(contentsOf: fixture.preference)
        let identity = store.activeQiMon?.originDigest, revision = store.evolution.revision
        let history = store.evolution.history, placement = store.placementRevision
        let seed = try XCTUnwrap(CompanionPresenceArt.png(form: .kinSeed, family: nil))
        store.preferences.visualTreatment = .protoStudy
        XCTAssertEqual(store.activeQiMon?.originDigest, identity)
        XCTAssertEqual(store.evolution.revision, revision); XCTAssertEqual(store.evolution.history, history)
        XCTAssertEqual(store.placementRevision, placement)
        XCTAssertEqual(store.presentationForm, .kinSeed); XCTAssertEqual(store.cursorPresentationForm, .kinSeed)
        XCTAssertEqual(try Data(contentsOf: fixture.preference), profile)
        XCTAssertEqual(seed, CompanionPresenceArt.png(form: .kinSeed, family: nil, treatment: .protoStudy))
        XCTAssertEqual(CompanionVisualAsset.appearanceID(form: .kinSeed, family: nil, treatment: .original),
            CompanionVisualAsset.appearanceID(form: .kinSeed, family: nil, treatment: .protoStudy))
        XCTAssertNotNil(CompanionVisualAsset.protoImage)
        XCTAssertNotEqual(CompanionPresenceArt.png(form: .kin, family: nil),
            CompanionPresenceArt.png(form: .kin, family: nil, treatment: .protoStudy))
        let request = try retainLessonUse(store)
        XCTAssertTrue(store.previewKinGrowth(receiptID: request)); XCTAssertTrue(store.keepKinGrowth())
        let snapshot = try XCTUnwrap(UnityPresentationSnapshot.capture(store: store, sessionID: UUID(),
            revision: 1, active: true, now: Date(), systemReduceMotion: false))
        XCTAssertEqual(snapshot.appearance, "proto"); XCTAssertEqual(snapshot.bodyAssetSHA256, CompanionVisualAsset.protoDigest)
        XCTAssertEqual(snapshot.seedAssetSHA256, CompanionVisualAsset.kinSeedDigest)
        XCTAssertTrue(CompanionVisualAsset.label(form: .kin, family: nil, treatment: .protoStudy).contains("Proto"))
        store.rememberPreferences = true; store.savePreferences()
        let reopened = CompanionStore(preferenceURL: fixture.preference, allowsPlay: false)
        XCTAssertEqual(reopened.preferences.visualTreatment, .protoStudy)
        XCTAssertEqual(reopened.activeQiMon?.originDigest, identity)
        await reopened.shutdownAssistant(); await store.shutdownAssistant()
    }

    @MainActor func testMissingIdentityCannotPublishOrOpenOldPlayer() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"), allowsPlay: false)
        XCTAssertThrowsError(try store.unityPresentation.beginPublishing(store: store, directory: directory))
        XCTAssertFalse(store.unityPresentation.isSharing)
        XCTAssertNil(UnityPresentationSnapshot.capture(store: store, sessionID: UUID(), revision: 1,
            active: true, now: Date(), systemReduceMotion: false))
        XCTAssertFalse(UnityPresentationConnection.isCompatiblePlayer(directory))
        await store.shutdownAssistant()
    }

    @MainActor private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("unity-presentation-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let preference = directory.appendingPathComponent("preferences.json")
        let kin = LocalQiMon(character: .kin, originDigest: String(repeating: "a", count: 64), welcomedAt: Date())
        let lesson = KeptLesson(topic: "Writing plans", text: "Begin with a short outline and one next step.", createdAt: Date())
        try NativePreferenceDocument(preferences: CompanionPreferences(), lessons: [lesson], qiMon: kin).encoded().write(to: preference)
        return Fixture(directory: directory, preference: preference,
                       store: CompanionStore(preferenceURL: preference, allowsPlay: false))
    }

    @MainActor private func retainLessonUse(_ store: CompanionStore) throws -> UUID {
        let id = UUID(), snapshot = LessonSnapshot(lesson: try XCTUnwrap(store.keptLessons.first))
        let source = String(repeating: "b", count: 64)
        var receipt = AssistantLaneReceipt(requestID: id.uuidString, route: .local, provider: .qwen,
            context: store.contextTicket(), inputDigest: String(repeating: "c", count: 64), sourceDigest: source,
            inputContract: "native-assistant-input/v4", deadline: .distantFuture,
            modelIdentity: "synthetic-unity-projection", state: .complete)
        receipt.localLessons = [snapshot]; receipt.usedLessonIDs = [snapshot.modelID]
        XCTAssertTrue(store.evolution.markUseful(receipt: receipt, sourceDigest: source, confirmedLesson: snapshot))
        return id
    }

    @MainActor private struct Fixture {
        let directory: URL
        let preference: URL
        let store: CompanionStore
        func clean() { store.unityPresentation.stop(); try? FileManager.default.removeItem(at: directory) }
    }
}
