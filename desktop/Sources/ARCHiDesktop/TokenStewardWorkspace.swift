import SwiftUI
import UniformTypeIdentifiers

/// The desktop reads its own journal. Opening this view never queries accounts.
@MainActor
struct TokenStewardWorkspace: View {
    @ObservedObject var store: TokenStewardStore
    var notice: String?
    var onRetry: () -> Void = {}
    var selectedTaskID: String? = nil
    var onOpenEvidence: ((String) -> Void)? = nil
    var canOpenEvidence: (String) -> Bool = { _ in false }
    @State private var daily = ""
    @State private var monthly = ""
    @State private var message: String?

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Usage").font(.system(size: 30, weight: .medium, design: .rounded))
                        Text("What ARCHi used, what it completed, and what you found useful.")
                            .foregroundStyle(.secondary)
                        Text("Usage metadata saves on this Mac. Questions, answers and document text are excluded.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let problem = notice ?? store.loadError {
                        Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                            .textSelection(.enabled).accessibilityIdentifier("steward.warning")
                        Button("Retry accounting", action: onRetry).accessibilityIdentifier("steward.retry")
                    }
                    if let selectedTaskID, !store.tasks.contains(where: { $0.id == selectedTaskID }) {
                        Text("The requested task is unavailable. No replacement task was selected.")
                            .font(.caption).foregroundStyle(.orange)
                            .accessibilityIdentifier("steward.selection-unavailable")
                    }
                    if store.summary.accountingAvailable {
                        usage
                        outcomes
                    } else {
                        Text("Accounting totals are unavailable. The journal needs review before these amounts can be displayed.")
                            .foregroundStyle(.orange)
                    }
                    budget
                    if let message { Text(message).font(.caption).textSelection(.enabled) }
                    HStack {
                        Button("Export usage journal…", systemImage: "square.and.arrow.up") { export() }
                            .accessibilityIdentifier("steward.export")
                            .disabled(!store.summary.accountingAvailable)
                        Spacer()
                        Text("No account collector is running").font(.caption).foregroundStyle(.secondary)
                    }
                    if store.summary.accountingAvailable { recentTasks }
                }
                .padding(28).frame(maxWidth: 940, alignment: .leading).frame(maxWidth: .infinity)
            }
            .onAppear {
                daily = store.budget.map { TokenStewardPresentation.dollars($0.dailyNanoUSD) } ?? ""
                monthly = store.budget.map { TokenStewardPresentation.dollars($0.monthlyNanoUSD) } ?? ""
                focusTask(using: reader)
            }
            .onChange(of: selectedTaskID) { _, _ in focusTask(using: reader) }
            .onChange(of: store.tasks.map(\.id)) { _, _ in focusTask(using: reader) }
            .accessibilityIdentifier("steward.workspace")
        }
    }

    private var usage: some View {
        GroupBox("Observed usage · this local journal") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Local model attempts", value: "\(store.summary.localAttemptCount)")
                LabeledContent("Local lanes without per-call telemetry", value: "\(store.summary.unmeasuredLocalLaneCount)")
                LabeledContent("Input tokens", value: tokens(store.summary.inputTokens, known: store.summary.knownInputTokens, missing: store.summary.missingInputCount))
                LabeledContent("Output tokens", value: tokens(store.summary.outputTokens, known: store.summary.knownOutputTokens, missing: store.summary.missingOutputCount))
                Divider()
                LabeledContent("Codex subscription requests", value: "\(store.summary.subscriptionRequestCount)")
                Text("Subscription quota, fees and tokens are unavailable here. Local tokens have no assigned API price.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                LabeledContent("Recorded API charges", value: TokenStewardPresentation.money(store.summary.knownAPIChargeNanoUSD))
                LabeledContent("Unbilled estimates · separate", value: TokenStewardPresentation.money(store.summary.estimatedAPIChargeNanoUSD))
                LabeledContent("Outstanding API reservations", value: TokenStewardPresentation.money(store.summary.reservedNanoUSD))
                LabeledContent("Unresolved API charges · all dates", value: "\(store.summary.unresolvedAPIObservationCount)")
                Text("Recorded amounts cover this journal only. Missing billing remains unknown, including charges from earlier months.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(10)
        }
    }

    private var outcomes: some View {
        GroupBox("Task outcomes") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Tasks", value: "\(store.summary.taskCount)")
                LabeledContent("Open or interrupted", value: "\(store.summary.openTaskCount)")
                LabeledContent("Answers delivered", value: "\(store.summary.deliveredTaskCount)")
                LabeledContent("Marked useful by you", value: "\(store.summary.usefulTaskCount)")
                LabeledContent("Separately checked successes", value: "\(store.summary.checkedSuccessfulTaskCount)")
                LabeledContent("Interactive ARC3 sessions", value: "\(store.summary.interactiveSessionCount)")
                LabeledContent("Offline ARC evaluations", value: "\(store.summary.evaluationTaskCount)")
                LabeledContent("Synthetic ARC checks passed", value: "\(store.summary.syntheticCheckedTaskCount)")
                LabeledContent("API cost per useful task", value: store.summary.apiCostPerUsefulTaskNanoUSD.map(TokenStewardPresentation.money) ?? "Not available")
                Text("API denominator: \(store.summary.usefulClosedAPITaskCount) useful tasks among \(store.summary.closedAPITaskCount) closed API tasks. Costs include unsuccessful attempts and retries across dates.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Compare is one task with two lane outcomes. Use “This helped” on a completed answer to record usefulness. ARC checks retain their dataset and synthetic status; they do not certify general intelligence or grant evolution.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Cost per useful task requires complete API cost for that task’s whole lifecycle. Subscription and local use are reported separately.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(10)
        }
    }

    private var budget: some View {
        GroupBox("API spending guard") {
            VStack(alignment: .leading, spacing: 12) {
                Text(!store.summary.accountingAvailable ? "Journal unavailable · guarded API dispatch is blocked" : store.budget == nil ? "No budget set · guarded API dispatch is blocked" : "Budget configured · reservations are checked before guarded API dispatch")
                    .font(.headline).accessibilityIdentifier("steward.guard-status")
                Text("The current assistant uses local Qwen or ChatGPT subscription access. Neither is an API charge. These limits apply to paid adapters routed through Token Steward, not purchases or calls made in other apps. No paid API adapter is enabled by setting a budget.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    TextField("Daily limit · USD", text: $daily).accessibilityIdentifier("steward.daily-budget")
                    TextField("Monthly limit · USD", text: $monthly).accessibilityIdentifier("steward.monthly-budget")
                }.textFieldStyle(.roundedBorder).disabled(!store.summary.accountingAvailable)
                Text("Calendar timezone: \(store.budget?.timeZoneID ?? TimeZone.current.identifier)")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Save limits") { saveBudget() }
                        .disabled(!store.summary.accountingAvailable).accessibilityIdentifier("steward.save-budget")
                    Button("Block paid dispatch") {
                        do { try store.configureBudget(nil); daily = ""; monthly = ""; message = "Paid dispatch blocked. Existing holds and charges remain." }
                        catch { message = error.localizedDescription }
                    }.disabled(store.budget == nil || !store.summary.accountingAvailable).accessibilityIdentifier("steward.clear-budget")
                }
            }.padding(10)
        }
    }

    private var recentTasks: some View {
        GroupBox("Recent work") {
            VStack(alignment: .leading, spacing: 12) {
                if store.tasks.isEmpty { Text("Your next request or ARC run will appear here.").foregroundStyle(.secondary) }
                ForEach(TokenStewardPresentation.visibleTasks(store.tasks, selectedTaskID: selectedTaskID)) { task in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(task.route == "arc-interactive" ? "ARC3 session" : task.route == "arc-evaluation" ? "ARC evaluation" : task.route).fontWeight(.medium)
                            Spacer()
                            Text(task.isClosed ? "Finished" : "Open / interrupted").foregroundStyle(.secondary)
                        }
                        if selectedTaskID == task.id {
                            Label("Selected run", systemImage: "scope")
                                .font(.caption).foregroundStyle(WorkspaceTheme.accent)
                                .accessibilityIdentifier("steward.selected-task")
                        }
                        Text(task.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                        Text(task.id).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                        if let reading = task.documentReading {
                            Text("Document reading · \(reading.sectionIDs.count) source sections · \(reading.control.lane.title)")
                                .font(.caption)
                            if let review = task.outcomes.last(where: { $0.kind == .userUseful && $0.evidenceID.hasPrefix(DocumentReadingTrace.feedbackEvidencePrefix) }) {
                                Text(review.value ? "Reading marked helpful" : "Reading needs correction")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text(task.route == "arc-interactive" ? "Local environment session · no model calls · not an assistant answer" : task.route == "arc-evaluation" ? "Offline evaluation · \(task.checkedSuccessful ? "all examples exact" : "not all examples exact or evaluation failed")" : task.userUseful ? "Marked useful" : task.delivered ? "Answer delivered · usefulness not assessed" : "No completed answer")
                            .font(.caption).foregroundStyle(.secondary)
                        if task.route == "arc-interactive", let detail = task.lanes.first?.admission { Text(detail).font(.caption).foregroundStyle(.secondary) }
                        ForEach(task.lanes) { lane in
                            Text("\(lane.provider) · \(lane.state)" + (lane.elapsedMilliseconds.map { " · \($0) ms" } ?? ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let onOpenEvidence, canOpenEvidence(task.id) {
                            Button("Open ARC result", systemImage: "square.grid.3x3") { onOpenEvidence(task.id) }
                                .accessibilityIdentifier("steward.open-arc.\(task.id)")
                        }
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(selectedTaskID == task.id ? WorkspaceTheme.accent.opacity(0.08) : .clear,
                                in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(selectedTaskID == task.id ? [.isSelected] : [])
                    .accessibilityIdentifier("steward.task.\(task.id)")
                    .id(task.id)
                    Divider()
                }
            }.padding(10)
        }
    }

    private func focusTask(using reader: ScrollViewProxy) {
        guard store.summary.accountingAvailable, let selectedTaskID,
              store.tasks.contains(where: { $0.id == selectedTaskID }) else { return }
        reader.scrollTo(selectedTaskID, anchor: .top)
    }

    private func tokens(_ total: Int64?, known: Int64, missing: Int) -> String {
        if let total { return String(total) }
        return missing == 0 ? (known == 0 ? "Not measured" : "\(known) reported · some work unmeasured")
            : "\(known) reported · \(missing) unavailable"
    }

    private func saveBudget() {
        guard let dailyLimit = TokenStewardPresentation.nanoUSD(daily),
              let monthlyLimit = TokenStewardPresentation.nanoUSD(monthly) else {
            message = "Enter nonnegative USD amounts with at most nine decimal places. Blank means unset; zero blocks spending."
            return
        }
        do {
            try store.configureBudget(TokenStewardBudget(dailyNanoUSD: dailyLimit,
                monthlyNanoUSD: monthlyLimit, timeZoneID: store.budget?.timeZoneID ?? TimeZone.current.identifier))
            message = "Limits saved locally. No request was sent."
        } catch { message = error.localizedDescription }
    }

    private func export() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ARCHi-usage-journal.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        do { try store.export(to: url); message = "Usage journal exported." }
        catch { message = error.localizedDescription }
    }
}

enum TokenStewardPresentation {
    /// Retain the bounded recent list while making an exact older navigation target visible.
    static func visibleTasks(_ tasks: [TokenStewardTask], selectedTaskID: String?) -> [TokenStewardTask] {
        let recent = Array(tasks.prefix(20))
        guard let selectedTaskID, !recent.contains(where: { $0.id == selectedTaskID }),
              let selected = tasks.first(where: { $0.id == selectedTaskID }) else { return recent }
        return [selected] + recent
    }

    /// Parse exactly; no floating-point conversion and no silent rounding.
    static func nanoUSD(_ text: String) -> Int64? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), !parts[0].isEmpty,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let whole = Int64(parts[0]), whole >= 0 else { return nil }
        let fractional = parts.count == 2 ? String(parts[1]) : ""
        guard fractional.count <= 9 else { return nil }
        let scaled = whole.multipliedReportingOverflow(by: 1_000_000_000)
        guard !scaled.overflow, let fraction = Int64(fractional + String(repeating: "0", count: 9 - fractional.count)) else { return nil }
        let result = scaled.partialValue.addingReportingOverflow(fraction)
        return result.overflow ? nil : result.partialValue
    }

    static func dollars(_ value: Int64) -> String {
        let fraction = String(format: "%09lld", value % 1_000_000_000)
        let trimmed = fraction.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        return "\(value / 1_000_000_000)" + (trimmed.isEmpty ? "" : ".\(trimmed)")
    }
    static func money(_ value: Int64) -> String { "$" + dollars(value) + " USD" }
}
