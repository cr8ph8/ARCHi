import Foundation
import XCTest
@testable import ARCHiDesktop

final class OrbPresentationTests: XCTestCase {
    func testClosedCommandsDoNotInterpretUnknownQuestionsOrExecutableInputs() {
        XCTAssertEqual(OrbCommand.parse("Make this room Minecraft!"), .theme(.voxel))
        XCTAssertEqual(OrbCommand.parse("make this room cyberpunk"), .theme(.neon))
        XCTAssertEqual(OrbCommand.parse("show my memories"), .memory)
        XCTAssertEqual(OrbCommand.parse("open QiMon"), .qimon)
        XCTAssertEqual(OrbCommand.parse("follow me"), .anchor(.follow))
        XCTAssertNil(OrbCommand.parse("What does QiMon mean?"))
        XCTAssertNil(OrbCommand.parse("make this room https://external-shader"))
        XCTAssertNil(OrbCommand.parse("save a memory"))
        XCTAssertNil(OrbCommand.parse(String(repeating: "x", count: 513)))
    }

    @MainActor func testOrbReusesIdentityAndNeverExportsPrivateAssistantTextOrWritesPreferences() async throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let before = try Data(contentsOf: fixture.profile)
        let connection = fixture.store.unityPresentation
        try connection.beginPublishing(store: fixture.store, directory: fixture.root, orb: UnityOrbPresentation(theme: .voxel))
        let snapshot = try XCTUnwrap(connection.lastSnapshot)
        XCTAssertEqual(snapshot.originDigest, fixture.store.activeQiMon?.originDigest)
        XCTAssertEqual(snapshot.orb?.theme, .voxel)
        XCTAssertEqual(snapshot.body, "seed")
        XCTAssertEqual(snapshot.cursor, "seed")
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(snapshot), encoding: .utf8))
        XCTAssertFalse(json.contains("PRIVATE"))
        XCTAssertNil(snapshot.pointPresentation, "Orb mode does not duplicate the knowledge projection")
        XCTAssertEqual(try Data(contentsOf: fixture.profile), before)
        XCTAssertTrue(connection.handleOrbCommand("make this room fantasy", store: fixture.store))
        XCTAssertEqual(connection.lastSnapshot?.orb?.theme, .fantasy)
        XCTAssertEqual(try Data(contentsOf: fixture.profile), before)
        XCTAssertFalse(connection.handleOrbCommand("save a memory", store: fixture.store))
        connection.stop()
        XCTAssertNil(connection.orbPresentation)
        XCTAssertFalse(connection.handleOrbCommand("make this room neon", store: fixture.store))
        await fixture.store.shutdownAssistant()
    }

    @MainActor func testRendererMustAcknowledgeTheExactOrbDescriptorAndItsWithdrawal() async throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let now = Date()
        var snapshot = try XCTUnwrap(UnityPresentationSnapshot.capture(store: fixture.store,
            sessionID: UUID(), revision: 1, active: true, now: now, systemReduceMotion: false))
        var ack = UnityPresentationAcknowledgment(schemaVersion: 1, sessionID: snapshot.sessionID,
            originDigest: snapshot.originDigest, revision: snapshot.revision, updatedAtUnix: now.timeIntervalSince1970,
            active: snapshot.active, body: snapshot.body, appearance: snapshot.appearance,
            staffPalette: snapshot.staffPalette, staffCrown: snapshot.staffCrown, renderer: "unity-companion")
        XCTAssertTrue(ack.matches(snapshot, now: now))
        let legacy = snapshot
        snapshot.orb = UnityOrbPresentation(theme: .neon)
        XCTAssertFalse(snapshot.hasSamePresentation(as: legacy))
        XCTAssertFalse(ack.matches(snapshot, now: now))
        ack.orb = snapshot.orb
        XCTAssertTrue(ack.matches(snapshot, now: now))
        ack.orb?.theme = .voxel
        XCTAssertFalse(ack.matches(snapshot, now: now))
        ack.orb = snapshot.orb; ack.orb?.speaking = true
        XCTAssertFalse(ack.matches(snapshot, now: now))
        ack.orb = snapshot.orb; snapshot.orb = nil
        XCTAssertFalse(ack.matches(snapshot, now: now), "An old orb ACK cannot acknowledge return to the original body view")
        await fixture.store.shutdownAssistant()
    }

    @MainActor func testRequestsAreBoundToTheCurrentSessionRevisionAndMonotonicSequence() async throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let now = Date()
        var snapshot = try XCTUnwrap(UnityPresentationSnapshot.capture(store: fixture.store,
            sessionID: UUID(), revision: 5, active: true, now: now, systemReduceMotion: false))
        snapshot.orb = UnityOrbPresentation()
        func request(_ changes: [String: Any] = [:]) throws -> UnityOrbActionRequest {
            var wire: [String: Any] = ["schemaVersion": 1, "sessionID": snapshot.sessionID,
                "originDigest": snapshot.originDigest, "revision": snapshot.revision, "sequence": 1,
                "updatedAtUnix": now.timeIntervalSince1970, "action": "theme", "value": "neon"]
            wire.merge(changes) { _, new in new }
            return try JSONDecoder().decode(UnityOrbActionRequest.self, from: JSONSerialization.data(withJSONObject: wire))
        }
        let good = try request()
        XCTAssertEqual(good.resolve(matching: [snapshot], after: 0, now: now), .theme(.neon))
        XCTAssertNil(good.resolve(matching: [snapshot], after: 1, now: now))
        XCTAssertNil(good.resolve(matching: [snapshot], after: 0, now: now.addingTimeInterval(6)))
        let invalid: [[String: Any]] = [["sessionID": UUID().uuidString], ["originDigest": String(repeating: "b", count: 64)],
            ["revision": 4], ["sequence": 0], ["schemaVersion": 2], ["value": "external"], ["action": "write-memory"]]
        for change in invalid {
            XCTAssertNil(try request(change).resolve(matching: [snapshot], after: 0, now: now))
        }
        // Snapshot identity/activity fields are immutable. Decode the synthetic
        // wire variants instead of making production projections mutable for tests.
        var snapshotWire = try XCTUnwrap(JSONSerialization.jsonObject(with:
            JSONEncoder().encode(snapshot)) as? [String: Any])
        snapshotWire["active"] = false
        let inactive = try JSONDecoder().decode(UnityPresentationSnapshot.self,
            from: JSONSerialization.data(withJSONObject: snapshotWire))
        XCTAssertNil(good.resolve(matching: [inactive], after: 0, now: now))
        snapshotWire["active"] = true
        snapshotWire["visible"] = false
        let hidden = try JSONDecoder().decode(UnityPresentationSnapshot.self,
            from: JSONSerialization.data(withJSONObject: snapshotWire))
        XCTAssertNil(good.resolve(matching: [hidden], after: 0, now: now))
        await fixture.store.shutdownAssistant()
    }

    @MainActor func testAPracticeOnlySessionCannotClaimTheCompanionOrb() async throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let empty = CompanionStore(preferenceURL: fixture.root.appendingPathComponent("empty.json"), allowsPlay: false)
        XCTAssertThrowsError(try empty.unityPresentation.beginPublishing(store: empty,
            directory: fixture.root, destination: .arena, orb: UnityOrbPresentation()))
        XCTAssertFalse(empty.unityPresentation.isSharing)
        XCTAssertNil(empty.activeQiMon)
        await empty.shutdownAssistant(); await fixture.store.shutdownAssistant()
    }

    @MainActor private struct Fixture {
        let root: URL, profile: URL
        let store: CompanionStore
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("archi-orb-tests-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            profile = root.appendingPathComponent("preferences.json")
            var preferences = CompanionPreferences(); preferences.quiet = true; preferences.reduceMotion = true
            let kin = LocalQiMon(character: .kin, originDigest: String(repeating: "a", count: 64), welcomedAt: Date())
            try NativePreferenceDocument(preferences: preferences, qiMon: kin).encoded().write(to: profile)
            store = CompanionStore(preferenceURL: profile, allowsPlay: false)
            store.prompt = "PRIVATE QUESTION"; store.sharedText = "PRIVATE DOCUMENT"; store.reply = "PRIVATE REPLY"
        }
        func clean() { store.unityPresentation.stop(); try? FileManager.default.removeItem(at: root) }
    }
}
