import Foundation
import XCTest
@testable import ARCHiDesktop

@MainActor
final class DocumentURLBoundaryRestorationTests: XCTestCase {
    private let source = "I was wondering whether you could please send 3 photos by Friday at 14:00 using https://example.com/photos ."
    private let raw = "Please send 3 photos by Friday at 14:00 using https://example.com/photos."
    private let restored = "Please send 3 photos by Friday at 14:00 using https://example.com/photos ."

    func testRestoresOnlyExactSourceSeparatorAndKeepsOriginalProposal() throws {
        for separator in [" ", "\t", " \t "] {
            let text = source.replacingOccurrences(of: "photos .", with: "photos" + separator + ".")
            let original = try proposal(text, replacement: raw)
            let checked = DocumentWorkCapability.verify(proposal: original, text: text, sourceRevision: 3,
                requirements: original.target.requirements)
            XCTAssertEqual(checked.checks.filter { !$0.passed }.map(\.id), ["links"])
            let result = try XCTUnwrap(DocumentURLBoundaryPreservation.restore(original, text: text, sourceRevision: 3))
            XCTAssertEqual(original.replacement, raw)
            XCTAssertEqual(result.proposal.replacement, restored.replacingOccurrences(of: "photos .", with: "photos" + separator + "."))
            XCTAssertEqual(result.proposal.target, original.target)
            XCTAssertEqual(result.proposal.explanation, original.explanation)
            XCTAssertEqual(result.proposal.sourceIDs, original.sourceIDs)
            XCTAssertEqual(result.proposal.memoryIDs, original.memoryIDs)
            XCTAssertTrue(result.restoration.isValid)
            XCTAssertEqual(result.restoration.originalReplacementDigest, WorkingCopyEditReceipt.digest(raw))
            XCTAssertEqual(result.restoration.restoredReplacementDigest, WorkingCopyEditReceipt.digest(result.proposal.replacement))
            XCTAssertEqual(result.restoration.separatorUTF8Length, separator.utf8.count)
            XCTAssertTrue(DocumentWorkCapability.verify(proposal: result.proposal, text: text, sourceRevision: 3,
                requirements: original.target.requirements).canApply)
            XCTAssertNil(DocumentURLBoundaryPreservation.restore(result.proposal, text: text, sourceRevision: 3), "A second pass must not change accepted bytes.")
        }
    }

    func testRefusesChangedURLAmbiguityAndUnsupportedPunctuation() throws {
        let cases: [(String, String)] = [
            (source, raw.replacingOccurrences(of: "example.com", with: "other.com")),
            (source, raw.replacingOccurrences(of: "photos.", with: "photos?view=all.")),
            (source, raw.replacingOccurrences(of: "photos.", with: "photos..")),
            (source.replacingOccurrences(of: " .", with: " ,"), raw.replacingOccurrences(of: "photos.", with: "photos,")),
            (source.replacingOccurrences(of: " .", with: "\n."), raw),
            (source.replacingOccurrences(of: " .", with: String(repeating: " ", count: 33) + "."), raw),
            (source.replacingOccurrences(of: " .", with: " .)"), raw),
            (source + " Also https://example.com/photos .", raw + " Also https://example.com/photos."),
            (source + " Also https://example.com/other .", raw + " Also https://example.com/other."),
            (source.replacingOccurrences(of: "photos .", with: "photos."), restored),
            (source.replacingOccurrences(of: "photos .", with: "cafe\u{301} ."), raw.replacingOccurrences(of: "photos.", with: "café."))
        ]
        for (text, replacement) in cases {
            XCTAssertNil(DocumentURLBoundaryPreservation.restore(try proposal(text, replacement: replacement),
                text: text, sourceRevision: 3), "Unsupported or ambiguous boundary: \(text) → \(replacement)")
        }
    }

    func testRefusesStaleSourceDisabledRequirementAndAnyOtherFailedCheck() throws {
        let original = try proposal(source, replacement: raw)
        XCTAssertNil(DocumentURLBoundaryPreservation.restore(original, text: source + "!", sourceRevision: 3))
        XCTAssertNil(DocumentURLBoundaryPreservation.restore(original, text: source, sourceRevision: 4))
        XCTAssertNil(DocumentURLBoundaryPreservation.restore(try proposal(source, replacement: raw,
            requirements: .init(mustBeShorter: true, preserveNumbersAndLinks: false)), text: source, sourceRevision: 3))
        XCTAssertNil(DocumentURLBoundaryPreservation.restore(try proposal(source, replacement: raw.replacingOccurrences(of: "3 photos", with: "4 photos")), text: source, sourceRevision: 3))
        XCTAssertNil(DocumentURLBoundaryPreservation.restore(try proposal(source, replacement: String(repeating: "Padding ", count: 30) + raw), text: source, sourceRevision: 3))
        let clarify = PassageRevisionProposal(target: original.target, decision: .clarify, replacement: "",
            explanation: "Clarify the request.", sourceIDs: [], memoryIDs: [])
        XCTAssertNil(DocumentURLBoundaryPreservation.restore(clarify, text: source, sourceRevision: 3))
    }

    func testUTF16SelectionLeavesSurroundingTextAndSourceBytesExact() throws {
        let text = "😀 Café\r\n" + source + "\r\nUnchanged suffix"
        let range = (text as NSString).range(of: source)
        let original = try proposal(text, replacement: raw, range: range)
        let result = try XCTUnwrap(DocumentURLBoundaryPreservation.restore(original, text: text, sourceRevision: 3))
        let changed = try WorkingCopyEditReceipt.applying(proposal: result.proposal, to: text, sourceRevision: 3)
        XCTAssertEqual(changed, "😀 Café\r\n" + restored + "\r\nUnchanged suffix")
        XCTAssertEqual(result.restoration.sourceDigest, WorkingCopyEditReceipt.digest(text))
    }

    func testProductionOwnerRetainsRawDigestAndRequiresExplicitApplyThenUndo() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("url-boundary-owner-\(UUID())")
        let role = URLBoundaryRoleClient(replacement: raw)
        let refused = URLBoundaryRefusedClient()
        let local = HamptonReasonsAssistant(reasoner: role, contextSelector: refused)
        let preference = directory.appendingPathComponent("preferences.json")
        let store = CompanionStore(preferenceURL: preference, assistant: local,
            assistantFactory: { _, _ in refused }, allowsPlay: false, tokenSteward: TokenStewardStore())
        defer { store.cancelWork(); store.disconnectAssistant(); try? FileManager.default.removeItem(at: directory) }
        store.setAssistantRoute(.automatic); store.setLocalWorkPreference(.reasoning)
        store.share(text: source, name: "synthetic-url.txt")
        store.selectText(range: NSRange(location: 0, length: source.utf16.count), sourceRevision: store.sourceRevision)
        store.preparePassageRevision(shorten: true)
        store.documentRequirements.preserveNumbersAndLinks = true
        store.submit()
        for _ in 0..<400 {
            if !store.isWorking { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(store.isWorking)
        let lane = try XCTUnwrap(store.compareResults[.qwen])
        let proposal = try XCTUnwrap(lane.revision)
        let receipt = try XCTUnwrap(lane.receipt)
        let restoration = try XCTUnwrap(lane.urlBoundaryRestoration)
        XCTAssertEqual(lane.state, .complete)
        XCTAssertEqual(lane.originalRevision?.replacement, raw)
        XCTAssertEqual(proposal.replacement, restored)
        XCTAssertEqual(receipt.localInvocationReceipts?.last?.outputDigest, WorkingCopyEditReceipt.digest(try XCTUnwrap(role.rawOutput)))
        XCTAssertEqual(receipt.localInvocationReceipts?.last?.metrics?.inputTokens, 123)
        XCTAssertEqual(receipt.localInvocationReceipts?.last?.metrics?.outputTokens, 45)
        XCTAssertEqual(store.sharedText, source, "Restoration prepares a candidate; it never applies.")
        let ready = try XCTUnwrap(store.documentRecord(requestID: receipt.requestID, provider: .qwen))
        XCTAssertEqual(ready.state, .ready)
        XCTAssertEqual(ready.urlBoundaryRestoration, restoration)
        XCTAssertEqual(ready.proposedDigest, restoration.restoredReplacementDigest)
        XCTAssertNil(ready.actualAfterDigest)
        XCTAssertNil(ready.feedback)
        XCTAssertEqual(refused.calls, 0)
        XCTAssertEqual(role.calls, 1)
        XCTAssertTrue(store.canApplyDocumentRevision(provider: .qwen, proposal: proposal))
        store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
        XCTAssertEqual(store.sharedText, restored)
        let applied = try XCTUnwrap(store.documentRecord(requestID: receipt.requestID, provider: .qwen))
        XCTAssertEqual(applied.state, .applied)
        XCTAssertEqual(applied.urlBoundaryRestoration, restoration)
        XCTAssertNil(applied.feedback)
        store.undoWorkingCopyEdit()
        XCTAssertEqual(store.sharedText, source)
        XCTAssertEqual(store.documentRecord(requestID: receipt.requestID, provider: .qwen)?.state, .undone)
        XCTAssertTrue(store.evolution.usefulReceipts.isEmpty)
        XCTAssertTrue(store.keptLessons.isEmpty)
        let journal = DocumentWorkJournal(url: preference.deletingPathExtension().appendingPathExtension("document-work.json"))
        XCTAssertNil(journal.loadError)
        XCTAssertEqual(journal.records.first?.urlBoundaryRestoration, restoration)
        var retired = lane
        retired.revision = nil
        XCTAssertNil(retired.originalRevision)
        XCTAssertNil(retired.urlBoundaryRestoration)
    }

    func testPersistenceIsTextFreeImmutableAndRejectsForgedMetadata() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("url-boundary-journal-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("work.json")
        let journal = DocumentWorkJournal(url: url)
        let original = try proposal(source, replacement: raw)
        let result = try XCTUnwrap(DocumentURLBoundaryPreservation.restore(original, text: source, sourceRevision: 3))
        let checked = DocumentWorkCapability.verify(proposal: result.proposal, text: source, sourceRevision: 3,
            requirements: original.target.requirements)
        let now = Date()
        var record = DocumentWorkRecord(id: UUID().uuidString, requestID: UUID().uuidString,
            provider: AssistantProvider.qwen.rawValue, targetID: original.target.id, sourceDigest: original.target.sourceDigest,
            sourceRevision: 3, selectionStart: 0, selectionLength: source.utf16.count,
            mustBeShorter: true, preserveNumbersAndLinks: true, createdAt: now, updatedAt: now)
        try journal.save(record)
        record.state = .ready
        record.proposedDigest = result.restoration.restoredReplacementDigest
        record.expectedAfterDigest = checked.predictedDigest
        record.checks = checked.checks.map { .init(id: $0.id, title: $0.title, passed: $0.passed) }
        record.urlBoundaryRestoration = result.restoration
        try journal.save(record)
        let bytes = try Data(contentsOf: url)
        let persisted = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(persisted.contains(source)); XCTAssertFalse(persisted.contains(raw)); XCTAssertFalse(persisted.contains("example.com"))
        let reopened = DocumentWorkJournal(url: url)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.records.first?.state, .cancelled, "Reload never resumes or applies a repaired proposal.")
        XCTAssertEqual(reopened.records.first?.urlBoundaryRestoration, result.restoration)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        var removed = record; removed.urlBoundaryRestoration = nil
        XCTAssertThrowsError(try journal.save(removed))
        var changed = record; changed.proposedDigest = String(repeating: "a", count: 64)
        XCTAssertThrowsError(try journal.save(changed))
        var failed = record; failed.checks[0].passed = false
        XCTAssertThrowsError(try journal.save(failed))
        var mismatched = record
        mismatched.urlBoundaryRestoration = .init(algorithm: result.restoration.algorithm,
            targetID: UUID().uuidString, sourceDigest: result.restoration.sourceDigest,
            originalReplacementDigest: result.restoration.originalReplacementDigest,
            restoredReplacementDigest: result.restoration.restoredReplacementDigest,
            restoredBoundaryCount: 1, separatorUTF8Length: 1)
        XCTAssertThrowsError(try journal.save(mismatched))
        var archive = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var rows = try XCTUnwrap(archive["records"] as? [[String: Any]])
        var metadata = try XCTUnwrap(rows[0]["urlBoundaryRestoration"] as? [String: Any])
        metadata["copiedText"] = "not permitted"
        rows[0]["urlBoundaryRestoration"] = metadata; archive["records"] = rows
        try JSONSerialization.data(withJSONObject: archive).write(to: url)
        XCTAssertNotNil(DocumentWorkJournal(url: url).loadError)
    }

    func testOfflineReplayOfRetainedFailuresPreservesOriginalReceipts() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let paths = ["output/hampton-method-transfer-2026-09-26/transfer-receipt.json",
            "output/hampton-method-guidance-2026-09-26/guidance-receipt.json"]
        guard paths.allSatisfy({ FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }) else {
            throw XCTSkip("Retained local live artifacts are not present. No model is invoked for offline replay.")
        }
        var outcomes: [[String: Any]] = []
        for path in paths {
            let url = root.appendingPathComponent(path)
            let bytes = try Data(contentsOf: url)
            let report = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            let calls = try XCTUnwrap(report["rawCalls"] as? [[String: Any]])
            let samples = try XCTUnwrap(report["samples"] as? [[String: Any]])
            for sample in samples {
                let text = try XCTUnwrap(sample["source"] as? String)
                let prior = try XCTUnwrap(sample["proposal"] as? [String: Any])
                let targetID = try XCTUnwrap(prior["targetID"] as? String)
                let rawOutput = try XCTUnwrap(calls.compactMap { $0["rawOutput"] as? String }.first { value in
                    guard let parsed = try? JSONDecoder().decode(JSONValue.self, from: Data(value.utf8)) else { return false }
                    return parsed["targetID"]?.string == targetID
                })
                let target = try proposal(text, replacement: raw, targetID: targetID).target
                let original = try PassageRevisionValidator.parse(rawOutput, target: target,
                    sourceIDs: ["current-question", "selected-passage"], memoryIDs: [])
                let before = DocumentWorkCapability.verify(proposal: original, text: text, sourceRevision: 3,
                    requirements: target.requirements)
                XCTAssertEqual(before.checks.filter { !$0.passed }.map(\.id), ["links"])
                let fixed = try XCTUnwrap(DocumentURLBoundaryPreservation.restore(original, text: text, sourceRevision: 3))
                XCTAssertTrue(DocumentWorkCapability.verify(proposal: fixed.proposal, text: text,
                    sourceRevision: 3, requirements: target.requirements).canApply)
                outcomes.append(["inputReceipt": path, "contextLabel": sample["contextLabel"] as? String ?? "unknown",
                    "originalLiveResult": sample["result"] as? String ?? "unknown", "rawReplacement": original.replacement,
                    "restoredCandidate": fixed.proposal.replacement, "rawStillFailsLinkCheck": true,
                    "restoredPassesUnchangedMechanicalChecks": true, "applied": false,
                    "rawOutputDigest": WorkingCopyEditReceipt.digest(rawOutput),
                    "restoration": try JSONSerialization.jsonObject(with: JSONEncoder().encode(fixed.restoration))])
            }
            XCTAssertEqual(try Data(contentsOf: url), bytes, "Offline replay must not rewrite live evidence.")
        }
        XCTAssertEqual(outcomes.count, 4)
        if let output = ProcessInfo.processInfo.environment["ARCHI_URL_BOUNDARY_REPLAY_OUTPUT"] {
            let expected = root.appendingPathComponent("output/hampton-method-guidance-2026-09-26/url-boundary-offline-replay.json")
            XCTAssertEqual(URL(fileURLWithPath: output).standardizedFileURL, expected.standardizedFileURL)
            guard URL(fileURLWithPath: output).standardizedFileURL == expected.standardizedFileURL else { return }
            let report: [String: Any] = ["schema": "archi-url-boundary-offline-replay/v1", "modelCalls": 0,
                "scope": "Offline deterministic candidate restoration from four retained failures. Original live results remain failed and immutable; no new model success or automatic Apply is claimed.",
                "cases": outcomes]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: expected, options: .atomic)
        }
    }

    private func proposal(_ text: String, replacement: String, range: NSRange? = nil,
                          targetID: String = UUID().uuidString,
                          requirements: DocumentWorkRequirements = .init(mustBeShorter: true, preserveNumbersAndLinks: true)) throws -> PassageRevisionProposal {
        let selection = try XCTUnwrap(DocumentSelection(range: range ?? NSRange(location: 0, length: text.utf16.count), text: text, sourceRevision: 3))
        let target = try XCTUnwrap(RevisionTarget(text: text, sourceRevision: 3, selection: selection, id: targetID, requirements: requirements))
        return PassageRevisionProposal(target: target, decision: .propose, replacement: replacement,
            explanation: "Synthetic revision for boundary checks.", sourceIDs: ["selected-passage"], memoryIDs: [])
    }
}

@MainActor private final class URLBoundaryRoleClient: LocalRoleClient {
    let replacement: String
    private(set) var calls = 0
    private(set) var rawOutput: String?
    init(replacement: String) { self.replacement = replacement }
    func connect() async throws {}
    func disconnect() {}
    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
        calls += 1
        let targetID = try XCTUnwrap(request.input["context"]?["revisionTarget"]?["id"]?.string)
        let value: JSONValue = .object(["schema": .string("native-passage-revision/v1"), "targetID": .string(targetID),
            "decision": .string("PROPOSE"), "replacement": .string(replacement), "explanation": .string("Synthetic shortening."),
            "sourceIDs": .array([.string("selected-passage")]), "memoryIDs": .array([])])
        let text = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        rawOutput = text
        return LocalRoleResult(requestID: request.id, role: request.role, text: text,
            model: .init(name: "boundary-fixture", family: "fixture", parameterSize: "fixture", quantization: "fixture", digest: String(repeating: "b", count: 64)),
            elapsedMilliseconds: 7, metrics: .init(inputTokens: 123, outputTokens: 45))
    }
}

@MainActor private final class URLBoundaryRefusedClient: AssistantClient, LocalRoleClient {
    private(set) var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.configuration }
    func disconnect() {}
    func shutdown() async {}
    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
        calls += 1; throw AssistantFailure.configuration
    }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; throw AssistantFailure.configuration
    }
}
