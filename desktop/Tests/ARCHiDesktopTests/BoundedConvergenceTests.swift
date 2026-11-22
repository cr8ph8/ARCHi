// Bounded measurements against the declared synthetic peer reference.
// Historical records are not fresh evidence. Agreement does not authorize work.
// Execution results belong to the per-run report; these fixtures do not qualify
// installed-app UI, live inference or a real peer network.

import Foundation
import XCTest
@testable import ARCHiDesktop

final class BoundedConvergenceTests: XCTestCase {
    private struct Measurements {
        let referenceError: Int
        let disagreement: Int
        let freshCoverage: Int
    }

    /// The fixed reference is the four declared fixture observations. Full value
    /// equality checks accompany the identity-set metrics, so an unchanged ID
    /// cannot hide altered evidence, origin, revision, representation, or links.
    private func measure(
        _ simulation: PeerGossipSimulation,
        at time: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Measurements {
        let reference = Set(simulation.fixtureObservations.map(\.id))
        XCTAssertEqual(reference.count, 4, file: file, line: line)
        var knowledge: [Set<PeerObservationIdentity>] = []

        for peer in simulation.peerIDs {
            let directory = try XCTUnwrap(
                simulation.directories[peer], "Missing peer directory: \(peer)",
                file: file, line: line
            )
            // Expiry retains records for replay protection; raw record counts
            // must never stand in for the currently fresh knowledge set.
            let fresh = directory.observationRecords.filter { $0.isFresh(at: time) }
            for record in fresh {
                let expected = try XCTUnwrap(
                    simulation.fixtureObservations.first { $0.id == record.id },
                    "Fresh record is outside the declared fixture reference.",
                    file: file, line: line
                )
                XCTAssertEqual(record.observation, expected, file: file, line: line)
            }
            knowledge.append(Set(fresh.map(\.id)))
        }

        XCTAssertEqual(knowledge.count, 4, file: file, line: line)
        let referenceError = knowledge.map { $0.symmetricDifference(reference).count }.max() ?? 0
        var disagreement = 0
        for left in knowledge {
            for right in knowledge {
                disagreement = max(disagreement, left.symmetricDifference(right).count)
            }
        }
        return Measurements(
            referenceError: referenceError,
            disagreement: disagreement,
            freshCoverage: knowledge.reduce(0) { $0 + $1.count }
        )
    }

    private func graphInput(contextDigest: String) -> PeerInspectionInput {
        PeerInspectionInput(
            graphID: "bounded-graph",
            sourceID: "bounded-source",
            sourceDigest: String(repeating: "c", count: 64),
            contextDigest: contextDigest,
            nodes: [
                PeerGraphNode(id: "n1", kind: "node", status: "ready"),
                PeerGraphNode(id: "n2", kind: "particle", status: "working")
            ],
            edges: [PeerGraphEdge(id: "e1", sourceID: "n1", targetID: "n2")]
        )
    }

    func testAllThreeFanoutClassesReachTheFullFreshReferenceByRoundTwo() throws {
        // The production fanout uses seed % 3. These seeds cover each class.
        let expectedErrors = [3, 1, 0, 0, 0]
        let expectedDisagreements = [2, 2, 0, 0, 0]
        let expectedCoverage = [4, 12, 16, 16, 16]

        for seed in [UInt64(0), UInt64(1), UInt64(2)] {
            var simulation = PeerGossipSimulation(seed: seed)
            XCTAssertEqual(simulation.fixtureObservations.count, 4)
            XCTAssertEqual(
                Set(simulation.fixtureObservations.map(\.originPeerID)),
                Set(simulation.peerIDs)
            )
            XCTAssertTrue(simulation.start(now: 0), "seed=\(seed)")

            for round in 0...4 {
                let time = Double(round) / 10
                if round > 0 {
                    XCTAssertTrue(simulation.step(now: time), "seed=\(seed), round=\(round)")
                }
                XCTAssertEqual(simulation.round, round)
                let measured = try measure(simulation, at: time)
                let context = "seed=\(seed), round=\(round), time=\(time)"
                XCTAssertEqual(measured.referenceError, expectedErrors[round], context)
                XCTAssertEqual(measured.disagreement, expectedDisagreements[round], context)
                XCTAssertEqual(measured.freshCoverage, expectedCoverage[round], context)
            }
        }
    }

    func testValidExpiryProducesEmptyAgreementWithoutFreshReferenceCoverage() throws {
        var simulation = PeerGossipSimulation(seed: 42)
        XCTAssertTrue(simulation.start(now: 0))
        for round in 1...4 {
            XCTAssertTrue(simulation.step(now: Double(round) / 10))
        }
        let before = try measure(simulation, at: 0.4)
        XCTAssertEqual(before.referenceError, 0)
        XCTAssertEqual(before.disagreement, 0)
        XCTAssertEqual(before.freshCoverage, 16)

        var retainedBefore: [String: [PeerStoredObservation]] = [:]
        for peer in simulation.peerIDs {
            retainedBefore[peer] = try XCTUnwrap(simulation.directories[peer]).observationRecords
        }

        // Every record was first received by t=0.2, with a six-second TTL.
        // t=7 is deliberately beyond every receiver-local expiration time.
        XCTAssertTrue(simulation.step(now: 7))
        XCTAssertTrue(simulation.lastRoundDeliveries.isEmpty)
        let after = try measure(simulation, at: 7)
        XCTAssertEqual(after.disagreement, 0)
        XCTAssertEqual(after.referenceError, 4)
        XCTAssertEqual(after.freshCoverage, 0)

        for peer in simulation.peerIDs {
            let records = try XCTUnwrap(simulation.directories[peer]).observationRecords
            XCTAssertEqual(records.count, 4)
            XCTAssertEqual(records, try XCTUnwrap(retainedBefore[peer]))
            XCTAssertTrue(records.allSatisfy { !$0.isFresh(at: 7) })
        }
        // E=4 here describes missing fresh coverage against the original fixed
        // reference. Valid expiry is expected behavior, not a protocol defect.
    }

    func testUnpreparedSessionCannotExecuteOrAdmitAReport() {
        var session = PeerWorkSession(sessionID: "bounded-unprepared")
        let context = String(repeating: "a", count: 64)

        XCTAssertNil(session.execute(now: 0))
        XCTAssertEqual(session.admit(currentContextDigest: context, now: 1).decision, .escalate)
        XCTAssertNil(session.currentAttempt)
        XCTAssertNil(session.candidate)
        XCTAssertTrue(session.reports.isEmpty)

        XCTAssertNil(session.execute(now: 2))
        XCTAssertEqual(session.admit(currentContextDigest: context, now: 3).decision, .escalate)
        XCTAssertTrue(session.reports.isEmpty)
    }

    func testFreshAuthorizedAttemptRecoversAfterStaleContextAndCommitsOnlyOnce() throws {
        let oldContext = String(repeating: "a", count: 64)
        let currentContext = String(repeating: "b", count: 64)
        var session = PeerWorkSession(sessionID: "bounded-recovery")

        let oldAttempt = try session.prepare(
            input: graphInput(contextDigest: oldContext), now: 0, permitDuration: 10
        )
        XCTAssertNotNil(session.execute(now: 1))
        XCTAssertTrue(session.reports.isEmpty)
        XCTAssertEqual(
            session.admit(currentContextDigest: currentContext, now: 2).decision, .escalate
        )
        XCTAssertNil(session.candidate)
        XCTAssertTrue(session.reports.isEmpty)

        let freshAttempt = try session.prepare(
            input: graphInput(contextDigest: currentContext), now: 3, permitDuration: 10
        )
        XCTAssertGreaterThan(freshAttempt.epoch, oldAttempt.epoch)
        XCTAssertNotEqual(freshAttempt.binding, oldAttempt.binding)
        let report = try XCTUnwrap(session.execute(now: 4))
        XCTAssertEqual(report.binding, freshAttempt.binding)
        XCTAssertEqual(report.contextDigest, currentContext)
        XCTAssertEqual(report.sourceDigest, String(repeating: "c", count: 64))
        XCTAssertEqual(report.graphID, "bounded-graph")
        XCTAssertEqual(report.nodeCount, 2)
        XCTAssertEqual(report.edgeCount, 1)
        XCTAssertEqual(report.unresolvedEdgeCount, 0)
        XCTAssertTrue(report.unresolvedEdgeIDs.isEmpty)
        XCTAssertEqual(report.duplicateNodeCount, 0)
        XCTAssertEqual(report.duplicateEdgeCount, 0)
        XCTAssertEqual(report.truncatedCount, 0)
        XCTAssertEqual(report.kindCounts, ["node": 1, "particle": 1])
        XCTAssertEqual(report.statusCounts, ["ready": 1, "working": 1])
        XCTAssertTrue(report.checks.contains { $0.required })
        XCTAssertTrue(report.checks.allSatisfy { $0.status == .pass })
        XCTAssertEqual(session.currentAttempt?.progress, .candidateReady)
        XCTAssertTrue(session.reports.isEmpty)

        let admission = session.admit(currentContextDigest: currentContext, now: 5)
        XCTAssertEqual(admission.decision, .commit)
        XCTAssertEqual(admission.reportID, report.id)
        XCTAssertEqual(session.reports, [report])
        XCTAssertEqual(session.currentAttempt?.progress, .committed)
        XCTAssertNil(session.candidate)

        XCTAssertNil(session.execute(now: 6))
        XCTAssertEqual(
            session.admit(currentContextDigest: currentContext, now: 7).decision, .escalate
        )
        XCTAssertEqual(session.reports, [report])
    }
}
