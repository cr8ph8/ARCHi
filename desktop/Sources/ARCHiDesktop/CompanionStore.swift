import AppKit
import Combine
import UniformTypeIdentifiers
import CryptoKit

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case assistant = "Assistant"
    case nodeLab = "Node Lab"
    case steward = "Token Steward"
    case capabilities = "ARC Capabilities"
    case unity = "Unity Area"
    case play = "Habitat & Arena"
    case appearance = "Appearance"
    case marketplace = "Marketplace"
    case evolution = "Evolution"
    case rhythm = "Personal rhythm"
    case memory = "What I remember"
    case context = "Work together"
    case connections = "Connections"
    case accessibility = "Accessibility"
    case advanced = "Advanced"
    var id: String { rawValue }
}

enum CompanionForm: String, CaseIterable, Identifiable, Codable {
    case companion = "Companion", light = "Guide light", particle = "Particle light"
    case corePearl = "Core pearl", orbitField = "Orbit field", lightForm = "Light Form"
    case ribbon = "Ribbon", ink = "Ink", pixel = "Pixel"
    case constellation = "Constellation", sprout = "Jade Sprout"
    case ribbonSpirit = "Ribbon Spirit", geode = "Crystal Core"
    case kin = "KIN · First Light", kinSpark = "KIN · Spark", kinSimple = "Simple KIN"
    case kinSeed = "KIN · Core Seed"
    case particleSeed = "Particle Seed"
    case hamptonSeed = "Hampton · Liminal Seed"
    case velaSeed = "Vela Seed", velaLantern = "Vela Lantern"
    var id: String { rawValue }

    /// Related local drawings of the same companion, not additional individuals.
    var isOpticalLight: Bool { self == .corePearl || self == .orbitField || self == .lightForm }
    static var opticalLightChoices: [Self] { [.corePearl, .orbitField, .lightForm] }
}

struct CompanionPreferences: Codable, Equatable {
    var workspaceAppearance: WorkspaceAppearance = .system
    var form: CompanionForm = .companion
    var seedAppearance: CompanionSeedAppearance = .kinParticles
    var seedColor: CompanionSeedColor = .original
    var visualTreatment: CompanionVisualTreatment = .original
    /// Explicit visual pose; nil retains the saved historical growth behavior.
    var companionPose: CompanionPresentationPose? = nil
    var liminalPointProgress: Double = 107.0 / 119.0
    var equipment: CompanionEquipment = .empty
    var tone = "Calm"
    var replyLength = 0.35
    var size = 1.0
    var adaptive = true
    var reduceMotion = false
    var quiet = false
    var musicalCues = false
    var musicalVolume = 0.35

    var isValid: Bool {
        liminalPointProgress.isFinite && (0...1).contains(liminalPointProgress)
        && equipment.isValid && size.isFinite && (0.65...1.6).contains(size)
        && replyLength.isFinite && (0...1).contains(replyLength)
        && musicalVolume.isFinite && (0...1).contains(musicalVolume)
        && ["Calm", "Direct", "Playful", "Warm"].contains(tone)
    }
}

extension CompanionPreferences {
    // Historical fields retain their decoding requirements. Older saves can
    // omit visual treatment and equipment without selecting a wearable.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        workspaceAppearance = try values.decodeIfPresent(WorkspaceAppearance.self, forKey: .workspaceAppearance) ?? .system
        form = try values.decode(CompanionForm.self, forKey: .form)
        seedAppearance = try values.decodeIfPresent(CompanionSeedAppearance.self, forKey: .seedAppearance) ?? .kinParticles
        seedColor = try values.decodeIfPresent(CompanionSeedColor.self, forKey: .seedColor) ?? .original
        visualTreatment = try values.decodeIfPresent(CompanionVisualTreatment.self, forKey: .visualTreatment) ?? .original
        companionPose = try values.decodeIfPresent(CompanionPresentationPose.self, forKey: .companionPose)
        liminalPointProgress = try values.decodeIfPresent(Double.self, forKey: .liminalPointProgress) ?? 107.0 / 119.0
        equipment = try values.decodeIfPresent(CompanionEquipment.self, forKey: .equipment) ?? .empty
        tone = try values.decode(String.self, forKey: .tone)
        replyLength = try values.decode(Double.self, forKey: .replyLength)
        size = try values.decode(Double.self, forKey: .size)
        adaptive = try values.decode(Bool.self, forKey: .adaptive)
        reduceMotion = try values.decode(Bool.self, forKey: .reduceMotion)
        quiet = try values.decode(Bool.self, forKey: .quiet)
        musicalCues = try values.decodeIfPresent(Bool.self, forKey: .musicalCues) ?? false
        musicalVolume = try values.decodeIfPresent(Double.self, forKey: .musicalVolume) ?? 0.35
    }
}

struct ContextTicket: Equatable, Sendable {
    let generation: UInt64
    let placement: UInt64
    let source: UInt64
    let selection: UInt64
}

@MainActor
final class CompanionStore: ObservableObject {
    let liminalStructureSessionID = UUID().uuidString
    let tokenSteward: TokenStewardStore
    let arcCapabilities: ARCCapabilitiesStore
    let arc3: ARC3SessionStore
    @Published private(set) var documentWork: DocumentWorkJournal
    @Published private(set) var documentProcedures: DocumentProcedureLibrary
    @Published private(set) var readingSources: ReadingSourceLibrary
    @Published var selectedReadingSourceIDs: Set<String> = []
    @Published var knowledgePageDraft: KnowledgePageDraft?
    @Published var knowledgeLinkDraft: KnowledgeLinkDraft?
    var hasOpenKnowledgeDraft: Bool { knowledgePageDraft != nil || knowledgeLinkDraft != nil }
    @Published var selectedKnowledgePageID: String?
    @Published var selectedKnowledgePages: [KnowledgePageBinding] = []
    @Published var knowledgePageMessage: String?
    @Published private(set) var knowledgeMethodDraftPage: KnowledgePageBinding?
    @Published private(set) var knowledgeMethodDraftMessage: String?
    @Published private(set) var knowledgeMethodDraft: KnowledgeMethodDraft?
    private var knowledgeMethodDraftRequestID: String?
    @Published private(set) var knowledgeConceptDraft: KnowledgeConceptDraft?
    @Published private(set) var knowledgeConceptDraftMessage: String?
    private var knowledgeConceptDraftRequestID: String?
    @Published private(set) var preparedDocumentProcedure: DocumentProcedureUse?
    private var preparedProcedureSelection: DocumentSelection?
    private var preparedProcedureSourceDigest: String?
    private var documentProcedureRequests: [String: DocumentProcedureUse] = [:]
    @Published private(set) var documentWorkMessage: String?
    @Published var documentReadingPreview: DocumentReadingPreview?
    @Published var documentReadingMessage: String?
    @Published private(set) var showsARC3Reply = false
    /// Transient navigation only. Everyday reasoning never starts a solver or world.
    @Published var showsReasoningTools = false
    @Published private(set) var arenaActivity: ArenaActivity = .practice
    @Published private(set) var reasoningToolsShowWorlds = false
    @Published private(set) var lastARC3Summary: ARC3SessionSummary?
    @Published private(set) var stewardMessage: String?
    /// Navigation focus is transient and never enters a profile or usage journal.
    @Published private(set) var selectedStewardTaskID: String?
    @Published private(set) var selectedGraphNodeID: String?
    /// Transient cross-surface focus, never persisted as identity or learning.
    @Published private(set) var memoryParticleSelection: CompanionParticleSelection?
    /// Disposable projection cache; rebuilt whenever owner evidence changes.
    var particleSceneCache: CompanionParticleScene?
    @Published var inspectedDocumentMethod: DocumentMethodInspectionSelection?
    /// Chosen method for the document-side preview; never persisted or sent.
    @Published private(set) var documentMethodToTry: DocumentMethodInspectionSelection?
    @Published private(set) var workspaceRoutingNotice: String?
    private var pendingStewardReceipts: [String: AssistantLaneReceipt] = [:]
    private var pendingStewardEvaluations: [String: ARCCapabilitiesEvent] = [:]
    private var pendingStewardUseful: Set<String> = []
    private var pendingARC3Summaries: [String: ARC3SessionSummary] = [:]
    /// Desktop delivery may suspend the game without altering its saved data.
    let allowsPlay: Bool
    @Published var section: WorkspaceSection = .home {
        didSet {
            // The page editor is hosted by Memories. Keep that host alive until
            // the user explicitly saves or cancels its local editable fields.
            if hasOpenKnowledgeDraft, section != .memory {
                section = .memory
                knowledgePageMessage = "Save or cancel your open page or connection draft before changing views."
            }
            if section == .play && !allowsPlay { section = .assistant }
            if section != oldValue, focusGesturePlayback != nil { stopFocusGesture() }
            if section != oldValue, oldValue == .context {
                // Retire the document's spatial reference at navigation time,
                // before SwiftUI dismantles its native view during an update.
                invalidateTextSelection(reason: "Work together closed. Select the passage again when you return.")
            }
        }
    }
    @Published var preferences = CompanionPreferences() {
        didSet {
            if preferences.quiet { stopKinLightPreview() }
            if preferences.quiet || !preferences.musicalCues || preferences.musicalVolume == 0 { stopHarmonyTheme() }
            if preferences != oldValue { invalidatePlacementPreview(reason: "Appearance or preferences changed. Preview again.") }
            refreshReactorReference()
        }
    }
    @Published var isVisible = true {
        didSet {
            if !isVisible {
                desktopInterest.cancel(reason: "ARCHi hidden. Point again when ready.")
                stopKinLightPreview()
                stopHarmonyTheme()
                invalidatePlacementPreview(reason: "Companion hidden. Preview again when shown.")
            }
            refreshReactorReference()
        }
    }
    @Published var position = CGPoint.zero
    @Published var placementRevision: UInt64 = 0
    @Published var sharedText = "" {
        didSet { if sharedText != oldValue { invalidateActiveARCSource() } }
    }
    let desktopInterest: DesktopInterestSession
    @Published private(set) var desktopInterestSource: DesktopInterestSource?
    @Published private(set) var desktopInterestExternalDigest: String?
    @Published var sourceName: String? {
        didSet { if sourceName != oldValue { invalidateActiveARCSource() } }
    }
    @Published var sourceRevision: UInt64 = 0 {
        didSet { if sourceRevision != oldValue { invalidateActiveARCSource() } }
    }
    @Published private(set) var textSelection: DocumentSelection?
    @Published private(set) var replySourceSelection: DocumentSelection?
    @Published private(set) var spatialPreview: SpatialPreview?
    @Published private(set) var lastPlacementReceipt: SpatialPlacementReceipt?
    @Published private(set) var isRecordingSpatial = false
    @Published private(set) var spatialRecordCount = 0
    @Published private(set) var spatialRecordingMessage = "Recording is off. Geometry stays in this session until you export it."
    @Published var spatialMessage = "Preview a spot without moving ARCHi."
    @Published var reply = "Ask a question or tell me what you would like help with. Sharing a document is optional."
    @Published var prompt = ""
    let voiceInput: VoiceInputController
    @Published var requestsRevision = false
    @Published var documentRequirements = DocumentWorkRequirements()
    @Published private(set) var workingCopyNotice = "Select a passage to begin."
    private var workingCopyUndo: WorkingCopyEditReceipt?
    @Published private(set) var pendingDocumentReceipt: DocumentWorkRecord?
    private var openedWorkingCopyDigest: String?
    private var exportedWorkingCopyDigest: String?
    @Published private(set) var workingCopyIsPasted = false
    @Published var pastedDocumentDraft = PastedDocumentDraft()
    var hasUnexportedWorkingCopy: Bool {
        guard sourceName != nil, let openedWorkingCopyDigest else { return false }
        let current = SHA256.hash(data: Data(sharedText.utf8)).map { String(format: "%02x", $0) }.joined()
        return (workingCopyIsPasted || current != openedWorkingCopyDigest) && current != exportedWorkingCopyDigest
    }
    private var importedSourceURL: URL?
    @Published private(set) var wikiOSTask: QiWorkRequestFile?
    @Published var wikiOSExchangeReview: WikiOSExchangeReview?
    @Published var wikiOSExchangeMessage: String?
    @Published var activity: [String] = []
    @Published var isWorking = false
    @Published private(set) var activeARCAnswer: ARCActiveAssistantAnswer?
    private var activeARCOwner: ARCActiveAssistantOwnership?
    @Published private(set) var isShuttingDown = false
    @Published var connectionState: AssistantConnectionState = .disconnected
    @Published var connectionMessage = "Connect Qwen on this Mac when you are ready."
    @Published private(set) var assistantProvider: AssistantProvider
    @Published private(set) var route: AssistantRoute
    @Published private(set) var compareResults: [AssistantProvider: AssistantLaneResult] = [:]
    @Published private var connectionStates: [AssistantProvider: AssistantConnectionState] = [:]
    @Published private var connectionMessages: [AssistantProvider: String] = [:]
    @Published private(set) var qwenModel = QwenAssistant.defaultModel
    @Published private(set) var qwenContextModel = HamptonReasonsAssistant.defaultContextModel
    @Published private(set) var localWorkPreference: LocalWorkPreference = .automatic
    @Published private(set) var installedLocalModels: [QwenModelMetadata]?
    @Published private(set) var modelInventoryNotice = "Refresh to inspect installed local models."
    @Published private(set) var isRefreshingModels = false
    private var modelInventoryTask: Task<Void, Never>?
    // Reader selection belongs to this visit, never to a Seed or retained memory.
    @Published private(set) var representationReader: GGUFReaderArtifact?
    @Published private(set) var representationMeasurementsEnabled = false
    @Published private(set) var representationNotice = "Import a model-specific reader for inspection."
    @Published private(set) var sessionContextEnabled = false
    @Published private(set) var localConversation = AssistantConversation()
    @Published private(set) var localConversationEnabled = true
    @Published private(set) var localConversationNotice = "Recent Qwen exchanges stay in this visit only."
    private var localConversationRequestIDs = Set<UUID>()
    private var localConversationExpiry: Date?
    private var localConversationReadingSources: [ReadingSourceBinding]?
    private var localConversationKnowledgePages: [KnowledgePageBinding]?
    private var localContextTaskScope: HamptonTaskScope?
    @Published private(set) var hamptonSnapshot = HamptonAssistantSnapshot()
    @Published var rememberPreferences = false
    @Published private(set) var keptLessons: [KeptLesson] = []
    @Published private(set) var lessonRevision: UInt64 = 0
    @Published var lessonDraft: LessonCorrectionDraft?
    @Published private(set) var lessonMessage = "Keep only what you want ARCHi to use again."
    @Published private(set) var itemLibrary: [CompanionItemPackage] = []
    @Published var marketplaceMessage = "Your collection stays on this Mac. No purchase needed."
    @Published var importedMarketItem: CompanionItemPackage?
    @Published private(set) var keptFocusGesture: FocusGestureConfiguration?
    @Published private(set) var keptQiMon: LocalQiMon?
    @Published private(set) var qiMonJourneyOrigin: String?
    @Published private(set) var qiMonMessage = "Welcome KIN to your saved Journey."
    @Published var focusGestureDraft: FocusGestureConfiguration? {
        didSet {
            if focusGestureDraft != oldValue, focusGesturePlayback != nil { stopFocusGesture() }
        }
    }
    @Published private(set) var focusGesturePlayback: FocusGesturePlayback?
    @Published private(set) var kinLightPreview: KinLightPreview?
    @Published var harmonyMessage = "Musical cues are off."
    @Published private(set) var harmonyThemeRequest: UUID?
    private var kinLightPreviewTask: Task<Void, Never>?
    @Published private(set) var focusGestureMessage = "Teach how the staff points when you ask."
    @Published var status = "On this Mac · assistant not connected"
    var onShowCompanion: (() -> Void)?
    var onHideCompanion: (() -> Void)?
    var onOpenLab: (() -> Void)?
    var onOpenPlay: (() -> Void)?
    var onOpenWorkspace: ((WorkspaceSection) -> Void)?
    var onBeginDesktopInterest: (() -> Void)?
    var selectedPassageObserverID: UUID?
    var onObserveSelectedPassage: (() -> SelectedPassageGeometry?)?
    var onObserveSpatialEnvironment: (() -> SpatialEnvironment?)?
    var onMoveCompanion: ((CGRect) -> Void)?
    var onPresentPlacementPreview: ((SpatialPreview?) -> Void)?
    private var workGeneration: UInt64 = 0
    private var selectionRevision: UInt64 = 0
    private var connectionGenerations: [AssistantProvider: UInt64] = [:]
    private var connectionTasks: [AssistantProvider: Task<Void, Never>] = [:]
    private var replyTasks: [AssistantProvider: Task<Void, Never>] = [:]
    private var replyOwners: [AssistantProvider: UUID] = [:]
    private var laneStartedAt: [AssistantProvider: TimeInterval] = [:]
    private var laneTimeoutTasks: [AssistantProvider: Task<Void, Never>] = [:]
    private var previewExpiryTask: Task<Void, Never>?
    private var focusGestureTask: Task<Void, Never>?
    private let spatialRecorder = SpatialRecorder()
    private let monotonicTime: () -> TimeInterval
    private var assistants: [AssistantProvider: any AssistantClient] = [:]
    private let assistantFactory: @MainActor (AssistantProvider, String) -> any AssistantClient
    private var retiringAssistants: [UUID: Task<Void, Never>] = [:]
    private let preferenceURL: URL
    @Published var hasPersonalContextDraft = false
    @Published var hasSeedDesignDraft = false
    private var preferenceDocument = NativePreferenceDocument()
    private var preferenceBaseline: Data?
    private var preferenceFileReadable = true
    private var preferenceBaselineKnownCurrent = true
    @Published private(set) var profileRecoveryBlock: String?
    private let wallClock: () -> Date
    let evolution: EvolutionStore
    let reactor = ReactorExpressionStore()
    let unityPresentation = UnityPresentationConnection()
    let marketplaceCatalog: MarketplaceCatalogStore
    private var evolutionSubscriptions = Set<AnyCancellable>()
    private var documentDataSubscriptions = Set<AnyCancellable>()
    private var lastEvolutionAppearanceID: String?

    /// Ordinary settings have their own explicit Save. Remember controls that
    /// action; switching it off neither forgets nor conceals an earlier save.
    var preferenceRetention: PreferenceRetentionState {
        guard preferenceFileReadable else { return .unavailable }
        guard let saved = preferenceDocument.preferences else { return .thisVisit }
        return preferences == saved ? .saved : .changed
    }
    var hasSavedPreferences: Bool { preferenceDocument.preferences != nil }
    /// The outfit retained for a later visit is independent of this visit's
    /// equipment, other changed settings, and the current Save opt-in.
    var savedMarketplaceEquipment: CompanionEquipment? {
        marketplaceOutfitReadable ? preferenceDocument.preferences?.equipment : nil
    }
    var marketplaceOutfitReadable: Bool {
        preferenceFileReadable && preferenceBaselineKnownCurrent && profileRecoveryBlock == nil
    }
    var knownRetainedLessonCount: Int { preferenceDocument.lessons.count }
    var hasRetainedQiMon: Bool { preferenceDocument.qiMon != nil }
    var hasRetainedFocusGesture: Bool { preferenceDocument.focusGesture != nil }

    /// Identify the configured local profile without exposing its path or
    /// inspecting another app's files. Custom/test locations remain distinct.
    var retentionProfileLabel: String {
        switch preferenceURL.standardizedFileURL.deletingLastPathComponent().lastPathComponent {
        case "ARCHiDesktopReview": "ARCHi"
        case "ARCHiDesktop": "Legacy Desktop Preview"
        default: "Custom local profile"
        }
    }

    var nextReplySettings: AssistantSettingsSnapshot {
        AssistantSettingsSnapshot(tone: preferences.tone, replyLength: preferences.replyLength,
            role: evolution.confirmedRole, helpStyle: evolution.confirmedHelpStyle)
    }

    var assistantActivity: AssistantActivity {
        if showsARC3Reply {
            if arc3.isWorking { return .working }
            if arc3.error != nil { return .failed }
            if arc3.observation != nil { return .ready }
        }
        if let answer = activeARCAnswer {
            return answer.isWorking ? .working : answer.cancelled ? .stopped : answer.error == nil ? .ready : .failed
        }
        return AssistantActivity.derive(owned: Set(replyOwners.keys), results: compareResults)
    }

    var hasFreshKinFocus: Bool {
        guard activeQiMon != nil, isVisible, !isShuttingDown,
              let preview = spatialPreview, preview.isFresh(at: monotonicTime()),
              preview.ticket == contextTicket(),
              textSelection == preview.geometry.selection,
              preview.geometry.selection.matches(text: sharedText, sourceRevision: sourceRevision),
              onObserveSelectedPassage?() == preview.geometry,
              onObserveSpatialEnvironment?() == preview.environment else { return false }
        return true
    }

    var kinLightExpression: KinLightExpression {
        kinLightExpression(for: preferences)
    }

    private func kinLightExpression(for settings: CompanionPreferences) -> KinLightExpression {
        let preview = kinLightPreview.flatMap {
            $0.isFresh(at: monotonicTime(), ticket: contextTicket()) ? $0.mode : nil
        }
        // Pointing shows attention to the same outlined window, without claiming
        // its content has been read. The acquisition owner retires this cue.
        let outlinedWindow = desktopInterest.cue.outlineFrame != nil
        return KinLightRules.resolve(activity: assistantActivity, hasFreshFocus: hasFreshKinFocus || outlinedWindow,
            preview: preview, visible: isVisible && !isShuttingDown,
            quiet: settings.quiet, activeKin: activeQiMon != nil)
    }

    var canPreviewKinLight: Bool {
        activeQiMon != nil && isVisible && !isShuttingDown && !preferences.quiet && !isWorking && !hasFreshKinFocus
    }

    @discardableResult
    func previewKinLight(_ mode: KinLightMode) -> Bool {
        guard canPreviewKinLight, mode != .rest else { return false }
        let now = monotonicTime()
        guard now.isFinite, now >= 0 else { return false }
        stopHarmonyTheme()
        stopKinLightPreview()
        let preview = KinLightPreview(id: UUID(), mode: mode, startedAt: now, ticket: contextTicket())
        kinLightPreview = preview
        kinLightPreviewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(KinLightPreview.lifetime))
            guard !Task.isCancelled, let self, self.kinLightPreview?.id == preview.id else { return }
            self.stopKinLightPreview()
        }
        return true
    }

    func stopKinLightPreview() {
        kinLightPreviewTask?.cancel()
        kinLightPreviewTask = nil
        if kinLightPreview != nil { kinLightPreview = nil }
    }

    var canPreviewHarmonyTheme: Bool {
        canPreviewKinLight && preferences.musicalCues && preferences.musicalVolume > 0
    }

    func previewHarmonyTheme() {
        guard canPreviewHarmonyTheme else { return }
        stopKinLightPreview()
        harmonyThemeRequest = UUID()
    }

    func stopHarmonyTheme() {
        if harmonyThemeRequest != nil { harmonyThemeRequest = nil }
    }

    @discardableResult
    func validateKinLightPreview(id: UUID) -> Bool {
        guard let preview = kinLightPreview, preview.id == id else { return false }
        guard canPreviewKinLight, preview.isFresh(at: monotonicTime(), ticket: contextTicket()) else {
            stopKinLightPreview(); return false
        }
        return true
    }

    var assistantAccessibilityValue: String {
        assistantAccessibilityValue(for: preferences)
    }

    var cursorAccessibilityValue: String { cursorAccessibilityValue(for: preferences) }

    func cursorAccessibilityValue(for preferences: CompanionPreferences) -> String {
        cursorAccessibilityValue(for: preferences, gesture: focusGesturePlayback)
    }

    func cursorAccessibilityValue(for preferences: CompanionPreferences, gesture: FocusGesturePlayback?) -> String {
        assistantAccessibilityValue(for: preferences, gesture: gesture, role: .cursor)
    }

    func assistantAccessibilityValue(for preferences: CompanionPreferences) -> String {
        assistantAccessibilityValue(for: preferences, gesture: focusGesturePlayback)
    }

    func assistantAccessibilityValue(for preferences: CompanionPreferences, gesture: FocusGesturePlayback?,
                                     role: CompanionPresentationRole = .body) -> String {
        let cue = gesture?.purpose == .practice ? ". Practicing staff gesture"
            : gesture?.purpose == .pointing ? ". Pointing with staff" : ""
        let identity = role == .cursor ? activeQiMon.map { "\($0.name) · Seed cursor. " } ?? "" : ""
        return identity + CompanionVisualAsset.label(form: presentationForm(for: preferences, role: role), family: presentationFamily,
            treatment: preferences.visualTreatment, recipe: presentationRecipe,
            naturalVariation: presentationNaturalVariation, equipment: preferences.equipment, seedColor: preferences.seedColor) + ". Assistant: " + assistantActivity.title + cue
            + (activeQiMon == nil ? "" : ". Light expression: " + kinLightExpression(for: preferences).label)
            + (desktopInterest.phase == .idle ? "" : ". Object of interest: " + desktopInterest.message)
    }

    var nextExecutionSelection: AssistantExecutionSelection {
        executionSelection(question: prompt, pointing: nil)
    }

    func executionSelection(question: String, pointing: AssistantPointingSnapshot?) -> AssistantExecutionSelection {
        .select(question: question, hasPreparedProcedure: preparedDocumentProcedure != nil, hasPointing: pointing != nil)
    }

    var nextLocalExpertDecision: LocalExpertDecision {
        LocalExpertPolicy.decide(prompt: prompt,
            requiresReasoning: !selectedKnowledgePages.isEmpty || sourceName != nil || !sharedText.isEmpty || textSelection != nil
                || requestsRevision || !selectedReadingSourceIDs.isEmpty,
            preference: localWorkPreference, measurements: representationMeasurementsEnabled)
    }

    /// Configuration checks only; current-source, proposal and budget validation
    /// remain owned by submit. Reading previews never prepare or mutate a plan.
    var nextAssistantBlockedReason: String? {
        nextExecutionSelection == .assistant ? assistantBlockedReason(hasPointing: false) : nil
    }

    private func assistantBlockedReason(hasPointing: Bool) -> String? {
        if preparedDocumentProcedureKnowledge != nil,
           hasPointing || route == .codex || route == .compare {
            return "Methods linked to knowledge pages stay on this Mac. Choose a local route before sending."
        }
        if !selectedKnowledgePages.isEmpty {
            if requestsRevision || hasPointing || route == .codex || route == .compare {
                return "Selected knowledge pages use local chat. Finish or detach the pages before revising, pointing, or using an external route. Nothing sent."
            }
            if let issue = selectedKnowledgePageIssue { return issue + " Nothing sent." }
        }
        if representationMeasurementsEnabled && !route.providers.allSatisfy({ $0 == .qwen }) {
            return "Model measurements stay on this Mac. Choose a local route, or turn measurements off before using an external assistant. Nothing sent."
        }
        if selectedKnowledgePages.isEmpty, !selectedReadingSourceIDs.isEmpty,
           requestsRevision || hasPointing || sourceName == nil || route == .codex || route == .compare {
            return "Kept reading copies use local Qwen for document questions. Choose a local route or deselect the copies. Nothing sent."
        }
        return nil
    }

    /// This is a ceiling explanation, never permission to invoke fallback.
    /// The captured request still passes finishFailedAttempt's complete checks.
    var nextAssistantFallbackBlockedReason: String? {
        if preparedDocumentProcedureKnowledge != nil { return "This method is linked to a knowledge page; external fallback is disabled." }
        if !selectedKnowledgePages.isEmpty { return "Selected knowledge pages stay local; external fallback is disabled." }
        if representationMeasurementsEnabled { return "Model measurements stay local; external fallback is disabled." }
        if !selectedReadingSourceIDs.isEmpty { return "Selected kept reading copies stay local; external fallback is disabled." }
        let lessons = nextReplyLessons
        let knowledgeBackedLesson = keptLessons.contains { lesson in
            !(lesson.origin?.knowledgePages?.isEmpty ?? true) && lessons.contains { $0.id == lesson.id }
        }
        if knowledgeBackedLesson || (!nextReplyConversation.isEmpty && !(localConversationKnowledgePages?.isEmpty ?? true)) {
            return "Context supported by knowledge pages stays local; external fallback is disabled."
        }
        let readingBackedLesson = keptLessons.contains { lesson in
            !(lesson.origin?.readingSources?.isEmpty ?? true) && lessons.contains { $0.id == lesson.id }
        }
        if readingBackedLesson || (!nextReplyConversation.isEmpty && !(localConversationReadingSources?.isEmpty ?? true)) {
            return "Context supported by kept reading copies stays local; external fallback is disabled."
        }
        if desktopInterestSource != nil, desktopInterestExternalDigest != LessonSource.digest(of: sharedText) {
            return "This window copy stays local until you allow this exact copy for an external route."
        }
        return nil
    }

    var nextCallBudget: String {
        if let budget = nextExecutionSelection.nativeCallBudget { return budget }
        if let reason = nextAssistantBlockedReason { return "0 model calls · " + reason }
        let answerCalls = nextLocalExpertDecision.target == .reasoning
            ? "1 local answer attempt" : "Up to 2 local answer attempts (compact + recovery)"
        let local = answerCalls + (sessionContextEnabled ? ", plus up to 2 context calls" : "")
        switch route {
        case .native:
            return local + (nextAssistantFallbackBlockedReason == nil
                ? " · at most 1 Codex fallback request" : " · no external requests")
        case .local, .automatic: return local + " · no external requests"
        case .codex: return "1 Codex request"
        case .compare: return local + " · 1 Codex request"
        }
    }

    var arc3CommandSelected: Bool { nextExecutionSelection.isARC3Command }
    var arcCommandSelected: Bool { nextExecutionSelection.isNativeCommand }
    var isARCWorking: Bool { activeARCOwner != nil || arc3.isWorking }
    var canBeginReply: Bool { canBeginReply(selection: nextExecutionSelection, hasPointing: false) }

    private func canBeginReply(selection: AssistantExecutionSelection, hasPointing: Bool) -> Bool {
        !isShuttingDown && !voiceInput.isActive
            && (selection.isNativeCommand || (assistantBlockedReason(hasPointing: hasPointing) == nil
                && canShareDesktopInterestWithRoute && (route.connectsAutomatically || connectionState == .ready)))
    }

    var canShareDesktopInterestWithRoute: Bool {
        desktopInterestSource == nil || route == .local || route.connectsAutomatically
            || desktopInterestExternalDigest == LessonSource.digest(of: sharedText)
    }

    func allowDesktopInterestWithExternalRoute() {
        guard !isShuttingDown, desktopInterestSource != nil,
              route == .codex || route == .compare || route == .native else { return }
        desktopInterestExternalDigest = LessonSource.digest(of: sharedText)
        status = "This exact copy may be sent with your selected route. Nothing sent yet."
    }
    var resultProviders: [AssistantProvider] {
        if knowledgeMethodDraftPage != nil || knowledgeConceptDraftRequestID != nil { return [.qwen] }
        return route == .native && compareResults[.codex] != nil ? [.qwen, .codex] : route.providers
    }

    var nextReplyConversation: [AssistantConversationExchange] {
        localConversationEnabled && route != .codex
            && localPreferenceMemoryIsCurrent
            && (localContextTaskScope == nil || localContextTaskScope == currentTaskScope)
            && readingDependenciesAreCurrent(localConversationReadingSources)
            && knowledgeDependenciesAreCurrent(localConversationKnowledgePages)
            && (localConversationExpiry.map { $0 > wallClock() } ?? true) ? localConversation.exchanges : []
    }

    func setLocalConversationEnabled(_ enabled: Bool) {
        guard !isShuttingDown, enabled != localConversationEnabled else { return }
        startNewLocalConversation()
        localConversationEnabled = enabled
        localConversationNotice = enabled ? "Recent Qwen exchanges stay in this visit only." : "Follow-up context is off. Each question starts fresh."
    }

    func startNewLocalConversation() {
        guard !isShuttingDown else { return }
        cancelActiveARC(reason: "New conversation.")
        arc3.stop(reason: "New conversation.")
        showsARC3Reply = false
        clearSessionContext()
        localConversationNotice = "New local conversation. Your draft, shared copy and kept lessons are unchanged."
        if assistantProvider == .qwen { reply = "What would you like to work on?" }
        if !isWorking { status = localConversationNotice }
    }

    /// A reading correction retires generated continuation, not exact source
    /// spans or explicitly kept lessons. Preserve the visible answer for review.
    func invalidateCorrectedReadingContinuation() {
        clearLocalConversation()
        localConversationNotice = "The corrected answer was removed from follow-up context. Your shared copy and kept lessons are unchanged."
    }

    private func readingContinuationIsCurrent(_ parents: Set<UUID>) -> Bool {
        guard !parents.isEmpty else { return true }
        do { try tokenSteward.refresh() } catch { return false }
        return parents.isDisjoint(with: HamptonMemoryDependencies.invalidatedReadings(tasks: tokenSteward.tasks))
    }

    private func clearLocalConversation() {
        // Document detachment can retire an already-empty selection during a
        // native view update. Do not publish a change when nothing changed.
        if !localConversation.exchanges.isEmpty { localConversation.clear() }
        if localConversationExpiry != nil { localConversationExpiry = nil }
        localConversationReadingSources = nil
        localConversationKnowledgePages = nil
        localConversationRequestIDs.removeAll()
        localContextTaskScope = nil
        let notice = "Recent Qwen exchanges stay in this visit only."
        if localConversationNotice != notice { localConversationNotice = notice }
    }

    init(preferenceURL: URL? = nil, assistant: (any AssistantClient)? = nil,
         provider: AssistantProvider = .qwen,
         assistantFactory: @escaping @MainActor (AssistantProvider, String) -> any AssistantClient = { provider, model in
             provider == .qwen ? HamptonReasonsAssistant(model: model, nativeRuntime: .shared) : CodexAssistant()
         },
         monotonicTime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         wallClock: @escaping () -> Date = Date.init, allowsPlay: Bool = true,
         voiceInput: VoiceInputController? = nil, interestReader: (any DesktopInterestReading)? = nil,
         tokenSteward: TokenStewardStore? = nil, arcCapabilities: ARCCapabilitiesStore? = nil, arc3: ARC3SessionStore? = nil,
         marketplaceCatalog: MarketplaceCatalogStore? = nil) {
        self.marketplaceCatalog = marketplaceCatalog ?? MarketplaceCatalogStore()
        self.voiceInput = voiceInput ?? VoiceInputController()
        self.desktopInterest = DesktopInterestSession(reader: interestReader)
        self.allowsPlay = allowsPlay
        self.monotonicTime = monotonicTime
        self.wallClock = wallClock
        self.assistantProvider = provider
        self.route = provider == .qwen ? .local : .codex
        self.assistantFactory = assistantFactory
        self.assistants[provider] = assistant ?? assistantFactory(provider, QwenAssistant.defaultModel)
        self.connectionMessage = "Connect \(provider.destination) when you are ready."
        let resolvedPreferenceURL = preferenceURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ARCHiDesktop/preferences.json")
        self.preferenceURL = resolvedPreferenceURL
        self.tokenSteward = tokenSteward ?? TokenStewardStore(url: resolvedPreferenceURL.deletingPathExtension().appendingPathExtension("steward.json"))
        self.arcCapabilities = arcCapabilities ?? ARCCapabilitiesStore(storageURL: resolvedPreferenceURL.deletingPathExtension().appendingPathExtension("arc.json"))
        self.arc3 = arc3 ?? ARC3SessionStore(outputDirectory: resolvedPreferenceURL.deletingLastPathComponent().appendingPathComponent("ARC3Episodes", isDirectory: true))
        // Resolve all five files before admitting any dependent document owner.
        let startupRecoveryBlock = DesktopRecoveryStartup.recoverIfNeeded(at: resolvedPreferenceURL)
        self.documentWork = DocumentWorkJournal(url: resolvedPreferenceURL.deletingPathExtension().appendingPathExtension("document-work.json"), recoveryBlocked: startupRecoveryBlock != nil)
        self.documentProcedures = DocumentProcedureLibrary(url: resolvedPreferenceURL.deletingPathExtension().appendingPathExtension("document-procedures.json"), recoveryBlocked: startupRecoveryBlock != nil)
        self.readingSources = ReadingSourceLibrary(url: resolvedPreferenceURL.deletingPathExtension().appendingPathExtension("reading-sources.json"), recoveryBlocked: startupRecoveryBlock != nil)
        self.profileRecoveryBlock = startupRecoveryBlock
        do {
            if let startupRecoveryBlock { throw DesktopRecoveryError.blocked(startupRecoveryBlock) }
            let loaded = try NativePreferencePersistence.read(resolvedPreferenceURL)
            preferenceDocument = loaded.document
            preferenceBaseline = loaded.baseline
            keptLessons = loaded.document.lessons
            keptFocusGesture = loaded.document.focusGesture
            keptQiMon = loaded.document.qiMon
            itemLibrary = loaded.document.itemLibrary
            lessonRevision = loaded.document.revision
        } catch {
            preferenceFileReadable = false
            lessonMessage = "The saved settings file could not be read. It has been preserved; reopen after restoring a valid file before saving."
        }
        let initialPreferences = preferenceDocument.preferences
        self.evolution = EvolutionStore(origin: initialPreferences?.form ?? .companion,
            saveURL: resolvedPreferenceURL.deletingPathExtension().appendingPathExtension("evolution.json"))
        self.evolution.persistenceBlockedReason = startupRecoveryBlock
        if documentWork.loadError != nil {
            self.evolution.historicalEvidenceUnavailableReason = "Document review history could not be read. Restore that file and reopen ARCHi before loading saved learning; your current appearance is unchanged."
        }
        if let saved = initialPreferences {
            preferences = saved
            rememberPreferences = true
        }
        bindHamptonAssistant()
        evolution.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &evolutionSubscriptions)
        self.tokenSteward.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &evolutionSubscriptions)
        self.arcCapabilities.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &evolutionSubscriptions)
        bindDocumentDataOwners()
        self.arc3.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
            guard let self else { return }
            self.objectWillChange.send()
            self.isWorking = !self.replyOwners.isEmpty || self.activeARCOwner != nil || self.arc3.isWorking
            if self.showsARC3Reply { self.status = self.arc3.status }
        }.store(in: &evolutionSubscriptions)
        self.arc3.onFinished = { [weak self] summary in
            guard let self else { return }
            self.lastARC3Summary = summary
            self.pendingARC3Summaries[summary.sessionID] = summary
            do { try self.retryStewardReceipts(); self.stewardMessage = nil }
            catch { self.stewardMessage = "ARC3 episode retained; Usage needs attention: \(error.localizedDescription)" }
        }

        reactor.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &evolutionSubscriptions)
        self.voiceInput.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &evolutionSubscriptions)
        desktopInterest.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &evolutionSubscriptions)
        $compareResults.combineLatest($isWorking).receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }; self.reactor.updateCue(self.assistantActivity)
        }.store(in: &evolutionSubscriptions)
        $activeARCAnswer.receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }; self.reactor.updateCue(self.assistantActivity)
        }.store(in: &evolutionSubscriptions)
        refreshReactorReference()
        lastEvolutionAppearanceID = CompanionVisualAsset.appearanceID(form: presentationForm,
            family: presentationFamily, treatment: preferences.visualTreatment, recipe: presentationRecipe, naturalVariation: presentationNaturalVariation, seedColor: preferences.seedColor)
        evolution.$revision.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            let id = CompanionVisualAsset.appearanceID(form: self.presentationForm, family: self.presentationFamily,
                treatment: self.preferences.visualTreatment, recipe: self.presentationRecipe, naturalVariation: self.presentationNaturalVariation, seedColor: self.preferences.seedColor)
            guard id != self.lastEvolutionAppearanceID else { return }
            self.lastEvolutionAppearanceID = id
            self.invalidatePlacementPreview(reason: "ARCHi's chosen appearance changed. Preview placement again.")
            self.refreshReactorReference()
        }.store(in: &evolutionSubscriptions)
    }

    func placed(at point: CGPoint) {
        guard point.x.isFinite, point.y.isFinite else { return }
        position = point
        placementRevision &+= 1
        invalidateDocumentGeometry(reason: "ARCHi moved. Preview pointing again.")
    }

    func showCompanion() { isVisible = true; onShowCompanion?() }
    func hideCompanion() {
        isVisible = false
        invalidateTextSelection(reason: "Companion hidden; passage reference cleared.")
        cancelWork(reason: "Companion hidden.")
        onHideCompanion?()
    }
    func open(_ section: WorkspaceSection) {
        voiceInput.cancel()
        if workspaceRoutingNotice != nil { workspaceRoutingNotice = nil }
        let destination = section == .play && !allowsPlay ? .assistant : section
        if destination == .capabilities { showsReasoningTools = false }
        if self.section != destination { self.section = destination }
        onOpenWorkspace?(destination)
    }

    func openReasoningTools(worlds: Bool = false) {
        open(.capabilities)
        reasoningToolsShowWorlds = worlds
        showsReasoningTools = true
    }

    /// Browsing Arena never discovers games, starts a solver, or launches Unity.
    /// In-flight work stays with the same owners when the page changes.
    func openArena(_ activity: ArenaActivity) {
        arenaActivity = activity
        open(.unity)
    }

    var arcGridStartUnavailableReason: String? {
        if isShuttingDown { return "ARCHi is finishing this session." }
        if arc3.isWorking || arc3.isSessionActive {
            return "A World Trial is open. Choose Stop & keep record there before starting a Pattern Trial."
        }
        return nil
    }

    func dismissWorkspaceRoutingNotice() { workspaceRoutingNotice = nil }

    @discardableResult
    func openDocumentUsage(taskID: String) -> Bool {
        let available = tokenSteward.loadError == nil && tokenSteward.tasks.contains { $0.id == taskID }
        selectedStewardTaskID = available ? taskID : nil
        open(.steward)
        workspaceRoutingNotice = available ? nil : "That request's usage is unavailable. No replacement was selected."
        return available
    }

    @discardableResult
    func openARCUsage(taskID: String) -> Bool {
        let available = tokenSteward.loadError == nil && tokenSteward.tasks.contains {
            $0.id == taskID && ["arc-evaluation", "arc-interactive"].contains($0.route)
        }
        selectedStewardTaskID = available ? taskID : nil
        open(.steward)
        workspaceRoutingNotice = available ? nil : "That ARC usage task is unavailable. No replacement task was selected."
        return available
    }

    /// General navigation starts at memory; exact receipt routes retain their selection.
    func openMemoryMap() {
        selectedGraphNodeID = nil
        open(.nodeLab)
    }

    /// Navigation to the retained version, including a corrected or withdrawn
    /// one. Opening its evidence never prepares work or picks a newer version.
    @discardableResult
    func openDocumentMethodMap(_ binding: DocumentProcedureUse) -> Bool {
        guard !isShuttingDown, profileRecoveryBlock == nil,
              documentProcedures.isCurrentOnDisk, documentWork.isCurrentOnDisk,
              documentProcedures.procedure(matching: binding) != nil,
              memoryMapSnapshot().nodes.contains(where: { $0.id == DocumentMethodGraph.nodeID(binding) }) else {
            workspaceRoutingNotice = "That exact method or its history is unavailable. No replacement was selected."
            return false
        }
        selectedGraphNodeID = DocumentMethodGraph.nodeID(binding)
        open(.nodeLab)
        workspaceRoutingNotice = nil
        return true
    }

    @discardableResult
    func beginDocumentMethodWork(_ selection: DocumentMethodInspectionSelection) -> Bool {
        guard !isWorking, let method = methodForInspection(selection),
              documentProcedures.latestProcedures.contains(method),
              documentProcedureUnavailable(method.binding) == nil, !hasOpenKnowledgeDraft else { return false }
        documentMethodToTry = selection
        selectedGraphNodeID = DocumentMethodGraph.nodeID(method.binding)
        inspectedDocumentMethod = nil
        open(.context)
        return true
    }

    func clearDocumentMethodToTry() { documentMethodToTry = nil }

    @discardableResult
    func openARCGraph(evidenceID: String) -> Bool {
        let node = companionGraphSnapshot().nodes.first {
            $0.kind == .evaluation && $0.target == .arcEvidence(proposalHash: evidenceID)
        }
        selectedGraphNodeID = node?.id
        open(.nodeLab)
        workspaceRoutingNotice = node == nil ? "That ARC result is unavailable in this profile's Activity map. No replacement was selected." : nil
        return node != nil
    }

    /// Resolve the current record again at interaction time. This opens the
    /// existing inspector; it does not run the target action or admit memory.
    @discardableResult
    func inspectKnowledgeParticle(nodeID: String, graphDigest: String) -> Bool {
        let graph = companionGraphSnapshot()
        guard LiminalKnowledgeBindings.digest(graph) == graphDigest,
              graph.nodes.contains(where: { $0.id == nodeID }) else { return false }
        selectedGraphNodeID = nodeID
        open(.nodeLab)
        return true
    }

    /// Revalidate a displayed Seed/map binding before highlighting or opening it.
    @discardableResult
    func selectMemoryParticle(_ id: String, in scene: CompanionParticleScene, openInspector: Bool = false) -> Bool {
        guard let current = companionParticleScene(),
              scene.isCurrent(graph: current.graph, originDigest: current.originDigest),
              current.graph.nodes.contains(where: { $0.id == id }) else { return false }
        memoryParticleSelection = .init(originDigest: current.originDigest, graphDigest: current.graphDigest, nodeID: id)
        if openInspector { selectedGraphNodeID = id; open(.nodeLab) }
        return true
    }

    func canOpenARCEvidenceForUsage(taskID: String) -> Bool {
        currentARC3EvidenceMatches(taskID) || arcEvidenceForUsage(taskID: taskID) != nil
    }

    private func currentARC3EvidenceMatches(_ taskID: String) -> Bool {
        tokenSteward.loadError == nil && lastARC3Summary?.sessionID == taskID
            && lastARC3Summary?.receiptURL == arc3.receiptURL && arc3.receiptURL != nil
            && tokenSteward.tasks.contains { $0.id == taskID && $0.route == "arc-interactive" }
    }

    func openARCEvidenceForUsage(taskID: String) -> Bool {
        if currentARC3EvidenceMatches(taskID) { return runARC3(.open) }
        guard let record = arcEvidenceForUsage(taskID: taskID) else {
            let notice = "This usage task has no matching ARC result available in the current profile. No replacement was selected."
            arcCapabilities.clearRecordSelection(notice: notice)
            open(.capabilities)
            workspaceRoutingNotice = notice
            return false
        }
        let selected = arcCapabilities.selectRecord(id: record.id)
        openReasoningTools()
        workspaceRoutingNotice = selected ? nil : arcCapabilities.selectionNotice
        return selected
    }

    private func arcEvidenceForUsage(taskID: String) -> ARCCapabilitiesRecord? {
        guard tokenSteward.loadError == nil,
              let task = tokenSteward.tasks.first(where: { $0.id == taskID && $0.route == "arc-evaluation" }) else { return nil }
        return arcCapabilities.records.first { record in
            let current = arcCapabilities.solverReview
            // The journal is shared across profiles. A matching evidence hash alone
            // cannot establish ownership of an older replay or another profile's task.
            let currentRunMatches = current?.taskID == taskID && current?.evidenceID == record.id && current?.error == nil
            let proposal = arcCapabilities.qwenProposalReview
            let currentProposalMatches = proposal?.taskID == taskID && proposal?.evidenceID == record.id && proposal?.error == nil
            guard record.taskID == taskID || currentRunMatches || currentProposalMatches else { return false }
            return task.outcomes.contains {
                $0.kind == .checked && $0.evidenceID == record.id && $0.value == record.summary.allExact
            }
        }
    }

    var activeQiMon: LocalQiMon? {
        // The native record is already validated by NativePreferenceDocument.
        // In desktop-only development it supplies identity without starting a
        // web view or pretending to observe the suspended game's live Journey.
        if !allowsPlay { return keptQiMon }
        guard let saved = keptQiMon, saved.originDigest == qiMonJourneyOrigin else { return nil }
        return saved
    }

    var canWelcomeKin: Bool { keptQiMon == nil && qiMonJourneyOrigin != nil && preferenceFileReadable }

    func observeQiMonJourney(_ projection: HostedPlayProjection?) {
        let origin = projection?.readiness == .ready && projection?.storage == .localBrowser
            ? projection?.originDigest : nil
        let verified = origin.flatMap { HostedArenaProjection.isDigest($0) ? $0 : nil }
        guard qiMonJourneyOrigin != verified else { return }
        let previous = activeQiMon
        qiMonJourneyOrigin = verified
        if previous != activeQiMon {
            cancelWork(reason: "The active QiMon changed. Earlier replies were cleared.")
            clearSessionContext()
            refreshReactorReference()
        }
    }

    @discardableResult
    func welcomeKin() -> Bool {
        guard canWelcomeKin, let origin = qiMonJourneyOrigin else {
            qiMonMessage = "KIN needs a saved local Journey. Open Habitat and try again."
            return false
        }
        var document = preferenceDocument
        document.qiMon = LocalQiMon(character: .kin, originDigest: origin, welcomedAt: wallClock())
        document.preferences = preferences
        guard commitPreferenceDocument(document) else { qiMonMessage = status; return false }
        cancelWork(reason: "KIN welcomed. Earlier replies were cleared.")
        clearSessionContext()
        refreshReactorReference()
        rememberPreferences = true
        qiMonMessage = "KIN is here. Your QiMon is saved with this Journey on this Mac."
        status = qiMonMessage
        showCompanion()
        return true
    }

    var wikiOSExchangeBlockReason: String? {
        if isShuttingDown { return "ARCHi is closing. Reopen the task after this session ends." }
        if isWorking || isARCWorking { return "Finish or stop the current request before changing task context." }
        if voiceInput.isActive || voiceInput.phase == .review { return "Use or discard the current voice draft first." }
        if pendingDocumentReceipt != nil { return "Save the pending document receipt before changing task context." }
        if documentWork.records.contains(where: { $0.state.isActive }) { return "Apply or dismiss the pending document proposal before changing task context." }
        if profileRecoveryBlock != nil { return "Finish profile recovery before exchanging work." }
        if hasOpenKnowledgeDraft { return "Save or cancel the open knowledge page or connection draft before reviewing this task." }
        return nil
    }

    /// Opening a file stages one review. It never replaces the current copy.
    @discardableResult
    func stageWikiOSTask(from url: URL) -> Bool {
        guard wikiOSExchangeReview == nil else {
            wikiOSExchangeMessage = "Finish or cancel the open task review before opening another task."
            return false
        }
        do {
            let file = try QiWorkRequestFile.read(url)
            wikiOSExchangeReview = .incoming(file)
            wikiOSExchangeMessage = nil
            return true
        } catch {
            wikiOSExchangeMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func acceptWikiOSTask(_ file: QiWorkRequestFile, reviewWorkingCopy: (() -> Bool)? = nil) -> Bool {
        guard case .incoming(let pending) = wikiOSExchangeReview, pending == file else {
            wikiOSExchangeMessage = WikiOSTaskExchangeError.changed.localizedDescription; return false
        }
        if let reason = wikiOSExchangeBlockReason { wikiOSExchangeMessage = reason; return false }
        let previousRevision = sourceRevision, previousName = sourceName
        let previousBytes = Data(sharedText.utf8), previousPrompt = Data(prompt.utf8)
        do {
            try file.verifyUnchanged()
            let review = reviewWorkingCopy ?? {
                self.confirmDiscardWorkingCopy(before: "opening this WikiOS task", discardTitle: "Use WikiOS task instead")
            }
            guard review(), sourceRevision == previousRevision, sourceName == previousName,
                  Data(sharedText.utf8) == previousBytes, Data(prompt.utf8) == previousPrompt,
                  wikiOSExchangeBlockReason == nil, sourceRevision < UInt64.max,
                  case .incoming(let latest) = wikiOSExchangeReview, latest == file else {
                wikiOSExchangeMessage = "The task was not imported. Your current copy and question are still here."
                return false
            }
            try file.verifyUnchanged()
            share(text: file.request.brief, name: "WikiOS · " + file.request.taskTitle)
            wikiOSTask = file
            importedSourceURL = file.url.resolvingSymlinksInPath().standardizedFileURL
            wikiOSExchangeReview = nil
            workingCopyNotice = "WikiOS task opened locally · return your work before closing this session."
            wikiOSExchangeMessage = "Task copy imported. Select a passage or prepare a question; Send starts a request."
            open(.context)
            return true
        } catch { wikiOSExchangeMessage = error.localizedDescription; return false }
    }

    @discardableResult
    func beginWikiOSReturnReview() -> Bool {
        guard wikiOSExchangeReview == nil else { return false }
        if let reason = wikiOSExchangeBlockReason { wikiOSExchangeMessage = reason; return false }
        guard let request = wikiOSTask, let sourceName else {
            wikiOSExchangeMessage = WikiOSTaskExchangeError.noTask.localizedDescription; return false
        }
        wikiOSExchangeReview = .outgoing(WikiOSReturnPreview(request: request, text: sharedText,
            sourceName: sourceName, sourceRevision: sourceRevision))
        return true
    }

    /// Saves reviewed bytes only. Delivery and WikiOS admission are later actions.
    func exportWikiOSResult(_ preview: WikiOSReturnPreview, summary: String,
                           directory: URL? = nil) throws -> QiWorkResultFile {
        if let reason = wikiOSExchangeBlockReason { throw WikiOSTaskExchangeError.busy(reason) }
        guard wikiOSTask == preview.request, sourceName == preview.sourceName,
              sourceRevision == preview.sourceRevision, Data(sharedText.utf8) == Data(preview.text.utf8),
              case .outgoing(let current) = wikiOSExchangeReview, current == preview else {
            throw WikiOSTaskExchangeError.changed
        }
        try preview.request.verifyUnchanged()
        let request = preview.request.request
        let result = QiWorkResult(resultID: UUID().uuidString, requestID: request.requestID,
            requestSHA256: preview.request.digest, taskID: request.taskID, projectID: request.projectID,
            taskRevision: request.taskRevision, createdAtUnix: wallClock().timeIntervalSince1970,
            summary: summary, text: preview.text, textSHA256: QiWorkExchange.digest(Data(preview.text.utf8)),
            sourceRevision: preview.sourceRevision)
        try result.validate(request: preview.request)
        let outbox = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ARCHiTaskExchange/Outbox", isDirectory: true)
        let url = outbox.appendingPathComponent(result.resultID + ".qiresult")
        try QiWorkExchange.writeNew(QiWorkExchange.encode(result), to: url)
        let saved = try QiWorkResultFile.read(url)
        guard saved.result == result else { throw QiWorkExchangeError.writeFailed }
        exportedWorkingCopyDigest = result.textSHA256
        workingCopyNotice = "WikiOS result saved · working-copy bytes verified."
        wikiOSExchangeMessage = "Result saved locally. Review it in WikiOS before attaching it to the task."
        return saved
    }

    var canBeginPastedDocumentImport: Bool {
        !isShuttingDown && !isWorking && !isARCWorking && profileRecoveryBlock == nil
            && !voiceInput.isActive && voiceInput.phase != .review
            && pendingDocumentReceipt == nil && !documentWork.records.contains { $0.state.isActive }
    }

    func beginPastedDocumentImport() -> PastedDocumentImportContext? {
        guard canBeginPastedDocumentImport else { return nil }
        return PastedDocumentImportContext(sourceRevision: sourceRevision, sourceName: sourceName,
            sourceBytes: Data(sharedText.utf8), journalOwner: ObjectIdentifier(documentWork), companion: activeQiMon)
    }

    func pastedDocumentImportBlockReason(_ context: PastedDocumentImportContext) -> String? {
        guard context.journalOwner == ObjectIdentifier(documentWork), context.companion == activeQiMon,
              context.sourceRevision == sourceRevision, context.sourceName == sourceName,
              context.sourceBytes == Data(sharedText.utf8) else {
            return "Your document or profile changed. Keep this text and reopen Paste text from the current workspace."
        }
        guard canBeginPastedDocumentImport else {
            return "Finish the current request, proposal, voice draft or profile recovery before replacing the working copy."
        }
        return nil
    }

    static func pastedDocumentValidationMessage(text: String, title: String) -> String? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Paste some text to begin." }
        guard text.utf8.count <= 100_000 else { return "Use up to 100 KB of text. Nothing is trimmed automatically." }
        guard !text.contains("\0") else { return "Use plain text without binary content." }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count <= 160, name.rangeOfCharacter(from: .controlCharacters) == nil else {
            return "Use a single-line title of up to 160 characters."
        }
        return nil
    }

    @discardableResult
    func importPastedDocument(text: String, title: String, context: PastedDocumentImportContext,
                              reviewWorkingCopy: (() -> Bool)? = nil) -> Bool {
        if let reason = Self.pastedDocumentValidationMessage(text: text, title: title)
            ?? pastedDocumentImportBlockReason(context) { status = reason; return false }
        let review = reviewWorkingCopy ?? {
            self.confirmDiscardWorkingCopy(before: "using pasted text", discardTitle: "Use pasted text instead")
        }
        guard review() else { return false }
        // Modal alerts can run callbacks. Approval cannot follow a replaced source/profile.
        if let reason = pastedDocumentImportBlockReason(context) { status = reason; return false }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        share(text: text, name: name.isEmpty ? "Pasted text" : name)
        workingCopyIsPasted = true
        pastedDocumentDraft = PastedDocumentDraft()
        workingCopyNotice = "Pasted copy · Export to keep. Select a passage to begin."
        status = "Pasted locally · no content sent"
        open(.context)
        return true
    }

    func chooseDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .utf8PlainText, .text, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a text document to share with ARCHi locally."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard confirmDiscardWorkingCopy(before: "changing documents", discardTitle: "Discard edits and change document") else { return }
        if importWorkingCopy(from: url) { open(.context) }
    }

    @discardableResult
    func importWorkingCopy(from url: URL) -> Bool {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 100_000 else {
                status = "Choose a text file smaller than 100 KB."; return false
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            share(text: text, name: url.lastPathComponent)
            importedSourceURL = url.resolvingSymlinksInPath().standardizedFileURL
            return true
        } catch { status = "Could not read that UTF-8 text document."; return false }
    }

    @discardableResult
    func importMeetingNotes(_ notes: MeetingNotesImport, sourceURL: URL? = nil,
                            reviewWorkingCopy: (() -> Bool)? = nil) -> Bool {
        guard canImportMeetingNotes(notes) else { status = meetingNotesBudgetNotice; return false }
        let previousRevision = sourceRevision, previousName = sourceName
        let previousBytes = Data(sharedText.utf8)
        let review = reviewWorkingCopy ?? { self.confirmDiscardWorkingCopy(before: "importing meeting notes", discardTitle: "Use meeting notes instead") }
        guard review(), sourceRevision == previousRevision, sourceName == previousName,
              Data(sharedText.utf8) == previousBytes else { return false }
        guard canImportMeetingNotes(notes) else { status = meetingNotesBudgetNotice; return false }
        let hasDraftQuestion = !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        share(text: notes.sharedText, name: notes.sourceName)
        importedSourceURL = sourceURL?.resolvingSymlinksInPath().standardizedFileURL
        if !hasDraftQuestion { prepareMeetingDigest() }
        workingCopyNotice = "Meeting copy opened locally. Review proposed facts before keeping a lesson."
        status = hasDraftQuestion ? "Meeting notes shared locally · your draft question was kept" : "Meeting notes shared locally · digest question ready to send"
        open(.context)
        return true
    }

    func prepareMeetingDigest() {
        guard sourceName != nil, !isWorking else { return }
        guard meetingNotesQuestionFitsLocalBudget(MeetingNotesImport.digestQuestion,
            sourceName: sourceName, sourceText: sharedText, sourceRevision: sourceRevision) else {
            status = meetingNotesBudgetNotice
            return
        }
        clearTextSelection()
        requestsRevision = false
        prompt = MeetingNotesImport.digestQuestion
        status = "Digest question prepared · Send starts the request"
    }

    var meetingNotesBudgetNotice: String {
        "This question and its selected source sections exceed the local assistant's 22 KB encoded request budget, including instructions and lessons. Review a shorter excerpt or shorten your question. Nothing was sent or replaced."
    }

    func canImportMeetingNotes(_ notes: MeetingNotesImport) -> Bool {
        var questions = [MeetingNotesImport.digestQuestion]
        if !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { questions.append(prompt) }
        return questions.allSatisfy {
            meetingNotesQuestionFitsLocalBudget($0, sourceName: notes.sourceName,
                sourceText: notes.sharedText, sourceRevision: sourceRevision &+ 1)
        }
    }

    private func meetingNotesQuestionFitsLocalBudget(_ question: String, sourceName: String?,
                                                   sourceText: String, sourceRevision: UInt64) -> Bool {
        let lessons = keptLessons.filter {
            lessonDependenciesAreCurrent($0.origin) && $0.matches(question: question, sourceName: sourceName, sourceText: sourceText, now: wallClock(), taskScope: .documentQuestion)
        }.map(LessonSnapshot.init(lesson:))
        let reading = prepareReading(question: question, text: sourceText, selection: nil)
        guard let reading, reading.control.lane != .stop else { return false }
        let request = AssistantRequest(prompt: question, sourceName: sourceName, sourceText: sourceText,
            sourceRevision: sourceRevision, placementRevision: placementRevision, settings: nextReplySettings,
            localLessons: lessons, companion: activeQiMon?.character, localProfile: personalContext?.assistantSnapshot,
            localControl: reading.control, localReading: reading.plan)
        return HamptonReasonsAssistant.fitsMandatoryReasoningInput(request)
    }

    func share(text: String, name: String) {
        guard text.utf8.count <= 100_000 else {
            status = "Choose a text file no larger than 100 KB. The current source is unchanged."
            return
        }
        invalidateTextSelection(reason: "Shared source changed.")
        cancelWork(reason: "Shared source changed.")
        clearSessionContext()
        desktopInterest.cancel()
        desktopInterestSource = nil; desktopInterestExternalDigest = nil
        wikiOSTask = nil
        wikiOSExchangeMessage = nil
        sharedText = text
        openedWorkingCopyDigest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        exportedWorkingCopyDigest = nil
        workingCopyIsPasted = false
        sourceName = name
        importedSourceURL = nil
        workingCopyUndo = nil
        requestsRevision = false
        workingCopyNotice = "Working copy opened · select a passage to begin."
        sourceRevision &+= 1
        compareResults = [:]
        reply = "This copy is shared locally. Send a question using your chosen assistant route."
        status = "Shared locally · no content sent"
        record("Opened \(name) locally")
    }

    func beginDesktopInterest() {
        guard !isShuttingDown else { return }
        desktopInterest.begin()
        showCompanion()
        onBeginDesktopInterest?()
    }

    @discardableResult
    func useDesktopInterestCapture() -> Bool {
        guard !isShuttingDown, desktopInterest.phase == .review,
              let capture = desktopInterest.capture else { return false }
        guard confirmDiscardWorkingCopy(before: "using the window snapshot", discardTitle: "Use snapshot instead"),
              desktopInterest.capture == capture, desktopInterest.phase == .review else { return false }
        guard !capture.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              capture.text.utf8.count <= 60_000 else { return false }
        let name = "Window snapshot · \(capture.target.appName) · \(capture.target.title)"
        share(text: capture.text, name: name)
        desktopInterestSource = DesktopInterestSource(appName: capture.target.appName, title: capture.target.title,
            method: capture.method, capturedAt: capture.capturedAt, digest: LessonSource.digest(of: capture.text))
        workingCopyNotice = "Local snapshot · edits affect this copy only. Select a passage to work on."
        status = "Window text shared locally · no model call made"
        open(.context)
        return true
    }

    /// User-facing retention check; programmatic sharing and test helpers keep
    /// their existing deterministic behavior through stopSharing().
    func requestStopSharing() {
        guard confirmDiscardWorkingCopy(before: "stopping sharing", discardTitle: "Discard edits and stop sharing") else { return }
        stopSharing()
    }

    func confirmQuitWithWorkingCopy() -> Bool {
        confirmDiscardWorkingCopy(before: "quitting", discardTitle: "Quit without exporting")
    }

    private func confirmDiscardWorkingCopy(before action: String, discardTitle: String) -> Bool {
        guard hasUnexportedWorkingCopy else { return true }
        let reviewedRevision = sourceRevision
        let reviewedSourceName = sourceName
        let reviewedBytes = Data(sharedText.utf8)
        let alert = NSAlert()
        alert.messageText = "Keep this draft before \(action)?"
        alert.informativeText = workingCopyIsPasted
            ? "This pasted copy has not been exported. Keep working to save a draft, or discard this session copy."
            : "Your working copy has edits that have not been exported. Keep working to export a separate draft, or discard these session edits. The original file stays unchanged."
        alert.alertStyle = .warning
        let keep = alert.addButton(withTitle: "Keep working")
        keep.keyEquivalent = "\r"
        let discard = alert.addButton(withTitle: discardTitle)
        discard.hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return false }
        // A modal alert can service callbacks. Discard approval belongs only to
        // the exact working copy reviewed when this alert was presented.
        guard sourceRevision == reviewedRevision, sourceName == reviewedSourceName,
              Data(sharedText.utf8) == reviewedBytes else {
            workingCopyNotice = "The working copy changed while this choice was open. Your latest copy is unchanged; review it before discarding."
            return false
        }
        return true
    }

    func stopSharing() {
        desktopInterest.cancel()
        desktopInterestSource = nil; desktopInterestExternalDigest = nil
        invalidateTextSelection(reason: "Sharing stopped.")
        cancelWork(reason: "Sharing stopped.")
        clearSessionContext()
        wikiOSTask = nil
        wikiOSExchangeMessage = nil
        sharedText = ""; sourceName = nil; sourceRevision &+= 1
        openedWorkingCopyDigest = nil; exportedWorkingCopyDigest = nil
        workingCopyIsPasted = false
        importedSourceURL = nil; workingCopyUndo = nil; requestsRevision = false
        workingCopyNotice = "Select a text document to begin."
        compareResults = [:]
        reply = "Nothing is shared."
        status = "Shared context cleared"
    }

    func selectText(range: NSRange, sourceRevision: UInt64) {
        // Late native callbacks from a replaced document cannot clear or replace a newer selection.
        guard sourceName != nil, sourceRevision == self.sourceRevision else { return }
        if range.length == 0 {
            guard range.location >= 0, range.location <= sharedText.utf16.count else { return }
            clearTextSelection(); return
        }
        guard let selection = DocumentSelection(range: range, text: sharedText, sourceRevision: sourceRevision),
              selection != textSelection else { return }
        invalidateTextSelection(reason: "Selected passage changed.")
        cancelWork(reason: "Selected passage changed.")
        textSelection = selection
        selectionRevision &+= 1
        workingCopyNotice = "Passage selected · ask about it or prepare a revision."
        status = "Passage selected · nothing sent"
    }

    func clearTextSelection() { invalidateTextSelection(reason: "Passage selection cleared.") }

    /// Layout is a spatial dependency, not a change to the selected source bytes.
    /// A history card, resize or scroll must retire old pointing coordinates
    /// without cancelling an ordinary document question or reviewed revision.
    func invalidateDocumentGeometry(reason: String) {
        stopKinLightPreview()
        stopHarmonyTheme()
        invalidatePlacementPreview(reason: reason)
        guard compareResults.values.contains(where: { $0.state != .cancelled && $0.receipt?.pointing != nil }) else { return }
        clearLocalConversation()
        cancelWork(reason: reason)
    }

    func invalidateTextSelection(reason: String) {
        clearLocalConversation()
        invalidatePlacementPreview(reason: reason)
        guard textSelection != nil || replySourceSelection != nil else { return }
        let hadScopedReply = replySourceSelection != nil
        textSelection = nil
        replySourceSelection = nil
        selectionRevision &+= 1
        cancelWork(reason: reason)
        if hadScopedReply {
            hamptonSnapshot.proposal = nil
            compareResults = [:]
            reply = "The passage reference changed. Select text again to ask about it."
        }
        status = reason
    }

    func askAboutSelection() {
        guard let selection = textSelection, selection.matches(text: sharedText, sourceRevision: sourceRevision) else {
            status = "Select a passage in the document first."; return
        }
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt = "Explain the selected passage."
        }
        status = "Question ready · press Send when you are ready"
    }

    func preparePassageExplanation() {
        requestsRevision = false
        prompt = "Explain the selected passage."
        askAboutSelection()
    }

    var canPointAndExplainSelection: Bool {
        !isShuttingDown && !isWorking && isVisible && preferences.equipment.supportsPointing
            && textSelection?.matches(text: sharedText, sourceRevision: sourceRevision) == true
            && preparedDocumentProcedure == nil
            && canBeginReply(selection: .select(question: pointedExplanationQuestion,
                hasPreparedProcedure: preparedDocumentProcedure != nil, hasPointing: true), hasPointing: true)
            && pointedExplanationQuestion.utf8.count <= 16_000
    }

    private var pointedExplanationQuestion: String {
        let instruction = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = "Explain the selected passage."
        return instruction.isEmpty || instruction == base ? base
            : base + "\n\nMy instructions for this explanation:\n" + instruction
    }

    /// One explicit send; plain pointing, practice and Preview keep their
    /// local-only behavior. The composer's unsent draft is never overwritten.
    @discardableResult
    func pointAndExplainSelection() -> Bool {
        guard canPointAndExplainSelection else {
            status = "To point and explain, equip the staff, select a passage and connect the chosen assistant. Nothing sent."
            return false
        }
        let ticket = contextTicket()
        let now = monotonicTime()
        guard let selection = textSelection,
              let geometry = onObserveSelectedPassage?(), geometry.selection == selection,
              let environment = onObserveSpatialEnvironment?(),
              let display = environment.displays.first(where: { $0.id == geometry.screenID }),
              display.frame == geometry.screenFrame,
              let candidate = SpatialPlacementPlanner.propose(geometry: geometry,
                  companionFrame: environment.companionFrame, visibleDisplay: display.visibleFrame),
              isCurrent(ticket), now.isFinite, now >= 0 else {
            status = "Keep the whole selected passage visible and ARCHi shown, then try again. Nothing sent."
            return false
        }
        let pointing = AssistantPointingSnapshot(geometry: geometry, environment: environment,
            candidate: candidate, gesture: effectiveFocusGesture)
        return submit(question: pointedExplanationQuestion, pointing: pointing)
    }

    private func isCurrentPointing(_ pointing: AssistantPointingSnapshot) -> Bool {
        isVisible && preferences.equipment.supportsPointing
            && textSelection == pointing.geometry.selection
            && pointing.geometry.selection.matches(text: sharedText, sourceRevision: sourceRevision)
            && onObserveSelectedPassage?() == pointing.geometry
            && onObserveSpatialEnvironment?() == pointing.environment
    }

    func preparePassageRevision(shorten: Bool = false) {
        guard let textSelection, textSelection.matches(text: sharedText, sourceRevision: sourceRevision) else {
            status = "Select a passage in the document first."; return
        }
        clearPreparedDocumentProcedure()
        requestsRevision = true
        documentRequirements.mustBeShorter = shorten
        prompt = shorten ? "Shorten the selected passage while preserving its meaning."
            : "Make the selected passage clearer while preserving its meaning."
        status = "Revision prepared · describe what you want, then Send"
    }

    func documentProcedureUnavailable(_ use: DocumentProcedureUse) -> String? {
        if profileRecoveryBlock != nil || !documentWork.isCurrentOnDisk || documentProcedures.loadError != nil {
            return "Procedure history needs recovery before reuse."
        }
        guard let procedure = documentProcedures.procedure(matching: use) else {
            return "This exact procedure version is unavailable."
        }
        if let reason = documentProcedures.availability(of: procedure, records: documentWork.records,
            knowledgeIsCurrent: { knowledgeDependenciesAreCurrent([$0]) }) { return reason }
        // Preserve the originating local lesson dependencies through procedure
        // chaining; withdrawing a lesson cannot smuggle it back through a method.
        var current: DocumentProcedure? = procedure
        var visited = Set<DocumentProcedureUse>()
        while let item = current {
            guard visited.insert(item.binding).inserted else { return "The procedure’s source history is cyclic." }
            if item.knowledgeOrigin != nil && item.originRecordID.isEmpty { break }
            guard let origin = documentWork.records.first(where: { $0.id == item.originRecordID }) else {
                return "The procedure’s source history is unavailable."
            }
            if let reason = documentMethodDependencyIssue(origin) { return reason }
            current = origin.procedureUse.flatMap { documentProcedures.procedure(matching: $0) }
        }
        return nil
    }

    /// Availability follows every supplied lesson version. A model citation is
    /// useful for explicit credit, but cannot enumerate all possible influence.
    func documentMethodDependencyIssue(_ record: DocumentWorkRecord) -> String? {
        guard let learning = record.learning, learning.isValid, learning.hasCompleteLessonProvenance else {
            return "This earlier result did not retain all supplied lesson dependencies. Complete and review a fresh edit before keeping or reusing a method."
        }
        if !learning.dependencyLessons.isEmpty {
            guard let disk = try? NativePreferencePersistence.read(preferenceURL), disk.baseline == preferenceBaseline else {
                return "Saved lessons changed outside this session. Reopen ARCHi before using this method."
            }
        }
        for lesson in learning.dependencyLessons {
            guard let supporting = keptLessons.first(where: {
                let snapshot = LessonSnapshot(lesson: $0)
                return lesson.matches(snapshot: snapshot) && currentKeptLesson(matching: snapshot) != nil
            }) else { return "A lesson supplied to this method’s source result changed, was withdrawn, or expired." }
            guard supporting.taskScope == nil || supporting.taskScope == .passageRevision else {
                return "A supporting lesson no longer applies to passage revision."
            }
            guard supporting.source == nil || supporting.source == currentLessonSource else {
                return "A supporting lesson applies only to its original shared copy."
            }
        }
        return nil
    }

    var canKeepDocumentProcedure: Bool {
        !isShuttingDown && !isWorking && profileRecoveryBlock == nil
            && pendingDocumentReceipt == nil && documentWork.isCurrentOnDisk
    }

    @discardableResult
    func keepDocumentProcedure(recordID: String, title: String, instruction: String) -> Bool {
        guard canKeepDocumentProcedure, documentWork.isCurrentOnDisk, pendingDocumentReceipt == nil,
              let record = documentWork.records.first(where: { $0.id == recordID }),
              canReviewDocument(record), record.state == .applied, record.feedback?.verdict == .helpful,
              record.procedureUse.map({ documentProcedureUnavailable($0) == nil }) ?? true else { return false }
        if let reason = documentMethodDependencyIssue(record) {
            documentWorkMessage = reason
            return false
        }
        do {
            _ = try documentProcedures.keep(from: record, title: title, instruction: instruction, records: documentWork.records,
                knowledgeIsCurrent: { knowledgeDependenciesAreCurrent([$0]) })
            documentWorkMessage = "Procedure kept on this Mac. Select it for a matching passage; every result still needs review."
            return true
        } catch {
            documentWorkMessage = "Procedure was not kept: \(error.localizedDescription)"
            return false
        }
    }

    func withdrawDocumentProcedure(_ use: DocumentProcedureUse) {
        guard !isShuttingDown, profileRecoveryBlock == nil else { return }
        do {
            try documentProcedures.withdraw(binding: use)
            documentWorkMessage = "Procedure withdrawn. Its history is retained; future reuse is disabled."
        } catch { documentWorkMessage = "Procedure withdrawal was not saved: \(error.localizedDescription)" }
    }

    /// A revision retains a named helpful result and checks its lesson/ancestor
    /// dependencies with the same live owners used for ordinary procedure reuse.
    func revisionSourceRecords(for use: DocumentProcedureUse) -> [DocumentWorkRecord] {
        guard canKeepDocumentProcedure, pendingDocumentReceipt == nil, documentWork.isCurrentOnDisk,
              documentProcedures.loadError == nil,
              let previous = documentProcedures.procedure(matching: use) else { return [] }
        let previousUnavailable = documentProcedureUnavailable(use) != nil
        return documentWork.records.filter { record in
            guard canReviewDocument(record),
                  documentProcedures.canSupportRevision(of: use, with: record, records: documentWork.records,
                    knowledgeIsCurrent: { knowledgeDependenciesAreCurrent([$0]) }),
                  record.procedureUse.map({ documentProcedureUnavailable($0) == nil }) ?? true else { return false }
            if previousUnavailable && (record.id == previous.originRecordID || record.createdAt <= previous.createdAt) { return false }
            return documentMethodDependencyIssue(record) == nil
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func reviseDocumentProcedure(_ use: DocumentProcedureUse, title: String, instruction: String,
                                 changeNote: String, recordID: String) -> Bool {
        guard let record = revisionSourceRecords(for: use).first(where: { $0.id == recordID }) else {
            documentWorkMessage = "Choose a current helpful applied result. Complete and review corrective work before revising a blocked method."
            return false
        }
        do {
            let revision = try documentProcedures.revise(binding: use, title: title, instruction: instruction,
                changeNote: changeNote, from: record, records: documentWork.records,
                knowledgeIsCurrent: { knowledgeDependenciesAreCurrent([$0]) })
            documentWorkMessage = "Version \(revision.revision) saved as a candidate. Earlier versions and their outcomes remain in history. Choose Use when you want to try it."
            return true
        } catch {
            documentWorkMessage = "New version was not saved: \(error.localizedDescription)"
            return false
        }
    }

    func canPrepareDocumentProcedure(_ procedure: DocumentProcedure) -> Bool {
        !isShuttingDown && !isWorking && requestsRevision && procedure.matches(requirements: documentRequirements)
            && documentProcedures.latestProcedures.contains(procedure)
            && textSelection?.matches(text: sharedText, sourceRevision: sourceRevision) == true
            && documentProcedureUnavailable(procedure.binding) == nil
    }

    @discardableResult
    func prepareDocumentProcedure(_ use: DocumentProcedureUse) -> Bool {
        guard let procedure = documentProcedures.procedure(matching: use), canPrepareDocumentProcedure(procedure) else {
            documentWorkMessage = "Select a passage in Revise mode with the procedure’s requirements before using it."
            return false
        }
        preparedDocumentProcedure = use
        preparedProcedureSelection = textSelection
        preparedProcedureSourceDigest = WorkingCopyEditReceipt.digest(sharedText)
        prompt = procedure.instruction
        status = "Procedure prepared · review its instruction, then Send"
        return true
    }

    func preparedProcedureMatchesCurrentDraft(question: String) -> Bool {
        guard let use = preparedDocumentProcedure, let procedure = documentProcedures.procedure(matching: use) else { return false }
        return requestsRevision && question.utf8.elementsEqual(procedure.instruction.utf8)
            && procedure.matches(requirements: documentRequirements)
            && textSelection == preparedProcedureSelection
            && preparedProcedureSourceDigest == WorkingCopyEditReceipt.digest(sharedText)
    }

    func clearPreparedDocumentProcedure() {
        preparedDocumentProcedure = nil
        preparedProcedureSelection = nil
        preparedProcedureSourceDigest = nil
    }

    var canUndoWorkingCopyEdit: Bool {
        guard let undo = workingCopyUndo, undo.canUndo(text: sharedText, revision: sourceRevision),
              let id = undo.documentWorkID else { return false }
        return documentWork.records.contains { $0.id == id && $0.state == .applied }
    }

    /// Follow-through belongs to the exact edit still visible in this session,
    /// never whichever historical record happens to sort first. Read-only;
    /// opening the card cannot keep a method, rate work or restore a document.
    var currentDocumentOutcome: DocumentWorkRecord? {
        guard profileRecoveryBlock == nil, pendingDocumentReceipt == nil,
              documentWork.isCurrentOnDisk,
              let edit = workingCopyUndo, edit.canUndo(text: sharedText, revision: sourceRevision),
              let id = edit.documentWorkID,
              let record = documentWork.records.first(where: { $0.id == id }),
              record.state == .applied, canReviewDocument(record),
              record.afterRevision == sourceRevision,
              record.actualAfterDigest == edit.afterDigest else { return nil }
        return record
    }

    func documentVerification(_ proposal: PassageRevisionProposal) -> DocumentWorkVerification {
        let checked = DocumentWorkCapability.verify(proposal: proposal, text: sharedText,
            sourceRevision: sourceRevision, requirements: proposal.target.requirements)
        guard let use = documentWork.records.first(where: { $0.targetID == proposal.target.id })?.procedureUse,
              let reason = documentProcedureUnavailable(use) else { return checked }
        return DocumentWorkVerification(checks: checked.checks + [
            .init(id: "procedure", title: reason, passed: false)
        ], predictedDigest: nil)
    }

    func documentRecord(requestID: String, provider: AssistantProvider) -> DocumentWorkRecord? {
        documentWork.records.first { $0.id == requestID + "-" + provider.rawValue }
    }

    func canApplyDocumentRevision(provider: AssistantProvider, proposal: PassageRevisionProposal) -> Bool {
        guard let lane = compareResults[provider], lane.state == .complete,
              let receipt = lane.receipt, isCurrentReplyContext(receipt),
              textSelection == proposal.target.selection, documentWork.loadError == nil,
              let record = documentRecord(requestID: receipt.requestID, provider: provider),
              record.targetID == proposal.target.id, record.state == .ready else { return false }
        return documentVerification(proposal).canApply
    }

    private func beginDocumentWork(requestID: String, provider: AssistantProvider, target: RevisionTarget,
                                   control: HamptonQ2EDecision? = nil) throws {
        try retryDocumentReceipt()
        guard documentWork.isCurrentOnDisk, control?.isValid ?? true,
              control == nil || (control?.contextID == target.sourceDigest && control?.lane != .stop) else {
            throw DocumentWorkJournalError.changed
        }
        // Connection can suspend after Send. A changed review or method must
        // not dispatch the previously captured approach. Same-request provider
        // lanes are not prior outcomes and cannot invalidate one another.
        if let control, [HamptonQ2EController.version, HamptonQ2EController.numericalVersion].contains(control.version) {
            guard control == makeDocumentQ2EDecision(excludingRequestID: requestID) else {
                throw DocumentWorkJournalError.changed
            }
        }
        let use = documentProcedureRequests[requestID]
        if let use, let reason = documentProcedureUnavailable(use) {
            throw DocumentWorkJournalError.invalid(reason)
        }
        let now = wallClock()
        try documentWork.save(DocumentWorkRecord(id: requestID + "-" + provider.rawValue,
            requestID: requestID, provider: provider.rawValue, targetID: target.id,
            sourceDigest: target.sourceDigest, sourceRevision: target.selection.sourceRevision,
            selectionStart: target.selection.range.location, selectionLength: target.selection.range.length,
            mustBeShorter: target.requirements.mustBeShorter,
            preserveNumbersAndLinks: target.requirements.preserveNumbersAndLinks,
            createdAt: now, updatedAt: now, state: .proposing,
            detail: "Exact working-copy passage captured. No edit applied.", procedureUse: use,
            q2eDecision: control))
        documentWorkMessage = nil
    }

    private func completeDocumentProposal(requestID: String, provider: AssistantProvider, proposal: PassageRevisionProposal) throws {
        guard var record = documentRecord(requestID: requestID, provider: provider), record.state == .proposing else {
            throw WorkingCopyRevisionError.staleTarget
        }
        let originalChecks = documentVerification(proposal)
        let restoration = provider == .qwen && originalChecks.checks.filter({ !$0.passed }).map(\.id) == ["links"]
            ? DocumentURLBoundaryPreservation.restore(proposal, text: sharedText, sourceRevision: sourceRevision) : nil
        let effective = restoration?.proposal ?? proposal
        let checked = documentVerification(effective)
        record.proposedDigest = WorkingCopyEditReceipt.digest(effective.replacement)
        record.urlBoundaryRestoration = restoration?.restoration
        record.expectedAfterDigest = checked.predictedDigest
        record.checks = checked.checks.map { .init(id: $0.id, title: $0.title, passed: $0.passed) }
        if let receipt = compareResults[provider]?.receipt {
            record.learning = DocumentWorkLearningContext(requestBinding: EvolutionRequestBinding(receipt: receipt),
                usedLessons: provider == .qwen ? receipt.localLessons.filter {
                    receipt.usedLessonIDs.contains($0.modelID)
                }.compactMap(EvolutionLessonUse.make(snapshot:)) : [],
                suppliedLessons: provider == .qwen ? receipt.localLessons.compactMap(EvolutionLessonUse.make(snapshot:)) : [])
        }
        record.state = checked.canApply ? .ready : .blocked
        record.updatedAt = wallClock()
        record.detail = checked.canApply ? (restoration == nil
            ? "Mechanical checks passed. Review meaning and facts before Apply."
            : "ARCHi restored the source's spacing after one link. Mechanical checks passed; review before Apply.")
            : "No edit applied. The proposal needs clarification or fails a requested mechanical constraint."
        try documentWork.save(record)
        if let restoration {
            compareResults[provider]?.originalRevision = proposal
            compareResults[provider]?.urlBoundaryRestoration = restoration.restoration
            compareResults[provider]?.revision = effective
        }
    }

    func canReviewDocument(_ record: DocumentWorkRecord) -> Bool {
        !isShuttingDown && documentWork.isCurrentOnDisk
            && documentReviewEvidenceIsCurrent(record)
    }

    /// Read-only recovery of pending reviews across working copies and restarts.
    /// Check the journal once for this bounded projection; action owners still
    /// check it again when the user submits an individual review.
    var documentReviewQueue: DocumentReviewQueue? {
        guard !isShuttingDown, !isWorking, profileRecoveryBlock == nil,
              pendingDocumentReceipt == nil, documentWork.isCurrentOnDisk else { return nil }
        let reviewable = Set(documentWork.records.filter(documentReviewEvidenceIsCurrent).map(\.id))
        return DocumentReviewQueue(records: documentWork.records, historyIsCurrent: true,
            reviewableRecordIDs: reviewable, currentOutcomeID: currentDocumentOutcome?.id)
    }

    private func documentReviewEvidenceIsCurrent(_ record: DocumentWorkRecord) -> Bool {
        documentWork.records.first(where: { $0.id == record.id }) == record
            && [.applied, .undone].contains(record.state)
            && !(record.procedureUse.map { documentProcedureKnowledgeUnavailable(use: $0) } ?? false)
            && record.learning?.requestBinding.isValid == true && UUID(uuidString: record.requestID) != nil
            && record.expectedAfterDigest != nil && record.expectedAfterDigest == record.actualAfterDigest
            && record.afterRevision != nil && record.checks.allSatisfy(\.passed) && !record.checks.isEmpty
    }

    func canManageDocumentFeedback(_ record: DocumentWorkRecord) -> Bool {
        !isShuttingDown && documentWork.isCurrentOnDisk
            && documentWork.records.first(where: { $0.id == record.id }) == record && record.feedback != nil
            && [.applied, .undone, .failed].contains(record.state)
    }

    @discardableResult
    func reviewDocument(id: String, verdict: DocumentWorkFeedback.Verdict) -> Bool {
        guard var record = documentWork.records.first(where: { $0.id == id }),
              canReviewDocument(record) || (verdict == .withdrawn && canManageDocumentFeedback(record)),
              pendingDocumentReceipt == nil else { return false }
        do {
            if record.feedback?.verdict != verdict {
                guard (record.feedback?.revision ?? 0) < UInt64.max else { return false }
                record.feedback = DocumentWorkFeedback(id: UUID().uuidString,
                    revision: (record.feedback?.revision ?? 0) + 1, verdict: verdict, recordedAt: wallClock())
                record.feedbackUsageSyncedID = nil
                if record.procedureUse != nil, verdict != .helpful { record.procedureUseRejected = true }
                record.updatedAt = wallClock()
                try documentWork.save(record)
            }
            syncDocumentFeedback(id: id)
            return true
        } catch {
            documentWorkMessage = "Your review was not saved: \(error.localizedDescription)"
            return false
        }
    }

    func syncDocumentFeedback(id: String) {
        guard var record = documentWork.records.first(where: { $0.id == id }), canManageDocumentFeedback(record),
              let feedback = record.feedback else { return }
        do {
            // Save the review first, then project only that exact latest event.
            // Retrying after either write fails uses the same event identifier.
            try tokenSteward.recordUserFeedback(requestID: record.requestID,
                evidenceID: "document-review-" + feedback.id, useful: feedback.verdict == .helpful)
            if record.feedbackUsageSyncedID != feedback.id {
                record.feedbackUsageSyncedID = feedback.id
                record.updatedAt = wallClock()
                try documentWork.save(record)
            }
            documentWorkMessage = "Your review is saved on this Mac and reflected in Usage. Learning and kept lessons have separate review controls."
        } catch {
            documentWorkMessage = "Your document review is saved; Usage still needs reconciliation: \(error.localizedDescription)"
        }
    }

    func documentFeedbackUsageCurrent(_ record: DocumentWorkRecord) -> Bool {
        guard let feedback = record.feedback, record.feedbackUsageSyncedID == feedback.id,
              tokenSteward.loadError == nil,
              let outcome = tokenSteward.tasks.first(where: { $0.id == record.requestID })?.outcomes.last(where: { $0.kind == .userUseful }) else { return false }
        return outcome.evidenceID == "document-review-" + feedback.id && outcome.value == (feedback.verdict == .helpful)
    }

    func documentReviewLessons(_ record: DocumentWorkRecord) -> [LessonSnapshot] {
        guard canReviewDocument(record), record.provider == AssistantProvider.qwen.rawValue else { return [] }
        return keptLessons.map(LessonSnapshot.init(lesson:)).filter { snapshot in
            currentKeptLesson(matching: snapshot) != nil
                && record.learning?.usedLessons.contains(where: { $0.matches(snapshot: snapshot) }) == true
        }
    }

    @discardableResult
    func addDocumentToLearningReview(id: String, lesson: LessonSnapshot? = nil) -> Bool {
        guard let record = documentWork.records.first(where: { $0.id == id }), canReviewDocument(record),
              record.feedback?.verdict == .helpful, let learning = record.learning,
              let requestID = UUID(uuidString: record.requestID),
              lesson == nil || documentReviewLessons(record).contains(lesson!) else { return false }
        let admitted = evolution.markDocumentWorkUseful(requestID: requestID, sourceDigest: record.sourceDigest,
            requestBinding: learning.requestBinding, confirmedLesson: lesson.flatMap(EvolutionLessonUse.make(snapshot:)))
        documentWorkMessage = admitted ? "Added to this session’s learning review. Use Save evolution to retain it."
            : "The learning review could not accept this outcome: " + evolution.status
        return admitted
    }

    func beginDocumentCorrection(id: String) {
        guard let record = documentWork.records.first(where: { $0.id == id }), canReviewDocument(record),
              let binding = record.learning?.requestBinding else { return }
        guard lessonDraft == nil else {
            lessonMessage = "Your unfinished lesson is still here. Keep or discard it before starting a new document correction."
            open(.memory)
            return
        }
        guard reviewDocument(id: id, verdict: .needsCorrection) else { return }
        lessonDraft = LessonCorrectionDraft(expectedRevision: lessonRevision, prior: nil,
            origin: LessonOrigin(requestID: record.requestID, inputDigest: binding.inputDigest))
        lessonMessage = "Write what ARCHi should do differently and when to use it. Nothing becomes a lesson until you Keep it."
        open(.memory)
    }

    func withdrawLearningReview(requestID: UUID) {
        if let document = documentWork.records.first(where: { UUID(uuidString: $0.requestID) == requestID && $0.feedback != nil }) {
            guard reviewDocument(id: document.id, verdict: .withdrawn) else { return }
        }
        evolution.withdrawUseful(requestID: requestID)
    }

    private func retireDocumentWork(requestID: String, provider: AssistantProvider, failed: Bool) {
        guard var record = documentRecord(requestID: requestID, provider: provider),
              [.proposing, .ready].contains(record.state) else { return }
        record.state = failed ? .failed : .cancelled
        record.updatedAt = wallClock()
        record.detail = failed ? "Request did not finish. No edit was applied." : "Request retired. No edit was applied."
        do { try documentWork.save(record) }
        catch { documentWorkMessage = "Document history could not be updated: \(error.localizedDescription)" }
    }

    /// The pending receipt is saved before mutation. No await separates source
    /// verification, replacement and the check of the actual resulting bytes.
    func applyPassageRevision(provider: AssistantProvider, targetID: String) {
        guard let lane = compareResults[provider], let proposal = lane.revision,
              proposal.target.id == targetID, canApplyDocumentRevision(provider: provider, proposal: proposal),
              let receipt = lane.receipt,
              var record = documentRecord(requestID: receipt.requestID, provider: provider) else {
            workingCopyNotice = "This revision is stale or a required check failed. Review the checks and request a new revision."; return
        }
        let before = sharedText
        let after: String
        do {
            after = try WorkingCopyEditReceipt.applying(proposal: proposal, to: before, sourceRevision: sourceRevision)
            guard WorkingCopyEditReceipt.digest(after) == record.expectedAfterDigest else { throw WorkingCopyRevisionError.staleTarget }
            record.state = .applying; record.updatedAt = wallClock()
            record.detail = "Apply requested. Awaiting actual working-copy verification."
            try documentWork.save(record)
        } catch {
            workingCopyNotice = "Could not prepare a retained Apply receipt. Nothing changed. \(error.localizedDescription)"; return
        }
        invalidateTextSelection(reason: "A reviewed revision was applied.")
        cancelWork(reason: "Working copy changed; earlier proposals cleared.")
        clearSessionContext()
        sharedText = after
        sourceRevision &+= 1
        compareResults = [:]
        workingCopyUndo = WorkingCopyEditReceipt(before: before, afterDigest: WorkingCopyEditReceipt.digest(after),
            afterRevision: sourceRevision, documentWorkID: record.id)
        requestsRevision = false
        record.actualAfterDigest = WorkingCopyEditReceipt.digest(sharedText)
        record.afterRevision = sourceRevision
        record.updatedAt = wallClock()
        let verified = record.actualAfterDigest == record.expectedAfterDigest
            && workingCopyUndo?.canUndo(text: sharedText, revision: sourceRevision) == true
        record.state = verified ? .applied : .failed
        record.detail = verified ? "Applied after review; actual bytes match the predicted working copy. Meaning and facts are user-reviewed. Original file unchanged."
            : "Apply outcome could not be verified. Inspect the working copy."
        do { try documentWork.save(record); documentWorkMessage = nil; pendingDocumentReceipt = nil }
        catch {
            pendingDocumentReceipt = record
            documentWorkMessage = "The copy changed, but its completed receipt could not be saved. Retry saving the receipt to enable Undo."
        }
        workingCopyNotice = verified && pendingDocumentReceipt == nil
            ? "Applied to working copy · Undo available. Export to keep a separate draft."
            : documentWorkMessage ?? record.detail
        reply = proposal.explanation
        status = workingCopyNotice
        self.record("Applied reviewed passage revision \(targetID) to working copy revision \(sourceRevision)")
    }

    private func retryDocumentReceipt() throws {
        guard let pendingDocumentReceipt else { return }
        try documentWork.save(pendingDocumentReceipt)
        self.pendingDocumentReceipt = nil
        documentWorkMessage = nil
    }

    func retryDocumentHistorySave() {
        do {
            try retryDocumentReceipt()
            workingCopyNotice = canUndoWorkingCopyEdit ? "Receipt saved · Undo is available." : "Document receipt saved."
        } catch { documentWorkMessage = "Receipt remains pending: \(error.localizedDescription)" }
    }

    func dismissPassageRevision(provider: AssistantProvider) {
        guard let lane = compareResults[provider], lane.state == .complete else { return }
        if let receipt = lane.receipt, var record = documentRecord(requestID: receipt.requestID, provider: provider) {
            record.state = .dismissed; record.updatedAt = wallClock()
            record.detail = "Proposal dismissed. Working copy unchanged."
            do { try documentWork.save(record) }
            catch { documentWorkMessage = "Dismissal was not saved: \(error.localizedDescription)" }
        }
        compareResults[provider]?.revision = nil
        compareResults[provider]?.status = "Revision dismissed · copy unchanged"
        workingCopyNotice = "Revision dismissed · your working copy is unchanged."
    }

    func undoWorkingCopyEdit() {
        guard let undo = workingCopyUndo, undo.canUndo(text: sharedText, revision: sourceRevision),
              let id = undo.documentWorkID, var record = documentWork.records.first(where: { $0.id == id }),
              record.state == .applied else {
            workingCopyNotice = "That Undo is unavailable or belongs to an earlier copy."; return
        }
        record.state = .undoing; record.updatedAt = wallClock()
        if record.procedureUse != nil { record.procedureUseRejected = true }
        record.detail = "Undo requested. Awaiting verification of the original working-copy bytes."
        do { try documentWork.save(record) }
        catch { workingCopyNotice = "Could not prepare an Undo receipt. Nothing changed."; return }
        invalidateTextSelection(reason: "Working-copy revision undone.")
        cancelWork(reason: "Working-copy revision undone.")
        clearSessionContext()
        sharedText = undo.before
        sourceRevision &+= 1
        compareResults = [:]; workingCopyUndo = nil; requestsRevision = false
        let restored = WorkingCopyEditReceipt.digest(sharedText) == record.sourceDigest
        record.state = restored ? .undone : .failed
        record.updatedAt = wallClock()
        record.detail = restored ? "Undo restored the exact original working-copy bytes. Apply digests remain as history."
            : "Undo outcome unverified. Inspect the working copy."
        do { try documentWork.save(record); documentWorkMessage = nil; pendingDocumentReceipt = nil }
        catch {
            pendingDocumentReceipt = record
            documentWorkMessage = "The copy was restored, but the completed Undo receipt could not be saved. Retry saving the receipt."
        }
        workingCopyNotice = record.detail; status = workingCopyNotice
        self.record("Undid working-copy edit; source revision \(sourceRevision)")
    }

    func exportWorkingCopy() {
        guard sourceName != nil else { return }
        let revision = sourceRevision
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.utf8PlainText]
        let stem = ((sourceName ?? "ARCHi") as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(stem)-draft.txt"
        panel.message = "Save a separate UTF-8 draft of the working copy."
        guard panel.runModal() == .OK, let url = panel.url else {
            workingCopyNotice = "Export cancelled · your working copy is unchanged."; return
        }
        _ = exportWorkingCopy(to: url, expectedRevision: revision)
    }

    @discardableResult
    func exportWorkingCopy(to url: URL, expectedRevision: UInt64) -> Bool {
        guard sourceName != nil, sourceRevision == expectedRevision,
              url.isFileURL, sharedText.utf8.count <= 100_000 else {
            workingCopyNotice = "The copy changed while choosing a destination. Export the current copy again."; return false
        }
        let destination = url.resolvingSymlinksInPath().standardizedFileURL
        guard destination != importedSourceURL && !isImportedFile(destination) else {
            workingCopyNotice = "Choose a separate draft filename to preserve the imported original."; return false
        }
        let bytes = Data(sharedText.utf8)
        do {
            try bytes.write(to: url, options: .atomic)
            guard try Data(contentsOf: url) == bytes else {
                workingCopyNotice = "The exported file could not be verified. Your working copy is retained."; return false
            }
            exportedWorkingCopyDigest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            workingCopyNotice = "Exported \(url.lastPathComponent) · saved bytes verified."
            status = workingCopyNotice
            return true
        } catch {
            workingCopyNotice = "The draft could not be exported. Your working copy is retained."
            return false
        }
    }

    private func isImportedFile(_ destination: URL) -> Bool {
        guard let importedSourceURL,
              let original = try? FileManager.default.attributesOfItem(atPath: importedSourceURL.path),
              let candidate = try? FileManager.default.attributesOfItem(atPath: destination.path),
              let originalDevice = original[.systemNumber] as? NSNumber,
              let originalInode = original[.systemFileNumber] as? NSNumber,
              let candidateDevice = candidate[.systemNumber] as? NSNumber,
              let candidateInode = candidate[.systemFileNumber] as? NSNumber else { return false }
        // Covers case aliases and hard links in addition to resolved URL equality.
        return originalDevice == candidateDevice && originalInode == candidateInode
    }

    func cancelWork(reason: String = "Stopped.") {
        voiceInput.cancel()
        stopKinLightPreview()
        stopHarmonyTheme()
        invalidatePlacementPreview(reason: reason)
        let wasWorking = isWorking
        let hadDerivedReply = !compareResults.isEmpty || hamptonSnapshot.proposal != nil || activeARCAnswer != nil
        workGeneration &+= 1
        cancelActiveARC(reason: reason, keepAnswer: reason == "Stopped.")
        arc3.stop(reason: reason)
        if reason != "Stopped." { showsARC3Reply = false }
        for provider in Array(replyOwners.keys) { cancelLane(provider, reason: reason) }
        // Completed lanes are also bound to the superseded request ticket.
        for provider in Array(compareResults.keys) {
            setLane(provider, text: "", status: reason, state: .cancelled)
        }
        if knowledgeMethodDraftPage != nil {
            knowledgeMethodDraft = nil
            if reason != "Stopped." && reason != "Method drafting stopped." { knowledgeMethodDraftPage = nil }
            knowledgeMethodDraftRequestID = nil
            knowledgeMethodDraftMessage = reason
        }
        if knowledgeConceptDraftRequestID != nil {
            knowledgeConceptDraft = nil
            knowledgeConceptDraftRequestID = nil
            knowledgeConceptDraftMessage = reason
        }
        if wasWorking || hadDerivedReply {
            hamptonSnapshot.proposal = nil
            replySourceSelection = nil
            // A global source/position invalidation also removes a sibling that
            // finished before the other lane. Neither result has a current ticket.
            reply = wasWorking ? "The previous response was stopped."
                : "The previous answer was cleared because its context changed."
            status = reason
            workingCopyNotice = "Earlier work cleared · your working copy is unchanged."
        }
        isWorking = !replyOwners.isEmpty
        refreshRouteConnection()
        if activity.last != reason { record(reason) }
    }

    func submit() { _ = submit(question: prompt, pointing: nil) }

    var isDraftingKnowledgeMethod: Bool {
        knowledgeMethodDraftRequestID != nil && replyOwners[.qwen] != nil
            && compareResults[.qwen]?.receipt?.requestID == knowledgeMethodDraftRequestID
    }

    func canDraftKnowledgeMethod(page: KnowledgePage) -> Bool {
        !isShuttingDown && !isWorking && !isARCWorking && !voiceInput.isActive
            && !hasOpenKnowledgeDraft && page.kind == .concept && page.state == .reviewed
            && knowledgeDependenciesAreCurrent([page.binding])
    }

    func currentKnowledgeMethodDraft(for page: KnowledgePage) -> KnowledgeMethodDraft? {
        guard let draft = knowledgeMethodDraft, draft.binding == page.binding,
              draft.requestID == knowledgeMethodDraftRequestID,
              let receipt = compareResults[.qwen]?.receipt, receipt.state == .complete,
              receipt.requestID == draft.requestID, isCurrentReplyContext(receipt),
              knowledgeDependenciesAreCurrent([draft.binding]) else { return nil }
        return draft
    }

    func discardKnowledgeMethodDraft() {
        if isDraftingKnowledgeMethod { cancelWork(reason: "Method drafting stopped.") }
        knowledgeMethodDraft = nil
        knowledgeMethodDraftPage = nil
        knowledgeMethodDraftRequestID = nil
        knowledgeMethodDraftMessage = nil
    }

    /// Acquisition uses the ordinary local request owner and accounting. It
    /// neither edits the user's chat draft/copy nor saves or rates a method.
    @discardableResult
    func draftKnowledgeMethod(page: KnowledgePage, requirements: DocumentWorkRequirements) -> Bool {
        guard canDraftKnowledgeMethod(page: page),
              let context = KnowledgePageContext.make(page: page,
                quotes: page.anchors.compactMap { readingSources.quote(for: $0) }),
              client(for: .qwen) is HamptonReasonsAssistant else {
            if !isWorking { knowledgeMethodDraftPage = page.binding }
            knowledgeMethodDraftMessage = "Finish current work and use a reviewed concept with current passages that fit the local context limit. Local Hampton reasoning is required."
            return false
        }
        do {
            let target = try KnowledgeMethodDraftRequest(context: context, requirements: requirements,
                requestID: UUID().uuidString)
            cancelWork(reason: "Preparing a local method candidate.")
            let request = AssistantRequest(prompt: target.prompt, sourceName: nil, sourceText: "",
                sourceRevision: sourceRevision, placementRevision: placementRevision,
                tone: "Direct", replyLength: 0.3, localKnowledge: context, localMethodDraft: target)
            let digest = SHA256.hash(data: Data(request.localContextInput.utf8)).map { String(format: "%02x", $0) }.joined()
            try retryStewardReceipts()
            try tokenSteward.preflight(requestID: target.requestID, route: .automatic)
            knowledgeMethodDraftPage = page.binding
            knowledgeMethodDraftRequestID = target.requestID
            knowledgeMethodDraftMessage = "Drafting a method with local Qwen…"
            knowledgeMethodDraft = nil
            assistantProvider = .qwen
            hamptonSnapshot.proposal = nil
            compareResults = [:]
            documentProcedureRequests = [:]
            replySourceSelection = nil
            isWorking = true
            launchLane(.qwen, request: request, ticket: contextTicket(), route: .automatic,
                requestID: target.requestID, inputDigest: digest,
                routingReason: "Method candidate acquisition from one reviewed concept and its exact passages. Local Qwen only; no external fallback, prior dialogue, saved lessons or personal context. Drafting is not evidence of usefulness.")
            return true
        } catch {
            knowledgeMethodDraftPage = page.binding
            knowledgeMethodDraftMessage = "Method drafting did not start: \(error.localizedDescription)"
            return false
        }
    }

    var isDraftingKnowledgeConcept: Bool {
        knowledgeConceptDraftRequestID != nil && replyOwners[.qwen] != nil
            && compareResults[.qwen]?.receipt?.requestID == knowledgeConceptDraftRequestID
    }

    var currentKnowledgeConceptDraft: KnowledgeConceptDraft? {
        guard let draft = knowledgeConceptDraft, draft.requestID == knowledgeConceptDraftRequestID,
              let receipt = compareResults[.qwen]?.receipt, receipt.state == .complete,
              receipt.requestID == draft.requestID, isCurrentReplyContext(receipt),
              draft.anchors.allSatisfy({ readingSources.quote(for: $0) != nil }) else { return nil }
        return draft
    }

    func editKnowledgeConceptDraft() {
        guard let draft = currentKnowledgeConceptDraft, !hasOpenKnowledgeDraft, !isWorking else { return }
        knowledgePageDraft = KnowledgePageDraft(proposal: draft)
        knowledgePageMessage = "Review this generated interpretation and its limitations. Save creates an unreviewed draft."
    }

    func discardKnowledgeConceptDraft() {
        if isDraftingKnowledgeConcept { cancelWork(reason: "Concept drafting stopped.") }
        knowledgeConceptDraft = nil
        knowledgeConceptDraftRequestID = nil
        knowledgeConceptDraftMessage = nil
    }

    @discardableResult
    func draftKnowledgeConcept(title: String, anchors: [KnowledgeAnchor]) -> Bool {
        guard !isShuttingDown, !isWorking, !isARCWorking, !voiceInput.isActive,
              !hasOpenKnowledgeDraft, client(for: .qwen) is HamptonReasonsAssistant else { return false }
        do {
            let target = try KnowledgeConceptDraftRequest(requestID: UUID().uuidString, title: title,
                anchors: anchors, quotes: anchors.compactMap { readingSources.quote(for: $0) })
            guard readingDependenciesAreCurrent(target.readingSources) else { throw KnowledgeConceptDraftError.invalidContext }
            cancelWork(reason: "Preparing a source-grounded concept draft.")
            let request = AssistantRequest(prompt: target.prompt, sourceName: nil, sourceText: "",
                sourceRevision: sourceRevision, placementRevision: placementRevision,
                tone: "Direct", replyLength: 0.3, localConceptDraft: target)
            let digest = LessonSource.digest(of: request.localContextInput)
            try retryStewardReceipts()
            try tokenSteward.preflight(requestID: target.requestID, route: .automatic)
            knowledgeConceptDraftRequestID = target.requestID
            knowledgeConceptDraftMessage = "Drafting a concept with local Qwen…"
            knowledgeConceptDraft = nil
            assistantProvider = .qwen
            hamptonSnapshot.proposal = nil
            compareResults = [:]
            documentProcedureRequests = [:]
            replySourceSelection = nil
            isWorking = true
            launchLane(.qwen, request: request, ticket: contextTicket(), route: .automatic,
                requestID: target.requestID, inputDigest: digest,
                routingReason: "Concept draft from explicitly selected source passages. Local Qwen only; no external fallback, personal context, saved lessons or dialogue. Generating a note neither saves nor reviews it.")
            return true
        } catch {
            knowledgeConceptDraftMessage = "Concept drafting did not start: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func prepareARC3Action() -> Bool {
        guard !isShuttingDown, !voiceInput.isActive else { return false }
        if !replyOwners.isEmpty || activeARCOwner != nil { cancelWork(reason: "ARC3 replaces earlier work.") }
        arcCapabilities.stopSolving()
        activeARCAnswer = nil
        compareResults = [:]
        if !arc3.isSessionActive { lastARC3Summary = nil }
        showsARC3Reply = true
        return true
    }

    @discardableResult
    func runARC3(_ command: ARC3AssistantCommand) -> Bool {
        guard !isShuttingDown else { return false }
        if command == .stop {
            arc3.stop(reason: "Stopped by you.")
            showsARC3Reply = true
            return true
        }
        guard !voiceInput.isActive else { status = "Finish dictation before using ARC3."; return false }
        switch command {
        case .open:
            showsARC3Reply = true
            openReasoningTools(worlds: true)
            if arc3.games.isEmpty, !arc3.isWorking, !arc3.isSessionActive { arc3.discover() }
        case .explore:
            guard !arc3.isWorking else { return false }
            guard prepareARC3Action() else { return false }
            arc3.explore(maxActions: 8)
        case .invalid:
            cancelWork(reason: "Invalid ARC3 command. No new action dispatched.")
            status = "Use /arc3 open, /arc3 explore, or /arc3 stop."
            reply = status
            return false
        case .stop: break
        }
        return true
    }

    /// Native assistant dispatch. This reuses the profile's existing ARC owner,
    /// evaluator, evidence shelf and Usage path; no model lane is synthesized.
    @discardableResult
    func runARC(_ command: ARCActiveAssistantCommand) -> Bool {
        guard !isShuttingDown, !voiceInput.isActive else { return false }
        cancelWork(reason: "New ARC request replaces prior work.")
        compareResults = [:]
        replySourceSelection = nil
        hamptonSnapshot.proposal = nil
        // Explicit assistant dispatch also replaces work started in the ARC view.
        arcCapabilities.stopSolving()
        do {
            if let name = sourceName {
                try arcCapabilities.loadSolverTask(data: Data(sharedText.utf8), name: name)
            }
            guard let document = arcCapabilities.solverDocument else {
                showActiveARCError(command: command,
                    message: "Share standard ARC train/test JSON in the working copy, or load a task in ARC, then try again.")
                return false
            }
            let owner = ARCActiveAssistantOwnership(command: command, ticket: contextTicket(), document: document)
            activeARCOwner = owner
            let message = command == .solve ? "Solving this ARC task with native rules…"
                : "Asking local Qwen for one bounded ARC rule, then checking it…"
            activeARCAnswer = ARCActiveAssistantAnswer(command: command, taskID: nil, evidenceID: nil,
                inputName: document.name, inputDigest: document.inputDigest, status: message,
                result: nil, summary: nil, error: nil, isWorking: true)
            isWorking = true
            reply = message
            status = message
            let receive: @MainActor (ARCCapabilitiesEvent) -> Void = { [weak self, owner] event in
                owner.lastEvent = event
                guard let self else { return }
                // Accounting belongs to the actual attempt even after the reply
                // owner is retired. Cancellation never manufactures zero usage.
                self.recordARCEvaluation(event)
                self.receiveActiveARC(event, owner: owner)
            }
            switch command {
            case .solve: arcCapabilities.startSolving(onEvaluation: receive)
            case .propose: arcCapabilities.startQwenProposal(model: qwenModel, onEvaluation: receive)
            }
            // Recovery/preflight failures can reject before an ARC owner exists.
            if activeARCOwner?.id == owner.id, !arcCapabilities.isSolving, !arcCapabilities.isProposing {
                activeARCOwner = nil
                showActiveARCError(command: command, message: command == .solve
                    ? arcCapabilities.solverStatus : arcCapabilities.qwenProposalStatus)
                return false
            }
            return true
        } catch {
            showActiveARCError(command: command,
                message: "The shared working copy is not a valid ARC task. \(error.localizedDescription) Use standard train/test JSON, or stop sharing to use the loaded ARC task.")
            return false
        }
    }

    private func receiveActiveARC(_ event: ARCCapabilitiesEvent, owner: ARCActiveAssistantOwnership) {
        guard activeARCOwner?.id == owner.id else { return }
        guard !isShuttingDown, isCurrentContent(owner.ticket) else {
            cancelActiveARC(reason: "The ARC request context changed.")
            return
        }
        if event.proposalInProgress {
            let message = event.proposalInference?.attempted == true
                ? "Local Qwen is proposing one rule. ARC will independently check it."
                : "Connecting to Qwen on this Mac for this ARC task…"
            activeARCAnswer = ARCActiveAssistantAnswer(command: owner.command, taskID: event.taskID, evidenceID: nil,
                inputName: owner.document.name, inputDigest: owner.document.inputDigest, status: message,
                result: nil, summary: nil, error: nil, isWorking: true)
            reply = message; status = message
            return
        }
        let result: ARCActiveAssistantResult?
        if owner.command == .solve, let review = arcCapabilities.solverReview, review.taskID == event.taskID {
            result = .symbolic(review.run)
        } else if owner.command == .propose, let review = arcCapabilities.qwenProposalReview,
                  review.taskID == event.taskID, let proposed = review.result {
            result = .proposal(proposed)
        } else { result = nil }
        let summary = event.evidenceID.flatMap { id in arcCapabilities.records.first(where: { $0.id == id })?.summary }
        let message = event.error ?? result?.description ?? "ARC finished without an admitted prediction."
        activeARCOwner = nil
        let answer = ARCActiveAssistantAnswer(command: owner.command, taskID: event.taskID, evidenceID: event.evidenceID,
            inputName: owner.document.name, inputDigest: owner.document.inputDigest, status: message,
            result: result, summary: summary, error: event.error, isWorking: false, cancelled: event.cancelled)
        activeARCAnswer = answer
        isWorking = !replyOwners.isEmpty
        reply = answer.replyText
        status = message
    }

    private func showActiveARCError(command: ARCActiveAssistantCommand, message: String) {
        activeARCAnswer = ARCActiveAssistantAnswer(command: command, taskID: nil, evidenceID: nil,
            inputName: sourceName, inputDigest: nil, status: "ARC needs your attention",
            result: nil, summary: nil, error: message, isWorking: false)
        isWorking = !replyOwners.isEmpty
        reply = message
        status = "ARC needs your attention"
    }

    private func cancelActiveARC(reason: String, keepAnswer: Bool = false) {
        let owner = activeARCOwner
        // Retire before the store synchronously reports cancellation.
        activeARCOwner = nil
        if owner != nil { arcCapabilities.stopSolving() }
        if keepAnswer, let owner {
            activeARCAnswer = ARCActiveAssistantAnswer(command: owner.command, taskID: owner.lastEvent?.taskID,
                evidenceID: nil, inputName: owner.document.name, inputDigest: owner.document.inputDigest,
                status: reason, result: nil, summary: nil, error: reason, isWorking: false, cancelled: true)
        } else { activeARCAnswer = nil }
        isWorking = !replyOwners.isEmpty
    }

    private func invalidateActiveARCSource() {
        guard activeARCOwner != nil || activeARCAnswer != nil || arc3.isWorking || arc3.isSessionActive else { return }
        cancelWork(reason: "Shared source changed. The earlier ARC answer was cleared.")
    }

    private func submit(question: String, pointing: AssistantPointingSnapshot?) -> Bool {
        guard !isShuttingDown else { return false }
        switch executionSelection(question: question, pointing: pointing) {
        case .arc3(let command): return runARC3(command)
        case .arc(let command):
            guard !voiceInput.isActive else {
                status = "Finish or cancel voice input before starting ARC."; return false
            }
            return runARC(command)
        case .invalidARC:
            guard !voiceInput.isActive else {
                status = "Finish or cancel voice input before starting ARC."; return false
            }
            cancelWork(reason: "New ARC request replaces prior work.")
            compareResults = [:]
            showActiveARCError(command: .solve, message: ARCActiveAssistant.commandHelp)
            return false
        case .assistant: break
        }
        guard canShareDesktopInterestWithRoute else {
            status = "This window snapshot stays local. Allow this exact copy for your external route, or choose Local Qwen. Nothing sent."
            return false
        }
        guard !voiceInput.isActive else {
            status = "Finish or cancel voice input before sending. Your draft is unchanged."
            return false
        }
        if route.providers.contains(.qwen), !requireCurrentLocalPreferenceMemory() { return false }
        if !localConversationRequestIDs.isEmpty {
            do { try tokenSteward.refresh() } catch {
                status = "Reading history is unavailable. Nothing was sent."
                return false
            }
        }
        if localConversationRequestIDs.count >= 128 {
            clearLocalConversation()
            localConversationNotice = "Started fresh context after a long conversation; kept lessons remain available."
        }
        if !readingDependenciesAreCurrent(localConversationReadingSources) || !knowledgeDependenciesAreCurrent(localConversationKnowledgePages) {
            clearSessionContext()
            localConversationNotice = "A supporting reading source changed. Temporary context was cleared."
        }
        if let expiry = localConversationExpiry, expiry <= wallClock() {
            clearLocalConversation()
            localConversationNotice = "A lesson used earlier expired. Recent conversation was cleared before this request."
        }
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard question.utf8.count <= 16_000 else { status = "Keep the message below 16 KB. Nothing was sent."; return false }
        // A measurement visit cannot also dispatch the same material through an
        // external/compare lane. This guard precedes every connection, budget
        // reservation and provider dispatch, including explicitly chosen routes.
        if let reason = assistantBlockedReason(hasPointing: pointing != nil) {
            status = reason
            return false
        }
        guard textSelection == nil || textSelection?.matches(text: sharedText, sourceRevision: sourceRevision) == true else {
            invalidateTextSelection(reason: "The selected passage is no longer current. Nothing was sent.")
            return false
        }
        let revisionTarget: RevisionTarget?
        if requestsRevision && pointing == nil {
            guard let selection = textSelection,
                  let target = RevisionTarget(text: sharedText, sourceRevision: sourceRevision, selection: selection, requirements: documentRequirements) else {
                status = "Select a current passage before requesting a revision. Nothing was sent."; return false
            }
            revisionTarget = target
        } else { revisionTarget = nil }
        let procedureUse: DocumentProcedureUse?
        if let prepared = preparedDocumentProcedure {
            guard revisionTarget != nil, preparedProcedureMatchesCurrentDraft(question: question),
                  documentProcedureUnavailable(prepared) == nil else {
                status = "This procedure or its draft changed. Choose it again, or Detach procedure before sending. Nothing sent."
                return false
            }
            procedureUse = prepared
        } else { procedureUse = nil }
        cancelWork(reason: "New request replaces prior work.")
        let selectedRoute = route
        if selectedKnowledgePages.isEmpty, !selectedReadingSourceIDs.isEmpty {
            guard readingReferencesAreCurrent(currentReadingReferences),
                  currentReadingReferences.count == selectedReadingSourceIDs.count else {
                invalidateReadingContext(reason: "Kept sources changed or need recovery. Reopen ARCHi before using them.")
                return false
            }
        }
        guard selectedRoute.connectsAutomatically || selectedRoute.providers.allSatisfy({ connection(for: $0) == .ready }) else {
            replySourceSelection = nil
            compareResults = [:]
            reply = "Connect \(selectedRoute == .compare ? "both assistants" : assistantProvider.name) to send this message. This request has not been sent."
            status = "Not sent · assistant not connected"
            return false
        }
        if selectedRoute.providers.contains(.qwen) { hamptonSnapshot.proposal = nil }
        let knowledge = currentKnowledgeContext
        guard selectedKnowledgePages.isEmpty || knowledge != nil else {
            status = selectedKnowledgePageIssue ?? "Knowledge pages changed. Select current reviewed pages again. Nothing sent."
            return false
        }
        let request = AssistantRequest(prompt: question, sourceName: knowledge == nil ? sourceName : nil, sourceText: knowledge == nil ? sharedText : "",
            sourceRevision: sourceRevision, placementRevision: placementRevision, settings: nextReplySettings,
            selection: knowledge == nil ? textSelection : nil, revisionTarget: revisionTarget, companion: activeQiMon?.character,
            localProfile: personalContext?.assistantSnapshot, localKnowledge: knowledge,
            localProcedureKnowledge: procedureUse.flatMap { documentProcedures.procedure(matching: $0)?.knowledgeOrigin }.map { [$0] })
        let requestTaskScope: HamptonTaskScope = revisionTarget != nil ? .passageRevision
            : request.sourceName != nil ? .documentQuestion : .conversation
        let requiresReading = revisionTarget == nil && request.sourceName != nil && !request.sourceText.isEmpty
            && selectedRoute.providers.contains(.qwen)
        if requiresReading { documentReadingMessage = nil }
        let reading = requiresReading ? prepareReading(question: question, text: sharedText, selection: textSelection) : nil
        if requiresReading && reading == nil {
            status = documentReadingMessage ?? "The reading context could not fit. Shorten the question or select a smaller passage. Nothing sent."
            return false
        }
        let capturedControl = selectedRoute.providers.contains(.qwen)
            ? (revisionTarget != nil ? documentQ2EDecision : reading?.control) : nil
        if let control = capturedControl, control.lane == .stop || !control.isValid {
            status = control.reason + " Nothing sent."
            return false
        }
        if selectedRoute.providers.contains(.qwen) {
            if let previousScope = localContextTaskScope, previousScope != requestTaskScope {
                clearSessionContext()
                localConversationNotice = "Started fresh local context for \(requestTaskScope.title.lowercased()). Kept lessons still follow their chosen scope."
            }
            localContextTaskScope = requestTaskScope
        }
        let ticket = contextTicket()
        replySourceSelection = textSelection
        // The same immutable current-input contract is dispatched to both lanes.
        // Hampton may add local-only excerpts internally; no answer is forwarded.
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let input = try? JSONDecoder().decode(JSONValue.self, from: Data(request.input.utf8)),
              let bytes = try? encoder.encode(input) else {
            status = "The current request could not be prepared. Nothing was sent."; return false
        }
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let requestID = UUID().uuidString
        do {
            try retryStewardReceipts()
            try tokenSteward.preflight(requestID: requestID, route: selectedRoute)
            stewardMessage = nil
        } catch {
            stewardMessage = "Usage could not be recorded: \(error.localizedDescription)"
            status = "Not sent · " + (stewardMessage ?? "Token Steward unavailable")
            return false
        }
        assistantProvider = selectedRoute.primaryProvider
        // Prior owners were cancelled above. Keep only this request's immutable
        // binding, also used by its possible external fallback lane.
        documentProcedureRequests = procedureUse.map { [requestID: $0] } ?? [:]
        compareResults = [:]
        isWorking = true; reply = ""; status = "Sending · \(selectedRoute.title)…"
        if revisionTarget != nil { workingCopyNotice = "Preparing a revision · your working copy is unchanged." }
        let capturedLessons = matchingLessons(question: request.prompt, taskScope: requestTaskScope)
        let capturedConversation = nextReplyConversation
        // Expiry follows indirect use too: a later answer may repeat a lesson
        // without citing it again. Keep the earliest dependency conservatively.
        let conversationExpiry = (capturedConversation.isEmpty ? [] : [localConversationExpiry].compactMap { $0 })
            + keptLessons.filter { lesson in capturedLessons.contains { $0.id == lesson.id } }.compactMap(\.expiresAt)
        for provider in selectedRoute.providers {
            let laneRequest = AssistantRequest(prompt: request.prompt, sourceName: request.sourceName,
                sourceText: request.sourceText, sourceRevision: request.sourceRevision,
                placementRevision: request.placementRevision, settings: request.settings,
                selection: request.selection, localLessons: provider == .qwen ? capturedLessons : [],
                revisionTarget: request.revisionTarget, companion: request.companion,
                localConversation: provider == .qwen ? capturedConversation : [],
                localProfile: provider == .qwen ? request.localProfile : nil,
                localControl: provider == .qwen ? capturedControl : nil,
                localReading: provider == .qwen ? reading?.plan : nil,
                localKnowledge: provider == .qwen ? request.localKnowledge : nil,
                localProcedureKnowledge: request.localProcedureKnowledge)
            launchLane(provider, request: laneRequest, ticket: ticket, route: selectedRoute,
                       requestID: requestID, inputDigest: digest, pointing: pointing,
                       routingReason: request.localProcedureKnowledge != nil ? "A user-authored method linked to a reviewed page uses local reasoning. Source history stays attached; external fallback is disabled." : knowledge != nil ? "Selected reviewed pages and exact passages use local reasoning. Shared document is not sent; no external fallback." : !(reading?.plan.references.isEmpty ?? true) ? "Local Qwen with selected kept copies; external fallback is disabled for this reading."
                           : selectedRoute == .native ? (representationMeasurementsEnabled
                               ? "Local Qwen with read-only measurements; automatic external fallback is disabled."
                               : "ARCHi-managed local Qwen first; one external fallback only on an eligible failure.")
                           : selectedRoute == .automatic ? "Local Qwen · connects when needed; failures stay on this Mac." : nil,
                       conversationExpiry: provider == .qwen ? conversationExpiry.min() : nil)
        }
        if let pointing {
            presentPlacementPreview(candidate: pointing.candidate, geometry: pointing.geometry,
                environment: pointing.environment, ticket: ticket)
            if let preview = spatialPreview {
                startFocusGesture(configuration: pointing.gesture, purpose: .explaining, spatialPreviewID: preview.id)
            }
            workingCopyNotice = "Explaining this passage · your working copy is unchanged."
        }
        return true
    }

    private func launchLane(_ provider: AssistantProvider, request: AssistantRequest, ticket: ContextTicket,
                            route: AssistantRoute, requestID: String, inputDigest: String,
                            pointing: AssistantPointingSnapshot? = nil, routingReason: String? = nil,
                            conversationExpiry: Date? = nil) {
        // A manual connection check cannot race an automatically owned check.
        if route.connectsAutomatically, connection(for: provider) != .ready { closeConnection(provider) }
        let assistant = client(for: provider)
        if let local = assistant as? HamptonReasonsAssistant { local.workPreference = localWorkPreference }
        let allowsExternalFallback = !(provider == .qwen
            && (assistant as? HamptonReasonsAssistant)?.requiresRepresentation == true)
        var dependencies = (request.localReading?.references.map(\.binding) ?? []) + (request.localKnowledge?.readingSources ?? []) + (request.localConceptDraft?.readingSources ?? [])
        var knowledgeDependencies = (request.localKnowledge?.bindings ?? []) + (request.localProcedureKnowledge ?? [])
        for binding in request.localProcedureKnowledge ?? [] {
            if let page = readingSources.latestKnowledgePages.first(where: { $0.binding == binding }) {
                dependencies += page.anchors.map(\.source)
            }
        }
        for lesson in request.localLessons {
            let origin = keptLessons.first(where: { LessonSnapshot(lesson: $0) == lesson })?.origin
            dependencies += origin?.readingSources ?? []
            knowledgeDependencies += origin?.knowledgePages ?? []
        }
        if !request.localConversation.isEmpty {
            dependencies += localConversationReadingSources ?? []
            knowledgeDependencies += localConversationKnowledgePages ?? []
        }
        let uniqueKnowledge = knowledgeDependencies.reduce(into: [KnowledgePageBinding]()) { if !$0.contains($1) { $0.append($1) } }.sorted { $0.id < $1.id }
        let capturedKnowledgeDependencies: [KnowledgePageBinding]? = uniqueKnowledge.isEmpty ? nil : uniqueKnowledge
        let uniqueDependencies = dependencies.reduce(into: [ReadingSourceBinding]()) { result, item in
            if !result.contains(item) { result.append(item) }
        }.sorted { $0.id < $1.id }
        let capturedReadingDependencies: [ReadingSourceBinding]? = uniqueDependencies.isEmpty ? nil : uniqueDependencies
        let conversationParents = request.localConversation.isEmpty ? Set<UUID>() : localConversationRequestIDs
        let owner = UUID(), epoch = connectionGenerations[provider, default: 0]
        let seconds = provider == .qwen ? 180 : 90
        let deadline = Date().addingTimeInterval(Double(seconds))
        replyOwners[provider] = owner
        laneStartedAt[provider] = monotonicTime()
        compareResults[provider] = AssistantLaneResult(text: "", status: "Preparing \(provider.name) answer…", state: .pending,
            receipt: AssistantLaneReceipt(requestID: requestID, route: route, provider: provider, context: ticket,
                inputDigest: inputDigest, inputContract: AssistantRequest.inputContract, deadline: deadline,
                modelIdentity: nil, state: .pending, settings: request.settings,
                localInvocations: assistant is HamptonReasonsAssistant ? [] : nil))
        compareResults[provider]?.receipt?.sourceDigest = request.sourceName == nil ? nil
            : SHA256.hash(data: Data(request.sourceText.utf8)).map { String(format: "%02x", $0) }.joined()
        compareResults[provider]?.receipt?.readingDependencies = capturedReadingDependencies
        compareResults[provider]?.receipt?.knowledgeDependencies = capturedKnowledgeDependencies
        compareResults[provider]?.receipt?.isKnowledgeAcquisition = request.isKnowledgeAcquisition
        compareResults[provider]?.receipt?.knowledgeContextDigest = request.localKnowledge?.digest
        compareResults[provider]?.receipt?.sourceContext = provider == .qwen
            ? AssistantSourceContext.capture(request, sourceTitles: Dictionary(uniqueKeysWithValues: readingSources.sources.map { ($0.id, $0.title) })) : nil
        compareResults[provider]?.receipt?.documentReading = request.localReading
        compareResults[provider]?.receipt?.readingControl = request.localReading == nil ? nil : request.localControl
        compareResults[provider]?.receipt?.localLessons = request.localLessons
        if provider == .qwen {
            let omissions = lessonOmissions(for: request, now: wallClock())
            compareResults[provider]?.receipt?.localLessonOmissions = omissions
        }
        compareResults[provider]?.receipt?.localLessonDigest = request.localLessonDigest
        compareResults[provider]?.receipt?.localProfileDigest = request.localProfile?.digest
        compareResults[provider]?.receipt?.localProfileRevision = request.localProfile?.revision
        compareResults[provider]?.receipt?.localConversationCount = request.localConversation.count
        compareResults[provider]?.receipt?.localConversationBytes = request.localConversationUTF8Bytes
        compareResults[provider]?.receipt?.localConversationDigest = request.localConversationDigest
        compareResults[provider]?.receipt?.pointing = pointing
        compareResults[provider]?.receipt?.routingReason = routingReason
        if let local = assistant as? HamptonReasonsAssistant {
            local.mayAdmitResponse = { [weak self, weak local] in
                guard let self, let local else { return false }
                return self.isCurrentLane(provider, owner: owner, epoch: epoch, client: local, ticket: ticket)
                    && self.readingDependenciesAreCurrent(capturedReadingDependencies)
                    && self.knowledgeDependenciesAreCurrent(capturedKnowledgeDependencies)
                    && self.readingContinuationIsCurrent(conversationParents)
            }
            local.onSnapshot = { [weak self, weak local] snapshot in
                guard let self, let local,
                      self.isCurrentLane(provider, owner: owner, epoch: epoch, client: local, ticket: ticket),
                      self.compareResults[provider]?.receipt?.requestStarted == true else { return }
                // Source invalidation rejects the semantic result, not work
                // already spent by this exact request. Retain terminal metrics
                // before a stale-source failure clears the local context owner.
                self.compareResults[provider]?.receipt?.localInvocations = snapshot.attemptedInvocations
                self.compareResults[provider]?.receipt?.localInvocationReceipts = snapshot.invocations
                self.compareResults[provider]?.receipt?.admissionOutcome = snapshot.admissionOutcome
                guard self.knowledgeDependenciesAreCurrent(capturedKnowledgeDependencies),
                      self.readingDependenciesAreCurrent(capturedReadingDependencies) else { return }
                self.hamptonSnapshot = snapshot
                if let decision = snapshot.expertDecision {
                    self.compareResults[provider]?.receipt?.localExpertDecision = decision
                    self.compareResults[provider]?.receipt?.routingReason = decision.reason + " " + (routingReason ?? "")
                }
                self.compareResults[provider]?.receipt?.localConversationCount = snapshot.localConversationCount
                self.compareResults[provider]?.receipt?.localConversationBytes = snapshot.localConversationBytes
                self.compareResults[provider]?.receipt?.localConversationDigest = snapshot.localConversationDigest
                self.compareResults[provider]?.receipt?.localConversationOmittedCount = snapshot.localConversationOmittedCount
                self.compareResults[provider]?.receipt?.admissionOutcome = snapshot.admissionOutcome
                self.compareResults[provider]?.receipt?.usedLessonIDs = snapshot.proposal?.memoryIDs.filter {
                    request.localLessons.map(\.modelID).contains($0)
                } ?? []
                self.compareResults[provider]?.receipt?.localInvocations = snapshot.attemptedInvocations
                self.compareResults[provider]?.receipt?.localInvocationReceipts = snapshot.invocations
                let evidence = self.capturedEvidence(snapshot.evidence, for: provider)
                self.compareResults[provider]?.receipt?.evidence = evidence
                if let receipt = snapshot.receipts.last(where: { $0.role == .reasoning }) {
                    self.compareResults[provider]?.receipt?.modelIdentity = receipt.model.name + " @ " + receipt.model.digest
                }
                self.compareResults[provider]?.status = snapshot.phase
                if self.route != .compare { self.status = snapshot.phase }
            }
        }
        laneTimeoutTasks[provider] = Task { [weak self, assistant] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, self.isCurrentLane(provider, owner: owner, epoch: epoch, client: assistant, ticket: ticket) else { return }
            if provider == .qwen {
                self.compareResults[provider]?.receipt?.admissionOutcome = HamptonAdmissionOutcome(
                    status: .rejected, stage: self.compareResults[provider]?.receipt?.requestStarted == true ? .generation : .connection,
                    role: nil, requestID: nil, reason: .timedOut)
            }
            self.finishFailedAttempt(provider, error: QwenFailure.timedOut,
                message: "\(provider.name) reached its \(seconds)-second reply limit.",
                request: request, ticket: ticket, route: route, requestID: requestID,
                inputDigest: inputDigest, pointing: pointing, allowsExternalFallback: allowsExternalFallback)
        }
        replyTasks[provider] = Task { [weak self, assistant] in
            do {
                guard let self, self.isCurrentLane(provider, owner: owner, epoch: epoch, client: assistant, ticket: ticket), !Task.isCancelled else { return }
                if route.connectsAutomatically, self.connection(for: provider) != .ready {
                    self.connectionStates[provider] = .connecting
                    self.connectionMessages[provider] = "Checking \(provider.name) for this request…"
                    self.compareResults[provider]?.status = "Connecting to \(provider.name)…"
                    self.status = "Connecting to \(provider.name)…"
                    self.refreshRouteConnection()
                    try await assistant.connect()
                    guard self.isCurrentLane(provider, owner: owner, epoch: epoch, client: assistant, ticket: ticket), !Task.isCancelled else { return }
                    self.connectionStates[provider] = .ready
                    self.connectionMessages[provider] = "\(provider.name) connected for this request."
                    self.refreshRouteConnection()
                }
                guard self.knowledgeDependenciesAreCurrent(capturedKnowledgeDependencies),
                      self.readingDependenciesAreCurrent(capturedReadingDependencies),
                      self.readingContinuationIsCurrent(conversationParents) else { throw QwenFailure.invalidResponse }
                if let target = request.revisionTarget {
                    try self.beginDocumentWork(requestID: requestID, provider: provider, target: target,
                                               control: request.localControl)
                }
                if let reading = request.localReading, let control = request.localControl {
                    guard provider == .qwen, request.hasValidLocalControl else { throw QwenFailure.invalidResponse }
                    try self.tokenSteward.recordDocumentReading(requestID: requestID,
                        trace: DocumentReadingTrace(sourceDigest: reading.sourceDigest,
                            questionDigest: reading.questionDigest, planDigest: reading.digest,
                            sectionIDs: reading.sourceIDs, control: control,
                            references: reading.references.isEmpty ? nil : reading.references.map(\.binding),
                            conversationRequestIDs: conversationParents.isEmpty ? nil : conversationParents.map(\.uuidString).sorted()))
                }
                if let reading = request.localReading {
                    guard self.readingReferencesAreCurrent(reading.references) else { throw QwenFailure.invalidResponse }
                }
                if let receipt = self.compareResults[provider]?.receipt,
                   let provenance = TokenStewardRequestProvenance.capture(receipt) {
                    try self.tokenSteward.recordRequestProvenance(requestID: requestID, provenance: provenance)
                }
                try self.tokenSteward.recordDispatch(requestID: requestID, provider: provider)
                guard self.readingContinuationIsCurrent(conversationParents) else { throw QwenFailure.invalidResponse }
                self.compareResults[provider]?.receipt?.requestStarted = true
                try await assistant.reply(to: request) { [weak self] event in
                    guard let self, self.isCurrentLane(provider, owner: owner, epoch: epoch, client: assistant, ticket: ticket) else { return }
                    guard self.knowledgeDependenciesAreCurrent(capturedKnowledgeDependencies),
                          self.readingDependenciesAreCurrent(capturedReadingDependencies) else {
                        self.clearSessionContext()
                        self.failLane(provider, message: "Supporting knowledge changed. This reply is no longer current.")
                        return
                    }
                    switch event {
                    case .text(let text):
                        guard request.revisionTarget == nil else {
                            self.failLane(provider, message: "The revision response was not a validated proposal."); return
                        }
                        self.setLane(provider, text: text, status: "\(provider.name) is replying…", state: .pending)
                        if provider == self.assistantProvider, !request.isKnowledgeAcquisition { self.reply = text }
                        self.status = self.route == .compare ? "Receiving independent answers…" : "ARCHi is replying…"
                    case .revision(let proposal):
                        guard proposal.target == request.revisionTarget,
                              proposal.target.matches(text: self.sharedText, sourceRevision: self.sourceRevision) else {
                            self.failLane(provider, message: "The revision target changed. Select the passage again."); return
                        }
                        self.compareResults[provider]?.revision = proposal
                        self.compareResults[provider]?.receipt?.usedLessonIDs = proposal.memoryIDs.filter {
                            request.localLessons.map(\.modelID).contains($0)
                        }
                        self.setLane(provider, text: proposal.explanation, status: "Revision received · validating completion", state: .pending)
                        if provider == self.assistantProvider { self.reply = proposal.explanation }
                    }
                }
                guard self.isCurrentLane(provider, owner: owner, epoch: epoch, client: assistant, ticket: ticket), !Task.isCancelled else { return }
                guard self.readingContinuationIsCurrent(conversationParents) else { throw QwenFailure.invalidResponse }
                guard self.knowledgeDependenciesAreCurrent(capturedKnowledgeDependencies),
                      self.readingDependenciesAreCurrent(capturedReadingDependencies) else {
                    self.clearSessionContext()
                    throw QwenFailure.invalidResponse
                }
                if request.revisionTarget != nil && self.compareResults[provider]?.revision == nil {
                    self.failLane(provider, message: "No validated revision completed. Your copy is unchanged."); return
                }
                if let proposal = self.compareResults[provider]?.revision {
                    try self.completeDocumentProposal(requestID: requestID, provider: provider, proposal: proposal)
                }
                if let reading = request.localReading, provider == .qwen {
                    // Capture the exact displayed result while this lane still
                    // owns the request. A citation is membership, not entailment.
                    guard self.readingReferencesAreCurrent(reading.references),
                          let proposal = self.hamptonSnapshot.proposal,
                          let answer = self.compareResults[provider]?.text, !answer.isEmpty else {
                        throw QwenFailure.invalidResponse
                    }
                    let result = DocumentReadingResult(answerDigest: LessonSource.digest(of: answer),
                        kind: proposal.kind.rawValue,
                        citedSectionIDs: proposal.sourceIDs.filter { reading.sourceIDs.contains($0) })
                    try self.tokenSteward.recordDocumentReadingResult(requestID: requestID, result: result)
                    self.compareResults[provider]?.receipt?.readingResult = result
                }
                if let target = request.localMethodDraft {
                    guard provider == .qwen, self.knowledgeMethodDraftRequestID == requestID,
                          let proposal = self.hamptonSnapshot.proposal else { throw QwenFailure.invalidResponse }
                    self.knowledgeMethodDraft = try target.admit(proposal: proposal)
                }
                if let target = request.localConceptDraft {
                    guard provider == .qwen, self.knowledgeConceptDraftRequestID == requestID,
                          let proposal = (assistant as? HamptonReasonsAssistant)?.snapshot.proposal else { throw KnowledgeConceptDraftError.invalidReply }
                    self.knowledgeConceptDraft = try target.admit(proposal: proposal)
                }
                self.finishOwnership(provider)
                self.setLane(provider, status: request.localConceptDraft != nil ? "Concept draft ready for your review" : request.localMethodDraft != nil ? "Method draft ready for your review" : request.revisionTarget == nil ? "Reply ready" : "Revision ready for review", state: .complete)
                // Only terminal, current local answers become temporary dialogue.
                // Revision proposals, partial output and external answers never enter it.
                if provider == .qwen, request.revisionTarget == nil, !request.isKnowledgeAcquisition, self.localConversationEnabled,
                   let answer = self.compareResults[provider]?.text, !answer.isEmpty {
                    if let expiry = conversationExpiry, expiry <= self.wallClock() {
                        self.clearLocalConversation()
                        self.localConversationNotice = "A supplied lesson expired during this reply. This answer was not retained for follow-up."
                    } else {
                        self.localConversationNotice = self.localConversation.retain(question: request.prompt, answer: answer).status
                        if !self.localConversation.exchanges.isEmpty,
                           self.compareResults[provider]?.receipt?.readingResult?.kind == "ANSWER",
                           let id = UUID(uuidString: requestID) {
                            self.localConversationRequestIDs = conversationParents.union([id])
                        } else { self.localConversationRequestIDs = conversationParents }
                        self.localConversationExpiry = self.localConversation.exchanges.isEmpty ? nil : conversationExpiry
                        self.localConversationReadingSources = self.localConversation.exchanges.isEmpty ? nil : capturedReadingDependencies
                        self.localConversationKnowledgePages = self.localConversation.exchanges.isEmpty ? nil : capturedKnowledgeDependencies
                    }
                }
                if request.revisionTarget != nil {
                    self.workingCopyNotice = "Review Before and After. Apply changes only the working copy."
                }
                self.refreshWorkStatus()
                self.record("\(provider.name) reply received for shared source revision \(ticket.source)")
            } catch {
                guard let self, self.isCurrentLane(provider, owner: owner, epoch: epoch, client: assistant, ticket: ticket), !Task.isCancelled else { return }
                if !self.readingDependenciesAreCurrent(capturedReadingDependencies) || !self.knowledgeDependenciesAreCurrent(capturedKnowledgeDependencies) {
                    self.clearSessionContext()
                }
                if provider == .qwen, self.compareResults[provider]?.receipt?.admissionOutcome == nil {
                    self.compareResults[provider]?.receipt?.admissionOutcome = HamptonAdmissionOutcome.failure(error,
                        stage: self.compareResults[provider]?.receipt?.requestStarted == true ? .generation : .connection,
                        role: nil, requestID: nil)
                }
                self.finishFailedAttempt(provider, error: error,
                    message: (error as? LocalizedError)?.errorDescription ?? "The assistant connection stopped. Try connecting again.",
                    request: request, ticket: ticket, route: route, requestID: requestID,
                    inputDigest: inputDigest, pointing: pointing, allowsExternalFallback: allowsExternalFallback)
            }
        }
    }

    func connection(for provider: AssistantProvider) -> AssistantConnectionState { connectionStates[provider] ?? .disconnected }
    func message(for provider: AssistantProvider) -> String {
        connectionMessages[provider] ?? "Connect \(provider.destination) when you are ready."
    }

    func connectAssistant() { for provider in route.providers { connectAssistant(provider: provider) } }

    /// Launch checks local readiness without sending a question or contacting
    /// an external account. Only explicit Send owns any fallback.
    func prepareNativeAssistant(route selected: AssistantRoute = .native) {
        guard !isShuttingDown else { return }
        setAssistantRoute(selected)
        if selected.connectsAutomatically { connectAssistant(provider: .qwen) }
    }

    func connectAssistant(provider: AssistantProvider) {
        guard !isShuttingDown, replyOwners[provider] == nil,
              connection(for: provider) != .connecting, connection(for: provider) != .ready else { return }
        let assistant = client(for: provider)
        connectionGenerations[provider, default: 0] &+= 1
        let generation = connectionGenerations[provider, default: 0]
        connectionStates[provider] = .connecting
        connectionMessages[provider] = provider == .qwen
            ? "Checking the installed local Qwen model…"
            : "Checking your existing Codex account and shared-text connection…"
        refreshRouteConnection()
        connectionTasks[provider] = Task { [weak self, assistant] in
            do {
                try await assistant.connect()
                guard let self, !self.isShuttingDown, self.assistants[provider] === assistant,
                      self.connectionGenerations[provider] == generation, !Task.isCancelled else { return }
                self.connectionStates[provider] = .ready; self.connectionTasks[provider] = nil
                self.connectionMessages[provider] = provider == .qwen
                    ? (self.representationMeasurementsEnabled
                       ? "\(self.qwenModel) reader and local runtime are ready. Send loads the CPU model for a measured reply; no inference has run yet."
                       : "\(self.qwenModel) is available locally. Send runs inference on this Mac; the first reply may take longer to load.")
                    : "Connected through your ChatGPT login. Send includes only your message and shared copy."
                self.refreshRouteConnection()
                if self.route.providers.contains(provider), !self.isWorking { self.status = "\(provider.name) connected · nothing sent yet" }
            } catch {
                guard let self, !self.isShuttingDown, self.assistants[provider] === assistant,
                      self.connectionGenerations[provider] == generation, !Task.isCancelled else { return }
                self.connectionStates[provider] = .failed; self.connectionTasks[provider] = nil
                self.connectionMessages[provider] = (error as? LocalizedError)?.errorDescription ?? "Could not connect to \(provider.name). Try again."
                self.refreshRouteConnection()
                if self.route.providers.contains(provider), !self.isWorking { self.status = self.message(for: provider) }
            }
        }
    }

    func disconnectAssistant() {
        for provider in resultProviders { disconnectAssistant(provider: provider) }
    }

    func disconnectAssistant(provider: AssistantProvider) {
        let hadWork = replyOwners[provider] != nil
        cancelLane(provider, reason: "\(provider.name) disconnected.")
        if !hadWork { closeConnection(provider) }
        connectionMessages[provider] = "Disconnected. Your shared copy stays here until you stop sharing."
        refreshRouteConnection()
        if !isWorking { status = "\(provider.name) disconnected" }
    }

    func setAssistantRoute(_ selected: AssistantRoute) {
        guard !isShuttingDown, selected != route else { return }
        cancelWork(reason: "Assistant route changed.")
        route = selected; assistantProvider = selected.primaryProvider
        for provider in selected.providers { _ = client(for: provider) }
        compareResults = [:]; replySourceSelection = nil; hamptonSnapshot.proposal = nil
        reply = "\(selected.title) selected. Send when you are ready."
        refreshRouteConnection()
        status = "Assistant route changed · nothing sent"
    }

    func selectAssistantProvider(_ provider: AssistantProvider) {
        setAssistantRoute(provider == .qwen ? .local : .codex)
    }

    func setLocalWorkPreference(_ preference: LocalWorkPreference) {
        guard !isShuttingDown, preference != localWorkPreference else { return }
        cancelLocalWork(reason: "Local work preference changed.")
        localWorkPreference = preference
        (assistants[.qwen] as? HamptonReasonsAssistant)?.workPreference = preference
        status = "Local work preference changed · nothing sent"
    }

    func refreshInstalledLocalModels() {
        guard !isShuttingDown, !isRefreshingModels else { return }
        isRefreshingModels = true
        modelInventoryTask = Task { [weak self] in
            do {
                let models = try await QwenAssistant.discoverInstalledModels()
                guard let self, !self.isShuttingDown, !Task.isCancelled else { return }
                self.installedLocalModels = models
                self.modelInventoryNotice = models.isEmpty ? "No supported local model was found. Nothing was downloaded."
                    : "Installed models found. Each connection still verifies the selected model."
                self.isRefreshingModels = false
                self.modelInventoryTask = nil
            } catch {
                guard let self, !self.isShuttingDown, !Task.isCancelled else { return }
                self.installedLocalModels = nil
                self.modelInventoryNotice = "Local model inventory is unavailable. Start Ollama and refresh. Nothing was downloaded."
                self.isRefreshingModels = false
                self.modelInventoryTask = nil
            }
        }
    }

    var localModelChoices: [String] {
        let installed = installedLocalModels?.map(\.name) ?? QwenAssistant.supportedModels
        return Array(Set(installed + [qwenModel, qwenContextModel])).sorted()
    }

    func localModelLabel(_ name: String) -> String {
        guard let models = installedLocalModels else { return name + " · not checked" }
        return name + (models.contains { $0.name == name } ? " · installed" : " · unavailable")
    }

    func selectQwenModel(_ model: String) {
        guard !isShuttingDown, QwenAssistant.supportedModels.contains(model), model != qwenModel else { return }
        cancelActiveARC(reason: "Local Qwen model changed.")
        arcCapabilities.stopQwenProposal(reason: "Local Qwen model changed.")
        qwenModel = model
        if representationReader?.modelName != model {
            representationMeasurementsEnabled = false
            representationReader = nil
            representationNotice = "Model changed. Import a reader fitted for \(model) to inspect its report."
        }
        replaceLocalAssistant()
    }

    func importRepresentationReader(from url: URL) {
        guard !isShuttingDown else { return }
        do {
            let reader = try GGUFReaderArtifact.load(from: url)
            guard reader.modelName == qwenModel else {
                representationNotice = "This reader is for \(reader.modelName). Select that reasoning model before importing it."
                return
            }
            representationMeasurementsEnabled = false
            representationReader = reader
            replaceLocalAssistant()
            representationNotice = "Reader imported for inspection this visit. Its supplied calibration history does not qualify ordinary reply measurements."
        } catch {
            representationNotice = "Reader was not imported: \(error.localizedDescription)"
        }
    }

    func setRepresentationMeasurementsEnabled(_ enabled: Bool) {
        guard !isShuttingDown, enabled != representationMeasurementsEnabled else { return }
        if enabled {
            guard representationReader?.canMeasureGeneralReplies == true else {
                representationNotice = "Ordinary reply measurements require a reader qualified for general replies. Imported synthetic readers remain available for inspection."
                return
            }
            guard representationReader?.modelName == qwenModel,
                  representationReader?.hasLimitedShadowReport == true,
                  GGUFRepresentationClient.bundledWorkerAvailable else {
                representationNotice = "A matching reader with a complete passing calibration report and the bundled local measurement runtime are required. Legacy readers can be inspected but cannot enable measurements."
                return
            }
        }
        representationMeasurementsEnabled = enabled
        replaceLocalAssistant()
        representationNotice = enabled
            ? "Read-only measurements selected for local replies this visit. No steering or automatic external fallback. Connect checks readiness; Send loads the model."
            : "Standard local Qwen selected. Measurements are off."
    }

    func removeRepresentationReader() {
        guard !isShuttingDown else { return }
        representationMeasurementsEnabled = false
        representationReader = nil
        replaceLocalAssistant()
        representationNotice = "Reader removed from this visit. Standard local Qwen selected."
    }

    func selectQwenContextModel(_ model: String) {
        guard !isShuttingDown, QwenAssistant.supportedModels.contains(model), model != qwenContextModel else { return }
        cancelActiveARC(reason: "Local context model changed.")
        qwenContextModel = model
        replaceLocalAssistant()
    }

    func setSessionContextEnabled(_ enabled: Bool) {
        guard !isShuttingDown, sessionContextEnabled != enabled else { return }
        clearLocalConversation()
        cancelLocalWork(reason: "Session context setting changed.")
        sessionContextEnabled = enabled
        (assistants[.qwen] as? HamptonReasonsAssistant)?.setContextEnabled(enabled)
        hamptonSnapshot = (assistants[.qwen] as? HamptonReasonsAssistant)?.snapshot ?? HamptonAssistantSnapshot()
        if route == .local {
            replySourceSelection = nil
            reply = enabled ? "Temporary context is on for local Qwen. Send a question to begin." : "Temporary context is off and has been cleared."
        }
        if !isWorking { status = enabled ? "Session context enabled · nothing sent" : "Session context cleared" }
    }

    func clearSessionContext() {
        clearLocalConversation()
        cancelLocalWork(reason: "Session context cleared.")
        (assistants[.qwen] as? HamptonReasonsAssistant)?.clearSessionContext()
        hamptonSnapshot = HamptonAssistantSnapshot(phase: "Session context cleared")
        if route == .local {
            replySourceSelection = nil
            reply = "Session context cleared. Your current draft and shared copy stay here."
        }
        if !isWorking { status = "Session context cleared" }
    }

    private func bindHamptonAssistant() {
        hamptonSnapshot = HamptonAssistantSnapshot()
        guard let client = assistants[.qwen] as? HamptonReasonsAssistant else { return }
        client.setContextModel(qwenContextModel)
        client.setContextEnabled(sessionContextEnabled)
        client.workPreference = localWorkPreference
        hamptonSnapshot = client.snapshot
        // Each reply installs a callback bound to its own operation and ticket.
        client.onSnapshot = nil
    }

    private func replaceLocalAssistant() {
        clearLocalConversation()
        guard let previous = assistants[.qwen] else { return }
        cancelLocalWork(reason: "Local model changed.")
        closeConnection(.qwen)
        (previous as? HamptonReasonsAssistant)?.onSnapshot = nil
        (previous as? HamptonReasonsAssistant)?.clearSessionContext()
        assistants[.qwen] = makeAssistant(.qwen)
        bindHamptonAssistant()
        if route == .local {
            invalidateTextSelection(reason: "Local model changed. Select the passage again to restore its reference.")
            replySourceSelection = nil
            reply = "The local model changed. Connect Qwen, then Send when you are ready."
        }
        connectionMessages[.qwen] = "Connect Qwen on this Mac when you are ready."
        refreshRouteConnection()
        if !isWorking { status = "Local model changed · nothing sent" }
        let retirement = UUID()
        retiringAssistants[retirement] = Task { [weak self, previous] in
            await previous.shutdown()
            self?.retiringAssistants[retirement] = nil
        }
    }

    func shutdownAssistant() async {
        guard !isShuttingDown else { return }
        arcCapabilities.stopSolving()
        unityPresentation.stop()
        desktopInterest.cancel(reason: "ARCHi is closing.")
        clearLocalConversation()
        isShuttingDown = true
        modelInventoryTask?.cancel(); modelInventoryTask = nil; isRefreshingModels = false
        cancelWork(reason: "App is shutting down.")
        let current = Array(assistants.values)
        for provider in Array(assistants.keys) { closeConnection(provider) }
        // Begin both cleanups before awaiting either; one slow child cannot hide
        // another owned process from shutdown.
        let cleanup = current.map { client in Task { await client.shutdown() } }
        for task in cleanup { await task.value }
        hamptonSnapshot = HamptonAssistantSnapshot(phase: "Session context cleared")
        for retirement in Array(retiringAssistants.values) { await retirement.value }
    }

    private func client(for provider: AssistantProvider) -> any AssistantClient {
        if let existing = assistants[provider] { return existing }
        let created = makeAssistant(provider)
        assistants[provider] = created
        if provider == .qwen { bindHamptonAssistant() }
        return created
    }

    private func makeAssistant(_ provider: AssistantProvider) -> any AssistantClient {
        if provider == .qwen, representationMeasurementsEnabled, let reader = representationReader,
           reader.canMeasureGeneralReplies, reader.hasLimitedShadowReport,
           reader.modelName == qwenModel, GGUFRepresentationClient.bundledWorkerAvailable {
            return HamptonReasonsAssistant(model: qwenModel,
                reasoner: GGUFRepresentationClient(model: qwenModel, reader: reader), nativeRuntime: .shared)
        }
        return assistantFactory(provider, qwenModel)
    }

    private func isCurrentLane(_ provider: AssistantProvider, owner: UUID, epoch: UInt64,
                               client: any AssistantClient, ticket: ContextTicket) -> Bool {
        guard !isShuttingDown && replyOwners[provider] == owner && assistants[provider] === client
            && connectionGenerations[provider, default: 0] == epoch
            && isCurrentContent(ticket) else { return false }
        if provider == .qwen, !requireCurrentLocalPreferenceMemory() { return false }
        // Recheck the actual target before dispatch and every incoming event,
        // even after the short staff animation has completed.
        if let pointing = compareResults[provider]?.receipt?.pointing,
           (!isCurrent(ticket, requireVisible: false) || !isCurrentPointing(pointing)) {
            cancelWork(reason: "The passage or ARCHi moved. Select the current passage and explain again.")
            return false
        }
        return true
    }

    private func finishOwnership(_ provider: AssistantProvider) {
        if let local = assistants[provider] as? HamptonReasonsAssistant,
           let attempts = local.inFlightInvocations {
            compareResults[provider]?.receipt?.localInvocations = attempts
            compareResults[provider]?.receipt?.localInvocationReceipts = local.snapshot.invocations
            let evidence = capturedEvidence(local.snapshot.evidence, for: provider)
            compareResults[provider]?.receipt?.evidence = evidence
        }
        if let started = laneStartedAt.removeValue(forKey: provider) {
            compareResults[provider]?.receipt?.elapsedMilliseconds = max(0, Int((monotonicTime() - started) * 1000))
        }
        replyOwners[provider] = nil
        replyTasks[provider] = nil
        laneTimeoutTasks.removeValue(forKey: provider)?.cancel()
        isWorking = !replyOwners.isEmpty
        if provider == .qwen, let receipt = compareResults[provider]?.receipt,
           (receipt.requestID == knowledgeMethodDraftRequestID || receipt.requestID == knowledgeConceptDraftRequestID) {
            // Acquisition uses Qwen temporarily without changing the user's
            // selected chat route or its readiness after the draft ends.
            assistantProvider = route.primaryProvider
            refreshRouteConnection()
        }
        if !isWorking, let receipt = compareResults[provider]?.receipt,
           receipt.pointing != nil, spatialPreview?.ticket == receipt.context {
            invalidatePlacementPreview(reason: "Point and explain finished.")
        }
    }

    private func closeConnection(_ provider: AssistantProvider) {
        connectionGenerations[provider, default: 0] &+= 1
        connectionTasks.removeValue(forKey: provider)?.cancel()
        assistants[provider]?.disconnect()
        connectionStates[provider] = .disconnected
        refreshRouteConnection()
    }

    private func cancelLane(_ provider: AssistantProvider, reason: String) {
        guard replyOwners[provider] != nil else { return }
        replyTasks[provider]?.cancel()
        finishOwnership(provider)
        closeConnection(provider)
        if provider == .qwen {
            compareResults[provider]?.receipt?.admissionOutcome = HamptonAdmissionOutcome(status: .stopped,
                stage: compareResults[provider]?.receipt?.requestStarted == true ? .generation : .connection,
                role: nil, requestID: nil, reason: .cancelled)
        }
        setLane(provider, text: "", status: reason, state: .cancelled)
        connectionMessages[provider] = "Response stopped. Connect again when you are ready."
        if provider == .qwen { hamptonSnapshot.proposal = nil }
        if provider == assistantProvider { reply = "The previous response was stopped." }
        if !isWorking { replySourceSelection = nil }
        refreshRouteConnection()
        refreshWorkStatus()
    }

    private func cancelLocalWork(reason: String) {
        cancelActiveARC(reason: reason)
        arc3.stop(reason: reason)
        let hadLocalWork = replyOwners[.qwen] != nil
        cancelLane(.qwen, reason: reason)
        if route == .native { cancelLane(.codex, reason: reason) }
        if hadLocalWork && !isWorking && route == .local { workGeneration &+= 1 }
        // Completed local answers can refer to excerpts that have just been
        // revoked, so remove that lane while leaving Codex's result intact.
        if compareResults[.qwen] != nil { setLane(.qwen, text: "", status: reason, state: .cancelled) }
    }

    private func failLane(_ provider: AssistantProvider, message: String) {
        // This cleanup never starts external work. Only finishFailedAttempt
        // can apply the captured route's explicit fallback permission.
        replyTasks[provider]?.cancel()
        finishOwnership(provider)
        closeConnection(provider)
        connectionStates[provider] = .failed
        connectionMessages[provider] = message
        setLane(provider, text: "", status: message, state: .failed)
        workingCopyNotice = "\(provider.name) could not finish · your working copy is unchanged."
        if provider == .qwen { hamptonSnapshot.proposal = nil }
        if provider == assistantProvider { reply = message }
        if !isWorking && route != .compare { replySourceSelection = nil }
        refreshRouteConnection()
        refreshWorkStatus()
    }

    /// Called only for a caught provider failure or the owned reply deadline.
    /// Invalid proposals, storage failures and cancellations never grant fallback.
    private func finishFailedAttempt(_ provider: AssistantProvider, error: any Error, message: String,
                                     request: AssistantRequest, ticket: ContextTicket, route: AssistantRoute,
                                     requestID: String, inputDigest: String, pointing: AssistantPointingSnapshot?,
                                     allowsExternalFallback: Bool) {
        let local = assistants[provider] as? HamptonReasonsAssistant
        let failedRole = local?.snapshot.admissionOutcome?.role
        let optionalContextFailure = local?.optionalContextActive == true
            || failedRole == .memorySelection || failedRole == .memoryReminder
        let eligible = allowsExternalFallback && provider == .qwen && route == .native && self.route == .native
            && !optionalContextFailure
            && (request.localReading?.references.isEmpty ?? true)
            && compareResults[provider]?.receipt?.readingDependencies == nil
            && compareResults[provider]?.receipt?.knowledgeDependencies == nil
            && request.localKnowledge == nil && request.localProcedureKnowledge == nil && !request.isKnowledgeAcquisition
            && NativeAssistantFallback.isEligible(error) && compareResults[.codex] == nil
        failLane(provider, message: message)
        guard eligible, !isShuttingDown, isCurrentContent(ticket) else { return }
        guard desktopInterestSource == nil || desktopInterestExternalDigest == LessonSource.digest(of: sharedText) else {
            status = "Local Qwen is unavailable. This window copy is local-only; allow this exact copy before using an external route."
            return
        }
        if let pointing, !isCurrent(ticket, requireVisible: false) || !isCurrentPointing(pointing) { return }
        do {
            try retryStewardReceipts()
            try tokenSteward.registerFallback(requestID: requestID)
        } catch {
            stewardMessage = "External fallback was not started: \(error.localizedDescription)"
            status = stewardMessage ?? "Fallback accounting unavailable"
            return
        }
        let external = AssistantRequest(prompt: request.prompt, sourceName: request.sourceName,
            sourceText: request.sourceText, sourceRevision: request.sourceRevision,
            placementRevision: request.placementRevision, settings: request.settings,
            selection: request.selection, revisionTarget: request.revisionTarget, companion: request.companion)
        assistantProvider = .codex
        replySourceSelection = request.selection
        isWorking = true
        launchLane(.codex, request: external, ticket: ticket, route: route, requestID: requestID,
            inputDigest: inputDigest, pointing: pointing,
            routingReason: "Local Qwen could not finish: \(message) One Codex fallback; no local lessons, personal context or prior conversation forwarded.")
        status = "Qwen unavailable · using Codex fallback"
    }

    private func setLane(_ provider: AssistantProvider, text: String? = nil, status: String, state: AssistantLaneState) {
        guard var result = compareResults[provider] else { return }
        let recordsTerminalOutcome = result.state == .pending && state != .pending
        if let text { result.text = text }
        if state == .cancelled || state == .failed {
            if let receipt = result.receipt {
                self.retireDocumentWork(requestID: receipt.requestID, provider: provider, failed: state == .failed)
            }
            result.revision = nil
            // A store-owned timeout can end the lane before the coordinator's
            // terminal callback. Retire only unfinished attempts in the captured
            // receipt; completed responses keep their reported work and outcome.
            let invocations = result.receipt?.localInvocationReceipts?.map { invocation in
                var terminal = invocation
                if terminal.outcome == .dispatched {
                    terminal.outcome = state == .cancelled ? .cancelled : .failed
                }
                return terminal
            }
            result.receipt?.localInvocationReceipts = invocations
        }
        result.status = status; result.state = state; result.receipt?.state = state
        compareResults[provider] = result
        if provider == .qwen, let id = knowledgeConceptDraftRequestID, result.receipt?.requestID == id {
            knowledgeConceptDraftMessage = status
            if state == .failed || state == .cancelled { knowledgeConceptDraft = nil }
        }
        if provider == .qwen, result.receipt?.requestID == knowledgeMethodDraftRequestID {
            knowledgeMethodDraftMessage = status
            if state == .failed || state == .cancelled { knowledgeMethodDraft = nil }
        }
        if recordsTerminalOutcome, let receipt = result.receipt {
            let key = receipt.requestID + ":" + receipt.provider.rawValue
            pendingStewardReceipts[key] = receipt
            do { try tokenSteward.recordLane(receipt); pendingStewardReceipts[key] = nil }
            catch { stewardMessage = "Answer usage could not be saved: \(error.localizedDescription)" }
        }
    }

    private func retryStewardReceipts() throws {
        for (key, receipt) in pendingStewardReceipts {
            try tokenSteward.recordLane(receipt)
            pendingStewardReceipts[key] = nil
        }
        for (key, event) in pendingStewardEvaluations {
            try tokenSteward.recordEvaluation(taskID: event.taskID, evidenceID: event.evidenceID,
                passed: event.passed, startedAt: event.startedAt, finishedAt: event.finishedAt,
                sourceStatus: event.sourceStatus, error: event.error,
                localSolver: event.localSolver, cancelled: event.cancelled,
                proposalInference: event.proposalInference, proposalInProgress: event.proposalInProgress)
            pendingStewardEvaluations[key] = nil
        }
        for (key, summary) in pendingARC3Summaries {
            try tokenSteward.recordInteractiveARC(summary)
            pendingARC3Summaries[key] = nil
        }
        for requestID in pendingStewardUseful {
            try tokenSteward.recordUseful(requestID: requestID)
            pendingStewardUseful.remove(requestID)
        }
    }

    func retryStewardAccounting() {
        do { try tokenSteward.refresh(); try retryStewardReceipts(); stewardMessage = nil }
        catch { stewardMessage = "Usage journal still needs attention: \(error.localizedDescription)" }
    }

    func recordARCEvaluation(_ event: ARCCapabilitiesEvent) {
        pendingStewardEvaluations[event.taskID] = event
        do {
            try retryStewardReceipts()
            stewardMessage = nil
        } catch { stewardMessage = "ARC evidence remains separate; usage journal failed: \(error.localizedDescription)" }
    }

    func recordUsefulReply(requestID: String) {
        pendingStewardUseful.insert(requestID)
        do { try retryStewardReceipts(); stewardMessage = nil }
        catch { stewardMessage = "Usefulness could not be recorded in Token Steward: \(error.localizedDescription)" }
    }

    private func refreshRouteConnection() {
        if route == .compare {
            let states = route.providers.map { connection(for: $0) }
            connectionState = states.allSatisfy { $0 == .ready } ? .ready
                : states.contains(.connecting) ? .connecting : states.contains(.failed) ? .failed : .disconnected
            connectionMessage = route.providers.map { "\($0.name): \(connection(for: $0).rawValue)" }.joined(separator: " · ")
        } else {
            connectionState = connection(for: assistantProvider)
            connectionMessage = message(for: assistantProvider)
        }
    }

    private func refreshWorkStatus() {
        isWorking = !replyOwners.isEmpty
        if knowledgeConceptDraftRequestID != nil {
            status = knowledgeConceptDraftMessage ?? "Concept draft"
            return
        }
        if knowledgeMethodDraftPage != nil {
            status = knowledgeMethodDraftMessage ?? "Method candidate"
        } else if route == .compare {
            if isWorking { status = "Waiting for " + route.providers.filter { replyOwners[$0] != nil }.map(\.name).joined(separator: " and ") + "…" }
            else {
                let completed = compareResults.values.filter { $0.state == .complete }.count
                status = completed == 2 ? "Comparison ready · independent answers" : completed == 1 ? "One answer ready · other lane did not finish" : "No completed answers"
            }
        } else if let result = compareResults[assistantProvider] {
            if result.state == .complete { status = sourceName == nil ? "Reply ready" : "Reply ready · shared copy revision \(sourceRevision)" }
            else { status = result.status }
        }
    }

    // Item recipes and acquisition claims share the profile's atomic admission.
    func marketItemAcquisition(for item: CompanionItemPackage) -> MarketplaceItemAcquisition? {
        preferenceDocument.itemAcquisitions?.first { $0.matches(item) }
    }

    @discardableResult
    func collectMarketDownload(_ download: MarketplaceDownloadedItem) -> Bool {
        guard marketplaceCatalog.isCurrent(download) else {
            marketplaceMessage = "This download is no longer current. Download it again from the signed-in account library."
            return false
        }
        return collectMarketItem(download.recipe, acquisition: download.acquisition)
    }

    @discardableResult
    func collectMarketItem(_ item: CompanionItemPackage, acquisition: MarketplaceItemAcquisition? = nil) -> Bool {
        guard !isShuttingDown else {
            marketplaceMessage = "Choose a valid item recipe before adding it."; return false
        }
        let review = item.review
        guard review.isValid else {
            marketplaceMessage = review.correctionMessage; return false
        }
        guard acquisition?.matches(item) ?? true else {
            marketplaceMessage = "The acquisition record does not match this exact design. Nothing was added."; return false
        }
        let saved = marketItemAcquisition(for: item)
        guard acquisition == nil || saved == nil || saved == acquisition else {
            marketplaceMessage = "This design already has a different acquisition record. Its saved provenance was preserved."; return false
        }
        let alreadyCollected = itemLibrary.contains(where: { $0.id == item.id })
        if alreadyCollected {
            guard profileRecoveryBlock == nil, preferenceFileReadable, preferenceBaselineKnownCurrent,
                  let disk = try? NativePreferencePersistence.read(preferenceURL), disk.baseline == preferenceBaseline else {
                marketplaceMessage = "The saved collection changed outside this session. Reopen ARCHi before adding this design."
                return false
            }
        }
        guard !alreadyCollected || (acquisition != nil && saved == nil) else {
            marketplaceMessage = "This exact design is already in My items."; return true
        }
        guard alreadyCollected || itemLibrary.count < CompanionItemPackage.maximumLibraryCount else {
            marketplaceMessage = "Your local Alpha collection holds eight designs. Remove one before adding another."; return false
        }
        var next = preferenceDocument
        if !alreadyCollected { next.itemLibrary.append(item) }
        if let acquisition { next.itemAcquisitions = (next.itemAcquisitions ?? []) + [acquisition] }
        guard commitPreferenceDocument(next) else { marketplaceMessage = status; return false }
        marketplaceMessage = alreadyCollected
            ? "Saved this design's catalog acquisition declaration on this Mac. Legal ownership has not been verified."
            : "Added \(item.title) to My items on this Mac. Choose Equip when ready."
        return true
    }

    @discardableResult
    func equipMarketItem(_ item: CompanionItemPackage) -> Bool {
        guard !isShuttingDown, item.isValid, itemLibrary.contains(item) else {
            marketplaceMessage = "Add this design to My items before equipping it."; return false
        }
        preferences.equipment = CompanionEquipment(hand: .focusStaff, design: item)
        if !marketplaceOutfitReadable {
            marketplaceMessage = "\(item.title) equipped for this visit. The saved outfit could not be read."
        } else if savedMarketplaceEquipment == preferences.equipment {
            marketplaceMessage = "\(item.title) equipped. This outfit is also saved for the next visit."
        } else if savedMarketplaceEquipment != nil {
            marketplaceMessage = "\(item.title) equipped for this visit. Your saved outfit is unchanged; review Save choices in What I remember to update it."
        } else {
            marketplaceMessage = "\(item.title) equipped for this visit. Save choices in What I remember to wear it next time."
        }
        return true
    }

    @discardableResult
    func unequipMarketItem(_ item: CompanionItemPackage) -> Bool {
        guard !isShuttingDown, item.isValid,
              preferences.equipment == CompanionEquipment(hand: .focusStaff, design: item) else {
            marketplaceMessage = "This design is not available to unequip from the current outfit."
            return false
        }
        preferences.equipment = .empty
        if !marketplaceOutfitReadable {
            marketplaceMessage = "\(item.title) unequipped for this visit. The saved outfit could not be read."
        } else if savedMarketplaceEquipment != nil {
            marketplaceMessage = "\(item.title) unequipped for this visit. Your saved outfit is unchanged."
        } else {
            marketplaceMessage = "\(item.title) unequipped for this visit. No outfit is saved for the next visit."
        }
        return true
    }

    func canUseMarketItemInWorkTogether(_ item: CompanionItemPackage) -> Bool {
        !isShuttingDown && item.isValid && itemLibrary.contains(item)
            && preferences.equipment == CompanionEquipment(hand: .focusStaff, design: item)
            && preferences.equipment.supportsPointing
    }

    /// This shortcut only opens the existing workspace. Pointing, reading a
    /// source, and asking a model remain separate actions owned by Work together.
    @discardableResult
    func useMarketItemInWorkTogether(_ item: CompanionItemPackage) -> Bool {
        guard canUseMarketItemInWorkTogether(item) else {
            marketplaceMessage = "Equip this pointing design from My items before using it in Work together."
            return false
        }
        open(.context)
        marketplaceMessage = "Work together is ready. Select a passage, then choose Point with staff to use \(item.title)."
        return true
    }

    @discardableResult
    func removeMarketItem(_ item: CompanionItemPackage) -> Bool {
        guard !isShuttingDown, itemLibrary.contains(item) else { return false }
        var next = preferenceDocument
        next.itemLibrary.removeAll { $0.id == item.id }
        next.itemAcquisitions?.removeAll { $0.recipeID == item.id }
        if next.itemAcquisitions?.isEmpty == true { next.itemAcquisitions = nil }
        if next.preferences?.equipment.design?.id == item.id { next.preferences?.equipment = .empty }
        guard commitPreferenceDocument(next) else { marketplaceMessage = status; return false }
        if preferences.equipment.design?.id == item.id { preferences.equipment = .empty }
        marketplaceMessage = "Removed \(item.title) from this Mac and any saved outfit. Other choices remain yours."
        return true
    }

    func importMarketItem() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Review a local ARCHi design recipe before adding it. Maximum 4 KB."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw CompanionItemPackageError.invalidPackage
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: CompanionItemPackage.maximumBytes + 1) ?? Data()
            importedMarketItem = try CompanionItemPackage.decode(data)
            marketplaceMessage = "Recipe read. Review its appearance, action and attribution before Add to My items."
        } catch { importedMarketItem = nil; marketplaceMessage = error.localizedDescription }
    }

    func exportMarketItem(_ item: CompanionItemPackage) {
        do {
            let data = try item.encoded()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "ARCHi-item-\(item.id.prefix(8)).json"
            panel.message = "Shares this design and its declared license. No personal memory, companion identity or ownership record is included."
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            marketplaceMessage = "Exported a copyable design recipe. Export does not create an edition or transfer ownership."
        } catch { marketplaceMessage = "Could not export the item: \(error.localizedDescription)" }
    }

    func savePreferences() {
        guard rememberPreferences else { status = "Preferences apply to this visit."; return }
        guard preferences.isValid else { status = "Choose valid appearance and reply settings before saving."; return }
        var document = preferenceDocument
        document.preferences = preferences
        if commitPreferenceDocument(document) {
            status = "Preferences saved on this device."
        }
    }

    func forgetPreferences() {
        var document = preferenceDocument
        document.preferences = nil
        if commitPreferenceDocument(document) {
            rememberPreferences = false
            status = "Saved appearance and rhythm removed. Kept lessons and current visit are unchanged."
        }
    }

    func contextTicket() -> ContextTicket {
        ContextTicket(generation: workGeneration, placement: placementRevision, source: sourceRevision, selection: selectionRevision)
    }

    /// Only the native document and window adapters supply observations. A reply
    /// or generated body has no path into this local geometry contract.
    func previewPlacement() {
        stopKinLightPreview()
        stopHarmonyTheme()
        invalidatePlacementPreview(reason: "Preview replaced.")
        let ticket = contextTicket()
        guard isVisible, !isWorking, let selection = textSelection,
              selection.matches(text: sharedText, sourceRevision: sourceRevision),
              let geometry = onObserveSelectedPassage?(), geometry.selection == selection,
              let environment = onObserveSpatialEnvironment?(),
              let display = environment.displays.first(where: { $0.id == geometry.screenID }),
              display.frame == geometry.screenFrame,
              let candidate = SpatialPlacementPlanner.propose(geometry: geometry,
                  companionFrame: environment.companionFrame, visibleDisplay: display.visibleFrame),
              isCurrent(ticket) else {
            spatialMessage = "Keep the whole selected passage visible and ARCHi shown, then preview again."
            return
        }
        presentPlacementPreview(candidate: candidate, geometry: geometry, environment: environment, ticket: ticket)
    }

    private func presentPlacementPreview(candidate: SpatialPlacementCandidate, geometry: SelectedPassageGeometry,
                                         environment: SpatialEnvironment, ticket: ContextTicket) {
        let now = monotonicTime()
        guard now.isFinite, now >= 0 else { return }
        let preview = SpatialPreview(id: UUID(), candidate: candidate, geometry: geometry,
                                     environment: environment, ticket: ticket, createdAt: now)
        spatialPreview = preview
        spatialRecorder.capture(preview, now: now)
        refreshSpatialRecordingState()
        spatialMessage = candidate.reason
        onPresentPlacementPreview?(preview)
        record("Placement preview created from the current shared passage")
        previewExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(SpatialPreview.lifetime))
            guard !Task.isCancelled else { return }
            self?.expirePlacementPreview()
        }
    }

    func dismissPlacementPreview() {
        invalidatePlacementPreview(reason: "Preview dismissed. ARCHi stayed in place.", recordingOutcome: .dismissed)
    }

    func invalidatePlacementPreview(reason: String, recordingOutcome: SpatialRecordingOutcome = .invalidated) {
        retireFocusGesture(message: reason)
        guard let preview = spatialPreview else { return }
        // Applying consumes the on-screen preview before moving. Its recording
        // stays pending until the actual result has been observed below.
        if recordingOutcome != .pending {
            spatialRecorder.finish(previewID: preview.id, kind: recordingOutcome, now: monotonicTime())
            refreshSpatialRecordingState()
        }
        previewExpiryTask?.cancel(); previewExpiryTask = nil
        spatialPreview = nil
        onPresentPlacementPreview?(nil)
        spatialMessage = reason
    }

    func expirePlacementPreview() {
        guard let preview = spatialPreview else { return }
        if !preview.isFresh(at: monotonicTime()) {
            invalidatePlacementPreview(reason: "Preview expired. Preview again using the current passage.", recordingOutcome: .expired)
        }
    }

    func applyPlacementPreview() {
        guard let preview = spatialPreview else { return }
        guard preview.isFresh(at: monotonicTime()) else {
            invalidatePlacementPreview(reason: "Preview expired. Preview again using the current passage.", recordingOutcome: .expired)
            return
        }
        // The complete observation is reacquired immediately before mutation.
        // No await, animation, or model call can intervene in this local step.
        guard !isWorking, isCurrent(preview.ticket), preview.isFresh(at: monotonicTime()),
              textSelection == preview.geometry.selection,
              preview.geometry.selection.matches(text: sharedText, sourceRevision: sourceRevision),
              onObserveSelectedPassage?() == preview.geometry,
              onObserveSpatialEnvironment?() == preview.environment,
              isCurrent(preview.ticket), spatialPreview?.id == preview.id,
              let move = onMoveCompanion else {
            invalidatePlacementPreview(reason: "The passage, display, or ARCHi changed. Preview again.")
            return
        }
        invalidatePlacementPreview(reason: "Applying the reviewed placement…", recordingOutcome: .pending)
        if preview.candidate.staysPut {
            spatialRecorder.finish(previewID: preview.id, kind: .stayed,
                actualFrame: preview.environment.companionFrame, now: monotonicTime())
            refreshSpatialRecordingState()
            spatialMessage = "ARCHi stayed here. The selected passage remains clear."
            record("Current placement retained after a fresh layout check")
            return
        }
        move(preview.candidate.frame)
        // Inspect the frame AppKit actually accepted. A request alone is not a move receipt.
        let receipt = SpatialPlacementReceipt(requestedFrame: preview.candidate.frame,
                                              actualFrame: onObserveSpatialEnvironment?()?.companionFrame)
        lastPlacementReceipt = receipt
        spatialRecorder.finish(previewID: preview.id, kind: receipt.matched ? .moved : .unconfirmed,
            actualFrame: receipt.actualFrame, now: monotonicTime())
        refreshSpatialRecordingState()
        if receipt.matched {
            spatialMessage = "ARCHi moved beside the passage. Select again to continue from his new position."
            record("Reviewed placement applied and actual frame checked")
        } else {
            spatialMessage = "The requested placement was not confirmed. Preview again from ARCHi’s current position."
            record("Requested placement did not match the observed frame")
        }
    }

    func startSpatialRecording() {
        guard !spatialRecorder.isRecording else { return }
        spatialRecorder.clear()
        spatialRecorder.start()
        refreshSpatialRecordingState()
        spatialRecordingMessage = "Recording locally. Return to Shared context and try placement previews."
    }

    func stopSpatialRecording() {
        spatialRecorder.stop(now: monotonicTime())
        refreshSpatialRecordingState()
        spatialRecordingMessage = "Stopped · \(spatialRecordCount) placement previews retained locally."
    }

    func clearSpatialRecording() {
        guard !spatialRecorder.isRecording else { return }
        spatialRecorder.clear()
        refreshSpatialRecordingState()
        spatialRecordingMessage = "Recording cleared from this session. Exported files are unchanged."
    }

    /// Exact stopped projection used by the save action and cross-runtime tests.
    /// Its Codable contract excludes source text and identifying metadata.
    func spatialRecordingData() throws -> Data { try spatialRecorder.exportData() }

    func exportSpatialRecording() {
        do {
            let data = try spatialRecordingData()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "archi-placement-recording.json"
            panel.message = "Save geometry and timing for local Node Lab replay. No document text or filenames are included."
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            spatialRecordingMessage = "Recording exported. Import this JSON in Node Lab → Native recordings."
        } catch let error as SpatialRecordingError {
            spatialRecordingMessage = error.localizedDescription
        } catch {
            spatialRecordingMessage = "Could not write the recording. Choose a writable location and try again."
        }
    }

    private func refreshSpatialRecordingState() {
        let wasRecording = isRecordingSpatial
        isRecordingSpatial = spatialRecorder.isRecording
        spatialRecordCount = spatialRecorder.records.count
        if spatialRecorder.limitReached {
            spatialRecordingMessage = "Recording stopped at 100 previews. Export or start a new recording."
        } else if wasRecording && !isRecordingSpatial {
            spatialRecordingMessage = "Recording stopped. Retained previews are available for export."
        }
    }

    /// Used by future asynchronous adapters immediately before publishing a contextual result.
    func isCurrent(_ ticket: ContextTicket, requireVisible: Bool = true) -> Bool {
        (!requireVisible || isVisible) && ticket == contextTicket()
    }

    /// Ordinary content work depends on the request, source and exact selection.
    /// Companion movement changes presentation but cannot change those inputs.
    /// Hide, close, source replacement and profile changes still revoke work
    /// through their existing generation/selection invalidation paths.
    func isCurrentContent(_ ticket: ContextTicket) -> Bool {
        ticket.generation == workGeneration && ticket.source == sourceRevision
            && ticket.selection == selectionRevision
    }

    /// A pointing receipt retains its additional placement and live geometry
    /// requirements, including when a completed answer is reviewed later.
    func isCurrentReplyContext(_ receipt: AssistantLaneReceipt) -> Bool {
        guard isCurrentContent(receipt.context), readingDependenciesAreCurrent(receipt.readingDependencies),
              knowledgeDependenciesAreCurrent(receipt.knowledgeDependencies) else { return false }
        if receipt.provider == .qwen, !localPreferenceMemoryIsCurrent { return false }
        guard let pointing = receipt.pointing else { return true }
        return isCurrent(receipt.context, requireVisible: false) && isCurrentPointing(pointing)
    }

    private func record(_ message: String) {
        activity.append(message)
        if activity.count > 40 { activity.removeFirst(activity.count - 40) }
    }
}

// The existing preference owner is the only durable lesson write boundary.
// Model clients receive immutable snapshots and have no way to keep a lesson.
extension CompanionStore {
    var currentTaskScope: HamptonTaskScope {
        if !selectedKnowledgePages.isEmpty { return .conversation }
        if requestsRevision { return .passageRevision }
        return sourceName == nil ? .conversation : .documentQuestion
    }
    var currentLessonSource: LessonSource? {
        guard let name = sourceName else { return nil }
        return LessonSource(name: name, digest: SHA256.hash(data: Data(sharedText.utf8))
            .map { String(format: "%02x", $0) }.joined())
    }

    var nextReplyLessons: [LessonSnapshot] {
        route == .codex ? [] : matchingLessons(question: prompt)
    }

    func matchingLessons(question: String, taskScope: HamptonTaskScope? = nil) -> [LessonSnapshot] {
        dependencyBoundedLessons(question: question, taskScope: taskScope ?? currentTaskScope).snapshots
    }

    /// Separate from a blocked-request reason: an otherwise valid local reply
    /// can proceed with the lessons that fit its exact dependency envelope.
    var nextReplyKnowledgeOmissionMessage: String? {
        guard route != .codex else { return nil }
        let count = dependencyBoundedLessons(question: prompt, taskScope: currentTaskScope).omissionCount
        guard count > 0 else { return nil }
        let subject = count == 1 ? "1 saved lesson will" : "\(count) saved lessons will"
        return subject + " be left out of this reply to keep its combined page and source references within the local context limit. Your saved lessons are unchanged."
    }

    private func dependencyBoundedLessons(question: String, taskScope: HamptonTaskScope)
        -> (snapshots: [LessonSnapshot], omissionCount: Int) {
        guard localPreferenceMemoryIsCurrent else { return ([], 0) }
        func union<T: Equatable>(_ lhs: [T], _ rhs: [T]) -> [T] {
            rhs.reduce(into: lhs) { if !$0.contains($1) { $0.append($1) } }
        }
        var pages = selectedKnowledgePages
        var sources = currentKnowledgeContext?.readingSources ?? []
        if selectedKnowledgePages.isEmpty, taskScope == .documentQuestion,
           sourceName != nil, !sharedText.isEmpty {
            sources = union(sources, currentReadingReferences.map(\.binding))
        }
        if !nextReplyConversation.isEmpty {
            pages = union(pages, localConversationKnowledgePages ?? [])
            sources = union(sources, localConversationReadingSources ?? [])
        }
        let now = wallClock()
        var snapshots: [LessonSnapshot] = []
        var omissionCount = 0
        // Retain persisted lesson order. Exact duplicates share a binding;
        // differing versions of one identity remain a conflict, never a merge.
        for lesson in keptLessons where (selectedKnowledgePages.isEmpty || lesson.source == nil)
            && lessonDependenciesAreCurrent(lesson.origin)
            && lesson.matches(question: question, sourceName: sourceName,
                sourceText: sharedText, now: now, taskScope: taskScope) {
            let nextPages = union(pages, lesson.origin?.knowledgePages ?? [])
            let nextSources = union(sources, lesson.origin?.readingSources ?? [])
            guard KnowledgePageBinding.valid(nextPages.isEmpty ? nil : nextPages),
                  ReadingSourceBinding.valid(nextSources.isEmpty ? nil : nextSources) else {
                omissionCount += 1
                continue
            }
            pages = nextPages
            sources = nextSources
            snapshots.append(LessonSnapshot(lesson: lesson))
        }
        return (snapshots, omissionCount)
    }

    func currentKeptLesson(matching snapshot: LessonSnapshot) -> KeptLesson? {
        guard localPreferenceMemoryIsCurrent else { return nil }
        return keptLessons.first {
            LessonSnapshot(lesson: $0) == snapshot && $0.isValid && lessonDependenciesAreCurrent($0.origin)
                && ($0.expiresAt == nil || $0.expiresAt! > wallClock())
        }
    }

    /// Rebuild the local structure study from current owners, never graph size
    /// or particle count. Reading this projection cannot save or award a body.
    var liveLiminalPointStructure: LiminalPointStructure? {
        LiminalV008Runtime.asset.flatMap { liminalPointStructure(sessionID: liminalStructureSessionID, asset: $0) }
    }

    func liminalFormDevelopment(at now: Date = Date()) -> LiminalFormDevelopment.Snapshot? {
        guard let individual = activeQiMon, individual.isValid,
              profileRecoveryBlock == nil, !isShuttingDown,
              let disk = try? NativePreferencePersistence.read(preferenceURL), disk.baseline == preferenceBaseline,
              evolution.observedJourneyOriginDigest == nil || evolution.observedJourneyOriginDigest == individual.originDigest,
              evolution.practiceJourneyOriginDigest == nil || evolution.practiceJourneyOriginDigest == individual.originDigest
        else { return nil }
        let available = Set(keptLessons.filter {
            currentKeptLesson(matching: LessonSnapshot(lesson: $0)) != nil
                && ($0.source == nil || $0.source == currentLessonSource)
        }.map(\.id))
        let feedbackCurrent = documentWork.isCurrentOnDisk && tokenSteward.isCurrentOnDisk
            && evolution.historicalEvidenceUnavailableReason == nil && evolution.persistenceBlockedReason == nil
        let withdrawn = HamptonMemoryDependencies.withdrawnDevelopmentReadings(tasks: tokenSteward.tasks)
            .union(documentWork.records.compactMap { record in
                guard let feedback = record.feedback, feedback.verdict != .helpful else { return nil }
                return UUID(uuidString: record.requestID)
            })
        return LiminalFormDevelopment.build(originDigest: individual.originDigest, lessons: keptLessons,
            currentLessonIDs: available, receipts: evolution.usefulReceipts.filter { !withdrawn.contains($0.requestID) },
            evidenceOrigin: feedbackCurrent ? evolution.practiceJourneyOriginDigest : nil, now: now,
            currentKnowledgePages: readingSources.latestKnowledgePages.filter { readingSources.availability(of: $0) == nil })
    }

    /// Explicit user action. The study can use the current profile's reviewed
    /// references without inventing per-receipt individual attribution.
    @discardableResult func connectLiminalLearningStudy() -> Bool {
        guard !isWorking, let individual = activeQiMon,
              liminalFormDevelopment(at: wallClock()) != nil,
              evolution.persistenceBlockedReason == nil,
              documentWork.isCurrentOnDisk, tokenSteward.isCurrentOnDisk else { return false }
        return evolution.bindPracticeJourney(individual.originDigest)
    }

    func lessonAvailability(_ lesson: KeptLesson) -> String {
        if !lessonDependenciesAreCurrent(lesson.origin) { return "Supporting reading copy changed or was forgotten · review this lesson before reuse" }
        if let expiry = lesson.expiresAt, expiry <= wallClock() { return "Expired · revise to use again" }
        if let source = lesson.source, source != currentLessonSource {
            return "Waiting for the same shared copy · \(source.name)"
        }
        if let scope = lesson.taskScope {
            return "\(scope.title) · " + (scope == currentTaskScope ? "matches this activity" : "available for that activity")
        }
        return "Available when your question contains “\(lesson.topic)”"
    }

    func beginLessonCorrection(for provider: AssistantProvider? = nil, revisingID: String? = nil) {
        guard !isShuttingDown else { return }
        if provider == .qwen, !requireCurrentLocalPreferenceMemory() { return }
        if let provider, compareResults[provider]?.receipt?.isKnowledgeAcquisition == true { return }
        if let revisingID {
            guard let prior = keptLessons.first(where: { $0.id == revisingID }) else { return }
            lessonDraft = LessonCorrectionDraft(lessonID: prior.id, expectedRevision: lessonRevision,
                prior: prior, topic: prior.topic, text: prior.text, reason: prior.reason,
                source: prior.origin?.knowledgePages == nil ? prior.source : nil,
                origin: prior.origin, expiresAt: prior.expiresAt,
                taskScope: prior.origin?.knowledgePages == nil ? prior.taskScope : .conversation)
        } else {
            var origin: LessonOrigin?
            if let provider, let result = compareResults[provider], result.state == .complete,
               !result.text.isEmpty, let receipt = result.receipt {
                origin = LessonOrigin(requestID: receipt.requestID, inputDigest: receipt.inputDigest,
                    readingSources: receipt.readingDependencies, knowledgePages: receipt.knowledgeDependencies)
            }
            lessonDraft = LessonCorrectionDraft(expectedRevision: lessonRevision, prior: nil, origin: origin,
                taskScope: origin?.knowledgePages == nil ? nil : .conversation)
        }
        lessonMessage = "Review the lesson and when to use it. Nothing is saved until you press Keep."
        open(.memory)
    }

    func discardLessonDraft() {
        lessonDraft = nil
        lessonMessage = "Draft discarded. Nothing was saved."
    }

    @discardableResult
    func keepLesson(_ draft: LessonCorrectionDraft) -> Bool {
        guard !isShuttingDown, draft.expectedRevision == lessonRevision,
              draft.prior == keptLessons.first(where: { $0.id == draft.lessonID }),
              (draft.lessonID == nil) == (draft.prior == nil) else {
            lessonMessage = "Saved choices changed while this draft was open. Close it and review a fresh draft."
            return false
        }
        if let source = draft.source, source != currentLessonSource {
            lessonMessage = "The shared copy changed. Share the original copy again, or remove its scope before keeping."
            return false
        }
        guard lessonDependenciesAreCurrent(draft.origin) else {
            lessonMessage = "A supporting reading copy changed or was forgotten. Start a fresh review using current sources."
            return false
        }
        if draft.origin?.knowledgePages != nil, draft.taskScope != .conversation || draft.source != nil {
            lessonMessage = "A lesson supported by knowledge pages must use local chat without an exact shared-copy restriction. Review a fresh Chat draft before keeping."
            return false
        }
        let now = wallClock()
        guard draft.prior?.revision != UInt64.max else { return false }
        let lesson = KeptLesson(id: draft.lessonID ?? UUID().uuidString,
            revision: (draft.prior?.revision ?? 0) + 1,
            topic: draft.topic.trimmingCharacters(in: .whitespacesAndNewlines),
            text: draft.text.trimmingCharacters(in: .whitespacesAndNewlines),
            reason: draft.reason.trimmingCharacters(in: .whitespacesAndNewlines),
            source: draft.source, origin: draft.origin,
            createdAt: draft.prior?.createdAt ?? now, updatedAt: now, expiresAt: draft.expiresAt, taskScope: draft.taskScope)
        guard lesson.isValid, lesson.expiresAt == nil || lesson.expiresAt! > now else {
            lessonMessage = "Use a topic phrase of 2–80 characters, a lesson of 1–600 characters, an optional reason up to 300 characters, and a future expiry if set."
            return false
        }
        var document = preferenceDocument
        if let index = document.lessons.firstIndex(where: { $0.id == lesson.id }) {
            document.lessons[index] = lesson
        } else {
            guard document.lessons.count < NativePreferenceDocument.maximumLessons else {
                lessonMessage = "You can keep up to 16 lessons. Withdraw an unused lesson before adding another."
                return false
            }
            document.lessons.append(lesson)
        }
        guard commitPreferenceDocument(document) else { return false }
        if draft.prior != nil { revokeLocalLessonSnapshot(lesson.id) }
        lessonDraft = nil
        lessonMessage = "Lesson kept on this Mac. It will be considered for the next matching local question."
        status = lessonMessage
        return true
    }

    @discardableResult
    func withdrawLesson(id: String, expectedRevision: UInt64) -> Bool {
        guard !isShuttingDown, expectedRevision == lessonRevision,
              keptLessons.contains(where: { $0.id == id }) else {
            lessonMessage = "Saved lessons changed. Review the current list before withdrawing."
            return false
        }
        var document = preferenceDocument
        document.lessons.removeAll { $0.id == id }
        guard commitPreferenceDocument(document) else { return false }
        revokeLocalLessonSnapshot(id)
        if lessonDraft?.lessonID == id { lessonDraft = nil }
        lessonMessage = "Lesson withdrawn from this Mac. It will not be included in future replies."
        status = lessonMessage
        return true
    }

    func lessonExportData() throws -> Data {
        var export = preferenceDocument
        export.preferences = nil
        export.focusGesture = nil
        export.qiMon = nil
        export.itemLibrary = []
        export.itemAcquisitions = nil
        export.personalContext = nil
        return try export.encoded()
    }

    func exportLessons() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ARCHi-kept-lessons.json"
        panel.message = "Exports all kept lessons, including expired ones, their text and source references. Appearance, conversations and Journey are excluded."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try lessonExportData().write(to: url, options: .atomic)
            lessonMessage = "Exported \(keptLessons.count) kept lessons, including expired or unavailable ones."
        } catch { lessonMessage = "Could not export lessons. The saved originals are unchanged." }
    }

    var personalContext: PersonalContext? { preferenceDocument.personalContext }

    /// The loaded envelope owns saved private context and lessons. Another
    /// session's correction or forget must revoke their cached and indirect use,
    /// just as a changed kept-source journal revokes its request snapshots.
    private var localPreferenceMemoryIsCurrent: Bool {
        guard preferenceDocument.personalContext != nil || !preferenceDocument.lessons.isEmpty else { return true }
        guard preferenceFileReadable, preferenceBaselineKnownCurrent, profileRecoveryBlock == nil else { return false }
        do { return try NativePreferencePersistence.read(preferenceURL).baseline == preferenceBaseline }
        catch { return false }
    }

    private func requireCurrentLocalPreferenceMemory() -> Bool {
        guard !localPreferenceMemoryIsCurrent else { return true }
        preferenceBaselineKnownCurrent = false
        clearSessionContext()
        let reason = "Saved personal context or lessons changed outside this session. Reopen ARCHi before using local memory again."
        localConversationNotice = reason
        lessonMessage = reason
        if assistantProvider == .qwen { reply = reason }
        status = reason
        return false
    }

    @discardableResult
    func updatePersonalContext(_ value: PersonalContext?, expected: PersonalContext?) -> Bool {
        guard !isShuttingDown, preferenceDocument.personalContext == expected,
              value?.isValid ?? true else {
            status = "Profile changed or needs correction. Review the current context before saving."
            return false
        }
        var document = preferenceDocument
        var next = value
        if let expected, next != nil { next?.revision = expected.revision + 1 }
        document.personalContext = next
        guard commitPreferenceDocument(document) else { return false }
        // A correction/forget must not leak an old profile through follow-ups,
        // pending callbacks, optional context banks or a stale visible answer.
        cancelWork(reason: "Personal context updated. Earlier replies cleared.")
        clearSessionContext()
        clearLocalConversation()
        status = next == nil ? "Personal context forgotten on this Mac." : "Personal context saved · local Qwen only."
        objectWillChange.send()
        return true
    }

    private func commitPreferenceDocument(_ proposed: NativePreferenceDocument) -> Bool {
        guard profileRecoveryBlock == nil else {
            lessonMessage = profileRecoveryBlock ?? "Resolve profile recovery before saving."
            status = lessonMessage
            return false
        }
        guard preferenceFileReadable, preferenceDocument.revision < UInt64.max else {
            lessonMessage = "The saved settings file is unavailable. It has been preserved; reopen after restoring a valid file."
            status = lessonMessage
            return false
        }
        var next = proposed
        next.revision = preferenceDocument.revision + 1
        do {
            let baseline = try NativePreferencePersistence.write(document: next, to: preferenceURL, expected: preferenceBaseline)
            // Atomic write completes before any admitted state or request changes.
            preferenceBaseline = baseline
            preferenceBaselineKnownCurrent = true
            preferenceDocument = next
            keptLessons = next.lessons
            keptFocusGesture = next.focusGesture
            keptQiMon = next.qiMon
            itemLibrary = next.itemLibrary
            lessonRevision = next.revision
            return true
        } catch {
            // A known external edit invalidates claims about the next visit's
            // outfit without replacing the last admitted profile or its owner.
            if let preferenceError = error as? NativePreferenceError {
                switch preferenceError {
                case .conflict, .invalidLocation:
                    preferenceBaselineKnownCurrent = false
                default:
                    break
                }
            }
            lessonMessage = "Could not save: \(error.localizedDescription) Previous saved choices are unchanged."
            status = lessonMessage
            return false
        }
    }

    private func bindDocumentDataOwners() {
        documentMethodToTry = nil
        documentDataSubscriptions.removeAll()
        // Token Steward installs its immutable journal before publishing revision.
        // Read that owner's fresh task projection, not a duplicate feedback store.
        self.tokenSteward.$revision.sink { [weak self] _ in
            guard let self else { return }
            let excluded = HamptonMemoryDependencies.invalidatedReadings(tasks: self.tokenSteward.tasks)
            self.evolution.setReadingFeedbackExclusions(
                HamptonMemoryDependencies.withdrawnDevelopmentReadings(tasks: self.tokenSteward.tasks))
            if !self.localConversationRequestIDs.isDisjoint(with: excluded) {
                self.invalidateCorrectedReadingContinuation()
            }
        }.store(in: &documentDataSubscriptions)
        self.documentWork.$records.sink { [weak self] records in
            self?.evolution.setDocumentFeedbackExclusions(Set(records.compactMap { record in
                guard let feedback = record.feedback, feedback.verdict != .helpful else { return nil }
                return UUID(uuidString: record.requestID)
            }))
        }.store(in: &documentDataSubscriptions)
        self.documentWork.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &documentDataSubscriptions)
        self.documentProcedures.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &documentDataSubscriptions)
        self.readingSources.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &documentDataSubscriptions)
    }

    // Recovery is a file operation followed by admission through these existing
    // owners. The backup view never becomes a second source of companion state.
    var recoveryPreferenceURL: URL { preferenceURL }

    var recoveryBusyReason: String? {
        if isShuttingDown { return "ARCHi is closing. Reopen before managing backups." }
        if isWorking { return "Finish or stop the current reply before managing backups." }
        if voiceInput.isActive { return "Finish or cancel dictation before managing backups." }
        if pendingDocumentReceipt != nil { return "Save the pending document receipt before managing backups." }
        if connectionStates.values.contains(.connecting) { return "Wait for the current connection attempt to finish." }
        return nil
    }

    var recoveryRestoreBlockReason: String? {
        if let recoveryBusyReason { return recoveryBusyReason }
        if profileRecoveryBlock == nil, evolution.hasUnsavedChanges { return "Save or review your Evolution changes before restoring." }
        if profileRecoveryBlock == nil, preferences != (preferenceDocument.preferences ?? CompanionPreferences()) {
            return "Save your changed appearance and rhythm settings before restoring."
        }
        if pastedDocumentDraft.hasContent { return "Use or discard the pasted text draft before restoring." }
        if lessonDraft != nil { return "Keep or discard the lesson draft before restoring." }
        if hasOpenKnowledgeDraft { return "Save or discard the knowledge page or connection draft before restoring." }
        if focusGestureDraft != nil { return "Keep or discard the gesture draft before restoring." }
        if voiceInput.phase == .review { return "Use or discard the voice draft before restoring." }
        return nil
    }

    var hasUnreviewedRecoveryChoices: Bool {
        evolution.hasUnsavedChanges || preferences != (preferenceDocument.preferences ?? CompanionPreferences())
    }

    var recoveryStamp: DesktopRestoreStamp {
        DesktopRestoreStamp(preferences: preferences, preferenceBaseline: preferenceBaseline,
            lessonRevision: lessonRevision, evolutionRevision: evolution.revision)
    }

    /// The caller has already verified the restored pair and retained rollback.
    /// No provider invocation, new identity, or save is performed during reload.
    func admitRestoredProfile() throws {
        let loaded = try NativePreferencePersistence.read(preferenceURL)
        let restoredWork = DocumentWorkJournal(url: preferenceURL.deletingPathExtension().appendingPathExtension("document-work.json"))
        let restoredMethods = DocumentProcedureLibrary(url: preferenceURL.deletingPathExtension().appendingPathExtension("document-procedures.json"))
        let restoredSources = ReadingSourceLibrary(url: preferenceURL.deletingPathExtension().appendingPathExtension("reading-sources.json"))
        guard restoredWork.loadError == nil, restoredMethods.loadError == nil, restoredSources.loadError == nil else {
            throw DesktopRecoveryError.blocked("The restored document work could not be loaded.")
        }
        cancelWork(reason: "Saved profile restored. Earlier replies and references cleared.")
        selectedReadingSourceIDs = []
        selectedKnowledgePageID = nil
        selectedKnowledgePages = []
        knowledgePageMessage = nil
        documentReadingPreview = nil
        arc3.resetForProfile()
        lastARC3Summary = nil
        clearSessionContext()
        compareResults = [:]
        invalidateTextSelection(reason: "Saved profile restored. Select a passage again.")
        requestsRevision = false
        workingCopyUndo = nil
        clearPreparedDocumentProcedure()
        documentProcedureRequests = [:]
        documentWorkMessage = nil
        documentReadingMessage = nil
        documentWork = restoredWork
        documentProcedures = restoredMethods
        readingSources = restoredSources
        bindDocumentDataOwners()
        evolution.historicalEvidenceUnavailableReason = nil
        stopFocusGesture()
        reactor.stop(reason: "Saved profile restored. Local artwork is active.")
        evolution.persistenceBlockedReason = nil
        guard evolution.loadRestoredProfile(origin: loaded.document.preferences?.form ?? .companion) else {
            throw DesktopRecoveryError.blocked("The restored development could not be loaded. " + evolution.status)
        }
        importedMarketItem = nil
        preferenceDocument = loaded.document
        preferenceBaseline = loaded.baseline
        preferenceFileReadable = true
        preferenceBaselineKnownCurrent = true
        preferences = loaded.document.preferences ?? CompanionPreferences()
        rememberPreferences = loaded.document.preferences != nil
        keptLessons = loaded.document.lessons
        keptFocusGesture = loaded.document.focusGesture
        keptQiMon = loaded.document.qiMon
        itemLibrary = loaded.document.itemLibrary
        lessonRevision = loaded.document.revision
        profileRecoveryBlock = nil
        lessonMessage = "Saved lessons restored. Historical development references do not recreate forgotten lessons."
        reply = "Your saved profile is restored. Your current typed draft and working document are still here."
        status = "Profile restored · saved choices loaded"
        refreshReactorReference()
    }

    func blockProfileForRecovery(_ reason: String) {
        cancelWork(reason: "Profile recovery needs review.")
        clearSessionContext()
        compareResults = [:]
        profileRecoveryBlock = reason
        preferenceFileReadable = false
        evolution.persistenceBlockedReason = reason
        documentWork = DocumentWorkJournal(url: preferenceURL.deletingPathExtension().appendingPathExtension("document-work.json"), recoveryBlocked: true)
        documentProcedures = DocumentProcedureLibrary(url: preferenceURL.deletingPathExtension().appendingPathExtension("document-procedures.json"), recoveryBlocked: true)
        readingSources = ReadingSourceLibrary(url: preferenceURL.deletingPathExtension().appendingPathExtension("reading-sources.json"), recoveryBlocked: true)
        bindDocumentDataOwners()
        evolution.historicalEvidenceUnavailableReason = reason
        workingCopyUndo = nil
        clearPreparedDocumentProcedure()
        selectedReadingSourceIDs = []
        selectedKnowledgePageID = nil
        selectedKnowledgePages = []
        knowledgePageMessage = nil
        documentReadingPreview = nil
        status = reason
    }

    private func revokeLocalLessonSnapshot(_ id: String) {
        let heldLesson = compareResults[.qwen]?.receipt?.localLessons.contains(where: { $0.id == id }) == true
        // Removing or changing a lesson also clears possible earlier excerpts.
        // The existing lane owner fences late events; Codex keeps its own work.
        clearSessionContext()
        if heldLesson { compareResults[.qwen] = nil }
        if assistantProvider == .qwen { reply = "Local lesson changed. Send a new question when you are ready." }
    }

    var effectiveFocusGesture: FocusGestureConfiguration {
        keptFocusGesture ?? preferences.equipment.design?.defaultGesture ?? FocusGestureConfiguration()
    }

    // The staff's learned preference uses the existing preference file. Playback
    // is a short-lived presentation of an explicit command, never a new action owner.
    func beginFocusGestureTeaching() {
        stopFocusGesture()
        focusGestureDraft = effectiveFocusGesture
        focusGestureMessage = "Adjust, preview, then keep the gesture you prefer."
    }

    func cancelFocusGestureTeaching() {
        stopFocusGesture()
        focusGestureDraft = nil
        focusGestureMessage = "Changes discarded. Your kept gesture is unchanged."
    }

    func previewFocusGesture() {
        guard !isShuttingDown, let configuration = focusGestureDraft else { return }
        stopFocusGesture()
        startFocusGesture(configuration: configuration, purpose: .preview, spatialPreviewID: nil)
    }

    @discardableResult
    func keepFocusGesture() -> Bool {
        guard !isShuttingDown, let configuration = focusGestureDraft else { return false }
        var proposed = preferenceDocument
        proposed.focusGesture = configuration
        guard commitPreferenceDocument(proposed) else {
            focusGestureMessage = status
            return false
        }
        stopFocusGesture()
        focusGestureDraft = nil
        focusGestureMessage = "Gesture kept on this Mac. Point with staff will use it next time."
        return true
    }

    @discardableResult
    func forgetFocusGesture() -> Bool {
        guard !isShuttingDown, keptFocusGesture != nil else { return false }
        var proposed = preferenceDocument
        proposed.focusGesture = nil
        guard commitPreferenceDocument(proposed) else {
            focusGestureMessage = status
            return false
        }
        stopFocusGesture()
        focusGestureDraft = nil
        focusGestureMessage = "Kept gesture forgotten. The staff uses its this design’s default cue."
        return true
    }

    @discardableResult
    func practiceFocusGesture() -> Bool {
        guard let configuration = focusGestureDraft else { return false }
        return performFocusGestureOnSelection(configuration: configuration, purpose: .practice)
    }

    @discardableResult
    func performFocusGestureOnSelection(configuration: FocusGestureConfiguration, purpose: FocusGesturePurpose) -> Bool {
        guard purpose != .preview, preferences.equipment.supportsPointing, !isShuttingDown else {
            focusGestureMessage = "Equip the Focus Staff before practicing on a passage."
            return false
        }
        previewPlacement()
        guard let preview = spatialPreview else {
            focusGestureMessage = spatialMessage
            return false
        }
        startFocusGesture(configuration: configuration, purpose: purpose, spatialPreviewID: preview.id)
        return focusGesturePlayback != nil
    }

    func stopFocusGesture() {
        if focusGesturePlayback?.purpose == .explaining, isWorking {
            cancelWork(reason: "Point and explain stopped.")
            return
        }
        let isPointing = focusGesturePlayback?.spatialPreviewID != nil
        retireFocusGesture(message: "Gesture stopped.")
        if isPointing { invalidatePlacementPreview(reason: "Gesture stopped. ARCHi stayed in place.") }
    }

    private func retireFocusGesture(message: String) {
        focusGestureTask?.cancel()
        focusGestureTask = nil
        if focusGesturePlayback != nil {
            focusGesturePlayback = nil
            focusGestureMessage = message
        }
    }

    private func startFocusGesture(configuration: FocusGestureConfiguration, purpose: FocusGesturePurpose,
                                   spatialPreviewID: UUID?) {
        let now = monotonicTime()
        guard now.isFinite, now >= 0 else { return }
        retireFocusGesture(message: "Gesture replaced.")
        let playback = FocusGesturePlayback(configuration: configuration, startedAt: now,
            purpose: purpose, spatialPreviewID: spatialPreviewID)
        focusGesturePlayback = playback
        focusGestureMessage = purpose == .preview ? "Previewing here. ARCHi stays in place."
            : purpose == .practice ? "Practicing your draft on the selected passage. Nothing sent."
            : purpose == .explaining ? "Pointing while ARCHi explains the selected passage."
            : "Pointing with your staff gesture. Nothing sent."
        focusGestureTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled, let self, self.focusGesturePlayback?.id == playback.id else { return }
                guard self.validateFocusGesturePlayback(id: playback.id) else { return }
            }
        }
    }

    /// Reobserve while pointing so missed scroll/window notifications cannot
    /// leave the short cue attached to stale geometry. The task owns no movement.
    @discardableResult
    func validateFocusGesturePlayback(id: UUID) -> Bool {
        guard let playback = focusGesturePlayback, playback.id == id else { return false }
        let now = monotonicTime()
        if let previewID = playback.spatialPreviewID {
            guard isVisible, (!isWorking || playback.purpose == .explaining), preferences.equipment.supportsPointing,
                  let preview = spatialPreview, preview.id == previewID,
                  preview.isFresh(at: now), isCurrent(preview.ticket),
                  textSelection == preview.geometry.selection,
                  preview.geometry.selection.matches(text: sharedText, sourceRevision: sourceRevision),
                  onObserveSelectedPassage?() == preview.geometry,
                  onObserveSpatialEnvironment?() == preview.environment else {
                if playback.purpose == .explaining, isWorking {
                    cancelWork(reason: "The passage or ARCHi changed. Select the current passage and explain again.")
                } else {
                    invalidatePlacementPreview(reason: "The passage or ARCHi changed. Practice again from the current selection.")
                }
                return false
            }
        }
        guard playback.isFresh(at: now) else {
            retireFocusGesture(message: "Gesture finished. You can adjust it or use it again.")
            return false
        }
        return true
    }
}

// Shared request ownership also owns invalidation after reading-copy changes.
extension CompanionStore {
    /// Invalidate the request owner and all indirect transient context too.
    /// Persistent lessons retain their provenance and become unavailable through
    /// their exact source-version dependency checks, rather than being erased.
    func invalidateReadingContext(reason: String) {
        cancelWork(reason: reason)
        clearSessionContext()
        compareResults = [:]
        documentReadingPreview = nil
        documentReadingMessage = reason
        // Keep the exact method binding with any instruction still in the
        // composer. Its source checks will now block stale use. Clearing only
        // the binding would turn that instruction into unqualified plain text;
        // the prepared-method UI provides an explicit Detach action instead.
    }

}
