import Foundation

@MainActor
extension CompanionStore {
    /// Kept knowledge is a separate owner and can change without an Evolution
    /// revision. Recheck its exact version and expiry at both Preview and Keep.
    var kinGrowthEvidence: [EvolutionUsefulReceipt] {
        guard activeQiMon?.character == .kin else { return [] }
        return evolution.usefulReceipts.filter { receipt in
            guard let use = receipt.lessonUse else { return false }
            return keptLessons.contains { lesson in
                let snapshot = LessonSnapshot(lesson: lesson)
                return use.matches(snapshot: snapshot) && currentKeptLesson(matching: snapshot) != nil
            }
        }
    }

    var kinGrowthControlsAvailable: Bool { activeQiMon?.character == .kin && !isWorking && !isShuttingDown }

    @discardableResult
    func previewKinGrowth(receiptID: UUID) -> Bool {
        guard kinGrowthControlsAvailable, let kin = activeQiMon,
              let receipt = kinGrowthEvidence.first(where: { $0.requestID == receiptID }) else { return false }
        return evolution.proposeKinGrowth(originDigest: kin.originDigest, receipt: receipt) != nil
    }

    var canKeepKinGrowth: Bool {
        guard kinGrowthControlsAvailable, let kin = activeQiMon,
              let proposal = evolution.kinGrowthProposal,
              proposal.originDigest == kin.originDigest,
              proposal.revision == evolution.revision,
              kinGrowthEvidence.contains(proposal.receipt) else { return false }
        return true
    }

    @discardableResult
    func keepKinGrowth() -> Bool {
        guard canKeepKinGrowth, let candidate = evolution.kinGrowthProposal else {
            evolution.dismissKinGrowthPreview()
            return false
        }
        stopKinLightPreview()
        return evolution.keepKinGrowth(candidate)
    }

    func returnKinToSeed() {
        guard kinGrowthControlsAvailable, let kin = activeQiMon else { return }
        stopKinLightPreview()
        evolution.returnKinToSeed(originDigest: kin.originDigest)
    }

    @discardableResult
    func resumeKinFirstLight() -> Bool {
        guard kinGrowthControlsAvailable, let kin = activeQiMon else { return false }
        stopKinLightPreview()
        return evolution.resumeKinGrowth(originDigest: kin.originDigest)
    }
}
