import SwiftUI

/// A preview of a body is view-local. The existing Evolution store alone owns
/// the kept form and its saved historical reason.
@MainActor
struct KinGrowthCard: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject var evolution: EvolutionStore
    @State var showStudy = false
    @State var selectedReceiptID: UUID?
    @State private var saveNotice: String?

    private var matchingRecord: KinGrowthRecord? {
        guard let kin = store.activeQiMon, kin.character == .kin,
              let record = evolution.kinGrowthRecord, record.originDigest == kin.originDigest else { return nil }
        return record
    }

    var body: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("A first unfolding", systemImage: "leaf")
                    .font(.system(size: 18, weight: .medium))
                if store.activeQiMon?.character == .hampton {
                    Text("Liminal Seed · a new beginning")
                        .font(.system(size: 14, weight: .medium))
                    Text("Potential is room to develop through shared experience. This Seed has no earned later body yet; KIN’s First Light belongs to KIN.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("Review kept lessons") { store.open(.memory) }.buttonStyle(.borderless)
                } else if let record = matchingRecord {
                    Text(record.active ? "First Light · kept for KIN" : "Core Seed · First Light is still yours to use")
                        .font(.system(size: 14, weight: .medium))
                    Text("Your teaching helped, and you chose this body. His Seed remains your desktop cursor presence. Using the Seed as his body keeps this milestone.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    if let use = record.receipt.lessonUse { reason(use, requestID: record.receipt.requestID) }
                    HStack {
                        if record.active {
                            Button("Use Seed body") { store.returnKinToSeed() }
                                .accessibilityIdentifier("kin-growth.return")
                        } else {
                            Button("Use First Light") { _ = store.resumeKinFirstLight() }
                                .accessibilityIdentifier("kin-growth.resume")
                        }
                        saveControls
                    }.buttonStyle(.bordered).disabled(!store.kinGrowthControlsAvailable)
                } else if evolution.kinGrowthRecord != nil {
                    Text("The loaded form record belongs to another individual. KIN keeps Core Seed. Load his saved development to use his kept form.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Text("When a kept lesson helps with a local answer and you confirm it, KIN can grow into First Light. You choose whether to keep the change.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    if store.kinGrowthEvidence.isEmpty {
                        Text("Teach a lesson in What I remember, ask a matching question in chat or about a shared document, then confirm that the cited lesson helped. A conversation alone never changes his body.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Button("Review kept lessons") { store.open(.memory) }.buttonStyle(.borderless)
                    } else {
                        Picker("A lesson that helped", selection: $selectedReceiptID) {
                            Text("Choose a retained experience").tag(nil as UUID?)
                            ForEach(store.kinGrowthEvidence, id: \.requestID) { receipt in
                                Text(evidenceTitle(receipt)).tag(Optional(receipt.requestID))
                            }
                        }.accessibilityIdentifier("kin-growth.evidence")
                    }
                    Button(showStudy ? "Close form preview" : "Preview First Light") {
                        showStudy.toggle()
                        evolution.dismissKinGrowthPreview()
                        if showStudy, let id = selectedReceiptID { _ = store.previewKinGrowth(receiptID: id) }
                    }.buttonStyle(.bordered).disabled(!store.kinGrowthControlsAvailable)
                        .accessibilityIdentifier("kin-growth.preview")
                    if showStudy { preview }
                }
                Text(evolution.hasUnsavedChanges
                     ? "Changes are in this session. Save evolution to keep them on this Mac; Load restores them next visit."
                     : "Evolution uses explicit Save and Load. Your identity and kept lessons keep their existing storage.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if let saveNotice {
                    Text("Last save: \(saveNotice)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .accessibilityIdentifier("kin-growth.save-result")
                }
            }
        }
        .accessibilityIdentifier("kin-growth.card")
        .onChange(of: selectedReceiptID) { _, id in
            evolution.dismissKinGrowthPreview()
            if showStudy, let id { _ = store.previewKinGrowth(receiptID: id) }
        }
        .onDisappear { evolution.dismissKinGrowthPreview() }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CompanionPresenceArt(form: .kinSeed, family: nil, size: 116, reduceMotion: true, seedColor: store.preferences.seedColor)
                    .accessibilityLabel("KIN Core Seed, unchanged beginning")
                Image(systemName: "arrow.right").accessibilityHidden(true)
                CompanionPresenceArt(form: .kin, family: nil, size: 144,
                    reduceMotion: store.preferences.reduceMotion || store.preferences.quiet,
                    treatment: store.preferences.visualTreatment, seedColor: store.preferences.seedColor)
                    .accessibilityLabel("First Light body preview, not kept")
                Spacer(minLength: 0)
            }
            Text("First Light unfolds the body expression you have chosen around the same ivory core. His Seed stays on the desktop for pointing and chat. Both share his lessons, items and abilities.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if let proposal = evolution.kinGrowthProposal, let use = proposal.receipt.lessonUse {
                reason(use, requestID: proposal.receipt.requestID)
            }
            if store.canKeepKinGrowth {
                Button("Keep First Light") { if store.keepKinGrowth() { showStudy = false } }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("kin-growth.keep")
            } else {
                Text("Preview only. Choose a retained experience with a currently kept lesson to invite this change.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if let id = selectedReceiptID, store.kinGrowthEvidence.contains(where: { $0.requestID == id }) {
                    Button("Refresh invitation") { _ = store.previewKinGrowth(receiptID: id) }
                        .buttonStyle(.borderless).disabled(!store.kinGrowthControlsAvailable)
                }
            }
        }.accessibilityIdentifier("kin-growth.body-preview")
    }

    private var saveControls: some View {
        Button("Save evolution") {
            _ = evolution.save()
            saveNotice = evolution.status
        }
            .disabled(!evolution.hasUnsavedChanges)
            .accessibilityIdentifier("kin-growth.save")
    }

    private func reason(_ use: EvolutionLessonUse, requestID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.lessonUseDescription(use))
            Text("Retained request \(requestID.uuidString.prefix(8)) · a reviewed learning milestone")
        }.font(.system(size: 11)).foregroundStyle(.secondary)
    }

    private func evidenceTitle(_ receipt: EvolutionUsefulReceipt) -> String {
        guard let use = receipt.lessonUse else { return "Retained work" }
        let topic = store.keptLessons.first { use.matches(snapshot: LessonSnapshot(lesson: $0)) }?.topic ?? "Kept lesson"
        return "\(topic) · \(receipt.sourceDigest == nil ? "chat" : "document") · \(receipt.requestID.uuidString.prefix(8))"
    }
}
