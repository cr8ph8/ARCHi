import CryptoKit
import XCTest
@testable import ARCHiDesktop

@MainActor
final class ArenaARCTests: XCTestCase {
    func testDefaultRuntimePreservesLegacyUntilNativeSetupIsComplete() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("arena-runtime-home-\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        let legacy = home.appendingPathComponent("ARC-AGI-3-Agents")
        XCTAssertEqual(ARC3SessionStore.defaultRuntimeRoot(home: home), legacy)
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        let managed = home.appendingPathComponent("Library/Application Support/ARCHi/ARC3Runtime-\(arch)-v1")
        let bin = managed.appendingPathComponent(".venv/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: bin.appendingPathComponent("python").path)
        try FileManager.default.createDirectory(at: managed.appendingPathComponent("environment_files"), withIntermediateDirectories: true)
        XCTAssertEqual(ARC3SessionStore.defaultRuntimeRoot(home: home), legacy, "Partial setup cannot replace the existing default")
        try Data("{}".utf8).write(to: managed.appendingPathComponent("runtime-ready.json"))
        XCTAssertEqual(ARC3SessionStore.defaultRuntimeRoot(home: home).path, managed.path)
    }

    func testArenaAndReasoningShareLoadedTaskWithoutDispatchOrSaving() async throws {
        let fixture = try ArenaARCFixture()
        defer { fixture.clean() }
        let store = fixture.store
        try store.arcCapabilities.loadSolverSample()
        let digest = try XCTUnwrap(store.arcCapabilities.solverDocument?.inputDigest)
        let before = try fixture.files()
        let grids = store.arcCapabilities, worlds = store.arc3
        store.openArena(.arc)
        XCTAssertEqual(store.section, .unity)
        XCTAssertEqual(store.arenaActivity, .arc)
        store.openReasoningTools(worlds: true)
        store.openArena(.practice)
        store.open(.assistant)
        store.open(.unity)
        XCTAssertEqual(store.arenaActivity, .practice)
        store.openArena(.arc)
        XCTAssertTrue(store.arcCapabilities === grids)
        XCTAssertTrue(store.arc3 === worlds)
        XCTAssertEqual(store.arcCapabilities.solverDocument?.inputDigest, digest)
        XCTAssertNil(store.arcGridStartUnavailableReason)
        XCTAssertTrue(store.tokenSteward.tasks.isEmpty)
        XCTAssertFalse(store.unityPresentation.isSharing)
        XCTAssertEqual(fixture.client.calls, 0)
        let commands = await fixture.transport.commands
        XCTAssertTrue(commands.isEmpty, "Browsing must not even discover environments")
        XCTAssertEqual(try fixture.files(), before)
        await store.shutdownAssistant()
    }

    func testPausedEpisodeSurvivesArenaNavigationAndBlocksGridStartUntilStopped() async throws {
        let fixture = try ArenaARCFixture()
        defer { fixture.clean() }
        let store = fixture.store
        let profile = try Data(contentsOf: fixture.profile)
        store.arc3.discover()
        try await wait { !store.arc3.isWorking }
        store.arc3.start(budget: 4)
        try await wait { !store.arc3.isWorking }
        XCTAssertTrue(store.arc3.isSessionActive)
        let frame = store.arc3.observation
        let receipt = store.arc3.receiptURL
        XCTAssertNotNil(store.arcGridStartUnavailableReason, "Paused between actions still owns the session")
        let before = try fixture.files()
        store.openArena(.arc)
        store.openArena(.practice)
        store.openReasoningTools()
        store.openArena(.arc)
        XCTAssertEqual(store.arc3.observation, frame)
        XCTAssertEqual(store.arc3.receiptURL, receipt)
        XCTAssertEqual(try fixture.files(), before)
        let commands = await fixture.transport.commands
        XCTAssertEqual(commands, ["discover", "start"])
        XCTAssertTrue(store.runARC3(.stop))
        XCTAssertFalse(store.arc3.isSessionActive)
        XCTAssertNil(store.arcGridStartUnavailableReason)
        XCTAssertEqual(store.lastARC3Summary?.dispatches, 1)
        XCTAssertEqual(store.tokenSteward.summary.interactiveSessionCount, 1)
        XCTAssertEqual(fixture.client.calls, 0)
        XCTAssertEqual(try Data(contentsOf: fixture.profile), profile)
        await store.shutdownAssistant()
    }

    func testPlayEntryReturnsToPracticeEvenWhenUnityUnavailable() async throws {
        let fixture = try ArenaARCFixture()
        defer { fixture.clean() }
        let owner = UnityPresentationConnection(launchApplication: { _, _ in
            XCTFail("Unavailable Unity cannot launch")
            throw CocoaError(.executableLoad)
        }, bundledResourceURL: nil, fallbackPlayers: [])
        fixture.store.openArena(.arc)
        let before = try fixture.files()
        await ArenaEntryAction.open(store: fixture.store, connection: owner)
        XCTAssertEqual(fixture.store.section, .unity)
        XCTAssertEqual(fixture.store.arenaActivity, .practice)
        XCTAssertFalse(owner.isSharing)
        XCTAssertEqual(try fixture.files(), before)
        XCTAssertEqual(fixture.client.calls, 0)
        await fixture.store.shutdownAssistant()
    }

    private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 where !predicate() { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(predicate())
    }
}

@MainActor
private final class ArenaARCFixture {
    let root: URL
    let profile: URL
    let store: CompanionStore
    let client = ArenaARCNoModel()
    let transport = ArenaARCTransport()
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("arena-arc-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        profile = root.appendingPathComponent("preferences.json")
        try NativePreferenceDocument().encoded().write(to: profile)
        let client = client, transport = transport
        store = CompanionStore(preferenceURL: profile, assistant: client,
            assistantFactory: { _, _ in client }, allowsPlay: false,
            arc3: ARC3SessionStore(outputDirectory: root.appendingPathComponent("episodes"), transportFactory: { _ in transport }))
    }
    func files() throws -> [String: Data] {
        let urls = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])!
        var snapshot: [String: Data] = [:]
        for case let url as URL in urls where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            snapshot[url.path] = try Data(contentsOf: url)
        }
        return snapshot
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

@MainActor
private final class ArenaARCNoModel: AssistantClient {
    var calls = 0
    func connect() async throws { calls += 1; XCTFail("Navigation cannot connect a model") }
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; XCTFail("Navigation cannot invoke a model")
    }
}

private actor ArenaARCTransport: ARC3Transport {
    private(set) var commands: [String] = []
    func request(_ request: ARC3Request) async throws -> ARC3Response {
        commands.append(request.command)
        if request.command == "discover" {
            return ARC3Response(id: request.id, ok: true, games: [ARC3Game(id: "fixture-v1", title: "Fixture")])
        }
        if request.command == "start" {
            let frame = [[1]]
            let digest = SHA256.hash(data: try JSONEncoder().encode(frame)).map { String(format: "%02x", $0) }.joined()
            return ARC3Response(id: request.id, ok: true, observation: ARC3Observation(gameID: "fixture-v1",
                state: "NOT_FINISHED", levelsCompleted: 0, winLevels: 1, availableActions: [1], frame: frame,
                frameDigest: digest, dispatches: 1, budget: request.budget!))
        }
        return ARC3Response(id: request.id, ok: true)
    }
    nonisolated func stop() {}
}
