import AppKit
import CryptoKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class KinFirstLightRenderingTests: XCTestCase {
    @MainActor
    func testFirstLightIsDistinctTransparentAndKeepsTheSeedAsset() throws {
        let firstLightURL = try XCTUnwrap(CompanionVisualAsset.resourceURL(named: CompanionVisualAsset.kinFirstLightFilename))
        let firstLightSource = try Data(contentsOf: firstLightURL)
        XCTAssertEqual(SHA256.hash(data: firstLightSource).map { String(format: "%02x", $0) }.joined(),
            CompanionVisualAsset.kinFirstLightDigest)
        XCTAssertNotNil(CompanionVisualAsset.kinFirstLightImage, "The reviewed Blender asset must reach the native renderer")
        let seedURL = try XCTUnwrap(CompanionVisualAsset.resourceURL(named: CompanionVisualAsset.kinSeedFilename))
        let seedSource = try Data(contentsOf: seedURL)
        let seed = try XCTUnwrap(CompanionPresenceArt.png(form: .kinSeed, family: nil))
        let firstLight = try XCTUnwrap(CompanionPresenceArt.png(form: .kin, family: nil))
        XCTAssertNotEqual(firstLight, seed)
        let pixels = try inspect(firstLight, dimension: 512)
        let core = try XCTUnwrap(pixels.colorAt(x: 266, y: 318))
        XCTAssertEqual(core.alphaComponent, 1)
        XCTAssertGreaterThan(core.redComponent, 0.9)
        XCTAssertGreaterThan(core.greenComponent, 0.6)
        let native = try render(CompanionArt(form: .kin, size: 256, reduceMotion: true))
        XCTAssertTrue(try NaturalPresentationComparison.compare(firstLight, native).withinAlphaPresentationBound)
        let body = try XCTUnwrap(CompanionVisualAsset.kinFirstLightImage)
        let sourceFrame = try render(Image(nsImage: body).resizable().interpolation(.high).scaledToFit()
            .frame(width: 256, height: 256))
        XCTAssertTrue(try NaturalPresentationComparison.compare(firstLight, sourceFrame).withinAlphaPresentationBound,
            "Static export must contain the reviewed Blender body without a live activity cue")
        XCTAssertEqual(try Data(contentsOf: seedURL), seedSource)
        XCTAssertEqual(SHA256.hash(data: seedSource).map { String(format: "%02x", $0) }.joined(),
            CompanionVisualAsset.kinSeedDigest)
        try save(firstLight, name: "kin-first-light-rest.png")
        try save(seed, name: "kin-core-seed-unchanged.png")
        for size in [64.0, 96.0] {
            let small = try render(KinArt(form: .kin, size: size, reduceMotion: true), scale: 1)
            _ = try inspect(small, dimension: Int(size))
            try save(small, name: "kin-first-light-\(Int(size))pt.png")
        }
        if ProcessInfo.processInfo.environment["ARCHI_KIN_GROWTH_RENDER_DIR"] != nil {
            let comparison = VStack(spacing: 24) {
                Text("KIN · FIRST LIGHT").font(.system(size: 19, weight: .medium, design: .rounded)).tracking(4)
                HStack(spacing: 24) {
                    VStack(spacing: 12) {
                        KinArt(form: .kinSeed, size: 220, reduceMotion: true)
                        Text("Core Seed · preserved")
                    }
                    VStack(spacing: 12) {
                        KinFirstLightPortrait(size: 220, reduceMotion: true,
                            lightExpression: .resting, bodyImage: nil)
                        Text("Prior native drawing")
                    }
                    VStack(spacing: 12) {
                        KinArt(form: .kin, size: 220, reduceMotion: true)
                        Text("Refined Blender body")
                    }
                }
                Text("Native render study · same identity, light rules and growth choice")
                    .font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.62))
            }
            .font(.system(size: 13, weight: .medium)).foregroundStyle(Color(red: 0.94, green: 0.87, blue: 0.73))
            .padding(32).background(Color(red: 0.07, green: 0.065, blue: 0.08))
            try save(try render(comparison), name: "kin-native-before-and-after.png")
        }
    }

    @MainActor
    func testTemporaryLightIsVisibleAndKeepsFirstLightsOpaqueCoreAndExport() throws {
        let resting = try render(CompanionPresenceArt(form: .kin, family: nil, size: 256, reduceMotion: true))
        let original = try XCTUnwrap(NSBitmapImageRep(data: resting))
        for mode in KinLightMode.allCases where mode != .rest {
            let frame = try render(CompanionPresenceArt(form: .kin, family: nil, size: 256,
                reduceMotion: true, lightExpression: KinLightExpression(mode: mode)))
            let pixels = try inspect(frame, dimension: 512)
            XCTAssertNotEqual(frame, resting, "\(mode) must reach the actual native First Light renderer")
            var samples = 0
            for y in 300..<335 {
                for x in 249..<284 {
                    let dx = Double(x) / 512 - 0.52, dy = Double(y) / 512 - 0.62
                    guard dx * dx + dy * dy < 0.025 * 0.025 else { continue }
                    let before = try XCTUnwrap(original.colorAt(x: x, y: y))
                    let after = try XCTUnwrap(pixels.colorAt(x: x, y: y))
                    XCTAssertEqual(before.alphaComponent, 1)
                    XCTAssertEqual(after.alphaComponent, before.alphaComponent, "\(mode) core alpha")
                    XCTAssertEqual(after.redComponent, before.redComponent, "\(mode) core red")
                    XCTAssertEqual(after.greenComponent, before.greenComponent, "\(mode) core green")
                    XCTAssertEqual(after.blueComponent, before.blueComponent, "\(mode) core blue")
                    samples += 1
                }
            }
            XCTAssertGreaterThan(samples, 400)
            try save(frame, name: "kin-first-light-\(mode.rawValue).png")
        }
        let export = try XCTUnwrap(CompanionPresenceArt.png(form: .kin, family: nil))
        XCTAssertTrue(try NaturalPresentationComparison.compare(resting, export).withinAlphaPresentationBound,
            "Temporary work cues must not become canonical body artwork")
    }

    @MainActor
    func testSystemReduceMotionUsesTheSameStaticFirstLightFrame() throws {
        // macOS exposes this environment value as read-only. Never change the
        // user's accessibility preference merely to manufacture a test result.
        guard NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            throw XCTSkip("System Reduce Motion is off; analytical policy covers both inputs. Native system rendering needs that existing setting enabled.")
        }
        let explicit = try render(KinArt(form: .kin, size: 256, reduceMotion: true,
            lightExpression: .init(mode: .orbit)))
        let system = try render(KinArt(form: .kin, size: 256, reduceMotion: false,
            lightExpression: .init(mode: .orbit))
            // ImageRenderer is a separate root, outside the app's environment.
            .environment(\.accessibilityReduceMotion, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion))
        XCTAssertTrue(try NaturalPresentationComparison.compare(explicit, system).withinAlphaPresentationBound)
    }

    func testFirstLightFloatSettlesAndResumesContinuouslyWithItsAttentionClock() {
        var clock = KinSeedMotion(at: 0)
        let moving = clock.sample(at: 1.3)
        clock.transition(to: .init(mode: .focus), at: 1.3)
        XCTAssertEqual(KinFirstLightPresentation.verticalOffset(for: moving),
            KinFirstLightPresentation.verticalOffset(for: clock.sample(at: 1.3)), accuracy: 1e-12)
        let settled = KinFirstLightPresentation.verticalOffset(for: clock.sample(at: 2))
        XCTAssertEqual(settled, KinFirstLightPresentation.verticalOffset(for: clock.sample(at: 4)), accuracy: 1e-12)
        clock.transition(to: .init(mode: .hold), at: 4)
        XCTAssertEqual(settled, KinFirstLightPresentation.verticalOffset(for: clock.sample(at: 5)), accuracy: 1e-12)
        clock.transition(to: .init(mode: .rest), at: 5)
        XCTAssertEqual(settled, KinFirstLightPresentation.verticalOffset(for: clock.sample(at: 5)), accuracy: 1e-12)
        XCTAssertNotEqual(settled, KinFirstLightPresentation.verticalOffset(for: clock.sample(at: 6)))
        for policy in [KinSeedMotion.Policy(mode: .rest, reduceMotion: true),
                       .init(mode: .rest, systemReduceMotion: true)] {
            var frozen = clock
            let before = KinFirstLightPresentation.verticalOffset(for: frozen.sample(at: 6))
            frozen.transition(to: policy, at: 6)
            XCTAssertEqual(before, KinFirstLightPresentation.verticalOffset(for: frozen.sample(at: 6)), accuracy: 1e-12)
            XCTAssertEqual(before, KinFirstLightPresentation.verticalOffset(for: frozen.sample(at: 600)), accuracy: 1e-12)
        }
    }

    @MainActor
    func testFirstLightHasOneVersionedBodyIdentityWithSeparateEquipment() {
        let firstLight = CompanionVisualAsset.appearanceID(form: .kin, family: nil, treatment: .original)
        XCTAssertEqual(firstLight, "kf1-\(CompanionVisualAsset.kinFirstLightDigest)")
        let fallback = CompanionVisualAsset.appearanceID(form: .kin, family: nil, treatment: .original, assetAvailable: false)
        XCTAssertEqual(fallback, "kin-first-light-native-v2")
        XCTAssertNotEqual(firstLight, fallback)
        XCTAssertEqual(firstLight, CompanionVisualAsset.appearanceID(form: .kin, family: nil, treatment: .pearlStudy))
        XCTAssertEqual(fallback, CompanionVisualAsset.appearanceID(form: .kin, family: nil, treatment: .pearlStudy, assetAvailable: false))
        XCTAssertFalse(CompanionVisualAsset.applies(form: .kin, family: nil, treatment: .original))
        XCTAssertNil(CompanionVisualAsset.resolvedImage(form: .kin, family: nil, treatment: .original),
            "Generic image resolution must not bypass KIN's own light and motion path")
        XCTAssertNotEqual(firstLight, CompanionVisualAsset.appearanceID(form: .kinSeed, family: nil, treatment: .original))
        XCTAssertNotEqual(firstLight, CompanionVisualAsset.appearanceID(form: .kin, family: nil,
            treatment: .original, equipment: CompanionEquipment(hand: .focusStaff)))
        XCTAssertFalse(CompanionForm.starterChoices.contains(where: \.isKin),
            "Personal growth does not turn KIN back into generic selectable skins")
    }

    @MainActor
    func testUnverifiedFirstLightAssetFallsBackToNativeBodyWithoutLosingLightEffects() throws {
        let url = try XCTUnwrap(CompanionVisualAsset.resourceURL(named: CompanionVisualAsset.kinFirstLightFilename))
        let source = try Data(contentsOf: url)
        let wrongDigest = String(repeating: "0", count: 64)
        XCTAssertNil(CompanionVisualAsset.verifiedImage(source, expectedDigest: wrongDigest))
        XCTAssertNil(CompanionVisualAsset.verifiedImage(Data(source.dropLast()), expectedDigest: CompanionVisualAsset.kinFirstLightDigest))
        XCTAssertNotNil(CompanionVisualAsset.verifiedImage(source, expectedDigest: CompanionVisualAsset.kinFirstLightDigest))
        let fallback = try render(KinFirstLightPortrait(size: 256, reduceMotion: true,
            lightExpression: .resting, bodyImage: nil))
        let pixels = try inspect(fallback, dimension: 512)
        let core = try XCTUnwrap(pixels.colorAt(x: 266, y: 318))
        XCTAssertEqual(core.alphaComponent, 1)
        XCTAssertGreaterThan(core.redComponent, 0.9)
        XCTAssertGreaterThan(core.greenComponent, 0.6)
        let liveAsset = try XCTUnwrap(CompanionPresenceArt.png(form: .kin, family: nil))
        XCTAssertFalse(try NaturalPresentationComparison.compare(fallback, liveAsset).withinAlphaPresentationBound,
            "A missing asset must use the retained native body with a distinct cache identity")
        for mode in KinLightMode.allCases where mode != .rest {
            let frame = try render(KinFirstLightPortrait(size: 256, reduceMotion: true,
                lightExpression: KinLightExpression(mode: mode), bodyImage: nil))
            let changed = try inspect(frame, dimension: 512)
            XCTAssertNotEqual(frame, fallback)
            let after = try XCTUnwrap(changed.colorAt(x: 266, y: 318))
            XCTAssertEqual(after.alphaComponent, core.alphaComponent)
            XCTAssertEqual(after.redComponent, core.redComponent)
            XCTAssertEqual(after.greenComponent, core.greenComponent)
            XCTAssertEqual(after.blueComponent, core.blueComponent)
        }
        try save(fallback, name: "kin-first-light-native-fallback.png")
    }

    @MainActor private func inspect(_ data: Data, dimension: Int) throws -> NSBitmapImageRep {
        let pixels = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(pixels.pixelsWide, dimension)
        XCTAssertEqual(pixels.pixelsHigh, dimension)
        XCTAssertTrue(pixels.hasAlpha)
        XCTAssertLessThan(data.count, CompanionVisualAsset.maximumBytes)
        for coordinate in 0..<dimension {
            for (x, y) in [(coordinate, 0), (coordinate, dimension - 1), (0, coordinate), (dimension - 1, coordinate)] {
                XCTAssertEqual(try XCTUnwrap(pixels.colorAt(x: x, y: y)).alphaComponent, 0,
                    "First Light and its light field must fit the unchanged native frame")
            }
        }
        return pixels
    }

    @MainActor private func render<V: View>(_ view: V, scale: CGFloat = 2) throws -> Data {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let tiff = try XCTUnwrap(renderer.nsImage?.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }

    private func save(_ data: Data, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_KIN_GROWTH_RENDER_DIR"] else { return }
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name))
    }
}
