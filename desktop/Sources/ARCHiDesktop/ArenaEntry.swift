import Foundation

/// One consumer entry shared by Home, the Arena page and app menus. Browsing the
/// page remains passive; only this explicit action starts or focuses its owner.
enum ArenaEntryAction {
    @MainActor
    static func open(store: CompanionStore, connection: UnityPresentationConnection? = nil) async {
        store.open(.unity)
        let owner = connection ?? store.unityPresentation
        let state = ArenaEntryState(store: store, connection: owner)
        guard state.canEnter else { return }
        if !store.isVisible { store.showCompanion() }
        await owner.openArena(store: store)
    }
}

/// Availability is read-only and uses the same capability gates as the launcher.
struct ArenaEntryState: Equatable {
    enum Availability: Equatable {
        case ready, opening, open, hidden, retry, unavailable, updateRequired, closing
    }

    let availability: Availability
    let title: String
    let summary: String
    let actionTitle: String
    let canEnter: Bool

    @MainActor
    init(store: CompanionStore, connection: UnityPresentationConnection? = nil) {
        let owner = connection ?? store.unityPresentation
        let hasCompanion = store.activeQiMon != nil
        if store.isShuttingDown {
            self.init(.closing, "Finishing your session", "Arena will be ready when ARCHi opens again.", "Finishing…", false)
        } else if let reason = store.unityPresentationUnavailableReason(for: owner.availablePlayer) {
            self.init(.updateRequired, "Arena needs a Seed update", reason, "Set up Arena", false)
        } else if let player = owner.availablePlayer {
            let supportsLook = !hasCompanion || store.preferences.seedAppearance == .kinParticles
                || UnityPresentationConnection.supportsSeedAppearances(player)
            let supportsOutfit = !hasCompanion || store.preferences.equipment.design == nil
                || UnityPresentationConnection.supportsStaffRecipes(player)
            if !UnityPresentationConnection.supportsArena(player) || !supportsLook || !supportsOutfit {
                self.init(.updateRequired, "Arena needs an update",
                    "Use the current ARCHi app with Arena included to bring your companion’s look and outfit along.", "Set up Arena", false)
            } else if !store.isVisible {
                self.init(.hidden, "Your companion is hidden", "Show your companion, then head into a practice round together.", "Show & play", true)
            } else if owner.isSharing && owner.destination == .arena {
                if owner.hasRenderAcknowledgment && owner.lastSnapshot?.active == true && owner.lastSnapshot?.visible == true {
                    self.init(.open, "Your Arena is open", "Pick up where you left off. Your current practice session is waiting.", "Return to Arena", true)
                } else {
                    self.init(.opening, "Getting Arena ready",
                        owner.isOpening ? "Your practice window is opening." : "Connecting your companion. You can end the session below and try again if this takes longer.",
                        "Show Arena", true)
                }
            } else if owner.lastLaunchFailure != nil {
                self.init(.retry, "Arena couldn’t open", "Try again, or reconnect the Arena app in Advanced below.", "Try again", true)
            } else {
                self.init(.ready, "Ready for a round?",
                    hasCompanion ? "Try a friendly practice round with your companion. Your current look and outfit come along."
                        : "Choose from the practice roster and try a round. You don’t need to set up a companion first.", "Play Arena", true)
            }
        } else {
            self.init(.unavailable, "Arena isn’t included in this copy",
                "Open the current ARCHi app with Arena included. If you already have an Arena app, connect it in Advanced below.", "Set up Arena", false)
        }
    }

    private init(_ availability: Availability, _ title: String, _ summary: String, _ actionTitle: String, _ canEnter: Bool) {
        self.availability = availability; self.title = title; self.summary = summary
        self.actionTitle = actionTitle; self.canEnter = canEnter
    }
}
