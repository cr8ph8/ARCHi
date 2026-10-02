import Darwin
import Foundation
import Testing
@testable import ARCHiDesktop

/// These tests launch only this local Python fixture. They never invoke Codex,
/// access an account, contact a network, or request model generation.
@MainActor
struct CodexTransportTests {
    private var request: AssistantRequest {
        AssistantRequest(prompt: "When is the launch?", sourceName: "fixture.txt",
                         sourceText: "The launch is Friday.", sourceRevision: 3,
                         placementRevision: 8, tone: "Calm", replyLength: 0.25, role: .scout, helpStyle: .exploratory)
    }

    private func revisionRequest() throws -> AssistantRequest {
        let source = request
        let selection = try #require(DocumentSelection(range: NSRange(location: 0, length: source.sourceText.utf16.count),
            text: source.sourceText, sourceRevision: source.sourceRevision))
        let target = try #require(RevisionTarget(text: source.sourceText, sourceRevision: source.sourceRevision, selection: selection))
        let lesson = LessonSnapshot(id: UUID().uuidString, revision: 1, topic: "launch", text: "Private local guidance.")
        return AssistantRequest(prompt: "Make this concise.", sourceName: source.sourceName, sourceText: source.sourceText,
            sourceRevision: source.sourceRevision, placementRevision: source.placementRevision, settings: source.settings,
            selection: selection, localLessons: [lesson], revisionTarget: target)
    }

    @Test func revisionBuffersJSONAndValidatesOneFinalProposalWithoutSendingLocalLessons() async throws {
        let fixture = try CodexProcessFixture(mode: "revision_valid")
        defer { fixture.cleanup() }
        let client = CodexAssistant(executable: fixture.executable), request = try revisionRequest()
        do {
            try await client.connect()
            var proposals: [PassageRevisionProposal] = [], texts: [String] = []
            try await client.reply(to: request) { event in
                switch event { case .text(let text): texts.append(text); case .revision(let proposal): proposals.append(proposal) }
            }
            #expect(texts.isEmpty)
            #expect(proposals.count == 1)
            #expect(proposals.first?.target == request.revisionTarget)
            #expect(proposals.first?.replacement == "Launch: Friday.")
            let turn = try #require(fixture.requests.first { $0["method"]?.string == "turn/start" })
            let raw = try #require(turn["params"]?["input"]?.array?.first?["text"]?.string)
            let sent = try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
            #expect(sent["task"] == .string("revise"))
            #expect(sent["revisionTarget"] == request.revisionTarget?.input)
            #expect(sent["memories"] == nil)
            #expect(!raw.contains("Private local guidance."))
            #expect(sent["outputSchema"]?["properties"]?["memoryIDs"]?["maxItems"] == .number(0))
            #expect(turn["params"]?["outputSchema"] == nil, "The existing transport does not assume schema support")
            let start = try #require(fixture.requests.first { $0["method"]?.string == "thread/start" })
            #expect(start["params"]?["baseInstructions"] == .string(AssistantInstructions.passageRevisionText))
            #expect(start["params"]?["dynamicTools"] == .array([]))
            await client.shutdown()
            #expect(fixture.livePIDs.isEmpty)
        } catch { await client.shutdown(); throw error }
    }

    @Test(arguments: ["revision_malformed", "revision_wrong_target", "revision_unknown_memory"])
    func invalidRevisionNeverPublishesAnyResponse(_ mode: String) async throws {
        let fixture = try CodexProcessFixture(mode: mode)
        defer { fixture.cleanup() }
        let client = CodexAssistant(executable: fixture.executable), request = try revisionRequest()
        do {
            try await client.connect()
            await #expect(throws: AssistantFailure.self) {
                try await client.reply(to: request) { _ in Issue.record("Invalid revision escaped validation") }
            }
            await client.shutdown()
            #expect(fixture.livePIDs.isEmpty)
        } catch { await client.shutdown(); throw error }
    }

    @Test func cancelledRevisionCannotPublishBufferedPartialJSON() async throws {
        let fixture = try CodexProcessFixture(mode: "revision_hold")
        defer { fixture.cleanup() }
        let client = CodexAssistant(executable: fixture.executable), request = try revisionRequest()
        try await client.connect()
        let task = Task { try await client.reply(to: request) { _ in Issue.record("A held revision published an event") } }
        do {
            for _ in 0..<100 {
                if fixture.events.contains(where: { $0["event"]?.string == "revision_partial" }) { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(fixture.events.contains { $0["event"]?.string == "revision_partial" })
            client.disconnect()
            await #expect(throws: AssistantFailure.self) { try await task.value }
            await client.shutdown()
            #expect(fixture.livePIDs.isEmpty)
        } catch { task.cancel(); await client.shutdown(); throw error }
    }

    @Test func bufferedEventsBeforeTurnAcknowledgementProduceFinalAnswer() async throws {
        let fixture = try CodexProcessFixture(mode: "early_events")
        defer { fixture.cleanup() }
        let client = CodexAssistant(executable: fixture.executable)
        var snapshots: [String] = []
        var emittedBeforeAcknowledgement = false
        do {
            try await client.connect()
            #expect(client.configurationChecks.values.allSatisfy { $0 })
            #expect(!fixture.requests.contains { $0["method"]?.string == "turn/start" })
            try await client.reply(to: request) { event in
                if case .text(let text) = event {
                    snapshots.append(text)
                    if !fixture.events.contains(where: { $0["event"]?.string == "turn_ack" }) { emittedBeforeAcknowledgement = true }
                }
            }
            #expect(!emittedBeforeAcknowledgement)
            #expect(snapshots.last == "The launch is Friday.")
            #expect(!snapshots.contains("Late commentary"))
            let turns = fixture.requests.filter { $0["method"]?.string == "turn/start" }
            #expect(turns.count == 1)
            #expect(turns.first?["params"]?["input"]?.array?.count == 1)
            #expect(turns.first?["params"]?["input"]?.array?.first?["type"]?.string == "text")
            let sent = try #require(turns.first?["params"]?["input"]?.array?.first?["text"]?.string)
            let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(sent.utf8))
            #expect(decoded["question"]?.string == request.prompt)
            #expect(decoded["source"]?["text"]?.string == request.sourceText)
            #expect(decoded["role"]?.string == "scout")
            #expect(decoded["helpStyle"]?.string == "exploratory")
            #expect(fixture.requests.contains { $0["method"]?.string == "thread/unsubscribe" })
            // The first config has an inherited server; the second process must
            // receive its explicit disabled setting before preflight succeeds.
            #expect(fixture.events.filter { $0["event"]?.string == "started" }.count == 2)
            await client.shutdown()
            #expect(fixture.livePIDs.isEmpty)
        } catch {
            await client.shutdown()
            throw error
        }
    }

    @Test(arguments: ["provider_drift", "durable_thread", "cwd_drift", "roots_drift", "network_drift", "instructions_drift"])
    func rejectedThreadConfigurationNeverReceivesDocument(_ mode: String) async throws {
        let fixture = try CodexProcessFixture(mode: mode)
        defer { fixture.cleanup() }
        let client = CodexAssistant(executable: fixture.executable)
        do {
            try await client.connect()
            var rejected = false
            do { try await client.reply(to: request) { _ in Issue.record("Rejected thread published assistant text") } }
            catch AssistantFailure.configuration { rejected = true }
            #expect(rejected)
            #expect(fixture.requests.filter { $0["method"]?.string == "thread/start" }.count == 1)
            #expect(!fixture.requests.contains { $0["method"]?.string == "turn/start" })
            await client.shutdown()
            #expect(fixture.livePIDs.isEmpty)
        } catch {
            await client.shutdown()
            throw error
        }
    }

    @Test(arguments: ["duplicate_thread_key", "escaped_duplicate_thread_key"])
    func ambiguousThreadConfigurationNeverReceivesDocument(_ mode: String) async throws {
        let fixture = try CodexProcessFixture(mode: mode)
        defer { fixture.cleanup() }
        let client = CodexAssistant(executable: fixture.executable)
        do {
            try await client.connect()
            await #expect(throws: AssistantFailure.protocolError) {
                try await client.reply(to: request) { _ in Issue.record("Ambiguous configuration published a response") }
            }
            #expect(!fixture.requests.contains { $0["method"]?.string == "turn/start" },
                    "Reject duplicate security fields before sending the document")
            await client.shutdown()
            #expect(fixture.livePIDs.isEmpty)
        } catch { await client.shutdown(); throw error }
    }

    @Test func ambiguousConfigurationResponseCannotCompletePreflight() async throws {
        let fixture = try CodexProcessFixture(mode: "duplicate_config_result")
        defer { fixture.cleanup() }
        let client = CodexAssistant(executable: fixture.executable)
        await #expect(throws: AssistantFailure.protocolError) { try await client.connect() }
        #expect(!fixture.requests.contains { $0["method"]?.string == "thread/start" })
        #expect(!fixture.requests.contains { $0["method"]?.string == "turn/start" })
        await client.shutdown()
        #expect(fixture.livePIDs.isEmpty)
    }

    @Test func shutdownWaitsForChildrenThatIgnoreTermination() async throws {
        let fixture = try CodexProcessFixture(mode: "ignore_term")
        defer { fixture.cleanup() }
        let client = CodexAssistant(executable: fixture.executable)
        do {
            try await client.connect()
            let started = fixture.events.filter { $0["event"]?.string == "started" }
            #expect(started.count == 2)
            #expect(!fixture.livePIDs.isEmpty)
            let directories = started.compactMap { $0["cwd"]?.string }
            await client.shutdown()
            #expect(fixture.events.contains { $0["event"]?.string == "ignored_sigterm" })
            #expect(fixture.livePIDs.isEmpty)
            #expect(directories.allSatisfy { !FileManager.default.fileExists(atPath: $0) })
            #expect(!fixture.requests.contains { $0["method"]?.string == "turn/start" })
        } catch {
            await client.shutdown()
            throw error
        }
    }

    @Test func aSecondReplyCannotStartWhileTheFirstThreadIsBeingCreated() async throws {
        let fixture = try CodexProcessFixture(mode: "delayed_thread")
        defer { fixture.cleanup() }
        let client = CodexAssistant(executable: fixture.executable)
        try await client.connect()
        let first = Task { try await client.reply(to: request) { _ in } }
        do {
            for _ in 0..<100 {
                if fixture.requests.contains(where: { $0["method"]?.string == "thread/start" }) { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(fixture.requests.contains { $0["method"]?.string == "thread/start" })
            var refused = false
            do { try await client.reply(to: request) { _ in Issue.record("Second reply published") } }
            catch AssistantFailure.unavailable { refused = true }
            #expect(refused)
            try await first.value
            #expect(fixture.requests.filter { $0["method"]?.string == "turn/start" }.count == 1)
            await client.shutdown()
        } catch { await client.shutdown(); _ = try? await first.value; throw error }
    }

    @Test func cancelledOldReplyCannotDisconnectAReplacementConnection() async throws {
        let fixture = try CodexProcessFixture(mode: "delayed_thread")
        defer { fixture.cleanup() }
        let client = CodexAssistant(executable: fixture.executable)
        try await client.connect()
        let first = Task { try await client.reply(to: request) { _ in Issue.record("Cancelled reply published") } }
        do {
            for _ in 0..<100 {
                if fixture.requests.contains(where: { $0["method"]?.string == "thread/start" }) { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(fixture.requests.contains { $0["method"]?.string == "thread/start" })
            client.disconnect()
            try await client.connect()
            do { try await first.value; Issue.record("Old reply should have stopped") }
            catch AssistantFailure.stopped { }
            var result = ""
            try await client.reply(to: request) { if case .text(let text) = $0 { result = text } }
            #expect(result == "The launch is Friday.")
            #expect(fixture.requests.filter { $0["method"]?.string == "turn/start" }.count == 1)
            await client.shutdown()
        } catch { await client.shutdown(); _ = try? await first.value; throw error }
    }
}

@MainActor
private final class CodexProcessFixture {
    let directory: URL
    let executable: URL
    private let log: URL

    init(mode: String) throws {
        let paths = ["/usr/bin/python3"] + (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map { String($0) + "/python3" }
        let python = try #require(paths.first { FileManager.default.isExecutableFile(atPath: $0) }, "Python 3 is required for the local stdio fixture")
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-transport-fixture-\(UUID().uuidString)")
        executable = directory.appendingPathComponent("fixture.py")
        log = directory.appendingPathComponent("events.jsonl")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(["mode": mode]).write(to: directory.appendingPathComponent("fixture.json"))
        try ("#!\(python)\n" + Self.script).write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }

    var events: [JSONValue] {
        guard let data = try? Data(contentsOf: log) else { return [] }
        return data.split(separator: 10).compactMap { try? JSONDecoder().decode(JSONValue.self, from: Data($0)) }
    }

    var requests: [JSONValue] { events.compactMap { $0["request"] } }

    var livePIDs: [Int32] {
        events.filter { $0["event"]?.string == "started" }.compactMap { event in
            guard case .number(let value) = event["pid"], value > 0, value < Double(Int32.max) else { return nil }
            let pid = Int32(value)
            return Darwin.kill(pid, 0) == 0 ? pid : nil
        }
    }

    func cleanup() {
        // A fixture-specific file releases only our Python processes if a test
        // fails. Never signal an old numeric PID that might have been reused.
        try? Data().write(to: directory.appendingPathComponent("cleanup.request"))
        let deadline = Date().addingTimeInterval(2)
        while !livePIDs.isEmpty && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if livePIDs.isEmpty { try? FileManager.default.removeItem(at: directory) }
    }

    private static let script = #"""
import json, os, pathlib, signal, sys, threading, time

root = pathlib.Path(__file__).parent
mode = json.loads((root / "fixture.json").read_text())["mode"]
log_path = root / "events.jsonl"

def record(value):
    payload = (json.dumps(value, separators=(",", ":")) + "\n").encode("utf-8")
    fd = os.open(str(log_path), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.write(fd, payload)
    finally:
        os.close(fd)

def cleanup_watch():
    while True:
        if (root / "cleanup.request").exists():
            os._exit(0)
        time.sleep(0.02)

threading.Thread(target=cleanup_watch, daemon=True).start()

if mode == "ignore_term":
    def ignore_term(signum, frame):
        record({"event": "ignored_sigterm", "pid": os.getpid()})
    signal.signal(signal.SIGTERM, ignore_term)

record({"event": "started", "pid": os.getpid(), "cwd": os.getcwd()})

def emit(value):
    sys.stdout.write(json.dumps(value, separators=(",", ":")) + "\n")
    sys.stdout.flush()

def reply(request, value):
    if mode == "duplicate_config_result" and request.get("method") == "config/read":
        # Even identical duplicate values are an ambiguous protocol envelope.
        payload = json.dumps(value, separators=(",", ":"))
        sys.stdout.write('{"id":' + str(request["id"]) + ',"result":' + payload + ',"result":' + payload + '}\n')
        sys.stdout.flush()
        return
    emit({"id": request["id"], "result": value})

def notify(method, params):
    emit({"method": method, "params": params})

args = sys.argv[1:]
features = {}
for index, value in enumerate(args[:-1]):
    if value == "--disable":
        features[args[index + 1]] = False
server_disabled = "mcp_servers.fixture_server.enabled=false" in args
config = {"features": features, "web_search": "disabled", "notify": [],
          "model_provider": "openai", "mcp_servers": {"fixture_server": {"enabled": not server_disabled}}}

for line in sys.stdin:
    request = json.loads(line)
    record({"event": "request", "pid": os.getpid(), "request": request})
    method = request.get("method")
    params = request.get("params", {})
    if method == "initialize":
        reply(request, {"userAgent": "local-fixture"})
    elif method == "config/read":
        reply(request, {"config": config})
    elif method == "account/read":
        reply(request, {"account": {"type": "chatgpt"}, "requiresOpenaiAuth": True})
    elif method == "thread/start":
        if mode == "delayed_thread": time.sleep(0.2)
        value = {"thread": {"id": "fixture-thread", "ephemeral": True},
                 "cwd": params["cwd"], "runtimeWorkspaceRoots": [],
                 "modelProvider": "openai", "approvalPolicy": "never",
                 "sandbox": {"type": "readOnly", "networkAccess": False}, "instructionSources": []}
        if mode == "provider_drift": value["modelProvider"] = "other-provider"
        elif mode == "durable_thread": value["thread"]["ephemeral"] = False
        elif mode == "cwd_drift": value["cwd"] += "/unexpected"
        elif mode == "roots_drift": value["runtimeWorkspaceRoots"] = ["/unexpected-root"]
        elif mode == "network_drift": value["sandbox"]["networkAccess"] = True
        elif mode == "instructions_drift": value["instructionSources"] = ["/unexpected/AGENTS.md"]
        if mode in ("duplicate_thread_key", "escaped_duplicate_thread_key"):
            payload = json.dumps({"id": request["id"], "result": value}, separators=(",", ":"))
            duplicate_key = 'networkAccess' if mode == "duplicate_thread_key" else 'network\\u0041ccess'
            payload = payload.replace('"networkAccess":false', '"networkAccess":false,"' + duplicate_key + '":false')
            sys.stdout.write(payload + "\n")
            sys.stdout.flush()
            continue
        reply(request, value)
    elif method == "turn/start":
        base = {"threadId": "fixture-thread", "turnId": "fixture-turn"}
        if mode.startswith("revision_"):
            current = json.loads(params["input"][0]["text"])
            payload = {"schema": "native-passage-revision/v1", "targetID": current["revisionTarget"]["id"],
                       "decision": "PROPOSE", "replacement": "Launch: Friday.", "explanation": "Removed unnecessary words.",
                       "sourceIDs": ["selected-passage"], "memoryIDs": []}
            if mode == "revision_wrong_target": payload["targetID"] = "obsolete-target"
            if mode == "revision_unknown_memory": payload["memoryIDs"] = ["private-unknown-memory"]
            text = "malformed JSON" if mode == "revision_malformed" else json.dumps(payload)
            notify("item/agentMessage/delta", dict(base, itemId="B", delta=text[:len(text)//2]))
            if mode == "revision_hold":
                reply(request, {"turn": {"id": "fixture-turn"}})
                record({"event": "revision_partial", "pid": os.getpid()})
                continue
            notify("item/completed", dict(base, item={"type": "agentMessage", "id": "B", "text": text, "phase": "final_answer"}))
            notify("turn/completed", {"threadId": "fixture-thread", "turn": {"id": "fixture-turn", "status": "completed"}})
            reply(request, {"turn": {"id": "fixture-turn"}})
            continue
        notify("item/started", dict(base, item={"type": "agentMessage", "id": "A", "text": "", "phase": "commentary"}))
        notify("item/agentMessage/delta", dict(base, itemId="B", delta="The launch "))
        notify("item/agentMessage/delta", dict(base, itemId="B", delta="is Friday."))
        notify("item/completed", dict(base, item={"type": "agentMessage", "id": "B", "text": "The launch is Friday.", "phase": "final_answer"}))
        notify("item/completed", dict(base, item={"type": "agentMessage", "id": "A", "text": "Late commentary", "phase": "commentary"}))
        notify("turn/completed", {"threadId": "fixture-thread", "turn": {"id": "fixture-turn", "status": "completed"}})
        time.sleep(0.04)
        record({"event": "turn_ack", "pid": os.getpid()})
        reply(request, {"turn": {"id": "fixture-turn"}})
    elif method in ("thread/unsubscribe", "turn/interrupt"):
        reply(request, {})
    elif "id" in request:
        emit({"id": request["id"], "error": {"code": -32601, "message": "Unsupported fixture method"}})

if mode == "ignore_term":
    # Stay alive after stdin closes; only the client's bounded kill fallback
    # (or this fixture's emergency cleanup file) can finish the process.
    while True:
        time.sleep(0.05)
"""#
}
