import Foundation
import XCTest
@testable import ARCHiDesktop

@MainActor
final class DocumentWorkFeedbackJournalTests: XCTestCase {
    func testLegacyJournalRemainsUnchangedAndCannotAcquireInventedLearningEvidence() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("document-work.json")
        var legacy = completedRecord()
        legacy.learning = nil
        let bytes = try writeArchive([legacy], to: url)
        let journal = DocumentWorkJournal(url: url)
        XCTAssertNil(journal.loadError)
        XCTAssertNil(journal.records.first?.learning)
        XCTAssertNil(journal.records.first?.feedback)
        XCTAssertNil(journal.records.first?.feedbackUsageSyncedID)
        XCTAssertEqual(try Data(contentsOf: url), bytes, "Opening the v1 archive does not migrate or rewrite it.")

        var invented = legacy
        invented.learning = context()
        invented.feedback = feedback(.helpful)
        invented.updatedAt = invented.feedback!.recordedAt
        XCTAssertThrowsError(try journal.save(invented), "An already applied legacy record cannot acquire new request provenance.")
        XCTAssertEqual(try Data(contentsOf: url), bytes)

        let modern = completedRecord()
        let modernBytes = try writeArchive([modern], to: url)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: modernBytes) as? [String: Any])
        var rows = try XCTUnwrap(object["records"] as? [[String: Any]])
        var learning = try XCTUnwrap(rows[0]["learning"] as? [String: Any])
        learning["documentText"] = "Unrecognized raw text must not be admitted."
        rows[0]["learning"] = learning
        object["records"] = rows
        let malformed = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try malformed.write(to: url)
        let rejected = DocumentWorkJournal(url: url)
        XCTAssertNotNil(rejected.loadError)
        XCTAssertTrue(rejected.records.isEmpty)
        XCTAssertThrowsError(try rejected.save(completedRecord()))
        XCTAssertEqual(try Data(contentsOf: url), malformed, "Unknown nested learning fields are preserved on disk but never admitted.")
    }

    func testFeedbackIdentityRetriesAndChangedVerdictsRemainBoundThroughUndoAndRestart() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("document-work.json")
        var record = completedRecord()
        record.state = .applying
        let journal = DocumentWorkJournal(url: url)
        try journal.save(record)
        record.state = .applied
        try journal.save(record)
        record.feedback = feedback(.helpful)
        record.updatedAt = record.feedback!.recordedAt
        try journal.save(record)
        let first = try Data(contentsOf: url)
        try journal.save(record)
        XCTAssertEqual(try Data(contentsOf: url), first, "An exact retry keeps the same event and archive bytes.")

        var conflicting = record
        conflicting.feedback = feedback(.helpful)
        XCTAssertThrowsError(try journal.save(conflicting), "A retry cannot invent another ID for revision one.")
        conflicting.feedback = feedback(.needsCorrection)
        XCTAssertThrowsError(try journal.save(conflicting), "Changing the verdict without advancing the revision is rejected.")
        XCTAssertEqual(try Data(contentsOf: url), first)

        record.feedbackUsageSyncedID = record.feedback!.id
        try journal.save(record)
        XCTAssertFalse(journal.records[0].hasPendingFeedbackUsageSync)
        var unacknowledged = record
        unacknowledged.feedbackUsageSyncedID = nil
        XCTAssertThrowsError(try journal.save(unacknowledged), "Successful Usage acknowledgment cannot regress on an unchanged event.")

        record.feedback = feedback(.needsCorrection, revision: 2, at: 1_002)
        record.feedbackUsageSyncedID = nil
        record.updatedAt = record.feedback!.recordedAt
        try journal.save(record)
        XCTAssertTrue(journal.records[0].hasPendingFeedbackUsageSync)
        XCTAssertThrowsError(try journal.save(unacknowledged), "An older positive verdict cannot overwrite the correction.")

        var changedEvidence = record
        changedEvidence.learning = DocumentWorkLearningContext(requestBinding: EvolutionRequestBinding(
            inputDigest: String(repeating: "e", count: 64), contextDigest: String(repeating: "f", count: 64)))
        XCTAssertThrowsError(try journal.save(changedEvidence), "The completed edit's request evidence remains immutable.")

        record.state = .undoing
        try journal.save(record)
        let pendingUndo = try Data(contentsOf: url)
        let reopened = DocumentWorkJournal(url: url)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.records.first?.state, .failed)
        XCTAssertEqual(reopened.records.first?.feedback, record.feedback)
        XCTAssertEqual(reopened.records.first?.learning, record.learning)
        XCTAssertEqual(reopened.records.first?.hasPendingFeedbackUsageSync, true)
        XCTAssertEqual(try Data(contentsOf: url), pendingUndo, "Interrupted Undo preserves the judgment without rewriting or replaying the action.")
        var interrupted = try XCTUnwrap(reopened.records.first)
        interrupted.feedbackUsageSyncedID = interrupted.feedback!.id
        try reopened.save(interrupted)
        XCTAssertEqual(reopened.records.first?.feedback?.verdict, .needsCorrection)
    }

    func testReviewedHistoryCannotBeEvictedBeforeOrAfterUsageAcknowledgment() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("document-work.json")
        let records = (0..<DocumentWorkJournal.maximumRecords).map { index in
            var record = completedRecord()
            record.feedback = feedback(index.isMultiple(of: 2) ? .withdrawn : .needsCorrection)
            record.updatedAt = record.feedback!.recordedAt
            if index > 0 { record.feedbackUsageSyncedID = record.feedback!.id }
            return record
        }
        let full = try writeArchive(records, to: url)
        let journal = DocumentWorkJournal(url: url)
        XCTAssertNil(journal.loadError)
        XCTAssertEqual(journal.records.filter(\.hasPendingFeedbackUsageSync).count, 1)
        var newWork = completedRecord()
        newWork.state = .proposing
        newWork.actualAfterDigest = nil
        newWork.afterRevision = nil
        XCTAssertThrowsError(try journal.save(newWork))
        XCTAssertEqual(try Data(contentsOf: url), full)

        var pending = try XCTUnwrap(journal.records.first(where: \.hasPendingFeedbackUsageSync))
        pending.feedbackUsageSyncedID = pending.feedback!.id
        try journal.save(pending)
        let acknowledged = try Data(contentsOf: url)
        XCTAssertThrowsError(try journal.save(newWork), "Acknowledged negative feedback still prevents old Evolution evidence from resurfacing.")
        XCTAssertEqual(try Data(contentsOf: url), acknowledged)
        XCTAssertEqual(journal.records.count, DocumentWorkJournal.maximumRecords)
        let reopened = DocumentWorkJournal(url: url)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.records.filter { $0.feedback != nil }.count, DocumentWorkJournal.maximumRecords)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("archi-document-feedback-\(UUID().uuidString)")
    }

    private func context() -> DocumentWorkLearningContext {
        DocumentWorkLearningContext(requestBinding: EvolutionRequestBinding(
            inputDigest: String(repeating: "c", count: 64), contextDigest: String(repeating: "d", count: 64)))
    }

    private func completedRecord() -> DocumentWorkRecord {
        let requestID = UUID().uuidString
        let date = Date(timeIntervalSince1970: 1_000)
        return DocumentWorkRecord(id: requestID + "-Qwen", requestID: requestID, provider: "Qwen",
            targetID: UUID().uuidString, sourceDigest: String(repeating: "a", count: 64), sourceRevision: 1,
            selectionStart: 0, selectionLength: 12, createdAt: date, updatedAt: date,
            state: .applied, proposedDigest: String(repeating: "b", count: 64),
            expectedAfterDigest: String(repeating: "b", count: 64),
            actualAfterDigest: String(repeating: "b", count: 64), afterRevision: 2,
            checks: [DocumentWorkAuditCheck(id: "source", title: "Exact source binding", passed: true)],
            learning: context())
    }

    private func feedback(_ verdict: DocumentWorkFeedback.Verdict, revision: UInt64 = 1,
                          at timestamp: TimeInterval = 1_001) -> DocumentWorkFeedback {
        DocumentWorkFeedback(revision: revision, verdict: verdict, recordedAt: Date(timeIntervalSince1970: timestamp))
    }

    private struct Archive: Encodable {
        let schema = "archi-document-work/v1"
        let records: [DocumentWorkRecord]
    }

    @discardableResult
    private func writeArchive(_ records: [DocumentWorkRecord], to url: URL) throws -> Data {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(Archive(records: records))
        try bytes.write(to: url)
        return bytes
    }
}
