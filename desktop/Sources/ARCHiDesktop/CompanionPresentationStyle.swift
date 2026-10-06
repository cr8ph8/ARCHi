import SwiftUI

/// Presentation of the current individual. The serialized Seed identifiers and
/// the identity/development owners remain unchanged.
enum CompanionPresentationStyle: String, CaseIterable, Identifiable {
    case proto, kin, liminal
    var id: Self { self }
    var title: String { switch self { case .proto: "Proto"; case .kin: "KIN"; case .liminal: "Liminal" } }
    var detail: String {
        switch self {
        case .proto: "Light Seed · aqua body"
        case .kin: "Particle Seed · First Light body"
        case .liminal: "Garnet Seed · curled and beast forms"
        }
    }
    var seedForm: CompanionForm { switch self { case .proto: .corePearl; case .kin: .particleSeed; case .liminal: .hamptonSeed } }
    var bodyForm: CompanionForm { self == .liminal ? .hamptonSeed : .kin }
    var treatment: CompanionVisualTreatment { self == .proto ? .protoStudy : .original }
    var seedAppearance: CompanionSeedAppearance {
        switch self { case .proto: .archiLight; case .kin: .kinParticles; case .liminal: .hamptonLiminal }
    }
    static func resolve(_ preferences: CompanionPreferences) -> Self? {
        switch preferences.seedAppearance {
        case .hamptonLiminal: .liminal
        case .kinParticles: preferences.visualTreatment == .protoStudy ? .proto : .kin
        case .archiLight: preferences.visualTreatment == .protoStudy ? .proto : nil
        case .vela: nil
        }
    }
}

enum CompanionPresentationPose: String, Codable, CaseIterable, Identifiable {
    case seed, body
    var id: Self { self }
    var title: String { self == .seed ? "Seed" : "Body" }
}

@MainActor extension CompanionStore {
    var companionPresentationStyle: CompanionPresentationStyle? { .resolve(preferences) }
    var companionPresentationPose: CompanionPresentationPose {
        if companionPresentationStyle == .liminal {
            return preferences.visualTreatment == .liminalV008
                && abs(preferences.liminalPointProgress - LiminalV008Runtime.orbProgress) > 0.001 ? .body : .seed
        }
        return preferences.companionPose ?? (presentationForm == .kin ? .body : .seed)
    }
    var canPresentCompanionBody: Bool {
        guard !isShuttingDown, !hasPersonalQiMon || activeQiMon != nil else { return false }
        switch companionPresentationStyle {
        case .proto: return CompanionVisualAsset.protoImage != nil
        case .kin: return activeQiMon != nil && CompanionVisualAsset.kinFirstLightImage != nil
        case .liminal: return LiminalV008Runtime.asset != nil
        case nil: return false
        }
    }
    func chooseCompanionPresentationStyle(_ style: CompanionPresentationStyle) {
        guard !isShuttingDown, !hasPersonalQiMon || activeQiMon != nil,
              companionPresentationStyle != style else { return }
        chooseSeedAppearance(style.seedAppearance)
        preferences.companionPose = .seed
        preferences.visualTreatment = style.treatment
        if style == .liminal { preferences.liminalPointProgress = LiminalV008Runtime.orbProgress }
    }
    func chooseCompanionPresentationPose(_ pose: CompanionPresentationPose) {
        guard !isShuttingDown, !hasPersonalQiMon || activeQiMon != nil,
              companionPresentationStyle != nil, pose == .seed || canPresentCompanionBody else { return }
        stopKinLightPreview()
        preferences.companionPose = pose
        if companionPresentationStyle == .liminal {
            preferences.visualTreatment = pose == .body ? .liminalV008 : .original
            preferences.liminalPointProgress = pose == .body ? LiminalV008Runtime.standingProgress : LiminalV008Runtime.orbProgress
        } else if !hasPersonalQiMon {
            preferences.form = pose == .body ? .companion : companionPresentationStyle!.seedForm
        }
    }
}
