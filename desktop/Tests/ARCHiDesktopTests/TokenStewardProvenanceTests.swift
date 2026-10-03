import Foundation
import XCTest
@testable import ARCHiDesktop

@MainActor
final class TokenStewardProvenanceTests: XCTestCase {
    private let source = ReadingSourceBinding(id: "AAAAAAAA-0000-4000-8000-000000000001", revision: 2,
        digest: String(repeating: "a", count: 64), provenance: ReadingSourceProvenanceReceipt(
            origin: .mixed, acquisition: .derivedCopy,
            parents: [ReadingSourceParent(binding: ReadingSourceBinding(
                id: "CCCCCCCC-0000-4000-8000-000000000003", revision: 1, digest: String(repeating: "e", count: 64)))],
            digest: String(repeating: "f", count: 64)))
    private let page = KnowledgePageBinding(id: "BBBBBBBB-0000-4000-8000-000000000002", revision: 3,
        digest: String(repeating: "b", count: 64))

    private func provenance(input: String = "c") -> TokenStewardRequestProvenance {
        TokenStewardRequestProvenance(inputDigest: String(repeating: input, count: 64),
            readingDependencies: [source], knowledgeDependencies: [page],
            knowledgeContextDigest: String(repeating: "d", count: 64))
    }

    private func receipt(_ requestID: String, route: AssistantRoute = .automatic,
                         state: AssistantLaneState = .complete,
                         provenance: TokenStewardRequestProvenance? = nil) -> AssistantLaneReceipt {
        var result = AssistantLaneReceipt(requestID: requestID, route: route, provider: .qwen,
            context: ContextTicket(generation: 1, placement: 0, source: 0, selection: 0),
            inputDigest: provenance?.inputDigest ?? String(repeating: "c", count: 64),
            inputContract: AssistantRequest.inputContract, deadline: Date().addingTimeInterval(90),
            modelIdentity: nil, state: state)
        result.requestStarted = true
        result.readingDependencies = provenance?.readingDependencies
        result.knowledgeDependencies = provenance?.knowledgeDependencies
        result.knowledgeContextDigest = provenance?.knowledgeContextDigest
        result.isKnowledgeAcquisition = provenance?.isKnowledgeAcquisition ?? false
        return result
    }

    func testExactBindingsSurviveRestartAndRemainInspectableWithoutCurrentSourceText() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-provenance-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("steward.json")
        let store = TokenStewardStore(url: url)
        let captured = provenance()
        try store.preflight(requestID: "saved", route: .automatic)
        try store.recordRequestProvenance(requestID: "saved", provenance: captured)
        try store.recordDispatch(requestID: "saved", provider: .qwen)
        try store.recordLane(receipt("saved", provenance: captured))

        let restarted = TokenStewardStore(url: url)
        XCTAssertNil(restarted.loadError)
        XCTAssertEqual(restarted.tasks.first?.requestProvenance, captured)
        let graph = CompanionGraph.build(receipts: [], lessons: [], source: nil, now: Date(), accountingTasks: restarted.tasks)
        XCTAssertTrue(graph.nodes.contains { $0.target == .stewardTask(taskID: "saved") })
        XCTAssertTrue(graph.nodes.contains { $0.kind == .source && $0.status == "Historical reference"
            && $0.details.contains(.init(label: "Digest", value: source.digest)) })
        XCTAssertTrue(graph.nodes.contains { $0.kind == .knowledge && $0.target == .knowledgePage(id: page.id)
            && $0.details.contains(.init(label: "Revision", value: "3")) })
        XCTAssertEqual(graph.edges.filter { $0.label == "captured dependency at dispatch" }.count, 2)

        let encoded = try JSONEncoder().encode(captured)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["inputDigest", "readingDependencies", "knowledgeDependencies", "knowledgeContextDigest", "isKnowledgeAcquisition"])
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("\"title\""))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("\"text\""))
    }

    func testSameBindingReplayIsIdempotentAndConflictsNeverReplaceIt() throws {
        let store = TokenStewardStore()
        let captured = provenance()
        try store.preflight(requestID: "replay", route: .automatic)
        try store.recordRequestProvenance(requestID: "replay", provenance: captured)
        let beforeDispatch = store.revision
        try store.recordRequestProvenance(requestID: "replay", provenance: captured)
        XCTAssertEqual(store.revision, beforeDispatch)
        try store.recordDispatch(requestID: "replay", provider: .qwen)
        try store.recordLane(receipt("replay", provenance: captured))
        let terminalRevision = store.revision
        try store.recordRequestProvenance(requestID: "replay", provenance: captured)
        try store.recordLane(receipt("replay", provenance: captured))
        XCTAssertEqual(store.revision, terminalRevision)
        XCTAssertThrowsError(try store.recordRequestProvenance(requestID: "replay", provenance: provenance(input: "e")))
        XCTAssertThrowsError(try store.recordLane(receipt("replay", provenance: provenance(input: "e"))))
        XCTAssertEqual(store.tasks.first?.requestProvenance, captured)
        XCTAssertEqual(store.revision, terminalRevision)
    }

    func testFirstLateBindingAndExternalRouteAreRejected() throws {
        let store = TokenStewardStore()
        try store.preflight(requestID: "late", route: .automatic)
        try store.recordDispatch(requestID: "late", provider: .qwen)
        XCTAssertThrowsError(try store.recordRequestProvenance(requestID: "late", provenance: provenance()))
        XCTAssertNil(store.tasks.first?.requestProvenance)
        try store.preflight(requestID: "external", route: .codex)
        XCTAssertThrowsError(try store.recordRequestProvenance(requestID: "external", provenance: provenance()))
    }

    func testLegacyNilRemainsUnrecordedOnReloadAndReceiptReplay() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-legacy-provenance-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("steward.json")
        let store = TokenStewardStore(url: url)
        try store.preflight(requestID: "legacy", route: .automatic)
        try store.recordDispatch(requestID: "legacy", provider: .qwen)
        try store.recordLane(receipt("legacy"))
        let before = try Data(contentsOf: url)
        XCTAssertFalse(String(decoding: before, as: UTF8.self).contains("requestProvenance"))
        let restarted = TokenStewardStore(url: url)
        XCTAssertNil(restarted.loadError)
        XCTAssertNil(restarted.tasks.first?.requestProvenance)
        try restarted.recordLane(receipt("legacy", provenance: provenance()))
        XCTAssertNil(restarted.tasks.first?.requestProvenance)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testMalformedBindingsAndPrivateExtraFieldsAreRejected() throws {
        let duplicate = ReadingSourceBinding(id: source.id.lowercased(), revision: source.revision, digest: source.digest)
        let invalid = TokenStewardRequestProvenance(inputDigest: String(repeating: "c", count: 64),
            readingDependencies: [source, duplicate])
        XCTAssertFalse(invalid.isValid)
        let store = TokenStewardStore()
        try store.preflight(requestID: "invalid", route: .automatic)
        XCTAssertThrowsError(try store.recordRequestProvenance(requestID: "invalid", provenance: invalid))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(provenance())) as? [String: Any])
        object["sourceText"] = "Private text must not enter a provenance record."
        let bytes = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(TokenStewardRequestProvenance.self, from: bytes))
    }

    func testPersistedLocalDependenciesCannotAuthorizeNativeFallback() throws {
        let store = TokenStewardStore()
        let captured = provenance()
        try store.preflight(requestID: "local-only", route: .native)
        try store.recordRequestProvenance(requestID: "local-only", provenance: captured)
        try store.recordDispatch(requestID: "local-only", provider: .qwen)
        try store.recordLane(receipt("local-only", route: .native, state: .failed, provenance: captured))
        XCTAssertThrowsError(try store.registerFallback(requestID: "local-only"))
        XCTAssertEqual(store.tasks.first?.lanes.count, 1)
    }

    func testKnowledgeChatOwnerPersistsBindingsBeforeCallingLocalClient() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-owner-provenance-\(UUID())")
        let client = ProvenanceOwnerClient()
        let usage = TokenStewardStore(url: directory.appendingPathComponent("usage.json"))
        let store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"),
            assistant: client, allowsPlay: false, tokenSteward: usage)
        defer { store.cancelWork(); client.drain(); try? FileManager.default.removeItem(at: directory) }
        let source = try store.readingSources.keep(title: "Synthetic source title", text: "A synthetic supporting passage.")
        let anchor = try store.readingSources.makeAnchor(sourceID: source.id, range: NSRange(location: 0, length: source.text.utf16.count))
        let draft = try store.readingSources.saveKnowledgePage(title: "Synthetic page title", body: "An interpretation.", kind: .claim, anchors: [anchor])
        let page = try store.readingSources.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        client.atDispatch = {
            XCTAssertEqual(usage.tasks.first?.requestProvenance?.readingDependencies, [source.binding])
            XCTAssertEqual(usage.tasks.first?.requestProvenance?.knowledgeDependencies, [page.binding])
            XCTAssertEqual(usage.tasks.first?.lanes.first?.dispatched, true)
        }
        store.useKnowledgePageInChat(page)
        store.prompt = "Explain the selected note."
        store.submit()
        for _ in 0..<500 {
            if client.called { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertTrue(client.called)
        let bytes = try usage.exportData()
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(text.contains("Synthetic source title"))
        XCTAssertFalse(text.contains("Synthetic page title"))
        XCTAssertFalse(text.contains(source.text))
        XCTAssertFalse(text.contains(store.prompt))
    }
}

@MainActor
private final class ProvenanceOwnerClient: AssistantClient {
    var atDispatch: (() -> Void)?
    private(set) var called = false
    private var continuation: CheckedContinuation<Void, any Error>?
    func connect() async throws {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        atDispatch?(); called = true
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func disconnect() {}
    func shutdown() async {}
    func drain() { let pending = continuation; continuation = nil; pending?.resume(throwing: AssistantFailure.stopped) }
}
