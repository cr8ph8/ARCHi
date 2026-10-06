import Foundation
import XCTest
@testable import ARCHiDesktop

final class LiminalPresentationPropagationTests: XCTestCase {
    @MainActor
    func testLiminalSnapshotIdentityTracksDisplayedSourceFrameAndSafeFallback() {
        let digest = String(repeating: "a", count: 64)
        func identity(_ progress: Double) -> String {
            CompanionVisualAsset.liminalAppearanceID(manifestSHA256: digest,
                seedColor: .garnet, pointProgress: progress)
        }
        let poses = [LiminalV008Runtime.standingProgress, LiminalV008Runtime.curledProgress,
                     LiminalV008Runtime.orbProgress]
        XCTAssertEqual(Set(poses.map(identity)).count, 3)
        XCTAssertEqual(identity((36.25 - 1) / 119), identity((36.49 - 1) / 119))
        XCTAssertNotEqual(identity((36.49 - 1) / 119), identity((36.5 - 1) / 119))
        XCTAssertEqual(identity((36.5 - 1) / 119), identity((36.75 - 1) / 119))
        XCTAssertEqual(identity(.nan), identity(LiminalV008Runtime.orbProgress))
        XCTAssertEqual(identity(.infinity), identity(LiminalV008Runtime.orbProgress))
        XCTAssertEqual(identity(-1), identity(0))
        XCTAssertEqual(identity(2), identity(1))
    }

    @MainActor
    func testUnrelatedAppearanceIdentityDoesNotDependOnLiminalPose() {
        let standing = CompanionVisualAsset.appearanceID(form: .companion, family: nil,
            treatment: .original, pointProgress: LiminalV008Runtime.standingProgress)
        let orb = CompanionVisualAsset.appearanceID(form: .companion, family: nil,
            treatment: .original, pointProgress: LiminalV008Runtime.orbProgress)
        XCTAssertEqual(standing, orb)
    }

    @MainActor
    func testHostedPointSnapshotReceivesPoseColorAndEquipmentWithoutChangingLegacyRenderer() {
        var legacyForms: [CompanionForm] = []
        var pointRequests: [(CompanionEquipment, CompanionSeedColor, Double)] = []
        let host = HostedPlayHost(assetDirectory: nil,
            appearanceRenderer: { form, _, _, _, _, _, _ in
                legacyForms.append(form)
                return nil
            }, pointSnapshotRenderer: { equipment, color, progress in
                pointRequests.append((equipment, color, progress))
                return nil
            })
        let equipment = CompanionEquipment(hand: .focusStaff)
        host.updateAppearance(form: .hamptonSeed, family: nil, reduceMotion: true,
            treatment: .liminalV008, equipment: equipment, seedColor: .garnet,
            pointProgress: LiminalV008Runtime.standingProgress)
        XCTAssertTrue(legacyForms.isEmpty)
        XCTAssertEqual(pointRequests.count, 1)
        XCTAssertEqual(pointRequests.first?.0, equipment)
        XCTAssertEqual(pointRequests.first?.1, .garnet)
        XCTAssertEqual(pointRequests.first?.2, LiminalV008Runtime.standingProgress)

        host.updateAppearance(form: .hamptonSeed, family: nil, reduceMotion: true,
            treatment: .liminalV008, pointProgress: .nan)
        XCTAssertEqual(pointRequests.last?.2, LiminalV008Runtime.orbProgress)
        host.updateAppearance(form: .companion, family: nil, reduceMotion: true,
            pointProgress: LiminalV008Runtime.curledProgress)
        XCTAssertEqual(legacyForms, [.companion])
        XCTAssertEqual(pointRequests.count, 2)
        // No page, asset server, GPU render, profile mutation or model call starts.
        XCTAssertEqual(host.state, .idle)
    }
}
