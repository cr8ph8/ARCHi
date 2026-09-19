import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class SeedAppearanceRenderingTests: XCTestCase {
    @MainActor
    func testPrimarySeedsUseDistinctVerifiedArtAndTheExistingSnapshotPath() throws {
        XCTAssertNotNil(CompanionVisualAsset.lightSeedImage)
        XCTAssertNotNil(CompanionVisualAsset.kinSeedImage)
        let light = try XCTUnwrap(CompanionPresenceArt.png(form: .corePearl, family: nil))
        let particles = try XCTUnwrap(CompanionPresenceArt.png(form: .particleSeed, family: nil))
        let kin = try XCTUnwrap(CompanionPresenceArt.png(form: .kinSeed, family: nil))
        XCTAssertNotEqual(light, particles)
        XCTAssertTrue(try NaturalPresentationComparison.compare(particles, kin).withinAlphaPresentationBound)
        for data in [light, particles] {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
            XCTAssertEqual(bitmap.pixelsWide, 512)
            XCTAssertEqual(bitmap.pixelsHigh, 512)
            XCTAssertTrue(bitmap.hasAlpha)
            XCTAssertLessThan(data.count, CompanionVisualAsset.maximumBytes)
            XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0.01)
            XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 256, y: 256)).alphaComponent, 0.9)
        }
        if let directory = ProcessInfo.processInfo.environment["ARCHI_SEED_REVIEW_DIR"] {
            let url = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try light.write(to: url.appendingPathComponent("desktop-ball-of-light.png"))
            try particles.write(to: url.appendingPathComponent("desktop-particle-seed.png"))
            let store = CompanionStore(preferenceURL: url.appendingPathComponent("unused-test-preferences.json"))
            store.chooseSeedAppearance(.archiLight)
            for dark in [false, true] {
                let renderer = ImageRenderer(content: SeedAppearanceCard(store: store).padding(24).frame(width: 660)
                    .background(dark ? Color(red: 0.045, green: 0.06, blue: 0.065) : Color.white)
                    .environment(\.colorScheme, dark ? .dark : .light))
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.nsImage)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: url.appendingPathComponent(dark ? "appearance-dark.png" : "appearance-light.png"))
            }
        }
    }

    func testOlderPreferencesRetainTheirSeedLook() throws {
        let original = CompanionPreferences()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "seedAppearance")
        let decoded = try JSONDecoder().decode(CompanionPreferences.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.seedAppearance, .kinParticles)
        XCTAssertEqual(decoded.form, original.form)
        var updated = decoded
        updated.seedAppearance = .archiLight
        XCTAssertEqual(try JSONDecoder().decode(CompanionPreferences.self, from: JSONEncoder().encode(updated)), updated)
    }
}
