import XCTest
@testable import ARCHiDesktop

@MainActor
final class CompanionParticleMotionTests: XCTestCase {
    func testDisplayAcknowledgmentCannotResampleTimeAndWallClockChangesDoNotChangeSimulationClock() {
        var uptime = 10.0
        let clock = ParticlePresentationClock(uptime: { uptime })
        let tick = Date(timeIntervalSinceReferenceDate: 100)
        XCTAssertEqual(clock.time(for: tick), 10)
        uptime = 20
        XCTAssertEqual(clock.time(for: tick), 10, "GPU acknowledgment uses the already scheduled frame time")
        XCTAssertEqual(clock.time(for: tick.addingTimeInterval(-500)), 20, "A changed wall clock cannot rewind simulation time")
        uptime = 21
        XCTAssertEqual(clock.time(for: tick.addingTimeInterval(500)), 21)
    }

    private typealias Vector = KnowledgeParticleField.Vector
    private let session = "00000000-0000-4000-8000-000000000001"

    func testRealSceneStartsSettlingAndMultipleSurfacesShareExactlyOneClock() throws {
        let scene = try makeScene()
        let motion = CompanionParticleMotion(), control = CompanionParticleMotion()
        motion.reconcile(scene: scene); control.reconcile(scene: scene)
        let first = motion.sample(sceneDigest: scene.motionID, time: 100, active: true, reduceMotion: false)
        _ = control.sample(sceneDigest: scene.motionID, time: 100, active: true, reduceMotion: false)
        let moved = motion.sample(sceneDigest: scene.motionID, time: 100.02, active: true, reduceMotion: false)
        XCTAssertNotEqual(first.offsets, moved.offsets, "A display step must advance positions, not only opacity.")
        XCTAssertGreaterThan(moved.revision, first.revision)
        XCTAssertEqual(moved, motion.sample(sceneDigest: scene.motionID, time: 100.02, active: true, reduceMotion: false))
        XCTAssertEqual(moved, motion.sample(sceneDigest: scene.motionID, time: 100.0201, active: true, reduceMotion: false))
        XCTAssertEqual(moved, motion.sample(sceneDigest: scene.motionID, time: 99, active: true, reduceMotion: false))
        XCTAssertEqual(moved, motion.snapshot(sceneDigest: scene.motionID))
        XCTAssertEqual(moved, control.sample(sceneDigest: scene.motionID, time: 100.02, active: true, reduceMotion: false))
        motion.reconcile(scene: scene)
        XCTAssertEqual(moved, motion.snapshot(sceneDigest: scene.motionID), "A second surface must not restart the same scene.")
    }

    func testHiddenSnapshotDoesNotStopVisibleDriverAndLongGapsNeverCatchUp() throws {
        let scene = try makeScene()
        let motion = CompanionParticleMotion()
        motion.reconcile(scene: scene)
        _ = motion.sample(sceneDigest: scene.motionID, time: 10, active: true, reduceMotion: false)
        let before = motion.snapshot(sceneDigest: scene.motionID)
        XCTAssertEqual(motion.snapshot(sceneDigest: scene.motionID), before)
        let moving = motion.sample(sceneDigest: scene.motionID, time: 10.02, active: true, reduceMotion: false)
        XCTAssertNotEqual(moving, before)
        XCTAssertEqual(motion.sample(sceneDigest: scene.motionID, time: 200, active: true, reduceMotion: false), moving)
        XCTAssertNotEqual(motion.sample(sceneDigest: scene.motionID, time: 200.02, active: true, reduceMotion: false), moving)
    }

    func testInactiveAndReducedMotionFreezeAndResumeWithoutAccumulatedTime() throws {
        let scene = try makeScene()
        for reduced in [false, true] {
            let motion = CompanionParticleMotion()
            motion.reconcile(scene: scene)
            XCTAssertTrue(motion.grab(nodeID: "a", offset: .init(x: 0.2, y: 0), sceneDigest: scene.motionID))
            let frozen = motion.snapshot(sceneDigest: scene.motionID)
            XCTAssertEqual(motion.sample(sceneDigest: scene.motionID, time: 20, active: reduced, reduceMotion: reduced), frozen)
            XCTAssertEqual(motion.sample(sceneDigest: scene.motionID, time: 200, active: reduced, reduceMotion: reduced), frozen)
            XCTAssertEqual(motion.sample(sceneDigest: scene.motionID, time: 300, active: true, reduceMotion: false), frozen)
            let resumed = motion.sample(sceneDigest: scene.motionID, time: 300.02, active: true, reduceMotion: false)
            XCTAssertNotEqual(resumed.offsets, frozen.offsets, "Pausing also revokes the held gesture, allowing its release to settle.")
        }
    }

    func testTopologyReconciliationPreservesAbsolutePositionAndVelocityAndRemovesWithdrawnBodies() throws {
        let original = try makeScene(ids: ["a", "b"])
        var dynamics = CompanionParticleDynamics()
        dynamics.reconcile(scene: original)
        XCTAssertTrue(dynamics.grab(nodeID: "a", offset: .init(x: 0.2, y: 0.1)))
        dynamics.release(nodeID: "a")
        for _ in 0..<8 { dynamics.step(1.0 / 120) }
        let previous = try XCTUnwrap(dynamics.bodies["a"])
        let expanded = try makeScene(ids: ["a", "b", "c"])
        dynamics.reconcile(scene: expanded)
        let continuing = try XCTUnwrap(dynamics.bodies["a"])
        XCTAssertNotEqual(previous.rest, continuing.rest, "The fixture must exercise a changed rest layout.")
        XCTAssertEqual(continuing.position, previous.position)
        XCTAssertEqual(continuing.velocity, previous.velocity)
        let added = try XCTUnwrap(dynamics.bodies["c"])
        XCTAssertEqual(added.position, added.rest)
        XCTAssertGreaterThan(added.velocity.length, 0)
        XCTAssertTrue(dynamics.grab(nodeID: "a", offset: .init(x: 0.1, y: 0)))
        dynamics.reconcile(scene: try makeScene(ids: ["a", "c"], withdrawn: ["a"]))
        XCTAssertEqual(Set(dynamics.bodies.keys), ["c"])
        XCTAssertFalse(dynamics.grab(nodeID: "a", offset: .zero))
        dynamics.step(1.0 / 120)
        XCTAssertEqual(Set(dynamics.offsets.keys), ["c"])
    }

    func testRestoredIdenticalGraphRejectsOldMotionIdentityAndOriginResetClearsMotion() throws {
        let first = try makeScene()
        let restored = try makeScene(sessionID: "00000000-0000-4000-8000-000000000002")
        XCTAssertEqual(first.digest, restored.digest)
        XCTAssertNotEqual(first.motionID, restored.motionID)
        let motion = CompanionParticleMotion()
        motion.reconcile(scene: first)
        XCTAssertTrue(motion.grab(nodeID: "a", offset: .init(x: 0.2, y: 0), sceneDigest: first.motionID))
        motion.reconcile(scene: restored)
        XCTAssertEqual(motion.snapshot(sceneDigest: first.motionID), .still)
        XCTAssertEqual(motion.sample(sceneDigest: first.motionID, time: 12, active: true, reduceMotion: false), .still)
        XCTAssertFalse(motion.grab(nodeID: "a", offset: .zero, sceneDigest: first.motionID))
        XCTAssertEqual(motion.snapshot(sceneDigest: restored.motionID).offsets["a"], .zero)
        XCTAssertTrue(motion.grab(nodeID: "a", offset: .init(x: 0.1, y: 0), sceneDigest: restored.motionID))
        motion.release(nodeID: "a", sceneDigest: first.motionID)
        _ = motion.sample(sceneDigest: restored.motionID, time: 20, active: true, reduceMotion: false)
        XCTAssertEqual(motion.sample(sceneDigest: restored.motionID, time: 20.02, active: true, reduceMotion: false).offsets["a"]?.x ?? 0, 0.1, accuracy: 1e-12)
        let foreign = try makeScene(sessionID: restored.sessionID, origin: String(repeating: "d", count: 64))
        motion.reconcile(scene: foreign)
        XCTAssertEqual(motion.snapshot(sceneDigest: restored.motionID), .still)
        XCTAssertEqual(motion.snapshot(sceneDigest: foreign.motionID).offsets["a"], .zero)
        motion.reset()
        XCTAssertEqual(motion.snapshot(sceneDigest: foreign.motionID), .still)
    }

    func testInvalidAndStaleGesturesCannotMutateFrameAndLargeGrabsAreBounded() throws {
        let scene = try makeScene()
        let motion = CompanionParticleMotion()
        motion.reconcile(scene: scene)
        let initial = motion.snapshot(sceneDigest: scene.motionID)
        XCTAssertFalse(motion.grab(nodeID: "absent", offset: .zero, sceneDigest: scene.motionID))
        XCTAssertFalse(motion.grab(nodeID: "a", offset: .init(x: .nan, y: 0), sceneDigest: scene.motionID))
        XCTAssertFalse(motion.grab(nodeID: "a", offset: .init(x: 0, y: .infinity), sceneDigest: scene.motionID))
        XCTAssertFalse(motion.grab(nodeID: "a", offset: .zero, sceneDigest: scene.digest))
        XCTAssertEqual(motion.snapshot(sceneDigest: scene.motionID), initial)
        XCTAssertEqual(motion.sample(sceneDigest: scene.motionID, time: .nan, active: true, reduceMotion: false), initial)
        XCTAssertTrue(motion.grab(nodeID: "a", offset: .init(x: 90, y: -90), sceneDigest: scene.motionID))
        XCTAssertEqual(try XCTUnwrap(motion.snapshot(sceneDigest: scene.motionID).offsets["a"]).length, 0.25, accuracy: 1e-12)
        motion.cancelInteraction()
        _ = motion.sample(sceneDigest: scene.motionID, time: 30, active: true, reduceMotion: false)
        XCTAssertLessThan(try XCTUnwrap(motion.sample(sceneDigest: scene.motionID, time: 30.03, active: true, reduceMotion: false).offsets["a"]).length, 0.25)
    }

    func testReleasedMovementTransfersThroughExistingLinksAndSettlesWithoutNewEdges() throws {
        let scene = try makeScene(ids: ["a", "b"], linked: true)
        var control = CompanionParticleDynamics(); control.reconcile(scene: scene)
        var pulled = control
        let a = try XCTUnwrap(pulled.bodies["a"]), b = try XCTUnwrap(pulled.bodies["b"])
        let away = (a.rest - b.rest) * (0.2 / (a.rest - b.rest).length)
        XCTAssertTrue(pulled.grab(nodeID: "a", offset: away))
        for _ in 0..<12 { control.step(1.0 / 120); pulled.step(1.0 / 120) }
        let response = try XCTUnwrap(pulled.bodies["b"]).position - XCTUnwrap(control.bodies["b"]).position
        XCTAssertGreaterThan(response.x * away.x + response.y * away.y, 0, "The recorded neighbour must respond to the displaced anchor.")
        pulled.release(nodeID: "a")
        for _ in 0..<3600 { pulled.step(1.0 / 120) }
        for body in pulled.bodies.values {
            XCTAssertLessThan((body.position - body.rest).length, 1e-5)
            XCTAssertLessThan(body.velocity.length, 1e-5)
        }
        XCTAssertEqual(scene.graph.edges.count, 1)
    }

    func testReviewedSupportChangesDampedResponseAndRevocationRestoresUnreviewedResponse() throws {
        let plainScene = try makeScene(ids: ["a"])
        let reviewedScene = try makeScene(ids: ["a"], reviewed: 8)
        var plain = CompanionParticleDynamics(); plain.reconcile(scene: plainScene)
        var reviewed = CompanionParticleDynamics(); reviewed.reconcile(scene: reviewedScene)
        _ = plain.grab(nodeID: "a", offset: .init(x: 0.2, y: 0))
        _ = reviewed.grab(nodeID: "a", offset: .init(x: 0.2, y: 0))
        plain.release(nodeID: "a"); reviewed.release(nodeID: "a")
        for _ in 0..<12 { plain.step(1.0 / 120); reviewed.step(1.0 / 120) }
        XCTAssertLessThan(try XCTUnwrap(reviewed.bodies["a"]).velocity.length, try XCTUnwrap(plain.bodies["a"]).velocity.length)
        XCTAssertNotEqual(reviewed.offsets, plain.offsets)
        let old = try XCTUnwrap(reviewed.bodies["a"])
        reviewed.reconcile(scene: plainScene)
        XCTAssertEqual(try XCTUnwrap(reviewed.bodies["a"]).position, old.position)
        XCTAssertEqual(try XCTUnwrap(reviewed.bodies["a"]).velocity, old.velocity)
        // Reapply the same public gesture to equalize position/velocity; the
        // next real response must now match the unreviewed dynamics exactly.
        _ = plain.grab(nodeID: "a", offset: .init(x: 0.2, y: 0))
        _ = reviewed.grab(nodeID: "a", offset: .init(x: 0.2, y: 0))
        plain.release(nodeID: "a"); reviewed.release(nodeID: "a")
        for _ in 0..<24 { plain.step(1.0 / 120); reviewed.step(1.0 / 120) }
        XCTAssertEqual(reviewed.offsets, plain.offsets)
        XCTAssertEqual(reviewed.bodies["a"]?.velocity, plain.bodies["a"]?.velocity)
    }

    func testMaximumSceneAndLongRunStayFiniteAndBounded() throws {
        let scene = try makeScene(ids: (0..<220).map { "record-\($0)" })
        var dense = CompanionParticleDynamics(); dense.reconcile(scene: scene)
        XCTAssertEqual(dense.bodies.count, 220)
        for id in dense.bodies.keys.sorted().prefix(8) {
            XCTAssertTrue(dense.grab(nodeID: id, offset: .init(x: 100, y: -100)))
        }
        dense.cancelInteraction()
        for _ in 0..<24 { dense.step(1.0 / 120) }
        assertBounded(dense)
        var long = CompanionParticleDynamics(); long.reconcile(scene: try makeScene(ids: (0..<8).map { "record-\($0)" }))
        _ = long.grab(nodeID: "record-0", offset: .init(x: -100, y: 100)); long.release(nodeID: "record-0")
        for index in 0..<3600 {
            long.step(index == 20 ? 10 : 1.0 / 120)
            if index.isMultiple(of: 120) { assertBounded(long) }
        }
        assertBounded(long)
    }

    func testSettledDynamicsSleepWithoutDriftAndWakeForGrabReleaseAndNewRecords() throws {
        var dynamics = CompanionParticleDynamics()
        dynamics.reconcile(scene: try makeScene(ids: ["a"]))
        for _ in 0..<2400 { dynamics.step(1.0 / 120) }
        XCTAssertTrue(dynamics.isSleeping)
        let sleeping = try XCTUnwrap(dynamics.bodies["a"])
        for _ in 0..<240 { dynamics.step(1.0 / 120) }
        XCTAssertEqual(dynamics.bodies["a"]?.position, sleeping.position)
        XCTAssertEqual(dynamics.bodies["a"]?.velocity, .zero)
        XCTAssertTrue(dynamics.grab(nodeID: "a", offset: .init(x: 0.2, y: 0)))
        XCTAssertFalse(dynamics.isSleeping)
        for _ in 0..<24 { dynamics.step(1.0 / 120) }
        XCTAssertTrue(dynamics.isSleeping, "A stationary held anchor does not require an endless force loop.")
        dynamics.release(nodeID: "a")
        XCTAssertFalse(dynamics.isSleeping)
        let released = dynamics.offsets
        dynamics.step(1.0 / 120)
        XCTAssertNotEqual(dynamics.offsets, released)
        for _ in 0..<2400 { dynamics.step(1.0 / 120) }
        XCTAssertTrue(dynamics.isSleeping)
        dynamics.reconcile(scene: try makeScene(ids: ["a", "b"]))
        XCTAssertFalse(dynamics.isSleeping)
        XCTAssertGreaterThan(try XCTUnwrap(dynamics.bodies["b"]).velocity.length, 0)
    }

    func testMaximumDensityThirtyHzSampleCost() throws {
        let ids = (0..<220).map { "density-\($0)" }
        let edges = ids.indices.flatMap { index in
            [1, 7].map { distance in
                CompanionGraphEdge(id: "edge-\(index)-\(distance)", source: ids[index],
                    target: ids[(index + distance) % ids.count], label: "recorded dependency")
            }
        }
        let scene = try makeScene(ids: ids, recordedEdges: edges)
        let motion = CompanionParticleMotion()
        motion.reconcile(scene: scene)
        for id in ids.prefix(8) {
            XCTAssertTrue(motion.grab(nodeID: id, offset: .init(x: 0.15, y: -0.1), sceneDigest: scene.motionID))
        }
        motion.cancelInteraction()
        let start = motion.sample(sceneDigest: scene.motionID, time: 100, active: true, reduceMotion: false)
        var durations: [Double] = []
        var last = start
        for tick in 1...90 {
            let began = ProcessInfo.processInfo.systemUptime
            last = motion.sample(sceneDigest: scene.motionID, time: 100 + Double(tick) / 30,
                active: true, reduceMotion: false)
            durations.append((ProcessInfo.processInfo.systemUptime - began) * 1000)
        }
        let sorted = durations.sorted()
        let receipt: [String: Any] = ["schema": "archi-particle-motion-cost/v1", "nodes": ids.count,
            "recordedEdges": edges.count, "sampleHz": 30, "integrationHz": 120, "ticks": durations.count,
            "averageMs": durations.reduce(0, +) / Double(durations.count),
            "p95Ms": sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1], "worstMs": sorted.last!,
            "overThirtyHzBudget": durations.filter { $0 > 1000.0 / 30 }.count,
            "scope": "In-process simulation sample cost; excludes rendering, source projection and window composition."]
        let json = try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
        print("PARTICLE_MOTION_COST " + String(decoding: json, as: UTF8.self))
        XCTAssertEqual(last.offsets.count, 220)
        XCTAssertGreaterThan(last.revision, start.revision)
        XCTAssertTrue(last.offsets.values.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    func testAttractionUsesRealSpringDisplacementAndBoundedTargetThenSettlesAfterRelease() throws {
        let scene = try makeScene(ids: ["a"])
        let motion = CompanionParticleMotion(); motion.reconcile(scene: scene)
        let before = motion.snapshot(sceneDigest: scene.motionID)
        let lease = try XCTUnwrap(motion.beginAttraction(sceneDigest: scene.motionID))
        let target = Vector(x: 100, y: 0)
        XCTAssertTrue(motion.updateAttraction(lease: lease, sceneDigest: scene.motionID, offsets: ["a": target], time: 10))
        let admitted = motion.snapshot(sceneDigest: scene.motionID)
        XCTAssertEqual(admitted.offsets, before.offsets, "Admission must not teleport an anchor.")
        XCTAssertEqual(admitted.attractionProgress, ["a": 0])
        _ = motion.sample(sceneDigest: scene.motionID, time: 10, active: true, reduceMotion: false)
        let first = motion.sample(sceneDigest: scene.motionID, time: 10.02, active: true, reduceMotion: false)
        let firstOffset = try XCTUnwrap(first.offsets["a"])
        XCTAssertGreaterThan(firstOffset.x, 0)
        XCTAssertLessThan(firstOffset.x, CompanionParticleDynamics.maximumAttractionOffset)
        XCTAssertEqual(try XCTUnwrap(first.attractionProgress["a"]),
            firstOffset.x / CompanionParticleDynamics.maximumAttractionOffset, accuracy: 1e-12)
        XCTAssertEqual(first, motion.sample(sceneDigest: scene.motionID, time: 10.02, active: true, reduceMotion: false))
        var settled = first
        for tick in 1...360 {
            let time = 10.02 + Double(tick) / 30
            XCTAssertTrue(motion.updateAttraction(lease: lease, sceneDigest: scene.motionID, offsets: ["a": target], time: time))
            settled = motion.sample(sceneDigest: scene.motionID, time: time, active: true, reduceMotion: false)
        }
        XCTAssertEqual(try XCTUnwrap(settled.offsets["a"]).x, 0.65, accuracy: 1e-5)
        XCTAssertEqual(try XCTUnwrap(settled.offsets["a"]).y, 0, accuracy: 1e-5)
        XCTAssertGreaterThan(try XCTUnwrap(settled.attractionProgress["a"]), 0.999)
        motion.endAttraction(lease: lease)
        let released = motion.snapshot(sceneDigest: scene.motionID)
        XCTAssertEqual(released.offsets, settled.offsets)
        XCTAssertTrue(released.attractionProgress.isEmpty)
        XCTAssertFalse(motion.isAttractionCurrent(lease: lease, sceneDigest: scene.motionID))
        for tick in 1...360 {
            settled = motion.sample(sceneDigest: scene.motionID, time: 22.02 + Double(tick) / 30, active: true, reduceMotion: false)
        }
        XCTAssertLessThan(try XCTUnwrap(settled.offsets["a"]).length, 1e-5)
    }

    func testAttractionRejectsInvalidUpdatesAtomicallyAndNeverTargetsCompanionIdentity() throws {
        let scene = try makeScene(ids: ["a", "core"], companionIDs: ["core"])
        let motion = CompanionParticleMotion(); motion.reconcile(scene: scene)
        XCTAssertNil(motion.beginAttraction(sceneDigest: scene.digest))
        let lease = try XCTUnwrap(motion.beginAttraction(sceneDigest: scene.motionID))
        XCTAssertTrue(motion.updateAttraction(lease: lease, sceneDigest: scene.motionID,
            offsets: ["a": .init(x: 0.3, y: 0)], time: 10))
        let before = motion.snapshot(sceneDigest: scene.motionID)
        for invalid in [["a": Vector(x: .nan, y: 0)], ["a": Vector(x: 0, y: .infinity)],
                        ["unknown": .zero], ["core": Vector(x: 0.2, y: 0)],
                        ["a": Vector(x: 0.4, y: 0), "unknown": .zero]] {
            XCTAssertFalse(motion.updateAttraction(lease: lease, sceneDigest: scene.motionID, offsets: invalid, time: 10.1))
            XCTAssertEqual(motion.snapshot(sceneDigest: scene.motionID), before)
        }
        for time in [Double.nan, .infinity, -1, 9.9] {
            XCTAssertFalse(motion.updateAttraction(lease: lease, sceneDigest: scene.motionID,
                offsets: ["a": .init(x: 0.4, y: 0)], time: time))
        }
        XCTAssertFalse(motion.updateAttraction(lease: UUID(), sceneDigest: scene.motionID, offsets: [:], time: 10.1))
        XCTAssertFalse(motion.updateAttraction(lease: lease, sceneDigest: scene.digest, offsets: [:], time: 10.1))
        XCTAssertEqual(motion.snapshot(sceneDigest: scene.motionID), before)
        XCTAssertTrue(motion.updateAttraction(lease: lease, sceneDigest: scene.motionID, offsets: [:], time: 10.1))
        XCTAssertTrue(motion.snapshot(sceneDigest: scene.motionID).attractionProgress.isEmpty)
        XCTAssertTrue(motion.isAttractionCurrent(lease: lease, sceneDigest: scene.motionID))
    }

    func testNewAttractionLeaseRetiresOldProducerWithoutAllowingStaleEndOrUpdate() throws {
        let scene = try makeScene(ids: ["a", "b"])
        let motion = CompanionParticleMotion(); motion.reconcile(scene: scene)
        let old = try XCTUnwrap(motion.beginAttraction(sceneDigest: scene.motionID))
        XCTAssertTrue(motion.updateAttraction(lease: old, sceneDigest: scene.motionID,
            offsets: ["a": .init(x: 0.2, y: 0)], time: 10))
        let current = try XCTUnwrap(motion.beginAttraction(sceneDigest: scene.motionID))
        XCTAssertTrue(motion.snapshot(sceneDigest: scene.motionID).attractionProgress.isEmpty)
        XCTAssertTrue(motion.updateAttraction(lease: current, sceneDigest: scene.motionID,
            offsets: ["b": .init(x: 0, y: 0.3)], time: 10.1))
        let frame = motion.snapshot(sceneDigest: scene.motionID)
        motion.endAttraction(lease: old)
        XCTAssertFalse(motion.updateAttraction(lease: old, sceneDigest: scene.motionID, offsets: [:], time: 10.2))
        XCTAssertEqual(motion.snapshot(sceneDigest: scene.motionID), frame)
        XCTAssertTrue(motion.isAttractionCurrent(lease: current, sceneDigest: scene.motionID))
        XCTAssertEqual(Set(frame.attractionProgress.keys), ["b"])
        _ = motion.sample(sceneDigest: scene.motionID, time: 10.2, active: true, reduceMotion: false)
        XCTAssertFalse(motion.updateAttraction(lease: current, sceneDigest: scene.motionID, offsets: [:], time: 10.15),
            "An update older than the sampled frame must not replace its input.")
    }

    func testAttractionExpiresWithoutHiddenCatchupAndDelayedProducerCannotRenew() throws {
        let scene = try makeScene(ids: ["a"])
        let motion = CompanionParticleMotion(); motion.reconcile(scene: scene)
        let lease = try XCTUnwrap(motion.beginAttraction(sceneDigest: scene.motionID))
        XCTAssertTrue(motion.updateAttraction(lease: lease, sceneDigest: scene.motionID,
            offsets: ["a": .init(x: 0.3, y: 0)], time: 10))
        _ = motion.sample(sceneDigest: scene.motionID, time: 10, active: true, reduceMotion: false)
        _ = motion.sample(sceneDigest: scene.motionID, time: 10.1, active: true, reduceMotion: false)
        let before = motion.snapshot(sceneDigest: scene.motionID)
        XCTAssertTrue(motion.isAttractionCurrent(lease: lease, sceneDigest: scene.motionID))
        _ = motion.sample(sceneDigest: scene.motionID, time: 10.5, active: true, reduceMotion: false)
        XCTAssertTrue(motion.isAttractionCurrent(lease: lease, sceneDigest: scene.motionID), "The exact freshness boundary is inclusive.")
        let expired = motion.sample(sceneDigest: scene.motionID, time: 11, active: true, reduceMotion: false)
        XCTAssertEqual(expired.offsets, before.offsets, "Returning after a gap releases stale forces without hidden simulation catch-up.")
        XCTAssertTrue(expired.attractionProgress.isEmpty)
        XCTAssertFalse(motion.isAttractionCurrent(lease: lease, sceneDigest: scene.motionID))
        XCTAssertFalse(motion.updateAttraction(lease: lease, sceneDigest: scene.motionID, offsets: [:], time: 11))
        let next = try XCTUnwrap(motion.beginAttraction(sceneDigest: scene.motionID))
        XCTAssertTrue(motion.updateAttraction(lease: next, sceneDigest: scene.motionID,
            offsets: ["a": .init(x: 0.3, y: 0)], time: 11))
        XCTAssertFalse(motion.updateAttraction(lease: next, sceneDigest: scene.motionID,
            offsets: ["a": .init(x: 0.3, y: 0)], time: 11.5001))
        XCTAssertFalse(motion.isAttractionCurrent(lease: next, sceneDigest: scene.motionID))
    }

    func testAttractionClearsOnPauseChangedSceneReopenAndReset() throws {
        let scene = try makeScene(ids: ["a"])
        for reduced in [false, true] {
            let motion = CompanionParticleMotion(); motion.reconcile(scene: scene)
            let lease = try XCTUnwrap(motion.beginAttraction(sceneDigest: scene.motionID))
            XCTAssertTrue(motion.updateAttraction(lease: lease, sceneDigest: scene.motionID,
                offsets: ["a": .init(x: 0.3, y: 0)], time: 10))
            let paused = motion.sample(sceneDigest: scene.motionID, time: 10, active: reduced, reduceMotion: reduced)
            XCTAssertTrue(paused.attractionProgress.isEmpty)
            XCTAssertFalse(motion.isAttractionCurrent(lease: lease, sceneDigest: scene.motionID))
        }
        let motion = CompanionParticleMotion(); motion.reconcile(scene: scene)
        var currentScene = scene
        let changed = try makeScene(ids: ["a", "b"])
        let reopened = try makeScene(ids: ["a", "b"], sessionID: "00000000-0000-4000-8000-000000000002")
        for next in [changed, reopened] {
            let lease = try XCTUnwrap(motion.beginAttraction(sceneDigest: currentScene.motionID))
            XCTAssertTrue(motion.updateAttraction(lease: lease, sceneDigest: currentScene.motionID,
                offsets: ["a": .init(x: 0.3, y: 0)], time: 10))
            motion.reconcile(scene: currentScene)
            XCTAssertTrue(motion.isAttractionCurrent(lease: lease, sceneDigest: currentScene.motionID))
            motion.reconcile(scene: next)
            XCTAssertFalse(motion.isAttractionCurrent(lease: lease, sceneDigest: next.motionID))
            XCTAssertFalse(motion.updateAttraction(lease: lease, sceneDigest: next.motionID, offsets: [:], time: 10))
            XCTAssertTrue(motion.snapshot(sceneDigest: next.motionID).attractionProgress.isEmpty)
            currentScene = next
        }
        let lease = try XCTUnwrap(motion.beginAttraction(sceneDigest: currentScene.motionID))
        XCTAssertTrue(motion.updateAttraction(lease: lease, sceneDigest: currentScene.motionID,
            offsets: ["a": .init(x: 0.3, y: 0)], time: 10))
        motion.cancelInteraction()
        XCTAssertFalse(motion.isAttractionCurrent(lease: lease, sceneDigest: currentScene.motionID))
        XCTAssertTrue(motion.snapshot(sceneDigest: currentScene.motionID).attractionProgress.isEmpty)
        let finalLease = try XCTUnwrap(motion.beginAttraction(sceneDigest: currentScene.motionID))
        XCTAssertTrue(motion.updateAttraction(lease: finalLease, sceneDigest: currentScene.motionID,
            offsets: ["a": .init(x: 0.3, y: 0)], time: 10))
        motion.reset()
        XCTAssertFalse(motion.isAttractionCurrent(lease: finalLease, sceneDigest: currentScene.motionID))
        XCTAssertEqual(motion.snapshot(sceneDigest: currentScene.motionID), .still)
    }

    func testAttractionRetainsRecordedCouplingAndSettledTargetsDoNotKeepWakingSimulation() throws {
        let scene = try makeScene(ids: ["a", "b"], linked: true)
        var control = CompanionParticleDynamics(); control.reconcile(scene: scene)
        var attracted = control
        XCTAssertTrue(attracted.setAttraction(offsets: ["a": .init(x: 0.3, y: 0)]))
        for _ in 0..<120 { control.step(1.0 / 120); attracted.step(1.0 / 120) }
        XCTAssertNotEqual(attracted.bodies["b"]?.position, control.bodies["b"]?.position,
            "The real recorded neighbour responds through existing forces.")
        XCTAssertEqual(scene.graph.edges.count, 1)
        assertBounded(attracted)
        var single = CompanionParticleDynamics(); single.reconcile(scene: try makeScene(ids: ["a"]))
        let offsets: [String: Vector] = ["a": .init(x: 0.2, y: 0)]
        XCTAssertTrue(single.setAttraction(offsets: offsets))
        for _ in 0..<2400 { single.step(1.0 / 120) }
        XCTAssertTrue(single.isSleeping)
        let settled = single.offsets
        XCTAssertTrue(single.setAttraction(offsets: offsets))
        XCTAssertTrue(single.isSleeping, "A fresh unchanged heartbeat does not invalidate equilibrium.")
        single.step(1.0 / 120)
        XCTAssertEqual(single.offsets, settled)
        single.clearAttraction()
        XCTAssertFalse(single.isSleeping)
        single.step(1.0 / 120)
        XCTAssertNotEqual(single.offsets, settled)
    }

    func testLinkedOpposingAttractionTargetsConvergeAndReleaseRestoresOriginalEquilibrium() throws {
        let scene = try makeScene(ids: ["a", "b", "core"], linked: true, companionIDs: ["core"])
        var dynamics = CompanionParticleDynamics(); dynamics.reconcile(scene: scene)
        let original = dynamics.bodies
        // Opposing targets make original-rest coupling visibly oppose both
        // attractions. A one-node fixture cannot expose that failed equilibrium.
        let separation = try XCTUnwrap(original["a"]).rest - XCTUnwrap(original["b"]).rest
        let away = separation * (0.6 / separation.length)
        let targets = ["a": away, "b": away * -1]
        XCTAssertTrue(dynamics.setAttraction(offsets: targets))
        for _ in 0..<2400 { dynamics.step(1.0 / 120) }
        for (id, target) in targets {
            let actual = try XCTUnwrap(dynamics.offsets[id])
            XCTAssertEqual(actual.x, target.x, accuracy: 1e-5)
            XCTAssertEqual(actual.y, target.y, accuracy: 1e-5)
            XCTAssertGreaterThan(try XCTUnwrap(dynamics.attractionProgress[id]), 0.999)
            XCTAssertEqual(dynamics.bodies[id]?.rest, original[id]?.rest)
        }
        XCTAssertLessThan(try XCTUnwrap(dynamics.offsets["core"]).length, 1e-5)
        XCTAssertNil(dynamics.attractionProgress["core"])
        XCTAssertTrue(dynamics.isSleeping)
        assertBounded(dynamics)
        dynamics.clearAttraction()
        for _ in 0..<2400 { dynamics.step(1.0 / 120) }
        XCTAssertTrue(dynamics.isSleeping)
        for id in original.keys {
            XCTAssertLessThan(try XCTUnwrap(dynamics.offsets[id]).length, 1e-5)
            XCTAssertEqual(dynamics.bodies[id]?.rest, original[id]?.rest)
        }
        XCTAssertEqual(scene.graph.edges.count, 1)
    }

    private func assertBounded(_ dynamics: CompanionParticleDynamics, file: StaticString = #filePath, line: UInt = #line) {
        for body in dynamics.bodies.values {
            XCTAssertTrue(body.position.x.isFinite && body.position.y.isFinite && body.velocity.x.isFinite && body.velocity.y.isFinite, file: file, line: line)
            XCTAssertLessThanOrEqual(body.position.length, CompanionParticleDynamics.maximumPosition + 1e-12, file: file, line: line)
            XCTAssertLessThanOrEqual(body.velocity.length, CompanionParticleDynamics.maximumVelocity + 1e-12, file: file, line: line)
        }
    }

    private func makeScene(ids: [String] = ["a", "b"], sessionID: String? = nil,
                           origin: String = String(repeating: "a", count: 64), reviewed: Int? = nil,
                           withdrawn: Set<String> = [], linked: Bool = false,
                           recordedEdges: [CompanionGraphEdge]? = nil,
                           companionIDs: Set<String> = []) throws -> CompanionParticleScene {
        let nodes = ids.map { id in
            CompanionGraphNode(id: id, title: id, subtitle: "Synthetic motion fixture", kind: companionIDs.contains(id) ? .companion : .knowledge,
                status: "Retained", details: [], target: .memory,
                presentationState: withdrawn.contains(id) ? .withdrawn : .recorded)
        }
        let edges: [CompanionGraphEdge] = recordedEdges ?? (linked ? [.init(id: "source-link", source: "a", target: "b", label: "recorded dependency")] : [])
        let graph = CompanionGraphSnapshot(nodes: nodes, edges: edges, truncatedCount: 0)
        let development = reviewed.map { count in
            LiminalFormDevelopment.Snapshot(originDigest: origin, nodes: [
                .init(id: String(repeating: "b", count: 64), lessonIDs: [], graphNodeIDs: ["a"], title: "Reviewed fixture",
                    applications: min(8, count), reviewedApplicationCount: count, supportDigest: String(repeating: "c", count: 64))
            ], unavailableLessons: 0, duplicateLessons: 0, evidenceAvailable: true)
        }
        return try XCTUnwrap(CompanionParticleScene.build(originDigest: origin, graph: graph, development: development,
            sessionID: sessionID ?? session))
    }
}
