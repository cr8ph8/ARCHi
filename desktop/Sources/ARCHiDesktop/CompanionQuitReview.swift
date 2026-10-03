import AppKit

enum EvolutionQuitDecision {
    case review
    case saveAndQuit
    case quitWithoutSaving
}

extension CompanionStore {
    /// The app-level quit hook joins the two existing retention owners. The
    /// callbacks are a narrow test seam for decisions made by native modal UI;
    /// neither callback owns or writes a copy of the companion's state.
    @MainActor
    func confirmQuitRetainingWork(
        reviewWorkingCopy: (() -> Bool)? = nil,
        chooseEvolution: (() -> EvolutionQuitDecision)? = nil
    ) -> Bool {
        guard !isImageRegionImportPresented else {
            status = "Use or close the image region draft before quitting. Your draft is still open."
            return false
        }
        guard !pastedDocumentDraft.hasContent else {
            status = "Use or discard your pasted text draft before quitting. Your draft is still open."
            open(.context)
            return false
        }
        let reviewedSource = QuitSourceSnapshot(store: self)
        guard (reviewWorkingCopy ?? confirmQuitWithWorkingCopy)() else { return false }
        guard reviewedSource.matches(self) else { return keepChangedSourceOpen() }

        guard evolution.hasUnsavedChanges else { return true }
        let reviewedEvolutionRevision = evolution.revision
        let reviewedUnsavedState = evolution.hasUnsavedChanges
        let decision = (chooseEvolution ?? presentEvolutionQuitChoice)()

        // NSAlert.runModal services the main run loop. An earlier document
        // discard choice must not cover edits made during this later prompt.
        guard reviewedSource.matches(self) else { return keepChangedSourceOpen() }
        guard evolution.revision == reviewedEvolutionRevision,
              evolution.hasUnsavedChanges == reviewedUnsavedState else {
            status = "Evolution changed while the quit choice was open. Review the latest changes before quitting."
            open(.evolution)
            return false
        }

        switch decision {
        case .review:
            open(.evolution)
            return false
        case .quitWithoutSaving:
            // This is permission to end the session, never a delete, Load, or
            // mutation of the still-open session or its earlier saved version.
            return true
        case .saveAndQuit:
            // Invalid saved files still require the existing explicit Replace
            // action in Evolution. Quit cannot silently acquire that authority.
            guard evolution.save() else {
                status = "ARCHi is staying open because Evolution was not saved. \(evolution.status)"
                open(.evolution)
                return false
            }
            guard reviewedSource.matches(self) else { return keepChangedSourceOpen() }
            guard evolution.revision == reviewedEvolutionRevision,
                  !evolution.hasUnsavedChanges else {
                status = "Evolution changed during saving. ARCHi is staying open so you can review it."
                open(.evolution)
                return false
            }
            return true
        }
    }

    @MainActor
    private func presentEvolutionQuitChoice() -> EvolutionQuitDecision {
        let alert = NSAlert()
        alert.messageText = "Keep your Evolution changes before quitting?"
        alert.informativeText = "Your confirmed choices and shared growth history have changes from this session. Save them on this Mac, or review them and keep working. Quitting without saving leaves any earlier Evolution save unchanged. Saving Evolution does not export a document draft."
        alert.alertStyle = .warning
        let review = alert.addButton(withTitle: "Review Evolution")
        review.keyEquivalent = "\r"
        alert.addButton(withTitle: "Save and quit")
        let discard = alert.addButton(withTitle: "Quit without saving")
        discard.hasDestructiveAction = true
        switch alert.runModal() {
        case .alertSecondButtonReturn: return .saveAndQuit
        case .alertThirdButtonReturn: return .quitWithoutSaving
        default: return .review
        }
    }

    @MainActor
    private func keepChangedSourceOpen() -> Bool {
        status = "The working copy changed while the quit choice was open. Review the latest draft before quitting."
        open(.context)
        return false
    }
}

/// Source text is compared as bytes: canonically equivalent Unicode is not an
/// export or approval for a different document. This snapshot is short-lived.
@MainActor
private struct QuitSourceSnapshot {
    let revision: UInt64
    let name: String?
    let bytes: Data

    init(store: CompanionStore) {
        revision = store.sourceRevision
        name = store.sourceName
        bytes = Data(store.sharedText.utf8)
    }

    func matches(_ store: CompanionStore) -> Bool {
        !store.isImageRegionImportPresented && !store.pastedDocumentDraft.hasContent && revision == store.sourceRevision && name == store.sourceName
            && bytes == Data(store.sharedText.utf8)
    }
}
