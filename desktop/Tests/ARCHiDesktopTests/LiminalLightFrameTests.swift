import XCTest
@testable import ARCHiDesktop

final class LiminalLightFrameTests: XCTestCase {
    func testRestPreservesBaselineAtEveryClockSample() {
        for time in [-8.0, -0.25, 0, 0.5, 1, 3, 4, 1_800_000_000.25] {
            let frame = LiminalLightFrame.sample(mode: .rest, unixTime: time)
            XCTAssertEqual(frame.intensity, 1)
            XCTAssertEqual(frame.glow, 0)
        }
    }

    func testEveryModeStaysFiniteAndBoundedAcrossTheCycleAndExtremeClocks() {
        let times = Array(stride(from: -8.0, through: 8.0, by: 0.125))
            + [-Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude,
               -Double.leastNonzeroMagnitude, Double.leastNonzeroMagnitude,
               1_800_000_000.25]
        for mode in KinLightMode.allCases {
            for time in times {
                let frame = LiminalLightFrame.sample(mode: mode, unixTime: time)
                XCTAssertTrue(frame.intensity.isFinite, "\(mode) at \(time)")
                XCTAssertTrue(frame.glow.isFinite, "\(mode) at \(time)")
                XCTAssertGreaterThanOrEqual(frame.intensity, 1)
                XCTAssertLessThanOrEqual(frame.intensity, 1.38 + 0.000001)
                XCTAssertGreaterThanOrEqual(frame.glow, 0)
                XCTAssertLessThanOrEqual(frame.glow, 0.228 + 0.000001)
                for component in 0..<3 {
                    XCTAssertTrue(frame.accent[component].isFinite)
                    XCTAssertGreaterThanOrEqual(frame.accent[component], 0)
                    XCTAssertLessThanOrEqual(frame.accent[component], 1)
                }
            }
        }
        // The shared four-second clock must actually animate an active cue.
        let peak = LiminalLightFrame.sample(mode: .pulse, unixTime: 1)
        let trough = LiminalLightFrame.sample(mode: .pulse, unixTime: 3)
        XCTAssertEqual(peak.intensity, 1.38, accuracy: 0.000001)
        XCTAssertEqual(trough.intensity, 1.2736, accuracy: 0.000001)
        XCTAssertGreaterThan(peak.glow, trough.glow)
    }

    func testFourSecondPeriodMatchesAcrossNegativeAndUTCEpochClocks() {
        for mode in KinLightMode.allCases {
            for time in [-8.25, -4, -0.25, 0, 0.125, 1, 2.75, 1_800_000_000.25] {
                let expected = LiminalLightFrame.sample(mode: mode, unixTime: time)
                XCTAssertEqual(LiminalLightFrame.sample(mode: mode, unixTime: time + 4), expected)
                XCTAssertEqual(LiminalLightFrame.sample(mode: mode, unixTime: time - 4), expected)
            }
        }
    }

    func testReducedMotionKeepsEachActivityCueSteady() {
        for mode in KinLightMode.allCases {
            let expected = LiminalLightFrame.sample(mode: mode, unixTime: 0)
            for time in [-100.25, 0, 1, 3.5, 1_800_000_000.25] {
                XCTAssertEqual(LiminalLightFrame.sample(mode: mode, unixTime: time, reduced: true), expected)
            }
            if mode != .rest {
                XCTAssertGreaterThan(expected.intensity, 1)
                XCTAssertGreaterThan(expected.glow, 0)
            }
        }
    }

    func testNonfiniteClocksFallBackToTheSteadyPhase() {
        for mode in KinLightMode.allCases {
            let expected = LiminalLightFrame.sample(mode: mode, unixTime: 0)
            for time in [Double.nan, Double.infinity, -Double.infinity] {
                XCTAssertEqual(LiminalLightFrame.sample(mode: mode, unixTime: time), expected)
                XCTAssertEqual(LiminalLightFrame.sample(mode: mode, unixTime: time, reduced: true), expected)
            }
        }
    }
}
