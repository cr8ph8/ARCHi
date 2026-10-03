import XCTest
@testable import ARCHiDesktop

final class TokenStewardExportTests: XCTestCase {
    @MainActor func testExportRejectsLiveJournalLockAndAliasesWithoutChangingThem() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("steward-export-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = directory.appendingPathComponent("usage.json")
        let store = TokenStewardStore(url: journal)
        try store.preflight(requestID: UUID().uuidString, route: .local)
        let original = try Data(contentsOf: journal)
        let lock = journal.appendingPathExtension("lock")
        let lockBytes = try Data(contentsOf: lock)
        let symbolic = directory.appendingPathComponent("symbolic.json")
        let hard = directory.appendingPathComponent("hard.json")
        try FileManager.default.createSymbolicLink(at: symbolic, withDestinationURL: journal)
        try FileManager.default.linkItem(at: journal, to: hard)
        for destination in [journal, lock, symbolic, hard] {
            XCTAssertThrowsError(try store.export(to: destination))
        }
        XCTAssertEqual(try Data(contentsOf: journal), original)
        XCTAssertEqual(try Data(contentsOf: lock), lockBytes)
        XCTAssertEqual(try Data(contentsOf: hard), original)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: symbolic.path), journal.path)
    }

    @MainActor func testExportReadsLatestSnapshotAndWritesPrivateReadableCopy() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("steward-export-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = directory.appendingPathComponent("usage.json")
        let first = TokenStewardStore(url: journal), second = TokenStewardStore(url: journal)
        try first.preflight(requestID: UUID().uuidString, route: .local)
        try second.preflight(requestID: UUID().uuidString, route: .compare)
        let original = try Data(contentsOf: journal)
        let destination = directory.appendingPathComponent("export.json")
        try first.export(to: destination)
        let reopened = TokenStewardStore(url: destination)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.tasks.count, 2)
        XCTAssertEqual(reopened.tasks, first.tasks)
        XCTAssertEqual(reopened.summary, first.summary)
        XCTAssertEqual(try Data(contentsOf: journal), original)
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    @MainActor func testFailedExportPreservesDestinationAndCorruptSource() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("steward-export-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = directory.appendingPathComponent("usage.json")
        let corrupt = Data("preserve corrupt source".utf8)
        try corrupt.write(to: journal)
        let destination = directory.appendingPathComponent("export.json")
        let original = Data("previous export".utf8)
        try original.write(to: destination)
        let store = TokenStewardStore(url: journal)
        XCTAssertThrowsError(try store.export(to: destination))
        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertEqual(try Data(contentsOf: journal), corrupt)
        XCTAssertFalse(store.summary.accountingAvailable)
    }
}
