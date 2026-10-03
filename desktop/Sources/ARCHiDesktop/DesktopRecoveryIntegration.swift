import Foundation

enum DesktopRecoveryError: LocalizedError {
    case blocked(String)
    case retainedRollback(String, URL)
    var errorDescription: String? {
        switch self { case .blocked(let reason), .retainedRollback(let reason, _): reason }
    }
    var rollbackArchiveURL: URL? { if case .retainedRollback(_, let url) = self { return url }; return nil }
}

struct DesktopRestoreStamp: Equatable {
    let preferences: CompanionPreferences
    let preferenceBaseline: Data?
    let lessonRevision: UInt64
    let evolutionRevision: UInt64
}

struct DesktopRestoreReview {
    let preview: DesktopProfileBackup.RestorePreview
    let stamp: DesktopRestoreStamp
}

/// Resolves only a verified interrupted operation against its fixed local
/// profile. If files differ from both known pairs, nothing is guessed or loaded.
@MainActor
enum DesktopRecoveryStartup {
    static func profile(at url: URL) -> DesktopProfileBackup.ProfileKind {
        switch url.standardizedFileURL.deletingLastPathComponent().lastPathComponent {
        case "ARCHiDesktopReview": .review
        case "ARCHiDesktop": .preview
        default: .custom
        }
    }

    static func recoverIfNeeded(at url: URL) -> String? {
        do {
            if let pending = try DesktopProfileBackup.pendingRecovery(profile: profile(at: url), preferenceURL: url) {
                _ = try DesktopProfileBackup.recover(pending)
            }
            return nil
        } catch {
            return "Profile recovery needs review. Saved data has been preserved and saving is paused. " + error.localizedDescription
        }
    }
}

@MainActor
extension CompanionStore {
    var recoveryJournalBlockReason: String? {
        DesktopProfileBackup.hasPendingJournal(preferenceURL: recoveryPreferenceURL)
            ? (profileRecoveryBlock ?? "Resolve the interrupted restore before choosing another backup.") : nil
    }
    func createProfileBackup(at destination: URL) throws -> DesktopProfileBackup.ArchiveSummary {
        if let reason = recoveryBusyReason ?? profileRecoveryBlock { throw DesktopRecoveryError.blocked(reason) }
        return try DesktopProfileBackup.create(profile: DesktopRecoveryStartup.profile(at: recoveryPreferenceURL),
            preferenceURL: recoveryPreferenceURL, archiveURL: destination)
    }

    func previewProfileRestore(from archive: URL) throws -> DesktopRestoreReview {
        if let reason = recoveryRestoreBlockReason ?? recoveryJournalBlockReason { throw DesktopRecoveryError.blocked(reason) }
        let preview = try DesktopProfileBackup.preview(archiveURL: archive,
            profile: DesktopRecoveryStartup.profile(at: recoveryPreferenceURL), preferenceURL: recoveryPreferenceURL)
        return DesktopRestoreReview(preview: preview, stamp: recoveryStamp)
    }

    func restoreProfile(_ review: DesktopRestoreReview) throws -> DesktopProfileBackup.RestoreReport {
        if let reason = recoveryRestoreBlockReason ?? recoveryJournalBlockReason { throw DesktopRecoveryError.blocked(reason) }
        guard recoveryStamp == review.stamp else {
            throw DesktopRecoveryError.blocked("Your choices changed while the restore preview was open. Preview this backup again.")
        }
        let rollbackDirectory = recoveryPreferenceURL.deletingLastPathComponent().appendingPathComponent("Recovery", isDirectory: true)
        let report: DesktopProfileBackup.RestoreReport
        do {
            // Synchronous on MainActor: no in-app writer runs between preflight,
            // file replacement and re-admission. Other processes are rechecked.
            report = try DesktopProfileBackup.restore(review.preview, rollbackDirectory: rollbackDirectory)
        } catch {
            if DesktopProfileBackup.hasPendingJournal(preferenceURL: recoveryPreferenceURL) {
                blockProfileForRecovery("Restore could not finish. Saved data is preserved for recovery. " + error.localizedDescription)
            }
            throw error
        }
        do {
            try admitRestoredProfile()
            return report
        } catch {
            do {
                _ = try DesktopProfileBackup.undoRestore(report)
                try admitRestoredProfile()
            } catch {
                blockProfileForRecovery("Profile recovery needs review before saving. The before-restore backup has been retained.")
            }
            throw DesktopRecoveryError.retainedRollback("The restored profile could not be loaded. The before-restore backup has been retained; review recovery before continuing.", report.rollbackArchiveURL)
        }
    }

    func retryInterruptedProfileRecovery(discardVisitChoices: Bool = false) throws {
        if let reason = recoveryBusyReason { throw DesktopRecoveryError.blocked(reason) }
        if !discardVisitChoices, hasUnreviewedRecoveryChoices {
            throw DesktopRecoveryError.blocked("Review replacing your temporary appearance and Evolution choices before recovery.")
        }
        if !discardVisitChoices, let reason = recoveryRestoreBlockReason { throw DesktopRecoveryError.blocked(reason) }
        guard lessonDraft == nil, !hasOpenKnowledgeDraft, focusGestureDraft == nil, voiceInput.phase != .review else {
            throw DesktopRecoveryError.blocked("Keep or discard your lesson, knowledge page or connection, gesture or voice draft before loading recovered choices.")
        }
        if let reason = DesktopRecoveryStartup.recoverIfNeeded(at: recoveryPreferenceURL) {
            blockProfileForRecovery(reason)
            throw DesktopRecoveryError.blocked(reason)
        }
        do { try admitRestoredProfile() }
        catch {
            blockProfileForRecovery("Recovered files need review before saving. " + error.localizedDescription)
            throw error
        }
    }
}
