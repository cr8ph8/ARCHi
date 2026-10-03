import Foundation
import XCTest
@testable import ARCHiDesktop

/// One opt-in local request through the production finder and preparation
/// owners. Synthetic disposable data only; no Apply, feedback or learning.
final class DocumentMethodFinderLiveTests: XCTestCase {
    @MainActor
    func testOneFoundAndChosenMethodReachesCheckedLocalProposal() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ARCHI_METHOD_FINDER_LIVE"] == "1",
              let outputPath = environment["ARCHI_METHOD_FINDER_LIVE_OUTPUT"], !outputPath.isEmpty else {
            throw XCTSkip("Set ARCHI_METHOD_FINDER_LIVE=1 and ARCHI_METHOD_FINDER_LIVE_OUTPUT for one local method-finder request.")
        }
        let output = URL(fileURLWithPath: outputPath, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        guard output.path.hasPrefix("/private/tmp/") || output.path.hasPrefix(temporary + "/") else {
            throw MethodFinderLiveFailure("The evidence directory must be under a temporary directory.")
        }
        let markerURL = output.appendingPathComponent("attempt-started.json")
        let reportURL = output.appendingPathComponent("method-finder-live.json")
        guard !FileManager.default.fileExists(atPath: markerURL.path),
              !FileManager.default.fileExists(atPath: reportURL.path) else {
            throw XCTSkip("This evidence directory already started its one request. Its evidence is preserved; no retry was started.")
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        // Create-new is the durable attempt claim. It precedes every possible
        // connection, and remains even if setup, connection or generation fails.
        try JSONSerialization.data(withJSONObject: [
            "schema": "archi-method-finder-live-start/v1",
            "startedAt": ISO8601DateFormatter().string(from: Date()),
            "maximumRequests": 1, "maximumGenerations": 1, "maximumRetries": 0,
            "contextEnabled": false, "report": reportURL.lastPathComponent
        ], options: [.prettyPrinted, .sortedKeys]).write(to: markerURL, options: .withoutOverwriting)

        let passage = "For the project update, I wanted to mention that we completed 3 interface screens. The export review is still waiting on accessibility feedback. I also wanted to mention that the next step is to check the focus order on Friday."
        let principle = "Project updates distinguish completed work, the current blocker, and the next action. Remove introductory repetition while preserving the stated facts, counts, timing and uncertainty. Do not invent completed work or commitments."
        let instruction = "Revise the selected project update into a concise status paragraph. State the completed work, the current blocker, and the next action. Remove introductory repetition while preserving existing facts, counts and timing. Do not invent commitments or completed work."
        let originalDraft = "This unrelated unsent draft must stay here until I explicitly choose a method."
        let query = "project update blocker"
        let requirements = DocumentWorkRequirements(mustBeShorter: true, preserveNumbersAndLinks: true)
        var report: [String: Any] = [
            "schema": "archi-method-finder-local-demonstration/v1",
            "scope": "One synthetic everyday project-update method found, previewed and explicitly chosen through production owners, followed by one local proposal. No personal data or native UI qualification.",
            "route": "local", "configuredModel": QwenAssistant.defaultModel,
            "maximumRequests": 1, "maximumGenerations": 1, "maximumRetries": 0,
            "contextEnabled": false, "configuredContextTokenLimit": HamptonInvocationPolicy.contextTokens,
            "configuredOutputTokenLimit": HamptonInvocationPolicy.outputTokens,
            "configuredTemperature": HamptonInvocationPolicy.temperature,
            "connectionWaitLimitSeconds": 30, "generationWaitLimitSeconds": 190,
            "source": passage, "sourceGuidance": principle, "instruction": instruction,
            "query": query, "initialUnrelatedDraft": originalDraft,
            "requirements": ["mustBeShorter": true, "preserveNumbersAndLinks": true],
            "exactReplacementSupplied": false, "semanticUsefulness": "UNREVIEWED",
            "feedbackPolicy": "No Apply, Helpful review, learning review or saved development, regardless of the mechanical result.",
            "limitations": "A single synthetic mechanical pass does not establish preserved meaning, useful writing, broad transfer or personal learning. Inspect the actual replacement and explanation separately.",
            "dollarCost": NSNull(), "energyCost": NSNull(), "result": "started",
            "shutdownAwaited": false
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: reportURL, options: .withoutOverwriting)

        let profile = FileManager.default.temporaryDirectory.appendingPathComponent("archi-method-finder-live-\(UUID())")
        defer { try? FileManager.default.removeItem(at: profile) }
        var storeForCleanup: CompanionStore?
        do {
            try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
            let preferenceURL = profile.appendingPathComponent("preferences.json")
            var preferences = CompanionPreferences()
            preferences.tone = "Direct"; preferences.replyLength = 0.2; preferences.reduceMotion = true
            try NativePreferenceDocument(preferences: preferences).encoded().write(to: preferenceURL)
            let local = HamptonReasonsAssistant(contextEnabled: false, nativeRuntime: .shared)
            let refused = MethodFinderNoExternalClient()
            let store = CompanionStore(preferenceURL: preferenceURL, assistant: local,
                assistantFactory: { _, _ in refused }, allowsPlay: false)
            storeForCleanup = store
            store.setLocalWorkPreference(.reasoning)
            let initialEvolutionRevision = store.evolution.revision
            var checks: [String: Bool] = [:]
            var phases: [String: Bool] = [
                "methodFound": false, "previewOpened": false, "methodExplicitlyChosen": false,
                "requestSubmitted": false, "generationCompleted": false,
                "proposalAdmitted": false, "mechanicallyChecked": false,
                "applyRequested": false, "feedbackRecorded": false
            ]
            var capturedInvocations: [HamptonInvocationReceipt] = []
            var capturedRoles: [LocalModelRole] = []
            var capturedValidatedReceiptCount = 0
            func verify(_ name: String, _ condition: Bool, fatal: Bool = true) throws {
                checks[name] = condition
                if fatal && !condition { throw MethodFinderLiveFailure(name) }
            }
            func captureInvocationEvidence() {
                let snapshot = local.snapshot
                // Disconnect/shutdown may clear the visit snapshot. Preserve the
                // final operation evidence already observed by this recorder.
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
                if let lane = store.compareResults[.qwen] {
                    report["lane"] = ["state": lane.state.rawValue, "status": lane.status, "text": lane.text,
                        "requestID": lane.receipt?.requestID as Any? ?? NSNull(),
                        "admission": lane.receipt?.admissionOutcome?.status.rawValue as Any? ?? NSNull()]
                    if let proposal = lane.revision {
                        report["proposal"] = Self.proposalJSON(proposal)
                        let verification = store.documentVerification(proposal)
                        report["mechanicalChecks"] = verification.checks.map {
                            ["id": $0.id, "title": $0.title, "passed": $0.passed] as [String: Any]
                        }
                        report["mechanicallyApplicable"] = verification.canApply
                    }
                    if let original = lane.originalRevision { report["originalProposal"] = Self.proposalJSON(original) }
                }
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    .write(to: reportURL, options: .atomic)
            }
            do {
                try verify("disposableProfileHasNoPersonalIdentityOrLessons", store.activeQiMon == nil && store.keptLessons.isEmpty)
                try verify("localReasoningOnly", store.route == .local && store.localWorkPreference == .reasoning
                    && !store.sessionContextEnabled && !local.contextEnabled)
                let source = try store.readingSources.keep(title: "Synthetic project-update guidance", text: principle)
                let anchor = try store.readingSources.makeAnchor(sourceID: source.id,
                    range: NSRange(location: 0, length: source.text.utf16.count))
                try verify("knowledgeDraftSaved", store.saveKnowledgePage(prior: nil,
                    title: "Project status updates", body: principle, kind: .concept, anchors: [anchor]))
                store.reviewKnowledgePage(try XCTUnwrap(store.readingSources.latestKnowledgePages.first))
                let page = try XCTUnwrap(store.readingSources.latestKnowledgePages.first)
                try verify("reviewedConceptIsCurrent", page.state == .reviewed && store.readingSources.availability(of: page) == nil)
                try verify("candidateMethodKept", store.keepKnowledgeProcedure(page: page,
                    title: "Project update with blocker and next action", instruction: instruction, requirements: requirements))
                let method = try XCTUnwrap(store.documentProcedures.latestProcedures.first)
                report["sourceBinding"] = try Self.json(source.binding)
                report["knowledgePage"] = try Self.json(page)
                report["knowledgeBinding"] = try Self.json(page.binding)
                report["methodBinding"] = try Self.json(method.binding)
                try verify("methodRetainsExactKnowledgeVersion", method.knowledgeOrigin == page.binding)

                store.share(text: passage, name: "synthetic-project-update.txt")
                store.selectText(range: NSRange(location: 0, length: passage.utf16.count), sourceRevision: store.sourceRevision)
                store.requestsRevision = true
                store.documentRequirements = requirements
                store.prompt = originalDraft
                let initialSourceRevision = store.sourceRevision
                let matches = try store.findDocumentMethods(query: query)
                let hit = try XCTUnwrap(matches.hits.first)
                try verify("finderReturnsExactEligibleMethod", hit.procedure.binding == method.binding
                    && matches.matchingCount == 1 && !hit.matchedTerms.isEmpty)
                phases["methodFound"] = true
                report["finder"] = ["queryTerms": matches.queryTerms, "matchedTerms": hit.matchedTerms,
                    "score": hit.score, "matchingCount": matches.matchingCount, "omittedCount": matches.omittedCount]
                report["matchedMethodBinding"] = try Self.json(hit.procedure.binding)
                let preview = try XCTUnwrap(store.previewDocumentMethod(hit.procedure.binding))
                phases["previewOpened"] = true
                try verify("searchAndPreviewPreserveUnrelatedDraft", store.prompt.utf8.elementsEqual(originalDraft.utf8)
                    && preview.originalPrompt.utf8.elementsEqual(originalDraft.utf8)
                    && store.preparedDocumentProcedure == nil && store.sharedText == passage)
                try verify("previewDidNotGenerateOrInventWork", local.snapshot.attemptedInvocations.isEmpty
                    && store.documentWork.records.isEmpty && store.tokenSteward.tasks.isEmpty && refused.calls == 0)
                try verify("explicitMethodChoiceAccepted", store.applyDocumentMethodPreview(preview))
                phases["methodExplicitlyChosen"] = true
                try verify("choiceBindsExactInstructionAndMethod", store.prompt.utf8.elementsEqual(instruction.utf8)
                    && store.preparedDocumentProcedure == method.binding
                    && store.preparedProcedureMatchesCurrentDraft(question: store.prompt))
                try verify("budgetIsOneLocalReasoningAttempt", store.nextCallBudget == "1 local answer attempt · no external requests"
                    && store.nextLocalExpertDecision.target == .reasoning && store.nextAssistantFallbackBlockedReason != nil)
                report["callBudget"] = store.nextCallBudget
                try saveReport()
                store.connectAssistant(provider: .qwen)
                try await wait(seconds: 30) { store.connection(for: .qwen) != .connecting }
                try verify("localConnectionReady", store.connection(for: .qwen) == .ready)
                report["result"] = "running"
                phases["requestSubmitted"] = true
                try saveReport() // Durable state before the sole submit call.
                store.submit()
                try await wait(seconds: 190) { !store.isWorking }
                captureInvocationEvidence()
                phases["generationCompleted"] = capturedInvocations.contains { $0.outcome == .completed }
                try saveReport() // Retain actual output even if a following check fails.

                let lane = try XCTUnwrap(store.compareResults[.qwen])
                let receipt = try XCTUnwrap(lane.receipt)
                report["requestID"] = receipt.requestID
                report["requestBinding"] = try Self.json(EvolutionRequestBinding(receipt: receipt))
                report["requestSourceDigest"] = receipt.sourceDigest as Any? ?? NSNull()
                report["requestKnowledgeDependencies"] = try Self.json(receipt.knowledgeDependencies)
                try verify("oneCompletedLocalReasoningInvocation", capturedRoles == [.reasoning]
                    && capturedInvocations.count == 1 && capturedInvocations.first?.outcome == .completed
                    && receipt.localInvocations == [.reasoning] && capturedValidatedReceiptCount == 1
                    && receipt.localInvocationReceipts == capturedInvocations)
                try verify("noExternalRoute", refused.calls == 0 && store.compareResults[.codex] == nil)
                try verify("admittedCompletedLane", lane.state == .complete && receipt.state == .complete
                    && receipt.admissionOutcome?.status == .accepted)
                let proposal = try XCTUnwrap(lane.revision)
                phases["proposalAdmitted"] = true
                let verification = store.documentVerification(proposal)
                phases["mechanicallyChecked"] = verification.canApply
                try verify("allMechanicalChecksPass", verification.canApply)
                let record = try XCTUnwrap(store.documentRecord(requestID: receipt.requestID, provider: .qwen))
                try verify("exactSourceSelectionAndMethodRetained", record.procedureUse == hit.procedure.binding
                    && record.sourceDigest == WorkingCopyEditReceipt.digest(passage)
                    && receipt.sourceDigest == record.sourceDigest && proposal.target.sourceDigest == record.sourceDigest
                    && proposal.target.selection.quote.utf8.elementsEqual(passage.utf8)
                    && proposal.target.selection.sourceRevision == initialSourceRevision
                    && record.targetID == proposal.target.id && receipt.knowledgeDependencies == [page.binding])
                try verify("workingCopyUnchangedAndReviewAbsent", store.sharedText.utf8.elementsEqual(passage.utf8)
                    && store.sourceRevision == initialSourceRevision && record.state == .ready && record.feedback == nil
                    && store.documentWork.records.count == 1 && store.documentWork.records.allSatisfy { $0.feedback == nil })
                try verify("ownerAllowsInspectionBeforeApply", store.canApplyDocumentRevision(provider: .qwen, proposal: proposal))
                let invocation = try XCTUnwrap(capturedInvocations.first)
                let metrics = try XCTUnwrap(invocation.metrics)
                try verify("measuredLocalTokensPresent", (metrics.inputTokens ?? 0) > 0
                    && (metrics.outputTokens ?? 0) > 0 && metrics.malformedFields.isEmpty)
                let observations = store.tokenSteward.observations.filter { $0.taskID == receipt.requestID }
                let observation = try XCTUnwrap(observations.first)
                try verify("usageRetainsOneMeasuredInvocation", observations.count == 1
                    && observation.resource == .localInference && observation.role == LocalModelRole.reasoning.rawValue
                    && observation.inputDigest == invocation.inputDigest
                    && observation.inputTokens == metrics.inputTokens.map(Int64.init)
                    && observation.outputTokens == metrics.outputTokens.map(Int64.init)
                    && observation.modelDigest == invocation.model?.digest)
                let task = try XCTUnwrap(store.tokenSteward.tasks.first { $0.id == receipt.requestID })
                try verify("oneTaskWithMeasuredCompletedLaneAndNoUsefulReview", store.tokenSteward.tasks.count == 1
                    && task.lanes.count == 1 && task.lanes.first?.state == "complete"
                    && task.lanes.first?.localAttemptsMeasured == true
                    && !task.outcomes.contains { $0.kind == .userUseful })
                try verify("contextDisabledWithoutOptionalCalls", receipt.evidence?.contextEnabled == false
                    && receipt.evidence?.candidates.dispatchedIDs.isEmpty == true
                    && receipt.evidence?.reminders.dispatchedIDs.isEmpty == true)
                try verify("noLearningOrGrowth", store.activeQiMon == nil && store.keptLessons.isEmpty
                    && store.evolution.revision == initialEvolutionRevision && store.evolution.usefulReceipts.isEmpty
                    && store.evolution.kinGrowthRecord == nil)
                report["result"] = "mechanical-proposal-pass-semantic-usefulness-unreviewed"
                try saveReport()
                await store.shutdownAssistant()
                storeForCleanup = nil
                report["shutdownAwaited"] = true
                // Shutdown clears presentation state. Keep the admitted lane
                // and output captured before shutdown as the attempt evidence.
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    .write(to: reportURL, options: .atomic)
            } catch {
                report["result"] = "failed"
                report["failure"] = error.localizedDescription
                captureInvocationEvidence()
                try? saveReport()
                store.cancelWork()
                await store.shutdownAssistant()
                storeForCleanup = nil
                report["shutdownAwaited"] = true
                try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    .write(to: reportURL, options: .atomic)
                throw error
            }
        } catch {
            // Setup failures still leave the permanent start marker and a
            // failure receipt. Neither this catch nor the inner catch retries.
            if let store = storeForCleanup {
                store.cancelWork()
                await store.shutdownAssistant()
                report["shutdownAwaited"] = true
            }
            report["result"] = "failed"
            report["failure"] = error.localizedDescription
            try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: reportURL, options: .atomic)
            throw error
        }
    }

    @MainActor private func wait(seconds: Int, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw MethodFinderLiveFailure("The bounded local operation did not finish in \(seconds) seconds.")
    }

    private static func json<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: .fragmentsAllowed)
    }

    private static func proposalJSON(_ proposal: PassageRevisionProposal) -> [String: Any] {
        ["decision": proposal.decision.rawValue, "replacement": proposal.replacement,
         "explanation": proposal.explanation, "targetID": proposal.target.id,
         "sourceDigest": proposal.target.sourceDigest, "sourceRevision": proposal.target.selection.sourceRevision,
         "sourceIDs": proposal.sourceIDs, "memoryIDs": proposal.memoryIDs]
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
         "loadNanoseconds": value.metrics?.loadNanoseconds as Any? ?? NSNull(),
         "promptEvaluationNanoseconds": value.metrics?.promptEvaluationNanoseconds as Any? ?? NSNull(),
         "evaluationNanoseconds": value.metrics?.evaluationNanoseconds as Any? ?? NSNull(),
         "malformedMetricFields": value.metrics?.malformedFields as Any? ?? NSNull()]
    }
}

private struct MethodFinderLiveFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor private final class MethodFinderNoExternalClient: AssistantClient {
    private(set) var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.configuration }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; throw AssistantFailure.configuration
    }
    func disconnect() {}
    func shutdown() async {}
}
