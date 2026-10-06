import Foundation
import XCTest
@testable import ARCHiDesktop

final class DesktopApplicationIdentityTests: XCTestCase {
    private typealias Identity = DesktopApplicationIdentity

    func testCanonicalAppKeepsExistingKINProfileWithoutMigration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-app-identity-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let saved = directory.appendingPathComponent("ARCHiDesktopReview/preferences.json")
        try FileManager.default.createDirectory(at: saved.deletingLastPathComponent(), withIntermediateDirectories: true)
        let authored = Data("existing KIN identity and Seed".utf8)
        try authored.write(to: saved)

        XCTAssertEqual(Identity.bundleIdentifier, "com.quotient.archi.desktop.review")
        XCTAssertEqual(Identity.preferenceURL(applicationSupport: directory), saved)
        XCTAssertEqual(try Data(contentsOf: saved), authored)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["ARCHiDesktopReview"])
    }

    func testRepeatedOrSimultaneousCanonicalLaunchesChooseOneOwner() {
        let first = instance(100, Identity.bundleIdentifier, at: 10)
        let second = instance(200, Identity.bundleIdentifier, at: 10)
        XCTAssertEqual(Identity.launchDisposition(currentProcess: 100, instances: [second, first]), .beginSession)
        XCTAssertEqual(Identity.launchDisposition(currentProcess: 200, instances: [first, second]), .reuse(100))
        // Launch time, rather than process number, owns an existing session.
        let older = instance(300, Identity.bundleIdentifier, at: 5)
        XCTAssertEqual(Identity.launchDisposition(currentProcess: 100, instances: [first, older]), .reuse(300))
    }

    func testLegacyPreviewNeedsNormalQuitBeforeCanonicalSessionStarts() {
        let canonical = instance(200, Identity.bundleIdentifier, at: 20)
        let legacy = instance(100, Identity.legacyPreviewIdentifier, at: 10)
        XCTAssertEqual(Identity.launchDisposition(currentProcess: 200, instances: [canonical, legacy]), .reviewLegacy(100))
        let existing = instance(150, Identity.bundleIdentifier, at: 15)
        XCTAssertEqual(Identity.launchDisposition(currentProcess: 200, instances: [legacy, existing, canonical]), .reuse(150))
    }

    func testUnityAndUnrelatedAppsNeverBecomeNativeProfileOwners() {
        let current = instance(200, Identity.bundleIdentifier, at: 20)
        let player = instance(80, "local.archi.unityport", at: 5)
        let other = instance(90, "com.example.other", at: 10)
        XCTAssertEqual(Identity.launchDisposition(currentProcess: 200, instances: [current, player, other]), .beginSession)
    }

    @MainActor
    func testBlockedStartupDoesNotConstructCompanionStoreOrServices() {
        var ownershipChecks = 0
        ARCHiDesktopMain.runDesktop(mayStartSession: {
            ownershipChecks += 1
            return false
        }, makeDelegate: {
            XCTFail("A duplicate launch must exit before constructing the companion/profile owner")
            fatalError("Unexpected personal session creation")
        })
        XCTAssertEqual(ownershipChecks, 1)
    }

    private func instance(_ pid: pid_t, _ bundle: String, at timestamp: TimeInterval) -> Identity.Instance {
        Identity.Instance(processIdentifier: pid, bundleIdentifier: bundle, launchedAt: Date(timeIntervalSince1970: timestamp))
    }
}
