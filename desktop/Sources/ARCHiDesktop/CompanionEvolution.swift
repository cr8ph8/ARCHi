import Foundation
import Combine
import CryptoKit
import Darwin

enum EvolutionFamily: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case lumen, fen, frame, pop, relic, veil
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var summary: String {
        switch self {
        case .lumen: "A luminous presence with a soft, guiding glow."
        case .fen: "An organic companion with a curious, woodland character."
        case .frame: "A geometric presence that gives ideas a clear outline."
        case .pop: "A playful, graphic companion with bright expression."
        case .relic: "A sculptural companion with a quiet, timeworn character."
        case .veil: "A flowing, translucent presence with gentle movement."
        }
    }
}

enum EvolutionRole: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case hearth, muse, scout, beacon, keeper, guardian
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var summary: String {
        switch self {
        case .hearth: "Help me settle into my work."
        case .muse: "Help me explore creative possibilities."
        case .scout: "Help me find what deserves a closer look."
        case .beacon: "Help me find a clear next step."
        case .keeper: "Help me organize what I choose to keep."
        case .guardian: "Help me review decisions and boundaries."
        }
    }
}

enum EvolutionHelpStyle: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case concise, exploratory, stepByStep, reflective
    var id: String { rawValue }
    var title: String {
        switch self {
        case .concise: "Concise"
        case .exploratory: "Exploratory"
        case .stepByStep: "Step by step"
        case .reflective: "Reflective"
        }
    }
}

enum EvolutionPreferenceCategory: String, CaseIterable, Identifiable, Sendable {
    case role, helpStyle, family
    var id: String { rawValue }
}

struct EvolutionPreferences: Equatable, Sendable {
    var role: EvolutionRole?
    var helpStyle: EvolutionHelpStyle?
    var family: EvolutionFamily?
    var confirmedCount: Int { [role != nil, helpStyle != nil, family != nil].filter { $0 }.count }
}

/// These identifiers refer to user-marked, completed requests. They contain no
/// document, question, answer, account, or model training data.
struct EvolutionUsefulReceipt: Codable, Equatable, Identifiable, Sendable {
    let requestID: UUID
    /// Absent for an ordinary conversation. Never substitute a message hash here.
    let sourceDigest: String?
    /// Absent only on preserved historical document receipts (v1–v6).
    let requestBinding: EvolutionRequestBinding?
    let lessonUse: EvolutionLessonUse?
    var id: UUID { requestID }

    init(requestID: UUID, sourceDigest: String?, requestBinding: EvolutionRequestBinding? = nil,
         lessonUse: EvolutionLessonUse? = nil) {
        self.requestID = requestID; self.sourceDigest = sourceDigest
        self.requestBinding = requestBinding; self.lessonUse = lessonUse
    }

    var hasValidEvidence: Bool {
        guard sourceDigest == nil || PracticeEvolutionReference.isDigest(sourceDigest!) else { return false }
        if let requestBinding { return requestBinding.isValid }
        return sourceDigest != nil
    }

    var evidenceTitle: String {
        if requestBinding == nil { return "Shared document · historical source reference" }
        return sourceDigest == nil ? "Conversation · local Qwen" : "Shared document"
    }

    private enum CodingKeys: String, CodingKey { case requestID, sourceDigest, requestBinding, lessonUse }
    private struct InputKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let all = try decoder.container(keyedBy: InputKey.self)
        let keys = Set(all.allKeys.map(\.stringValue))
        let required: Set<String> = ["requestID"]
        let allowed = required.union(["sourceDigest", "requestBinding", "lessonUse"])
        guard keys.isSuperset(of: required), keys.isSubset(of: allowed) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported useful-request fields."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try values.decode(UUID.self, forKey: .requestID)
        sourceDigest = try values.decodeIfPresent(String.self, forKey: .sourceDigest)
        requestBinding = try values.decodeIfPresent(EvolutionRequestBinding.self, forKey: .requestBinding)
        lessonUse = try values.decodeIfPresent(EvolutionLessonUse.self, forKey: .lessonUse)
        // A missing binding is legacy document evidence; a null binding is not.
        guard hasValidEvidence, !keys.contains("requestBinding") || requestBinding != nil,
              !keys.contains("sourceDigest") || sourceDigest != nil else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid useful-request evidence."))
        }
    }
}

/// Fingerprints bind new feedback to the exact dispatched input and request
/// context. They retain no question, answer, document, or reconstructable lesson.
struct EvolutionRequestBinding: Codable, Equatable, Sendable {
    let inputDigest: String
    let contextDigest: String
    var isValid: Bool {
        PracticeEvolutionReference.isDigest(inputDigest) && PracticeEvolutionReference.isDigest(contextDigest)
    }

    init(inputDigest: String, contextDigest: String) {
        self.inputDigest = inputDigest; self.contextDigest = contextDigest
    }

    init(receipt: AssistantLaneReceipt) {
        inputDigest = receipt.inputDigest.lowercased()
        let ticket = receipt.context
        let context = "archi-evolution-context/v1|generation:\(ticket.generation)|placement:\(ticket.placement)|source:\(ticket.source)|selection:\(ticket.selection)"
        contextDigest = SHA256.hash(data: Data(context.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private enum CodingKeys: String, CodingKey { case inputDigest, contextDigest }
    private struct InputKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    init(from decoder: Decoder) throws {
        let all = try decoder.container(keyedBy: InputKey.self)
        guard Set(all.allKeys.map(\.stringValue)) == ["inputDigest", "contextDigest"] else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported request binding."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        inputDigest = try values.decode(String.self, forKey: .inputDigest)
        contextDigest = try values.decode(String.self, forKey: .contextDigest)
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid request binding."))
        }
    }
}

/// A user's confirmation that one captured lesson helped with a completed
/// request. The reference cannot reconstruct or restore the lesson itself.
struct EvolutionLessonUse: Codable, Equatable, Sendable {
    let lessonID: String
    let lessonRevision: UInt64
    let snapshotDigest: String

    private init(lessonID: String, lessonRevision: UInt64, snapshotDigest: String) {
        self.lessonID = lessonID; self.lessonRevision = lessonRevision; self.snapshotDigest = snapshotDigest
    }

    static func make(snapshot: LessonSnapshot) -> Self? {
        guard snapshot.isValid else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let bytes = try? encoder.encode(snapshot) else { return nil }
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return Self(lessonID: snapshot.id, lessonRevision: snapshot.revision, snapshotDigest: digest)
    }

    func matches(snapshot: LessonSnapshot) -> Bool { Self.make(snapshot: snapshot) == self }

    private enum CodingKeys: String, CodingKey { case lessonID, lessonRevision, snapshotDigest }
    private struct InputKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let all = try decoder.container(keyedBy: InputKey.self)
        guard Set(all.allKeys.map(\.stringValue)) == ["lessonID", "lessonRevision", "snapshotDigest"] else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported lesson-use fields."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let id = try values.decode(String.self, forKey: .lessonID)
        let revision = try values.decode(UInt64.self, forKey: .lessonRevision)
        let digest = try values.decode(String.self, forKey: .snapshotDigest)
        guard UUID(uuidString: id) != nil, revision > 0, PracticeEvolutionReference.isDigest(digest) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid lesson-use reference."))
        }
        self.init(lessonID: id, lessonRevision: revision, snapshotDigest: digest)
    }
}

struct EvolutionProposal: Equatable, Identifiable, Sendable {
    let id: UUID
    let revision: UInt64
    let family: EvolutionFamily
    let preferences: EvolutionPreferences
    let evidence: [EvolutionUsefulReceipt]
    let basis: EvolutionProposalBasis
    let appearanceRecipe: CompanionAppearanceRecipe?

    init(id: UUID, revision: UInt64, family: EvolutionFamily, preferences: EvolutionPreferences,
         evidence: [EvolutionUsefulReceipt], basis: EvolutionProposalBasis,
         appearanceRecipe: CompanionAppearanceRecipe? = nil) {
        self.id = id; self.revision = revision; self.family = family; self.preferences = preferences
        self.evidence = evidence; self.basis = basis; self.appearanceRecipe = appearanceRecipe
    }
}

struct EvolutionHistoryEntry: Equatable, Identifiable, Sendable {
    enum Kind: String, Sendable { case kept, returned }
    let kind: Kind
    let family: EvolutionFamily?
    // History is a bounded cosmetic sequence, not a character identity ledger.
    let id: UUID
    let appearanceRecipe: CompanionAppearanceRecipe?

    init(kind: Kind, family: EvolutionFamily?, id: UUID, appearanceRecipe: CompanionAppearanceRecipe? = nil) {
        self.kind = kind; self.family = family; self.id = id; self.appearanceRecipe = appearanceRecipe
    }
}

@MainActor
final class EvolutionStore: ObservableObject {
    static let maximumUsefulReceipts = 32
    static let maximumHistoryEntries = 32
    static let maximumSaveBytes = 32 * 1024
    static let schema = "archi-companion-evolution/v7"
    static let maximumReviewedPractices = 8
    static let retentionExplanation = "Evolution stays in this session until you choose Save. A save contains confirmed choices, up to 32 useful-request references with optional confirmed lesson-use identifiers, one optional personal KIN body choice with its reviewed reference, up to 8 reviewed practice references, a Journey binding, and up to 32 kept/returned appearances with their individual recipes and reasons. It contains no lesson text, source text, or assistant conversation. Lesson references cannot restore lessons. Journey owns the identity and battle history. Load is explicit; Forget clears this session and attempts to delete this save."

    // A cosmetic starting form, not a character/passport identity. Only an
    // explicit validated Load may restore a different saved starting form.
    @Published private(set) var origin: CompanionForm
    let saveURL: URL?
    @Published private(set) var preferences = EvolutionPreferences()
    @Published private(set) var usefulReceipts: [EvolutionUsefulReceipt] = []
    @Published private(set) var practiceJourneyOriginDigest: String?
    @Published private(set) var reviewedPractices: [PracticeEvolutionReference] = []
    @Published private(set) var keptBasis: EvolutionProposalBasis?
    @Published private(set) var keptAppearanceRecipe: CompanionAppearanceRecipe?
    @Published private(set) var kinGrowthRecord: KinGrowthRecord?
    @Published private(set) var kinGrowthProposal: KinGrowthProposal?
    // An ephemeral observation from the existing host, never another identity writer.
    @Published private(set) var observedJourneyOriginDigest: String?
    @Published private(set) var proposal: EvolutionProposal?
    @Published private(set) var previewFamily: EvolutionFamily?
    @Published private(set) var activeFamily: EvolutionFamily?
    @Published private(set) var history: [EvolutionHistoryEntry] = []
    @Published private(set) var revision: UInt64 = 0
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var requiresReplacement = false
    /// Set by the profile owner when recovery cannot establish a coherent pair.
    /// This owner must not read, replace or forget a file while that hold remains.
    @Published var persistenceBlockedReason: String?
    /// The document owner must establish current withdrawals before old
    /// learning receipts can be loaded. Session preferences remain available.
    var historicalEvidenceUnavailableReason: String?
    @Published private(set) var status = "Your individual is already distinct. Appearance choices and shared history stay in this session until saved."
    private let deleteFile: (URL) throws -> Void
    // Exact bytes from the last successful explicit Load or Save. Construction
    // does not read disk, so a first Save expects an absent destination.
    private var saveBaseline: Data?
    private var excludedDocumentRequests = Set<UUID>()

    /// A clean initial session does not establish that an earlier save was
    /// loaded. Only successful explicit Load/Save creates a known baseline.
    var hasKnownSavedBaseline: Bool { saveBaseline != nil }
    var retentionState: EvolutionRetentionState {
        if hasUnsavedChanges { return .changed }
        return hasKnownSavedBaseline ? .saved : .notLoaded
    }

    var confirmedRole: EvolutionRole? { preferences.role }
    var confirmedHelpStyle: EvolutionHelpStyle? { preferences.helpStyle }
    var confirmedFamily: EvolutionFamily? { preferences.family }
    var activeAppearanceRecipe: CompanionAppearanceRecipe? {
        guard let recipe = keptAppearanceRecipe, recipe.family == activeFamily,
              recipe.originDigest == practiceJourneyOriginDigest,
              observedJourneyOriginDigest == nil || observedJourneyOriginDigest == recipe.originDigest else { return nil }
        return recipe
    }
    /// Natural variation belongs to the current Journey, independent of help
    /// preferences or activity counts. A validated saved binding is a fallback
    /// until the existing native host supplies the current Journey at launch.
    var naturalVariation: CompanionNaturalVariation? {
        (observedJourneyOriginDigest ?? practiceJourneyOriginDigest).flatMap {
            CompanionNaturalVariation.make(originDigest: $0)
        }
    }

    /// Called only with a validated projection from the existing native play host.
    /// A different observed Journey retires previews and hides another origin's
    /// individual details without rewriting the saved binding or kept history.
    func observeJourneyOrigin(_ originDigest: String) {
        guard PracticeEvolutionReference.isDigest(originDigest), observedJourneyOriginDigest != originDigest else { return }
        observedJourneyOriginDigest = originDigest
        proposal = nil; previewFamily = nil; kinGrowthProposal = nil
        if let bound = practiceJourneyOriginDigest, bound != originDigest {
            status = "A different individual is open. Its natural details follow this Journey; earlier personal history remains linked to its original Journey."
        }
        revision &+= 1
    }
    var canProposeForm: Bool { confirmedFamily != nil }

    @discardableResult
    func bindPracticeJourney(_ originDigest: String) -> Bool {
        guard PracticeEvolutionReference.isDigest(originDigest) else { status = "That Journey origin reference is invalid."; return false }
        guard practiceJourneyOriginDigest != originDigest else { return true }
        let rebinding = practiceJourneyOriginDigest != nil
        practiceJourneyOriginDigest = originDigest
        reviewedPractices = []
        changed(rebinding
            ? "Journey history reconnected. Earlier practice references stay with their original Journey; your kept appearance remains."
            : "Journey connected for personal history. Its natural details are already present.", preservingKeptAppearance: true)
        return true
    }

    /// The host integration supplies an exact reference from its current validated
    /// projection only after the user presses Review. This store cannot replay TS battles.
    @discardableResult
    func reviewPractice(_ reference: PracticeEvolutionReference, currentOriginDigest: String) -> Bool {
        guard reference.isValid, reference.originDigest == currentOriginDigest,
              practiceJourneyOriginDigest == currentOriginDigest else {
            status = "Review a valid outcome from the bound Journey. Bind a different Journey explicitly first."; return false
        }
        guard !reviewedPractices.contains(where: { $0.id == reference.id }) else {
            status = "This Journey outcome has already been reviewed."; return false
        }
        guard reviewedPractices.count < Self.maximumReviewedPractices else {
            status = "Eight practice references are retained. Withdraw an older reference before reviewing another."; return false
        }
        reviewedPractices.append(reference)
        changed("Practice added to your shared history. It does not unlock a body or measure personal growth.", preservingKeptAppearance: true)
        return true
    }

    func withdrawPractice(id: String) {
        guard reviewedPractices.contains(where: { $0.id == id }) else { return }
        reviewedPractices.removeAll { $0.id == id }
        changed("Practice reference removed from shared history. Your appearance stays the same.", preservingKeptAppearance: true)
    }

    init(origin: CompanionForm = .companion, saveURL: URL? = nil,
         persistenceBlockedReason: String? = nil,
         deleteFile: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) {
        self.origin = origin
        self.saveURL = saveURL
        self.persistenceBlockedReason = persistenceBlockedReason
        self.deleteFile = deleteFile
        // No implicit disk read or write; the existing appearance preference file
        // and all provider, identity, battle, and source state stay outside this store.
    }

    func confirmRole(_ role: EvolutionRole) {
        preferences.role = role; changed("Work role confirmed.")
    }
    func confirmHelpStyle(_ style: EvolutionHelpStyle) {
        preferences.helpStyle = style; changed("Help style confirmed.")
    }
    func confirmFamily(_ family: EvolutionFamily) {
        preferences.family = family; changed("Visual family confirmed.")
    }
    func revoke(_ category: EvolutionPreferenceCategory) {
        switch category {
        case .role: preferences.role = nil
        case .helpStyle: preferences.helpStyle = nil
        case .family: preferences.family = nil
        }
        changed("Preference withdrawn.")
    }

    /// The integration supplies the current completed lane and an optional
    /// shared-source digest. Source-free feedback is limited to local Qwen.
    /// Every new record binds the exact input and context, including documents.
    /// Both Compare lanes have one request ID and therefore count only once.
    @discardableResult
    func markUseful(receipt: AssistantLaneReceipt, sourceDigest: String?, confirmedLesson: LessonSnapshot? = nil) -> Bool {
        guard receipt.state == .complete, let requestID = UUID(uuidString: receipt.requestID),
              Self.validDigest(receipt.inputDigest),
              sourceDigest == nil || Self.validDigest(sourceDigest!),
              receipt.sourceDigest?.lowercased() == sourceDigest?.lowercased(),
              sourceDigest != nil || receipt.provider == .qwen else {
            status = "Only a completed local conversation or shared-document request with valid evidence can count."; return false
        }
        guard !excludedDocumentRequests.contains(requestID) else { return false }
        let binding = EvolutionRequestBinding(receipt: receipt)
        let lessonUse: EvolutionLessonUse?
        if let snapshot = confirmedLesson {
            guard receipt.provider == .qwen, receipt.localLessons.contains(snapshot),
                  receipt.usedLessonIDs.contains(snapshot.modelID),
                  let reference = EvolutionLessonUse.make(snapshot: snapshot) else {
                status = "Choose a valid lesson captured and used by this completed local answer."; return false
            }
            lessonUse = reference
        } else { lessonUse = nil }
        if let index = usefulReceipts.firstIndex(where: { $0.requestID == requestID }) {
            let existing = usefulReceipts[index]
            guard let lessonUse, existing.lessonUse == nil,
                  existing.sourceDigest == sourceDigest?.lowercased(), existing.requestBinding == binding else {
                status = "This request is already marked useful. Withdraw its lesson-use reference before choosing another."; return false
            }
            usefulReceipts[index] = EvolutionUsefulReceipt(requestID: requestID, sourceDigest: existing.sourceDigest, requestBinding: binding, lessonUse: lessonUse)
            changed("Lesson use confirmed for this useful request. Your appearance stays the same.")
            return true
        }
        guard usefulReceipts.count < Self.maximumUsefulReceipts else {
            status = "The 32-request limit is reached. Withdraw an older receipt before adding another."; return false
        }
        usefulReceipts.append(EvolutionUsefulReceipt(requestID: requestID, sourceDigest: sourceDigest?.lowercased(), requestBinding: binding, lessonUse: lessonUse))
        changed(lessonUse == nil ? "Completed request marked useful." : "Completed request marked useful with your confirmed lesson use. Your appearance stays the same.")
        return true
    }

    /// Durable document judgments can suppress older saved evidence without
    /// saving unrelated session choices or changing a previously kept body.
    func setDocumentFeedbackExclusions(_ ids: Set<UUID>) {
        excludedDocumentRequests = ids
        let priorCount = usefulReceipts.count
        usefulReceipts.removeAll { ids.contains($0.requestID) }
        if usefulReceipts.count != priorCount {
            changed("Document feedback withdrawn from this learning review. Save evolution to retain the withdrawal; your appearance stays the same.")
        }
    }

    @discardableResult
    func markDocumentWorkUseful(requestID: UUID, sourceDigest: String,
                                requestBinding: EvolutionRequestBinding,
                                confirmedLesson: EvolutionLessonUse? = nil) -> Bool {
        guard !excludedDocumentRequests.contains(requestID), Self.validDigest(sourceDigest), requestBinding.isValid else {
            status = "This document outcome is unavailable for learning review."; return false
        }
        if let index = usefulReceipts.firstIndex(where: { $0.requestID == requestID }) {
            let prior = usefulReceipts[index]
            guard prior.sourceDigest == sourceDigest, prior.requestBinding == requestBinding else { return false }
            if prior.lessonUse == confirmedLesson || confirmedLesson == nil { return true }
            guard prior.lessonUse == nil else { return false }
            usefulReceipts[index] = .init(requestID: requestID, sourceDigest: sourceDigest,
                requestBinding: requestBinding, lessonUse: confirmedLesson)
        } else {
            guard usefulReceipts.count < Self.maximumUsefulReceipts else {
                status = "The 32-request limit is reached. Withdraw an older experience first."; return false
            }
            usefulReceipts.append(.init(requestID: requestID, sourceDigest: sourceDigest,
                requestBinding: requestBinding, lessonUse: confirmedLesson))
        }
        changed("Document outcome added to learning review. Save evolution to keep it; your appearance stays the same.")
        return true
    }

    func withdrawLessonUse(requestID: UUID) {
        guard let index = usefulReceipts.firstIndex(where: { $0.requestID == requestID }),
              usefulReceipts[index].lessonUse != nil else { return }
        let existing = usefulReceipts[index]
        usefulReceipts[index] = EvolutionUsefulReceipt(requestID: existing.requestID, sourceDigest: existing.sourceDigest, requestBinding: existing.requestBinding)
        changed("Lesson-use reference withdrawn. The request remains marked useful; your appearance stays the same.")
    }

    func withdrawUseful(requestID: UUID) {
        guard usefulReceipts.contains(where: { $0.requestID == requestID }) else { return }
        usefulReceipts.removeAll { $0.requestID == requestID }
        changed("Useful-request evidence withdrawn.")
    }

    func preview(_ family: EvolutionFamily) {
        kinGrowthProposal = nil
        if proposal?.family != family { proposal = nil }
        previewFamily = family
        status = "Exploring \(family.title) in this workspace. Your desktop appearance has not changed."
    }
    func dismissPreview() { previewFamily = nil; proposal = nil; kinGrowthProposal = nil }

    /// CompanionStore supplies the active individual's origin and independently
    /// checks the cited lesson is still kept before proposing and keeping.
    @discardableResult
    func proposeKinGrowth(originDigest: String, receipt: EvolutionUsefulReceipt) -> KinGrowthProposal? {
        kinGrowthProposal = nil
        guard let origin = currentKinOrigin(originDigest), kinGrowthRecord == nil,
              KinGrowthRecord.isValidEvidence(receipt), usefulReceipts.contains(receipt) else {
            status = "Review a current useful request with a confirmed lesson before previewing First Light. A kept body choice remains available through its own return controls."
            return nil
        }
        let candidate = KinGrowthProposal(id: UUID(), originDigest: origin, revision: revision, receipt: receipt)
        proposal = nil; previewFamily = nil
        kinGrowthProposal = candidate
        status = "Previewing KIN’s First Light here. His chosen body is unchanged until Keep; his Seed cursor stays available."
        return candidate
    }

    @discardableResult
    func keepKinGrowth(_ candidate: KinGrowthProposal) -> Bool {
        guard kinGrowthProposal == candidate, candidate.revision == revision, kinGrowthRecord == nil,
              currentKinOrigin(candidate.originDigest) != nil,
              KinGrowthRecord.isValidEvidence(candidate.receipt), usefulReceipts.contains(candidate.receipt) else {
            status = "That growth preview is no longer current. Review the useful moment and preview again."
            return false
        }
        kinGrowthRecord = KinGrowthRecord(originDigest: candidate.originDigest, active: true, receipt: candidate.receipt)
        changed("First Light kept as KIN’s body in this session. His Seed cursor stays available. Save evolution explicitly to restore this body choice later.")
        return true
    }

    func returnKinToSeed(originDigest: String) {
        guard let origin = currentKinOrigin(originDigest), let record = kinGrowthRecord,
              record.originDigest == origin, record.active else { return }
        kinGrowthRecord = record.settingActive(false)
        changed("KIN’s body returned to Core Seed. His Seed cursor stays available, and the kept First Light choice remains. Save to retain this choice.")
    }

    @discardableResult
    func resumeKinGrowth(originDigest: String) -> Bool {
        guard let origin = currentKinOrigin(originDigest), let record = kinGrowthRecord,
              record.originDigest == origin, !record.active else {
            status = "There is no returned First Light choice for this individual."
            return false
        }
        kinGrowthRecord = record.settingActive(true)
        changed("KIN’s kept First Light body restored for this session. His Seed cursor stays available. This reuses the earlier choice, without claiming new lesson evidence. Save to retain it.")
        return true
    }

    func dismissKinGrowthPreview() { kinGrowthProposal = nil }

    private func currentKinOrigin(_ supplied: String) -> String? {
        let origin = supplied.lowercased()
        guard PracticeEvolutionReference.isDigest(origin),
              observedJourneyOriginDigest == nil || observedJourneyOriginDigest == origin else { return nil }
        return origin
    }

    @discardableResult
    func proposeEvolution() -> EvolutionProposal? {
        kinGrowthProposal = nil
        guard let family = confirmedFamily else {
            proposal = nil; status = "Choose a form to preview. No tasks or battles are required."; return nil
        }
        let candidate = EvolutionProposal(id: UUID(), revision: revision, family: family,
            preferences: preferences, evidence: usefulReceipts,
            basis: EvolutionProposalBasis(kind: .appearanceChoice, practice: nil))
        proposal = candidate
        previewFamily = family
        status = "Previewing \(family.title). This is an appearance choice; your individual and experiences continue."
        return candidate
    }

    @discardableResult
    func keepEvolution() -> Bool {
        guard let candidate = proposal else { status = "Create a fresh evolution proposal first."; return false }
        return keepEvolution(candidate)
    }

    @discardableResult
    func keepEvolution(_ candidate: EvolutionProposal) -> Bool {
        guard proposal == candidate, candidate.revision == revision,
              candidate.family == confirmedFamily, candidate.family == previewFamily, candidate.preferences == preferences,
              candidate.evidence == usefulReceipts, candidate.basis == EvolutionProposalBasis(kind: .appearanceChoice, practice: nil),
              candidate.appearanceRecipe == nil else {
            status = "That proposal is no longer current. Review your choices and propose again."; return false
        }
        activeFamily = candidate.family
        keptBasis = candidate.basis
        keptAppearanceRecipe = candidate.appearanceRecipe
        appendHistory(.kept, family: candidate.family, recipe: candidate.appearanceRecipe)
        changed("\(candidate.family.title) kept for this session. Save explicitly to reopen it later.")
        previewFamily = nil
        return true
    }

    func returnToStarter() {
        if activeFamily != nil { appendHistory(.returned, family: nil) }
        activeFamily = nil
        keptBasis = nil
        keptAppearanceRecipe = nil
        previewFamily = nil
        changed("Returned to your \(origin.rawValue) starter. Your confirmed choices remain.")
    }

    /// All file operations are synchronous and bounded on the store actor. An
    /// older pending Save or Load cannot finish after Forget and restore state.
    @discardableResult
    func forget() -> Bool {
        guard persistenceAllowed else { return false }
        // The existing explicit Forget behavior still clears unreadable saves.
        // A newer valid save belongs to another writer: neither this session nor
        // that file may be cleared by a stale owner. Load it explicitly first.
        let observedBytes = saveURL.flatMap { try? readBounded($0) }
        let observedValid = observedBytes.flatMap { (try? decode($0)) == nil ? nil : $0 }
        if let observedValid, observedValid != saveBaseline {
            requiresReplacement = false
            status = "Evolution was not forgotten. \(boundedError(EvolutionFileError.conflict))"
            return false
        }
        guard let url = saveURL else {
            clearForgottenSession()
            hasUnsavedChanges = false; requiresReplacement = false
            status = "Evolution choices and evidence cleared from this session. No save location is configured."
            return true
        }
        do {
            if let type = try entryType(url) {
                guard type == .typeRegular || type == .typeSymbolicLink else { throw EvolutionFileError.unsupportedItem }
                let latest = try? readBounded(url)
                let latestValid = latest.flatMap { (try? decode($0)) == nil ? nil : $0 }
                // Recheck immediately before deletion, still before publishing
                // cleared session state. This is not an interprocess lock.
                guard (observedValid == nil || latest == observedValid),
                      latestValid == nil || latestValid == saveBaseline else { throw EvolutionFileError.conflict }
                try deleteFile(url)
            }
            clearForgottenSession()
            hasUnsavedChanges = false; requiresReplacement = false
            saveBaseline = nil
            status = "Evolution choices and evidence cleared; no saved evolution remains at this location."
            return true
        } catch {
            if case EvolutionFileError.conflict = error {
                requiresReplacement = false
                status = "Evolution was not forgotten. \(boundedError(error))"
                return false
            }
            clearForgottenSession()
            requiresReplacement = true
            status = "This session is cleared, but the saved evolution could not be deleted. It may still be loaded. \(boundedError(error))"
            return false
        }
    }

    private func clearForgottenSession() {
        preferences = EvolutionPreferences(); usefulReceipts = []; proposal = nil
        kinGrowthRecord = nil; kinGrowthProposal = nil
        previewFamily = nil; activeFamily = nil; history = []
        practiceJourneyOriginDigest = nil; reviewedPractices = []; keptBasis = nil; keptAppearanceRecipe = nil
        revision &+= 1; hasUnsavedChanges = true
    }

    @discardableResult
    func save(replacingInvalidFile: Bool = false) -> Bool {
        guard persistenceAllowed else { return false }
        guard let url = saveURL else { status = "No evolution save location is configured."; return false }
        do {
            let existingType = try entryType(url)
            guard existingType == nil || existingType == .typeRegular || existingType == .typeSymbolicLink else {
                throw EvolutionFileError.unsupportedItem
            }
            let existingMetadata = try saveTargetMetadata(url)
            var existingBytes: Data?
            var replacingUnreadable = false
            if existingType != nil {
                do {
                    let bytes = try readBounded(url)
                    existingBytes = bytes
                    _ = try decode(bytes)
                }
                catch {
                    guard replacingInvalidFile else {
                        requiresReplacement = true
                        status = "The existing save could not be validated and was preserved. Choose Replace saved evolution explicitly to replace it. \(boundedError(error))"
                        return false
                    }
                    replacingUnreadable = true
                }
            }
            if !replacingUnreadable {
                // A stale invalid-file confirmation must not overwrite a file
                // another writer has since repaired into a valid save.
                requiresReplacement = false
                guard existingBytes == saveBaseline else { throw EvolutionFileError.conflict }
            }
            let bytes = try encodeCurrentState()
            guard bytes.count <= Self.maximumSaveBytes else { throw EvolutionFileError.invalid }
            try writeAtomically(bytes, to: url) {
                if replacingUnreadable {
                    // Explicit repair replaces the invalid entry itself. Small
                    // malformed files are compared exactly; unreadable/oversized
                    // entries and symlinks are checked by bounded metadata.
                    guard try self.saveTargetMetadata(url) == existingMetadata else { throw EvolutionFileError.conflict }
                    if let existingBytes {
                        guard try self.readBounded(url) == existingBytes else { throw EvolutionFileError.conflict }
                    }
                } else {
                    let current = try self.entryType(url) == nil ? nil : self.readBounded(url)
                    guard current == self.saveBaseline else { throw EvolutionFileError.conflict }
                }
            }
            saveBaseline = bytes
            hasUnsavedChanges = false; requiresReplacement = false
            status = "Evolution choices, evidence identifiers, and kept appearance saved on this Mac."
            return true
        } catch {
            status = "Evolution was not saved. \(boundedError(error))"
            return false
        }
    }

    /// Match the preference owner's two-read write pattern. The final compare
    /// follows the temporary file's completed write and immediately precedes
    /// atomic rename. This detects stale writers, not simultaneous transactions.
    private func writeAtomically(_ bytes: Data, to url: URL, validate: () throws -> Void) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let descriptor = temporary.path.withCString { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600) }
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var isOpen = true
        defer {
            if isOpen { Darwin.close(descriptor) }
            try? FileManager.default.removeItem(at: temporary)
        }
        try bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                offset += written
            }
        }
        guard fsync(descriptor) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard Darwin.close(descriptor) == 0 else {
            isOpen = false
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        isOpen = false
        try validate()
        let result = temporary.path.withCString { source in url.path.withCString { target in Darwin.rename(source, target) } }
        guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    private func saveTargetMetadata(_ url: URL) throws -> NSDictionary? {
        guard try entryType(url) != nil else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let keys: Set<FileAttributeKey> = [.type, .size, .modificationDate, .creationDate, .systemNumber, .systemFileNumber]
        var metadata: [String: Any] = [:]
        for (key, value) in attributes where keys.contains(key) { metadata[key.rawValue] = value }
        if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            metadata["linkDestination"] = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
        }
        return NSDictionary(dictionary: metadata)
    }

    @discardableResult
    func load() -> Bool {
        guard persistenceAllowed else { return false }
        if let historicalEvidenceUnavailableReason {
            status = historicalEvidenceUnavailableReason
            return false
        }
        kinGrowthProposal = nil
        guard let url = saveURL else { status = "No evolution save location is configured."; return false }
        do {
            guard try entryType(url) != nil else {
                status = "No saved evolution was found. This session is unchanged."; return false
            }
            let bytes = try readBounded(url)
            let loaded = try decode(bytes)
            origin = loaded.origin
            preferences = loaded.preferences; usefulReceipts = loaded.receipts
            activeFamily = loaded.active; history = loaded.history
            practiceJourneyOriginDigest = loaded.practiceOrigin
            reviewedPractices = loaded.practices; keptBasis = loaded.basis
            keptAppearanceRecipe = loaded.recipe
            kinGrowthRecord = loaded.kinGrowth
            saveBaseline = bytes
            proposal = nil; previewFamily = nil; kinGrowthProposal = nil; revision &+= 1
            hasUnsavedChanges = false; requiresReplacement = false
            status = "Saved evolution choices loaded. Their receipt identifiers are retained records, not fresh assistant observations."
            setDocumentFeedbackExclusions(excludedDocumentRequests)
            return true
        } catch {
            requiresReplacement = true
            status = "The saved evolution could not be loaded. This session and the file are unchanged. \(boundedError(error))"
            return false
        }
    }

    /// Called only after the existing profile owner validates/restores its pair.
    /// An explicitly absent Evolution member clears this session without a file
    /// deletion or another save; a present member uses the ordinary Load boundary.
    @discardableResult
    func loadRestoredProfile(origin restoredOrigin: CompanionForm = .companion) -> Bool {
        guard persistenceAllowed else { return false }
        guard let url = saveURL else { status = "No evolution save location is configured."; return false }
        do {
            if try entryType(url) != nil { return load() }
            clearForgottenSession()
            origin = restoredOrigin
            observedJourneyOriginDigest = nil
            saveBaseline = nil
            hasUnsavedChanges = false; requiresReplacement = false
            status = "The restored profile has no saved evolution. Its development session is clear."
            return true
        } catch {
            status = "Restored evolution could not be read. This session is unchanged. \(boundedError(error))"
            return false
        }
    }

    private var persistenceAllowed: Bool {
        guard let reason = persistenceBlockedReason else { return true }
        status = "Evolution storage is paused: \(reason)"
        return false
    }

    private func changed(_ message: String, preservingKeptAppearance: Bool = false) {
        proposal = nil; kinGrowthProposal = nil; hasUnsavedChanges = true
        // Appearance is a user choice. Editing help preferences or withdrawing
        // activity feedback must never demote or redraw the kept individual.
        status = message
        // Publish the revision after the complete transition so native snapshots,
        // placement and Reactor references see one consistent chosen appearance.
        revision &+= 1
    }

    private func appendHistory(_ kind: EvolutionHistoryEntry.Kind, family: EvolutionFamily?, recipe: CompanionAppearanceRecipe? = nil) {
        history.append(EvolutionHistoryEntry(kind: kind, family: family, id: UUID(), appearanceRecipe: recipe))
        if history.count > Self.maximumHistoryEntries { history.removeFirst(history.count - Self.maximumHistoryEntries) }
    }

    private static func validDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
    }
    private func boundedError(_ error: Error) -> String { String(error.localizedDescription.prefix(220)) }
    private func entryType(_ url: URL) throws -> FileAttributeType? {
        // attributesOfItem examines the last path entry, including a dangling
        // symbolic link. fileExists follows it and can incorrectly report absence.
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let type = attributes[.type] as? FileAttributeType else { throw EvolutionFileError.unsupportedItem }
            return type
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        }
    }
    private func readBounded(_ url: URL) throws -> Data {
        // Validate the opened entry, not cached URL resource values. Explicit
        // repair can replace a symlink with a regular file at this same URL.
        // Nonblocking open also keeps a swapped special file from blocking here.
        let descriptor = url.path.withCString { Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) }
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard info.st_mode & S_IFMT == S_IFREG else { throw EvolutionFileError.invalid }
        guard info.st_size > 0, info.st_size <= Self.maximumSaveBytes else { throw EvolutionFileError.oversized }
        let data = try file.read(upToCount: Self.maximumSaveBytes + 1) ?? Data()
        guard !data.isEmpty, data.count <= Self.maximumSaveBytes else { throw EvolutionFileError.oversized }
        return data
    }

    private struct SavedState {
        let origin: CompanionForm
        let preferences: EvolutionPreferences
        let receipts: [EvolutionUsefulReceipt]
        let active: EvolutionFamily?
        let history: [EvolutionHistoryEntry]
        let practiceOrigin: String?
        let practices: [PracticeEvolutionReference]
        let basis: EvolutionProposalBasis?
        let recipe: CompanionAppearanceRecipe?
        let kinGrowth: KinGrowthRecord?
    }

    private func encodeCurrentState() throws -> Data {
        let object: [String: Any] = [
            "schema": Self.schema, "origin": origin.rawValue,
            "role": preferences.role?.rawValue as Any? ?? NSNull(),
            "helpStyle": preferences.helpStyle?.rawValue as Any? ?? NSNull(),
            "family": preferences.family?.rawValue as Any? ?? NSNull(),
            "activeFamily": activeFamily?.rawValue as Any? ?? NSNull(),
            "usefulReceipts": try JSONSerialization.jsonObject(with: JSONEncoder().encode(usefulReceipts)),
            "history": try history.map { ["kind": $0.kind.rawValue, "family": $0.family?.rawValue as Any? ?? NSNull(), "id": $0.id.uuidString,
                "appearanceRecipe": try encodedRecipe($0.appearanceRecipe)] as [String: Any] },
            "practiceJourneyOriginDigest": practiceJourneyOriginDigest as Any? ?? NSNull(),
            "reviewedPractices": try JSONSerialization.jsonObject(with: JSONEncoder().encode(reviewedPractices)),
            "keptBasis": try keptBasis.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull(),
            "keptAppearanceRecipe": try encodedRecipe(keptAppearanceRecipe),
            "kinGrowthRecord": try kinGrowthRecord.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull()
        ]
        // Compact formatting keeps all bounded historical records plus their
        // optional lesson references representable within the existing 32 KiB cap.
        return try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
    }

    private func decode(_ data: Data) throws -> SavedState {
        guard data.count <= Self.maximumSaveBytes else { throw EvolutionFileError.oversized }
        var scanner = EvolutionJSONKeyScanner(bytes: Array(data)); try scanner.validate()
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw EvolutionFileError.invalid }
        let legacy = object["schema"] as? String == "archi-companion-evolution/v1"
        let prior = object["schema"] as? String == "archi-companion-evolution/v2"
        let current = object["schema"] as? String == Self.schema
        let hasKinGrowth = current || object["schema"] as? String == "archi-companion-evolution/v6"
        let hasLessonUse = hasKinGrowth || object["schema"] as? String == "archi-companion-evolution/v5"
        let modernAppearance = hasLessonUse || object["schema"] as? String == "archi-companion-evolution/v4"
        let hasRecipes = modernAppearance || object["schema"] as? String == "archi-companion-evolution/v3"
        let baseKeys: Set<String> = ["schema", "origin", "role", "helpStyle", "family", "activeFamily", "usefulReceipts", "history"]
        let v2Keys = baseKeys.union(["practiceJourneyOriginDigest", "reviewedPractices", "keptBasis"])
        let expectedKeys = legacy ? baseKeys : hasKinGrowth ? v2Keys.union(["keptAppearanceRecipe", "kinGrowthRecord"])
            : hasRecipes ? v2Keys.union(["keptAppearanceRecipe"]) : v2Keys
        guard Set(object.keys) == expectedKeys,
              legacy || prior || hasRecipes,
              let rawOrigin = object["origin"] as? String, let savedOrigin = CompanionForm(rawValue: rawOrigin),
              let rawReceipts = object["usefulReceipts"] as? [[String: Any]], rawReceipts.count <= Self.maximumUsefulReceipts,
              let rawHistory = object["history"] as? [[String: Any]], rawHistory.count <= Self.maximumHistoryEntries else { throw EvolutionFileError.invalid }
        let preferences = EvolutionPreferences(role: try optionalEnum(object["role"], EvolutionRole.self),
            helpStyle: try optionalEnum(object["helpStyle"], EvolutionHelpStyle.self),
            family: try optionalEnum(object["family"], EvolutionFamily.self))
        let active = try optionalEnum(object["activeFamily"], EvolutionFamily.self)
        var ids = Set<UUID>()
        let receipts = try rawReceipts.map { item -> EvolutionUsefulReceipt in
            var fields = item
            let keys = Set(item.keys), required: Set<String> = ["requestID", "sourceDigest"]
            if !current {
                guard keys == required || (hasLessonUse && keys == required.union(["lessonUse"])) else {
                    throw EvolutionFileError.invalid
                }
                // v1–v6 admitted case-insensitive source fingerprints and
                // normalized them. Preserve that compatibility without changing
                // the stricter new binding or historical nested growth contracts.
                guard let digest = item["sourceDigest"] as? String, Self.validDigest(digest) else {
                    throw EvolutionFileError.invalid
                }
                fields["sourceDigest"] = digest.lowercased()
            }
            let receipt = try JSONDecoder().decode(EvolutionUsefulReceipt.self,
                from: JSONSerialization.data(withJSONObject: fields))
            guard ids.insert(receipt.requestID).inserted else { throw EvolutionFileError.invalid }
            return receipt
        }
        var historyIDs = Set<UUID>()
        let history = try rawHistory.map { item -> EvolutionHistoryEntry in
            guard Set(item.keys) == (hasRecipes ? ["kind", "family", "id", "appearanceRecipe"] : ["kind", "family", "id"]), let rawKind = item["kind"] as? String,
                  let kind = EvolutionHistoryEntry.Kind(rawValue: rawKind),
                  let rawID = item["id"] as? String, let id = UUID(uuidString: rawID), historyIDs.insert(id).inserted else { throw EvolutionFileError.invalid }
            let family = try optionalEnum(item["family"], EvolutionFamily.self)
            let recipe = hasRecipes ? try decodedRecipe(item["appearanceRecipe"]) : nil
            guard (kind == .kept && family != nil) || (kind == .returned && family == nil) else { throw EvolutionFileError.invalid }
            guard recipe == nil || (kind == .kept && recipe?.family == family) else { throw EvolutionFileError.invalid }
            return EvolutionHistoryEntry(kind: kind, family: family, id: id, appearanceRecipe: recipe)
        }
        let practiceOrigin: String?
        let practices: [PracticeEvolutionReference]
        let basis: EvolutionProposalBasis?
        if legacy {
            practiceOrigin = nil; practices = []
            basis = active == nil ? nil : EvolutionProposalBasis(kind: .usefulWork, practice: nil)
        } else {
            if object["practiceJourneyOriginDigest"] is NSNull { practiceOrigin = nil }
            else if let raw = object["practiceJourneyOriginDigest"] as? String, PracticeEvolutionReference.isDigest(raw) { practiceOrigin = raw }
            else { throw EvolutionFileError.invalid }
            guard let rows = object["reviewedPractices"] as? [[String: Any]], rows.count <= Self.maximumReviewedPractices,
                  rows.allSatisfy({ Set($0.keys) == PracticeEvolutionReference.keys }) else { throw EvolutionFileError.invalid }
            practices = try JSONDecoder().decode([PracticeEvolutionReference].self, from: JSONSerialization.data(withJSONObject: rows))
            guard practices.allSatisfy({ $0.isValid && $0.originDigest == practiceOrigin }),
                  Set(practices.map(\.id)).count == practices.count else { throw EvolutionFileError.invalid }
            if object["keptBasis"] is NSNull { basis = nil }
            else {
                guard let raw = object["keptBasis"] as? [String: Any],
                      Set(raw.keys) == ["kind", "practice"] || Set(raw.keys) == ["kind"] else { throw EvolutionFileError.invalid }
                if let practice = raw["practice"], !(practice is NSNull) {
                    guard let value = practice as? [String: Any], Set(value.keys) == PracticeEvolutionReference.keys else { throw EvolutionFileError.invalid }
                }
                basis = try JSONDecoder().decode(EvolutionProposalBasis.self, from: JSONSerialization.data(withJSONObject: raw))
                guard basis?.isValid == true, modernAppearance || basis?.kind != .appearanceChoice else { throw EvolutionFileError.invalid }
            }
        }
        let recipe = hasRecipes ? try decodedRecipe(object["keptAppearanceRecipe"]) : nil
        if let active {
            guard (modernAppearance || (preferences.confirmedCount == 3 && active == preferences.family)),
                  history.last?.kind == .kept, history.last?.family == active, basis?.isValid == true else { throw EvolutionFileError.invalid }
            guard history.last?.appearanceRecipe == recipe else { throw EvolutionFileError.invalid }
            if let recipe {
                guard basis?.kind != .appearanceChoice, recipe.family == active, recipe.basisKind == basis?.kind,
                      basis?.practice == nil || basis?.practice?.originDigest == recipe.originDigest else { throw EvolutionFileError.invalid }
            }
            // A v2 kept basis records the reviewed choice at Keep time. Later
            // evidence withdrawal can retire new-proposal eligibility without
            // invalidating that historical choice or making its save unreadable.
            if legacy {
                guard preferences.confirmedCount == 3, receipts.count >= 2, active == preferences.family else { throw EvolutionFileError.invalid }
            }
        } else if history.last?.kind == .kept { throw EvolutionFileError.invalid }
        else if basis != nil || recipe != nil { throw EvolutionFileError.invalid }
        let kinGrowth: KinGrowthRecord?
        if hasKinGrowth, !(object["kinGrowthRecord"] is NSNull) {
            guard let fields = object["kinGrowthRecord"] as? [String: Any] else { throw EvolutionFileError.invalid }
            kinGrowth = try JSONDecoder().decode(KinGrowthRecord.self,
                from: JSONSerialization.data(withJSONObject: fields))
            guard current || kinGrowth?.version == 1 else { throw EvolutionFileError.invalid }
        } else { kinGrowth = nil }
        return SavedState(origin: savedOrigin, preferences: preferences, receipts: receipts, active: active, history: history,
            practiceOrigin: practiceOrigin, practices: practices, basis: basis, recipe: recipe, kinGrowth: kinGrowth)
    }

    private func encodedRecipe(_ recipe: CompanionAppearanceRecipe?) throws -> Any {
        try recipe.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull()
    }

    private func decodedRecipe(_ value: Any?) throws -> CompanionAppearanceRecipe? {
        if value is NSNull { return nil }
        guard let object = value as? [String: Any] else { throw EvolutionFileError.invalid }
        return try JSONDecoder().decode(CompanionAppearanceRecipe.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func optionalEnum<T: RawRepresentable>(_ value: Any?, _ type: T.Type) throws -> T? where T.RawValue == String {
        if value is NSNull { return nil }
        guard let raw = value as? String, let result = T(rawValue: raw) else { throw EvolutionFileError.invalid }
        return result
    }
}

private enum EvolutionFileError: LocalizedError {
    case invalid, oversized, unsupportedItem, conflict
    var errorDescription: String? {
        switch self {
        case .invalid: "The save has an unsupported version, invalid fields, or an unknown starter form."
        case .oversized: "The save is empty or exceeds the 32 KB limit."
        case .unsupportedItem: "The save location is a directory or special file and was preserved."
        case .conflict: "The saved evolution changed outside this session and was preserved. Load and review it before saving or forgetting. If the file was removed, Forget explicitly acknowledges its absence and starts anew."
        }
    }
}

/// Foundation's object decoder collapses duplicate keys. Reject them, including
/// escaped equivalents, before validating the closed saved-state contract.
private struct EvolutionJSONKeyScanner {
    let bytes: [UInt8]
    private var index = 0
    init(bytes: [UInt8]) { self.bytes = bytes }
    mutating func validate() throws {
        try value(depth: 0); whitespace()
        guard index == bytes.count else { throw EvolutionFileError.invalid }
    }
    private mutating func value(depth: Int) throws {
        whitespace()
        guard depth <= 16, index < bytes.count else { throw EvolutionFileError.invalid }
        switch bytes[index] {
        case 123:
            index += 1; whitespace()
            if take(125) { return }
            var keys = Set<String>()
            while true {
                whitespace(); let key = try string()
                guard keys.insert(key).inserted else { throw EvolutionFileError.invalid }
                whitespace(); guard take(58) else { throw EvolutionFileError.invalid }
                try value(depth: depth + 1); whitespace()
                if take(125) { return }
                guard take(44) else { throw EvolutionFileError.invalid }
            }
        case 91:
            index += 1; whitespace()
            if take(93) { return }
            while true {
                try value(depth: depth + 1); whitespace()
                if take(93) { return }
                guard take(44) else { throw EvolutionFileError.invalid }
            }
        case 34: _ = try string()
        default:
            let start = index
            while index < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
            guard index > start else { throw EvolutionFileError.invalid }
        }
    }
    private mutating func string() throws -> String {
        let start = index
        guard take(34) else { throw EvolutionFileError.invalid }
        while index < bytes.count {
            let byte = bytes[index]; index += 1
            if byte == 34 { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) }
            if byte == 92 {
                guard index < bytes.count else { throw EvolutionFileError.invalid }; index += 1
            } else if byte < 32 { throw EvolutionFileError.invalid }
        }
        throw EvolutionFileError.invalid
    }
    private mutating func whitespace() {
        while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }
    private mutating func take(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1; return true
    }
}
