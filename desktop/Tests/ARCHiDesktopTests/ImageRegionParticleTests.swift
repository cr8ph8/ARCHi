import CoreGraphics
import Foundation
import XCTest
@testable import ARCHiDesktop

/// Image attention moves existing presentation anchors; it never creates a
/// record or changes the identity used by the memory inspector.
@MainActor
final class ImageRegionParticleTests: XCTestCase {
    private typealias Vector = KnowledgeParticleField.Vector
    private let canvas = CGSize(width: 640, height: 480)
    private let target = CGRect(x: 230, y: 160, width: 160, height: 120)
    private let base: [String: Vector] = [
        "knowledge:alpha": .init(x: 72, y: 90),
        "lesson:beta": .init(x: 540, y: 120),
        "source:gamma": .init(x: 410, y: 390)
    ]

    func testStartIsExactAndFiniteProgressClampsToEndpoints() {
        XCTAssertEqual(project(progress: 0), base)
        XCTAssertEqual(project(progress: -1), base)
        XCTAssertEqual(project(progress: -Double.greatestFiniteMagnitude), base)
        let end = project(progress: 1)
        XCTAssertNotEqual(end, base)
        XCTAssertEqual(project(progress: 2), end)
        XCTAssertEqual(project(progress: Double.greatestFiniteMagnitude), end)
        XCTAssertEqual(Set(end.keys), Set(base.keys))
    }

    func testEndpointSurroundsExactSelectedRegionWithoutAddingRecords() throws {
        let end = project(progress: 1)
        for id in base.keys {
            let point = try XCTUnwrap(end[id])
            let x = (point.x - target.midX) / (target.width / 2 + 22)
            let y = (point.y - target.midY) / (target.height / 2 + 22)
            XCTAssertEqual(x * x + y * y, 1, accuracy: 1e-12,
                "A central region has an unclipped elliptical attention boundary.")
        }
        XCTAssertEqual(end.count, base.count)
    }

    func testIntermediateArcsStayBoundedAndAreNotStraightTeleports() throws {
        let end = project(progress: 1)
        var sawCurve = false
        for progress in [0.01, 0.1, 0.25, 0.5, 0.75, 0.9, 0.99] {
            let positions = project(progress: progress)
            let t = progress * progress * (3 - 2 * progress)
            for (id, start) in base {
                let actual = try XCTUnwrap(positions[id])
                let finish = try XCTUnwrap(end[id])
                let straight = start * (1 - t) + finish * t
                let deviation = (actual - straight).length
                // The quadratic control is bounded to 60 px from its midpoint;
                // its maximum contribution is one half at the middle of the arc.
                XCTAssertLessThanOrEqual(deviation, 30 + 1e-10)
                sawCurve = sawCurve || deviation > 0.01
                assertInsideCanvas(actual)
            }
        }
        XCTAssertTrue(sawCurve, "The accepted transition must include an actual curved path.")
    }

    func testEdgeRegionClipsEndpointAndEntirePathToCanvasMargins() throws {
        let edgeRegion = CGRect(x: 0, y: 0, width: 20, height: 18)
        for progress in [0.0, 0.1, 0.5, 0.9, 1.0] {
            let positions = KnowledgeParticleField.regionPositions(base: base, target: edgeRegion,
                canvas: canvas, progress: progress)
            XCTAssertEqual(Set(positions.keys), Set(base.keys))
            for point in positions.values { assertInsideCanvas(point) }
            if progress == 1 {
                for point in positions.values {
                    XCTAssertGreaterThanOrEqual(point.x, 18)
                    XCTAssertGreaterThanOrEqual(point.y, 18)
                }
            }
        }
    }

    func testOrderAndVisibilityDoNotReshuffleAnyRemainingRecord() throws {
        let nodes: [CompanionGraphNode] = [
            node("companion:one", kind: .companion),
            node("lesson:two", kind: .lesson),
            node("source:three", kind: .source)
        ]
        let field = KnowledgeParticleField(snapshot: .init(nodes: nodes, edges: [], truncatedCount: 0))
        let framing = KnowledgeParticleField.framing(particles: field.particles, spread: 1, reduceMotion: true)
        let all = KnowledgeParticleField.displayPositions(particles: field.particles, frame: framing,
            spread: 1, reduceMotion: true, width: canvas.width, height: canvas.height)
        let remainingID = "lesson:two"
        let filtered = KnowledgeParticleField.displayPositions(
            particles: field.particles.filter { $0.nodeID == remainingID }, frame: framing,
            spread: 1, reduceMotion: true, width: canvas.width, height: canvas.height)
        let reordered = Dictionary(uniqueKeysWithValues: all.sorted { $0.key > $1.key })
        for progress in [0.0, 0.2, 0.5, 1.0] {
            let full = KnowledgeParticleField.regionPositions(base: all, target: target,
                canvas: canvas, progress: progress)
            let visible = KnowledgeParticleField.regionPositions(base: filtered, target: target,
                canvas: canvas, progress: progress)
            XCTAssertEqual(visible.keys.sorted(), [remainingID])
            XCTAssertEqual(try XCTUnwrap(visible[remainingID]), try XCTUnwrap(full[remainingID]))
            XCTAssertEqual(full, KnowledgeParticleField.regionPositions(base: reordered,
                target: target, canvas: canvas, progress: progress))
        }
    }

    func testAbsentOrInvalidRegionLeavesOriginalPositionsUntouched() {
        let invalid: [CGRect?] = [
            nil, .zero, .null, .infinite,
            CGRect(x: 40, y: 40, width: 0, height: 20),
            CGRect(x: 40, y: 40, width: 20, height: 0),
            // CGRect.width standardizes negative raw sizes. Reject the raw
            // selection instead of silently converting it to a different box.
            CGRect(x: 200, y: 200, width: -60, height: 40),
            CGRect(x: 200, y: 200, width: 60, height: -40),
            CGRect(x: -1, y: 20, width: 40, height: 40),
            CGRect(x: 620, y: 20, width: 40, height: 40),
            CGRect(x: 20, y: 460, width: 40, height: 40),
            CGRect(x: CGFloat.nan, y: 20, width: 40, height: 40),
            CGRect(x: 20, y: 20, width: CGFloat.infinity, height: 40)
        ]
        for region in invalid {
            XCTAssertEqual(KnowledgeParticleField.regionPositions(base: base, target: region,
                canvas: canvas, progress: 1), base)
        }
    }

    func testInvalidCanvasOrProgressDoesNotMoveAnchors() {
        for size in [CGSize.zero, CGSize(width: -640, height: 480), CGSize(width: 24, height: 480),
                     CGSize(width: 640, height: 24), CGSize(width: CGFloat.nan, height: 480),
                     CGSize(width: 640, height: CGFloat.infinity)] {
            XCTAssertEqual(KnowledgeParticleField.regionPositions(base: base, target: target,
                canvas: size, progress: 1), base)
        }
        for progress in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertEqual(project(progress: progress), base)
        }
        XCTAssertTrue(KnowledgeParticleField.regionPositions(base: [:], target: target,
            canvas: canvas, progress: 0.5).isEmpty)
    }

    func testLandscapeAndPortraitImagesUseActualLetterboxedFrame() {
        let square = CGSize(width: 600, height: 600)
        XCTAssertEqual(ImageRegionCanvas.imageFrame(pixelWidth: 1600, pixelHeight: 900, in: square),
            CGRect(x: 0, y: 131.25, width: 600, height: 337.5))
        XCTAssertEqual(ImageRegionCanvas.imageFrame(pixelWidth: 900, pixelHeight: 1600, in: square),
            CGRect(x: 131.25, y: 0, width: 337.5, height: 600))
        XCTAssertEqual(ImageRegionCanvas.imageFrame(pixelWidth: 1600, pixelHeight: 900,
            in: CGSize(width: 800, height: 450)), CGRect(x: 0, y: 0, width: 800, height: 450))
    }

    func testInvalidImageOrViewportHasNoSelectableFrame() {
        for (width, height) in [(0, 10), (10, 0), (-1, 10), (10, -1)] {
            XCTAssertEqual(ImageRegionCanvas.imageFrame(pixelWidth: width, pixelHeight: height,
                in: canvas), .zero)
        }
        for size in [CGSize.zero, CGSize(width: -1, height: 400), CGSize(width: 400, height: 0),
                     CGSize(width: CGFloat.nan, height: 400), CGSize(width: 400, height: CGFloat.infinity)] {
            XCTAssertEqual(ImageRegionCanvas.imageFrame(pixelWidth: 1600, pixelHeight: 900,
                in: size), .zero)
        }
    }

    private func project(progress: Double) -> [String: Vector] {
        KnowledgeParticleField.regionPositions(base: base, target: target, canvas: canvas, progress: progress)
    }

    private func assertInsideCanvas(_ point: Vector, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(point.x.isFinite && point.y.isFinite, file: file, line: line)
        XCTAssertGreaterThanOrEqual(point.x, 12 - 1e-10, file: file, line: line)
        XCTAssertGreaterThanOrEqual(point.y, 12 - 1e-10, file: file, line: line)
        XCTAssertLessThanOrEqual(point.x, canvas.width - 12 + 1e-10, file: file, line: line)
        XCTAssertLessThanOrEqual(point.y, canvas.height - 12 + 1e-10, file: file, line: line)
    }

    private func node(_ id: String, kind: CompanionGraphKind) -> CompanionGraphNode {
        .init(id: id, title: "Synthetic record", subtitle: "Geometry fixture", kind: kind,
            status: "Current", details: [], target: .memory)
    }
}
