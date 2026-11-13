import Foundation
import XCTest
@testable import ARCHiDesktop

final class KinGrowthStoreTests: XCTestCase {
    private let origin = String(repeating: "a", count: 64)
    private let foreignOrigin = String(repeating: "b", count: 64)
    private let source = String(repeating: "c", count: 64)
    private let lesson = LessonSnapshot(id: "11111111-1111-1111-1111-111111111111", revision: 2,
        topic: "Drawing practice", text: "Begin with charcoal.")

    @MainActor
    func testPreviewKeepSaveLoadReturnAndResumeUseOneBoundedRecord() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = EvolutionStore(saveURL: url)
        let receipt = try addUsefulLesson(to: store)
        let before = store.revision
        let proposal = try XCTUnwrap(store.proposeKinGrowth(originDigest: origin, receipt: receipt))
        XCTAssertNil(store.kinGrowthRecord, "Preview never changes the kept desktop body")
        XCTAssertEqual(store.revision, before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(store.keepKinGrowth(proposal), store.status)
        let record = try XCTUnwrap(store.kinGrowthRecord)
        XCTAssertTrue(record.active)
        XCTAssertEqual(record.id, proposal.id, "Keep binds the retained record to the exact reviewed proposal")
        XCTAssertEqual(record.originDigest, origin)
        XCTAssertEqual(record.receipt, receipt)
        XCTAssertNil(store.kinGrowthProposal)
        XCTAssertFalse(store.keepKinGrowth(proposal), "An accepted preview cannot be replayed")
        XCTAssertNil(store.proposeKinGrowth(originDigest: origin, receipt: receipt))
        XCTAssertTrue(store.hasUnsavedChanges)
        XCTAssertTrue(store.save(), store.status)
        let firstSave = try Data(contentsOf: url)
        XCTAssertFalse(String(decoding: firstSave, as: UTF8.self).contains(lesson.text))
        XCTAssertFalse(String(decoding: firstSave, as: UTF8.self).contains(lesson.topic))
        XCTAssertEqual(try object(firstSave)["schema"] as? String, EvolutionStore.schema)

        let reopened = EvolutionStore(saveURL: url)
        XCTAssertNil(reopened.kinGrowthRecord, "Opening the owner does not implicitly load")
        XCTAssertTrue(reopened.load(), reopened.status)
        XCTAssertEqual(reopened.kinGrowthRecord, record)
        reopened.returnKinToSeed(originDigest: origin)
        XCTAssertEqual(reopened.kinGrowthRecord, record.settingActive(false))
        XCTAssertEqual(try Data(contentsOf: url), firstSave, "Return needs explicit Save")
        XCTAssertTrue(reopened.save(), reopened.status)
        XCTAssertTrue(store.load(), store.status)
        XCTAssertEqual(store.kinGrowthRecord?.active, false)
        XCTAssertTrue(store.resumeKinGrowth(originDigest: origin))
        XCTAssertEqual(store.kinGrowthRecord, record)
        XCTAssertFalse(store.resumeKinGrowth(originDigest: origin), "Resume has no repeated side effect")
        XCTAssertTrue(store.forget())
        XCTAssertNil(store.kinGrowthRecord)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func testValidRecordShapeDoesNotAdmitAnUnrequestedContinuityChange() throws {
        let store = EvolutionStore()
        let receipt = try addUsefulLesson(to: store)
        let proposal = try XCTUnwrap(store.proposeKinGrowth(originDigest: origin, receipt: receipt))
        let before = KinGrowthContinuity<EvolutionUsefulReceipt>.Snapshot(
            originDigest: origin, revision: proposal.revision, record: nil)
        let check = KinGrowthContinuity<EvolutionUsefulReceipt>(before: before,
            effect: .keepFirstLight(id: proposal.id, evidence: receipt))
        let differentReference = EvolutionUsefulReceipt(requestID: UUID(), sourceDigest: receipt.sourceDigest,
            requestBinding: receipt.requestBinding, lessonUse: receipt.lessonUse)
        let unwanted = [
            KinGrowthRecord(id: proposal.id, originDigest: foreignOrigin, active: true, receipt: receipt),
            KinGrowthRecord(id: UUID(), originDigest: origin, active: true, receipt: receipt),
            KinGrowthRecord(id: proposal.id, originDigest: origin, active: false, receipt: receipt),
            KinGrowthRecord(id: proposal.id, originDigest: origin, active: true, receipt: differentReference)
        ]
        for candidate in unwanted {
            XCTAssertTrue(candidate.isValid, "These faults pass the record's structural validator")
            XCTAssertFalse(check.accepts(current: before, candidate: candidate.continuityRecord))
        }
        XCTAssertNil(store.kinGrowthRecord)
        XCTAssertEqual(store.kinGrowthProposal, proposal)
        XCTAssertEqual(store.revision, before.revision)
        XCTAssertTrue(store.keepKinGrowth(proposal), "The exact reviewed choice still uses the existing owner")
        XCTAssertEqual(store.kinGrowthRecord?.id, proposal.id)
    }

    @MainActor
    func testInitialProposalRequiresExactRetainedLessonEvidence() throws {
        let store = EvolutionStore()
        let valid = EvolutionUsefulReceipt(requestID: UUID(), sourceDigest: source,
            lessonUse: try XCTUnwrap(EvolutionLessonUse.make(snapshot: lesson)))
        XCTAssertNil(store.proposeKinGrowth(originDigest: origin, receipt: valid), "Invented receipt is not retained")
        let plainLane = laneReceipt()
        XCTAssertTrue(store.markUseful(receipt: plainLane, sourceDigest: source))
        let plain = try XCTUnwrap(store.usefulReceipts.first)
        XCTAssertNil(store.proposeKinGrowth(originDigest: origin, receipt: plain), "Plain useful work is not confirmed lesson use")
        XCTAssertTrue(store.markUseful(receipt: plainLane, sourceDigest: source, confirmedLesson: lesson))
        let retained = try XCTUnwrap(store.usefulReceipts.first)
        XCTAssertNil(store.proposeKinGrowth(originDigest: "not an origin", receipt: retained))
        let otherSource = EvolutionUsefulReceipt(requestID: retained.requestID, sourceDigest: foreignOrigin, lessonUse: retained.lessonUse)
        XCTAssertNil(store.proposeKinGrowth(originDigest: origin, receipt: otherSource), "Same request cannot substitute another source")
        let otherLesson = LessonSnapshot(id: lesson.id, revision: 3, topic: lesson.topic, text: lesson.text)
        let otherUse = EvolutionUsefulReceipt(requestID: retained.requestID, sourceDigest: source,
            lessonUse: try XCTUnwrap(EvolutionLessonUse.make(snapshot: otherLesson)))
        XCTAssertNil(store.proposeKinGrowth(originDigest: origin, receipt: otherUse))
        XCTAssertNotNil(store.proposeKinGrowth(originDigest: origin.uppercased(), receipt: retained))
        XCTAssertEqual(store.kinGrowthProposal?.originDigest, origin)
        XCTAssertNil(store.kinGrowthRecord)
    }

    @MainActor
    func testPreviewReplacementPreferenceChangesWithdrawalAndDismissalFenceOldCandidates() throws {
        let store = EvolutionStore()
        let receipt = try addUsefulLesson(to: store)
        let first = try XCTUnwrap(store.proposeKinGrowth(originDigest: origin, receipt: receipt))
        let second = try XCTUnwrap(store.proposeKinGrowth(originDigest: origin, receipt: receipt))
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertFalse(store.keepKinGrowth(first))
        store.confirmHelpStyle(.reflective)
        XCTAssertNil(store.kinGrowthProposal)
        XCTAssertFalse(store.keepKinGrowth(second))
        let third = try XCTUnwrap(store.proposeKinGrowth(originDigest: origin, receipt: receipt))
        store.dismissKinGrowthPreview()
        XCTAssertFalse(store.keepKinGrowth(third))
        let fourth = try XCTUnwrap(store.proposeKinGrowth(originDigest: origin, receipt: receipt))
        store.withdrawLessonUse(requestID: receipt.requestID)
        XCTAssertNil(store.kinGrowthProposal)
        XCTAssertFalse(store.keepKinGrowth(fourth))
        XCTAssertNil(store.proposeKinGrowth(originDigest: origin, receipt: receipt))
        XCTAssertNil(store.kinGrowthRecord)
    }

    @MainActor
    func testObservedOriginChangesFencePreviewAndForeignOperationsPreserveKeptRecord() throws {
        let store = EvolutionStore()
        let receipt = try addUsefulLesson(to: store)
        store.observeJourneyOrigin(origin)
        let preview = try XCTUnwrap(store.proposeKinGrowth(originDigest: origin, receipt: receipt))
        store.observeJourneyOrigin(foreignOrigin)
        XCTAssertNil(store.kinGrowthProposal)
        XCTAssertFalse(store.keepKinGrowth(preview))
        XCTAssertNil(store.proposeKinGrowth(originDigest: origin, receipt: receipt))
        store.observeJourneyOrigin(origin)
        XCTAssertTrue(store.keepKinGrowth(try XCTUnwrap(store.proposeKinGrowth(originDigest: origin, receipt: receipt))))
        let kept = try XCTUnwrap(store.kinGrowthRecord)
        let revision = store.revision
        store.returnKinToSeed(originDigest: foreignOrigin)
        XCTAssertFalse(store.resumeKinGrowth(originDigest: foreignOrigin))
        XCTAssertEqual(store.kinGrowthRecord, kept)
        XCTAssertEqual(store.revision, revision)
        store.observeJourneyOrigin(foreignOrigin)
        XCTAssertNil(store.proposeKinGrowth(originDigest: foreignOrigin, receipt: receipt), "Another individual cannot overwrite this retained record")
        XCTAssertFalse(store.resumeKinGrowth(originDigest: origin))
        store.returnKinToSeed(originDigest: origin)
        XCTAssertEqual(store.kinGrowthRecord, kept)
    }

    @MainActor
    func testWithdrawalPreservesHistoricalBodyAndResumeDoesNotRequireTheOldLesson() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = EvolutionStore(saveURL: url)
        let receipt = try addUsefulLesson(to: store)
        XCTAssertTrue(store.keepKinGrowth(try XCTUnwrap(store.proposeKinGrowth(originDigest: origin, receipt: receipt))))
        let accepted = try XCTUnwrap(store.kinGrowthRecord)
        store.withdrawLessonUse(requestID: receipt.requestID)
        store.withdrawUseful(requestID: receipt.requestID)
        XCTAssertTrue(store.usefulReceipts.isEmpty)
        XCTAssertEqual(store.kinGrowthRecord, accepted)
        store.returnKinToSeed(originDigest: origin)
        XCTAssertTrue(store.save(), store.status)
        let reopened = EvolutionStore(saveURL: url)
        XCTAssertTrue(reopened.load(), reopened.status)
        XCTAssertTrue(reopened.usefulReceipts.isEmpty)
        XCTAssertEqual(reopened.kinGrowthRecord, accepted.settingActive(false))
        XCTAssertTrue(reopened.resumeKinGrowth(originDigest: origin), "Explicitly resume a previously kept appearance, not new evidence")
        XCTAssertEqual(reopened.kinGrowthRecord, accepted)
        XCTAssertNil(reopened.proposeKinGrowth(originDigest: origin, receipt: receipt))
    }

    @MainActor
    func testLoadForgetAndGeneralAppearancePreviewRetirePersonalPreview() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = EvolutionStore(saveURL: url)
        let receipt = try addUsefulLesson(to: store)
        XCTAssertTrue(store.save())
        let beforeLoad = try XCTUnwrap(store.proposeKinGrowth(originDigest: origin, receipt: receipt))
        XCTAssertTrue(store.load())
        XCTAssertNil(store.kinGrowthProposal)
        XCTAssertFalse(store.keepKinGrowth(beforeLoad))
        let beforeInvalidLoad = try XCTUnwrap(store.proposeKinGrowth(originDigest: origin, receipt: receipt))
        try Data("invalid".utf8).write(to: url)
        XCTAssertFalse(store.load())
        XCTAssertNil(store.kinGrowthProposal)
        XCTAssertFalse(store.keepKinGrowth(beforeInvalidLoad))
        let beforeGeneral = try XCTUnwrap(store.proposeKinGrowth(originDigest: origin, receipt: receipt))
        store.preview(.lumen)
        XCTAssertNil(store.kinGrowthProposal)
        XCTAssertFalse(store.keepKinGrowth(beforeGeneral))
        let beforeForget = try XCTUnwrap(store.proposeKinGrowth(originDigest: origin, receipt: receipt))
        XCTAssertNil(store.previewFamily)
        XCTAssertTrue(store.forget())
        XCTAssertNil(store.kinGrowthProposal)
        XCTAssertFalse(store.keepKinGrowth(beforeForget))
    }

    func testRecordStrictlyDecodesOnlyItsVersionIdentityStateAndLessonReference() throws {
        let receipt = EvolutionUsefulReceipt(requestID: UUID(), sourceDigest: source,
            lessonUse: try XCTUnwrap(EvolutionLessonUse.make(snapshot: lesson)))
        let record = KinGrowthRecord(originDigest: origin, active: true, receipt: receipt)
        let bytes = try JSONEncoder().encode(record)
        XCTAssertEqual(try JSONDecoder().decode(KinGrowthRecord.self, from: bytes), record)
        let valid = try object(bytes)
        var variants: [[String: Any]] = []
        for (key, value) in [("version", 2 as Any), ("version", true), ("active", 1), ("id", "bad"),
                             ("originDigest", "bad"), ("originDigest", origin.uppercased()), ("stage", "invented-body")] {
            var fields = valid; fields[key] = value; variants.append(fields)
        }
        for key in valid.keys { var fields = valid; fields.removeValue(forKey: key); variants.append(fields) }
        let validReceipt = try XCTUnwrap(valid["receipt"] as? [String: Any])
        for (key, value) in [("sourceDigest", "bad" as Any), ("requestID", "bad"), ("lessonUse", NSNull()), ("text", "unwanted text")] {
            var fields = valid, reference = validReceipt; reference[key] = value; fields["receipt"] = reference; variants.append(fields)
        }
        var absentLesson = validReceipt; absentLesson.removeValue(forKey: "lessonUse")
        var absentFields = valid; absentFields["receipt"] = absentLesson; variants.append(absentFields)
        for fields in variants {
            XCTAssertThrowsError(try JSONDecoder().decode(KinGrowthRecord.self,
                from: JSONSerialization.data(withJSONObject: fields)), "\(fields)")
        }
        let invalid = KinGrowthRecord(originDigest: "bad", active: true, receipt: receipt)
        XCTAssertThrowsError(try JSONEncoder().encode(invalid))
    }

    @MainActor
    func testMalformedOrDuplicateSavedGrowthPreservesAcceptedStateAndExistingFile() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = EvolutionStore(saveURL: url)
        let receipt = try addUsefulLesson(to: store)
        XCTAssertTrue(store.keepKinGrowth(try XCTUnwrap(store.proposeKinGrowth(originDigest: origin, receipt: receipt))))
        XCTAssertTrue(store.save())
        let accepted = store.kinGrowthRecord, valid = try object(Data(contentsOf: url))
        let record = try XCTUnwrap(valid["kinGrowthRecord"] as? [String: Any])
        var invalidRecord = record; invalidRecord["active"] = "true"
        var invalid = valid; invalid["kinGrowthRecord"] = invalidRecord
        var missing = valid; missing.removeValue(forKey: "kinGrowthRecord")
        let string = String(decoding: try JSONSerialization.data(withJSONObject: valid, options: .sortedKeys), as: UTF8.self)
        let duplicate = string.replacingOccurrences(of: "\"active\":true", with: "\"active\":false,\"active\":true")
        XCTAssertNotEqual(duplicate, string)
        for bytes in [try JSONSerialization.data(withJSONObject: invalid), try JSONSerialization.data(withJSONObject: missing), Data(duplicate.utf8)] {
            try bytes.write(to: url)
            XCTAssertFalse(store.load())
            XCTAssertEqual(store.kinGrowthRecord, accepted)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
            XCTAssertFalse(store.save(), "Invalid saved growth requires explicit replacement")
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }

    @MainActor
    func testLegacyV1ThroughV5MigrateWithoutCreatingGrowthAndV5RetainsLessonUse() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        for version in 1...4 {
            let bytes = try EvolutionLegacyTestData.data(version: version)
            try bytes.write(to: url)
            let store = EvolutionStore(saveURL: url)
            XCTAssertTrue(store.load(), "v\(version): \(store.status)")
            XCTAssertNil(store.kinGrowthRecord)
            XCTAssertEqual(try Data(contentsOf: url), bytes, "Migration does not write")
        }
        try FileManager.default.removeItem(at: url)
        let original = EvolutionStore(saveURL: url)
        let receipt = try addUsefulLesson(to: original)
        XCTAssertTrue(original.save())
        var v5 = try object(Data(contentsOf: url))
        v5["schema"] = "archi-companion-evolution/v5"
        v5.removeValue(forKey: "kinGrowthRecord")
        var historicalRows = try XCTUnwrap(v5["usefulReceipts"] as? [[String: Any]])
        for index in historicalRows.indices { historicalRows[index].removeValue(forKey: "requestBinding") }
        v5["usefulReceipts"] = historicalRows
        let historicalReceipt = EvolutionUsefulReceipt(requestID: receipt.requestID, sourceDigest: receipt.sourceDigest,
            lessonUse: receipt.lessonUse)
        let v5Bytes = try JSONSerialization.data(withJSONObject: v5, options: .sortedKeys)
        try v5Bytes.write(to: url)
        let migrated = EvolutionStore(saveURL: url)
        XCTAssertTrue(migrated.load(), migrated.status)
        XCTAssertNil(migrated.kinGrowthRecord)
        XCTAssertEqual(migrated.usefulReceipts, [historicalReceipt])
        XCTAssertEqual(try Data(contentsOf: url), v5Bytes)
        XCTAssertTrue(migrated.save())
        XCTAssertEqual(try object(Data(contentsOf: url))["schema"] as? String, EvolutionStore.schema)
        let reopened = EvolutionStore(saveURL: url)
        XCTAssertTrue(reopened.load())
        XCTAssertEqual(reopened.usefulReceipts, [historicalReceipt])
        XCTAssertNil(reopened.kinGrowthRecord)
    }

    @MainActor
    func testPersonalGrowthFitsAlongsideMaximumExistingHistoricalRecords() throws {
        let url = temporarySave()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let practices = (0..<8).map { index in
            PracticeEvolutionReference(originDigest: origin, eventId: "\(index):" + String(repeating: "e", count: 158),
                battleId: UUID(), rulesVersion: 1, rounds: 20, outcome: .lost,
                replayDigest: source, committedAt: "2026-09-06T18:00:00.123456789+00:00")
        }
        var legacy = try EvolutionLegacyTestData.object(practice: practices[0], historyCount: 32, receiptCount: 32)
        legacy["reviewedPractices"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(practices))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: legacy).write(to: url)
        let store = EvolutionStore(saveURL: url)
        XCTAssertTrue(store.load(), store.status)
        let generalHistory = store.history, generalRecipe = store.keptAppearanceRecipe
        let snapshot = LessonSnapshot(id: lesson.id, revision: UInt64.max, topic: lesson.topic, text: lesson.text)
        for record in store.usefulReceipts {
            var lane = laneReceipt(id: record.requestID)
            lane.sourceDigest = record.sourceDigest
            lane.localLessons = [snapshot]; lane.usedLessonIDs = [snapshot.modelID]
            store.withdrawUseful(requestID: record.requestID)
            XCTAssertTrue(store.markUseful(receipt: lane, sourceDigest: record.sourceDigest, confirmedLesson: snapshot))
        }
        let receipt = try XCTUnwrap(store.usefulReceipts.first)
        XCTAssertTrue(store.keepKinGrowth(try XCTUnwrap(store.proposeKinGrowth(originDigest: origin, receipt: receipt))))
        XCTAssertTrue(store.save(), store.status)
        XCTAssertLessThanOrEqual(try Data(contentsOf: url).count, EvolutionStore.maximumSaveBytes)
        let reopened = EvolutionStore(saveURL: url)
        XCTAssertTrue(reopened.load(), reopened.status)
        XCTAssertEqual(reopened.kinGrowthRecord, store.kinGrowthRecord)
        XCTAssertEqual(reopened.history, generalHistory)
        XCTAssertEqual(reopened.keptAppearanceRecipe, generalRecipe)
        XCTAssertEqual(reopened.usefulReceipts, store.usefulReceipts)
        XCTAssertEqual(reopened.reviewedPractices, practices)
    }

    @MainActor
    private func addUsefulLesson(to store: EvolutionStore) throws -> EvolutionUsefulReceipt {
        let lane = laneReceipt()
        XCTAssertTrue(store.markUseful(receipt: lane, sourceDigest: source, confirmedLesson: lesson), store.status)
        return try XCTUnwrap(store.usefulReceipts.first { $0.requestID.uuidString == lane.requestID })
    }

    private func laneReceipt(id: UUID = UUID()) -> AssistantLaneReceipt {
        var lane = AssistantLaneReceipt(requestID: id.uuidString, route: .local, provider: .qwen,
            context: ContextTicket(generation: 1, placement: 1, source: 1, selection: 1),
            inputDigest: String(repeating: "d", count: 64), sourceDigest: source,
            inputContract: "native-assistant-input/v4", deadline: .distantFuture, modelIdentity: "synthetic-fixture", state: .complete)
        lane.localLessons = [lesson]; lane.usedLessonIDs = [lesson.modelID]
        return lane
    }

    private func temporarySave() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("archi-kin-growth-\(UUID().uuidString)/evolution.json")
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
