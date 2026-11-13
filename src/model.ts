import { sha256 } from "@noble/hashes/sha2.js";
import { replayCompletedPractice, type PracticeReplay } from "./battle-engine";
import {
  createBrokenRelayState,
  transitionBrokenRelay,
  type BrokenRelayEvent,
  type BrokenRelayState,
} from "./companion-activities/broken-relay";

export const ROLE_ORDER = ["hearth", "muse", "scout", "beacon", "keeper", "guardian"] as const;

export type RoleId = (typeof ROLE_ORDER)[number];

export type AuraId =
  | "importance"
  | "danger"
  | "opportunity"
  | "memory"
  | "repair"
  | "unknown"
  | "truth"
  | "simulation"
  | "relationship";

export interface RoleDefinition {
  id: RoleId;
  title: string;
  shortTitle: string;
  form: string;
  purpose: string;
  promise: string;
  hue: string;
  rgb: [number, number, number];
  glyph: string;
}

export const ROLES: Record<RoleId, RoleDefinition> = {
  hearth: {
    id: "hearth",
    title: "Home · Hearth",
    shortTitle: "Hearth",
    form: "Fen",
    purpose: "Notice rhythms and make room for care.",
    promise: "Suggest, then wait for confirmation.",
    hue: "#f2bb58",
    rgb: [242, 187, 88],
    glyph: "✦",
  },
  muse: {
    id: "muse",
    title: "Studio · Muse",
    shortTitle: "Muse",
    form: "Pop",
    purpose: "Spark drafts and playful possibilities.",
    promise: "Drafts remain drafts until reviewed.",
    hue: "#f06eaa",
    rgb: [240, 110, 170],
    glyph: "✧",
  },
  scout: {
    id: "scout",
    title: "Research · Scout",
    shortTitle: "Scout",
    form: "Lumen",
    purpose: "Surface patterns and test what is true.",
    promise: "Evidence stays attached to claims.",
    hue: "#54d9ed",
    rgb: [84, 217, 237],
    glyph: "⌾",
  },
  beacon: {
    id: "beacon",
    title: "Journey · Beacon",
    shortTitle: "Beacon",
    form: "Veil",
    purpose: "Keep direction without choosing the route.",
    promise: "The player always chooses the way.",
    hue: "#b6c7d7",
    rgb: [182, 199, 215],
    glyph: "⌁",
  },
  keeper: {
    id: "keeper",
    title: "Archive · Keeper",
    shortTitle: "Keeper",
    form: "Relic",
    purpose: "Preserve the traces the player keeps.",
    promise: "No silent memory writes.",
    hue: "#e69b3a",
    rgb: [230, 155, 58],
    glyph: "◇",
  },
  guardian: {
    id: "guardian",
    title: "Guardian · Hold",
    shortTitle: "Guardian",
    form: "Frame",
    purpose: "Notice risk and protect the pause.",
    promise: "Warn or hold; never act alone.",
    hue: "#ef765f",
    rgb: [239, 118, 95],
    glyph: "⬡",
  },
};

export const AURAS: Record<AuraId, { label: string; color: string; roleBias: RoleId }> = {
  importance: { label: "Importance", color: "#f2c15f", roleBias: "hearth" },
  danger: { label: "Danger", color: "#ff695b", roleBias: "guardian" },
  opportunity: { label: "Opportunity", color: "#71df7b", roleBias: "muse" },
  memory: { label: "Memory", color: "#56a9ff", roleBias: "keeper" },
  repair: { label: "Repair", color: "#f29b51", roleBias: "hearth" },
  unknown: { label: "Unknown", color: "#b979ff", roleBias: "beacon" },
  truth: { label: "Verified truth", color: "#55e7e2", roleBias: "scout" },
  simulation: { label: "Simulation", color: "#9e79ef", roleBias: "muse" },
  relationship: { label: "Relationship", color: "#f493bb", roleBias: "hearth" },
};

export const AURA_ORDER = Object.keys(AURAS) as AuraId[];

export const CORE_CONTINUITY = Object.freeze({
  identity: "ARCHi",
  origin: "Arbitration · Reason · Codex · Hampton interphase",
  values: Object.freeze(["care", "honesty", "bounded help"]),
  consent: "player-led",
  authority: "propose-only",
});

export const CARE_ACTION_ORDER = ["greet", "tend", "rest", "explore"] as const;

export type CareActionId = (typeof CARE_ACTION_ORDER)[number];
export type CareMood = "bright" | "balanced" | "curious" | "resting" | "unsettled";
export type PlayGeneratorId = "branching" | "legacy";

export interface CareState {
  energy: number;
  calm: number;
  curiosity: number;
  updatedAt: string;
}

export interface CareProjection extends CareState {
  elapsedHours: number;
  mood: CareMood;
}

export interface CareTrace {
  id: string;
  sequence: number;
  action: CareActionId;
  actedAt: string;
}

export interface CareIntent {
  action: CareActionId;
  baseRevision: string;
}

export const CARE_ACTIONS: Record<
  CareActionId,
  { label: string; shortDescription: string; delta: Pick<CareState, "energy" | "calm" | "curiosity"> }
> = {
  greet: {
    label: "Greet",
    shortDescription: "Connect",
    delta: { energy: 2, calm: 10, curiosity: 4 },
  },
  tend: {
    label: "Tend",
    shortDescription: "Restore energy",
    delta: { energy: 12, calm: 16, curiosity: -4 },
  },
  rest: {
    label: "Rest",
    shortDescription: "Settle calm",
    delta: { energy: 28, calm: 8, curiosity: 6 },
  },
  explore: {
    label: "Explore",
    shortDescription: "Follow curiosity",
    delta: { energy: -14, calm: -4, curiosity: -24 },
  },
};

export interface KeptTrace {
  id: string;
  play: number;
  keptAt: string;
  fieldName: string;
  choice: RoleId | "hold";
  signals: AuraId[];
  generator: PlayGeneratorId;
}

interface JourneyEventBase {
  schema: 2;
  sequence: number;
  eventId: string;
  previousEventId: string;
  committedAt: string;
}

export interface CareActionEvent extends JourneyEventBase {
  kind: "care-action";
  action: CareActionId;
}

export interface PlayCommitEvent extends JourneyEventBase {
  kind: "play-commit";
  play: number;
  sessionId: string;
  fieldName: string;
  choice: RoleId | "hold";
  signals: AuraId[];
  generator: PlayGeneratorId;
}

export type RelayAction = Readonly<Extract<BrokenRelayEvent, { type: "START" | "REDIRECT" | "INSPECT" | "RESOLVE" }>>;

export interface RelayAttempt {
  readonly activityId: "broken-relay";
  readonly rulesVersion: 1;
  readonly baseRevision: string;
  readonly sessionId: string;
  /** Accepted progress steps, not a complete interaction history. At most eight. */
  readonly actions: readonly RelayAction[];
  readonly state: BrokenRelayState;
}

export interface ActivityCompleteEvent extends Omit<JourneyEventBase, "schema"> {
  readonly schema: 3;
  readonly kind: "activity-complete";
  readonly activityId: "broken-relay";
  readonly rulesVersion: 1;
  readonly sessionId: string;
  readonly actions: readonly RelayAction[];
}

export interface ActivityMilestone {
  readonly id: "game:broken-relay:restored";
  readonly activityId: "broken-relay";
  readonly rulesVersion: 1;
  readonly title: string;
  readonly text: string;
  readonly eventId: string;
  readonly committedAt: string;
}

export interface PracticeAttempt {
  readonly originDigest: string;
  readonly baseRevision: string;
  readonly sessionId: string;
  readonly replay: PracticeReplay;
}

export interface PracticeCompleteEvent extends Omit<JourneyEventBase, "schema">, PracticeAttempt {
  readonly schema: 4;
  readonly kind: "practice-complete";
}

export interface PracticeSummary {
  readonly originDigest: string;
  readonly eventId: string;
  readonly battleId: string;
  readonly rulesVersion: 1;
  readonly rounds: number;
  readonly outcome: "won" | "lost" | "draw";
  readonly replayDigest: string;
  readonly committedAt: string;
}

export const MAX_KEPT_PRACTICES = 64;
export type JourneyEvent = CareActionEvent | PlayCommitEvent | ActivityCompleteEvent | PracticeCompleteEvent;

export type JourneyProvenance =
  | {
      source: "native-v3";
      ordering: "native";
      ambiguousEqualTimeTies: 0;
      sourceDigest: "native";
    }
  | {
      source: "migrated-v1";
      ordering: "source-order";
      ambiguousEqualTimeTies: 0;
      migratedEventCount: number;
      sourceDigest: string;
    }
  | {
      source: "migrated-v2";
      ordering: "timestamp-play-before-care";
      ambiguousEqualTimeTies: number;
      migratedEventCount: number;
      sourceDigest: string;
    };

export interface Journey {
  version: 3 | 4 | 5;
  id: string;
  seed: string;
  createdAt: string;
  updatedAt: string;
  plays: number;
  bond: number;
  expression: RoleId;
  affinities: Record<RoleId, number>;
  careStartedAt: string;
  care: CareState;
  provenance: JourneyProvenance;
  events: JourneyEvent[];
  core: typeof CORE_CONTINUITY;
}

/** An inspectable view of an existing local individual, never a writable identity record. */
export interface JourneyPassport {
  readonly schema: "archi-journey-passport/v1";
  readonly instanceID: string;
  readonly displayJourneyID: string;
  readonly createdAt: string;
  readonly status: "local-only";
  readonly coreProfile: Readonly<{ id: "archi-core-continuity"; version: 1 }>;
  readonly journeyRevision: string;
}

export type GrowthStageName = "Hatchling" | "Young" | "Adolescent" | "Mature" | "Advanced";

export interface FieldEcho {
  id: string;
  aura: AuraId;
  role: RoleId;
  x: number;
  y: number;
  phase: number;
}

export interface StaticZone {
  id: string;
  x: number;
  y: number;
  radius: number;
  phase: number;
}

export interface FieldSpark {
  id: string;
  x: number;
  y: number;
  phase: number;
}

export interface PlaySession {
  id: string;
  seed: number;
  play: number;
  baseRevision: string;
  fieldName: string;
  echoes: FieldEcho[];
  staticZones: StaticZone[];
  sparks: FieldSpark[];
  collected: string[];
  proposals: RoleId[];
}

const FIELD_FIRST = ["Opal", "Quiet", "Luminous", "Drifting", "Kindled", "Hidden", "Tender", "Silver"];
const FIELD_SECOND = ["Garden", "Archive", "Crossing", "Canopy", "Orbit", "Hollow", "Threshold", "Tide"];

function emptyAffinities(): Record<RoleId, number> {
  return {
    hearth: 0,
    muse: 0,
    scout: 0,
    beacon: 0,
    keeper: 0,
    guardian: 0,
  };
}

export function hashString(value: string): number {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

export function sha256String(value: string): string {
  return [...sha256(new TextEncoder().encode(value))].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function seededRandom(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state += 0x6d2b79f5;
    let value = state;
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

function randomSeed(): string {
  const bytes = new Uint32Array(2);
  crypto.getRandomValues(bytes);
  return `${bytes[0].toString(36)}-${bytes[1].toString(36)}`;
}

const NATIVE_PROVENANCE: JourneyProvenance = Object.freeze({
  source: "native-v3",
  ordering: "native",
  ambiguousEqualTimeTies: 0,
  sourceDigest: "native",
});

function createJourneyWithCareOrigin(
  seed: string,
  createdAt: string,
  careStartedAt: string,
  provenance: JourneyProvenance = NATIVE_PROVENANCE,
): Journey {
  return {
    version: 3,
    id: `ARCHI-${hashString(seed).toString(16).toUpperCase().padStart(8, "0")}`,
    seed,
    createdAt,
    updatedAt: createdAt,
    plays: 0,
    bond: 1,
    expression: "scout",
    affinities: emptyAffinities(),
    careStartedAt,
    care: initialCare(careStartedAt),
    provenance,
    events: [],
    core: CORE_CONTINUITY,
  };
}

export function createJourney(seed = randomSeed(), now = new Date().toISOString()): Journey {
  return createJourneyWithCareOrigin(seed, now, now);
}

function isRole(value: unknown): value is RoleId {
  return typeof value === "string" && ROLE_ORDER.includes(value as RoleId);
}

function isAura(value: unknown): value is AuraId {
  return typeof value === "string" && Object.prototype.hasOwnProperty.call(AURAS, value);
}

function isIsoTimestamp(value: unknown): value is string {
  if (typeof value !== "string") return false;
  const milliseconds = Date.parse(value);
  return Number.isFinite(milliseconds) && new Date(milliseconds).toISOString() === value;
}

function isCareAction(value: unknown): value is CareActionId {
  return typeof value === "string" && CARE_ACTION_ORDER.includes(value as CareActionId);
}

function clampNeed(value: number, minimum: number, maximum = 100): number {
  return Math.max(minimum, Math.min(maximum, Math.round(value)));
}

export function initialCare(at: string): CareState {
  return {
    energy: 80,
    calm: 75,
    curiosity: 50,
    updatedAt: at,
  };
}

export function careMood(care: Pick<CareState, "energy" | "calm" | "curiosity">): CareMood {
  if (care.energy <= 48) return "resting";
  if (care.calm <= 56) return "unsettled";
  if (care.curiosity >= 76) return "curious";
  if (care.energy >= 86 && care.calm >= 82 && care.curiosity <= 66) return "bright";
  return "balanced";
}

export function projectCare(care: CareState, now: string): CareProjection {
  if (!isIsoTimestamp(care.updatedAt) || !isIsoTimestamp(now)) {
    throw new Error("Care projection requires canonical timestamps.");
  }
  const elapsedHours = Math.min(
    24,
    Math.max(0, Math.floor((Date.parse(now) - Date.parse(care.updatedAt)) / 3_600_000)),
  );
  const energyFloor = Math.min(care.energy, 40);
  const calmFloor = Math.min(care.calm, 50);
  const curiosityCeiling = Math.max(care.curiosity, 90);
  const projection = {
    energy: clampNeed(care.energy - elapsedHours * 2, energyFloor),
    calm: clampNeed(care.calm - elapsedHours, calmFloor),
    curiosity: clampNeed(care.curiosity + elapsedHours * 2, 0, curiosityCeiling),
    updatedAt: care.updatedAt,
  };
  return { ...projection, elapsedHours, mood: careMood(projection) };
}

function monotonicTimestamp(previous: string, requested: string): string {
  return Date.parse(requested) >= Date.parse(previous)
    ? requested
    : new Date(Date.parse(previous) + 1).toISOString();
}

function legacyCareTraceId(
  seed: string,
  careStartedAt: string,
  previousTraceId: string,
  sequence: number,
  action: CareActionId,
  actedAt: string,
): string {
  const digest = hashString(
    `${seed}:care:${careStartedAt}:${previousTraceId}:${sequence}:${action}:${actedAt}`,
  );
  return `care-${sequence}-${digest.toString(16).padStart(8, "0")}`;
}

function applyCareDelta(care: CareState, action: CareActionId, actedAt: string): CareState {
  const projected = projectCare(care, actedAt);
  const delta = CARE_ACTIONS[action].delta;
  return {
    energy: clampNeed(projected.energy + delta.energy, 10),
    calm: clampNeed(projected.calm + delta.calm, 10),
    curiosity: clampNeed(projected.curiosity + delta.curiosity, 0),
    updatedAt: actedAt,
  };
}

type JourneyEventPayload =
  | (PracticeAttempt & { kind: "practice-complete" })
  | { kind: "care-action"; action: CareActionId }
  | {
      kind: "activity-complete";
      activityId: "broken-relay";
      rulesVersion: 1;
      sessionId: string;
      actions: readonly RelayAction[];
    }
  | {
      kind: "play-commit";
      play: number;
      sessionId: string;
      fieldName: string;
      choice: RoleId | "hold";
      signals: AuraId[];
      generator: PlayGeneratorId;
    };

function provenanceTuple(provenance: JourneyProvenance): readonly unknown[] {
  return [
    provenance.source,
    provenance.ordering,
    provenance.ambiguousEqualTimeTies,
    "migratedEventCount" in provenance ? provenance.migratedEventCount : 0,
    provenance.sourceDigest,
  ];
}

function parseJourneyProvenance(value: unknown): JourneyProvenance | null {
  if (!value || typeof value !== "object") return null;
  const candidate = value as Partial<JourneyProvenance> & { migratedEventCount?: unknown };
  if (
    candidate.source === "native-v3" &&
    candidate.ordering === "native" &&
    candidate.ambiguousEqualTimeTies === 0 &&
    candidate.sourceDigest === "native"
  ) {
    return NATIVE_PROVENANCE;
  }
  if (
    candidate.source === "migrated-v1" &&
    candidate.ordering === "source-order" &&
    candidate.ambiguousEqualTimeTies === 0 &&
    Number.isSafeInteger(candidate.migratedEventCount) &&
    Number(candidate.migratedEventCount) >= 0 &&
    typeof candidate.sourceDigest === "string" &&
    /^[0-9a-f]{64}$/.test(candidate.sourceDigest)
  ) {
    return {
      source: candidate.source,
      ordering: candidate.ordering,
      ambiguousEqualTimeTies: 0,
      migratedEventCount: Number(candidate.migratedEventCount),
      sourceDigest: candidate.sourceDigest,
    };
  }
  if (
    candidate.source === "migrated-v2" &&
    candidate.ordering === "timestamp-play-before-care" &&
    Number.isSafeInteger(candidate.ambiguousEqualTimeTies) &&
    Number(candidate.ambiguousEqualTimeTies) >= 0 &&
    Number.isSafeInteger(candidate.migratedEventCount) &&
    Number(candidate.migratedEventCount) >= 0 &&
    typeof candidate.sourceDigest === "string" &&
    /^[0-9a-f]{64}$/.test(candidate.sourceDigest)
  ) {
    return {
      source: candidate.source,
      ordering: candidate.ordering,
      ambiguousEqualTimeTies: Number(candidate.ambiguousEqualTimeTies),
      migratedEventCount: Number(candidate.migratedEventCount),
      sourceDigest: candidate.sourceDigest,
    };
  }
  return null;
}

function originEventId(journey: Pick<Journey, "seed" | "createdAt" | "careStartedAt" | "provenance">): string {
  const digest = sha256String(
    JSON.stringify([
      "journey-v3-origin",
      journey.seed,
      journey.createdAt,
      journey.careStartedAt,
      ...provenanceTuple(journey.provenance),
    ]),
  );
  return `origin-${digest}`;
}

function eventPayloadTuple(payload: JourneyEventPayload): readonly unknown[] {
  if (payload.kind === "practice-complete") {
    return [payload.kind, payload.originDigest, payload.baseRevision, payload.sessionId, payload.replay];
  }
  if (payload.kind === "activity-complete") {
    return [payload.kind, payload.activityId, payload.rulesVersion, payload.sessionId, payload.actions.map(relayActionTuple)];
  }
  return payload.kind === "care-action"
    ? [payload.kind, payload.action]
    : [
        payload.kind,
        payload.play,
        payload.sessionId,
        payload.fieldName,
        payload.choice,
        payload.signals,
        payload.generator,
      ];
}

function eventHeadId(journey: Journey): string {
  return journey.events.at(-1)?.eventId ?? originEventId(journey);
}

function journeyEventId(
  previousEventId: string,
  sequence: number,
  committedAt: string,
  payload: JourneyEventPayload,
): string {
  const digest = sha256String(
    JSON.stringify([
      payload.kind === "practice-complete" ? "journey-event-v4" : payload.kind === "activity-complete" ? "journey-event-v3" : "journey-event-v2",
      previousEventId,
      sequence,
      committedAt,
      ...eventPayloadTuple(payload),
    ]),
  );
  return `event-${sequence}-${digest}`;
}

export function playHistory(journey: Journey): PlayCommitEvent[] {
  return journey.events.filter((event): event is PlayCommitEvent => event.kind === "play-commit");
}

export function careHistory(journey: Journey): CareActionEvent[] {
  return journey.events.filter((event): event is CareActionEvent => event.kind === "care-action");
}

const EVENT_BASE_KEYS = ["schema", "kind", "sequence", "eventId", "previousEventId", "committedAt"];
export const MAX_RELAY_RECEIPT_ACTIONS = 8;
const RELAY_ACTIONS: readonly RelayAction[] = [
  { type: "START" },
  { type: "REDIRECT", node: 1 }, { type: "REDIRECT", node: 2 }, { type: "REDIRECT", node: 3 },
  { type: "INSPECT", id: "A" }, { type: "INSPECT", id: "B" }, { type: "INSPECT", id: "C" },
  { type: "RESOLVE", id: "A" }, { type: "RESOLVE", id: "B" }, { type: "RESOLVE", id: "C" },
];

function plainDataRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value && typeof value === "object" && Object.getPrototypeOf(value) === Object.prototype &&
    Reflect.ownKeys(value).every((key) => typeof key === "string") &&
    Object.values(Object.getOwnPropertyDescriptors(value)).every((descriptor) => "value" in descriptor));
}

function exactDataRecord(value: unknown, keys: readonly string[]): value is Record<string, unknown> {
  return plainDataRecord(value) && Reflect.ownKeys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key));
}

function denseDataArray(value: unknown): value is unknown[] {
  if (!Array.isArray(value) || Object.getPrototypeOf(value) !== Array.prototype) return false;
  const keys = Reflect.ownKeys(value);
  return keys.length === value.length + 1 &&
    Array.from({ length: value.length }, (_, index) => String(index)).every((key) =>
      Object.hasOwn(value, key) && "value" in Object.getOwnPropertyDescriptor(value, key)!);
}

function isRelaySessionId(value: unknown): value is string {
  return typeof value === "string" && /^[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}$/.test(value);
}

function canonicalRelayAction(value: unknown): RelayAction {
  if (!plainDataRecord(value)) throw new Error("Relay steps must contain plain data.");
  if (value.type === "START" && exactDataRecord(value, ["type"])) return Object.freeze({ type: "START" });
  if (value.type === "REDIRECT" && exactDataRecord(value, ["type", "node"]) &&
      (value.node === 1 || value.node === 2 || value.node === 3)) {
    return Object.freeze({ type: "REDIRECT", node: value.node });
  }
  if ((value.type === "INSPECT" || value.type === "RESOLVE") && exactDataRecord(value, ["type", "id"]) &&
      (value.id === "A" || value.id === "B" || value.id === "C")) {
    return Object.freeze({ type: value.type, id: value.id });
  }
  throw new Error("Unknown Relay activity step.");
}

function relayActionTuple(action: RelayAction): readonly unknown[] {
  return action.type === "START" ? [action.type] : action.type === "REDIRECT" ? [action.type, action.node] : [action.type, action.id];
}

function madeRelayProgress(before: BrokenRelayState, after: BrokenRelayState): boolean {
  return before.phase !== after.phase || before.protectedSteps !== after.protectedSteps ||
    before.readTransmissionIds.length !== after.readTransmissionIds.length;
}

function freezeRelayState(state: BrokenRelayState): BrokenRelayState {
  return Object.freeze({ ...state, readTransmissionIds: Object.freeze([...state.readTransmissionIds]) });
}

function replayRelayActions(value: unknown): { actions: readonly RelayAction[]; state: BrokenRelayState } {
  if (!Array.isArray(value) || value.length > MAX_RELAY_RECEIPT_ACTIONS || !denseDataArray(value)) {
    throw new Error("A Relay receipt contains at most eight accepted puzzle steps.");
  }
  const actions: RelayAction[] = [];
  let state = createBrokenRelayState();
  for (const raw of value) {
    const action = canonicalRelayAction(raw);
    const next = transitionBrokenRelay(state, action);
    if (!madeRelayProgress(state, next)) throw new Error("A Relay receipt may contain only accepted progress steps.");
    actions.push(action);
    state = next;
  }
  return { actions: Object.freeze(actions), state: freezeRelayState(state) };
}

function relayStateTuple(state: BrokenRelayState): readonly unknown[] {
  return [state.phase, state.protectedSteps, state.readTransmissionIds, state.selectedTransmissionId, state.feedback, state.adaptation];
}

function canonicalRelayAttempt(value: RelayAttempt): RelayAttempt {
  if (!exactDataRecord(value, ["activityId", "rulesVersion", "baseRevision", "sessionId", "actions", "state"]) ||
      value.activityId !== "broken-relay" || value.rulesVersion !== 1 || !isRelaySessionId(value.sessionId) ||
      typeof value.baseRevision !== "string" || value.baseRevision.length === 0 || value.baseRevision.length > 1024) {
    throw new Error("This Relay attempt has no valid Journey/session binding.");
  }
  const receipt = replayRelayActions(value.actions);
  const state = value.state;
  if (!exactDataRecord(state, ["phase", "protectedSteps", "readTransmissionIds", "selectedTransmissionId", "feedback", "adaptation"]) ||
      typeof state.phase !== "string" || typeof state.protectedSteps !== "number" ||
      !Array.isArray(state.readTransmissionIds) || state.readTransmissionIds.length > 3 || !denseDataArray(state.readTransmissionIds) ||
      !state.readTransmissionIds.every((id) => id === "A" || id === "B" || id === "C") ||
      !(state.selectedTransmissionId === null || state.selectedTransmissionId === "A" || state.selectedTransmissionId === "B" || state.selectedTransmissionId === "C") ||
      typeof state.feedback !== "string" || state.feedback.length > 512 || state.adaptation !== "BASE") {
    throw new Error("This Relay attempt contains an invalid puzzle projection.");
  }
  // A wrong choice or reselection changes only feedback/selection. Retain that
  // source behavior without saving it as accepted progress or limiting retries.
  const possibleStates = [receipt.state, ...RELAY_ACTIONS.map((action) => transitionBrokenRelay(receipt.state, action))
    .filter((next) => !madeRelayProgress(receipt.state, next))];
  const canonicalState = possibleStates.find((candidate) =>
    JSON.stringify(relayStateTuple(candidate)) === JSON.stringify(relayStateTuple(state)));
  if (!canonicalState) throw new Error("This Relay projection does not match its accepted steps.");
  return Object.freeze({
    activityId: "broken-relay", rulesVersion: 1, baseRevision: value.baseRevision, sessionId: value.sessionId,
    actions: receipt.actions, state: freezeRelayState(canonicalState),
  });
}

export function createRelayAttempt(journey: Journey, sessionId: string): RelayAttempt {
  if (!isRelaySessionId(sessionId)) throw new Error("A Relay attempt requires a bounded session identifier.");
  const canonical = canonicalJourneyForCommit(journey);
  return Object.freeze({
    activityId: "broken-relay", rulesVersion: 1, baseRevision: revisionForJourney(canonical), sessionId,
    actions: Object.freeze([]), state: freezeRelayState(createBrokenRelayState()),
  });
}

export function advanceRelayAttempt(attempt: RelayAttempt, action: RelayAction): RelayAttempt {
  const canonical = canonicalRelayAttempt(attempt);
  const step = canonicalRelayAction(action);
  const next = transitionBrokenRelay(canonical.state, step);
  const actions = madeRelayProgress(canonical.state, next) ? Object.freeze([...canonical.actions, step]) : canonical.actions;
  return Object.freeze({ ...canonical, actions, state: freezeRelayState(next) });
}

export function commitRelayCompletion(
  journey: Journey,
  attempt: RelayAttempt,
  expectedSessionId: string,
  now = new Date().toISOString(),
): Journey {
  const canonical = canonicalJourneyForCommit(journey);
  const reviewed = canonicalRelayAttempt(attempt);
  if (!isRelaySessionId(expectedSessionId) || reviewed.sessionId !== expectedSessionId) {
    throw new Error("This Relay session has ended or changed.");
  }
  if (replayRelayActions(reviewed.actions).state.phase !== "RESTORED") throw new Error("Complete the Relay before keeping its receipt.");
  if (!isIsoTimestamp(now)) throw new Error("A Relay completion requires a canonical timestamp.");
  const previous = canonical.events.find((event): event is ActivityCompleteEvent => event.kind === "activity-complete");
  if (reviewed.baseRevision !== revisionForJourney(canonical)) {
    // Repeating the exact completed command is harmless, including after a later
    // care/play event. A different stale attempt must still be reviewed again.
    if (previous && previous.sessionId === reviewed.sessionId &&
        reviewed.baseRevision === `${canonical.id}:${previous.sequence - 1}:${previous.previousEventId}` &&
        JSON.stringify(previous.actions.map(relayActionTuple)) === JSON.stringify(reviewed.actions.map(relayActionTuple))) return journey;
    throw new Error("This Relay completion is stale because the Journey changed.");
  }
  if (previous) return journey;
  return commitJourneyOperation(canonical, {
    kind: "activity-complete", activityId: "broken-relay", rulesVersion: 1, sessionId: reviewed.sessionId, actions: reviewed.actions,
  }, now);
}

/** Explicit Keep uses the same Journey admission boundary as care, field and Relay. */
export function commitPracticeCompletion(journey: Journey, attempt: PracticeAttempt, expectedSessionId: string,
  now = new Date().toISOString()): Journey {
  const canonical = canonicalJourneyForCommit(journey);
  if (!exactDataRecord(attempt, ["originDigest", "baseRevision", "sessionId", "replay"]) ||
      attempt.originDigest !== journeyOriginSha256(canonical) || attempt.sessionId !== expectedSessionId ||
      !/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(attempt.sessionId) || !isIsoTimestamp(now)) {
    throw new Error("This practice no longer belongs to the current Journey/session.");
  }
  const verified = replayCompletedPractice(attempt.replay);
  const previous = canonical.events.find((event): event is PracticeCompleteEvent =>
    event.kind === "practice-complete" && event.replay.battleId === verified.replay.battleId);
  if (previous) {
    if (previous.sessionId === attempt.sessionId && previous.baseRevision === attempt.baseRevision &&
        JSON.stringify(previous.replay) === JSON.stringify(verified.replay)) return journey;
    throw new Error("A different completion already uses this practice ID.");
  }
  if (attempt.baseRevision !== revisionForJourney(canonical)) throw new Error("The Journey changed. Start a fresh practice before keeping another result.");
  return commitJourneyOperation(canonical, { kind: "practice-complete", originDigest: attempt.originDigest,
    baseRevision: attempt.baseRevision, sessionId: attempt.sessionId, replay: verified.replay }, now);
}

/** Derived solely by replaying saved events, not by trusting displayed outcome totals. */
export function derivePracticeSummaries(journey: Journey): readonly PracticeSummary[] {
  return Object.freeze(journey.events.filter((event): event is PracticeCompleteEvent => event.kind === "practice-complete")
    .map((event): PracticeSummary => {
      const verified = replayCompletedPractice(event.replay);
      return Object.freeze({ originDigest: event.originDigest, eventId: event.eventId, battleId: event.replay.battleId,
        rulesVersion: 1, rounds: verified.state.history.length,
        outcome: verified.state.winner === "one" ? "won" : verified.state.winner === "two" ? "lost" : "draw",
        replayDigest: verified.digest, committedAt: event.committedAt });
    }));
}

export function deriveActivityMilestones(journey: Journey): readonly ActivityMilestone[] {
  return Object.freeze(journey.events.filter((event): event is ActivityCompleteEvent => event.kind === "activity-complete")
    .map((event): ActivityMilestone => Object.freeze({
      id: "game:broken-relay:restored", activityId: "broken-relay", rulesVersion: 1,
      title: "Broken Relay restored",
      text: "Protected the relay through nodes 2 → 1 → 3, inspected all three transmissions, and identified B as contradicting the field log.",
      eventId: event.eventId, committedAt: event.committedAt,
    })));
}

/** Full original Journey origin fingerprint; activity upgrades do not mint an identity. */
export function journeyOriginSha256(journey: Journey): string {
  return originEventId(journey).slice("origin-".length);
}

export function deriveJourneyPassport(journey: Journey): JourneyPassport {
  const canonical = canonicalJourneyForCommit(journey);
  return Object.freeze({
    schema: "archi-journey-passport/v1",
    instanceID: originEventId(canonical),
    displayJourneyID: canonical.id,
    createdAt: canonical.createdAt,
    status: "local-only",
    coreProfile: Object.freeze({ id: "archi-core-continuity", version: 1 }),
    journeyRevision: revisionForJourney(canonical),
  });
}

export function serializeJourney(journey: Journey): string {
  return JSON.stringify({
    version: journey.version,
    seed: journey.seed,
    createdAt: journey.createdAt,
    careStartedAt: journey.careStartedAt,
    provenance: journey.provenance,
    events: journey.events,
  });
}

function makeJourneyEvent(journey: Journey, payload: JourneyEventPayload, requestedAt: string): JourneyEvent {
  if (!isIsoTimestamp(requestedAt)) throw new Error("A journey event requires a canonical timestamp.");
  const committedAt = monotonicTimestamp(journey.updatedAt, requestedAt);
  const sequence = journey.events.length + 1;
  const previousEventId = eventHeadId(journey);
  const eventId = journeyEventId(previousEventId, sequence, committedAt, payload);
  const base = { schema: 2 as const, sequence, eventId, previousEventId, committedAt };
  const event: JourneyEvent =
    payload.kind === "practice-complete" ? Object.freeze({ ...base, ...payload, schema: 4 as const })
      : payload.kind === "activity-complete"
      ? Object.freeze({ ...base, schema: 3 as const, ...payload, actions: replayRelayActions(payload.actions).actions })
      : payload.kind === "care-action"
      ? { ...base, kind: payload.kind, action: payload.action }
      : {
          ...base,
          kind: payload.kind,
          play: payload.play,
          sessionId: payload.sessionId,
          fieldName: payload.fieldName,
          choice: payload.choice,
          signals: [...payload.signals],
          generator: payload.generator,
        };
  return event;
}

function appendJourneyEvent(journey: Journey, payload: JourneyEventPayload, requestedAt: string): Journey {
  return reduceJourneyEvent(journey, makeJourneyEvent(journey, payload, requestedAt));
}

/** Owner-created evidence for one already authorized action; never a permission token. */
export interface JourneyTransitionContract {
  readonly schema: "archi-journey-transition/v1";
  readonly originDigest: string;
  readonly baseRevision: string;
  readonly beforeAuthority: string;
  readonly expectedEvent: string;
}

export interface JourneyTransitionCheck {
  readonly id: "contract" | "snapshot" | "identity" | "history" | "requested-effect" | "scope" | "replay" | "projection";
  readonly status: "PASS" | "FAIL" | "ERROR";
}

/** Reject accessors/cycles without executing them during the postcondition check. */
function continuityData(value: unknown, ancestors = new Set<object>(), depth = 0): boolean {
  if (value === null || typeof value === "string" || typeof value === "boolean") return true;
  if (typeof value === "number") return Number.isFinite(value);
  if (typeof value !== "object" || depth > 32 || ancestors.has(value)) return false;
  const isArray = Array.isArray(value);
  if (isArray ? !denseDataArray(value) : !plainDataRecord(value)) return false;
  ancestors.add(value);
  const result = Object.values(Object.getOwnPropertyDescriptors(value)).every((descriptor) =>
    "value" in descriptor && continuityData(descriptor.value, ancestors, depth + 1));
  ancestors.delete(value);
  return result;
}

function journeyProjectionTuple(journey: Journey): readonly unknown[] {
  return [journey.version, journey.id, journey.seed, journey.createdAt, journey.updatedAt,
    journey.plays, journey.bond, journey.expression, ROLE_ORDER.map((role) => journey.affinities[role]),
    journey.careStartedAt, journey.care, provenanceTuple(journey.provenance), journey.core];
}

/**
 * A synchronous semantic guard in the current Journey owner. It derives every
 * check itself, accepts no submitted PASS flags, and writes no state. Persistence,
 * browser locks, cancellation and explicit user review remain in the caller.
 * Replay shares the production reducer; scope/effect checks are separate checks,
 * not an independent implementation or a quantum fault-tolerance claim.
 */
export function verifyJourneyTransition(
  before: Journey, candidate: Journey, contract: JourneyTransitionContract,
): Readonly<{ accepted: boolean; checks: readonly JourneyTransitionCheck[] }> {
  return verifyJourneyTransitionWithBase(before, candidate, contract);
}

function verifyJourneyTransitionWithBase(
  before: Journey, candidate: Journey, contract: JourneyTransitionContract, validatedOriginal?: Journey,
): Readonly<{ accepted: boolean; checks: readonly JourneyTransitionCheck[] }> {
  const checks: JourneyTransitionCheck[] = [];
  const check = (id: JourneyTransitionCheck["id"], predicate: () => boolean): void => {
    let status: JourneyTransitionCheck["status"];
    try { status = predicate() ? "PASS" : "FAIL"; }
    catch { status = "ERROR"; }
    checks.push(Object.freeze({ id, status }));
  };
  let inputsAreData = false;
  let original: Journey | null = null;
  let expected: JourneyEvent | null = null;
  let replayed: Journey | null = null;
  check("contract", () => {
    inputsAreData = continuityData(before) && continuityData(candidate) && continuityData(contract);
    if (!inputsAreData || !exactDataRecord(contract, ["schema", "originDigest", "baseRevision", "beforeAuthority", "expectedEvent"]) ||
        contract.schema !== "archi-journey-transition/v1" || typeof contract.originDigest !== "string" ||
        typeof contract.baseRevision !== "string" || typeof contract.beforeAuthority !== "string" ||
        typeof contract.expectedEvent !== "string") return false;
    const authority = JSON.parse(contract.beforeAuthority);
    original = validatedOriginal ?? hydrateJourney(authority);
    expected = JSON.parse(contract.expectedEvent) as JourneyEvent;
    return original !== null && original.events.length === authority.events.length && continuityData(expected) &&
      ["care-action", "play-commit", "activity-complete", "practice-complete"].includes(expected.kind);
  });
  const bound = (): boolean => inputsAreData && checks[0]?.status === "PASS" && original !== null && expected !== null;
  check("snapshot", () => bound() && serializeJourney(before) === contract.beforeAuthority &&
    revisionForJourney(before) === contract.baseRevision && journeyOriginSha256(before) === contract.originDigest &&
    JSON.stringify(journeyProjectionTuple(before)) === JSON.stringify(journeyProjectionTuple(original!)));
  check("identity", () => bound() && journeyOriginSha256(candidate) === contract.originDigest &&
    candidate.id === original!.id && JSON.stringify(candidate.core) === JSON.stringify(CORE_CONTINUITY));
  check("history", () => bound() && candidate.events.length === original!.events.length + 1 &&
    JSON.stringify(candidate.events.slice(0, -1)) === JSON.stringify(original!.events));
  check("requested-effect", () => bound() && JSON.stringify(candidate.events.at(-1)) === contract.expectedEvent);
  check("scope", () => {
    if (!bound() || !exactDataRecord(candidate, ["version", "id", "seed", "createdAt", "updatedAt", "plays", "bond",
        "expression", "affinities", "careStartedAt", "care", "provenance", "events", "core"]) ||
        !exactDataRecord(candidate.affinities, ROLE_ORDER) ||
        !exactDataRecord(candidate.care, ["energy", "calm", "curiosity", "updatedAt"])) return false;
    const kind = expected!.kind;
    const unchanged = (keys: readonly (keyof Journey)[]): boolean =>
      keys.every((key) => JSON.stringify(candidate[key]) === JSON.stringify(original![key]));
    return unchanged(["id", "seed", "createdAt", "careStartedAt", "provenance", "core"]) &&
      (kind === "care-action" || unchanged(["care"])) &&
      (kind === "play-commit" || unchanged(["plays", "bond", "expression", "affinities"])) &&
      ((kind === "activity-complete" || kind === "practice-complete") || unchanged(["version"]));
  });
  check("replay", () => {
    if (!bound() || checks.find((entry) => entry.id === "history")?.status !== "PASS") return false;
    // Induction over the verified prefix: unchanged old events plus one checked
    // new event verifies the complete chain without replaying every old battle.
    replayed = replayJourneyEvent(original!, candidate.events.at(-1), candidate.version >= 4, candidate.version === 5);
    return replayed !== null && replayed.events.length === candidate.events.length &&
      serializeJourney(replayed) === serializeJourney(candidate);
  });
  check("projection", () => bound() && replayed !== null &&
    JSON.stringify(journeyProjectionTuple(candidate)) === JSON.stringify(journeyProjectionTuple(replayed)));
  return Object.freeze({ accepted: checks.every((entry) => entry.status === "PASS"), checks: Object.freeze(checks) });
}

function commitJourneyOperation(journey: Journey, payload: JourneyEventPayload, requestedAt: string): Journey {
  // Every caller has already obtained this base from canonicalJourneyForCommit.
  // A detached copy preserves its projections even if a faulty reducer mutates
  // the input. This proof is private; submitted data cannot mark itself verified.
  const validatedOriginal = structuredClone(journey);
  const event = makeJourneyEvent(journey, payload, requestedAt);
  // Capture immutable values before the reducer runs. Neither an altered event
  // nor a mutation of the supplied base can rewrite this operation's contract.
  const contract: JourneyTransitionContract = Object.freeze({
    schema: "archi-journey-transition/v1", originDigest: journeyOriginSha256(journey),
    baseRevision: revisionForJourney(journey), beforeAuthority: serializeJourney(journey), expectedEvent: JSON.stringify(event),
  });
  const candidate = reduceJourneyEvent(journey, event);
  const result = verifyJourneyTransitionWithBase(journey, candidate, contract, validatedOriginal);
  if (!result.accepted) {
    throw new Error(`Journey continuity check did not pass: ${result.checks.filter((entry) => entry.status !== "PASS").map((entry) => entry.id).join(", ")}.`);
  }
  return candidate;
}

function reduceJourneyEvent(journey: Journey, event: JourneyEvent): Journey {
  if (
    event.sequence !== journey.events.length + 1 ||
    event.previousEventId !== eventHeadId(journey) ||
    Date.parse(event.committedAt) < Date.parse(journey.updatedAt)
  ) {
    throw new Error("Journey events must form one monotonic chain.");
  }
  if (event.kind === "practice-complete") {
    if (event.originDigest !== journeyOriginSha256(journey) || event.baseRevision !== revisionForJourney(journey) ||
        !/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(event.sessionId) ||
        journey.events.some((prior) => prior.kind === "practice-complete" && prior.replay.battleId === event.replay.battleId) ||
        journey.events.filter((prior) => prior.kind === "practice-complete").length >= MAX_KEPT_PRACTICES) {
      throw new Error("The practice is stale, repeated, or this Journey's practice limit is reached.");
    }
    replayCompletedPractice(event.replay);
    return { ...journey, version: 5, updatedAt: event.committedAt, events: [...journey.events, event], core: CORE_CONTINUITY };
  }
  if (event.kind === "care-action") {
    if (Date.parse(event.committedAt) < Date.parse(journey.care.updatedAt)) {
      throw new Error("A care event cannot precede the care origin.");
    }
    return {
      ...journey,
      updatedAt: event.committedAt,
      care: applyCareDelta(journey.care, event.action, event.committedAt),
      events: [...journey.events, event],
      core: CORE_CONTINUITY,
    };
  }
  if (event.kind === "activity-complete") {
    if (event.activityId !== "broken-relay" || event.rulesVersion !== 1 ||
        replayRelayActions(event.actions).state.phase !== "RESTORED" ||
        journey.events.some((prior) => prior.kind === "activity-complete" && prior.activityId === event.activityId)) {
      throw new Error("A Relay completion requires one complete, previously unkept activity receipt.");
    }
    return { ...journey, version: journey.version === 5 ? 5 : 4, updatedAt: event.committedAt, events: [...journey.events, event], core: CORE_CONTINUITY };
  }
  return applyPlayCommitEvent(journey, event);
}

function replayJourneyEvent(journey: Journey, value: unknown, allowActivity = false, allowPractice = false): Journey | null {
  if (!value || typeof value !== "object") return null;
  if (allowActivity && !plainDataRecord(value)) return null;
  const candidate = value as Partial<JourneyEvent>;
  if (
    (candidate.schema !== 2 && !(allowActivity && candidate.schema === 3 && candidate.kind === "activity-complete") && !(allowPractice && candidate.schema === 4 && candidate.kind === "practice-complete")) ||
    candidate.sequence !== journey.events.length + 1 ||
    candidate.previousEventId !== eventHeadId(journey) ||
    !isIsoTimestamp(candidate.committedAt) ||
    Date.parse(candidate.committedAt) < Date.parse(journey.updatedAt) ||
    typeof candidate.eventId !== "string"
  ) {
    return null;
  }

  let payload: JourneyEventPayload;
  if (candidate.kind === "care-action") {
    if (candidate.schema !== 2 || !isCareAction(candidate.action) ||
        (allowActivity && !exactDataRecord(candidate, [...EVENT_BASE_KEYS, "action"]))) return null;
    payload = { kind: candidate.kind, action: candidate.action };
  } else if (candidate.kind === "play-commit") {
    if (
      candidate.schema !== 2 ||
      (allowActivity && !exactDataRecord(candidate, [...EVENT_BASE_KEYS, "play", "sessionId", "fieldName", "choice", "signals", "generator"])) ||
      typeof candidate.play !== "number" ||
      !Number.isSafeInteger(candidate.play) ||
      typeof candidate.sessionId !== "string" ||
      typeof candidate.fieldName !== "string" ||
      (candidate.choice !== "hold" && !isRole(candidate.choice)) ||
      !Array.isArray(candidate.signals) ||
      candidate.signals.length !== 3 ||
      (allowActivity && !denseDataArray(candidate.signals)) ||
      !candidate.signals.every(isAura) ||
      new Set(candidate.signals).size !== candidate.signals.length ||
      (candidate.generator !== "branching" && candidate.generator !== "legacy")
    ) {
      return null;
    }
    payload = {
      kind: candidate.kind,
      play: candidate.play,
      sessionId: candidate.sessionId,
      fieldName: candidate.fieldName,
      choice: candidate.choice,
      signals: [...candidate.signals],
      generator: candidate.generator,
    };
  } else if (candidate.kind === "practice-complete") {
    if (!allowPractice || candidate.schema !== 4 || !exactDataRecord(candidate, [...EVENT_BASE_KEYS,
        "originDigest", "baseRevision", "sessionId", "replay"]) || typeof candidate.originDigest !== "string" ||
        typeof candidate.baseRevision !== "string" || typeof candidate.sessionId !== "string") return null;
    try {
      const verified = replayCompletedPractice(candidate.replay);
      payload = { kind: "practice-complete", originDigest: candidate.originDigest, baseRevision: candidate.baseRevision,
        sessionId: candidate.sessionId, replay: verified.replay };
    } catch { return null; }
  } else if (candidate.kind === "activity-complete") {
    if (!allowActivity || candidate.schema !== 3 ||
        !exactDataRecord(candidate, [...EVENT_BASE_KEYS, "activityId", "rulesVersion", "sessionId", "actions"]) ||
        candidate.activityId !== "broken-relay" || candidate.rulesVersion !== 1 || !isRelaySessionId(candidate.sessionId)) return null;
    try {
      const receipt = replayRelayActions(candidate.actions);
      if (receipt.state.phase !== "RESTORED") return null;
      payload = { kind: "activity-complete", activityId: "broken-relay", rulesVersion: 1, sessionId: candidate.sessionId, actions: receipt.actions };
    } catch {
      return null;
    }
  } else {
    return null;
  }

  const expectedId = journeyEventId(
    candidate.previousEventId,
    candidate.sequence,
    candidate.committedAt,
    payload,
  );
  if (candidate.eventId !== expectedId) return null;
  const base = {
    schema: 2 as const,
    sequence: candidate.sequence,
    eventId: expectedId,
    previousEventId: candidate.previousEventId,
    committedAt: candidate.committedAt,
  };
  const canonical: JourneyEvent =
    payload.kind === "practice-complete" ? Object.freeze({ ...base, ...payload, schema: 4 as const })
      : payload.kind === "activity-complete"
      ? Object.freeze({ ...base, ...payload, schema: 3 as const })
      : payload.kind === "care-action"
      ? { ...base, kind: payload.kind, action: payload.action }
      : { ...base, ...payload, signals: [...payload.signals] };
  try {
    return reduceJourneyEvent(journey, canonical);
  } catch {
    return null;
  }
}

export function createCareIntent(journey: Journey, action: CareActionId): CareIntent {
  if (!isCareAction(action)) throw new Error("Unknown care action.");
  return { action, baseRevision: revisionForJourney(journey) };
}

export function commitCareAction(
  journey: Journey,
  intent: CareIntent,
  now = new Date().toISOString(),
): Journey {
  if (!isCareAction(intent.action)) throw new Error("Unknown care action.");
  const canonicalJourney = canonicalJourneyForCommit(journey);
  if (intent.baseRevision !== revisionForJourney(canonicalJourney)) {
    throw new Error("This care choice is stale because the journey changed.");
  }
  if (!isIsoTimestamp(now)) throw new Error("A care choice requires a canonical timestamp.");

  return commitJourneyOperation(canonicalJourney, { kind: "care-action", action: intent.action }, now);
}

function replayLegacyCareTrace(
  seed: string,
  careStartedAt: string,
  care: CareState,
  accepted: CareTrace[],
  value: unknown,
): { care: CareState; trace: CareTrace } | null {
  if (!value || typeof value !== "object") return null;
  const trace = value as Partial<CareTrace>;
  const sequence = accepted.length + 1;
  if (
    trace.sequence !== sequence ||
    !isCareAction(trace.action) ||
    !isIsoTimestamp(trace.actedAt) ||
    Date.parse(trace.actedAt) < Date.parse(care.updatedAt)
  ) {
    return null;
  }
  const expectedId = legacyCareTraceId(
    seed,
    careStartedAt,
    accepted.at(-1)?.id ?? "origin",
    sequence,
    trace.action,
    trace.actedAt,
  );
  if (trace.id !== expectedId) return null;
  const canonical: CareTrace = {
    id: expectedId,
    sequence,
    action: trace.action,
    actedAt: trace.actedAt,
  };
  return { care: applyCareDelta(care, canonical.action, canonical.actedAt), trace: canonical };
}

function legacySourceDigest(
  version: 1 | 2,
  careStartedAt: string,
  plays: PlayCommitEvent[],
  careTraces: CareTrace[],
): string {
  return sha256String(
    JSON.stringify([
      `v${version}`,
      careStartedAt,
      plays.map((event) => [
        event.play,
        event.sessionId,
        event.committedAt,
        event.fieldName,
        event.choice,
        event.signals,
        event.generator,
      ]),
      careTraces.map((trace) => [trace.id, trace.sequence, trace.action, trace.actedAt]),
    ]),
  );
}

function countAmbiguousCrossLaneTies(plays: PlayCommitEvent[], careTraces: CareTrace[]): number {
  const playCounts = new Map<string, number>();
  for (const play of plays) playCounts.set(play.committedAt, (playCounts.get(play.committedAt) ?? 0) + 1);
  let count = 0;
  for (const care of careTraces) count += playCounts.get(care.actedAt) ?? 0;
  return count;
}

function migrateLegacyJourney(value: unknown): Journey | null {
  if (!value || typeof value !== "object") return null;
  const candidate = value as {
    version?: unknown;
    seed?: unknown;
    createdAt?: unknown;
    traces?: unknown;
    careStartedAt?: unknown;
    careTraces?: unknown;
  };
  if (
    (candidate.version !== 1 && candidate.version !== 2) ||
    typeof candidate.seed !== "string" ||
    candidate.seed.length === 0
  ) {
    return null;
  }

  if (!isIsoTimestamp(candidate.createdAt)) return null;
  const createdAt = candidate.createdAt;
  let playProjection = createJourney(candidate.seed, createdAt);
  if (Array.isArray(candidate.traces)) {
    for (const trace of candidate.traces) {
      const replayed = replayLegacyPlayTrace(playProjection, trace, candidate.version === 1);
      if (!replayed) break;
      playProjection = replayed;
    }
  }

  const plays = playHistory(playProjection);

  if (candidate.version === 1) {
    const careStartedAt = playProjection.updatedAt;
    const provenance: JourneyProvenance = {
      source: "migrated-v1",
      ordering: "source-order",
      ambiguousEqualTimeTies: 0,
      migratedEventCount: plays.length,
      sourceDigest: legacySourceDigest(1, careStartedAt, plays, []),
    };
    return buildMigratedJourney(
      candidate.seed,
      createdAt,
      careStartedAt,
      provenance,
      playProjection,
      plays,
      [],
      initialCare(careStartedAt),
    );
  }

  const canonicalCareStartTimes = new Set([createdAt, ...plays.map((event) => event.committedAt)]);
  const careStartedAt =
    isIsoTimestamp(candidate.careStartedAt) && canonicalCareStartTimes.has(candidate.careStartedAt)
      ? candidate.careStartedAt
      : playProjection.updatedAt;
  let care = initialCare(careStartedAt);
  const careTraces: CareTrace[] = [];
  if (Array.isArray(candidate.careTraces)) {
    for (const trace of candidate.careTraces) {
      const replayed = replayLegacyCareTrace(candidate.seed, careStartedAt, care, careTraces, trace);
      if (!replayed) break;
      care = replayed.care;
      careTraces.push(replayed.trace);
    }
  }
  const provenance: JourneyProvenance = {
    source: "migrated-v2",
    ordering: "timestamp-play-before-care",
    ambiguousEqualTimeTies: countAmbiguousCrossLaneTies(plays, careTraces),
    migratedEventCount: plays.length + careTraces.length,
    sourceDigest: legacySourceDigest(2, careStartedAt, plays, careTraces),
  };
  return buildMigratedJourney(
    candidate.seed,
    createdAt,
    careStartedAt,
    provenance,
    playProjection,
    plays,
    careTraces,
    care,
  );
}

function buildMigratedJourney(
  seed: string,
  createdAt: string,
  careStartedAt: string,
  provenance: JourneyProvenance,
  expectedPlayState: Journey,
  plays: PlayCommitEvent[],
  careTraces: CareTrace[],
  expectedCare: CareState,
): Journey | null {
  const pending: Array<{ committedAt: string; kindRank: 0 | 1; laneOrdinal: number; payload: JourneyEventPayload }> = [
    ...plays.map((event, laneOrdinal) => ({
      committedAt: event.committedAt,
      kindRank: 0 as const,
      laneOrdinal,
      payload: {
        kind: "play-commit" as const,
        play: event.play,
        sessionId: event.sessionId,
        fieldName: event.fieldName,
        choice: event.choice,
        signals: [...event.signals],
        generator: event.generator,
      },
    })),
    ...careTraces.map((trace, laneOrdinal) => ({
      committedAt: trace.actedAt,
      kindRank: 1 as const,
      laneOrdinal,
      payload: { kind: "care-action" as const, action: trace.action },
    })),
  ];
  // V2 stored two lanes, so equal-time cross-lane order is unknowable. Migration always admits play before care.
  pending.sort(
    (left, right) =>
      Date.parse(left.committedAt) - Date.parse(right.committedAt) ||
      left.kindRank - right.kindRank ||
      left.laneOrdinal - right.laneOrdinal,
  );

  let journey = createJourneyWithCareOrigin(seed, createdAt, careStartedAt, provenance);
  try {
    for (const event of pending) journey = appendJourneyEvent(journey, event.payload, event.committedAt);
  } catch {
    return null;
  }

  const expectedUpdatedAt =
    Date.parse(expectedCare.updatedAt) > Date.parse(playProjectionTimestamp(plays, createdAt))
      ? expectedCare.updatedAt
      : playProjectionTimestamp(plays, createdAt);
  if (
    journey.plays !== plays.length ||
    journey.bond !== expectedPlayState.bond ||
    journey.expression !== expectedPlayState.expression ||
    JSON.stringify(journey.affinities) !== JSON.stringify(expectedPlayState.affinities) ||
    journey.updatedAt !== expectedUpdatedAt ||
    JSON.stringify(journey.care) !== JSON.stringify(expectedCare)
  ) {
    return null;
  }
  return journey;
}

function playProjectionTimestamp(plays: PlayCommitEvent[], createdAt: string): string {
  return plays.at(-1)?.committedAt ?? createdAt;
}

function migrationProvenanceIsValid(journey: Journey): boolean {
  const provenance = journey.provenance;
  if (provenance.source === "native-v3") return true;
  if (provenance.migratedEventCount > journey.events.length) return false;

  const migratedEvents = journey.events.slice(0, provenance.migratedEventCount);
  if (migratedEvents.some((event) => event.kind === "activity-complete" || event.kind === "practice-complete")) return false;
  const migratedPlays = migratedEvents.filter((event): event is PlayCommitEvent => event.kind === "play-commit");
  const migratedCareEvents = migratedEvents.filter(
    (event): event is CareActionEvent => event.kind === "care-action",
  );
  if (provenance.source === "migrated-v1" && migratedCareEvents.length > 0) return false;

  for (let index = 1; index < migratedEvents.length; index += 1) {
    const previous = migratedEvents[index - 1];
    const current = migratedEvents[index];
    if (
      previous.committedAt === current.committedAt &&
      previous.kind === "care-action" &&
      current.kind === "play-commit"
    ) {
      return false;
    }
  }

  let previousCareId = "origin";
  const migratedCareTraces = migratedCareEvents.map((event, index) => {
    const sequence = index + 1;
    const id = legacyCareTraceId(
      journey.seed,
      journey.careStartedAt,
      previousCareId,
      sequence,
      event.action,
      event.committedAt,
    );
    previousCareId = id;
    return { id, sequence, action: event.action, actedAt: event.committedAt };
  });
  const validCareOrigins = new Set([journey.createdAt, ...migratedPlays.map((event) => event.committedAt)]);
  if (!validCareOrigins.has(journey.careStartedAt)) return false;
  if (
    provenance.source === "migrated-v1" &&
    journey.careStartedAt !== playProjectionTimestamp(migratedPlays, journey.createdAt)
  ) {
    return false;
  }

  const sourceVersion = provenance.source === "migrated-v1" ? 1 : 2;
  if (
    provenance.source === "migrated-v2" &&
    provenance.ambiguousEqualTimeTies !== countAmbiguousCrossLaneTies(migratedPlays, migratedCareTraces)
  ) {
    return false;
  }
  return (
    provenance.sourceDigest ===
    legacySourceDigest(sourceVersion, journey.careStartedAt, migratedPlays, migratedCareTraces)
  );
}

function hydrateV3Journey(value: unknown, version: 3 | 4 | 5 = 3): Journey | null {
  if (!value || typeof value !== "object") return null;
  if (version >= 4 && !exactDataRecord(value, ["version", "seed", "createdAt", "careStartedAt", "provenance", "events"])) return null;
  const candidate = value as {
    seed?: unknown;
    createdAt?: unknown;
    careStartedAt?: unknown;
    provenance?: unknown;
    events?: unknown;
  };
  if (
    typeof candidate.seed !== "string" ||
    candidate.seed.length === 0 ||
    !isIsoTimestamp(candidate.createdAt) ||
    !isIsoTimestamp(candidate.careStartedAt) ||
    Date.parse(candidate.careStartedAt) < Date.parse(candidate.createdAt) ||
    !Array.isArray(candidate.events) || (version >= 4 && !denseDataArray(candidate.events))
  ) {
    return null;
  }
  if (version >= 4 && !plainDataRecord(candidate.provenance)) return null;
  const provenance = parseJourneyProvenance(candidate.provenance);
  if (!provenance || (provenance.source === "native-v3" && candidate.careStartedAt !== candidate.createdAt)) {
    return null;
  }
  if (version >= 4 && !exactDataRecord(candidate.provenance, provenance.source === "native-v3"
    ? ["source", "ordering", "ambiguousEqualTimeTies", "sourceDigest"]
    : ["source", "ordering", "ambiguousEqualTimeTies", "migratedEventCount", "sourceDigest"])) return null;
  let journey = createJourneyWithCareOrigin(candidate.seed, candidate.createdAt, candidate.careStartedAt, provenance);
  for (const value of candidate.events) {
    const replayed = replayJourneyEvent(journey, value, version >= 4, version === 5);
    if (!replayed) {
      if (version >= 4) return null;
      break;
    }
    journey = replayed;
  }
  // v4 is introduced by the first activity receipt, never by relabeling v3 data.
  if (version >= 4 && journey.version !== version) return null;
  if (candidate.events.length > 0 && journey.events.length === 0) return null;
  if (!migrationProvenanceIsValid(journey)) return null;
  const canonicalCareStartTimes = new Set([
    journey.createdAt,
    ...playHistory(journey).map((event) => event.committedAt),
  ]);
  if (!canonicalCareStartTimes.has(journey.careStartedAt)) return null;
  return journey;
}

function canonicalJourneyForCommit(value: Journey): Journey {
  if ((value.version !== 3 && value.version !== 4 && value.version !== 5) || !Array.isArray(value.events)) {
    throw new Error("This journey does not contain supported event authority.");
  }
  const authority = value.version === 3 ? value : {
    version: value.version, seed: value.seed, createdAt: value.createdAt, careStartedAt: value.careStartedAt,
    provenance: value.provenance, events: value.events,
  };
  const canonical = hydrateV3Journey(authority, value.version);
  if (!canonical || canonical.events.length !== value.events.length) {
    throw new Error("This journey does not contain a complete valid event chain.");
  }
  return canonical;
}

export function hydrateJourney(value: unknown): Journey | null {
  if (!value || typeof value !== "object") return null;
  const version = (value as { version?: unknown }).version;
  if (version === 3) return hydrateV3Journey(value);
  if (version === 4 || version === 5) return hydrateV3Journey(value, version);
  if (version === 1 || version === 2) return migrateLegacyJourney(value);
  return null;
}

export function stageForJourney(journey: Journey): { name: GrowthStageName; progress: number; scale: number } {
  const practicedRoles = ROLE_ORDER.filter((role) => journey.affinities[role] > 0).length;
  if (journey.plays >= 20 && journey.bond >= 70 && practicedRoles >= 5) {
    return { name: "Advanced", progress: 1, scale: 1.18 };
  }
  if (journey.plays >= 10 && journey.bond >= 38 && practicedRoles >= 4) {
    return { name: "Mature", progress: Math.min(1, (journey.plays - 10) / 10), scale: 1.1 };
  }
  if (journey.plays >= 5 && journey.bond >= 18 && practicedRoles >= 2) {
    return { name: "Adolescent", progress: Math.min(1, (journey.plays - 5) / 5), scale: 1 };
  }
  if (journey.plays >= 2 && journey.bond >= 7) {
    return { name: "Young", progress: Math.min(1, (journey.plays - 2) / 3), scale: 0.9 };
  }
  return { name: "Hatchling", progress: Math.min(1, journey.plays / 2), scale: 0.82 };
}

export function dominantRole(journey: Journey): RoleId {
  const maximum = Math.max(...ROLE_ORDER.map((role) => journey.affinities[role]));
  if (maximum === 0) return journey.expression;
  return ROLE_ORDER.find((role) => journey.affinities[role] === maximum) ?? journey.expression;
}

export function revisionForJourney(journey: Journey): string {
  return `${journey.id}:${journey.events.length}:${eventHeadId(journey)}`;
}

function lineageForJourney(journey: Journey): string {
  const plays = playHistory(journey);
  if (plays.length === 0) return "";
  let digest = hashString(`${journey.seed}:lineage`);
  for (const event of plays) {
    digest = hashString(`${digest.toString(16)}:${event.choice}:${event.signals.join(",")}`);
  }
  return `:lineage:${digest.toString(16)}`;
}

function shuffled<T>(items: readonly T[], random: () => number): T[] {
  const copy = [...items];
  for (let index = copy.length - 1; index > 0; index -= 1) {
    const swap = Math.floor(random() * (index + 1));
    [copy[index], copy[swap]] = [copy[swap], copy[index]];
  }
  return copy;
}

function pointAwayFromCenter(random: () => number, minimum = 0.2): { x: number; y: number } {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    const x = 0.1 + random() * 0.8;
    const y = 0.18 + random() * 0.68;
    if (Math.hypot(x - 0.5, y - 0.54) >= minimum) return { x, y };
  }
  return { x: 0.2, y: 0.25 };
}

function createPlaySessionFromSeed(journey: Journey, seed: number): PlaySession {
  const random = seededRandom(seed);
  const auras = shuffled(AURA_ORDER, random).slice(0, 6);
  const roles = shuffled(ROLE_ORDER, random);
  const echoes = auras.map((aura, index) => {
    const point = pointAwayFromCenter(random, 0.2);
    const role = random() < 0.58 ? AURAS[aura].roleBias : roles[index % roles.length];
    return {
      id: `echo-${index + 1}`,
      aura,
      role,
      x: point.x,
      y: point.y,
      phase: random() * Math.PI * 2,
    };
  });

  const staticZones = Array.from({ length: 3 }, (_, index) => {
    const point = pointAwayFromCenter(random, 0.17);
    return {
      id: `static-${index + 1}`,
      x: point.x,
      y: point.y,
      radius: 0.038 + random() * 0.018,
      phase: random() * Math.PI * 2,
    };
  });

  const sparks = Array.from({ length: 22 }, (_, index) => {
    const point = pointAwayFromCenter(random, 0.04);
    return { id: `spark-${index + 1}`, x: point.x, y: point.y, phase: random() * Math.PI * 2 };
  });

  const fieldName = `${FIELD_FIRST[Math.floor(random() * FIELD_FIRST.length)]} ${
    FIELD_SECOND[Math.floor(random() * FIELD_SECOND.length)]
  }`;

  return {
    id: `play-${journey.plays + 1}-${seed.toString(16)}`,
    seed,
    play: journey.plays + 1,
    baseRevision: revisionForJourney(journey),
    fieldName,
    echoes,
    staticZones,
    sparks,
    collected: [],
    proposals: [],
  };
}

export function createPlaySession(journey: Journey): PlaySession {
  return createPlaySessionFromSeed(
    journey,
    hashString(`${journey.seed}:play:${journey.plays + 1}${lineageForJourney(journey)}`),
  );
}

function createLegacyPlaySession(journey: Journey): PlaySession {
  return createPlaySessionFromSeed(journey, hashString(`${journey.seed}:play:${journey.plays + 1}`));
}

export function collectEcho(session: PlaySession, echoId: string): PlaySession {
  if (session.collected.includes(echoId) || session.collected.length >= 3) return session;
  const echo = session.echoes.find((candidate) => candidate.id === echoId);
  if (!echo) return session;
  const collected = [...session.collected, echoId];
  return {
    ...session,
    collected,
    proposals: collected.length === 3 ? proposalsFor(session.echoes, collected) : [],
  };
}

export function proposalsFor(echoes: FieldEcho[], collectedIds: string[]): RoleId[] {
  const scores = new Map<RoleId, number>(ROLE_ORDER.map((role) => [role, 0]));
  for (const id of collectedIds) {
    const echo = echoes.find((candidate) => candidate.id === id);
    if (!echo) continue;
    scores.set(echo.role, (scores.get(echo.role) ?? 0) + 2);
    const bias = AURAS[echo.aura].roleBias;
    scores.set(bias, (scores.get(bias) ?? 0) + 1);
  }
  return [...ROLE_ORDER]
    .sort((left, right) => (scores.get(right) ?? 0) - (scores.get(left) ?? 0))
    .slice(0, 2);
}

function sameEcho(left: FieldEcho, right: FieldEcho): boolean {
  return (
    left.id === right.id &&
    left.aura === right.aura &&
    left.role === right.role &&
    left.x === right.x &&
    left.y === right.y &&
    left.phase === right.phase
  );
}

function sameStaticZone(left: StaticZone, right: StaticZone): boolean {
  return (
    left.id === right.id &&
    left.x === right.x &&
    left.y === right.y &&
    left.radius === right.radius &&
    left.phase === right.phase
  );
}

function sameSpark(left: FieldSpark, right: FieldSpark): boolean {
  return left.id === right.id && left.x === right.x && left.y === right.y && left.phase === right.phase;
}

function sameCanonicalSession(actual: PlaySession, canonical: PlaySession): boolean {
  return (
    actual.id === canonical.id &&
    actual.seed === canonical.seed &&
    actual.play === canonical.play &&
    actual.fieldName === canonical.fieldName &&
    Array.isArray(actual.echoes) &&
    actual.echoes.length === canonical.echoes.length &&
    actual.echoes.every((echo, index) => sameEcho(echo, canonical.echoes[index])) &&
    Array.isArray(actual.staticZones) &&
    actual.staticZones.length === canonical.staticZones.length &&
    actual.staticZones.every((zone, index) => sameStaticZone(zone, canonical.staticZones[index])) &&
    Array.isArray(actual.sparks) &&
    actual.sparks.length === canonical.sparks.length &&
    actual.sparks.every((spark, index) => sameSpark(spark, canonical.sparks[index]))
  );
}

function canonicalSessionForGenerator(journey: Journey, generator: PlayGeneratorId): PlaySession {
  return generator === "legacy" ? createLegacyPlaySession(journey) : createPlaySession(journey);
}

function applyPlayCommitEvent(journey: Journey, event: PlayCommitEvent): Journey {
  const canonical = canonicalSessionForGenerator(journey, event.generator);
  if (
    event.play !== canonical.play ||
    event.sessionId !== canonical.id ||
    event.fieldName !== canonical.fieldName
  ) {
    throw new Error("A play event does not match the canonical field.");
  }

  let session = canonical;
  for (const aura of event.signals) {
    const echo = canonical.echoes.find((candidate) => candidate.aura === aura);
    if (!echo) throw new Error("A play event contains a non-canonical signal.");
    session = collectEcho(session, echo.id);
  }
  if (session.collected.length !== 3 || (event.choice !== "hold" && !session.proposals.includes(event.choice))) {
    throw new Error("A play event contains a non-canonical choice.");
  }

  const affinities = { ...journey.affinities };
  if (event.choice === "hold") {
    affinities.guardian += 1;
  } else {
    affinities[event.choice] += 3;
    for (const id of session.collected) {
      const role = canonical.echoes.find((echo) => echo.id === id)?.role;
      if (role && role !== event.choice) affinities[role] += 1;
    }
  }

  return {
    ...journey,
    updatedAt: event.committedAt,
    plays: journey.plays + 1,
    bond: Math.min(100, journey.bond + (event.choice === "hold" ? 2 : 4)),
    expression: event.choice === "hold" ? journey.expression : event.choice,
    affinities,
    events: [...journey.events, event],
    core: CORE_CONTINUITY,
  };
}

function replayLegacyPlayTrace(journey: Journey, value: unknown, allowLegacy = false): Journey | null {
  if (!value || typeof value !== "object") return null;
  const trace = value as Partial<KeptTrace>;
  const generator = trace.generator;
  if (generator !== undefined && generator !== "branching" && generator !== "legacy") return null;
  const candidates: Array<{ generator: PlayGeneratorId; session: PlaySession }> = [];
  if (generator !== "legacy") {
    candidates.push({ generator: "branching", session: createPlaySession(journey) });
  }
  if (generator === "legacy" || (allowLegacy && generator === undefined)) {
    candidates.push({ generator: "legacy", session: createLegacyPlaySession(journey) });
  }
  const matched = candidates.find(
    ({ generator: candidateGenerator, session }) =>
      (generator === undefined || generator === candidateGenerator) &&
      trace.id === session.id &&
      trace.play === session.play &&
      trace.fieldName === session.fieldName,
  );
  if (!matched) return null;
  const signals = trace.signals;
  if (
    !isIsoTimestamp(trace.keptAt) ||
    Date.parse(trace.keptAt) < Date.parse(journey.updatedAt) ||
    (trace.choice !== "hold" && !isRole(trace.choice)) ||
    !Array.isArray(signals) ||
    signals.length !== 3 ||
    !signals.every(isAura) ||
    new Set(signals).size !== signals.length
  ) {
    return null;
  }
  try {
    return appendJourneyEvent(
      journey,
      {
        kind: "play-commit",
        play: matched.session.play,
        sessionId: matched.session.id,
        fieldName: matched.session.fieldName,
        choice: trace.choice,
        signals: [...signals],
        generator: matched.generator,
      },
      trace.keptAt,
    );
  } catch {
    return null;
  }
}

export function commitSession(
  journey: Journey,
  session: PlaySession,
  choice: RoleId | "hold",
  now = new Date().toISOString(),
): Journey {
  const canonicalJourney = canonicalJourneyForCommit(journey);
  const canonical = createPlaySession(canonicalJourney);
  if (session.baseRevision !== canonical.baseRevision) {
    throw new Error("This proposal is stale because the journey changed after the play began.");
  }
  if (!sameCanonicalSession(session, canonical)) {
    throw new Error("This play session does not match the canonical field.");
  }
  if (
    !Array.isArray(session.collected) ||
    session.collected.length !== 3 ||
    new Set(session.collected).size !== 3 ||
    !session.collected.every((id) => canonical.echoes.some((echo) => echo.id === id))
  ) {
    throw new Error("A play requires exactly three unique signals from the canonical field.");
  }

  const proposals = proposalsFor(canonical.echoes, session.collected);
  if (
    !Array.isArray(session.proposals) ||
    session.proposals.length !== proposals.length ||
    session.proposals.some((proposal, index) => proposal !== proposals[index])
  ) {
    throw new Error("This play's proposals do not match the canonical signals.");
  }
  if (choice !== "hold" && !proposals.includes(choice)) {
    throw new Error("Only a proposed expression or hold may be committed.");
  }
  if (!isIsoTimestamp(now)) throw new Error("A committed play requires a canonical timestamp.");
  const signals = session.collected
    .map((id) => canonical.echoes.find((echo) => echo.id === id)?.aura)
    .filter((aura): aura is AuraId => Boolean(aura));
  return commitJourneyOperation(
    canonicalJourney,
    {
      kind: "play-commit",
      play: canonical.play,
      sessionId: canonical.id,
      fieldName: canonical.fieldName,
      choice,
      signals,
      generator: "branching",
    },
    now,
  );
}
