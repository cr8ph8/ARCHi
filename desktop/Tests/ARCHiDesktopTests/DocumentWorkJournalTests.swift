import Foundation
import XCTest
@testable import ARCHiDesktop

@MainActor
final class DocumentWorkJournalTests: XCTestCase {
    func testReloadProjectsInterruptedWorkWithoutWritingOrClaimingSuccess() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("document-work.json")
        let journal = DocumentWorkJournal(url: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path), "Opening an absent journal must not create profile files.")
        for (index, state) in [DocumentWorkRecord.State.proposing, .ready, .applying, .undoing].enumerated() {
            var value = record(index)
            value.state = state
            try journal.save(value)
        }
        let before = try Data(contentsOf: url)
        let reopened = DocumentWorkJournal(url: url)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(try Data(contentsOf: url), before, "Recovery projection must not rewrite the source file.")
        XCTAssertEqual(reopened.records.filter { $0.state == .cancelled }.count, 2)
        let uncertain = reopened.records.filter { $0.state == .failed }
        XCTAssertEqual(uncertain.count, 2)
        XCTAssertTrue(uncertain.allSatisfy { $0.detail.contains("unverified") && $0.detail.contains("no action was replayed") })
        try reopened.save(record(10))
        XCTAssertEqual(reopened.records.count, 5, "Saving after recovery still compares against the exact original disk baseline.")
    }

    func testStaleWriterAndUnreadableJournalPreserveExistingBytes() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("document-work.json")
        let first = DocumentWorkJournal(url: url)
        let stale = DocumentWorkJournal(url: url)
        try first.save(record(1))
        let retained = try Data(contentsOf: url)
        XCTAssertThrowsError(try stale.save(record(2)))
        XCTAssertEqual(try Data(contentsOf: url), retained)
        XCTAssertTrue(stale.records.isEmpty)

        let corrupt = Data("{ preserved unreadable journal".utf8)
        try corrupt.write(to: url)
        let failed = DocumentWorkJournal(url: url)
        XCTAssertNotNil(failed.loadError)
        XCTAssertThrowsError(try failed.save(record(3)))
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
        XCTAssertThrowsError(try first.save(record(4)), "An external edit is detected even when the original owner remains alive.")
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    func testFullActiveJournalRejectsNewWorkAndApplyRequiresPendingReceipt() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("document-work.json")
        let journal = DocumentWorkJournal(url: url)
        for index in 0..<DocumentWorkJournal.maximumRecords { try journal.save(record(index)) }
        let full = try Data(contentsOf: url)
        XCTAssertThrowsError(try journal.save(record(100)))
        XCTAssertEqual(try Data(contentsOf: url), full)
        XCTAssertEqual(journal.records.count, 64)

        var transition = record(0)
        transition.state = .applied
        transition.expectedAfterDigest = String(repeating: "b", count: 64)
        transition.actualAfterDigest = transition.expectedAfterDigest
        transition.afterRevision = 2
        XCTAssertThrowsError(try journal.save(transition), "Success cannot skip the persisted applying step.")
        transition.state = .applying
        try journal.save(transition)
        transition.state = .applied
        try journal.save(transition)
        try journal.save(record(100))
        XCTAssertEqual(journal.records.count, 64)
        XCTAssertNil(journal.records.first { $0.id == record(0).id }, "The oldest terminal record can make room; active work is retained.")
        XCTAssertNotNil(journal.records.first { $0.id == record(63).id })
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("archi-document-journal-\(UUID().uuidString)")
    }

    private func record(_ index: Int) -> DocumentWorkRecord {
        let time = Date(timeIntervalSince1970: 1_000 + Double(index))
        return DocumentWorkRecord(id: "request-\(index)-Qwen", requestID: "request-\(index)", provider: "Qwen",
            targetID: "target-\(index)", sourceDigest: String(repeating: "a", count: 64), sourceRevision: 1,
            selectionStart: 0, selectionLength: 12, createdAt: time, updatedAt: time,
            checks: [DocumentWorkAuditCheck(id: "source", title: "Exact source binding", passed: true)])
    }
}
