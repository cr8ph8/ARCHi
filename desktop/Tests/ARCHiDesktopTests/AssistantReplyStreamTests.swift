import Testing
@testable import ARCHiDesktop

struct AssistantReplyStreamTests {
    private func delta(_ id: String, _ text: String) -> JSONValue {
        .object(["itemId": .string(id), "delta": .string(text)])
    }

    private func item(_ id: String, _ text: String, phase: String? = nil) -> JSONValue {
        var data: [String: JSONValue] = ["type": .string("agentMessage"), "id": .string(id), "text": .string(text)]
        if let phase { data["phase"] = .string(phase) }
        return .object(["item": .object(data)])
    }

    private func rejects(_ stream: inout AssistantReplyStream, method: String, params: JSONValue) -> Bool {
        do { _ = try stream.consume(method: method, params: params); return false }
        catch AssistantFailure.protocolError { return true }
        catch { return false }
    }

    @Test func lateCommentaryCannotReplaceCompletedFinal() throws {
        var stream = AssistantReplyStream()
        _ = try stream.consume(method: "item/started", params: item("A", "", phase: "commentary"))
        #expect(try stream.consume(method: "item/completed", params: item("B", "The final answer.", phase: "final_answer")) == "The final answer.")
        #expect(try stream.consume(method: "item/completed", params: item("A", "Checking that…", phase: "commentary")) == nil)
        #expect(stream.finalText == "The final answer.")
    }

    @Test func distinctInterleavedMessagesNeverConcatenate() throws {
        var stream = AssistantReplyStream()
        #expect(try stream.consume(method: "item/agentMessage/delta", params: delta("A", "First")) == "First")
        #expect(try stream.consume(method: "item/agentMessage/delta", params: delta("B", "Second")) == "Second")
        #expect(try stream.consume(method: "item/agentMessage/delta", params: delta("A", " message")) == nil)
        #expect(try stream.consume(method: "item/agentMessage/delta", params: delta("B", " message")) == "Second message")
        _ = try stream.consume(method: "item/completed", params: item("B", "Second message"))
        #expect(stream.finalText == "Second message")
    }

    @Test func duplicateCompletionAndLateDeltaCannotChangeSettledText() throws {
        var stream = AssistantReplyStream()
        _ = try stream.consume(method: "item/completed", params: item("A", "Done", phase: "final_answer"))
        #expect(try stream.consume(method: "item/completed", params: item("A", "Done", phase: "final_answer")) == nil)
        #expect(try stream.consume(method: "item/agentMessage/delta", params: delta("A", " stale")) == nil)
        #expect(try stream.consume(method: "item/started", params: item("A", "")) == nil)
        #expect(stream.finalText == "Done")
        #expect(rejects(&stream, method: "item/completed", params: item("A", "Changed", phase: "final_answer")))
        #expect(stream.finalText == "Done")
    }

    @Test func commentaryAndPartialFinalDoNotEarnTerminalAnswer() throws {
        var stream = AssistantReplyStream()
        _ = try stream.consume(method: "item/completed", params: item("A", "Checking…", phase: "commentary"))
        #expect(stream.finalText == nil)
        _ = try stream.consume(method: "item/started", params: item("B", "", phase: "final_answer"))
        _ = try stream.consume(method: "item/agentMessage/delta", params: delta("B", "Incomplete"))
        #expect(stream.finalText == nil)
        _ = try stream.consume(method: "item/completed", params: item("B", "Complete", phase: "final_answer"))
        #expect(stream.finalText == "Complete")
    }

    @Test func phaseUnknownPreservesLegacyCompatibility() throws {
        var stream = AssistantReplyStream()
        _ = try stream.consume(method: "item/completed", params: item("A", "Legacy answer"))
        #expect(stream.finalText == "Legacy answer")
        _ = try stream.consume(method: "item/started", params: item("B", ""))
        #expect(stream.finalText == nil)
        _ = try stream.consume(method: "item/completed", params: item("B", "Newest answer"))
        #expect(stream.finalText == "Newest answer")
    }

    @Test func finalRetainsPriorityOverNewerLegacyMessage() throws {
        var stream = AssistantReplyStream()
        _ = try stream.consume(method: "item/completed", params: item("A", "Final", phase: "final_answer"))
        #expect(try stream.consume(method: "item/completed", params: item("B", "Late unknown")) == nil)
        #expect(stream.finalText == "Final")
    }

    @Test func delayedStartPreservesAlreadyStreamedPrefixAndAddsPhase() throws {
        var stream = AssistantReplyStream()
        _ = try stream.consume(method: "item/agentMessage/delta", params: delta("A", "Prefix"))
        #expect(try stream.consume(method: "item/started", params: item("A", "", phase: "final_answer")) == nil)
        #expect(try stream.consume(method: "item/agentMessage/delta", params: delta("A", " suffix")) == "Prefix suffix")
        _ = try stream.consume(method: "item/completed", params: item("A", "Prefix suffix"))
        #expect(stream.finalText == "Prefix suffix")
    }

    @Test func delayedPhaseMetadataCannotLeaveCommentaryEligibleAsFinalAnswer() throws {
        for method in ["item/started", "item/completed"] {
            var stream = AssistantReplyStream()
            _ = try stream.consume(method: "item/completed", params: item("A", "Checking…"))
            #expect(stream.finalText == "Checking…")
            let text = method == "item/started" ? "" : "Checking…"
            #expect(try stream.consume(method: method, params: item("A", text, phase: "commentary")) == nil)
            #expect(stream.finalText == nil)
        }
    }

    @Test func delayedFinalPhaseRetainsPriorityAndRejectsContradictoryMetadata() throws {
        for method in ["item/started", "item/completed"] {
            var stream = AssistantReplyStream()
            _ = try stream.consume(method: "item/completed", params: item("A", "Final"))
            let text = method == "item/started" ? "" : "Final"
            _ = try stream.consume(method: method, params: item("A", text, phase: "final_answer"))
            #expect(try stream.consume(method: "item/completed", params: item("B", "Later legacy text")) == nil)
            #expect(stream.finalText == "Final")
            #expect(rejects(&stream, method: method, params: item("A", text, phase: "commentary")))
            #expect(stream.finalText == "Final")
        }
    }

    @Test func rejectsMalformedMessageData() {
        var stream = AssistantReplyStream()
        #expect(rejects(&stream, method: "item/agentMessage/delta", params: .object(["itemId": .string(""), "delta": .string("x")])))
        #expect(rejects(&stream, method: "item/agentMessage/delta", params: .object(["itemId": .string("A"), "delta": .number(2)])))
        #expect(rejects(&stream, method: "item/completed", params: item("A", "x", phase: "invented")))
        #expect(rejects(&stream, method: "item/completed", params: .object(["item": .object(["type": .string("agentMessage"), "id": .string("A")])])) )
        #expect(stream.finalText == nil)
    }

    @Test func enforcesUTF8ByteLimitAndLeavesPriorStateOnRejection() throws {
        var stream = AssistantReplyStream()
        let full = String(repeating: "é", count: 50_000)
        _ = try stream.consume(method: "item/agentMessage/delta", params: delta("A", full))
        #expect(rejects(&stream, method: "item/agentMessage/delta", params: delta("A", "x")))
        _ = try stream.consume(method: "item/completed", params: item("A", full))
        #expect(stream.finalText == full)
        #expect(rejects(&stream, method: "item/completed", params: item("B", String(repeating: "a", count: 100_001))))
    }

    @Test func boundsAggregateTextAcrossItems() throws {
        var stream = AssistantReplyStream()
        _ = try stream.consume(method: "item/completed", params: item("A", String(repeating: "a", count: 60_000)))
        #expect(rejects(&stream, method: "item/agentMessage/delta", params: delta("B", String(repeating: "b", count: 40_001))))
        #expect(stream.finalText?.utf8.count == 60_000)
    }

    @Test func boundsItemCountIncludingEmptyMessages() throws {
        var stream = AssistantReplyStream()
        for id in 0..<256 { _ = try stream.consume(method: "item/started", params: item(String(id), "")) }
        #expect(rejects(&stream, method: "item/started", params: item("overflow", "")))
    }

    @Test func reasoningAndUnknownNotificationsDoNotChangeAnswer() throws {
        var stream = AssistantReplyStream()
        _ = try stream.consume(method: "item/completed", params: item("A", "Answer"))
        #expect(try stream.consume(method: "item/completed", params: .object(["item": .object(["type": .string("reasoning")])])) == nil)
        #expect(try stream.consume(method: "future/notification", params: .null) == nil)
        #expect(stream.finalText == "Answer")
    }
}
