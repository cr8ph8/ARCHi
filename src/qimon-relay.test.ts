import { describe, expect, it } from "vitest";
import { battleRevision, createBattle, createBattleCommand, resolveBattleRound,
  type BattleTeamId, type BattleTeamSetup } from "./battle-engine";
import { ROLE_ORDER, type RoleId } from "./model";
import { availableRelayTargets, createRelayBattle, createRelayCommand, relayRevision,
  replayRelayBattle, resolveRelayRound, type RelayAction, type RelayBattleState,
  type RelayCommand, type RelayEligibility, type RelayPairEdge, type RelayTeamSelection } from "./qimon-relay";

function formation(id: BattleTeamId, roles: readonly RoleId[]): BattleTeamSetup {
  return { id, label: id === "one" ? "Owned team" : "Practice partner", bondRole: roles[0],
    roster: roles.map((role, index) => ({ id: `${id}-member-${index + 1}`,
      name: `Member ${index + 1}`, role })) };
}

function owned(id: BattleTeamId, roles: readonly RoleId[], pairs: readonly [number, number][]): RelayTeamSelection {
  const team = formation(id, roles);
  const edges: RelayPairEdge[] = pairs.map(([a, b], index) => ({ id: `${id}-pair-${index + 1}`,
    members: [team.roster[a].id, team.roster[b].id], sourceEventId: `event-${id}-${index + 1}` }));
  return { formation: team, eligibility: { source: "owned", originDigest: id === "one" ? "a".repeat(64) : "b".repeat(64),
    rosterRevision: `roster-sha256:${id === "one" ? "c".repeat(64) : "d".repeat(64)}`,
    selectedMemberIds: team.roster.map((member) => member.id), pairEdges: edges } };
}

function practice(id: BattleTeamId, roles: readonly RoleId[]): RelayTeamSelection {
  const team = formation(id, roles);
  return { formation: team, eligibility: { source: "practice", originDigest: null, rosterRevision: null,
    selectedMemberIds: team.roster.map((member) => member.id), pairEdges: [] } };
}

function battle(one: RelayTeamSelection = owned("one", ["hearth", "guardian"], [[0, 1]]),
                two: RelayTeamSelection = practice("two", ["scout"])): RelayBattleState {
  return createRelayBattle("relay-match", one, two);
}

function resolve(state: RelayBattleState, first: RelayAction, second: RelayAction,
                 firstTarget?: string, secondTarget?: string): RelayBattleState {
  const result = resolveRelayRound(state, createRelayCommand(state, "one", first, firstTarget),
    createRelayCommand(state, "two", second, secondTarget));
  expect(result.accepted).toBe(true);
  if (!result.accepted) throw new Error(result.reason);
  return result.state;
}

describe("opt-in QiMon Relay rules v2", () => {
  it("requires an explicit selected roster and bounded, source-named earned edges", () => {
    const selected = owned("one", ["hearth", "guardian"], [[0, 1]]);
    expect(() => battle({ ...selected, eligibility: { ...selected.eligibility,
      selectedMemberIds: [selected.formation.roster[0].id] } })).toThrow("explicitly selected");
    expect(() => battle({ ...selected, eligibility: { ...selected.eligibility,
      pairEdges: [{ ...selected.eligibility.pairEdges[0], members: ["foreign", "one-member-1"] }] } })).toThrow("Invalid earned");
    expect(() => battle({ ...selected, eligibility: { ...selected.eligibility,
      pairEdges: [...selected.eligibility.pairEdges, ...selected.eligibility.pairEdges] } })).toThrow();
    expect(() => battle({ ...selected, eligibility: { ...selected.eligibility,
      source: "practice", originDigest: null, rosterRevision: null } })).toThrow("Practice members");
    const initial = battle();
    expect(initial.rulesVersion).toBe(2);
    expect(initial.revision).toBe(relayRevision(initial));
    expect(initial.revision).toBe(battle().revision);
    const reversed = { ...selected, eligibility: { pairEdges: selected.eligibility.pairEdges,
      selectedMemberIds: selected.eligibility.selectedMemberIds,
      rosterRevision: selected.eligibility.rosterRevision,
      originDigest: selected.eligibility.originDigest,
      source: selected.eligibility.source } as RelayEligibility };
    expect(battle(reversed).revision).toBe(initial.revision);
    expect(Object.isFrozen(initial.teams[0].eligibility.pairEdges[0].members)).toBe(true);
    expect(Object.isFrozen(initial.teams[0].roster[0])).toBe(true);
    expect(availableRelayTargets(initial, "one")).toEqual([{ targetQiMonId: "one-member-2", pairEdgeId: "one-pair-1" }]);
    expect(availableRelayTargets(initial, "two")).toEqual([]);
  });

  it("spends one shared Spark, charges the incoming reserve, and sends simultaneous damage to it", () => {
    const first = battle();
    const before = JSON.stringify(first);
    const next = resolve(first, "relay", "pulse", "one-member-2");
    expect(JSON.stringify(first)).toBe(before);
    expect(next.teams[0].spark).toBe(2);
    expect(next.teams[0].usedPairEdgeIds).toEqual(["one-pair-1"]);
    expect(next.teams[0].activeQiMonId).toBe("one-member-2");
    expect(next.teams[0].roster.map((member) => [member.integrity, member.charge])).toEqual([[18, 0], [11, 2]]);
    expect(next.history[0].outcomes[0]).toMatchObject({ action: "relay", actorQiMonId: "one-member-1",
      damageRecipientQiMonId: "one-member-2", sparkSpent: 1, pairEdgeId: "one-pair-1",
      chargeGranted: 2, damageDealt: 0, damageTaken: 7 });
    expect(next.teams[0].eligibility.pairEdges).toEqual(first.teams[0].eligibility.pairEdges);
    expect(availableRelayTargets(next, "one")).toEqual([]);
  });

  it("consumes a two-point Charge on the next Pulse or Guard, without restoring Spark", () => {
    const charged = resolve(battle(), "relay", "guard", "one-member-2");
    const pulse = resolve(charged, "pulse", "pulse");
    expect(pulse.history[1].outcomes[0]).toMatchObject({ damageDealt: 7, chargeConsumed: 2,
      chargeGranted: 0, sparkSpent: 0 });
    expect(pulse.teams[0].roster[1].charge).toBe(0);
    expect(pulse.teams[0].spark).toBe(2);
    const guarded = resolve(charged, "guard", "pulse");
    expect(guarded.history[1].outcomes[0]).toMatchObject({ shieldRaised: 7, damageTaken: 0,
      damageAbsorbed: 7, chargeConsumed: 2 });
    expect(guarded.teams[0].roster[1].charge).toBe(0);
    const later = resolve(guarded, "pulse", "guard");
    expect(later.history[2].outcomes[0].damageDealt).toBe(5);
  });

  it("rejects absent, self, KO, already used, Sparkless, and stale Relay commands without mutation", () => {
    const initial = battle();
    const invalidTargets = [undefined, "one-member-1", "missing"];
    for (const target of invalidTargets) {
      const result = resolveRelayRound(initial, createRelayCommand(initial, "one", "relay", target),
        createRelayCommand(initial, "two", "guard"));
      expect(result.accepted).toBe(false);
      expect(result.state).toBe(initial);
    }
    const old = createRelayCommand(initial, "one", "relay", "one-member-2");
    const after = resolve(initial, "relay", "guard", "one-member-2");
    expect(resolveRelayRound(after, old, createRelayCommand(after, "two", "guard"))).toMatchObject({
      accepted: false, state: after });
    const back = resolve(after, "swap", "guard", "one-member-1");
    const reused = resolveRelayRound(back, createRelayCommand(back, "one", "relay", "one-member-2"),
      createRelayCommand(back, "two", "guard"));
    expect(reused).toMatchObject({ accepted: false, state: back });
    const drained = { ...initial, teams: [{ ...initial.teams[0], spark: 0 }, initial.teams[1]] } as RelayBattleState;
    const corrected = { ...drained, revision: relayRevision(drained) };
    const noSpark = resolveRelayRound(corrected, createRelayCommand(corrected, "one", "relay", "one-member-2"),
      createRelayCommand(corrected, "two", "guard"));
    expect(noSpark).toMatchObject({ accepted: false, state: corrected });
    const KO = { ...initial, teams: [{ ...initial.teams[0],
      roster: [initial.teams[0].roster[0], { ...initial.teams[0].roster[1], integrity: 0 }] }, initial.teams[1]] } as RelayBattleState;
    const knockout = { ...KO, revision: relayRevision(KO) };
    expect(availableRelayTargets(knockout, "one")).toEqual([]);
    expect(resolveRelayRound(knockout, createRelayCommand(knockout, "one", "relay", "one-member-2"),
      createRelayCommand(knockout, "two", "guard"))).toMatchObject({ accepted: false, state: knockout });
  });

  it("drops Charge on Signature, Swap, entry knockout, and match end", () => {
    const charged = resolve(battle(), "relay", "guard", "one-member-2");
    const signature = resolve(charged, "signature", "guard");
    expect(signature.history[1].outcomes[0]).toMatchObject({ chargeLost: 2, chargeConsumed: 0, sparkSpent: 1 });
    expect(signature.teams[0].roster[1].charge).toBe(0);
    const swapped = resolve(charged, "swap", "guard", "one-member-1");
    expect(swapped.history[1].outcomes[0].chargeLost).toBe(2);

    let wounded = battle(owned("one", ["hearth", "guardian"], [[0, 1]]), practice("two", ["muse"]));
    wounded = resolve(wounded, "swap", "pulse", "one-member-2");
    wounded = resolve(wounded, "swap", "guard", "one-member-1");
    const KO = resolve(wounded, "relay", "signature", "one-member-2");
    expect(KO.teams[0].roster[1]).toMatchObject({ integrity: 0, charge: 0 });
    expect(KO.teams[0].usedPairEdgeIds).toEqual(["one-pair-1"]);
    expect(KO.history[2].outcomes[0]).toMatchObject({ chargeGranted: 2, chargeLost: 2,
      replacementQiMonId: "one-member-1" });

    let last = battle();
    for (let index = 0; index < 19; index += 1) last = resolve(last, "guard", "guard");
    expect(last.round).toBe(20);
    const completed = resolve(last, "relay", "guard", "one-member-2");
    expect(completed.status).toBe("complete");
    expect(completed.teams[0].roster.every((member) => member.charge === 0)).toBe(true);
    expect(completed.history.at(-1)!.outcomes[0]).toMatchObject({ chargeGranted: 2, chargeLost: 2 });
  });

  it("can chain two distinct edges but never turn a temporary charge into a lasting pair", () => {
    let state = battle(owned("one", ["hearth", "guardian", "scout"], [[0, 1], [1, 2]]));
    state = resolve(state, "relay", "guard", "one-member-2");
    state = resolve(state, "relay", "guard", "one-member-3");
    expect(state.teams[0].spark).toBe(1);
    expect(state.teams[0].usedPairEdgeIds).toEqual(["one-pair-1", "one-pair-2"]);
    expect(state.teams[0].roster.map((member) => member.charge)).toEqual([0, 0, 2]);
    expect(state.history[1].outcomes[0]).toMatchObject({ chargeLost: 2, chargeGranted: 2 });
    expect(state.teams[0].eligibility.pairEdges).toHaveLength(2);
    expect(availableRelayTargets(state, "one")).toEqual([]);
  });

  it("rejects malformed state and replays v2 only from canonical commands", () => {
    const initial = battle();
    const malformed = { ...initial, teams: [{ ...initial.teams[0],
      roster: [{ ...initial.teams[0].roster[0], charge: 3 }, initial.teams[0].roster[1]] }, initial.teams[1]] } as RelayBattleState;
    const invalid = { ...malformed, revision: relayRevision(malformed) };
    expect(resolveRelayRound(invalid, createRelayCommand(initial, "one", "guard"),
      createRelayCommand(initial, "two", "guard"))).toMatchObject({ accepted: false, state: invalid });

    let state = initial;
    const commands: [RelayCommand, RelayCommand][] = [];
    while (state.status === "active") {
      const pair: [RelayCommand, RelayCommand] = [createRelayCommand(state, "one",
        state.round === 1 ? "relay" : "guard", state.round === 1 ? "one-member-2" : undefined),
      createRelayCommand(state, "two", "guard")];
      commands.push(pair);
      const result = resolveRelayRound(state, ...pair);
      if (!result.accepted) throw new Error(result.reason);
      state = result.state;
    }
    const input = { rulesVersion: 2, battleId: "relay-match",
      selections: [owned("one", ["hearth", "guardian"], [[0, 1]]), practice("two", ["scout"])], commands };
    const replayed = replayRelayBattle(input);
    expect(replayed.state).toEqual(state);
    expect(replayed.digest).toBe(replayRelayBattle(input).digest);
    const reordered = commands.map((pair) => pair.map((command) => ({
      action: command.action, activeQiMonId: command.activeQiMonId, teamId: command.teamId,
      baseRevision: command.baseRevision, round: command.round, battleId: command.battleId,
      ...(command.targetQiMonId === undefined ? {} : { targetQiMonId: command.targetQiMonId }),
    })));
    expect(replayRelayBattle({ ...input, commands: reordered }).state).toEqual(state);
    expect(() => replayRelayBattle({ ...input, rulesVersion: 1 })).toThrow("v2");
    expect(() => replayRelayBattle({ ...input, commands: [[{ ...commands[0][0],
      baseRevision: "sha256:bad" }, commands[0][1]], ...commands.slice(1)] })).toThrow("Stale");
    expect(() => replayRelayBattle({ ...input, commands: [
      [{ ...commands[0][0], action: "surrender" }, commands[0][1]], ...commands.slice(1)] })).toThrow("non-surrender");
  });

  it("leaves the v1 reducer and its replay revision untouched", () => {
    const one = formation("one", ["hearth", "guardian"]);
    const two = formation("two", ["scout"]);
    const v1 = createBattle("same-match", one, two);
    const revision = battleRevision(v1);
    const original = resolveBattleRound(v1, createBattleCommand(v1, "one", "swap", one.roster[1].id),
      createBattleCommand(v1, "two", "pulse"));
    battle(owned("one", ["hearth", "guardian"], [[0, 1]]), practice("two", ["scout"]));
    const repeated = resolveBattleRound(v1, createBattleCommand(v1, "one", "swap", one.roster[1].id),
      createBattleCommand(v1, "two", "pulse"));
    expect(battleRevision(v1)).toBe(revision);
    expect(repeated).toEqual(original);
    expect(v1.schema).toBe(1);
  });

  it("uses the established uncharged move effects for every role", () => {
    for (const role of ROLE_ORDER) {
      for (const action of ["pulse", "guard", "signature"] as const) {
        const one = formation("one", [role]);
        const two = formation("two", ["guardian"]);
        const v1 = createBattle(`parity-${role}-${action}`, one, two);
        const v2 = createRelayBattle(`parity-${role}-${action}`, practice("one", [role]), practice("two", ["guardian"]));
        const old = resolveBattleRound(v1, createBattleCommand(v1, "one", action),
          createBattleCommand(v1, "two", "guard"));
        const next = resolveRelayRound(v2, createRelayCommand(v2, "one", action),
          createRelayCommand(v2, "two", "guard"));
        expect(old.accepted && next.accepted).toBe(true);
        if (!old.accepted || !next.accepted) throw new Error("Ordinary move unexpectedly rejected");
        expect(next.state.teams.map((team) => ({ spark: team.spark, activeQiMonId: team.activeQiMonId,
          roster: team.roster.map(({ charge: _charge, ...member }) => member) }))).toEqual(
          old.state.teams.map((team) => ({ spark: team.spark, activeQiMonId: team.activeQiMonId,
            roster: team.roster })));
        expect(next.event.outcomes.map(({ pairEdgeId: _edge, chargeGranted: _grant,
          chargeConsumed: _consumed, chargeLost: _lost, ...outcome }) => outcome)).toEqual(old.event.outcomes);
      }
    }
  });
});
