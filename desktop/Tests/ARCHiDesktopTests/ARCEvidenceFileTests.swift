import XCTest
import Darwin
@testable import ARCHiDesktop

final class ARCEvidenceFileTests: XCTestCase {
    @MainActor func testFileImportRescoresAndReopensWithoutChangingInput() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("evidence.json")
        try ARCCapabilitiesEvaluator.syntheticBundle.write(to: input)
        let archive = directory.appendingPathComponent("archive.json")
        let store = ARCCapabilitiesStore(storageURL: archive)
        let event = try store.evaluate(fileURL: input)
        XCTAssertNil(event.error)
        XCTAssertEqual(event.passed, false)
        XCTAssertEqual(store.records.first?.summary.counts.exact, 1)
        XCTAssertEqual(store.records.first?.summary.counts.incorrect, 1)
        XCTAssertEqual(try Data(contentsOf: input), ARCCapabilitiesEvaluator.syntheticBundle)
        let reopened = ARCCapabilitiesStore(storageURL: archive)
        XCTAssertNil(reopened.lastError)
        XCTAssertEqual(reopened.records.first?.id, event.evidenceID)
    }

    @MainActor func testMalformedFileKeepsPreviouslySavedEvidence() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = directory.appendingPathComponent("archive.json")
        let store = ARCCapabilitiesStore(storageURL: archive)
        XCTAssertNil(store.runSyntheticDemonstration().error)
        let original = try Data(contentsOf: archive)
        let input = directory.appendingPathComponent("broken.json")
        try Data("{invalid".utf8).write(to: input)
        let event = try store.evaluate(fileURL: input)
        XCTAssertNotNil(event.error)
        XCTAssertNil(event.passed)
        XCTAssertNil(event.evidenceID)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(try Data(contentsOf: archive), original)
    }

    @MainActor func testOversizedDirectoryAndPipeInputsAreRejectedWithoutSaving() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = directory.appendingPathComponent("archive.json")
        let store = ARCCapabilitiesStore(storageURL: archive)
        let oversized = directory.appendingPathComponent("large.json")
        try Data(repeating: 32, count: ARCCapabilitiesEvaluator.maximumBytes + 1).write(to: oversized)
        let pipe = directory.appendingPathComponent("pipe.json")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        for url in [oversized, directory, pipe, directory.appendingPathComponent("absent.json")] {
            XCTAssertThrowsError(try store.evaluate(fileURL: url))
        }
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-evidence-file-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
