import {
  BATTLE_ACTIONS, BATTLE_LIMITS, BATTLE_SCHEMA, battleRevision, createBattle,
  createBattleCommand, previewBattleCommand, resolveBattleRound,
  type BattleAction, type BattleCommand, type BattleState, type BattleTeamId,
  type BattleTeamSetup, type QiMonCard,
} from "./battle-engine";
import {
  ROLE_ORDER, hydrateJourney, revisionForJourney, serializeJourney, sha256String,
  type RoleId,
} from "./model";
import { inspectQiMonRoster, revisionForQiMonRoster } from "./qimon-roster";
import { parseJsonWithoutDuplicateKeys } from "./strict-json";

/** Human-vs-human Field rules. This module has no Journey, roster, or History writer. */
export const OWNED_NEARBY_RULES_ID = "archi-nearby-owned-field/v1" as const;
/** Contract fingerprint. A transport must also compare bundled Play digests for binary parity. */
export const OWNED_NEARBY_RULES_DIGEST = sha256String(JSON.stringify([
  OWNED_NEARBY_RULES_ID, BATTLE_SCHEMA, BATTLE_ACTIONS, BATTLE_LIMITS, ROLE_ORDER,
  "human-human", "session-only", "no-reward",
]));
const VERSION = 1 as const;
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const DIGEST = /^[a-f0-9]{64}$/;
const preparedTeams = new WeakSet<object>();
const activeMatches = new WeakSet<object>();

export interface SavedOwnedRosterReadback {
  readonly savedJourney: string;
  readonly savedRoster: string;
  /** Current in-memory Field receipt. Saved bytes must match both revisions. */
  readonly expectedJourneyRevision: string;
  readonly expectedRosterRevision: string;
}

export interface OwnedFormationWire {
  readonly version: typeof VERSION;
  readonly mode: "owned-practice";
  readonly rulesId: typeof OWNED_NEARBY_RULES_ID;
  readonly rulesDigest: string;
  readonly matchId: string;
  readonly seat: BattleTeamId;
  readonly team: BattleTeamSetup;
}

/** Only `wire` is sent. Private revisions stay on the selecting phone. */
export interface PreparedOwnedTeam {
  readonly wire: OwnedFormationWire;
  readonly journeyRevision: string;
  readonly rosterRevision: string;
}

export interface OwnedMatch {
  readonly localSeat: BattleTeamId;
  readonly state: BattleState;
}

export interface OwnedChoiceReveal {
  readonly command: BattleCommand;
  readonly nonce: string;
}

export interface OwnedRoundWire {
  readonly version: typeof VERSION;
  readonly rulesId: typeof OWNED_NEARBY_RULES_ID;
  readonly rulesDigest: string;
  readonly matchId: string;
  readonly round: number;
  readonly baseRevision: string;
  readonly commands: readonly [BattleCommand, BattleCommand];
  readonly eventDigest: string;
  readonly afterRevision: string;
}

function fail(message: string): never { throw new Error(message); }

function exactRecord(value: unknown, keys: readonly string[]): value is Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(value))) return false;
  const own = Reflect.ownKeys(value);
  return own.length === keys.length && keys.every((key) => {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    return descriptor && Object.hasOwn(descriptor, "value");
  });
}

function dense(value: unknown): value is unknown[] {
  return Array.isArray(value) && Object.getPrototypeOf(value) === Array.prototype &&
    Reflect.ownKeys(value).length === value.length + 1 &&
    Array.from({ length: value.length }, (_, index) => Object.getOwnPropertyDescriptor(value, String(index)))
      .every((descriptor) => descriptor && Object.hasOwn(descriptor, "value"));
}

function boundedLabel(value: unknown): value is string {
  return typeof value === "string" && value === value.trim() && value.length >= 1 && value.length <= 28 &&
    !/[\u0000-\u001f\u007f]/.test(value);
}
function role(value: unknown): value is RoleId {
  return typeof value === "string" && (ROLE_ORDER as readonly string[]).includes(value);
}
function otherSeat(seat: BattleTeamId): BattleTeamId { return seat === "one" ? "two" : "one"; }
function requireMatch(match: OwnedMatch): void {
  if (!activeMatches.has(match)) fail("The match was not started from a checked local roster.");
}

function checkedFormation(value: unknown): OwnedFormationWire {
  if (!exactRecord(value, ["version", "mode", "rulesId", "rulesDigest", "matchId", "seat", "team"]) ||
      value.version !== VERSION || value.mode !== "owned-practice" ||
      value.rulesId !== OWNED_NEARBY_RULES_ID || value.rulesDigest !== OWNED_NEARBY_RULES_DIGEST ||
      typeof value.matchId !== "string" || !UUID.test(value.matchId) ||
      (value.seat !== "one" && value.seat !== "two")) {
    fail("The peer uses incompatible owned-battle rules or a malformed formation.");
  }
  const seat = value.seat as BattleTeamId;
  const team = value.team;
  if (!exactRecord(team, ["id", "label", "bondRole", "roster"]) || team.id !== seat ||
      team.label !== (seat === "one" ? "Host" : "Guest") || !role(team.bondRole) ||
      !dense(team.roster) || team.roster.length < 1 || team.roster.length > BATTLE_LIMITS.maximumRoster) {
    fail("The peer formation is malformed.");
  }
  const cards: QiMonCard[] = [];
  for (let index = 0; index < team.roster.length; index += 1) {
    const card = team.roster[index];
    if (!exactRecord(card, ["id", "name", "role"]) || card.id !== `${seat}-${index + 1}` ||
        !boundedLabel(card.name) || !role(card.role)) fail("The peer formation has an invalid QiMon card.");
    cards.push(Object.freeze({ id: card.id as string, name: card.name, role: card.role }));
  }
  if (team.bondRole !== cards[0].role) fail("The formation's Bond role does not match its lead QiMon.");
  return Object.freeze({ version: VERSION, mode: "owned-practice", rulesId: OWNED_NEARBY_RULES_ID,
    rulesDigest: OWNED_NEARBY_RULES_DIGEST, matchId: value.matchId, seat,
    team: Object.freeze({ id: seat, label: seat === "one" ? "Host" : "Guest", bondRole: team.bondRole,
      roster: Object.freeze(cards) }) });
}

/** Replay saved bytes and strip stable member IDs and provenance from the peer formation. */
export function prepareOwnedTeam(source: SavedOwnedRosterReadback, matchId: string,
  seat: BattleTeamId): PreparedOwnedTeam {
  if (!UUID.test(matchId) || (seat !== "one" && seat !== "two") ||
      !exactRecord(source, ["savedJourney", "savedRoster", "expectedJourneyRevision", "expectedRosterRevision"]) ||
      typeof source.savedJourney !== "string" || typeof source.savedRoster !== "string" ||
      typeof source.expectedJourneyRevision !== "string" || typeof source.expectedRosterRevision !== "string" ||
      new TextEncoder().encode(source.savedJourney).length > 4 * 1024 * 1024 ||
      new TextEncoder().encode(source.savedRoster).length > 256 * 1024) {
    fail("Saved Field bytes are unavailable or oversized.");
  }
  let parsed: unknown;
  try { parsed = parseJsonWithoutDuplicateKeys(source.savedJourney, "saved Field Journey"); }
  catch { return fail("Saved Field Journey is invalid or ambiguous."); }
  const journey = hydrateJourney(parsed);
  if (!journey || ![3, 4, 5].includes(journey.version) || serializeJourney(journey) !== source.savedJourney ||
      revisionForJourney(journey) !== source.expectedJourneyRevision) {
    fail("The saved Field Journey does not match the current checked head.");
  }
  const inspected = inspectQiMonRoster(source.savedRoster, journey);
  if (inspected.status !== "valid" || inspected.projection.revision !== source.expectedRosterRevision ||
      revisionForQiMonRoster(inspected.roster) !== source.expectedRosterRevision) {
    fail("The saved QiMon roster does not match the current checked head.");
  }
  const chosen = inspected.projection.team;
  if (chosen.length < 1 || chosen.length > BATTLE_LIMITS.maximumRoster) {
    fail("Select one to three saved QiMon before inviting a friend.");
  }
  const wire = checkedFormation({ version: VERSION, mode: "owned-practice", rulesId: OWNED_NEARBY_RULES_ID,
    rulesDigest: OWNED_NEARBY_RULES_DIGEST, matchId, seat,
    team: { id: seat, label: seat === "one" ? "Host" : "Guest", bondRole: chosen[0].role,
      roster: chosen.map((card, index) => ({ id: `${seat}-${index + 1}`, name: card.name, role: card.role })) } });
  const prepared = Object.freeze({ wire, journeyRevision: source.expectedJourneyRevision,
    rosterRevision: source.expectedRosterRevision });
  preparedTeams.add(prepared);
  return prepared;
}

/** The friend's formation is a bounded gameplay claim, not proof of remote ownership. */
export function startOwnedMatch(local: PreparedOwnedTeam, remoteValue: unknown): OwnedMatch {
  if (!preparedTeams.has(local)) fail("Local QiMon were not selected from checked saved bytes.");
  const remote = checkedFormation(remoteValue);
  if (remote.matchId !== local.wire.matchId || remote.seat !== otherSeat(local.wire.seat)) {
    fail("The peer formation belongs to another match or seat.");
  }
  const one = local.wire.seat === "one" ? local.wire.team : remote.team;
  const two = local.wire.seat === "two" ? local.wire.team : remote.team;
  const match = Object.freeze({ localSeat: local.wire.seat, state: createBattle(local.wire.matchId, one, two) });
  activeMatches.add(match);
  return match;
}

function checkedCommand(match: OwnedMatch, seat: BattleTeamId, value: unknown): BattleCommand {
  const keys = ["battleId", "round", "baseRevision", "teamId", "activeQiMonId", "action"];
  if (value && typeof value === "object" && Object.hasOwn(value, "targetQiMonId")) keys.push("targetQiMonId");
  if (!exactRecord(value, keys) || value.teamId !== seat || typeof value.action !== "string" ||
      !(BATTLE_ACTIONS as readonly string[]).includes(value.action) ||
      (Object.hasOwn(value, "targetQiMonId") && typeof value.targetQiMonId !== "string")) {
    fail("The battle command is malformed or belongs to another seat.");
  }
  const expected = createBattleCommand(match.state, seat, value.action as BattleAction,
    value.targetQiMonId as string | undefined);
  if (keys.some((key) => value[key] !== expected[key as keyof BattleCommand]) ||
      previewBattleCommand(match.state, expected) === null) fail("The battle command is stale or illegal.");
  return expected;
}

export function createOwnedCommand(match: OwnedMatch, action: BattleAction,
  targetQiMonId?: string): BattleCommand {
  requireMatch(match);
  return checkedCommand(match, match.localSeat,
    createBattleCommand(match.state, match.localSeat, action, targetQiMonId));
}

function choiceDigest(match: OwnedMatch, reveal: OwnedChoiceReveal): string {
  return sha256String(JSON.stringify([OWNED_NEARBY_RULES_ID, OWNED_NEARBY_RULES_DIGEST,
    match.state.battleId, match.state.round, battleRevision(match.state), reveal.command.teamId,
    reveal.command, reveal.nonce]));
}

/** Transport supplies a fresh random UUID nonce before revealing the command. */
export function createOwnedChoice(match: OwnedMatch, command: unknown, nonce: string):
  Readonly<{ reveal: OwnedChoiceReveal; commitment: string }> {
  requireMatch(match);
  if (!UUID.test(nonce)) fail("A fresh random choice nonce is required.");
  const reveal = Object.freeze({ command: checkedCommand(match, match.localSeat, command), nonce });
  return Object.freeze({ reveal, commitment: choiceDigest(match, reveal) });
}

export function verifyOwnedChoice(match: OwnedMatch, seat: BattleTeamId, commitment: string,
  revealed: unknown): BattleCommand {
  requireMatch(match);
  if (seat !== otherSeat(match.localSeat) || !DIGEST.test(commitment) ||
      !exactRecord(revealed, ["command", "nonce"]) || typeof revealed.nonce !== "string" || !UUID.test(revealed.nonce)) {
    fail("The friend's locked choice is malformed.");
  }
  const command = checkedCommand(match, seat, revealed.command);
  if (choiceDigest(match, { command, nonce: revealed.nonce }) !== commitment) {
    fail("The friend's revealed move differs from the locked choice.");
  }
  return command;
}

function resolved(match: OwnedMatch, own: unknown, peer: unknown): Readonly<{ match: OwnedMatch; wire: OwnedRoundWire }> {
  requireMatch(match);
  const local = checkedCommand(match, match.localSeat, own);
  const remote = checkedCommand(match, otherSeat(match.localSeat), peer);
  const one = match.localSeat === "one" ? local : remote;
  const two = match.localSeat === "two" ? local : remote;
  const result = resolveBattleRound(match.state, one, two);
  if (!result.accepted) fail(result.reason);
  const wire: OwnedRoundWire = Object.freeze({ version: VERSION, rulesId: OWNED_NEARBY_RULES_ID,
    rulesDigest: OWNED_NEARBY_RULES_DIGEST, matchId: match.state.battleId, round: match.state.round,
    baseRevision: battleRevision(match.state), commands: Object.freeze([one, two]) as readonly [BattleCommand, BattleCommand],
    eventDigest: sha256String(JSON.stringify(result.event)), afterRevision: battleRevision(result.state) });
  const next = Object.freeze({ localSeat: match.localSeat, state: result.state });
  activeMatches.add(next);
  return Object.freeze({ match: next, wire });
}

/** Both phones independently run the Field reducer; no saved state changes. */
export function resolveOwnedRound(match: OwnedMatch, own: unknown, peer: unknown):
  Readonly<{ match: OwnedMatch; wire: OwnedRoundWire }> { return resolved(match, own, peer); }

export function verifyOwnedRound(match: OwnedMatch, value: unknown): OwnedMatch {
  requireMatch(match);
  if (!exactRecord(value, ["version", "rulesId", "rulesDigest", "matchId", "round", "baseRevision",
    "commands", "eventDigest", "afterRevision"]) || value.version !== VERSION ||
      value.rulesId !== OWNED_NEARBY_RULES_ID || value.rulesDigest !== OWNED_NEARBY_RULES_DIGEST ||
      value.matchId !== match.state.battleId || value.round !== match.state.round ||
      value.baseRevision !== battleRevision(match.state) || !dense(value.commands) || value.commands.length !== 2 ||
      typeof value.eventDigest !== "string" || !DIGEST.test(value.eventDigest) ||
      typeof value.afterRevision !== "string" || !/^sha256:[a-f0-9]{64}$/.test(value.afterRevision)) {
    fail("The peer's round receipt is malformed, stale, or for different rules.");
  }
  const own = value.commands[match.localSeat === "one" ? 0 : 1];
  const peer = value.commands[match.localSeat === "one" ? 1 : 0];
  const checked = resolved(match, own, peer);
  if (checked.wire.eventDigest !== value.eventDigest || checked.wire.afterRevision !== value.afterRevision) {
    fail("The peer's round result differs from the checked Field rules.");
  }
  return checked.match;
}
