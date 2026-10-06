import XCTest
@testable import ARCHiDesktop

final class LessonStoreTests: XCTestCase {
    @MainActor
    func testOnlyReviewedKeepWritesAndReopensTheSameLesson() throws {
        let fixture = LessonStoreFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        var draft = try review(store)
        store.lessonDraft = draft
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.url.path))
        store.lessonDraft = nil
        XCTAssertTrue(store.keptLessons.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.url.path))

        draft.reason = "Use the reviewed launch terminology."
        store.lessonDraft = draft
        XCTAssertTrue(store.keepLesson(draft))
        let kept = try XCTUnwrap(store.keptLessons.first)
        XCTAssertEqual(store.lessonRevision, 1)
        XCTAssertEqual(kept.topic, draft.topic)
        XCTAssertEqual(kept.text, draft.text)
        XCTAssertEqual(kept.reason, draft.reason)
        XCTAssertEqual(kept.createdAt, fixture.clock.now)
        XCTAssertNil(store.lessonDraft)
        let saved = try NativePreferencePersistence.read(fixture.url).document
        XCTAssertEqual(saved.lessons, [kept])
        XCTAssertNil(saved.preferences)

        let reopened = CompanionStore(preferenceURL: fixture.url, assistant: LessonStoreClient(),
            wallClock: { fixture.clock.now })
        defer { reopened.disconnectAssistant() }
        XCTAssertEqual(reopened.keptLessons, [kept])
        XCTAssertEqual(reopened.lessonRevision, saved.revision)
        XCTAssertEqual(reopened.matchingLessons(question: "Prepare the launch review."), [LessonSnapshot(lesson: kept)])
        XCTAssertTrue(reopened.matchingLessons(question: "Prepare lunch.").isEmpty)
    }

    @MainActor
    func testStoreMatchingUsesQuestionPhraseExactSharedCopyAndExpiry() throws {
        let fixture = LessonStoreFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.share(text: "The café launch review is Friday.", name: "launch.txt")
        var draft = try review(store, topic: "café launch")
        draft.source = store.currentLessonSource
        draft.expiresAt = fixture.clock.now.addingTimeInterval(60)
        XCTAssertTrue(store.keepLesson(draft))
        let snapshot = store.keptLessons.map(LessonSnapshot.init(lesson:))
        XCTAssertEqual(store.matchingLessons(question: "Explain CAFE—LAUNCH."), snapshot)
        XCTAssertTrue(store.matchingLessons(question: "Explain cafés launches.").isEmpty)
        XCTAssertTrue(store.matchingLessons(question: "Explain this source.").isEmpty,
                      "A phrase in shared text alone must not select a lesson")
        store.share(text: "The café launch review is Thursday.", name: "launch.txt")
        XCTAssertTrue(store.matchingLessons(question: "Explain café launch.").isEmpty)
        store.share(text: "The café launch review is Friday.", name: "renamed.txt")
        XCTAssertTrue(store.matchingLessons(question: "Explain café launch.").isEmpty)
        store.share(text: "The café launch review is Friday.", name: "launch.txt")
        XCTAssertEqual(store.matchingLessons(question: "Explain café launch."), snapshot)
        fixture.clock.now = fixture.clock.now.addingTimeInterval(60)
        XCTAssertTrue(store.matchingLessons(question: "Explain café launch.").isEmpty)
        XCTAssertEqual(store.keptLessons.count, 1, "Expiry makes a kept lesson inactive without silently deleting it")
    }

    @MainActor
    func testStaleRevisionPriorValueAndChangedSourceRejectTheReviewedDraft() throws {
        let fixture = LessonStoreFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        XCTAssertTrue(store.keepLesson(try review(store)))
        let original = try XCTUnwrap(store.keptLessons.first)
        store.beginLessonCorrection(revisingID: original.id)
        var stale = try XCTUnwrap(store.lessonDraft)
        stale.text = "Use the revised review terminology."
        XCTAssertTrue(store.keepLesson(try review(store, topic: "daily notes")))
        let bytes = try Data(contentsOf: fixture.url), revision = store.lessonRevision
        XCTAssertFalse(store.keepLesson(stale))
        XCTAssertFalse(store.withdrawLesson(id: original.id, expectedRevision: stale.expectedRevision))
        var falsePrior = original
        falsePrior.text = "An unreviewed replacement."
        let forged = LessonCorrectionDraft(lessonID: original.id, expectedRevision: revision,
            prior: falsePrior, topic: original.topic, text: "Try a replacement.", reason: "Test prior-value guard.")
        XCTAssertFalse(store.keepLesson(forged))
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
        XCTAssertEqual(store.lessonRevision, revision)
        XCTAssertEqual(store.keptLessons.first, original)

        store.share(text: "Reviewed copy.", name: "review.txt")
        var scoped = try review(store, topic: "reviewed copy")
        scoped.source = store.currentLessonSource
        store.share(text: "Changed copy.", name: "review.txt")
        XCTAssertFalse(store.keepLesson(scoped))
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
    }

    @MainActor
    func testUnreadableInitialFileAndUnavailableParentDoNotPublishOrOverwrite() throws {
        let fixture = LessonStoreFixture()
        defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
        let invalid = Data("{ preserved but invalid".utf8)
        try invalid.write(to: fixture.url)
        let blocked = CompanionStore(preferenceURL: fixture.url, assistant: LessonStoreClient())
        defer { blocked.disconnectAssistant() }
        let draft = try review(blocked)
        blocked.lessonDraft = draft
        XCTAssertFalse(blocked.keepLesson(draft))
        XCTAssertEqual(blocked.lessonDraft, draft)
        XCTAssertTrue(blocked.keptLessons.isEmpty)
        XCTAssertEqual(blocked.lessonRevision, 0)
        XCTAssertEqual(try Data(contentsOf: fixture.url), invalid)

        let parentFile = fixture.directory.appendingPathComponent("occupied")
        let parentBytes = Data("Existing parent is a file".utf8)
        try parentBytes.write(to: parentFile)
        let unavailable = CompanionStore(preferenceURL: parentFile.appendingPathComponent("preferences.json"),
            assistant: LessonStoreClient())
        defer { unavailable.disconnectAssistant() }
        XCTAssertFalse(unavailable.keepLesson(try review(unavailable)))
        XCTAssertTrue(unavailable.keptLessons.isEmpty)
        XCTAssertEqual(unavailable.lessonRevision, 0)
        XCTAssertEqual(try Data(contentsOf: parentFile), parentBytes)
    }

    @MainActor
    func testLessonChangesPreserveSavedAppearanceAndAppearanceForgetPreservesLessons() throws {
        let fixture = LessonStoreFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.rememberPreferences = true
        store.preferences.tone = "Warm"
        store.savePreferences()
        let savedAppearance = store.preferences
        store.preferences.tone = "Direct"
        XCTAssertTrue(store.keepLesson(try review(store)))
        var saved = try NativePreferencePersistence.read(fixture.url).document
        XCTAssertEqual(saved.preferences, savedAppearance, "Keep must not save unrelated unsaved appearance choices")
        XCTAssertEqual(saved.lessons, store.keptLessons)
        store.savePreferences()
        saved = try NativePreferencePersistence.read(fixture.url).document
        XCTAssertEqual(saved.preferences, store.preferences)
        XCTAssertEqual(saved.lessons, store.keptLessons)
        let exported = try NativePreferenceDocument.decode(store.lessonExportData())
        XCTAssertNil(exported.preferences)
        XCTAssertEqual(exported.lessons, saved.lessons)
        store.forgetPreferences()
        saved = try NativePreferencePersistence.read(fixture.url).document
        XCTAssertNil(saved.preferences)
        XCTAssertEqual(saved.lessons, exported.lessons)
        XCTAssertFalse(store.rememberPreferences)
        let lesson = try XCTUnwrap(store.keptLessons.first)
        XCTAssertTrue(store.withdrawLesson(id: lesson.id, expectedRevision: store.lessonRevision))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.url.path))
        XCTAssertTrue(store.keptLessons.isEmpty)
    }

    @MainActor
    func testAcceptedReplyNeverAutomaticallyKeepsAndOnlyLocalLaneReceivesKeptSnapshot() async throws {
        let fixture = LessonStoreFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.prompt = "Prepare the launch review."
        try await connect(store)
        store.submit()
        try await waitUntil { !store.isWorking }
        XCTAssertEqual(store.compareResults[.qwen]?.state, .complete)
        XCTAssertNil(store.stewardMessage, fixture.diagnostics)
        XCTAssertEqual(store.tokenSteward.tasks.last?.lanes.first?.state, "complete")
        XCTAssertTrue(store.keptLessons.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.url.path))
        store.beginLessonCorrection(for: .qwen)
        var draft = try XCTUnwrap(store.lessonDraft)
        XCTAssertNotNil(draft.origin)
        XCTAssertEqual(draft.text, "", "A model answer is not an automatically reviewed lesson")
        draft.topic = "launch review"; draft.text = "Use the approved launch name."; draft.reason = "Reviewed correction."
        XCTAssertTrue(store.keepLesson(draft))
        let offered = store.keptLessons.map(LessonSnapshot.init(lesson:))
        store.setAssistantRoute(.codex)
        XCTAssertTrue(store.nextReplyLessons.isEmpty)
        XCTAssertEqual(store.matchingLessons(question: store.prompt), offered)
        store.setAssistantRoute(.compare)
        XCTAssertEqual(store.nextReplyLessons, offered)
        try await connect(store)
        store.submit()
        try await waitUntil { !store.isWorking }
        let cloudRequest = try XCTUnwrap(fixture.cloud.requests.last, fixture.diagnostics)
        let local = try XCTUnwrap(store.compareResults[.qwen]?.receipt)
        let cloud = try XCTUnwrap(store.compareResults[.codex]?.receipt)
        XCTAssertTrue(cloudRequest.localLessons.isEmpty)
        XCTAssertNil(cloudRequest.localLessonDigest)
        XCTAssertFalse(cloudRequest.input.contains(draft.text))
        XCTAssertEqual(local.inputDigest, cloud.inputDigest)
        XCTAssertEqual(local.localLessons, offered)
        XCTAssertNotNil(local.localLessonDigest)
        XCTAssertEqual(local.usedLessonIDs, offered.map(\.modelID))
        XCTAssertTrue(cloud.localLessons.isEmpty)
        XCTAssertNil(cloud.localLessonDigest)
        XCTAssertEqual(fixture.rig.reasoner.requests.last?.input["memories"]?.array, offered.map(\.modelInput))
        XCTAssertEqual(store.keptLessons.count, 1)
    }

    @MainActor func testWithdrawCancelsCapturedLocalLessonAndClearsContextButCodexFinishes() async throws {
        try await checkPendingMutation(.withdraw)
    }

    @MainActor func testRevisionCancelsCapturedLocalLessonAndClearsContextButCodexFinishes() async throws {
        try await checkPendingMutation(.revise)
    }

    @MainActor func testFailedWritePreservesStateButExternalChangeRevokesLateLocalAnswer() async throws {
        try await checkPendingMutation(.failWrite)
    }

    @MainActor func testNewKeepDoesNotChangeAnAlreadyCapturedAnswer() async throws {
        try await checkPendingMutation(.newKeep)
    }

    @MainActor
    func testRevokingCompletedCompareAnswerClearsEveryLocalAnswerSurfaceAndRetainsCodex() async throws {
        for revise in [false, true] {
          for relevant in [false, true] {
            let fixture = LessonStoreFixture()
            defer { fixture.cleanUp() }
            let store = fixture.store
            XCTAssertTrue(store.keepLesson(try review(store)))
            let original = try XCTUnwrap(store.keptLessons.first)
            store.setAssistantRoute(.compare)
            store.prompt = relevant ? "Prepare the launch review." : "What is two plus two?"
            try await connect(store)
            store.submit()
            try await waitUntil { !store.isWorking }
            XCTAssertEqual(store.compareResults[.qwen]?.state, .complete)
            XCTAssertEqual(store.compareResults[.codex]?.state, .complete)
            XCTAssertEqual(store.reply, "Local fixture answer")
            let cloud = store.compareResults[.codex]
            if revise {
                store.beginLessonCorrection(revisingID: original.id)
                var draft = try XCTUnwrap(store.lessonDraft)
                draft.text = "Use the newly reviewed launch name."
                XCTAssertTrue(store.keepLesson(draft))
            } else {
                XCTAssertTrue(store.withdrawLesson(id: original.id, expectedRevision: store.lessonRevision))
            }
            if relevant { XCTAssertNil(store.compareResults[.qwen]) }
            else { XCTAssertEqual(store.compareResults[.qwen]?.text, "") }
            XCTAssertNil(store.hamptonSnapshot.proposal)
            XCTAssertNotEqual(store.reply, "Local fixture answer", "A completed local answer must leave the shared reply surface too")
            XCTAssertEqual(store.compareResults[.codex]?.text, cloud?.text)
            XCTAssertEqual(store.compareResults[.codex]?.receipt, cloud?.receipt)
            XCTAssertEqual(store.connection(for: .codex), .ready)
          }
        }
    }

    @MainActor
    func testPreflightFailureLabelsLessonsPreparedRatherThanUsed() async throws {
        let fixture = LessonStoreFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        XCTAssertTrue(store.keepLesson(try review(store)))
        // Document reading now selects bounded passages, so a large shared file
        // does not force the mandatory model envelope over budget. Escaping this
        // valid-size question does, without depending on passage selection.
        store.prompt = "Prepare the launch review. " + String(repeating: "\"", count: 11_000)
        XCTAssertLessThanOrEqual(store.prompt.utf8.count, 16_000)
        let input = AssistantRequest(prompt: store.prompt, sourceName: nil, sourceText: "",
            sourceRevision: store.sourceRevision, placementRevision: 0, settings: store.nextReplySettings,
            localLessons: store.nextReplyLessons)
        XCTAssertFalse(HamptonReasonsAssistant.fitsMandatoryReasoningInput(input))
        try await connect(store)
        store.submit()
        try await waitUntil { !store.isWorking }
        let receipt = try XCTUnwrap(store.compareResults[.qwen]?.receipt)
        let lesson = try XCTUnwrap(receipt.localLessons.first)
        XCTAssertTrue(receipt.requestStarted)
        XCTAssertEqual(receipt.localInvocations, [])
        XCTAssertTrue(receipt.lessonDeliveryDescription(for: lesson).hasPrefix("Prepared"))
        XCTAssertTrue(receipt.usedLessonIDs.isEmpty)
        XCTAssertTrue(fixture.rig.reasoner.requests.isEmpty)
        XCTAssertTrue(fixture.rig.selector.requests.isEmpty)
    }

    private enum Mutation { case withdraw, revise, failWrite, newKeep }

    @MainActor
    private func checkPendingMutation(_ mutation: Mutation) async throws {
        let fixture = LessonStoreFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        XCTAssertTrue(store.keepLesson(try review(store)))
        let original = try XCTUnwrap(store.keptLessons.first)
        store.setSessionContextEnabled(true)
        store.share(text: "One. Two.", name: "notes.txt")
        store.prompt = "Keep the explanation brief."
        try await connect(store)
        store.submit()
        try await waitUntil { !store.isWorking }
        XCTAssertFalse(store.hamptonSnapshot.records.isEmpty)
        XCTAssertNil(store.stewardMessage, fixture.diagnostics)
        XCTAssertEqual(store.tokenSteward.tasks.last?.lanes.first?.state, "complete")
        store.setAssistantRoute(.compare)
        try await connect(store)
        fixture.rig.reasoner.hold = true; fixture.cloud.hold = true
        store.prompt = "Prepare the launch review."
        store.submit()
        try await waitUntil(diagnostics: { fixture.diagnostics }) {
            !fixture.rig.reasoner.pendingIndices.isEmpty && fixture.cloud.isPending
        }
        let pending = try XCTUnwrap(fixture.rig.reasoner.pendingIndices.first)
        let oldCallback = try XCTUnwrap(fixture.rig.assistant.onSnapshot)
        let before = store.hamptonSnapshot, revision = store.lessonRevision
        let localReceipt = try XCTUnwrap(store.compareResults[.qwen]?.receipt)
        XCTAssertEqual(localReceipt.localLessons, [LessonSnapshot(lesson: original)])
        let cloudDisconnects = fixture.cloud.disconnectCount
        let localDisconnects = fixture.rig.reasoner.disconnectCount
        let cancels = mutation == .withdraw || mutation == .revise

        switch mutation {
        case .withdraw:
            XCTAssertTrue(store.withdrawLesson(id: original.id, expectedRevision: revision))
            XCTAssertTrue(store.keptLessons.isEmpty)
        case .revise:
            store.beginLessonCorrection(revisingID: original.id)
            var draft = try XCTUnwrap(store.lessonDraft)
            draft.text = "Use the newer reviewed launch name."
            XCTAssertTrue(store.keepLesson(draft))
            XCTAssertEqual(store.keptLessons.first?.revision, original.revision + 1)
        case .failWrite:
            store.beginLessonCorrection(revisingID: original.id)
            var draft = try XCTUnwrap(store.lessonDraft)
            draft.text = "This revision cannot be saved."
            store.lessonDraft = draft
            var outsideBytes = try Data(contentsOf: fixture.url)
            outsideBytes.append(Data("\n ".utf8))
            try outsideBytes.write(to: fixture.url)
            XCTAssertFalse(store.keepLesson(draft))
            XCTAssertEqual(try Data(contentsOf: fixture.url), outsideBytes)
            XCTAssertEqual(store.keptLessons, [original])
            XCTAssertEqual(store.lessonRevision, revision)
            XCTAssertEqual(store.lessonDraft, draft)
        case .newKeep:
            XCTAssertTrue(store.keepLesson(try review(store, topic: "launch review", text: "A second reviewed detail.")))
            XCTAssertEqual(store.keptLessons.count, 2)
        }

        XCTAssertTrue(store.isWorking, "The independent Codex lane remains owned")
        XCTAssertTrue(fixture.cloud.isPending)
        XCTAssertEqual(store.compareResults[.codex]?.state, .pending)
        XCTAssertEqual(store.connection(for: .codex), .ready)
        XCTAssertEqual(fixture.cloud.disconnectCount, cloudDisconnects)
        XCTAssertTrue(fixture.cloud.requests.last?.localLessons.isEmpty == true)
        if cancels {
            XCTAssertTrue(store.hamptonSnapshot.records.isEmpty)
            XCTAssertNil(store.compareResults[.qwen])
            XCTAssertGreaterThan(fixture.rig.reasoner.disconnectCount, localDisconnects)
            oldCallback(before)
            XCTAssertTrue(store.hamptonSnapshot.records.isEmpty, "An obsolete callback must not restore revoked context")
        } else {
            XCTAssertEqual(store.hamptonSnapshot, before)
            XCTAssertEqual(store.compareResults[.qwen]?.state, .pending)
            XCTAssertEqual(store.compareResults[.qwen]?.receipt?.localLessons, localReceipt.localLessons)
            XCTAssertEqual(fixture.rig.reasoner.disconnectCount, localDisconnects)
        }
        fixture.rig.reasoner.resolve(pending)
        try await waitUntil { fixture.rig.reasoner.finished.contains(pending) }
        fixture.cloud.resolve()
        try await waitUntil { !store.isWorking }
        XCTAssertEqual(store.compareResults[.codex]?.state, .complete)
        XCTAssertEqual(store.compareResults[.codex]?.text, "Codex fixture answer")
        if cancels {
            oldCallback(before)
            XCTAssertNil(store.compareResults[.qwen])
            XCTAssertTrue(store.hamptonSnapshot.records.isEmpty)
            XCTAssertNil(store.hamptonSnapshot.proposal)
        } else if mutation == .failWrite {
            // The failed save itself preserves the draft, bytes and pending
            // context above. Its external-writer conflict separately makes the
            // captured local memory stale when the delayed answer arrives.
            XCTAssertEqual(store.compareResults[.qwen]?.state, .cancelled)
            XCTAssertEqual(store.compareResults[.qwen]?.text, "")
            XCTAssertNotEqual(store.reply, "Local fixture answer")
            oldCallback(before)
            XCTAssertTrue(store.hamptonSnapshot.records.isEmpty)
            XCTAssertNil(store.hamptonSnapshot.proposal)
            XCTAssertEqual(store.keptLessons, [original])
            XCTAssertEqual(store.lessonRevision, revision)
            XCTAssertEqual(store.lessonDraft?.text, "This revision cannot be saved.")
            XCTAssertEqual(store.compareResults[.qwen]?.receipt?.localLessons, [LessonSnapshot(lesson: original)])
        } else {
            XCTAssertEqual(store.compareResults[.qwen]?.state, .complete)
            XCTAssertEqual(store.compareResults[.qwen]?.receipt?.localLessons, [LessonSnapshot(lesson: original)])
        }
    }

    @MainActor
    private func review(_ store: CompanionStore, topic: String = "launch review",
                        text: String = "Use the approved launch name.") throws -> LessonCorrectionDraft {
        store.beginLessonCorrection()
        var draft = try XCTUnwrap(store.lessonDraft)
        draft.topic = topic; draft.text = text; draft.reason = "Reviewed correction."
        return draft
    }

    @MainActor private func connect(_ store: CompanionStore) async throws {
        store.connectAssistant()
        try await waitUntil { store.route.providers.allSatisfy { store.connection(for: $0) == .ready } }
    }

    @MainActor
    private func waitUntil(file: StaticString = #filePath, line: UInt = #line,
                           diagnostics: @MainActor () -> String = { "" },
                           _ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("The deterministic fixture did not finish. \(diagnostics())", file: file, line: line)
        throw LessonStoreTestFailure.waitTimedOut
    }
}

private enum LessonStoreTestFailure: Error { case waitTimedOut }

@MainActor private final class LessonStoreClock {
    var now = Date(timeIntervalSince1970: 1_788_700_000)
}

@MainActor private final class LessonStoreFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ARCHi-LessonStore-\(UUID().uuidString)")
    var url: URL { directory.appendingPathComponent("preferences.json") }
    let clock = LessonStoreClock()
    let rig = LessonStoreRig()
    let cloud = LessonStoreClient()
    lazy var store = CompanionStore(preferenceURL: url, assistant: rig.assistant,
        assistantFactory: { [cloud] _, _ in cloud }, wallClock: { [clock] in clock.now })
    var diagnostics: String {
        "route=\(store.route.rawValue); status=\(store.status); blocked=\(store.nextAssistantBlockedReason ?? "none"); "
            + "usage=\(store.stewardMessage ?? "none"); local=\(String(describing: store.compareResults[.qwen]?.state)); "
            + "codex=\(String(describing: store.compareResults[.codex]?.state)); "
            + "reasonerRequests=\(rig.reasoner.requests.count); cloudRequests=\(cloud.requests.count)"
    }
    func cleanUp() {
        store.disconnectAssistant(); rig.drain(); cloud.drain()
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor private final class LessonStoreRig {
    let reasoner = LessonStoreRoleClient(), selector = LessonStoreRoleClient()
    let assistant: HamptonReasonsAssistant
    init() {
        assistant = HamptonReasonsAssistant(model: QwenAssistant.defaultModel,
            contextModel: HamptonReasonsAssistant.defaultContextModel, reasoner: reasoner, contextSelector: selector)
    }
    func drain() { reasoner.drain(); selector.drain() }
}

@MainActor private final class LessonStoreClient: AssistantClient {
    private(set) var requests: [AssistantRequest] = []
    private(set) var disconnectCount = 0
    var hold = false
    private var pending: CheckedContinuation<Void, any Error>?
    var isPending: Bool { pending != nil }
    func connect() async throws {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        requests.append(request)
        if hold { try await withCheckedThrowingContinuation { pending = $0 } }
        onEvent(.text("Codex fixture answer"))
    }
    func disconnect() { disconnectCount += 1 }
    func resolve() { let saved = pending; pending = nil; saved?.resume() }
    func drain() { let saved = pending; pending = nil; saved?.resume(throwing: AssistantFailure.stopped) }
}

/// Deliberately lets a held valid response arrive after disconnect, requiring
/// production lane ownership and Hampton generations to reject late results.
@MainActor private final class LessonStoreRoleClient: LocalRoleClient {
    var hold = false
    private(set) var requests: [LocalRoleRequest] = []
    private(set) var finished = Set<Int>()
    private(set) var disconnectCount = 0
    private var pending: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var draining = false
    var pendingIndices: Set<Int> { Set(pending.keys) }
    func connect() async throws {}
    func disconnect() { disconnectCount += 1 }
    func shutdown() async { disconnect() }
    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
        let index = requests.count
        requests.append(request)
        defer { finished.insert(index) }
        guard !draining else { throw QwenFailure.stopped }
        if hold { try await withCheckedThrowingContinuation { pending[index] = $0 } }
        var payload: [String: JSONValue] = ["requestID": .string(request.id)]
        switch request.role {
        case .memorySelection:
            payload["schema"] = .string("archi-session-selection/v1")
            let ids = request.input["candidates"]?.array?.prefix(1).compactMap { $0["id"]?.string } ?? []
            payload["candidateIDs"] = .array(ids.map(JSONValue.string))
        case .memoryReminder:
            payload["schema"] = .string("archi-session-reminder/v1")
            payload["decision"] = .string("NONE"); payload["memoryIDs"] = .array([])
        case .reasoning:
            payload["schema"] = .string("archi-reason-proposal/v1")
            payload["kind"] = .string("ANSWER"); payload["answer"] = .string("Local fixture answer")
            payload["uncertainty"] = .string(""); payload["sourceIDs"] = .array([])
            let ids = request.input["memories"]?.array?.compactMap { $0["id"]?.string } ?? []
            payload["memoryIDs"] = .array(ids.map(JSONValue.string))
        }
        let text = String(decoding: try JSONEncoder().encode(JSONValue.object(payload)), as: UTF8.self)
        return LocalRoleResult(requestID: request.id, role: request.role, text: text,
            model: QwenModelMetadata(name: "lesson-store-fixture", family: "qwen", parameterSize: "fixture",
                // Synthetic artifact identity must obey the same hash contract
                // as real metadata or usage cannot close before the next send.
                quantization: "fixture", digest: String(repeating: "f", count: 64)), elapsedMilliseconds: 0)
    }
    func resolve(_ index: Int) { pending.removeValue(forKey: index)?.resume() }
    func drain() {
        draining = true
        let saved = Array(pending.values); pending.removeAll()
        saved.forEach { $0.resume(throwing: QwenFailure.stopped) }
    }
}
