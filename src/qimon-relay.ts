import {
  BATTLE_LIMITS, createBattle, createBattleCommand, previewBattleCommand,
  type BattleAction, type BattleOutcome, type BattleQiMonState, type BattleState,
  type BattleTeamId, type BattleTeamSetup, type BattleTeamState, type BattleWinner,
} from "./battle-engine";
import { sha256String } from "./model";

/** Opt-in battle rules. Nothing in this module writes a Journey or roster. */
export const RELAY_RULES_VERSION = 2 as const;
export const RELAY_CHARGE_LIMIT = 2 as const;

export interface RelayPairEdge {
  readonly id: string;
  readonly members: readonly [string, string];
  /** Exact kept practice event supplied by a validated roster projection. */
  readonly sourceEventId: string;
}

export interface RelayEligibility {
  readonly source: "owned" | "practice";
  readonly originDigest: string | null;
  /** Exact roster-sha256 revision; null for a clearly labeled practice side. */
  readonly rosterRevision: string | null;
  /** Exact selected formation, in order. This is not an ownership proof. */
  readonly selectedMemberIds: readonly string[];
  readonly pairEdges: readonly RelayPairEdge[];
}

export interface RelayTeamSelection {
  readonly formation: BattleTeamSetup;
  /** The caller must obtain owned edges from the current validated roster. */
  readonly eligibility: RelayEligibility;
}

export interface RelayQiMonState extends BattleQiMonState {
  readonly charge: number;
}

export interface RelayTeamState extends Omit<BattleTeamState, "roster"> {
  readonly roster: readonly RelayQiMonState[];
  readonly eligibility: RelayEligibility;
  readonly usedPairEdgeIds: readonly string[];
}

export type RelayAction = BattleAction | "relay";
export interface RelayCommand {
  readonly battleId: string;
  readonly round: number;
  readonly baseRevision: string;
  readonly teamId: BattleTeamId;
  readonly activeQiMonId: string;
  readonly action: RelayAction;
  readonly targetQiMonId?: string;
}

export interface RelayOutcome extends Omit<BattleOutcome, "action"> {
  readonly action: RelayAction;
  readonly pairEdgeId: string | null;
  readonly chargeGranted: number;
  readonly chargeConsumed: number;
  readonly chargeLost: number;
}

export interface RelayRoundEvent {
  readonly round: number;
  readonly baseRevision: string;
  readonly commands: readonly [RelayCommand, RelayCommand];
  readonly outcomes: readonly [RelayOutcome, RelayOutcome];
  readonly winner: BattleWinner;
}

export interface RelayBattleState {
  readonly rulesVersion: typeof RELAY_RULES_VERSION;
  readonly battleId: string;
  readonly round: number;
  readonly status: "active" | "complete";
  readonly winner: BattleWinner;
  readonly teams: readonly [RelayTeamState, RelayTeamState];
  readonly history: readonly RelayRoundEvent[];
  readonly revision: string;
}

export type RelayResolution =
  | { readonly accepted: true; readonly state: RelayBattleState; readonly event: RelayRoundEvent }
  | { readonly accepted: false; readonly state: RelayBattleState; readonly reason: string };

export interface RelayReplay {
  readonly rulesVersion: typeof RELAY_RULES_VERSION;
  readonly battleId: string;
  readonly selections: readonly [RelayTeamSelection, RelayTeamSelection];
  readonly commands: readonly (readonly [RelayCommand, RelayCommand])[];
}

type Effect = NonNullable<ReturnType<typeof previewBattleCommand>>;
type MutableMember = RelayQiMonState & { integrity: number; exposed: boolean; charge: number };
type MutableTeam = Omit<RelayTeamState, "roster" | "spark" | "activeQiMonId" | "usedPairEdgeIds"> & {
  spark: number;
  activeQiMonId: string | null;
  roster: MutableMember[];
  usedPairEdgeIds: string[];
};

const safeId = (value: unknown): value is string =>
  typeof value === "string" && /^[a-z0-9][a-z0-9-]{0,39}$/.test(value);
const digest = (value: unknown): value is string =>
  typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
const eventId = (value: unknown): value is string =>
  typeof value === "string" && /^[a-z0-9][a-z0-9:._-]{0,159}$/.test(value);
const exactKeys = (value: unknown, keys: readonly string[]): value is Record<string, unknown> =>
  value !== null && typeof value === "object" && !Array.isArray(value)
  && [Object.prototype, null].includes(Object.getPrototypeOf(value))
  && Reflect.ownKeys(value).length === keys.length
  && keys.every((key) => Object.hasOwn(value, key));
const dense = (value: unknown): value is unknown[] =>
  Array.isArray(value) && Reflect.ownKeys(value).length === value.length + 1
  && Array.from({ length: value.length }, (_, index) => Object.hasOwn(value, index)).every(Boolean);

function validateEligibility(formation: BattleTeamSetup, eligibility: RelayEligibility): void {
  if (!formation || !eligibility || !dense(formation.roster) || !dense(eligibility.selectedMemberIds)
      || !dense(eligibility.pairEdges)
      || !exactKeys(eligibility, ["source", "originDigest", "rosterRevision", "selectedMemberIds", "pairEdges"])) {
    throw new Error("Relay formation is incomplete.");
  }
  const selected = formation.roster.map((member) => member.id);
  if (selected.length !== eligibility.selectedMemberIds.length
      || selected.some((id, index) => id !== eligibility.selectedMemberIds[index])) {
    throw new Error("Relay members must be explicitly selected from one roster snapshot.");
  }
  if (eligibility.source === "practice") {
    if (eligibility.originDigest !== null || eligibility.rosterRevision !== null || eligibility.pairEdges.length !== 0) {
      throw new Error("Practice members have no earned Relay edges.");
    }
    return;
  }
  if (eligibility.source !== "owned" || !digest(eligibility.originDigest)
      || typeof eligibility.rosterRevision !== "string"
      || !eligibility.rosterRevision.startsWith("roster-sha256:")
      || !digest(eligibility.rosterRevision.slice("roster-sha256:".length))) {
    throw new Error("Owned Relay selection needs a current origin and roster revision.");
  }
  if (eligibility.pairEdges.length > selected.length - 1) throw new Error("Too many earned pair edges for this team.");
  const ids = new Set<string>();
  const pairs = new Set<string>();
  for (const edge of eligibility.pairEdges) {
    if (!edge || !exactKeys(edge, ["id", "members", "sourceEventId"])
        || !eventId(edge.id) || !eventId(edge.sourceEventId)
        || !dense(edge.members) || edge.members.length !== 2
        || !selected.includes(edge.members[0]) || !selected.includes(edge.members[1])
        || edge.members[0] >= edge.members[1]) throw new Error("Invalid earned pair edge.");
    const pair = `${edge.members[0]}|${edge.members[1]}`;
    if (ids.has(edge.id) || pairs.has(pair)) throw new Error("Duplicate earned pair edge.");
    ids.add(edge.id); pairs.add(pair);
  }
}

function validateSelection(selection: RelayTeamSelection): void {
  if (!selection || !exactKeys(selection, ["formation", "eligibility"])
      || !exactKeys(selection.formation, ["id", "label", "bondRole", "roster"])
      || !dense(selection.formation.roster)
      || !selection.formation.roster.every((member) => exactKeys(member, ["id", "name", "role"]))) {
    throw new Error("Relay selection must contain only public formation fields.");
  }
  validateEligibility(selection.formation, selection.eligibility);
}

function frozenEligibility(value: RelayEligibility): RelayEligibility {
  return Object.freeze({ source: value.source, originDigest: value.originDigest,
    rosterRevision: value.rosterRevision,
    selectedMemberIds: Object.freeze([...value.selectedMemberIds]),
    pairEdges: Object.freeze(value.pairEdges.map((edge) => Object.freeze({
      id: edge.id, sourceEventId: edge.sourceEventId,
      members: Object.freeze([...edge.members]) as readonly [string, string],
    }))),
  });
}

function frozenTeam(value: RelayTeamState): RelayTeamState {
  return Object.freeze({ ...value, eligibility: frozenEligibility(value.eligibility),
    roster: Object.freeze(value.roster.map((member) => Object.freeze({ ...member }))),
    usedPairEdgeIds: Object.freeze([...value.usedPairEdgeIds]),
  });
}

function frozenEvent(value: RelayRoundEvent): RelayRoundEvent {
  return Object.freeze({ ...value,
    commands: Object.freeze(value.commands.map((command) => Object.freeze({ ...command }))) as RelayRoundEvent["commands"],
    outcomes: Object.freeze(value.outcomes.map((outcome) => Object.freeze({ ...outcome }))) as RelayRoundEvent["outcomes"],
  });
}

export function relayRevision(state: Omit<RelayBattleState, "revision">): string {
  return `sha256:${sha256String(JSON.stringify({ rulesVersion: state.rulesVersion,
    battleId: state.battleId, round: state.round, status: state.status, winner: state.winner,
    teams: state.teams, history: state.history }))}`;
}

function frozenState(value: Omit<RelayBattleState, "revision">): RelayBattleState {
  const withoutRevision = { ...value,
    teams: Object.freeze(value.teams.map(frozenTeam)) as RelayBattleState["teams"],
    history: Object.freeze(value.history.map(frozenEvent)),
  };
  return Object.freeze({ ...withoutRevision, revision: relayRevision(withoutRevision) });
}

/** The formation is selected explicitly; only a validated roster owner can attest its edges. */
export function createRelayBattle(battleId: string, one: RelayTeamSelection,
                                  two: RelayTeamSelection): RelayBattleState {
  validateSelection(one);
  validateSelection(two);
  const base = createBattle(battleId, one.formation, two.formation);
  const teams = base.teams.map((team, index): RelayTeamState => ({ ...team,
    roster: team.roster.map((member) => ({ ...member, charge: 0 })),
    eligibility: index === 0 ? one.eligibility : two.eligibility,
    usedPairEdgeIds: [],
  })) as [RelayTeamState, RelayTeamState];
  return frozenState({ rulesVersion: RELAY_RULES_VERSION, battleId, round: 1,
    status: "active", winner: null, teams, history: [] });
}

function usable(state: RelayBattleState): boolean {
  try {
    if (!state || state.rulesVersion !== RELAY_RULES_VERSION || !safeId(state.battleId)
        || !Number.isSafeInteger(state.round) || state.round < 1 || state.round > BATTLE_LIMITS.maximumRounds + 1
        || !dense(state.teams) || state.teams.length !== 2 || !dense(state.history)
        || state.history.length !== state.round - 1 || !digest(state.revision.slice(7))
        || state.revision !== relayRevision(state)
        || (state.status === "active" && state.round > BATTLE_LIMITS.maximumRounds)
        || ![null, "one", "two", "draw"].includes(state.winner)
        || (state.status === "active" ? state.winner !== null : state.status !== "complete" || state.winner === null)) return false;
    const baseline = createBattle(state.battleId,
      { id: "one", label: state.teams[0].label, bondRole: state.teams[0].bondRole,
        roster: state.teams[0].roster },
      { id: "two", label: state.teams[1].label, bondRole: state.teams[1].bondRole,
        roster: state.teams[1].roster });
    for (let index = 0; index < 2; index += 1) {
      const team = state.teams[index];
      if (!team || team.id !== (index === 0 ? "one" : "two") || !dense(team.roster)
          || !dense(team.usedPairEdgeIds) || !Number.isSafeInteger(team.spark)
          || team.spark < 0 || team.spark > BATTLE_LIMITS.teamSpark) return false;
      validateEligibility({ id: team.id, label: team.label, bondRole: team.bondRole,
        roster: team.roster }, team.eligibility);
      if (team.usedPairEdgeIds.length > team.eligibility.pairEdges.length
          || new Set(team.usedPairEdgeIds).size !== team.usedPairEdgeIds.length
          || team.usedPairEdgeIds.some((id) => !team.eligibility.pairEdges.some((edge) => edge.id === id))) return false;
      const perMember = BATTLE_LIMITS.teamIntegrity / team.roster.length;
      if (team.label !== baseline.teams[index].label || team.bondRole !== baseline.teams[index].bondRole
          || team.concentration !== baseline.teams[index].concentration) return false;
      for (let memberIndex = 0; memberIndex < team.roster.length; memberIndex += 1) {
        const member = team.roster[memberIndex];
        const initial = baseline.teams[index].roster[memberIndex];
        if (!Number.isSafeInteger(member.integrity) || member.integrity < 0 || member.integrity > perMember
            || member.maximumIntegrity !== perMember || member.resonance !== BATTLE_LIMITS.teamResonance / team.roster.length
            || member.id !== initial.id || member.name !== initial.name || member.role !== initial.role
            || typeof member.exposed !== "boolean"
            || ![0, RELAY_CHARGE_LIMIT].includes(member.charge)
            || (member.charge > 0 && (member.id !== team.activeQiMonId || member.integrity === 0 || state.status === "complete"))) return false;
      }
      if (state.status === "active" && !team.roster.some((member) =>
        member.id === team.activeQiMonId && member.integrity > 0)) return false;
    }
    return true;
  } catch { return false; }
}

export function createRelayCommand(state: RelayBattleState, teamId: BattleTeamId,
                                   action: RelayAction, targetQiMonId?: string): RelayCommand {
  if (!usable(state) || state.status !== "active") throw new Error("Relay battle is not active or valid.");
  const team = state.teams[teamId === "one" ? 0 : 1];
  if (team.id !== teamId || !team.activeQiMonId) throw new Error("Unknown Relay team.");
  return Object.freeze({ battleId: state.battleId, round: state.round, baseRevision: state.revision,
    teamId, activeQiMonId: team.activeQiMonId, action,
    ...(targetQiMonId === undefined ? {} : { targetQiMonId }),
  });
}

function pairFor(team: RelayTeamState, source: string, target: string): RelayPairEdge | undefined {
  return team.eligibility.pairEdges.find((edge) => edge.members.includes(source) && edge.members.includes(target));
}

function commandIssue(state: RelayBattleState, command: RelayCommand, teamId: BattleTeamId): string | null {
  if (!command || typeof command !== "object") return "Missing Relay command.";
  const keys = ["battleId", "round", "baseRevision", "teamId", "activeQiMonId", "action"];
  if (Object.hasOwn(command, "targetQiMonId")) keys.push("targetQiMonId");
  if (!exactKeys(command, keys)) return "Unsupported Relay command fields.";
  if (command.battleId !== state.battleId || command.round !== state.round
      || command.baseRevision !== state.revision) return "Relay command is stale or from another battle.";
  const team = state.teams[teamId === "one" ? 0 : 1];
  if (command.teamId !== teamId || command.activeQiMonId !== team.activeQiMonId) return "Only the active team member may act.";
  if (!["pulse", "guard", "signature", "swap", "surrender", "relay"].includes(command.action)) return "Unknown Relay action.";
  if (command.action === "relay") {
    if (team.eligibility.source !== "owned") return "Practice cards cannot use earned Relay.";
    if (team.spark < 1) return "No shared Spark remains for Relay.";
    const target = team.roster.find((member) => member.id === command.targetQiMonId);
    if (!target || target.integrity <= 0 || target.id === team.activeQiMonId) return "Relay needs a living reserve.";
    const edge = pairFor(team, team.activeQiMonId!, target.id);
    if (!edge || team.usedPairEdgeIds.includes(edge.id)) return "No unused earned pair edge connects these members.";
    return null;
  }
  const v1 = v1View(state);
  const commandV1 = createBattleCommand(v1, teamId, command.action, command.targetQiMonId);
  return previewBattleCommand(v1, commandV1) ? null : "Invalid ordinary battle action or target.";
}

/** Available Relay targets are advice only; the version-bound command is checked again on resolve. */
export function availableRelayTargets(state: RelayBattleState, teamId: BattleTeamId): readonly {
  targetQiMonId: string; pairEdgeId: string;
}[] {
  if (!usable(state) || state.status !== "active") return Object.freeze([]);
  const team = state.teams[teamId === "one" ? 0 : 1];
  if (team.id !== teamId || team.eligibility.source !== "owned" || team.spark < 1 || !team.activeQiMonId) return Object.freeze([]);
  return Object.freeze(team.roster.flatMap((member) => {
    if (member.id === team.activeQiMonId || member.integrity <= 0) return [];
    const edge = pairFor(team, team.activeQiMonId!, member.id);
    return edge && !team.usedPairEdgeIds.includes(edge.id)
      ? [Object.freeze({ targetQiMonId: member.id, pairEdgeId: edge.id })] : [];
  }));
}

function v1View(state: RelayBattleState): BattleState {
  return { schema: 1, battleId: state.battleId, round: state.round, status: state.status,
    winner: state.winner, teams: state.teams, history: [] };
}

function emptyOutcome(team: RelayTeamState, command: RelayCommand): RelayOutcome {
  return { teamId: team.id, actorQiMonId: command.activeQiMonId,
    damageRecipientQiMonId: command.activeQiMonId, action: command.action,
    targetQiMonId: command.targetQiMonId ?? null, damageDealt: 0, damageTaken: 0,
    damageAbsorbed: 0, integrityRestored: 0, selfDamage: 0, shieldRaised: 0,
    sparkSpent: 0, exposedApplied: false, exposedCleared: false,
    alignmentBonus: 0, replacementQiMonId: null, pairEdgeId: null,
    chargeGranted: 0, chargeConsumed: 0, chargeLost: 0 };
}

function winnerFor(teams: readonly [MutableTeam, MutableTeam], atLimit: boolean): BattleWinner {
  const integrity = teams.map((team) => team.roster.reduce((sum, member) => sum + member.integrity, 0));
  if (integrity[0] <= 0 && integrity[1] <= 0) return "draw";
  if (integrity[0] <= 0) return "two";
  if (integrity[1] <= 0) return "one";
  if (!atLimit) return null;
  if (integrity[0] !== integrity[1]) return integrity[0] > integrity[1] ? "one" : "two";
  if (teams[0].spark !== teams[1].spark) return teams[0].spark > teams[1].spark ? "one" : "two";
  return "draw";
}

/** Resolves sealed commands simultaneously. Rejection returns the exact input state. */
export function resolveRelayRound(state: RelayBattleState, one: RelayCommand,
                                  two: RelayCommand): RelayResolution {
  if (!usable(state)) return Object.freeze({ accepted: false, state, reason: "Invalid Relay battle state." });
  if (state.status !== "active") return Object.freeze({ accepted: false, state, reason: "The Relay battle is complete." });
  const issue = commandIssue(state, one, "one") ?? commandIssue(state, two, "two");
  if (issue) return Object.freeze({ accepted: false, state, reason: issue });

  const teams = state.teams.map((team): MutableTeam => ({ ...team,
    roster: team.roster.map((member) => ({ ...member })),
    usedPairEdgeIds: [...team.usedPairEdgeIds],
  })) as [MutableTeam, MutableTeam];
  const commands = [one, two] as const;
  const outcomes = [emptyOutcome(teams[0], one), emptyOutcome(teams[1], two)] as [RelayOutcome, RelayOutcome];
  let winner: BattleWinner = null;
  const surrenderOne = one.action === "surrender", surrenderTwo = two.action === "surrender";
  if (surrenderOne || surrenderTwo) winner = surrenderOne && surrenderTwo ? "draw" : surrenderOne ? "two" : "one";

  if (!winner) {
    const effects = commands.map((command, index): Effect => {
      const team = teams[index];
      const sender = team.roster.find((member) => member.id === command.activeQiMonId)!;
      const previousCharge = sender.charge;
      sender.charge = 0;
      if (previousCharge > 0) {
        if (command.action === "pulse" || command.action === "guard") {
          outcomes[index] = { ...outcomes[index], chargeConsumed: previousCharge };
        } else {
          outcomes[index] = { ...outcomes[index], chargeLost: previousCharge };
        }
      }
      if (command.action === "relay") {
        const target = team.roster.find((member) => member.id === command.targetQiMonId)!;
        const edge = pairFor(team, sender.id, target.id)!;
        team.usedPairEdgeIds.push(edge.id);
        team.activeQiMonId = target.id;
        target.charge = RELAY_CHARGE_LIMIT;
        outcomes[index] = { ...outcomes[index], pairEdgeId: edge.id, chargeGranted: RELAY_CHARGE_LIMIT };
        return { damage: 0, heal: 0, selfDamage: 0, shield: 0, applyExposed: false,
          clearExposed: false, passageTargetId: null, sparkSpent: 1, alignmentBonus: 0 };
      }
      if (command.action === "swap") team.activeQiMonId = command.targetQiMonId ?? null;
      const v1 = v1View(state);
      const normal = previewBattleCommand(v1, createBattleCommand(v1,
        command.teamId, command.action as BattleAction, command.targetQiMonId))!;
      return { ...normal,
        damage: normal.damage + (command.action === "pulse" ? outcomes[index].chargeConsumed : 0),
        shield: normal.shield + (command.action === "guard" ? outcomes[index].chargeConsumed : 0),
      };
    }) as [Effect, Effect];
    const actors = teams.map((team) => team.roster.find((member) =>
      member.id === team.activeQiMonId && member.integrity > 0)!) as [MutableMember, MutableMember];

    const cleared = [false, false];
    for (let index = 0; index < 2; index += 1) {
      cleared[index] = effects[index].clearExposed && actors[index].exposed;
      if (cleared[index]) actors[index].exposed = false;
    }
    const rawIncoming = [effects[1].damage, effects[0].damage];
    const exposure = actors.map((actor, index) => actor.exposed && rawIncoming[index] > 0 ? 3 : 0);
    const outgoing = [effects[0].damage + exposure[1], effects[1].damage + exposure[0]];
    for (let index = 0; index < 2; index += 1) {
      const actor = actors[index];
      const effect = effects[index];
      const incoming = rawIncoming[index] + exposure[index];
      const absorbed = Math.min(effect.shield, incoming);
      const taken = incoming - absorbed;
      const withoutHealing = Math.max(0, actor.integrity - taken - effect.selfDamage);
      actor.integrity = Math.max(0, Math.min(actor.maximumIntegrity,
        actor.integrity - taken - effect.selfDamage + effect.heal));
      const restored = Math.max(0, actor.integrity - withoutHealing);
      if (exposure[index] > 0) actor.exposed = false;
      teamSparkSpend(teams[index], effect.sparkSpent);
      outcomes[index] = { ...outcomes[index], damageRecipientQiMonId: actor.id,
        damageDealt: outgoing[index], damageTaken: taken, damageAbsorbed: absorbed,
        integrityRestored: restored, selfDamage: effect.selfDamage, shieldRaised: effect.shield,
        sparkSpent: effect.sparkSpent, exposedCleared: cleared[index], alignmentBonus: effect.alignmentBonus };
    }
    for (let index = 0; index < 2; index += 1) {
      const opposing = actors[1 - index];
      if (effects[index].applyExposed && opposing.integrity > 0) {
        opposing.exposed = true;
        outcomes[index] = { ...outcomes[index], exposedApplied: true };
      }
      const passage = effects[index].passageTargetId;
      if (passage && teams[index].roster.some((member) => member.id === passage && member.integrity > 0)) {
        teams[index].activeQiMonId = passage;
      }
    }
    for (let index = 0; index < 2; index += 1) {
      const active = teams[index].roster.find((member) => member.id === teams[index].activeQiMonId);
      if (!active || active.integrity <= 0) {
        const replacement = teams[index].roster.find((member) => member.integrity > 0)?.id ?? null;
        teams[index].activeQiMonId = replacement;
        outcomes[index] = { ...outcomes[index], replacementQiMonId: replacement };
      }
      for (const member of teams[index].roster) {
        if (member.charge > 0 && (member.integrity <= 0 || member.id !== teams[index].activeQiMonId)) {
          outcomes[index] = { ...outcomes[index], chargeLost: outcomes[index].chargeLost + member.charge };
          member.charge = 0;
        }
      }
    }
    winner = winnerFor(teams, state.round >= BATTLE_LIMITS.maximumRounds);
  }
  if (winner) {
    for (let index = 0; index < 2; index += 1) {
      for (const member of teams[index].roster) {
        outcomes[index] = { ...outcomes[index], chargeLost: outcomes[index].chargeLost + member.charge };
        member.charge = 0;
      }
    }
  }
  const event = frozenEvent({ round: state.round, baseRevision: state.revision,
    commands: [one, two], outcomes, winner });
  const next = frozenState({ rulesVersion: RELAY_RULES_VERSION, battleId: state.battleId,
    round: state.round + 1, status: winner ? "complete" : "active", winner,
    teams, history: [...state.history, event] });
  return Object.freeze({ accepted: true, state: next, event });
}

function teamSparkSpend(team: MutableTeam, amount: number): void {
  // Signature and Relay can each spend at most one; no move creates Spark.
  team.spark -= amount;
}

/** Rebuilds outcomes from v2 inputs; v1 replays and submitted outcomes are never admitted. */
export function replayRelayBattle(value: unknown): Readonly<{ replay: RelayReplay; state: RelayBattleState; digest: string }> {
  if (!exactKeys(value, ["rulesVersion", "battleId", "selections", "commands"])
      || value.rulesVersion !== RELAY_RULES_VERSION || typeof value.battleId !== "string"
      || !dense(value.selections) || value.selections.length !== 2
      || !dense(value.commands) || value.commands.length < 1
      || value.commands.length > BATTLE_LIMITS.maximumRounds) throw new Error("Invalid v2 Relay replay.");
  const selections = value.selections as unknown as [RelayTeamSelection, RelayTeamSelection];
  let state = createRelayBattle(value.battleId, selections[0], selections[1]);
  const commands: [RelayCommand, RelayCommand][] = [];
  for (const pair of value.commands) {
    if (!dense(pair) || pair.length !== 2 || state.status !== "active") throw new Error("Invalid v2 Relay round sequence.");
    const canonical = pair.map((command, index): RelayCommand => {
      const teamId = index === 0 ? "one" : "two";
      if (!command || typeof command !== "object" || !Object.hasOwn(command, "action")
          || typeof (command as Record<string, unknown>).action !== "string"
          || !["pulse", "guard", "signature", "swap", "relay"].includes((command as Record<string, string>).action)) {
        throw new Error("A kept Relay replay needs complete non-surrender rounds.");
      }
      const record = command as Record<string, unknown>;
      const expected = createRelayCommand(state, teamId, record.action as RelayAction,
        Object.hasOwn(record, "targetQiMonId") ? record.targetQiMonId as string : undefined);
      const keys = ["battleId", "round", "baseRevision", "teamId", "activeQiMonId", "action"];
      if (Object.hasOwn(record, "targetQiMonId")) keys.push("targetQiMonId");
      if (!exactKeys(record, keys) || keys.some((key) => record[key] !== expected[key as keyof RelayCommand])) {
        throw new Error("Stale or altered v2 Relay command.");
      }
      return expected;
    }) as [RelayCommand, RelayCommand];
    const result = resolveRelayRound(state, canonical[0], canonical[1]);
    if (!result.accepted) throw new Error(result.reason);
    commands.push(canonical); state = result.state;
  }
  if (state.status !== "complete") throw new Error("Finish the v2 Relay battle before keeping a replay.");
  const replay: RelayReplay = Object.freeze({ rulesVersion: RELAY_RULES_VERSION, battleId: state.battleId,
    selections: Object.freeze(selections.map((selection) => Object.freeze({
      formation: Object.freeze({ id: selection.formation.id, label: selection.formation.label.trim(),
        bondRole: selection.formation.bondRole,
        roster: Object.freeze(selection.formation.roster.map((member) => Object.freeze({
          id: member.id, name: member.name.trim(), role: member.role,
        }))),
      }), eligibility: frozenEligibility(selection.eligibility),
    }))) as RelayReplay["selections"],
    commands: Object.freeze(commands.map((pair) => Object.freeze(pair))),
  });
  return Object.freeze({ replay, state, digest: `sha256:${sha256String(JSON.stringify(replay))}` });
}
