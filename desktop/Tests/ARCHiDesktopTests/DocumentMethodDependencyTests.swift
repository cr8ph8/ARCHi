import Foundation
import XCTest
@testable import ARCHiDesktop

/// Native owners with an in-process revision client; no models or user files.
@MainActor
final class DocumentMethodDependencyTests: XCTestCase {
    func testSuppliedUncitedLessonIsRetainedAsDependencyWithoutLessonCredit() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let lesson = try fixture.keepLesson()
        let record = try await fixture.reviewedEdit()
        let learning = try XCTUnwrap(record.learning)
        let reference = try XCTUnwrap(EvolutionLessonUse.make(snapshot: lesson))

        XCTAssertEqual(learning.suppliedLessons, [reference])
        XCTAssertEqual(learning.dependencyLessons, [reference])
        XCTAssertTrue(learning.hasCompleteLessonProvenance)
        XCTAssertTrue(learning.usedLessons.isEmpty)
        XCTAssertTrue(fixture.store.documentReviewLessons(record).isEmpty)
        XCTAssertFalse(fixture.store.addDocumentToLearningReview(id: record.id, lesson: lesson),
            "Receiving a lesson does not establish its useful contribution.")
        XCTAssertTrue(fixture.store.addDocumentToLearningReview(id: record.id))
        XCTAssertNil(fixture.store.evolution.usefulReceipts.first?.lessonUse)
        let graph = fixture.store.companionGraphSnapshot(at: fixture.clock.now)
        let dependency = try XCTUnwrap(graph.nodes.first { $0.title == "Lesson dependency" })
        XCTAssertTrue(graph.edges.contains { $0.target == dependency.id && $0.label == "supplied lesson" })
        XCTAssertFalse(graph.edges.contains { $0.target == dependency.id && $0.label == "model cited" })
        XCTAssertTrue(graph.edges.contains { $0.source == dependency.id && $0.label == "exact retained version" })
        _ = try fixture.keepProcedure(from: record)
    }

    func testExternalWithdrawalOfUncitedLessonBlocksMethodAndFurtherKeeping() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let lesson = try fixture.keepLesson()
        let record = try await fixture.reviewedEdit()
        let procedure = try fixture.keepProcedure(from: record)
        XCTAssertNil(fixture.store.documentProcedureUnavailable(procedure.binding))

        let other = fixture.reopen()
        defer { other.disconnectAssistant() }
        XCTAssertTrue(other.withdrawLesson(id: lesson.id, expectedRevision: other.lessonRevision))

        XCTAssertFalse(fixture.store.keptLessons.isEmpty, "This owner still has its earlier cached snapshot.")
        XCTAssertNotNil(fixture.store.documentProcedureUnavailable(procedure.binding))
        XCTAssertFalse(fixture.store.keepDocumentProcedure(recordID: record.id,
            title: "Stale method", instruction: "Use plain words."))
        let graph = DocumentWorkGraph.append(to: .empty, records: [record], accountingTaskIDs: [])
        let dependency = try XCTUnwrap(graph.nodes.first { $0.title == "Lesson dependency" })
        XCTAssertEqual(dependency.status, "Version no longer kept")
        XCTAssertNil(dependency.target)
        XCTAssertFalse(dependency.details.contains { $0.value.contains(lesson.text) })
    }

    func testRevisingUncitedLessonBlocksTheOldMethodVersion() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let lesson = try fixture.keepLesson()
        let record = try await fixture.reviewedEdit()
        let procedure = try fixture.keepProcedure(from: record)

        fixture.store.beginLessonCorrection(revisingID: lesson.id)
        var draft = try XCTUnwrap(fixture.store.lessonDraft)
        draft.text = "Preserve qualifications while making sentences shorter."
        XCTAssertTrue(fixture.store.keepLesson(draft))

        XCTAssertNotNil(fixture.store.documentProcedureUnavailable(procedure.binding))
        XCTAssertFalse(fixture.store.keepDocumentProcedure(recordID: record.id,
            title: "Old input", instruction: "Use plain words."))
        XCTAssertEqual(fixture.store.documentProcedures.procedures.first?.binding, procedure.binding,
            "Invalidation preserves the historical method identity.")
    }

    func testExpiryOfUncitedLessonBlocksMethodReuse() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        _ = try fixture.keepLesson(expiresAt: fixture.clock.now.addingTimeInterval(60))
        let record = try await fixture.reviewedEdit()
        let procedure = try fixture.keepProcedure(from: record)
        XCTAssertNil(fixture.store.documentProcedureUnavailable(procedure.binding))

        fixture.clock.now = fixture.clock.now.addingTimeInterval(61)

        XCTAssertNotNil(fixture.store.documentProcedureUnavailable(procedure.binding))
        XCTAssertFalse(fixture.store.keepDocumentProcedure(recordID: record.id,
            title: "Expired input", instruction: "Use plain words."))
    }

    func testStrictProvenanceDecodingPreservesLegacyButCannotAdmitItAsFreshMethodEvidence() async throws {
        let lesson = LessonSnapshot(id: UUID().uuidString, revision: 1, topic: "selected passage", text: "Use plain words.")
        let reference = try XCTUnwrap(EvolutionLessonUse.make(snapshot: lesson))
        let binding = EvolutionRequestBinding(inputDigest: String(repeating: "a", count: 64),
            contextDigest: String(repeating: "b", count: 64))
        let complete = DocumentWorkLearningContext(requestBinding: binding,
            usedLessons: [reference], suppliedLessons: [reference])
        let encoded = try JSONEncoder().encode(complete)
        XCTAssertEqual(try JSONDecoder().decode(DocumentWorkLearningContext.self, from: encoded), complete)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        raw.removeValue(forKey: "suppliedLessons")
        let legacy = try decode(raw)
        XCTAssertNil(legacy.suppliedLessons)
        XCTAssertFalse(legacy.hasCompleteLessonProvenance)
        XCTAssertEqual(legacy.dependencyLessons, [reference])
        let legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        XCTAssertNil(legacyObject["suppliedLessons"], "Unknown provenance stays absent when re-encoded.")

        raw["suppliedLessons"] = []
        XCTAssertThrowsError(try decode(raw), "A cited version must have been supplied.")
        raw["suppliedLessons"] = NSNull()
        XCTAssertThrowsError(try decode(raw))
        let referenceObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reference))
        raw["suppliedLessons"] = [referenceObject, referenceObject]
        XCTAssertThrowsError(try decode(raw))
        raw["suppliedLessons"] = [referenceObject]
        raw["sourceText"] = "Unsupported payload"
        XCTAssertThrowsError(try decode(raw))
        raw.removeValue(forKey: "sourceText")
        raw["usedLessons"] = []
        raw["suppliedLessons"] = try (0..<17).map { index in
            let extra = LessonSnapshot(id: UUID().uuidString, revision: 1, topic: "lesson \(index)", text: "Use plain words.")
            return try JSONSerialization.jsonObject(with: JSONEncoder().encode(XCTUnwrap(EvolutionLessonUse.make(snapshot: extra))))
        }
        XCTAssertThrowsError(try decode(raw), "Dependency metadata remains bounded to 16 distinct lessons.")
        raw["suppliedLessons"] = []
        let empty = try decode(raw)
        XCTAssertTrue(empty.hasCompleteLessonProvenance)
        XCTAssertTrue(empty.dependencyLessons.isEmpty)

        // An old journal remains inspectable without inventing supplied context.
        let fixture = Fixture()
        defer { fixture.clean() }
        let record = try await fixture.reviewedEdit()
        var archive = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.journalURL)) as? [String: Any])
        var records = try XCTUnwrap(archive["records"] as? [[String: Any]])
        let index = try XCTUnwrap(records.firstIndex { $0["id"] as? String == record.id })
        var context = try XCTUnwrap(records[index]["learning"] as? [String: Any])
        context.removeValue(forKey: "suppliedLessons")
        records[index]["learning"] = context
        archive["records"] = records
        let legacyBytes = try JSONSerialization.data(withJSONObject: archive, options: [.sortedKeys])
        try legacyBytes.write(to: fixture.journalURL, options: .atomic)
        let reopened = fixture.reopen()
        defer { reopened.disconnectAssistant() }
        XCTAssertNil(reopened.documentWork.loadError)
        XCTAssertNil(reopened.documentWork.records.first { $0.id == record.id }?.learning?.suppliedLessons)
        XCTAssertFalse(reopened.keepDocumentProcedure(recordID: record.id,
            title: "Legacy context", instruction: "Use plain words."))
        XCTAssertEqual(try Data(contentsOf: fixture.journalURL), legacyBytes)
    }

    func testExternalDocumentCorrectionCannotEnterLearningThroughCachedHelpfulRecord() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let record = try await fixture.reviewedEdit()
        let other = DocumentWorkJournal(url: fixture.journalURL)
        var corrected = try XCTUnwrap(other.records.first { $0.id == record.id })
        corrected.feedback = DocumentWorkFeedback(revision: (corrected.feedback?.revision ?? 0) + 1,
            verdict: .needsCorrection, recordedAt: fixture.clock.now.addingTimeInterval(1))
        corrected.feedbackUsageSyncedID = nil
        corrected.updatedAt = fixture.clock.now.addingTimeInterval(1)
        try other.save(corrected)
        let bytes = try Data(contentsOf: fixture.journalURL)

        XCTAssertEqual(fixture.store.documentWork.records.first { $0.id == record.id }?.feedback?.verdict, .helpful)
        XCTAssertFalse(fixture.store.documentWork.isCurrentOnDisk)
        XCTAssertFalse(fixture.store.addDocumentToLearningReview(id: record.id))
        XCTAssertTrue(fixture.store.evolution.usefulReceipts.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture.journalURL), bytes)
    }

    private func decode(_ value: [String: Any]) throws -> DocumentWorkLearningContext {
        try JSONDecoder().decode(DocumentWorkLearningContext.self,
            from: JSONSerialization.data(withJSONObject: value))
    }

    @MainActor
    private final class Clock { var now = Date(timeIntervalSince1970: 1_800_000_000) }

    @MainActor
    private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-method-dependency-\(UUID())")
        let client = MethodDependencyClient()
        let clock = Clock()
        var preferenceURL: URL { directory.appendingPathComponent("preferences.json") }
        var journalURL: URL { directory.appendingPathComponent("preferences.document-work.json") }
        lazy var store = CompanionStore(preferenceURL: preferenceURL, assistant: client,
            assistantFactory: { [client] _, _ in client }, wallClock: { [clock] in clock.now },
            allowsPlay: false, tokenSteward: TokenStewardStore())

        func keepLesson(expiresAt: Date? = nil) throws -> LessonSnapshot {
            store.beginLessonCorrection()
            var draft = try XCTUnwrap(store.lessonDraft)
            draft.topic = "selected passage"; draft.text = "Use plain words without changing meaning."
            draft.taskScope = .passageRevision; draft.expiresAt = expiresAt
            XCTAssertTrue(store.keepLesson(draft), store.lessonMessage)
            return LessonSnapshot(lesson: try XCTUnwrap(store.keptLessons.first))
        }

        func reviewedEdit() async throws -> DocumentWorkRecord {
            store.evolution.observeJourneyOrigin(String(repeating: "a", count: 64))
            store.share(text: "Original copy.", name: "fixture.txt")
            store.selectText(range: NSRange(location: 0, length: store.sharedText.utf16.count), sourceRevision: store.sourceRevision)
            store.preparePassageRevision()
            store.setAssistantRoute(.automatic)
            store.submit()
            try await wait { self.client.request != nil }
            let proposal = try client.complete()
            try await wait { !self.store.isWorking }
            XCTAssertEqual(store.compareResults[.qwen]?.state, .complete, store.status)
            XCTAssertTrue(store.canApplyDocumentRevision(provider: .qwen, proposal: proposal), store.status)
            store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
            let applied = try XCTUnwrap(store.documentWork.records.first { $0.targetID == proposal.target.id })
            XCTAssertEqual(applied.state, .applied, store.documentWorkMessage ?? store.status)
            XCTAssertTrue(store.reviewDocument(id: applied.id, verdict: .helpful), store.documentWorkMessage ?? store.status)
            return try XCTUnwrap(store.documentWork.records.first { $0.id == applied.id })
        }

        func keepProcedure(from record: DocumentWorkRecord) throws -> DocumentProcedure {
            XCTAssertTrue(store.keepDocumentProcedure(recordID: record.id,
                title: "Plain revision", instruction: "Use plain words."), store.documentWorkMessage ?? store.status)
            return try XCTUnwrap(store.documentProcedures.procedures.first)
        }

        func reopen() -> CompanionStore {
            CompanionStore(preferenceURL: preferenceURL, assistant: MethodDependencyClient(),
                wallClock: { [clock] in clock.now }, allowsPlay: false, tokenSteward: TokenStewardStore())
        }

        func wait(_ condition: @MainActor () -> Bool) async throws {
            for _ in 0..<400 {
                if condition() { return }
                try await Task.sleep(for: .milliseconds(5))
            }
            XCTFail("Timed out: \(store.status) | \(store.documentWorkMessage ?? "none") | \(store.stewardMessage ?? "none")")
            throw AssistantFailure.timedOut
        }

        func clean() {
            store.cancelWork(); store.disconnectAssistant(); client.resolve()
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

@MainActor
private final class MethodDependencyClient: AssistantClient {
    var request: AssistantRequest?
    private var handler: (@MainActor (AssistantEvent) -> Void)?
    private var continuation: CheckedContinuation<Void, Error>?
    func connect() async throws {}
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        self.request = request; handler = onEvent
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func complete() throws -> PassageRevisionProposal {
        let target = try XCTUnwrap(request?.revisionTarget)
        let proposal = PassageRevisionProposal(target: target, decision: .propose, replacement: "Clear copy.",
            explanation: "Review the proposed wording.", sourceIDs: ["selected-passage"], memoryIDs: [])
        handler?(.revision(proposal)); resolve()
        return proposal
    }
    func resolve() { let pending = continuation; continuation = nil; pending?.resume() }
}
