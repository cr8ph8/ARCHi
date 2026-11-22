import XCTest
@testable import ARCHiDesktop

final class SeedTelemetryTests: XCTestCase {
    private let context = ContextTicket(generation: 1, placement: 2, source: 3, selection: 4)

    func testIdleProjectionHasNoInventedActivityOrActivationRecorder() throws {
        let snapshot = project()
        XCTAssertEqual(snapshot.origin, "native")
        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.telemetry.harness.state, "idle")
        XCTAssertTrue(snapshot.telemetry.harness.lanes.isEmpty)
        XCTAssertEqual(snapshot.telemetry.peer.progress, "idle")
        XCTAssertNil(snapshot.telemetry.peer.simulation)
        XCTAssertFalse(snapshot.telemetry.peer.candidateReady)
        XCTAssertEqual(snapshot.telemetry.peer.acceptedReportCount, 0)
        XCTAssertFalse(snapshot.telemetry.neural.available)
        XCTAssertEqual(snapshot.telemetry.neural.reason, "No activation recorder is connected.")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(try snapshot.webPayload()))
    }

    func testRequestIdentityAndRecordedInvocationAreIndependentOfProviderName() throws {
        var first = receipt(id: "request-one")
        first.requestStarted = true
        first.modelIdentity = "recorded-model @ synthetic-digest"
        first.localInvocationReceipts = [.init(id: "selection-one", role: .memorySelection,
            inputDigest: "private-input", systemDigest: "private-system", schemaDigest: "private-schema",
            outcome: .completed)]
        let lane = AssistantLaneResult(text: "private-answer", status: "private-status", state: .pending, receipt: first)
        let snapshot = project(lanes: [.qwen: lane], isWorking: true)
        let row = try XCTUnwrap(snapshot.telemetry.harness.lanes.first)
        XCTAssertEqual(row.id, "qwen")
        XCTAssertEqual(row.provider, "Qwen")
        XCTAssertEqual(row.requestID, "request-one")
        XCTAssertEqual(row.contextCurrent, true)
        XCTAssertTrue(row.requestStarted)
        XCTAssertEqual(row.phase, "Request in progress")
        XCTAssertEqual(row.invocations.first?.role, "MEMORY_SELECTION")
        XCTAssertEqual(row.invocations.first?.status, "completed")
        XCTAssertEqual(row.modelIdentity, "recorded-model @ synthetic-digest")
        XCTAssertFalse(snapshot.telemetry.neural.available, "A model identity is not an activation recorder")

        let second = AssistantLaneResult(text: "", status: "", state: .pending, receipt: receipt(id: "request-two"))
        let changed = project(lanes: [.qwen: second], isWorking: true)
        XCTAssertEqual(changed.telemetry.harness.lanes.first?.id, row.id)
        XCTAssertNotEqual(changed.telemetry.harness.lanes.first?.requestID, row.requestID)
        XCTAssertTrue(changed.telemetry.harness.lanes.first?.invocations.isEmpty == true)
    }

    func testTerminalOutcomesRemainDistinctAndNeverBecomeKeptMemory() throws {
        for state in [AssistantLaneState.complete, .failed, .cancelled] {
            var value = receipt(id: "terminal", state: state)
            let outcome: HamptonAdmissionOutcome.Status = state == .complete ? .accepted : state == .failed ? .rejected : .stopped
            value.admissionOutcome = .init(status: outcome, stage: .publication, role: .reasoning,
                requestID: value.requestID, reason: state == .failed ? .staleContext : state == .cancelled ? .cancelled : nil)
            let snapshot = project(lanes: [.qwen: .init(text: "", status: "", state: state, receipt: value)])
            let lane = try XCTUnwrap(snapshot.telemetry.harness.lanes.first)
            XCTAssertEqual(lane.state, state.rawValue)
            XCTAssertEqual(lane.admission?.status, outcome.rawValue)
            XCTAssertEqual(lane.admission?.stage, "publication")
            XCTAssertEqual(snapshot.telemetry.memory.keptLessonCount, 0)
            XCTAssertEqual(snapshot.telemetry.peer.acceptedReportCount, 0)
        }
    }

    func testContextReplacementChangesOpaqueIdentityAndMarksOldReceipt() throws {
        let prior = receipt(id: "old-request", state: .cancelled)
        let lane = AssistantLaneResult(text: "", status: "", state: .cancelled, receipt: prior)
        let old = project(lanes: [.qwen: lane])
        let replacement = ContextTicket(generation: 1, placement: 2, source: 5, selection: 4)
        let changed = project(lanes: [.qwen: lane], ticket: replacement)
        XCTAssertNotEqual(old.contextID, changed.contextID)
        XCTAssertEqual(changed.contextID.utf8.count, 72)
        XCTAssertEqual(changed.telemetry.harness.lanes.first?.contextCurrent, false)
        XCTAssertEqual(changed.telemetry.harness.lanes.first?.state, "cancelled")
        XCTAssertNotEqual(old.contextID, project(lessonRevision: 2).contextID)
        XCTAssertTrue(project(ticket: replacement).telemetry.harness.lanes.isEmpty)

        let node = CompanionGraphNode(id: "private", title: "Current record", subtitle: "",
            kind: .lesson, status: "Current", details: [.init(label: "Words", value: "Private fixture")], target: .memory)
        let original = CompanionGraphSnapshot(nodes: [node], edges: [], truncatedCount: 0)
        let statusOnly = CompanionGraphNode(id: node.id, title: node.title, subtitle: node.subtitle,
            kind: node.kind, status: "Expired", details: node.details, target: node.target)
        let updated = CompanionGraphSnapshot(nodes: [statusOnly], edges: [], truncatedCount: 0)
        XCTAssertFalse(SeedDiveReplacementPolicy.requiresFence(previous: original, next: updated,
            previousContextID: old.contextID, nextContextID: old.contextID), "Status-only updates stay visible for animation")
        XCTAssertFalse(SeedDiveReplacementPolicy.requiresFence(previous: .empty, next: original,
            previousContextID: old.contextID, nextContextID: old.contextID), "Additions do not hide the live page")
        XCTAssertTrue(SeedDiveReplacementPolicy.requiresFence(previous: original, next: .empty,
            previousContextID: old.contextID, nextContextID: old.contextID), "Removed records need an immediate redaction fence")
        XCTAssertTrue(SeedDiveReplacementPolicy.requiresFence(previous: original, next: original,
            previousContextID: old.contextID, nextContextID: changed.contextID), "A new context hides the prior content")
        let redacted = CompanionGraphNode(id: node.id, title: node.title, subtitle: node.subtitle,
            kind: node.kind, status: node.status, details: [.init(label: "Words", value: "Unavailable")], target: node.target)
        XCTAssertTrue(SeedDiveReplacementPolicy.requiresFence(previous: original,
            next: .init(nodes: [redacted], edges: [], truncatedCount: 0),
            previousContextID: old.contextID, nextContextID: old.contextID), "Changed text needs the same fence even with a retained identity")
    }

    func testTelemetryExcludesPromptsAnswersSourceBodiesAndInternalDigests() throws {
        var value = receipt(id: "request")
        value.sourceDigest = "PRIVATE_SOURCE_DIGEST"
        value.localConversationDigest = "PRIVATE_CONVERSATION_DIGEST"
        value.localLessons = [LessonSnapshot(lesson: .init(topic: "PRIVATE_TOPIC", text: "PRIVATE_LESSON",
            createdAt: Date(timeIntervalSince1970: 1)))]
        let node = CompanionGraphNode(id: "source", title: "PRIVATE_SOURCE_TITLE", subtitle: "PRIVATE_SUBTITLE",
            kind: .source, status: "Current", details: [.init(label: "Body", value: "PRIVATE_SOURCE_BODY")], target: .context)
        let graph = CompanionGraphSnapshot(nodes: [node], edges: [], truncatedCount: 3)
        let snapshot = project(lanes: [.qwen: .init(text: "PRIVATE_ANSWER", status: "PRIVATE_STATUS",
            state: .pending, receipt: value)], graph: graph)
        let encoded = try JSONEncoder().encode(snapshot)
        let json = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(json.contains("PRIVATE_"))
        XCTAssertFalse(json.contains("deadline"))
        XCTAssertFalse(json.contains("inputDigest"))
        XCTAssertFalse(json.contains("localLessons"))
        XCTAssertEqual(snapshot.telemetry.memory.graphNodeCount, 1)
        XCTAssertEqual(snapshot.telemetry.memory.graphEdgeCount, 0)
        XCTAssertEqual(snapshot.telemetry.memory.truncatedCount, 3)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(try snapshot.webPayload()))
    }

    func testExplicitLimitsPreserveUniqueLongIdentifiersAndValidUnicode() throws {
        var value = receipt(id: String(repeating: "x", count: 300) + "first")
        value.modelIdentity = String(repeating: "🎼", count: 200)
        value.localInvocationReceipts = (0..<20).map { index in
            .init(id: String(repeating: "i", count: 300) + String(index), role: .reasoning,
                inputDigest: "", systemDigest: "", schemaDigest: "")
        }
        var lab = CompanionPeerLabState()
        lab.lastDecision = .init(id: 1, attemptID: nil, epoch: nil, decision: .escalate,
            detail: "private detail", at: nil, reportID: nil,
            checks: (0..<20).map { .init(id: "check-\($0)", status: .error, detail: "private") })
        let snapshot = project(lanes: [.qwen: .init(text: "", status: "", state: .pending, receipt: value)], lab: lab)
        let row = try XCTUnwrap(snapshot.telemetry.harness.lanes.first)
        XCTAssertLessThanOrEqual(try XCTUnwrap(row.requestID).utf8.count, SeedTelemetryProjection.maximumIdentifierBytes)
        XCTAssertLessThanOrEqual(try XCTUnwrap(row.modelIdentity).utf8.count, SeedTelemetryProjection.maximumModelIdentityBytes)
        XCTAssertFalse(try XCTUnwrap(row.modelIdentity).contains("�"))
        XCTAssertEqual(row.invocations.count, SeedTelemetryProjection.maximumInvocationsPerLane)
        XCTAssertEqual(Set(row.invocations.map(\.id)).count, row.invocations.count)
        XCTAssertEqual(row.omittedInvocationCount, 4)
        XCTAssertEqual(snapshot.telemetry.peer.checks.count, SeedTelemetryProjection.maximumChecks)
        XCTAssertEqual(snapshot.telemetry.peer.omittedCheckCount, 4)
        let other = receipt(id: String(repeating: "x", count: 300) + "second")
        XCTAssertNotEqual(row.requestID, project(lanes: [.qwen: .init(text: "", status: "", state: .pending,
            receipt: other)]).telemetry.harness.lanes.first?.requestID)
    }

    func testSyntheticPeerProvenanceNeverBecomesNeuralOrNativeNetworkEvidence() throws {
        var lab = CompanionPeerLabState()
        var simulation = PeerGossipSimulation(seed: 42)
        XCTAssertTrue(simulation.start(now: 0))
        XCTAssertTrue(simulation.step(now: 1))
        lab.simulation = simulation
        let snapshot = project(lab: lab)
        XCTAssertEqual(snapshot.origin, "native")
        XCTAssertEqual(snapshot.telemetry.peer.simulation?.origin, "synthetic")
        XCTAssertEqual(snapshot.telemetry.peer.simulation?.round, 1)
        XCTAssertEqual(snapshot.telemetry.peer.simulation?.workerCount, 4)
        XCTAssertFalse(snapshot.telemetry.neural.available)
        XCTAssertEqual(snapshot.telemetry.peer.acceptedReportCount, 0)
    }

    @MainActor
    func testStoreProjectionDoesNotDispatchPersistOrAcceptAndRefreshesFromCurrentState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-seed-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = directory.appendingPathComponent("preferences.json")
        let lesson = KeptLesson(topic: "Synthetic", text: "Private fixture lesson", createdAt: Date(timeIntervalSince1970: 1))
        let bytes = try NativePreferenceDocument(lessons: [lesson]).encoded()
        try bytes.write(to: profile)
        let client = SeedTelemetryClient()
        let store = CompanionStore(preferenceURL: profile, assistant: client,
            assistantFactory: { _, _ in client }, allowsPlay: false)
        store.share(text: "Private fixture source", name: "fixture.txt")
        let current = store.seedTelemetrySnapshot(graph: store.companionGraphSnapshot())
        let again = store.seedTelemetrySnapshot(graph: store.companionGraphSnapshot())
        XCTAssertEqual(current, again, "Reading unchanged owners must not create clock or event activity")
        XCTAssertEqual(current.telemetry.memory.keptLessonCount, 1)
        XCTAssertEqual(current.telemetry.memory.graphNodeCount, store.companionGraphSnapshot().nodes.count)
        XCTAssertEqual(client.connectCount, 0)
        XCTAssertEqual(client.replyCount, 0)
        XCTAssertTrue(store.peerLab.inspection.reports.isEmpty)
        XCTAssertEqual(try Data(contentsOf: profile), bytes)

        store.preparePeerInspection()
        let candidate = store.seedTelemetrySnapshot(graph: store.companionGraphSnapshot())
        XCTAssertEqual(candidate.telemetry.peer.progress, "candidateReady")
        XCTAssertTrue(candidate.telemetry.peer.candidateReady)
        XCTAssertEqual(candidate.telemetry.peer.acceptedReportCount, 0)
        store.cancelPeerInspection()
        let cancelled = store.seedTelemetrySnapshot(graph: store.companionGraphSnapshot())
        XCTAssertEqual(cancelled.telemetry.peer.progress, "cancelled")
        XCTAssertFalse(cancelled.telemetry.peer.candidateReady)
        XCTAssertEqual(cancelled.telemetry.peer.acceptedReportCount, 0)
        XCTAssertEqual(client.connectCount, 0)
        XCTAssertEqual(client.replyCount, 0)
        XCTAssertEqual(try Data(contentsOf: profile), bytes)
    }

    private func project(lanes: [AssistantProvider: AssistantLaneResult] = [:], isWorking: Bool = false,
                         ticket: ContextTicket? = nil, lessonRevision: UInt64 = 1,
                         lab: CompanionPeerLabState = .init(), graph: CompanionGraphSnapshot = .empty) -> SeedTelemetrySnapshot {
        SeedTelemetryProjection.build(context: ticket ?? context, lessonRevision: lessonRevision, graph: graph,
            keptLessonCount: 0, temporaryRecordCount: 0, isWorking: isWorking, lanes: lanes, peerLab: lab)
    }

    private func receipt(id: String, state: AssistantLaneState = .pending) -> AssistantLaneReceipt {
        .init(requestID: id, route: .local, provider: .qwen, context: context,
            inputDigest: "PRIVATE_INPUT_DIGEST", inputContract: "PRIVATE_CONTRACT",
            deadline: Date(timeIntervalSince1970: 123), modelIdentity: nil, state: state)
    }
}

@MainActor
private final class SeedTelemetryClient: AssistantClient {
    private(set) var connectCount = 0
    private(set) var replyCount = 0
    func connect() async throws { connectCount += 1 }
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        replyCount += 1
        onEvent(.text("Controlled synthetic reply"))
    }
}
