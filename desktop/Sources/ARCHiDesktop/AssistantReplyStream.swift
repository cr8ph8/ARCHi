import Foundation

/// Content state for one already-correlated turn. The transport remains the owner
/// of process/thread/turn identity and decides which tool events are forbidden.
struct AssistantReplyStream {
    private enum Phase { case unknown, commentary, finalAnswer }
    private struct Message {
        var text: String
        var byteCount: Int
        var phase: Phase
        let order: Int
        var settled: Bool
    }

    private static let textLimit = 100_000
    private static let itemLimit = 256
    private var messages: [String: Message] = [:]
    private var retainedBytes = 0
    private var nextOrder = 0

    /// A successful turn needs a completed answer, not a progress comment or a
    /// partially streamed final. Unknown phases retain older-provider compatibility.
    var finalText: String? {
        let finals = messages.values.filter { $0.phase == .finalAnswer }
        if !finals.isEmpty {
            guard let latest = finals.max(by: { $0.order < $1.order }), latest.settled, !latest.text.isEmpty else { return nil }
            return latest.text
        }
        guard let latest = messages.values.filter({ $0.phase == .unknown }).max(by: { $0.order < $1.order }),
              latest.settled, !latest.text.isEmpty else { return nil }
        return latest.text
    }

    /// Returns only a changed visible message. Each item retains its own text, so
    /// interleaved deltas cannot concatenate unrelated messages.
    mutating func consume(method: String, params: JSONValue) throws -> String? {
        let before = visibleText
        var candidate = self
        try candidate.apply(method: method, params: params)
        self = candidate
        let after = visibleText
        return before == after ? nil : after
    }

    private var visibleText: String? {
        messages.values.max {
            if ($0.phase == .finalAnswer) != ($1.phase == .finalAnswer) { return $0.phase != .finalAnswer }
            return $0.order < $1.order
        }?.text
    }

    private mutating func apply(method: String, params: JSONValue) throws {
        switch method {
        case "item/agentMessage/delta":
            guard let id = params["itemId"]?.string, validID(id), let delta = params["delta"]?.string else { throw AssistantFailure.protocolError }
            let deltaBytes = delta.utf8.count
            guard deltaBytes <= Self.textLimit else { throw AssistantFailure.protocolError }
            if messages[id]?.settled == true { return }
            var message = try existingOrNew(id: id, phase: .unknown)
            guard message.byteCount + deltaBytes <= Self.textLimit,
                  retainedBytes + deltaBytes <= Self.textLimit else { throw AssistantFailure.protocolError }
            message.text += delta
            message.byteCount += deltaBytes
            retainedBytes += deltaBytes
            messages[id] = message

        case "item/started", "item/completed":
            guard let item = params["item"], let type = item["type"]?.string, !type.isEmpty else { throw AssistantFailure.protocolError }
            guard type == "agentMessage" else { return }
            guard let id = item["id"]?.string, validID(id), let body = item["text"]?.string else { throw AssistantFailure.protocolError }
            let bodyBytes = body.utf8.count
            guard bodyBytes <= Self.textLimit else { throw AssistantFailure.protocolError }
            let phase = try decodePhase(item["phase"])
            if var settled = messages[id], settled.settled {
                // A completion can precede a delayed start notification. A repeated
                // completion must preserve the content already received, while
                // delayed explicit phase metadata still constrains its use.
                if method == "item/completed" {
                    guard body == settled.text else { throw AssistantFailure.protocolError }
                }
                if phase != .unknown {
                    guard settled.phase == .unknown || phase == settled.phase else { throw AssistantFailure.protocolError }
                    settled.phase = phase
                    messages[id] = settled
                }
                return
            }
            let existed = messages[id] != nil
            var message = try existingOrNew(id: id, phase: phase)
            if message.phase == .unknown { message.phase = phase }
            else if phase != .unknown && phase != message.phase { throw AssistantFailure.protocolError }
            if method == "item/completed" || !existed {
                let nextBytes = retainedBytes - message.byteCount + bodyBytes
                guard nextBytes <= Self.textLimit else { throw AssistantFailure.protocolError }
                retainedBytes = nextBytes
                message.text = body
                message.byteCount = bodyBytes
            }
            message.settled = method == "item/completed"
            messages[id] = message

        default:
            return
        }
    }

    private mutating func existingOrNew(id: String, phase: Phase) throws -> Message {
        if let existing = messages[id] { return existing }
        guard messages.count < Self.itemLimit else { throw AssistantFailure.protocolError }
        let message = Message(text: "", byteCount: 0, phase: phase, order: nextOrder, settled: false)
        nextOrder += 1
        return message
    }

    private func validID(_ id: String) -> Bool { !id.isEmpty && id.utf8.count <= 512 }

    private func decodePhase(_ value: JSONValue?) throws -> Phase {
        switch value {
        case nil, .null: return .unknown
        case .string("commentary"): return .commentary
        case .string("final_answer"): return .finalAnswer
        default: throw AssistantFailure.protocolError
        }
    }
}
