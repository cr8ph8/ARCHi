import AppKit
import ARCHiSpatial
import CoreText
import CryptoKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class ImageRegionPresentationTests: XCTestCase {
    /// Opt-in native snapshots use the real image canvas and record-ID particle
    /// projection. All content is synthetic and no CompanionStore is created.
    @MainActor
    func testNativeImageRegionAttentionFrames() async throws {
        guard ProcessInfo.processInfo.environment["ARCHI_IMAGE_REGION_RENDER_TEST"] == "1" else {
            throw XCTSkip("Set ARCHI_IMAGE_REGION_RENDER_TEST=1 for bounded native image-region snapshots")
        }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            throw XCTSkip("Intermediate-motion rendering requires Reduce Motion to be off; do not change the user's setting")
        }
        let output = URL(fileURLWithPath: "/private/tmp/archi-image-region-render", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let fixture = output.appendingPathComponent("synthetic-memory-screenshot.png")
        let original = try syntheticScreenshot()
        try original.write(to: fixture, options: .atomic)
        let image = try await ImageRegionReader.load(url: fixture)
        let region = try XCTUnwrap(ImageRegionRect(x: 0.46, y: 0.25, width: 0.40, height: 0.44))
        let size = CGSize(width: 880, height: 330)
        let imageFrame = ImageRegionCanvas.imageFrame(pixelWidth: image.pixelWidth,
            pixelHeight: image.pixelHeight, in: size)
        let target = region.displayed(in: imageFrame)
        XCTAssertEqual(imageFrame.height, size.height, accuracy: 0.001)
        XCTAssertGreaterThan(imageFrame.minX, 0, "The fixture must exercise horizontal letterboxing")

        let nodes = ["Source versions", "Kept lessons", "Reviewed application", "Attributable outcomes"].enumerated().map {
            CompanionGraphNode(id: "synthetic-current-page-\($0.offset)-v1", title: $0.element,
                subtitle: "Synthetic current source · version 1", kind: .knowledge, status: "Synthetic fixture",
                details: [.init(label: "Scope", value: "Rendering fixture, not a saved memory")], target: nil)
        }
        let graph = CompanionGraphSnapshot(nodes: nodes, edges: [], truncatedCount: 0)
        let field = KnowledgeParticleField(snapshot: graph)
        let framing = KnowledgeParticleField.framing(particles: field.particles, spread: 1, reduceMotion: false)
        let base = KnowledgeParticleField.displayPositions(particles: field.particles, frame: framing,
            spread: 1, reduceMotion: false, width: size.width, height: size.height)
        let baseline = try render(ImageRegionCanvas(image: image, region: region)
            .frame(width: size.width, height: size.height))
        try baseline.write(to: output.appendingPathComponent("canvas.png"), options: .atomic)
        let baselineBitmap = try XCTUnwrap(NSBitmapImageRep(data: baseline))
        var rendered: [Data] = []
        var receipt: [[String: Any]] = []
        for progress in [0.0, 0.5, 1.0] {
            let view = ZStack {
                ImageRegionCanvas(image: image, region: region)
                KnowledgeParticleView(field: field, nodes: nodes, selectedID: nil,
                    spread: 1, pulses: false, reduceMotion: false, tint: WorkspaceTheme.accent,
                    showsLabels: false, compact: true, interactive: false,
                    regionTarget: target, regionProgress: progress, onSelect: { _ in
                        XCTFail("Rendering must not select or mutate a record")
                    })
            }.frame(width: size.width, height: size.height)
            let data = try render(view)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
            XCTAssertEqual(bitmap.pixelsWide, Int(size.width)); XCTAssertEqual(bitmap.pixelsHigh, Int(size.height))
            let points = KnowledgeParticleField.regionPositions(base: base, target: target, canvas: size, progress: progress)
            XCTAssertEqual(Set(points.keys), Set(nodes.map(\.id)))
            for (id, point) in points {
                XCTAssertTrue(CGRect(origin: .zero, size: size).insetBy(dx: 11, dy: 11)
                    .contains(CGPoint(x: point.x, y: point.y)), "Anchor and selection ring must fit: \(id)")
                XCTAssertGreaterThan(try changedPixels(near: CGPoint(x: point.x, y: point.y),
                    actual: bitmap, baseline: baselineBitmap), 4,
                    "The real Canvas must paint each current record at its shared projected position: \(id)")
            }
            let filename = "attention-\(Int(progress * 100)).png"
            try data.write(to: output.appendingPathComponent(filename), options: .atomic)
            rendered.append(data)
            receipt.append(["progress": progress, "file": filename,
                "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                "points": points.mapValues { ["x": $0.x, "y": $0.y] }])
        }
        XCTAssertEqual(Set(rendered).count, 3, "The native snapshots must include intermediate motion, not three endpoint copies")
        XCTAssertEqual(try Data(contentsOf: fixture), original, "Presentation cannot modify its input image")
        XCTAssertEqual(graph.nodes, nodes, "Motion must not replace graph records")
        let receiptData = try JSONSerialization.data(withJSONObject: [
            "scope": "Synthetic native UI rendering only; no saved profile, model call, OCR result, or learning event",
            "canvas": ["width": size.width, "height": size.height], "frames": receipt
        ], options: [.prettyPrinted, .sortedKeys])
        try receiptData.write(to: output.appendingPathComponent("render-receipt.json"), options: .atomic)
    }

    @MainActor private func render<V: View>(_ view: V) throws -> Data {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.nsImage)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    @MainActor private func changedPixels(near point: CGPoint, actual: NSBitmapImageRep,
                                         baseline: NSBitmapImageRep) throws -> Int {
        var changed = 0
        for y in max(0, Int(point.y) - 5)...min(actual.pixelsHigh - 1, Int(point.y) + 5) {
            for x in max(0, Int(point.x) - 5)...min(actual.pixelsWide - 1, Int(point.x) + 5) {
                let a = try XCTUnwrap(actual.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let b = try XCTUnwrap(baseline.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let distance = abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent)
                    + abs(a.blueComponent - b.blueComponent)
                if distance > 0.15 { changed += 1 }
            }
        }
        return changed
    }

    private func syntheticScreenshot() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1_200, height: 700, bitsPerComponent: 8,
            bytesPerRow: 4_800, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.035, green: 0.065, blue: 0.075, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1_200, height: 700))
        context.setFillColor(CGColor(red: 0.075, green: 0.13, blue: 0.145, alpha: 1))
        context.fill(CGRect(x: 540, y: 200, width: 520, height: 340))
        let rows: [(String, CGFloat, CGFloat, CGFloat)] = [
            ("ARCHi · synthetic image fixture", 55, 625, 34),
            ("Local selection walkthrough", 55, 560, 24),
            ("Select part of this image.", 55, 470, 23),
            ("Review recognized text.", 55, 425, 23),
            ("Keep the source and version.", 55, 380, 23),
            ("SOURCE-AWARE MEMORY", 575, 485, 26),
            ("Knowledge keeps its source.", 575, 425, 23),
            ("Reviewed use can add support.", 575, 375, 23),
            ("Particles show existing records.", 575, 325, 23),
            ("No memory is created by motion.", 575, 275, 23),
            ("Test data only · no personal record or claimed experience", 55, 70, 23)
        ]
        for (text, x, y, size) in rows {
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, size, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.93, alpha: 1)
            ]
            context.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
        }
        return try XCTUnwrap(NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
            .representation(using: .png, properties: [:]))
    }
}
