import { replayCompletedPractice, type QiMonCard } from "./battle-engine";
import {
  hydrateJourney, journeyOriginSha256, revisionForJourney, serializeJourney, sha256String,
  type Journey, type JourneyEvent, type PracticeCompleteEvent, type RoleId,
} from "./model";
import { parseJsonWithoutDuplicateKeys } from "./strict-json";

/** Independent local authority. A roster never adds or changes a Journey event. */
export const QIMON_ROSTER_SCHEMA = "archi-roster/v1" as const;
export const QIMON_ROSTER_ARCHIVE_FORMAT = "archi-qimon-roster" as const;
export const QIMON_ROSTER_ARCHIVE_VERSION = 1 as const;
export const QIMON_ROSTER_LIMITS = Object.freeze({ members: 12, events: 256, trainingTier: 3, team: 3, archiveBytes: 256 * 1024 });

const ROLE_NAMES: Readonly<Record<RoleId, string>> = Object.freeze({
  hearth: "Hearth QiMon", muse: "Muse QiMon", scout: "Scout QiMon",
  beacon: "Beacon QiMon", keeper: "Keeper QiMon", guardian: "Guardian QiMon",
});
const SHA256 = /^[a-f0-9]{64}$/;

export type QiMonRosterAction =
  | Readonly<{ kind: "discover"; sourceEventId: string; sourceEventSha256: string;
      offerId: string; memberId: string; name: string; role: RoleId }>
  | Readonly<{ kind: "invite"; offerId: string }>
  | Readonly<{ kind: "train"; memberId: string; sourceEventId: string;
      sourceEventSha256: string; replayDigest: string; tier: number }>
  | Readonly<{ kind: "bond"; memberIds: readonly [string, string]; sourceEventId: string;
      sourceEventSha256: string; replayDigest: string }>
  | Readonly<{ kind: "team"; memberIds: readonly string[] }>;

type QiMonRosterRequest =
  | Readonly<{ kind: "discover"; sourceEventId: string }>
  | Readonly<{ kind: "invite"; offerId: string }>
  | Readonly<{ kind: "train"; memberId: string; sourceEventId: string }>
  | Readonly<{ kind: "bond"; memberIds: readonly [string, string]; sourceEventId: string }>
  | Readonly<{ kind: "team"; memberIds: readonly string[] }>;

export interface QiMonRosterEvent {
  readonly sequence: number;
  readonly previousEventId: string;
  readonly eventId: string;
  readonly recordedAt: string;
  readonly journeyEventCount: number;
  readonly journeyHeadEventId: string;
  readonly action: QiMonRosterAction;
}

export interface QiMonRoster {
  readonly schema: typeof QIMON_ROSTER_SCHEMA;
  readonly version: 1;
  readonly originDigest: string;
  readonly createdAt: string;
  readonly baseJourneyRevision: string;
  readonly baseEventCount: number;
  readonly baseHeadEventId: string;
  readonly events: readonly QiMonRosterEvent[];
}

export interface QiMonOffer {
  readonly id: string;
  readonly memberId: string;
  readonly card: QiMonCard;
  readonly sourceEventId: string;
  readonly discoveredAt: string;
}

export interface RecruitedQiMon {
  readonly id: string;
  readonly card: QiMonCard;
  readonly sourceEventId: string;
  readonly invitationEventId: string;
  readonly trainingTier: number;
  readonly trainingEventIds: readonly string[];
}

export interface QiMonPairBond {
  readonly memberIds: readonly [string, string];
  readonly sourceEventId: string;
  readonly bondEventId: string;
}

export interface QiMonRosterProjection {
  readonly revision: string;
  readonly offers: readonly QiMonOffer[];
  readonly members: readonly RecruitedQiMon[];
  readonly bonds: readonly QiMonPairBond[];
  readonly team: readonly QiMonCard[];
}

export type QiMonRosterInspection =
  | Readonly<{ status: "valid"; exportedAt: string; roster: QiMonRoster; projection: QiMonRosterProjection }>
  | Readonly<{ status: "invalid"; code: "too-large" | "invalid-json" | "invalid-envelope" |
      "unsupported-version" | "origin-mismatch" | "invalid-authority" | "manifest-mismatch"; message: string }>;

class RosterError extends Error {
  constructor(readonly code: Extract<QiMonRosterInspection, { status: "invalid" }>["code"], message: string) {
    super(message);
  }
}

interface OfferState extends QiMonOffer { readonly atCount: number; readonly invited: boolean }
interface MemberState extends RecruitedQiMon { readonly invitedAtCount: number }
interface ReplayState {
  offers: Map<string, OfferState>;
  members: Map<string, MemberState>;
  bonds: Map<string, QiMonPairBond>;
  teamIds: string[];
  creditedSources: Set<string>;
}

function fail(message: string, code: RosterError["code"] = "invalid-authority"): never {
  throw new RosterError(code, message);
}

function exactRecord(value: unknown, keys: readonly string[]): value is Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value) || Object.getPrototypeOf(value) !== Object.prototype) return false;
  const ownKeys = Reflect.ownKeys(value);
  return ownKeys.length === keys.length && keys.every((key) => {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    return descriptor && Object.hasOwn(descriptor, "value");
  });
}

function denseArray(value: unknown): value is unknown[] {
  return Array.isArray(value) && Object.getPrototypeOf(value) === Array.prototype &&
    Reflect.ownKeys(value).length === value.length + 1 &&
    Array.from({ length: value.length }, (_, index) => Object.getOwnPropertyDescriptor(value, String(index)))
      .every((descriptor) => descriptor && Object.hasOwn(descriptor, "value"));
}

function canonicalTime(value: unknown): value is string {
  return typeof value === "string" && Number.isFinite(Date.parse(value)) && new Date(Date.parse(value)).toISOString() === value;
}

function canonicalJourney(value: Journey): Journey {
  const authority = JSON.parse(serializeJourney(value)) as unknown;
  const restored = hydrateJourney(authority);
  if (!restored || restored.version !== value.version || restored.events.length !== value.events.length ||
      revisionForJourney(restored) !== revisionForJourney(value)) fail("The current Journey has no complete validated authority.");
  return restored;
}

function headAt(journey: Journey, eventCount: number): string {
  return journey.events[eventCount - 1]?.eventId ?? `origin-${journeyOriginSha256(journey)}`;
}

function sourceAt(journey: Journey, eventCount: number, eventId: string): JourneyEvent {
  const source = journey.events.find((event) => event.eventId === eventId && event.sequence <= eventCount);
  if (!source) fail("The kept source event is absent from this Journey prefix.");
  return source;
}

function sourceDigest(source: JourneyEvent): string { return sha256String(JSON.stringify(source)); }

function recruitIDs(originDigest: string, sourceEventId: string): { offerId: string; memberId: string } {
  const suffix = sha256String(JSON.stringify([QIMON_ROSTER_SCHEMA, originDigest, sourceEventId])).slice(0, 32);
  return { offerId: `offer-${suffix}`, memberId: `qm-${suffix}` };
}

function pairKey(first: string, second: string): string { return [first, second].sort().join(":"); }

function emptyState(): ReplayState {
  return { offers: new Map(), members: new Map(), bonds: new Map(), teamIds: [], creditedSources: new Set() };
}

function validObservation(journey: Journey, roster: QiMonRoster, eventCount: number, head: string): void {
  if (!Number.isSafeInteger(eventCount) || eventCount < roster.baseEventCount || eventCount > journey.events.length ||
      head !== headAt(journey, eventCount)) fail("The roster observation does not match this Journey chain.", "origin-mismatch");
}

function practiceSource(journey: Journey, state: ReplayState, eventCount: number, eventId: string): {
  event: PracticeCompleteEvent; replayDigest: string;
} {
  const event = sourceAt(journey, eventCount, eventId);
  if (event.kind !== "practice-complete" || state.creditedSources.has(eventId)) {
    fail("Training and pair bonds require one newly kept, unused practice completion.");
  }
  const verified = replayCompletedPractice(event.replay);
  return { event, replayDigest: verified.digest };
}

function sameCard(left: QiMonCard, right: QiMonCard): boolean {
  return left.id === right.id && left.name === right.name && left.role === right.role;
}

function deriveAction(journey: Journey, roster: QiMonRoster, state: ReplayState, eventCount: number,
  requested: QiMonRosterRequest): QiMonRosterAction {
  switch (requested.kind) {
    case "discover": {
      const source = sourceAt(journey, eventCount, requested.sourceEventId);
      const activeOffers = [...state.offers.values()].filter((offer) => !offer.invited).length;
      if (source.kind !== "play-commit" || source.sequence <= roster.baseEventCount || source.choice === "hold" ||
          state.creditedSources.has(source.eventId) || state.members.size + activeOffers >= QIMON_ROSTER_LIMITS.members) {
        fail("Find requires a new kept Field play with a chosen role and an unused source.");
      }
      const ids = recruitIDs(roster.originDigest, source.eventId);
      return { kind: "discover", sourceEventId: source.eventId, sourceEventSha256: sourceDigest(source),
        ...ids, name: ROLE_NAMES[source.choice], role: source.choice };
    }
    case "invite": {
      const offer = state.offers.get(requested.offerId);
      if (!offer || offer.invited || state.members.size >= QIMON_ROSTER_LIMITS.members) {
        fail("This offer is missing or already invited.");
      }
      return { kind: "invite", offerId: offer.id };
    }
    case "train": {
      const member = state.members.get(requested.memberId);
      if (!member || member.trainingTier >= QIMON_ROSTER_LIMITS.trainingTier) {
        fail("This recruited QiMon cannot receive another training credit from this Journey state.");
      }
      const { event, replayDigest } = practiceSource(journey, state, eventCount, requested.sourceEventId);
      if (event.sequence <= member.invitedAtCount) fail("A training practice must be kept after this recruit's invitation.");
      const cards = event.replay.teams[0].roster;
      if (cards.length !== 1 || !sameCard(cards[0], member.card)) {
        fail("Training requires a kept one-member practice played by this exact recruit.");
      }
      return { kind: "train", memberId: member.id, sourceEventId: event.eventId,
        sourceEventSha256: sourceDigest(event), replayDigest, tier: member.trainingTier + 1 };
    }
    case "bond": {
      if (!denseArray(requested.memberIds) || requested.memberIds.length !== 2 ||
          typeof requested.memberIds[0] !== "string" || typeof requested.memberIds[1] !== "string" ||
          requested.memberIds[0] === requested.memberIds[1]) fail("A pair needs two distinct recruited QiMon.");
      const ids = [...requested.memberIds].sort() as [string, string];
      const first = state.members.get(ids[0]), second = state.members.get(ids[1]);
      if (!first || !second || state.bonds.has(pairKey(ids[0], ids[1]))) {
        fail("This pair is absent or already bonded.");
      }
      const { event, replayDigest } = practiceSource(journey, state, eventCount, requested.sourceEventId);
      if (event.sequence <= Math.max(first.invitedAtCount, second.invitedAtCount)) {
        fail("A pair practice must be kept after both invitations.");
      }
      const cards = event.replay.teams[0].roster;
      if (cards.length !== 2 || !cards.some((card) => sameCard(card, first.card)) ||
          !cards.some((card) => sameCard(card, second.card))) {
        fail("A pair bond requires a kept two-member practice with these exact recruits.");
      }
      const actors = new Set(event.replay.commands.map((pair) => pair[0].activeQiMonId));
      if (!ids.every((id) => actors.has(id))) fail("Both recruits must act in the kept pair practice.");
      return { kind: "bond", memberIds: ids, sourceEventId: event.eventId,
        sourceEventSha256: sourceDigest(event), replayDigest };
    }
    case "team": {
      if (!denseArray(requested.memberIds) || requested.memberIds.length < 1 ||
          requested.memberIds.length > QIMON_ROSTER_LIMITS.team ||
          requested.memberIds.some((id) => typeof id !== "string" || !state.members.has(id)) ||
          new Set(requested.memberIds).size !== requested.memberIds.length ||
          JSON.stringify(requested.memberIds) === JSON.stringify(state.teamIds)) {
        fail("Choose one to three distinct recruited QiMon for a changed team.");
      }
      return { kind: "team", memberIds: [...requested.memberIds] };
    }
  }
}

function actionKeys(kind: QiMonRosterAction["kind"]): readonly string[] {
  switch (kind) {
    case "discover": return ["kind", "sourceEventId", "sourceEventSha256", "offerId", "memberId", "name", "role"];
    case "invite": return ["kind", "offerId"];
    case "train": return ["kind", "memberId", "sourceEventId", "sourceEventSha256", "replayDigest", "tier"];
    case "bond": return ["kind", "memberIds", "sourceEventId", "sourceEventSha256", "replayDigest"];
    case "team": return ["kind", "memberIds"];
  }
}

function sameAction(actual: unknown, expected: QiMonRosterAction): boolean {
  if (!exactRecord(actual, actionKeys(expected.kind)) || actual.kind !== expected.kind) return false;
  return actionKeys(expected.kind).every((key) => Array.isArray(actual[key])
    ? denseArray(actual[key]) && JSON.stringify(actual[key]) === JSON.stringify((expected as unknown as Record<string, unknown>)[key])
    : actual[key] === (expected as unknown as Record<string, unknown>)[key]);
}

function frozenAction(action: QiMonRosterAction): QiMonRosterAction {
  return Object.freeze(action.kind === "bond" || action.kind === "team"
    ? { ...action, memberIds: Object.freeze([...action.memberIds]) } as QiMonRosterAction
    : { ...action });
}

function eventID(roster: QiMonRoster, event: Omit<QiMonRosterEvent, "eventId">): string {
  return `qimon-event-${event.sequence}-${sha256String(JSON.stringify([
    QIMON_ROSTER_SCHEMA, roster.originDigest, event.sequence, event.previousEventId,
    event.recordedAt, event.journeyEventCount, event.journeyHeadEventId, event.action,
  ]))}`;
}

function applyState(state: ReplayState, event: QiMonRosterEvent): void {
  const action = event.action;
  switch (action.kind) {
    case "discover":
      state.offers.set(action.offerId, { id: action.offerId, memberId: action.memberId,
        card: { id: action.memberId, name: action.name, role: action.role }, sourceEventId: action.sourceEventId,
        discoveredAt: event.recordedAt, atCount: event.journeyEventCount, invited: false });
      state.creditedSources.add(action.sourceEventId);
      break;
    case "invite": {
      const offer = state.offers.get(action.offerId)!;
      state.offers.set(action.offerId, { ...offer, invited: true });
      state.members.set(offer.memberId, { id: offer.memberId, card: offer.card, sourceEventId: offer.sourceEventId,
        invitationEventId: event.eventId, trainingTier: 0, trainingEventIds: [], invitedAtCount: event.journeyEventCount });
      break;
    }
    case "train": {
      const member = state.members.get(action.memberId)!;
      state.members.set(action.memberId, { ...member, trainingTier: action.tier,
        trainingEventIds: [...member.trainingEventIds, action.sourceEventId] });
      state.creditedSources.add(action.sourceEventId);
      break;
    }
    case "bond":
      state.bonds.set(pairKey(action.memberIds[0], action.memberIds[1]), {
        memberIds: [...action.memberIds] as [string, string], sourceEventId: action.sourceEventId, bondEventId: event.eventId,
      });
      state.creditedSources.add(action.sourceEventId);
      break;
    case "team": state.teamIds = [...action.memberIds]; break;
  }
}

function replayRoster(rosterValue: unknown, sourceJourney: Journey): { roster: QiMonRoster; state: ReplayState; journey: Journey } {
  const journey = canonicalJourney(sourceJourney);
  if (!exactRecord(rosterValue, ["schema", "version", "originDigest", "createdAt", "baseJourneyRevision",
      "baseEventCount", "baseHeadEventId", "events"])) fail("The roster sidecar has unknown or missing fields.");
  const roster = rosterValue as unknown as QiMonRoster;
  if (roster.schema !== QIMON_ROSTER_SCHEMA || roster.version !== 1) fail("Unsupported roster schema or version.", "unsupported-version");
  if (!SHA256.test(roster.originDigest) || roster.originDigest !== journeyOriginSha256(journey)) {
    fail("This roster belongs to another Journey origin.", "origin-mismatch");
  }
  if (!canonicalTime(roster.createdAt) || Date.parse(roster.createdAt) <
        Date.parse(journey.events[roster.baseEventCount - 1]?.committedAt ?? journey.createdAt) ||
      !Number.isSafeInteger(roster.baseEventCount) || roster.baseEventCount < 0 ||
      roster.baseEventCount > journey.events.length || typeof roster.baseHeadEventId !== "string" ||
      roster.baseHeadEventId !== headAt(journey, roster.baseEventCount) ||
      roster.baseJourneyRevision !== `${journey.id}:${roster.baseEventCount}:${roster.baseHeadEventId}` ||
      !denseArray(roster.events) || roster.events.length > QIMON_ROSTER_LIMITS.events) {
    fail("The roster baseline or event chain is invalid.", "origin-mismatch");
  }
  const state = emptyState();
  const canonicalEvents: QiMonRosterEvent[] = [];
  let previousId = `roster-origin-${sha256String(JSON.stringify([
    roster.originDigest, roster.baseJourneyRevision, roster.createdAt,
  ]))}`;
  let previousAt = roster.baseEventCount;
  let previousTime = roster.createdAt;
  for (const candidate of roster.events) {
    if (!exactRecord(candidate, ["sequence", "previousEventId", "eventId", "recordedAt",
        "journeyEventCount", "journeyHeadEventId", "action"]) ||
        candidate.sequence !== canonicalEvents.length + 1 || candidate.previousEventId !== previousId ||
        !canonicalTime(candidate.recordedAt) || Date.parse(candidate.recordedAt) < Date.parse(previousTime) ||
        !Number.isSafeInteger(candidate.journeyEventCount) || candidate.journeyEventCount < previousAt ||
        typeof candidate.journeyHeadEventId !== "string") fail("The roster event chain is stale or malformed.");
    validObservation(journey, roster, candidate.journeyEventCount as number, candidate.journeyHeadEventId);
    const supplied = candidate.action;
    if (!supplied || typeof supplied !== "object" || !("kind" in supplied) ||
        !["discover", "invite", "train", "bond", "team"].includes(String(supplied.kind))) fail("Unknown roster action.");
    const expectedAction = deriveAction(journey, roster, state, candidate.journeyEventCount as number,
      supplied as QiMonRosterRequest);
    if (!sameAction(supplied, expectedAction)) fail("The roster action does not match its source authority.");
    if ((expectedAction.kind === "discover" || expectedAction.kind === "train" || expectedAction.kind === "bond") &&
        Date.parse(candidate.recordedAt) < Date.parse(sourceAt(journey, candidate.journeyEventCount as number,
          expectedAction.sourceEventId).committedAt)) fail("A roster action cannot precede its kept source event.");
    const eventBase = { sequence: candidate.sequence as number, previousEventId: previousId,
      recordedAt: candidate.recordedAt, journeyEventCount: candidate.journeyEventCount as number,
      journeyHeadEventId: candidate.journeyHeadEventId, action: frozenAction(expectedAction) };
    const expectedId = eventID(roster, eventBase);
    if (candidate.eventId !== expectedId) fail("The roster event digest does not match its content.");
    const event = Object.freeze({ ...eventBase, eventId: expectedId });
    canonicalEvents.push(event);
    applyState(state, event);
    previousId = expectedId;
    previousAt = event.journeyEventCount;
    previousTime = event.recordedAt;
  }
  return { roster: Object.freeze({ schema: QIMON_ROSTER_SCHEMA, version: 1, originDigest: roster.originDigest,
    createdAt: roster.createdAt, baseJourneyRevision: roster.baseJourneyRevision, baseEventCount: roster.baseEventCount,
    baseHeadEventId: roster.baseHeadEventId, events: Object.freeze(canonicalEvents) }), state, journey };
}

function projection(roster: QiMonRoster, state: ReplayState): QiMonRosterProjection {
  const members = [...state.members.values()].map((member): RecruitedQiMon => Object.freeze({
    id: member.id, card: Object.freeze({ ...member.card }), sourceEventId: member.sourceEventId,
    invitationEventId: member.invitationEventId, trainingTier: member.trainingTier,
    trainingEventIds: Object.freeze([...member.trainingEventIds]),
  }));
  const offers = [...state.offers.values()].filter((offer) => !offer.invited)
    .map((offer): QiMonOffer => Object.freeze({
    id: offer.id, memberId: offer.memberId, card: Object.freeze({ ...offer.card }),
    sourceEventId: offer.sourceEventId, discoveredAt: offer.discoveredAt,
  }));
  return Object.freeze({ revision: revisionForQiMonRoster(roster), offers: Object.freeze(offers),
    members: Object.freeze(members), bonds: Object.freeze([...state.bonds.values()].map((bond) => Object.freeze({
      ...bond, memberIds: Object.freeze([...bond.memberIds]) as unknown as readonly [string, string],
    }))), team: Object.freeze(state.teamIds.map((id) => Object.freeze({ ...state.members.get(id)!.card }))) });
}

/** A new sidecar pins the current head; existing plays never become offers retroactively. */
export function createQiMonRoster(sourceJourney: Journey, now = new Date().toISOString()): QiMonRoster {
  const journey = canonicalJourney(sourceJourney);
  if (!canonicalTime(now) || Date.parse(now) < Date.parse(journey.updatedAt)) {
    fail("Roster creation needs a canonical timestamp after the current Journey head.");
  }
  const baseEventCount = journey.events.length;
  return Object.freeze({ schema: QIMON_ROSTER_SCHEMA, version: 1, originDigest: journeyOriginSha256(journey),
    createdAt: now, baseJourneyRevision: revisionForJourney(journey), baseEventCount,
    baseHeadEventId: headAt(journey, baseEventCount), events: Object.freeze([]) });
}

export function revisionForQiMonRoster(roster: QiMonRoster): string {
  return `roster-sha256:${sha256String(JSON.stringify([
    roster.schema, roster.version, roster.originDigest, roster.createdAt,
    roster.baseJourneyRevision, roster.events.length, roster.events.at(-1)?.eventId ?? null,
  ]))}`;
}

export function projectQiMonRoster(journey: Journey, roster: QiMonRoster): QiMonRosterProjection {
  const replayed = replayRoster(roster, journey);
  return projection(replayed.roster, replayed.state);
}

function commit(journey: Journey, roster: QiMonRoster, requested: QiMonRosterRequest,
  expectedRosterRevision: string, expectedJourneyRevision: string, now: string): QiMonRoster {
  const current = replayRoster(roster, journey);
  if (expectedRosterRevision !== revisionForQiMonRoster(current.roster) ||
      expectedJourneyRevision !== revisionForJourney(current.journey)) fail("The roster or Journey changed. Review the current state first.");
  if (!canonicalTime(now) || Date.parse(now) < Date.parse(current.roster.events.at(-1)?.recordedAt ?? current.roster.createdAt)) {
    fail("Roster actions require monotonic canonical timestamps.");
  }
  if (current.roster.events.length >= QIMON_ROSTER_LIMITS.events) fail("The local roster event limit has been reached.");
  const eventCount = current.journey.events.length;
  const action = deriveAction(current.journey, current.roster, current.state, eventCount, requested);
  const eventBase = { sequence: current.roster.events.length + 1,
    previousEventId: current.roster.events.at(-1)?.eventId ?? `roster-origin-${sha256String(JSON.stringify([
      current.roster.originDigest, current.roster.baseJourneyRevision, current.roster.createdAt,
    ]))}`,
    recordedAt: now, journeyEventCount: eventCount, journeyHeadEventId: headAt(current.journey, eventCount), action };
  const event = Object.freeze({ ...eventBase, eventId: eventID(current.roster, eventBase) });
  const updated: QiMonRoster = { ...current.roster, events: [...current.roster.events, event] };
  return replayRoster(updated, current.journey).roster;
}

export function discoverQiMon(journey: Journey, roster: QiMonRoster, playEventId: string,
  expectedRosterRevision: string, expectedJourneyRevision: string, now = new Date().toISOString()): QiMonRoster {
  return commit(journey, roster, { kind: "discover", sourceEventId: playEventId },
    expectedRosterRevision, expectedJourneyRevision, now);
}

export function inviteQiMon(journey: Journey, roster: QiMonRoster, offerId: string,
  expectedRosterRevision: string, expectedJourneyRevision: string, now = new Date().toISOString()): QiMonRoster {
  return commit(journey, roster, { kind: "invite", offerId }, expectedRosterRevision, expectedJourneyRevision, now);
}

export function trainQiMon(journey: Journey, roster: QiMonRoster, memberId: string, practiceEventId: string,
  expectedRosterRevision: string, expectedJourneyRevision: string, now = new Date().toISOString()): QiMonRoster {
  return commit(journey, roster, { kind: "train", memberId, sourceEventId: practiceEventId },
    expectedRosterRevision, expectedJourneyRevision, now);
}

export function bondQiMonPair(journey: Journey, roster: QiMonRoster, firstId: string, secondId: string, practiceEventId: string,
  expectedRosterRevision: string, expectedJourneyRevision: string, now = new Date().toISOString()): QiMonRoster {
  return commit(journey, roster, { kind: "bond", memberIds: [firstId, secondId], sourceEventId: practiceEventId },
    expectedRosterRevision, expectedJourneyRevision, now);
}

export function selectQiMonTeam(journey: Journey, roster: QiMonRoster, memberIds: readonly string[],
  expectedRosterRevision: string, expectedJourneyRevision: string, now = new Date().toISOString()): QiMonRoster {
  return commit(journey, roster, { kind: "team", memberIds: [...memberIds] },
    expectedRosterRevision, expectedJourneyRevision, now);
}

/** Separate from the existing Journey archive; the caller previews before replacing local storage. */
export function serializeQiMonRoster(roster: QiMonRoster, journey: Journey,
  exportedAt = new Date().toISOString()): string {
  if (!canonicalTime(exportedAt)) fail("Roster export needs a canonical timestamp.");
  const replayed = replayRoster(roster, journey);
  const authority = replayed.roster;
  const manifest = { originDigest: authority.originDigest, rosterRevision: revisionForQiMonRoster(authority),
    eventCount: authority.events.length, memberCount: replayed.state.members.size,
    authoritySha256: sha256String(JSON.stringify(authority)) };
  const archive = `${JSON.stringify({ format: QIMON_ROSTER_ARCHIVE_FORMAT,
    archiveVersion: QIMON_ROSTER_ARCHIVE_VERSION, exportedAt, authority, manifest }, null, 2)}\n`;
  if (new TextEncoder().encode(archive).byteLength > QIMON_ROSTER_LIMITS.archiveBytes) fail("Roster archive exceeds the local size limit.", "too-large");
  return archive;
}

export function inspectQiMonRoster(source: string, journey: Journey): QiMonRosterInspection {
  if (new TextEncoder().encode(source).byteLength > QIMON_ROSTER_LIMITS.archiveBytes) {
    return { status: "invalid", code: "too-large", message: "This roster archive exceeds the local size limit." };
  }
  let parsed: unknown;
  try { parsed = parseJsonWithoutDuplicateKeys(source, "QiMon roster archive"); }
  catch { return { status: "invalid", code: "invalid-json", message: "This is not unambiguous valid JSON." }; }
  if (!exactRecord(parsed, ["format", "archiveVersion", "exportedAt", "authority", "manifest"]) ||
      parsed.format !== QIMON_ROSTER_ARCHIVE_FORMAT || !canonicalTime(parsed.exportedAt) ||
      !exactRecord(parsed.manifest, ["originDigest", "rosterRevision", "eventCount", "memberCount", "authoritySha256"])) {
    return { status: "invalid", code: "invalid-envelope", message: "This is not a complete QiMon roster archive." };
  }
  if (parsed.archiveVersion !== QIMON_ROSTER_ARCHIVE_VERSION) {
    return { status: "invalid", code: "unsupported-version", message: "This roster archive version is unsupported." };
  }
  try {
    const replayed = replayRoster(parsed.authority, journey);
    const authority = replayed.roster;
    const manifest = parsed.manifest;
    if (manifest.originDigest !== authority.originDigest ||
        manifest.rosterRevision !== revisionForQiMonRoster(authority) ||
        manifest.eventCount !== authority.events.length || manifest.memberCount !== replayed.state.members.size ||
        manifest.authoritySha256 !== sha256String(JSON.stringify(authority))) {
      fail("The roster manifest does not match its authority.", "manifest-mismatch");
    }
    return { status: "valid", exportedAt: parsed.exportedAt, roster: authority,
      projection: projection(authority, replayed.state) };
  } catch (error) {
    return { status: "invalid", code: error instanceof RosterError ? error.code : "invalid-authority",
      message: error instanceof Error ? error.message : "The roster authority is invalid." };
  }
}
