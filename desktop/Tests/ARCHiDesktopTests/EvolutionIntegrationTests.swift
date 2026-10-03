import XCTest
import Combine
@testable import ARCHiDesktop

final class EvolutionIntegrationTests: XCTestCase {
    @MainActor
    func testHelpPreferencesDoNotRedrawNaturalIdentityAndNewJourneyRefreshesWithoutMoving() async throws {
        let store = fixture()
        store.preferences.reduceMotion = true
        store.preferences.visualTreatment = .pearlStudy
        let origin = String(repeating: "a", count: 64)
        store.evolution.observeJourneyOrigin(origin)
        let natural = try XCTUnwrap(store.evolution.naturalVariation)
        store.evolution.confirmFamily(.lumen)
        let panel = CompanionPanelController(store: store)
        defer { panel.window.orderOut(nil) }
        let frame = panel.window.frame, placement = store.placementRevision
        XCTAssertTrue(store.evolution.keepEvolution(try XCTUnwrap(store.evolution.proposeEvolution())))
        let referenceID = store.reactor.appearanceID
        XCTAssertEqual(referenceID, CompanionVisualAsset.appearanceID(form: store.preferences.form, family: .lumen,
            treatment: .pearlStudy, naturalVariation: natural))
        XCTAssertEqual(panel.window.contentView?.accessibilityValue() as? String, store.assistantAccessibilityValue)
        store.evolution.confirmRole(.guardian)
        store.evolution.confirmHelpStyle(.reflective)
        XCTAssertEqual(store.evolution.naturalVariation, natural)
        XCTAssertEqual(store.reactor.appearanceID, referenceID, "Assistance preferences cannot redraw an individual")
        XCTAssertTrue(store.evolution.keepEvolution(try XCTUnwrap(store.evolution.proposeEvolution())))
        XCTAssertEqual(store.reactor.appearanceID, referenceID, "Rekeeping the same family does not generate a new identity or finish")
        XCTAssertNil(store.evolution.keptAppearanceRecipe, "The new flow does not create historical role-based recipes")
        XCTAssertEqual(panel.window.contentView?.accessibilityValue() as? String, store.assistantAccessibilityValue)
        XCTAssertEqual(panel.window.frame, frame)
        XCTAssertEqual(store.placementRevision, placement)
        store.evolution.observeJourneyOrigin(String(repeating: "b", count: 64))
        let next = try XCTUnwrap(store.evolution.naturalVariation)
        XCTAssertNotEqual(next, natural)
        XCTAssertNotEqual(store.reactor.appearanceID, referenceID)
        XCTAssertEqual(store.reactor.appearanceID, CompanionVisualAsset.appearanceID(form: store.preferences.form,
            family: .lumen, treatment: .pearlStudy, naturalVariation: next))
        XCTAssertEqual(panel.window.contentView?.accessibilityValue() as? String, store.assistantAccessibilityValue)
        XCTAssertEqual(panel.window.frame, frame)
        XCTAssertEqual(store.placementRevision, placement)
        await store.shutdownAssistant()
    }

    @MainActor
    func testOnlyCurrentCompletedSharedWorkCanBecomeFeedback() async throws {
        let store = fixture()
        store.share(text: "Synthetic source: the room is Cedar.", name: "fixture.txt")
        try await answer(store)
        let id = try XCTUnwrap(store.compareResults[.qwen]?.receipt?.requestID)
        XCTAssertNotNil(store.compareResults[.qwen]?.receipt?.sourceDigest)
        store.placed(at: CGPoint(x: 123, y: 234))
        XCTAssertNotNil(store.evolutionFeedbackReceipt(provider: .qwen, requestID: id), "Movement preserves content-only evidence")
        XCTAssertTrue(store.markReplyUsefulForEvolution(provider: .qwen, requestID: id))
        XCTAssertFalse(store.markReplyUsefulForEvolution(provider: .qwen, requestID: id))
        XCTAssertEqual(store.evolution.usefulReceipts.count, 1)
        store.share(text: "A replaced source.", name: "new.txt")
        XCTAssertFalse(store.markReplyUsefulForEvolution(provider: .qwen, requestID: id))
        XCTAssertEqual(store.evolution.usefulReceipts.count, 1, "Prior admitted feedback survives later source changes")
        await store.shutdownAssistant()
    }

    @MainActor
    func testConversationCanCountButChangedSourceBytesCannot() async throws {
        let store = fixture()
        try await answer(store)
        var id = try XCTUnwrap(store.compareResults[.qwen]?.receipt?.requestID)
        XCTAssertTrue(store.markReplyUsefulForEvolution(provider: .qwen, requestID: id))
        XCTAssertNil(store.evolution.usefulReceipts.first?.sourceDigest)
        XCTAssertNotNil(store.evolution.usefulReceipts.first?.requestBinding)
        store.share(text: "Synthetic source A.", name: "fixture.txt")
        try await answer(store)
        id = try XCTUnwrap(store.compareResults[.qwen]?.receipt?.requestID)
        // Even direct property mutation that bypasses the source revision cannot
        // reuse an old receipt because admission compares exact source digests.
        store.sharedText = "Synthetic source B."
        XCTAssertFalse(store.markReplyUsefulForEvolution(provider: .qwen, requestID: id))
        XCTAssertEqual(store.evolution.usefulReceipts.count, 1)
        await store.shutdownAssistant()
    }

    @MainActor
    func testEvolutionCanUpdateWithoutAnimationOrChangingPlacementAndProvider() async throws {
        let store = fixture()
        store.preferences.reduceMotion = true
        store.placed(at: CGPoint(x: 500, y: 400))
        let position = store.position, placement = store.placementRevision
        store.share(text: "Synthetic source for useful work.", name: "fixture.txt")
        store.evolution.confirmRole(.muse)
        store.evolution.confirmHelpStyle(.exploratory)
        store.evolution.confirmFamily(.fen)
        for _ in 0..<2 {
            try await answer(store)
            let id = try XCTUnwrap(store.compareResults[.qwen]?.receipt?.requestID)
            XCTAssertTrue(store.markReplyUsefulForEvolution(provider: .qwen, requestID: id))
        }
        var changes = 0
        let subscription = store.objectWillChange.sink { changes += 1 }
        let proposal = try XCTUnwrap(store.evolution.proposeEvolution())
        XCTAssertTrue(store.evolution.keepEvolution(proposal))
        XCTAssertGreaterThan(changes, 0, "Nested evolution must notify the live views even when animation is off")
        XCTAssertEqual(store.evolution.activeFamily, .fen)
        XCTAssertEqual(store.position, position)
        XCTAssertEqual(store.placementRevision, placement)
        XCTAssertEqual(store.route, .local)
        XCTAssertEqual(store.connection(for: .qwen), .ready)
        store.chooseStartingForm(.light)
        XCTAssertNil(store.evolution.activeFamily)
        XCTAssertEqual(store.preferences.form, .light)
        XCTAssertEqual(store.evolution.usefulReceipts.count, 2)
        withExtendedLifetime(subscription) {}
        await store.shutdownAssistant()
    }

    @MainActor private func fixture() -> CompanionStore {
        CompanionStore(preferenceURL: FileManager.default.temporaryDirectory.appendingPathComponent("evolution-integration-\(UUID().uuidString).json"),
                       assistant: HamptonReasonsAssistant(reasoner: EvolutionFixtureAssistant(),
                                                          contextSelector: EvolutionFixtureAssistant()))
    }
    @MainActor private func answer(_ store: CompanionStore) async throws {
        store.connectAssistant(provider: .qwen)
        try await wait { store.connection(for: .qwen) == .ready }
        store.prompt = "Explain the shared source."
        store.submit()
        try await wait { !store.isWorking }
        XCTAssertEqual(store.compareResults[.qwen]?.state, .complete, "Current request status: \(store.status)")
    }
    @MainActor private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 { if condition() { return }; try await Task.sleep(for: .milliseconds(5)) }
        XCTFail("Fixture did not complete within its bound")
    }
}

@MainActor
private final class EvolutionFixtureAssistant: LocalRoleClient {
    func connect() async throws {}
    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
        let payload: [String: JSONValue] = ["schema": .string("archi-reason-proposal/v1"),
            "requestID": .string(request.id), "kind": .string("ANSWER"),
            "answer": .string("A synthetic useful response."), "uncertainty": .string(""),
            "sourceIDs": .array([]), "memoryIDs": .array([])]
        return LocalRoleResult(requestID: request.id, role: request.role,
            text: String(decoding: try JSONEncoder().encode(payload), as: UTF8.self),
            model: QwenModelMetadata(name: "evolution-fixture", family: "qwen", parameterSize: "fixture",
                quantization: "fixture", digest: String(repeating: "e", count: 64)), elapsedMilliseconds: 0)
    }
    func disconnect() {}
    func shutdown() async {}
}
