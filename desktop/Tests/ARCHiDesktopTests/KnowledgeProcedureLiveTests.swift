import Foundation
import XCTest
@testable import ARCHiDesktop

/// One explicitly enabled local generation through the production owners.
/// The source, knowledge page, method, edit, and objective review are synthetic
/// and live only in a disposable profile. This is not personal learning or UI QA.
final class KnowledgeProcedureLiveTests: XCTestCase {
    @MainActor
    func testOneLocalKnowledgeMethodRevisionHasCheckedReviewedCostEvidence() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ARCHI_KNOWLEDGE_LIVE"] == "1",
              let outputPath = environment["ARCHI_KNOWLEDGE_LIVE_OUTPUT"], !outputPath.isEmpty else {
            throw XCTSkip("Set ARCHI_KNOWLEDGE_LIVE=1 and ARCHI_KNOWLEDGE_LIVE_OUTPUT for one local knowledge-method generation.")
        }
        let output = URL(fileURLWithPath: outputPath, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        guard output.path.hasPrefix("/private/tmp/") || output.path.hasPrefix(temporary + "/") else {
            throw KnowledgeProcedureLiveFailure("The evidence directory must be under a temporary directory.")
        }
        let reportURL = output.appendingPathComponent("knowledge-procedure-live.json")
        guard !FileManager.default.fileExists(atPath: reportURL.path) else {
            throw XCTSkip("This evidence directory already contains its one-generation receipt. No retry was started.")
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let profile = FileManager.default.temporaryDirectory.appendingPathComponent("archi-knowledge-procedure-live-\(UUID())")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: profile) }
        let preferenceURL = profile.appendingPathComponent("preferences.json")
        var preferences = CompanionPreferences()
        preferences.tone = "Direct"; preferences.replyLength = 0.2; preferences.reduceMotion = true
        try NativePreferenceDocument(preferences: preferences).encoded().write(to: preferenceURL)
        let local = HamptonReasonsAssistant(contextEnabled: false, nativeRuntime: .shared)
        let refused = KnowledgeProcedureNoExternalClient()
        let store = CompanionStore(preferenceURL: preferenceURL, assistant: local,
            assistantFactory: { _, _ in refused }, allowsPlay: false)
        store.setLocalWorkPreference(.reasoning)

        let passage = "I would like to ask you if you would please close the door."
        let expected = "Please close the door."
        let instruction = "Shorten the selected passage to one short sentence. Preserve its request to close the door. For this synthetic check, set the replacement to exactly: Please close the door."
        let requirements = DocumentWorkRequirements(mustBeShorter: true, preserveNumbersAndLinks: false)
        let initialEvolutionRevision = store.evolution.revision
        var checks: [String: Bool] = [:]
        var phases: [String: Bool] = [
            "methodKept": false, "requestSubmitted": false, "generationCompleted": false,
            "proposalAdmitted": false, "mechanicallyChecked": false, "exactTargetMatched": false,
            "applyRequested": false, "applied": false, "helpfulReviewRecorded": false
        ]
        var capturedInvocations: [HamptonInvocationReceipt] = []
        var capturedRoles: [LocalModelRole] = []
        var capturedValidatedReceiptCount = 0
        var report: [String: Any] = [
            "schema": "archi-knowledge-procedure-local-demonstration/v1",
            "scope": "One synthetic knowledge-derived method and one local passage-revision request through production owners. No personal profile or native UI qualification.",
            "route": "local", "configuredModel": QwenAssistant.defaultModel,
            "maximumGenerations": 1, "maximumRetries": 0, "contextEnabled": false,
            "configuredContextTokenLimit": HamptonInvocationPolicy.contextTokens,
            "configuredOutputTokenLimit": HamptonInvocationPolicy.outputTokens,
            "configuredTemperature": HamptonInvocationPolicy.temperature,
            "connectionWaitLimitSeconds": 30, "generationWaitLimitSeconds": 190,
            "source": passage, "expectedReplacement": expected, "instruction": instruction,
            "reviewPolicy": "Scripted synthetic Helpful review is permitted only after exact replacement bytes, all mechanical checks, and a retained applied outcome. This is not a human usefulness judgment.",
            "dollarCost": NSNull(), "energyCost": NSNull(), "result": "not-started"
        ]
        func verify(_ name: String, _ condition: Bool, fatal: Bool = true) throws {
            checks[name] = condition
            if fatal && !condition { throw KnowledgeProcedureLiveFailure(name) }
        }
        func captureInvocationEvidence() {
            let snapshot = local.snapshot
            if !snapshot.attemptedInvocations.isEmpty || capturedRoles.isEmpty {
                capturedInvocations = snapshot.invocations
                capturedRoles = snapshot.attemptedInvocations
                capturedValidatedReceiptCount = snapshot.receipts.count
            }
        }
        func saveReport() throws {
            captureInvocationEvidence()
            report["checks"] = checks
            report["phases"] = phases
            report["externalCalls"] = refused.calls
            report["attemptedRoles"] = capturedRoles.map(\.rawValue)
            report["invocationCount"] = capturedInvocations.count
            report["validatedReceiptCount"] = capturedValidatedReceiptCount
            report["invocations"] = capturedInvocations.map(Self.invocationJSON)
            report["documentRecords"] = try Self.json(store.documentWork.records)
            report["methods"] = try Self.json(store.documentProcedures.procedures)
            report["usageTasks"] = try Self.json(store.tokenSteward.tasks)
            report["costObservations"] = try Self.json(store.tokenSteward.observations)
            report["workingCopy"] = store.sharedText
            report["status"] = store.status
            report["documentWorkMessage"] = store.documentWorkMessage as Any? ?? NSNull()
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: reportURL, options: .atomic)
        }
        do {
            try verify("disposableProfileHasNoPersonalIdentityOrLessons", store.activeQiMon == nil && store.keptLessons.isEmpty)
            try verify("localReasoningOnly", store.route == .local && store.localWorkPreference == .reasoning && !local.contextEnabled)
            let source = try store.readingSources.keep(title: "Synthetic concise-request rule",
                text: "A verbose request can be shortened by stating the requested action directly and politely.")
            let anchor = try store.readingSources.makeAnchor(sourceID: source.id,
                range: NSRange(location: 0, length: source.text.utf16.count))
            try verify("knowledgeDraftSaved", store.saveKnowledgePage(prior: nil,
                title: "Synthetic concise requests", body: "For a polite request, keep the requested action and remove introductory padding.",
                kind: .concept, anchors: [anchor]))
            store.reviewKnowledgePage(try XCTUnwrap(store.readingSources.latestKnowledgePages.first))
            let page = try XCTUnwrap(store.readingSources.latestKnowledgePages.first)
            try verify("knowledgePageReviewedAndCurrent", page.state == .reviewed && store.readingSources.availability(of: page) == nil)
            report["knowledgePage"] = try Self.json(page)
            report["sourceBinding"] = try Self.json(source.binding)
            try verify("knowledgeMethodKept", store.keepKnowledgeProcedure(page: page,
                title: "Synthetic concise request", instruction: instruction, requirements: requirements))
            let method = try XCTUnwrap(store.documentProcedures.latestProcedures.first)
            phases["methodKept"] = true
            report["methodBinding"] = try Self.json(method.binding)
            report["knowledgeBinding"] = try Self.json(page.binding)
            try verify("methodRetainsExactKnowledgeVersion", method.knowledgeOrigin == page.binding)
            try verify("methodAvailableBeforeUse", store.documentProcedureUnavailable(method.binding) == nil)
            try verify("authoringDidNotGenerateOrInventWork", local.snapshot.attemptedInvocations.isEmpty && store.documentWork.records.isEmpty)

            store.share(text: passage, name: "synthetic-knowledge-method.txt")
            store.selectText(range: NSRange(location: 0, length: passage.utf16.count), sourceRevision: store.sourceRevision)
            store.preparePassageRevision(shorten: true)
            store.documentRequirements.preserveNumbersAndLinks = false
            try verify("methodPrepared", store.prepareDocumentProcedure(method.binding))
            try verify("exactInstructionPrepared", store.prompt.utf8.elementsEqual(instruction.utf8))
            store.connectAssistant(provider: .qwen)
            try await wait(seconds: 30) { store.connection(for: .qwen) != .connecting }
            try verify("localConnectionReady", store.connection(for: .qwen) == .ready)
            report["result"] = "running"
            try saveReport()
            phases["requestSubmitted"] = true
            store.submit()
            try await wait(seconds: 190) { !store.isWorking }
            captureInvocationEvidence()
            phases["generationCompleted"] = capturedInvocations.contains { $0.outcome == .completed }
            try saveReport()

            let lane = try XCTUnwrap(store.compareResults[.qwen])
            report["laneState"] = lane.state.rawValue
            report["laneStatus"] = lane.status
            let receipt = try XCTUnwrap(lane.receipt)
            report["requestID"] = receipt.requestID
            report["requestBinding"] = try Self.json(EvolutionRequestBinding(receipt: receipt))
            report["sourceDigest"] = receipt.sourceDigest as Any? ?? NSNull()
            try verify("oneCompletedLocalReasoningInvocation", capturedRoles == [.reasoning]
                && capturedInvocations.count == 1 && capturedInvocations.first?.outcome == .completed
                && receipt.localInvocations == [.reasoning] && capturedValidatedReceiptCount == 1)
            try verify("noExternalRoute", refused.calls == 0 && store.compareResults[.codex] == nil)
            try verify("admittedCompletedLane", lane.state == .complete && receipt.state == .complete
                && receipt.admissionOutcome?.status == .accepted)
            let proposal = try XCTUnwrap(lane.revision)
            phases["proposalAdmitted"] = true
            report["proposal"] = ["decision": proposal.decision.rawValue, "replacement": proposal.replacement,
                "explanation": proposal.explanation, "targetID": proposal.target.id]
            let verification = store.documentVerification(proposal)
            phases["mechanicallyChecked"] = verification.canApply
            report["mechanicalChecks"] = verification.checks.map { ["id": $0.id, "title": $0.title, "passed": $0.passed] as [String: Any] }
            let exactTarget = proposal.replacement.utf8.elementsEqual(expected.utf8)
            phases["exactTargetMatched"] = exactTarget
            try verify("allMechanicalChecksPass", verification.canApply)
            try verify("objectiveExactReplacement", exactTarget)
            let preparedRecord = try XCTUnwrap(store.documentRecord(requestID: receipt.requestID, provider: .qwen))
            try verify("requestRetainsExactMethodVersion", preparedRecord.procedureUse == method.binding)
            try verify("noApplyOrReviewBeforeExplicitAction", store.sharedText == passage
                && preparedRecord.state == .ready && preparedRecord.feedback == nil)
            try verify("ownerAllowsApply", store.canApplyDocumentRevision(provider: .qwen, proposal: proposal))
            phases["applyRequested"] = true
            store.applyPassageRevision(provider: .qwen, targetID: proposal.target.id)
            let applied = try XCTUnwrap(store.documentWork.records.first { $0.id == preparedRecord.id })
            phases["applied"] = applied.state == .applied && store.sharedText.utf8.elementsEqual(expected.utf8)
            try verify("appliedBytesAndReceiptMatch", phases["applied"] == true
                && applied.actualAfterDigest == applied.expectedAfterDigest && applied.feedback == nil)
            try verify("objectiveHelpfulReviewSaved", store.reviewDocument(id: applied.id, verdict: .helpful))
            let reviewed = try XCTUnwrap(store.documentWork.records.first { $0.id == applied.id })
            phases["helpfulReviewRecorded"] = reviewed.feedback?.verdict == .helpful
            try verify("reviewKeepsExactMethodBinding", phases["helpfulReviewRecorded"] == true && reviewed.procedureUse == method.binding)
            try verify("reviewAccountedByUsage", store.documentFeedbackUsageCurrent(reviewed))
            let metrics = try XCTUnwrap(capturedInvocations.first?.metrics)
            try verify("measuredLocalCostPresent", (metrics.inputTokens ?? 0) > 0 && (metrics.outputTokens ?? 0) > 0 && metrics.malformedFields.isEmpty)
            let cost = HamptonMethodResourceOutcomes(procedure: method.binding, records: store.documentWork.records,
                tasks: store.tokenSteward.tasks, observations: store.tokenSteward.observations)
            if let cost {
                report["methodCost"] = ["totalTokens": cost.totalTokens, "recordedUses": cost.recordedUses,
                    "localAttempts": cost.localAttempts, "helpfulResults": cost.helpfulResults,
                    "comparisonSignature": cost.comparisonSignature] as [String: Any]
            } else { report["methodCost"] = NSNull() }
            try verify("oneMeasuredReviewedMethodUse", cost?.recordedUses == 1 && cost?.localAttempts == 1 && cost?.helpfulResults == 1)
            try verify("noPersonalGrowthOrAdditionalGeneration", store.activeQiMon == nil && store.keptLessons.isEmpty
                && store.evolution.revision == initialEvolutionRevision && store.evolution.usefulReceipts.isEmpty
                && capturedRoles == [.reasoning] && refused.calls == 0)
            report["result"] = "passed"
            try saveReport()
            await store.shutdownAssistant()
        } catch {
            report["result"] = "failed"
            report["failure"] = error.localizedDescription
            try? saveReport()
            store.cancelWork()
            await store.shutdownAssistant()
            throw error
        }
    }

    @MainActor private func wait(seconds: Int, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw KnowledgeProcedureLiveFailure("The bounded local operation did not finish in \(seconds) seconds.")
    }

    private static func json<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }

    private static func invocationJSON(_ value: HamptonInvocationReceipt) -> [String: Any] {
        ["id": value.id, "role": value.role.rawValue, "outcome": value.outcome.rawValue,
         "model": value.model?.name as Any? ?? NSNull(), "modelDigest": value.model?.digest as Any? ?? NSNull(),
         "inputDigest": value.inputDigest, "outputDigest": value.outputDigest as Any? ?? NSNull(),
         "systemDigest": value.systemDigest, "schemaDigest": value.schemaDigest,
         "policyVersion": value.policyVersion, "contextTokenLimit": value.contextTokenLimit,
         "outputTokenLimit": value.outputTokenLimit, "temperature": value.temperature,
         "elapsedMilliseconds": value.elapsedMilliseconds as Any? ?? NSNull(),
         "inputTokens": value.metrics?.inputTokens as Any? ?? NSNull(),
         "outputTokens": value.metrics?.outputTokens as Any? ?? NSNull(),
         "totalNanoseconds": value.metrics?.totalNanoseconds as Any? ?? NSNull(),
         "malformedMetricFields": value.metrics?.malformedFields as Any? ?? NSNull()]
    }
}

private struct KnowledgeProcedureLiveFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor private final class KnowledgeProcedureNoExternalClient: AssistantClient {
    private(set) var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.configuration }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; throw AssistantFailure.configuration
    }
    func disconnect() {}
    func shutdown() async {}
}
