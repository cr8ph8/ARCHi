import "./styles.css";
import { isPortraitChoice, liminalPortraitLight, LIMINAL_LIGHT_STYLE, portraitLabel,
  visibleLiminalPortrait, type PortraitChoice, type LiminalPortraitChoice } from "./liminal-portrait";
import {
  AURAS,
  CARE_ACTIONS,
  CARE_ACTION_ORDER,
  ROLE_ORDER,
  ROLES,
  collectEcho,
  commitCareAction,
  commitSession,
  createRelayAttempt,
  advanceRelayAttempt,
  commitRelayCompletion,
  deriveActivityMilestones,
  deriveJourneyPassport,
  journeyOriginSha256, commitPracticeCompletion, derivePracticeSummaries, MAX_KEPT_PRACTICES,
  type PracticeAttempt, type PracticeSummary,
  createCareIntent,
  createJourney,
  createPlaySession,
  dominantRole,
  hashString,
  hydrateJourney,
  careHistory,
  playHistory,
  projectCare,
  revisionForJourney,
  seededRandom,
  serializeJourney,
  sha256String,
  stageForJourney,
  type AuraId,
  type CareActionId,
  type CareProjection,
  type FieldEcho,
  type GrowthStageName,
  type Journey,
  type PlaySession,
  type RoleId,
  type StaticZone,
  type RelayAttempt,
} from "./model";
import {
  BROKEN_RELAY_FIELD_LOG,
  BROKEN_RELAY_TRANSMISSIONS,
  type BrokenRelayEvent,
} from "./companion-activities/broken-relay";
import {
  MAX_JOURNEY_ARCHIVE_BYTES,
  compareJourneyLineage,
  inspectJourneyArchive,
  serializeJourneyArchive,
  type JourneyArchivePreview,
  type JourneyRelation,
} from "./journey-portability";
import { parseJsonWithoutDuplicateKeys } from "./strict-json";
import { visualProfileForStage, type GrowthVisualProfile } from "./visual-growth";
import { deviceShellSnapshot, setupDeviceShell, type DeviceShellSnapshot } from "./device-shell";
import { connectDesktopHost, createDesktopInteractionScope, createDownloadLeasePool, type DesktopArenaState, type DesktopArenaAction } from "./desktop-host";
import {
  DEFAULT_PRESENTATION_STATE,
  PRESENTATION_FORMS,
  PRESENTATION_MOTIONS,
  PRESENTATION_VIEWS,
  presentationLabel,
  updatePresentationState,
  type PresentationAction,
  type PresentationForm,
  type PresentationMotion,
  type PresentationState,
  type PresentationView,
} from "./presentation-control";
import {
  PRESENCE_PHASES,
  advancePresenceSequence,
  createPresenceSequence,
  presenceMix,
  presencePhaseForPosition,
  retargetPresenceSequence,
  type PresenceSequenceState,
} from "./presence-sequence";
import {
  protoVisualRigForView,
  type ProtoRigAppendage,
} from "./proto-visual-rig";
import {
  ENCOUNTER_COMPOSITION_VERSION,
  battleEncounterComposition,
  habitatEncounterComposition,
  type BattleTeamEncounterComposition,
} from "./encounter-composition";
import {
  BATTLE_ACTIONS,
  BATTLE_LIMITS,
  BATTLE_TEAM_IDS,
  battleRevision,
  createBattle,
  createBattleCommand,
  choosePracticeCommand,
  resolveBattleRound,
  previewBattleCommand,
  teamIntegrity,
  type BattleAction, type BattleRoundEvent,
  type BattleCommand,
  type BattleQiMonState,
  type BattleState,
  type BattleTeamId,
  type BattleTeamSetup,
  type QiMonCard,
} from "./battle-engine";
import { compareBattleChoices, listBattleChoices, describeBattleAction, displayedBattleRound } from "./battle-presentation";
import { buildBattleReadback } from "./battle-readback";
import {
  bondQiMonPair, createQiMonRoster, discoverQiMon, inspectQiMonRoster, inviteQiMon,
  projectQiMonRoster, revisionForQiMonRoster, selectQiMonTeam, serializeQiMonRoster,
  trainQiMon, type QiMonRoster, type QiMonRosterProjection,
} from "./qimon-roster";
import {
  availableRelayTargets, createRelayBattle, createRelayCommand, resolveRelayRound,
  type RelayBattleState,
} from "./qimon-relay";

declare global {
  interface Window {
    advanceTime: (milliseconds: number) => void;
    render_game_to_text: () => string;
  }
}

type Mode = "habitat" | "field" | "proposal" | "reflection" | "battle" | "relay";

interface Point {
  x: number;
  y: number;
}

interface Particle extends Point {
  vx: number;
  vy: number;
  life: number;
  maxLife: number;
  size: number;
  color: string;
}

interface Star {
  x: number;
  y: number;
  size: number;
  phase: number;
  warmth: number;
}

interface QiMonDrawSpec {
  readonly nativeBody?: boolean;
  readonly role: RoleId;
  readonly seed: string;
  readonly view: PresentationView;
  readonly motion: PresentationMotion;
  readonly scale: number;
  readonly facing: -1 | 1;
  readonly careMood: CareProjection["mood"];
  readonly stageName: GrowthStageName;
  readonly gazeX: number;
}

function element<T extends HTMLElement>(id: string): T {
  const node = document.getElementById(id);
  if (!node) throw new Error(`Missing required element #${id}`);
  return node as T;
}

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.max(minimum, Math.min(maximum, value));
}

function rgba(rgb: readonly number[], alpha: number): string {
  return `rgba(${rgb[0]}, ${rgb[1]}, ${rgb[2]}, ${alpha})`;
}

const canvas = element<HTMLCanvasElement>("field");
const canvasContext = canvas.getContext("2d");
if (!canvasContext) throw new Error("Canvas 2D is required for ARCHi.");
const context: CanvasRenderingContext2D = canvasContext;

const ui = {
  topbar: element<HTMLElement>("topbar"),
  experience: element<HTMLElement>("experience"),
  presenceConsole: element<HTMLElement>("presence-console"),
  presenceState: element<HTMLOutputElement>("presence-state"),
  presenceUnfold: element<HTMLButtonElement>("presence-unfold"),
  presenceReturn: element<HTMLButtonElement>("presence-return"),
  intro: element<HTMLElement>("intro-panel"),
  fieldCopy: element<HTMLElement>("field-copy"),
  proposal: element<HTMLElement>("proposal-panel"),
  reflection: element<HTMLElement>("reflection-panel"),
  reflectionEyebrow: element<HTMLElement>("reflection-eyebrow"),
  begin: element<HTMLButtonElement>("begin-button"),
  exploreDescription: element<HTMLElement>("explore-description"),
  careMood: element<HTMLElement>("care-mood"),
  careResponse: element<HTMLElement>("care-response"),
  careEnergy: element<HTMLMeterElement>("care-energy"),
  careEnergyOutput: element<HTMLElement>("care-energy-output"),
  careCalm: element<HTMLMeterElement>("care-calm"),
  careCalmOutput: element<HTMLElement>("care-calm-output"),
  careCuriosity: element<HTMLMeterElement>("care-curiosity"),
  careCuriosityOutput: element<HTMLElement>("care-curiosity-output"),
  careGreet: element<HTMLButtonElement>("care-greet"),
  careTend: element<HTMLButtonElement>("care-tend"),
  careRest: element<HTMLButtonElement>("care-rest"),
  controlHint: element<HTMLElement>("control-hint"),
  again: element<HTMLButtonElement>("again-button"),
  home: element<HTMLButtonElement>("home-button"),
  sound: element<HTMLButtonElement>("sound-button"),
  install: element<HTMLButtonElement>("install-button"),
  continuityButton: element<HTMLButtonElement>("continuity-button"),
  battleButton: element<HTMLButtonElement>("battle-button"),
  rosterEntry: element<HTMLButtonElement>("roster-entry"),
  rosterPanel: element<HTMLElement>("qimon-roster-panel"),
  rosterClose: element<HTMLButtonElement>("qimon-roster-close"),
  rosterStatus: element<HTMLElement>("qimon-roster-status"),
  rosterOffers: element<HTMLElement>("qimon-offers"),
  rosterMembers: element<HTMLElement>("qimon-members"),
  rosterTeamControls: element<HTMLElement>("qimon-team-controls"),
  rosterTraining: element<HTMLElement>("qimon-training"),
  rosterRelay: element<HTMLElement>("qimon-relay"),
  rosterReview: element<HTMLButtonElement>("qimon-roster-review"),
  rosterFile: element<HTMLInputElement>("qimon-roster-file"),
  rosterImportPreview: element<HTMLElement>("qimon-roster-import-preview"),
  rosterImportTitle: element<HTMLElement>("qimon-roster-import-title"),
  rosterImportDetail: element<HTMLElement>("qimon-roster-import-detail"),
  rosterImportCancel: element<HTMLButtonElement>("qimon-roster-import-cancel"),
  rosterImportConfirm: element<HTMLButtonElement>("qimon-roster-import-confirm"),
  battleRosterReturn: element<HTMLButtonElement>("battle-roster-return"),
  battleOpponentMode: element<HTMLSelectElement>("battle-opponent-mode"),
  battleCommandHelp: element<HTMLElement>("battle-command-help"),
  battlePartnerNote: element<HTMLElement>("battle-partner-note"),
  battlePanel: element<HTMLElement>("battle-panel"),
  battleStatus: element<HTMLElement>("battle-status"),
  battleReturn: element<HTMLButtonElement>("battle-return"),
  battleSetup: element<HTMLElement>("battle-setup"),
  battleCombat: element<HTMLElement>("battle-combat"),
  battleStart: element<HTMLButtonElement>("battle-start"),
  battleOneBond: element<HTMLSelectElement>("battle-one-bond"),
  battleTwoBond: element<HTMLSelectElement>("battle-two-bond"),
  battleOneSize: element<HTMLSelectElement>("battle-one-size"),
  battleTwoSize: element<HTMLSelectElement>("battle-two-size"),
  battleOneAllocation: element<HTMLOutputElement>("battle-one-allocation"),
  battleTwoAllocation: element<HTMLOutputElement>("battle-two-allocation"),
  battleOneName: element<HTMLElement>("battle-one-name"),
  battleTwoName: element<HTMLElement>("battle-two-name"),
  battleOneSpark: element<HTMLElement>("battle-one-spark"),
  battleTwoSpark: element<HTMLElement>("battle-two-spark"),
  battleOneIntegrityFill: element<HTMLElement>("battle-one-integrity-fill"),
  battleTwoIntegrityFill: element<HTMLElement>("battle-two-integrity-fill"),
  battleOneMeta: element<HTMLElement>("battle-one-meta"),
  battleTwoMeta: element<HTMLElement>("battle-two-meta"),
  battleOneRoster: element<HTMLElement>("battle-one-roster"),
  battleTwoRoster: element<HTMLElement>("battle-two-roster"),
  battleRoundLabel: element<HTMLElement>("battle-round-label"),
  battleRoundResult: element<HTMLElement>("battle-round-result"),
  battleCommandDock: element<HTMLElement>("battle-command-dock"),
  battleOneAction: element<HTMLSelectElement>("battle-one-action"),
  battleTwoAction: element<HTMLSelectElement>("battle-two-action"),
  battleOneTargetLabel: element<HTMLElement>("battle-one-target-label"),
  battleTwoTargetLabel: element<HTMLElement>("battle-two-target-label"),
  battleOneTarget: element<HTMLSelectElement>("battle-one-target"),
  battleTwoTarget: element<HTMLSelectElement>("battle-two-target"),
  battleOneCommandFieldset: element<HTMLFieldSetElement>("battle-one-command-fieldset"),
  battleTwoCommandFieldset: element<HTMLFieldSetElement>("battle-two-command-fieldset"),
  battleOneLock: element<HTMLButtonElement>("battle-one-lock"),
  battleTwoLock: element<HTMLButtonElement>("battle-two-lock"),
  battleOneSealed: element<HTMLElement>("battle-one-sealed"),
  battleTwoSealed: element<HTMLElement>("battle-two-sealed"),
  battleResolve: element<HTMLButtonElement>("battle-resolve"),
  battleComplete: element<HTMLElement>("battle-complete"),
  battleWinner: element<HTMLElement>("battle-winner"),
  battleAgain: element<HTMLButtonElement>("battle-again"),
  battleTranscript: element<HTMLOListElement>("battle-transcript"),
  relayEntry: element<HTMLButtonElement>("relay-entry"),
  relayPanel: element<HTMLElement>("relay-panel"),
  relayReturn: element<HTMLButtonElement>("relay-return"),
  relayTitle: element<HTMLElement>("relay-title"),
  relayStep: element<HTMLElement>("relay-step"),
  relayFeedback: element<HTMLElement>("relay-feedback"),
  relayContent: element<HTMLElement>("relay-content"),
  relayKeep: element<HTMLButtonElement>("relay-keep"),
  relayRestart: element<HTMLButtonElement>("relay-restart"),
  relayKeepCopy: element<HTMLElement>("relay-keep-copy"),
  milestoneList: element<HTMLOListElement>("milestone-list"),
  milestoneCount: element<HTMLElement>("milestone-count"),
  continuity: element<HTMLElement>("continuity-panel"),
  closeContinuity: element<HTMLButtonElement>("close-continuity"),
  continuityGrowth: element<HTMLElement>("continuity-growth"),
  passportDisplayID: element<HTMLElement>("passport-display-id"),
  passportCreated: element<HTMLTimeElement>("passport-created"),
  passportOrigin: element<HTMLElement>("passport-origin"),
  scrim: element<HTMLElement>("scrim"),
  navigator: element<HTMLElement>("field-navigator"),
  navigatorStatus: element<HTMLElement>("navigator-status"),
  navigatorSignals: element<HTMLElement>("navigator-signals"),
  closeNavigator: element<HTMLButtonElement>("close-navigator"),
  stageLabel: element<HTMLElement>("stage-label"),
  playLabel: element<HTMLElement>("play-label"),
  fieldName: element<HTMLElement>("field-name"),
  fieldEyebrow: element<HTMLElement>("field-eyebrow"),
  fieldTitle: element<HTMLElement>("field-title"),
  fieldInstruction: element<HTMLElement>("field-instruction"),
  proposalSummary: element<HTMLElement>("proposal-summary"),
  proposalChoices: element<HTMLElement>("proposal-choices"),
  hold: element<HTMLButtonElement>("hold-button"),
  reflectionTitle: element<HTMLElement>("reflection-title"),
  reflectionCopy: element<HTMLElement>("reflection-copy"),
  reflectionTrace: element<HTMLElement>("reflection-trace"),
  fieldRail: element<HTMLElement>("field-rail"),
  signalProgress: element<HTMLElement>("signal-progress"),
  composureFill: element<HTMLElement>("composure-fill"),
  composureProgress: element<HTMLProgressElement>("composure-progress"),
  signalPips: [...document.querySelectorAll<HTMLElement>(".signal-pip")],
  dominantRole: element<HTMLElement>("dominant-role-label"),
  affinityList: element<HTMLElement>("affinity-list"),
  traceCount: element<HTMLElement>("trace-count"),
  traceList: element<HTMLOListElement>("trace-list"),
  exportJourney: element<HTMLButtonElement>("export-journey"),
  reviewJourney: element<HTMLButtonElement>("review-journey"),
  journeyFile: element<HTMLInputElement>("journey-file"),
  journeyArchiveStatus: element<HTMLElement>("journey-archive-status"),
  journeyImportPreview: element<HTMLElement>("journey-import-preview"),
  journeyImportTitle: element<HTMLElement>("journey-import-title"),
  journeyImportSummary: element<HTMLElement>("journey-import-summary"),
  journeyImportRelation: element<HTMLElement>("journey-import-relation"),
  deviceShellState: element<HTMLElement>("device-shell-state"),
  deviceShellCopy: element<HTMLElement>("device-shell-copy"),
  cancelJourneyImport: element<HTMLButtonElement>("cancel-journey-import"),
  confirmJourneyImport: element<HTMLButtonElement>("confirm-journey-import"),
  reset: element<HTMLButtonElement>("reset-button"),
  resetConfirm: element<HTMLElement>("reset-confirm"),
  cancelReset: element<HTMLButtonElement>("cancel-reset"),
  confirmReset: element<HTMLButtonElement>("confirm-reset"),
  toast: element<HTMLElement>("toast"),
};

const presentationFormButtons = [
  ...document.querySelectorAll<HTMLButtonElement>("[data-presentation-form]"),
];
const liminalPortraitButtons = [...document.querySelectorAll<HTMLButtonElement>("[data-liminal-portrait]")];
let portraitChoice: PortraitChoice = "presence";
// Public source may omit this artwork. Only these exact authored assets qualify;
// absent files leave the existing presence renderer available.
const liminalPortraitSources = import.meta.glob<string>([
  "../ios/ARCHi/Assets.xcassets/LiminalGarnet.imageset/hampton-liminal-garnet-v1.png",
  "../ios/ARCHi/Assets.xcassets/LiminalCurled.imageset/curled-rest.png",
  "../ios/ARCHi/Assets.xcassets/LiminalStanding.imageset/standing-rest.png",
], { eager: true, query: "?inline", import: "default" });
const liminalPortraits = Object.fromEntries(Object.entries({
  seed: liminalPortraitSources["../ios/ARCHi/Assets.xcassets/LiminalGarnet.imageset/hampton-liminal-garnet-v1.png"],
  ball: liminalPortraitSources["../ios/ARCHi/Assets.xcassets/LiminalCurled.imageset/curled-rest.png"],
  beast: liminalPortraitSources["../ios/ARCHi/Assets.xcassets/LiminalStanding.imageset/standing-rest.png"],
}).flatMap(([key, source]) => {
    if (!source) return [];
    const image = new Image(); image.src = source;
    return [[key, image]];
  })) as Partial<Record<LiminalPortraitChoice, HTMLImageElement>>;
function currentLiminalPortrait(): LiminalPortraitChoice | null {
  return visibleLiminalPortrait(portraitChoice, Boolean(desktopHost),
    portraitChoice !== "presence" && Boolean(liminalPortraits[portraitChoice]));
}
const presentationViewButtons = [
  ...document.querySelectorAll<HTMLButtonElement>("[data-presentation-view]"),
];
const presentationMotionButtons = [
  ...document.querySelectorAll<HTMLButtonElement>("[data-presentation-motion]"),
];
const presentationScaleButtons = [
  ...document.querySelectorAll<HTMLButtonElement>("[data-presentation-scale]"),
];
const battleRoleSelects = [...document.querySelectorAll<HTMLSelectElement>("[data-battle-role-select]")];
const battleRosterRoleSelects: Record<BattleTeamId, readonly HTMLSelectElement[]> = {
  one: [0, 1, 2].map((slot) => element<HTMLSelectElement>(`battle-one-role-${slot}`)),
  two: [0, 1, 2].map((slot) => element<HTMLSelectElement>(`battle-two-role-${slot}`)),
};
const battleRosterSlots: Record<BattleTeamId, readonly HTMLElement[]> = {
  one: [0, 1, 2].map((slot) => document.querySelector<HTMLElement>(`[data-battle-slot="one-${slot}"]`)).filter(Boolean) as HTMLElement[],
  two: [0, 1, 2].map((slot) => document.querySelector<HTMLElement>(`[data-battle-slot="two-${slot}"]`)).filter(Boolean) as HTMLElement[],
};

const DEFAULT_CARE_RESPONSE = "Choose how to be present. Care shapes this moment, never ARCHi’s identity.";
const DEFAULT_CONTROL_HINT = "Move with WASD, arrow keys, or a tap · F for fullscreen";
const DEVICE_SETTLING_RESPONSE =
  "ARCHi is settling into this device. Close and reopen the installed app before care or play. Your Journey will not change during setup.";
const DEVICE_SETTLING_HINT = "Close and reopen ARCHi once · Journey input is paused during setup";
let journeyInputInterlocked = false;
let mainPresentationReady = false;
const desktopHost = connectDesktopHost(window);
if (desktopHost) document.documentElement.dataset.desktopHost = "true";
let desktopAppearanceImage: HTMLImageElement | null = null;
let desktopAppearanceID: string | null = null;
let desktopAppearanceRequest = 0;
let desktopReduceMotion = false;
const desktopInteractions = desktopHost ? createDesktopInteractionScope(() => desktopHost.visible) : null;

function applyJourneyInputInterlock(snapshot: DeviceShellSnapshot): void {
  journeyInputInterlocked = snapshot.standalone && !snapshot.controlled;
  for (const control of [
    ui.careGreet,
    ui.careTend,
    ui.careRest,
    ui.begin,
    ui.again,
    ui.hold,
    ui.reset,
    ui.confirmReset,
    ui.battleButton,
    ui.relayEntry,
  ]) {
    control.disabled = journeyInputInterlocked;
  }
  for (const control of ui.proposalChoices.querySelectorAll<HTMLButtonElement>("button")) {
    control.disabled = journeyInputInterlocked;
  }
  canvas.setAttribute("aria-disabled", String(journeyInputInterlocked));
  ui.controlHint.textContent = journeyInputInterlocked ? DEVICE_SETTLING_HINT : DEFAULT_CONTROL_HINT;

  if (!mainPresentationReady) return;
  const importHasSafeWrite = pendingJourneyImport
    ? pendingJourneyImport.requiresWrite &&
      (qaMode || Boolean(navigator.locks)) &&
      pendingJourneyImport.storageSnapshot.status !== "unreadable"
    : true;
  ui.confirmJourneyImport.disabled = journeyInputInterlocked || !importHasSafeWrite;
  updateCareInterface();
  updateFieldInterface();
}

setupDeviceShell({
  installButton: ui.install,
  stateLabel: ui.deviceShellState,
  copy: ui.deviceShellCopy,
  onSnapshot: applyJourneyInputInterlock,
});

const STORAGE_KEY = "archi.journey.v3";
const V2_STORAGE_KEY = "archi.journey.v2";
const V1_STORAGE_KEY = "archi.journey.v1";
const JOURNEY_LOCK_NAME = "archi.journey.commit";
const ROSTER_STORAGE_KEY = "archi.qimon.roster.v1";
const ROSTER_LOCK_NAME = "archi.qimon.roster.commit";
const ROSTER_BACKUP_PREFIX = "archi.qimon.roster.backup.";
const LEDGER_TAIL_LIMIT = 12;
const query = new URLSearchParams(window.location.search);
const qaMode = query.get("qa") === "golden";
const reducedMotionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
let reducedMotion = reducedMotionQuery.matches;
let presentationState: PresentationState = DEFAULT_PRESENTATION_STATE;
let presenceSequence: PresenceSequenceState = createPresenceSequence(DEFAULT_PRESENTATION_STATE.form);
let presentationPulse = 0;
let battleState: BattleState | null = null;
let battleOwnedCards: readonly QiMonCard[] | null = null;
let relayBattle: RelayBattleState | null = null;
let relayBattleMessage = "Choose a team with an earned pair bond to begin a Relay practice.";
let rosterTeamDraft: string[] = [];
let rosterReturnFocus: HTMLElement | null = null;
let battleOpponentMode: "companion" | "local" = "companion";
let battleLockedCommands: Partial<Record<BattleTeamId, BattleCommand>> = {};
// A transient rehearsal belongs to this view of the existing match. It never
// becomes a real round, a sealed command, or a Journey record.
let battleWhatIf: { basis: string; report: NonNullable<ReturnType<typeof compareBattleChoices>> } | null = null;
let battleSequence = 0;
let battlePracticeBase: Omit<PracticeAttempt, "replay"> & { teams: readonly [BattleTeamSetup, BattleTeamSetup]; opponentMode: "companion" | "local" } | null = null;
let battleSavedId: string | null = null;
let battleKeepMessage = "Nothing is saved until you choose Keep practice.";
let battleKeepBusy = false;
let battleReviewGeneration = 0;
let battleLockAbort: AbortController | null = null;
let practiceSummaryJourney: Journey | null = null;
let practiceSummaryCache: readonly PracticeSummary[] = [];
function savedPracticeSummaries(): readonly PracticeSummary[] {
  if (practiceSummaryJourney !== journey) {
    practiceSummaryCache = derivePracticeSummaries(journey);
    practiceSummaryJourney = journey;
  }
  return practiceSummaryCache;
}
let battleLastResult = "Choose both commands";
let battleImpactPulse = 0;
let battleFocusReturnTarget: HTMLElement | null = null;
let journeyWasMigrated = false;
let storageWriteAvailable = false;
let sessionOnlyAuthority = false;
let persistedEventCount: number | null = null;
let persistedHeadId: string | null = null;
let persistedRevision: string | null = null;

type PrimaryStorageSnapshot =
  | { status: "present"; digest: string }
  | { status: "absent"; digest: null }
  | { status: "unreadable"; digest: null };

interface PendingJourneyImport {
  generation: number;
  preview: JourneyArchivePreview;
  relation: JourneyRelation;
  baseRevision: string;
  baseWasPersisted: boolean;
  storageSnapshot: PrimaryStorageSnapshot;
  requiresWrite: boolean;
}

let pendingJourneyImport: PendingJourneyImport | null = null;
let journeyImportGeneration = 0;
let journeyImportLockAbort: AbortController | null = null;
let resetReviewGeneration = 0;
let resetLockAbort: AbortController | null = null;

function isSupportedStorageRecord(value: unknown): value is { version: 3 | 4 | 5; events: unknown[] } {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const record = value as { version?: unknown; events?: unknown };
  return (record.version === 3 || record.version === 4 || record.version === 5) && Array.isArray(record.events);
}

function recordPersistedJourney(candidate: Journey): void {
  persistedEventCount = candidate.events.length;
  persistedHeadId = candidate.events.at(-1)?.eventId ?? null;
  persistedRevision = revisionForJourney(candidate);
}

function loadJourney(): Journey {
  if (qaMode) return createJourney("archi-golden-journey", "2026-08-28T12:00:00.000Z");
  journeyWasMigrated = false;
  try {
    const storedV3 = window.localStorage.getItem(STORAGE_KEY);
    if (storedV3 !== null) {
      try {
        const parsed: unknown = parseJsonWithoutDuplicateKeys(storedV3, "ARCHi stored Journey");
        const restored = isSupportedStorageRecord(parsed) ? hydrateJourney(parsed) : null;
        if (restored && isSupportedStorageRecord(parsed) && restored.events.length === parsed.events.length) {
          recordPersistedJourney(restored);
          return restored;
        }
      } catch {
        // A present v3 key is authoritative even when it cannot be admitted.
      }
      sessionOnlyAuthority = true;
      storageWriteAvailable = false;
      return createJourney();
    }

    for (const storageKey of [V2_STORAGE_KEY, V1_STORAGE_KEY]) {
      const stored = window.localStorage.getItem(storageKey);
      if (stored === null) continue;
      let restored: Journey | null = null;
      try {
        restored = hydrateJourney(JSON.parse(stored));
      } catch {
        continue;
      }
      if (restored) {
        journeyWasMigrated = true;
        return restored;
      }
    }
  } catch {
    // Unreadable existing bytes cannot be replaced by a successful later write.
    sessionOnlyAuthority = true;
    storageWriteAvailable = false;
  }
  return createJourney();
}

function writeStoredJourney(candidate: Journey, allowExplicitRecovery = false): boolean {
  if (qaMode || (sessionOnlyAuthority && !allowExplicitRecovery)) return false;
  try {
    window.localStorage.setItem(STORAGE_KEY, serializeJourney(candidate));
    storageWriteAvailable = true;
    sessionOnlyAuthority = false;
    recordPersistedJourney(candidate);
    return true;
  } catch {
    storageWriteAvailable = false;
    sessionOnlyAuthority = true;
    return false;
  }
}

function saveJourney(): boolean {
  const saved = writeStoredJourney(journey);
  publishDesktopJourney();
  return saved;
}

type StoredJourneyRead =
  | { status: "valid"; journey: Journey }
  | { status: "absent" }
  | { status: "invalid-or-unreadable" };

function readStoredJourney(_requireComplete = true): StoredJourneyRead {
  if (qaMode) return { status: "absent" };
  try {
    const stored = window.localStorage.getItem(STORAGE_KEY);
    if (stored === null) return { status: "absent" };
    const parsed: unknown = parseJsonWithoutDuplicateKeys(stored, "ARCHi stored Journey");
    if (!isSupportedStorageRecord(parsed)) return { status: "invalid-or-unreadable" };
    const restored = hydrateJourney(parsed);
    if (!restored) return { status: "invalid-or-unreadable" };
    if (restored.events.length !== parsed.events.length) {
      return { status: "invalid-or-unreadable" };
    }
    recordPersistedJourney(restored);
    return { status: "valid", journey: restored };
  } catch {
    return { status: "invalid-or-unreadable" };
  }
}

function readPrimaryStorageSnapshot(): PrimaryStorageSnapshot {
  if (qaMode) return { status: "absent", digest: null };
  try {
    const stored = window.localStorage.getItem(STORAGE_KEY);
    return stored === null
      ? { status: "absent", digest: null }
      : { status: "present", digest: sha256String(stored) };
  } catch {
    return { status: "unreadable", digest: null };
  }
}

function sameStorageSnapshot(left: PrimaryStorageSnapshot, right: PrimaryStorageSnapshot): boolean {
  return left.status === right.status && left.digest === right.digest;
}

function replaceStoredJourney(candidate: Journey): boolean {
  if (qaMode) return false;
  let previous: string | null;
  try {
    previous = window.localStorage.getItem(STORAGE_KEY);
  } catch {
    storageWriteAvailable = false;
    sessionOnlyAuthority = true;
    return false;
  }

  const replacement = serializeJourney(candidate);
  try {
    window.localStorage.setItem(STORAGE_KEY, replacement);
    if (window.localStorage.getItem(STORAGE_KEY) !== replacement) {
      throw new Error("The imported Journey could not be verified after writing.");
    }
    storageWriteAvailable = true;
    sessionOnlyAuthority = false;
    recordPersistedJourney(candidate);
    return true;
  } catch {
    try {
      if (previous === null) window.localStorage.removeItem(STORAGE_KEY);
      else window.localStorage.setItem(STORAGE_KEY, previous);
    } catch {
      // The in-memory Journey remains unchanged even if browser recovery is unavailable.
    }
    storageWriteAvailable = false;
    sessionOnlyAuthority = true;
    return false;
  }
}

function removeLegacyJourneyKeys(): void {
  for (const storageKey of [V2_STORAGE_KEY, V1_STORAGE_KEY]) {
    try {
      window.localStorage.removeItem(storageKey);
    } catch {
      // A canonical v3 write already shadows an inaccessible legacy key.
    }
  }
}

async function bootstrapJourney(): Promise<Journey> {
  const bootstrapUnderCurrentLock = (): Journey => {
    const loaded = loadJourney();
    const persisted = writeStoredJourney(loaded);
    if (persisted && journeyWasMigrated) removeLegacyJourneyKeys();
    return loaded;
  };

  if (!qaMode && navigator.locks) {
    return navigator.locks.request(JOURNEY_LOCK_NAME, bootstrapUnderCurrentLock);
  }
  return bootstrapUnderCurrentLock();
}

let journey = await bootstrapJourney();
let roster: QiMonRoster | null = null;
let rosterStorageBaseline: string | null = null;
let rosterIssue: string | null = null;
let rosterProjectionIssue = false;
let rosterStatusMessage = "Field traces can become invitations after you explicitly keep and review them.";
let pendingRosterImport: {
  generation: number;
  candidate: QiMonRoster;
  baseline: string | null;
  journeyRevision: string;
} | null = null;
let rosterImportGeneration = 0;

async function bootstrapQiMonRoster(): Promise<void> {
  if (qaMode) { roster = createQiMonRoster(journey); return; }
  if (!storageWriteAvailable || !navigator.locks) {
    rosterIssue = "The local save or write lock is unavailable. Your QiMon roster is paused so progress cannot be lost.";
    return;
  }
  try {
    await navigator.locks.request(JOURNEY_LOCK_NAME, () => navigator.locks.request(ROSTER_LOCK_NAME, () => {
      const stored = window.localStorage.getItem(ROSTER_STORAGE_KEY);
      if (stored !== null) {
        const inspected = inspectQiMonRoster(stored, journey);
        if (inspected.status !== "valid") {
          rosterIssue = `Saved roster needs review: ${inspected.message} Its bytes were kept.`;
          rosterStorageBaseline = stored;
          return;
        }
        roster = inspected.roster;
        rosterStorageBaseline = stored;
        return;
      }
      const created = createQiMonRoster(journey);
      const archive = serializeQiMonRoster(created, journey);
      window.localStorage.setItem(ROSTER_STORAGE_KEY, archive);
      if (window.localStorage.getItem(ROSTER_STORAGE_KEY) !== archive) {
        rosterIssue = "Roster readback failed. The Field Journey is unchanged.";
        return;
      }
      roster = created;
      rosterStorageBaseline = archive;
    }));
  } catch (error) {
    rosterIssue = error instanceof Error ? error.message : "Roster storage is unavailable.";
  }
}

await bootstrapQiMonRoster();

function currentQiMonRoster(): QiMonRosterProjection | null {
  if (!roster) return null;
  try {
    const projection = projectQiMonRoster(journey, roster);
    if (rosterProjectionIssue) { rosterIssue = null; rosterProjectionIssue = false; }
    return projection;
  }
  catch (error) {
    rosterIssue = error instanceof Error ? error.message : "The roster no longer matches this Journey.";
    rosterProjectionIssue = true;
    return null;
  }
}

async function commitQiMonRoster(
  change: (current: QiMonRoster, rosterRevision: string, journeyRevision: string) => QiMonRoster,
  success: string,
): Promise<void> {
  const current = roster;
  if (!current || rosterIssue || journeyInputInterlocked || commitInFlight) return;
  const expectedJourneyRevision = revisionForJourney(journey);
  const expectedRosterRevision = revisionForQiMonRoster(current);
  const baseline = rosterStorageBaseline;
  commitInFlight = true;
  try {
    const underLock = (): void => {
      if (roster !== current || revisionForJourney(journey) !== expectedJourneyRevision ||
          revisionForQiMonRoster(current) !== expectedRosterRevision) {
        throw new Error("The Journey or roster changed. Reopen the QiMon roster before trying again.");
      }
      if (!qaMode) {
        const saved = readStoredJourney();
        if (!storageWriteAvailable || saved?.status !== "valid" ||
            revisionForJourney(saved.journey) !== expectedJourneyRevision ||
            window.localStorage.getItem(ROSTER_STORAGE_KEY) !== baseline) {
          throw new Error("Saved Journey or roster changed. No QiMon action was kept.");
        }
      }
      const candidate = change(current, expectedRosterRevision, expectedJourneyRevision);
      const archive = serializeQiMonRoster(candidate, journey);
      if (!qaMode) {
        try {
          window.localStorage.setItem(ROSTER_STORAGE_KEY, archive);
          if (window.localStorage.getItem(ROSTER_STORAGE_KEY) !== archive) throw new Error("Roster readback failed.");
        } catch (error) {
          try {
            if (baseline === null) window.localStorage.removeItem(ROSTER_STORAGE_KEY);
            else window.localStorage.setItem(ROSTER_STORAGE_KEY, baseline);
          } catch { /* Keep the visible error; do not claim a saved action. */ }
          throw error;
        }
      }
      roster = candidate;
      rosterStorageBaseline = qaMode ? baseline : archive;
      rosterStatusMessage = success;
    };
    if (!qaMode && navigator.locks) {
      await navigator.locks.request(JOURNEY_LOCK_NAME, () => navigator.locks.request(ROSTER_LOCK_NAME, underLock));
    }
    else if (qaMode) underLock();
    else throw new Error("Roster write lock unavailable. No QiMon action was kept.");
  } catch (error) {
    rosterStatusMessage = error instanceof Error ? error.message : "This QiMon action was not kept.";
  } finally {
    commitInFlight = false;
    renderQiMonRoster();
  }
}
let session: PlaySession | null = null;
let relayAttempt: RelayAttempt | null = null;
let relaySequence = 0;
let relaySaved = false;
let relayLockAbort: AbortController | null = null;
let relayReviewGeneration = 0;
let mode: Mode = "habitat";
let width = 1;
let height = 1;
let pixelRatio = 1;
let elapsed = 0;
let lastFrame = performance.now();
let soundEnabled = false;
let audioContext: AudioContext | null = null;
let stars: Star[] = [];
let particles: Particle[] = [];
let collectedSparks = new Set<string>();
let proposalCountdown = 0;
let toastTimer = 0;
let transition = 0;
let morphFlash = 0;
let petPulse = 0;
let lastStaticHit = -10;
let fieldComposure = 100;
let lastComposureRendered = -1;
let overlayReturnFocus: HTMLElement | null = null;
let commitInFlight = false;
let careProjection: CareProjection = projectCare(
  journey.care,
  qaMode ? journey.care.updatedAt : new Date().toISOString(),
);

const keys = new Set<string>();
const pointer: Point = { x: window.innerWidth * 0.7, y: window.innerHeight * 0.45 };
const target: Point = { x: window.innerWidth / 2, y: window.innerHeight / 2 };
const player = { x: window.innerWidth / 2, y: window.innerHeight / 2, vx: 0, vy: 0 };

function animationTime(): number {
  return reducedMotion ? 0 : elapsed;
}

function createStars(): Star[] {
  const random = seededRandom(hashString(`${journey.seed}:sky`));
  return Array.from({ length: 94 }, () => ({
    x: random(),
    y: random(),
    size: 0.35 + random() * 1.25,
    phase: random() * Math.PI * 2,
    warmth: random(),
  }));
}

stars = createStars();

function resizeCanvas(): void {
  const oldWidth = width;
  const oldHeight = height;
  const bounds = canvas.getBoundingClientRect();
  width = Math.max(1, bounds.width);
  height = Math.max(1, bounds.height);
  pixelRatio = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width = Math.round(width * pixelRatio);
  canvas.height = Math.round(height * pixelRatio);
  context.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);

  if (oldWidth > 1 && oldHeight > 1) {
    player.x = (player.x / oldWidth) * width;
    player.y = (player.y / oldHeight) * height;
    target.x = (target.x / oldWidth) * width;
    target.y = (target.y / oldHeight) * height;
  } else {
    player.x = width / 2;
    player.y = height * 0.55;
    target.x = player.x;
    target.y = player.y;
  }
  if (mode === "field") updateFieldNavigator();
  render();
}

function currentCompanionPosition(): Point {
  if (mode === "field") return { x: player.x, y: player.y };
  return habitatEncounterComposition(width, height).anchor;
}

function showToast(message: string): void {
  ui.toast.textContent = message;
  ui.toast.classList.add("is-visible");
  toastTimer = 2.2;
}

function tone(frequency: number, duration = 0.12, gainValue = 0.035): void {
  if (!soundEnabled) return;
  audioContext ??= new AudioContext();
  const oscillator = audioContext.createOscillator();
  const gain = audioContext.createGain();
  const start = audioContext.currentTime;
  oscillator.type = "sine";
  oscillator.frequency.setValueAtTime(frequency, start);
  oscillator.frequency.exponentialRampToValueAtTime(frequency * 1.35, start + duration);
  gain.gain.setValueAtTime(gainValue, start);
  gain.gain.exponentialRampToValueAtTime(0.0001, start + duration);
  oscillator.connect(gain).connect(audioContext.destination);
  oscillator.start(start);
  oscillator.stop(start + duration);
}

function updatePresentationInterface(): void {
  const sequenceMix = presenceMix(presenceSequence.position);
  const visibleState = { ...presentationState, form: sequenceMix.phase } satisfies PresentationState;
  const startPhase = presencePhaseForPosition(presenceSequence.startPosition);
  const targetPhase = presencePhaseForPosition(presenceSequence.targetPosition);
  const selectedPortrait = currentLiminalPortrait();
  const stateLabel = selectedPortrait
    ? `${portraitLabel(selectedPortrait)} · ${Math.round(presentationState.scale * 100)}%`
    : presenceSequence.direction === "settled"
    ? presentationLabel(visibleState)
    : `${presenceSequence.direction === "reveal" ? "Unfolding" : "Returning"} · ${
        startPhase[0].toUpperCase()
      }${startPhase.slice(1)} → ${targetPhase[0].toUpperCase()}${targetPhase.slice(1)} · ${
        presentationState.view === "three-quarter"
          ? "Three-quarter"
          : `${presentationState.view[0].toUpperCase()}${presentationState.view.slice(1)}`
      } · ${presentationState.motion[0].toUpperCase()}${presentationState.motion.slice(1)} · ${Math.round(
        presentationState.scale * 100,
      )}%`;
  if (ui.presenceState.value !== stateLabel) ui.presenceState.value = stateLabel;
  ui.presenceConsole.dataset.form = sequenceMix.phase;
  ui.presenceConsole.dataset.targetForm = presentationState.form;
  ui.presenceConsole.dataset.phase = sequenceMix.phase;
  ui.presenceConsole.dataset.position = presenceSequence.position.toFixed(3);
  ui.presenceConsole.dataset.direction = presenceSequence.direction;
  ui.presenceConsole.dataset.view = presentationState.view;
  ui.presenceConsole.dataset.motion = presentationState.motion;
  ui.presenceConsole.dataset.portrait = selectedPortrait ?? "presence";
  for (const button of liminalPortraitButtons) {
    const active = button.dataset.liminalPortrait === (selectedPortrait ?? "presence");
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-pressed", String(active));
    const choice = button.dataset.liminalPortrait;
    const missing = isPortraitChoice(choice) && choice !== "presence" && !liminalPortraits[choice];
    button.disabled = Boolean(desktopHost) || missing;
    if (missing) button.textContent = `${portraitLabel(choice)} · Source unavailable`;
  }
  // A single captured view does not pretend to rotate or unfold like the live rig.
  for (const button of [...presentationFormButtons, ...presentationViewButtons, ...presentationMotionButtons,
    ui.presenceUnfold, ui.presenceReturn]) button.disabled = selectedPortrait !== null;

  for (const button of presentationFormButtons) {
    const active = button.dataset.presentationForm === sequenceMix.phase;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-pressed", String(active));
  }
  for (const button of presentationViewButtons) {
    const active = button.dataset.presentationView === presentationState.view;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-pressed", String(active));
  }
  for (const button of presentationMotionButtons) {
    const active = button.dataset.presentationMotion === presentationState.motion;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-pressed", String(active));
  }
  const reset = presentationScaleButtons.find((button) => button.dataset.presentationScale === "reset");
  if (reset) reset.textContent = `${Math.round(presentationState.scale * 100)}%`;
  const unfolding = presenceSequence.direction === "reveal" && presenceSequence.targetPosition === 1;
  ui.presenceUnfold.classList.toggle("is-running", unfolding);
  const returning = presenceSequence.direction === "return" && presenceSequence.targetPosition === 0;
  ui.presenceReturn.classList.toggle("is-running", returning);
}

function isPresentationForm(value: string | undefined): value is PresentationForm {
  return typeof value === "string" && (PRESENTATION_FORMS as readonly string[]).includes(value);
}

function isPresentationView(value: string | undefined): value is PresentationView {
  return typeof value === "string" && (PRESENTATION_VIEWS as readonly string[]).includes(value);
}

function isPresentationMotion(value: string | undefined): value is PresentationMotion {
  return typeof value === "string" && (PRESENTATION_MOTIONS as readonly string[]).includes(value);
}

function applyPresentationAction(action: PresentationAction): void {
  const prior = presentationState;
  const next = updatePresentationState(prior, action);
  if (next.form !== prior.form) {
    presenceSequence = retargetPresenceSequence(presenceSequence, next.form, reducedMotion);
  }
  if (next === prior && presenceSequence.direction === "settled") return;
  presentationState = next;
  if (next.motion === "play" && prior.motion !== "play") {
    presentationPulse = reducedMotion ? 0 : 1;
    if (!reducedMotion) {
      const companion = currentCompanionPosition();
      spawnBurst(companion.x, companion.y, "#8af1e6", 26, 0.72);
    }
  }
  updatePresentationInterface();
  render();
}

function unfoldPresenceSequence(): void {
  presentationState = updatePresentationState(presentationState, { type: "form", value: "context" });
  presenceSequence = retargetPresenceSequence(createPresenceSequence("core"), "context", reducedMotion);
  presentationPulse = reducedMotion ? 0 : 1;
  updatePresentationInterface();
  render();
}

const BATTLE_ACTION_LABELS: Record<BattleAction, string> = {
  pulse: "Pulse",
  guard: "Guard",
  signature: "Signature",
  swap: "Swap",
  surrender: "Surrender",
};

const BATTLE_ACTION_DESCRIPTIONS: Record<BattleAction, string> = {
  pulse: "direct Field impact",
  guard: "shield this round",
  signature: "spend 1 shared Spark",
  swap: "relay to a reserve",
  surrender: "end the practice",
};

const BATTLE_SIGNATURE_LABELS: Record<RoleId, string> = {
  hearth: "Mend",
  muse: "Burst",
  scout: "Mark",
  beacon: "Passage",
  keeper: "Clear",
  guardian: "Hold",
};

function roleOptionLabel(roleId: RoleId): string {
  const role = ROLES[roleId];
  return `${role.form} · ${role.shortTitle} · ${BATTLE_SIGNATURE_LABELS[roleId]}`;
}

function battleSize(teamId: BattleTeamId): number {
  const value = teamId === "one" ? ui.battleOneSize.value : ui.battleTwoSize.value;
  return clamp(Number(value) || 1, BATTLE_LIMITS.minimumRoster, BATTLE_LIMITS.maximumRoster);
}

function updateBattleBuilder(teamId: BattleTeamId): void {
  const size = teamId === "one" && battleOwnedCards ? battleOwnedCards.length : battleSize(teamId);
  battleRosterSlots[teamId].forEach((slot, index) => {
    const visible = index < size;
    slot.hidden = !visible;
    battleRosterRoleSelects[teamId][index].disabled = !visible || (teamId === "one" && !!battleOwnedCards);
    const caption = slot.querySelector("span");
    if (caption) caption.textContent = teamId === "one" && battleOwnedCards?.[index]
      ? battleOwnedCards[index].name : `QiMon ${index + 1}`;
  });
  if (teamId === "one") {
    ui.battleOneSize.disabled = !!battleOwnedCards;
    ui.battleOneBond.disabled = !!battleOwnedCards;
  }
  const integrity = BATTLE_LIMITS.teamIntegrity / size;
  const resonance = BATTLE_LIMITS.teamResonance / size;
  const concentration = BATTLE_LIMITS.maximumRoster - size;
  const copy = `${integrity} Integrity each · ${resonance} Resonance each · Concentration +${concentration}`;
  (teamId === "one" ? ui.battleOneAllocation : ui.battleTwoAllocation).textContent = copy;
}

function initializeBattleControls(): void {
  for (const select of battleRoleSelects) {
    select.replaceChildren();
    for (const roleId of ROLE_ORDER) {
      const option = document.createElement("option");
      option.value = roleId;
      option.textContent = roleOptionLabel(roleId);
      select.append(option);
    }
  }
  ui.battleOneBond.value = "scout";
  ui.battleTwoBond.value = "guardian";
  const oneDefaults: RoleId[] = ["scout", "hearth", "muse"];
  const twoDefaults: RoleId[] = ["guardian", "keeper", "beacon"];
  battleRosterRoleSelects.one.forEach((select, index) => (select.value = oneDefaults[index]));
  battleRosterRoleSelects.two.forEach((select, index) => (select.value = twoDefaults[index]));
  updateBattleBuilder("one");
  updateBattleBuilder("two");
}

function battlePlayerName(teamId: BattleTeamId): string {
  return battleOpponentMode === "companion" ? teamId === "one" ? "You" : "Practice partner"
    : teamId === "one" ? "Player One" : "Player Two";
}

function updateBattleOpponentMode(): void {
  if (battleState) return;
  battleOpponentMode = ui.battleOpponentMode.value === "local" ? "local" : "companion";
  ui.battlePanel.dataset.opponentMode = battleOpponentMode;
  ui.battlePartnerNote.textContent = battleOpponentMode === "companion"
    ? "A local practice partner chooses its move before you do. No connection needed. Change either formation to try a different matchup."
    : "Share this device. Choose and seal each command separately, then reveal the round together.";
  for (const teamId of BATTLE_TEAM_IDS) {
    const name = battlePlayerName(teamId);
    const builder = document.querySelector(`[data-battle-builder="${teamId}"] > legend`);
    if (builder) builder.textContent = teamId === "one" && battleOwnedCards
      ? "Your invited QiMon" : teamId === "one" && battleOpponentMode === "companion" ? "Your formation" : name;
    const heading = document.querySelector(`#battle-${teamId}-hud .battle-team-hud__heading > div > span`);
    if (heading) heading.textContent = name;
    const commandLegend = document.querySelector(`#battle-${teamId}-command-fieldset > legend`);
    if (commandLegend) commandLegend.textContent = teamId === "one" && battleOpponentMode === "companion" ? "Your move" : `${name} command`;
  }
  updateBattleInterface();
}

/** The partner commits to a public-state decision before any player selection. */
function preparePracticePartner(): void {
  if (battleOpponentMode === "companion" && battleState?.status === "active") {
    battleLockedCommands = { ...battleLockedCommands, two: choosePracticeCommand(battleState, "two") };
  }
}

function readBattleTeamSetup(teamId: BattleTeamId): BattleTeamSetup {
  if (teamId === "one" && battleOwnedCards?.length) {
    return { id: "one", label: "You", bondRole: battleOwnedCards[0].role,
      roster: battleOwnedCards.map((card) => ({ ...card })) };
  }
  const size = battleSize(teamId);
  const label = battlePlayerName(teamId);
  const bond = teamId === "one" ? ui.battleOneBond.value : ui.battleTwoBond.value;
  const bondRole = (ROLE_ORDER as readonly string[]).includes(bond) ? (bond as RoleId) : "scout";
  const roster = battleRosterRoleSelects[teamId].slice(0, size).map((select, index) => {
    const role = (ROLE_ORDER as readonly string[]).includes(select.value) ? (select.value as RoleId) : bondRole;
    return {
      id: `${teamId}-practice-${index + 1}`,
      name: `${ROLES[role].form} ${index + 1}`,
      role,
    };
  });
  return { id: teamId, label, bondRole, roster };
}

function battleSetupReadback(): Record<BattleTeamId, unknown> {
  return Object.fromEntries(
    BATTLE_TEAM_IDS.map((teamId) => {
      const setup = readBattleTeamSetup(teamId);
      const size = setup.roster.length;
      return [
        teamId,
        {
          ...setup,
          allocation: {
            teamIntegrity: BATTLE_LIMITS.teamIntegrity,
            teamResonance: BATTLE_LIMITS.teamResonance,
            teamSpark: BATTLE_LIMITS.teamSpark,
            integrityPerQiMon: BATTLE_LIMITS.teamIntegrity / size,
            resonancePerQiMon: BATTLE_LIMITS.teamResonance / size,
            concentration: BATTLE_LIMITS.maximumRoster - size,
          },
        },
      ];
    }),
  ) as Record<BattleTeamId, unknown>;
}

function openBattleLab(): void {
  if (journeyInputInterlocked) {
    showToast("ARCHi is still settling into this device · battle remains paused");
    return;
  }
  battleFocusReturnTarget = document.activeElement instanceof HTMLElement
    ? document.activeElement
    : ui.battleButton;
  battleOwnedCards = null;
  setMode("battle");
  updateBattleOpponentMode();
  updateBattleInterface();
  ui.battleOneBond.focus({ preventScroll: true });
}

function cancelRelayConfirmation(): void {
  relayReviewGeneration += 1;
  relayLockAbort?.abort();
  relayLockAbort = null;
}

function openRelay(): void {
  if (journeyInputInterlocked || commitInFlight || (desktopHost && !desktopHost.visible)) return;
  cancelRelayConfirmation();
  session = null;
  proposalCountdown = 0;
  particles = [];
  keys.clear();
  player.vx = player.vy = 0;
  relayAttempt = createRelayAttempt(journey, qaMode ? `relay-qa-${++relaySequence}` : `relay-${crypto.randomUUID()}`);
  relaySaved = false;
  setMode("relay");
  updateRelayInterface(true);
  render();
}

function leaveRelay(): void {
  setMode("habitat");
  refreshCareProjection();
  updateFieldInterface();
  ui.relayEntry.focus({ preventScroll: true });
}

function relayButton(label: string, action: Extract<BrokenRelayEvent, { type: "START" | "REDIRECT" | "INSPECT" | "RESOLVE" }>, id: string): HTMLButtonElement {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "relay-choice";
  button.id = id;
  button.textContent = label;
  button.addEventListener("click", () => {
    if (!relayAttempt || mode !== "relay" || commitInFlight || continuityIsOpen() ||
        journeyInputInterlocked || (desktopHost && !desktopHost.visible)) return;
    relayAttempt = advanceRelayAttempt(relayAttempt, action);
    updateRelayInterface(false, id);
    render();
  });
  return button;
}

function updateRelayInterface(focus = false, previousControl?: string): void {
  const attempt = relayAttempt;
  if (!attempt) return;
  const { state } = attempt;
  const phaseChanged = ui.relayPanel.dataset.phase !== state.phase.toLowerCase();
  const completedEarlier = deriveActivityMilestones(journey).some((entry) => entry.activityId === "broken-relay");
  const phaseCopy = {
    READY: ["A small repair, together", "01 · Make a connection"],
    INTERFERENCE: ["Steady the signal", "02 · Redirect interference"],
    PUZZLE: ["Which message can we trust?", "03 · Compare the evidence"],
    RESTORED: ["The relay is clear", "04 · Choose what to keep"],
  } as const;
  ui.relayTitle.textContent = phaseCopy[state.phase][0];
  ui.relayStep.textContent = phaseCopy[state.phase][1];
  ui.relayFeedback.textContent = state.phase === "RESTORED"
    ? "Transmission B sends the convoy onto a closed bridge. The field log contains no later inspection or reopening."
    : state.feedback;
  ui.relayContent.replaceChildren();
  if (state.phase === "READY") {
    const copy = document.createElement("p");
    copy.textContent = "A relay is carrying conflicting messages. Help ARCHi protect the signal, read the field log, and trace the claim that does not fit.";
    ui.relayContent.append(copy, relayButton("Connect to the relay", { type: "START" }, "relay-start"));
  } else if (state.phase === "INTERFERENCE") {
    const route = document.createElement("p");
    route.className = "relay-route";
    route.textContent = `Route 2 → 1 → 3 · ${state.protectedSteps} of 3 secured`;
    const nodes = document.createElement("div");
    nodes.className = "relay-nodes";
    for (const node of [1, 2, 3] as const) nodes.append(relayButton(`Node ${node}`, { type: "REDIRECT", node }, `relay-node-${node}`));
    ui.relayContent.append(route, nodes);
  } else if (state.phase === "PUZZLE") {
    const log = document.createElement("blockquote");
    log.className = "relay-log";
    log.textContent = BROKEN_RELAY_FIELD_LOG;
    const label = document.createElement("p");
    label.className = "eyebrow";
    label.textContent = "Recorded field log";
    const readings = document.createElement("div");
    readings.className = "relay-transmissions";
    for (const transmission of BROKEN_RELAY_TRANSMISSIONS) {
      const read = state.readTransmissionIds.includes(transmission.id);
      const button = relayButton(`${transmission.id} · ${transmission.title}${read ? " · Read" : ""}`, { type: "INSPECT", id: transmission.id }, `relay-inspect-${transmission.id}`);
      button.setAttribute("aria-pressed", String(state.selectedTransmissionId === transmission.id));
      readings.append(button);
    }
    ui.relayContent.append(label, log, readings);
    const selected = BROKEN_RELAY_TRANSMISSIONS.find(({ id }) => id === state.selectedTransmissionId);
    if (selected) {
      const reading = document.createElement("p");
      reading.className = "relay-reading";
      reading.textContent = selected.text;
      const choose = relayButton(`Flag transmission ${selected.id}`, { type: "RESOLVE", id: selected.id }, "relay-resolve");
      choose.disabled = state.readTransmissionIds.length !== BROKEN_RELAY_TRANSMISSIONS.length;
      const count = document.createElement("p");
      count.className = "relay-note";
      count.textContent = `${state.readTransmissionIds.length} of 3 read. Compare all three before flagging the conflicting message.`;
      ui.relayContent.append(reading, count, choose);
    }
  } else {
    const copy = document.createElement("p");
    copy.textContent = "You protected the Core and checked all three transmissions. Keeping this adds one Relay milestone to the current Journey. It leaves field growth and appearance unchanged.";
    const receipt = document.createElement("p");
    receipt.className = "relay-note";
    receipt.textContent = "Accepted steps: connect → nodes 2, 1, 3 → inspect all three transmissions → flag B. Retry attempts are not part of this completion record.";
    ui.relayContent.append(copy, receipt);
  }
  ui.relayKeep.hidden = state.phase !== "RESTORED";
  ui.relayKeep.disabled = completedEarlier || commitInFlight || journeyInputInterlocked;
  ui.relayKeep.textContent = completedEarlier ? "Already in this Journey" : "Keep completion";
  ui.relayKeepCopy.hidden = state.phase !== "RESTORED";
  ui.relayKeepCopy.textContent = completedEarlier
    ? relaySaved ? "Kept. Your Relay milestone is in Continuity." : "This Journey already contains the Relay milestone. Replaying does not add another."
    : "Nothing is saved until you choose Keep. The updated Journey will need a build that supports activity history.";
  ui.relayRestart.hidden = state.phase !== "RESTORED";
  ui.relayPanel.dataset.phase = state.phase.toLowerCase();
  if (phaseChanged) ui.relayPanel.scrollTop = 0;
  if (focus || previousControl) {
    const previous = previousControl ? document.getElementById(previousControl) : null;
    const next = state.phase === "RESTORED" ? (completedEarlier ? ui.relayReturn : ui.relayKeep)
      : previous ?? ui.relayContent.querySelector<HTMLButtonElement>("button");
    next?.focus({ preventScroll: true });
  }
}

async function keepRelayCompletion(): Promise<void> {
  const attempt = relayAttempt;
  if (!attempt || mode !== "relay" || attempt.state.phase !== "RESTORED" || commitInFlight ||
      journeyInputInterlocked || continuityIsOpen()) return;
  const interaction = desktopInteractions?.begin();
  if (desktopInteractions && !interaction) return;
  const generation = relayReviewGeneration;
  const snapshot = readPrimaryStorageSnapshot();
  const expectedSaved = storageWriteAvailable;
  const lockAbort = new AbortController();
  relayLockAbort = lockAbort;
  commitInFlight = true;
  updateRelayInterface();
  const commit = (): void => {
    if (lockAbort.signal.aborted || relayAttempt !== attempt || generation !== relayReviewGeneration ||
        mode !== "relay" || continuityIsOpen() || journeyInputInterlocked ||
        (interaction && !interaction.isCurrent())) return;
    const stored = qaMode ? null : readStoredJourney();
    if (revisionForJourney(journey) !== attempt.baseRevision ||
        !sameStorageSnapshot(snapshot, readPrimaryStorageSnapshot()) ||
        (expectedSaved && (stored?.status !== "valid" || revisionForJourney(stored.journey) !== attempt.baseRevision))) {
      cancelRelayConfirmation();
      if (expectedSaved && stored?.status === "valid") {
        journey = stored.journey;
        storageWriteAvailable = true;
        sessionOnlyAuthority = false;
        stars = createStars();
        leaveRelay();
        refreshCareProjection("The saved Journey changed. Your Relay attempt was released; open a fresh relay to continue from this history.");
        showToast("Journey updated from local save · Relay completion was not kept");
      } else {
        storageWriteAvailable = false;
        sessionOnlyAuthority = true;
        ui.relayKeepCopy.textContent = "The saved Journey could not be verified. This completion was not kept. Your open Journey remains in this session.";
      }
      updateContinuity();
      publishDesktopJourney();
      render();
      return;
    }
    const candidate = commitRelayCompletion(journey, attempt, attempt.sessionId);
    if (candidate === journey) return;
    if (!qaMode && (!expectedSaved || !navigator.locks || !replaceStoredJourney(candidate))) {
      ui.relayKeepCopy.textContent = "Completion is ready, but a verified local save is unavailable. Your current Journey was kept.";
      return;
    }
    journey = candidate;
    relaySaved = true;
    updateContinuity();
    publishDesktopJourney();
    showToast(qaMode ? "Relay kept for this test session" : "Relay completion kept in your Journey");
  };
  try {
    if (!qaMode && navigator.locks) await navigator.locks.request(JOURNEY_LOCK_NAME, { signal: lockAbort.signal }, commit);
    else commit();
  } catch (error) {
    if (!lockAbort.signal.aborted) ui.relayKeepCopy.textContent = error instanceof Error ? error.message : "The completion could not be saved.";
  } finally {
    interaction?.finish();
    if (relayLockAbort === lockAbort) relayLockAbort = null;
    commitInFlight = false;
    ui.relayKeep.disabled = journeyInputInterlocked || deriveActivityMilestones(journey).some((entry) => entry.activityId === "broken-relay");
  }
  if (relaySaved && relayAttempt === attempt && mode === "relay") {
    updateRelayInterface(true);
    render();
  }
}

function leaveBattleLab(): void {
  cancelBattleConfirmation();
  battlePracticeBase = null; battleSavedId = null;
  const returnTarget = battleFocusReturnTarget?.isConnected ? battleFocusReturnTarget : ui.battleButton;
  battleFocusReturnTarget = null;
  battleState = null;
  battleOwnedCards = null;
  battleLockedCommands = {};
  battleLastResult = "Choose both commands";
  setMode("habitat");
  returnTarget.focus({ preventScroll: true });
}

function cancelBattleConfirmation(): void {
  battleWhatIf = null;
  battleReviewGeneration += 1;
  battleLockAbort?.abort();
  battleLockAbort = null;
}

function currentPracticeAttempt(): PracticeAttempt | null {
  if (!battleState || !battlePracticeBase || battlePracticeBase.opponentMode !== "companion" ||
      battleState.status !== "complete" || battleState.history.some((event) => event.commands.some((command) => command.action === "surrender"))) return null;
  return { originDigest: battlePracticeBase.originDigest, baseRevision: battlePracticeBase.baseRevision,
    sessionId: battlePracticeBase.sessionId,
    replay: { rulesVersion: 1, battleId: battleState.battleId, teams: battlePracticeBase.teams,
      commands: battleState.history.map((event) => event.commands) } };
}

function canKeepBattle(): boolean {
  const attempt = currentPracticeAttempt();
  return !!attempt && !battleKeepBusy && !commitInFlight && !journeyInputInterlocked && !continuityIsOpen() &&
    (qaMode || (storageWriteAvailable && Boolean(navigator.locks))) &&
    mode === "battle" && attempt.baseRevision === revisionForJourney(journey) &&
    attempt.originDigest === journeyOriginSha256(journey) && battleSavedId !== attempt.replay.battleId &&
    savedPracticeSummaries().length < MAX_KEPT_PRACTICES;
}

/** Read the existing save owner; a finished round is never itself a saved result. */
function battleRetention(): { status: "unsaved" | "saving" | "saved" | "session-only" | "unavailable"; message: string } {
  if (battleKeepBusy) return { status: "saving", message: "Checking the replay and keeping this practice…" };
  if (battleState && battleSavedId === battleState.battleId) return qaMode
    ? { status: "session-only", message: "Kept for this test session only. This is not a saved Journey." }
    : { status: "saved", message: "Kept once in your Journey. You can return to Habitat." };
  if (battleOpponentMode === "local") return { status: "unavailable", message: "Two-player practice is temporary. Return to Habitat when you are done." };
  if (battleState?.history.some((event) => event.commands.some((command) => command.action === "surrender"))) {
    return { status: "unavailable", message: "Ended early. Only completed partner practices can be kept." };
  }
  const attempt = currentPracticeAttempt();
  if (attempt && (attempt.baseRevision !== revisionForJourney(journey) || attempt.originDigest !== journeyOriginSha256(journey))) {
    return { status: "unavailable", message: "Your Journey changed during this practice. This result has not been kept." };
  }
  if (savedPracticeSummaries().length >= MAX_KEPT_PRACTICES) return { status: "unavailable", message: "Your Journey has reached its saved-practice limit. This result remains temporary." };
  if (!qaMode && (!storageWriteAvailable || !navigator.locks)) return { status: "unavailable", message: "A verified local save is unavailable. This result remains temporary." };
  return { status: "unsaved", message: boundedNativeText(battleKeepMessage, 300) };
}

async function keepBattleCompletion(): Promise<void> {
  if (!canKeepBattle()) return;
  const attempt = currentPracticeAttempt()!;
  const completedState = battleState;
  const interaction = desktopInteractions?.begin();
  if (desktopInteractions && !interaction) return;
  const generation = battleReviewGeneration;
  const snapshot = readPrimaryStorageSnapshot();
  const expectedSaved = storageWriteAvailable;
  const lockAbort = new AbortController();
  battleLockAbort = lockAbort;
  battleKeepBusy = true; commitInFlight = true;
  battleKeepMessage = "Checking and keeping this practice…";
  updateBattleInterface();
  const commit = (): void => {
    if (lockAbort.signal.aborted || completedState !== battleState || generation !== battleReviewGeneration ||
        mode !== "battle" || continuityIsOpen() || journeyInputInterlocked || (interaction && !interaction.isCurrent())) return;
    const stored = qaMode ? null : readStoredJourney();
    if (revisionForJourney(journey) !== attempt.baseRevision ||
        !sameStorageSnapshot(snapshot, readPrimaryStorageSnapshot()) ||
        (expectedSaved && (stored?.status !== "valid" || revisionForJourney(stored.journey) !== attempt.baseRevision))) {
      battleKeepMessage = "The saved Journey changed. This result was not kept; return to Habitat and review current history.";
      return;
    }
    const candidate = commitPracticeCompletion(journey, attempt, attempt.sessionId);
    if (candidate === journey) return;
    // Keep each admitted save portable within the existing archive limits.
    serializeJourneyArchive(candidate);
    if (!qaMode && (!expectedSaved || !navigator.locks || !replaceStoredJourney(candidate))) {
      battleKeepMessage = "A verified local save is unavailable. This result was not kept and your current Journey is unchanged.";
      return;
    }
    journey = candidate;
    battleSavedId = attempt.replay.battleId;
    battleKeepMessage = qaMode ? "Kept for this test session only." : "Kept once in your Journey. Review the round history anytime in this encounter.";
    updateContinuity();
    publishDesktopJourney();
  };
  try {
    if (!qaMode && navigator.locks) await navigator.locks.request(JOURNEY_LOCK_NAME, { signal: lockAbort.signal }, commit);
    else commit();
  } catch (error) {
    if (!lockAbort.signal.aborted) battleKeepMessage = error instanceof Error ? error.message : "This practice could not be kept.";
  } finally {
    interaction?.finish();
    if (battleLockAbort === lockAbort) battleLockAbort = null;
    battleKeepBusy = false; commitInFlight = false;
    if (completedState === battleState && battleSavedId !== attempt.replay.battleId &&
        battleKeepMessage === "Checking and keeping this practice…") {
      battleKeepMessage = lockAbort.signal.aborted ? "Keep was cancelled. This result remains temporary."
        : "This practice was not kept. Your Journey is unchanged.";
    }
    if (completedState === battleState && mode === "battle") updateBattleInterface();
    publishDesktopJourney();
  }
}

function describeBattleCommand(state: BattleState, command: BattleCommand): string {
  return describeBattleAction(state, command.teamId, command.action, command.targetQiMonId);
}

function describeBattleOutcome(event: BattleRoundEvent): string {
  return event.outcomes.map((outcome) => {
    const effects = [`${outcome.damageTaken} taken`, `${outcome.damageAbsorbed} absorbed`];
    if (outcome.integrityRestored) effects.push(`${outcome.integrityRestored} restored`);
    if (outcome.selfDamage) effects.push(`${outcome.selfDamage} self-cost`);
    if (outcome.sparkSpent) effects.push(`${outcome.sparkSpent} Spark spent`);
    if (outcome.exposedApplied) effects.push("opponent marked");
    if (outcome.exposedCleared) effects.push("exposure cleared");
    if (outcome.replacementQiMonId) effects.push("reserve entered");
    return `${battlePlayerName(outcome.teamId)} ${BATTLE_ACTION_LABELS[outcome.action]}: ${effects.join(", ")}`;
  }).join(". ");
}

function boundedNativeText(text: string, bytes: number): string {
  let result = "";
  for (const character of text) {
    if (new TextEncoder().encode(result + character).length > bytes) break;
    result += character;
  }
  return result;
}

function currentWhatIfBasis(): string | null {
  if (!desktopHost?.visible || mode !== "battle" || !battleState || battleState.status !== "active" ||
      battleLockedCommands.one || journeyInputInterlocked || continuityIsOpen() || commitInFlight || battleKeepBusy) return null;
  // The automatic partner's sealed move is deliberately never an input. A
  // human opponent sealing is a public control transition, not a move reveal.
  return JSON.stringify([battleRevision(battleState), revisionForJourney(journey), battleOpponentMode,
    battleOpponentMode === "local" && !!battleLockedCommands.two, battleReviewGeneration]);
}

function currentWhatIfReport(): NonNullable<ReturnType<typeof compareBattleChoices>> | null {
  if (battleWhatIf && battleWhatIf.basis !== currentWhatIfBasis()) battleWhatIf = null;
  return battleWhatIf?.report ?? null;
}

function updateWhatIf(actionId: string): boolean {
  const basis = currentWhatIfBasis();
  if (!basis || !battleState) return false;
  if (actionId === "what-if:close") { battleWhatIf = null; return true; }
  const current = currentWhatIfReport();
  const choices = listBattleChoices(battleState, "one");
  const first = actionId.startsWith("what-if:first:") ? actionId.slice("what-if:first:".length)
    : current?.firstId ?? choices[0]?.id;
  const second = actionId.startsWith("what-if:second:") ? actionId.slice("what-if:second:".length)
    : current?.secondId ?? choices[1]?.id;
  if (!first || !second) return false;
  const report = compareBattleChoices(battleState, "one", first, second);
  if (!report || currentWhatIfBasis() !== basis) return false;
  battleWhatIf = { basis, report };
  return true;
}

/** Available UI intents only. Partner sealed commands are intentionally absent. */
function projectArena(): DesktopArenaState | null {
  if (mode !== "habitat" && mode !== "battle") { battleWhatIf = null; return null; }
  const state = mode === "battle" ? battleState : null;
  const whatIf = currentWhatIfReport();
  const blocked = journeyInputInterlocked || continuityIsOpen() || commitInFlight || battleKeepBusy;
  const actions: DesktopArenaAction[] = [];
  const add = (id: string, label: string, detail: string): void => {
    actions.push({ id, label: boundedNativeText(label, 120), detail: boundedNativeText(detail, 300) });
  };
  if (!blocked) {
    if (!state) add("start", "Start partner practice", "Use the current formation with a public-state practice partner. Nothing is sent to a model.");
    else if (state.status === "complete") {
      if (canKeepBattle()) add("keep", "Keep practice in Journey", "Save this replay-checked completion once. No care, growth or appearance points are awarded.");
      add("again", "Build another formation", "Leave this result and choose another formation.");
    } else {
      for (const teamId of BATTLE_TEAM_IDS) {
        if (battleLockedCommands[teamId] || (battleOpponentMode === "companion" && teamId === "two")) continue;
        const team = state.teams[teamId === "one" ? 0 : 1];
        const actor = team.roster.find((card) => card.id === team.activeQiMonId);
        for (const action of BATTLE_ACTIONS) {
          const targets = action === "swap" ? team.roster.filter((card) => card.integrity > 0 && card.id !== team.activeQiMonId).map((card) => card.id)
            : action === "signature" && actor?.role === "beacon" ? [undefined, ...team.roster.filter((card) => card.integrity > 0 && card.id !== team.activeQiMonId).map((card) => card.id)] : [undefined];
          for (const target of targets) {
            const command = createBattleCommand(state, teamId, action, target);
            if (!previewBattleCommand(state, command)) continue;
            const prefix = battleOpponentMode === "local" ? `${battlePlayerName(teamId)} · ` : "";
            const targetName = target ? team.roster.find((card) => card.id === target)?.name : null;
            add(`${teamId}:${action}${target ? `:${target}` : ""}`, prefix + BATTLE_ACTION_LABELS[action] + (targetName ? ` → ${targetName}` : ""), describeBattleCommand(state, command));
          }
        }
      }
      if (battleLockedCommands.one && battleLockedCommands.two) add("resolve", "Reveal and resolve", "Resolve both sealed commands together using the current rules.");
      if (currentWhatIfBasis()) {
        if (!whatIf) add("what-if:open", "What if?", "Compare first-player moves against possible responses. Your match stays unchanged.");
        else {
          add("what-if:close", "Close comparison", "Leave this rehearsal. No move has been chosen or sealed.");
          for (const choice of whatIf.choices) {
            if (choice.id !== whatIf.secondId) add(`what-if:first:${choice.id}`, choice.label, "Compare as the first option; does not play the move.");
            if (choice.id !== whatIf.firstId) add(`what-if:second:${choice.id}`, choice.label, "Compare as the second option; does not play the move.");
          }
        }
      }
    }
    if (mode === "battle") add("leave", "Return to Habitat", "Unkept practice stays temporary. Your Journey is unchanged.");
  }
  const phase = !state ? "entry" : state.status === "complete" ? "finished"
    : battleLockedCommands.one ? "sealed" : "planning";
  const readback = state ? buildBattleReadback(state, battleRetention()) : null;
  const summary = !state ? "Practice together with the same ARCHi. Choose a move and understand its outcome."
    : state.status === "complete" ? `${ui.battleWinner.textContent ?? "Practice complete"} ${battleKeepMessage}`
      : `Round ${state.round}. ${battleLastResult}`;
  const revision = sha256String(JSON.stringify([mode, state ? battleRevision(state) : null,
    revisionForJourney(journey), battleOpponentMode, !!battleLockedCommands.one,
    battleOpponentMode === "local" && !!battleLockedCommands.two, blocked, battleReviewGeneration, battleSavedId,
    state ? null : battleSetupReadback(), actions, whatIf ? [whatIf.firstId, whatIf.secondId] : null, readback]));
  return { battleId: state?.battleId ?? null, revision, phase, round: displayedBattleRound(state),
    summary: boundedNativeText(summary, 500), actions, whatIf, readback };
}

function performArenaAction(actionId: string, expectedRevision: string): boolean {
  const current = projectArena();
  if (!current || current.revision !== expectedRevision || !current.actions.some((action) => action.id === actionId) ||
      (desktopHost && !desktopHost.visible)) return false;
  if (actionId.startsWith("what-if:")) {
    if (!updateWhatIf(actionId)) return false;
  } else if (actionId === "start") {
    if (mode !== "battle") openBattleLab();
    ui.battleOpponentMode.value = "companion"; updateBattleOpponentMode(); startBattle();
  } else if (actionId === "leave") leaveBattleLab();
  else if (actionId === "again") ui.battleAgain.click();
  else if (actionId === "keep") { void keepBattleCompletion(); }
  else if (actionId === "resolve") resolveBattle();
  else {
    const [teamId, action, target] = actionId.split(":") as [BattleTeamId, BattleAction, string | undefined];
    const control = battleCommandControl(teamId);
    control.action.value = action; updateBattleTarget(teamId);
    control.target.value = target ?? "";
    lockBattleCommand(teamId);
  }
  publishDesktopJourney();
  render();
  return true;
}

function startBattle(): void {
  if (commitInFlight || journeyInputInterlocked || mode !== "battle" || continuityIsOpen() || (desktopHost && !desktopHost.visible)) return;
  cancelBattleConfirmation();
  battleSequence += 1;
  const teams = [readBattleTeamSetup("one"), readBattleTeamSetup("two")] as const;
  const battleId = qaMode ? `00000000-0000-4000-8000-${String(battleSequence).padStart(12, "0")}` : crypto.randomUUID();
  battleState = createBattle(battleId, teams[0], teams[1]);
  battlePracticeBase = { originDigest: journeyOriginSha256(journey), baseRevision: revisionForJourney(journey),
    sessionId: crypto.randomUUID(), teams, opponentMode: battleOpponentMode };
  battleSavedId = null;
  battleKeepMessage = "Nothing is saved until you choose Keep practice.";
  battleLockedCommands = {};
  preparePracticePartner();
  battleLastResult = battleOpponentMode === "companion" ? "Choose your first move" : "Choose both commands";
  battleImpactPulse = reducedMotion ? 0 : 1;
  updateBattleInterface();
  render();
  focusBattleControl(ui.battleOneAction);
}

function focusBattleControl(control: HTMLElement): void {
  if (desktopHost) {
    ui.battlePanel.tabIndex = -1;
    ui.battlePanel.focus({ preventScroll: true });
  } else control.focus();
}

function battleTeam(teamId: BattleTeamId) {
  return battleState?.teams.find((team) => team.id === teamId) ?? null;
}

function battleActiveQiMon(teamId: BattleTeamId): BattleQiMonState | null {
  const team = battleTeam(teamId);
  return team?.roster.find((card) => card.id === team.activeQiMonId) ?? null;
}

function battleDisplayedQiMon(teamId: BattleTeamId): BattleQiMonState | null {
  const active = battleActiveQiMon(teamId);
  if (active) return active;
  const team = battleTeam(teamId);
  if (!team) return null;
  for (const event of [...(battleState?.history ?? [])].reverse()) {
    for (const outcome of event.outcomes) {
      const recipient = team.roster.find((card) => card.id === outcome.damageRecipientQiMonId);
      if (recipient) return recipient;
    }
  }
  return team.roster.at(-1) ?? null;
}

function battleNeedsTarget(teamId: BattleTeamId, action: BattleAction): boolean {
  const team = battleTeam(teamId);
  const active = battleActiveQiMon(teamId);
  const hasReserve = Boolean(team?.roster.some((card) => card.integrity > 0 && card.id !== team.activeQiMonId));
  return hasReserve && (action === "swap" || (action === "signature" && active?.role === "beacon"));
}

function updateBattleTarget(teamId: BattleTeamId): void {
  const actionSelect = teamId === "one" ? ui.battleOneAction : ui.battleTwoAction;
  const targetSelect = teamId === "one" ? ui.battleOneTarget : ui.battleTwoTarget;
  const targetLabel = teamId === "one" ? ui.battleOneTargetLabel : ui.battleTwoTargetLabel;
  const team = battleTeam(teamId);
  const action = (BATTLE_ACTIONS as readonly string[]).includes(actionSelect.value)
    ? (actionSelect.value as BattleAction)
    : "pulse";
  const playerName = battlePlayerName(teamId);
  const actionDescription = `${BATTLE_ACTION_LABELS[action]}: ${BATTLE_ACTION_DESCRIPTIONS[action]}`;
  actionSelect.setAttribute("aria-label", `${playerName} command, ${actionDescription}`);
  actionSelect.title = actionDescription;
  const needsTarget = battleNeedsTarget(teamId, action);
  const previous = targetSelect.value;
  targetSelect.replaceChildren();
  if (action === "signature") {
    const stay = document.createElement("option");
    stay.value = "";
    stay.textContent = "Stay active";
    targetSelect.append(stay);
  }
  for (const card of team?.roster ?? []) {
    if (card.integrity <= 0 || card.id === team?.activeQiMonId) continue;
    const option = document.createElement("option");
    option.value = card.id;
    option.textContent = `${card.name} · ${card.integrity}/${card.maximumIntegrity}`;
    targetSelect.append(option);
  }
  if ([...targetSelect.options].some((option) => option.value === previous)) targetSelect.value = previous;
  targetLabel.hidden = !needsTarget;
  targetSelect.disabled = !needsTarget;
  if (teamId === "one") updateBattleCommandHelp();
}

function updateBattleCommandHelp(): void {
  const action = ui.battleOneAction.value as BattleAction;
  ui.battleCommandHelp.textContent = describeBattleAction(battleState, "one", action, selectedBattleTarget("one", action));
  ui.battleOneLock.textContent = battleOpponentMode === "companion" ? "Play turn" : "Seal P1 command";
}

function updateBattleActionSelect(teamId: BattleTeamId): void {
  const select = teamId === "one" ? ui.battleOneAction : ui.battleTwoAction;
  const team = battleTeam(teamId);
  const previous = select.value;
  select.replaceChildren();
  for (const action of BATTLE_ACTIONS) {
    const option = document.createElement("option");
    option.value = action;
    option.textContent = BATTLE_ACTION_LABELS[action];
    option.disabled =
      (action === "signature" && (team?.spark ?? 0) <= 0) ||
      (action === "swap" && !team?.roster.some((card) => card.integrity > 0 && card.id !== team.activeQiMonId));
    select.append(option);
  }
  if ([...select.options].some((option) => option.value === previous && !option.disabled)) select.value = previous;
  else select.value = "pulse";
  updateBattleTarget(teamId);
}

function battleCommandControl(teamId: BattleTeamId) {
  return teamId === "one"
    ? {
        fieldset: ui.battleOneCommandFieldset,
        action: ui.battleOneAction,
        target: ui.battleOneTarget,
        lock: ui.battleOneLock,
        sealed: ui.battleOneSealed,
      }
    : {
        fieldset: ui.battleTwoCommandFieldset,
        action: ui.battleTwoAction,
        target: ui.battleTwoTarget,
        lock: ui.battleTwoLock,
        sealed: ui.battleTwoSealed,
      };
}

function updateBattleCommandLocks(): void {
  const complete = !battleState || battleState.status === "complete";
  for (const teamId of BATTLE_TEAM_IDS) {
    const control = battleCommandControl(teamId);
    const partner = battleOpponentMode === "companion" && teamId === "two";
    control.fieldset.hidden = partner;
    const locked = Boolean(battleLockedCommands[teamId]);
    control.fieldset.dataset.locked = String(locked);
    control.action.disabled = complete || locked;
    control.target.disabled = complete || locked || !battleNeedsTarget(
      teamId,
      (BATTLE_ACTIONS as readonly string[]).includes(control.action.value)
        ? (control.action.value as BattleAction)
        : "pulse",
    );
    control.lock.disabled = complete || locked;
    control.lock.hidden = locked;
    control.sealed.hidden = !locked;
  }
  ui.battleResolve.disabled =
    complete || !battleLockedCommands.one || !battleLockedCommands.two;
  ui.battleResolve.hidden = battleOpponentMode === "companion";
}

function renderBattleRoster(teamId: BattleTeamId): void {
  const team = battleTeam(teamId);
  const container = teamId === "one" ? ui.battleOneRoster : ui.battleTwoRoster;
  container.replaceChildren();
  for (const card of team?.roster ?? []) {
    const item = document.createElement("span");
    item.setAttribute("role", "listitem");
    item.classList.toggle("is-active", card.id === team?.activeQiMonId);
    item.classList.toggle("is-ko", card.integrity <= 0);
    item.style.setProperty("--role-color", ROLES[card.role].hue);
    item.textContent = `${ROLES[card.role].glyph} ${card.name} · ${card.integrity}`;
    item.setAttribute(
      "aria-label",
      `${card.name}, ${ROLES[card.role].title}, ${card.integrity} of ${card.maximumIntegrity} Integrity${card.exposed ? ", exposed: next damaging impact gains 3" : ""}${
        card.id === team?.activeQiMonId ? ", active" : ""
      }${card.integrity <= 0 ? ", settled" : ""}`,
    );
    container.append(item);
  }
}

function describeBattleRound(): string {
  const event = battleState?.history.at(-1);
  if (!event) return battleOpponentMode === "companion" ? "Choose your move" : "Choose both commands";
  return describeBattleOutcome(event);
}

function updateBattleTeamHud(teamId: BattleTeamId): void {
  const team = battleTeam(teamId);
  const displayed = battleDisplayedQiMon(teamId);
  if (!team || !displayed) return;
  const total = teamIntegrity(team);
  const fill = teamId === "one" ? ui.battleOneIntegrityFill : ui.battleTwoIntegrityFill;
  const name = teamId === "one" ? ui.battleOneName : ui.battleTwoName;
  const spark = teamId === "one" ? ui.battleOneSpark : ui.battleTwoSpark;
  const meta = teamId === "one" ? ui.battleOneMeta : ui.battleTwoMeta;
  fill.style.width = `${(total / BATTLE_LIMITS.teamIntegrity) * 100}%`;
  const integrity = fill.parentElement;
  integrity?.setAttribute("aria-valuenow", String(total));
  integrity?.setAttribute("aria-valuetext", `${total} of ${BATTLE_LIMITS.teamIntegrity} total Integrity`);
  name.textContent = team.activeQiMonId ? displayed.name : `${displayed.name} · Settled`;
  spark.textContent = `Spark ${team.spark}`;
  meta.textContent = team.activeQiMonId
    ? `${total} / ${BATTLE_LIMITS.teamIntegrity} Integrity · Active ${ROLES[displayed.role].form} · ${displayed.resonance} Resonance`
    : `0 / ${BATTLE_LIMITS.teamIntegrity} Integrity · Formation settled · ${ROLES[displayed.role].form} projection retained`;
  renderBattleRoster(teamId);
}

function updateBattleTranscript(): void {
  ui.battleTranscript.replaceChildren();
  for (const event of battleState?.history ?? []) {
    const item = document.createElement("li");
    item.textContent = `Round ${event.round} · ${describeBattleOutcome(event)}`;
    ui.battleTranscript.append(item);
  }
}

function updateBattleInterface(): void {
  const active = Boolean(battleState);
  ui.battlePanel.classList.toggle("has-active-battle", active);
  ui.battlePanel.dataset.opponentMode = battleOpponentMode;
  ui.battleSetup.hidden = active;
  ui.battleCombat.hidden = !active;
  if (!battleState) {
    ui.battleStatus.textContent = battleOwnedCards
      ? "Your invited QiMon are ready. This is a rules v1 practice; Keep the result before claiming training or a pair bond."
      : "Choose a formation. Discover how your QiMon work together.";
    updateBattleBuilder("one");
    updateBattleBuilder("two");
    if (mode === "battle") updateHeader();
    publishDesktopJourney();
    return;
  }
  updateBattleTeamHud("one");
  updateBattleTeamHud("two");
  updateBattleActionSelect("one");
  updateBattleActionSelect("two");
  updateBattleCommandLocks();
  updateBattleTranscript();
  ui.battleRoundLabel.textContent = battleState.status === "complete" ? "Field settled" : `Round ${battleState.round}`;
  ui.battleRoundResult.textContent = battleLastResult;
  ui.battleStatus.textContent = battleState.status === "complete" ? "Take a breath. Try another formation when you’re ready."
    : battleOpponentMode === "companion" ? "Choose a move, then play the turn. Your partner is ready."
    : "Seal both commands, then reveal the turn together.";
  const complete = battleState.status === "complete";
  const keep = element<HTMLButtonElement>("battle-keep");
  keep.hidden = !complete;
  keep.disabled = !canKeepBattle();
  keep.textContent = battleSavedId === battleState.battleId ? "Practice kept" : battleKeepBusy ? "Keeping…" : "Keep practice";
  element<HTMLElement>("battle-keep-status").textContent = battleOpponentMode === "local"
    ? "Two-player encounters remain temporary; kept practice uses the public-state partner."
    : battleState.history.some((event) => event.commands.some((command) => command.action === "surrender"))
      ? "This practice ended early. Complete a non-surrender practice to keep a receipt."
      : battleKeepMessage;
  ui.battleCommandDock.hidden = complete;
  ui.battleComplete.hidden = !complete;
  if (complete) {
    ui.battleWinner.textContent =
      battleState.winner === "draw"
        ? "The Field settles in a draw."
        : battleState.winner === "one"
          ? battleOpponentMode === "companion" ? "Your formation holds the field." : "Player One holds the Field."
          : battleOpponentMode === "companion" ? "Your partner holds the field. Try a new tactic." : "Player Two holds the Field.";
  }
  if (mode === "battle") updateHeader();
  publishDesktopJourney();
}

function selectedBattleTarget(teamId: BattleTeamId, action: BattleAction): string | undefined {
  if (!battleNeedsTarget(teamId, action)) return undefined;
  const target = teamId === "one" ? ui.battleOneTarget.value : ui.battleTwoTarget.value;
  return target || undefined;
}

function battleCommand(teamId: BattleTeamId): BattleCommand {
  if (!battleState) throw new Error("No battle is active.");
  const value = teamId === "one" ? ui.battleOneAction.value : ui.battleTwoAction.value;
  const action = (BATTLE_ACTIONS as readonly string[]).includes(value) ? (value as BattleAction) : "pulse";
  return createBattleCommand(battleState, teamId, action, selectedBattleTarget(teamId, action));
}

function lockBattleCommand(teamId: BattleTeamId): void {
  if (!battleState || battleState.status !== "active" || battleLockedCommands[teamId] || mode !== "battle" ||
      continuityIsOpen() || (desktopHost && !desktopHost.visible)) return;
  battleLockedCommands = { ...battleLockedCommands, [teamId]: battleCommand(teamId) };
  if (battleOpponentMode === "companion" && teamId === "one") {
    resolveBattle();
    return;
  }
  const bothLocked = Boolean(battleLockedCommands.one && battleLockedCommands.two);
  battleLastResult = bothLocked
    ? "Both commands sealed"
    : `${teamId === "one" ? "Player One" : "Player Two"} sealed · pass the device`;
  ui.battleRoundResult.textContent = battleLastResult;
  updateBattleCommandLocks();
  publishDesktopJourney();
  focusBattleControl(bothLocked ? ui.battleResolve : teamId === "one" ? ui.battleTwoAction : ui.battleOneAction);
}

function resolveBattle(): void {
  if (!battleState || battleState.status !== "active" || mode !== "battle" || continuityIsOpen() ||
      (desktopHost && !desktopHost.visible)) return;
  const commandOne = battleLockedCommands.one;
  const commandTwo = battleLockedCommands.two;
  if (!commandOne || !commandTwo) {
    battleLastResult = "Seal both commands first";
    ui.battleRoundResult.textContent = battleLastResult;
    updateBattleCommandLocks();
    return;
  }
  const result = resolveBattleRound(battleState, commandOne, commandTwo);
  if (!result.accepted) {
    battleLockedCommands = {};
    preparePracticePartner();
    battleLastResult = result.reason;
    updateBattleInterface();
    return;
  }
  battleState = result.state;
  battleLockedCommands = {};
  preparePracticePartner();
  battleLastResult = describeBattleRound();
  battleImpactPulse = reducedMotion ? 0 : 1;
  const onePosition = battleQiMonPosition("one");
  const twoPosition = battleQiMonPosition("two");
  if (!reducedMotion && result.event.outcomes[1].damageDealt > 0) {
    spawnBurst(onePosition.x, onePosition.y, ROLES[battleActiveQiMon("one")?.role ?? "scout"].hue, 16, 0.55);
  }
  if (!reducedMotion && result.event.outcomes[0].damageDealt > 0) {
    spawnBurst(twoPosition.x, twoPosition.y, ROLES[battleActiveQiMon("two")?.role ?? "guardian"].hue, 16, 0.55);
  }
  updateBattleInterface();
  render();
  focusBattleControl(battleState.status === "complete" ? ui.battleAgain : ui.battleOneAction);
}

function setMode(next: Mode): void {
  if (mode === "relay" && next !== "relay") {
    cancelRelayConfirmation();
    relayAttempt = null;
    relaySaved = false;
  }
  mode = next;
  document.documentElement.dataset.mode = next;
  const visibility = [
    [ui.intro, next === "habitat"],
    [ui.fieldCopy, next === "field"],
    [ui.proposal, next === "proposal"],
    [ui.reflection, next === "reflection"],
  ] as const;
  for (const [panel, visible] of visibility) {
    panel.classList.toggle("is-visible", visible);
    panel.setAttribute("aria-hidden", String(!visible));
    panel.inert = !visible;
  }
  ui.fieldRail.classList.toggle("is-active", next === "field" || next === "proposal");
  const battleVisible = next === "battle";
  const relayVisible = next === "relay";
  canvas.tabIndex = battleVisible || relayVisible ? -1 : 0;
  ui.battlePanel.hidden = !battleVisible;
  ui.battlePanel.inert = !battleVisible;
  ui.relayPanel.hidden = !relayVisible;
  ui.relayPanel.inert = !relayVisible;
  ui.experience.classList.toggle("is-hidden", battleVisible || relayVisible);
  ui.experience.setAttribute("aria-hidden", String(battleVisible || relayVisible));
  ui.fieldRail.classList.toggle("is-hidden", battleVisible || relayVisible);
  const presenceVisible = next === "habitat";
  ui.presenceConsole.classList.toggle("is-hidden", !presenceVisible);
  ui.presenceConsole.setAttribute("aria-hidden", String(!presenceVisible));
  ui.presenceConsole.inert = !presenceVisible;
  const navigatorAvailable = next === "field";
  ui.navigator.hidden = !navigatorAvailable;
  ui.navigator.inert = !navigatorAvailable;
  if (navigatorAvailable) updateFieldNavigator(undefined, false);
  if (next === "field") canvas.focus({ preventScroll: true });
  updateHeader();
  publishDesktopJourney();
}

function updateHeader(): void {
  if (mode === "relay") {
    ui.stageLabel.textContent = "Broken Relay";
    ui.playLabel.textContent = "A shared repair";
    return;
  }
  if (mode === "battle") {
    ui.stageLabel.textContent = "Practice Arena";
    ui.playLabel.textContent = battleState?.status === "complete" ? "Practice complete"
      : battleState ? `Round ${displayedBattleRound(battleState)}` : "Build teams";
    return;
  }
  const stage = stageForJourney(journey);
  const playLabel = `Play ${String(journey.plays + 1).padStart(2, "0")}`;
  const exploreDescription = journey.plays === 0 ? "Enter the first field" : "Enter today’s field";
  if (ui.stageLabel.textContent !== stage.name) ui.stageLabel.textContent = stage.name;
  if (ui.playLabel.textContent !== playLabel) ui.playLabel.textContent = playLabel;
  if (ui.exploreDescription.textContent !== exploreDescription) ui.exploreDescription.textContent = exploreDescription;
}

const CARE_MOOD_LABELS: Record<CareProjection["mood"], string> = {
  bright: "Bright",
  balanced: "Balanced",
  curious: "Curious",
  resting: "Resting",
  unsettled: "Seeking calm",
};

const CARE_MOOD_VISUALS: Record<CareProjection["mood"], { rgb: readonly [number, number, number]; pace: number; lift: number }> = {
  bright: { rgb: [239, 196, 112], pace: 1.7, lift: 5.6 },
  balanced: { rgb: [101, 224, 220], pace: 1.55, lift: 5 },
  curious: { rgb: [154, 124, 244], pace: 1.85, lift: 5.4 },
  resting: { rgb: [94, 169, 231], pace: 1.05, lift: 3.2 },
  unsettled: { rgb: [239, 118, 95], pace: 1.34, lift: 3.8 },
};

function careObservationTime(): string {
  return qaMode ? journey.care.updatedAt : new Date().toISOString();
}

function updateCareInterface(message?: string): void {
  const values = [
    [ui.careEnergy, ui.careEnergyOutput, careProjection.energy],
    [ui.careCalm, ui.careCalmOutput, careProjection.calm],
    [ui.careCuriosity, ui.careCuriosityOutput, careProjection.curiosity],
  ] as const;
  for (const [meter, output, value] of values) {
    const rounded = Math.round(value);
    meter.value = rounded;
    meter.textContent = `${rounded}%`;
    output.textContent = String(rounded);
  }
  ui.careMood.textContent = CARE_MOOD_LABELS[careProjection.mood];
  element<HTMLElement>("app").dataset.careMood = careProjection.mood;
  if (journeyInputInterlocked) ui.careResponse.textContent = DEVICE_SETTLING_RESPONSE;
  else if (message) ui.careResponse.textContent = message;
  else if (ui.careResponse.textContent === DEVICE_SETTLING_RESPONSE) ui.careResponse.textContent = DEFAULT_CARE_RESPONSE;
}

function refreshCareProjection(message?: string): void {
  careProjection = projectCare(journey.care, careObservationTime());
  updateCareInterface(message);
}

function describeRelativePoint(point: Point): string {
  const dx = point.x - player.x;
  const dy = point.y - player.y;
  const distance = Math.max(0, Math.round(Math.hypot(dx, dy) / 10) * 10);
  const angle = Math.atan2(dy, dx);
  const directions = ["east", "southeast", "south", "southwest", "west", "northwest", "north", "northeast"];
  const directionIndex = Math.round(angle / (Math.PI / 4));
  const direction = directions[(directionIndex + 8) % 8];
  return `${direction}, about ${distance} pixels away`;
}

function updateFieldNavigator(announcement?: string, announceStatus = true): void {
  ui.navigatorSignals.replaceChildren();
  if (!session || mode !== "field") {
    const status = "The accessible navigator becomes available inside a field.";
    if (announceStatus && ui.navigatorStatus.textContent !== status) ui.navigatorStatus.textContent = status;
    return;
  }

  const remaining = session.echoes.filter((echo) => !session!.collected.includes(echo.id));
  if (remaining.length === 0) {
    const status = announcement ?? "Three signals found. A proposal is forming.";
    if (announceStatus && ui.navigatorStatus.textContent !== status) ui.navigatorStatus.textContent = status;
    return;
  }

  const status = announcement ?? `${session.collected.length} of 3 signals found. Choose a remaining signal to guide ARCHi toward it.`;
  if (announceStatus && ui.navigatorStatus.textContent !== status) ui.navigatorStatus.textContent = status;
  for (const echo of remaining) {
    const point = echoPosition(echo);
    const aura = AURAS[echo.aura];
    const button = document.createElement("button");
    button.type = "button";
    button.className = "navigator-signal";
    button.style.setProperty("--signal-color", aura.color);
    button.textContent = `${aura.label} · ${describeRelativePoint(point)}`;
    button.addEventListener("click", () => {
      const currentPoint = echoPosition(echo);
      target.x = currentPoint.x;
      target.y = currentPoint.y;
      ui.navigatorStatus.textContent = `Guiding ARCHi toward ${aura.label.toLowerCase()}, ${describeRelativePoint(currentPoint)}.`;
    });
    ui.navigatorSignals.append(button);
  }
}

function updateFieldInterface(): void {
  const collected = session?.collected.length ?? 0;
  ui.fieldName.textContent = session ? `Field · ${session.fieldName}` : "Habitat · Core Pearl";
  ui.fieldEyebrow.textContent = collected === 0 ? "Observe" : collected < 3 ? `Observe · ${collected} of 3` : "Propose";
  ui.fieldTitle.textContent = collected === 0 ? "Find three signals" : collected < 3 ? "Follow what resonates" : "A pattern is forming";
  ui.fieldInstruction.textContent =
    collected < 3
      ? "Guide ARCHi into the lights that feel worth noticing. Red static can unsettle, but never ends the play."
      : "ARCHi is translating the signals into two possible expressions.";

  ui.signalPips.forEach((pip, index) => {
    const echoId = session?.collected[index];
    const aura = session?.echoes.find((echo) => echo.id === echoId)?.aura;
    pip.classList.toggle("is-found", Boolean(aura));
    pip.style.setProperty("--signal-color", aura ? AURAS[aura].color : "#65e0dc");
    pip.setAttribute("aria-label", aura ? `Signal ${index + 1}: ${AURAS[aura].label} found` : `Signal ${index + 1} not found`);
  });
  ui.signalProgress.setAttribute("aria-label", `Signals found: ${collected} of 3`);
  updateComposureInterface(true);
}

function updateComposureInterface(force = false): void {
  const roundedComposure = Math.round(fieldComposure);
  if (!force && roundedComposure === lastComposureRendered) return;
  lastComposureRendered = roundedComposure;
  ui.composureFill.style.width = `${fieldComposure}%`;
  ui.composureFill.style.background = fieldComposure < 45 ? "#ef765f" : "#65e0dc";
  ui.composureProgress.value = roundedComposure;
  ui.composureProgress.textContent = `${roundedComposure}%`;
}

function updateContinuity(): void {
  const passport = deriveJourneyPassport(journey);
  ui.passportDisplayID.textContent = passport.displayJourneyID;
  ui.passportCreated.dateTime = passport.createdAt;
  ui.passportCreated.textContent = new Date(passport.createdAt).toLocaleDateString(undefined, {
    year: "numeric", month: "long", day: "numeric",
  });
  ui.passportOrigin.textContent = passport.instanceID;
  publishDesktopJourney();
  const leading = dominantRole(journey);
  const stage = stageForJourney(journey);
  const plays = playHistory(journey);
  ui.dominantRole.textContent = ROLES[leading].title;
  ui.continuityGrowth.textContent = `${stage.name} · bond ${journey.bond} · ${journey.plays} completed ${journey.plays === 1 ? "play" : "plays"}`;
  ui.traceCount.textContent = `${plays.length} local`;
  const maximum = Math.max(1, ...ROLE_ORDER.map((role) => journey.affinities[role]));

  ui.affinityList.replaceChildren();
  for (const roleId of ROLE_ORDER) {
    const role = ROLES[roleId];
    const value = journey.affinities[roleId];
    const row = document.createElement("div");
    row.className = "affinity-row";
    row.style.setProperty("--role-color", role.hue);
    row.innerHTML = `
      <span>${role.shortTitle}</span>
      <span class="affinity-track"><span style="--affinity: ${(value / maximum) * 100}%"></span></span>
      <output>${value}</output>
    `;
    ui.affinityList.append(row);
  }

  ui.traceList.replaceChildren();
  const recent = plays.slice(-7).reverse();
  if (recent.length === 0) {
    const empty = document.createElement("li");
    empty.className = "trace-empty";
    empty.textContent = "No play has been kept yet. ARCHi’s first field is waiting.";
    ui.traceList.append(empty);
  } else {
    for (const trace of recent) {
      const item = document.createElement("li");
      const choice = trace.choice === "hold" ? "Held" : ROLES[trace.choice].shortTitle;
      const play = document.createElement("span");
      play.textContent = String(trace.play).padStart(2, "0");
      const field = document.createElement("span");
      field.textContent = trace.fieldName;
      const kept = document.createElement("em");
      kept.textContent = choice;
      item.append(play, field, kept);
      ui.traceList.append(item);
    }
  }
  const milestones = [ ...deriveActivityMilestones(journey), ...savedPracticeSummaries().map((practice) => ({
    title: `Practice ${practice.outcome} · ${practice.rounds} rounds`,
    text: `A complete partner practice, kept once. Replay ${practice.replayDigest.slice(0, 12)}. No care or appearance reward.`,
    committedAt: practice.committedAt,
  })) ];
  ui.milestoneCount.textContent = `${milestones.length} kept`;
  ui.milestoneList.replaceChildren();
  if (milestones.length === 0) {
    const empty = document.createElement("li");
    empty.className = "trace-empty";
    empty.textContent = "Shared activities can leave a milestone here when you choose to keep them.";
    ui.milestoneList.append(empty);
  }
  for (const milestone of milestones) {
    const item = document.createElement("li");
    const title = document.createElement("strong");
    title.textContent = milestone.title;
    const copy = document.createElement("p");
    copy.textContent = milestone.text;
    const time = document.createElement("time");
    time.dateTime = milestone.committedAt;
    time.textContent = new Date(milestone.committedAt).toLocaleDateString();
    item.append(title, copy, time);
    ui.milestoneList.append(item);
  }
}

function setJourneyArchiveStatus(message: string, isError = false): void {
  ui.journeyArchiveStatus.textContent = message;
  ui.journeyArchiveStatus.classList.toggle("is-error", isError);
}

function clearJourneyImportReview(clearStatus = false): void {
  journeyImportGeneration += 1;
  journeyImportLockAbort?.abort();
  journeyImportLockAbort = null;
  pendingJourneyImport = null;
  ui.journeyImportPreview.hidden = true;
  ui.confirmJourneyImport.disabled = journeyInputInterlocked;
  ui.confirmJourneyImport.textContent = "Replace Journey";
  ui.journeyFile.value = "";
  if (clearStatus) setJourneyArchiveStatus("");
}

function clearResetReview(): void {
  resetReviewGeneration += 1;
  resetLockAbort?.abort();
  resetLockAbort = null;
  ui.resetConfirm.hidden = true;
}

function rejectChangedJourneyStorage(adoptCompleteStoredJourney: boolean): void {
  const stored = readStoredJourney(true);
  const protectedStoredConflict = stored.status === "valid" && !adoptCompleteStoredJourney;
  if (stored.status === "valid" && adoptCompleteStoredJourney) {
    journey = stored.journey;
    storageWriteAvailable = true;
    sessionOnlyAuthority = false;
    session = null;
    particles = [];
    stars = createStars();
    setMode("habitat");
    refreshCareProjection("The saved Journey changed while the archive was being reviewed.");
  } else {
    storageWriteAvailable = false;
    sessionOnlyAuthority = true;
    refreshCareProjection(
      stored.status === "valid"
        ? "A different complete Journey is saved. The open session-only Journey was kept in memory."
        : "The saved Journey changed or became unavailable. The open Journey was kept in memory.",
    );
  }
  clearJourneyImportReview();
  updateContinuity();
  updateFieldInterface();
  setJourneyArchiveStatus(
    protectedStoredConflict
      ? "A different complete Journey is already saved. Download this session copy before reloading; replacement is blocked to protect both."
      : "The saved Journey changed. Choose Review a copy again before replacing it.",
    true,
  );
  if (continuityIsOpen()) ui.reviewJourney.focus();
}

function relationDescription(relation: JourneyRelation, eventDifference: number): string {
  if (relation === "same") return "This is already the current chain-checked Journey.";
  if (relation === "advance") {
    return `This continues the same history by ${eventDifference} chain-checked ${eventDifference === 1 ? "event" : "events"}.`;
  }
  if (relation === "rewind") return "This returns to an earlier chain-checked point in the same history.";
  if (relation === "divergent") return "This shares ARCHi’s declared origin but follows a different chain-checked branch.";
  return "This archive belongs to a different ARCHi origin.";
}

function downloadJourneyArchive(): void {
  try {
    const exportedAt = new Date().toISOString();
    const source = serializeJourneyArchive(journey, exportedAt);
    const url = URL.createObjectURL(new Blob([source], { type: "application/json" }));
    const download = document.createElement("a");
    download.href = url;
    download.download = `ARCHi-Journey-${journey.id}-${exportedAt.slice(0, 10)}.json`;
    journeyDownloadLeases.retain(url);
    download.click();
    setJourneyArchiveStatus(`Prepared ${journey.events.length} locally bound ${journey.events.length === 1 ? "event" : "events"} · choose where to save in the download prompt.`);
  } catch (error) {
    setJourneyArchiveStatus(
      error instanceof Error ? error.message : "This Journey could not be prepared for download.",
      true,
    );
  }
}

async function reviewJourneyFile(file: File): Promise<void> {
  const reviewIsCurrent = desktopInteractions?.capture();
  if (desktopInteractions && (!reviewIsCurrent || !continuityIsOpen())) return;
  clearResetReview();
  clearJourneyImportReview();
  const reviewGeneration = journeyImportGeneration;
  const reviewBaseRevision = revisionForJourney(journey);
  const reviewStorageSnapshot = readPrimaryStorageSnapshot();
  const reviewExpectedPersisted = storageWriteAvailable;
  const canonicalMemorySnapshot: PrimaryStorageSnapshot = qaMode
    ? { status: "absent", digest: null }
    : { status: "present", digest: sha256String(serializeJourney(journey)) };
  if (!sameStorageSnapshot(reviewStorageSnapshot, canonicalMemorySnapshot)) {
    if (reviewExpectedPersisted) {
      rejectChangedJourneyStorage(true);
      return;
    }
    if (reviewStorageSnapshot.status === "present") {
      const stored = readStoredJourney(true);
      if (stored.status === "valid" && revisionForJourney(stored.journey) !== reviewBaseRevision) {
        rejectChangedJourneyStorage(false);
        return;
      }
    }
  }
  if (file.size > MAX_JOURNEY_ARCHIVE_BYTES) {
    setJourneyArchiveStatus("This Journey file is larger than the local import limit.", true);
    return;
  }

  let source: string;
  try {
    source = await file.text();
  } catch {
    if (reviewGeneration !== journeyImportGeneration || !continuityIsOpen() || (reviewIsCurrent && !reviewIsCurrent())) return;
    setJourneyArchiveStatus("This Journey file could not be read.", true);
    return;
  }
  if (reviewGeneration !== journeyImportGeneration || !continuityIsOpen() || (reviewIsCurrent && !reviewIsCurrent())) return;
  const inspection = inspectJourneyArchive(source);
  if (inspection.status !== "valid") {
    setJourneyArchiveStatus(inspection.message, true);
    return;
  }

  if (
    reviewGeneration !== journeyImportGeneration ||
    revisionForJourney(journey) !== reviewBaseRevision ||
    reviewExpectedPersisted !== storageWriteAvailable ||
    !sameStorageSnapshot(readPrimaryStorageSnapshot(), reviewStorageSnapshot)
  ) {
    rejectChangedJourneyStorage(reviewExpectedPersisted);
    return;
  }

  const preview = inspection.preview;
  const relation = compareJourneyLineage(journey, preview.journey);
  const currentStoredMatchesMemory =
    reviewStorageSnapshot.status === "present" &&
    reviewStorageSnapshot.digest === sha256String(serializeJourney(journey));
  const requiresWrite = relation !== "same" || !currentStoredMatchesMemory || !storageWriteAvailable;
  pendingJourneyImport = {
    generation: reviewGeneration,
    preview,
    relation,
    baseRevision: revisionForJourney(journey),
    baseWasPersisted: reviewExpectedPersisted,
    storageSnapshot: reviewStorageSnapshot,
    requiresWrite,
  };

  const stage = stageForJourney(preview.journey);
  const eventDifference = Math.abs(preview.eventCount - journey.events.length);
  ui.journeyImportTitle.textContent = `${preview.journeyId} · ${stage.name}`;
  ui.journeyImportSummary.textContent = `${preview.eventCount} chain-checked ${preview.eventCount === 1 ? "event" : "events"} · bond ${preview.journey.bond} · ${ROLES[preview.journey.expression].shortTitle}`;
  ui.journeyImportRelation.textContent = relationDescription(relation, eventDifference);
  const safeLockAvailable = qaMode || Boolean(navigator.locks);
  const storageSnapshotIsBindable = reviewStorageSnapshot.status !== "unreadable";
  const safeReplacementAvailable = safeLockAvailable && storageSnapshotIsBindable;
  ui.confirmJourneyImport.disabled = journeyInputInterlocked || !requiresWrite || !safeReplacementAvailable;
  ui.confirmJourneyImport.textContent =
    !safeReplacementAvailable && requiresWrite
      ? "Replacement unavailable"
      : relation === "same" && requiresWrite
        ? "Restore local save"
        : requiresWrite
          ? "Replace Journey"
          : "Already current";
  ui.journeyImportPreview.hidden = false;
  setJourneyArchiveStatus(
    safeReplacementAvailable || !requiresWrite
      ? "Archive structure and event chain checked. Nothing changes until you confirm."
      : !storageSnapshotIsBindable
        ? "Archive checked, but the current saved bytes cannot be read and bound safely."
        : "Archive checked, but this browser cannot safely lock a Journey replacement.",
    !safeReplacementAvailable && requiresWrite,
  );
  (requiresWrite && safeReplacementAvailable ? ui.confirmJourneyImport : ui.cancelJourneyImport).focus();
}

async function confirmJourneyImport(): Promise<void> {
  if (journeyInputInterlocked) {
    showToast("Reopen ARCHi to finish device setup · Journey unchanged");
    return;
  }
  const pending = pendingJourneyImport;
  if (!pending || !pending.requiresWrite || commitInFlight) return;
  if (pending.storageSnapshot.status === "unreadable") {
    setJourneyArchiveStatus("The current saved bytes cannot be read and bound safely.", true);
    return;
  }
  if (!qaMode && !navigator.locks) {
    setJourneyArchiveStatus("This browser cannot safely lock a Journey replacement.", true);
    return;
  }
  commitInFlight = true;
  let imported = false;

  const replaceUnderReviewedState = (): void => {
    if (
      pendingJourneyImport !== pending ||
      pending.generation !== journeyImportGeneration ||
      !continuityIsOpen()
    ) {
      return;
    }
    if (
      revisionForJourney(journey) !== pending.baseRevision ||
      !sameStorageSnapshot(readPrimaryStorageSnapshot(), pending.storageSnapshot)
    ) {
      rejectChangedJourneyStorage(pending.baseWasPersisted);
      return;
    }

    if (!replaceStoredJourney(pending.preview.journey)) {
      setJourneyArchiveStatus("The replacement could not be written and read back. The current Journey was kept.", true);
      return;
    }

    journey = pending.preview.journey;
    removeLegacyJourneyKeys();
    stars = createStars();
    session = null;
    particles = [];
    imported = true;
  };

  const lockAbort = new AbortController();
  journeyImportLockAbort = lockAbort;
  try {
    if (!qaMode) {
      await navigator.locks.request(JOURNEY_LOCK_NAME, { signal: lockAbort.signal }, replaceUnderReviewedState);
    } else {
      replaceUnderReviewedState();
    }
  } catch (error) {
    if (!(error instanceof DOMException && error.name === "AbortError")) {
      setJourneyArchiveStatus("The Journey replacement lock failed. The current Journey was kept.", true);
    }
  } finally {
    if (journeyImportLockAbort === lockAbort) journeyImportLockAbort = null;
    commitInFlight = false;
  }

  if (!imported) return;
  clearJourneyImportReview(true);
  closeContinuity();
  setMode("habitat");
  refreshCareProjection("A chain-checked Journey copy is now active on this device.");
  updateContinuity();
  updateFieldInterface();
  showToast("Journey copy restored locally · open field proposals released");
}

function openContinuity(): void {
  cancelRelayConfirmation();
  cancelBattleConfirmation();
  overlayReturnFocus = document.activeElement instanceof HTMLElement ? document.activeElement : ui.continuityButton;
  updateContinuity();
  ui.continuity.classList.add("is-open");
  ui.continuity.inert = false;
  ui.continuity.setAttribute("aria-hidden", "false");
  ui.continuityButton.setAttribute("aria-expanded", "true");
  ui.scrim.hidden = false;
  for (const region of [canvas, ui.topbar, ui.presenceConsole, ui.experience, ui.battlePanel, ui.relayPanel, ui.fieldRail, ui.navigator]) {
    region.inert = true;
  }
  keys.clear();
  player.vx = 0;
  player.vy = 0;
  target.x = player.x;
  target.y = player.y;
  ui.closeContinuity.focus();
  publishDesktopJourney();
}

function closeContinuity(): void {
  ui.continuity.classList.remove("is-open");
  ui.continuity.inert = true;
  ui.continuity.setAttribute("aria-hidden", "true");
  ui.continuityButton.setAttribute("aria-expanded", "false");
  ui.scrim.hidden = true;
  clearResetReview();
  clearJourneyImportReview(true);
  for (const region of [canvas, ui.topbar, ui.experience, ui.fieldRail]) region.inert = false;
  ui.presenceConsole.inert = mode !== "habitat";
  ui.battlePanel.inert = mode !== "battle";
  ui.relayPanel.inert = mode !== "relay";
  ui.navigator.inert = mode !== "field";
  const returnFocus = overlayReturnFocus?.isConnected ? overlayReturnFocus : ui.continuityButton;
  overlayReturnFocus = null;
  returnFocus.focus({ preventScroll: true });
  publishDesktopJourney();
}

function rosterCard(title: string, detail: string, action?: { label: string; run: () => void }, role?: RoleId): HTMLElement {
  const card = document.createElement("div");
  card.className = "qimon-roster-card";
  if (role) {
    const sigil = document.createElement("span");
    sigil.className = "qimon-roster-card__sigil";
    sigil.textContent = ROLES[role].glyph;
    sigil.style.setProperty("--qimon-sigil", ROLES[role].hue);
    sigil.setAttribute("aria-hidden", "true");
    card.append(sigil);
  }
  const copy = document.createElement("div");
  copy.className = "qimon-roster-card__text";
  const heading = document.createElement("strong");
  heading.textContent = title;
  const subline = document.createElement("small");
  subline.textContent = detail;
  copy.append(heading, subline);
  card.append(copy);
  if (action) {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = action.label;
    button.addEventListener("click", action.run);
    card.append(button);
  }
  return card;
}

function rosterAction(label: string, run: () => void, disabled = false): HTMLButtonElement {
  const button = document.createElement("button");
  button.type = "button";
  button.textContent = label;
  button.disabled = disabled;
  button.addEventListener("click", run);
  return button;
}

function startOwnedPractice(cards: readonly QiMonCard[]): void {
  if (journeyInputInterlocked || !cards.length || cards.length > 3 || !currentQiMonRoster()) return;
  closeQiMonRoster();
  battleFocusReturnTarget = ui.rosterEntry;
  battleOwnedCards = cards.map((card) => ({ ...card }));
  battleOpponentMode = "companion";
  ui.battleOpponentMode.value = "companion";
  ui.battleOneSize.value = String(cards.length);
  ui.battleOneBond.value = cards[0].role;
  cards.forEach((card, index) => { battleRosterRoleSelects.one[index].value = card.role; });
  setMode("battle");
  updateBattleOpponentMode();
  updateBattleInterface();
  ui.battleStart.focus({ preventScroll: true });
}

function startOwnedRelay(projection: QiMonRosterProjection): void {
  if (projection.team.length < 2 || projection.team.length > 3 || !roster) return;
  const selectedIds = projection.team.map((card) => card.id);
  const edges = projection.bonds.filter((bond) => bond.memberIds.every((id) => selectedIds.includes(id)))
    .map((bond) => ({ id: bond.bondEventId, members: bond.memberIds, sourceEventId: bond.sourceEventId }));
  if (!edges.length) return;
  try {
    relayBattle = createRelayBattle(crypto.randomUUID(), {
      formation: { id: "one", label: "Your QiMon", bondRole: projection.team[0].role,
        roster: projection.team.map((card) => ({ ...card })) },
      eligibility: { source: "owned", originDigest: journeyOriginSha256(journey),
        rosterRevision: projection.revision, selectedMemberIds: selectedIds, pairEdges: edges },
    }, {
      formation: { id: "two", label: "Practice partner", bondRole: "guardian",
        roster: [{ id: "two-practice-1", name: "Guardian echo", role: "guardian" }] },
      eligibility: { source: "practice", originDigest: null, rosterRevision: null,
        selectedMemberIds: ["two-practice-1"], pairEdges: [] },
    });
    relayBattleMessage = "Relay practice started. The partner follows a public Pulse/Guard rhythm; choose each of your moves.";
  } catch (error) {
    relayBattleMessage = error instanceof Error ? error.message : "Relay practice could not start.";
  }
  renderQiMonRoster();
}

function playOwnedRelay(action: Parameters<typeof createRelayCommand>[2], target?: string): void {
  if (!relayBattle || relayBattle.status !== "active") return;
  try {
    const first = createRelayCommand(relayBattle, "one", action, target);
    const partnerAction = relayBattle.round % 3 === 0 ? "guard" : "pulse";
    const second = createRelayCommand(relayBattle, "two", partnerAction);
    const result = resolveRelayRound(relayBattle, first, second);
    if (!result.accepted) relayBattleMessage = result.reason;
    else {
      relayBattle = result.state;
      const effect = result.event.outcomes[0];
      relayBattleMessage = action === "relay"
        ? `Relay spent one Spark and passed ${effect.chargeGranted} temporary Charge. The incoming QiMon took the simultaneous opposing move.`
        : `${action[0].toUpperCase()}${action.slice(1)} resolved. ${effect.damageDealt} damage dealt, ${effect.damageTaken} taken${effect.chargeConsumed ? `, ${effect.chargeConsumed} Charge used` : ""}.`;
      if (result.state.status === "complete") {
        relayBattleMessage += ` Practice complete: ${result.state.winner === "one" ? "your team prevailed" : result.state.winner === "two" ? "the practice partner prevailed" : "draw"}. No Journey reward is kept from this v2 match.`;
      }
    }
  } catch (error) {
    relayBattleMessage = error instanceof Error ? error.message : "That Relay move was unavailable.";
  }
  renderQiMonRoster();
}

function renderQiMonRoster(): void {
  for (const node of [ui.rosterOffers, ui.rosterMembers, ui.rosterTeamControls, ui.rosterTraining, ui.rosterRelay]) {
    node.replaceChildren();
  }
  const projection = currentQiMonRoster();
  ui.rosterStatus.textContent = rosterIssue ?? rosterStatusMessage;
  ui.rosterStatus.classList.toggle("is-error", !!rosterIssue);
  if (!roster || !projection || rosterIssue) {
    ui.rosterOffers.append(rosterCard("Roster paused", "The saved roster remains untouched. Download it before reviewing a new Journey or roster source."));
    ui.rosterTeamControls.append(rosterAction("Download saved bytes", downloadQiMonRoster, !rosterStorageBaseline));
    ui.rosterTeamControls.append(rosterAction("Archive old roster and start fresh", () => void startNewQiMonRoster(),
      !storageWriteAvailable || !navigator.locks || !rosterStorageBaseline));
    appendArchivedRosterCopies();
    return;
  }
  const found = new Set(roster.events.flatMap((event) => event.action.kind === "discover"
    ? [event.action.sourceEventId] : []));
  const plays = journey.events.slice(roster.baseEventCount)
    .filter((event) => event.kind === "play-commit" && event.choice !== "hold" && !found.has(event.eventId));
  for (const offer of projection.offers) {
    ui.rosterOffers.append(rosterCard(offer.card.name, `Invitation from kept trace ${offer.sourceEventId.slice(0, 24)}…`, {
      label: "Invite",
      run: () => void commitQiMonRoster((current, r, j) => inviteQiMon(journey, current, offer.id, r, j),
        `${offer.card.name} joined your local roster.`),
    }, offer.card.role));
  }
  for (const event of plays.slice(-4).reverse()) {
    if (event.kind !== "play-commit") continue;
    ui.rosterOffers.append(rosterCard(event.fieldName, `Kept Field trace · ${event.committedAt.slice(0, 10)} · ${event.choice}`, {
      label: "Find",
      run: () => void commitQiMonRoster((current, r, j) => discoverQiMon(journey, current, event.eventId, r, j),
        "A source-bound QiMon invitation is ready for your review."),
    }));
  }
  if (!projection.offers.length && !plays.length) {
    ui.rosterOffers.append(rosterCard("Your next discovery is ahead", "Explore a Field, choose an expression and Keep the trace. Then return to invite a QiMon."));
  }

  const memberIds = new Set(projection.members.map((member) => member.id));
  rosterTeamDraft = rosterTeamDraft.filter((id) => memberIds.has(id));
  if (!rosterTeamDraft.length && projection.team.length) rosterTeamDraft = projection.team.map((card) => card.id);
  for (const member of projection.members) {
    const card = rosterCard(member.card.name,
      `Training tier ${member.trainingTier}/3 · invited from ${member.sourceEventId.slice(0, 24)}…`, {
        label: "Train solo", run: () => startOwnedPractice([member.card]),
      }, member.card.role);
    const checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    checkbox.checked = rosterTeamDraft.includes(member.id);
    checkbox.setAttribute("aria-label", `Select ${member.card.name} for your team`);
    checkbox.addEventListener("change", () => {
      if (checkbox.checked && rosterTeamDraft.length < 3) rosterTeamDraft.push(member.id);
      else if (!checkbox.checked) rosterTeamDraft = rosterTeamDraft.filter((id) => id !== member.id);
      else checkbox.checked = false;
      renderQiMonRoster();
    });
    card.prepend(checkbox);
    ui.rosterMembers.append(card);
  }
  if (!projection.members.length) ui.rosterMembers.append(rosterCard("No QiMon invited yet", "Find a kept Field trace above and explicitly invite its QiMon."));

  const chosen = rosterTeamDraft.map((id) => projection.members.find((member) => member.id === id)!.card);
  const changedTeam = JSON.stringify(chosen.map((card) => card.id)) !== JSON.stringify(projection.team.map((card) => card.id));
  ui.rosterTeamControls.append(rosterAction("Keep formation", () => {
    void commitQiMonRoster((current, r, j) => selectQiMonTeam(journey, current, chosen.map((card) => card.id), r, j),
      "Your formation was kept in the local QiMon roster.");
  }, !chosen.length || !changedTeam));
  ui.rosterTeamControls.append(rosterAction("Practice selected", () => startOwnedPractice(chosen), !chosen.length));
  ui.rosterTeamControls.append(rosterAction("Download roster copy", downloadQiMonRoster));
  appendArchivedRosterCopies();

  const credited = new Set(roster.events.flatMap((record) =>
    record.action.kind === "train" || record.action.kind === "bond" ? [record.action.sourceEventId] : []));
  let candidates = 0;
  for (const event of journey.events.slice(roster.baseEventCount)) {
    if (event.kind !== "practice-complete" || credited.has(event.eventId)) continue;
    const cards = event.replay.teams[0].roster;
    const recruited = cards.map((card) => projection.members.find((member) => member.id === card.id &&
      member.card.name === card.name && member.card.role === card.role));
    if (recruited.some((member) => !member)) continue;
    const members = recruited as typeof projection.members[number][];
    const invitedBeforePractice = members.every((member) => {
      const invitation = roster!.events.find((record) => record.eventId === member.invitationEventId);
      return invitation && event.sequence > invitation.journeyEventCount;
    });
    if (!invitedBeforePractice) continue;
    if (cards.length === 1 && members[0].trainingTier < 3) {
      candidates += 1;
      ui.rosterTraining.append(rosterCard(`${members[0].card.name} · solo practice`,
        `Kept battle ${event.replay.battleId.slice(0, 13)}… · exact replay available`, {
          label: "Keep training",
          run: () => void commitQiMonRoster((current, r, j) => trainQiMon(journey, current, members[0].id, event.eventId, r, j),
            `${members[0].card.name} earned one training tier.`),
        }));
    } else if (cards.length === 2 && !projection.bonds.some((bond) =>
      bond.memberIds.includes(members[0].id) && bond.memberIds.includes(members[1].id))) {
      const actors = new Set(event.replay.commands.map((round) => round[0].activeQiMonId));
      candidates += 1;
      ui.rosterTraining.append(rosterCard(`${members[0].card.name} + ${members[1].card.name}`,
        actors.has(members[0].id) && actors.has(members[1].id)
          ? "Both acted in a kept two-member practice. Review and keep their pair bond."
          : "Both QiMon need to act; try a Swap and move with each member in another practice.",
        actors.has(members[0].id) && actors.has(members[1].id) ? {
          label: "Keep pair bond",
          run: () => void commitQiMonRoster((current, r, j) => bondQiMonPair(journey, current,
            members[0].id, members[1].id, event.eventId, r, j), "An earned pair bond was kept."),
        } : undefined));
    }
  }
  if (!candidates) ui.rosterTraining.append(rosterCard("Practice creates the next node", "Keep a solo match to train one recruit, or keep a two-member match where both acted to form a pair."));
  renderQiMonRelay(projection);
}

function renderQiMonRelay(projection: QiMonRosterProjection): void {
  if (relayBattle) {
    const one = relayBattle.teams[0], two = relayBattle.teams[1];
    const active = one.roster.find((member) => member.id === one.activeQiMonId);
    const opposing = two.roster.find((member) => member.id === two.activeQiMonId);
    ui.rosterRelay.append(rosterCard(`Round ${relayBattle.round} · ${active?.name ?? "QiMon"}`,
      `Your Integrity ${active?.integrity ?? 0} · Spark ${one.spark} · Charge ${active?.charge ?? 0} | Partner Integrity ${opposing?.integrity ?? 0}`));
    const message = document.createElement("p");
    message.className = "qimon-relay-readout";
    message.textContent = relayBattleMessage;
    ui.rosterRelay.append(message);
    const actions = document.createElement("div");
    actions.className = "qimon-relay-actions";
    if (relayBattle.status === "active") {
      for (const action of ["pulse", "guard", "signature"] as const) {
        actions.append(rosterAction(action[0].toUpperCase() + action.slice(1), () => playOwnedRelay(action)));
      }
      for (const target of one.roster.filter((member) => member.id !== one.activeQiMonId && member.integrity > 0)) {
        actions.append(rosterAction(`Swap → ${target.name}`, () => playOwnedRelay("swap", target.id)));
      }
      for (const target of availableRelayTargets(relayBattle, "one")) {
        const name = one.roster.find((member) => member.id === target.targetQiMonId)?.name ?? "QiMon";
        actions.append(rosterAction(`Relay → ${name}`, () => playOwnedRelay("relay", target.targetQiMonId)));
      }
      actions.append(rosterAction("End practice", () => playOwnedRelay("surrender")));
    } else actions.append(rosterAction("Close result", () => { relayBattle = null; renderQiMonRoster(); }));
    ui.rosterRelay.append(actions);
    return;
  }
  const selectedIds = projection.team.map((card) => card.id);
  const paired = projection.bonds.some((bond) => bond.memberIds.every((id) => selectedIds.includes(id)));
  ui.rosterRelay.append(rosterCard(paired ? "An earned pair is ready" : "Build an earned pair",
    paired ? "Relay transfers temporary Charge and spends one shared Spark. This v2 practice is session only."
      : "Keep a two-member match in which both QiMon act, then keep the pair bond and formation."));
  ui.rosterRelay.append(rosterAction("Start Relay practice", () => startOwnedRelay(projection), !paired));
}

function archivedRosterKeys(): string[] {
  try {
    return Array.from({ length: window.localStorage.length }, (_, index) => window.localStorage.key(index))
      .filter((key): key is string => Boolean(key?.startsWith(ROSTER_BACKUP_PREFIX)))
      .sort();
  } catch { return []; }
}

function appendArchivedRosterCopies(): void {
  for (const key of archivedRosterKeys()) {
    ui.rosterTeamControls.append(rosterAction(`Download archived copy ${key.slice(-8)}`, () => {
      try {
        const saved = window.localStorage.getItem(key);
        if (!saved) throw new Error("This archived copy is unavailable.");
        downloadRawQiMonRoster(saved, `archi-qimon-archived-${key.slice(-12)}.json`);
      } catch (error) {
        rosterStatusMessage = error instanceof Error ? error.message : "The archived copy could not be read.";
      }
      renderQiMonRoster();
    }));
  }
}

async function startNewQiMonRoster(): Promise<void> {
  if (!rosterIssue || !rosterStorageBaseline || commitInFlight || journeyInputInterlocked ||
      !storageWriteAvailable || !navigator.locks) return;
  const baseline = rosterStorageBaseline;
  const expectedJourneyRevision = revisionForJourney(journey);
  commitInFlight = true;
  try {
    await navigator.locks.request(JOURNEY_LOCK_NAME, () => navigator.locks.request(ROSTER_LOCK_NAME, () => {
      const saved = readStoredJourney();
      if (saved?.status !== "valid" || revisionForJourney(saved.journey) !== expectedJourneyRevision ||
          window.localStorage.getItem(ROSTER_STORAGE_KEY) !== baseline) {
        throw new Error("The saved Journey or roster changed. Nothing was replaced.");
      }
      const backupKey = `${ROSTER_BACKUP_PREFIX}${sha256String(baseline)}`;
      const previousBackup = window.localStorage.getItem(backupKey);
      if (previousBackup !== null && previousBackup !== baseline) {
        throw new Error("The archived roster key contains different data. Nothing was replaced.");
      }
      if (previousBackup === null) window.localStorage.setItem(backupKey, baseline);
      if (window.localStorage.getItem(backupKey) !== baseline) {
        throw new Error("The old roster could not be archived. Nothing was replaced.");
      }
      const fresh = createQiMonRoster(journey);
      const archive = serializeQiMonRoster(fresh, journey);
      try {
        window.localStorage.setItem(ROSTER_STORAGE_KEY, archive);
        if (window.localStorage.getItem(ROSTER_STORAGE_KEY) !== archive) throw new Error("New roster readback failed.");
      } catch (error) {
        try { window.localStorage.setItem(ROSTER_STORAGE_KEY, baseline); } catch { /* Report failure below. */ }
        throw error;
      }
      roster = fresh;
      rosterStorageBaseline = archive;
      rosterIssue = null;
      rosterProjectionIssue = false;
      rosterTeamDraft = [];
      rosterStatusMessage = "A new roster was saved for this Journey. The previous roster remains in a separate downloadable local archive.";
    }));
  } catch (error) {
    rosterStatusMessage = error instanceof Error ? error.message : "The new roster could not be saved.";
  } finally {
    commitInFlight = false;
    renderQiMonRoster();
  }
}

function downloadRawQiMonRoster(archive: string, filename: string): void {
  const url = URL.createObjectURL(new Blob([archive], { type: "application/json" }));
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60_000);
  rosterStatusMessage = "A separate QiMon roster copy was prepared. Your Journey archive remains separate.";
}

function downloadQiMonRoster(): void {
  try {
    const archive = rosterIssue ? rosterStorageBaseline : roster ? serializeQiMonRoster(roster, journey) : rosterStorageBaseline;
    if (!archive) throw new Error("No roster copy is available on this device.");
    downloadRawQiMonRoster(archive, `archi-qimon-roster-${new Date().toISOString().slice(0, 10)}.json`);
  } catch (error) {
    rosterStatusMessage = error instanceof Error ? error.message : "Roster copy was unavailable.";
  }
  renderQiMonRoster();
}

function cancelQiMonRosterImport(): void {
  pendingRosterImport = null;
  rosterImportGeneration += 1;
  ui.rosterImportPreview.hidden = true;
  ui.rosterFile.value = "";
}

async function reviewQiMonRosterFile(file: File): Promise<void> {
  cancelQiMonRosterImport();
  const generation = rosterImportGeneration;
  if (file.size > 256 * 1024) {
    rosterStatusMessage = "That roster copy exceeds the local size limit. Nothing changed.";
    renderQiMonRoster();
    return;
  }
  try {
    const contents = await file.text();
    if (generation !== rosterImportGeneration || ui.rosterPanel.hidden) return;
    const inspected = inspectQiMonRoster(contents, journey);
    if (inspected.status !== "valid") {
      rosterStatusMessage = `Roster file rejected: ${inspected.message} Nothing changed.`;
      renderQiMonRoster();
      return;
    }
    pendingRosterImport = { generation, candidate: inspected.roster,
      baseline: rosterStorageBaseline, journeyRevision: revisionForJourney(journey) };
    ui.rosterImportTitle.textContent = `${inspected.projection.members.length} invited QiMon · ${inspected.roster.events.length} roster events`;
    ui.rosterImportDetail.textContent = `Origin ${inspected.roster.originDigest.slice(0, 18)}… · created ${inspected.roster.createdAt.slice(0, 10)}. Current roster: ${roster?.events.length ?? "unavailable"} events. This replaces the entire QiMon roster if you choose it.`;
    ui.rosterImportPreview.hidden = false;
    ui.rosterImportCancel.focus();
    rosterStatusMessage = "Review the exact roster copy below before replacing anything.";
    renderQiMonRoster();
  } catch (error) {
    rosterStatusMessage = error instanceof Error ? error.message : "That roster copy could not be read.";
    renderQiMonRoster();
  }
}

async function confirmQiMonRosterImport(): Promise<void> {
  const pending = pendingRosterImport;
  if (!pending || commitInFlight || journeyInputInterlocked || ui.rosterImportPreview.hidden) return;
  commitInFlight = true;
  try {
    const replace = (): void => {
      if (pendingRosterImport !== pending || pending.generation !== rosterImportGeneration ||
          revisionForJourney(journey) !== pending.journeyRevision ||
          (!qaMode && window.localStorage.getItem(ROSTER_STORAGE_KEY) !== pending.baseline)) {
        throw new Error("The Journey or saved roster changed while you reviewed the file. Nothing was replaced.");
      }
      if (!qaMode) {
        const saved = readStoredJourney();
        if (!storageWriteAvailable || saved?.status !== "valid" ||
            revisionForJourney(saved.journey) !== pending.journeyRevision) {
          throw new Error("The saved Journey changed. This roster file was not installed.");
        }
      }
      const archive = serializeQiMonRoster(pending.candidate, journey);
      if (!qaMode) {
        try {
          window.localStorage.setItem(ROSTER_STORAGE_KEY, archive);
          if (window.localStorage.getItem(ROSTER_STORAGE_KEY) !== archive) throw new Error("Roster readback failed.");
        } catch (error) {
          try {
            if (pending.baseline === null) window.localStorage.removeItem(ROSTER_STORAGE_KEY);
            else window.localStorage.setItem(ROSTER_STORAGE_KEY, pending.baseline);
          } catch { /* Report the failed replacement without claiming recovery. */ }
          throw error;
        }
      }
      roster = pending.candidate;
      rosterStorageBaseline = qaMode ? pending.baseline : archive;
      rosterIssue = null;
      rosterProjectionIssue = false;
      rosterTeamDraft = [];
      rosterStatusMessage = "Reviewed QiMon roster replaced locally. The Journey and phone History were unchanged.";
      cancelQiMonRosterImport();
    };
    if (!qaMode && navigator.locks) {
      await navigator.locks.request(JOURNEY_LOCK_NAME, () => navigator.locks.request(ROSTER_LOCK_NAME, replace));
    }
    else if (qaMode) replace();
    else throw new Error("The roster write lock is unavailable. Nothing was replaced.");
  } catch (error) {
    rosterStatusMessage = error instanceof Error ? error.message : "Roster replacement failed. The current roster was kept.";
    cancelQiMonRosterImport();
  } finally {
    commitInFlight = false;
    renderQiMonRoster();
  }
}

function openQiMonRoster(): void {
  if (mode === "battle") leaveBattleLab();
  if (ui.continuity.classList.contains("is-open")) closeContinuity();
  rosterReturnFocus = document.activeElement instanceof HTMLElement ? document.activeElement : ui.rosterEntry;
  relayBattle = null;
  renderQiMonRoster();
  ui.rosterPanel.hidden = false;
  ui.rosterPanel.inert = false;
  ui.rosterPanel.setAttribute("aria-hidden", "false");
  for (const region of [canvas, ui.topbar, ui.presenceConsole, ui.experience, ui.battlePanel, ui.relayPanel, ui.fieldRail, ui.navigator]) {
    region.inert = true;
  }
  keys.clear();
  player.vx = 0;
  player.vy = 0;
  ui.rosterClose.focus();
}

function closeQiMonRoster(): void {
  if (ui.rosterPanel.hidden) return;
  relayBattle = null;
  cancelQiMonRosterImport();
  ui.rosterPanel.hidden = true;
  ui.rosterPanel.inert = true;
  ui.rosterPanel.setAttribute("aria-hidden", "true");
  for (const region of [canvas, ui.topbar, ui.experience, ui.fieldRail]) region.inert = false;
  ui.presenceConsole.inert = mode !== "habitat";
  ui.battlePanel.inert = mode !== "battle";
  ui.relayPanel.inert = mode !== "relay";
  ui.navigator.inert = mode !== "field";
  const returnFocus = rosterReturnFocus?.isConnected ? rosterReturnFocus : ui.rosterEntry;
  rosterReturnFocus = null;
  returnFocus.focus({ preventScroll: true });
}

function trapQiMonRosterFocus(event: KeyboardEvent): void {
  const focusable = [...ui.rosterPanel.querySelectorAll<HTMLElement>("button:not([disabled]), [href], input:not([disabled])")]
    .filter((node) => !node.hidden && node.getClientRects().length > 0);
  if (!focusable.length) return;
  if (event.shiftKey && document.activeElement === focusable[0]) {
    event.preventDefault();
    focusable[focusable.length - 1].focus();
  } else if (!event.shiftKey && document.activeElement === focusable[focusable.length - 1]) {
    event.preventDefault();
    focusable[0].focus();
  }
}

function continuityIsOpen(): boolean {
  return ui.continuity.classList.contains("is-open");
}

function trapContinuityFocus(event: KeyboardEvent): void {
  const focusable = [...ui.continuity.querySelectorAll<HTMLElement>("button:not([disabled]), [href], input:not([disabled]), [tabindex]:not([tabindex='-1'])")]
    .filter((node) => !node.hidden && node.getClientRects().length > 0);
  if (focusable.length === 0) return;
  const first = focusable[0];
  const last = focusable[focusable.length - 1];
  if (event.shiftKey && document.activeElement === first) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && document.activeElement === last) {
    event.preventDefault();
    first.focus();
  }
}

const CARE_RESPONSE: Record<CareActionId, string> = {
  greet: "ARCHi answers with a warm pulse. This connection stays in the present moment.",
  tend: "Tending restores energy and softens the rhythm. The Core Pearl remains unchanged.",
  rest: "ARCHi settles close by. Rest changes the rhythm, never the identity.",
  explore: "Curiosity has somewhere to go. ARCHi is ready to enter a field with you.",
};

async function performCareAction(action: CareActionId, enterField = false): Promise<void> {
  if (journeyInputInterlocked) {
    keys.clear();
    showToast("Reopen ARCHi to finish device setup · Journey unchanged");
    return;
  }
  const canExploreFromReflection = mode === "reflection" && action === "explore" && enterField;
  if (commitInFlight || (mode !== "habitat" && !canExploreFromReflection)) return;
  const interaction = desktopInteractions?.begin();
  if (desktopInteractions && !interaction) return;
  commitInFlight = true;
  const intent = createCareIntent(journey, action);
  let committed = false;
  let persisted = false;

  const commitUnderCurrentRevision = (): void => {
    if (interaction && !interaction.isCurrent()) return;
    let storedJourney: Journey | null = null;
    if (storageWriteAvailable) {
      const stored = readStoredJourney();
      if (stored.status !== "valid") {
        storageWriteAvailable = false;
        sessionOnlyAuthority = true;
        refreshCareProjection("The saved journey became unavailable. This care choice was not kept.");
        updateContinuity();
        updateHeader();
        showToast("Saved journey unavailable · care choice released");
        return;
      }
      storedJourney = stored.journey;
    }
    if (storedJourney && revisionForJourney(storedJourney) !== intent.baseRevision) {
      journey = storedJourney;
      session = null;
      setMode("habitat");
      refreshCareProjection("This journey changed in another tab. Review the current rhythm and choose again.");
      updateContinuity();
      updateHeader();
      showToast("Journey changed in another tab · stale care choice released");
      return;
    }
    if (storedJourney) journey = storedJourney;
    try {
      journey = commitCareAction(
        journey,
        intent,
        qaMode ? journey.updatedAt : new Date().toISOString(),
      );
    } catch (error) {
      showToast(error instanceof Error ? error.message : "This care choice could not be kept");
      return;
    }
    persisted = saveJourney();
    careProjection = projectCare(journey.care, journey.care.updatedAt);
    updateCareInterface(
      persisted || qaMode
        ? CARE_RESPONSE[action]
        : `${CARE_RESPONSE[action]} Local save is unavailable, so this care remains in this session.`,
    );
    petPulse = 1;
    morphFlash = reducedMotion ? 0.2 : 0.55;
    const companion = currentCompanionPosition();
    const color =
      action === "greet"
        ? AURAS.relationship.color
        : action === "tend"
          ? AURAS.repair.color
          : action === "rest"
            ? AURAS.memory.color
            : AURAS.opportunity.color;
    spawnBurst(companion.x, companion.y - 22, color, 13, 0.55);
    tone(action === "rest" ? 294 : action === "explore" ? 523.25 : 440, 0.18, 0.022);
    showToast(
      persisted
        ? `${CARE_ACTIONS[action].label} kept locally · core unchanged`
        : qaMode
          ? `${CARE_ACTIONS[action].label} kept for this test session`
          : `${CARE_ACTIONS[action].label} kept for this session · local save unavailable`,
    );
    committed = true;
  };

  try {
    if (!qaMode && navigator.locks) {
      if (interaction) await navigator.locks.request(JOURNEY_LOCK_NAME, { signal: interaction.signal }, commitUnderCurrentRevision);
      else await navigator.locks.request(JOURNEY_LOCK_NAME, commitUnderCurrentRevision);
    } else {
      commitUnderCurrentRevision();
    }
  } catch (error) {
    if (!interaction?.signal.aborted) throw error;
  } finally {
    interaction?.finish();
    commitInFlight = false;
  }

  if (committed && enterField && (!interaction || interaction.isCurrent())) beginPlay();
}

function beginPlay(): void {
  session = createPlaySession(journey);
  collectedSparks = new Set();
  particles = [];
  fieldComposure = 100;
  proposalCountdown = 0;
  transition = reducedMotion ? 0 : 1;
  player.x = width * 0.5;
  player.y = height * 0.55;
  player.vx = 0;
  player.vy = 0;
  target.x = player.x;
  target.y = player.y;
  setMode("field");
  updateFieldInterface();
  showToast(`${session.fieldName} opened · choose what to notice`);
  tone(392, 0.24, 0.025);
}

function abandonToHabitat(): void {
  if (mode === "field" && (session?.collected.length ?? 0) > 0) {
    showToast("Uncommitted signals released · the journey did not change");
  }
  session = null;
  proposalCountdown = 0;
  transition = reducedMotion ? 0 : 0.7;
  setMode("habitat");
  refreshCareProjection();
  updateFieldInterface();
}

function collectedAuras(): AuraId[] {
  if (!session) return [];
  return session.collected
    .map((id) => session!.echoes.find((echo) => echo.id === id)?.aura)
    .filter((aura): aura is AuraId => Boolean(aura));
}

function showProposal(): void {
  if (!session || session.proposals.length < 2) return;
  setMode("proposal");
  const labels = collectedAuras().map((aura) => AURAS[aura].label.toLowerCase());
  ui.proposalSummary.textContent = `ARCHi noticed ${labels.join(", ")}. A chosen expression gains +3 affinity; other encountered roles may gain +1. Bond gains +4 and the trace is kept locally.`;
  ui.proposalChoices.replaceChildren();

  for (const [index, roleId] of session.proposals.entries()) {
    const role = ROLES[roleId];
    const button = document.createElement("button");
    button.type = "button";
    button.className = "proposal-choice";
    button.style.setProperty("--role-color", role.hue);
    button.style.setProperty("--role-rgb", role.rgb.join(", "));
    button.disabled = journeyInputInterlocked;
    button.innerHTML = `
      <span class="proposal-choice__glyph" aria-hidden="true">${role.glyph}</span>
      <strong>${index + 1} · ${role.title}</strong>
      <small>${role.purpose} ${role.promise} Keep ${role.form}: +3 ${role.shortTitle} affinity, +4 bond.</small>
    `;
    button.addEventListener("click", () => keepChoice(roleId));
    ui.proposalChoices.append(button);
  }
  ui.hold.textContent = `Hold the current shape · +1 Guardian · +2 bond`;
  ui.proposalChoices.querySelector<HTMLButtonElement>("button")?.focus();
}

function renderReflection(choice: RoleId | "hold", persisted: boolean): void {
  if (!session) return;
  ui.reflectionEyebrow.textContent = persisted
    ? "Kept locally · play complete"
    : qaMode
      ? "Kept for this test session · play complete"
      : "Kept for this session · local save unavailable";
  const auras = collectedAuras();
  ui.reflectionTrace.replaceChildren();
  for (const aura of auras) {
    const chip = document.createElement("span");
    chip.className = "trace-chip";
    chip.style.setProperty("--chip-color", AURAS[aura].color);
    chip.textContent = AURAS[aura].label;
    ui.reflectionTrace.append(chip);
  }

  if (choice === "hold") {
    ui.reflectionTitle.textContent = "ARCHi held its shape.";
    ui.reflectionCopy.textContent =
      "The signals remain an attributable play trace, while the current expression stays unchanged. The pause strengthened Guardian affinity.";
  } else {
    const role = ROLES[choice];
    ui.reflectionTitle.textContent = `${role.form} light joined ARCHi.`;
    ui.reflectionCopy.textContent = `${role.title} is now the active expression. This branch can deepen in later fields; the Core Pearl did not change.`;
  }
}

async function keepChoice(choice: RoleId | "hold"): Promise<void> {
  if (journeyInputInterlocked) {
    keys.clear();
    showToast("Reopen ARCHi to finish device setup · Journey unchanged");
    return;
  }
  if (!session || commitInFlight) return;
  const interaction = desktopInteractions?.begin();
  if (desktopInteractions && !interaction) return;
  const proposedSession = session;
  commitInFlight = true;

  const commitUnderCurrentRevision = (): void => {
    if (interaction && (!interaction.isCurrent() || session !== proposedSession)) return;
    if (!session) return;
    let storedJourney: Journey | null = null;
    if (storageWriteAvailable) {
      const stored = readStoredJourney();
      if (stored.status !== "valid") {
        storageWriteAvailable = false;
        sessionOnlyAuthority = true;
        session = null;
        setMode("habitat");
        refreshCareProjection("The saved journey became unavailable. This field proposal was not kept.");
        updateContinuity();
        updateFieldInterface();
        showToast("Saved journey unavailable · field proposal released");
        ui.begin.focus({ preventScroll: true });
        return;
      }
      storedJourney = stored.journey;
    }
    if (storedJourney && revisionForJourney(storedJourney) !== session.baseRevision) {
      journey = storedJourney;
      session = null;
      setMode("habitat");
      refreshCareProjection("This journey changed in another tab. The current care rhythm is shown.");
      updateContinuity();
      updateFieldInterface();
      showToast("Journey changed in another tab · stale proposal released");
      ui.begin.focus({ preventScroll: true });
      return;
    }
    const previousStage = stageForJourney(journey).name;
    try {
      journey = commitSession(journey, session, choice);
    } catch (error) {
      showToast(error instanceof Error ? error.message : "This proposal could not be kept");
      return;
    }
    const nextStage = stageForJourney(journey).name;
    const grew = previousStage !== nextStage;
    const persisted = saveJourney();
    morphFlash = reducedMotion ? 0.25 : 1;
    transition = 0;
    if (grew) {
      const companion = currentCompanionPosition();
      spawnBurst(companion.x, companion.y + 18, rgba(ROLES[journey.expression].rgb, 0.86), 12, 0.72);
    }
    tone(choice === "hold" ? 294 : 523.25, 0.34, 0.035);
    renderReflection(choice, persisted);
    setMode("reflection");
    updateContinuity();
    updateFieldInterface();
    const ordinaryCommitMessage = persisted
      ? choice === "hold"
        ? "Current expression held · play trace kept locally"
        : `${ROLES[choice].shortTitle} expression kept locally · core unchanged`
      : qaMode
        ? "Test-session trace kept · core unchanged"
        : "Local save unavailable · change remains in this session only";
    const growthPersistence = persisted
      ? "and was kept locally"
      : qaMode
        ? "for this test session"
        : "for this session only; local save is unavailable";
    showToast(
      grew
        ? `ARCHi grew into ${nextStage} ${growthPersistence}. Core identity and permissions are unchanged.`
        : ordinaryCommitMessage,
    );
    ui.again.focus({ preventScroll: true });
  };

  try {
    if (!qaMode && navigator.locks) {
      if (interaction) await navigator.locks.request(JOURNEY_LOCK_NAME, { signal: interaction.signal }, commitUnderCurrentRevision);
      else await navigator.locks.request(JOURNEY_LOCK_NAME, commitUnderCurrentRevision);
    } else {
      commitUnderCurrentRevision();
    }
  } catch (error) {
    if (!interaction?.signal.aborted) throw error;
  } finally {
    interaction?.finish();
    commitInFlight = false;
  }
}

function playAgain(): void {
  void performCareAction("explore", true);
}

function spawnBurst(x: number, y: number, color: string, count = 18, energy = 1): void {
  if (reducedMotion) return;
  const random = seededRandom(hashString(`${x}:${y}:${elapsed}:${particles.length}`));
  for (let index = 0; index < count; index += 1) {
    const angle = random() * Math.PI * 2;
    const speed = (28 + random() * 72) * energy;
    const maxLife = 0.5 + random() * 0.8;
    particles.push({
      x,
      y,
      vx: Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed,
      life: maxLife,
      maxLife,
      size: 0.8 + random() * 2.5,
      color,
    });
  }
}

function echoPosition(echo: FieldEcho): Point {
  const time = animationTime();
  let x = echo.x * width + Math.sin(time * 0.73 + echo.phase) * 8;
  let y = echo.y * height + Math.cos(time * 0.61 + echo.phase) * 7;
  x = clamp(x, 54, width - 54);
  y = clamp(y, 104, height - 96);
  if (width <= 800) {
    y = Math.min(y, height * 0.61);
  } else if (x < Math.min(540, width * 0.48) && y > height * 0.59) {
    x = Math.max(x, width * 0.58);
  }
  return { x, y };
}

function staticPosition(zone: StaticZone): Point {
  const time = animationTime();
  const x = clamp(zone.x * width + Math.sin(time * 0.31 + zone.phase) * 10, 48, width - 48);
  let y = clamp(zone.y * height + Math.cos(time * 0.28 + zone.phase) * 8, 98, height - 90);
  if (width <= 800) y = Math.min(y, height * 0.62);
  return { x, y };
}

function updateField(delta: number): void {
  if (!session) return;
  let inputX = 0;
  let inputY = 0;
  if (keys.has("arrowleft") || keys.has("a")) inputX -= 1;
  if (keys.has("arrowright") || keys.has("d")) inputX += 1;
  if (keys.has("arrowup") || keys.has("w")) inputY -= 1;
  if (keys.has("arrowdown") || keys.has("s")) inputY += 1;

  const keyboardActive = inputX !== 0 || inputY !== 0;
  if (keyboardActive) {
    const length = Math.hypot(inputX, inputY) || 1;
    inputX /= length;
    inputY /= length;
    target.x = player.x;
    target.y = player.y;
  } else {
    const dx = target.x - player.x;
    const dy = target.y - player.y;
    const distance = Math.hypot(dx, dy);
    if (distance > 9) {
      inputX = dx / distance;
      inputY = dy / distance;
    }
  }

  const speed = clamp(Math.min(width, height) * 0.34, 190, 280);
  const desiredX = inputX * speed;
  const desiredY = inputY * speed;
  const easing = 1 - Math.exp(-delta * 9);
  player.vx += (desiredX - player.vx) * easing;
  player.vy += (desiredY - player.vy) * easing;
  if (inputX === 0 && inputY === 0) {
    player.vx *= Math.exp(-delta * 6);
    player.vy *= Math.exp(-delta * 6);
  }
  player.x += player.vx * delta;
  player.y += player.vy * delta;

  const margin = clamp(Math.min(width, height) * 0.075, 42, 72);
  player.x = clamp(player.x, margin, width - margin);
  player.y = clamp(player.y, Math.max(88, margin), height - Math.max(74, margin));

  if (!reducedMotion && Math.hypot(player.vx, player.vy) > 42 && Math.floor(elapsed * 18) % 4 === 0) {
    particles.push({
      x: player.x - player.vx * 0.025,
      y: player.y - player.vy * 0.025 + 16,
      vx: -player.vx * 0.08,
      vy: -player.vy * 0.08,
      life: 0.42,
      maxLife: 0.42,
      size: 1.4,
      color: ROLES[journey.expression].hue,
    });
  }

  if (session.collected.length < 3) {
    for (const echo of session.echoes) {
      if (session.collected.includes(echo.id)) continue;
      const point = echoPosition(echo);
      if (Math.hypot(player.x - point.x, player.y - point.y) < clamp(Math.min(width, height) * 0.075, 43, 60)) {
        session = collectEcho(session, echo.id);
        spawnBurst(point.x, point.y, AURAS[echo.aura].color, 26, 1.2);
        showToast(`${AURAS[echo.aura].label} noticed · no change committed`);
        tone(330 + session.collected.length * 90, 0.18, 0.025);
        updateFieldInterface();
        updateFieldNavigator(`${AURAS[echo.aura].label} found. ${session.collected.length} of 3 signals found.`);
        if (session.collected.length === 3) proposalCountdown = reducedMotion ? 0.05 : 0.85;
      }
    }
  }

  for (const spark of session.sparks) {
    if (collectedSparks.has(spark.id)) continue;
    const x = spark.x * width;
    const y = spark.y * height;
    if (Math.hypot(player.x - x, player.y - y) < 24) {
      collectedSparks.add(spark.id);
      fieldComposure = Math.min(100, fieldComposure + 2);
      spawnBurst(x, y, "#c8fff4", 5, 0.4);
    }
  }

  for (const zone of session.staticZones) {
    const point = staticPosition(zone);
    const radius = zone.radius * Math.min(width, height);
    if (Math.hypot(player.x - point.x, player.y - point.y) < radius + 28 && elapsed - lastStaticHit > 1.05) {
      lastStaticHit = elapsed;
      fieldComposure = Math.max(18, fieldComposure - 12);
      player.vx *= -0.75;
      player.vy *= -0.75;
      target.x = player.x;
      target.y = player.y;
      spawnBurst(player.x, player.y, "#ef765f", 16, 0.8);
      showToast("Static unsettled ARCHi · pause and reorient");
      tone(164, 0.22, 0.025);
    }
  }
  fieldComposure = Math.min(100, fieldComposure + delta * 1.6);

  if (proposalCountdown > 0) {
    proposalCountdown -= delta;
    if (proposalCountdown <= 0) showProposal();
  }
  updateComposureInterface();
}

function update(delta: number): void {
  elapsed += delta;
  transition = Math.max(0, transition - delta * 1.35);
  morphFlash = Math.max(0, morphFlash - delta * 0.72);
  petPulse = Math.max(0, petPulse - delta * 1.7);
  const previousPresenceSequence = presenceSequence;
  presenceSequence = advancePresenceSequence(presenceSequence, delta);
  if (presenceSequence !== previousPresenceSequence) updatePresentationInterface();
  presentationPulse = Math.max(0, presentationPulse - delta * 0.85);
  battleImpactPulse = Math.max(0, battleImpactPulse - delta * 1.25);
  if (toastTimer > 0) {
    toastTimer -= delta;
    if (toastTimer <= 0) ui.toast.classList.remove("is-visible");
  }

  if (mode === "field" && !continuityIsOpen()) updateField(delta);

  for (const particle of particles) {
    particle.life -= delta;
    particle.x += particle.vx * delta;
    particle.y += particle.vy * delta;
    particle.vx *= Math.exp(-delta * 1.7);
    particle.vy *= Math.exp(-delta * 1.7);
  }
  particles = particles.filter((particle) => particle.life > 0).slice(-420);
}

// These drawing helpers borrow existing positions; they own no play state.
// The iPhone's bundled portrait has a distinct Qi atmosphere; the Mac and
// browser retain their authored palette and companion appearance.
function isIOSFieldArt(): boolean {
  return desktopAppearanceID?.startsWith("ios-portrait:") ?? false;
}

function pearlAccent(rgb: readonly number[], alpha: number): string {
  return `rgba(${Math.round(rgb[0] * 0.42 + 54 * 0.58)},${Math.round(rgb[1] * 0.42 + 35 * 0.58)},${Math.round(rgb[2] * 0.42 + 79 * 0.58)},${alpha})`;
}

function drawPearlLandscape(arena: boolean): void {
  if (isIOSFieldArt()) {
    const sky = context.createLinearGradient(0, 0, width * 0.3, height);
    sky.addColorStop(0, "#071619");
    sky.addColorStop(0.58, arena ? "#10363b" : "#0e3035");
    sky.addColorStop(1, "#081c21");
    context.fillStyle = sky;
    context.fillRect(0, 0, width, height);

    const light = context.createRadialGradient(width * 0.68, height * 0.19, 0,
      width * 0.68, height * 0.19, width * 0.76);
    light.addColorStop(0, "rgba(230,173,80,0.19)");
    light.addColorStop(0.38, "rgba(78,190,198,0.08)");
    light.addColorStop(1, "transparent");
    context.fillStyle = light;
    context.fillRect(0, 0, width, height);

    for (let layer = 0; layer < 3; layer += 1) {
      const ridgeY = height * (0.48 + layer * 0.12);
      context.fillStyle = ["rgba(48,115,123,0.13)", "rgba(16,68,76,0.34)",
        "rgba(4,35,43,0.5)"][layer];
      context.beginPath();
      context.moveTo(0, ridgeY + height * 0.07);
      context.bezierCurveTo(width * 0.14, ridgeY - height * 0.12, width * 0.22,
        ridgeY + height * 0.06, width * 0.4, ridgeY);
      context.bezierCurveTo(width * 0.62, ridgeY - height * 0.17, width * 0.75,
        ridgeY + height * 0.06, width, ridgeY - height * 0.04);
      context.lineTo(width, height); context.lineTo(0, height); context.closePath();
      context.fill();
    }
    for (const [index, star] of stars.entries()) {
      if (index % 3 !== 0) continue;
      const alpha = 0.13 + (Math.sin(animationTime() * 0.3 + star.phase) + 1) * 0.06;
      context.fillStyle = star.warmth > 0.7 ? `rgba(229,177,91,${alpha})` : `rgba(130,216,220,${alpha})`;
      context.beginPath();
      context.arc(star.x * width, star.y * height, star.size * 0.72, 0, Math.PI * 2);
      context.fill();
    }
    return;
  }
  const sky = context.createLinearGradient(0, 0, width * 0.25, height);
  sky.addColorStop(0, "#fffbf3");
  sky.addColorStop(0.42, "#f1eaf5");
  sky.addColorStop(1, arena ? "#c7bddc" : "#ded5e9");
  context.fillStyle = sky;
  context.fillRect(0, 0, width, height);

  const daylight = context.createRadialGradient(width * 0.72, height * 0.22, 0, width * 0.72, height * 0.22, width * 0.58);
  daylight.addColorStop(0, "rgba(255,252,233,0.94)");
  daylight.addColorStop(0.34, "rgba(255,247,231,0.35)");
  daylight.addColorStop(1, "rgba(255,247,231,0)");
  context.fillStyle = daylight;
  context.fillRect(0, 0, width, height);

  // Broad, quiet silhouettes establish depth without competing with controls.
  for (let layer = 0; layer < 3; layer += 1) {
    const ridgeY = height * (0.47 + layer * 0.13);
    context.fillStyle = ["rgba(178,163,204,0.17)", "rgba(173,157,197,0.18)", "rgba(151,139,182,0.12)"][layer];
    context.beginPath();
    context.moveTo(0, ridgeY + height * 0.07);
    context.bezierCurveTo(width * 0.14, ridgeY - height * 0.12, width * 0.22, ridgeY + height * 0.06, width * 0.4, ridgeY);
    context.bezierCurveTo(width * 0.62, ridgeY - height * 0.17, width * 0.75, ridgeY + height * 0.06, width, ridgeY - height * 0.04);
    context.lineTo(width, height); context.lineTo(0, height); context.closePath();
    context.fill();
  }

  context.save();
  const time = animationTime();
  for (const [index, star] of stars.entries()) {
    if (index % 3 !== 0) continue;
    const alpha = 0.15 + (Math.sin(time * 0.3 + star.phase) + 1) * 0.08;
    context.fillStyle = star.warmth > 0.7 ? `rgba(177,135,100,${alpha})` : `rgba(115,93,153,${alpha})`;
    context.beginPath();
    context.arc(star.x * width, star.y * height, star.size * 0.72, 0, Math.PI * 2);
    context.fill();
  }
  context.restore();
}

function drawPearlIsland(x: number, y: number, radiusX: number, radiusY: number, accent: string, planted = false): void {
  const qi = isIOSFieldArt();
  context.save();
  context.translate(x, y);
  const shadow = context.createRadialGradient(0, radiusY * 1.3, 0, 0, radiusY * 1.3, radiusX * 1.2);
  shadow.addColorStop(0, qi ? "rgba(1,11,16,0.48)" : "rgba(80,62,119,0.20)");
  shadow.addColorStop(1, qi ? "rgba(1,11,16,0)" : "rgba(80,62,119,0)");
  context.save(); context.scale(1, 0.38);
  context.fillStyle = shadow;
  context.beginPath(); context.arc(0, radiusY * 2.8, radiusX * 1.2, 0, Math.PI * 2); context.fill();
  context.restore();

  const depth = context.createLinearGradient(0, -radiusY * 0.2, 0, radiusY * 2.2);
  depth.addColorStop(0, qi ? "#28585f" : "#c5b9d9");
  depth.addColorStop(0.48, qi ? "#164149" : "#ac9bc7");
  depth.addColorStop(1, qi ? "#09282f" : "#8977a8");
  context.fillStyle = depth;
  context.beginPath();
  context.moveTo(-radiusX, 0);
  context.bezierCurveTo(-radiusX * 0.92, radiusY * 1.8, -radiusX * 0.48, radiusY * 2, 0, radiusY * 1.9);
  context.bezierCurveTo(radiusX * 0.62, radiusY * 2.1, radiusX * 0.96, radiusY * 1.3, radiusX, 0);
  context.closePath(); context.fill();

  const surface = context.createLinearGradient(-radiusX * 0.45, -radiusY, radiusX * 0.35, radiusY * 1.5);
  surface.addColorStop(0, qi ? "#3b7980" : "#fffdf7");
  surface.addColorStop(0.46, qi ? "#24575f" : "#eee7f3");
  surface.addColorStop(1, qi ? "#123b43" : "#d2c6e2");
  context.fillStyle = surface;
  context.strokeStyle = qi ? "rgba(152,231,221,0.65)" : "rgba(255,255,255,0.88)";
  context.lineWidth = 1.4;
  context.beginPath(); context.ellipse(0, 0, radiusX, radiusY, 0, 0, Math.PI * 2); context.fill(); context.stroke();
  context.strokeStyle = accent; context.lineWidth = 1;
  context.beginPath(); context.ellipse(0, 0, radiusX * 0.83, radiusY * 0.73, 0, 0.04, Math.PI * 1.96); context.stroke();
  context.strokeStyle = qi ? "rgba(235,184,95,0.28)" : "rgba(255,255,255,0.26)";
  context.beginPath(); context.ellipse(0, radiusY * 0.8, radiusX * 0.85, radiusY * 0.85, 0, 0.04, Math.PI - 0.04); context.stroke();

  if (planted) {
    for (const side of [-1, 1]) {
      const plantX = side * radiusX * 0.78;
      const plantY = -radiusY * 0.08;
      for (let leaf = 0; leaf < 3; leaf += 1) {
        context.save(); context.translate(plantX, plantY);
        context.rotate(side * (leaf - 1) * 0.5);
        const length = 23 + leaf * 6;
        const petal = context.createLinearGradient(0, 0, 0, -length);
        petal.addColorStop(0, qi ? "#2e7173" : "#8a799f");
        petal.addColorStop(1, qi ? (leaf === 1 ? "#8ad3cf" : "#5b9f9f")
          : (leaf === 1 ? "#ded4e9" : "#b3a1cb"));
        context.fillStyle = petal;
        context.beginPath(); context.moveTo(0, 0);
        context.bezierCurveTo(-13, -length * 0.48, -8, -length, 0, -length);
        context.bezierCurveTo(9, -length, 12, -length * 0.38, 0, 0); context.fill();
        context.strokeStyle = qi ? "rgba(234,190,109,0.5)" : "rgba(255,255,255,0.5)";
        context.lineWidth = 0.7;
        context.beginPath(); context.moveTo(0, -3); context.lineTo(0, -length + 4); context.stroke();
        context.restore();
      }
    }
  }
  context.restore();
}

function drawBackground(): void {
  drawPearlLandscape(false);
  const companion = currentCompanionPosition();
  if (mode === "field") {
    // Field terrain stays fixed while the existing player moves across it.
    drawPearlIsland(width * 0.5, height * 0.59, width * 0.46, height * 0.24,
      isIOSFieldArt() ? "rgba(226,177,88,0.2)" : "rgba(119,98,159,0.16)");
  } else {
    const radius = clamp(Math.min(width, height) * 0.24, 88, 186);
    drawPearlIsland(companion.x, companion.y + clamp(height * 0.09, 42, 72), radius, radius * 0.24,
      isIOSFieldArt() ? "rgba(226,177,88,0.3)" : "rgba(119,98,159,0.23)", true);
  }
}

function drawStaticZone(zone: StaticZone): void {
  const time = animationTime();
  const point = staticPosition(zone);
  const radius = zone.radius * Math.min(width, height);
  context.save();
  context.translate(point.x, point.y);
  context.rotate(time * 0.08 + zone.phase);
  context.strokeStyle = `rgba(239, 90, 75, ${0.26 + Math.sin(time * 1.2 + zone.phase) * 0.08})`;
  context.lineWidth = 1;
  context.setLineDash([5, 8]);
  context.beginPath();
  context.arc(0, 0, radius, 0, Math.PI * 2);
  context.stroke();
  context.setLineDash([]);
  context.strokeStyle = "rgba(239, 90, 75, 0.12)";
  context.beginPath();
  for (let side = 0; side < 6; side += 1) {
    const angle = (side / 6) * Math.PI * 2;
    const x = Math.cos(angle) * radius * 0.65;
    const y = Math.sin(angle) * radius * 0.65;
    if (side === 0) context.moveTo(x, y);
    else context.lineTo(x, y);
  }
  context.closePath();
  context.stroke();
  context.restore();
  context.save();
  context.fillStyle = "#9d536a";
  context.font = "8px ui-monospace, SFMono-Regular, Menlo, monospace";
  context.textAlign = "center";
  context.fillText("STATIC", point.x, point.y + radius + 15);
  context.restore();
}

function drawEcho(echo: FieldEcho): void {
  if (session?.collected.includes(echo.id)) return;
  const point = echoPosition(echo);
  const aura = AURAS[echo.aura];
  const time = animationTime();
  const pulse = 1 + Math.sin(time * 1.6 + echo.phase) * 0.08;
  const radius = clamp(Math.min(width, height) * 0.026, 15, 23) * pulse;
  context.save();
  context.translate(point.x, point.y);
  context.fillStyle = "rgba(91,65,130,0.14)";
  context.beginPath(); context.ellipse(0, radius * 0.96, radius * 1.3, radius * 0.38, 0, 0, Math.PI * 2); context.fill();
  const glow = context.createRadialGradient(0, 0, 0, 0, 0, radius * 3.4);
  glow.addColorStop(0, `${aura.color}66`);
  glow.addColorStop(0.18, `${aura.color}33`);
  glow.addColorStop(0.55, `${aura.color}11`);
  glow.addColorStop(1, "transparent");
  context.fillStyle = glow;
  context.beginPath();
  context.arc(0, 0, radius * 3.4, 0, Math.PI * 2);
  context.fill();
  context.globalCompositeOperation = "source-over";
  const pearl = context.createRadialGradient(-radius * 0.3, -radius * 0.4, 0, 0, 0, radius * 1.2);
  pearl.addColorStop(0, "#fffdf7"); pearl.addColorStop(0.45, "#f2e9fa"); pearl.addColorStop(1, "#b59ecb");
  context.fillStyle = pearl;
  context.strokeStyle = "rgba(255,255,255,0.9)";
  context.lineWidth = 1.5;
  context.beginPath();
  context.arc(0, 0, radius, 0, Math.PI * 2);
  context.fill(); context.stroke();
  context.strokeStyle = `${aura.color}ee`;
  context.lineWidth = 2;
  context.beginPath(); context.arc(0, 0, radius * 0.57, 0, Math.PI * 2); context.stroke();
  context.fillStyle = "#71538f";
  context.beginPath();
  context.arc(0, 0, 3.2, 0, Math.PI * 2);
  context.fill();
  context.rotate(-time * 0.2 + echo.phase);
  context.strokeStyle = "rgba(113,83,143,0.34)";
  context.beginPath();
  context.ellipse(0, 0, radius * 1.7, radius * 0.55, 0, 0, Math.PI * 2);
  context.stroke();
  context.restore();
  context.save();
  context.fillStyle = "#594466";
  context.font = "9px ui-monospace, SFMono-Regular, Menlo, monospace";
  context.letterSpacing = "0.08em";
  context.textAlign = "center";
  context.fillText(aura.label.toUpperCase(), point.x, point.y + radius + 18);
  context.restore();
}

function drawFieldEntities(): void {
  if (!session || mode !== "field") return;
  for (const zone of session.staticZones) drawStaticZone(zone);

  for (const spark of session.sparks) {
    if (collectedSparks.has(spark.id)) continue;
    const alpha = 0.24 + (Math.sin(animationTime() * 1.1 + spark.phase) + 1) * 0.18;
    context.fillStyle = isIOSFieldArt() ? `rgba(230, 184, 102, ${alpha})`
      : `rgba(109, 81, 147, ${alpha})`;
    context.beginPath();
    context.arc(spark.x * width, spark.y * height, 1.2, 0, Math.PI * 2);
    context.fill();
  }

  for (const echo of session.echoes) drawEcho(echo);

  if (Math.hypot(target.x - player.x, target.y - player.y) > 14) {
    context.save();
    context.strokeStyle = isIOSFieldArt() ? "rgba(115,217,217,0.52)" : "rgba(100, 72, 144, 0.46)";
    context.setLineDash([2, 7]);
    context.beginPath();
    context.arc(target.x, target.y, 11 + Math.sin(animationTime() * 4) * 2, 0, Math.PI * 2);
    context.stroke();
    context.restore();
  }
}

function drawParticles(): void {
  context.save();
  context.globalCompositeOperation = "source-over";
  for (const particle of particles) {
    const alpha = clamp(particle.life / particle.maxLife, 0, 1);
    context.globalAlpha = alpha;
    context.fillStyle = particle.color;
    context.beginPath();
    context.arc(particle.x, particle.y, particle.size * alpha, 0, Math.PI * 2);
    context.fill();
  }
  context.restore();
}

function drawLeafEar(
  appendage: ProtoRigAppendage,
  accent: string,
  profile: GrowthVisualProfile,
  time: number,
): void {
  if (!appendage.visible) return;
  const qi = isIOSFieldArt();
  const side = appendage.side === "left" ? -1 : 1;
  const geometry = profile.geometry;
  const movement = profile.movement;
  const earSway =
    Math.sin(time * movement.earSwayRate + side * movement.opposingEarPhase) * movement.earSway;
  context.save();
  context.globalAlpha *= appendage.opacity;
  context.translate(appendage.x, appendage.y);
  context.rotate(appendage.rotation + earSway);
  context.scale(appendage.scaleX, appendage.scaleY);
  const gradient = context.createLinearGradient(0, 22, side * 12, geometry.earTipY);
  gradient.addColorStop(0, qi ? "#245f68" : "#a996cc");
  gradient.addColorStop(0.64, qi ? "#6bb6b7" : "#e0d6f0");
  gradient.addColorStop(1, qi ? "#e9bd77" : "#fffaf5");
  context.fillStyle = gradient;
  context.strokeStyle = accent;
  context.lineWidth = 1.3;
  context.beginPath();
  context.moveTo(0, 18);
  context.bezierCurveTo(side * -7, -4, side * -2, geometry.earTipY + 9, side * 10, geometry.earTipY);
  context.bezierCurveTo(
    side * (geometry.earWidth - 2),
    geometry.earTipY + 7,
    side * geometry.earWidth,
    -12,
    0,
    18,
  );
  context.closePath();
  context.fill();
  context.stroke();
  context.strokeStyle = qi ? "rgba(247,212,150,0.72)" : "rgba(255, 255, 255, 0.72)";
  context.beginPath();
  context.moveTo(0, 15);
  context.quadraticCurveTo(side * 12, -16, side * 10, geometry.earTipY + 7);
  context.stroke();
  context.restore();
}

function drawRigArm(
  appendage: ProtoRigAppendage,
  profile: GrowthVisualProfile,
  roleId: RoleId,
  time: number,
  motion: PresentationMotion,
  motionAmplitude: number,
): void {
  if (!appendage.visible) return;
  const qi = isIOSFieldArt();
  const sign = appendage.side === "left" ? -1 : 1;
  const armOpen = motion === "play" ? 1.32 : motion === "focus" ? 0.62 : 1;
  context.save();
  context.globalAlpha *= appendage.opacity;
  context.translate(appendage.x, appendage.y);
  context.rotate(
    appendage.rotation * armOpen -
      sign * Math.sin(time * 1.2) * profile.movement.armSway * motionAmplitude,
  );
  context.scale(appendage.scaleX, appendage.scaleY);
  const shell = context.createLinearGradient(-8, -20, 10, 24);
  shell.addColorStop(0, qi ? "#c6e8dd" : "#f8f1fb");
  shell.addColorStop(0.5, qi ? "#5ca5a4" : "#d5c6e9");
  shell.addColorStop(1, qi ? "#275e6b" : "#9f8bbc");
  context.fillStyle = shell;
  context.strokeStyle = rgba(ROLES[roleId].rgb, 0.28);
  context.lineWidth = 1.2;
  context.beginPath();
  context.ellipse(0, 0, profile.geometry.armRadiusX, profile.geometry.armRadiusY, 0, 0, Math.PI * 2);
  context.fill();
  context.stroke();
  context.restore();
}

function drawRigFoot(appendage: ProtoRigAppendage, profile: GrowthVisualProfile): void {
  if (!appendage.visible) return;
  const qi = isIOSFieldArt();
  context.save();
  context.globalAlpha *= appendage.opacity;
  context.translate(appendage.x, appendage.y);
  context.rotate(appendage.rotation);
  context.scale(appendage.scaleX, appendage.scaleY);
  const shell = context.createLinearGradient(0, -10, 0, 11);
  shell.addColorStop(0, qi ? "#80c2bb" : "#e4d8f2");
  shell.addColorStop(1, qi ? "#234d5a" : "#9a85b7");
  context.fillStyle = shell;
  context.strokeStyle = qi ? "rgba(191,234,220,0.8)" : "rgba(248, 237, 255, 0.8)";
  context.lineWidth = 1.2;
  context.beginPath();
  context.ellipse(0, 0, profile.geometry.footRadiusX, profile.geometry.footRadiusY, 0, 0, Math.PI * 2);
  context.fill();
  context.stroke();
  context.restore();
}

function drawRigAppendage(
  appendage: ProtoRigAppendage,
  profile: GrowthVisualProfile,
  roleId: RoleId,
  time: number,
  motion: PresentationMotion,
  motionAmplitude: number,
): void {
  if (!appendage.visible) return;
  if (appendage.kind === "ear") {
    drawLeafEar(appendage, rgba(ROLES[roleId].rgb, appendage.opacity < 1 ? 0.48 : 0.68), profile, time);
  } else if (appendage.kind === "arm") {
    drawRigArm(appendage, profile, roleId, time, motion, motionAmplitude);
  } else {
    drawRigFoot(appendage, profile);
  }
}

function drawLightBall(x: number, y: number, scale: number, roleId: RoleId): void {
  const role = ROLES[roleId];
  const time = animationTime();
  const radius = 38 * scale;
  context.save();
  context.translate(x, y);
  context.globalCompositeOperation = "source-over";
  const glow = context.createRadialGradient(0, 0, 0, 0, 0, radius * 2.8);
  glow.addColorStop(0, "rgba(255,255,255,0.98)");
  glow.addColorStop(0.16, "rgba(211,191,234,0.9)");
  glow.addColorStop(0.48, pearlAccent(role.rgb, 0.2));
  glow.addColorStop(1, "transparent");
  context.fillStyle = glow;
  context.beginPath();
  context.arc(0, 0, radius * 2.8, 0, Math.PI * 2);
  context.fill();
  context.globalCompositeOperation = "source-over";
  context.strokeStyle = pearlAccent(role.rgb, 0.62);
  for (let ring = 0; ring < 3; ring += 1) {
    context.save();
    context.rotate(time * (ring % 2 ? -0.34 : 0.25) + ring);
    context.beginPath();
    context.ellipse(0, 0, radius * (1.08 + ring * 0.22), radius * (0.42 + ring * 0.06), 0, 0, Math.PI * 2);
    context.stroke();
    context.restore();
  }
  context.restore();
}

function drawExpressionMark(roleId: RoleId): void {
  const role = ROLES[roleId];
  const time = animationTime();
  context.save();
  context.strokeStyle = pearlAccent(role.rgb, 0.72);
  context.fillStyle = pearlAccent(role.rgb, 0.6);
  context.lineWidth = 1.15;

  if (roleId === "hearth") {
    for (const side of [-1, 1] as const) {
      context.beginPath();
      context.moveTo(side * 15, 12);
      context.quadraticCurveTo(side * 31, 3, side * 35, -13);
      context.quadraticCurveTo(side * 20, -8, side * 15, 12);
      context.stroke();
    }
  } else if (roleId === "muse") {
    context.rotate(time * 0.16);
    for (let ray = 0; ray < 5; ray += 1) {
      context.rotate((Math.PI * 2) / 5);
      context.beginPath();
      context.moveTo(0, -49);
      context.lineTo(0, -57);
      context.stroke();
    }
    context.fillText("♪", 36, -38);
  } else if (roleId === "scout") {
    context.beginPath();
    context.arc(0, -28, 67, -0.42, 0.42);
    context.stroke();
    context.beginPath();
    context.arc(61, -28, 2.4, 0, Math.PI * 2);
    context.fill();
  } else if (roleId === "beacon") {
    for (let arc = 0; arc < 3; arc += 1) {
      context.beginPath();
      context.arc(0, 18, 54 + arc * 7, 0.16 * Math.PI, 0.84 * Math.PI);
      context.stroke();
    }
  } else if (roleId === "keeper") {
    context.strokeRect(-38, -69, 76, 82);
    context.beginPath();
    context.moveTo(-32, -61);
    context.lineTo(-25, -54);
    context.moveTo(32, -61);
    context.lineTo(25, -54);
    context.stroke();
  } else {
    context.beginPath();
    context.moveTo(0, -75);
    context.lineTo(62, -48);
    context.lineTo(52, 33);
    context.quadraticCurveTo(0, 76, -52, 33);
    context.lineTo(-62, -48);
    context.closePath();
    context.stroke();
  }
  context.restore();
}

function drawProtoArchi(x: number, y: number, alpha = 1, drawSpec?: QiMonDrawSpec): void {
  if (desktopHost && drawSpec?.nativeBody !== false) { drawNativePresence(x, y, alpha, drawSpec); return; }
  const roleId = drawSpec?.role ?? journey.expression;
  const role = ROLES[roleId];
  const stage = stageForJourney(journey);
  const visualProfile = visualProfileForStage(drawSpec?.stageName ?? stage.name);
  const movement = visualProfile.movement;
  const auraGeometry = visualProfile.auraGeometry;
  const careVisual = CARE_MOOD_VISUALS[drawSpec?.careMood ?? careProjection.mood];
  const presentationActive = !drawSpec && mode === "habitat";
  const activeView = drawSpec?.view ?? (presentationActive ? presentationState.view : "front");
  const activeMotion = drawSpec?.motion ?? (presentationActive ? presentationState.motion : "idle");
  const visualRig = protoVisualRigForView(activeView, visualProfile);
  const corePearl = visualRig.core.visual;
  const qi = isIOSFieldArt();
  const rearView = visualRig.silhouette === "face-free-back";
  const motionAmplitude = activeMotion === "focus" ? 0.28 : activeMotion === "play" ? 1.35 : 1;
  const compactHabitat = mode !== "field" && width <= 800 && height <= 680;
  const fieldScale = drawSpec?.scale ?? (mode === "field" ? 0.68 : compactHabitat ? 0.72 : width <= 800 ? 0.92 : 1.28);
  const responsiveScale = clamp(Math.min(width, height) / 760, 0.72, 1.22);
  const presentationStageScale = presentationActive
    ? presentationState.scale * (width <= 800 ? 1.04 : 1.18) * habitatEncounterComposition(width, height).scaleMultiplier
    : 1;
  const scale = (drawSpec ? 1 : stage.scale) * fieldScale * responsiveScale * presentationStageScale;
  const time = animationTime();
  const baseBob =
    Math.sin(time * careVisual.pace * movement.bobRate) *
    (!drawSpec && mode === "field" ? movement.fieldLift : careVisual.lift * movement.habitatLift) *
    motionAmplitude;
  const playfulLift =
    activeMotion === "play" && !reducedMotion
      ? -Math.abs(Math.sin(time * 1.55)) * (4 + presentationPulse * 7)
      : 0;
  const bob = baseBob + playfulLift;

  if (!drawSpec && mode === "field" && transition > 0.42) {
    const ballScale = scale * (0.65 + (transition - 0.42) * 0.7);
    drawLightBall(x, y + bob, ballScale, journey.expression);
    return;
  }

  context.save();
  context.translate(x, y + bob);
  context.scale(scale, scale);
  if (drawSpec?.facing === -1) context.scale(-1, 1);
  const travelLean =
    !reducedMotion && mode === "field" ? clamp(player.vx / 2800, -movement.travelLean, movement.travelLean) : 0;
  context.rotate(travelLean + Math.sin(time * 0.62) * movement.idleLean);
  context.globalAlpha = alpha * (!drawSpec && mode === "field" && transition > 0 ? 1 - transition / 0.42 : 1);

  context.save();
  const contact = context.createRadialGradient(0, 0, 0, 0, 0, 61);
  contact.addColorStop(0, qi ? "rgba(1,23,28,0.48)" : "rgba(70,48,106,0.28)");
  contact.addColorStop(1, qi ? "rgba(1,23,28,0)" : "rgba(70,48,106,0)");
  context.translate(0, 53 - bob); context.scale(1, 0.25);
  context.fillStyle = contact;
  context.beginPath(); context.arc(0, 0, 61, 0, Math.PI * 2); context.fill();
  context.restore();

  const auraStrength =
    auraGeometry.baseStrength +
    morphFlash * 0.32 +
    petPulse * 0.2 +
    (activeMotion === "focus" ? 0.04 : activeMotion === "play" ? 0.1 + presentationPulse * 0.08 : 0);
  context.save();
  context.globalCompositeOperation = "lighter";
  const aura = context.createRadialGradient(0, 0, 8, 0, 0, auraGeometry.radius);
  aura.addColorStop(0, rgba(role.rgb, auraStrength));
  aura.addColorStop(0.42, rgba(careVisual.rgb, auraStrength * 0.42));
  aura.addColorStop(1, "transparent");
  context.fillStyle = aura;
  context.beginPath();
  context.arc(0, 0, auraGeometry.radius, 0, Math.PI * 2);
  context.fill();
  context.restore();

  context.strokeStyle = rgba(careVisual.rgb, 0.24 + morphFlash * 0.42);
  context.lineWidth = 1;
  context.beginPath();
  context.ellipse(
    0,
    48,
    auraGeometry.groundRadiusX + Math.sin(time) * 3,
    auraGeometry.groundRadiusY,
    0,
    0,
    Math.PI * 2,
  );
  context.stroke();
  if (auraGeometry.outerGroundRing) {
    context.save();
    context.setLineDash([3, 7]);
    context.strokeStyle = rgba(role.rgb, 0.25 + morphFlash * 0.28);
    context.beginPath();
    context.ellipse(
      0,
      48,
      auraGeometry.groundRadiusX + 10 + morphFlash * 7,
      auraGeometry.groundRadiusY + 4 + morphFlash * 3,
      0,
      0,
      Math.PI * 2,
    );
    context.stroke();
    context.restore();

    context.save();
    context.globalCompositeOperation = "lighter";
    context.strokeStyle = rgba(careVisual.rgb, 0.2 + morphFlash * 0.18);
    context.lineWidth = 0.9;
    context.rotate(time * 0.06);
    context.beginPath();
    context.ellipse(
      0,
      4,
      auraGeometry.orbitRadiusX + morphFlash * 8,
      auraGeometry.orbitRadiusY + morphFlash * 5,
      -0.12,
      0,
      Math.PI * 2,
    );
    context.stroke();
    context.fillStyle = "rgba(231, 255, 249, 0.72)";
    for (let index = 0; index < auraGeometry.orbitMotes; index += 1) {
      const angle = time * 0.18 + (index / auraGeometry.orbitMotes) * Math.PI * 2;
      context.beginPath();
      context.arc(
        Math.cos(angle) * auraGeometry.orbitRadiusX,
        4 + Math.sin(angle) * auraGeometry.orbitRadiusY,
        1.45,
        0,
        Math.PI * 2,
      );
      context.fill();
    }
    context.restore();
  }

  const drawAppendagesBetween = (minimumDepth: number, maximumDepth: number): void => {
    for (const layerId of visualRig.depthOrder) {
      const appendage = visualRig.appendages.find((candidate) => candidate.id === layerId);
      if (!appendage) continue;
      if (appendage.depth < minimumDepth || appendage.depth >= maximumDepth) continue;
      drawRigAppendage(appendage, visualProfile, roleId, time, activeMotion, motionAmplitude);
    }
  };

  drawAppendagesBetween(Number.NEGATIVE_INFINITY, visualRig.body.depth);

  const bodyGradient = context.createRadialGradient(
    rearView ? visualRig.body.x : visualRig.body.x - visualRig.body.radiusX * 0.32,
    visualRig.body.y - visualRig.body.radiusY * (rearView ? 0.58 : 0.46),
    rearView ? 10 : 4,
    visualRig.body.x,
    visualRig.body.y,
    Math.max(visualRig.body.radiusX, visualRig.body.radiusY) + 11,
  );
  bodyGradient.addColorStop(0, qi ? (rearView ? "#8ac6bd" : "#e1f1df")
    : (rearView ? "#efe7f6" : "#fffdf7"));
  bodyGradient.addColorStop(0.25, qi ? "#91cfc5" : "#eadff4");
  bodyGradient.addColorStop(0.72, qi ? "#478d91" : "#c4b2dc");
  bodyGradient.addColorStop(1, qi ? "#1b5360" : "#8d76ad");
  context.fillStyle = bodyGradient;
  context.strokeStyle = qi ? "rgba(188,235,220,0.82)" : "rgba(255, 250, 255, 0.86)";
  context.lineWidth = 1.5;
  context.beginPath();
  context.ellipse(
    visualRig.body.x,
    visualRig.body.y,
    visualRig.body.radiusX,
    visualRig.body.radiusY,
    visualRig.body.rotation,
    0,
    Math.PI * 2,
  );
  context.fill();
  context.stroke();

  context.save();
  context.beginPath();
  context.ellipse(
    visualRig.body.x,
    visualRig.body.y,
    visualRig.body.radiusX - 1.5,
    visualRig.body.radiusY - 1.5,
    visualRig.body.rotation,
    0,
    Math.PI * 2,
  );
  context.clip();
  context.globalCompositeOperation = "screen";
  const bodyVolume = context.createRadialGradient(
    rearView ? visualRig.body.x : visualRig.body.x - visualRig.body.radiusX * 0.4,
    visualRig.body.y - visualRig.body.radiusY * (rearView ? 0.62 : 0.48),
    rearView ? 8 : 1,
    visualRig.body.x,
    visualRig.body.y,
    visualRig.body.radiusY * 1.15,
  );
  bodyVolume.addColorStop(0, rearView ? "rgba(255, 255, 255, 0.18)" : "rgba(255, 255, 255, 0.34)");
  bodyVolume.addColorStop(0.23, "rgba(255, 228, 211, 0.23)");
  bodyVolume.addColorStop(0.58, rgba(role.rgb, 0.045));
  bodyVolume.addColorStop(1, "transparent");
  context.fillStyle = bodyVolume;
  context.fillRect(
    visualRig.body.x - visualRig.body.radiusX,
    visualRig.body.y - visualRig.body.radiusY,
    visualRig.body.radiusX * 2,
    visualRig.body.radiusY * 2,
  );
  context.strokeStyle = "rgba(255, 251, 255, 0.38)";
  context.lineWidth = 0.75;
  context.beginPath();
  context.ellipse(
    visualRig.body.x + 2,
    visualRig.body.y + 1,
    Math.max(2, visualRig.body.radiusX - 5),
    Math.max(2, visualRig.body.radiusY - 5),
    visualRig.body.rotation,
    -0.18 * Math.PI,
    0.72 * Math.PI,
  );
  context.stroke();
  context.restore();

  drawAppendagesBetween(visualRig.body.depth, visualRig.head.depth);

  const headGradient = context.createRadialGradient(
    rearView ? visualRig.head.x : visualRig.head.x - visualRig.head.radiusX * 0.34,
    visualRig.head.y - visualRig.head.radiusY * (rearView ? 0.62 : 0.4),
    rearView ? 12 : 4,
    visualRig.head.x,
    visualRig.head.y + 3,
    Math.max(visualRig.head.radiusX, visualRig.head.radiusY) + 12,
  );
  headGradient.addColorStop(0, qi ? (rearView ? "#9ad4c8" : "#f2f5dc")
    : (rearView ? "#f6eef9" : "#fffdf8"));
  headGradient.addColorStop(0.26, qi ? "#ade0cf" : "#f0e7fa");
  headGradient.addColorStop(0.78, qi ? "#5baba9" : "#c6b4e2");
  headGradient.addColorStop(1, qi ? "#2a6971" : "#9a7fbd");
  context.fillStyle = headGradient;
  context.strokeStyle = qi ? "rgba(210,244,225,0.9)" : "rgba(255, 250, 255, 0.94)";
  context.beginPath();
  context.ellipse(
    visualRig.head.x,
    visualRig.head.y,
    visualRig.head.radiusX,
    visualRig.head.radiusY,
    visualRig.head.rotation,
    0,
    Math.PI * 2,
  );
  context.fill();
  context.stroke();

  context.save();
  context.beginPath();
  context.ellipse(
    visualRig.head.x,
    visualRig.head.y,
    visualRig.head.radiusX - 1.5,
    visualRig.head.radiusY - 1.5,
    visualRig.head.rotation,
    0,
    Math.PI * 2,
  );
  context.clip();
  context.globalCompositeOperation = "screen";
  const headVolume = context.createRadialGradient(
    rearView ? visualRig.head.x : visualRig.head.x - visualRig.head.radiusX * 0.42,
    visualRig.head.y - visualRig.head.radiusY * (rearView ? 0.64 : 0.5),
    rearView ? 10 : 1,
    visualRig.head.x,
    visualRig.head.y,
    visualRig.head.radiusX * 1.18,
  );
  headVolume.addColorStop(0, rearView ? "rgba(255, 255, 255, 0.2)" : "rgba(255, 255, 255, 0.42)");
  headVolume.addColorStop(0.22, "rgba(255, 225, 213, 0.26)");
  headVolume.addColorStop(0.62, rgba(role.rgb, 0.04));
  headVolume.addColorStop(1, "transparent");
  context.fillStyle = headVolume;
  context.fillRect(
    visualRig.head.x - visualRig.head.radiusX,
    visualRig.head.y - visualRig.head.radiusY,
    visualRig.head.radiusX * 2,
    visualRig.head.radiusY * 2,
  );
  context.strokeStyle = "rgba(255, 248, 255, 0.46)";
  context.lineWidth = 0.75;
  context.beginPath();
  context.ellipse(
    visualRig.head.x + 1,
    visualRig.head.y + 1,
    Math.max(2, visualRig.head.radiusX - 5),
    Math.max(2, visualRig.head.radiusY - 5),
    visualRig.head.rotation,
    -0.16 * Math.PI,
    0.78 * Math.PI,
  );
  context.stroke();
  context.restore();

  const random = seededRandom(hashString(`${drawSpec?.seed ?? journey.seed}:specks`));
  context.save();
  context.globalCompositeOperation = "lighter";
  const speckMinY = visualRig.head.y - visualRig.head.radiusY * 0.78;
  const speckMaxY = visualRig.body.y + visualRig.body.radiusY * 0.72;
  const speckSpanX = Math.max(visualRig.head.radiusX, visualRig.body.radiusX) * 1.45;
  let specksDrawn = 0;
  for (let attempt = 0; attempt < auraGeometry.speckCount * 3 && specksDrawn < auraGeometry.speckCount; attempt += 1) {
    const sx = (random() - 0.5) * speckSpanX + (visualRig.head.x + visualRig.body.x) / 2;
    const sy = speckMinY + random() * (speckMaxY - speckMinY);
    const inHead =
      ((sx - visualRig.head.x) / visualRig.head.radiusX) ** 2 +
        ((sy - visualRig.head.y) / visualRig.head.radiusY) ** 2 <=
      0.82;
    const inBody =
      ((sx - visualRig.body.x) / visualRig.body.radiusX) ** 2 +
        ((sy - visualRig.body.y) / visualRig.body.radiusY) ** 2 <=
      0.82;
    if (!inHead && !inBody) continue;
    const alpha = 0.22 + random() * 0.42;
    context.fillStyle = `rgba(255, 246, 238, ${alpha})`;
    context.beginPath();
    context.arc(sx, sy, 0.45 + random() * 0.8, 0, Math.PI * 2);
    context.fill();
    specksDrawn += 1;
  }
  context.restore();

  const lookX = drawSpec?.gazeX ?? clamp(((pointer.x - x) / Math.max(width, 1)) * 15, -4.2, 4.2);
  const lookY = drawSpec ? 0 : clamp(((pointer.y - y) / Math.max(height, 1)) * 10, -2.6, 3.2);
  const blinkSeed = drawSpec ? hashString(drawSpec.seed) : (session?.seed ?? 1);
  const blink = !reducedMotion && Math.sin(time * 0.68 + blinkSeed) > 0.988;
  drawAppendagesBetween(visualRig.head.depth, Number.POSITIVE_INFINITY);
  for (const eye of visualRig.face.eyes) {
    if (!visualRig.face.visible || !eye.visible) continue;
    const eyeX = eye.x;
    const eyeY = eye.y;
    const openEyeHeight = activeMotion === "focus" ? 13.5 : activeMotion === "play" ? 18 : 17;
    context.save();
    context.globalAlpha *= eye.opacity;
    context.fillStyle = "rgba(247, 255, 253, 0.96)";
    context.beginPath();
    context.ellipse(eyeX, eyeY, 12 * eye.scaleX, blink ? 1.3 : openEyeHeight, 0, 0, Math.PI * 2);
    context.fill();
    if (!blink) {
      const iris = context.createRadialGradient(eyeX + lookX, eyeY + 1 + lookY, 1, eyeX + lookX, eyeY + 1 + lookY, 10);
      iris.addColorStop(0, qi ? "#092a35" : "#151333");
      iris.addColorStop(0.45, qi ? "#246b77" : "#392d85");
      iris.addColorStop(0.75, qi ? "#67c4be" : "#7167d7");
      iris.addColorStop(1, qi ? "#071f2b" : "#11182d");
      context.fillStyle = iris;
      context.beginPath();
      context.ellipse(eyeX + lookX, eyeY + 1 + lookY, 8.5 * eye.scaleX, 12.5, 0, 0, Math.PI * 2);
      context.fill();
      context.fillStyle = "white";
      context.beginPath();
      context.arc(eyeX - 3 + lookX, eyeY - 5 + lookY, 2.8, 0, Math.PI * 2);
      context.fill();
    }
    context.restore();
  }

  if (visualRig.face.visible) {
    context.strokeStyle = "rgba(64, 44, 91, 0.82)";
    context.lineWidth = 1.3;
    context.beginPath();
    const mouthX = visualRig.face.mouthX;
    if (mode === "reflection" || petPulse > 0.25 || activeMotion === "play") {
      context.arc(mouthX, visualRig.head.y + 17, 7, 0.15 * Math.PI, 0.85 * Math.PI);
    } else if (activeMotion === "focus") {
      context.moveTo(mouthX - 3, visualRig.head.y + 20);
      context.lineTo(mouthX + 3, visualRig.head.y + 20);
    } else {
      context.moveTo(mouthX - 3, visualRig.head.y + 19);
      context.quadraticCurveTo(mouthX, visualRig.head.y + 21, mouthX + 3, visualRig.head.y + 19);
    }
    context.stroke();
  }
  if (visualRig.dorsalSeam.visible) {
    context.save();
    context.globalAlpha *= visualRig.dorsalSeam.opacity;
    const napeY = visualRig.head.y + visualRig.head.radiusY * 0.46;
    const shoulderY = visualRig.body.y - visualRig.body.radiusY * 0.42;
    const drawDorsalPath = (): void => {
      context.beginPath();
      context.moveTo(visualRig.head.x, visualRig.head.y - visualRig.head.radiusY * 0.58);
      context.quadraticCurveTo(
        visualRig.head.x - 3,
        napeY,
        visualRig.body.x,
        visualRig.body.y + visualRig.body.radiusY * 0.56,
      );
      context.moveTo(visualRig.head.x, napeY);
      context.quadraticCurveTo(
        visualRig.body.x - visualRig.body.radiusX * 0.14,
        shoulderY - 2,
        visualRig.body.x - visualRig.body.radiusX * 0.42,
        shoulderY,
      );
      context.moveTo(visualRig.head.x, napeY);
      context.quadraticCurveTo(
        visualRig.body.x + visualRig.body.radiusX * 0.14,
        shoulderY - 2,
        visualRig.body.x + visualRig.body.radiusX * 0.42,
        shoulderY,
      );
    };
    context.strokeStyle = "rgba(106, 79, 143, 0.72)";
    context.lineWidth = 2.4;
    drawDorsalPath();
    context.stroke();
    context.strokeStyle = "rgba(255, 245, 251, 0.92)";
    context.lineWidth = 0.9;
    drawDorsalPath();
    context.stroke();
    context.fillStyle = "rgba(235, 255, 251, 0.9)";
    for (const seamY of [
      visualRig.head.y - visualRig.head.radiusY * 0.18,
      visualRig.head.y + visualRig.head.radiusY * 0.34,
      visualRig.body.y + visualRig.body.radiusY * 0.2,
    ]) {
      context.beginPath();
      context.arc(visualRig.head.x, seamY, 1.35, 0, Math.PI * 2);
      context.fill();
    }
    context.restore();
  }

  const corePulse = 1 + Math.sin(time * 2.1) * movement.corePulse + morphFlash * 0.18;
  context.save();
  context.globalAlpha *= visualRig.core.shellTransmission;
  context.globalCompositeOperation = "lighter";
  const coreGlow = context.createRadialGradient(
    corePearl.x,
    corePearl.y,
    0,
    corePearl.x,
    corePearl.y,
    (corePearl.glowRadius - 1) * corePulse,
  );
  coreGlow.addColorStop(0, "rgba(255, 255, 255, 1)");
  coreGlow.addColorStop(0.21, "rgba(255, 239, 197, 0.95)");
  coreGlow.addColorStop(0.55, rgba(role.rgb, 0.28 + morphFlash * 0.3));
  coreGlow.addColorStop(1, "transparent");
  context.fillStyle = coreGlow;
  context.beginPath();
  context.arc(corePearl.x, corePearl.y, corePearl.glowRadius * corePulse, 0, Math.PI * 2);
  context.fill();
  context.restore();
  context.save();
  context.globalAlpha *= visualRig.core.shellTransmission;
  context.fillStyle = "rgba(255, 250, 230, 0.96)";
  context.strokeStyle = "rgba(255, 226, 166, 0.82)";
  context.beginPath();
  context.arc(corePearl.x, corePearl.y, corePearl.innerRadius * corePulse, 0, Math.PI * 2);
  context.fill();
  context.stroke();
  context.restore();

  if (visualRig.face.visible) {
    context.save();
    context.translate(visualRig.face.centerX, 0);
    drawExpressionMark(roleId);
    context.restore();
  }

  if (activeMotion === "focus") {
    context.save();
    context.strokeStyle = rgba(role.rgb, 0.24 + presentationPulse * 0.18);
    context.lineWidth = 0.8;
    for (let ring = 0; ring < 3; ring += 1) {
      context.beginPath();
      context.ellipse(0, corePearl.y, 33 + ring * 9, 15 + ring * 4, 0, 0, Math.PI * 2);
      context.stroke();
    }
    context.restore();
  } else if (activeMotion === "play") {
    context.save();
    context.globalCompositeOperation = "lighter";
    for (let mote = 0; mote < 7; mote += 1) {
      const angle = time * 0.7 + (mote / 7) * Math.PI * 2;
      const orbitX = Math.cos(angle) * (67 + (mote % 2) * 9);
      const orbitY = 5 + Math.sin(angle) * (59 + (mote % 3) * 4);
      context.fillStyle = mote % 2 === 0 ? "rgba(247, 255, 226, 0.78)" : rgba(role.rgb, 0.66);
      context.beginPath();
      context.arc(orbitX, orbitY, 1.4 + (mote % 3) * 0.45, 0, Math.PI * 2);
      context.fill();
    }
    context.restore();
  }

  context.restore();
}

function abstractPresenceScale(): number {
  const responsive = clamp(Math.min(width, height) / 760, 0.72, 1.22);
  return responsive * (width <= 800 ? 0.98 : 1.26) * presentationState.scale;
}

function drawCorePresence(x: number, y: number, alpha: number, expanded = false): void {
  const role = ROLES[journey.expression];
  const time = animationTime();
  const scale = abstractPresenceScale();
  const motion = presentationState.motion;
  const focusFactor = motion === "focus" ? 0.82 : 1;
  const playFactor = motion === "play" ? 1.08 + presentationPulse * 0.08 : 1;
  const breath = 1 + Math.sin(time * (motion === "focus" ? 1.1 : 1.55)) * (reducedMotion ? 0 : 0.035);
  const latticeRadius = (expanded ? 78 : 62) * focusFactor * playFactor;

  context.save();
  context.translate(x, y);
  context.scale(scale, scale);
  context.globalAlpha = alpha;

  context.save();
  context.globalCompositeOperation = "lighter";
  const ambient = context.createRadialGradient(0, 0, 0, 0, 0, latticeRadius * 1.75);
  ambient.addColorStop(0, "rgba(255, 249, 225, 0.3)");
  ambient.addColorStop(0.32, rgba(role.rgb, 0.16));
  ambient.addColorStop(1, "transparent");
  context.fillStyle = ambient;
  context.beginPath();
  context.arc(0, 0, latticeRadius * 1.75, 0, Math.PI * 2);
  context.fill();
  context.restore();

  context.save();
  context.strokeStyle = pearlAccent(role.rgb, 0.48);
  context.lineWidth = 0.8;
  for (let orbit = 0; orbit < 4; orbit += 1) {
    context.save();
    context.rotate(time * (orbit % 2 === 0 ? 0.055 : -0.045) + orbit * 0.74);
    context.beginPath();
    context.ellipse(
      0,
      0,
      latticeRadius * (0.66 + orbit * 0.13),
      latticeRadius * (0.25 + orbit * 0.045),
      0,
      0,
      Math.PI * 2,
    );
    context.stroke();
    context.restore();
  }
  context.restore();

  context.save();
  context.fillStyle = "rgba(123,92,164,0.75)";
  context.globalCompositeOperation = "source-over";
  for (let node = 0; node < 8; node += 1) {
    const angle = time * 0.13 + (node / 8) * Math.PI * 2;
    const radius = latticeRadius * (node % 2 === 0 ? 0.68 : 0.91);
    context.beginPath();
    context.arc(Math.cos(angle) * radius, Math.sin(angle) * radius * 0.42, 1.35, 0, Math.PI * 2);
    context.fill();
  }
  context.restore();

  context.save();
  context.globalCompositeOperation = "source-over";
  const glowRadius = 45 * breath;
  const glow = context.createRadialGradient(0, 0, 0, 0, 0, glowRadius);
  glow.addColorStop(0, "rgba(255, 255, 255, 1)");
  glow.addColorStop(0.2, "rgba(255, 246, 214, 0.98)");
  glow.addColorStop(0.48, "rgba(173,145,207,0.42)");
  glow.addColorStop(1, "transparent");
  context.fillStyle = glow;
  context.beginPath();
  context.arc(0, 0, glowRadius, 0, Math.PI * 2);
  context.fill();
  context.restore();

  context.fillStyle = "rgba(255, 251, 231, 0.98)";
  context.strokeStyle = "rgba(161,127,177,0.88)";
  context.lineWidth = 1;
  context.beginPath();
  context.arc(0, 0, 15 * breath, 0, Math.PI * 2);
  context.fill();
  context.stroke();

  context.restore();
}

function drawFieldPresence(x: number, y: number, alpha: number): void {
  const role = ROLES[journey.expression];
  const time = animationTime();
  const scale = abstractPresenceScale();
  const motion = presentationState.motion;
  const fieldScale = motion === "focus" ? 0.82 : motion === "play" ? 1.08 + presentationPulse * 0.08 : 1;

  context.save();
  context.translate(x, y);
  context.scale(scale * fieldScale, scale * fieldScale);
  context.globalAlpha = alpha;
  context.globalCompositeOperation = "source-over";

  for (let petal = 0; petal < 6; petal += 1) {
    context.save();
    context.rotate((petal / 6) * Math.PI * 2 + time * (petal % 2 === 0 ? 0.035 : -0.028));
    const membrane = context.createLinearGradient(0, -18, 0, -126);
    membrane.addColorStop(0, "rgba(255,250,255,0.34)");
    membrane.addColorStop(0.58, rgba(role.rgb, 0.075));
    membrane.addColorStop(1, "rgba(151,119,192,0.12)");
    context.fillStyle = membrane;
    context.strokeStyle = rgba(role.rgb, 0.24);
    context.lineWidth = 0.75;
    context.beginPath();
    context.moveTo(0, -14);
    context.bezierCurveTo(46, -45, 48, -99, 0, -128);
    context.bezierCurveTo(-48, -99, -46, -45, 0, -14);
    context.fill();
    context.stroke();
    context.restore();
  }

  context.strokeStyle = rgba(role.rgb, 0.29);
  context.lineWidth = 0.8;
  for (let ring = 0; ring < 4; ring += 1) {
    context.beginPath();
    context.ellipse(0, 0, 86 + ring * 17, 36 + ring * 9, ring * 0.11, 0, Math.PI * 2);
    context.stroke();
  }

  context.fillStyle = "rgba(220, 255, 249, 0.72)";
  for (let node = 0; node < 12; node += 1) {
    const angle = time * 0.16 + (node / 12) * Math.PI * 2;
    const nodeX = Math.cos(angle) * (92 + (node % 3) * 13);
    const nodeY = Math.sin(angle) * (40 + (node % 2) * 11);
    context.beginPath();
    context.arc(nodeX, nodeY, 1.2 + (node % 2) * 0.45, 0, Math.PI * 2);
    context.fill();
  }
  context.restore();

  drawCorePresence(x, y, alpha, true);
}

function drawLightPresence(x: number, y: number, alpha: number): void {
  const role = ROLES[journey.expression];
  const time = animationTime();
  const scale = abstractPresenceScale();
  const motionScale = presentationState.motion === "focus" ? 0.9 : presentationState.motion === "play" ? 1.07 : 1;

  context.save();
  context.translate(x, y);
  context.scale(scale * motionScale, scale * motionScale);
  context.globalAlpha = alpha;
  context.globalCompositeOperation = "source-over";

  const volume = context.createRadialGradient(0, 0, 12, 0, 0, 170);
  volume.addColorStop(0, "rgba(255, 250, 224, 0.24)");
  volume.addColorStop(0.38, rgba(role.rgb, 0.13));
  volume.addColorStop(0.72, "rgba(98, 225, 216, 0.055)");
  volume.addColorStop(1, "transparent");
  context.fillStyle = volume;
  context.beginPath();
  context.arc(0, 0, 170, 0, Math.PI * 2);
  context.fill();

  for (let layer = 0; layer < 2; layer += 1) {
    const count = layer === 0 ? 8 : 6;
    const length = layer === 0 ? 132 : 94;
    const widthAtCrown = layer === 0 ? 46 : 34;
    context.save();
    context.rotate(time * (layer === 0 ? 0.035 : -0.052) + layer * 0.22);
    for (let petal = 0; petal < count; petal += 1) {
      context.save();
      context.rotate((petal / count) * Math.PI * 2);
      const membrane = context.createLinearGradient(0, -12, 0, -length);
      membrane.addColorStop(0, "rgba(255,252,245,0.36)");
      membrane.addColorStop(0.42, rgba(role.rgb, layer === 0 ? 0.12 : 0.085));
      membrane.addColorStop(0.8, "rgba(163,135,195,0.22)");
      membrane.addColorStop(1, "rgba(218,190,223,0.1)");
      context.fillStyle = membrane;
      context.strokeStyle = layer === 0 ? "rgba(131,101,165,0.46)" : pearlAccent(role.rgb, 0.32);
      context.lineWidth = layer === 0 ? 0.9 : 0.65;
      context.beginPath();
      context.moveTo(0, -12);
      context.bezierCurveTo(widthAtCrown, -42, widthAtCrown * 0.78, -length * 0.82, 0, -length);
      context.bezierCurveTo(-widthAtCrown * 0.78, -length * 0.82, -widthAtCrown, -42, 0, -12);
      context.fill();
      context.stroke();
      context.restore();
    }
    context.restore();
  }

  context.strokeStyle = "rgba(132,99,167,0.35)";
  context.lineWidth = 0.7;
  for (let ring = 0; ring < 3; ring += 1) {
    context.beginPath();
    context.ellipse(0, 0, 78 + ring * 25, 34 + ring * 11, ring * 0.17, 0, Math.PI * 2);
    context.stroke();
  }
  context.restore();

  drawCorePresence(x, y, alpha, true);
}

function drawRevealPresence(x: number, y: number, alpha: number): void {
  const role = ROLES[journey.expression];
  const time = animationTime();
  const scale = abstractPresenceScale();

  context.save();
  context.translate(x, y);
  context.scale(scale, scale);
  context.globalAlpha = alpha;
  context.globalCompositeOperation = "source-over";

  const beam = context.createLinearGradient(0, -150, 0, 120);
  beam.addColorStop(0, "transparent");
  beam.addColorStop(0.4, rgba(role.rgb, 0.08));
  beam.addColorStop(0.56, "rgba(255, 248, 221, 0.24)");
  beam.addColorStop(1, "transparent");
  context.fillStyle = beam;
  context.fillRect(-22, -150, 44, 270);

  for (const side of [-1, 1] as const) {
    for (let shell = 0; shell < 3; shell += 1) {
      const openness = 0.76 + shell * 0.13;
      context.save();
      context.scale(side, 1);
      context.rotate((0.09 + shell * 0.035) * Math.sin(time * 0.33));
      const membrane = context.createLinearGradient(14, 0, 170, -70 + shell * 52);
      membrane.addColorStop(0, "rgba(255,250,248,0.3)");
      membrane.addColorStop(0.5, rgba(role.rgb, 0.13 - shell * 0.018));
      membrane.addColorStop(1, "rgba(148,115,187,0.09)");
      context.fillStyle = membrane;
      context.strokeStyle = shell === 0 ? "rgba(145,107,178,0.5)" : pearlAccent(role.rgb, 0.32);
      context.lineWidth = 0.8;
      context.beginPath();
      context.moveTo(18, 68 - shell * 23);
      context.bezierCurveTo(78, 62 - shell * 44, 126 * openness, 3 - shell * 28, 162, -88 + shell * 24);
      context.bezierCurveTo(112, -47 + shell * 31, 72, -7 + shell * 41, 18, 68 - shell * 23);
      context.fill();
      context.stroke();
      context.restore();
    }
  }

  context.strokeStyle = "rgba(255, 230, 179, 0.42)";
  context.lineWidth = 0.8;
  context.beginPath();
  context.ellipse(0, 50, 128, 25, 0, 0, Math.PI * 2);
  context.stroke();
  context.restore();

  drawProtoArchi(x, y, alpha * 0.82);
}

function drawContextAura(x: number, y: number, alpha: number): void {
  const roleId = journey.expression;
  const role = ROLES[roleId];
  const time = animationTime();
  const scale = abstractPresenceScale();
  const radius = 132;

  context.save();
  context.translate(x, y);
  context.scale(scale, scale);
  context.globalAlpha = alpha;
  context.globalCompositeOperation = "source-over";
  context.strokeStyle = pearlAccent(role.rgb, 0.46);
  context.fillStyle = pearlAccent(role.rgb, 0.14);
  context.lineWidth = 1;

  for (let ring = 0; ring < 3; ring += 1) {
    context.save();
    context.rotate(time * (ring % 2 === 0 ? 0.025 : -0.032) + ring * 0.28);
    context.setLineDash(ring === 1 ? [3, 8] : []);
    context.beginPath();
    context.ellipse(0, 4, radius + ring * 20, 66 + ring * 11, ring * 0.12, 0, Math.PI * 2);
    context.stroke();
    context.restore();
  }

  if (roleId === "hearth") {
    for (const side of [-1, 1] as const) {
      context.save();
      context.scale(side, 1);
      for (let leaf = 0; leaf < 4; leaf += 1) {
        const leafY = 34 - leaf * 38;
        context.beginPath();
        context.ellipse(122 + leaf * 8, leafY, 18, 7, -0.5 + leaf * 0.13, 0, Math.PI * 2);
        context.fill();
        context.stroke();
      }
      context.restore();
    }
  } else if (roleId === "muse") {
    for (const side of [-1, 1] as const) {
      context.save();
      context.scale(side, 1);
      context.beginPath();
      context.moveTo(32, -58);
      context.bezierCurveTo(128, -122, 164, 15, 82, 82);
      context.bezierCurveTo(48, 108, 103, 124, 151, 91);
      context.stroke();
      context.restore();
    }
  } else if (roleId === "scout") {
    for (let node = 0; node < 8; node += 1) {
      const angle = (node / 8) * Math.PI * 2 + time * 0.035;
      const nodeX = Math.cos(angle) * 156;
      const nodeY = 2 + Math.sin(angle) * 91;
      context.save();
      context.translate(nodeX, nodeY);
      context.rotate(angle + Math.PI / 4);
      context.strokeRect(-5, -5, 10, 10);
      context.restore();
    }
  } else if (roleId === "beacon") {
    for (let spoke = 0; spoke < 8; spoke += 1) {
      const angle = (spoke / 8) * Math.PI * 2;
      context.beginPath();
      context.moveTo(Math.cos(angle) * 112, Math.sin(angle) * 68);
      context.lineTo(Math.cos(angle) * 172, Math.sin(angle) * 102);
      context.stroke();
    }
  } else if (roleId === "keeper") {
    for (const side of [-1, 1] as const) {
      for (let plate = 0; plate < 3; plate += 1) {
        context.save();
        context.translate(side * (118 + plate * 15), -50 + plate * 50);
        context.rotate(side * (-0.08 + plate * 0.07));
        context.strokeRect(-13, -18, 26, 36);
        context.restore();
      }
    }
  } else {
    context.beginPath();
    context.moveTo(0, -138);
    context.lineTo(132, -76);
    context.lineTo(112, 67);
    context.quadraticCurveTo(0, 140, -112, 67);
    context.lineTo(-132, -76);
    context.closePath();
    context.stroke();
    for (let spike = 0; spike < 6; spike += 1) {
      const angle = (spike / 6) * Math.PI * 2 - Math.PI / 2;
      context.beginPath();
      context.moveTo(Math.cos(angle) * 145, Math.sin(angle) * 86);
      context.lineTo(Math.cos(angle) * 173, Math.sin(angle) * 105);
      context.stroke();
    }
  }

  context.restore();
}

function drawContextPresence(x: number, y: number, alpha: number): void {
  drawContextAura(x, y, alpha);
  drawProtoArchi(x, y, alpha);
}

function drawPresentationForm(form: PresentationForm, x: number, y: number, alpha: number): void {
  if (form === "core") {
    drawCorePresence(x, y, alpha);
  } else if (form === "field") {
    drawFieldPresence(x, y, alpha);
  } else if (form === "light") {
    drawLightPresence(x, y, alpha);
  } else if (form === "reveal") {
    drawRevealPresence(x, y, alpha);
  } else if (form === "context") {
    drawContextPresence(x, y, alpha);
  } else {
    drawProtoArchi(x, y, alpha);
  }
}

function drawArchi(x: number, y: number): void {
  if (desktopHost) { drawNativePresence(x, y); return; }
  const portrait = currentLiminalPortrait();
  if (portrait) { drawLiminalPortrait(portrait, x, y); return; }
  if (mode !== "habitat") {
    drawProtoArchi(x, y);
    return;
  }
  const mix = presenceMix(presenceSequence.position);
  for (const phase of PRESENCE_PHASES) {
    const weight = mix.weights[phase];
    if (weight > 0) drawPresentationForm(phase, x, y, weight);
  }
}

function drawLiminalPortrait(portrait: LiminalPortraitChoice, x: number, y: number): void {
  const image = liminalPortraits[portrait];
  if (!image || !image.complete || image.naturalWidth === 0) return;
  const quiet = reducedMotion || document.visibilityState !== "visible";
  const light = liminalPortraitLight(animationTime(), quiet);
  const dimension = clamp(Math.min(width, height) * (mode === "habitat" ? 0.5 : 0.28), 100, 400)
    * presentationState.scale * light.scale;
  context.save();
  context.translate(x, y);
  context.shadowColor = `rgba(239,186,95,${light.haloAlpha})`;
  context.shadowBlur = 12;
  context.drawImage(image, -dimension / 2, -dimension / 2, dimension, dimension);
  context.restore();
}

function drawIOSStageHalo(dimension: number, profile: GrowthVisualProfile, time: number): void {
  const detail = profile.auraGeometry;
  const reach = dimension * (0.5 + (detail.radius - 104) / 520);
  context.save();
  context.globalCompositeOperation = "lighter";
  const glow = context.createRadialGradient(0, 0, dimension * 0.06, 0, 0, reach * 1.45);
  glow.addColorStop(0, `rgba(231,174,85,${detail.baseStrength * 0.66})`);
  glow.addColorStop(0.45, `rgba(71,191,204,${detail.baseStrength * 0.34})`);
  glow.addColorStop(1, "transparent");
  context.fillStyle = glow;
  context.beginPath(); context.arc(0, 0, reach * 1.45, 0, Math.PI * 2); context.fill();

  const ringCount = detail.outerGroundRing ? 2 : 1;
  for (let ring = 0; ring < ringCount; ring += 1) {
    context.save();
    context.rotate(time * (ring === 0 ? 0.025 : -0.019));
    context.strokeStyle = ring === 0 ? "rgba(239,186,95,0.38)" : "rgba(122,218,223,0.3)";
    context.lineWidth = ring === 0 ? 1.3 : 0.9;
    context.beginPath();
    context.ellipse(0, 0, reach * (1 + ring * 0.15), reach * (0.68 + ring * 0.08),
      -0.2, 0, Math.PI * 2);
    context.stroke();
    context.restore();
  }
  for (let mote = 0; mote < detail.orbitMotes; mote += 1) {
    const angle = (mote / detail.orbitMotes) * Math.PI * 2 + time * 0.11;
    context.fillStyle = mote % 2 === 0 ? "rgba(246,203,129,0.78)" : "rgba(151,234,231,0.7)";
    context.beginPath();
    context.arc(Math.cos(angle) * reach, Math.sin(angle) * reach * 0.7,
      1.4 + (mote % 3) * 0.35, 0, Math.PI * 2);
    context.fill();
  }
  context.restore();
}

/** Reuses the selected portrait. Stage effects are display-only and leave its Core Pearl untouched. */
function drawNativePresence(x: number, y: number, alpha = 1, spec?: QiMonDrawSpec): void {
  if (!desktopAppearanceImage) return;
  const iosVisual = isIOSFieldArt();
  const stageVisual = iosVisual
    ? visualProfileForStage(spec?.stageName ?? stageForJourney(journey).name) : null;
  const stageScale = stageVisual ? 0.9 + (stageVisual.auraGeometry.radius - 104) / 360 : 1;
  const dimension = clamp(Math.min(width, height) * (mode === "habitat" ? 0.38 : mode === "field" ? 0.22 : 0.30), 90, 310)
    * (spec?.scale ?? 1) * stageScale;
  const bob = reducedMotion ? 0 : Math.sin(animationTime() * 1.5) * dimension * 0.016;
  const actionLift = spec?.motion === "play" && !reducedMotion ? Math.sin(battleImpactPulse * Math.PI) * -12 : 0;
  context.save();
  context.globalAlpha = alpha;
  context.translate(x, y + bob + actionLift);
  if (stageVisual) drawIOSStageHalo(dimension, stageVisual, reducedMotion ? 0 : animationTime());
  if (spec) {
    context.strokeStyle = pearlAccent(ROLES[spec.role].rgb, 0.7);
    context.lineWidth = 1.5;
    context.beginPath(); context.ellipse(0, dimension * 0.31, dimension * 0.40, dimension * 0.10, 0, 0, Math.PI * 2); context.stroke();
  }
  context.drawImage(desktopAppearanceImage, -dimension / 2, -dimension / 2, dimension, dimension);
  context.restore();
}

function battleQiMonPosition(teamId: BattleTeamId): Point {
  return currentBattleEncounterComposition().teams[teamId].active;
}

function currentBattleEncounterComposition() {
  return battleEncounterComposition(width, height, {
    one: battleTeam("one")?.roster.length ?? battleSize("one"),
    two: battleTeam("two")?.roster.length ?? battleSize("two"),
  });
}

function drawBattleBackground(): void {
  drawPearlLandscape(true);
  const qi = isIOSFieldArt();
  const composition = currentBattleEncounterComposition();
  const center = composition.fieldCenter;
  const radiusX = Math.max(80, Math.abs(composition.teams.two.active.x - composition.teams.one.active.x) * 0.68);
  const radiusY = clamp(height * 0.095, 28, 70);
  drawPearlIsland(center.x, center.y + radiusY * 0.45, radiusX, radiusY,
    qi ? "rgba(230,185,96,0.34)" : "rgba(125,98,159,0.3)");

  context.save();
  context.translate(center.x, center.y + radiusY * 0.45);
  context.strokeStyle = qi ? "rgba(133,220,214,0.32)" : "rgba(138,112,172,0.28)";
  context.lineWidth = 1;
  for (let ring = 0; ring < 3; ring += 1) {
    context.beginPath();
    context.ellipse(0, 0, radiusX * (0.27 + ring * 0.17), radiusY * (0.27 + ring * 0.17), 0, 0, Math.PI * 2);
    context.stroke();
  }
  // Inlaid radial marks are scenery, without adding another combat HUD.
  for (let mark = 0; mark < 12; mark += 1) {
    const angle = mark * Math.PI / 6;
    context.beginPath();
    context.moveTo(Math.cos(angle) * radiusX * 0.7, Math.sin(angle) * radiusY * 0.7);
    context.lineTo(Math.cos(angle) * radiusX * 0.76, Math.sin(angle) * radiusY * 0.76);
    context.stroke();
  }
  context.fillStyle = "#fff9ea"; context.strokeStyle = qi ? "#e8b976" : "#b698cb";
  context.beginPath(); context.ellipse(0, 0, 7, 4, 0, 0, Math.PI * 2); context.fill(); context.stroke();
  context.restore();
}

function drawBattleFormationField(
  teamId: BattleTeamId,
  teamComposition: BattleTeamEncounterComposition,
): void {
  const team = battleTeam(teamId);
  if (!team) return;
  const role = ROLES[battleDisplayedQiMon(teamId)?.role ?? team.bondRole];
  drawPearlIsland(teamComposition.ground.x, teamComposition.ground.y,
    teamComposition.ground.radiusX * 1.2, teamComposition.ground.radiusY * 1.22,
    rgba(role.rgb, 0.55));
  context.save();
  context.strokeStyle = "rgba(121,93,158,0.3)";
  context.lineWidth = 1;
  context.setLineDash([2, 6]);
  context.beginPath();
  context.ellipse(
    teamComposition.ground.x,
    teamComposition.ground.y,
    teamComposition.ground.radiusX,
    teamComposition.ground.radiusY,
    0,
    0,
    Math.PI * 2,
  );
  context.stroke();
  context.setLineDash([]);
  for (const reserve of teamComposition.reserves) {
    context.beginPath();
    context.moveTo(teamComposition.ground.x, teamComposition.ground.y);
    context.quadraticCurveTo(
      (teamComposition.ground.x + reserve.x) / 2,
      teamComposition.ground.y + (reserve.y - teamComposition.ground.y) * 0.22,
      reserve.x,
      reserve.y + 28 * reserve.drawScale,
    );
    context.stroke();
  }
  context.restore();
}

function drawBattleReserveProjections(
  teamId: BattleTeamId,
  teamComposition: BattleTeamEncounterComposition,
  stageName: GrowthStageName,
): void {
  const team = battleTeam(teamId);
  const displayed = battleDisplayedQiMon(teamId);
  if (!team || !displayed) return;
  const reserveCards = team.roster.filter((card) => card.id !== displayed.id);
  for (const [index, card] of reserveCards.entries()) {
    const placement = teamComposition.reserves[index];
    if (!placement) continue;
    drawProtoArchi(placement.x, placement.y, card.integrity > 0 ? placement.opacity : 0.2, {
      nativeBody: false,
      role: card.role,
      seed: card.id,
      view: "three-quarter",
      motion: "idle",
      scale: placement.drawScale,
      facing: teamComposition.active.facing,
      careMood: "balanced",
      stageName,
      gazeX: 2.4,
    });
  }
}

function drawBattleExchange(composition: ReturnType<typeof currentBattleEncounterComposition>): void {
  if (reducedMotion || !battleState || battleImpactPulse <= 0) return;
  const lastRound = battleState.history.at(-1);
  if (!lastRound) return;
  const phase = 1 - battleImpactPulse;
  const pointFor = (teamId: BattleTeamId, id: string): Point | undefined => {
    const displayed = battleDisplayedQiMon(teamId);
    const team = battleTeam(teamId);
    if (!displayed || !team) return undefined;
    if (displayed.id === id) return composition.teams[teamId].active;
    const index = team.roster.filter(card => card.id !== displayed.id).findIndex(card => card.id === id);
    return composition.teams[teamId].reserves[index];
  };
  context.save();
  context.globalAlpha = Math.sin(Math.PI * Math.min(0.99, phase)) * 0.8;
  context.lineCap = "round";
  for (const outcome of lastRound.outcomes) {
    const source = pointFor(outcome.teamId, outcome.actorQiMonId);
    if (!source) continue;
    const radius = clamp(Math.min(width, height) * 0.07, 26, 48);
    if (outcome.shieldRaised > 0) {
      context.fillStyle = "rgba(139,116,197,0.09)";
      context.strokeStyle = "rgba(114,82,171,0.85)"; context.lineWidth = 2;
      context.beginPath();
      context.ellipse(source.x, source.y - 12, radius * 1.2, radius * 1.6, 0, 0, Math.PI * 2);
      context.fill(); context.stroke();
    }
    if (outcome.integrityRestored > 0) {
      context.strokeStyle = "rgba(88,142,118,0.9)"; context.lineWidth = 2;
      for (let ring = 0; ring < 2; ring += 1) {
        context.beginPath();
        context.ellipse(source.x, source.y + 22 - phase * 42 - ring * 10, radius * (0.7 + phase * 0.4), radius * 0.3, 0, 0, Math.PI * 2);
        context.stroke();
      }
    }
    if (outcome.damageDealt <= 0) continue;
    const otherTeam = outcome.teamId === "one" ? "two" : "one";
    // Each outcome names its own team's receiver, including a same-round swap.
    const receivingOutcome = lastRound.outcomes.find(entry => entry.teamId === otherTeam);
    if (!receivingOutcome) continue;
    const recipient = pointFor(otherTeam, receivingOutcome.damageRecipientQiMonId);
    if (!recipient) continue;
    const arcHeight = clamp(Math.abs(recipient.x - source.x) * 0.14, 25, 65);
    const beam = context.createLinearGradient(source.x, source.y, recipient.x, recipient.y);
    beam.addColorStop(0, "rgba(137,98,190,0.15)"); beam.addColorStop(0.5, "#fff8e7"); beam.addColorStop(1, "#b486b6");
    context.strokeStyle = beam; context.lineWidth = outcome.action === "signature" ? 5 : 3;
    context.beginPath(); context.moveTo(source.x, source.y - 4);
    context.quadraticCurveTo((source.x + recipient.x) / 2, Math.min(source.y, recipient.y) - arcHeight, recipient.x, recipient.y - 4);
    context.stroke();
    context.strokeStyle = "rgba(148,85,142,0.7)"; context.lineWidth = 1.5;
    context.beginPath(); context.arc(recipient.x, recipient.y - 4, radius * (0.35 + phase * 0.85), 0, Math.PI * 2); context.stroke();
    for (let ray = 0; ray < 6; ray += 1) {
      const angle = ray * Math.PI / 3 + phase * 0.4;
      context.beginPath();
      context.moveTo(recipient.x + Math.cos(angle) * radius * (0.55 + phase), recipient.y - 4 + Math.sin(angle) * radius * (0.55 + phase));
      context.lineTo(recipient.x + Math.cos(angle) * radius * (0.7 + phase), recipient.y - 4 + Math.sin(angle) * radius * (0.7 + phase));
      context.stroke();
    }
  }
  context.restore();
}

function drawBattleArena(): void {
  if (!battleState) {
    context.save();
    context.translate(width / 2, height * 0.53);
    context.strokeStyle = "rgba(213, 164, 81, 0.28)";
    context.setLineDash([4, 9]);
    context.beginPath();
    context.arc(0, 0, Math.min(width, height) * 0.18, 0, Math.PI * 2);
    context.stroke();
    context.restore();
    return;
  }
  const currentStage = stageForJourney(journey).name;
  const composition = currentBattleEncounterComposition();
  // Round feedback is transient and derives only from resolved outcomes.
  drawBattleExchange(composition);
  for (const teamId of BATTLE_TEAM_IDS) {
    const team = battleTeam(teamId);
    const card = battleDisplayedQiMon(teamId);
    if (!team || !card) continue;
    const teamComposition = composition.teams[teamId];
    const position = teamComposition.active;
    const lastAction = battleState.history.at(-1)?.outcomes.find((outcome) => outcome.teamId === teamId)?.action;
    const motion: PresentationMotion = battleImpactPulse <= 0 ? "idle" : lastAction === "guard" ? "focus" : lastAction === "pulse" || lastAction === "signature" ? "play" : "idle";
    const concentrationScale = 1 + team.concentration * 0.07;
    drawBattleFormationField(teamId, teamComposition);
    drawBattleReserveProjections(teamId, teamComposition, currentStage);
    drawProtoArchi(position.x, position.y, card.integrity > 0 ? 1 : 0.35, {
      nativeBody: false,
      role: card.role,
      seed: card.id,
      view: "three-quarter",
      motion,
      scale: teamComposition.active.drawScale * concentrationScale,
      facing: teamComposition.active.facing,
      careMood: "balanced",
      stageName: currentStage,
      gazeX: 3.2,
    });
  }
}

function drawCornerSigils(): void {
  context.save();
  context.strokeStyle = "rgba(115, 88, 151, 0.17)";
  context.lineWidth = 1;
  const margin = 24;
  const size = 42;
  for (const [x, y, sx, sy] of [
    [margin, margin, 1, 1],
    [width - margin, margin, -1, 1],
    [margin, height - margin, 1, -1],
    [width - margin, height - margin, -1, -1],
  ]) {
    context.save();
    context.translate(x, y);
    context.scale(sx, sy);
    context.beginPath();
    context.moveTo(0, size);
    context.lineTo(0, 0);
    context.lineTo(size, 0);
    context.moveTo(8, 28);
    context.lineTo(28, 8);
    context.moveTo(14, 0);
    context.arc(14, 14, 14, -Math.PI / 2, 0);
    context.stroke();
    context.restore();
  }
  context.restore();
}

function render(): void {
  context.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
  context.clearRect(0, 0, width, height);
  if (mode === "battle") {
    drawBattleBackground();
    drawParticles();
    drawBattleArena();
    drawCornerSigils();
    return;
  }
  drawBackground();
  drawFieldEntities();
  drawParticles();
  const companion = currentCompanionPosition();
  drawArchi(companion.x, companion.y);
  drawCornerSigils();
}

function animationFrame(now: number): void {
  animationFrameID = null;
  if (desktopHost && !desktopHost.visible) return;
  const delta = clamp((now - lastFrame) / 1000, 0, 0.05);
  lastFrame = now;
  update(delta);
  render();
  animationFrameID = requestAnimationFrame(animationFrame);
}

let animationFrameID: number | null = null;
const journeyDownloadLeases = createDownloadLeasePool({
  revoke: (url) => URL.revokeObjectURL(url),
  later: (callback, milliseconds) => window.setTimeout(callback, milliseconds),
  cancel: (timer) => window.clearTimeout(timer),
});

function publishDesktopJourney(): void {
  if (!desktopHost || !mainPresentationReady) return;
  desktopHost.publish({
    readiness: "ready", storage: qaMode ? "qa-ephemeral" : storageWriteAvailable ? "local-browser" : "session-only",
    mode, journeyId: journey.id, revision: revisionForJourney(journey), eventCount: journey.events.length,
    originDigest: journeyOriginSha256(journey), practices: savedPracticeSummaries().slice(-8).reverse(), arena: projectArena(),
  });
}

function applyDesktopVisibility(visible: boolean): void {
  keys.clear();
  player.vx = 0;
  player.vy = 0;
  target.x = player.x;
  target.y = player.y;
  // The host can pause presentation, never decide a Journey replacement.
  if (!visible) {
    battleWhatIf = null;
    cancelRelayConfirmation();
    cancelBattleConfirmation();
    desktopInteractions?.invalidate();
    if (continuityIsOpen()) closeContinuity();
    else {
      clearResetReview();
      clearJourneyImportReview(true);
    }
    if (animationFrameID !== null) cancelAnimationFrame(animationFrameID);
    animationFrameID = null;
  } else {
    lastFrame = performance.now();
    refreshCareProjection();
    resizeCanvas();
    if (animationFrameID === null) animationFrameID = requestAnimationFrame(animationFrame);
  }
  element<HTMLElement>("app").inert = !visible;
  publishDesktopJourney();
}

function pointerCoordinates(event: PointerEvent): Point {
  const bounds = canvas.getBoundingClientRect();
  return {
    x: ((event.clientX - bounds.left) / bounds.width) * width,
    y: ((event.clientY - bounds.top) / bounds.height) * height,
  };
}

canvas.addEventListener("pointermove", (event) => {
  if (desktopHost && !desktopHost.visible) return;
  const point = pointerCoordinates(event);
  pointer.x = point.x;
  pointer.y = point.y;
});

canvas.addEventListener("pointerdown", (event) => {
  if (desktopHost && !desktopHost.visible) return;
  const point = pointerCoordinates(event);
  pointer.x = point.x;
  pointer.y = point.y;
  if (mode === "field") {
    target.x = point.x;
    target.y = point.y;
    canvas.setPointerCapture(event.pointerId);
    return;
  }
  if (mode === "battle" || mode === "relay") return;
  const companion = currentCompanionPosition();
  if (Math.hypot(point.x - companion.x, point.y - companion.y) < clamp(Math.min(width, height) * 0.18, 80, 145)) {
    void performCareAction("greet");
  }
});

window.addEventListener("keydown", (event) => {
  if (desktopHost && !desktopHost.visible) return;
  if (!ui.rosterPanel.hidden) {
    if (event.key === "Escape") { event.preventDefault(); closeQiMonRoster(); }
    else if (event.key === "Tab") trapQiMonRosterFocus(event);
    return;
  }
  if (continuityIsOpen()) {
    if (event.key === "Escape") {
      event.preventDefault();
      closeContinuity();
    } else if (event.key === "Tab") {
      trapContinuityFocus(event);
    }
    return;
  }
  const key = event.key.toLowerCase();
  const targetElement = event.target instanceof Element ? event.target : null;
  const interactiveTarget = Boolean(targetElement?.closest("button, a, input, select, textarea, [contenteditable='true']"));
  if (!interactiveTarget && ["arrowleft", "arrowright", "arrowup", "arrowdown", "w", "a", "s", "d"].includes(key)) {
    event.preventDefault();
    keys.add(key);
  }
  if (!interactiveTarget && key === "f" && !event.repeat) {
    event.preventDefault();
    if (document.fullscreenElement) void document.exitFullscreen();
    else void element<HTMLElement>("app").requestFullscreen();
  }
  if (!interactiveTarget && key === "enter" && mode === "habitat") void performCareAction("explore", true);
  else if (!interactiveTarget && key === "enter" && mode === "reflection") playAgain();
  else if (mode === "proposal" && session) {
    if (key === "1") keepChoice(session.proposals[0]);
    if (key === "2") keepChoice(session.proposals[1]);
    if (key === "h") keepChoice("hold");
  }
});

window.addEventListener("keyup", (event) => keys.delete(event.key.toLowerCase()));
window.addEventListener("blur", () => keys.clear());
window.addEventListener("resize", resizeCanvas);
reducedMotionQuery.addEventListener("change", (event) => {
  reducedMotion = event.matches || desktopReduceMotion;
  if (!reducedMotion) return;
  if (presenceSequence.direction !== "settled") {
    presenceSequence = retargetPresenceSequence(presenceSequence, presentationState.form, true);
    updatePresentationInterface();
  }
  presentationPulse = 0;
  battleImpactPulse = 0;
  particles = [];
  render();
});
document.addEventListener("fullscreenchange", resizeCanvas);
document.addEventListener("visibilitychange", () => {
  if (desktopHost) {
    desktopHost.setDocumentVisibility(document.visibilityState === "visible");
    return;
  }
  if (document.visibilityState !== "visible") {
    cancelRelayConfirmation();
    return;
  }
  refreshCareProjection();
  render();
});

for (const button of liminalPortraitButtons) {
  button.addEventListener("click", () => {
    const value = button.dataset.liminalPortrait;
    if (desktopHost || !isPortraitChoice(value) || (value !== "presence" && !liminalPortraits[value])) return;
    portraitChoice = value;
    updatePresentationInterface();
    render();
  });
}
for (const button of presentationFormButtons) {
  button.addEventListener("click", () => {
    const value = button.dataset.presentationForm;
    if (isPresentationForm(value)) applyPresentationAction({ type: "form", value });
  });
}
for (const button of presentationViewButtons) {
  button.addEventListener("click", () => {
    const value = button.dataset.presentationView;
    if (isPresentationView(value)) applyPresentationAction({ type: "view", value });
  });
}
for (const button of presentationMotionButtons) {
  button.addEventListener("click", () => {
    const value = button.dataset.presentationMotion;
    if (isPresentationMotion(value)) applyPresentationAction({ type: "motion", value });
  });
}
for (const button of presentationScaleButtons) {
  button.addEventListener("click", () => {
    const value = button.dataset.presentationScale;
    if (value === "decrease" || value === "reset" || value === "increase") {
      applyPresentationAction({ type: "scale", value });
    }
  });
}
ui.presenceUnfold.addEventListener("click", unfoldPresenceSequence);
ui.presenceReturn.addEventListener("click", () => applyPresentationAction({ type: "return" }));
ui.battleOneSize.addEventListener("change", () => { updateBattleBuilder("one"); publishDesktopJourney(); });
ui.battleTwoSize.addEventListener("change", () => { updateBattleBuilder("two"); publishDesktopJourney(); });
ui.battleOpponentMode.addEventListener("change", () => { updateBattleOpponentMode(); publishDesktopJourney(); });
for (const select of document.querySelectorAll("[data-battle-role-select]")) select.addEventListener("change", publishDesktopJourney);
ui.battleButton.addEventListener("click", openBattleLab);
ui.rosterEntry.addEventListener("click", openQiMonRoster);
ui.rosterClose.addEventListener("click", closeQiMonRoster);
ui.battleRosterReturn.addEventListener("click", openQiMonRoster);
ui.rosterReview.addEventListener("click", () => { cancelQiMonRosterImport(); ui.rosterFile.click(); });
ui.rosterFile.addEventListener("change", () => {
  const file = ui.rosterFile.files?.[0];
  if (file) void reviewQiMonRosterFile(file);
});
ui.rosterImportCancel.addEventListener("click", () => { cancelQiMonRosterImport(); ui.rosterReview.focus(); });
ui.rosterImportConfirm.addEventListener("click", () => void confirmQiMonRosterImport());
ui.battleReturn.addEventListener("click", leaveBattleLab);
ui.relayEntry.addEventListener("click", openRelay);
ui.relayReturn.addEventListener("click", leaveRelay);
ui.relayRestart.addEventListener("click", openRelay);
ui.relayKeep.addEventListener("click", () => void keepRelayCompletion());
ui.battleStart.addEventListener("click", startBattle);
element<HTMLButtonElement>("battle-keep").addEventListener("click", () => { void keepBattleCompletion(); });
ui.battleOneAction.addEventListener("change", () => updateBattleTarget("one"));
ui.battleTwoAction.addEventListener("change", () => updateBattleTarget("two"));
ui.battleOneLock.addEventListener("click", () => lockBattleCommand("one"));
ui.battleTwoLock.addEventListener("click", () => lockBattleCommand("two"));
ui.battleResolve.addEventListener("click", resolveBattle);
ui.battleAgain.addEventListener("click", () => {
  cancelBattleConfirmation();
  battlePracticeBase = null; battleSavedId = null;
  battleState = null;
  battleLockedCommands = {};
  battleLastResult = "Choose both commands";
  updateBattleInterface();
  render();
  ui.battleOneBond.focus();
});

ui.begin.addEventListener("click", () => void performCareAction("explore", true));
ui.careGreet.addEventListener("click", () => void performCareAction("greet"));
ui.careTend.addEventListener("click", () => void performCareAction("tend"));
ui.careRest.addEventListener("click", () => void performCareAction("rest"));
ui.again.addEventListener("click", playAgain);
ui.home.addEventListener("click", () => {
  if (mode === "battle") leaveBattleLab();
  else if (mode === "relay") leaveRelay();
  else abandonToHabitat();
});
ui.hold.addEventListener("click", () => keepChoice("hold"));
ui.continuityButton.addEventListener("click", () => {
  if (ui.continuity.classList.contains("is-open")) closeContinuity();
  else openContinuity();
});
ui.closeContinuity.addEventListener("click", closeContinuity);
ui.scrim.addEventListener("click", closeContinuity);
ui.closeNavigator.addEventListener("click", () => canvas.focus({ preventScroll: true }));
ui.sound.addEventListener("click", () => {
  soundEnabled = !soundEnabled;
  ui.sound.textContent = soundEnabled ? "Sound on" : "Sound off";
  ui.sound.setAttribute("aria-pressed", String(soundEnabled));
  tone(392, 0.1, 0.02);
});
ui.exportJourney.addEventListener("click", downloadJourneyArchive);
ui.reviewJourney.addEventListener("click", () => {
  clearResetReview();
  ui.journeyFile.value = "";
  ui.journeyFile.click();
});
ui.journeyFile.addEventListener("change", () => {
  const file = ui.journeyFile.files?.[0];
  if (file) void reviewJourneyFile(file);
});
ui.cancelJourneyImport.addEventListener("click", () => {
  clearJourneyImportReview();
  setJourneyArchiveStatus("The current Journey was kept.");
  ui.reviewJourney.focus();
});
ui.confirmJourneyImport.addEventListener("click", () => void confirmJourneyImport());
ui.reset.addEventListener("click", () => {
  clearResetReview();
  clearJourneyImportReview(true);
  ui.resetConfirm.hidden = false;
  ui.cancelReset.focus();
});
ui.cancelReset.addEventListener("click", () => {
  clearResetReview();
  ui.reset.focus();
});
async function resetJourney(): Promise<void> {
  if (journeyInputInterlocked) {
    showToast("Reopen ARCHi to finish device setup · Journey unchanged");
    return;
  }
  if (commitInFlight || !continuityIsOpen() || ui.resetConfirm.hidden) return;
  commitInFlight = true;
  const reviewedGeneration = resetReviewGeneration;
  const lockAbort = new AbortController();
  resetLockAbort = lockAbort;
  const resetUnderCurrentLock = (): void => {
    // A queued confirmation does not survive cancellation, a replaced review,
    // a closed panel, or loss of the installed shell's write permission.
    if (
      lockAbort.signal.aborted ||
      reviewedGeneration !== resetReviewGeneration ||
      !continuityIsOpen() ||
      ui.resetConfirm.hidden ||
      journeyInputInterlocked
    ) return;
    journey = qaMode ? createJourney("archi-golden-journey", "2026-08-28T12:00:00.000Z") : createJourney();
    const persisted = writeStoredJourney(journey, true);
    if (persisted) removeLegacyJourneyKeys();
    stars = createStars();
    session = null;
    particles = [];
    ui.resetConfirm.hidden = true;
    closeContinuity();
    setMode("habitat");
    refreshCareProjection("A new ARCHi has hatched with a fresh care rhythm.");
    updateContinuity();
    updateFieldInterface();
    showToast(
      persisted || qaMode
        ? "A new local journey has hatched"
        : "New journey hatched for this session · local save unavailable",
    );
  };

  try {
    if (!qaMode && navigator.locks) {
      await navigator.locks.request(JOURNEY_LOCK_NAME, { signal: lockAbort.signal }, resetUnderCurrentLock);
    } else {
      resetUnderCurrentLock();
    }
  } catch (error) {
    if (!(error instanceof DOMException && error.name === "AbortError")) {
      showToast("Reset lock unavailable · Journey kept");
    }
  } finally {
    if (resetLockAbort === lockAbort) resetLockAbort = null;
    commitInFlight = false;
  }
}

ui.confirmReset.addEventListener("click", () => void resetJourney());

window.render_game_to_text = () => {
  const stage = stageForJourney(journey);
  const visualProfile = visualProfileForStage(stage.name);
  const plays = playHistory(journey);
  const careEvents = careHistory(journey);
  const ledgerHead = journey.events.at(-1);
  const ledgerTail = journey.events.slice(-LEDGER_TAIL_LIMIT).map((event) =>
    event.kind === "care-action"
      ? {
          schema: event.schema,
          sequence: event.sequence,
          eventId: event.eventId,
          previousEventId: event.previousEventId,
          committedAt: event.committedAt,
          kind: event.kind,
          action: event.action,
        }
      : event.kind === "activity-complete" ? {
          schema: event.schema,
          sequence: event.sequence,
          eventId: event.eventId,
          previousEventId: event.previousEventId,
          committedAt: event.committedAt,
          kind: event.kind,
          activityId: event.activityId,
          rulesVersion: event.rulesVersion,
          sessionId: event.sessionId,
          actions: event.actions,
        } : event.kind === "practice-complete" ? { ...event } : {
          schema: event.schema,
          sequence: event.sequence,
          eventId: event.eventId,
          previousEventId: event.previousEventId,
          committedAt: event.committedAt,
          kind: event.kind,
          play: event.play,
          sessionId: event.sessionId,
          fieldName: event.fieldName,
          choice: event.choice,
          signals: [...event.signals],
          generator: event.generator,
        },
  );
  const currentHeadId = ledgerHead?.eventId ?? null;
  const currentRevision = revisionForJourney(journey);
  const qimonRosterReadback = (() => {
    const schema = "archi-qimon-roster-readback/v1";
    const journeySaved = readPrimaryStorageSnapshot();
    const journeyBytesMatchMemory = !qaMode && journeySaved.status === "present"
      && journeySaved.digest === sha256String(serializeJourney(journey));
    let savedRoster: string | null = null;
    let rosterReadable = true;
    if (!qaMode) {
      try { savedRoster = window.localStorage.getItem(ROSTER_STORAGE_KEY); }
      catch { rosterReadable = false; }
    }
    const rosterBytesMatchBaseline = !qaMode && rosterReadable && savedRoster !== null
      && rosterStorageBaseline !== null && savedRoster === rosterStorageBaseline;
    const basePersistence = {
      journeyBytesMatchMemory,
      rosterBytesMatchBaseline,
      readbackVerified: false,
    };
    const unavailable = (issue: string | null) => ({
      schema, availability: issue ? "paused" : "absent", issue,
      originDigest: null, revision: null, eventCount: null, head: null,
      persistence: { ...basePersistence, status: qaMode ? "qa-ephemeral"
        : !rosterReadable ? "unreadable" : savedRoster === null ? "missing" : "unvalidated" },
      members: [], pairs: [], selectedTeamMemberIds: [],
    });
    if (!roster) return unavailable(rosterIssue);
    let projection: QiMonRosterProjection;
    try { projection = projectQiMonRoster(journey, roster); }
    catch (error) {
      return unavailable(error instanceof Error ? error.message : "The QiMon roster did not replay against this Journey.");
    }
    let archiveReplays = false;
    if (rosterBytesMatchBaseline && savedRoster !== null) {
      const inspected = inspectQiMonRoster(savedRoster, journey);
      archiveReplays = inspected.status === "valid"
        && JSON.stringify(inspected.roster) === JSON.stringify(roster);
    }
    const readbackVerified = journeyBytesMatchMemory && rosterBytesMatchBaseline && archiveReplays;
    const persistence = {
      journeyBytesMatchMemory, rosterBytesMatchBaseline, readbackVerified,
      status: qaMode ? "qa-ephemeral" : !rosterReadable ? "unreadable"
        : savedRoster === null ? "missing" : !rosterBytesMatchBaseline ? "changed"
          : !archiveReplays ? "invalid" : !journeyBytesMatchMemory ? "journey-not-current" : "verified",
    };
    const head = roster.events.at(-1);
    return {
      schema,
      availability: rosterIssue || (!qaMode && !readbackVerified) ? "paused" : "available",
      issue: rosterIssue ?? (!qaMode && !readbackVerified ? "Saved Journey or QiMon roster needs review." : null),
      originDigest: roster.originDigest,
      revision: projection.revision,
      eventCount: roster.events.length,
      head: head ? { sequence: head.sequence, eventId: head.eventId,
        previousEventId: head.previousEventId, recordedAt: head.recordedAt,
        journeyEventCount: head.journeyEventCount, journeyHeadEventId: head.journeyHeadEventId,
        actionKind: head.action.kind } : null,
      persistence,
      members: projection.members.map((member) => ({ id: member.id, role: member.card.role,
        sourceEventId: member.sourceEventId, invitationEventId: member.invitationEventId,
        trainingTier: member.trainingTier, trainingEventIds: [...member.trainingEventIds] })),
      pairs: projection.bonds.map((pair) => ({ memberIds: [...pair.memberIds],
        sourceEventId: pair.sourceEventId, bondEventId: pair.bondEventId })),
      selectedTeamMemberIds: projection.team.map((member) => member.id),
    };
  })();
  const persistedHeadIsAncestor =
    persistedEventCount !== null &&
    (persistedEventCount === 0
      ? persistedRevision === revisionForJourney({ ...journey, events: [] })
      : journey.events[persistedEventCount - 1]?.eventId === persistedHeadId);
  const unsavedEventCount = qaMode
    ? null
    : persistedRevision === currentRevision
      ? 0
      : persistedEventCount === null || !persistedHeadIsAncestor
      ? journey.events.length
      : Math.max(0, journey.events.length - persistedEventCount);
  const visibleEchoes = session
    ? session.echoes
        .filter((echo) => !session!.collected.includes(echo.id))
        .map((echo) => {
          const point = echoPosition(echo);
          return {
            id: echo.id,
            aura: echo.aura,
            role: echo.role,
            x: Math.round(point.x),
            y: Math.round(point.y),
          };
        })
    : [];
  const staticZones = session
    ? session.staticZones.map((zone) => {
        const point = staticPosition(zone);
        return {
          id: zone.id,
          x: Math.round(point.x),
          y: Math.round(point.y),
          radius: Math.round(zone.radius * Math.min(width, height)),
        };
      })
    : [];
  const presentationMix = presenceMix(presenceSequence.position);
  const presentationRig = protoVisualRigForView(presentationState.view, visualProfile);
  const habitatComposition = habitatEncounterComposition(width, height);
  const battleComposition = mode === "battle" ? currentBattleEncounterComposition() : null;
  const diagnosticBattleId = battleState?.battleId;
  const battlePracticeReceipt = diagnosticBattleId ? savedPracticeSummaries().find((entry) => entry.battleId === diagnosticBattleId) ?? null : null;
  const selectedPortrait = currentLiminalPortrait();
  return JSON.stringify({
    coordinateSystem: "CSS pixels; origin top-left; +x right; +y down",
    viewport: { width: Math.round(width), height: Math.round(height) },
    mode,
    presentation: {
      owner: desktopHost ? "native-companion" : "presentation-study",
      portrait: selectedPortrait,
      portraitStyle: selectedPortrait ? LIMINAL_LIGHT_STYLE : null,
      portraitReady: selectedPortrait !== null && (liminalPortraits[selectedPortrait]?.naturalWidth ?? 0) > 0,
      ...presentationState,
      form: presentationMix.phase,
      targetForm: presentationState.form,
      label: presentationLabel({ ...presentationState, form: presentationMix.phase }),
      targetLabel: presentationLabel(presentationState),
      sequence: {
        phase: presentationMix.phase,
        position: Math.round(presenceSequence.position * 1000) / 1000,
        targetPosition: presenceSequence.targetPosition,
        direction: presenceSequence.direction,
        settled: presenceSequence.direction === "settled",
        weights: presentationMix.weights,
        fieldAmount: Math.round(presentationMix.fieldAmount * 1000) / 1000,
        petalAmount: Math.round(presentationMix.petalAmount * 1000) / 1000,
        bodyReveal: Math.round(presentationMix.bodyReveal * 1000) / 1000,
        contextAmount: Math.round(presentationMix.contextAmount * 1000) / 1000,
      },
      rig: {
        schemaVersion: presentationRig.schemaVersion,
        view: presentationRig.view,
        silhouette: presentationRig.silhouette,
        nearSide: presentationRig.nearSide,
        farSide: presentationRig.farSide,
        body: presentationRig.body,
        head: presentationRig.head,
        face: {
          kind: presentationRig.face.kind,
          visible: presentationRig.face.visible,
          visibleEyes: presentationRig.face.eyes.filter((eye) => eye.visible).map((eye) => eye.side),
        },
        core: {
          ...presentationRig.core.visual,
          shellTransmission: presentationRig.core.shellTransmission,
          occludedByShell: presentationRig.core.occludedByShell,
        },
        dorsalSeam: presentationRig.dorsalSeam,
        occlusion: presentationRig.occlusion,
        appendages: presentationRig.appendages.map((appendage) => ({
          id: appendage.id,
          visible: appendage.visible,
          opacity: appendage.opacity,
          depth: appendage.depth,
          x: appendage.x,
          y: appendage.y,
        })),
        depthOrder: presentationRig.depthOrder,
        persistence: "none",
        authority: "visual-only",
      },
      visible: mode === "habitat",
      persistence: "none",
      authority: "visual-only",
    },
    relay: mode === "relay" && relayAttempt ? {
      activityId: relayAttempt.activityId,
      phase: relayAttempt.state.phase,
      protectedSteps: relayAttempt.state.protectedSteps,
      readTransmissionIds: relayAttempt.state.readTransmissionIds,
      selectedTransmissionId: relayAttempt.state.selectedTransmissionId,
      acceptedSteps: relayAttempt.actions.length,
      baseRevision: relayAttempt.baseRevision,
      completedInJourney: deriveActivityMilestones(journey).some((entry) => entry.activityId === "broken-relay"),
      confirmationPending: Boolean(relayLockAbort),
      feedback: ui.relayFeedback.textContent,
      saveStatus: ui.relayKeepCopy.hidden ? null : ui.relayKeepCopy.textContent,
    } : null,
    activityMilestones: deriveActivityMilestones(journey),
    battle: battleState
      ? {
          ...battleState,
          revision: battleRevision(battleState),
          sealedCommands: {
            one: Boolean(battleLockedCommands.one),
            two: Boolean(battleLockedCommands.two),
          },
          commandPolicy: battleOpponentMode === "companion" ? "public-state-practice-partner" : "local-pass-and-play-seal",
          opponentMode: battleOpponentMode,
          visible: mode === "battle",
          limits: BATTLE_LIMITS,
          visualRig: {
            schemaVersion: protoVisualRigForView("three-quarter", visualProfile).schemaVersion,
            view: "three-quarter",
            renderer: "shared-drawProtoArchi",
            rendererByPlacement: {
              playerOneActive: "shared-drawProtoArchi",
              opponentActive: "shared-drawProtoArchi",
              reserves: "shared-drawProtoArchi",
            },
            encounterComposition: battleComposition,
            displayedQiMonIds: {
              one: battleDisplayedQiMon("one")?.id ?? null,
              two: battleDisplayedQiMon("two")?.id ?? null,
            },
          },
          persistence: battlePracticeReceipt ? qaMode ? "qa-session-replay-receipt" : "journey-v5-replay-receipt" : "none",
          network: "none",
          authority: battlePracticeReceipt ? "replay-verified-practice-receipt" : "simulation-only",
          journeyEffects: battlePracticeReceipt ? "practice-receipt-only" : "none",
          keptPractice: battlePracticeReceipt,
          rewards: { care: false, stats: false },
        }
      : null,
    battleSetup:
      mode === "battle" && !battleState
        ? {
            opponentMode: battleOpponentMode,
            teams: battleSetupReadback(),
            limits: BATTLE_LIMITS,
            composition: battleComposition,
            persistence: "none",
            network: "none",
            authority: "setup-only",
          }
        : null,
    encounterComposition: {
      schemaVersion: ENCOUNTER_COMPOSITION_VERSION,
      habitat: {
        ...habitatComposition,
        visible: mode === "habitat",
      },
      battle: battleComposition,
      persistence: "none",
      authority: "visual-only",
    },
    journey: {
      version: journey.version,
      revision: currentRevision,
      originDigest: journeyOriginSha256(journey),
      id: journey.id,
      play: journey.plays + 1,
      completedPlays: journey.plays,
      stage: stage.name,
      bond: journey.bond,
      expression: journey.expression,
      dominantRole: dominantRole(journey),
      affinities: journey.affinities,
      keptTraceCount: plays.length,
      ledger: {
        eventCount: journey.events.length,
        playEventCount: plays.length,
        careEventCount: careEvents.length,
        head: ledgerHead
          ? {
              sequence: ledgerHead.sequence,
              eventId: ledgerHead.eventId,
              kind: ledgerHead.kind,
              committedAt: ledgerHead.committedAt,
            }
          : null,
        provenance: journey.provenance,
        tailLimit: LEDGER_TAIL_LIMIT,
        tailStartSequence: ledgerTail.at(0)?.sequence ?? null,
        tail: ledgerTail,
        persistence: {
          persistedEventCount: qaMode ? null : persistedEventCount,
          persistedHeadId: qaMode ? null : persistedHeadId,
          persistedRevision: qaMode ? null : persistedRevision,
          snapshotVerified: qaMode ? null : storageWriteAvailable,
          persistedHeadIsAncestor: qaMode ? null : persistedHeadIsAncestor,
          unsavedEventCount,
          hasUnpersistedRevision: qaMode ? null : !storageWriteAvailable || persistedRevision !== currentRevision,
          currentHeadPersisted:
            qaMode
              ? null
              : storageWriteAvailable &&
                persistedRevision === currentRevision &&
                persistedEventCount === journey.events.length &&
                persistedHeadId === currentHeadId,
        },
      },
      care: {
        energy: careProjection.energy,
        calm: careProjection.calm,
        curiosity: careProjection.curiosity,
        mood: careProjection.mood,
        elapsedHours: careProjection.elapsedHours,
        keptTraceCount: careEvents.length,
        lastAction: careEvents.at(-1)?.action ?? null,
        canonicalUpdatedAt: journey.care.updatedAt,
      },
      core: { identity: journey.core.identity, authority: journey.core.authority },
      storage: qaMode ? "qa-ephemeral" : storageWriteAvailable ? "local-browser" : "session-only",
    },
    qimonRoster: qimonRosterReadback,
    companion: {
      nativeAppearance: desktopHost ? { id: desktopAppearanceID, ready: desktopAppearanceImage !== null, renderer: "CompanionPresenceArt" } : null,
      ...currentCompanionPosition(),
      vx: Math.round(player.vx),
      vy: Math.round(player.vy),
      fieldComposure: Math.round(fieldComposure),
      growthVisual: {
        tier: visualProfile.tier,
        silhouette: visualProfile.silhouette,
        motion: visualProfile.motion,
        aura: visualProfile.aura,
        reducedMotion,
        corePearl: visualProfile.corePearl,
      },
    },
    session: session
      ? {
          id: session.id,
          baseRevision: session.baseRevision,
          fieldName: session.fieldName,
          signalsRequired: 3,
          collected: session.collected.map((id) => session!.echoes.find((echo) => echo.id === id)?.aura),
          proposals: session.proposals,
          visibleEchoes,
          staticZones,
          ambientSparksRemaining: session.sparks.length - collectedSparks.size,
        }
      : null,
    portability: {
      importReview: pendingJourneyImport
        ? {
            candidateId: pendingJourneyImport.preview.journeyId,
            candidateRevision: pendingJourneyImport.preview.revision,
            eventCount: pendingJourneyImport.preview.eventCount,
            relation: pendingJourneyImport.relation,
            requiresWrite: pendingJourneyImport.requiresWrite,
          }
        : null,
      status: ui.journeyArchiveStatus.textContent,
    },
    deviceShell: deviceShellSnapshot(),
    inputGuard: {
      blocked: journeyInputInterlocked,
      reason: journeyInputInterlocked ? "installed-shell-pending" : null,
    },
    controls: {
      care: CARE_ACTION_ORDER,
      move: ["WASD", "arrow keys", "click/tap target"],
      fullscreen: "F",
      proposal: "buttons or 1/2; H holds current expression",
      battle: BATTLE_ACTIONS,
    },
  });
};

window.advanceTime = (milliseconds: number) => {
  if (desktopHost && !desktopHost.visible) return;
  const steps = Math.min(1200, Math.max(1, Math.round(milliseconds / (1000 / 60))));
  for (let index = 0; index < steps; index += 1) update(1 / 60);
  render();
};

updateContinuity();
updateFieldInterface();
updateCareInterface(journeyWasMigrated ? "Your earlier journey is intact. ARCHi’s care rhythm now has its own replayable history." : undefined);
updatePresentationInterface();
initializeBattleControls();
resizeCanvas();
setMode("habitat");
mainPresentationReady = true;
applyJourneyInputInterlock(deviceShellSnapshot());
document.documentElement.classList.add("archi-ready");
if (!storageWriteAvailable && !qaMode) showToast("Local save unavailable · this journey is temporary");
if (desktopHost) {
  desktopHost.onAppearanceChange((appearance) => {
    const request = ++desktopAppearanceRequest;
    desktopReduceMotion = appearance.reduceMotion;
    reducedMotion = reducedMotionQuery.matches || desktopReduceMotion;
    const next = new Image();
    next.onload = () => {
      if (request !== desktopAppearanceRequest) return;
      desktopAppearanceImage = next;
      desktopAppearanceID = appearance.id;
      render();
    };
    next.src = appearance.png;
  });
  // Inert blocks real input; capture also rejects delayed native controls and synthetic clicks while hidden.
  for (const type of ["click", "change", "submit"] as const) {
    document.addEventListener(type, (event) => {
      if (desktopHost.visible) return;
      event.preventDefault();
      event.stopImmediatePropagation();
    }, true);
  }
  desktopHost.onArenaAction(performArenaAction);
  desktopHost.onVisibilityChange(applyDesktopVisibility);
  publishDesktopJourney();
} else {
  animationFrameID = requestAnimationFrame(animationFrame);
}
window.addEventListener("pagehide", () => {
  journeyDownloadLeases.dispose();
  if (desktopHost) {
    desktopHost.setDocumentVisibility(false);
    desktopHost.dispose();
  }
}, { once: true });
