import Foundation
import XCTest
@testable import ARCHiDesktop

final class EvolutionSaveConflictTests: XCTestCase {
    private let origin = String(repeating: "a", count: 64)

    @MainActor
    func testStaleStoreCannotOverwriteNewerReturnedBody() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = try savedFirstLight(at: url)
        let stale = EvolutionStore(saveURL: url)
        XCTAssertTrue(stale.load())
        let original = try XCTUnwrap(stale.kinGrowthRecord)
        first.returnKinToSeed(originDigest: origin)
        XCTAssertTrue(first.save(), first.status)
        let newer = try Data(contentsOf: url)
        stale.confirmRole(.guardian)
        let revision = stale.revision
        XCTAssertFalse(stale.save())
        XCTAssertTrue(stale.status.contains("changed outside this session"))
        XCTAssertEqual(stale.kinGrowthRecord, original)
        XCTAssertEqual(stale.revision, revision)
        XCTAssertTrue(stale.hasUnsavedChanges)
        XCTAssertEqual(try Data(contentsOf: url), newer)
        XCTAssertTrue(stale.load())
        XCTAssertEqual(stale.kinGrowthRecord?.active, false)
        XCTAssertTrue(stale.save(), stale.status)
        XCTAssertEqual(try Data(contentsOf: url), newer)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)),
                       [url.lastPathComponent, DesktopProfileLock.filename])
    }

    @MainActor
    func testFirstSaveExpectsAbsenceAndDetectsExternalCreation() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let fresh = EvolutionStore(saveURL: url)
        fresh.confirmRole(.muse)
        XCTAssertTrue(fresh.save())
        fresh.confirmRole(.keeper)
        XCTAssertTrue(fresh.save(), "A successful Save advances the byte baseline")
        let existing = try Data(contentsOf: url)
        let unopened = EvolutionStore(saveURL: url)
        unopened.confirmHelpStyle(.concise)
        XCTAssertFalse(unopened.save(), "Construction must not silently adopt an existing file as its own")
        XCTAssertFalse(unopened.forget(), "A fresh owner must Load an existing valid save before deleting it")
        XCTAssertEqual(unopened.confirmedHelpStyle, .concise)
        XCTAssertEqual(try Data(contentsOf: url), existing)

        let otherURL = url.deletingLastPathComponent().appendingPathComponent("created-later.json")
        let beforeCreation = EvolutionStore(saveURL: otherURL)
        beforeCreation.confirmRole(.hearth)
        try existing.write(to: otherURL)
        XCTAssertFalse(beforeCreation.save())
        XCTAssertEqual(try Data(contentsOf: otherURL), existing)
        XCTAssertTrue(beforeCreation.load())
        beforeCreation.confirmRole(.hearth)
        XCTAssertTrue(beforeCreation.save())
    }

    @MainActor
    func testExternalRemovalAndFailedMissingLoadCannotResurrectDeletedHistory() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try savedFirstLight(at: url)
        let kept = store.kinGrowthRecord
        try FileManager.default.removeItem(at: url)
        store.confirmRole(.scout)
        XCTAssertFalse(store.save())
        XCTAssertFalse(store.load(), "Missing Load preserves the old baseline and session")
        XCTAssertFalse(store.save())
        XCTAssertEqual(store.kinGrowthRecord, kept)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(store.forget(), "Explicit Forget acknowledges absence and starts a new local session")
        XCTAssertNil(store.kinGrowthRecord)
        store.confirmRole(.muse)
        XCTAssertTrue(store.save())
        let reopened = EvolutionStore(saveURL: url)
        XCTAssertTrue(reopened.load())
        XCTAssertNil(reopened.kinGrowthRecord)
        XCTAssertEqual(reopened.confirmedRole, .muse)
    }

    @MainActor
    func testFailedLoadDoesNotAdoptCorruptOrLaterRepairedBytes() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try savedFirstLight(at: url)
        let originalBytes = try Data(contentsOf: url), original = store.kinGrowthRecord
        try Data("{not valid".utf8).write(to: url)
        XCTAssertFalse(store.load())
        XCTAssertEqual(store.kinGrowthRecord, original)
        var repaired = try object(originalBytes)
        repaired["role"] = "guardian"
        let repairedBytes = try JSONSerialization.data(withJSONObject: repaired, options: .sortedKeys)
        try repairedBytes.write(to: url)
        XCTAssertFalse(store.save())
        XCTAssertFalse(store.save(replacingInvalidFile: true), "An old repair confirmation cannot overwrite a now-valid foreign save")
        XCTAssertFalse(store.forget())
        XCTAssertEqual(store.kinGrowthRecord, original)
        XCTAssertEqual(try Data(contentsOf: url), repairedBytes)
        XCTAssertTrue(store.load())
        XCTAssertEqual(store.confirmedRole, .guardian)
        XCTAssertTrue(store.save())
    }

    @MainActor
    func testStaleForgetPreservesBothNewerFileAndUnclearedSession() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let writer = try savedFirstLight(at: url)
        let stale = EvolutionStore(saveURL: url)
        XCTAssertTrue(stale.load())
        stale.confirmHelpStyle(.reflective)
        let staleRecord = stale.kinGrowthRecord, stalePreferences = stale.preferences
        let staleRevision = stale.revision, staleReceipts = stale.usefulReceipts
        writer.returnKinToSeed(originDigest: origin)
        XCTAssertTrue(writer.save())
        let newer = try Data(contentsOf: url)
        XCTAssertFalse(stale.forget())
        XCTAssertTrue(stale.status.contains("not forgotten"))
        XCTAssertEqual(stale.kinGrowthRecord, staleRecord)
        XCTAssertEqual(stale.preferences, stalePreferences)
        XCTAssertEqual(stale.usefulReceipts, staleReceipts)
        XCTAssertEqual(stale.revision, staleRevision)
        XCTAssertEqual(try Data(contentsOf: url), newer)
        XCTAssertTrue(stale.load())
        XCTAssertTrue(stale.forget())
        XCTAssertNil(stale.kinGrowthRecord)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func testExplicitCorruptRepairStillWorksForBoundedEmptyAndOversizedFiles() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        for invalid in [Data("{invalid".utf8), Data(), Data(repeating: 32, count: EvolutionStore.maximumSaveBytes + 1)] {
            try invalid.write(to: url)
            let store = EvolutionStore(saveURL: url)
            store.confirmRole(.keeper)
            XCTAssertFalse(store.save())
            XCTAssertTrue(store.requiresReplacement)
            XCTAssertEqual(try Data(contentsOf: url), invalid)
            XCTAssertTrue(store.save(replacingInvalidFile: true), store.status)
            XCTAssertFalse(store.requiresReplacement)
            let repaired = try Data(contentsOf: url)
            XCTAssertTrue(store.load())
            XCTAssertEqual(store.confirmedRole, .keeper)
            XCTAssertTrue(store.save())
            XCTAssertEqual(try Data(contentsOf: url), repaired)
        }
    }

    @MainActor
    func testExplicitSymlinkRepairReplacesOnlyTheLink() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let target = url.deletingLastPathComponent().appendingPathComponent("unrelated.json")
        let contents = Data("Preserve this target exactly.".utf8)
        try contents.write(to: target)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        let store = EvolutionStore(saveURL: url)
        store.confirmRole(.muse)
        XCTAssertFalse(store.save())
        XCTAssertTrue(store.save(replacingInvalidFile: true), store.status)
        XCTAssertEqual(try Data(contentsOf: target), contents)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType, .typeRegular)
        XCTAssertTrue(store.load(), store.status)
        XCTAssertEqual(store.confirmedRole, .muse)
    }

    @MainActor
    func testKnownLegacyLoadPreservesExactBaselineUntilAnExplicitSave() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let legacy = try EvolutionLegacyTestData.data(version: 4)
        try legacy.write(to: url)
        let store = EvolutionStore(saveURL: url)
        XCTAssertTrue(store.load())
        XCTAssertEqual(try Data(contentsOf: url), legacy)
        XCTAssertTrue(store.save())
        let migrated = try Data(contentsOf: url)
        XCTAssertEqual(try object(migrated)["schema"] as? String, EvolutionStore.schema)
        XCTAssertTrue(store.save(), "Migration Save advances the baseline to new bytes")
        XCTAssertEqual(try Data(contentsOf: url), migrated)
    }

    @MainActor
    private func savedFirstLight(at url: URL) throws -> EvolutionStore {
        let store = EvolutionStore(saveURL: url)
        let lesson = LessonSnapshot(id: "11111111-1111-1111-1111-111111111111", revision: 2,
            topic: "Planning", text: "Start with a clear next action.")
        var lane = AssistantLaneReceipt(requestID: UUID().uuidString, route: .local, provider: .qwen,
            context: ContextTicket(generation: 1, placement: 1, source: 1, selection: 1),
            inputDigest: origin, sourceDigest: origin, inputContract: "native-assistant-input/v4",
            deadline: .distantFuture, modelIdentity: "synthetic-fixture", state: .complete)
        lane.localLessons = [lesson]; lane.usedLessonIDs = [lesson.modelID]
        XCTAssertTrue(store.markUseful(receipt: lane, sourceDigest: origin, confirmedLesson: lesson))
        let receipt = try XCTUnwrap(store.usefulReceipts.first)
        XCTAssertTrue(store.keepKinGrowth(try XCTUnwrap(store.proposeKinGrowth(originDigest: origin, receipt: receipt))))
        XCTAssertTrue(store.save(), store.status)
        return store
    }

    private func temporarySave() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("archi-evolution-conflict-\(UUID().uuidString)/evolution.json")
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
