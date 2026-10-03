import XCTest
@testable import ARCHiDesktop

@MainActor
final class ARC3IntegrationTests: XCTestCase {
    func testOnlyWholeUserCommandsSelectInteractiveCapability() {
        XCTAssertEqual(ARC3AssistantCommand.select(" /ARC3 EXPLORE\n"), .explore)
        XCTAssertEqual(ARC3AssistantCommand.select("open ARC3"), .open)
        XCTAssertEqual(ARC3AssistantCommand.select("/arc3 run arbitrary.py"), .invalid)
        XCTAssertNil(ARC3AssistantCommand.select("The document says /arc3 explore"))
        XCTAssertNil(ARC3AssistantCommand.select("\"/arc3 explore\""))
        XCTAssertNil(ARC3AssistantCommand.select("/arc30"))
    }

    func testInteractiveCommandIsAvailableDisconnectedWithoutSendingAModelRequest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"))
        store.prompt = "/arc3 invalid"
        XCTAssertTrue(store.canBeginReply)
        XCTAssertTrue(AssistantComposerState(store: store).canSend)
        XCTAssertTrue(store.nextCallBudget.contains("0 model calls"))
        store.submit()
        XCTAssertEqual(store.reply, "Use /arc3 open, /arc3 explore, or /arc3 stop.")
        XCTAssertFalse(store.arc3.isSessionActive)
        XCTAssertTrue(store.tokenSteward.tasks.isEmpty)
    }

    func testEnvironmentProgressCannotBecomeCheckedAnswerOrTokenUsage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TokenStewardStore(url: directory.appendingPathComponent("usage.json"))
        let start = Date(timeIntervalSince1970: 1_000)
        let summary = ARC3SessionSummary(sessionID: "arc3-test", gameID: "fixture-version",
            startedAt: start, finishedAt: start.addingTimeInterval(5), dispatches: 3,
            outcome: "complete", receiptURL: nil, lastState: "WIN", error: nil)
        try store.recordInteractiveARC(summary)
        try store.recordInteractiveARC(summary)
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.summary.interactiveSessionCount, 1)
        XCTAssertEqual(store.summary.deliveredTaskCount, 0)
        XCTAssertEqual(store.summary.checkedSuccessfulTaskCount, 0)
        XCTAssertEqual(store.summary.localAttemptCount, 0)
        XCTAssertEqual(store.summary.subscriptionRequestCount, 0)
        XCTAssertTrue(store.tasks[0].outcomes.isEmpty)
        XCTAssertThrowsError(try store.recordUseful(requestID: "arc3-test"))
        XCTAssertThrowsError(try store.recordChecked(requestID: "arc3-test", evidenceID: "invented", passed: true))
    }

    func testInteractiveGraphKeepsBoundsEndpointsAndExactAccountingTarget() {
        let start = Date(timeIntervalSince1970: 1_000)
        let observation = ARC3Observation(gameID: "fixture-version", state: "NOT_FINISHED",
            levelsCompleted: 0, winLevels: 1, availableActions: [1], frame: [[1]],
            frameDigest: String(repeating: "a", count: 64), dispatches: 3, budget: 32)
        let transitions = (0..<20).map { _ in
            ARC3Transition(id: UUID(), beforeDigest: observation.frameDigest, afterDigest: observation.frameDigest,
                action: 1, x: nil, y: nil, predictedDigest: nil, verdict: .observed, invalidated: false,
                before: observation, after: observation)
        }
        let summary = ARC3SessionSummary(sessionID: "arc3-exact-session", gameID: observation.gameID,
            startedAt: start, finishedAt: start.addingTimeInterval(5), dispatches: 3, outcome: "stopped",
            receiptURL: nil, lastState: observation.state, error: nil, attemptedDispatches: 3)
        let base = CompanionGraph.build(receipts: [], lessons: [], source: nil, now: start)
        let normal = ARC3Graph.append(to: base, observation: observation, transitions: transitions, summary: summary)
        XCTAssertEqual(normal.nodes.filter { $0.id.hasPrefix("arc3-transition-") }.count, 16)
        XCTAssertEqual(normal.nodes.first { $0.kind == .accounting }?.target,
                       .stewardTask(taskID: summary.sessionID))
        XCTAssertEqual(normal.nodes.first { $0.id == "arc3-current-episode" }?.target, .interactiveARC)
        XCTAssertFalse(normal.nodes.contains { $0.kind == .lesson || $0.kind == .answer })
        XCTAssertGreaterThanOrEqual(normal.truncatedCount, 4)

        let filler = (0..<(CompanionGraph.maximumNodes - base.nodes.count - 2)).map { index in
            CompanionGraphNode(id: "filler-\(index)", title: "Existing record", subtitle: "",
                kind: .context, status: "", details: [], target: nil)
        }
        let fullEdges = (0..<(CompanionGraph.maximumEdges - 1)).map { index in
            CompanionGraphEdge(id: "existing-edge-\(index)", source: "companion-archi",
                target: "filler-0", label: "existing relationship")
        }
        let crowded = CompanionGraphSnapshot(nodes: base.nodes + filler, edges: fullEdges, truncatedCount: 0)
        let bounded = ARC3Graph.append(to: crowded, observation: observation, transitions: transitions, summary: summary)
        XCTAssertLessThanOrEqual(bounded.nodes.count, CompanionGraph.maximumNodes)
        XCTAssertLessThanOrEqual(bounded.edges.count, CompanionGraph.maximumEdges)
        let nodeIDs = Set(bounded.nodes.map(\.id))
        XCTAssertTrue(bounded.edges.allSatisfy { nodeIDs.contains($0.source) && nodeIDs.contains($0.target) })
        XCTAssertEqual(nodeIDs.count, bounded.nodes.count)
        XCTAssertGreaterThan(bounded.truncatedCount, 0)
    }
}
