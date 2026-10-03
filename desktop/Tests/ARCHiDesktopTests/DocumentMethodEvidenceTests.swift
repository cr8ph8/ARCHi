import Foundation
import XCTest
@testable import ARCHiDesktop

/// Synthetic owner records only. Projection never dispatches a model or writes.
@MainActor
final class DocumentMethodEvidenceTests: XCTestCase {
    func testPreparedCandidateDoesNotBecomeDispatchedCheckedOrReviewed() throws {
        let fixture = Fixture(); defer { fixture.clean() }
        let method = try fixture.candidate()
        fixture.store.share(text: "Keep this private working passage.", name: "working.txt")
        fixture.store.selectText(range: NSRange(location: 0, length: 9), sourceRevision: fixture.store.sourceRevision)
        fixture.store.preparePassageRevision()
        XCTAssertTrue(fixture.store.prepareDocumentProcedure(method.binding))
        let bytes = try fixture.bytes()
        let node = try fixture.node(method)

        XCTAssertEqual(node.presentationState, .candidate)
        XCTAssertEqual(node.target, .documentMethod(method.binding))
        XCTAssertTrue(node.evidenceTrail.contains { $0.stage == .prepared })
        XCTAssertFalse(node.evidenceTrail.contains { [.dispatched, .checked, .ownerReviewed, .adaptation].contains($0.stage) })
        XCTAssertTrue(node.evidenceTrail.contains { $0.summary.contains("No retained uses") && $0.reference?.contains(method.binding.digest) == true })
        XCTAssertTrue(fixture.store.memoryMapSnapshot().edges.contains { $0.source == node.id && $0.relationship == .authoredFrom })
        XCTAssertEqual(try fixture.bytes(), bytes)
        XCTAssertEqual(fixture.client.calls, 0)

        fixture.store.prompt = "An edited unsent instruction."
        let changed = try fixture.node(method)
        XCTAssertFalse(changed.evidenceTrail.contains { $0.stage == .prepared })
        XCTAssertTrue(changed.evidenceTrail.contains { $0.summary.contains("no longer matches") })
    }

    func testChecksAndOwnerReviewNeverInventMissingDispatchEvidence() throws {
        let fixture = Fixture(); defer { fixture.clean() }
        let method = try fixture.candidate()
        let record = try fixture.record(using: method.binding, verdict: .helpful)
        let withoutDispatch = try fixture.node(method)
        XCTAssertEqual(withoutDispatch.presentationState, .reviewed)
        XCTAssertFalse(withoutDispatch.evidenceTrail.contains { $0.stage == .dispatched })
        XCTAssertTrue(withoutDispatch.evidenceTrail.contains { $0.stage == .checked && $0.summary.contains("1 of 1") })
        XCTAssertTrue(withoutDispatch.evidenceTrail.contains { $0.stage == .ownerReviewed && $0.reference?.contains(record.feedback!.id) == true })
        XCTAssertTrue(withoutDispatch.evidenceTrail.contains { $0.summary.contains("No unambiguous dispatch receipt") })
        XCTAssertTrue(withoutDispatch.evidenceTrail.contains { $0.summary.contains("No valid exact-source Hampton control receipt") })

        try fixture.store.tokenSteward.preflight(requestID: record.requestID, route: .automatic)
        XCTAssertFalse(try fixture.node(method).evidenceTrail.contains { $0.stage == .dispatched }, "Preflight is not dispatch.")
        try fixture.store.tokenSteward.recordDispatch(requestID: record.requestID, provider: .qwen)
        let before = try fixture.bytes()
        let dispatched = try fixture.node(method)
        let entry = try XCTUnwrap(dispatched.evidenceTrail.first { $0.stage == .dispatched })
        XCTAssertTrue(entry.reference?.contains(record.requestID) == true)
        XCTAssertEqual(entry.relatedNodeID, DocumentWorkGraph.nodeID(recordID: record.id))
        XCTAssertEqual(try fixture.node(method), dispatched)
        XCTAssertEqual(try fixture.bytes(), before)
        XCTAssertEqual(fixture.client.calls, 0)
    }

    func testExactVersionCorrectionWithdrawalAndHistoricalOutcomesRemainSeparate() throws {
        let fixture = Fixture(); defer { fixture.clean() }
        let origin = try fixture.record()
        let first = try fixture.store.documentProcedures.keep(from: origin, title: "Plain revision",
            instruction: "Use plain words.", records: fixture.store.documentWork.records)
        let support = try fixture.record(using: first.binding, verdict: .helpful)
        let next = try fixture.store.documentProcedures.revise(binding: first.binding, title: first.title,
            instruction: "Keep qualifications while using plain words.", changeNote: "Retain qualifications.",
            from: support, records: fixture.store.documentWork.records)
        let historical = try fixture.node(first)
        XCTAssertEqual(historical.presentationState, .historical)
        XCTAssertTrue(historical.evidenceTrail.contains { $0.stage == .historical })
        XCTAssertTrue(historical.evidenceTrail.contains { $0.reference?.contains(support.requestID) == true })
        XCTAssertFalse(try fixture.node(next).evidenceTrail.contains { $0.reference?.contains(support.requestID) == true },
            "A later method version cannot inherit an earlier version's use outcomes.")

        let corrected = try fixture.record(using: first.binding, verdict: .needsCorrection)
        let withdrewReview = try fixture.record(using: first.binding, verdict: .withdrawn)
        let correctedNode = try fixture.node(first)
        XCTAssertEqual(correctedNode.presentationState, .corrected)
        XCTAssertTrue(correctedNode.evidenceTrail.contains { $0.stage == .correction && $0.reference?.contains(corrected.requestID) == true })
        XCTAssertTrue(correctedNode.evidenceTrail.contains { $0.stage == .withdrawn && $0.reference?.contains(withdrewReview.feedback!.id) == true })
        try fixture.store.documentProcedures.withdraw(binding: first.binding)
        let withdrawn = try fixture.node(first)
        XCTAssertEqual(withdrawn.presentationState, .withdrawn)
        XCTAssertEqual(withdrawn.id, historical.id)
        XCTAssertTrue(withdrawn.evidenceTrail.contains { $0.stage == .ownerReviewed && $0.reference?.contains(support.requestID) == true })
        XCTAssertTrue(withdrawn.evidenceTrail.contains { $0.stage == .correction })
        let graph = fixture.store.memoryMapSnapshot()
        XCTAssertTrue(graph.edges.contains { $0.source == DocumentMethodGraph.nodeID(next.binding) && $0.target == withdrawn.id && $0.relationship == .supersedes })
        XCTAssertTrue(graph.edges.contains { $0.source == withdrawn.id && $0.target == DocumentWorkGraph.nodeID(recordID: origin.id) && $0.relationship == .retainedFrom })
        XCTAssertTrue(fixture.store.companionGraphSnapshot().edges.contains {
            $0.source == DocumentWorkGraph.nodeID(recordID: support.id) && $0.target == withdrawn.id && $0.relationship == .usedMethod
        })
    }

    func testCapturedHamptonDecisionShowsItsExactInputsAndDeltaWithoutClaimingGain() throws {
        let fixture = Fixture(); defer { fixture.clean() }
        let method = try fixture.candidate()
        let decision = HamptonQ2EController.decide(domain: "document-revision", contextID: fixture.hex("a"),
            signals: .init(observations: 2, retainedSupport: 1, contradictions: 0, unchangedSteps: 0,
                availableAlternatives: 1, remainingBudget: 3, totalBudget: 4), useNumericalControl: false)
        XCTAssertTrue(decision.isValid)
        XCTAssertNotEqual(decision.lane, .stop)
        let record = try fixture.record(using: method.binding, verdict: nil, decision: decision)
        let entry = try XCTUnwrap(try fixture.node(method).evidenceTrail.first { $0.stage == .adaptation })
        XCTAssertTrue(entry.summary.contains(decision.version))
        XCTAssertTrue(entry.summary.contains(try XCTUnwrap(decision.coordinateSchema)))
        XCTAssertTrue(entry.summary.contains("2 observations, 1 support"))
        XCTAssertTrue(entry.summary.contains("budget 3/4"))
        XCTAssertTrue(entry.summary.contains("Delta:"))
        XCTAssertTrue(entry.summary.contains("Action: " + decision.lane.rawValue))
        XCTAssertTrue(entry.summary.contains("initial zero reference; no observed predecessor"))
        XCTAssertTrue(entry.summary.contains("not a learning gain or persistent companion state change"))
        XCTAssertTrue(entry.reference?.contains(decision.bindingDigest) == true)
        XCTAssertTrue(entry.reference?.contains(record.sourceDigest) == true)
        XCTAssertFalse(try fixture.node(method).evidenceTrail.contains { $0.stage == .ownerReviewed })
    }

    func testLegacyControllerDoesNotInventInitialZeroReference() throws {
        let fixture = Fixture(); defer { fixture.clean() }
        let method = try fixture.candidate()
        let current = HamptonQ2EController.decide(domain: "document-revision", contextID: fixture.hex("a"),
            signals: .init(observations: 2, retainedSupport: 1, contradictions: 0, unchangedSteps: 0,
                availableAlternatives: 1, remainingBudget: 3, totalBudget: 4), useNumericalControl: false)
        let legacy = HamptonQ2EDecision(version: HamptonQ2EController.legacyVersion,
            domain: current.domain, contextID: current.contextID, revision: 4, signals: current.signals,
            pressures: current.pressures, delta: current.delta.mapValues { _ in 0.125 },
            laneWeights: current.laneWeights, lane: current.lane, reason: current.reason)
        XCTAssertTrue(legacy.isValid, "Legacy receipts did not bind their prior state or reconstruct delta lineage.")
        XCTAssertNil(legacy.predecessor)
        _ = try fixture.record(using: method.binding, verdict: nil, decision: legacy)
        let entry = try XCTUnwrap(try fixture.node(method).evidenceTrail.first { $0.stage == .adaptation })
        XCTAssertTrue(entry.summary.contains("reference: not recorded by legacy receipt"))
        XCTAssertFalse(entry.summary.contains("initial zero"))
        XCTAssertTrue(entry.reference?.contains(legacy.bindingDigest) == true)
    }

    func testTrailIsBoundedAndStaleOwnersReplaceOutcomeClaimsWithUnknown() throws {
        let fixture = Fixture(); defer { fixture.clean() }
        let method = try fixture.candidate()
        var records: [DocumentWorkRecord] = []
        for index in 0..<6 {
            records.append(try fixture.record(using: method.binding, verdict: .helpful,
                created: Date(timeIntervalSince1970: 1_000 + Double(index))))
        }
        let node = try fixture.node(method)
        XCTAssertLessThanOrEqual(node.evidenceTrail.count, 20)
        XCTAssertTrue(node.evidenceTrail.contains { $0.stage == .historical && $0.summary.contains("latest 3 of 6") && $0.summary.contains("3 earlier uses") })
        XCTAssertFalse(node.evidenceTrail.contains { $0.reference?.contains(records[0].requestID) == true })
        XCTAssertTrue(node.evidenceTrail.contains { $0.reference?.contains(records[5].requestID) == true })

        let other = DocumentProcedureLibrary(url: fixture.methodURL)
        try other.withdraw(binding: method.binding)
        let bytes = try fixture.bytes()
        let stale = try fixture.node(method)
        XCTAssertEqual(stale.presentationState, .needsReview)
        XCTAssertEqual(stale.evidenceTrail.count, 1)
        XCTAssertEqual(stale.evidenceTrail.first?.stage, .unknown)
        XCTAssertEqual(try fixture.bytes(), bytes)
        XCTAssertEqual(fixture.client.calls, 0)
    }

    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-method-evidence-\(UUID())")
        let client = MethodEvidenceNoModelClient()
        var preferenceURL: URL { directory.appendingPathComponent("preferences.json") }
        var methodURL: URL { directory.appendingPathComponent("preferences.document-procedures.json") }
        lazy var store = CompanionStore(preferenceURL: preferenceURL, assistant: client,
            assistantFactory: { [client] _, _ in client }, allowsPlay: false, tokenSteward: TokenStewardStore())

        func candidate() throws -> DocumentProcedure {
            let source = try store.readingSources.keep(title: "Synthetic source", text: "Keep claims attributed.")
            let anchor = try store.readingSources.makeAnchor(sourceID: source.id,
                range: NSRange(location: 0, length: source.text.utf16.count))
            let draft = try store.readingSources.saveKnowledgePage(title: "Attribution", body: "Keep the source attribution.",
                kind: .concept, anchors: [anchor])
            let page = try store.readingSources.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
            return try store.documentProcedures.keepCandidate(from: page, title: "Plain revision", instruction: "Use plain words.",
                requirements: store.documentRequirements, knowledgeIsCurrent: { self.store.knowledgeDependenciesAreCurrent([$0]) })
        }

        func record(using method: DocumentProcedureUse? = nil,
                    verdict: DocumentWorkFeedback.Verdict? = .helpful,
                    decision: HamptonQ2EDecision? = nil, created: Date = Date()) throws -> DocumentWorkRecord {
            let request = UUID().uuidString
            var record = DocumentWorkRecord(id: request + "-Qwen", requestID: request,
                provider: AssistantProvider.qwen.rawValue, targetID: UUID().uuidString,
                sourceDigest: hex("a"), sourceRevision: 1, selectionStart: 0, selectionLength: 12,
                preserveNumbersAndLinks: true, createdAt: created, updatedAt: created.addingTimeInterval(20),
                state: .applying, proposedDigest: hex("b"), expectedAfterDigest: hex("c"), actualAfterDigest: hex("c"), afterRevision: 2,
                checks: [.init(id: "source", title: "Exact source", passed: true)],
                learning: .init(requestBinding: .init(inputDigest: hex("d"), contextDigest: hex("e")), suppliedLessons: []),
                procedureUse: method, q2eDecision: decision)
            try store.documentWork.save(record)
            record.state = .applied
            if let verdict {
                record.feedback = .init(revision: 1, verdict: verdict, recordedAt: created.addingTimeInterval(10))
                if method != nil && verdict != .helpful { record.procedureUseRejected = true }
            }
            try store.documentWork.save(record)
            return record
        }

        func node(_ method: DocumentProcedure) throws -> CompanionGraphNode {
            try XCTUnwrap(store.memoryMapSnapshot().nodes.first { $0.id == DocumentMethodGraph.nodeID(method.binding) })
        }

        func bytes() throws -> [String: Data] {
            guard let enumerator = FileManager.default.enumerator(at: directory,
                includingPropertiesForKeys: [.isRegularFileKey]) else { return [:] }
            var result: [String: Data] = [:]
            for case let url as URL in enumerator {
                if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                    result[url.lastPathComponent] = try Data(contentsOf: url)
                }
            }
            return result
        }

        func hex(_ character: Character) -> String { String(repeating: character, count: 64) }
        func clean() { store.disconnectAssistant(); try? FileManager.default.removeItem(at: directory) }
    }
}

@MainActor private final class MethodEvidenceNoModelClient: AssistantClient {
    var calls = 0
    func connect() async throws {}
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1
        XCTFail("Inspecting method evidence must never dispatch a model.")
    }
}
