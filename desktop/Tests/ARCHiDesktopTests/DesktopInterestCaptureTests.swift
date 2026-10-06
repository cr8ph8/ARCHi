import AppKit
import Testing
@testable import ARCHiDesktop

struct DesktopInterestCaptureTests {
    private let desktop = DesktopInterestGeometry(primaryTopY: 1_080,
        screenFrames: [CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
                       CGRect(x: -1_280, y: -200, width: 1_280, height: 1_024),
                       CGRect(x: 0, y: 1_080, width: 1_600, height: 900)], ownProcessID: 44)

    @Test func coordinatesRoundTripAcrossNegativeAndUpperDisplays() {
        let screenFrames = [CGRect(x: 120, y: 70, width: 500, height: 320),
                            CGRect(x: -1_200, y: 400, width: 700, height: 500),
                            CGRect(x: 100, y: -850, width: 900, height: 600)]
        for frame in screenFrames {
            let appKit = desktop.appKitFrame(fromScreenFrame: frame)
            #expect(desktop.screenFrame(fromAppKitFrame: appKit) == frame)
        }
        #expect(desktop.appKitFrame(fromScreenFrame: screenFrames[1]).minX == -1_200)
        #expect(desktop.appKitFrame(fromScreenFrame: screenFrames[2]).minY == 1_330)
    }

    @Test func metadataKeepsFrontToBackOrderAndRejectsOwnHiddenAndNonWindowLayers() {
        let records = [record(id: 1, pid: 44), record(id: 2, layer: 3),
                       record(id: 3, onScreen: false), record(id: 4, alpha: 0),
                       record(id: 5), record(id: 6)]
        let now = Date(timeIntervalSince1970: 10)
        let targets = DesktopInterestWindowCatalog.targets(from: records, in: desktop, observedAt: now)
        #expect(targets.map(\.windowID) == [5, 6])
        #expect(targets.first?.observedAt == now)
        #expect(targets.first?.id == "77:5")
        #expect(targets.first?.frame == CGRect(x: 100, y: 680, width: 600, height: 300))
    }

    @Test func metadataAllowsUntitledWindowsAndSkipsWhollyOffscreenBounds() {
        var untitled = record(id: 1)
        untitled.removeValue(forKey: kCGWindowName as String)
        var offscreen = record(id: 2)
        offscreen[kCGWindowBounds as String] = ["X": 50_000, "Y": 0, "Width": 600, "Height": 300]
        let targets = DesktopInterestWindowCatalog.targets(from: [untitled, offscreen], in: desktop,
                                                            observedAt: Date(timeIntervalSince1970: 10))
        #expect(targets.count == 1)
        #expect(targets.first?.title == "")
    }

    @Test func geometryRejectsMovedResizedInvalidAndOversizedWindows() {
        let frame = CGRect(x: -120, y: 20, width: 600, height: 400)
        #expect(DesktopInterestGeometry.sameFrame(frame, frame.offsetBy(dx: 0.5, dy: -0.5)))
        #expect(!DesktopInterestGeometry.sameFrame(frame, frame.offsetBy(dx: 2, dy: 0)))
        #expect(!DesktopInterestGeometry.sameFrame(frame, frame.insetBy(dx: 2, dy: 0)))
        #expect(!DesktopInterestGeometry.valid(CGRect(x: 0, y: 0, width: -5, height: 3)))
        #expect(DesktopInterestGeometry.screenshotSize(for: .zero) == nil)
        #expect(DesktopInterestGeometry.screenshotSize(for: CGRect(x: 0, y: 0, width: 20_000, height: 500)) == nil)
    }

    @Test func metadataRefreshFollowsOnlyExactProcessWindowAndTitleWhileAllowingMovement() throws {
        let initial = try #require(DesktopInterestWindowCatalog.targets(from: [record(id: 7)], in: desktop,
            observedAt: Date(timeIntervalSince1970: 10)).first)
        var moved = record(id: 7)
        moved[kCGWindowBounds as String] = ["X": -900, "Y": 400, "Width": 700, "Height": 500]
        let current = DesktopInterestWindowCatalog.targets(from: [record(id: 8), moved], in: desktop,
            observedAt: Date(timeIntervalSince1970: 20))
        let refreshed = try #require(DesktopInterestWindowCatalog.refreshedTarget(for: initial, candidates: current))
        #expect(refreshed.windowID == initial.windowID)
        #expect(refreshed.processID == initial.processID)
        #expect(refreshed.frame == CGRect(x: -900, y: 180, width: 700, height: 500))
        #expect(refreshed.observedAt == Date(timeIntervalSince1970: 20))
        #expect(!DesktopInterestGeometry.sameFrame(refreshed.frame, initial.frame))
        #expect(DesktopInterestWindowCatalog.refreshedTarget(for: initial, candidates: [refreshed, refreshed]) == nil)
        var renamed = moved
        renamed[kCGWindowName as String] = "Another document"
        let changed = DesktopInterestWindowCatalog.targets(from: [renamed], in: desktop, observedAt: Date())
        #expect(DesktopInterestWindowCatalog.refreshedTarget(for: initial, candidates: changed) == nil)
        let otherProcess = DesktopInterestWindowCatalog.targets(from: [record(id: 7, pid: 88)], in: desktop, observedAt: Date())
        #expect(DesktopInterestWindowCatalog.refreshedTarget(for: initial, candidates: otherProcess) == nil)
    }

    @Test func metadataRefreshRejectsClosedOffscreenTinyAndMalformedFrames() throws {
        let initial = try #require(DesktopInterestWindowCatalog.targets(from: [record(id: 7)], in: desktop, observedAt: Date()).first)
        var offscreen = record(id: 7), tiny = record(id: 7), malformed = record(id: 7)
        offscreen[kCGWindowBounds as String] = ["X": 50_000, "Y": 0, "Width": 600, "Height": 300]
        tiny[kCGWindowBounds as String] = ["X": 100, "Y": 100, "Width": 79, "Height": 60]
        malformed[kCGWindowBounds as String] = ["X": 100, "Y": 100, "Width": Double.nan, "Height": 300]
        for entries in [[], [record(id: 7, onScreen: false)], [offscreen], [tiny], [malformed]] {
            let current = DesktopInterestWindowCatalog.targets(from: entries, in: desktop, observedAt: Date())
            #expect(DesktopInterestWindowCatalog.refreshedTarget(for: initial, candidates: current) == nil)
        }
        #expect(!DesktopInterestGeometry.validAttractionFrame(CGRect(x: 0, y: 0, width: 80, height: 59)))
        #expect(!DesktopInterestGeometry.validAttractionFrame(CGRect(x: 0, y: 0, width: 20_000, height: 300)))
        #expect(DesktopInterestGeometry.validAttractionFrame(CGRect(x: -100, y: -100, width: 80, height: 60)))
    }

    @Test func screenshotAllocationIsBoundedAndPreservesTheWindowAspectRatio() throws {
        let wide = try #require(DesktopInterestGeometry.screenshotSize(for: CGRect(x: -100, y: -200, width: 4_000, height: 2_000)))
        #expect(wide == CGSize(width: 1_600, height: 800))
        let small = try #require(DesktopInterestGeometry.screenshotSize(for: CGRect(x: 0, y: 0, width: 400, height: 300)))
        #expect(small == CGSize(width: 800, height: 600))
    }

    @Test func outputLimitCountsUTF8BytesAndSeparators() throws {
        var exact = DesktopInterestTextBuffer()
        try exact.append(String(repeating: "😀", count: 15_000))
        #expect(exact.byteCount == 60_000)
        #expect(exact.text.utf8.count == 60_000)
        #expect(throws: DesktopInterestReadError.contentTooLarge(limit: 60_000)) { try exact.append("a") }
        var separated = DesktopInterestTextBuffer()
        try separated.append("  First  ")
        try separated.append("Second")
        #expect(separated.text == "First\n\nSecond")
        #expect(separated.byteCount == separated.text.utf8.count)
        var oversized = DesktopInterestTextBuffer()
        #expect(throws: DesktopInterestReadError.contentTooLarge(limit: 60_000)) {
            try oversized.append(String(repeating: "😀", count: 15_001))
        }
        #expect(oversized.text.isEmpty)
    }

    @Test func repeatedDocumentParagraphsArePreserved() throws {
        var buffer = DesktopInterestTextBuffer()
        try buffer.append("Same paragraph.")
        try buffer.append("Same paragraph.")
        #expect(buffer.text == "Same paragraph.\n\nSame paragraph.")
    }

    private func record(id: UInt32, pid: Int32 = 77, layer: Int = 0,
                        onScreen: Bool = true, alpha: Double = 1) -> [String: Any] {
        [kCGWindowNumber as String: NSNumber(value: id),
         kCGWindowOwnerPID as String: NSNumber(value: pid),
         kCGWindowLayer as String: NSNumber(value: layer),
         kCGWindowIsOnscreen as String: NSNumber(value: onScreen),
         kCGWindowAlpha as String: NSNumber(value: alpha),
         kCGWindowOwnerName as String: "Fixture Editor",
         kCGWindowName as String: "Fixture.txt",
         kCGWindowBounds as String: ["X": 100, "Y": 100, "Width": 600, "Height": 300]]
    }
}
