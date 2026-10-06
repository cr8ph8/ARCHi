import Foundation
import XCTest
@testable import ARCHiDesktop

@MainActor
final class DocumentProcedureTests: XCTestCase {
    func testOnlyAuthoritativeHelpfulAppliedEvidenceCanSaveAndReloadDoesNotWrite() throws {
        let directory = fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("procedures.json")
        let library = DocumentProcedureLibrary(url: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        var record = appliedRecord()
        XCTAssertThrowsError(try library.keep(from: record, title: "Clarity", instruction: "Use direct verbs.", records: []))
        record.state = .ready
        XCTAssertThrowsError(try library.keep(from: record, title: "Clarity", instruction: "Use direct verbs.", records: [record]))
        record.state = .undone
        XCTAssertThrowsError(try library.keep(from: record, title: "Clarity", instruction: "Use direct verbs.", records: [record]))
        record.state = .applied
        let saved = try library.keep(from: record, title: "Clarity", instruction: "Use direct verbs.", records: [record])
        let bytes = try Data(contentsOf: url)
        let retry = try library.keep(from: record, title: "Clarity", instruction: "Use direct verbs.", records: [record])
        XCTAssertEqual(retry, saved)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        let reopened = DocumentProcedureLibrary(url: url)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.procedures, [saved])
        XCTAssertNil(reopened.availability(of: saved, records: [record]))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertTrue(saved.matches(requirements: .init(mustBeShorter: false, preserveNumbersAndLinks: true)))
        XCTAssertFalse(saved.matches(requirements: .init(mustBeShorter: true, preserveNumbersAndLinks: true)))
    }

    func testWithdrawalPreservesBindingAndDisablesDerivedProcedure() throws {
        let directory = fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = DocumentProcedureLibrary(url: directory.appendingPathComponent("procedures.json"))
        let origin = appliedRecord()
        let first = try library.keep(from: origin, title: "Clarity", instruction: "Use direct verbs.", records: [origin])
        var later = appliedRecord()
        later.procedureUse = first.binding
        let child = try library.keep(from: later, title: "Short sentences", instruction: "Keep one main idea per sentence.", records: [origin, later])
        XCTAssertNil(library.availability(of: child, records: [origin, later]))
        try library.withdraw(binding: first.binding)
        let withdrawn = try XCTUnwrap(library.procedure(matching: first.binding))
        XCTAssertTrue(withdrawn.withdrawn)
        XCTAssertEqual(withdrawn.binding, first.binding)
        XCTAssertNotNil(library.availability(of: child, records: [origin, later]))
        XCTAssertNotNil(library.availability(of: withdrawn, records: [origin, later]))
        XCTAssertEqual(library.procedures.count, 2, "Withdrawal retains exact provenance.")
    }

    func testCorrectionsStayRejectedAndOriginalReviewMustRemainExact() throws {
        let directory = fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = DocumentProcedureLibrary(url: directory.appendingPathComponent("procedures.json"))
        var origin = appliedRecord()
        let value = try library.keep(from: origin, title: "Clarity", instruction: "Use direct verbs.", records: [origin])
        var later = appliedRecord()
        later.procedureUse = value.binding
        later.procedureUseRejected = true
        XCTAssertNotNil(library.availability(of: value, records: [origin, later]),
                        "A later helpful review cannot erase the permanent rejection latch.")
        later.procedureUseRejected = nil
        later.feedback = .init(revision: 2, verdict: .needsCorrection)
        XCTAssertNotNil(library.availability(of: value, records: [origin, later]))
        origin.feedback = .init(revision: 2, verdict: .helpful)
        XCTAssertNotNil(library.availability(of: value, records: [origin]), "A different helpful event is not the original evidence.")
    }

    func testStaleOwnersCannotReuseOrOverwriteAndUnreadableFilesArePreserved() throws {
        let directory = fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("procedures.json")
        let first = DocumentProcedureLibrary(url: url)
        let record = appliedRecord()
        let value = try first.keep(from: record, title: "Clarity", instruction: "Use direct verbs.", records: [record])
        let stale = DocumentProcedureLibrary(url: url)
        try first.withdraw(binding: value.binding)
        let retained = try Data(contentsOf: url)
        XCTAssertNotNil(stale.availability(of: value, records: [record]))
        XCTAssertThrowsError(try stale.keep(from: record, title: "New", instruction: "Review each sentence.", records: [record]))
        XCTAssertEqual(try Data(contentsOf: url), retained)
        let corrupt = Data("{ preserved malformed procedures".utf8)
        try corrupt.write(to: url)
        let unreadable = DocumentProcedureLibrary(url: url)
        XCTAssertNotNil(unreadable.loadError)
        XCTAssertThrowsError(try unreadable.keep(from: record, title: "New", instruction: "Review each sentence.", records: [record]))
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    private func fixtureDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("archi-procedure-\(UUID().uuidString)")
    }

    private func appliedRecord() -> DocumentWorkRecord {
        let request = UUID().uuidString
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        return DocumentWorkRecord(id: request + "-Qwen", requestID: request, provider: "Qwen", targetID: UUID().uuidString,
            sourceDigest: String(repeating: "a", count: 64), sourceRevision: 1, selectionStart: 0, selectionLength: 12,
            preserveNumbersAndLinks: true, createdAt: date, updatedAt: date, state: .applied,
            proposedDigest: String(repeating: "b", count: 64), expectedAfterDigest: String(repeating: "c", count: 64),
            actualAfterDigest: String(repeating: "c", count: 64), afterRevision: 2,
            checks: [.init(id: "source", title: "Exact source", passed: true)],
            learning: .init(requestBinding: .init(inputDigest: String(repeating: "d", count: 64),
                                                   contextDigest: String(repeating: "e", count: 64))),
            feedback: .init(revision: 1, verdict: .helpful, recordedAt: date))
    }
}
