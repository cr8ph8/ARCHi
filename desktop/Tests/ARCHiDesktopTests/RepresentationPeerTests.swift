import Foundation
import XCTest
@testable import ARCHiDesktop

final class RepresentationPeerTests: XCTestCase {
    private let digest = String(repeating: "a", count: 64)
    private let otherDigest = String(repeating: "b", count: 64)
    private let peers: Set<String> = ["a", "b", "c", "d"]

    private func pixel(width: Int = 8, region: PixelRegion? = nil) -> RepresentationReference {
        .pixels(PixelFrameReference(
            object: RepresentationObjectReference(semanticObjectID: "object", artifactID: "frame", revision: "1"),
            frameIndex: 0, frameWidth: width, frameHeight: 8, region: region
        ))
    }

    private func observation(
        origin: String = "a", event: String = "event-1", id: String = "observation-1",
        sequence: UInt64 = 1, status: PeerReportedStatus = .ready,
        representations: [RepresentationReference]? = nil, evidenceDigest: String? = nil,
        evidenceOrigin: PeerDataOrigin = .simulation
    ) -> PeerObservation {
        PeerObservation(
            sessionID: "session", originPeerID: origin, eventID: event, observationID: id,
            sequence: sequence, semanticObjectID: "object", origin: .simulation, status: status,
            representations: representations ?? [pixel()],
            evidence: [PeerEvidenceReference(
                id: "evidence-1", artifactID: "fixture", revision: "1",
                contentDigest: evidenceDigest ?? digest, producerPeerID: origin, origin: evidenceOrigin
            )]
        )
    }

    private func envelope(
        _ observation: PeerObservation, delivery: String = "delivery-1",
        sender: String = "a", recipient: String = "b", ttl: TimeInterval = 5
    ) -> PeerEnvelope {
        PeerEnvelope(sessionID: "session", deliveryID: delivery, senderPeerID: sender,
                     recipientPeerID: recipient, observation: observation, ttl: ttl)
    }

    private func directory(local: String = "b", limits: PeerDirectoryLimits = .init()) -> PeerObservationDirectory {
        PeerObservationDirectory(sessionID: "session", localPeerID: local, allowedPeerIDs: peers, limits: limits)
    }

    private func input(context: String? = nil, duplicateNode: Bool = false, unresolvedEdge: Bool = false) -> PeerInspectionInput {
        PeerInspectionInput(
            graphID: "graph", sourceID: "snapshot", sourceDigest: digest,
            contextDigest: context ?? digest,
            nodes: [PeerGraphNode(id: "n1", kind: "node", status: "ready"),
                    PeerGraphNode(id: duplicateNode ? "n1" : "n2", kind: "particle", status: "working")],
            edges: [PeerGraphEdge(id: "e1", sourceID: "n1", targetID: unresolvedEdge ? "missing" : "n2")]
        )
    }

    func testDuplicateDeliveriesAndRelaysNeverExtendFreshness() throws {
        var receiver = directory()
        let original = observation()
        XCTAssertEqual(receiver.receive(envelope(original), now: 10).disposition, .accepted)
        XCTAssertEqual(receiver.receive(envelope(original), now: 12).disposition, .duplicateDelivery)
        XCTAssertEqual(receiver.receive(envelope(original, delivery: "relay", sender: "c", ttl: 100), now: 14).disposition, .duplicateObservation)
        let record = try XCTUnwrap(receiver.observationRecords.first)
        XCTAssertEqual(record.firstReceivedAt, 10)
        XCTAssertEqual(record.expiresAt, 15)
        XCTAssertEqual(record.observation, original)
        XCTAssertTrue(receiver.expire(now: 15))
        XCTAssertFalse(record.isFresh(at: 15))
        XCTAssertFalse(try XCTUnwrap(receiver.peers.first(where: { $0.peerID == "a" })).reportIsFresh(at: 15))
        XCTAssertEqual(receiver.receive(envelope(original, delivery: "late-replay"), now: 16).disposition, .duplicateObservation)
        XCTAssertEqual(receiver.observationRecords.first?.expiresAt, 15)
    }

    func testConflictsAreScopedAndOriginalEvidenceSurvivesRelay() throws {
        var first = directory()
        let original = observation()
        XCTAssertEqual(first.receive(envelope(original), now: 0).disposition, .accepted)
        XCTAssertEqual(first.receive(envelope(observation(status: .working)), now: 1).disposition, .conflict)
        XCTAssertEqual(first.receive(envelope(observation(id: "changed-id", sequence: 2), delivery: "changed-event"), now: 1).disposition, .conflict)
        XCTAssertEqual(first.receive(envelope(observation(event: "other-event", id: "other-id", sequence: 2, evidenceDigest: otherDigest), delivery: "changed-evidence"), now: 1).disposition, .conflict)
        let otherOrigin = observation(origin: "c")
        XCTAssertEqual(first.receive(envelope(otherOrigin, delivery: "other-origin", sender: "c"), now: 1).disposition, .accepted)
        XCTAssertEqual(Set(first.observationRecords.map(\.id)).count, 2)

        var second = directory(local: "d")
        let relayed = try XCTUnwrap(first.observations.first(where: { $0.originPeerID == "a" }))
        XCTAssertEqual(second.receive(envelope(relayed, delivery: "forward", sender: "b", recipient: "d"), now: 2).disposition, .accepted)
        XCTAssertEqual(second.observations.first, original)
        XCTAssertEqual(second.observations.first?.evidence.first?.producerPeerID, "a")
        XCTAssertEqual(second.observations.first?.evidence.first?.contentDigest, digest)
    }

    func testInvalidScopeAndOriginMismatchAreRejected() {
        let original = observation()
        let outOfScope = [
            envelope(original, sender: "outsider"),
            envelope(original, recipient: "c"),
            envelope(observation(origin: "outsider")),
            envelope(observation(evidenceOrigin: .remoteClaim)),
            PeerEnvelope(sessionID: "other-session", deliveryID: "d", senderPeerID: "a", recipientPeerID: "b", observation: original, ttl: 5),
            PeerEnvelope(protocolVersion: 2, sessionID: "session", deliveryID: "d", senderPeerID: "a", recipientPeerID: "b", observation: original, ttl: 5)
        ]
        for invalid in outOfScope {
            var receiver = directory()
            XCTAssertEqual(receiver.receive(invalid, now: 0).disposition, .rejected)
            XCTAssertTrue(receiver.observations.isEmpty)
            XCTAssertEqual(receiver.deliveryCount, 0)
        }
    }

    func testRepresentationAndCapacityBoundsFailClosed() {
        for region in [PixelRegion(x: -1, y: 0, width: 1, height: 1),
                       PixelRegion(x: 0, y: 0, width: 0, height: 1),
                       PixelRegion(x: 7, y: 0, width: 2, height: 1),
                       PixelRegion(x: Int.max, y: 0, width: Int.max, height: 1)] {
            XCTAssertFalse(region.fits(width: 8, height: 8))
            var receiver = directory()
            XCTAssertEqual(receiver.receive(envelope(observation(representations: [pixel(region: region)])), now: 0).disposition, .rejected)
        }
        XCTAssertTrue(PixelRegion(x: 7, y: 7, width: 1, height: 1).fits(width: 8, height: 8))
        XCTAssertFalse(pixel(width: 0).isWellFormed)
        XCTAssertFalse(PeerFieldValidation.identifier(String(repeating: "x", count: 257)))
        XCTAssertFalse(PeerFieldValidation.sha256Digest("not-a-digest"))

        var limits = PeerDirectoryLimits()
        limits.maxObservations = 1
        limits.maxHistory = 2
        var receiver = directory(limits: limits)
        XCTAssertEqual(receiver.receive(envelope(observation()), now: 0).disposition, .accepted)
        for index in 2...4 {
            let next = observation(event: "event-\(index)", id: "observation-\(index)", sequence: UInt64(index))
            XCTAssertEqual(receiver.receive(envelope(next, delivery: "delivery-\(index)"), now: 1).disposition, .capacity)
        }
        XCTAssertEqual(receiver.observations.count, 1)
        XCTAssertEqual(receiver.history.count, 2)
    }

    func testNonfiniteBackwardAndInvalidTTLTimesDoNotAdmit() throws {
        var receiver = directory()
        XCTAssertEqual(receiver.receive(envelope(observation()), now: 10).disposition, .accepted)
        for time in [Double.nan, Double.infinity, -Double.infinity, -1, 9] {
            XCTAssertEqual(receiver.receive(envelope(observation(), delivery: "bad-clock"), now: time).disposition, .invalidTime)
            XCTAssertFalse(receiver.expire(now: time))
            XCTAssertEqual(receiver.now, 10)
        }
        for ttl in [Double.nan, Double.infinity, -1, 0, 121] {
            var empty = directory()
            XCTAssertEqual(empty.receive(envelope(observation(), ttl: ttl), now: 0).disposition, .rejected)
            XCTAssertTrue(empty.observations.isEmpty)
        }
        var session = PeerWorkSession(sessionID: "work")
        try session.prepare(input: input(), now: 10)
        XCTAssertNotNil(session.execute(now: 11))
        for time in [Double.nan, Double.infinity, -1, 10] {
            let result = session.admit(currentContextDigest: digest, now: time)
            XCTAssertEqual(result.decision, .escalate)
            XCTAssertNil(result.at)
            XCTAssertTrue(session.reports.isEmpty)
        }
        XCTAssertEqual(session.admit(currentContextDigest: digest, now: 12).decision, .commit)
    }

    func testOnlyExplicitAdmissionCommitsAValidSessionReportAndReplayCannotCommit() throws {
        var session = PeerWorkSession(sessionID: "work")
        let attempt = try session.prepare(input: input(), now: 0, permitDuration: 10)
        XCTAssertTrue(session.reports.isEmpty)
        let report = try XCTUnwrap(session.execute(now: 1))
        XCTAssertEqual(report.binding, attempt.binding)
        XCTAssertEqual(report.nodeCount, 2)
        XCTAssertEqual(report.edgeCount, 1)
        XCTAssertEqual(report.unresolvedEdgeCount, 0)
        XCTAssertTrue(report.checks.allSatisfy { $0.status == .pass })
        XCTAssertEqual(session.execute(now: 2), report)
        XCTAssertTrue(session.reports.isEmpty)
        XCTAssertEqual(session.currentAttempt?.progress, .candidateReady)
        let result = session.admit(currentContextDigest: digest, now: 3)
        XCTAssertEqual(result.decision, .commit)
        XCTAssertEqual(result.reportID, report.id)
        XCTAssertEqual(session.reports, [report])
        XCTAssertEqual(session.currentAttempt?.progress, .committed)
        XCTAssertNil(session.candidate)
        XCTAssertNil(session.execute(now: 4))
        XCTAssertEqual(session.admit(currentContextDigest: digest, now: 5).decision, .escalate)
        XCTAssertEqual(session.reports.count, 1)
    }

    func testRequiredSkippedErrorAndFailedChecksNeverAuthorizeCommit() throws {
        for status in [PeerCheckStatus.skipped, .error, .fail] {
            let decision = PeerAdmissionPolicy.evaluate([
                PeerCheckResult(id: "valid", status: .pass, detail: "checked"),
                PeerCheckResult(id: "required", status: status, detail: "not passed")
            ])
            XCTAssertNotEqual(decision, .commit)
        }
        XCTAssertEqual(PeerAdmissionPolicy.evaluate([]), .escalate)
        XCTAssertEqual(PeerAdmissionPolicy.evaluate([PeerCheckResult(id: "optional", status: .pass, detail: "optional", required: false)]), .escalate)
        XCTAssertEqual(PeerAdmissionPolicy.evaluate([
            PeerCheckResult(id: "duplicate", status: .pass, detail: "first"),
            PeerCheckResult(id: "duplicate", status: .pass, detail: "second")
        ]), .escalate)

        for malformed in [input(duplicateNode: true), input(unresolvedEdge: true)] {
            var session = PeerWorkSession(sessionID: "work")
            try session.prepare(input: malformed, now: 0)
            let candidate = try XCTUnwrap(session.execute(now: 1))
            XCTAssertTrue(candidate.checks.contains { $0.status != .pass })
            XCTAssertNotEqual(session.admit(currentContextDigest: digest, now: 2).decision, .commit)
            XCTAssertTrue(session.reports.isEmpty)
        }
    }

    func testMissingExecutionStaleContextAndExpiryFenceAdmission() throws {
        var missing = PeerWorkSession(sessionID: "missing")
        try missing.prepare(input: input(), now: 0)
        let skipped = missing.admit(currentContextDigest: digest, now: 1)
        XCTAssertEqual(skipped.decision, .escalate)
        XCTAssertTrue(skipped.checks.contains { $0.required && $0.status == .skipped })
        XCTAssertTrue(missing.reports.isEmpty)

        var stale = PeerWorkSession(sessionID: "stale")
        try stale.prepare(input: input(), now: 0)
        XCTAssertNotNil(stale.execute(now: 1))
        XCTAssertEqual(stale.admit(currentContextDigest: otherDigest, now: 2).decision, .escalate)
        XCTAssertNil(stale.candidate)
        XCTAssertEqual(stale.admit(currentContextDigest: digest, now: 3).decision, .escalate)
        XCTAssertTrue(stale.reports.isEmpty)

        var expired = PeerWorkSession(sessionID: "expired")
        try expired.prepare(input: input(), now: 0, permitDuration: 2)
        XCTAssertNotNil(expired.execute(now: 1))
        XCTAssertEqual(expired.admit(currentContextDigest: digest, now: 2).decision, .escalate)
        XCTAssertTrue(expired.reports.isEmpty)
        XCTAssertNil(expired.candidate)
        var expiredBeforeExecution = PeerWorkSession(sessionID: "expired-execution")
        try expiredBeforeExecution.prepare(input: input(), now: 0, permitDuration: 2)
        XCTAssertNil(expiredBeforeExecution.execute(now: 2))
        XCTAssertTrue(expiredBeforeExecution.reports.isEmpty)
    }

    func testCancellationAndSupersededAttemptsCannotReuseCandidates() throws {
        for cancellationTime in [2.0, Double.nan, 0] {
            var cancelled = PeerWorkSession(sessionID: "cancelled")
            try cancelled.prepare(input: input(), now: 0)
            XCTAssertNotNil(cancelled.execute(now: 1))
            let result = try XCTUnwrap(cancelled.cancel(now: cancellationTime))
            XCTAssertEqual(result.decision, .escalate)
            XCTAssertEqual(cancelled.currentAttempt?.progress, .cancelled)
            XCTAssertNil(cancelled.candidate)
            XCTAssertNil(cancelled.execute(now: 3))
            XCTAssertEqual(cancelled.admit(currentContextDigest: digest, now: 4).decision, .escalate)
            XCTAssertTrue(cancelled.reports.isEmpty)
        }

        var superseded = PeerWorkSession(sessionID: "superseded")
        let old = try superseded.prepare(input: input(), now: 0)
        XCTAssertNotNil(superseded.execute(now: 1))
        let fresh = try superseded.prepare(input: input(context: otherDigest), now: 2)
        XCTAssertGreaterThan(fresh.epoch, old.epoch)
        XCTAssertNotEqual(fresh.id, old.id)
        XCTAssertNil(superseded.candidate)
        let newReport = try XCTUnwrap(superseded.execute(now: 3))
        XCTAssertEqual(newReport.binding, fresh.binding)
        XCTAssertNotEqual(newReport.binding, old.binding)
        XCTAssertEqual(superseded.admit(currentContextDigest: digest, now: 4).decision, .escalate)
        XCTAssertTrue(superseded.reports.isEmpty)
    }

    func testWorkInputBoundsAndDampingLeaveReportsUncommitted() throws {
        var limits = PeerWorkLimits()
        limits.maxNodes = 1
        var tooSmall = PeerWorkSession(sessionID: "bounded", limits: limits)
        XCTAssertThrowsError(try tooSmall.prepare(input: input(), now: 0))
        XCTAssertNil(tooSmall.currentAttempt)
        for permit in [Double.nan, Double.infinity, -1, 0, 301] {
            var invalidPermit = PeerWorkSession(sessionID: "permit")
            XCTAssertThrowsError(try invalidPermit.prepare(input: input(), now: 0, permitDuration: permit))
            XCTAssertNil(invalidPermit.currentAttempt)
        }
        var damped = PeerWorkSession(sessionID: "damped")
        try damped.prepare(input: input(), now: 0)
        XCTAssertNotNil(damped.execute(now: 1))
        XCTAssertEqual(damped.damp(now: 2)?.decision, .damp)
        XCTAssertNil(damped.candidate)
        XCTAssertTrue(damped.reports.isEmpty)
        XCTAssertEqual(damped.admit(currentContextDigest: digest, now: 3).decision, .escalate)
    }

    func testSeededGossipConvergesDeterministicallyWithinBoundedRounds() throws {
        var first = PeerGossipSimulation(seed: 42)
        var second = PeerGossipSimulation(seed: 42)
        XCTAssertTrue(first.start(now: 0))
        XCTAssertTrue(second.start(now: 0))
        XCTAssertFalse(first.start(now: 0))
        let fixtureKinds = Set(first.fixtureObservations.flatMap(\.representations).map(\.kind))
        XCTAssertTrue(Set([RepresentationKind.particles, .node, .neural, .pixels]).isSubset(of: fixtureKinds))
        for step in 1...4 {
            XCTAssertTrue(first.step(now: Double(step) / 10))
            XCTAssertTrue(second.step(now: Double(step) / 10))
            XCTAssertEqual(first.lastRoundDeliveries, second.lastRoundDeliveries)
        }
        let expected = Set(first.fixtureObservations.map(\.id))
        for peer in first.peerIDs {
            let records = try XCTUnwrap(first.directories[peer]).observationRecords
            XCTAssertEqual(Set(records.map(\.id)), expected)
            for record in records {
                XCTAssertEqual(record.observation, first.fixtureObservations.first(where: { $0.id == record.id }))
            }
        }
        XCTAssertFalse(first.step(now: .nan))
        for step in 5...first.maximumRounds {
            XCTAssertTrue(first.step(now: Double(step) / 10))
        }
        XCTAssertEqual(first.round, first.maximumRounds)
        XCTAssertFalse(first.step(now: 4))
        XCTAssertLessThanOrEqual(first.history.count, 128)
    }

    func testDisconnectedPeerDoesNotAcquireKnowledgeUntilDeliveryResumes() {
        let fixture = PeerGossipSimulation(seed: 7)
        let ids = fixture.peerIDs
        let allowed = Set(ids)
        var receivers = Dictionary(uniqueKeysWithValues: ids.map {
            ($0, PeerObservationDirectory(sessionID: fixture.sessionID, localPeerID: $0, allowedPeerIDs: allowed))
        })
        for original in fixture.fixtureObservations {
            let own = original.originPeerID
            let message = PeerEnvelope(sessionID: fixture.sessionID, deliveryID: "self-\(own)", senderPeerID: own,
                                       recipientPeerID: own, observation: original, ttl: 5)
            XCTAssertEqual(receivers[own]?.receive(message, now: 0).disposition, .accepted)
        }
        let isolated = ids[3]
        let connected = Array(ids.prefix(3))
        for origin in fixture.fixtureObservations where origin.originPeerID != isolated {
            for recipient in connected where recipient != origin.originPeerID {
                let message = PeerEnvelope(sessionID: fixture.sessionID, deliveryID: "connected-\(origin.originPeerID)-\(recipient)",
                                           senderPeerID: origin.originPeerID, recipientPeerID: recipient, observation: origin, ttl: 5)
                XCTAssertEqual(receivers[recipient]?.receive(message, now: 1).disposition, .accepted)
            }
        }
        XCTAssertEqual(receivers[isolated]?.observations.count, 1)
        for peer in connected { XCTAssertEqual(receivers[peer]?.observations.count, 3) }
        for original in fixture.fixtureObservations where original.originPeerID != isolated {
            let message = PeerEnvelope(sessionID: fixture.sessionID, deliveryID: "reconnect-\(original.originPeerID)",
                                       senderPeerID: connected[0], recipientPeerID: isolated, observation: original, ttl: 5)
            XCTAssertEqual(receivers[isolated]?.receive(message, now: 2).disposition, .accepted)
        }
        XCTAssertEqual(Set(receivers[isolated]?.observations.map(\.id) ?? []), Set(fixture.fixtureObservations.map(\.id)))
    }
}
