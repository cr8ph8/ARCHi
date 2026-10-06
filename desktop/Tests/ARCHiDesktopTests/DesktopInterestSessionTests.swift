import Foundation
import Combine
import XCTest
import ARCHiSpatial
@testable import ARCHiDesktop

final class DesktopInterestSessionTests: XCTestCase {
    @MainActor
    func testUnchangedGeometryDoesNotContinuouslyInvalidateTheCompanion() throws {
        let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
        defer { session.cancel() }
        chooseTarget(session)
        XCTAssertTrue(session.beginMarkingArea())
        let marking = try XCTUnwrap(session.areaMarking)
        let region = try XCTUnwrap(ImageRegionRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        XCTAssertTrue(session.completeMarkingArea(region, markingID: marking.id))
        var changes = 0
        let observation = session.objectWillChange.sink { changes += 1 }
        defer { observation.cancel() }
        for step in 0..<20 {
            let old = reader.offeredTarget
            reader.offeredTarget = .init(windowID: old.windowID, processID: old.processID,
                appName: old.appName, title: old.title, frame: old.frame, observedAt: Date(timeIntervalSince1970: Double(step)))
            session.refreshBoundary()
        }
        XCTAssertEqual(changes, 0, "Unchanged metadata must not invalidate every source-backed view.")
        XCTAssertTrue(session.startAttraction())
        changes = 0
        for step in 20..<40 {
            let old = reader.offeredTarget
            reader.offeredTarget = .init(windowID: old.windowID, processID: old.processID,
                appName: old.appName, title: old.title, frame: old.frame, observedAt: Date(timeIntervalSince1970: Double(step)))
            XCTAssertTrue(session.refreshAttraction())
        }
        XCTAssertEqual(changes, 0)
        reader.offeredTarget = interestTarget(frame: CGRect(x: 200, y: 100, width: 400, height: 300))
        XCTAssertTrue(session.refreshAttraction())
        XCTAssertEqual(changes, 1, "Real geometry changes still publish.")
        XCTAssertEqual(session.attractionTarget, reader.offeredTarget)
        XCTAssertTrue(reader.requests.isEmpty)
    }

    @MainActor
    func testHoverAndFinishOnlySelectMetadataWithoutReading() {
        let reader = InterestSessionReader()
        let active = DesktopInterestSession(reader: reader)
        // Inactive controls cannot acquire a target or begin content access.
        active.hover(at: CGPoint(x: 10, y: 20)); active.finishAim(); active.read()
        XCTAssertEqual(active.phase, .idle)
        XCTAssertNil(active.target)
        defer { active.cancel() }
        active.begin()
        active.hover(at: CGPoint(x: CGFloat.nan, y: 0))
        XCTAssertEqual(reader.targetCalls, 0)
        active.hover(at: CGPoint(x: 25, y: 40))
        XCTAssertEqual(active.phase, .aiming)
        XCTAssertEqual(active.target, reader.offeredTarget)
        XCTAssertEqual(reader.targetCalls, 1)
        active.finishAim()
        XCTAssertEqual(active.phase, .targeted)
        XCTAssertNil(active.capture)
        XCTAssertTrue(reader.requests.isEmpty)
    }

    @MainActor
    func testMissingOrChangedTargetCannotFinishOrStartReading() {
        let reader = InterestSessionReader()
        let active = DesktopInterestSession(reader: reader)
        active.begin(); active.finishAim()
        XCTAssertEqual(active.phase, .idle)
        XCTAssertNil(active.target)
        defer { active.cancel() }
        active.begin(); active.hover(at: .zero)
        reader.current = false
        active.finishAim()
        XCTAssertEqual(active.phase, .idle)
        XCTAssertTrue(reader.requests.isEmpty)

        reader.current = true
        chooseTarget(active)
        reader.current = false
        active.read()
        XCTAssertEqual(active.phase, .idle)
        XCTAssertNil(active.capture)
        XCTAssertTrue(reader.requests.isEmpty)
    }

    @MainActor
    func testExplicitReadOccursOnceAndProducesOnlyAReviewSnapshot() async throws {
        let reader = InterestSessionReader()
        let active = DesktopInterestSession(reader: reader)
        active.read()
        XCTAssertEqual(active.phase, .idle)
        defer { active.cancel(); reader.cancelPending() }
        chooseTarget(active)
        XCTAssertTrue(reader.requests.isEmpty)
        active.read(); active.read(); active.finishAim()
        try await interestSettle { reader.requests.count == 1 }
        XCTAssertEqual(active.phase, .reading)
        XCTAssertNil(active.capture)
        XCTAssertEqual(reader.requests[0], reader.offeredTarget)
        let result = reader.snapshot(text: "A synthetic passage to review.")
        reader.complete(0, with: result)
        try await interestSettle { active.phase == .review }
        XCTAssertEqual(active.capture, result)
        XCTAssertEqual(reader.requests.count, 1)
    }

    @MainActor
    func testCancelRejectsLateSuccessAndLateFailure() async throws {
        for fails in [false, true] {
            let reader = InterestSessionReader()
            let active = DesktopInterestSession(reader: reader)
            defer { active.cancel(); reader.cancelPending() }
            chooseTarget(active); active.read()
            try await interestSettle { reader.requests.count == 1 }
            active.cancel(reason: "Cancelled by user")
            if fails { reader.fail(0) }
            else { reader.complete(0, with: reader.snapshot(text: "Late private text")) }
            try await interestSettle { reader.completed.contains(0) }
            await interestDrain()
            XCTAssertEqual(active.phase, .idle)
            XCTAssertNil(active.capture)
            XCTAssertNil(active.target)
            XCTAssertEqual(active.message, "Cancelled by user")
        }
    }

    @MainActor
    func testOldCompletionCannotReplaceOrFailANewerAcquisition() async throws {
        let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
        defer { session.cancel(); reader.cancelPending() }
        chooseTarget(session); session.read()
        try await interestSettle { reader.requests.count == 1 }
        reader.offeredTarget = interestTarget(windowID: 222, title: "Second synthetic window")
        chooseTarget(session); session.read()
        try await interestSettle { reader.requests.count == 2 }
        let current = reader.snapshot(text: "Current reviewed text")
        reader.complete(1, with: current)
        try await interestSettle { session.phase == .review }
        reader.complete(0, with: reader.snapshot(text: "Old text", target: reader.requests[0]))
        try await interestSettle { reader.completed.contains(0) }
        await interestDrain()
        XCTAssertEqual(session.phase, .review)
        XCTAssertEqual(session.capture, current)
        XCTAssertEqual(session.target, current.target)
        XCTAssertEqual(reader.requests.count, 2)
    }

    @MainActor
    func testTargetChangeDuringReadRejectsResultWithOrWithoutRefreshNotification() async throws {
        for refreshes in [false, true] {
            let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
            defer { session.cancel(); reader.cancelPending() }
            chooseTarget(session); session.read()
            try await interestSettle { reader.requests.count == 1 }
            reader.current = false
            if refreshes { session.refreshBoundary() }
            reader.complete(0, with: reader.snapshot(text: "A stale window snapshot"))
            try await interestSettle { reader.completed.contains(0) && session.phase != .reading }
            await interestDrain()
            XCTAssertEqual(session.phase, refreshes ? .idle : .failed)
            XCTAssertNil(session.capture)
            XCTAssertEqual(reader.requests.count, 1)
        }
    }

    @MainActor
    func testReturnedWindowIdentityMustMatchEveryCapturedBoundary() async throws {
        let original = interestTarget()
        let mismatches = [
            interestTarget(windowID: original.windowID + 1),
            interestTarget(processID: original.processID + 1),
            interestTarget(appName: "Other synthetic app"),
            interestTarget(title: "Other synthetic document"),
            interestTarget(frame: original.frame.offsetBy(dx: 1, dy: 0))
        ]
        for mismatch in mismatches {
            let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
            defer { session.cancel(); reader.cancelPending() }
            chooseTarget(session); session.read()
            try await interestSettle { reader.requests.count == 1 }
            reader.complete(0, with: reader.snapshot(text: "Mismatched snapshot", target: mismatch))
            try await interestSettle { session.phase == .failed }
            XCTAssertNil(session.capture)
        }
    }

    @MainActor
    func testEmptyWhitespaceAndOversizedUTF8AreRejectedWithoutTruncation() async throws {
        for text in ["", " \n\t ", String(repeating: "a", count: 60_001), String(repeating: "é", count: 30_001)] {
            let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
            defer { session.cancel(); reader.cancelPending() }
            chooseTarget(session); session.read()
            try await interestSettle { reader.requests.count == 1 }
            reader.complete(0, with: reader.snapshot(text: text))
            try await interestSettle { session.phase == .failed }
            XCTAssertNil(session.capture)
            XCTAssertEqual(reader.requests.count, 1)
        }
    }

    @MainActor
    func testExactByteLimitAndStableIdentityWithNewObservationTimeAreAccepted() async throws {
        let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
        defer { session.cancel(); reader.cancelPending() }
        chooseTarget(session); session.read()
        try await interestSettle { reader.requests.count == 1 }
        let text = String(repeating: "é", count: 30_000)
        let newerObservation = interestTarget(observedAt: Date(timeIntervalSince1970: 1_800_000_100))
        reader.complete(0, with: reader.snapshot(text: text, target: newerObservation))
        try await interestSettle { session.phase == .review }
        XCTAssertEqual(session.capture?.text, text)
        XCTAssertEqual(session.capture?.text.utf8.count, 60_000)
    }

    @MainActor
    func testReaderFailureKeepsNoCaptureAndCannotPassivelyRetry() async throws {
        let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
        defer { session.cancel(); reader.cancelPending() }
        chooseTarget(session); session.read()
        try await interestSettle { reader.requests.count == 1 }
        reader.fail(0)
        try await interestSettle { session.phase == .failed }
        XCTAssertNil(session.capture)
        session.read(); session.hover(at: .zero); session.finishAim(); session.refreshBoundary()
        await interestDrain()
        XCTAssertEqual(session.phase, .failed)
        XCTAssertEqual(reader.requests.count, 1)
    }

    @MainActor
    func testProductionReadDeadlineFailsAndRejectsLateSuccess() async throws {
        let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
        defer { session.cancel(); reader.cancelPending() }
        chooseTarget(session)
        let clock = ContinuousClock()
        let started = clock.now
        let limit = started.advanced(by: .seconds(12))
        session.read()
        try await interestSettle { reader.requests.count == 1 }
        // Exercise the production ten-second deadline. The synthetic reader
        // deliberately stays suspended even when its task is cancelled.
        while session.phase == .reading && clock.now < limit {
            try await Task.sleep(for: .milliseconds(25))
        }
        guard session.phase == .failed else {
            XCTFail("The production read deadline did not fail within twelve seconds")
            throw InterestSessionFailure.timeout
        }
        XCTAssertGreaterThanOrEqual(started.duration(to: clock.now), .seconds(10))
        XCTAssertNil(session.capture)
        XCTAssertTrue(session.message.contains("took too long"))
        let failureMessage = session.message
        reader.complete(0, with: reader.snapshot(text: "Late success must never become a review"))
        try await interestSettle { reader.completed.contains(0) }
        await interestDrain()
        XCTAssertEqual(session.phase, .failed)
        XCTAssertNil(session.capture)
        XCTAssertEqual(session.message, failureMessage)
        session.read()
        await interestDrain()
        XCTAssertEqual(reader.requests.count, 1, "Timeout does not automatically retry")
    }

    @MainActor
    func testReviewStaysCapturedSnapshotWithoutFollowingWindowOrRecapturing() async throws {
        let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
        defer { session.cancel(); reader.cancelPending() }
        chooseTarget(session); session.read()
        try await interestSettle { reader.requests.count == 1 }
        let captured = reader.snapshot(text: "Text as captured at the explicit read")
        reader.complete(0, with: captured)
        try await interestSettle { session.phase == .review }
        let observedCalls = reader.targetCalls, boundaryChecks = reader.currentChecks
        reader.current = false
        reader.offeredTarget = interestTarget(windowID: 333, title: "A different window now")
        session.refreshBoundary(); session.hover(at: CGPoint(x: 99, y: 99)); session.finishAim(); session.read()
        await interestDrain()
        XCTAssertEqual(session.phase, .review)
        XCTAssertEqual(session.capture, captured)
        XCTAssertEqual(reader.targetCalls, observedCalls)
        XCTAssertEqual(reader.currentChecks, boundaryChecks)
        XCTAssertEqual(reader.requests.count, 1)
        session.cancel()
        XCTAssertNil(session.capture)
        XCTAssertNil(session.target)
    }

    @MainActor
    func testExplicitAttractionRefreshFollowsOnlyTheSelectedWindowWithoutReading() {
        let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
        defer { session.cancel() }
        XCTAssertFalse(session.startAttraction())
        XCTAssertEqual(reader.refreshCalls, 0)
        session.begin()
        XCTAssertFalse(session.startAttraction(), "A hover is not a selected window.")
        chooseTarget(session)
        let selected = session.target
        XCTAssertTrue(session.startAttraction())
        XCTAssertTrue(session.attracting)
        XCTAssertEqual(session.attractionTarget, selected)

        let moved = interestTarget(frame: CGRect(x: 30, y: 80, width: 640, height: 450))
        reader.offeredTarget = moved
        reader.current = false // The old read boundary correctly rejects movement.
        XCTAssertTrue(session.refreshAttraction())
        XCTAssertEqual(session.attractionTarget, moved)
        XCTAssertEqual(session.target, selected, "Following metadata cannot replace the explicit read boundary.")
        XCTAssertEqual(session.phase, .targeted)
        XCTAssertNil(session.capture)
        XCTAssertTrue(reader.requests.isEmpty)

        reader.offeredTarget = interestTarget(windowID: moved.windowID + 1, frame: moved.frame)
        XCTAssertFalse(session.refreshAttraction(), "An identical-looking replacement window has no selection authority.")
        XCTAssertFalse(session.attracting)
        XCTAssertNil(session.attractionTarget)
        let calls = reader.refreshCalls
        XCTAssertFalse(session.refreshAttraction(), "Polling cannot restart stopped attraction.")
        XCTAssertEqual(reader.refreshCalls, calls)
        XCTAssertEqual(session.target, selected)
    }

    @MainActor
    func testClosedChangedAndInvalidTargetsStopAttractionWithoutSubstitution() {
        let alternatives: [DesktopInterestTarget?] = [
            nil,
            interestTarget(processID: 999),
            interestTarget(title: "A different document"),
            interestTarget(appName: "A different app"),
            interestTarget(frame: CGRect(x: 0, y: 0, width: 79, height: 60)),
            interestTarget(frame: CGRect(x: CGFloat.nan, y: 0, width: 400, height: 300))
        ]
        for alternative in alternatives {
            let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
            defer { session.cancel() }
            chooseTarget(session)
            XCTAssertTrue(session.startAttraction())
            reader.metadataAvailable = alternative != nil
            if let alternative { reader.offeredTarget = alternative }
            XCTAssertFalse(session.refreshAttraction())
            XCTAssertFalse(session.attracting)
            XCTAssertNil(session.attractionTarget)
            XCTAssertEqual(session.phase, .targeted)
            XCTAssertTrue(reader.requests.isEmpty)
            XCTAssertFalse(session.startAttraction(), "A stale selection cannot authorize a fresh follow session.")
        }
    }

    @MainActor
    func testReviewCaptureRemainsFixedWhileExplicitAttractionFollowsFreshMetadata() async throws {
        let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
        defer { session.cancel(); reader.cancelPending() }
        chooseTarget(session)
        XCTAssertTrue(session.startAttraction())
        session.read()
        XCTAssertFalse(session.attracting, "Explicit reading ends attraction before capturing an exact frame.")
        XCTAssertNil(session.attractionTarget)
        try await interestSettle { reader.requests.count == 1 }
        let captured = reader.snapshot(text: "This reviewed text belongs to the original capture.")
        reader.complete(0, with: captured)
        try await interestSettle { session.phase == .review }
        let moved = interestTarget(frame: CGRect(x: 300, y: 150, width: 800, height: 500))
        reader.offeredTarget = moved; reader.current = false
        XCTAssertFalse(session.refreshAttraction(), "An old review never starts attraction passively.")
        XCTAssertTrue(session.startAttraction(), "The explicit action refreshes the same window's metadata.")
        XCTAssertEqual(session.attractionTarget, moved)
        XCTAssertEqual(session.capture, captured)
        XCTAssertEqual(session.target, captured.target)
        reader.metadataAvailable = false
        XCTAssertFalse(session.refreshAttraction())
        XCTAssertEqual(session.capture, captured, "Closing the followed window does not rewrite reviewed text.")
        XCTAssertEqual(session.phase, .review)
        XCTAssertEqual(reader.requests.count, 1)
    }

    @MainActor
    func testNewAimCancelAndReadFenceAttractionAndLateOldReads() async throws {
        let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
        defer { session.cancel(); reader.cancelPending() }
        chooseTarget(session)
        XCTAssertTrue(session.startAttraction())
        session.begin()
        XCTAssertFalse(session.attracting); XCTAssertNil(session.attractionTarget)
        chooseTarget(session); session.read()
        try await interestSettle { reader.requests.count == 1 }
        reader.offeredTarget = interestTarget(windowID: 222, title: "New selected window")
        chooseTarget(session)
        XCTAssertTrue(session.startAttraction())
        let newest = session.attractionTarget
        reader.fail(0)
        try await interestSettle { reader.completed.contains(0) }
        await interestDrain()
        XCTAssertTrue(session.attracting, "An old failed read cannot stop a newer explicit attraction.")
        XCTAssertEqual(session.attractionTarget, newest)
        XCTAssertEqual(session.phase, .targeted)
        session.cancel()
        XCTAssertFalse(session.attracting); XCTAssertNil(session.attractionTarget)

        chooseTarget(session)
        XCTAssertTrue(session.startAttraction())
        reader.offeredTarget = interestTarget(windowID: 222, title: "New selected window",
            frame: CGRect(x: 80, y: 60, width: 600, height: 400))
        reader.current = false
        XCTAssertTrue(session.refreshAttraction())
        session.read()
        XCTAssertEqual(session.phase, .idle, "Moved metadata does not silently authorize a new content capture.")
        XCTAssertFalse(session.attracting); XCTAssertNil(session.attractionTarget)
        XCTAssertEqual(reader.requests.count, 1)
    }
    @MainActor
    func testExplicitAreaMarkingUsesMetadataAndFollowsOnlySameWindow() throws {
        let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
        defer { session.cancel() }
        XCTAssertFalse(session.beginMarkingArea())
        XCTAssertEqual(reader.refreshCalls, 0)
        chooseTarget(session)
        let readBoundary = session.target
        XCTAssertTrue(session.beginMarkingArea())
        let marking = try XCTUnwrap(session.areaMarking)
        let region = try XCTUnwrap(ImageRegionRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        XCTAssertTrue(session.completeMarkingArea(region, markingID: marking.id))
        XCTAssertEqual(session.markedArea, region)
        XCTAssertNil(session.areaMarking)
        XCTAssertFalse(session.attracting)
        let moved = interestTarget(frame: CGRect(x: 200, y: -80, width: 800, height: 600))
        reader.offeredTarget = moved; reader.current = false
        session.refreshBoundary()
        XCTAssertEqual(session.areaTarget, moved)
        XCTAssertEqual(session.markedArea, region)
        XCTAssertEqual(session.target, readBoundary, "Geometry attention never replaces the text-read boundary.")
        let projected = try XCTUnwrap(ParticleAttractionProjection.desktopAreaFrame(session.markedArea, in: moved.frame))
        XCTAssertEqual(projected.minX, 280, accuracy: 1e-10)
        XCTAssertEqual(projected.minY, 160, accuracy: 1e-10)
        XCTAssertEqual(projected.size, CGSize(width: 240, height: 240))
        XCTAssertTrue(session.startAttraction())
        XCTAssertEqual(session.attractionTarget, moved)
        XCTAssertTrue(reader.requests.isEmpty)
        reader.offeredTarget = interestTarget(windowID: 222, frame: moved.frame)
        XCTAssertFalse(session.refreshAttraction())
        session.refreshBoundary()
        XCTAssertNil(session.markedArea)
        XCTAssertNil(session.areaTarget)
        XCTAssertTrue(reader.requests.isEmpty)
    }

    @MainActor
    func testMarkGestureRejectsMovedClosedReplacedAndLateTargets() throws {
        let region = try XCTUnwrap(ImageRegionRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4))
        let alternatives: [DesktopInterestTarget?] = [nil,
            interestTarget(frame: CGRect(x: 100, y: 100, width: 400, height: 300)),
            interestTarget(frame: CGRect(x: -500, y: 30, width: 800, height: 300)),
            interestTarget(processID: 55), interestTarget(windowID: 333), interestTarget(title: "Changed title")]
        for alternative in alternatives {
            let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
            chooseTarget(session)
            XCTAssertTrue(session.beginMarkingArea())
            let old = try XCTUnwrap(session.areaMarking)
            reader.metadataAvailable = alternative != nil
            if let alternative { reader.offeredTarget = alternative }
            XCTAssertFalse(session.completeMarkingArea(region, markingID: old.id))
            XCTAssertNil(session.markedArea)
            XCTAssertNil(session.areaMarking)
            XCTAssertTrue(reader.requests.isEmpty)
            session.cancel()
        }
        let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
        defer { session.cancel() }
        chooseTarget(session)
        XCTAssertTrue(session.beginMarkingArea())
        let old = try XCTUnwrap(session.areaMarking)
        session.cancelMarkingArea()
        XCTAssertTrue(session.beginMarkingArea())
        let current = try XCTUnwrap(session.areaMarking)
        XCTAssertNotEqual(old.id, current.id)
        XCTAssertFalse(session.completeMarkingArea(region, markingID: old.id))
        XCTAssertEqual(session.areaMarking?.id, current.id)
        XCTAssertTrue(session.completeMarkingArea(region, markingID: current.id))
    }

    @MainActor
    func testCancelMarkingPreservesAreaAndWholeWindowAndNewAimClearIt() throws {
        let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
        defer { session.cancel() }
        chooseTarget(session)
        let region = try XCTUnwrap(ImageRegionRect(x: 0.1, y: 0.2, width: 0.5, height: 0.5))
        XCTAssertTrue(session.beginMarkingArea())
        XCTAssertTrue(session.completeMarkingArea(region, markingID: try XCTUnwrap(session.areaMarking).id))
        XCTAssertTrue(session.startAttraction())
        XCTAssertTrue(session.beginMarkingArea())
        XCTAssertFalse(session.attracting)
        session.cancelMarkingArea()
        XCTAssertEqual(session.markedArea, region)
        session.useWholeWindow()
        XCTAssertNil(session.markedArea); XCTAssertNil(session.areaTarget)
        XCTAssertTrue(session.startAttraction())
        XCTAssertEqual(session.attractionTarget?.frame, reader.offeredTarget.frame)
        XCTAssertTrue(session.beginMarkingArea())
        let old = try XCTUnwrap(session.areaMarking)
        session.begin()
        XCTAssertNil(session.areaMarking); XCTAssertNil(session.markedArea)
        XCTAssertFalse(session.completeMarkingArea(region, markingID: old.id))
        XCTAssertTrue(reader.requests.isEmpty)
    }

    @MainActor
    func testTinyMarksAreRejectedAndReadingCancelsPendingGesture() async throws {
        let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
        defer { session.cancel(); reader.cancelPending() }
        chooseTarget(session)
        XCTAssertTrue(session.beginMarkingArea())
        let tiny = try XCTUnwrap(ImageRegionRect(x: 0, y: 0, width: 0.001, height: 0.5))
        XCTAssertFalse(session.completeMarkingArea(tiny, markingID: try XCTUnwrap(session.areaMarking).id))
        XCTAssertNil(session.markedArea); XCTAssertNil(session.areaMarking)
        XCTAssertTrue(reader.requests.isEmpty)
        XCTAssertTrue(session.beginMarkingArea())
        let old = try XCTUnwrap(session.areaMarking)
        session.read()
        XCTAssertNil(session.areaMarking)
        let region = try XCTUnwrap(ImageRegionRect(x: 0, y: 0, width: 0.5, height: 0.5))
        XCTAssertFalse(session.completeMarkingArea(region, markingID: old.id))
        try await interestSettle { reader.requests.count == 1 }
        reader.complete(0, with: reader.snapshot(text: "The explicit read remains a separate action."))
        try await interestSettle { session.phase == .review }
        XCTAssertEqual(reader.requests.count, 1)
    }
}

@MainActor
private func chooseTarget(_ session: DesktopInterestSession) {
    session.begin(); session.hover(at: CGPoint(x: 25, y: 40)); session.finishAim()
    XCTAssertEqual(session.phase, .targeted)
}

private func interestTarget(windowID: UInt32 = 111, processID: Int32 = 4242,
                            appName: String = "Synthetic Editor", title: String = "Synthetic notes",
                            frame: CGRect = CGRect(x: -500, y: 30, width: 400, height: 300),
                            observedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> DesktopInterestTarget {
    DesktopInterestTarget(windowID: windowID, processID: processID, appName: appName, title: title,
                          frame: frame, observedAt: observedAt)
}

@MainActor
private func interestSettle(_ predicate: () -> Bool) async throws {
    for _ in 0..<500 {
        if predicate() { return }
        await Task.yield()
    }
    XCTFail("Synthetic interest session did not reach its expected state")
    throw InterestSessionFailure.timeout
}

@MainActor
private func interestDrain() async {
    for _ in 0..<20 { await Task.yield() }
}

private enum InterestSessionFailure: Error { case timeout, syntheticReadFailure }

/// Deliberately ignores cancellation until resumed, exercising session ownership
/// fences instead of letting a cooperative platform adapter hide late callbacks.
@MainActor
private final class InterestSessionReader: DesktopInterestReading {
    var offeredTarget = interestTarget()
    var current = true
    var targetCalls = 0, currentChecks = 0
    var metadataAvailable = true
    var refreshCalls = 0
    private(set) var requests: [DesktopInterestTarget] = []
    private(set) var completed: Set<Int> = []
    private var pending: [Int: CheckedContinuation<DesktopInterestCapture, any Error>] = [:]

    func target(at point: CGPoint) -> DesktopInterestTarget? {
        targetCalls += 1
        return offeredTarget
    }

    func isCurrent(_ target: DesktopInterestTarget) -> Bool {
        currentChecks += 1
        return current
    }

    func refreshedTarget(for target: DesktopInterestTarget) -> DesktopInterestTarget? {
        refreshCalls += 1
        return metadataAvailable ? offeredTarget : nil
    }

    func read(_ target: DesktopInterestTarget) async throws -> DesktopInterestCapture {
        let index = requests.count
        requests.append(target)
        defer { completed.insert(index) }
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }

    func snapshot(text: String, target: DesktopInterestTarget? = nil) -> DesktopInterestCapture {
        DesktopInterestCapture(target: target ?? offeredTarget, text: text, method: "Synthetic app-provided text",
                               capturedAt: Date(timeIntervalSince1970: 1_800_000_010))
    }

    func complete(_ index: Int, with result: DesktopInterestCapture) {
        guard let continuation = pending.removeValue(forKey: index) else { XCTFail("Missing synthetic read"); return }
        continuation.resume(returning: result)
    }

    func fail(_ index: Int) {
        guard let continuation = pending.removeValue(forKey: index) else { XCTFail("Missing synthetic read"); return }
        continuation.resume(throwing: InterestSessionFailure.syntheticReadFailure)
    }

    func cancelPending() {
        let continuations = Array(pending.values)
        pending.removeAll()
        for continuation in continuations { continuation.resume(throwing: CancellationError()) }
    }
}
