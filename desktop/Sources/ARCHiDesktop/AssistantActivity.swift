import SwiftUI

/// A projection of owned work, never a second character state or evolution input.
enum AssistantActivity: String, CaseIterable, Equatable, Sendable {
    case idle, working, responding, ready, failed, stopped

    var title: String {
        switch self {
        case .idle: "Idle"
        case .working: "Working"
        case .responding: "Responding"
        case .ready: "Answer ready"
        case .failed: "Reply failed"
        case .stopped: "Stopped"
        }
    }

    var symbol: String {
        switch self {
        case .idle: "circle"
        case .working: "ellipsis.circle"
        case .responding: "text.bubble"
        case .ready: "checkmark.circle"
        case .failed: "exclamationmark.circle"
        case .stopped: "pause.circle"
        }
    }

    func animates(quiet: Bool, reduceMotion: Bool, systemReduceMotion: Bool) -> Bool {
        (self == .working || self == .responding) && !quiet && !reduceMotion && !systemReduceMotion
    }

    static func derive(owned: Set<AssistantProvider>, results: [AssistantProvider: AssistantLaneResult]) -> Self {
        if owned.contains(where: { results[$0]?.state == .pending && !(results[$0]?.text.isEmpty ?? true) }) { return .responding }
        if !owned.isEmpty { return .working }
        if results.values.contains(where: { $0.state == .complete && !$0.text.isEmpty }) { return .ready }
        if results.values.contains(where: { $0.state == .failed }) { return .failed }
        if results.values.contains(where: { $0.state == .cancelled }) { return .stopped }
        return .idle
    }
}

/// Kept outside CompanionPresenceArt and its PNG export, with no layout animation.
struct AssistantTaskCue: View {
    let activity: AssistantActivity
    let quiet: Bool
    let reduceMotion: Bool
    var showsLabel = true
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        let moving = activity.animates(quiet: quiet, reduceMotion: reduceMotion, systemReduceMotion: systemReduceMotion)
        HStack(spacing: 5) {
            TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !moving)) { time in
                Image(systemName: activity.symbol)
                    .opacity(moving ? 0.75 + 0.25 * sin(time.date.timeIntervalSinceReferenceDate * 2.5) : 1)
            }
            .frame(width: 13, height: 13)
            if showsLabel { Text(activity.title).lineLimit(1) }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(activity == .failed ? Color.orange : WorkspaceTheme.accent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Assistant: \(activity.title)")
        .accessibilityIdentifier("assistant-task-activity")
        .help("Assistant: \(activity.title)")
    }
}

@MainActor
struct NextReplySettingsView: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Next reply · " + store.nextReplySettings.summary)
                .accessibilityIdentifier("assistant-next-settings")
                .fixedSize(horizontal: false, vertical: true)
            if store.route != .codex, let profile = store.personalContext?.assistantSnapshot {
                Text("Local personal context · \(profile.preferredName) · \(profile.facts.count) details")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("Role & help style") { store.section = .evolution }
                Button("Tone & length") { store.section = .rhythm }
            }.buttonStyle(.borderless)
            Text(store.nextCallBudget).foregroundStyle(.secondary)
                .accessibilityIdentifier("assistant-call-budget")
            Text("Activity · \(store.currentTaskScope.title)").foregroundStyle(.secondary)
                .accessibilityIdentifier("assistant-task-scope")
            Button(store.nextReplyLessons.isEmpty ? "Kept lessons · none for this reply" : "Kept lessons · \(store.nextReplyLessons.count) for local Qwen") {
                store.open(.memory)
            }.buttonStyle(.borderless).accessibilityIdentifier("assistant-next-lessons")
                .help("Matched lessons: " + store.nextReplyLessons.map(\.topic).joined(separator: ", ")
                    + ". Kept lessons stay on this Mac and do not add model calls.")
        }
        .font(.system(size: 10))
        .help("These settings guide the next Send. An instruction in your question takes precedence; changing settings does not change an earlier answer.")
    }
}

extension AssistantLaneReceipt {
    var workSummary: String {
        let calls: String
        if provider == .codex {
            calls = "\(requestStarted ? 1 : 0) Codex request(s) attempted"
        } else if let localInvocations {
            calls = "\(localInvocations.count) local model call(s) attempted"
        } else {
            calls = "Local call count unavailable"
        }
        guard let elapsedMilliseconds else { return calls }
        return calls + " · " + String(format: "%.1f s elapsed", Double(elapsedMilliseconds) / 1000)
    }
}

struct AssistantReceiptDetails: View {
    let receipt: AssistantLaneReceipt
    var onOpenGraph: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let revision = receipt.localProfileRevision {
                Text("Local personal context · revision \(revision) · \(receipt.localProfileDigest?.prefix(12) ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let settings = receipt.settings {
                Text((receipt.requestStarted ? "Attempted with · " : "Prepared with · ") + settings.summary)
                    .accessibilityIdentifier("assistant-captured-settings")
            }
            if let pointing = receipt.pointing {
                Text("Point and explain · " + pointing.gesture.summary)
                    .accessibilityIdentifier("assistant-captured-pointing")
                    .help("The staff gesture captured for this request. Changing your gesture affects the next request.")
            }
            Text(receipt.workSummary).accessibilityIdentifier("assistant-observed-calls")
            AssistantEvidenceDetails(receipt: receipt)
            if let onOpenGraph {
                Button("Explore in Node Lab", systemImage: "point.3.connected.trianglepath.dotted", action: onOpenGraph)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("assistant-receipt.open-graph")
            }
            if receipt.provider == .qwen {
                Text(receipt.conversationDeliveryDescription)
                    .accessibilityIdentifier("assistant-captured-conversation")
            }
            if let reason = receipt.routingReason {
                Text(reason).accessibilityIdentifier("assistant-routing-reason")
            }
            if let outcome = receipt.admissionOutcome {
                DisclosureGroup(outcome.summary) {
                    Text(outcome.detail).textSelection(.enabled)
                }.accessibilityIdentifier("assistant-admission-outcome")
            }
            if !receipt.localLessons.isEmpty {
                DisclosureGroup("Local context · \(receipt.localLessons.count) kept lesson(s)") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(receipt.localLessons, id: \.id) { lesson in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(lesson.topic) · revision \(lesson.revision)")
                                Text(lesson.text).textSelection(.enabled)
                                if let scope = lesson.taskScope { Text("Activity · \(scope.title)") }
                                Text(receipt.lessonDeliveryDescription(for: lesson))
                                if let source = lesson.source { Text("Same shared-copy content · \(source.name)") }
                            }
                        }
                        Text("A citation identifies supplied guidance; it does not prove the lesson helped.")
                    }.padding(.top, 5)
                }.accessibilityIdentifier("assistant-captured-lessons")
            }
        }
        .font(.system(size: 10)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension AssistantLaneReceipt {
    var conversationDeliveryDescription: String {
        let attempted = localInvocations?.contains(.reasoning) == true
        let prefix = attempted ? "Reasoning context" : "Prepared follow-up context"
        let omitted = localConversationOmittedCount == 0 ? "" : " · \(localConversationOmittedCount) older exchange(s) omitted to fit"
        return "\(prefix) · \(localConversationCount) earlier Qwen exchange(s)\(omitted). Prior answers are unverified context."
    }

    func lessonDeliveryDescription(for lesson: LessonSnapshot) -> String {
        if usedLessonIDs.contains(lesson.modelID) { return "Cited by Qwen in its accepted reply." }
        let match = lesson.taskScope == nil ? "topic phrase matched" : "chosen activity matched"
        if localInvocations?.contains(.reasoning) == true {
            return "Included in the local reasoning attempt because its \(match); use was not confirmed."
        }
        return "Prepared because its \(match); no local reasoning attempt was recorded."
    }
}
