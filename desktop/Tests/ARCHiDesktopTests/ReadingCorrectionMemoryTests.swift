import Foundation
import XCTest
@testable import ARCHiDesktop

/// Exercises the real native feedback owners with deterministic in-process role
/// responses. No local weights, external models, games, or user files are used.
final class ReadingCorrectionMemoryTests: XCTestCase {
    @MainActor
    func testCorrectionDropsGeneratedContinuationButPreservesAnswerLessonsAndSourceSpans() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let receipt = try await fixture.answer()
        let store = fixture.store
        let displayed = store.compareResults[.qwen]
        let lessons = store.keptLessons
        let bank = fixture.assistant.snapshot.records
        XCTAssertFalse(bank.isEmpty, "This fixture retained an exact input span through the real context owner.")
        XCTAssertEqual(store.nextReplyConversation.count, 1)

        store.reviewReading(receipt, useful: false)

        XCTAssertTrue(store.nextReplyConversation.isEmpty)
        XCTAssertTrue(store.localConversation.exchanges.isEmpty)
        XCTAssertEqual(store.compareResults[.qwen], displayed)
        XCTAssertEqual(store.keptLessons, lessons)
        XCTAssertEqual(fixture.assistant.snapshot.records, bank,
            "Rejecting generated output does not erase the separately retained user/source spans.")
        XCTAssertEqual(store.tokenSteward.tasks.first { $0.id == receipt.requestID }?.outcomes.last?.value, false)
        XCTAssertEqual(fixture.reasoner.requests.count, 1, "Feedback does not run another inference.")
    }

    @MainActor
    func testHelpfulReversalDoesNotRestoreOldContinuationOrAwardLearning() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let receipt = try await fixture.answer()
        let store = fixture.store
        XCTAssertTrue(store.markReplyUsefulForEvolution(provider: .qwen, requestID: receipt.requestID))
        XCTAssertEqual(store.evolution.usefulReceipts.count, 1)
        store.reviewReading(receipt, useful: false)
        XCTAssertTrue(store.evolution.usefulReceipts.isEmpty)
        XCTAssertFalse(store.markReplyUsefulForEvolution(provider: .qwen, requestID: receipt.requestID))

        store.reviewReading(receipt, useful: true)

        XCTAssertFalse(store.markReplyUsefulForEvolution(provider: .qwen, requestID: receipt.requestID),
            "A changed passage verdict cannot re-award development credit to the same corrected answer.")
        XCTAssertTrue(store.nextReplyConversation.isEmpty)
        XCTAssertTrue(store.evolution.usefulReceipts.isEmpty,
            "Changing a reading verdict does not re-create an earlier explicit development review.")
        XCTAssertEqual(store.compareResults[.qwen]?.text, ReadingCorrectionRoleClient.answer)
        XCTAssertEqual(store.tokenSteward.tasks.first { $0.id == receipt.requestID }?.outcomes.last?.value, true)
    }

    @MainActor
    func testFailedFeedbackWriteDoesNotClearTheRetainedConversation() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let receipt = try await fixture.answer()
        let store = fixture.store
        let before = store.localConversation.exchanges
        let displayed = store.compareResults[.qwen]
        let damaged = Data("not a native journal".utf8)
        try damaged.write(to: fixture.stewardURL, options: .atomic)

        store.reviewReading(receipt, useful: false)

        XCTAssertEqual(store.localConversation.exchanges, before)
        XCTAssertEqual(store.compareResults[.qwen], displayed)
        XCTAssertEqual(try Data(contentsOf: fixture.stewardURL), damaged)
        XCTAssertNotNil(store.documentReadingMessage)
        XCTAssertEqual(fixture.reasoner.requests.count, 1)
    }

    @MainActor
    func testReloadCannotRestoreWithdrawnLearningAfterAHelpfulReadingReversal() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let receipt = try await fixture.answer()
        XCTAssertTrue(fixture.store.markReplyUsefulForEvolution(provider: .qwen, requestID: receipt.requestID))
        XCTAssertTrue(fixture.store.evolution.save())
        let savedURL = try XCTUnwrap(fixture.store.evolution.saveURL)
        let originalSaved = try Data(contentsOf: savedURL)
        fixture.store.reviewReading(receipt, useful: false)
        fixture.store.reviewReading(receipt, useful: true)
        XCTAssertEqual(fixture.store.tokenSteward.tasks.first { $0.id == receipt.requestID }?.outcomes.last?.value, true)

        let reopened = CompanionStore(preferenceURL: fixture.preferenceURL,
            assistant: fixture.assistant, assistantFactory: { _, _ in fixture.assistant }, allowsPlay: false)
        XCTAssertTrue(reopened.evolution.load())
        XCTAssertTrue(reopened.evolution.usefulReceipts.isEmpty)
        XCTAssertEqual(reopened.keptLessons, fixture.store.keptLessons)
        XCTAssertEqual(try Data(contentsOf: savedURL), originalSaved,
            "The saved receipt stays historical; a Helpful reversal cannot restore its withdrawn development credit.")
        reopened.disconnectAssistant()
    }

    @MainActor
    func testCrossWriterCorrectionRevokesAncestorAndDescendantContextBeforeNextUse() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let first = try await fixture.answer()
        let followUp = try await fixture.answer(question: "Explain that summary of the meeting notes.")
        let store = fixture.store
        let lessons = store.keptLessons
        XCTAssertEqual(followUp.localConversationCount, 1)
        let followUpRequest = try fixture.reasoningRequest(at: 1)
        XCTAssertNotNil(followUpRequest.input["context"]?["localConversation"], fixture.diagnostics)
        XCTAssertTrue(store.markReplyUsefulForEvolution(provider: .qwen, requestID: followUp.requestID))
        store.reviewReading(followUp, useful: true)
        let trace = try XCTUnwrap(store.tokenSteward.tasks.first { $0.id == followUp.requestID }?.documentReading)
        XCTAssertEqual(trace.conversationRequestIDs, [first.requestID],
            "The journal retains the consumed answer's owner, not just the visible text.")
        XCTAssertEqual(HamptonReadingOutcomeAdapter.project(tasks: store.tokenSteward.tasks,
            sourceDigest: trace.sourceDigest).support, 1)

        // This owner writes only to the shared journal. The live companion must
        // refresh at use time and find the correction to its earlier ancestor.
        let writer = TokenStewardStore(url: fixture.stewardURL)
        try writer.recordDocumentReadingFeedback(requestID: first.requestID, useful: false)
        let correctedEvidence = HamptonReadingOutcomeAdapter.project(tasks: writer.tasks, sourceDigest: trace.sourceDigest)
        XCTAssertTrue(correctedEvidence.isValid)
        XCTAssertNil(correctedEvidence.reconciliationIssue)
        XCTAssertEqual(correctedEvidence.support, 0)
        XCTAssertEqual(correctedEvidence.corrections, 1,
            "Withdrawing descendant support must not invent a second negative user review.")
        XCTAssertFalse(correctedEvidence.bindings.contains { $0.taskID == followUp.requestID })
        let fresh = try await fixture.answer(question: "Summarize the meeting notes again using the source.")

        XCTAssertEqual(fresh.localConversationCount, 0)
        let freshRequest = try fixture.reasoningRequest(at: 2)
        XCTAssertNil(freshRequest.input["context"]?["localConversation"],
            "Neither the rejected answer nor a follow-up derived from it may enter the next request.")
        XCTAssertEqual(store.localConversation.exchanges.count, 1,
            "Only the fresh answer may start the next generated continuation.")
        XCTAssertTrue(store.evolution.usefulReceipts.isEmpty,
            "A corrected ancestor also withdraws the descendant's earlier development credit.")
        XCTAssertEqual(store.keptLessons, lessons)
        XCTAssertEqual(fixture.reasoner.requests.count, 3)
    }

    @MainActor
    func testGenericUsefulCannotOverrideSpecificNegativeReadingFeedback() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let receipt = try await fixture.answer()
        let store = fixture.store
        let displayed = store.compareResults[.qwen]
        let writer = TokenStewardStore(url: fixture.stewardURL)
        try writer.recordDocumentReadingFeedback(requestID: receipt.requestID, useful: false)
        try writer.recordUseful(requestID: receipt.requestID)
        XCTAssertEqual(writer.tasks.first { $0.id == receipt.requestID }?.outcomes.last?.value, true,
            "The latest generic vote is deliberately positive; the specific reading correction still applies.")

        XCTAssertFalse(store.markReplyUsefulForEvolution(provider: .qwen, requestID: receipt.requestID))

        XCTAssertTrue(store.evolution.usefulReceipts.isEmpty)
        XCTAssertTrue(store.nextReplyConversation.isEmpty)
        XCTAssertEqual(store.compareResults[.qwen], displayed)
        XCTAssertEqual(fixture.reasoner.requests.count, 1)
    }

    @MainActor
    private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-reading-correction-\(UUID())")
        let reasoner = ReadingCorrectionRoleClient()
        let selector = ReadingCorrectionRoleClient()
        let assistant: HamptonReasonsAssistant
        let preferenceURL: URL
        let stewardURL: URL
        let store: CompanionStore

        init() throws {
            preferenceURL = directory.appendingPathComponent("preferences.json")
            stewardURL = preferenceURL.deletingPathExtension().appendingPathExtension("steward.json")
            assistant = HamptonReasonsAssistant(reasoner: reasoner, contextSelector: selector)
            let local = assistant
            store = CompanionStore(preferenceURL: preferenceURL, assistant: local,
                assistantFactory: { _, _ in local }, allowsPlay: false)
            store.setSessionContextEnabled(true)
            store.share(text: "# Meeting notes\nThe proposed event is Thursday. Verify that date before publishing.", name: "meeting.txt")
            store.beginLessonCorrection()
            var draft = try XCTUnwrap(store.lessonDraft)
            draft.topic = "meeting notes"
            draft.text = "Keep proposed dates separate from confirmed dates."
            draft.taskScope = .documentQuestion
            XCTAssertTrue(store.keepLesson(draft))
            store.evolution.observeJourneyOrigin(String(repeating: "a", count: 64))
        }

        func answer(question: String = "Summarize the meeting notes.") async throws -> AssistantLaneReceipt {
            store.setAssistantRoute(.automatic)
            store.prompt = question
            store.submit()
            XCTAssertTrue(store.isWorking, diagnostics)
            for _ in 0..<400 {
                if !store.isWorking { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            let lane = try XCTUnwrap(store.compareResults[.qwen], diagnostics)
            let receipt = try XCTUnwrap(lane.state == .complete ? lane.receipt : nil, diagnostics)
            return try XCTUnwrap(store.canReviewReading(receipt) ? receipt : nil, diagnostics)
        }

        func reasoningRequest(at index: Int) throws -> LocalRoleRequest {
            try XCTUnwrap(reasoner.requests.dropFirst(index).first, diagnostics)
        }

        /// Bounded provenance diagnostics only; no source or generated prose.
        var diagnostics: String {
            let lane = store.compareResults[.qwen]
            let receipt = lane?.receipt
            let task = store.tokenSteward.tasks.first { $0.id == receipt?.requestID }
            let journalLanes = task?.lanes.map { "\($0.provider):\($0.state):dispatched=\($0.dispatched)" }.joined(separator: ",") ?? "none"
            return String([
                "status=\(store.status)", "lane=\(String(describing: lane?.state))",
                "receiptState=\(String(describing: receipt?.state))", "request=\(receipt?.requestID ?? "none")",
                "readingResult=\(receipt?.readingResult?.kind ?? "none")",
                "readingPlan=\(receipt?.documentReading != nil)",
                "admission=\(String(describing: receipt?.admissionOutcome ?? assistant.snapshot.admissionOutcome))",
                "contextCurrent=\(receipt.map { store.isCurrentReplyContext($0) } ?? false)",
                "journalTask=\(task != nil)", "journalLanes=\(journalLanes)",
                "journalResult=\(task?.documentReadingResult?.kind ?? "none")",
                "loadError=\(store.tokenSteward.loadError ?? "none")",
                "steward=\(store.stewardMessage ?? "none")",
                "readingMessage=\(store.documentReadingMessage ?? "none")",
                "requests=\(reasoner.requests.count)",
                "admission=\(String(describing: store.hamptonSnapshot.admissionOutcome))",
                "proposal=\(String(describing: store.hamptonSnapshot.proposal?.kind))"
            ].joined(separator: " | ").prefix(2_400))
        }

        func clean() {
            store.cancelWork()
            store.disconnectAssistant()
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

@MainActor
private final class ReadingCorrectionRoleClient: LocalRoleClient {
    static let answer = "The event is confirmed for Thursday."
    private(set) var requests: [LocalRoleRequest] = []
    func connect() async throws {}
    func disconnect() {}
    func shutdown() async {}
    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
        requests.append(request)
        func ids(_ key: String) -> [String] { request.input[key]?.array?.compactMap { $0["id"]?.string } ?? [] }
        var payload: [String: JSONValue] = ["requestID": .string(request.id)]
        switch request.role {
        case .memorySelection:
            payload["schema"] = .string("archi-session-selection/v1")
            payload["candidateIDs"] = .array(ids("candidates").prefix(1).map(JSONValue.string))
        case .memoryReminder:
            payload["schema"] = .string("archi-session-reminder/v1")
            payload["decision"] = .string("NONE")
            payload["memoryIDs"] = .array([])
        case .reasoning:
            payload["schema"] = .string("archi-reason-proposal/v1")
            payload["kind"] = .string("ANSWER")
            payload["answer"] = .string(Self.answer)
            payload["uncertainty"] = .string("")
            payload["sourceIDs"] = .array(ids("sources").prefix(3).map(JSONValue.string))
            payload["memoryIDs"] = .array(ids("memories").prefix(3).map(JSONValue.string))
        }
        return LocalRoleResult(requestID: request.id, role: request.role,
            text: String(decoding: try JSONEncoder().encode(payload), as: UTF8.self),
            model: QwenModelMetadata(name: "reading-correction-fixture", family: "qwen", parameterSize: "fixture",
                quantization: "fixture", digest: String(repeating: "a", count: 64)), elapsedMilliseconds: 0)
    }
}
