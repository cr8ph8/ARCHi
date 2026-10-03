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
        let graph = CompanionGraphSnapshot(nodes: [
            .init(id: "lesson:lesson", title: "Retained lesson", subtitle: "Current record", kind: .lesson,
                  status: "Retained", details: [], target: .memory)
        ], edges: [], truncatedCount: 0)
        let kept = try XCTUnwrap(CompanionParticleScene.build(originDigest: snapshot(0).originDigest,
            graph: graph, development: snapshot(0)))
        let used = try XCTUnwrap(CompanionParticleScene.build(originDigest: snapshot(2).originDigest,
            graph: graph, development: snapshot(2)))
        let a = try XCTUnwrap(kept.field.particles.first)
        let b = try XCTUnwrap(used.field.particles.first)
        XCTAssertEqual(a.nodeID, "lesson:lesson")
        XCTAssertEqual(a, b, "Practice strengthens the same record without relocating it")
        XCTAssertEqual(used.growthByRecordID[b.nodeID]?.applications, 2)
        XCTAssertNotEqual(kept.digest, used.digest)
        for (form, treatment) in [(CompanionForm.corePearl, CompanionVisualTreatment.protoStudy), (.particleSeed, .original), (.kin, .protoStudy), (.hamptonSeed, .original)] {
            let plain = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: nil, treatment: treatment))
            let grown = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: nil, treatment: treatment, particleScene: used))
            XCTAssertNotEqual(plain, grown, "Real memory projection must reach \(form), not just a card counter")
            let image = try XCTUnwrap(NSBitmapImageRep(data: grown))
            XCTAssertEqual(image.pixelsWide, 512); XCTAssertTrue(image.hasAlpha)
            let original = try XCTUnwrap(NSBitmapImageRep(data: plain))
            // The new layer must preserve the authored center, rather than
            // succeeding by replacing the body with an empty timeline raster.
            let center = try XCTUnwrap(image.colorAt(x: 256, y: 256))
            let reference = try XCTUnwrap(original.colorAt(x: 256, y: 256))
            // Raster compositing can round a color channel by one 8-bit step.
            // Preserve the authored center and opacity, not rounding noise.
            XCTAssertEqual(center.redComponent, reference.redComponent, accuracy: 1.1 / 255, "\(form)")
            XCTAssertEqual(center.greenComponent, reference.greenComponent, accuracy: 1.1 / 255, "\(form)")
            XCTAssertEqual(center.blueComponent, reference.blueComponent, accuracy: 1.1 / 255, "\(form)")
            XCTAssertEqual(center.alphaComponent, reference.alphaComponent, accuracy: 1.1 / 255, "\(form)")
            XCTAssertGreaterThan(image.colorAt(x: 256, y: 256)?.alphaComponent ?? 0, 0)
            if let path = ProcessInfo.processInfo.environment["ARCHI_COMPANION_REVIEW_DIR"] {
                let directory = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try grown.write(to: directory.appendingPathComponent("\(form.id)-\(treatment.rawValue)-memory.png"))
            }
        }
    }
}
