import Foundation

/// Small native-owned wire descriptor. Asset data lives in the qualified loose
/// package; graph bindings live in a private, digest-bound session sidecar.
struct LiminalPointPresentation: Codable, Equatable {
    let schemaVersion: Int
    let assetID: String
    let manifestSHA256: String
    let progress: Double
    let motion: String
    let color: String
    let visible: Bool

    var isValid: Bool {
        schemaVersion == 1 && assetID == "liminal-v008" && LiminalKnowledgeBindings.isDigest(manifestSHA256)
            && progress.isFinite && (0...1).contains(progress)
            && ["sampled", "reduced"].contains(motion)
            && CompanionSeedColor(rawValue: color) != nil
    }
}
