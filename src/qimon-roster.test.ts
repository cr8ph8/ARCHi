import { describe, expect, it } from "vitest";
import {
  choosePracticeCommand, createBattle, createBattleCommand, resolveBattleRound,
  type BattleCommand, type BattleTeamSetup, type PracticeReplay, type QiMonCard,
} from "./battle-engine";
import {
  collectEcho, commitCareAction, commitPracticeCompletion, commitSession, createCareIntent,
  createJourney, createPlaySession, journeyOriginSha256, revisionForJourney,
  type Journey, type PlayCommitEvent,
} from "./model";
import {
  QIMON_ROSTER_LIMITS, bondQiMonPair, createQiMonRoster, discoverQiMon, inspectQiMonRoster,
  inviteQiMon, projectQiMonRoster, revisionForQiMonRoster, selectQiMonTeam,
  serializeQiMonRoster, trainQiMon, type QiMonRoster,
} from "./qimon-roster";

const at = (minute: number): string => new Date(Date.UTC(2026, 8, 29, 0, minute)).toISOString();

function appendPlay(journey: Journey, minute: number, hold = false): Journey {
  let session = createPlaySession(journey);
  for (const echo of session.echoes.slice(0, 3)) session = collectEcho(session, echo.id);
  return commitSession(journey, session, hold ? "hold" : session.proposals[0], at(minute));
}

function lastPlay(journey: Journey): PlayCommitEvent {
  const event = journey.events.at(-1);
  if (event?.kind !== "play-commit") throw new Error("Expected a kept play.");
  return event;
}

function discoverAndInvite(journey: Journey, roster: QiMonRoster, minute: number): QiMonRoster {
  const discovered = discoverQiMon(journey, roster, lastPlay(journey).eventId,
    revisionForQiMonRoster(roster), revisionForJourney(journey), at(minute));
  const offer = projectQiMonRoster(journey, discovered).offers[0];
  return inviteQiMon(journey, discovered, offer.id,
    revisionForQiMonRoster(discovered), revisionForJourney(journey), at(minute));
}

function uuid(prefix: string, index: number): string {
  return `${prefix}0000000-0000-4000-8000-${String(index).padStart(12, "0")}`;
}

function keepPractice(journey: Journey, cards: readonly QiMonCard[], minute: number, index: number,
  swapAfterFirst = false, defendOnly = false): Journey {
  const battleId = uuid("a", index), sessionId = uuid("b", index);
  const one: BattleTeamSetup = { id: "one", label: "Recruited team", bondRole: cards[0].role, roster: cards };
  const two: BattleTeamSetup = { id: "two", label: "Practice partner", bondRole: "guardian",
    roster: [{ id: `partner-${index}`, name: "Practice Guardian", role: "guardian" }] };
  let state = createBattle(battleId, one, two);
  const commands: [BattleCommand, BattleCommand][] = [];
  for (let turn = 0; turn < 20 && state.status === "active"; turn += 1) {
    const player = swapAfterFirst && turn === 1
      ? createBattleCommand(state, "one", "swap", cards[1].id)
      : createBattleCommand(state, "one", defendOnly ? "guard" : "pulse");
    const partner = choosePracticeCommand(state, "two");
    const resolved = resolveBattleRound(state, player, partner);
    if (!resolved.accepted) throw new Error(resolved.reason);
    commands.push([player, partner]);
    state = resolved.state;
  }
  if (state.status !== "complete") throw new Error("The practice did not finish.");
  const replay: PracticeReplay = { rulesVersion: 1, battleId, teams: [one, two], commands };
  return commitPracticeCompletion(journey, {
    originDigest: journeyOriginSha256(journey), baseRevision: revisionForJourney(journey),
    sessionId, replay,
  }, sessionId, at(minute));
}

function setupOneRecruit() {
  let journey = createJourney("roster-seed", at(0));
  const roster = createQiMonRoster(journey, at(0));
  journey = appendPlay(journey, 1);
  const invited = discoverAndInvite(journey, roster, 2);
  return { journey, roster: invited, member: projectQiMonRoster(journey, invited).members[0] };
}

describe("source-bound local QiMon roster", () => {
  it("opens empty on an existing Journey and admits only a new kept play plus explicit invite", () => {
    const oldJourney = appendPlay(createJourney("existing-journey", at(0)), 1);
    const oldEvent = lastPlay(oldJourney);
    const roster = createQiMonRoster(oldJourney, at(2));
    expect(projectQiMonRoster(oldJourney, roster).members).toHaveLength(0);
    expect(() => discoverQiMon(oldJourney, roster, oldEvent.eventId,
      revisionForQiMonRoster(roster), revisionForJourney(oldJourney), at(3))).toThrow(/new kept Field play/);

    const journey = appendPlay(oldJourney, 4);
    const journeyBefore = JSON.stringify(journey);
    const discovered = discoverQiMon(journey, roster, lastPlay(journey).eventId,
      revisionForQiMonRoster(roster), revisionForJourney(journey), at(5));
    expect(projectQiMonRoster(journey, discovered).offers).toHaveLength(1);
    expect(projectQiMonRoster(journey, discovered).members).toHaveLength(0);
    const offer = projectQiMonRoster(journey, discovered).offers[0];
    expect(offer.card.id).toMatch(/^qm-[a-f0-9]{32}$/);
    expect(offer.card.name.length).toBeLessThanOrEqual(28);
    const invited = inviteQiMon(journey, discovered, offer.id,
      revisionForQiMonRoster(discovered), revisionForJourney(journey), at(5));
    const member = projectQiMonRoster(journey, invited).members[0];
    expect(member.card).toEqual(offer.card);
    expect(projectQiMonRoster(journey, invited).offers).toHaveLength(0);
    expect(createBattle("battle-1", { id: "one", label: "Collected team", bondRole: member.card.role,
      roster: [member.card] }, { id: "two", label: "Partner", bondRole: "guardian",
      roster: [{ id: "partner", name: "Practice", role: "guardian" }] }).status).toBe("active");
    expect(JSON.stringify(journey)).toBe(journeyBefore);
  });

  it("rejects held plays and duplicate sources while retaining offers across later care", () => {
    let journey = createJourney("source-guards", at(0));
    const roster = createQiMonRoster(journey, at(0));
    journey = appendPlay(journey, 1, true);
    expect(() => discoverQiMon(journey, roster, lastPlay(journey).eventId,
      revisionForQiMonRoster(roster), revisionForJourney(journey), at(2))).toThrow(/chosen role/);
    journey = appendPlay(journey, 3);
    const discovered = discoverQiMon(journey, roster, lastPlay(journey).eventId,
      revisionForQiMonRoster(roster), revisionForJourney(journey), at(4));
    expect(() => discoverQiMon(journey, discovered, lastPlay(journey).eventId,
      revisionForQiMonRoster(discovered), revisionForJourney(journey), at(4))).toThrow(/unused source/);
    const offer = projectQiMonRoster(journey, discovered).offers[0];
    const advanced = commitCareAction(journey, createCareIntent(journey, "greet"), at(5));
    expect(projectQiMonRoster(advanced, discovered).offers).toHaveLength(1);
    const invited = inviteQiMon(advanced, discovered, offer.id,
      revisionForQiMonRoster(discovered), revisionForJourney(advanced), at(6));
    expect(projectQiMonRoster(advanced, invited).members).toHaveLength(1);
    expect(() => projectQiMonRoster(createJourney("other-origin", at(0)), discovered)).toThrow(/another Journey origin/);
    expect(() => projectQiMonRoster(createJourney("source-guards", at(0)), discovered)).toThrow(/roster observation/);
  });

  it("credits exact one-member kept practice once, caps training, and rejects synthetic practice cards", () => {
    let { journey, roster, member } = setupOneRecruit();
    journey = keepPractice(journey, [member.card], 3, 1);
    const source = journey.events.at(-1)!.eventId;
    roster = trainQiMon(journey, roster, member.id, source,
      revisionForQiMonRoster(roster), revisionForJourney(journey), at(4));
    expect(projectQiMonRoster(journey, roster).members[0].trainingTier).toBe(1);
    expect(() => trainQiMon(journey, roster, member.id, source,
      revisionForQiMonRoster(roster), revisionForJourney(journey), at(4))).toThrow(/unused practice/);
    journey = keepPractice(journey, [{ id: "one-practice-1", name: "Synthetic", role: member.card.role }], 5, 2);
    expect(() => trainQiMon(journey, roster, member.id, journey.events.at(-1)!.eventId,
      revisionForQiMonRoster(roster), revisionForJourney(journey), at(6))).toThrow(/exact recruit/);
    for (const [minute, index] of [[7, 3], [9, 4]] as const) {
      journey = keepPractice(journey, [member.card], minute, index);
      roster = trainQiMon(journey, roster, member.id, journey.events.at(-1)!.eventId,
        revisionForQiMonRoster(roster), revisionForJourney(journey), at(minute + 1));
    }
    expect(projectQiMonRoster(journey, roster).members[0].trainingTier).toBe(QIMON_ROSTER_LIMITS.trainingTier);
    journey = keepPractice(journey, [member.card], 11, 5);
    expect(() => trainQiMon(journey, roster, member.id, journey.events.at(-1)!.eventId,
      revisionForQiMonRoster(roster), revisionForJourney(journey), at(12))).toThrow(/cannot receive another/);
  });

  it("can claim a kept practice after later care, but cannot backfill a pre-invitation practice", () => {
    let { journey, roster, member } = setupOneRecruit();
    journey = keepPractice(journey, [member.card], 3, 10);
    const practiceID = journey.events.at(-1)!.eventId;
    journey = commitCareAction(journey, createCareIntent(journey, "greet"), at(4));
    roster = trainQiMon(journey, roster, member.id, practiceID,
      revisionForQiMonRoster(roster), revisionForJourney(journey), at(5));
    expect(projectQiMonRoster(journey, roster).members[0].trainingEventIds).toEqual([practiceID]);

    let beforeInvite = createJourney("late-invite", at(0));
    const freshRoster = createQiMonRoster(beforeInvite, at(0));
    beforeInvite = appendPlay(beforeInvite, 1);
    const discovered = discoverQiMon(beforeInvite, freshRoster, lastPlay(beforeInvite).eventId,
      revisionForQiMonRoster(freshRoster), revisionForJourney(beforeInvite), at(2));
    const offer = projectQiMonRoster(beforeInvite, discovered).offers[0];
    beforeInvite = keepPractice(beforeInvite, [offer.card], 3, 11);
    const olderPracticeID = beforeInvite.events.at(-1)!.eventId;
    const invited = inviteQiMon(beforeInvite, discovered, offer.id,
      revisionForQiMonRoster(discovered), revisionForJourney(beforeInvite), at(4));
    expect(() => trainQiMon(beforeInvite, invited, offer.memberId, olderPracticeID,
      revisionForQiMonRoster(invited), revisionForJourney(beforeInvite), at(5)))
      .toThrow(/after this recruit's invitation/);
  });

  it("earns a pair only when both exact recruits act in a later kept two-member practice", () => {
    let { journey, roster, member: first } = setupOneRecruit();
    journey = appendPlay(journey, 3);
    roster = discoverAndInvite(journey, roster, 4);
    const second = projectQiMonRoster(journey, roster).members[1];

    journey = keepPractice(journey, [first.card, second.card], 5, 6, false, true);
    expect(() => bondQiMonPair(journey, roster, first.id, second.id, journey.events.at(-1)!.eventId,
      revisionForQiMonRoster(roster), revisionForJourney(journey), at(6))).toThrow(/Both recruits must act/);

    journey = keepPractice(journey, [first.card, second.card], 7, 7, true);
    const pairPracticeID = journey.events.at(-1)!.eventId;
    journey = commitCareAction(journey, createCareIntent(journey, "greet"), at(8));
    roster = bondQiMonPair(journey, roster, first.id, second.id, pairPracticeID,
      revisionForQiMonRoster(roster), revisionForJourney(journey), at(9));
    const bonds = projectQiMonRoster(journey, roster).bonds;
    expect(bonds).toHaveLength(1);
    expect(bonds[0].memberIds).toEqual([first.id, second.id].sort());
    expect(() => bondQiMonPair(journey, roster, first.id, second.id, pairPracticeID,
      revisionForQiMonRoster(roster), revisionForJourney(journey), at(9))).toThrow(/already bonded/);
  });

  it("selects up to three collected cards and round-trips a strict, source-checked sidecar", () => {
    let journey = createJourney("four-recruits", at(0));
    let roster = createQiMonRoster(journey, at(0));
    for (let member = 1; member <= 4; member += 1) {
      journey = appendPlay(journey, member * 2 - 1);
      roster = discoverAndInvite(journey, roster, member * 2);
    }
    const journeyBefore = JSON.stringify(journey);
    const members = projectQiMonRoster(journey, roster).members;
    roster = selectQiMonTeam(journey, roster, members.slice(0, 3).map((member) => member.id),
      revisionForQiMonRoster(roster), revisionForJourney(journey), at(9));
    expect(projectQiMonRoster(journey, roster).team).toEqual(members.slice(0, 3).map((member) => member.card));
    expect(() => selectQiMonTeam(journey, roster, members.map((member) => member.id),
      revisionForQiMonRoster(roster), revisionForJourney(journey), at(9))).toThrow(/one to three/);
    expect(() => selectQiMonTeam(journey, roster, [members[0].id, members[0].id],
      revisionForQiMonRoster(roster), revisionForJourney(journey), at(9))).toThrow(/distinct/);
    expect(() => selectQiMonTeam(journey, roster, ["one-practice-1"],
      revisionForQiMonRoster(roster), revisionForJourney(journey), at(9))).toThrow(/recruited/);

    const archive = serializeQiMonRoster(roster, journey, at(10));
    const restored = inspectQiMonRoster(archive, journey);
    expect(restored.status).toBe("valid");
    if (restored.status !== "valid") return;
    expect(restored.projection).toEqual(projectQiMonRoster(journey, roster));
    expect(restored.roster).toEqual(roster);
    expect(JSON.stringify(journey)).toBe(journeyBefore);
    expect(inspectQiMonRoster(archive, createJourney("foreign", at(0)))).toMatchObject({
      status: "invalid", code: "origin-mismatch",
    });
    const corrupted = JSON.parse(archive);
    corrupted.authority.events[0].action.name = "Invented QiMon";
    expect(inspectQiMonRoster(JSON.stringify(corrupted), journey)).toMatchObject({
      status: "invalid", code: "invalid-authority",
    });
    const staleManifest = JSON.parse(archive);
    staleManifest.manifest.memberCount = 999;
    expect(inspectQiMonRoster(JSON.stringify(staleManifest), journey)).toMatchObject({
      status: "invalid", code: "manifest-mismatch",
    });
    expect(inspectQiMonRoster(archive.replace('"version": 1', '"version": 1, "version": 1'), journey))
      .toMatchObject({ status: "invalid", code: "invalid-json" });
    expect(inspectQiMonRoster(archive, createJourney("four-recruits", at(0)))).toMatchObject({
      status: "invalid", code: "origin-mismatch",
    });
  });
});
