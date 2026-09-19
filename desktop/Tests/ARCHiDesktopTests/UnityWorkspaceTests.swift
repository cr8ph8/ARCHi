import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class UnityWorkspaceTests: XCTestCase {
    @MainActor
    func testNativeUnityAreaLayoutPreservesProfileAndDoesNotOpenPlayer() async throws {
        guard ProcessInfo.processInfo.environment["ARCHI_UNITY_AREA_NATIVE"] == "1" else {
            throw XCTSkip("Set ARCHI_UNITY_AREA_NATIVE=1 for disposable native Unity Area layout evidence.")
        }
        let fixture = try UnityAreaFixture()
        defer { fixture.clean() }
        let original = try Data(contentsOf: fixture.profile)
        let application = NSApplication.shared, priorPolicy = application.activationPolicy()
        let previousApp = NSWorkspace.shared.frontmostApplication
        _ = application.setActivationPolicy(.accessory); application.finishLaunching()
        defer {
            _ = application.setActivationPolicy(priorPolicy)
            if previousApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp?.activate(options: []) }
        }
        let panel = NSPanel(contentRect: CGRect(x: 80, y: 80, width: 1100, height: 780),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.title = "ARCHi · synthetic Unity Area"
        defer { panel.contentView = nil; panel.close() }
        let output = ProcessInfo.processInfo.environment["ARCHI_UNITY_AREA_RENDER_DIR"].map { URL(fileURLWithPath: $0) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        for (width, dark) in [(1100.0, true), (630.0, false)] {
            let hosting = NSHostingView(rootView: UnityWorkspace(store: fixture.store)
                .frame(width: width, height: 780).preferredColorScheme(dark ? .dark : .light)
                .background(dark ? WorkspaceTheme.background : Color(nsColor: .windowBackgroundColor)))
            panel.setContentSize(NSSize(width: width, height: 780)); panel.contentView = hosting
            panel.makeKeyAndOrderFront(nil); application.activate(ignoringOtherApps: true)
            try await Task.sleep(for: .milliseconds(500))
            hosting.layoutSubtreeIfNeeded()
            if let output {
                let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: output.appendingPathComponent("unity-area-\(Int(width))-\(dark ? "dark" : "light").png"))
            }
            XCTAssertFalse(fixture.store.unityPresentation.isSharing)
            XCTAssertNil(fixture.store.unityPresentation.snapshotURL)
            XCTAssertEqual(try Data(contentsOf: fixture.profile), original)
        }
        await fixture.store.shutdownAssistant()
    }

    @MainActor
    func testWorkspaceConstructionAndReadbackNeverStartAPresentation() async throws {
        let fixture = try UnityAreaFixture()
        defer { fixture.clean() }
        let original = try Data(contentsOf: fixture.profile)
        let connection = fixture.store.unityPresentation
        let view = UnityWorkspace(store: fixture.store)
        _ = view.body
        _ = connection.availablePlayer
        XCTAssertFalse(UnityWorkspaceState(connection: connection).isFollowing)
        XCTAssertFalse(connection.isSharing)
        XCTAssertNil(connection.snapshotURL)
        XCTAssertNil(connection.lastSnapshot)
        XCTAssertEqual(try Data(contentsOf: fixture.profile), original)
        await fixture.store.shutdownAssistant()
    }

    @MainActor
    func testWorkspaceReadbackRequiresLiveVisibleCurrentAcknowledgment() async throws {
        let fixture = try UnityAreaFixture()
        defer { fixture.clean() }
        let store = fixture.store, connection = store.unityPresentation
        try connection.beginPublishing(store: store, directory: fixture.directory)
        XCTAssertFalse(UnityWorkspaceState(connection: connection).isFollowing)
        let first = try XCTUnwrap(connection.lastSnapshot)
        let ackURL = try XCTUnwrap(connection.snapshotURL).appendingPathExtension("ack")
        try acknowledgment(first).write(to: ackURL)
        connection.readAcknowledgment()
        XCTAssertTrue(UnityWorkspaceState(connection: connection).isFollowing)

        store.preferences.equipment = CompanionEquipment(hand: .focusStaff, design: .creatorDefault)
        try connection.publish(store: store)
        XCTAssertFalse(UnityWorkspaceState(connection: connection).isFollowing)
        let changed = try XCTUnwrap(connection.lastSnapshot)
        try acknowledgment(changed).write(to: ackURL)
        connection.readAcknowledgment()
        XCTAssertTrue(UnityWorkspaceState(connection: connection).isFollowing)
        store.isVisible = false
        try connection.publish(store: store)
        let hidden = try XCTUnwrap(connection.lastSnapshot)
        try acknowledgment(hidden).write(to: ackURL)
        connection.readAcknowledgment()
        XCTAssertFalse(UnityWorkspaceState(connection: connection).isFollowing)
        connection.stop()
        XCTAssertFalse(UnityWorkspaceState(connection: connection).isFollowing)
        XCTAssertEqual(store.activeQiMon?.originDigest, first.originDigest)
        XCTAssertEqual(store.cursorPresentationForm, .kinSeed)
        await store.shutdownAssistant()
    }

    @MainActor
    func testAllStaffRecipesProjectOnlyClosedVisualInputsAndRequireMatchingAcknowledgment() async throws {
        let fixture = try UnityAreaFixture()
        defer { fixture.clean() }
        let now = Date(), session = UUID()
        for palette in CompanionItemPackage.Palette.allCases {
            for crown in CompanionItemPackage.Crown.allCases {
                let design = CompanionItemPackage(title: "PRIVATE STAFF", creator: "PRIVATE CREATOR",
                    summary: "PRIVATE NOTES", palette: palette, crown: crown, action: .decoration)
                fixture.store.preferences.equipment = CompanionEquipment(hand: .focusStaff, design: design)
                let value = try XCTUnwrap(UnityPresentationSnapshot.capture(store: fixture.store, sessionID: session,
                    revision: 1, active: true, now: now, systemReduceMotion: false))
                XCTAssertTrue(value.equippedFocusStaff)
                XCTAssertEqual(value.staffPalette, palette.rawValue)
                XCTAssertEqual(value.staffCrown, crown.rawValue)
                let text = try XCTUnwrap(String(data: JSONEncoder().encode(value), encoding: .utf8))
                XCTAssertFalse(text.contains("PRIVATE"))
                XCTAssertFalse(text.contains("decoration"))
                var ack = try XCTUnwrap(JSONSerialization.jsonObject(with: acknowledgment(value)) as? [String: Any])
                let accepted = try JSONDecoder().decode(UnityPresentationAcknowledgment.self, from: JSONSerialization.data(withJSONObject: ack))
                XCTAssertTrue(accepted.matches(value, now: now))
                ack.removeValue(forKey: "staffPalette"); ack.removeValue(forKey: "staffCrown")
                let oldPlayer = try JSONDecoder().decode(UnityPresentationAcknowledgment.self, from: JSONSerialization.data(withJSONObject: ack))
                XCTAssertFalse(oldPlayer.matches(value, now: now), "An older player cannot attest to a creator design")
                ack["staffPalette"] = "unknown"; ack["staffCrown"] = crown.rawValue
                let wrong = try JSONDecoder().decode(UnityPresentationAcknowledgment.self, from: JSONSerialization.data(withJSONObject: ack))
                XCTAssertFalse(wrong.matches(value, now: now))
            }
        }
        await fixture.store.shutdownAssistant()
    }

    @MainActor
    func testOldPlayerKeepsBaseCompatibilityButCannotOpenCreatorDesign() async throws {
        let fixture = try UnityAreaFixture()
        defer { fixture.clean() }
        let old = try fixture.player(recipeVersion: nil, name: "Old")
        let updated = try fixture.player(recipeVersion: 1, name: "Updated")
        XCTAssertTrue(UnityPresentationConnection.isCompatiblePlayer(old))
        XCTAssertFalse(UnityPresentationConnection.supportsStaffRecipes(old))
        XCTAssertTrue(UnityPresentationConnection.supportsStaffRecipes(updated))
        fixture.store.preferences.equipment = CompanionEquipment(hand: .focusStaff, design: .creatorDefault)
        let connection = UnityPresentationConnection(launchApplication: { _, _ in
            XCTFail("An older player cannot launch with an unsupported design")
            throw CocoaError(.featureUnsupported)
        })
        XCTAssertTrue(connection.selectPlayer(old))
        await connection.open(store: fixture.store)
        XCTAssertFalse(connection.isSharing)
        XCTAssertNil(connection.snapshotURL)
        XCTAssertTrue(connection.status.contains("update"))
        await fixture.store.shutdownAssistant()
    }

    @MainActor
    func testInvalidEquipmentCannotEnterTheProjection() async throws {
        let fixture = try UnityAreaFixture()
        defer { fixture.clean() }
        fixture.store.preferences.equipment = CompanionEquipment(hand: .focusStaff,
            design: CompanionItemPackage(title: "", creator: "Creator", summary: "Invalid"))
        let value = try XCTUnwrap(UnityPresentationSnapshot.capture(store: fixture.store, sessionID: UUID(),
            revision: 1, active: true, now: Date(), systemReduceMotion: false))
        XCTAssertFalse(value.equippedFocusStaff)
        XCTAssertNil(value.staffPalette)
        XCTAssertNil(value.staffCrown)
        await fixture.store.shutdownAssistant()
    }

    private func acknowledgment(_ snapshot: UnityPresentationSnapshot) throws -> Data {
        var result: [String: Any] = ["schemaVersion": 1, "sessionID": snapshot.sessionID,
            "originDigest": snapshot.originDigest, "revision": snapshot.revision,
            "updatedAtUnix": snapshot.updatedAtUnix, "active": snapshot.active,
            "body": snapshot.body, "appearance": snapshot.appearance, "renderer": "unity-companion"]
        result["staffPalette"] = snapshot.staffPalette; result["staffCrown"] = snapshot.staffCrown
        return try JSONSerialization.data(withJSONObject: result)
    }
}

@MainActor private struct UnityAreaFixture {
    let directory: URL
    let profile: URL
    let store: CompanionStore

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("unity-area-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        profile = directory.appendingPathComponent("profile.json")
        let kin = LocalQiMon(character: .kin, originDigest: String(repeating: "a", count: 64), welcomedAt: Date())
        try NativePreferenceDocument(preferences: CompanionPreferences(), qiMon: kin).encoded().write(to: profile)
        store = CompanionStore(preferenceURL: profile, allowsPlay: false)
    }

    func player(recipeVersion: Int?, name: String) throws -> URL {
        let player = directory.appendingPathComponent(name + ".app")
        let contents = player.appendingPathComponent("Contents"), executables = contents.appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(at: executables, withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": "local.archi.unityport", "CFBundleExecutable": name,
            "CFBundlePackageType": "APPL", "ARCHiNativePresentationProtocol": 1]
        info["ARCHiNativeStaffRecipeVersion"] = recipeVersion
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let executable = executables.appendingPathComponent(name)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return player
    }

    func clean() { store.unityPresentation.stop(); try? FileManager.default.removeItem(at: directory) }
}
