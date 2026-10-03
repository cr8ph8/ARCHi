import Foundation
import CryptoKit
import XCTest
@testable import ARCHiDesktop

@MainActor
final class RevisionLiteralBudgetTests: XCTestCase {
    func testHamptonOmitsInventoryBeforeHistoryAndHashesActualInput() async throws {
        let history = [AssistantConversationExchange(question: "Earlier choice?", answer: "Keep the limitation.")]
        var selected: AssistantRequest?
        for count in stride(from: 0, through: 15_000, by: 128) {
            let request = try fixture(padding: count).replacingLocalConversation(history)
            let role = try roleRequest(request)
            if let bounded = try? HamptonReasonsAssistant.budgetedRequest(role),
               bounded.input["context"]?["revisionTarget"]?["literalPreservation"]?["status"] == .string("omitted-limit") {
                selected = request; break
            }
        }
        let request = try XCTUnwrap(selected, "Exercise a real envelope boundary with mandatory input still intact")
        let fake = LiteralBudgetClient()
        let assistant = HamptonReasonsAssistant(reasoner: fake, contextSelector: fake, contextEnabled: false)
        try await assistant.connect()
        try await assistant.reply(to: request) { _ in }
        let sent = try XCTUnwrap(fake.requests.first)
        XCTAssertEqual(fake.requests.count, 1)
        XCTAssertEqual(sent.input["context"]?["question"], .string(request.prompt))
        XCTAssertEqual(sent.input["context"]?["source"]?["text"], .string(request.sourceText))
        XCTAssertEqual(sent.input["context"]?["localConversation"], AssistantConversation.modelInput(for: history))
        XCTAssertEqual(sent.input["context"]?["revisionTarget"]?["requirements"], request.revisionTarget?.requirements.input)
        XCTAssertEqual(sent.input["context"]?["revisionTarget"]?["literalPreservation"], .object(["status": .string("omitted-limit")]))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let digest = SHA256.hash(data: try encoder.encode(sent.input)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(assistant.snapshot.invocations.first?.inputDigest, digest)
        XCTAssertEqual(assistant.snapshot.receipts.first?.inputDigest, digest)
        XCTAssertEqual(assistant.snapshot.localConversationOmittedCount, 0)
        await assistant.shutdown()
    }

    func testQwenUsesActualEscapedWireBudgetAndKeepsMandatoryInput() throws {
        let system = AssistantInstructions.passageRevisionText
        var found = false
        for count in stride(from: 0, through: 18_000, by: 64) {
            let request = try fixture(padding: count)
            let input = request.localInput
            let format = PassageRevisionValidator.schema(target: try XCTUnwrap(request.revisionTarget),
                sourceIDs: request.localSourceIDs, memoryIDs: [])
            let fullBody = try QwenAssistant.encodedChatBody(model: QwenAssistant.defaultModel, system: system, input: input, format: format)
            guard fullBody.count > QwenAssistant.maximumInputBytes,
                  input.utf8.count + system.utf8.count <= QwenAssistant.maximumInputBytes,
                  let fitted = try? QwenAssistant.budgetedChatInput(model: QwenAssistant.defaultModel, system: system, input: input, format: format) else { continue }
            let before = try JSONDecoder().decode(JSONValue.self, from: Data(input.utf8))
            let after = try JSONDecoder().decode(JSONValue.self, from: Data(fitted.utf8))
            XCTAssertEqual(after, RevisionLiteralBudget.omittingInventory(in: before))
            XCTAssertLessThanOrEqual(try QwenAssistant.encodedChatBody(model: QwenAssistant.defaultModel,
                system: system, input: fitted, format: format).count, QwenAssistant.maximumInputBytes)
            found = true; break
        }
        XCTAssertTrue(found, "Raw input can fit while the escaped transport body needs inventory omission")
        let tooLarge = try fixture(padding: 30_000)
        XCTAssertThrowsError(try QwenAssistant.budgetedChatInput(model: QwenAssistant.defaultModel,
            system: system, input: tooLarge.localInput, format: nil))
        XCTAssertThrowsError(try HamptonReasonsAssistant.budgetedRequest(roleRequest(tooLarge)))
    }

    func testCodexGuardOmitsOnlyInventoryAndRetainsSandboxFields() throws {
        let request = try fixture(padding: 0)
        let message: JSONValue = .object(["id": .number(42), "method": .string("turn/start"), "params": .object([
            "threadId": .string("synthetic-thread"), "approvalPolicy": .string("never"),
            "sandboxPolicy": .object(["type": .string("readOnly"), "networkAccess": .bool(false)]),
            "input": .array([.object(["type": .string("text"), "text": .string(request.codexInput)])])])])
        let unchanged = try XCTUnwrap(RevisionLiteralBudget.codexMessageData(message))
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: unchanged), message)
        let bounded = try XCTUnwrap(RevisionLiteralBudget.codexMessageData(message, maximumBytes: unchanged.count - 1))
        let result = try JSONDecoder().decode(JSONValue.self, from: bounded)
        XCTAssertEqual(result["params"]?["approvalPolicy"], message["params"]?["approvalPolicy"])
        XCTAssertEqual(result["params"]?["sandboxPolicy"], message["params"]?["sandboxPolicy"])
        XCTAssertEqual(result["id"], message["id"])
        let original = try JSONDecoder().decode(JSONValue.self, from: Data(request.codexInput.utf8))
        let sent = try XCTUnwrap(result["params"]?["input"]?.array?.first?["text"]?.string)
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: Data(sent.utf8)), RevisionLiteralBudget.omittingInventory(in: original))
        XCTAssertNil(try RevisionLiteralBudget.codexMessageData(message, maximumBytes: 1))
    }

    private func fixture(padding: Int) throws -> AssistantRequest {
        let source = "Keep 4 records and https://example.test/" + String(repeating: "x", count: 1_400) + " ."
        let selection = try XCTUnwrap(DocumentSelection(range: NSRange(location: 0, length: source.utf16.count), text: source, sourceRevision: 1))
        let target = try XCTUnwrap(RevisionTarget(text: source, sourceRevision: 1, selection: selection))
        return AssistantRequest(prompt: "Revise. " + String(repeating: "x", count: padding), sourceName: "synthetic.txt",
            sourceText: source, sourceRevision: 1, placementRevision: 0, tone: "Direct", replyLength: 0.4,
            selection: selection, revisionTarget: target)
    }

    private func roleRequest(_ request: AssistantRequest) throws -> LocalRoleRequest {
        let id = UUID().uuidString
        let schema = PassageRevisionValidator.schema(target: try XCTUnwrap(request.revisionTarget), sourceIDs: request.localSourceIDs, memoryIDs: [])
        return LocalRoleRequest(id: id, role: .reasoning, input: .object([
            "requestID": .string(id), "outputSchema": schema,
            "context": try JSONDecoder().decode(JSONValue.self, from: Data(request.localContextInput.utf8)),
            "sources": .array(request.localSourceIDs.map { .object(["id": .string($0), "label": .string($0)]) }),
            "memories": .array([])]), outputSchema: schema,
            systemInstructionOverride: AssistantInstructions.passageRevisionText + "\n" + LocalLessonGuidance.text
                + (request.localConversation.isEmpty ? "" : "\n" + LocalConversationGuidance.text))
    }
}

@MainActor
private final class LiteralBudgetClient: LocalRoleClient {
    var requests: [LocalRoleRequest] = []
    func connect() async throws {}
    func disconnect() {}
    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
        requests.append(request)
        let response: JSONValue = .object(["schema": .string(PassageRevisionValidator.schemaName),
            "targetID": request.input["context"]?["revisionTarget"]?["id"] ?? .null,
            "decision": .string("CLARIFY"), "replacement": .string(""), "explanation": .string("Synthetic budget fixture."),
            "sourceIDs": .array([]), "memoryIDs": .array([])])
        return LocalRoleResult(requestID: request.id, role: request.role,
            text: String(decoding: try JSONEncoder().encode(response), as: UTF8.self),
            model: QwenModelMetadata(name: QwenAssistant.defaultModel, family: "qwen35", parameterSize: "9B",
                quantization: "Q4", digest: "synthetic-budget-model"), elapsedMilliseconds: 1)
    }
}
