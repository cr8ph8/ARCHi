import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class VelaRenderingTests: XCTestCase {
    private let forms: [CompanionForm] = [.velaSeed, .velaLantern]

    @MainActor
    func testNativePresenceKeepsBothFormsVisibleAtCursorCardAndExportSizes() throws {
        let environment = ProcessInfo.processInfo.environment
        let output = (environment["ARCHI_VELA_REVIEW_DIR"] ?? environment["ARCHI_VELA_RENDER_DIR"])
            .map { URL(fileURLWithPath: $0) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        for form in forms {
            for pixels in [48, 96, 256] {
                let data = try render(CompanionPresenceArt(form: form, family: nil, size: CGFloat(pixels), reduceMotion: true))
                try inspectFrame(data, pixels: pixels)
                if let output { try data.write(to: output.appendingPathComponent("\(form.rawValue)-\(pixels).png")) }
            }
            let exported = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: nil))
            try inspectFrame(exported, pixels: 512)
            let native = try render(CompanionPresenceArt(form: form, family: nil, size: 256, reduceMotion: true), scale: 2)
            XCTAssertEqual(try pixels(exported), try pixels(native), "The retained appearance uses the same native drawing")
            if let output {
                try exported.write(to: output.appendingPathComponent("\(form.rawValue)-512.png"))
                let sheet = HStack(spacing: 0) {
                    CompanionPresenceArt(form: form, family: nil, size: 384, reduceMotion: true)
                        .background(Color(red: 0.06, green: 0.09, blue: 0.12))
                    CompanionPresenceArt(form: form, family: nil, size: 384, reduceMotion: true)
                        .background(Color(red: 0.97, green: 0.96, blue: 0.93))
                }
                try render(sheet).write(to: output.appendingPathComponent("\(form.rawValue)-review.png"))
            }
        }
        XCTAssertNotEqual(CompanionPresenceArt.png(form: .velaSeed, family: nil),
                          CompanionPresenceArt.png(form: .velaLantern, family: nil))
    }

    @MainActor
    func testSharedPalettesChangeMaterialsAndCacheWhileKeepingTheSamePearl() throws {
        for form in forms {
            let baseline = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: nil))
            let original = try XCTUnwrap(NSBitmapImageRep(data: baseline))
            var appearances = Set<Data>(), identities = Set<String>()
            for color in CompanionSeedColor.allCases {
                XCTAssertTrue(SeedColorRendering.applies(form: form))
                XCTAssertNil(SeedColorRendering.image(for: form, color: color), "A procedural Vela must not resolve a KIN raster")
                let data = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: nil, seedColor: color))
                XCTAssertTrue(appearances.insert(try pixels(data)).inserted, "Each palette changes the actual material")
                let id = CompanionVisualAsset.appearanceID(form: form, family: nil, treatment: .original, seedColor: color)
                XCTAssertTrue(identities.insert(id).inserted)
                XCTAssertLessThanOrEqual("\(id)-expression-\(UInt64.max)".utf16.count, 100)
                let label = CompanionVisualAsset.label(form: form, family: nil, treatment: .original, seedColor: color)
                XCTAssertTrue(label.hasPrefix("Vela · "))
                if color != .original { XCTAssertTrue(label.contains(color.title)) }
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
                // The center remains the same neutral light inside every shell.
                for y in 256...271 {
                    for x in 251...260 {
                        XCTAssertEqual(bitmap.colorAt(x: x, y: y), original.colorAt(x: x, y: y))
                    }
                }
            }
            for treatment in CompanionVisualTreatment.allCases {
                let data = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: nil, treatment: treatment))
                XCTAssertEqual(try pixels(data), try pixels(baseline), "Legacy treatments must not replace Vela")
            }
        }
    }

    @MainActor
    func testActivityAndWingMotionStayInsideTheFrameAndReachTheSharedView() throws {
        for form in forms {
            let rest = try render(CompanionPresenceArt(form: form, family: nil, size: 96, reduceMotion: true))
            for mode in KinLightMode.allCases where mode != .rest {
                let active = try render(CompanionPresenceArt(form: form, family: nil, size: 96, reduceMotion: true,
                    lightExpression: .init(mode: mode)))
                try inspectFrame(active, pixels: 96)
                XCTAssertNotEqual(try pixels(active), try pixels(rest), "Activity must reach both Vela forms")
            }
            for phase in [0.0, .pi / 2, .pi, .pi * 1.5, .nan, .infinity] {
                let data = try render(VelaCompanionFrame(lantern: form == .velaLantern, phase: phase,
                    expression: .init(mode: .delight)).frame(width: 48, height: 48))
                try inspectFrame(data, pixels: 48)
            }
        }
        let rest = try render(VelaCompanionFrame(lantern: true, phase: 0).frame(width: 256, height: 256))
        let moved = try render(VelaCompanionFrame(lantern: true, phase: .pi / 2).frame(width: 256, height: 256))
        XCTAssertNotEqual(try pixels(rest), try pixels(moved))
    }

    @MainActor
    func testReduceMotionFreezesBothSettingsAndInvalidTime() throws {
        for time in [0.0, 1, 100, 1e12, .nan, .infinity, -.infinity] {
            XCTAssertEqual(VelaGeometry.phase(at: time, reduceMotion: true, systemReduceMotion: false), 0)
            XCTAssertEqual(VelaGeometry.phase(at: time, reduceMotion: false, systemReduceMotion: true), 0)
        }
        XCTAssertEqual(VelaGeometry.phase(at: .nan, reduceMotion: false, systemReduceMotion: false), 0)
        XCTAssertNotEqual(VelaGeometry.phase(at: 1, reduceMotion: false, systemReduceMotion: false), 0)
        for form in forms {
            let app = try render(CompanionPresenceArt(form: form, family: nil, size: 96, reduceMotion: true))
            // The system setting is read-only; its policy is checked above.
            // Two native exports exercise the app's actual static drawing path.
            let repeated = try render(CompanionPresenceArt(form: form, family: nil, size: 96, reduceMotion: true))
            XCTAssertEqual(try pixels(app), try pixels(repeated))
        }
    }

    @MainActor private func render<V: View>(_ view: V, scale: Double = 1) throws -> Data {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let tiff = try XCTUnwrap(renderer.nsImage?.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }

    @MainActor private func pixels(_ data: Data) throws -> Data {
        let image = try XCTUnwrap(NSImage(data: data))
        return Data(try XCTUnwrap(SeedColorRendering.rgba(image)).bytes)
    }

    @MainActor private func inspectFrame(_ data: Data, pixels: Int) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(bitmap.pixelsWide, pixels)
        XCTAssertEqual(bitmap.pixelsHigh, pixels)
        XCTAssertTrue(bitmap.hasAlpha)
        XCTAssertLessThan(data.count, CompanionVisualAsset.maximumBytes)
        for index in 0..<pixels {
            for (x, y) in [(index, 0), (index, pixels - 1), (0, index), (pixels - 1, index)] {
                XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent, 0,
                    "The complete art must leave transparent edges without clipping")
            }
        }
        var visible = 0
        for y in stride(from: 0, to: pixels, by: max(1, pixels / 32)) {
            for x in stride(from: 0, to: pixels, by: max(1, pixels / 32)) {
                if try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent > 0.2 { visible += 1 }
            }
        }
        XCTAssertGreaterThan(visible, 90, "Tiny and large Vela drawings must remain visible")
    }
}
