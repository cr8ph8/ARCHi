import Foundation
import XCTest
@testable import ARCHiDesktop

final class WorldOutcomeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let session = "AF7E84E9-A6D7-4F3B-961B-3DB94FD3AB28"

    private func presentation(revision: Int = 7, sessionID: String? = nil) -> UnityPresentationSnapshot {
        UnityPresentationSnapshot(schemaVersion: 1, sessionID: sessionID ?? session, revision: revision,
            originDigest: String(repeating: "a", count: 64), displayName: "Fixture", body: "seed", appearance: "kin", cursor: "seed",
            seedAssetSHA256: String(repeating: "b", count: 64), bodyAssetSHA256: String(repeating: "b", count: 64),
            activity: "idle", lightMode: "rest", quiet: false, reduceMotion: false, visible: true,
            equippedFocusStaff: false, staffPalette: nil, staffCrown: nil, active: true,
            updatedAtUnix: now.timeIntervalSince1970, sessionKind: "companion", destination: "arena", destinationRevision: 1)
    }

    private func action(_ sequence: Int) -> WorldActionOutcome {
        WorldActionOutcome(sequence: sequence, actionID: UUID().uuidString, boutID: UUID().uuidString,
            presentationRevision: 7, atUnix: now.timeIntervalSince1970 - 0.25,
            action: "pulse", rivalAction: "signature", field: "guardian", round: 1,
            integrityBefore: 36, integrityAfter: 30, rivalIntegrityBefore: 36, rivalIntegrityAfter: 29,
            sparkBefore: 3, sparkAfter: 3, rivalSparkBefore: 3, rivalSparkAfter: 2,
            damageDealt: 7, damageTaken: 6, absorbed: 0, complete: false, winner: "")
    }

    private func snapshot(_ outcomes: [WorldActionOutcome], mode: String = "solo") -> WorldOutcomeSnapshot {
        WorldOutcomeSnapshot(schemaVersion: 1, sessionID: session, originDigest: String(repeating: "a", count: 64),
            sessionKind: "companion", revision: 7, updatedAtUnix: now.timeIntervalSince1970,
            currentArea: "arena", mode: mode, firstSequence: outcomes.first?.sequence ?? 0,
            lastSequence: outcomes.last?.sequence ?? 0, outcomes: outcomes)
    }

    private func altered<T: Codable>(_ value: T, _ edit: (inout [String: Any]) -> Void) throws -> T {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        edit(&object)
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testResolvedFactsRoundTripAndDuplicatePollingIsEmpty() throws {
        let original = snapshot([action(1), action(2)])
        let decoded = try JSONDecoder().decode(WorldOutcomeSnapshot.self, from: JSONEncoder().encode(original))
        try decoded.validate(matching: [presentation(revision: 8), presentation()], now: now)
        XCTAssertEqual(decoded, original)
        let batch = try decoded.batch(after: 0)
        XCTAssertEqual(batch.outcomes.count, 2)
        XCTAssertEqual(batch.missingCount, 0)
        XCTAssertEqual(batch.outcomes.first?.integrityAfter, 30)
        XCTAssertEqual(try decoded.batch(after: 2).outcomes, [])
    }

    func testRingEvictionReportsExactMissingSequenceCount() throws {
        let retained = snapshot((33...64).map(action))
        try retained.validate(matching: [presentation()], now: now)
        XCTAssertEqual(try retained.batch(after: 0).missingCount, 32)
        XCTAssertEqual(try retained.batch(after: 40).missingCount, 0)
        XCTAssertEqual(try retained.batch(after: 40).outcomes.count, 24)
        XCTAssertThrowsError(try retained.batch(after: 65)) { XCTAssertEqual($0 as? WorldOutcomeError, .sequenceRegression) }
    }

    func testSessionRevisionAndHeartbeatMustMatchActualPresentation() throws {
        let value = snapshot([action(1)])
        XCTAssertThrowsError(try value.validate(matching: [presentation(sessionID: UUID().uuidString)], now: now))
        XCTAssertThrowsError(try value.validate(matching: [presentation(revision: 8)], now: now))
        XCTAssertThrowsError(try value.validate(matching: [presentation()], now: now.addingTimeInterval(6)))
        XCTAssertThrowsError(try value.validate(matching: [presentation()], now: now.addingTimeInterval(-6)))
    }

    func testMalformedFactsAndFutureEventCannotBecomeOutcomes() throws {
        let edits: [(String, Any)] = [("integrityAfter", 35), ("sparkAfter", 4), ("round", 21),
                                     ("action", "grantGrowth"), ("atUnix", now.timeIntervalSince1970 + 1),
                                     ("presentationRevision", 8), ("complete", true)]
        for (key, value) in edits {
            let bad = try altered(action(1)) { $0[key] = value }
            XCTAssertThrowsError(try snapshot([bad]).validate(matching: [presentation()], now: now), key)
        }
    }

    func testDuplicateIDsInternalGapsAndExcessCapacityFailClosed() throws {
        let first = action(1)
        let duplicate = try altered(action(2)) { $0["actionID"] = first.actionID }
        XCTAssertThrowsError(try snapshot([first, duplicate]).validate(matching: [presentation()], now: now))
        XCTAssertThrowsError(try snapshot([first, action(3)]).validate(matching: [presentation()], now: now))
        XCTAssertThrowsError(try snapshot((1...33).map(action)).validate(matching: [presentation()], now: now))
    }

    func testPairedModeIsAnObservationWithOnlyPriorSoloFacts() throws {
        let paired = snapshot([action(1)], mode: "paired")
        try paired.validate(matching: [presentation()], now: now)
        XCTAssertEqual(paired.mode, "paired")
        XCTAssertEqual(try paired.batch(after: 1).outcomes, [])
        try snapshot([], mode: "unavailable").validate(matching: [presentation()], now: now)
    }

    func testReadRejectsRenderingAckSymlinkAndOversizedFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("world-outcome-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let presentationURL = directory.appendingPathComponent("presentation.json")
        let outcomeURL = presentationURL.appendingPathExtension(WorldOutcomeSnapshot.pathExtension)
        let value = snapshot([action(1)])
        try JSONEncoder().encode(value).write(to: outcomeURL)
        XCTAssertEqual(try WorldOutcomeSnapshot.read(from: presentationURL, matching: [presentation()], now: now), value)
        try Data("{\"schemaVersion\":1,\"renderer\":\"unity-companion\",\"active\":true}".utf8).write(to: outcomeURL)
        XCTAssertThrowsError(try WorldOutcomeSnapshot.read(from: presentationURL, matching: [presentation()], now: now))
        try Data(repeating: 32, count: WorldOutcomeSnapshot.maximumBytes + 1).write(to: outcomeURL)
        XCTAssertThrowsError(try WorldOutcomeSnapshot.read(from: presentationURL, matching: [presentation()], now: now))
        try FileManager.default.removeItem(at: outcomeURL)
        let target = directory.appendingPathComponent("other.json")
        try JSONEncoder().encode(value).write(to: target)
        try FileManager.default.createSymbolicLink(at: outcomeURL, withDestinationURL: target)
        XCTAssertThrowsError(try WorldOutcomeSnapshot.read(from: presentationURL, matching: [presentation()], now: now))
    }
}
