import Foundation
import XCTest
import ARCHiSpatial
@testable import ARCHiDesktop

/// Synthetic geometry exercises the production field, projection and transient
/// motion owner. It does not inspect windows, capture content or measure FPS.
@MainActor
final class ParticleAttractionProjectionTests: XCTestCase {
    private typealias Vector = KnowledgeParticleField.Vector
    private let canvas = CGSize(width: 900, height: 650)
    private let target = CGRect(x: 560, y: 150, width: 240, height: 300)

    func testAppKitFramesMapToTopLeftAcrossNegativeAndUpperDisplays() throws {
        // A virtual desktop spanning a left/lower display, primary display and
        // upper display. AppKit Y increases upward; the overlay Y increases down.
        let overlay = CGRect(x: -1_280, y: -200, width: 3_200, height: 2_180)
        let cases: [(CGRect, CGRect)] = [
            (CGRect(x: -1_100, y: 40, width: 600, height: 300), CGRect(x: 180, y: 1_640, width: 600, height: 300)),
            (CGRect(x: 100, y: 120, width: 800, height: 500), CGRect(x: 1_380, y: 1_360, width: 800, height: 500)),
            (CGRect(x: 150, y: 1_250, width: 600, height: 500), CGRect(x: 1_430, y: 230, width: 600, height: 500))
        ]
        for (screen, expected) in cases {
            XCTAssertEqual(try XCTUnwrap(ParticleAttractionProjection.localFrame(screen, in: overlay)), expected)
        }
        XCTAssertEqual(ParticleAttractionProjection.localFrame(overlay, in: overlay), CGRect(origin: .zero, size: overlay.size))
        let frame = cases[0].0
        XCTAssertEqual(ParticleAttractionProjection.localFrame(frame.offsetBy(dx: 400, dy: 100),
            in: overlay.offsetBy(dx: 400, dy: 100)), cases[0].1,
            "Changing the desktop origin does not change relative overlay coordinates.")
    }

    func testImageLetterboxingPreservesAspectRatioAndRejectsInvalidDimensions() {
        let square = CGSize(width: 800, height: 800)
        XCTAssertEqual(ParticleAttractionProjection.imageFrame(pixels: CGSize(width: 1_920, height: 1_080), canvas: square),
            CGRect(x: 0, y: 175, width: 800, height: 450))
        XCTAssertEqual(ParticleAttractionProjection.imageFrame(pixels: CGSize(width: 1_080, height: 1_920), canvas: square),
            CGRect(x: 175, y: 0, width: 450, height: 800))
        XCTAssertEqual(ParticleAttractionProjection.imageFrame(pixels: square, canvas: square), CGRect(origin: .zero, size: square))
        for invalid in [CGSize.zero, CGSize(width: -1, height: 100), CGSize(width: CGFloat.nan, height: 100),
                        CGSize(width: 100, height: CGFloat.infinity)] {
            XCTAssertEqual(ParticleAttractionProjection.imageFrame(pixels: invalid, canvas: square), .zero)
            XCTAssertEqual(ParticleAttractionProjection.imageFrame(pixels: square, canvas: invalid), .zero)
        }
    }

    func testInvalidAndOutOfBoundsGeometryCannotProduceAttraction() throws {
        let field = try scene().field
        let overlay = CGRect(origin: .zero, size: canvas)
        for invalid in [CGRect.zero, CGRect(x: 0, y: 0, width: -20, height: 30),
                        CGRect(x: CGFloat.nan, y: 0, width: 20, height: 30),
                        CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 30),
                        CGRect(x: -10, y: 0, width: 40, height: 40),
                        CGRect(x: 890, y: 620, width: 40, height: 40)] {
            XCTAssertNil(ParticleAttractionProjection.localFrame(invalid, in: overlay))
            XCTAssertTrue(ParticleAttractionProjection.offsets(field: field, canvas: canvas, target: invalid).isEmpty)
        }
        XCTAssertNil(ParticleAttractionProjection.localFrame(target, in: .zero))
        XCTAssertTrue(ParticleAttractionProjection.base(field: field, canvas: .zero).isEmpty)
        XCTAssertTrue(ParticleAttractionProjection.base(field: field, canvas: canvas, origin: .zero).isEmpty)
        XCTAssertTrue(ParticleAttractionProjection.offsets(field: field, canvas: .zero, target: target).isEmpty)
        XCTAssertEqual(ParticleAttractionProjection.scale(for: .zero), 0)
        XCTAssertEqual(ParticleAttractionProjection.scale(for: CGSize(width: CGFloat.infinity, height: 100)), 0)
        for invalidScale in [0.0, -1, .nan, .infinity] {
            XCTAssertTrue(ParticleAttractionProjection.offsets(field: field, canvas: canvas, target: target,
                pointsPerUnit: invalidScale).isEmpty)
        }
    }

    func testStableRecordTargetsSurviveReorderingAndFilteringAndExcludeCore() throws {
        let first = try scene(ids: ["record-z", "core", "record-a"])
        let reordered = try scene(ids: ["record-a", "record-z", "core"])
        let origin = CGRect(x: 40, y: 100, width: 240, height: 200)
        let offsets = ParticleAttractionProjection.offsets(field: first.field, canvas: canvas, target: target, origin: origin)
        XCTAssertEqual(offsets, ParticleAttractionProjection.offsets(field: reordered.field, canvas: canvas, target: target, origin: origin))
        XCTAssertEqual(Set(offsets.keys), ["record-a", "record-z"])
        XCTAssertNil(offsets["core"], "Companion identity is never an attraction target.")
        let base = ParticleAttractionProjection.base(field: first.field, canvas: canvas, origin: origin)
        let endpoints = KnowledgeParticleField.regionPositions(base: base, target: target, canvas: canvas, progress: 1)
        let filtered = KnowledgeParticleField.regionPositions(base: base.filter { $0.key == "record-z" },
            target: target, canvas: canvas, progress: 1)
        XCTAssertEqual(filtered["record-z"], endpoints["record-z"], "Removing an earlier record cannot reassign this endpoint by rank.")
        let scale = ParticleAttractionProjection.scale(for: canvas)
        let positions = ParticleAttractionProjection.positions(base: base, offsets: offsets, pointsPerUnit: scale)
        XCTAssertEqual(positions["core"], base["core"])
        for (id, offset) in offsets {
            XCTAssertLessThanOrEqual(offset.length, 0.6)
            XCTAssertLessThanOrEqual(offset.length, CompanionParticleDynamics.maximumAttractionOffset)
            let delta = try XCTUnwrap(endpoints[id]) - XCTUnwrap(base[id])
            XCTAssertEqual(offset.length * scale, delta.length, accuracy: 1e-9,
                "Requested displacement preserves the actual distance instead of normalizing every target.")
            XCTAssertGreaterThan(offset.x * delta.x + offset.y * delta.y, 0)
            let position = try XCTUnwrap(positions[id]), end = try XCTUnwrap(endpoints[id])
            XCTAssertEqual(position.x, end.x, accuracy: 1e-9)
            XCTAssertEqual(position.y, end.y, accuracy: 1e-9)
        }
    }

    func testActualPositionsUseStableScaleAndIgnoreMissingExtraOrInvalidOffsets() throws {
        let base: [String: Vector] = ["a": .init(x: 40, y: 70), "b": .init(x: 140, y: 170)]
        let offsets: [String: Vector] = ["a": .init(x: 0.2, y: -0.1), "unknown": .init(x: 1, y: 1)]
        XCTAssertEqual(ParticleAttractionProjection.positions(base: base, offsets: offsets, pointsPerUnit: 1_000),
            ["a": .init(x: 240, y: -30), "b": .init(x: 140, y: 170)])
        XCTAssertEqual(ParticleAttractionProjection.positions(base: base, offsets: [:], pointsPerUnit: 1_000), base)
        for invalid in [0.0, -1, .nan, .infinity] {
            XCTAssertEqual(ParticleAttractionProjection.positions(base: base, offsets: offsets, pointsPerUnit: invalid), base)
        }
        XCTAssertEqual(ParticleAttractionProjection.positions(base: base,
            offsets: ["a": .init(x: .nan, y: 1), "b": .init(x: .infinity, y: 1)], pointsPerUnit: 1_000), base)

        let field = try scene().field
        let fieldBase = ParticleAttractionProjection.base(field: field, canvas: canvas)
        let desktopScale = ParticleAttractionProjection.scale(for: CGSize(width: 3_200, height: 2_180))
        let requested = ParticleAttractionProjection.offsets(field: field, canvas: canvas, target: target, pointsPerUnit: desktopScale)
        let positions = ParticleAttractionProjection.positions(base: fieldBase, offsets: requested, pointsPerUnit: desktopScale)
        let ends = KnowledgeParticleField.regionPositions(base: fieldBase, target: target, canvas: canvas, progress: 1)
        for id in requested.keys {
            XCTAssertEqual(try XCTUnwrap(positions[id]).x, try XCTUnwrap(ends[id]).x, accuracy: 1e-9)
            XCTAssertEqual(try XCTUnwrap(positions[id]).y, try XCTUnwrap(ends[id]).y, accuracy: 1e-9)
        }
    }

    func testRealFieldProjectionAdvancesOnlyAfterSharedPhysicsMovesTheRecord() throws {
        let scene = try scene(ids: ["record-a"])
        let motion = CompanionParticleMotion()
        motion.reconcile(scene: scene)
        let base = ParticleAttractionProjection.base(field: scene.field, canvas: canvas)
        let scale = ParticleAttractionProjection.scale(for: canvas)
        let offsets = ParticleAttractionProjection.offsets(field: scene.field, canvas: canvas, target: target)
        let lease = try XCTUnwrap(motion.beginAttraction(sceneDigest: scene.motionID))
        XCTAssertTrue(motion.updateAttraction(lease: lease, sceneDigest: scene.motionID, offsets: offsets, time: 10))
        let initial = motion.snapshot(sceneDigest: scene.motionID)
        XCTAssertEqual(initial.attractionProgress, ["record-a": 0])
        XCTAssertEqual(ParticleAttractionProjection.positions(base: base, offsets: initial.offsets, pointsPerUnit: scale),
            base, "Admitting a target cannot teleport the field.")
        _ = motion.sample(sceneDigest: scene.motionID, time: 10, active: true, reduceMotion: false)
        var sampled = initial
        for tick in 1...30 {
            let time = 10 + Double(tick) / 30
            XCTAssertTrue(motion.updateAttraction(lease: lease, sceneDigest: scene.motionID, offsets: offsets, time: time))
            sampled = motion.sample(sceneDigest: scene.motionID, time: time, active: true, reduceMotion: false)
        }
        let progress = try XCTUnwrap(sampled.attractionProgress["record-a"])
        XCTAssertGreaterThan(progress, 0.02)
        XCTAssertLessThanOrEqual(progress, 1)
        XCTAssertGreaterThan(try XCTUnwrap(sampled.offsets["record-a"]).length, 0.01)
        let projected = ParticleAttractionProjection.positions(base: base, offsets: sampled.offsets, pointsPerUnit: scale)
        XCTAssertNotEqual(projected["record-a"], base["record-a"])
        let repeated = motion.sample(sceneDigest: scene.motionID, time: 11, active: true, reduceMotion: false)
        XCTAssertEqual(repeated, sampled, "A second surface shares the already advanced frame.")
        XCTAssertEqual(ParticleAttractionProjection.positions(base: base, offsets: repeated.offsets, pointsPerUnit: scale), projected)
        XCTAssertTrue(scene.growthByRecordID.isEmpty)
        XCTAssertEqual(scene.graph.nodes.map(\.id), ["record-a"])
        motion.endAttraction(lease: lease)
        XCTAssertTrue(motion.snapshot(sceneDigest: scene.motionID).attractionProgress.isEmpty)
    }

    func testCloserAndFartherTargetsAlongSameRayCannotTeleportAnExistingPhysicsSample() throws {
        let scene = try scene(ids: ["record-a"]), field = scene.field
        let base = ParticleAttractionProjection.base(field: field, canvas: canvas)
        let scale = ParticleAttractionProjection.scale(for: canvas)
        let original = CGRect(x: 540, y: 240, width: 80, height: 80)
        let originalEnd = try XCTUnwrap(KnowledgeParticleField.regionPositions(base: base, target: original,
            canvas: canvas, progress: 1)["record-a"])
        let delta = originalEnd - (try XCTUnwrap(base["record-a"]))
        let direction = delta * (1 / delta.length)
        let closer = original.offsetBy(dx: direction.x * -30, dy: direction.y * -30)
        let farther = original.offsetBy(dx: direction.x * 60, dy: direction.y * 60)
        let initial = ParticleAttractionProjection.offsets(field: field, canvas: canvas, target: original)
        let near = ParticleAttractionProjection.offsets(field: field, canvas: canvas, target: closer)
        let far = ParticleAttractionProjection.offsets(field: field, canvas: canvas, target: farther)
        let initialOffset = try XCTUnwrap(initial["record-a"])
        XCTAssertLessThan(try XCTUnwrap(near["record-a"]).length, initialOffset.length)
        XCTAssertGreaterThan(try XCTUnwrap(far["record-a"]).length, initialOffset.length)
        for requested in [near, far] {
            let offset = try XCTUnwrap(requested["record-a"])
            XCTAssertEqual(offset.x * initialOffset.y - offset.y * initialOffset.x, 0, accuracy: 1e-12)
        }

        let motion = CompanionParticleMotion()
        motion.reconcile(scene: scene)
        let lease = try XCTUnwrap(motion.beginAttraction(sceneDigest: scene.motionID))
        XCTAssertTrue(motion.updateAttraction(lease: lease, sceneDigest: scene.motionID, offsets: initial, time: 10))
        _ = motion.sample(sceneDigest: scene.motionID, time: 10, active: true, reduceMotion: false)
        var time = 10 + 1.0 / 30
        _ = motion.sample(sceneDigest: scene.motionID, time: time, active: true, reduceMotion: false)
        for requested in [near, far] {
            let held = motion.snapshot(sceneDigest: scene.motionID)
            let displayed = ParticleAttractionProjection.positions(base: base, offsets: held.offsets, pointsPerUnit: scale)
            XCTAssertTrue(motion.updateAttraction(lease: lease, sceneDigest: scene.motionID, offsets: requested, time: time))
            let accepted = motion.snapshot(sceneDigest: scene.motionID)
            XCTAssertEqual(accepted.offsets, held.offsets)
            XCTAssertEqual(ParticleAttractionProjection.positions(base: base, offsets: accepted.offsets, pointsPerUnit: scale), displayed,
                "Retargeting changes force input, not the position represented by a held sample.")
            time += 1.0 / 30
            let advanced = motion.sample(sceneDigest: scene.motionID, time: time, active: true, reduceMotion: false)
            XCTAssertNotEqual(advanced.offsets, held.offsets)
            XCTAssertNotEqual(ParticleAttractionProjection.positions(base: base, offsets: advanced.offsets, pointsPerUnit: scale), displayed)
        }
    }

    func testDesktopDepartureUsesTheAvatars256PointDrawingTransform() throws {
        let field = try scene().field
        let origin = CGRect(x: 83, y: 127, width: 128 * 0.89, height: 128 * 0.89)
        let framing = KnowledgeParticleField.framing(particles: field.particles, spread: 1, reduceMotion: true)
        let avatar = KnowledgeParticleField.displayPositions(particles: field.particles, frame: framing,
            spread: 1, reduceMotion: true, width: 256, height: 256)
        let actual = ParticleAttractionProjection.base(field: field, canvas: canvas, origin: origin)
        for particle in field.particles {
            let point = try XCTUnwrap(avatar[particle.nodeID])
            let departure = try XCTUnwrap(actual[particle.nodeID])
            XCTAssertEqual(departure.x, origin.minX + point.x * origin.width / 256, accuracy: 1e-12)
            XCTAssertEqual(departure.y, origin.minY + point.y * origin.height / 256, accuracy: 1e-12)
        }
    }

    func testNormalizedDesktopAreaFlipsOnceAndScalesWithTheChosenWindow() throws {
        let region = try XCTUnwrap(ImageRegionRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        let window = CGRect(x: -500, y: 30, width: 400, height: 300)
        let area = try XCTUnwrap(ParticleAttractionProjection.desktopAreaFrame(region, in: window))
        XCTAssertEqual(area.minX, -460, accuracy: 1e-10)
        XCTAssertEqual(area.minY, 150, accuracy: 1e-10)
        XCTAssertEqual(area.width, 120, accuracy: 1e-10)
        XCTAssertEqual(area.height, 120, accuracy: 1e-10)
        let overlay = try XCTUnwrap(ParticleAttractionProjection.desktopOverlay(displayFrames: [
            CGRect(x: -1_280, y: -200, width: 1_280, height: 1_024), CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        ]))
        let localWindow = try XCTUnwrap(ParticleAttractionProjection.localFrame(window, in: overlay))
        let localArea = try XCTUnwrap(ParticleAttractionProjection.localFrame(area, in: overlay))
        let expected = region.displayed(in: localWindow)
        XCTAssertEqual(localArea.minX, expected.minX, accuracy: 1e-10)
        XCTAssertEqual(localArea.minY, expected.minY, accuracy: 1e-10)
        XCTAssertEqual(localArea.size, expected.size)
        XCTAssertEqual(ParticleAttractionProjection.desktopAreaFrame(nil, in: window), window)
        XCTAssertNil(ParticleAttractionProjection.desktopAreaFrame(region, in: .zero))
        let resized = CGRect(x: 200, y: -80, width: 800, height: 600)
        let resizedArea = try XCTUnwrap(ParticleAttractionProjection.desktopAreaFrame(region, in: resized))
        XCTAssertEqual(resizedArea.minX, 280, accuracy: 1e-10)
        XCTAssertEqual(resizedArea.minY, 160, accuracy: 1e-10)
        XCTAssertEqual(resizedArea.size, CGSize(width: 240, height: 240))
    }

    func testFixedDesktopExtentRetainsTravellingParticlesWhenWindowMovesBack() throws {
        let desktop = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let overlay = try XCTUnwrap(ParticleAttractionProjection.desktopOverlay(displayFrames: [desktop]))
        let originScreen = CGRect(x: 100, y: 100, width: 114, height: 114)
        let farScreen = CGRect(x: 1_200, y: 100, width: 400, height: 400)
        let nearScreen = CGRect(x: 250, y: 100, width: 400, height: 400)
        let field = try scene(ids: ["record-a", "record-z"]).field
        let origin = try XCTUnwrap(ParticleAttractionProjection.localFrame(originScreen, in: overlay))
        let far = try XCTUnwrap(ParticleAttractionProjection.localFrame(farScreen, in: overlay))
        let near = try XCTUnwrap(ParticleAttractionProjection.localFrame(nearScreen, in: overlay))
        let scale = ParticleAttractionProjection.scale(for: desktop.size)
        let base = ParticleAttractionProjection.base(field: field, canvas: overlay.size, origin: origin)
        let held = ParticleAttractionProjection.offsets(field: field, canvas: overlay.size, target: far,
            origin: origin, pointsPerUnit: scale)
        let travelling = ParticleAttractionProjection.positions(base: base, offsets: held, pointsPerUnit: scale)
        let next = ParticleAttractionProjection.offsets(field: field, canvas: overlay.size, target: near,
            origin: origin, pointsPerUnit: scale)
        XCTAssertNotEqual(held, next)
        let oldShrinkingExtent = originScreen.union(nearScreen).insetBy(dx: -26, dy: -26)
        let globalPoints = travelling.values.map { CGPoint(x: overlay.minX + $0.x, y: overlay.maxY - $0.y) }
        XCTAssertTrue(globalPoints.allSatisfy { overlay.contains($0) })
        XCTAssertTrue(globalPoints.contains { !oldShrinkingExtent.contains($0) },
            "The previous target-union panel cropped physical positions before the field could return.")
        XCTAssertEqual(ParticleAttractionProjection.positions(base: base, offsets: held, pointsPerUnit: scale), travelling)
        XCTAssertNil(ParticleAttractionProjection.desktopOverlay(displayFrames: []))
        XCTAssertNil(ParticleAttractionProjection.desktopOverlay(displayFrames: [.zero]))
    }

    func testWithdrawnAnchorsRemainVisibleButCannotRejectOtherAttractionTargets() throws {
        var withdrawn = CompanionGraphNode(id: "withdrawn", title: "Withdrawn page", subtitle: "Synthetic",
            kind: .knowledge, status: "Withdrawn", details: [], target: .memory)
        withdrawn.presentationState = .withdrawn
        let retained = CompanionGraphNode(id: "current", title: "Current page", subtitle: "Synthetic",
            kind: .knowledge, status: "Retained", details: [], target: .memory)
        let graph = CompanionGraphSnapshot(nodes: [withdrawn, retained], edges: [], truncatedCount: 0)
        let scene = try XCTUnwrap(CompanionParticleScene.build(originDigest: String(repeating: "a", count: 64),
            graph: graph, development: nil, sessionID: "00000000-0000-4000-8000-000000000001"))
        let motion = CompanionParticleMotion()
        motion.reconcile(scene: scene)
        let lease = try XCTUnwrap(motion.beginAttraction(sceneDigest: scene.motionID))
        let unqualified = ParticleAttractionProjection.offsets(field: scene.field, canvas: canvas, target: target)
        XCTAssertTrue(unqualified.keys.contains("withdrawn"))
        XCTAssertFalse(motion.updateAttraction(lease: lease, sceneDigest: scene.motionID,
            offsets: unqualified, time: 10), "This reproduces the original whole-request rejection.")
        let qualified = ParticleAttractionProjection.offsets(scene: scene, canvas: canvas, target: target)
        XCTAssertEqual(Set(qualified.keys), ["current"])
        XCTAssertTrue(motion.updateAttraction(lease: lease, sceneDigest: scene.motionID, offsets: qualified, time: 10))
        _ = motion.sample(sceneDigest: scene.motionID, time: 10, active: true, reduceMotion: false)
        let sample = motion.sample(sceneDigest: scene.motionID, time: 10 + 1.0 / 30, active: true, reduceMotion: false)
        XCTAssertGreaterThan(try XCTUnwrap(sample.offsets["current"]).length, 0)
        XCTAssertNil(sample.offsets["withdrawn"])
        let base = ParticleAttractionProjection.base(field: scene.field, canvas: canvas)
        let shown = ParticleAttractionProjection.positions(base: base, offsets: sample.offsets,
            pointsPerUnit: ParticleAttractionProjection.scale(for: canvas))
        XCTAssertEqual(Set(shown.keys), ["withdrawn", "current"])
        XCTAssertEqual(shown["withdrawn"], base["withdrawn"])
    }

    private func scene(ids: [String] = ["record-a", "core", "record-z"]) throws -> CompanionParticleScene {
        let graph = CompanionGraphSnapshot(nodes: ids.map {
            .init(id: $0, title: "Synthetic \($0)", subtitle: "Projection fixture", kind: $0 == "core" ? .companion : .knowledge,
                status: "Retained", details: [], target: .memory)
        }, edges: [], truncatedCount: 0)
        return try XCTUnwrap(CompanionParticleScene.build(originDigest: String(repeating: "a", count: 64), graph: graph,
            development: nil, sessionID: "00000000-0000-4000-8000-000000000001"))
    }
}
