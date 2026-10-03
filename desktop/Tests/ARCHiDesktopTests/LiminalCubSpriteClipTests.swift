import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class LiminalCubSpriteClipTests: XCTestCase {
    @MainActor
    private func descriptor() throws -> Data {
        try Data(contentsOf: XCTUnwrap(LiminalCubSheetAsset.resourceURL(extension: "json")))
    }

    @MainActor
    private func clip() throws -> LiminalCubSpriteClip {
        try XCTUnwrap(LiminalCubSpriteClip.verifiedDescriptor(descriptor()))
    }

    @MainActor
    func testBundledUnchangedSheetAndPinnedDescriptorAreAccepted() throws {
        let data = try Data(contentsOf: XCTUnwrap(LiminalCubSheetAsset.resourceURL(extension: "png")))
        XCTAssertEqual(LiminalCubSpriteClip.digest(data), LiminalCubSpriteClip.sourceSHA256)
        let asset = try XCTUnwrap(LiminalCubSheetAsset.verified(sheet: data, descriptor: descriptor()))
        XCTAssertEqual(asset.image.size, NSSize(width: 1136, height: 1385))
        XCTAssertEqual(asset.clip.frames.count, 8)
        XCTAssertEqual(asset.clip.canvasWidth, 116)
        XCTAssertEqual(asset.clip.canvasHeight, 108)
        XCTAssertEqual(asset.clip.frames.first, .init(x: 75, y: 108, width: 107, height: 108))
    }

    @MainActor
    func testMissingCorruptOrReplacedSheetAndDescriptorCannotQualify() throws {
        let descriptor = try descriptor()
        let sheet = try Data(contentsOf: XCTUnwrap(LiminalCubSheetAsset.resourceURL(extension: "png")))
        XCTAssertNil(LiminalCubSheetAsset.verified(sheet: Data(), descriptor: descriptor))
        var corrupt = sheet
        corrupt[corrupt.count / 2] ^= 1
        XCTAssertNil(LiminalCubSheetAsset.verified(sheet: corrupt, descriptor: descriptor))
        XCTAssertNil(LiminalCubSheetAsset.verified(sheet: sheet, descriptor: descriptor + Data(" ".utf8)))
        XCTAssertNil(LiminalCubSheetAsset.verified(sheet: sheet, descriptor: Data()))
        let canonical = try Data(contentsOf: XCTUnwrap(CompanionVisualAsset.resourceURL(named: CompanionVisualAsset.hamptonGarnetFilename)))
        XCTAssertNil(LiminalCubSheetAsset.verified(sheet: canonical, descriptor: descriptor))
    }

    @MainActor
    func testDescriptorRejectsOutOfBoundsWrongDimensionsAndNonIdleClips() throws {
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: descriptor()) as? [String: Any])
        for mutation in ["negative-x", "overflow-width", "off-bottom", "empty", "dimensions", "rate", "clip"] {
            var object = original
            var frames = try XCTUnwrap(object["frames"] as? [[String: Any]])
            switch mutation {
            case "negative-x": frames[0]["x"] = -1
            case "overflow-width": frames[0]["width"] = Int.max
            case "off-bottom": frames[0]["y"] = 1385
            case "empty": frames = []
            case "dimensions": object["pixelWidth"] = 1536
            case "rate": object["framesPerSecond"] = 240
            default: object["clip"] = "attack"
            }
            object["frames"] = frames
            let value = try JSONDecoder().decode(LiminalCubSpriteClip.self,
                from: JSONSerialization.data(withJSONObject: object))
            XCTAssertFalse(value.isValid, mutation)
            XCTAssertEqual(value.frameIndex(at: 0.5, animating: true), 0, mutation)
        }
    }

    @MainActor
    func testClockIsDeterministicAndLoopsWithoutWritingClipState() throws {
        let clip = try clip()
        let before = clip
        for frame in 0..<8 {
            let time = (Double(frame) + 0.2) / 6
            XCTAssertEqual(clip.frameIndex(at: time, animating: true), frame)
            XCTAssertEqual(clip.frameIndex(at: time + 8.0 / 6, animating: true), frame)
        }
        for time in [Double.nan, .infinity, -.infinity, -1] {
            XCTAssertEqual(clip.frameIndex(at: time, animating: true), 0)
        }
        for tick in 0..<1000 {
            XCTAssertTrue((0..<8).contains(clip.frameIndex(at: Double(tick) / 17, animating: true)))
            XCTAssertEqual(clip.frameIndex(at: Double(tick), animating: false), 0)
        }
        XCTAssertTrue((0..<8).contains(clip.frameIndex(at: .greatestFiniteMagnitude, animating: true)))
        XCTAssertEqual(clip, before)
    }

    func testQuietAccessibilityHiddenFocusAndHoldAllStopThePreview() {
        for mode in KinLightMode.allCases {
            let expression = KinLightExpression(mode: mode)
            XCTAssertEqual(LiminalCubSpriteClip.motionAllowed(expression: expression, reduceMotion: false,
                systemReduceMotion: false, quiet: false, visible: true), mode != .focus && mode != .hold)
            for flags in [(true, false, false, true), (false, true, false, true),
                          (false, false, true, true), (false, false, false, false)] {
                XCTAssertFalse(LiminalCubSpriteClip.motionAllowed(expression: expression, reduceMotion: flags.0,
                    systemReduceMotion: flags.1, quiet: flags.2, visible: flags.3))
            }
        }
    }

    @MainActor
    func testOptInFrameAndCardSnapshotsKeepCanonicalSeedAndProfile() async throws {
        guard let outputPath = ProcessInfo.processInfo.environment["ARCHI_LIMINAL_CUB_REVIEW_DIR"] else {
            throw XCTSkip("Set ARCHI_LIMINAL_CUB_REVIEW_DIR for disposable reference-card snapshots")
        }
        let output = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("liminal-cub-preview-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = directory.appendingPathComponent("preferences.json")
        let identity = LocalQiMon(character: .hampton, originDigest: String(repeating: "b", count: 64),
                                welcomedAt: Date(timeIntervalSince1970: 1_700_000_000))
        var preferences = CompanionPreferences()
        preferences.form = .hamptonSeed
        preferences.seedAppearance = .hamptonLiminal
        preferences.seedColor = .garnet
        preferences.reduceMotion = true
        try NativePreferenceDocument(preferences: preferences, qiMon: identity).encoded().write(to: profile)
        let store = CompanionStore(preferenceURL: profile, allowsPlay: false)
        let profileBefore = try Data(contentsOf: profile)
        let historyBefore = store.evolution.history
        let seedBefore = try XCTUnwrap(CompanionPresenceArt.png(form: .hamptonSeed, family: nil, seedColor: .garnet))
        let asset = try XCTUnwrap(LiminalCubSheetAsset.bundled)
        var frames: [Data] = []
        for index in [0, 4] {
            let bytes = try render(LiminalCubSheetFrame(asset: asset, frameIndex: index)
                .frame(width: 232, height: 216).background(Color(red: 0.08, green: 0.07, blue: 0.07)))
            frames.append(bytes)
            try bytes.write(to: output.appendingPathComponent("idle-frame-\(index).png"))
        }
        XCTAssertNotEqual(frames[0], frames[1])
        let repeated = try render(LiminalCubSheetFrame(asset: asset, frameIndex: 0)
            .frame(width: 232, height: 216).background(Color(red: 0.08, green: 0.07, blue: 0.07)))
        XCTAssertEqual(frames[0], repeated)
        let card = try render(LiminalCubSheetPreview(store: store).padding(20).frame(width: 650)
            .environment(\.colorScheme, .dark).background(Color(red: 0.06, green: 0.07, blue: 0.08)))
        try card.write(to: output.appendingPathComponent("cub-motion-study-card.png"))
        XCTAssertEqual(store.activeQiMon, identity)
        XCTAssertEqual(store.preferences, preferences)
        XCTAssertEqual(store.presentationForm, .hamptonSeed)
        XCTAssertEqual(store.cursorPresentationForm, .hamptonSeed)
        XCTAssertEqual(store.evolution.history, historyBefore)
        XCTAssertEqual(try Data(contentsOf: profile), profileBefore)
        XCTAssertEqual(try XCTUnwrap(CompanionPresenceArt.png(form: .hamptonSeed, family: nil, seedColor: .garnet)), seedBefore)
        store.unityPresentation.stop()
        await store.shutdownAssistant()
    }

    @MainActor
    private func render<V: View>(_ view: V) throws -> Data {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}
