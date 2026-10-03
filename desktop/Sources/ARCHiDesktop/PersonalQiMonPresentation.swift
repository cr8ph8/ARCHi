import Foundation

/// Two native presentations of the same individual. A surface has no saved
/// identity, development, placement or permission state of its own.
enum CompanionPresentationRole: Equatable, Sendable {
    case body
    case cursor
}

@MainActor
extension CompanionStore {
    var hasPersonalQiMon: Bool { keptQiMon != nil }
    var canChooseStartingForm: Bool { !hasPersonalQiMon }

    /// Identity remains in LocalQiMon. The existing Evolution owner supplies
    /// an explicitly kept body only for that same individual.
    func presentationForm(for preferences: CompanionPreferences, role: CompanionPresentationRole = .body) -> CompanionForm {
        if let kin = activeQiMon {
            // The Seed persists as the individual's cursor even after a body is kept.
            // Use the same active-identity check as body presentation.
            if role == .cursor { return preferences.seedAppearance.personalForm }
            // A chosen Liminal form cannot be overridden by an earlier KIN body.
            // That growth record remains retained; this only resolves appearance.
            if preferences.seedAppearance == .hamptonLiminal { return .hamptonSeed }
            if let pose = preferences.companionPose,
               let style = CompanionPresentationStyle.resolve(preferences) {
                return pose == .seed ? preferences.seedAppearance.personalForm : style.bodyForm
            }
            if kin.character == .kin, let growth = evolution.kinGrowthRecord,
               growth.originDigest == kin.originDigest, growth.active { return .kin }
            return preferences.seedAppearance.personalForm
        }
        return preferences.form.isKin ? .companion : preferences.form
    }
    var presentationForm: CompanionForm { presentationForm(for: preferences) }
    var cursorPresentationForm: CompanionForm { presentationForm(for: preferences, role: .cursor) }
    var presentationFamily: EvolutionFamily? { hasPersonalQiMon ? nil : evolution.activeFamily }
    var presentationRecipe: CompanionAppearanceRecipe? { hasPersonalQiMon ? nil : evolution.activeAppearanceRecipe }
    var presentationNaturalVariation: CompanionNaturalVariation? { hasPersonalQiMon ? nil : evolution.naturalVariation }
    var presentationTitle: String { activeQiMon?.name ?? presentationFamily?.title ?? presentationForm.rawValue }
    var kinBodyTitle: String {
        switch presentationForm {
        case .kin: preferences.visualTreatment == .protoStudy ? "Proto body"
            : preferences.companionPose == .body ? "KIN body" : "First Light"
        case .corePearl: "Ball of Light"
        case .hamptonSeed: preferences.visualTreatment == .liminalV008
            && companionPresentationPose == .body ? "Liminal body" : "Liminal Seed"
        case .velaSeed: "Opal Seed"
        case .velaLantern: "Lantern Wing"
        default: "Particle Seed"
        }
    }

    var requiresPersonalSeedPresentation: Bool {
        activeQiMon != nil && (preferences.seedColor != .original
            || preferences.seedAppearance == .hamptonLiminal || preferences.seedAppearance == .vela)
    }

    var unityPresentationUnavailableReason: String? {
        unityPresentationUnavailableReason(for: unityPresentation.availablePlayer)
    }

    func unityPresentationUnavailableReason(for player: URL?) -> String? {
        if LiminalV008Runtime.applies(form: presentationForm, family: presentationFamily,
                                     treatment: preferences.visualTreatment),
           player.map({ !UnityPresentationConnection.supportsPointAssets($0) }) ?? true {
            return "Update the included Arena to bring Liminal’s v008 particles with you. Your current desktop appearance stays in place."
        }
        if [.velaSeed, .velaLantern].contains(presentationForm)
            || [.velaSeed, .velaLantern].contains(cursorPresentationForm) {
            return "Vela is available on your desktop. The included Arena does not yet support this form. Choose another Seed or form to enter."
        }
        guard requiresPersonalSeedPresentation else { return nil }
        guard let player, UnityPresentationConnection.supportsPersonalSeeds(player) else {
            return "Update the included Arena to bring your selected Seed and color along. Your desktop appearance stays as you chose it."
        }
        return nil
    }

    func chooseSeedAppearance(_ appearance: CompanionSeedAppearance) {
        guard !isShuttingDown, !hasPersonalQiMon || activeQiMon != nil else { return }
        stopKinLightPreview()
        preferences.seedAppearance = appearance
        preferences.companionPose = nil
        if !hasPersonalQiMon { chooseStartingForm(appearance.starterForm) }
    }

    func chooseSeedColor(_ color: CompanionSeedColor) {
        guard !isShuttingDown, !hasPersonalQiMon || activeQiMon != nil else { return }
        stopKinLightPreview()
        preferences.seedColor = color
    }

    /// Uses the existing saved appearance preference. A missing or mismatched
    /// personal Journey cannot select a different individual's presentation.
    func chooseLightForm(_ form: CompanionForm) {
        guard !isShuttingDown, form.isOpticalLight else { return }
        guard !hasPersonalQiMon else { return }
        chooseStartingForm(form)
    }
}
