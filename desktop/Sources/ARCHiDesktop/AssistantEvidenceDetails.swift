import SwiftUI

/// Partial totals remain explicitly partial; unavailable telemetry never reads
/// as free work. This presentation does not change reply or admission state.
enum AssistantMetricSummary {
    static func tokens(_ invocations: [HamptonInvocationReceipt], key: KeyPath<LocalInferenceMetrics, Int?>) -> String {
        let values = invocations.compactMap { $0.metrics?[keyPath: key] }
        guard !values.isEmpty else { return invocations.isEmpty ? "No local calls" : "Unavailable" }
        var sum = 0
        for value in values {
            let addition = sum.addingReportingOverflow(value)
            guard value >= 0, !addition.overflow else { return "Unavailable · invalid total" }
            sum = addition.partialValue
        }
        return values.count == invocations.count ? "\(sum)" : "\(sum) known · \(values.count)/\(invocations.count) calls reported"
    }

    static func duration(_ nanoseconds: Int?) -> String {
        guard let nanoseconds, nanoseconds >= 0 else { return "Unavailable" }
        return String(format: "%.3f s", Double(nanoseconds) / 1_000_000_000)
    }
}

struct AssistantEvidenceDetails: View {
    let receipt: AssistantLaneReceipt

    var body: some View {
        if receipt.provider == .qwen, receipt.localInvocationReceipts != nil || receipt.evidence != nil {
            DisclosureGroup("Evidence & cost") {
                VStack(alignment: .leading, spacing: 10) {
                    if let invocations = receipt.localInvocationReceipts {
                        Text("Input tokens · " + AssistantMetricSummary.tokens(invocations, key: \.inputTokens))
                            .accessibilityIdentifier("assistant-metrics.input")
                        Text("Output tokens · " + AssistantMetricSummary.tokens(invocations, key: \.outputTokens))
                            .accessibilityIdentifier("assistant-metrics.output")
                        Text("Counts include context selectors when used. Attempted means the local client was invoked; it does not establish that Ollama accepted the request. Missing reports remain unavailable.")
                        LocalInvocationDetails(invocations: invocations)
                    }
                    if let evidence = receipt.evidence { EvidenceDecisionDetails(evidence: evidence) }
                }.padding(.top, 5)
            }
            .accessibilityIdentifier("assistant-evidence-cost")
        }
    }
}

struct LocalInvocationDetails: View {
    let invocations: [HamptonInvocationReceipt]

    var body: some View {
        ForEach(Array(invocations.enumerated()), id: \.element.id) { offset, invocation in
            DisclosureGroup("Call \(offset + 1) · \(roleTitle(invocation.role)) · \(outcomeTitle(invocation.outcome))") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(invocation.model?.name ?? "Model not reported") · input \(invocation.metrics?.inputTokens.map(String.init) ?? "unavailable") tokens · output \(invocation.metrics?.outputTokens.map(String.init) ?? "unavailable") tokens")
                    if let elapsed = invocation.elapsedMilliseconds { Text("Client elapsed · \(elapsed) ms") }
                    Text("Model total · " + AssistantMetricSummary.duration(invocation.metrics?.totalNanoseconds))
                    Text("Model load · " + AssistantMetricSummary.duration(invocation.metrics?.loadNanoseconds))
                    Text("Prompt evaluation · " + AssistantMetricSummary.duration(invocation.metrics?.promptEvaluationNanoseconds))
                    Text("Response generation · " + AssistantMetricSummary.duration(invocation.metrics?.evaluationNanoseconds))
                    Text("Internal representations · " + invocation.representationAccess.title)
                    Text(invocation.representationAccess.detail)
                    Text(invocation.representationReceipt.detail)
                    if let assay = invocation.representationReceipt.assay {
                        Text("Assay · \(assay.basis.namespace) · layer \(assay.basis.layer) · \(assay.phase)")
                        if let scope = assay.basis.measurementScope {
                            Text("Reader scope · \(scope) · \(assay.basis.tokenRule)")
                            Text("Limited synthetic-record calibration. This answer is not independently verified by the reader.")
                        }
                        Text("Reader \(assay.basis.readerDigest)\nCalibration \(assay.basis.calibrationDigest)")
                    }
                    if let fields = invocation.metrics?.malformedFields, !fields.isEmpty {
                        Text("Unavailable telemetry fields · " + fields.joined(separator: ", "))
                    }
                    Text("Configured policy · \(invocation.policyVersion) · context \(invocation.contextTokenLimit) · output limit \(invocation.outputTokenLimit) · temperature \(invocation.temperature)")
                    Text("Input \(invocation.inputDigest)\nInstructions \(invocation.systemDigest)\nSchema \(invocation.schemaDigest)")
                    if let model = invocation.model { Text("Model digest · \(model.digest)") }
                    Text("Transport completion does not establish response validity or task correctness. Model durations are not total task time.")
                }.textSelection(.enabled).padding(.top, 4)
            }
        }
    }

    private func roleTitle(_ role: LocalModelRole) -> String {
        switch role { case .reasoning: "Answer"; case .memorySelection: "Keep temporary context"; case .memoryReminder: "Recall temporary context" }
    }
    private func outcomeTitle(_ outcome: HamptonInvocationReceipt.Outcome) -> String {
        switch outcome { case .dispatched: "Attempted"; case .completed: "Response received"; case .failed: "Failed"; case .cancelled: "Stopped" }
    }
}

private struct EvidenceDecisionDetails: View {
    let evidence: AssistantEvidenceReceipt

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(evidence.contextEnabled ? "Temporary context selectors enabled" : "Temporary context selectors off")
            Text("Answer attempt · \(evidence.reasoningSourceIDsDispatched.count) source reference(s), \(evidence.reasoningMemoryIDsDispatched.count) memory reference(s)")
            Text("Cited in checked response · \(evidence.sourceIDsCited.count) source(s), \(evidence.memoryIDsCited.count) memory reference(s)")
            Text("Earlier conversation · \(evidence.conversationDispatchedCount.map(String.init) ?? "not dispatched") exchange(s)")
            Text("Offered means prepared. Dispatched means handed to the local client. Selected or cited references are not proof of truth or usefulness.")
            DisclosureGroup("Reference IDs and omissions") {
                VStack(alignment: .leading, spacing: 6) {
                    ids("Available source", evidence.sourceIDsAvailable)
                    ids("Matching kept lessons", evidence.lessonIDsAvailable)
                    ids("Prepared for answer: sources", evidence.reasoningSourceIDsOffered)
                    ids("Prepared for answer: memory", evidence.reasoningMemoryIDsOffered)
                    ids("Dispatched to answer: sources", evidence.reasoningSourceIDsDispatched)
                    ids("Dispatched to answer: memory", evidence.reasoningMemoryIDsDispatched)
                    selection("Temporary candidates", evidence.candidates)
                    selection("Earlier records", evidence.reminders)
                    ids("Cited sources", evidence.sourceIDsCited)
                    ids("Cited memory", evidence.memoryIDsCited)
                    ForEach(Array(evidence.omissions.enumerated()), id: \.offset) { _, omission in
                        Text("\(omission.kind.rawValue) · \(reason(omission.reason)) · \(omission.count.map(String.init) ?? "count unavailable")\(omission.ids.isEmpty ? "" : " · " + omission.ids.joined(separator: ", "))")
                    }
                    Text("\(evidence.version) · IDs and counts only; raw prompts and hidden reasoning are not recorded here.")
                }.textSelection(.enabled).padding(.top, 4)
            }
        }
        .accessibilityIdentifier("assistant-evidence-decisions")
    }

    private func ids(_ title: String, _ values: [String]) -> some View {
        Text(title + " · " + (values.isEmpty ? "none recorded" : values.joined(separator: ", ")))
    }
    private func selection(_ title: String, _ value: AssistantEvidenceSelection) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ids(title + " eligible", value.eligibleIDs)
            ids(title + " offered", value.offeredIDs)
            ids(title + " dispatched", value.dispatchedIDs)
            ids(title + " selected", value.selectedIDs)
        }
    }
    private func reason(_ reason: AssistantEvidenceOmission.Reason) -> String {
        switch reason {
        case .budget: "omitted to fit budget"
        case .disabled: "selection disabled"
        case .expired: "expired"
        case .revoked: "source changed or revoked"
        case .unmatched: "topic did not match"
        case .otherSource: "different shared source"
        case .unavailable: "local component unavailable"
        }
    }
}
