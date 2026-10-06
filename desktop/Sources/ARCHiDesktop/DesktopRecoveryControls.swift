import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Short-lived review UI; the existing persistence owners admit a restore.
@MainActor
struct DesktopRecoveryControls: View {
    @ObservedObject var store: CompanionStore
    @State private var review: DesktopRestoreReview?
    @State private var message = ""
    @State private var artifact: URL?
    @State private var confirmsRecovery = false

    private var restoreReason: String? { store.recoveryRestoreBlockReason ?? store.recoveryJournalBlockReason }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Backup & restore").font(.system(size: 15, weight: .semibold))
            Text("A backup contains saved settings, personal context, kept lessons, your companion, saved development, document reviews, method versions and kept reading copies. It includes private context, lessons and source text; keep it somewhere you trust. Unsaved drafts, chats, voice, original documents, usage and cost accounting, ARC sessions and evidence, and model choices are excluded.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            HStack {
                Button("Back up saved profile…", action: chooseBackup)
                    .accessibilityIdentifier("desktop-recovery.backup")
                    .disabled(store.recoveryBusyReason != nil || store.profileRecoveryBlock != nil)
                Button("Choose backup…", action: chooseRestore)
                    .accessibilityIdentifier("desktop-recovery.choose")
                    .disabled(restoreReason != nil)
            }.controlSize(.small)
            if let reason = restoreReason {
                Text(reason).font(.system(size: 12)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("desktop-recovery.blocked")
            }
            if store.profileRecoveryBlock != nil {
                Text(store.profileRecoveryBlock ?? "Profile recovery needs review.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Button("Retry interrupted recovery…") { confirmsRecovery = true }
                    .disabled(store.recoveryBusyReason != nil)
                    .accessibilityIdentifier("desktop-recovery.retry")
            }
            if let review {
                restorePreview(review)
            }
            if !message.isEmpty {
                Text(message).font(.system(size: 12)).textSelection(.enabled)
                    .accessibilityIdentifier("desktop-recovery.result")
            }
            if let artifact {
                Button("Show retained backup in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([artifact])
                }.buttonStyle(.borderless).accessibilityIdentifier("desktop-recovery.reveal")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
        .alert("Load the recovered saved profile?", isPresented: $confirmsRecovery) {
            Button("Cancel", role: .cancel) {}
            Button("Recover saved profile", role: .destructive) {
                do {
                    try store.retryInterruptedProfileRecovery(discardVisitChoices: true)
                    message = "The saved profile was recovered and loaded."
                } catch { message = error.localizedDescription }
            }
        } message: {
            Text("Recovery returns to the files from before the interrupted restore and loads their saved choices. Temporary appearance and Evolution choices will be replaced. Your typed draft and current working copy stay here; earlier answers, passage references and Undo are cleared.")
        }
    }

    private func restorePreview(_ review: DesktopRestoreReview) -> some View {
        let summary = review.preview.summary
        return VStack(alignment: .leading, spacing: 8) {
            Text("Review before restoring").font(.system(size: 13, weight: .semibold))
            if store.profileRecoveryBlock != nil {
                Text("Recovery is paused. Restoring this verified backup also replaces temporary appearance and Evolution choices, which cannot currently be saved.")
                    .foregroundStyle(.secondary)
            }
            Text("\(store.retentionProfileLabel) · \(summary.createdAt.formatted(date: .abbreviated, time: .shortened))")
            Text("\(summary.lessonCount) kept lessons · \(summary.companionName.map { "\($0) retained" } ?? "No saved companion")")
            Text(summary.evolutionPresent ? "Development: \(summary.bodyLabel ?? "saved choices")" : "No saved development in this backup.")
            if summary.includesDocumentWork {
                Text("\(summary.documentRecordCount) document records · \(summary.procedureCount) method versions · \(summary.readingSourceCount) kept reading copies · \(summary.knowledgePageVersionCount) page versions · \(summary.knowledgeLinkVersionCount) connection versions")
                Text("Restoring replaces five saved files: settings, development, document history, methods and reading copies. A file absent from the backup will be removed from this profile. Kept reading copies include private source text.")
                    .foregroundStyle(.secondary).lineSpacing(3)
            } else {
                Text("This older backup contains settings and development only. It can be restored only in a profile without document history, method or reading-library files. Restoring replaces those two files; an absent file is removed.")
                    .foregroundStyle(.secondary).lineSpacing(3)
            }
            Text("A before-restore backup is kept automatically. Your typed draft and current working copy stay here; earlier answers, passage references and Undo are cleared. Usage and costs, ARC sessions and evidence, and model choices stay separate.")
                .foregroundStyle(.secondary).lineSpacing(3)
            HStack {
                Button("Cancel preview") { self.review = nil }
                    .accessibilityIdentifier("desktop-recovery.cancel-preview")
                Button("Restore saved profile", role: .destructive) { restore(review) }
                    .buttonStyle(.borderedProminent)
                    .disabled(restoreReason != nil)
                    .accessibilityIdentifier("desktop-recovery.restore")
            }.controlSize(.small)
        }
        .font(.system(size: 12)).padding(12)
        .background(WorkspaceTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("desktop-recovery.preview")
    }

    private func chooseBackup() {
        review = nil; message = ""; artifact = nil
        let panel = NSSavePanel()
        panel.title = "Back up saved ARCHi profile"
        panel.message = "Saved choices, document reviews, method versions and kept reading copies are included. This includes private source text. Save settings or development you want included first; unsaved documents and chats are excluded."
        panel.nameFieldStringValue = "ARCHi-\(store.retentionProfileLabel.replacingOccurrences(of: " ", with: "-"))-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).archibackup"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "archibackup") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let result = try store.createProfileBackup(at: url)
            artifact = url
            message = "Backup verified · \(result.lessonCount) kept lessons\(result.companionName.map { ", \($0)" } ?? "")\(result.evolutionPresent ? ", saved development" : ""), \(result.documentRecordCount) document records, \(result.procedureCount) method versions and \(result.readingSourceCount) kept reading copies, with \(result.knowledgePageVersionCount) page versions and \(result.knowledgeLinkVersionCount) connection versions. Your current profile is unchanged."
        } catch { message = error.localizedDescription }
    }

    private func chooseRestore() {
        review = nil; message = ""; artifact = nil
        let panel = NSOpenPanel()
        panel.title = "Choose an ARCHi backup to review"
        panel.message = "Choosing a backup only opens a preview. No saved files change until you choose Restore saved profile."
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { review = try store.previewProfileRestore(from: url) }
        catch { message = error.localizedDescription }
    }

    private func restore(_ review: DesktopRestoreReview) {
        do {
            let report = try store.restoreProfile(review)
            artifact = report.rollbackArchiveURL
            message = "Profile restored and loaded. The before-restore backup is retained."
        } catch {
            message = error.localizedDescription
            if let failure = error as? DesktopProfileBackup.Failure {
                artifact = failure.rollbackArchiveURL
            } else if let failure = error as? DesktopRecoveryError {
                artifact = failure.rollbackArchiveURL
            }
        }
        self.review = nil
    }
}
