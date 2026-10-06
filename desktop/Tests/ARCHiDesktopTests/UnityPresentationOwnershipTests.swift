import AppKit
import Darwin
import XCTest
@testable import ARCHiDesktop

final class UnityPresentationOwnershipTests: XCTestCase {
    @MainActor
    func testLateLaunchFailureCannotChangeStoppedOrReplacementSession() async throws {
        for startsReplacement in [false, true] {
            let fixture = try OwnershipFixture()
            defer { fixture.clean() }
            let launcher = DeferredUnityLaunch()
            defer { launcher.fail() }
            let connection = UnityPresentationConnection(launchApplication: { _, _ in try await launcher.launch() })
            defer { connection.stop() }
            XCTAssertTrue(connection.selectPlayer(fixture.player))
            let opening = Task { await connection.open(store: fixture.store) }
            try await waitForLaunch(launcher)
            let firstURL = try XCTUnwrap(connection.snapshotURL)
            defer { try? FileManager.default.removeItem(at: firstURL.deletingLastPathComponent()) }
            let first = try XCTUnwrap(connection.lastSnapshot)
            connection.stop()
            if startsReplacement { try connection.beginPublishing(store: fixture.store, directory: fixture.directory) }
            let expectedStatus = connection.status, expectedSnapshot = connection.lastSnapshot
            launcher.fail()
            await opening.value
            XCTAssertEqual(connection.isSharing, startsReplacement)
            XCTAssertEqual(connection.status, expectedStatus, "An older launch cannot replace current status")
            XCTAssertEqual(connection.lastSnapshot, expectedSnapshot)
            if startsReplacement {
                let replacement = try XCTUnwrap(connection.lastSnapshot)
                XCTAssertNotEqual(replacement.sessionID, first.sessionID)
                let bytes = try Data(contentsOf: XCTUnwrap(connection.snapshotURL))
                XCTAssertTrue(try JSONDecoder().decode(UnityPresentationSnapshot.self, from: bytes).active)
            }
            XCTAssertEqual(fixture.store.cursorPresentationForm, .kinSeed)
            XCTAssertEqual(fixture.assistant.calls, 0)
            await fixture.store.shutdownAssistant()
        }
    }

    @MainActor
    func testCurrentLaunchFailureStillStopsItsOwnPublication() async throws {
        let fixture = try OwnershipFixture()
        defer { fixture.clean() }
        let launcher = DeferredUnityLaunch()
        defer { launcher.fail() }
        let connection = UnityPresentationConnection(launchApplication: { _, _ in try await launcher.launch() })
        defer { connection.stop() }
        XCTAssertTrue(connection.selectPlayer(fixture.player))
        let opening = Task { await connection.open(store: fixture.store) }
        try await waitForLaunch(launcher)
        let url = try XCTUnwrap(connection.snapshotURL)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        launcher.fail()
        await opening.value
        XCTAssertFalse(connection.isSharing)
        XCTAssertTrue(connection.status.contains("Synthetic launch failure"))
        let retired = try JSONDecoder().decode(UnityPresentationSnapshot.self, from: Data(contentsOf: url))
        XCTAssertFalse(retired.active)
        XCTAssertFalse(retired.visible)
        XCTAssertEqual(retired.activity, "stopped")
        await fixture.store.shutdownAssistant()
    }

    @MainActor
    func testChangedPresentationImmediatelyInvalidatesOldAcknowledgmentAndHeartbeatCanCatchUp() async throws {
        let fixture = try OwnershipFixture()
        defer { fixture.clean() }
        let connection = fixture.store.unityPresentation
        try connection.beginPublishing(store: fixture.store, directory: fixture.directory)
        let url = try XCTUnwrap(connection.snapshotURL).appendingPathExtension("ack")
        let first = try XCTUnwrap(connection.lastSnapshot)
        try acknowledgment(first).write(to: url)
        connection.readAcknowledgment()
        XCTAssertTrue(connection.hasRenderAcknowledgment)

        fixture.store.preferences.quiet = true
        try connection.publish(store: fixture.store)
        XCTAssertFalse(connection.hasRenderAcknowledgment, "A previous presentation ACK cannot attest to changed quiet/light state")
        XCTAssertTrue(connection.status.contains("waiting"))
        let changed = try XCTUnwrap(connection.lastSnapshot)
        XCTAssertTrue(changed.quiet)
        try acknowledgment(changed).write(to: url)
        try connection.publish(store: fixture.store)
        XCTAssertTrue(connection.hasRenderAcknowledgment, "One heartbeat of lag is allowed only for identical presentation")

        fixture.store.isVisible = false
        try connection.publish(store: fixture.store)
        XCTAssertFalse(connection.hasRenderAcknowledgment)
        XCTAssertFalse(try XCTUnwrap(connection.lastSnapshot).active)
        await fixture.store.shutdownAssistant()
    }

    @MainActor
    func testAcknowledgmentRejectsSymlinkFIFOEmptyAndOversizedEntriesThenRecovers() async throws {
        let fixture = try OwnershipFixture()
        defer { fixture.clean() }
        let connection = fixture.store.unityPresentation
        try connection.beginPublishing(store: fixture.store, directory: fixture.directory)
        let snapshot = try XCTUnwrap(connection.lastSnapshot)
        let url = try XCTUnwrap(connection.snapshotURL).appendingPathExtension("ack")
        let valid = try acknowledgment(snapshot)
        let other = fixture.directory.appendingPathComponent("other-ack.json")
        try valid.write(to: other)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: other)
        connection.readAcknowledgment()
        XCTAssertFalse(connection.hasRenderAcknowledgment)
        XCTAssertEqual(try Data(contentsOf: other), valid)
        try FileManager.default.removeItem(at: url)

        XCTAssertEqual(url.path.withCString { Darwin.mkfifo($0, 0o600) }, 0)
        connection.readAcknowledgment() // Must return without waiting for a FIFO writer.
        XCTAssertFalse(connection.hasRenderAcknowledgment)
        try FileManager.default.removeItem(at: url)
        for bytes in [Data(), Data(repeating: 32, count: UnityPresentationConnection.maximumBytes + 1)] {
            try bytes.write(to: url)
            connection.readAcknowledgment()
            XCTAssertFalse(connection.hasRenderAcknowledgment)
        }
        try valid.write(to: url)
        connection.readAcknowledgment()
        XCTAssertTrue(connection.hasRenderAcknowledgment)
        await fixture.store.shutdownAssistant()
    }

    @MainActor private func waitForLaunch(_ launcher: DeferredUnityLaunch) async throws {
        for _ in 0..<500 {
            if launcher.isPending { return }
            await Task.yield()
        }
        XCTFail("Synthetic launch did not start")
        throw OwnershipFailure.launch
    }

    private func acknowledgment(_ snapshot: UnityPresentationSnapshot) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "sessionID": snapshot.sessionID,
            "originDigest": snapshot.originDigest, "revision": snapshot.revision,
            "updatedAtUnix": Date().timeIntervalSince1970, "active": snapshot.active,
            "body": snapshot.body, "appearance": snapshot.appearance, "renderer": "unity-companion"])
    }
}

private enum OwnershipFailure: Error, LocalizedError {
    case launch
    var errorDescription: String? { "Synthetic launch failure" }
}

@MainActor private final class DeferredUnityLaunch {
    private var continuation: CheckedContinuation<NSRunningApplication, any Error>?
    var isPending: Bool { continuation != nil }
    func launch() async throws -> NSRunningApplication {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func fail() {
        let pending = continuation; continuation = nil
        pending?.resume(throwing: OwnershipFailure.launch)
    }
}

@MainActor private struct OwnershipFixture {
    let directory: URL
    let player: URL
    let store: CompanionStore
    let assistant: OwnershipAssistant

    init() throws {
        let client = OwnershipAssistant()
        assistant = client
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("unity-owner-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        player = directory.appendingPathComponent("Fixture.app")
        let contents = player.appendingPathComponent("Contents"), executables = contents.appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(at: executables, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "local.archi.unityport", "CFBundleExecutable": "Fixture",
                                  "CFBundlePackageType": "APPL", "ARCHiNativePresentationProtocol": 1]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let executable = executables.appendingPathComponent("Fixture")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let profile = directory.appendingPathComponent("profile.json")
        let kin = LocalQiMon(character: .kin, originDigest: String(repeating: "a", count: 64), welcomedAt: Date())
        try NativePreferenceDocument(preferences: CompanionPreferences(), qiMon: kin).encoded().write(to: profile)
        store = CompanionStore(preferenceURL: profile, assistant: client, allowsPlay: false)
    }

    func clean() { store.unityPresentation.stop(); try? FileManager.default.removeItem(at: directory) }
}

@MainActor private final class OwnershipAssistant: AssistantClient {
    var calls = 0
    func connect() async throws { calls += 1 }
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws { calls += 1 }
}
