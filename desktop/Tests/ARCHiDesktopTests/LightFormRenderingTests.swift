import AppKit
import CryptoKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class LightFormRenderingTests: XCTestCase {
    private let forms: [CompanionForm] = [.corePearl, .orbitField, .lightForm]

    @MainActor
    func testLocalFormsAreVisibleDistinctAndTransparentAtNativeAndHostedSizes() throws {
        let output = ProcessInfo.processInfo.environment["ARCHI_LIGHT_RENDER_DIR"].map { URL(fileURLWithPath: $0) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        for pixels in [86, 192, 512] {
            var hashes = Set<String>()
            for form in forms {
                XCTAssertNil(CompanionVisualAsset.resolvedImage(form: form, family: nil, treatment: .original),
                    "The new native light must work without a bundled or generated raster body")
                let data = try render(CompanionPresenceArt(form: form, family: nil, size: CGFloat(pixels), reduceMotion: true))
                try inspectFrame(data, pixels: pixels)
                XCTAssertTrue(hashes.insert(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()).inserted,
                    "Each chosen light must have a distinct visible drawing")
                if let output {
                    try data.write(to: output.appendingPathComponent("\(form.rawValue)-\(pixels).png"))
                }
            }
        }
    }

    @MainActor
    func testReducedMotionAndHostedExportUseTheSameDeterministicFrame() throws {
        for form in forms {
            let expected = form == .corePearl
                ? try render(ArchiLightSeedArt(size: 256, reduceMotion: true), scale: 2)
                : try render(LightFormFrame(form: form, phase: 0).frame(width: 256, height: 256), scale: 2)
            let reduced = try render(CompanionArt(form: form, size: 256, reduceMotion: true), scale: 2)
            // SwiftUI's system Reduce Motion value is read-only. Its shared
            // `reduceMotion || systemReduceMotion` path is source-reviewed;
            // this test changes only the app input, never the macOS setting.
            let firstExport = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: nil))
            let repeatedExport = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: nil))
            let pearlSetting = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: nil, treatment: .pearlStudy))
            for actual in [reduced, firstExport, repeatedExport, pearlSetting] {
                let result = try NaturalPresentationComparison.compare(expected, actual)
                XCTAssertTrue(result.withinAlphaPresentationBound,
                    "Reduce Motion, Original/Pearl settings and Habitat must preserve the same static \(form.rawValue) frame")
            }
            try inspectFrame(firstExport, pixels: 512)
        }
    }

    @MainActor
    func testAppearanceIdentityKeepsEquipmentAndEvolutionDistinctWithoutChangingLegacyLight() throws {
        XCTAssertEqual(CompanionVisualAsset.appearanceID(form: .light, family: nil, treatment: .original), "Guide light:origin")
        XCTAssertEqual(CompanionVisualAsset.appearanceID(form: .particle, family: nil, treatment: .original), "Particle light:origin")
        let staff = CompanionEquipment(hand: .focusStaff)
        let natural = try XCTUnwrap(CompanionNaturalVariation.make(originDigest: String(repeating: "a", count: 64)))
        let recipe = try XCTUnwrap(CompanionAppearanceRecipe.make(originDigest: natural.originDigest,
            family: .lumen, role: .muse, helpStyle: .reflective, basisKind: .usefulWork))
        var identities = Set<String>()
        for form in forms {
            let base = CompanionVisualAsset.appearanceID(form: form, family: nil, treatment: .original)
            let equipped = CompanionVisualAsset.appearanceID(form: form, family: nil, treatment: .original, equipment: staff)
            XCTAssertTrue(identities.insert(base).inserted)
            XCTAssertTrue(identities.insert(equipped).inserted)
            XCTAssertNotEqual(base, equipped)
            for available in [true, false] {
                if form == .corePearl && !available {
                    XCTAssertNotEqual(base, CompanionVisualAsset.appearanceID(form: form, family: nil, treatment: .pearlStudy, assetAvailable: false))
                    continue
                }
                XCTAssertEqual(base, CompanionVisualAsset.appearanceID(form: form, family: nil, treatment: .pearlStudy,
                    recipe: recipe, naturalVariation: natural, assetAvailable: available))
            }
            for id in [base, equipped] {
                XCTAssertLessThanOrEqual("\(id)-expression-\(UInt64.max)".count, 100)
            }
            XCTAssertEqual(CompanionVisualAsset.label(form: form, family: nil, treatment: .pearlStudy,
                recipe: recipe, naturalVariation: natural, equipment: staff), "\(form == .corePearl ? "ARCHi · Ball of Light" : form.rawValue) · Focus Staff")
            let basicImage = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: nil))
            let equippedImage = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: nil, equipment: staff))
            XCTAssertNotEqual(basicImage, equippedImage)
            try inspectFrame(equippedImage, pixels: 512)

            let evolved = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: .lumen, recipe: recipe))
            let existingEvolvedPath = try XCTUnwrap(CompanionPresenceArt.png(form: .ink, family: .lumen, recipe: recipe))
            XCTAssertTrue(try NaturalPresentationComparison.compare(evolved, existingEvolvedPath).withinAlphaPresentationBound,
                "A light starter must retain the current evolved body path")
            XCTAssertNotEqual(base, CompanionVisualAsset.appearanceID(form: form, family: .lumen, treatment: .original, recipe: recipe))
        }
    }

    func testMotionGeometryStaysFiniteAndBoundedForInvalidAndWrappedClockInputs() {
        let stillPetals = LightFormGeometry.petals(phase: 0)
        let stillMotes = LightFormGeometry.motes(phase: 0)
        XCTAssertFalse(stillPetals.isEmpty)
        XCTAssertFalse(stillMotes.isEmpty)
        for phase in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(LightFormGeometry.normalizedPhase(phase), 0)
            XCTAssertEqual(LightFormGeometry.petals(phase: phase), stillPetals)
            XCTAssertEqual(LightFormGeometry.motes(phase: phase), stillMotes)
        }
        for phase in [-1e12, -Double.pi, 0, Double.pi, 1e12] {
            let normalized = LightFormGeometry.normalizedPhase(phase)
            XCTAssertTrue(normalized.isFinite && normalized >= 0 && normalized < .pi * 2)
            for petal in LightFormGeometry.petals(phase: phase) {
                XCTAssertTrue(petal.rotation.isFinite && petal.scale.isFinite && petal.scale > 0)
                XCTAssertLessThan(abs(petal.x), 0.5)
                XCTAssertLessThan(abs(petal.y), 0.5)
            }
            for mote in LightFormGeometry.motes(phase: phase) {
                XCTAssertTrue(mote.radius.isFinite && mote.radius > 0 && mote.radius < 0.05)
                XCTAssertTrue(mote.opacity.isFinite && (0...1).contains(mote.opacity))
                XCTAssertLessThan(abs(mote.x), 0.5)
                XCTAssertLessThan(abs(mote.y), 0.5)
            }
        }
    }

    @MainActor private func render<V: View>(_ view: V, scale: CGFloat = 1) throws -> Data {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let tiff = try XCTUnwrap(renderer.nsImage?.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }

    @MainActor private func inspectFrame(_ data: Data, pixels: Int) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(bitmap.pixelsWide, pixels)
        XCTAssertEqual(bitmap.pixelsHigh, pixels)
        XCTAssertTrue(bitmap.hasAlpha)
        XCTAssertLessThan(data.count, CompanionVisualAsset.maximumBytes)
        for i in 0..<pixels {
            for (x, y) in [(i, 0), (i, pixels - 1), (0, i), (pixels - 1, i)] {
                XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent, 0,
                    "The body must fit its existing transparent frame")
            }
        }
        var visible = 0
        for y in stride(from: 0, to: pixels, by: max(1, pixels / 32)) {
            for x in stride(from: 0, to: pixels, by: max(1, pixels / 32)) {
                if try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent > 0.1 { visible += 1 }
            }
        }
        XCTAssertGreaterThan(visible, 20, "A valid PNG must also contain a visible companion")
    }
}
