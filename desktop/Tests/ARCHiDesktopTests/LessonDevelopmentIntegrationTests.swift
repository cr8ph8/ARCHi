import Foundation
import XCTest
@testable import ARCHiDesktop

/// Exercises real Keep, Send, validation and save boundaries using an in-process
/// role client. No Ollama process, network transport or live provider is used.
final class LessonDevelopmentIntegrationTests: XCTestCase {
    @MainActor
    func testCitationRequiresExplicitConfirmationAndAnnotatesExistingUsefulWorkOnlyOnce() async throws {
        let fixture = try fixture()
        defer { clean(fixture) }
        let store = fixture.store
        let snapshot = try keepLesson(in: store)
        store.evolution.confirmFamily(.lumen)
        XCTAssertTrue(store.evolution.keepEvolution(try XCTUnwrap(store.evolution.proposeEvolution())))
        let preferences = store.preferences, history = store.evolution.history
        let family = store.evolution.activeFamily, origin = store.evolution.origin
        let natural = store.evolution.naturalVariation, position = store.position
        let lane = try await answer(fixture)
        let id = try XCTUnwrap(lane.receipt?.requestID)
        XCTAssertEqual(store.reviewableEvolutionLessons(provider: .qwen, requestID: id), [snapshot])
        XCTAssertTrue(store.evolution.usefulReceipts.isEmpty, "A model citation alone is not a usefulness confirmation")
        XCTAssertTrue(store.markReplyUsefulForEvolution(provider: .qwen, requestID: id))
        XCTAssertNil(store.evolution.usefulReceipts.first?.lessonUse)
        XCTAssertTrue(store.confirmLessonHelped(provider: .qwen, requestID: id, snapshot: snapshot))
        let use = try XCTUnwrap(store.evolution.usefulReceipts.first?.lessonUse)
        XCTAssertTrue(use.matches(snapshot: snapshot))
        XCTAssertFalse(store.confirmLessonHelped(provider: .qwen, requestID: id, snapshot: snapshot))
        XCTAssertEqual(store.evolution.usefulReceipts.count, 1)
        XCTAssertTrue(store.lessonUseDescription(use).contains("You confirmed “meeting notes” helped"))
        XCTAssertTrue(store.lessonUseDescription(use).contains("revision 1"))
        XCTAssertEqual(store.preferences, preferences)
        XCTAssertEqual(store.evolution.history, history)
        XCTAssertEqual(store.evolution.activeFamily, family)
        XCTAssertEqual(store.evolution.origin, origin)
        XCTAssertEqual(store.evolution.naturalVariation, natural)
        XCTAssertEqual(store.position, position)
        XCTAssertEqual(store.keptLessons.map(LessonSnapshot.init(lesson:)), [snapshot])
        XCTAssertEqual(fixture.reasoner.requests.count, 1, "Confirmation adds no inference")
    }

    @MainActor
    func testCompareQwenCanAnnotateTheSameRequestButCodexCannotConfirmALesson() async throws {
        let fixture = try fixture()
        defer { clean(fixture) }
        let store = fixture.store, snapshot = try keepLesson(in: fixture.store)
        fixture.reasoner.hold = true
        try await start(fixture, route: .compare)
        try await waitUntil { fixture.reasoner.hasPending && store.compareResults[.codex]?.state == .complete }
        let requestID = try XCTUnwrap(store.compareResults[.codex]?.receipt?.requestID)
        XCTAssertTrue(fixture.codex.requests.allSatisfy { $0.localLessons.isEmpty })
        XCTAssertTrue(store.markReplyUsefulForEvolution(provider: .codex, requestID: requestID))
        XCTAssertFalse(store.confirmLessonHelped(provider: .codex, requestID: requestID, snapshot: snapshot))
        fixture.reasoner.release()
        try await waitUntil { !store.isWorking }
        XCTAssertEqual(store.compareResults[.qwen]?.receipt?.requestID, requestID)
        XCTAssertEqual(store.reviewableEvolutionLessons(provider: .qwen, requestID: requestID), [snapshot])
        XCTAssertTrue(store.confirmLessonHelped(provider: .qwen, requestID: requestID, snapshot: snapshot))
        XCTAssertEqual(store.evolution.usefulReceipts.count, 1, "Compare counts the shared request once")
        XCTAssertTrue(try XCTUnwrap(store.evolution.usefulReceipts.first?.lessonUse).matches(snapshot: snapshot))
        XCTAssertFalse(store.confirmLessonHelped(provider: .codex, requestID: requestID, snapshot: snapshot))
        XCTAssertEqual(fixture.reasoner.requests.count, 1)
        XCTAssertEqual(fixture.codex.requests.count, 1)
    }

    @MainActor
    func testPreparedUncitedUnknownAndUnfinishedLessonsCannotBeConfirmed() async throws {
        let fixture = try fixture()
        defer { clean(fixture) }
        let store = fixture.store, snapshot = try keepLesson(in: fixture.store)
        fixture.reasoner.citations = []
        let uncited = try await answer(fixture)
        let uncitedID = try XCTUnwrap(uncited.receipt?.requestID)
        XCTAssertEqual(uncited.receipt?.localLessons, [snapshot])
        XCTAssertEqual(uncited.receipt?.usedLessonIDs, [])
        XCTAssertTrue(store.reviewableEvolutionLessons(provider: .qwen, requestID: uncitedID).isEmpty)
        XCTAssertFalse(store.confirmLessonHelped(provider: .qwen, requestID: uncitedID, snapshot: snapshot))
        fixture.reasoner.citations = ["unknown-lesson"]
        try await start(fixture)
        try await waitUntil { !store.isWorking }
        let failed = try XCTUnwrap(store.compareResults[.qwen])
        XCTAssertEqual(failed.state, .failed)
        XCTAssertFalse(store.confirmLessonHelped(provider: .qwen,
            requestID: try XCTUnwrap(failed.receipt?.requestID), snapshot: snapshot))
        fixture.reasoner.citations = nil
        let valid = try await answer(fixture)
        let id = try XCTUnwrap(valid.receipt?.requestID)
        let changed = LessonSnapshot(id: snapshot.id, revision: snapshot.revision,
            topic: snapshot.topic, text: "A different lesson was never captured.", source: snapshot.source)
        XCTAssertFalse(store.confirmLessonHelped(provider: .qwen, requestID: id, snapshot: changed))
        XCTAssertTrue(store.evolution.usefulReceipts.isEmpty)
    }

    @MainActor
    func testCorrectionAndWithdrawalInvalidateStaleLessonButtonsAndKeepDescriptionsHonest() async throws {
        for withdraw in [false, true] {
            let fixture = try fixture()
            defer { clean(fixture) }
            let store = fixture.store, snapshot = try keepLesson(in: fixture.store)
            let lane = try await answer(fixture)
            let id = try XCTUnwrap(lane.receipt?.requestID)
            let use = try XCTUnwrap(EvolutionLessonUse.make(snapshot: snapshot))
            if withdraw {
                XCTAssertTrue(store.withdrawLesson(id: snapshot.id, expectedRevision: store.lessonRevision))
            } else {
                store.beginLessonCorrection(revisingID: snapshot.id)
                var draft = try XCTUnwrap(store.lessonDraft)
                draft.text = "List the decision before the supporting details."
                XCTAssertTrue(store.keepLesson(draft))
                XCTAssertEqual(store.keptLessons.first?.revision, 2)
            }
            // A stale UI button still holding the captured snapshot cannot admit it.
            XCTAssertNil(store.currentKeptLesson(matching: snapshot))
            XCTAssertTrue(store.reviewableEvolutionLessons(provider: .qwen, requestID: id).isEmpty)
            XCTAssertFalse(store.confirmLessonHelped(provider: .qwen, requestID: id, snapshot: snapshot))
            XCTAssertTrue(store.evolution.usefulReceipts.isEmpty)
            XCTAssertTrue(store.lessonUseDescription(use).contains("That version is no longer kept."))
            XCTAssertFalse(store.lessonUseDescription(use).contains(snapshot.topic), "A historic hash cannot claim the current lesson's text")
        }
    }

    @MainActor
    func testExpiryBlocksNewConfirmationButDescribesAnAlreadyConfirmedReferenceAsExpired() async throws {
        let fixture = try fixture()
        defer { clean(fixture) }
        let store = fixture.store
        let snapshot = try keepLesson(in: store, expiresAt: fixture.clock.now.addingTimeInterval(60))
        let first = try await answer(fixture)
        let firstID = try XCTUnwrap(first.receipt?.requestID)
        XCTAssertTrue(store.confirmLessonHelped(provider: .qwen, requestID: firstID, snapshot: snapshot))
        let use = try XCTUnwrap(store.evolution.usefulReceipts.first?.lessonUse)
        let next = try await answer(fixture)
        let nextID = try XCTUnwrap(next.receipt?.requestID)
        fixture.clock.now = fixture.clock.now.addingTimeInterval(60)
        XCTAssertNil(store.currentKeptLesson(matching: snapshot))
        XCTAssertTrue(store.reviewableEvolutionLessons(provider: .qwen, requestID: nextID).isEmpty)
        XCTAssertFalse(store.confirmLessonHelped(provider: .qwen, requestID: nextID, snapshot: snapshot))
        XCTAssertTrue(store.lessonUseDescription(use).contains("expired"))
        XCTAssertEqual(store.evolution.usefulReceipts.count, 1, "Expiry does not erase the user's prior historical confirmation")
    }

    @MainActor
    func testSourceAndStopRejectLateCompletedReceipts() async throws {
        for cause in ["source", "source-bytes", "cancel"] {
            let fixture = try fixture()
            defer { clean(fixture) }
            let store = fixture.store, snapshot = try keepLesson(in: fixture.store)
            fixture.reasoner.hold = true
            try await start(fixture)
            try await waitUntil { fixture.reasoner.hasPending }
            let id = try XCTUnwrap(store.compareResults[.qwen]?.receipt?.requestID)
            XCTAssertEqual(store.compareResults[.qwen]?.state, .pending)
            XCTAssertFalse(store.confirmLessonHelped(provider: .qwen, requestID: id, snapshot: snapshot))
            switch cause {
            case "source": store.share(text: "A replacement synthetic source.", name: "replacement.txt")
            case "source-bytes": store.sharedText = "Different bytes without a source revision update."
            default: store.cancelWork()
            }
            // A real role response finishes after the request was invalidated.
            fixture.reasoner.release()
            try await waitUntil { fixture.reasoner.returnedCount == 1 && !store.isWorking }
            XCTAssertTrue(store.reviewableEvolutionLessons(provider: .qwen, requestID: id).isEmpty, cause)
            XCTAssertFalse(store.confirmLessonHelped(provider: .qwen, requestID: id, snapshot: snapshot), cause)
            XCTAssertTrue(store.evolution.usefulReceipts.isEmpty, "A late completed callback must not revive \(cause)-invalidated work")
        }
    }

    @MainActor
    func testEvolutionReloadKeepsTheReferenceButCannotRestoreAWithdrawnLesson() async throws {
        let fixture = try fixture()
        defer { clean(fixture) }
        let store = fixture.store, snapshot = try keepLesson(in: fixture.store)
        let lane = try await answer(fixture)
        let id = try XCTUnwrap(lane.receipt?.requestID)
        XCTAssertTrue(store.confirmLessonHelped(provider: .qwen, requestID: id, snapshot: snapshot))
        let reference = try XCTUnwrap(store.evolution.usefulReceipts.first?.lessonUse)
        XCTAssertTrue(store.evolution.save())
        let evolutionURL = try XCTUnwrap(store.evolution.saveURL)
        let savedBytes = try Data(contentsOf: evolutionURL)
        let savedText = String(decoding: savedBytes, as: UTF8.self)
        XCTAssertFalse(savedText.contains(snapshot.text))
        XCTAssertFalse(savedText.contains(snapshot.topic))
        let reopened = reopen(fixture)
        XCTAssertEqual(reopened.keptLessons.map(LessonSnapshot.init(lesson:)), [snapshot])
        XCTAssertTrue(reopened.evolution.usefulReceipts.isEmpty, "Evolution Load remains explicit")
        XCTAssertTrue(reopened.evolution.load())
        XCTAssertEqual(reopened.evolution.usefulReceipts, store.evolution.usefulReceipts)
        XCTAssertEqual(reopened.evolution.origin, store.evolution.origin)
        XCTAssertEqual(reopened.evolution.history, store.evolution.history)
        XCTAssertEqual(reopened.evolution.naturalVariation, store.evolution.naturalVariation)
        XCTAssertNotNil(reopened.currentKeptLesson(matching: snapshot))
        XCTAssertTrue(reopened.lessonUseDescription(reference).contains(snapshot.topic))
        XCTAssertTrue(reopened.reviewableEvolutionLessons(provider: .qwen, requestID: id).isEmpty,
            "Loading history does not recreate a fresh completed answer")
        XCTAssertTrue(reopened.withdrawLesson(id: snapshot.id, expectedRevision: reopened.lessonRevision))
        XCTAssertTrue(reopened.evolution.load())
        XCTAssertTrue(reopened.keptLessons.isEmpty, "An evolution hash reference must never resurrect lesson text")
        XCTAssertNil(reopened.currentKeptLesson(matching: snapshot))
        XCTAssertTrue(reopened.lessonUseDescription(reference).contains("no longer kept"))
        XCTAssertEqual(try Data(contentsOf: evolutionURL), savedBytes)
        let reopenedAgain = reopen(fixture)
        XCTAssertTrue(reopenedAgain.evolution.load())
        XCTAssertTrue(reopenedAgain.keptLessons.isEmpty)
        XCTAssertEqual(reopenedAgain.evolution.usefulReceipts.first?.lessonUse, reference)
    }

    @MainActor
    func testWithdrawingOnlyTheLessonReferenceRetainsUsefulWorkAndKeptKnowledgeAfterReload() async throws {
        let fixture = try fixture()
        defer { clean(fixture) }
        let store = fixture.store, snapshot = try keepLesson(in: fixture.store)
        let lane = try await answer(fixture)
        let id = try XCTUnwrap(lane.receipt?.requestID)
        XCTAssertTrue(store.confirmLessonHelped(provider: .qwen, requestID: id, snapshot: snapshot))
        store.evolution.withdrawLessonUse(requestID: try XCTUnwrap(UUID(uuidString: id)))
        XCTAssertEqual(store.evolution.usefulReceipts.count, 1)
        XCTAssertNil(store.evolution.usefulReceipts.first?.lessonUse)
        XCTAssertNotNil(store.currentKeptLesson(matching: snapshot))
        XCTAssertTrue(store.evolution.save())
        let reopened = reopen(fixture)
        XCTAssertTrue(reopened.evolution.load())
        XCTAssertEqual(reopened.evolution.usefulReceipts.count, 1)
        XCTAssertNil(reopened.evolution.usefulReceipts.first?.lessonUse)
        XCTAssertNotNil(reopened.currentKeptLesson(matching: snapshot))
    }

    @MainActor
    func testOrdinaryConversationLessonUseCanBecomeTheSameFirstLightMilestone() async throws {
        let fixture = try fixture(sharedDocument: false, personalKin: true)
        defer { clean(fixture) }
        let store = fixture.store
        XCTAssertNotNil(store.activeQiMon)
        let identity = store.activeQiMon, position = store.position
        let snapshot = try keepLesson(in: store)
        let lane = try await answer(fixture)
        let receipt = try XCTUnwrap(lane.receipt)
        XCTAssertNil(receipt.sourceDigest)
        XCTAssertEqual(store.reviewableEvolutionLessons(provider: .qwen, requestID: receipt.requestID), [snapshot])
        XCTAssertTrue(store.kinGrowthEvidence.isEmpty, "Neither chat nor a model citation is user feedback")
        XCTAssertTrue(store.confirmLessonHelped(provider: .qwen, requestID: receipt.requestID, snapshot: snapshot))
        let evidence = try XCTUnwrap(store.evolution.usefulReceipts.first)
        XCTAssertNil(evidence.sourceDigest, "A conversation is never labeled as a document")
        XCTAssertEqual(evidence.requestBinding, EvolutionRequestBinding(receipt: receipt))
        XCTAssertEqual(evidence.evidenceTitle, "Conversation · local Qwen")
        XCTAssertTrue(store.previewKinGrowth(receiptID: evidence.requestID))
        XCTAssertTrue(store.keepKinGrowth())
        XCTAssertEqual(store.presentationForm, .kin)
        XCTAssertEqual(store.cursorPresentationForm, .kinSeed)
        XCTAssertEqual(store.evolution.kinGrowthRecord?.version, 2)
        XCTAssertEqual(store.activeQiMon, identity)
        XCTAssertEqual(store.position, position)
        XCTAssertTrue(store.evolution.save(), store.evolution.status)
        let saved = try Data(contentsOf: XCTUnwrap(store.evolution.saveURL))
        let text = String(decoding: saved, as: UTF8.self)
        XCTAssertFalse(text.contains(snapshot.text))
        XCTAssertFalse(text.contains(store.prompt))
        XCTAssertFalse(text.contains("checked synthetic local answer"))
        XCTAssertFalse(text.contains("sourceDigest"), "No document evidence is manufactured for chat")
        let reopened = reopen(fixture)
        XCTAssertTrue(reopened.evolution.load(), reopened.evolution.status)
        XCTAssertEqual(reopened.evolution.kinGrowthRecord, store.evolution.kinGrowthRecord)
        XCTAssertEqual(reopened.presentationForm, .kin)
        XCTAssertEqual(reopened.cursorPresentationForm, .kinSeed)
        XCTAssertTrue(reopened.reviewableEvolutionLessons(provider: .qwen, requestID: receipt.requestID).isEmpty)
        XCTAssertEqual(fixture.reasoner.requests.count, 1, "Review, Keep, Save and Load add no model calls")
        await reopened.shutdownAssistant()
    }

    @MainActor
    func testConversationCorrectionWithdrawalAndExpiryRejectOldFeedback() async throws {
        for cause in ["correction", "withdrawal", "expiry"] {
            let fixture = try fixture(sharedDocument: false)
            defer { clean(fixture) }
            let store = fixture.store
            let snapshot = try keepLesson(in: store, expiresAt: fixture.clock.now.addingTimeInterval(60))
            let lane = try await answer(fixture)
            let id = try XCTUnwrap(lane.receipt?.requestID)
            switch cause {
            case "correction":
                store.beginLessonCorrection(revisingID: snapshot.id)
                var draft = try XCTUnwrap(store.lessonDraft)
                draft.text = "Give only the agreed decision."
                XCTAssertTrue(store.keepLesson(draft))
            case "withdrawal":
                XCTAssertTrue(store.withdrawLesson(id: snapshot.id, expectedRevision: store.lessonRevision))
            default: fixture.clock.now = fixture.clock.now.addingTimeInterval(60)
            }
            XCTAssertFalse(store.confirmLessonHelped(provider: .qwen, requestID: id, snapshot: snapshot), cause)
            XCTAssertTrue(store.evolution.usefulReceipts.isEmpty, cause)
        }
    }

    @MainActor
    func testConversationStopAndSourceChangesCannotReviveLateCallbacks() async throws {
        for cause in ["cancel", "source", "source-bytes", "source-name"] {
            let fixture = try fixture(sharedDocument: false)
            defer { clean(fixture) }
            let store = fixture.store, snapshot = try keepLesson(in: fixture.store)
            fixture.reasoner.hold = true
            try await start(fixture)
            try await waitUntil { fixture.reasoner.hasPending }
            let id = try XCTUnwrap(store.compareResults[.qwen]?.receipt?.requestID)
            XCTAssertFalse(store.confirmLessonHelped(provider: .qwen, requestID: id, snapshot: snapshot))
            switch cause {
            case "source": store.share(text: "A new document.", name: "new.txt")
            case "source-bytes": store.sharedText = "Unversioned source bytes."
            case "source-name": store.sourceName = "unversioned.txt"
            default: store.cancelWork()
            }
            fixture.reasoner.release()
            try await waitUntil { fixture.reasoner.returnedCount == 1 && !store.isWorking }
            XCTAssertFalse(store.confirmLessonHelped(provider: .qwen, requestID: id, snapshot: snapshot), cause)
            XCTAssertTrue(store.evolution.usefulReceipts.isEmpty, cause)
        }
    }

    @MainActor
    func testDifferentConversationInputsHaveDifferentBindingsAndOldAnswerCannotBeConfirmedAgain() async throws {
        let fixture = try fixture(sharedDocument: false)
        defer { clean(fixture) }
        let store = fixture.store, snapshot = try keepLesson(in: fixture.store)
        let firstLane = try await answer(fixture)
        let first = try XCTUnwrap(firstLane.receipt)
        XCTAssertTrue(store.confirmLessonHelped(provider: .qwen, requestID: first.requestID, snapshot: snapshot))
        store.prompt = "Help with meeting notes for a second decision."
        let secondLane = try await answer(fixture)
        let second = try XCTUnwrap(secondLane.receipt)
        XCTAssertNotEqual(first.inputDigest, second.inputDigest)
        XCTAssertNotEqual(EvolutionRequestBinding(receipt: first), EvolutionRequestBinding(receipt: second))
        XCTAssertFalse(store.confirmLessonHelped(provider: .qwen, requestID: first.requestID, snapshot: snapshot))
        XCTAssertTrue(store.confirmLessonHelped(provider: .qwen, requestID: second.requestID, snapshot: snapshot))
        XCTAssertEqual(store.evolution.usefulReceipts.count, 2)
        XCTAssertEqual(store.evolution.usefulReceipts.map(\.requestBinding),
            [EvolutionRequestBinding(receipt: first), EvolutionRequestBinding(receipt: second)])
    }

    @MainActor
    func testUncitedConversationAndCodexCannotQualifyALessonMilestone() async throws {
        let fixture = try fixture(sharedDocument: false)
        defer { clean(fixture) }
        let store = fixture.store, snapshot = try keepLesson(in: fixture.store)
        fixture.reasoner.citations = []
        try await start(fixture, route: .compare)
        try await waitUntil { !store.isWorking }
        let id = try XCTUnwrap(store.compareResults[.qwen]?.receipt?.requestID)
        XCTAssertFalse(store.confirmLessonHelped(provider: .qwen, requestID: id, snapshot: snapshot))
        XCTAssertFalse(store.confirmLessonHelped(provider: .codex, requestID: id, snapshot: snapshot))
        XCTAssertFalse(store.markReplyUsefulForEvolution(provider: .codex, requestID: id))
        XCTAssertTrue(store.markReplyUsefulForEvolution(provider: .qwen, requestID: id))
        XCTAssertNil(store.evolution.usefulReceipts.first?.lessonUse)
        XCTAssertTrue(store.kinGrowthEvidence.isEmpty)
    }

    @MainActor
    private func keepLesson(in store: CompanionStore, expiresAt: Date? = nil) throws -> LessonSnapshot {
        store.beginLessonCorrection()
        var draft = try XCTUnwrap(store.lessonDraft)
        draft.topic = "meeting notes"
        draft.text = "Start with the decision, then give two concrete next steps."
        draft.source = store.currentLessonSource
        draft.expiresAt = expiresAt
        XCTAssertTrue(store.keepLesson(draft))
        store.prompt = "Help organize these meeting notes."
        return try XCTUnwrap(store.matchingLessons(question: store.prompt).first)
    }

    @MainActor
    private func start(_ fixture: Fixture, route: AssistantRoute = .local) async throws {
        let store = fixture.store
        store.setAssistantRoute(route)
        for provider in route.providers where store.connection(for: provider) != .ready {
            store.connectAssistant(provider: provider)
        }
        try await waitUntil { route.providers.allSatisfy { store.connection(for: $0) == .ready } }
        store.submit()
        XCTAssertTrue(store.isWorking)
    }

    @MainActor
    private func answer(_ fixture: Fixture) async throws -> AssistantLaneResult {
        try await start(fixture)
        try await waitUntil { !fixture.store.isWorking }
        let lane = try XCTUnwrap(fixture.store.compareResults[.qwen])
        XCTAssertEqual(lane.state, .complete, lane.status)
        return lane
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Synthetic owned request did not reach its expected state")
        throw NSError(domain: "LessonDevelopmentIntegrationTests", code: 1)
    }

    @MainActor private struct Fixture {
        let directory: URL
        let preferenceURL: URL
        let clock: LessonDevelopmentClock
        let reasoner: LessonDevelopmentRoleClient
        let selector: LessonDevelopmentRoleClient
        let codex: LessonDevelopmentCodexClient
        let store: CompanionStore
    }

    @MainActor private func fixture(sharedDocument: Bool = true, personalKin: Bool = false) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-lesson-development-\(UUID())")
        let url = directory.appendingPathComponent("preferences.json")
        let clock = LessonDevelopmentClock(), reasoner = LessonDevelopmentRoleClient()
        let selector = LessonDevelopmentRoleClient(), codex = LessonDevelopmentCodexClient()
        let local = HamptonReasonsAssistant(reasoner: reasoner, contextSelector: selector)
        if personalKin {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let kin = LocalQiMon(character: .kin, originDigest: String(repeating: "a", count: 64), welcomedAt: clock.now)
            try NativePreferenceDocument(qiMon: kin).encoded().write(to: url)
        }
        let store = CompanionStore(preferenceURL: url, assistant: local,
            assistantFactory: { provider, _ in
                if provider == .qwen { return local }
                return codex
            }, wallClock: { clock.now }, allowsPlay: false)
        let origin = String(repeating: "a", count: 64)
        store.evolution.observeJourneyOrigin(origin)
        XCTAssertTrue(store.evolution.bindPracticeJourney(origin))
        if sharedDocument {
            store.share(text: "Synthetic meeting notes: agree on Cedar and identify the next steps.", name: "fixture.txt")
        }
        return Fixture(directory: directory, preferenceURL: url, clock: clock,
            reasoner: reasoner, selector: selector, codex: codex, store: store)
    }

    @MainActor private func reopen(_ fixture: Fixture) -> CompanionStore {
        let local = HamptonReasonsAssistant(reasoner: fixture.reasoner, contextSelector: fixture.selector)
        return CompanionStore(preferenceURL: fixture.preferenceURL, assistant: local,
            assistantFactory: { provider, _ in
                if provider == .qwen { return local }
                return fixture.codex
            }, wallClock: { fixture.clock.now }, allowsPlay: false)
    }

    @MainActor private func clean(_ fixture: Fixture) {
        fixture.store.cancelWork()
        fixture.reasoner.release()
        XCTAssertTrue(fixture.selector.requests.isEmpty, "Optional context stays off in these fixtures")
        try? FileManager.default.removeItem(at: fixture.directory)
    }
}

@MainActor private final class LessonDevelopmentClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

@MainActor private final class LessonDevelopmentCodexClient: AssistantClient {
    private(set) var requests: [AssistantRequest] = []
    func connect() async throws {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        requests.append(request)
        onEvent(.text("A synthetic independent Codex answer."))
    }
    func disconnect() {}
    func shutdown() async {}
}

@MainActor private final class LessonDevelopmentRoleClient: LocalRoleClient {
    private(set) var requests: [LocalRoleRequest] = []
    private(set) var returnedCount = 0
    var citations: [String]?
    var hold = false
    private var pending: CheckedContinuation<Void, Never>?
    var hasPending: Bool { pending != nil }
    func connect() async throws {}
    func disconnect() {}
    func release() {
        hold = false
        let continuation = pending
        pending = nil
        continuation?.resume()
    }
    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
        requests.append(request)
        // Capture before suspension, just as a provider receives immutable input.
        let ids = request.input["memories"]?.array?.compactMap { $0["id"]?.string } ?? []
        let capturedCitations = citations ?? Array(ids.prefix(3))
        if hold { await withCheckedContinuation { pending = $0 } }
        returnedCount += 1
        XCTAssertEqual(request.role, .reasoning)
        let output: JSONValue = .object([
            "requestID": .string(request.id), "schema": .string("archi-reason-proposal/v1"),
            "kind": .string("ANSWER"), "answer": .string("A checked synthetic local answer."),
            "uncertainty": .string(""), "sourceIDs": .array([]),
            "memoryIDs": .array(capturedCitations.map(JSONValue.string))
        ])
        return LocalRoleResult(requestID: request.id, role: request.role,
            text: String(decoding: try JSONEncoder().encode(output), as: UTF8.self),
            model: QwenModelMetadata(name: "lesson-development-fixture", family: "fixture", parameterSize: "fixture",
                quantization: "fixture", digest: String(repeating: "a", count: 64)), elapsedMilliseconds: 1)
    }
}
