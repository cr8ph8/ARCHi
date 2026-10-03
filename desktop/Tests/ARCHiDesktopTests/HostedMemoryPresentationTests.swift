import Foundation
import XCTest
@testable import ARCHiDesktop

final class HostedMemoryPresentationTests: XCTestCase {
    private func memory(origin: String = "a", applications: Int = 0, support: String = "c") -> LiminalFormDevelopment.Snapshot {
        .init(originDigest: String(repeating: origin, count: 64), nodes: [
            .init(id: String(repeating: "b", count: 64), lessonIDs: ["synthetic-lesson"],
                  graphNodeIDs: ["lesson:synthetic-lesson"], title: "Private synthetic title",
                  applications: applications, reviewedApplicationCount: applications,
                  supportDigest: String(repeating: support, count: 64))
        ], unavailableLessons: 0, duplicateLessons: 0, evidenceAvailable: true)
    }

    @MainActor func testSharedSnapshotCarriesExactEvidenceAndInvalidatesSameBodyOnReviewOrOriginChange() throws {
        var captured: [LiminalFormDevelopment.Snapshot] = []
        var legacyCalls = 0
        let host = HostedPlayHost(assetDirectory: nil, appearanceRenderer: { _,_,_,_,_,_,_ in
            legacyCalls += 1; return Data([1])
        }, memorySnapshotRenderer: { _,_,_,_,_,_,_, snapshot in
            captured.append(snapshot); return Data([2])
        })
        func update(_ value: LiminalFormDevelopment.Snapshot) {
            host.updateAppearance(form: .kin, family: nil, reduceMotion: true,
                                  treatment: .protoStudy, memoryDevelopment: value)
        }
        let first = memory()
        update(first)
        let initialID = try XCTUnwrap(host.presentedAppearanceID)
        XCTAssertTrue(initialID.hasPrefix("memory-live-"))
        update(first)
        XCTAssertEqual(captured.count, 1, "Identical current evidence reuses the rendered snapshot")
        update(memory(applications: 1))
        XCTAssertNotEqual(host.presentedAppearanceID, initialID)
        let practicedID = host.presentedAppearanceID
        update(memory(applications: 1, support: "d"))
        XCTAssertNotEqual(host.presentedAppearanceID, practicedID, "A correction changes exact support even with unchanged visible density")
        let correctedID = host.presentedAppearanceID
        update(memory(origin: "e", applications: 1, support: "d"))
        XCTAssertNotEqual(host.presentedAppearanceID, correctedID)
        XCTAssertEqual(captured.first, first)
        XCTAssertEqual(legacyCalls, 0)
        XCTAssertLessThanOrEqual(try XCTUnwrap(host.presentedAppearanceID).count, 100)
        XCTAssertFalse(try XCTUnwrap(host.presentedAppearanceID).contains("Private synthetic title"))
        XCTAssertEqual(host.state, .idle)
    }

    @MainActor func testWithdrawnMemoryCannotSurviveFailedReplacementAndCanRecover() throws {
        var fail = false
        let host = HostedPlayHost(assetDirectory: nil,
            appearanceRenderer: { _,_,_,_,_,_,_ in nil },
            memorySnapshotRenderer: { _,_,_,_,_,_,_,_ in fail ? nil : Data([2]) })
        let original = memory(applications: 2)
        host.updateAppearance(form: .kinSeed, family: nil, reduceMotion: true, memoryDevelopment: original)
        let before = try XCTUnwrap(host.presentedAppearanceID)
        fail = true
        host.updateAppearance(form: .kinSeed, family: nil, reduceMotion: true, memoryDevelopment: nil)
        XCTAssertNotEqual(host.presentedAppearanceID, before)
        XCTAssertTrue(host.presentedAppearanceID?.hasSuffix("-render-unavailable") == true)
        XCTAssertTrue(host.appearanceDeliveryDiagnostics.contains { $0.contains("retired-derived-appearance") })
        XCTAssertLessThanOrEqual(try XCTUnwrap(host.presentedAppearanceID).count, 100)
        fail = false
        host.updateAppearance(form: .kinSeed, family: nil, reduceMotion: true, memoryDevelopment: original)
        XCTAssertEqual(host.presentedAppearanceID, before)
    }

    @MainActor func testFailedNewOwnerMemorySnapshotRetiresPreviousOwnerPixels() throws {
        var fail = false
        let host = HostedPlayHost(assetDirectory: nil,
            appearanceRenderer: { _,_,_,_,_,_,_ in Data([1]) },
            memorySnapshotRenderer: { _,_,_,_,_,_,_,_ in fail ? nil : Data([2]) })
        host.updateAppearance(form: .corePearl, family: nil, reduceMotion: true, memoryDevelopment: memory())
        let before = try XCTUnwrap(host.presentedAppearanceID)
        fail = true
        host.updateAppearance(form: .corePearl, family: nil, reduceMotion: true, memoryDevelopment: memory(origin: "e"))
        XCTAssertNotEqual(host.presentedAppearanceID, before)
        XCTAssertTrue(host.presentedAppearanceID?.hasSuffix("-render-unavailable") == true)
        XCTAssertLessThanOrEqual(try XCTUnwrap(host.presentedAppearanceID).count, 100)
    }

    @MainActor func testPointPathDoesNotDrawSecondMemoryOverlayAndUnrelatedFormsKeepLegacyPath() {
        var pointCalls = 0, memoryCalls = 0, legacyCalls = 0
        let host = HostedPlayHost(assetDirectory: nil,
            appearanceRenderer: { _,_,_,_,_,_,_ in legacyCalls += 1; return Data([1]) },
            pointSnapshotRenderer: { _,_,_ in pointCalls += 1; return Data([2]) },
            memorySnapshotRenderer: { _,_,_,_,_,_,_,_ in memoryCalls += 1; return Data([3]) })
        host.updateAppearance(form: .hamptonSeed, family: nil, reduceMotion: true,
                              treatment: .liminalV008, memoryDevelopment: memory())
        host.updateAppearance(form: .geode, family: nil, reduceMotion: true, memoryDevelopment: memory())
        XCTAssertEqual(pointCalls, 1)
        XCTAssertEqual(legacyCalls, 1)
        XCTAssertEqual(memoryCalls, 0)
    }

    @MainActor func testExpressionPixelsCannotReplaceCurrentMemoryProjection() {
        var memoryCalls = 0
        let host = HostedPlayHost(assetDirectory: nil, memorySnapshotRenderer: { _,_,_,_,_,_,_,_ in
            memoryCalls += 1; return Data([2])
        })
        host.updateAppearance(form: .kin, family: nil, reduceMotion: false,
                              expressionPNG: Data([9]), expressionRevision: 1, memoryDevelopment: memory())
        XCTAssertEqual(memoryCalls, 1)
    }

    @MainActor func testReactorRefreshesBeforePreviewPreflightOrPaidDispatch() {
        var launches = 0, refreshes = 0
        let reactor = ReactorExpressionStore(factory: {
            launches += 1; throw CocoaError(.executableLoad)
        })
        reactor.updateReference(id: "old-memory", label: "Synthetic", png: Data([1]), motionAllowed: true, visible: true)
        reactor.refreshCurrentReference = { [weak reactor] in
            refreshes += 1
            reactor?.updateReference(id: "memory-withdrawn", label: "Unavailable", png: nil, motionAllowed: true, visible: true)
        }
        reactor.startLocalPreview()
        reactor.prepare()
        reactor.startLive(apiKey: "rk_fixture_only_123456", reviewedQuote: .init(id: UUID(), appearanceID: "old-memory",
            referenceDigest: "synthetic", date: Date(), creditsPerSecond: 1, creditsPerUSD: 1))
        XCTAssertEqual(refreshes, 3)
        XCTAssertEqual(launches, 0)
        XCTAssertNil(reactor.referencePNG)
        XCTAssertNil(reactor.framePNG)
        XCTAssertFalse(reactor.canStart)
    }
}
