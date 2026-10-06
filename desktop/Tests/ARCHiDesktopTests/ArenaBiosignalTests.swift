import XCTest
@testable import ARCHiDesktop

final class ArenaBiosignalTests: XCTestCase {
    private func session() -> ArenaBiosignalSession {
        .init(id: UUID(), participantID: UUID(), origin: .preview,
              calibration: .init(id: UUID(), featureID: "preview-fraction", low: 0.2, high: 0.8))
    }
    private func frame(_ s: ArenaBiosignalSession, sequence: UInt64 = 1, time: Double = 10,
                       value: Double = 1, quality: Double = 1, artifact: Bool = false,
                       origin: ArenaBiosignalOrigin = .preview, participant: UUID? = nil,
                       calibration: UUID? = nil) -> ArenaBiosignalFrame {
        .init(schemaVersion: 1, sessionID: s.id, participantID: participant ?? s.participantID,
              sequence: sequence, acquiredAt: time, origin: origin,
              calibrationID: calibration ?? s.calibration.id, featureID: s.calibration.featureID,
              fraction: value, quality: quality, artifactDetected: artifact)
    }

    func testBoundedExpressionExpiresAndHonorsVisibility() {
        var s = session()
        XCTAssertTrue(s.receive(frame(s), now: 10))
        XCTAssertEqual(s.expression(now: 10, visible: true, reduceMotion: false), .neutral)
        XCTAssertTrue(s.receive(frame(s, sequence: 2, time: 11), now: 11))
        let effect = s.expression(now: 11, visible: true, reduceMotion: false)
        XCTAssertGreaterThan(effect.hueDegrees, 0); XCTAssertLessThanOrEqual(effect.hueDegrees, 12)
        XCTAssertLessThanOrEqual(effect.brightness, 0.06)
        XCTAssertEqual(s.expression(now: 13.01, visible: true, reduceMotion: false), .neutral)
        XCTAssertEqual(s.expression(now: 11, visible: false, reduceMotion: false), .neutral)
        XCTAssertEqual(s.expression(now: 11, visible: true, reduceMotion: true), .neutral)
        s.stop(); XCTAssertEqual(s.expression(now: 11, visible: true, reduceMotion: false), .neutral)
        XCTAssertFalse(s.receive(frame(s, sequence: 3, time: 12), now: 12))
    }

    func testPreviewCannotMasqueradeAsLiveOrAnotherParticipant() {
        var s = session()
        XCTAssertFalse(s.receive(frame(s, origin: .live), now: 10))
        XCTAssertFalse(s.receive(frame(s, participant: UUID()), now: 10))
        XCTAssertFalse(s.receive(frame(s, calibration: UUID()), now: 10))
        XCTAssertTrue(s.receive(frame(s), now: 10))
    }

    func testInvalidQualityAndArtifactsRestoreNeutral() {
        for bad in [Double.nan, -.infinity, 1.1, -0.1, 0.79] {
            var s = session()
            XCTAssertFalse(s.receive(frame(s, quality: bad), now: 10))
            XCTAssertEqual(s.expression(now: 10, visible: true, reduceMotion: false), .neutral)
        }
        var s = session()
        XCTAssertFalse(s.receive(frame(s, artifact: true), now: 10))
        XCTAssertFalse(s.receive(frame(s, value: .nan), now: 10))
        XCTAssertFalse(s.receive(frame(s, value: 1.1), now: 10))
    }

    func testStaleFutureDuplicateAndReorderedSamplesAreRejected() {
        var s = session()
        XCTAssertFalse(s.receive(frame(s, time: 7), now: 10))
        XCTAssertFalse(s.receive(frame(s, time: 11), now: 10))
        XCTAssertTrue(s.receive(frame(s), now: 10))
        XCTAssertFalse(s.receive(frame(s), now: 10))
        XCTAssertFalse(s.receive(frame(s, sequence: 2, time: 9), now: 10))
        XCTAssertTrue(s.receive(frame(s, sequence: 2, time: 11), now: 11))
    }

    func testDegenerateCalibrationCannotDriveColors() {
        let c = ArenaBiosignalCalibration(id: UUID(), featureID: "fraction", low: 0.5, high: 0.5)
        var s = ArenaBiosignalSession(id: UUID(), participantID: UUID(), origin: .preview, calibration: c)
        XCTAssertFalse(s.receive(frame(s), now: 10))
    }

    func testForeignFrameCannotEraseCurrentExpression() {
        var s = session()
        XCTAssertTrue(s.receive(frame(s), now: 10))
        XCTAssertTrue(s.receive(frame(s, sequence: 2, time: 11), now: 11))
        let current = s.expression(now: 11, visible: true, reduceMotion: false)
        XCTAssertFalse(s.receive(frame(s, sequence: 3, time: 11, participant: UUID()), now: 11))
        XCTAssertEqual(s.expression(now: 11, visible: true, reduceMotion: false), current)
        XCTAssertFalse(s.receive(frame(s, sequence: 3, time: 11, origin: .live), now: 11))
        XCTAssertEqual(s.expression(now: 11, visible: true, reduceMotion: false), current)
    }
}
