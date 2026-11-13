import Foundation
import XCTest
@testable import ARCHiDesktop

/// Fault injection into the exact pure check used by EvolutionStore. These
/// synthetic references are values; no model, game, profile or file is opened.
final class KinGrowthContinuityTests: XCTestCase {
    private struct Evidence: Equatable, Sendable {
        let requestID: UUID
        let lessonRevision: UInt64
        let sourceDigest: String
    }
    private typealias Check = KinGrowthContinuity<Evidence>
    private let origin = String(repeating: "a", count: 64)
    private let foreignOrigin = String(repeating: "b", count: 64)
    private let recordID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let otherID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    private var evidence: Evidence {
        .init(requestID: otherID, lessonRevision: 2, sourceDigest: String(repeating: "c", count: 64))
    }

    func testKeepAdmitsOnlyTheRequestedFirstLight() {
        let before = snapshot(record: nil)
        let check = Check(before: before, effect: .keepFirstLight(id: recordID, evidence: evidence))
        XCTAssertTrue(check.accepts(current: before, candidate: record(active: true)))
        XCTAssertFalse(check.accepts(current: before, candidate: record(active: false)),
            "A valid Core Seed result does not satisfy a First Light request")
        XCTAssertFalse(check.accepts(current: before, candidate: record(active: true, id: otherID)))
        XCTAssertFalse(check.accepts(current: before, candidate: record(active: true, origin: foreignOrigin)))
    }

    func testKeepCannotOverwriteAnExistingBodyChoice() {
        for active in [false, true] {
            let before = snapshot(record: record(active: active))
            let check = Check(before: before, effect: .keepFirstLight(id: recordID, evidence: evidence))
            XCTAssertFalse(check.accepts(current: before, candidate: record(active: true)))
        }
    }

    func testReturnAndResumePreserveIdentityAndEvidence() {
        let firstLight = snapshot(record: record(active: true))
        let returning = Check(before: firstLight, effect: .returnToSeed)
        XCTAssertTrue(returning.accepts(current: firstLight, candidate: record(active: false)))
        let coreSeed = snapshot(record: record(active: false), revision: firstLight.revision + 1)
        let resuming = Check(before: coreSeed, effect: .resumeFirstLight)
        XCTAssertTrue(resuming.accepts(current: coreSeed, candidate: record(active: true)))

        for (check, current, target) in [(returning, firstLight, false), (resuming, coreSeed, true)] {
            XCTAssertFalse(check.accepts(current: current, candidate: record(active: target, id: otherID)))
            XCTAssertFalse(check.accepts(current: current, candidate: record(active: target, origin: foreignOrigin)))
        }
    }

    func testWrongRequestedTargetsAndNoOpEffectsAreRejected() {
        for active in [false, true] {
            let before = snapshot(record: record(active: active))
            let requested: Check.Effect = active ? .returnToSeed : .resumeFirstLight
            XCTAssertFalse(Check(before: before, effect: requested)
                .accepts(current: before, candidate: record(active: active)))
            let noOp: Check.Effect = active ? .resumeFirstLight : .returnToSeed
            XCTAssertFalse(Check(before: before, effect: noOp)
                .accepts(current: before, candidate: record(active: active)))
        }
    }

    func testStaleRevisionFailsEvenWhenTheBodyReturnsToTheSameValue() {
        let before = snapshot(record: record(active: true))
        let check = Check(before: before, effect: .returnToSeed)
        let restored = snapshot(record: before.record, revision: before.revision + 2)
        XCTAssertFalse(check.accepts(current: restored, candidate: record(active: false)),
            "Returning to identical values must not revive an older request")
    }

    func testCurrentOriginAndPreviousRecordAreBoundToTheRequest() {
        let before = snapshot(record: record(active: true))
        let check = Check(before: before, effect: .returnToSeed)
        let otherCurrent = Check.Snapshot(originDigest: foreignOrigin, revision: before.revision, record: before.record)
        XCTAssertFalse(check.accepts(current: otherCurrent, candidate: record(active: false)))
        XCTAssertFalse(check.accepts(current: snapshot(record: nil), candidate: record(active: false)))
        XCTAssertFalse(check.accepts(current: snapshot(record: record(active: true, id: otherID)),
            candidate: record(active: false)))
        XCTAssertFalse(check.accepts(current: snapshot(record: record(active: false)),
            candidate: record(active: false)))
    }

    func testEveryEvidenceFieldRemainsBoundForEveryEffect() {
        let changedEvidence = [
            Evidence(requestID: recordID, lessonRevision: evidence.lessonRevision, sourceDigest: evidence.sourceDigest),
            Evidence(requestID: evidence.requestID, lessonRevision: 3, sourceDigest: evidence.sourceDigest),
            Evidence(requestID: evidence.requestID, lessonRevision: evidence.lessonRevision, sourceDigest: foreignOrigin)
        ]
        let beforeKeep = snapshot(record: nil), beforeReturn = snapshot(record: record(active: true))
        let beforeResume = snapshot(record: record(active: false))
        let requests: [(Check, Check.Snapshot, Bool)] = [
            (Check(before: beforeKeep, effect: .keepFirstLight(id: recordID, evidence: evidence)), beforeKeep, true),
            (Check(before: beforeReturn, effect: .returnToSeed), beforeReturn, false),
            (Check(before: beforeResume, effect: .resumeFirstLight), beforeResume, true)
        ]
        for (check, current, active) in requests {
            for replacement in changedEvidence {
                XCTAssertFalse(check.accepts(current: current, candidate: .init(id: recordID,
                    originDigest: origin, active: active, evidence: replacement)))
            }
        }
    }

    func testForeignPriorRecordCannotBeReassignedToTheCurrentIndividual() {
        for active in [false, true] {
            let before = snapshot(record: record(active: active, origin: foreignOrigin))
            let effect: Check.Effect = active ? .returnToSeed : .resumeFirstLight
            XCTAssertFalse(Check(before: before, effect: effect)
                .accepts(current: before, candidate: record(active: !active)))
        }
    }

    func testReturnAndResumeRequireAPreviouslyKeptRecord() {
        let before = snapshot(record: nil)
        XCTAssertFalse(Check(before: before, effect: .returnToSeed)
            .accepts(current: before, candidate: record(active: false)))
        XCTAssertFalse(Check(before: before, effect: .resumeFirstLight)
            .accepts(current: before, candidate: record(active: true)))
    }

    private func snapshot(record: Check.Record?, revision: UInt64 = 42) -> Check.Snapshot {
        .init(originDigest: origin, revision: revision, record: record)
    }

    private func record(active: Bool, id: UUID? = nil, origin suppliedOrigin: String? = nil) -> Check.Record {
        .init(id: id ?? recordID, originDigest: suppliedOrigin ?? origin, active: active, evidence: evidence)
    }
}
