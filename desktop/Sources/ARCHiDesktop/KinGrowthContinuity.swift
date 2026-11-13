import Foundation

/// A value check immediately before the existing Evolution owner changes KIN's
/// body. This is an ephemeral projection, not another identity or save owner.
/// Evidence is compared in full; acceptance does not establish its semantic truth.
struct KinGrowthContinuity<Evidence: Equatable & Sendable>: Sendable {
    struct Record: Equatable, Sendable {
        let id: UUID
        let originDigest: String
        let active: Bool
        let evidence: Evidence
    }

    struct Snapshot: Equatable, Sendable {
        let originDigest: String
        let revision: UInt64
        let record: Record?
    }

    enum Effect: Sendable {
        case keepFirstLight(id: UUID, evidence: Evidence)
        case returnToSeed
        case resumeFirstLight
    }

    let before: Snapshot
    let effect: Effect

    /// Structural validity is checked by the caller. A valid record for the
    /// wrong individual, or a valid but unrequested body change, still fails.
    func accepts(current: Snapshot, candidate: Record) -> Bool {
        guard current == before, candidate.originDigest == before.originDigest else { return false }
        switch effect {
        case .keepFirstLight(let id, let evidence):
            return before.record == nil && candidate.id == id && candidate.active
                && candidate.evidence == evidence
        case .returnToSeed, .resumeFirstLight:
            guard let prior = before.record, prior.originDigest == before.originDigest else { return false }
            let targetActive: Bool
            switch effect {
            case .returnToSeed: targetActive = false
            case .resumeFirstLight: targetActive = true
            case .keepFirstLight: return false
            }
            return prior.active != targetActive && candidate.active == targetActive
                && candidate.id == prior.id && candidate.evidence == prior.evidence
        }
    }
}
