import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class SeedColorRenderingTests: XCTestCase {
    @MainActor
    func testEverySeedPaletteChangesMaterialWithoutChangingAlphaOrPearl() throws {
        for form in [CompanionForm.corePearl, .kinSeed, .hamptonSeed] {
            let original = try XCTUnwrap(SeedColorRendering.image(for: form, color: .original))
            let originalPixels = try XCTUnwrap(SeedColorRendering.rgba(original))
            XCTAssertEqual(originalPixels.width, 512)
            var appearances = Set<Data>()
            for color in CompanionSeedColor.allCases where color != .original {
                // Test the material transform independently of an optional
                // separate Blender render, whose antialiasing can differ.
                let image = try XCTUnwrap(SeedColorRendering.recolor(original, color: color, preserveGold: form == .hamptonSeed))
                let pixels = try XCTUnwrap(SeedColorRendering.rgba(image))
                XCTAssertNotEqual(pixels.bytes, originalPixels.bytes, "\(form) · \(color)")
                XCTAssertTrue(appearances.insert(Data(pixels.bytes)).inserted, "Every palette is distinct")
                XCTAssertEqual(stride(from: 3, to: pixels.bytes.count, by: 4).map { pixels.bytes[$0] },
                               stride(from: 3, to: originalPixels.bytes.count, by: 4).map { originalPixels.bytes[$0] })
                for y in 248...264 {
                    for x in 248...264 {
                        let index = (y * 512 + x) * 4
                        XCTAssertEqual(Array(pixels.bytes[index..<index + 4]), Array(originalPixels.bytes[index..<index + 4]),
                                       "The same central pearl remains")
                    }
                }
            }
        }
    }

    @MainActor
    func testHamptonGoldIsProtectedWhileItsAquaMaterialChanges() throws {
        let image = try XCTUnwrap(SeedColorRendering.image(for: .hamptonSeed, color: .original))
        let source = try XCTUnwrap(SeedColorRendering.rgba(image))
        let target = try XCTUnwrap(SeedColorRendering.rgba(XCTUnwrap(SeedColorRendering.recolor(image, color: .violet, preserveGold: true))))
        var protected = 0, changed = 0
        for index in stride(from: 0, to: source.bytes.count, by: 4) where source.bytes[index + 3] > 80 {
            let r = Double(source.bytes[index]), g = Double(source.bytes[index + 1]), b = Double(source.bytes[index + 2])
            // This narrow gold interval is inside the renderer's protected range.
            if r > g * 1.10, g > b * 1.20, r - g < (g - b) * 2 {
                protected += 1
                XCTAssertEqual(Array(source.bytes[index..<index + 4]), Array(target.bytes[index..<index + 4]))
            }
            if source.bytes[index] != target.bytes[index] || source.bytes[index + 2] != target.bytes[index + 2] { changed += 1 }
        }
        XCTAssertGreaterThan(protected, 100, "The gold arcs remain present")
        XCTAssertGreaterThan(changed, 1000, "The shell has an actual new palette")
    }

    @MainActor
    func testOriginalAssetsStayExactAndCachedPalettesAreReused() throws {
        XCTAssertTrue(SeedColorRendering.image(for: .corePearl, color: .original) === CompanionVisualAsset.lightSeedImage)
        XCTAssertTrue(SeedColorRendering.image(for: .kinSeed, color: .original) === CompanionVisualAsset.kinSeedImage)
        XCTAssertTrue(SeedColorRendering.image(for: .hamptonSeed, color: .original) === CompanionVisualAsset.hamptonSeedImage)
        let first = try XCTUnwrap(SeedColorRendering.image(for: .kinSeed, color: .violet))
        XCTAssertTrue(first === SeedColorRendering.image(for: .kinSeed, color: .violet))
        XCTAssertTrue(first === SeedColorRendering.image(for: .particleSeed, color: .violet))
        XCTAssertNil(SeedColorRendering.image(for: .kin, color: .garnet))
    }

    @MainActor
    func testGarnetLiminalUsesTheReviewedBlenderMaterialInsteadOfATintedOriginal() throws {
        let authored = try XCTUnwrap(CompanionVisualAsset.hamptonGarnetImage)
        XCTAssertTrue(authored === SeedColorRendering.image(for: .hamptonSeed, color: .garnet))
        XCTAssertEqual(CompanionVisualAsset.hamptonGarnetDigest,
                       "4926755798476430159df3923399242d0f564ea11fa3f8895f769f60655128a9")
        let pixels = try XCTUnwrap(SeedColorRendering.rgba(authored))
        XCTAssertEqual(pixels.width, 512)
        XCTAssertEqual(pixels.height, 512)
        XCTAssertEqual(pixels.bytes[3], 0)
        XCTAssertGreaterThan(pixels.bytes[(256 * 512 + 256) * 4 + 3], 240)
        let original = try XCTUnwrap(CompanionVisualAsset.hamptonSeedImage)
        XCTAssertNotEqual(pixels.bytes, SeedColorRendering.rgba(original)?.bytes)
        var garnetPixels = 0, goldPixels = 0
        for index in stride(from: 0, to: pixels.bytes.count, by: 4) where pixels.bytes[index + 3] > 80 {
            let r = Double(pixels.bytes[index]), g = Double(pixels.bytes[index + 1]), b = Double(pixels.bytes[index + 2])
            if r > g * 1.6, r > b * 1.3 { garnetPixels += 1 }
            if r > g * 1.10, g > b * 1.20, r - g < (g - b) * 2 { goldPixels += 1 }
        }
        XCTAssertGreaterThan(garnetPixels, 500)
        XCTAssertGreaterThan(goldPixels, 100)
    }

    @MainActor
    func testColorIdentityAndLabelsRespectSeedOnlyBoundary() throws {
        for form in [CompanionForm.corePearl, .particleSeed, .kinSeed, .hamptonSeed] {
            let original = CompanionVisualAsset.appearanceID(form: form, family: nil, treatment: .original)
            let garnet = CompanionVisualAsset.appearanceID(form: form, family: nil, treatment: .original, seedColor: .garnet)
            let violet = CompanionVisualAsset.appearanceID(form: form, family: nil, treatment: .original, seedColor: .violet)
            XCTAssertNotEqual(original, garnet)
            XCTAssertNotEqual(garnet, violet)
            XCTAssertLessThan(garnet.count, 80)
            XCTAssertTrue(CompanionVisualAsset.label(form: form, family: nil, treatment: .original, seedColor: .garnet).contains("Garnet"))
        }
        for form in [CompanionForm.kin, .companion, .sprout, .lightForm] {
            XCTAssertEqual(CompanionVisualAsset.appearanceID(form: form, family: nil, treatment: .original),
                           CompanionVisualAsset.appearanceID(form: form, family: nil, treatment: .original, seedColor: .garnet))
            XCTAssertEqual(CompanionVisualAsset.label(form: form, family: nil, treatment: .original),
                           CompanionVisualAsset.label(form: form, family: nil, treatment: .original, seedColor: .garnet))
        }
        XCTAssertEqual(CompanionVisualAsset.appearanceID(form: .companion, family: .lumen, treatment: .pearlStudy),
                       CompanionVisualAsset.appearanceID(form: .companion, family: .lumen, treatment: .pearlStudy, seedColor: .garnet))
    }

    @MainActor
    func testNativeExportsUsePaletteWithoutTintingAnAdultBody() throws {
        for form in [CompanionForm.corePearl, .particleSeed, .kinSeed, .hamptonSeed] {
            let original = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: nil))
            let colored = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: nil, seedColor: .garnet))
            XCTAssertNotEqual(original, colored, "Palette reaches native export for \(form)")
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: colored))
            XCTAssertEqual(bitmap.pixelsWide, 512)
            XCTAssertTrue(bitmap.hasAlpha)
            XCTAssertLessThan(colored.count, CompanionVisualAsset.maximumBytes)
            if let path = ProcessInfo.processInfo.environment["ARCHI_SEED_COLOR_REVIEW_DIR"] {
                let folder = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try colored.write(to: folder.appendingPathComponent("\(form.rawValue)-garnet.png"))
            }
        }
        XCTAssertEqual(CompanionPresenceArt.png(form: .kin, family: nil),
                       CompanionPresenceArt.png(form: .kin, family: nil, seedColor: .garnet))
    }
}
