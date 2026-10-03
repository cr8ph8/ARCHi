import AppKit
import XCTest
@testable import ARCHiDesktop

final class CompanionPresentationStyleTests: XCTestCase {
    @MainActor func testThreeStylesPreserveIdentityAndExplicitPoseRoundTrips() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("preferences.json")
        let identity = LocalQiMon(character: .hampton, originDigest: String(repeating: "b", count: 64), welcomedAt: Date())
        try NativePreferenceDocument(preferences: CompanionPreferences(), qiMon: identity).encoded().write(to: url)
        let store = CompanionStore(preferenceURL: url, allowsPlay: false)
        let baseline = try Data(contentsOf: url)
        for style in CompanionPresentationStyle.allCases {
            store.chooseCompanionPresentationStyle(style)
            XCTAssertEqual(store.companionPresentationStyle, style)
            XCTAssertEqual(store.companionPresentationPose, .seed)
            XCTAssertEqual(store.cursorPresentationForm, style.seedAppearance.personalForm)
            XCTAssertEqual(store.activeQiMon, identity)
            XCTAssertNil(store.evolution.kinGrowthRecord)
            XCTAssertEqual(try Data(contentsOf: url), baseline)
            let copy = try JSONDecoder().decode(CompanionPreferences.self, from: JSONEncoder().encode(store.preferences))
            XCTAssertEqual(copy, store.preferences)
            if style != .liminal {
                store.preferences.companionPose = .body
                XCTAssertEqual(store.presentationForm, .kin)
                XCTAssertEqual(store.cursorPresentationForm, style.seedAppearance.personalForm)
                store.chooseCompanionPresentationStyle(style)
                XCTAssertEqual(store.companionPresentationPose, .body, "Reselecting a style must not collapse its body")
            }
        }
    }

    func testOldAppearancesDecodeWithoutSilentMigration() throws {
        for appearance in CompanionSeedAppearance.allCases {
            var preferences = CompanionPreferences(); preferences.seedAppearance = appearance
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as? [String: Any])
            object.removeValue(forKey: "companionPose")
            let restored = try JSONDecoder().decode(CompanionPreferences.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(restored.seedAppearance, appearance)
            XCTAssertNil(restored.companionPose)
        }
        var legacy = CompanionPreferences(); legacy.seedAppearance = .vela
        XCTAssertNil(CompanionPresentationStyle.resolve(legacy))
    }

    @MainActor func testMemoryParticlesKeepAnchorsAcrossPracticeAndAcrossBodyRenders() throws {
        let id = String(repeating: "a", count: 64)
        func snapshot(_ applications: Int) -> LiminalFormDevelopment.Snapshot {
            .init(originDigest: String(repeating: "b", count: 64), nodes: [
                .init(id: id, lessonIDs: ["lesson"], graphNodeIDs: ["lesson:lesson"], title: "Retained lesson", applications: applications)
            ], unavailableLessons: 0, duplicateLessons: 0, evidenceAvailable: true)
        }
        let kept = snapshot(0), used = snapshot(2)
        let a = try XCTUnwrap(CompanionMemoryParticles.anchors(kept).first)
        let b = try XCTUnwrap(CompanionMemoryParticles.anchors(used).first)
        XCTAssertEqual(a.id, b.id); XCTAssertEqual(a.x, b.x); XCTAssertEqual(a.y, b.y)
        XCTAssertEqual(b.applications, 2)
        XCTAssertNotEqual(CompanionMemoryParticles.identity(kept), CompanionMemoryParticles.identity(used))
        for (form, treatment) in [(CompanionForm.corePearl, CompanionVisualTreatment.protoStudy), (.particleSeed, .original), (.kin, .protoStudy), (.hamptonSeed, .original)] {
            let plain = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: nil, treatment: treatment))
            let grown = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: nil, treatment: treatment, memoryDevelopment: used))
            XCTAssertNotEqual(plain, grown, "Real memory projection must reach \(form), not just a card counter")
            let image = try XCTUnwrap(NSBitmapImageRep(data: grown))
            XCTAssertEqual(image.pixelsWide, 512); XCTAssertTrue(image.hasAlpha)
            let original = try XCTUnwrap(NSBitmapImageRep(data: plain))
            // The new layer must preserve the authored center, rather than
            // succeeding by replacing the body with an empty timeline raster.
            XCTAssertEqual(image.colorAt(x: 256, y: 256), original.colorAt(x: 256, y: 256))
            XCTAssertGreaterThan(image.colorAt(x: 256, y: 256)?.alphaComponent ?? 0, 0)
            if let path = ProcessInfo.processInfo.environment["ARCHI_COMPANION_REVIEW_DIR"] {
                let directory = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try grown.write(to: directory.appendingPathComponent("\(form.id)-\(treatment.rawValue)-memory.png"))
            }
        }
    }
}
