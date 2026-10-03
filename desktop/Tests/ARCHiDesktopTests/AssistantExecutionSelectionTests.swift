import XCTest
@testable import ARCHiDesktop

final class AssistantExecutionSelectionTests: XCTestCase {
    func testOnlyUnpreparedExplicitCommandsSelectNativeExecution() {
        for command in ["/arc solve", "/arc propose", "/arc3 open", "/arc3 explore", "/arc3 stop"] {
            XCTAssertTrue(AssistantExecutionSelection.select(question: command,
                hasPreparedProcedure: false, hasPointing: false).isNativeCommand)
            XCTAssertEqual(AssistantExecutionSelection.select(question: command,
                hasPreparedProcedure: true, hasPointing: false), .assistant)
            XCTAssertEqual(AssistantExecutionSelection.select(question: command,
                hasPreparedProcedure: false, hasPointing: true), .assistant)
        }
        XCTAssertEqual(AssistantExecutionSelection.select(question: "Explain /arc solve to me",
            hasPreparedProcedure: false, hasPointing: false), .assistant)
    }

    @MainActor
    func testCallCeilingFollowsActualProtectedWorkPolicyWithoutModelCalls() async {
        let client = ExecutionSelectionNoCalls()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("execution-selection-\(UUID()).json")
        let store = CompanionStore(preferenceURL: url, assistant: client,
            assistantFactory: { _, _ in client }, allowsPlay: false)
        store.setAssistantRoute(.automatic)
        store.prompt = "Explain a complex idea."
        XCTAssertEqual(store.nextCallBudget, "1 local answer attempt · no external requests")
        store.prompt = "hello"
        XCTAssertTrue(store.nextCallBudget.hasPrefix("Up to 2 local answer attempts"))
        store.setLocalWorkPreference(.compact)
        store.share(text: "Synthetic protected material", name: "fixture.txt")
        XCTAssertEqual(store.nextLocalExpertDecision.target, .reasoning)
        XCTAssertEqual(store.nextCallBudget, "1 local answer attempt · no external requests")
        XCTAssertEqual(client.calls, 0)
        await store.shutdownAssistant()
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    func testInvalidCommandDoesNotDispatchAndOpenDoesNotAdvertiseGameplay() async {
        let client = ExecutionSelectionNoCalls()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("execution-invalid-\(UUID()).json")
        let store = CompanionStore(preferenceURL: url, assistant: client,
            assistantFactory: { _, _ in client }, allowsPlay: false)
        for command in ["/arc unknown", "/arc3 unknown"] {
            store.prompt = command
            XCTAssertTrue(store.nextCallBudget.contains("nothing executes"))
            store.submit()
            XCTAssertFalse(store.isWorking)
            XCTAssertEqual(client.calls, 0)
        }
        store.prompt = "/arc3 open"
        XCTAssertTrue(store.nextCallBudget.contains("no gameplay actions"))
        XCTAssertTrue(AssistantComposerState(store: store).sendDisclosure.contains("No gameplay"))
        store.prompt = "/arc3 explore"
        XCTAssertTrue(store.nextCallBudget.contains("up to 8"))
        // Inspect only; no ARC environment or puzzle is executed.
        await store.shutdownAssistant()
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    func testKeptReadingConflictIsVisibleBeforeSendAndDispatchStaysBlocked() async {
        let client = ExecutionSelectionNoCalls()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("execution-reading-\(UUID()).json")
        let store = CompanionStore(preferenceURL: url, assistant: client,
            assistantFactory: { _, _ in client }, allowsPlay: false)
        store.share(text: "Synthetic document", name: "fixture.txt")
        store.selectedReadingSourceIDs = [UUID().uuidString]
        store.prompt = "Explain this document."
        store.setAssistantRoute(.codex)
        let state = AssistantComposerState(store: store)
        XCTAssertFalse(state.canSend)
        XCTAssertTrue(state.blockedReason?.contains("Kept reading copies") == true)
        XCTAssertTrue(store.nextCallBudget.hasPrefix("0 model calls"))
        store.submit()
        XCTAssertEqual(client.calls, 0)
        XCTAssertFalse(store.isWorking)
        store.setAssistantRoute(.native)
        XCTAssertTrue(store.nextCallBudget.hasSuffix("no external requests"))
        XCTAssertTrue(AssistantComposerState(store: store).sendDisclosure.contains("fallback is disabled"))
        await store.shutdownAssistant()
        try? FileManager.default.removeItem(at: url)
    }
}

@MainActor
private final class ExecutionSelectionNoCalls: AssistantClient {
    var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.unavailable }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; throw AssistantFailure.unavailable
    }
    func disconnect() {}
}
