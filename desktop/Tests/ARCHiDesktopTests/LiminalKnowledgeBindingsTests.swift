import XCTest
@testable import ARCHiDesktop

final class LiminalKnowledgeBindingsTests: XCTestCase {
    private let digest = String(repeating: "a", count: 64)
    private let origin = String(repeating: "b", count: 64)
    private let session = UUID().uuidString
    private func graph(_ names: [String], status: String = "Retained") -> CompanionGraphSnapshot {
        .init(nodes: names.map { .init(id: $0, title: $0, subtitle: "v1", kind: .source,
            status: status, details: [.init(label: "Revision", value: "1")], target: .context) }, edges: [], truncatedCount: 0)
    }

    func testFilteringAndReorderingKeepActualBindings() throws {
        var map = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<5000))
        let first = try map.project(graph(["a", "b", "c"]), sessionID: session, originDigest: origin)
        let reordered = try map.project(graph(["c", "b", "a"]), sessionID: session, originDigest: origin)
        XCTAssertEqual(first, reordered)
        XCTAssertEqual(first.filtered(to: ["b"]).bindings, first.bindings.filter { $0.nodeID == "b" })
        XCTAssertEqual(first.bindings.count, 3)
        XCTAssertEqual(Set(first.bindings.flatMap(\.particleIDs)).count, 96)
    }

    func testRetiredParticleDoesNotBecomeAnotherRecord() throws {
        var map = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<5000))
        let first = try map.project(graph(["a", "b"]), sessionID: session, originDigest: origin)
        let later = try map.project(graph(["b", "c"]), sessionID: session, originDigest: origin)
        XCTAssertEqual(first.bindings.first { $0.nodeID == "b" }, later.bindings.first { $0.nodeID == "b" })
        XCTAssertTrue(Set(first.bindings.first { $0.nodeID == "a" }!.particleIDs)
            .isDisjoint(with: later.bindings.flatMap(\.particleIDs)))
    }

    func testCorrectionStaleSessionAndReplayCannotNavigate() throws {
        var map = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<5000))
        let original = graph(["a"])
        let sidecar = try map.project(original, sessionID: session, originDigest: origin)
        let now = Date(timeIntervalSince1970: 1_000)
        let pick = LiminalKnowledgeSelection(schemaVersion: 1, sessionID: session, originDigest: origin,
            revision: 4, manifestSHA256: digest, graphDigest: sidecar.graphDigest, nodeID: "a",
            artParticleID: sidecar.bindings[0].anchorID, sequence: 1, updatedAtUnix: 1_000)
        XCTAssertEqual(pick.resolves(in: sidecar, graph: original, revisions: [4], after: 0, now: now)?.id, "a")
        XCTAssertNil(pick.resolves(in: sidecar, graph: graph(["a"], status: "Needs source review"), revisions: [4], after: 0, now: now))
        XCTAssertNil(pick.resolves(in: sidecar, graph: graph([]), revisions: [4], after: 0, now: now))
        XCTAssertNil(pick.resolves(in: sidecar, graph: original, revisions: [5], after: 0, now: now))
        XCTAssertNil(pick.resolves(in: sidecar, graph: original, revisions: [4], after: 1, now: now))
        XCTAssertNil(pick.resolves(in: sidecar, graph: original, revisions: [4], after: 0, now: now.addingTimeInterval(6)))
        let other = try map.project(original, sessionID: UUID().uuidString, originDigest: origin)
        XCTAssertNil(pick.resolves(in: other, graph: original, revisions: [4], after: 0, now: now))
    }

    func testInvalidIDsAndExhaustionFailWithoutInventingParticles() throws {
        XCTAssertThrowsError(try LiminalKnowledgeBindings(manifestSHA256: "v002", lowDetailIDs: [1]))
        XCTAssertThrowsError(try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: [1, 1]))
        XCTAssertThrowsError(try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: [800_000]))
        XCTAssertThrowsError(try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: [UInt32.max]))
        XCTAssertNoThrow(try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: [799_999]))
        var map = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<32))
        XCTAssertThrowsError(try map.project(graph(["a", "b"]), sessionID: session, originDigest: origin))
    }

    func testFailedFirstProjectionDoesNotReserveParticlesOrIdentity() throws {
        var map = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<32))
        XCTAssertThrowsError(try map.project(graph(["a", "b"]), sessionID: session, originDigest: origin)) {
            XCTAssertEqual($0 as? LiminalKnowledgeBindings.BindingError, .exhausted)
        }
        // Even the ownership claim is provisional until the whole projection succeeds.
        let otherOrigin = String(repeating: "c", count: 64)
        let retry = try map.project(graph(["b"]), sessionID: session, originDigest: otherOrigin)
        var fresh = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<32))
        XCTAssertEqual(retry, try fresh.project(graph(["b"]), sessionID: session, originDigest: otherOrigin))
    }

    func testExhaustionDoesNotLeakPartialReservationsDuringRetry() throws {
        var map = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<64))
        let original = try map.project(graph(["a"]), sessionID: session, originDigest: origin)
        XCTAssertThrowsError(try map.project(graph(["a", "b", "c"]), sessionID: session, originDigest: origin))
        XCTAssertEqual(original, try map.project(graph(["a"]), sessionID: session, originDigest: origin))
        let retry = try map.project(graph(["a", "d"]), sessionID: session, originDigest: origin)
        var fresh = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<64))
        _ = try fresh.project(graph(["a"]), sessionID: session, originDigest: origin)
        XCTAssertEqual(retry, try fresh.project(graph(["a", "d"]), sessionID: session, originDigest: origin))
    }

    func testSessionOwnsOneOriginAndFreshSessionResetsRetiredReservations() throws {
        var map = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<32))
        let original = try map.project(graph(["a"]), sessionID: session, originDigest: origin)
        let changedOrigin = String(repeating: "c", count: 64)
        XCTAssertThrowsError(try map.project(graph(["a"]), sessionID: session, originDigest: changedOrigin)) {
            XCTAssertEqual($0 as? LiminalKnowledgeBindings.BindingError, .invalidIdentity)
        }
        XCTAssertEqual(original, try map.project(graph(["a"]), sessionID: session, originDigest: origin))
        _ = try map.project(graph([]), sessionID: session, originDigest: origin)
        XCTAssertThrowsError(try map.project(graph(["b"]), sessionID: session, originDigest: origin))
        let newSession = UUID().uuidString
        let next = try map.project(graph(["b"]), sessionID: newSession, originDigest: changedOrigin)
        var fresh = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<32))
        XCTAssertEqual(next, try fresh.project(graph(["b"]), sessionID: newSession, originDigest: changedOrigin))
    }

    func testFailedSessionTransitionKeepsPreviousOwnerAndReservations() throws {
        var map = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<32))
        let original = try map.project(graph(["a"]), sessionID: session, originDigest: origin)
        let nextSession = UUID().uuidString
        let nextOrigin = String(repeating: "c", count: 64)
        XCTAssertThrowsError(try map.project(graph(["b", "c"]), sessionID: nextSession, originDigest: nextOrigin))
        XCTAssertEqual(original, try map.project(graph(["a"]), sessionID: session, originDigest: origin))
        XCTAssertThrowsError(try map.project(graph(["d"]), sessionID: session, originDigest: origin))
        XCTAssertNoThrow(try map.project(graph(["b"]), sessionID: nextSession, originDigest: nextOrigin))
    }

    func testMalformedGraphsFailBeforeChangingBindings() throws {
        let base = graph(["a", "b"])
        let edge = CompanionGraphEdge(id: "edge", source: "a", target: "b", label: "source passage")
        let valid = CompanionGraphSnapshot(nodes: base.nodes, edges: [edge], truncatedCount: 0)
        let malformed = [
            CompanionGraphSnapshot(nodes: base.nodes + [base.nodes[0]], edges: [], truncatedCount: 0),
            .init(nodes: base.nodes, edges: [edge, edge], truncatedCount: 0),
            .init(nodes: base.nodes, edges: [.init(id: "dangling", source: "a", target: "missing", label: "")], truncatedCount: 0),
            .init(nodes: base.nodes, edges: [.init(id: "bad\nedge", source: "a", target: "b", label: "")], truncatedCount: 0),
            .init(nodes: base.nodes, edges: [.init(id: "edge", source: "a", target: "b", label: String(repeating: "x", count: 8_193))], truncatedCount: 0),
            .init(nodes: base.nodes, edges: (0...CompanionGraph.maximumEdges).map { .init(id: "edge-\($0)", source: "a", target: "b", label: "") }, truncatedCount: 0),
            .init(nodes: base.nodes, edges: [], truncatedCount: -1),
            graph([" "]), graph([String(repeating: "é", count: 129)]),
            graph((0...CompanionGraph.maximumNodes).map { "node-\($0)" })
        ]
        var map = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<96))
        let first = try map.project(valid, sessionID: session, originDigest: origin)
        for invalid in malformed {
            XCTAssertThrowsError(try map.project(invalid, sessionID: session, originDigest: origin)) {
                XCTAssertEqual($0 as? LiminalKnowledgeBindings.BindingError, .invalidGraph)
            }
        }
        XCTAssertEqual(first, try map.project(valid, sessionID: session, originDigest: origin))
        XCTAssertNoThrow(try map.project(graph(["a", "b", "new"]), sessionID: session, originDigest: origin))
    }

    func testGraphTextAndDetailsAreBoundedWithoutRejectingFullKnowledgePage() throws {
        func withDetails(_ details: [CompanionGraphDetail], target: CompanionGraphTarget? = .context) -> CompanionGraphSnapshot {
            .init(nodes: [.init(id: "page", title: "Knowledge", subtitle: "v1", kind: .knowledge,
                status: "Reviewed", details: details, target: target)], edges: [], truncatedCount: 0)
        }
        var map = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<96))
        let body = String(repeating: "x", count: 8_192)
        XCTAssertNoThrow(try map.project(withDetails([.init(label: "Note", value: body)]), sessionID: session, originDigest: origin))
        XCTAssertThrowsError(try map.project(withDetails([.init(label: "Note", value: body + "x")]), sessionID: session, originDigest: origin))
        XCTAssertThrowsError(try map.project(withDetails(Array(repeating: .init(label: "", value: ""), count: 33)), sessionID: session, originDigest: origin))
        XCTAssertThrowsError(try map.project(withDetails([], target: .knowledgePage(id: "\u{0}")), sessionID: session, originDigest: origin))
        let oversized = CompanionGraphSnapshot(nodes: (0..<9).map {
            .init(id: "node-\($0)", title: "", subtitle: "", kind: .knowledge, status: "",
                details: Array(repeating: .init(label: "", value: body), count: 32), target: nil)
        }, edges: [], truncatedCount: 0)
        XCTAssertThrowsError(try map.project(oversized, sessionID: session, originDigest: origin))
    }

    func testRealDocumentVerificationDetailsRemainInspectable() throws {
        let text = "Please keep all 12 items at https://example.test/items"
        let selection = try XCTUnwrap(DocumentSelection(range: NSRange(location: 0, length: text.utf16.count),
            text: text, sourceRevision: 3))
        let target = try XCTUnwrap(RevisionTarget(text: text, sourceRevision: 3, selection: selection))
        let proposal = PassageRevisionProposal(target: target, decision: .propose,
            replacement: "12 items: https://example.test/items", explanation: "Synthetic mechanical-check fixture.",
            sourceIDs: [], memoryIDs: [])
        let verified = DocumentWorkCapability.verify(proposal: proposal, text: text, sourceRevision: 3,
            requirements: .init(mustBeShorter: true, preserveNumbersAndLinks: true))
        XCTAssertTrue(verified.canApply)
        XCTAssertEqual(verified.checks.count, 8)
        let graph = documentGraph(checks: verified.checks.map { .init(id: $0.id, title: $0.title, passed: $0.passed) })
        let task = try XCTUnwrap(graph.nodes.first { $0.id.hasPrefix("document-work-") })
        XCTAssertEqual(task.details.count, 33, "25 owner metadata fields plus eight real mechanical checks")
        var map = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<96))
        let sidecar = try map.project(graph, sessionID: session, originDigest: origin)
        let bound = try XCTUnwrap(sidecar.bindings.first { $0.nodeID == task.id })
        let now = Date()
        let pick = LiminalKnowledgeSelection(schemaVersion: 1, sessionID: session, originDigest: origin,
            revision: 1, manifestSHA256: digest, graphDigest: sidecar.graphDigest, nodeID: task.id,
            artParticleID: bound.anchorID, sequence: 1, updatedAtUnix: now.timeIntervalSince1970)
        XCTAssertEqual(pick.resolves(in: sidecar, graph: graph, revisions: [1], after: 0, now: now), task)
    }

    func testDocumentDetailAllowanceIsBoundedToTheExistingOwnerShape() throws {
        let projected = documentGraph(checks: (0..<24).map {
            .init(id: "check-\($0)", title: "Synthetic check \($0)", passed: true)
        })
        let task = try XCTUnwrap(projected.nodes.first { $0.id.hasPrefix("document-work-") })
        XCTAssertEqual(task.details.count, 49, "DocumentWorkGraph's maximum25+24 details")
        var map = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<96))
        XCTAssertNoThrow(try map.project(projected, sessionID: session, originDigest: origin))
        func changed(id: String? = nil, kind: CompanionGraphKind? = nil,
                     target: CompanionGraphTarget = .context, details: [CompanionGraphDetail]? = nil) -> CompanionGraphSnapshot {
            .init(nodes: [.init(id: id ?? task.id, title: task.title, subtitle: task.subtitle,
                kind: kind ?? task.kind, status: task.status, details: details ?? task.details,
                target: target)], edges: [], truncatedCount: 0)
        }
        for invalid in [
            changed(id: "document-work-not-a-digest"), changed(kind: .knowledge), changed(target: .memory),
            changed(details: task.details + [.init(label: "Over budget", value: "one more")]),
            changed(details: [.init(label: "Oversized", value: String(repeating: "x", count: 8_193))])
        ] {
            XCTAssertThrowsError(try map.project(invalid, sessionID: session, originDigest: origin)) {
                XCTAssertEqual($0 as? LiminalKnowledgeBindings.BindingError, .invalidGraph)
            }
        }
    }

    private func documentGraph(checks: [DocumentWorkAuditCheck]) -> CompanionGraphSnapshot {
        var record = DocumentWorkRecord(id: "00000000-0000-4000-8000-000000000001-Qwen",
            requestID: "00000000-0000-4000-8000-000000000001", provider: "Qwen", targetID: UUID().uuidString,
            sourceDigest: digest, sourceRevision: 3, selectionStart: 0, selectionLength: 20)
        record.checks = checks; record.state = .ready
        return DocumentWorkGraph.append(to: graph(["companion-archi"]), records: [record], accountingTaskIDs: [])
    }

    func testCorrectionsPreserveParticleIdentityButInvalidateOldNavigation() throws {
        let original = graph(["a", "b"])
        let node = original.nodes[0]
        let corrections = [
            CompanionGraphSnapshot(nodes: [.init(id: node.id, title: node.title, subtitle: node.subtitle, kind: node.kind,
                status: node.status, details: node.details, target: .memory), original.nodes[1]], edges: [], truncatedCount: 0),
            .init(nodes: original.nodes, edges: [.init(id: "edge", source: "a", target: "b", label: "corrected")], truncatedCount: 0),
            .init(nodes: original.nodes, edges: [], truncatedCount: 1)
        ]
        var map = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<96))
        let first = try map.project(original, sessionID: session, originDigest: origin)
        let pick = LiminalKnowledgeSelection(schemaVersion: 1, sessionID: session, originDigest: origin,
            revision: 1, manifestSHA256: digest, graphDigest: first.graphDigest, nodeID: "a",
            artParticleID: first.bindings[0].anchorID, sequence: 1, updatedAtUnix: 1_000)
        for correction in corrections {
            let current = try map.project(correction, sessionID: session, originDigest: origin)
            XCTAssertEqual(first.bindings, current.bindings)
            XCTAssertNotEqual(first.graphDigest, current.graphDigest)
            XCTAssertNil(pick.resolves(in: current, graph: correction, revisions: [1], after: 0, now: Date(timeIntervalSince1970: 1_000)))
            XCTAssertNil(pick.resolves(in: first, graph: correction, revisions: [1], after: 0, now: Date(timeIntervalSince1970: 1_000)))
        }
    }

    func testCapacityFallbackPublishesCurrentEmptyBindingsAndRejectsOldPicks() throws {
        var map = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<64))
        let original = try map.projectForPresentation(graph(["a"]), sessionID: session, originDigest: origin)
        XCTAssertNil(original.inspectionUnavailableReason)
        let currentGraph = graph(["a", "b", "c"])
        let fallback = try map.projectForPresentation(currentGraph, sessionID: session, originDigest: origin)
        XCTAssertNotNil(fallback.inspectionUnavailableReason)
        XCTAssertEqual(fallback.sidecar.sessionID, session)
        XCTAssertEqual(fallback.sidecar.originDigest, origin)
        XCTAssertEqual(fallback.sidecar.manifestSHA256, digest)
        XCTAssertEqual(fallback.sidecar.graphDigest, LiminalKnowledgeBindings.digest(currentGraph))
        XCTAssertTrue(fallback.sidecar.bindings.isEmpty)
        let encoded = try fallback.sidecar.data()
        XCTAssertEqual(try JSONDecoder().decode(LiminalKnowledgeBindings.Sidecar.self, from: encoded), fallback.sidecar)
        let body = LiminalPointPresentation(schemaVersion: 1, assetID: "liminal-v008", manifestSHA256: digest,
            progress: 23.0 / 119.0, motion: "sampled", color: "garnet", visible: true)
        var snapshot = UnityPresentationSnapshot(schemaVersion: 1, sessionID: session, revision: 1,
            originDigest: origin, displayName: "Liminal", body: "seed", appearance: "kin", cursor: "seed",
            seedAssetSHA256: digest, bodyAssetSHA256: digest, activity: "idle", lightMode: "rest",
            quiet: false, reduceMotion: false, visible: true, equippedFocusStaff: false,
            staffPalette: nil, staffCrown: nil, active: true, updatedAtUnix: 1_000)
        XCTAssertEqual(try snapshot.attachPointPresentation(body, knowledge: fallback.sidecar), encoded)
        XCTAssertEqual(snapshot.pointPresentation, body)
        XCTAssertEqual(snapshot.pointKnowledgeSHA256, LiminalKnowledgeBindings.sha256(encoded))
        XCTAssertTrue(snapshot.active)
        // Both a delayed old pick and a pick carrying the current digest must
        // fail while inspection has no current bindings.
        for graphDigest in [original.sidecar.graphDigest, fallback.sidecar.graphDigest] {
            let pick = LiminalKnowledgeSelection(schemaVersion: 1, sessionID: session, originDigest: origin,
                revision: 1, manifestSHA256: digest, graphDigest: graphDigest, nodeID: "a",
                artParticleID: original.sidecar.bindings[0].anchorID, sequence: 1, updatedAtUnix: 1_000)
            XCTAssertNil(pick.resolves(in: fallback.sidecar, graph: currentGraph, revisions: [1],
                after: 0, now: Date(timeIntervalSince1970: 1_000)))
        }
        // A smaller retry uses the original reservations. The capacity fallback
        // neither resets the session nor reserves part of the failed graph.
        let retry = try map.projectForPresentation(graph(["a", "d"]), sessionID: session, originDigest: origin)
        XCTAssertNil(retry.inspectionUnavailableReason)
        XCTAssertEqual(retry.sidecar.bindings.first { $0.nodeID == "a" }, original.sidecar.bindings[0])
        XCTAssertTrue(Set(original.sidecar.bindings[0].particleIDs)
            .isDisjoint(with: retry.sidecar.bindings.first { $0.nodeID == "d" }!.particleIDs))
    }

    func testPresentationFallbackDoesNotHideIdentityOrGraphFailures() throws {
        var map = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<32))
        _ = try map.projectForPresentation(graph(["a"]), sessionID: session, originDigest: origin)
        XCTAssertThrowsError(try map.projectForPresentation(graph(["b"]), sessionID: session,
            originDigest: String(repeating: "c", count: 64))) {
            XCTAssertEqual($0 as? LiminalKnowledgeBindings.BindingError, .invalidIdentity)
        }
        XCTAssertThrowsError(try map.projectForPresentation(graph(["b", "b"]), sessionID: session, originDigest: origin)) {
            XCTAssertEqual($0 as? LiminalKnowledgeBindings.BindingError, .invalidGraph)
        }
        let empty = try map.projectForPresentation(graph([]), sessionID: session, originDigest: origin)
        XCTAssertTrue(empty.sidecar.bindings.isEmpty)
        XCTAssertNil(empty.inspectionUnavailableReason)
        let full = try map.projectForPresentation(graph(["b"]), sessionID: session, originDigest: origin)
        XCTAssertNotNil(full.inspectionUnavailableReason)
        XCTAssertTrue(full.sidecar.bindings.isEmpty)
        let returned = try map.projectForPresentation(graph(["a"]), sessionID: session, originDigest: origin)
        XCTAssertNil(returned.inspectionUnavailableReason)
        XCTAssertEqual(returned.sidecar.bindings.count, 1)
    }

    func testFirstCapacityFallbackClaimsSessionOriginWithoutPartialReservations() throws {
        var map = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<32))
        let fallback = try map.projectForPresentation(graph(["a", "b"]), sessionID: session, originDigest: origin)
        XCTAssertNotNil(fallback.inspectionUnavailableReason)
        XCTAssertThrowsError(try map.projectForPresentation(graph(["b"]), sessionID: session,
            originDigest: String(repeating: "c", count: 64))) {
            XCTAssertEqual($0 as? LiminalKnowledgeBindings.BindingError, .invalidIdentity)
        }
        let retry = try map.projectForPresentation(graph(["b"]), sessionID: session, originDigest: origin)
        XCTAssertNil(retry.inspectionUnavailableReason)
        XCTAssertEqual(retry.sidecar.bindings.map(\.nodeID), ["b"])
    }

    func testEvidenceOnlyChangesInvalidateSelectionWithoutReservingNewParticles() throws {
        var map = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<5000))
        var nodes = graph(["a", "b"]).nodes
        var edge = CompanionGraphEdge(id: "link", source: "a", target: "b", label: "declared support")
        let original = CompanionGraphSnapshot(nodes: nodes, edges: [edge], truncatedCount: 0)
        let sidecar = try map.project(original, sessionID: session, originDigest: origin)
        let now = Date(timeIntervalSince1970: 1_000)
        let pick = LiminalKnowledgeSelection(schemaVersion: 1, sessionID: session, originDigest: origin,
            revision: 4, manifestSHA256: digest, graphDigest: sidecar.graphDigest, nodeID: "a",
            artParticleID: sidecar.bindings[0].anchorID, sequence: 1, updatedAtUnix: 1_000)
        nodes[0].presentationState = .needsReview
        nodes[0].evidenceTrail = [.init(id: "review", stage: .correction, summary: "Review corrected")]
        edge.relationship = .supports; edge.rationale = "A reviewed declaration"; edge.reference = "exact declaration"
        let changes: [CompanionGraphSnapshot] = [
            .init(nodes: [nodes[0], original.nodes[1]], edges: original.edges, truncatedCount: 0),
            .init(nodes: original.nodes, edges: [edge], truncatedCount: 0)
        ]
        for changed in changes {
            XCTAssertNil(pick.resolves(in: sidecar, graph: changed, revisions: [4], after: 0, now: now))
            let updated = try map.project(changed, sessionID: session, originDigest: origin)
            XCTAssertEqual(updated.bindings, sidecar.bindings)
            XCTAssertNotEqual(updated.graphDigest, sidecar.graphDigest)
        }
        let export = try JSONEncoder().encode(KnowledgeParticleExport(field: .init(snapshot: changes[1])))
        XCTAssertFalse(String(decoding: export, as: UTF8.self).contains("A reviewed declaration"))
    }

    func testExactMethodTargetChangesRetireOldNavigation() throws {
        let methodID = UUID().uuidString
        func method(_ binding: DocumentProcedureUse) -> CompanionGraphSnapshot {
            .init(nodes: [.init(id: "method", title: "Retained method", subtitle: "", kind: .method,
                status: "Reviewed", details: [], target: .documentMethod(binding))], edges: [], truncatedCount: 0)
        }
        let firstGraph = method(.init(id: methodID, revision: 1, digest: digest))
        var map = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<64))
        let first = try map.project(firstGraph, sessionID: session, originDigest: origin)
        let pick = LiminalKnowledgeSelection(schemaVersion: 1, sessionID: session, originDigest: origin,
            revision: 1, manifestSHA256: digest, graphDigest: first.graphDigest, nodeID: "method",
            artParticleID: first.bindings[0].anchorID, sequence: 1, updatedAtUnix: 1_000)
        for binding in [DocumentProcedureUse(id: methodID, revision: 2, digest: digest),
                        .init(id: methodID, revision: 1, digest: origin)] {
            let changed = method(binding)
            let current = try map.project(changed, sessionID: session, originDigest: origin)
            XCTAssertEqual(current.bindings, first.bindings)
            XCTAssertNotEqual(current.graphDigest, first.graphDigest)
            XCTAssertNil(pick.resolves(in: first, graph: changed, revisions: [1], after: 0,
                now: Date(timeIntervalSince1970: 1_000)))
        }
        XCTAssertThrowsError(try map.project(method(.init(id: methodID, revision: 0, digest: digest)),
            sessionID: session, originDigest: origin))
    }

    func testEvidenceAndRelationshipTextShareGraphValidationBounds() throws {
        let original = graph(["a", "b"])
        var map = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<64))
        let first = try map.project(original, sessionID: session, originDigest: origin)
        var nodes = original.nodes
        nodes[0].evidenceTrail = [.init(id: "evidence", stage: .checked, summary: String(repeating: "x", count: 8_193))]
        XCTAssertThrowsError(try map.project(.init(nodes: nodes, edges: [], truncatedCount: 0),
            sessionID: session, originDigest: origin))
        nodes[0].evidenceTrail = (0..<33).map { .init(id: "evidence-\($0)", stage: .checked, summary: "") }
        XCTAssertThrowsError(try map.project(.init(nodes: nodes, edges: [], truncatedCount: 0),
            sessionID: session, originDigest: origin))
        let edge = CompanionGraphEdge(id: "edge", source: "a", target: "b", label: "support",
            relationship: .supports, rationale: String(repeating: "x", count: 8_193))
        XCTAssertThrowsError(try map.project(.init(nodes: original.nodes, edges: [edge], truncatedCount: 0),
            sessionID: session, originDigest: origin))
        XCTAssertEqual(first, try map.project(original, sessionID: session, originDigest: origin))
    }
}
