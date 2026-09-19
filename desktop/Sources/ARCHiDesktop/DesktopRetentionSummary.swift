import SwiftUI

/// A view of the existing save owners. Opening or navigating this sheet does
/// not read files, admit memory, change a model route or save a second snapshot.
@MainActor
struct DesktopRetentionSummary: View {
    @ObservedObject var store: CompanionStore
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Saved & this visit").font(.system(size: 22, weight: .medium, design: .rounded))
                    Text("\(store.retentionProfileLabel) · local profile")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .accessibilityIdentifier("desktop-retention.profile")
                }
                Spacer()
                Button("Done", action: close).keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("desktop-retention.close")
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DesktopRecoveryControls(store: store)
                    Divider()
                    retentionRow("Settings", state: store.preferenceRetention.title,
                        detail: settingsDetail, destination: .memory, action: "Review settings", id: "settings")
                    Divider()
                    retentionRow(store.hasRetainedQiMon ? "Knowledge & \(companionName)" : "Kept knowledge", state: knowledgeState,
                        detail: "Kept lessons\(store.hasRetainedQiMon ? ", \(companionName)’s identity" : "") and a kept staff gesture save through their explicit Keep, correction or withdrawal actions. Unkept drafts stay in this visit.",
                        destination: .memory, action: "Review kept lessons", id: "knowledge")
                    Divider()
                    retentionRow("Item collection", state: "\(store.itemLibrary.count) local designs",
                        detail: "Add to My items saves a recipe immediately. Equip changes this visit; Save preferences keeps the outfit. Remove clears the design and its saved outfit. Import and Create drafts are temporary.",
                        destination: .marketplace, action: "Review My items", id: "items")
                    Divider()
                    retentionRow("Development", state: store.evolution.requiresReplacement ? "Saved file needs review" : store.evolution.retentionState.title,
                        detail: developmentDetail + (store.evolution.requiresReplacement ? " " + store.evolution.status : ""),
                        destination: .evolution, action: "Review Save & Load", id: "development")
                    Divider()
                    retentionRow("Document draft", state: documentState,
                        detail: "Edits stay in the working copy until you Export a separate file. The original is unchanged. Reopen your exported file next visit; selection and Undo are temporary.",
                        destination: .context, action: "Review working copy", id: "document")
                    Divider()
                    retentionRow("Usage journal", state: store.tokenSteward.loadError == nil ? "Automatic local accounting" : "Needs attention",
                        detail: "Send records task IDs, model IDs, usage, timing and outcomes, without messages or document text. Limits and billing facts live in this separate journal. Export it in Token Steward; companion recovery packages do not include it.",
                        destination: .steward, action: "Review usage", id: "steward")
                    Divider()
                    retentionRow("Document methods & reviews", state: "\(store.documentProcedures.latestProcedures.count) methods · \(store.documentProcedures.procedures.count) versions",
                        detail: "Keep procedure saves your authored instruction and review references in a separate local file. Document history retains outcomes and counterexamples, without passage or reply text. These files are not included in companion recovery packages. Select a method explicitly before sending it through your chosen assistant route.",
                        destination: .context, action: "Review procedures", id: "procedures")
                    Divider()
                    retentionRow("ARC evidence", state: "\(store.arcCapabilities.records.count) retained evaluations",
                        detail: "Successful imports retain frozen tasks and raw predictions locally for re-scoring. The synthetic demonstration also saves its evidence. These records do not change your companion or enter model context; companion recovery packages do not include them.",
                        destination: .capabilities, action: "Review evidence", id: "capabilities")
                    Divider()
                    Text("Only this visit").font(.system(size: 13, weight: .semibold))
                    Text("Typed messages, replies, conversation, voice drafts, model selections and companion placement are temporary. Copy any chat text you want to keep before quitting. Voice input is not saved as audio.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                        .accessibilityIdentifier("desktop-retention.temporary")
                    Text("Saved means the last successful read or write by this app, not continuous disk verification. ARCHi keeps the existing companion profile previously named Development Review. Older preview saves stay preserved separately. A lessons export alone is not a complete companion backup.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                }.padding(24)
            }
        }
        .frame(width: 560, height: 540)
        .accessibilityIdentifier("desktop-retention.summary")
    }

    private var settingsDetail: String {
        if store.preferenceRetention == .unavailable {
            return "The settings file could not be read. It was preserved. Keep temporary work before reopening after restoring a valid file."
        }
        let earlier = store.hasSavedPreferences && !store.rememberPreferences
            ? " Turning Remember off leaves your earlier saved settings intact." : ""
        return "Appearance, equipped item, tone, reply length, motion and sound use Save preferences in What I remember. A kept body uses Save evolution." + earlier
    }

    private var companionName: String { store.keptQiMon?.name ?? "your companion" }

    private var knowledgeState: String {
        guard store.preferenceRetention != .unavailable else { return "Saved file unavailable" }
        let count = store.knownRetainedLessonCount
        var parts = ["\(count) kept \(count == 1 ? "lesson" : "lessons")"]
        if store.hasRetainedQiMon { parts.append("\(companionName) retained") }
        if store.hasRetainedFocusGesture { parts.append("Staff gesture retained") }
        return parts.joined(separator: " · ")
    }

    private var developmentDetail: String {
        switch store.evolution.retentionState {
        case .notLoaded:
            "An earlier save may exist. Load it in \(store.hasPersonalQiMon ? "Life with \(companionName)" : "Evolution") to restore role, help style, kept body and development records. Opening this summary does not load it."
        case .changed:
            "Role, help style, kept body or development records have changes in this visit. Save evolution to retain them. Load restores the saved version through its existing review."
        case .saved:
            "This visit matches the last successful Evolution Save or Load. On your next launch, Load restores that saved development."
        }
    }

    private var documentState: String {
        if store.sourceName == nil { return "No document shared" }
        return store.hasUnexportedWorkingCopy ? "Edits need Export" : "No unexported edits"
    }

    private func retentionRow(_ title: String, state: String, detail: String,
                              destination: WorkspaceSection, action: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(state).font(.system(size: 12, weight: .medium)).foregroundStyle(WorkspaceTheme.accent)
                .accessibilityIdentifier("desktop-retention.\(id).state")
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            Button(action) { close(); store.open(destination) }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("desktop-retention.\(id).review")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PreferenceRetentionState {
    var title: String {
        switch self {
        case .unavailable: "Saved file unavailable"
        case .thisVisit: "This visit only"
        case .changed: "Changes this visit"
        case .saved: "Matches saved settings"
        }
    }
}

extension EvolutionRetentionState {
    var title: String {
        switch self {
        case .notLoaded: "Not loaded this visit"
        case .changed: "Changes this visit"
        case .saved: "Matches saved development"
        }
    }
}
