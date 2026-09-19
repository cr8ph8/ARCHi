import XCTest
@testable import ARCHiDesktop

final class AutomaticAssistantRoutingTests: XCTestCase {
    @MainActor
    func testNativePreparationChecksLocalReadinessWithoutInferenceOrFallback() async throws {
        for result in [Result<Void, any Error>.success(()), .failure(QwenFailure.unavailable)] {
            let f = AutomaticRoutingFixture(), store = f.store
            defer { f.drain() }
            store.prompt = "An unsent draft must stay unsent."
            store.prepareNativeAssistant()
            store.prepareNativeAssistant()
            XCTAssertEqual(store.route, .native)
            try await wait("Native preparation checks Qwen once") { f.local.connectCount == 1 }
            XCTAssertFalse(store.isWorking)
            f.local.resolveConnection(0, result: result)
            try await wait("Native readiness check finishes") { store.connection(for: .qwen) != .connecting }
            XCTAssertEqual(f.local.connectCount, 1)
            XCTAssertTrue(f.local.replies.isEmpty)
            XCTAssertEqual(f.cloud.connectCount, 0)
            XCTAssertTrue(f.cloud.replies.isEmpty)
            XCTAssertTrue(store.compareResults.isEmpty)
            XCTAssertEqual(store.prompt, "An unsent draft must stay unsent.")
        }
    }

    @MainActor
    func testNativeLocalSuccessNeverConnectsOrSendsToCodex() async throws {
        let f = AutomaticRoutingFixture(), store = f.store
        defer { f.drain() }
        store.prepareNativeAssistant()
        try await wait("Native preparation connects Qwen") { f.local.connectCount == 1 }
        f.local.resolveConnection(0)
        try await wait("Native Qwen is ready") { store.connection(for: .qwen) == .ready }
        store.prompt = "Help arrange this local task."
        store.submit()
        try await wait("Native Send uses prepared Qwen") { f.local.replies.count == 1 }
        f.local.emit(0, text: "A completed local answer.")
        f.local.resolveReply(0)
        try await wait("Native answer completes") { !store.isWorking }
        XCTAssertEqual(store.reply, "A completed local answer.")
        XCTAssertEqual(store.compareResults[.qwen]?.receipt?.route, .native)
        XCTAssertEqual(store.compareResults[.qwen]?.state, .complete)
        XCTAssertEqual(store.assistantProvider, .qwen)
        XCTAssertEqual(f.local.connectCount, 1)
        XCTAssertEqual(f.cloud.connectCount, 0)
        XCTAssertTrue(f.cloud.replies.isEmpty)
        XCTAssertNil(store.compareResults[.codex])
    }

    @MainActor
    func testNativeUnavailableConnectFallsBackOnceWithLocalContextRemoved() async throws {
        let f = AutomaticRoutingFixture(), store = f.store
        defer { f.drain() }
        store.share(text: "First. Café is the selected passage.", name: "source.txt")
        store.selectText(range: NSRange(location: 7, length: 4), sourceRevision: store.sourceRevision)
        store.beginLessonCorrection()
        var lesson = try XCTUnwrap(store.lessonDraft)
        lesson.topic = "selected passage"
        lesson.text = "PRIVATE-LESSON: Prefer a brief explanation."
        lesson.source = store.currentLessonSource
        XCTAssertTrue(store.keepLesson(lesson), store.lessonMessage)
        let profile = PersonalContext(name: "Synthetic Person", preferredName: "Synthetic", entries: [
            .init(id: UUID().uuidString, title: "Working style", text: "PRIVATE-PROFILE: Start with a checklist.",
                  status: .confirmed, source: "Synthetic user preference", useInAssistance: true)
        ])
        XCTAssertTrue(store.updatePersonalContext(profile, expected: nil))
        store.setAssistantRoute(.native)
        store.prompt = "Explain the selected passage."
        store.submit()
        try await wait("Seed conversation connects locally") { f.local.connectCount == 1 }
        f.local.resolveConnection(0)
        try await wait("Seed conversation starts locally") { f.local.replies.count == 1 }
        let first = f.local.replies[0].request
        XCTAssertEqual(first.localLessons.count, 1)
        XCTAssertNotNil(first.localProfile)
        f.local.emit(0, text: "PRIVATE-CONVERSATION: Here is the earlier local answer.")
        f.local.resolveReply(0)
        try await wait("Local conversation is retained") { !store.isWorking && store.localConversation.exchanges.count == 1 }

        store.disconnectAssistant(provider: .qwen)
        store.prompt = "Explain the selected passage once more."
        let settings = store.nextReplySettings
        store.submit()
        try await wait("Native follow-up reconnects locally") { f.local.connectCount == 2 }
        let localReceipt = try XCTUnwrap(store.compareResults[.qwen]?.receipt)
        XCTAssertEqual(localReceipt.localLessons.count, 1)
        XCTAssertEqual(localReceipt.localConversationCount, 1)
        XCTAssertNotNil(localReceipt.localProfileDigest)
        f.local.resolveConnection(1, result: .failure(QwenFailure.unavailable))
        try await wait("Unavailable local service starts one Codex fallback") { f.cloud.connectCount == 1 }
        XCTAssertTrue(f.cloud.replies.isEmpty, "Account connection precedes any external prompt")
        f.cloud.resolveConnection(0)
        try await wait("Fallback starts its external request") { f.cloud.replies.count == 1 }
        let external = f.cloud.replies[0].request
        XCTAssertEqual(external.prompt, "Explain the selected passage once more.")
        XCTAssertEqual(external.sourceName, first.sourceName)
        XCTAssertEqual(external.sourceText, first.sourceText)
        XCTAssertEqual(external.sourceRevision, first.sourceRevision)
        XCTAssertEqual(external.selection, first.selection)
        XCTAssertEqual(external.settings, settings)
        XCTAssertTrue(external.localLessons.isEmpty)
        XCTAssertNil(external.localLessonDigest)
        XCTAssertTrue(external.localConversation.isEmpty)
        XCTAssertNil(external.localConversationDigest)
        XCTAssertNil(external.localProfile)
        for marker in ["PRIVATE-LESSON", "PRIVATE-PROFILE", "PRIVATE-CONVERSATION"] {
            XCTAssertFalse(external.codexInput.contains(marker), marker)
        }
        let externalReceipt = try XCTUnwrap(store.compareResults[.codex]?.receipt)
        XCTAssertEqual(externalReceipt.route, .native)
        XCTAssertEqual(externalReceipt.requestID, localReceipt.requestID)
        XCTAssertEqual(externalReceipt.localConversationCount, 0)
        XCTAssertNil(externalReceipt.localProfileDigest)
        XCTAssertTrue(externalReceipt.localLessons.isEmpty)
        f.cloud.emit(0, text: "The completed fallback answer.")
        f.cloud.resolveReply(0)
        try await wait("Native fallback completes") { !store.isWorking }
        XCTAssertEqual(store.reply, "The completed fallback answer.")
        XCTAssertEqual(store.compareResults[.qwen]?.state, .failed)
        XCTAssertEqual(store.compareResults[.codex]?.state, .complete)
        XCTAssertEqual(f.local.replies.count, 1)
        XCTAssertEqual(f.cloud.connectCount, 1)
        XCTAssertEqual(f.cloud.replies.count, 1)
    }

    @MainActor
    func testNativeCodexFailureIsTerminalWithoutLocalRetryOrSecondFallback() async throws {
        for stage in ["connect", "reply"] {
            let f = AutomaticRoutingFixture(), store = f.store
            defer { f.drain() }
            store.setAssistantRoute(.native)
            store.prompt = "Attempt one bounded fallback."
            store.submit()
            try await wait("Native request starts Qwen") { f.local.connectCount == 1 }
            f.local.resolveConnection(0, result: .failure(QwenFailure.unavailable))
            try await wait("Codex fallback connects") { f.cloud.connectCount == 1 }
            if stage == "connect" {
                f.cloud.resolveConnection(0, result: .failure(AssistantFailure.unavailable))
            } else {
                f.cloud.resolveConnection(0)
                try await wait("Codex fallback starts reply") { f.cloud.replies.count == 1 }
                f.cloud.emit(0, text: "Incomplete external reply")
                f.cloud.resolveReply(0, result: .failure(AssistantFailure.timedOut))
            }
            try await wait("Failed fallback ends the request") { !store.isWorking }
            await Task.yield()
            XCTAssertEqual(store.compareResults[.qwen]?.state, .failed, stage)
            XCTAssertEqual(store.compareResults[.codex]?.state, .failed, stage)
            XCTAssertEqual(store.compareResults[.codex]?.text, "", stage)
            XCTAssertEqual(f.local.connectCount, 1, stage)
            XCTAssertTrue(f.local.replies.isEmpty, stage)
            XCTAssertEqual(f.cloud.connectCount, 1, stage)
            XCTAssertEqual(f.cloud.replies.count, stage == "connect" ? 0 : 1, stage)
        }
    }

    @MainActor
    func testNativeStoppedInvalidAndOversizedRequestsNeverFallBack() async throws {
        for error in [QwenFailure.stopped, .invalidResponse, .contextLimit] {
            for stage in ["connect", "reply"] {
                let f = AutomaticRoutingFixture(), store = f.store
                defer { f.drain() }
                store.setAssistantRoute(.native)
                store.prompt = "A rejected request stays local."
                store.submit()
                try await wait("Native request starts Qwen") { f.local.connectCount == 1 }
                if stage == "connect" {
                    f.local.resolveConnection(0, result: .failure(error))
                } else {
                    f.local.resolveConnection(0)
                    try await wait("Native local reply starts") { f.local.replies.count == 1 }
                    f.local.emit(0, text: "Unaccepted local text")
                    f.local.resolveReply(0, result: .failure(error))
                }
                try await wait("Rejected native request finishes") { !store.isWorking }
                XCTAssertEqual(f.cloud.connectCount, 0, "\(stage): \(error)")
                XCTAssertTrue(f.cloud.replies.isEmpty, "\(stage): \(error)")
                XCTAssertNil(store.compareResults[.codex], "\(stage): \(error)")
                XCTAssertEqual(store.compareResults[.qwen]?.text, "")
            }
        }
    }

    @MainActor
    func testNativeContextAndRouteChangesRejectLateLocalFailuresWithoutFallback() async throws {
        for change in ["context", "route"] {
            for stage in ["connect", "reply"] {
                let f = AutomaticRoutingFixture(), store = f.store
                defer { f.drain() }
                store.setAssistantRoute(.native)
                store.prompt = "Cancel this before considering fallback."
                store.submit()
                try await wait("Native local connection starts") { f.local.connectCount == 1 }
                if stage == "reply" {
                    f.local.resolveConnection(0)
                    try await wait("Native local reply starts") { f.local.replies.count == 1 }
                }
                if change == "context" { store.clearSessionContext() }
                else { store.setAssistantRoute(.automatic) }
                XCTAssertFalse(store.isWorking)
                let reply = store.reply, status = store.status, results = store.compareResults
                if stage == "connect" {
                    f.local.resolveConnection(0, result: .failure(QwenFailure.unavailable))
                    try await wait("Late native connection failure drains") { f.local.finishedConnections.contains(0) }
                } else {
                    f.local.emit(0, text: "Stale local callback")
                    f.local.resolveReply(0, result: .failure(QwenFailure.timedOut))
                    try await wait("Late native reply failure drains") { f.local.finishedReplies.contains(0) }
                }
                await Task.yield()
                XCTAssertEqual(store.reply, reply, "\(change): \(stage)")
                XCTAssertEqual(store.status, status, "\(change): \(stage)")
                XCTAssertEqual(store.compareResults, results, "\(change): \(stage)")
                XCTAssertEqual(f.cloud.connectCount, 0, "\(change): \(stage)")
                XCTAssertTrue(f.cloud.replies.isEmpty, "\(change): \(stage)")
                XCTAssertFalse(store.isWorking)
            }
        }
    }

    @MainActor
    func testNativeContextChangeCancelsPendingFallbackAndRejectsLateCloudConnection() async throws {
        let f = AutomaticRoutingFixture(), store = f.store
        defer { f.drain() }
        store.setAssistantRoute(.native)
        store.prompt = "Cancel the pending fallback."
        store.submit()
        try await wait("Native local connection starts") { f.local.connectCount == 1 }
        f.local.resolveConnection(0, result: .failure(QwenFailure.unavailable))
        try await wait("Fallback connection is pending") { f.cloud.connectCount == 1 }
        store.clearSessionContext()
        XCTAssertFalse(store.isWorking)
        let reply = store.reply, results = store.compareResults
        f.cloud.resolveConnection(0)
        try await wait("Cancelled fallback connection drains") { f.cloud.finishedConnections.contains(0) }
        await Task.yield()
        XCTAssertTrue(f.cloud.replies.isEmpty)
        XCTAssertEqual(store.reply, reply)
        XCTAssertEqual(store.compareResults, results)
        XCTAssertFalse(store.isWorking)
    }

    @MainActor
    func testManualRoutesStillRequireExplicitReadyConnections() async throws {
        for route in [AssistantRoute.local, .codex, .compare] {
            let f = AutomaticRoutingFixture(), store = f.store
            defer { f.drain() }
            store.setAssistantRoute(route)
            store.prompt = "Do not connect a manual route implicitly."
            store.submit()
            await Task.yield()
            XCTAssertFalse(store.isWorking, route.rawValue)
            XCTAssertEqual(f.local.connectCount, 0, route.rawValue)
            XCTAssertEqual(f.cloud.connectCount, 0, route.rawValue)
            XCTAssertTrue(f.local.replies.isEmpty, route.rawValue)
            XCTAssertTrue(f.cloud.replies.isEmpty, route.rawValue)
        }
    }

    @MainActor
    func testAutomaticSelectionDoesNoWorkAndSuccessfulLocalSendNeverContactsCodex() async throws {
        let f = AutomaticRoutingFixture(), store = f.store
        defer { f.drain() }
        store.setAssistantRoute(.automatic)
        await Task.yield()
        XCTAssertEqual(f.local.connectCount, 0)
        XCTAssertEqual(f.cloud.connectCount, 0)
        XCTAssertTrue(f.local.replies.isEmpty)
        XCTAssertTrue(f.cloud.replies.isEmpty)

        store.prompt = "Help arrange a short local task."
        store.submit()
        // A manual Connect in the same run-loop turn cannot steal the automatic
        // lane's connection epoch and strand its work owner.
        store.connectAssistant(provider: .qwen)
        try await wait("Automatic Send connects locally") { f.local.connectCount == 1 }
        XCTAssertTrue(store.isWorking)
        XCTAssertEqual(store.assistantActivity, .working)
        XCTAssertTrue(f.local.replies.isEmpty)
        XCTAssertEqual(store.compareResults[.qwen]?.receipt?.requestStarted, false)
        f.local.resolveConnection(0)
        try await wait("Connected local request starts") { f.local.replies.count == 1 }
        f.local.emit(0, text: "The local answer.")
        f.local.resolveReply(0)
        try await wait("Local success finishes Automatic") { !store.isWorking }
        XCTAssertEqual(store.reply, "The local answer.")
        XCTAssertEqual(store.assistantActivity, .ready)
        let receipt = try XCTUnwrap(store.compareResults[.qwen]?.receipt)
        XCTAssertEqual(receipt.route, .automatic)
        XCTAssertEqual(receipt.state, .complete)
        XCTAssertNotNil(receipt.routingReason)
        XCTAssertEqual(f.cloud.connectCount, 0)
        XCTAssertTrue(f.cloud.replies.isEmpty)

        store.prompt = "A second local task."
        store.submit()
        try await wait("Next Automatic Send reuses the ready local connection") { f.local.replies.count == 2 }
        XCTAssertEqual(f.local.connectCount, 1)
        XCTAssertEqual(f.cloud.connectCount, 0)
        XCTAssertTrue(f.cloud.replies.isEmpty)
    }

    @MainActor
    func testDefaultRemainsQwenAndAutoConnectBudgetHasNoExternalRequest() {
        let f = AutomaticRoutingFixture(), store = f.store
        defer { f.drain() }
        XCTAssertEqual(store.route, .local)
        XCTAssertEqual(store.assistantProvider, .qwen)
        store.setAssistantRoute(.automatic)
        XCTAssertEqual(store.resultProviders, [.qwen])
        XCTAssertEqual(store.nextCallBudget, "1 local answer call · no external requests")
        store.setSessionContextEnabled(true)
        XCTAssertEqual(store.nextCallBudget, "1 local answer call, plus up to 2 context calls · no external requests")
    }

    @MainActor
    func testEveryLocalConnectionAndReplyFailureStaysLocal() async throws {
        let failures: [any Error] = [QwenFailure.unavailable, QwenFailure.unsupportedModel,
            QwenFailure.modelUnavailable, QwenFailure.nonLocalModel, QwenFailure.modelChanged,
            QwenFailure.invalidResponse, QwenFailure.contextLimit, QwenFailure.outputLimit,
            QwenFailure.timedOut, QwenFailure.stopped, QwenFailure.generationFailed, QwenFailure.busy,
            HamptonAssistantFailure.contextLimit, HamptonAssistantFailure.invalidProposal,
            HamptonAssistantFailure.timedOut, AssistantFailure.protocolError,
            AssistantFailure.stopped, CancellationError(), AutomaticRoutingTestFailure.unexpected]
        for error in failures {
            for stage in ["connect", "reply"] {
                let f = AutomaticRoutingFixture(), store = f.store
                defer { f.drain() }
                store.setAssistantRoute(.automatic)
                store.prompt = "This failure must not share my work externally."
                store.submit()
                try await wait("Local attempt begins") { f.local.connectCount == 1 }
                if stage == "connect" {
                    f.local.resolveConnection(0, result: .failure(error))
                } else {
                    f.local.resolveConnection(0)
                    try await wait("Local reply begins") { f.local.replies.count == 1 }
                    f.local.emit(0, text: "PRIVATE partial response")
                    f.local.resolveReply(0, result: .failure(error))
                }
                try await wait("Failure ends the local request") { !store.isWorking }
                await Task.yield()
                XCTAssertEqual(f.cloud.connectCount, 0, "\(stage): \(error)")
                XCTAssertTrue(f.cloud.replies.isEmpty, "\(stage): \(error)")
                XCTAssertNil(store.compareResults[.codex], "\(stage): \(error)")
                XCTAssertEqual(store.compareResults[.qwen]?.state, .failed)
                XCTAssertEqual(store.compareResults[.qwen]?.text, "")
                XCTAssertEqual(store.assistantProvider, .qwen)
                XCTAssertEqual(store.assistantActivity, .failed)
                XCTAssertEqual(f.local.connectCount, 1)
            }
        }
    }

    @MainActor
    func testRejectedOrMissingRevisionNeverStartsAnExternalRequest() async throws {
        for emitsUnvalidatedText in [false, true] {
            let f = AutomaticRoutingFixture(), store = f.store
            defer { f.drain() }
            store.share(text: "Keep this original passage.", name: "revision.txt")
            store.selectText(range: NSRange(location: 0, length: 26), sourceRevision: store.sourceRevision)
            store.requestsRevision = true
            try await beginLocal(f, question: "Make this passage shorter.")
            XCTAssertNotNil(f.local.replies[0].request.revisionTarget)
            if emitsUnvalidatedText { f.local.emit(0, text: "This is not a validated revision proposal.") }
            f.local.resolveReply(0)
            try await wait("Invalid revision ends locally") { !store.isWorking }
            await Task.yield()
            XCTAssertEqual(store.compareResults[.qwen]?.state, .failed)
            XCTAssertNil(store.compareResults[.qwen]?.revision)
            XCTAssertEqual(store.sharedText, "Keep this original passage.")
            XCTAssertEqual(f.cloud.connectCount, 0)
            XCTAssertTrue(f.cloud.replies.isEmpty)
            XCTAssertNil(store.compareResults[.codex])
        }
    }

    @MainActor
    func testLocalFailureNeverUsesAnAlreadyReadyCodexConnection() async throws {
        let f = AutomaticRoutingFixture(), store = f.store
        defer { f.drain() }
        store.connectAssistant(provider: .codex)
        try await wait("Explicit external connection starts") { f.cloud.connectCount == 1 }
        f.cloud.resolveConnection(0)
        try await wait("External connection is ready") { store.connection(for: .codex) == .ready }
        try await beginLocal(f)
        f.local.resolveReply(0, result: .failure(QwenFailure.timedOut))
        try await wait("Local failure finishes") { !store.isWorking }
        XCTAssertEqual(f.cloud.connectCount, 1)
        XCTAssertTrue(f.cloud.replies.isEmpty)
        XCTAssertNil(store.compareResults[.codex])
        XCTAssertEqual(store.connection(for: .codex), .ready)
    }

    @MainActor
    func testExplicitExternalSendAfterFailureCapturesCurrentChoiceWithoutPrivateContext() async throws {
        let f = AutomaticRoutingFixture(), store = f.store
        defer { f.drain() }
        store.share(text: "First. Café is the selected passage.", name: "original.txt")
        store.placed(at: CGPoint(x: -90, y: 320))
        store.selectText(range: NSRange(location: 7, length: 4), sourceRevision: store.sourceRevision)
        store.beginLessonCorrection()
        var draft = try XCTUnwrap(store.lessonDraft)
        draft.topic = "selected passage"
        draft.text = "LOCAL-ONLY-LESSON: Prefer a short explanation."
        draft.source = store.currentLessonSource
        XCTAssertTrue(store.keepLesson(draft), store.lessonMessage)
        store.preferences.tone = "Warm"
        store.evolution.confirmRole(.muse)
        store.evolution.confirmHelpStyle(.stepByStep)
        try await beginLocal(f, question: "Explain the selected passage.")
        let firstRequest = f.local.replies[0].request
        XCTAssertEqual(firstRequest.localLessons.count, 1)
        let originalReceipt = try XCTUnwrap(store.compareResults[.qwen]?.receipt)
        f.local.emit(0, text: "PRIVATE-LOCAL-PARTIAL")
        store.prompt = "Give a second opinion on the selected passage."
        store.preferences.tone = "Direct"
        store.evolution.confirmRole(.beacon)
        store.evolution.confirmHelpStyle(.concise)
        f.local.resolveReply(0, result: .failure(QwenFailure.invalidResponse))
        try await wait("Failed local request ends") { !store.isWorking }
        XCTAssertEqual(store.compareResults[.qwen]?.receipt?.settings, firstRequest.settings)
        XCTAssertEqual(f.cloud.connectCount, 0)
        XCTAssertTrue(f.cloud.replies.isEmpty)

        store.setAssistantRoute(.codex)
        await Task.yield()
        XCTAssertEqual(f.cloud.connectCount, 0, "Choosing a reference route sends nothing")
        XCTAssertTrue(f.cloud.replies.isEmpty)
        store.connectAssistant(provider: .codex)
        try await wait("Explicit reference connection starts") { f.cloud.connectCount == 1 }
        f.cloud.resolveConnection(0)
        try await wait("Reference connection is ready") { store.connection(for: .codex) == .ready }
        XCTAssertTrue(f.cloud.replies.isEmpty, "Connection is not Send")
        let selectedSettings = store.nextReplySettings
        store.submit()
        try await wait("Explicit Send starts the reference request") { f.cloud.replies.count == 1 }
        let reference = f.cloud.replies[0].request
        XCTAssertEqual(reference.prompt, "Give a second opinion on the selected passage.")
        XCTAssertEqual(reference.settings, selectedSettings)
        XCTAssertNotEqual(reference.settings, firstRequest.settings)
        XCTAssertEqual(reference.sourceText, firstRequest.sourceText)
        XCTAssertEqual(reference.selection, firstRequest.selection)
        XCTAssertTrue(reference.localLessons.isEmpty)
        XCTAssertNil(reference.localLessonDigest)
        XCTAssertFalse(reference.codexInput.contains("LOCAL-ONLY-LESSON"))
        XCTAssertFalse(reference.codexInput.contains("PRIVATE-LOCAL-PARTIAL"))
        let receipt = try XCTUnwrap(store.compareResults[.codex]?.receipt)
        XCTAssertEqual(receipt.route, .codex)
        XCTAssertNotEqual(receipt.requestID, originalReceipt.requestID)
        XCTAssertNotEqual(receipt.inputDigest, originalReceipt.inputDigest)
        f.cloud.emit(0, text: "The requested external reference.")
        f.cloud.resolveReply(0)
        try await wait("Reference finishes") { !store.isWorking }
        XCTAssertEqual(store.reply, "The requested external reference.")
        f.local.emit(0, text: "Late local callback")
        await Task.yield()
        XCTAssertEqual(store.reply, "The requested external reference.")
        XCTAssertEqual(f.cloud.replies.count, 1)
    }

    @MainActor
    func testStopDuringLocalConnectionRejectsLateSuccessAndFailure() async throws {
        for lateResult in [Result<Void, any Error>.success(()), .failure(QwenFailure.unavailable)] {
            let f = AutomaticRoutingFixture(), store = f.store
            defer { f.drain() }
            store.setAssistantRoute(.automatic)
            store.prompt = "Stop before any inference."
            store.submit()
            try await wait("Local connection pending") { f.local.connectCount == 1 }
            store.cancelWork()
            XCTAssertFalse(store.isWorking)
            let reply = store.reply, status = store.status, results = store.compareResults
            f.local.resolveConnection(0, result: lateResult)
            try await wait("Late connection callback drained") { f.local.finishedConnections.contains(0) }
            await Task.yield()
            XCTAssertTrue(f.local.replies.isEmpty)
            XCTAssertEqual(f.cloud.connectCount, 0)
            XCTAssertTrue(f.cloud.replies.isEmpty)
            XCTAssertEqual(store.reply, reply)
            XCTAssertEqual(store.status, status)
            XCTAssertEqual(store.compareResults, results)
            XCTAssertFalse(store.isWorking)
        }
    }

    @MainActor
    func testLocalReplyInvalidationPreventsStaleReplyOrExternalRequest() async throws {
        for change in ["stop", "source", "placement", "selection", "route", "model", "context model", "clear context", "disable context"] {
            let f = AutomaticRoutingFixture(), store = f.store
            defer { f.drain() }
            store.share(text: "First. Second.", name: "source.txt")
            store.setSessionContextEnabled(true)
            try await beginLocal(f)
            f.local.emit(0, text: "An obsolete local partial.")
            switch change {
            case "stop": store.cancelWork()
            case "source": store.share(text: "New shared source.", name: "new.txt")
            case "placement": store.placed(at: CGPoint(x: 700, y: -120))
            case "selection": store.selectText(range: NSRange(location: 0, length: 6), sourceRevision: store.sourceRevision)
            case "route": store.setAssistantRoute(.local)
            case "model": store.selectQwenModel(try XCTUnwrap(QwenAssistant.supportedModels.first { $0 != store.qwenModel }))
            case "context model": store.selectQwenContextModel(try XCTUnwrap(QwenAssistant.supportedModels.first { $0 != store.qwenContextModel }))
            case "clear context": store.clearSessionContext()
            default: store.setSessionContextEnabled(false)
            }
            XCTAssertFalse(store.isWorking, change)
            let reply = store.reply, status = store.status, results = store.compareResults
            f.local.emit(0, text: "Stale local text.")
            f.local.resolveReply(0, result: .failure(QwenFailure.generationFailed))
            try await wait("Invalidated reply callback drains") { f.local.finishedReplies.contains(0) }
            await Task.yield()
            XCTAssertEqual(f.cloud.connectCount, 0, change)
            XCTAssertTrue(f.cloud.replies.isEmpty, change)
            XCTAssertEqual(store.reply, reply, change)
            XCTAssertEqual(store.status, status, change)
            XCTAssertEqual(store.compareResults, results, change)
            XCTAssertFalse(store.isWorking, change)
        }
    }

    @MainActor
    func testLocalFailureCanRetryLocallyWithoutExternalCalls() async throws {
        let f = AutomaticRoutingFixture(), store = f.store
        defer { f.drain() }
        try await beginLocal(f)
        f.local.resolveReply(0, result: .failure(QwenFailure.generationFailed))
        try await wait("First local attempt ends") { !store.isWorking }
        store.prompt = "A shorter local retry."
        store.submit()
        try await wait("Local retry reconnects") { f.local.connectCount == 2 }
        f.local.resolveConnection(1)
        try await wait("Retry starts locally") { f.local.replies.count == 2 }
        f.local.emit(1, text: "The retry succeeded locally.")
        f.local.resolveReply(1)
        try await wait("Local retry finishes") { !store.isWorking }
        XCTAssertEqual(store.reply, "The retry succeeded locally.")
        XCTAssertEqual(f.cloud.connectCount, 0)
        XCTAssertTrue(f.cloud.replies.isEmpty)
    }

    @MainActor
    private func beginLocal(_ fixture: AutomaticRoutingFixture, question: String = "A bounded Automatic task.") async throws {
        fixture.store.setAssistantRoute(.automatic)
        fixture.store.prompt = question
        fixture.store.submit()
        try await wait("Automatic connects Qwen") { fixture.local.connectCount == 1 }
        fixture.local.resolveConnection(0)
        try await wait("Automatic starts local inference") { fixture.local.replies.count == 1 }
    }

    @MainActor
    private func wait(_ message: String, file: StaticString = #filePath, line: UInt = #line,
                      _ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail(message, file: file, line: line)
        throw AutomaticRoutingTestFailure.waitTimedOut
    }
}

private enum AutomaticRoutingTestFailure: Error { case waitTimedOut, unexpected }

@MainActor
private final class AutomaticRoutingFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ARCHi-AutomaticRouting-\(UUID().uuidString)")
    let local = AutomaticRoutingClient()
    let factory = AutomaticRoutingFactory()
    var cloud: AutomaticRoutingClient { factory.cloud }
    lazy var store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"),
        assistant: local, provider: .qwen,
        assistantFactory: { [factory] provider, model in factory.make(provider, model) })

    func drain() {
        store.cancelWork()
        store.disconnectAssistant(provider: .qwen)
        store.disconnectAssistant(provider: .codex)
        local.drain(); cloud.drain(); factory.replacements.forEach { $0.drain() }
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class AutomaticRoutingFactory {
    let cloud = AutomaticRoutingClient()
    private(set) var replacements: [AutomaticRoutingClient] = []
    func make(_ provider: AssistantProvider, _ model: String) -> AutomaticRoutingClient {
        if provider == .codex { return cloud }
        let client = AutomaticRoutingClient(); replacements.append(client); return client
    }
}

/// Deliberately delivers callbacks after cancellation. The production request
/// owner, not a cooperative mock transport, must prevent stale callbacks and external work.
@MainActor
private final class AutomaticRoutingClient: AssistantClient {
    struct Reply {
        let request: AssistantRequest
        let onEvent: @MainActor (AssistantEvent) -> Void
    }
    private(set) var connectCount = 0
    private(set) var replies: [Reply] = []
    private(set) var finishedConnections = Set<Int>()
    private(set) var finishedReplies = Set<Int>()
    private var connections: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var answers: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var draining = false

    func connect() async throws {
        let index = connectCount; connectCount += 1
        defer { finishedConnections.insert(index) }
        guard !draining else { throw AssistantFailure.stopped }
        try await withCheckedThrowingContinuation { connections[index] = $0 }
    }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        let index = replies.count; replies.append(Reply(request: request, onEvent: onEvent))
        defer { finishedReplies.insert(index) }
        guard !draining else { throw AssistantFailure.stopped }
        try await withCheckedThrowingContinuation { answers[index] = $0 }
    }
    func disconnect() {}
    func shutdown() async { disconnect() }
    func emit(_ index: Int, text: String) { replies[index].onEvent(.text(text)) }
    func resolveConnection(_ index: Int, result: Result<Void, any Error> = .success(())) {
        guard let continuation = connections.removeValue(forKey: index) else { XCTFail("No pending connection"); return }
        continuation.resume(with: result)
    }
    func resolveReply(_ index: Int, result: Result<Void, any Error> = .success(())) {
        guard let continuation = answers.removeValue(forKey: index) else { XCTFail("No pending reply"); return }
        continuation.resume(with: result)
    }
    func drain() {
        draining = true
        let pending = Array(connections.values) + Array(answers.values)
        connections.removeAll(); answers.removeAll()
        pending.forEach { $0.resume(throwing: AssistantFailure.stopped) }
    }
}
