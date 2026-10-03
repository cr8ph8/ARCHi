import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class KinPresentationTransitionTests: XCTestCase {
    func testInitialAndCompletedViewsStartAtTheAcceptedFormWithoutReplay() {
        for form in [KinPresentationTransition.Form.seed, .firstLight] {
            let state = KinPresentationTransition(form: form, at: 20)
            for time in [0.0, 20, 30, .greatestFiniteMagnitude] {
                XCTAssertEqual(state.sample(at: time).bodyAmount, form.rawValue)
                XCTAssertFalse(state.sample(at: time).isTransitioning)
            }
        }
    }

    func testKeepUnfoldsAndReturnRetracesSamePearlInFixedCoordinates() {
        var state = KinPresentationTransition(form: .seed)
        state.transition(to: .firstLight, policy: .init(), at: 10)
        XCTAssertEqual(state.sample(at: 10).bodyAmount, 0)
        let halfway = state.sample(at: 10.6)
        XCTAssertEqual(halfway.bodyAmount, 0.5, accuracy: 1e-12)
        XCTAssertEqual(halfway.coreX, 0.51, accuracy: 1e-12)
        XCTAssertEqual(halfway.coreY, 0.56, accuracy: 1e-12)
        XCTAssertEqual(state.sample(at: 11.3), .init(bodyAmount: 1, isTransitioning: false))
        state.transition(to: .seed, policy: .init(), at: 12)
        XCTAssertEqual(state.sample(at: 12.6).bodyAmount, halfway.bodyAmount, accuracy: 1e-12)
        XCTAssertEqual(state.sample(at: 13.3), .init(bodyAmount: 0, isTransitioning: false))
    }

    func testRapidReturnResumePreservesVisibleProgressAndCannotReceiveLateCompletion() {
        var state = KinPresentationTransition(form: .seed)
        state.transition(to: .firstLight, policy: .init(), at: 1)
        for (index, destination) in [KinPresentationTransition.Form.seed, .firstLight, .seed, .firstLight, .seed].enumerated() {
            let time = 1.12 + Double(index) * 0.08
            let before = state.sample(at: time)
            state.transition(to: destination, policy: .init(), at: time)
            XCTAssertEqual(state.sample(at: time).bodyAmount, before.bodyAmount, accuracy: 1e-12)
        }
        XCTAssertEqual(state.sample(at: 100), .init(bodyAmount: 0, isTransitioning: false))
        let accepted = state
        state.transition(to: .firstLight, policy: .init(), at: 1.1)
        XCTAssertEqual(state, accepted, "An older event cannot resurrect the former destination")
    }

    func testQuietAndEitherReduceMotionSelectExactDestinationAndDoNotReplayOnResume() {
        for policy in [KinPresentationTransition.Policy(quiet: true), .init(reduceMotion: true), .init(systemReduceMotion: true)] {
            var state = KinPresentationTransition(form: .seed)
            state.transition(to: .firstLight, policy: .init(), at: 1)
            XCTAssertTrue(state.sample(at: 1.3).isTransitioning)
            state.transition(to: .firstLight, policy: policy, at: 1.3)
            XCTAssertEqual(state.sample(at: 1.3), .init(bodyAmount: 1, isTransitioning: false))
            state.transition(to: .firstLight, policy: .init(), at: 2)
            XCTAssertEqual(state.sample(at: 2), .init(bodyAmount: 1, isTransitioning: false))
            state.transition(to: .seed, policy: policy, at: 3)
            XCTAssertEqual(state.sample(at: 3), .init(bodyAmount: 0, isTransitioning: false))
        }
    }

    func testSamplingIsBoundedCadenceIndependentAndNeverMutatesTransitionState() {
        var state = KinPresentationTransition(form: .seed)
        state.transition(to: .firstLight, policy: .init(), at: 10)
        let original = state
        for index in 0...240 {
            let sample = state.sample(at: 10 + Double(index) / 100)
            XCTAssertTrue((0...1).contains(sample.bodyAmount))
            XCTAssertEqual(sample.seedOpacity + sample.bodyOpacity, 1)
            XCTAssertTrue((0.5...0.52).contains(sample.coreX))
            XCTAssertTrue((0.5...0.62).contains(sample.coreY))
            XCTAssertTrue((0.32...1).contains(sample.seedScale))
            XCTAssertTrue((0.76...1).contains(sample.bodyScale))
        }
        XCTAssertEqual(state, original)
        for time in [Double.nan, .infinity, -.infinity, -1, 9] {
            state.transition(to: .seed, policy: .init(), at: time)
            XCTAssertEqual(state, original)
            XCTAssertTrue(state.sample(at: time).bodyAmount.isFinite)
        }
        XCTAssertEqual(state.sample(at: .greatestFiniteMagnitude).bodyAmount, 1)
    }

    @MainActor
    func testTransitionEndpointsMatchExistingExportsAndIntermediateFramesRemainBounded() throws {
        for (form, amount) in [(CompanionForm.kinSeed, 0.0), (.kin, 1.0)] {
            let frame = try render(amount: amount)
            let existing = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: nil))
            XCTAssertTrue(try NaturalPresentationComparison.compare(frame, existing).withinAlphaPresentationBound,
                "Transition endpoints must preserve the current asset and static export")
        }
        for amount in [0.0, 0.15, 0.35, 0.5, 0.65, 0.85, 1] {
            let data = try render(amount: amount)
            let pixels = try XCTUnwrap(NSBitmapImageRep(data: data))
            XCTAssertEqual(pixels.pixelsWide, 512)
            XCTAssertEqual(pixels.pixelsHigh, 512)
            for coordinate in 0..<512 {
                for (x, y) in [(coordinate, 0), (coordinate, 511), (0, coordinate), (511, coordinate)] {
                    XCTAssertEqual(try XCTUnwrap(pixels.colorAt(x: x, y: y)).alphaComponent, 0,
                        "The shared pearl transition must remain inside the fixed desktop frame")
                }
            }
            if let path = ProcessInfo.processInfo.environment["ARCHI_KIN_TRANSITION_RENDER_DIR"] {
                let directory = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: directory.appendingPathComponent("kin-transition-\(Int(amount * 100)).png"))
            }
        }
    }

    @MainActor private func render(amount: Double) throws -> Data {
        let renderer = ImageRenderer(content: KinPresentationFrame(size: 256,
            pose: .init(angle: 0, speed: 0), sample: .init(bodyAmount: amount, isTransitioning: amount > 0 && amount < 1),
            reduceMotion: true, lightExpression: .resting, bodyImage: CompanionVisualAsset.kinFirstLightImage))
        renderer.scale = 2
        let tiff = try XCTUnwrap(renderer.nsImage?.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }
}
