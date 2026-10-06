import Foundation
import CryptoKit
import XCTest
@testable import ARCHiDesktop

/// Opt-in development verification of revised URL-boundary guidance. The exact
/// prior generated method is reconstituted and reused; no new method is drafted.
final class KnowledgeMethodGuidanceLiveTests: XCTestCase {
    @MainActor
    func testExistingGeneratedMethodWithRevisedGuidanceOnTwoNewPassages() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ARCHI_METHOD_GUIDANCE_LIVE"] == "1",
              let outputPath = environment["ARCHI_METHOD_GUIDANCE_OUTPUT"] else {
            throw XCTSkip("Set ARCHI_METHOD_GUIDANCE_LIVE=1 and ARCHI_METHOD_GUIDANCE_OUTPUT to authorize at most two local generations.")
        }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let expectedOutput = repository.appendingPathComponent("output/hampton-method-guidance-2026-09-26")
            .standardizedFileURL.resolvingSymlinksInPath()
        let output = URL(fileURLWithPath: outputPath, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        guard output == expectedOutput else { throw GuidanceLiveFailure("Use the predeclared method-guidance evidence directory.") }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let marker = output.appendingPathComponent("attempt-started.json")
        guard !FileManager.default.fileExists(atPath: marker.path) else {
            throw XCTSkip("This bounded demonstration already started. No retries or further model calls are allowed by this test.")
        }
        let priorURL = repository.appendingPathComponent("output/hampton-method-transfer-2026-09-26/transfer-receipt.json")
        let priorBytes = try Data(contentsOf: priorURL)
        let priorDigest = SHA256.hash(data: priorBytes).map { String(format: "%02x", $0) }.joined()
        try Self.require(priorDigest == Self.priorReceiptDigest, "The original transfer receipt changed; no inference is allowed.")
        let prior = try XCTUnwrap(JSONSerialization.jsonObject(with: priorBytes) as? [String: Any])
        let priorDraft = try XCTUnwrap(prior["draft"] as? [String: Any])
        let priorPage = try XCTUnwrap(prior["knowledgePage"] as? [String: Any])
        try Self.require(priorDraft["instruction"] as? String == Self.instruction
            && priorPage["body"] as? String == Self.concept
            && prior["supportingPassage"] as? String == Self.principle,
            "The reconstituted instruction and concept must match the original receipt bytes.")
        let plan = Self.plan()
        let planBytes = try JSONSerialization.data(withJSONObject: plan, options: [.prettyPrinted, .sortedKeys])
        try planBytes.write(to: output.appendingPathComponent("evaluation-plan.json"), options: .withoutOverwriting)
        try JSONSerialization.data(withJSONObject: ["startedAt": ISO8601DateFormatter().string(from: Date()),
            "maximumGenerations": 2, "maximumRetries": 0], options: [.sortedKeys])
            .write(to: marker, options: .withoutOverwriting)
        let evidence = GuidanceEvidence(url: output.appendingPathComponent("guidance-receipt.json"), plan: plan)
        evidence.report["priorGeneratedMethodBinding"] = prior["savedMethodBinding"]
        evidence.report["priorReceiptSHA256"] = priorDigest
        evidence.report["newDraftGenerations"] = 0
        evidence.report["reconstitutedIdentity"] = "New disposable-profile IDs; the original generated instruction and concept text are byte-identical. The new candidate binding stays unchanged across both uses."
        try evidence.save()

        let profile = FileManager.default.temporaryDirectory.appendingPathComponent("archi-method-guidance-live-\(UUID())")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: profile) }
        let preferencesURL = profile.appendingPathComponent("preferences.json")
        var preferences = CompanionPreferences()
        preferences.tone = "Direct"; preferences.replyLength = 0.3; preferences.reduceMotion = true
        try NativePreferenceDocument(preferences: preferences).encoded().write(to: preferencesURL)
        let recorder = GuidanceRecordingClient(evidence: evidence)
        let denied = GuidanceNoOtherClient()
        let local = HamptonReasonsAssistant(reasoner: recorder, contextSelector: denied, contextEnabled: false)
        let store = CompanionStore(preferenceURL: preferencesURL, assistant: local,
            assistantFactory: { _, _ in denied }, allowsPlay: false)
        store.setAssistantRoute(.automatic)
        store.setLocalWorkPreference(.reasoning)
        let initialEvolutionRevision = store.evolution.revision
        let requirements = DocumentWorkRequirements(mustBeShorter: true, preserveNumbersAndLinks: true)

        func checkpoint() throws {
            evidence.report["documentRecords"] = try Self.json(store.documentWork.records)
            evidence.report["methods"] = try Self.json(store.documentProcedures.procedures)
            evidence.report["usageTasks"] = try Self.json(store.tokenSteward.tasks)
            evidence.report["costObservations"] = try Self.json(store.tokenSteward.observations)
            evidence.report["otherClientConnections"] = denied.connections
            evidence.report["otherClientGenerations"] = denied.generations
            evidence.report["externalReplies"] = denied.replies
            evidence.report["status"] = store.status
            evidence.report["workingCopy"] = store.sharedText
            evidence.report["lessonsKept"] = store.keptLessons.count
            evidence.report["usefulEvolutionReceipts"] = store.evolution.usefulReceipts.count
            evidence.report["evolutionRevisionUnchanged"] = store.evolution.revision == initialEvolutionRevision
            try evidence.save()
        }
        do {
            try Self.require(store.activeQiMon == nil && store.keptLessons.isEmpty,
                "A disposable profile must have no personal companion or lessons.")
            try Self.require(!local.contextEnabled && store.localWorkPreference == .reasoning,
                "Only the production local reasoning lane may generate.")
            let source = try store.readingSources.keep(title: "Synthetic direct-request principle", text: Self.principle)
            let anchor = try store.readingSources.makeAnchor(sourceID: source.id,
                range: NSRange(location: 0, length: source.text.utf16.count))
            let authored = try store.readingSources.saveKnowledgePage(title: "Direct polite actions",
                body: Self.concept, kind: .concept, anchors: [anchor])
            let page = try store.readingSources.reviewKnowledgePage(id: authored.id, expectedRevision: authored.revision)
            evidence.report["knowledgePage"] = try Self.json(page)
            evidence.report["supportingPassage"] = source.text
            evidence.report["result"] = "preparing-existing-method"
            evidence.report["unchangedInstruction"] = Self.instruction
            evidence.report["unchangedInstructionSHA256"] = LessonSource.digest(of: Self.instruction)
            try checkpoint()
            try Self.require(recorder.attempts == 0, "Reconstituting the saved method must not generate text.")
            try Self.require(store.documentProcedures.latestProcedures.isEmpty && store.documentWork.records.isEmpty,
                "The disposable profile must begin without saved methods or work.")
            try Self.require(store.keepKnowledgeProcedure(page: page, title: "Synthetic direct polite actions",
                instruction: Self.instruction, requirements: requirements), "Explicit candidate save failed.")
            let method = try XCTUnwrap(store.documentProcedures.latestProcedures.first)
            try Self.require(method.instruction.utf8.elementsEqual(Self.instruction.utf8)
                && method.knowledgeOrigin == page.binding, "The kept candidate must preserve the original instruction and exact recreated concept binding.")
            evidence.report["savedMethodBinding"] = try Self.json(method.binding)
            var results: [[String: Any]] = []
            for sample in Self.samples {
                var result: [String: Any] = ["contextLabel": sample.label, "source": sample.text,
                    "requiredAction": sample.action, "requiredLiteralPhrases": sample.required,
                    "semanticUsefulness": "UNREVIEWED", "helpfulFeedback": "UNREVIEWED", "result": "not-started"]
                do {
                    // The two passages have not entered any prior model request.
                    store.share(text: sample.text, name: sample.label + ".txt")
                    store.selectText(range: NSRange(location: 0, length: sample.text.utf16.count), sourceRevision: store.sourceRevision)
                    store.preparePassageRevision(shorten: true)
                    store.documentRequirements = requirements
                    try Self.require(store.prepareDocumentProcedure(method.binding), "The saved method was not prepared.")
                    try Self.require(store.prompt.utf8.elementsEqual(Self.instruction.utf8), "The method changed between uses.")
                    let selection = try XCTUnwrap(store.textSelection)
                    let target = try XCTUnwrap(RevisionTarget(text: sample.text, sourceRevision: store.sourceRevision,
                        selection: selection, requirements: requirements))
                    let identity = PassageRevisionProposal(target: target, decision: .propose,
                        replacement: sample.text, explanation: "Unchanged-input baseline; no inference.",
                        sourceIDs: ["selected-passage"], memoryIDs: [])
                    result["identityBaseline"] = Self.evaluate(identity, sample: sample)
                    result["unchangedInstruction"] = store.prompt
                    result["result"] = "running"
                    evidence.report["activeSample"] = result
                    try checkpoint()
                    store.submit()
                    try await wait(store: store, seconds: 210)
                    result["lane"] = Self.laneJSON(store.compareResults[.qwen])
                    let lane = try XCTUnwrap(store.compareResults[.qwen])
                    let receipt = try XCTUnwrap(lane.receipt)
                    result["requestID"] = receipt.requestID
                    try Self.require(lane.state == .complete && receipt.admissionOutcome?.status == .accepted,
                        "The local revision did not complete with an admitted proposal.")
                    let proposal = try XCTUnwrap(lane.revision)
                    result["proposal"] = ["decision": proposal.decision.rawValue, "replacement": proposal.replacement,
                        "explanation": proposal.explanation, "sourceIDs": proposal.sourceIDs,
                        "targetID": proposal.target.id]
                    let evaluation = Self.evaluate(proposal, sample: sample)
                    result["evaluation"] = evaluation
                    let checked = store.documentVerification(proposal)
                    result["productionMechanicalChecks"] = checked.checks.map {
                        ["id": $0.id, "title": $0.title, "passed": $0.passed] as [String: Any]
                    }
                    let record = try XCTUnwrap(store.documentRecord(requestID: receipt.requestID, provider: .qwen))
                    try Self.require(record.procedureUse == method.binding && record.feedback == nil,
                        "The use must retain the unchanged method and remain unreviewed.")
                    let passed = evaluation["allObjectiveRulesPassed"] as? Bool == true && checked.canApply
                    result["result"] = passed ? "objective-rules-passed" : "objective-rules-failed"
                    result["appliedInDisposableProfile"] = false
                    if passed && store.canApplyDocumentRevision(provider: .qwen, proposal: proposal) {
                        store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
                        let applied = try XCTUnwrap(store.documentWork.records.first { $0.id == record.id })
                        try Self.require(applied.state == .applied && applied.feedback == nil
                            && store.sharedText.utf8.elementsEqual(proposal.replacement.utf8), "Synthetic Apply did not retain exact proposed bytes.")
                        result["appliedInDisposableProfile"] = true
                    }
                } catch {
                    result["result"] = "failed"
                    result["failure"] = error.localizedDescription
                    result["lane"] = Self.laneJSON(store.compareResults[.qwen])
                    store.cancelWork()
                }
                results.append(result)
                evidence.report["samples"] = results
                evidence.report.removeValue(forKey: "activeSample")
                try checkpoint()
            }
            try Self.require(recorder.attempts == 2 && denied.connections == 0 && denied.generations == 0 && denied.replies == 0,
                "The fixed local-only generation budget was violated.")
            try Self.require(store.keptLessons.isEmpty && store.evolution.usefulReceipts.isEmpty
                && store.evolution.revision == initialEvolutionRevision && store.documentWork.records.allSatisfy { $0.feedback == nil },
                "Synthetic guidance verification must not award usefulness, lessons or personal growth.")
            let passing = results.filter { $0["result"] as? String == "objective-rules-passed" }.count
            evidence.report["objectivePassCount"] = passing
            evidence.report["objectiveSampleCount"] = results.count
            evidence.report["result"] = passing == 2 ? "completed-two-objective-passes" : "completed-with-failed-rules-or-operations"
            try checkpoint()
            await store.shutdownAssistant()
            try Self.require(passing == 2, "The predeclared guidance verification did not pass both cases. Inspect retained failure evidence; do not retry.")
        } catch {
            if evidence.report["result"] as? String != "completed-with-failed-rules-or-operations" {
                evidence.report["result"] = "failed-before-completing-guidance-check"
            }
            evidence.report["failure"] = error.localizedDescription
            store.cancelWork()
            try? checkpoint()
            await store.shutdownAssistant()
            throw error
        }
    }

    private static let principle = "A vague request can be made easier to act on by stating the requested action directly and politely. Remove introductory hedging without inventing actions, recipients or facts. Preserve the original action, object, exact deadline wording, every number and every link."
    private static let concept = "Replace vague requests with direct polite actions while preserving the requested action, exact deadlines, numbers and links. Removing introductory padding may shorten a request without changing its commitments."
    private struct Sample {
        let label: String
        let text: String
        let action: String
        let required: [String]
    }
    private static let instruction = "When editing a passage, replace vague requests with direct, polite actions that state the requested action clearly. Preserve every exact number, link, and deadline wording from the original text without inventing new details or recipients. Remove introductory hedging or padding to shorten the request while keeping all commitments intact."
    private static let priorReceiptDigest = "d8e7876ec45f46c9c1aab4c401f4c870076a8b12ce20cc7577f1d01467b29973"
    private static let samples = [
        Sample(label: "maintenance-handoff", text: "I was hoping you might be able to please upload 4 photos to the maintenance folder by Thursday at 16:30 using https://example.com/maintenance .",
            action: "upload", required: ["4 photos", "maintenance folder", "Thursday at 16:30", "https://example.com/maintenance"]),
        Sample(label: "lunch-planning", text: "I wanted to check whether you could perhaps please send 2 menu options to the lunch coordinator by Monday at 10:15 using https://example.com/lunch .",
            action: "send", required: ["2 menu options", "lunch coordinator", "Monday at 10:15", "https://example.com/lunch"])
    ]
    @MainActor private static func plan() -> [String: Any] {
        ["schema": "archi-method-guidance-predeclared/v1", "declaredBeforeGeneration": true,
         "scope": "Development verification of revised URL-boundary guidance using the exact previously generated method on two new ordinary synthetic passages. No new draft generation, cloud, puzzles, retries, personal profile or personal growth. This is not an untouched generalization benchmark.",
         "maximumGenerations": 2, "maximumRetries": 0, "configuredModel": QwenAssistant.defaultModel,
         "principle": principle, "concept": concept, "unchangedInstruction": instruction,
         "unchangedInstructionSHA256": LessonSource.digest(of: instruction), "priorReceiptSHA256": priorReceiptDigest,
         "revisionSystemGuidance": AssistantInstructions.passageRevisionText,
         "requirements": ["mustBeShorter": true, "preserveNumbersAndLinks": true],
         "samples": samples.map { ["contextLabel": $0.label, "source": $0.text,
             "requiredAction": $0.action, "requiredLiteralPhrases": $0.required] as [String: Any] },
         "objectiveEvaluator": "Production mechanical checks must pass, including shorter text and exact number/link multisets. Replacement must start with Please or Kindly followed immediately by the original action verb (case-insensitive), retain each case's exact literal object/deadline/link phrases, and contain no standalone not, never, no, don't or cannot. This is a conservative lexical check, not a semantic entailment judge.",
         "baseline": "Identity: leave each input unchanged, evaluated by the same pure checks with zero model calls. No comparison with an unaided model or claim of model superiority.",
         "feedbackPolicy": "Semantic usefulness and Helpful feedback remain UNREVIEWED even if objective checks pass. Apply is permitted only in the disposable profile after all objective checks. No learning-review action or usefulness credit.",
         "limitations": "Two fixed development examples after a targeted guidance change; no random sample, human review, model baseline, untouched generalization benchmark or personal development claim. A failed lexical rule can reject a semantically acceptable paraphrase. Missing failure metrics remain unknown, never zero.",
         "connectionAndGenerationWaitSeconds": 210]
    }
    private static func evaluate(_ proposal: PassageRevisionProposal, sample: Sample) -> [String: Any] {
        let text = proposal.replacement
        let lower = text.lowercased()
        let politeAction = ["please \(sample.action)", "kindly \(sample.action)"].contains {
            lower == $0 || lower.hasPrefix($0 + " ")
        }
        let literalChecks = sample.required.map { ["literal": $0, "preserved": text.contains($0)] as [String: Any] }
        let words = lower.split { !$0.isLetter && $0 != "'" }.map(String.init)
        let noNegation = Set(words).isDisjoint(with: ["not", "never", "no", "don't", "cannot"])
        let mechanical = DocumentWorkCapability.verify(proposal: proposal, text: sample.text,
            sourceRevision: proposal.target.selection.sourceRevision, requirements: proposal.target.requirements)
        return ["directPoliteOriginalAction": politeAction, "literalPreservation": literalChecks,
            "noNegationToken": noNegation, "mechanicalPass": mechanical.canApply,
            "characterCountBefore": sample.text.count, "characterCountAfter": text.count,
            "allObjectiveRulesPassed": politeAction && noNegation && mechanical.canApply && sample.required.allSatisfy(text.contains)]
    }
    @MainActor private func wait(store: CompanionStore, seconds: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while store.isWorking {
            guard ContinuousClock.now < deadline else { throw GuidanceLiveFailure("The bounded local operation timed out.") }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw GuidanceLiveFailure(message) }
    }
    private static func json<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }
    @MainActor private static func laneJSON(_ lane: AssistantLaneResult?) -> [String: Any] {
        guard let lane else { return ["state": "not-created"] }
        return ["state": lane.state.rawValue, "status": lane.status, "text": lane.text,
            "requestID": lane.receipt?.requestID as Any? ?? NSNull(),
            "admission": lane.receipt?.admissionOutcome?.status.rawValue as Any? ?? NSNull(),
            "invocations": (lane.receipt?.localInvocationReceipts ?? []).map(GuidanceEvidence.invocationJSON)]
    }
}

@MainActor private final class GuidanceEvidence {
    let url: URL
    var report: [String: Any]
    var calls: [[String: Any]] = []
    init(url: URL, plan: [String: Any]) {
        self.url = url
        report = ["schema": "archi-method-guidance-live-receipt/v1", "plan": plan,
            "result": "not-started", "semanticUsefulness": "UNREVIEWED", "dollarCost": NSNull(), "energyCost": NSNull()]
    }
    func save() throws {
        report["generationAttempts"] = calls.count
        report["rawCalls"] = calls
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: url, options: .atomic)
    }
    static func invocationJSON(_ value: HamptonInvocationReceipt) -> [String: Any] {
        ["id": value.id, "role": value.role.rawValue, "outcome": value.outcome.rawValue,
         "model": value.model?.name as Any? ?? NSNull(), "modelDigest": value.model?.digest as Any? ?? NSNull(),
         "inputDigest": value.inputDigest, "outputDigest": value.outputDigest as Any? ?? NSNull(),
         "elapsedMilliseconds": value.elapsedMilliseconds as Any? ?? NSNull(),
         "inputTokens": value.metrics?.inputTokens as Any? ?? NSNull(),
         "outputTokens": value.metrics?.outputTokens as Any? ?? NSNull()]
    }
}

@MainActor private final class GuidanceRecordingClient: LocalRoleClient {
    private let client = QwenAssistant(runtime: LocalQwenRuntime.shared)
    private let evidence: GuidanceEvidence
    var attempts: Int { evidence.calls.count }
    var representationAccess: LocalRepresentationAccess { client.representationAccess }
    init(evidence: GuidanceEvidence) { self.evidence = evidence }
    func connect() async throws { try await client.connect() }
    func disconnect() { client.disconnect() }
    func shutdown() async { await client.shutdown() }
    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
        guard request.role == .reasoning, attempts < 2 else { throw GuidanceLiveFailure("Two-generation reasoning-only budget reached.") }
        let index = attempts
        let started = ContinuousClock.now
        let encoded = try JSONEncoder().encode(request.input)
        evidence.calls.append(["ordinal": index + 1, "requestID": request.id, "role": request.role.rawValue,
            "startedAt": ISO8601DateFormatter().string(from: Date()), "status": "dispatched",
            "rawInput": String(decoding: encoded, as: UTF8.self), "systemInstruction": request.systemInstruction,
            "rawOutput": NSNull(), "inputTokens": NSNull(), "outputTokens": NSNull(), "elapsedMilliseconds": NSNull()])
        try evidence.save() // The hard counter is durable before any model call.
        do {
            let result = try await client.generate(request)
            evidence.calls[index]["status"] = "completed-transport"
            evidence.calls[index]["rawOutput"] = result.text
            evidence.calls[index]["model"] = result.model.name
            evidence.calls[index]["modelDigest"] = result.model.digest
            evidence.calls[index]["elapsedMilliseconds"] = result.elapsedMilliseconds
            evidence.calls[index]["inputTokens"] = result.metrics?.inputTokens as Any? ?? NSNull()
            evidence.calls[index]["outputTokens"] = result.metrics?.outputTokens as Any? ?? NSNull()
            evidence.calls[index]["malformedMetricFields"] = result.metrics?.malformedFields as Any? ?? NSNull()
            try evidence.save()
            return result
        } catch {
            let elapsed = started.duration(to: .now).components
            evidence.calls[index]["status"] = "failed-or-cancelled-transport"
            evidence.calls[index]["failure"] = error.localizedDescription
            evidence.calls[index]["elapsedMilliseconds"] = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
            evidence.calls[index]["unavailableFailureOutputOrMetrics"] = "The production transport did not return a completed result; absent raw output or metrics remain unknown."
            try? evidence.save()
            throw error
        }
    }
}

@MainActor private final class GuidanceNoOtherClient: AssistantClient, LocalRoleClient {
    private(set) var connections = 0
    private(set) var generations = 0
    private(set) var replies = 0
    func connect() async throws { connections += 1; throw AssistantFailure.configuration }
    func disconnect() {}
    func shutdown() async {}
    func generate(_ request: LocalRoleRequest) async throws -> LocalRoleResult {
        generations += 1; throw AssistantFailure.configuration
    }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        replies += 1; throw AssistantFailure.configuration
    }
}

private struct GuidanceLiveFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
