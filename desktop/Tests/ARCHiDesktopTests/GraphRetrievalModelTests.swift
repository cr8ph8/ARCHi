import Foundation
import XCTest
@testable import ARCHiDesktop

final class GraphRetrievalModelTests: XCTestCase {
    struct Answer: Decodable {
        let verdict: String
        let citations: [String]

        func scores(for question: GraphRetrievalFixture.Question, visible: Set<String>) -> (Bool, Bool) {
            let cited = Set(citations)
            return (verdict == question.verdict, cited.count == citations.count &&
                cited == Set(question.citations) && cited.isSubset(of: visible))
        }
    }

    func testGradingDetectsGuessingWrongRunAndExtraCitations() {
        let question = GraphRetrievalFixture.questions[3]
        let correct = Answer(verdict: "CONFLICT", citations: ["r46", "r45"])
        XCTAssertTrue(correct.scores(for: question, visible: ["r45", "r46"]).1)
        XCTAssertFalse(correct.scores(for: question, visible: ["r45"]).1)
        XCTAssertFalse(Answer(verdict: "PASS", citations: ["r45"]).scores(for: question, visible: ["r45"]).0)
        XCTAssertFalse(Answer(verdict: "CONFLICT", citations: ["r45", "r46", "r46"])
            .scores(for: question, visible: ["r45", "r46"]).1)
    }

    private let instruction = """
        You are reviewing synthetic qualification records. Find the named release's revision. Use only
        native macOS run receipts for that exact revision. A link may point to a run from an older revision.
        Return PASS or FAIL for an observed result. Return CONFLICT if matching receipts include both
        PASS and FAIL. Return UNVERIFIED if there is no decisive result. Cite exactly the IDs of all
        visible matching native receipts, including SKIPPED and ERROR. If none match, cite an empty array.
        """
    private let schema: JSONValue = .object([
        "type": .string("object"), "additionalProperties": .bool(false),
        "properties": .object([
            "verdict": .object(["type": .string("string"),
                "enum": .array(["PASS", "FAIL", "CONFLICT", "UNVERIFIED"].map(JSONValue.string))]),
            "citations": .object(["type": .string("array"), "items": .object(["type": .string("string")])])
        ]),
        "required": .array([.string("verdict"), .string("citations")])
    ])

    @MainActor
    func testPairedLocalQwen() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let model = env["ARCHI_RETRIEVAL_MODEL"], let output = env["ARCHI_RETRIEVAL_REPORT"] else {
            throw XCTSkip("Set ARCHI_RETRIEVAL_MODEL and ARCHI_RETRIEVAL_REPORT for the local Qwen comparison.")
        }
        let contextTokens = 4096
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 165
        let client = QwenAssistant(model: model, configuration: config, structuredContextTokens: contextTokens)
        defer { client.disconnect() }
        try await client.connect()
        let identity = try XCTUnwrap(client.metadata)
        let graph = GraphRetrievalFixture.snapshot
        let modes = CompanionGraphRetrieval.Mode.allCases
        var rows: [[String: Any]] = []
        let file = URL(fileURLWithPath: output)
        for (index, question) in GraphRetrievalFixture.questions.enumerated() {
            // Rotate the leading arm to distribute warm-up and prefix-cache effects.
            // Use the same request ID, question, schema and model for each paired trial.
            let id = UUID().uuidString
            for offset in 0..<modes.count {
                let mode = modes[(index + offset) % modes.count]
                let start = ProcessInfo.processInfo.systemUptime
                let hits = CompanionGraphRetrieval.search(graph, query: question.text, mode: mode)
                let ids = Set(hits.map(\.node.id))
                let records = hits.map { hit -> JSONValue in
                    let node = hit.node
                    return .object(["id": .string(node.id), "title": .string(node.title),
                        "description": .string(node.subtitle), "status": .string(node.status),
                        "details": .object(Dictionary(uniqueKeysWithValues: node.details.map { ($0.label, .string($0.value)) }))])
                }
                let links: [JSONValue] = graph.edges.filter { ids.contains($0.source) && ids.contains($0.target) }
                    .map { .array([.string($0.source), .string($0.label), .string($0.target)]) }
                let request = LocalRoleRequest(id: id, role: .reasoning,
                    input: .object(["requestID": .string(id), "question": .string(question.text),
                        "records": .array(records), "links": .array(links)]),
                    outputSchema: schema, systemInstructionOverride: instruction)
                var row: [String: Any] = ["case": question.alias, "mode": mode.rawValue, "selectedIDs": ids.sorted(),
                    "expectedVerdict": question.verdict, "expectedCitations": question.citations]
                do {
                    if client.metadata == nil { try await client.connect() }
                    guard client.metadata == identity else { throw QwenFailure.modelChanged }
                    let result = try await client.generate(request)
                    guard result.model == identity else { throw QwenFailure.modelChanged }
                    row["promptTokens"] = result.metrics?.inputTokens
                    row["outputTokens"] = result.metrics?.outputTokens
                    let answer = try JSONDecoder().decode(Answer.self, from: Data(result.text.utf8))
                    let (verdict, cited) = answer.scores(for: question, visible: ids)
                    row["verdict"] = answer.verdict
                    row["citations"] = answer.citations
                    row["correctVerdict"] = verdict
                    row["correctCitations"] = cited
                    row["status"] = verdict && cited ? "PASS" : "FAIL"
                } catch {
                    row["status"] = "ERROR"
                    row["error"] = String(describing: error)
                    print("Retrieval trial error", question.alias, mode.rawValue, error)
                }
                row["endToEndMs"] = (ProcessInfo.processInfo.systemUptime - start) * 1000
                // An independent readback uses the full fixture as a completeness index.
                // It is outside the timed model trial and never changes the raw answer.
                let readback = GraphRetrievalFixture.readback(alias: question.alias, graph: graph, visible: ids)
                row["receiptVerdict"] = readback.verdict
                row["receiptCitations"] = readback.citations
                row["receiptCoverageComplete"] = readback.complete
                row["receiptCorrect"] = readback.complete && readback.verdict == question.verdict
                    && readback.citations == question.citations
                rows.append(row)
                let report: [String: Any] = ["schema": "archi-retrieval/v1", "model": identity.name,
                    "digest": identity.digest, "contextWindowTokens": contextTokens, "os": ProcessInfo.processInfo.operatingSystemVersionString,
                    "plannedTrials": GraphRetrievalFixture.questions.count * modes.count, "trials": rows]
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    .write(to: file, options: .atomic)
            }
        }
        // Incorrect answers are benchmark observations. Execution or missing accounting fails the run.
        XCTAssertTrue(rows.allSatisfy { ($0["status"] as? String) != "ERROR" && ($0["promptTokens"] as? Int ?? 0) > 0 },
                      "See per-trial status and token accounting in the report")
    }
}
