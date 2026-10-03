import Foundation
import XCTest
@testable import ARCHiDesktop

final class RevisionLiteralGuidanceTests: XCTestCase {
    /// Opt-in, one local generation with synthetic input. No Apply, Helpful
    /// judgment, saved method, cloud route or personal profile is involved.
    @MainActor
    func testOneLocalRevisionWithLiteralAndLimitationRequirements() async throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_LITERAL_GUIDANCE_LIVE_DIR"] else {
            throw XCTSkip("Opt-in one-call local revision check.")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        guard directory.path.hasPrefix("/private/tmp/"), !FileManager.default.fileExists(atPath: directory.path) else {
            throw XCTSkip("Use a new /private/tmp directory; an earlier attempt cannot be retried here.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try Data("One local generation; no retries.\n".utf8).write(to: directory.appendingPathComponent("started.txt"), options: .withoutOverwriting)
        let caveat = "These observations do not establish general intelligence or improved performance."
        let text = "In this synthetic project update, we currently have 4 source records and 6 saved methods available for review. \(caveat) The next action is to review https://example.test/records ."
        let selection = try XCTUnwrap(DocumentSelection(range: NSRange(location: 0, length: text.utf16.count), text: text, sourceRevision: 1))
        let target = try XCTUnwrap(RevisionTarget(text: text, sourceRevision: 1, selection: selection,
            requirements: .init(mustBeShorter: true)))
        let request = AssistantRequest(prompt: "Shorten this synthetic update. Keep this sentence verbatim in the replacement: \(caveat) Keep the next action last. Preserve the numeric and URL tokens exactly.",
            sourceName: "synthetic-milestone.txt", sourceText: text, sourceRevision: 1, placementRevision: 0,
            tone: "Direct", replyLength: 0.4, selection: selection, revisionTarget: target)
        let client = HamptonReasonsAssistant(contextEnabled: false)
        var proposal: PassageRevisionProposal?
        var extraEvents = 0
        var failure: String?
        let start = Date()
        do {
            try await client.connect()
            try await client.reply(to: request) { event in
                if case .revision(let value) = event, proposal == nil { proposal = value }
                else { extraEvents += 1 }
            }
        } catch { failure = String(describing: error) }
        let snapshot = client.snapshot
        await client.shutdown()
        let verification = proposal.map { DocumentWorkCapability.verify(proposal: $0, text: text,
            sourceRevision: 1, requirements: target.requirements) }
        let caveatPreserved = proposal?.replacement.contains(caveat) == true
        let nextActionLast = proposal.map { value in
            guard let limitation = value.replacement.range(of: caveat),
                  let link = value.replacement.range(of: "https://example.test/records") else { return false }
            return limitation.upperBound <= link.lowerBound
                && value.replacement[link.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines) == "."
        } ?? false
        let report: [String: Any] = [
            "scope": "One synthetic local proposal; no owner usefulness or learning credit",
            "source": text, "prompt": request.prompt, "replacement": proposal?.replacement ?? "",
            "failure": failure as Any? ?? NSNull(), "elapsedSeconds": Date().timeIntervalSince(start),
            "mechanicalChecks": verification?.checks.map { ["id": $0.id, "passed": $0.passed] as [String: Any] } ?? [],
            "canApply": verification?.canApply ?? false, "caveatPreserved": caveatPreserved,
            "nextActionLast": nextActionLast, "extraEvents": extraEvents,
            "attemptedInvocations": snapshot.attemptedInvocations.map(\.rawValue),
            "models": snapshot.receipts.map { ["name": $0.model.name, "digest": $0.model.digest] },
            "applied": false, "helpfulFeedback": false, "methodSaved": false, "cloudCalls": 0
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("result.json"), options: .withoutOverwriting)
        XCTAssertNil(failure)
        XCTAssertEqual(extraEvents, 0)
        XCTAssertEqual(snapshot.attemptedInvocations, [.reasoning])
        XCTAssertTrue(verification?.canApply == true)
        XCTAssertTrue(caveatPreserved)
        XCTAssertTrue(nextActionLast)
    }

    func testGuideUsesExactCountsAndSelectedPassageOnly() throws {
        let quote = "Keep 4 records, 4 backups and 6 notes: https://example.test/v6 ."
        let text = "Outside 99. " + quote + " Outside https://private.test/77"
        let selection = try XCTUnwrap(DocumentSelection(range: (text as NSString).range(of: quote), text: text, sourceRevision: 1))
        let target = try XCTUnwrap(RevisionTarget(text: text, sourceRevision: 1, selection: selection))
        let guide = try XCTUnwrap(target.input["literalPreservation"])
        XCTAssertEqual(guide["status"], .string("complete"))
        XCTAssertEqual(guide["numbers"], .array([
            .object(["token": .string("4"), "count": .number(2)]),
            .object(["token": .string("6"), "count": .number(2)])]))
        XCTAssertEqual(guide["links"], .array([
            .object(["token": .string("https://example.test/v6"), "count": .number(1)])]))
        let data = try JSONEncoder().encode(guide)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("99"))
        let disabled = try XCTUnwrap(RevisionTarget(text: text, sourceRevision: 1, selection: selection,
            requirements: .init(preserveNumbersAndLinks: false)))
        XCTAssertNil(disabled.input["literalPreservation"])
    }

    func testUnicodeTokensRemainByteDistinctAndDeterministic() throws {
        let first = "https://example.test/cafe\u{301}"
        let second = "https://example.test/café"
        let guide = DocumentWorkCapability.literalPreservationInput(for: "\(first) \(second) -1,000.00 ١٢")
        let links = try XCTUnwrap(guide["links"]?.array)
        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(Set(links.compactMap { $0["token"]?.string }.map { Data($0.utf8) }),
                       Set([Data(first.utf8), Data(second.utf8)]))
        XCTAssertEqual(guide, DocumentWorkCapability.literalPreservationInput(for: "١٢ \(second) -1,000.00 \(first)"))
    }

    func testOverflowOmitsEntireInventoryWithoutWeakeningVerification() throws {
        for text in [
            (0..<129).map(String.init).joined(separator: " "),
            "https://example.test/" + String(repeating: "x", count: 8_200),
            String(repeating: "4 ", count: 4_097)
        ] {
            let guide = DocumentWorkCapability.literalPreservationInput(for: text)
            XCTAssertEqual(guide, .object(["status": .string("omitted-limit")]))
            let selection = try XCTUnwrap(DocumentSelection(range: NSRange(location: 0, length: text.utf16.count), text: text, sourceRevision: 1))
            let target = try XCTUnwrap(RevisionTarget(text: text, sourceRevision: 1, selection: selection))
            let proposal = PassageRevisionProposal(target: target, decision: .propose, replacement: "Shortened.",
                explanation: "Candidate.", sourceIDs: [], memoryIDs: [])
            XCTAssertFalse(DocumentWorkCapability.verify(proposal: proposal, text: text,
                sourceRevision: 1, requirements: target.requirements).canApply)
        }
    }

    func testPreviouslyObservedDigitToWordFailureIsStillRejected() throws {
        let text = "We have 4 records and 6 methods. These do not establish improved performance."
        let selection = try XCTUnwrap(DocumentSelection(range: NSRange(location: 0, length: text.utf16.count), text: text, sourceRevision: 1))
        let target = try XCTUnwrap(RevisionTarget(text: text, sourceRevision: 1, selection: selection))
        let proposal = PassageRevisionProposal(target: target, decision: .propose,
            replacement: "Four records and six methods are available.", explanation: "Shorter candidate.", sourceIDs: [], memoryIDs: [])
        let checked = DocumentWorkCapability.verify(proposal: proposal, text: text,
            sourceRevision: 1, requirements: target.requirements)
        XCTAssertFalse(checked.canApply)
        XCTAssertEqual(checked.checks.first { $0.id == "numbers" }?.passed, false)
    }
}
