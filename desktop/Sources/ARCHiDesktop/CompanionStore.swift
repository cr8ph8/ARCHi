import AppKit
import Combine
import UniformTypeIdentifiers
import CryptoKit

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case assistant = "Assistant"
    case nodeLab = "Node Lab"
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
    var id: String { rawValue }

    /// Related local drawings of the same companion, not additional individuals.
    var isOpticalLight: Bool { self == .corePearl || self == .orbitField || self == .lightForm }
    static var opticalLightChoices: [Self] { [.corePearl, .orbitField, .lightForm] }
}

struct CompanionPreferences: Codable, Equatable {
    var form: CompanionForm = .companion
    var visualTreatment: CompanionVisualTreatment = .original
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
        equipment.isValid && size.isFinite && (0.65...1.6).contains(size)
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
        form = try values.decode(CompanionForm.self, forKey: .form)
        visualTreatment = try values.decodeIfPresent(CompanionVisualTreatment.self, forKey: .visualTreatment) ?? .original
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
    /// Desktop delivery may suspend the game without altering its saved data.
    let allowsPlay: Bool
    @Published var section: WorkspaceSection = .assistant {
        didSet {
            if section == .play && !allowsPlay { section = .assistant; return }
            if section != oldValue, focusGesturePlayback != nil { stopFocusGesture() }
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
        didSet {
            // Undoing an edit restores bytes, not a previously granted allowance.
            if !sharedText.utf8.elementsEqual(oldValue.utf8) {
                desktopInterestExternalDigest = nil
                // Direct writes must fence queued dispatch and late events too.
                cancelWork(reason: "Working-copy bytes changed; earlier requests cleared.")
                clearSessionContext()
            }
        }
    }
    let desktopInterest: DesktopInterestSession
    @Published private(set) var desktopInterestSource: DesktopInterestSource?
    @Published private(set) var desktopInterestExternalDigest: String?
    @Published var sourceName: String?
    @Published var sourceRevision: UInt64 = 0
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
    @Published private(set) var workingCopyNotice = "Select a passage to begin."
    private var workingCopyUndo: WorkingCopyEditReceipt?
    private var openedWorkingCopyDigest: String?
    private var exportedWorkingCopyDigest: String?
    var hasUnexportedWorkingCopy: Bool {
        guard sourceName != nil, let openedWorkingCopyDigest else { return false }
        let current = SHA256.hash(data: Data(sharedText.utf8)).map { String(format: "%02x", $0) }.joined()
        return current != openedWorkingCopyDigest && current != exportedWorkingCopyDigest
    }
    private var importedSourceURL: URL?
    @Published var activity: [String] = []
    @Published var isWorking = false
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
    @Published private(set) var sessionContextEnabled = false
    @Published private(set) var localConversation = AssistantConversation()
    @Published private(set) var localConversationEnabled = true
    @Published private(set) var localConversationNotice = "Recent Qwen exchanges stay in this visit only."
    private var localConversationExpiry: Date?
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
    @Published var status = "Desktop preview · assistant not connected"
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
    private var preferenceDocument = NativePreferenceDocument()
    private var preferenceBaseline: Data?
    private var preferenceFileReadable = true
    private var preferenceBaselineKnownCurrent = true
    @Published private(set) var profileRecoveryBlock: String?
    private let wallClock: () -> Date
    let evolution: EvolutionStore
    let reactor = ReactorExpressionStore()
    private var evolutionSubscriptions = Set<AnyCancellable>()
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
        case "ARCHiDesktopReview": "Development Review"
        case "ARCHiDesktop": "ARCHi"
        default: "Custom local profile"
        }
    }

    var nextReplySettings: AssistantSettingsSnapshot {
        AssistantSettingsSnapshot(tone: preferences.tone, replyLength: preferences.replyLength,
            role: evolution.confirmedRole, helpStyle: evolution.confirmedHelpStyle)
    }

    var assistantActivity: AssistantActivity {
        AssistantActivity.derive(owned: Set(replyOwners.keys), results: compareResults)
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
        return KinLightRules.resolve(activity: assistantActivity, hasFreshFocus: hasFreshKinFocus,
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
        let identity = role == .cursor && activeQiMon != nil ? "KIN · Seed cursor. " : ""
        return identity + CompanionVisualAsset.label(form: presentationForm(for: preferences, role: role), family: presentationFamily,
            treatment: preferences.visualTreatment, recipe: presentationRecipe,
            naturalVariation: presentationNaturalVariation, equipment: preferences.equipment) + ". Assistant: " + assistantActivity.title + cue
            + (activeQiMon == nil ? "" : ". Light expression: " + kinLightExpression(for: preferences).label)
            + (desktopInterest.phase == .idle ? "" : ". Object of interest: " + desktopInterest.message)
    }

    var nextCallBudget: String {
        let local = sessionContextEnabled ? "1 local answer call, plus up to 2 context calls" : "1 local answer call"
        switch route {
        case .local: return local
        case .codex: return "1 Codex request"
        case .compare: return local + " · 1 Codex request"
        case .automatic: return local + " · no external requests"
        }
    }

    var canBeginReply: Bool { !isShuttingDown && !voiceInput.isActive && canShareDesktopInterestWithRoute
        && (route == .automatic || connectionState == .ready) }

    var canShareDesktopInterestWithRoute: Bool {
        desktopInterestSource == nil || route == .local || route == .automatic
            || desktopInterestExternalDigest == LessonSource.digest(of: sharedText)
    }

    func allowDesktopInterestWithExternalRoute() {
        guard !isShuttingDown, desktopInterestSource != nil,
              route == .codex || route == .compare else { return }
        desktopInterestExternalDigest = LessonSource.digest(of: sharedText)
        status = "This exact copy may be sent with your selected route. Nothing sent yet."
    }
    var resultProviders: [AssistantProvider] { route.providers }

    var nextReplyConversation: [AssistantConversationExchange] {
        localConversationEnabled && route != .codex
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
        clearSessionContext()
        localConversationNotice = "New local conversation. Your draft, shared copy and kept lessons are unchanged."
        if assistantProvider == .qwen { reply = "What would you like to work on?" }
        if !isWorking { status = localConversationNotice }
    }

    private func clearLocalConversation() {
        localConversation.clear()
        localConversationExpiry = nil
        localConversationNotice = "Recent Qwen exchanges stay in this visit only."
    }

    init(preferenceURL: URL? = nil, assistant: (any AssistantClient)? = nil,
         provider: AssistantProvider = .qwen,
         assistantFactory: @escaping @MainActor (AssistantProvider, String) -> any AssistantClient = { provider, model in
             provider == .qwen ? HamptonReasonsAssistant(model: model) : CodexAssistant()
         },
         monotonicTime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         wallClock: @escaping () -> Date = Date.init, allowsPlay: Bool = true,
         voiceInput: VoiceInputController? = nil, interestReader: (any DesktopInterestReading)? = nil) {
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
        // A prepared recovery journal is resolved before either saved owner is
        // admitted. A conflicting interrupted restore leaves both owners closed.
        let startupRecoveryBlock = DesktopRecoveryStartup.recoverIfNeeded(at: resolvedPreferenceURL)
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
        if let saved = initialPreferences {
            preferences = saved
            rememberPreferences = true
        }
        bindHamptonAssistant()
        evolution.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &evolutionSubscriptions)
        reactor.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &evolutionSubscriptions)
        self.voiceInput.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &evolutionSubscriptions)
        desktopInterest.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &evolutionSubscriptions)
        $compareResults.combineLatest($isWorking).receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }; self.reactor.updateCue(self.assistantActivity)
        }.store(in: &evolutionSubscriptions)
        refreshReactorReference()
        lastEvolutionAppearanceID = CompanionVisualAsset.appearanceID(form: presentationForm,
            family: presentationFamily, treatment: preferences.visualTreatment, recipe: presentationRecipe, naturalVariation: presentationNaturalVariation)
        evolution.$revision.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            let id = CompanionVisualAsset.appearanceID(form: self.presentationForm, family: self.presentationFamily,
                treatment: self.preferences.visualTreatment, recipe: self.presentationRecipe, naturalVariation: self.presentationNaturalVariation)
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
        invalidateTextSelection(reason: "ARCHi moved. Select the passage again to restore its reference.")
        cancelWork(reason: "Placement changed; old spatial work cancelled.")
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
        let destination = section == .play && !allowsPlay ? .assistant : section
        self.section = destination
        onOpenWorkspace?(destination)
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

    func chooseDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .utf8PlainText, .text]
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
        sharedText = text
        openedWorkingCopyDigest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        exportedWorkingCopyDigest = nil
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
        alert.informativeText = "Your working copy has edits that have not been exported. Keep working to export a separate draft, or discard these session edits. The original file stays unchanged."
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
        sharedText = ""; sourceName = nil; sourceRevision &+= 1
        openedWorkingCopyDigest = nil; exportedWorkingCopyDigest = nil
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
            && canBeginReply
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
        requestsRevision = true
        prompt = shorten ? "Shorten the selected passage while preserving its meaning."
            : "Make the selected passage clearer while preserving its meaning."
        status = "Revision prepared · describe what you want, then Send"
    }

    var canUndoWorkingCopyEdit: Bool {
        workingCopyUndo?.canUndo(text: sharedText, revision: sourceRevision) == true
    }

    /// A candidate stays inside its original lane until this explicit action.
    /// There is no await between checking the exact source and replacing it.
    func applyPassageRevision(provider: AssistantProvider, targetID: String) {
        guard let lane = compareResults[provider], lane.state == .complete,
              let proposal = lane.revision, proposal.decision == .propose,
              proposal.target.id == targetID, let receipt = lane.receipt,
              isCurrent(receipt.context, requireVisible: false),
              textSelection == proposal.target.selection else {
            workingCopyNotice = "This revision is no longer current. Select the passage and request a new one."; return
        }
        do {
            let before = sharedText
            let after = try WorkingCopyEditReceipt.applying(proposal: proposal, to: before, sourceRevision: sourceRevision)
            // Cancels a still-running Compare sibling and revokes both previews.
            invalidateTextSelection(reason: "A reviewed revision was applied.")
            cancelWork(reason: "Working copy changed; earlier proposals cleared.")
            clearSessionContext()
            sharedText = after
            sourceRevision &+= 1
            compareResults = [:]
            workingCopyUndo = WorkingCopyEditReceipt(before: before,
                afterDigest: SHA256.hash(data: Data(after.utf8)).map { String(format: "%02x", $0) }.joined(),
                afterRevision: sourceRevision)
            requestsRevision = false
            guard sharedText.utf8.elementsEqual(after.utf8), canUndoWorkingCopyEdit else {
                workingCopyNotice = "The working copy could not be verified."; return
            }
            workingCopyNotice = "Applied to working copy · Undo is available. Export to keep a separate draft."
            reply = proposal.explanation
            status = "Reviewed revision applied · original file unchanged"
            record("Applied reviewed \(provider.name) passage revision \(targetID) to working copy revision \(sourceRevision)")
        } catch {
            workingCopyNotice = "This revision could not be applied to the current copy. Nothing changed."
        }
    }

    func dismissPassageRevision(provider: AssistantProvider) {
        guard compareResults[provider]?.state == .complete else { return }
        compareResults[provider]?.revision = nil
        compareResults[provider]?.status = "Revision dismissed · copy unchanged"
        workingCopyNotice = "Revision dismissed · your working copy is unchanged."
    }

    func undoWorkingCopyEdit() {
        guard let undo = workingCopyUndo, undo.canUndo(text: sharedText, revision: sourceRevision) else {
            workingCopyNotice = "That Undo belongs to an earlier copy and cannot change this one."; return
        }
        invalidateTextSelection(reason: "Working-copy revision undone.")
        cancelWork(reason: "Working-copy revision undone.")
        clearSessionContext()
        sharedText = undo.before
        sourceRevision &+= 1
        compareResults = [:]
        workingCopyUndo = nil
        requestsRevision = false
        workingCopyNotice = "Undone · the exact previous working copy is restored."
        status = workingCopyNotice
        record("Undid working-copy edit; source revision \(sourceRevision)")
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
        let hadDerivedReply = !compareResults.isEmpty || hamptonSnapshot.proposal != nil
        workGeneration &+= 1
        for provider in Array(replyOwners.keys) { cancelLane(provider, reason: reason) }
        // Completed lanes are also bound to the superseded request ticket.
        for provider in Array(compareResults.keys) {
            setLane(provider, text: "", status: reason, state: .cancelled)
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

    private func submit(question: String, pointing: AssistantPointingSnapshot?) -> Bool {
        guard !isShuttingDown else { return false }
        guard canShareDesktopInterestWithRoute else {
            status = "This window snapshot stays local. Allow this exact copy for your external route, or choose Local Qwen. Nothing sent."
            return false
        }
        guard !voiceInput.isActive else {
            status = "Finish or cancel voice input before sending. Your draft is unchanged."
            return false
        }
        if let expiry = localConversationExpiry, expiry <= wallClock() {
            clearLocalConversation()
            localConversationNotice = "A lesson used earlier expired. Recent conversation was cleared before this request."
        }
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard question.utf8.count <= 16_000 else { status = "Keep the message below 16 KB. Nothing was sent."; return false }
        guard textSelection == nil || textSelection?.matches(text: sharedText, sourceRevision: sourceRevision) == true else {
            invalidateTextSelection(reason: "The selected passage is no longer current. Nothing was sent.")
            return false
        }
        let revisionTarget: RevisionTarget?
        if requestsRevision && pointing == nil {
            guard let selection = textSelection,
                  let target = RevisionTarget(text: sharedText, sourceRevision: sourceRevision, selection: selection) else {
                status = "Select a current passage before requesting a revision. Nothing was sent."; return false
            }
            revisionTarget = target
        } else { revisionTarget = nil }
        cancelWork(reason: "New request replaces prior work.")
        let selectedRoute = route
        guard selectedRoute == .automatic || selectedRoute.providers.allSatisfy({ connection(for: $0) == .ready }) else {
            replySourceSelection = nil
            compareResults = [:]
            reply = "Connect \(selectedRoute == .compare ? "both assistants" : assistantProvider.name) to send this message. This request has not been sent."
            status = "Not sent · assistant not connected"
            return false
        }
        let ticket = contextTicket()
        if selectedRoute.providers.contains(.qwen) { hamptonSnapshot.proposal = nil }
        let request = AssistantRequest(prompt: question, sourceName: sourceName, sourceText: sharedText,
            sourceRevision: sourceRevision, placementRevision: placementRevision, settings: nextReplySettings,
            selection: textSelection, revisionTarget: revisionTarget, companion: activeQiMon?.character)
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
        assistantProvider = selectedRoute.primaryProvider
        compareResults = [:]
        isWorking = true; reply = ""; status = "Sending · \(selectedRoute.title)…"
        if revisionTarget != nil { workingCopyNotice = "Preparing a revision · your working copy is unchanged." }
        let capturedLessons = matchingLessons(question: request.prompt)
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
                localConversation: provider == .qwen ? capturedConversation : [])
            launchLane(provider, request: laneRequest, ticket: ticket, route: selectedRoute,
                       requestID: requestID, inputDigest: digest, pointing: pointing,
                       routingReason: selectedRoute == .automatic ? "Local Qwen · connects when needed; failures stay on this Mac." : nil,
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
        if route == .automatic, connection(for: provider) != .ready { closeConnection(provider) }
        let assistant = client(for: provider)
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
        compareResults[provider]?.receipt?.localLessons = request.localLessons
        if provider == .qwen {
            let omissions = lessonOmissions(for: request, now: wallClock())
            compareResults[provider]?.receipt?.localLessonOmissions = omissions
        }
        compareResults[provider]?.receipt?.localLessonDigest = request.localLessonDigest
        compareResults[provider]?.receipt?.localConversationCount = request.localConversation.count
        compareResults[provider]?.receipt?.localConversationBytes = request.localConversationUTF8Bytes
        compareResults[provider]?.receipt?.localConversationDigest = request.localConversationDigest
        compareResults[provider]?.receipt?.pointing = pointing
        compareResults[provider]?.receipt?.routingReason = routingReason
        if let local = assistant as? HamptonReasonsAssistant {
            local.mayAdmitResponse = { [weak self, weak local] in
                guard let self, let local else { return false }
                return self.isCurrentLane(provider, owner: owner, epoch: epoch, client: local, ticket: ticket)
            }
            local.onSnapshot = { [weak self, weak local] snapshot in
                guard let self, let local,
                      self.isCurrentLane(provider, owner: owner, epoch: epoch, client: local, ticket: ticket),
                      self.compareResults[provider]?.receipt?.requestStarted == true else { return }
                self.hamptonSnapshot = snapshot
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
            self.failLane(provider, message: "\(provider.name) reached its \(seconds)-second reply limit.")
        }
        replyTasks[provider] = Task { [weak self, assistant] in
            do {
                guard let self, self.isCurrentLane(provider, owner: owner, epoch: epoch, client: assistant, ticket: ticket), !Task.isCancelled else { return }
                if route == .automatic, self.connection(for: provider) != .ready {
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
                self.compareResults[provider]?.receipt?.requestStarted = true
                try await assistant.reply(to: request) { [weak self] event in
                    guard let self, self.isCurrentLane(provider, owner: owner, epoch: epoch, client: assistant, ticket: ticket) else { return }
                    switch event {
                    case .text(let text):
                        guard request.revisionTarget == nil else {
                            self.failLane(provider, message: "The revision response was not a validated proposal."); return
                        }
                        self.setLane(provider, text: text, status: "\(provider.name) is replying…", state: .pending)
                        if provider == self.assistantProvider { self.reply = text }
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
                if request.revisionTarget != nil && self.compareResults[provider]?.revision == nil {
                    self.failLane(provider, message: "No validated revision completed. Your copy is unchanged."); return
                }
                self.finishOwnership(provider)
                self.setLane(provider, status: request.revisionTarget == nil ? "Reply ready" : "Revision ready for review", state: .complete)
                // Only terminal, current local answers become temporary dialogue.
                // Revision proposals, partial output and external answers never enter it.
                if provider == .qwen, request.revisionTarget == nil, self.localConversationEnabled,
                   let answer = self.compareResults[provider]?.text, !answer.isEmpty {
                    if let expiry = conversationExpiry, expiry <= self.wallClock() {
                        self.clearLocalConversation()
                        self.localConversationNotice = "A supplied lesson expired during this reply. This answer was not retained for follow-up."
                    } else {
                        self.localConversationNotice = self.localConversation.retain(question: request.prompt, answer: answer).status
                        self.localConversationExpiry = self.localConversation.exchanges.isEmpty ? nil : conversationExpiry
                    }
                }
                if request.revisionTarget != nil {
                    self.workingCopyNotice = "Review Before and After. Apply changes only the working copy."
                }
                self.refreshWorkStatus()
                self.record("\(provider.name) reply received for shared source revision \(ticket.source)")
            } catch {
                guard let self, self.isCurrentLane(provider, owner: owner, epoch: epoch, client: assistant, ticket: ticket), !Task.isCancelled else { return }
                if provider == .qwen, self.compareResults[provider]?.receipt?.admissionOutcome == nil {
                    self.compareResults[provider]?.receipt?.admissionOutcome = HamptonAdmissionOutcome.failure(error,
                        stage: self.compareResults[provider]?.receipt?.requestStarted == true ? .generation : .connection,
                        role: nil, requestID: nil)
                }
                self.failLane(provider, message: (error as? LocalizedError)?.errorDescription ?? "The assistant connection stopped. Try connecting again.")
            }
        }
    }

    func connection(for provider: AssistantProvider) -> AssistantConnectionState { connectionStates[provider] ?? .disconnected }
    func message(for provider: AssistantProvider) -> String {
        connectionMessages[provider] ?? "Connect \(provider.destination) when you are ready."
    }

    func connectAssistant() { for provider in route.providers { connectAssistant(provider: provider) } }

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
                    ? "\(self.qwenModel) is available locally. Send runs inference on this Mac; the first reply may take longer to load."
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

    func selectQwenModel(_ model: String) {
        guard !isShuttingDown, QwenAssistant.supportedModels.contains(model), model != qwenModel else { return }
        qwenModel = model
        replaceLocalAssistant()
    }

    func selectQwenContextModel(_ model: String) {
        guard !isShuttingDown, QwenAssistant.supportedModels.contains(model), model != qwenContextModel else { return }
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
        assistants[.qwen] = assistantFactory(.qwen, qwenModel)
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
        desktopInterest.cancel(reason: "ARCHi is closing.")
        clearLocalConversation()
        isShuttingDown = true
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
        let created = assistantFactory(provider, qwenModel)
        assistants[provider] = created
        if provider == .qwen { bindHamptonAssistant() }
        return created
    }

    private func isCurrentLane(_ provider: AssistantProvider, owner: UUID, epoch: UInt64,
                               client: any AssistantClient, ticket: ContextTicket) -> Bool {
        guard !isShuttingDown && replyOwners[provider] == owner && assistants[provider] === client
            && connectionGenerations[provider, default: 0] == epoch
            && isCurrent(ticket, requireVisible: false) else { return false }
        // Recheck the actual target before dispatch and every incoming event,
        // even after the short staff animation has completed.
        if let pointing = compareResults[provider]?.receipt?.pointing,
           !isCurrentPointing(pointing) {
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
        setLane(provider, text: "", status: reason, state: .cancelled)
        if provider == .qwen {
            compareResults[provider]?.receipt?.admissionOutcome = HamptonAdmissionOutcome(status: .stopped,
                stage: compareResults[provider]?.receipt?.requestStarted == true ? .generation : .connection,
                role: nil, requestID: nil, reason: .cancelled)
        }
        connectionMessages[provider] = "Response stopped. Connect again when you are ready."
        if provider == .qwen { hamptonSnapshot.proposal = nil }
        if provider == assistantProvider { reply = "The previous response was stopped." }
        if !isWorking { replySourceSelection = nil }
        refreshRouteConnection()
        refreshWorkStatus()
    }

    private func cancelLocalWork(reason: String) {
        let hadLocalWork = replyOwners[.qwen] != nil
        cancelLane(.qwen, reason: reason)
        if hadLocalWork && !isWorking && route == .local { workGeneration &+= 1 }
        // Completed local answers can refer to excerpts that have just been
        // revoked, so remove that lane while leaving Codex's result intact.
        if compareResults[.qwen] != nil { setLane(.qwen, text: "", status: reason, state: .cancelled) }
    }

    private func failLane(_ provider: AssistantProvider, message: String) {
        // A local failure never authorizes external processing. The user can
        // choose an external route and Send a new, visible request instead.
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

    private func setLane(_ provider: AssistantProvider, text: String? = nil, status: String, state: AssistantLaneState) {
        guard var result = compareResults[provider] else { return }
        if let text { result.text = text }
        if state == .cancelled || state == .failed {
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
        if route == .compare {
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

    // Item recipes share the existing profile's atomic admission and recovery.
    @discardableResult
    func collectMarketItem(_ item: CompanionItemPackage) -> Bool {
        guard !isShuttingDown, item.isValid else {
            marketplaceMessage = "Choose a valid item recipe before adding it."; return false
        }
        guard !itemLibrary.contains(where: { $0.id == item.id }) else {
            marketplaceMessage = "This exact design is already in My items."; return true
        }
        guard itemLibrary.count < CompanionItemPackage.maximumLibraryCount else {
            marketplaceMessage = "Your local Alpha collection holds eight designs. Remove one before adding another."; return false
        }
        var next = preferenceDocument
        next.itemLibrary.append(item)
        guard commitPreferenceDocument(next) else { marketplaceMessage = status; return false }
        marketplaceMessage = "Added \(item.title) to My items on this Mac. Choose Equip when ready."
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

    private func record(_ message: String) {
        activity.append(message)
        if activity.count > 40 { activity.removeFirst(activity.count - 40) }
    }
}

// The existing preference owner is the only durable lesson write boundary.
// Model clients receive immutable snapshots and have no way to keep a lesson.
extension CompanionStore {
    var currentLessonSource: LessonSource? {
        guard let name = sourceName else { return nil }
        return LessonSource(name: name, digest: SHA256.hash(data: Data(sharedText.utf8))
            .map { String(format: "%02x", $0) }.joined())
    }

    var nextReplyLessons: [LessonSnapshot] {
        route == .codex ? [] : matchingLessons(question: prompt)
    }

    func matchingLessons(question: String) -> [LessonSnapshot] {
        keptLessons.filter { $0.matches(question: question, sourceName: sourceName,
            sourceText: sharedText, now: wallClock()) }.map(LessonSnapshot.init(lesson:))
    }

    func currentKeptLesson(matching snapshot: LessonSnapshot) -> KeptLesson? {
        keptLessons.first {
            LessonSnapshot(lesson: $0) == snapshot && $0.isValid
                && ($0.expiresAt == nil || $0.expiresAt! > wallClock())
        }
    }

    func lessonAvailability(_ lesson: KeptLesson) -> String {
        if let expiry = lesson.expiresAt, expiry <= wallClock() { return "Expired · revise to use again" }
        if let source = lesson.source, source != currentLessonSource {
            return "Waiting for the same shared copy · \(source.name)"
        }
        return "Available when your question contains “\(lesson.topic)”"
    }

    func beginLessonCorrection(for provider: AssistantProvider? = nil, revisingID: String? = nil) {
        guard !isShuttingDown else { return }
        if let revisingID {
            guard let prior = keptLessons.first(where: { $0.id == revisingID }) else { return }
            lessonDraft = LessonCorrectionDraft(lessonID: prior.id, expectedRevision: lessonRevision,
                prior: prior, topic: prior.topic, text: prior.text, reason: prior.reason,
                source: prior.source, origin: prior.origin, expiresAt: prior.expiresAt)
        } else {
            var origin: LessonOrigin?
            if let provider, let result = compareResults[provider], result.state == .complete,
               !result.text.isEmpty, let receipt = result.receipt {
                origin = LessonOrigin(requestID: receipt.requestID, inputDigest: receipt.inputDigest)
            }
            lessonDraft = LessonCorrectionDraft(expectedRevision: lessonRevision, prior: nil, origin: origin)
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
        let now = wallClock()
        guard draft.prior?.revision != UInt64.max else { return false }
        let lesson = KeptLesson(id: draft.lessonID ?? UUID().uuidString,
            revision: (draft.prior?.revision ?? 0) + 1,
            topic: draft.topic.trimmingCharacters(in: .whitespacesAndNewlines),
            text: draft.text.trimmingCharacters(in: .whitespacesAndNewlines),
            reason: draft.reason.trimmingCharacters(in: .whitespacesAndNewlines),
            source: draft.source, origin: draft.origin,
            createdAt: draft.prior?.createdAt ?? now, updatedAt: now, expiresAt: draft.expiresAt)
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

    // Recovery is a file operation followed by admission through these existing
    // owners. The backup view never becomes a second source of companion state.
    var recoveryPreferenceURL: URL { preferenceURL }

    var recoveryBusyReason: String? {
        if isShuttingDown { return "ARCHi is closing. Reopen before managing backups." }
        if isWorking { return "Finish or stop the current reply before managing backups." }
        if voiceInput.isActive { return "Finish or cancel dictation before managing backups." }
        if connectionStates.values.contains(.connecting) { return "Wait for the current connection attempt to finish." }
        return nil
    }

    var recoveryRestoreBlockReason: String? {
        if let recoveryBusyReason { return recoveryBusyReason }
        if profileRecoveryBlock == nil, evolution.hasUnsavedChanges { return "Save or review your Evolution changes before restoring." }
        if profileRecoveryBlock == nil, preferences != (preferenceDocument.preferences ?? CompanionPreferences()) {
            return "Save your changed appearance and rhythm settings before restoring."
        }
        if lessonDraft != nil { return "Keep or discard the lesson draft before restoring." }
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
        desktopInterestExternalDigest = nil
        let loaded = try NativePreferencePersistence.read(preferenceURL)
        cancelWork(reason: "Saved profile restored. Earlier replies and references cleared.")
        clearSessionContext()
        compareResults = [:]
        invalidateTextSelection(reason: "Saved profile restored. Select a passage again.")
        requestsRevision = false
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
        desktopInterestExternalDigest = nil
        cancelWork(reason: "Profile recovery needs review.")
        clearSessionContext()
        compareResults = [:]
        profileRecoveryBlock = reason
        preferenceFileReadable = false
        evolution.persistenceBlockedReason = reason
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
