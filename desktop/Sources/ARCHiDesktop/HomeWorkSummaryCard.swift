import SwiftUI

/// Home exposes the existing document work, review and method owners. Visiting
/// this card never rates a result, prepares a request or changes a saved method.
@MainActor
struct HomeWorkSummaryCard: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject private var journal: DocumentWorkJournal
    @ObservedObject private var methods: DocumentProcedureLibrary
    @Environment(\.scenePhase) private var scenePhase
    @State private var summary = Summary.unavailable("Checking local work history…")
    @State private var detail: Detail?
    @State private var showsLearning = false

    init(store: CompanionStore) {
        self.store = store
        journal = store.documentWork
        methods = store.documentProcedures
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Work that carries forward", systemImage: "arrow.triangle.branch")
                .font(.system(size: 19, weight: .medium, design: .rounded))
            Text(summary.isEmpty
                 ? "Start with a passage. Review the change, then keep a method worth using again."
                 : "Your reviews help ARCHi choose which document methods to suggest next.")
                .font(.system(size: 12)).foregroundStyle(WorkspaceTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { counts }
                VStack(alignment: .leading, spacing: 12) { counts }
            }

            if let notice = summary.notice {
                Text(notice).font(.system(size: 11)).foregroundStyle(WorkspaceTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("home.work-summary.notice")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { actions }
                VStack(alignment: .leading, spacing: 8) { actions }
            }

            DisclosureGroup("How ARCHi learns from this work", isExpanded: $showsLearning) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Work on a passage → review the proposed edit → Apply → say whether it helped → keep a method you want to try again.")
                    Text("Hampton’s method loop uses your attributable reviews to order available suggestions. It uses comparable measured resource use only to break equal-quality ties. You choose the method and review every new result.")
                    Text("These counts describe applied assistant attempts and saved user reviews, not unique tasks or a capability score. Keeping a method does not train model weights or prove it will transfer.")
                }
                .foregroundStyle(WorkspaceTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            }
            .font(.system(size: 11)).tint(WorkspaceTheme.accent)
            .accessibilityIdentifier("home.work-summary.learning")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(WorkspaceSurface())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.work-summary")
        .sheet(item: $detail) { selection in detailSheet(selection) }
        .onAppear(perform: refresh)
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            if scenePhase == .active { refresh() }
        }
        .onChange(of: journal.records) { _, _ in refresh() }
        .onChange(of: journal.loadError) { _, _ in refresh() }
        .onChange(of: methods.procedures) { _, _ in refresh() }
        .onChange(of: methods.loadError) { _, _ in refresh() }
        .onChange(of: store.pendingDocumentReceipt) { _, _ in refresh() }
        .onChange(of: store.profileRecoveryBlock) { _, _ in refresh() }
        .onChange(of: store.isWorking) { _, _ in refresh() }
        .onChange(of: store.isShuttingDown) { _, _ in refresh() }
        .onChange(of: store.sourceRevision) { _, _ in refresh() }
        .onChange(of: store.keptLessons) { _, _ in refresh() }
        .onChange(of: store.readingSources.sources) { _, _ in refresh() }
        .onChange(of: store.readingSources.knowledgePages) { _, _ in refresh() }
        .onChange(of: ObjectIdentifier(store.documentWork)) { _, _ in reset() }
        .onChange(of: ObjectIdentifier(store.documentProcedures)) { _, _ in reset() }
        .onChange(of: store.activeQiMon) { _, _ in reset() }
        .onChange(of: store.section) { _, section in if section != .home { detail = nil } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    @ViewBuilder
    private var counts: some View {
        count(summary.awaitingReview, label: "awaiting your review", identifier: "reviews")
        count(summary.helpful, label: "reviewed helpful", identifier: "helpful")
        count(summary.availableMethods, label: "available methods", identifier: "methods")
    }

    private func count(_ value: Int?, label: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value.map(String.init) ?? "—")
                .font(.system(size: 20, weight: .medium, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 11)).foregroundStyle(WorkspaceTheme.muted)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.map { "\($0) \(label)" } ?? "\(label): unavailable")
        .accessibilityIdentifier("home.work-summary.count.\(identifier)")
    }

    @ViewBuilder
    private var actions: some View {
        Button { store.open(.context) } label: {
            Label(store.sourceName == nil ? "Work on a document" : "Continue document", systemImage: "doc.text")
        }
        .buttonStyle(WorkspaceActionStyle(prominent: true))
        .disabled(store.isShuttingDown)
        .accessibilityIdentifier("home.document")
        Button("Review outcomes", systemImage: "checkmark.bubble") { refresh(); detail = .reviews }
            .buttonStyle(WorkspaceActionStyle())
            .disabled(store.isShuttingDown)
            .accessibilityIdentifier("home.work-summary.reviews")
        Button("Saved methods", systemImage: "bookmark") { refresh(); detail = .methods }
            .buttonStyle(WorkspaceActionStyle())
            .disabled(store.isShuttingDown)
            .accessibilityIdentifier("home.work-summary.methods")
    }

    private func detailSheet(_ selection: Detail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(selection.title).font(.system(size: 21, weight: .medium, design: .rounded))
                Spacer()
                Button("Close", systemImage: "xmark") { detail = nil }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("home.work-summary.close")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let issue = historyIssue {
                        Text(issue).foregroundStyle(WorkspaceTheme.muted)
                    } else if selection == .reviews {
                        if let current = store.currentDocumentOutcome {
                            DisclosureGroup("Latest applied change") {
                                DocumentOutcomeView(store: store, record: current).padding(.top, 8)
                            }
                        }
                        DocumentReviewQueueView(store: store)
                        Text("Reviews are your judgments of applied work. The retained receipt does not contain the original passage or response.")
                            .font(.caption).foregroundStyle(WorkspaceTheme.muted)
                    } else {
                        if methods.loadError != nil || !methods.isCurrentOnDisk {
                            Text("The saved-method library needs review before it can be used.")
                                .foregroundStyle(WorkspaceTheme.muted)
                        } else if methods.latestProcedures.isEmpty {
                            Text("No saved methods yet.").font(.headline)
                            Text("After a helpful applied edit, keep an instruction from its review. You can also author a candidate from a reviewed knowledge page.")
                                .foregroundStyle(WorkspaceTheme.muted)
                        } else {
                            DocumentProcedureLibraryView(store: store)
                        }
                        Text("To use a method, open a document, select a passage and choose Revise with matching checks. Preview the instruction before Send.")
                            .font(.caption).foregroundStyle(WorkspaceTheme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.system(size: 12))
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 460)
            HStack {
                if store.pendingDocumentReceipt != nil {
                    Button("Retry saving receipt") { store.retryDocumentHistorySave(); refresh() }
                        .disabled(store.isWorking || store.isShuttingDown)
                }
                Spacer()
                Button("Open Work together", systemImage: "doc.text") { store.open(.context) }
                    .buttonStyle(WorkspaceActionStyle(prominent: true))
            }
        }
        .padding(22)
        .frame(width: 620, alignment: .leading)
        .background(WorkspaceTheme.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.work-summary.detail")
        .onAppear(perform: refresh)
    }

    private var historyIssue: String? {
        if store.isShuttingDown { return "Work history will be available when ARCHi is open again." }
        if store.profileRecoveryBlock != nil { return "Finish profile recovery before reviewing document work." }
        if store.pendingDocumentReceipt != nil { return "An applied change still needs its receipt saved. Resolve it before reviewing outcomes." }
        if journal.loadError != nil || !journal.isCurrentOnDisk { return "Document history needs review or recovery. Open Work together to see the current notice." }
        if HamptonMethodOutcomes(records: journal.records).reconciliationIssue != nil {
            return "Document history has conflicting request ownership. Its outcome counts are unavailable."
        }
        return nil
    }

    private func refresh() {
        guard let issue = historyIssue else {
            let outcomes = HamptonMethodOutcomes(records: journal.records)
            let queue = store.documentReviewQueue
            var pending = Set(queue?.records.map(\.id) ?? [])
            if let current = store.currentDocumentOutcome, current.feedback == nil,
               HamptonMethodOutcomes(records: [current]).awaitingReview == 1 {
                pending.insert(current.id)
            }
            let methodsCurrent = methods.loadError == nil && methods.isCurrentOnDisk
            let available = methodsCurrent ? methods.latestProcedures.filter {
                store.documentProcedureUnavailable($0.binding) == nil
            }.count : nil
            var notes: [String] = []
            if store.isWorking { notes.append("Reviews resume after the current request finishes.") }
            else if queue == nil { notes.append("Applied work is temporarily unavailable for review.") }
            if let queue, queue.blockedCount > 0 {
                notes.append("\(queue.blockedCount) other applied edits need their source support restored.")
            }
            if !methodsCurrent { notes.append("Saved methods need library review.") }
            summary = Summary(awaitingReview: queue == nil ? nil : pending.count,
                helpful: outcomes.helpful, availableMethods: available,
                isEmpty: outcomes.attempts == 0 && methodsCurrent && methods.latestProcedures.isEmpty,
                notice: notes.isEmpty ? nil : notes.joined(separator: " "))
            return
        }
        summary = .unavailable(issue)
    }

    private func reset() {
        detail = nil
        showsLearning = false
        refresh()
    }

    private struct Summary {
        let awaitingReview: Int?
        let helpful: Int?
        let availableMethods: Int?
        let isEmpty: Bool
        let notice: String?
        static func unavailable(_ reason: String) -> Self {
            .init(awaitingReview: nil, helpful: nil, availableMethods: nil, isEmpty: false, notice: reason)
        }
    }

    private enum Detail: String, Identifiable {
        case reviews, methods
        var id: String { rawValue }
        var title: String { self == .reviews ? "Review your applied work" : "Your saved methods" }
    }
}
