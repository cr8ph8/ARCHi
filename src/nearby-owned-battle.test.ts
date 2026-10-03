import { describe, expect, it } from "vitest";
import { battleRevision } from "./battle-engine";
import {
  collectEcho, commitSession, createJourney, createPlaySession, revisionForJourney,
  serializeJourney, type Journey,
} from "./model";
import {
  createQiMonRoster, discoverQiMon, inviteQiMon, projectQiMonRoster,
  revisionForQiMonRoster, selectQiMonTeam, serializeQiMonRoster, type QiMonRoster,
} from "./qimon-roster";
import {
  OWNED_NEARBY_RULES_DIGEST, createOwnedChoice, createOwnedCommand, prepareOwnedTeam,
  resolveOwnedRound, startOwnedMatch, verifyOwnedChoice, verifyOwnedRound,
  type SavedOwnedRosterReadback,
} from "./nearby-owned-battle";

const at = (minute: number): string => new Date(Date.UTC(2026, 8, 29, 0, minute)).toISOString();
const matchId = "11111111-1111-4111-8111-111111111111";
const hostNonce = "22222222-2222-4222-8222-222222222222";
const guestNonce = "33333333-3333-4333-8333-333333333333";

function appendPlay(journey: Journey, minute: number): Journey {
  let session = createPlaySession(journey);
  for (const echo of session.echoes.slice(0, 3)) session = collectEcho(session, echo.id);
  return commitSession(journey, session, session.proposals[0], at(minute));
}

function savedTeam(seed: string, size: number): {
  readback: SavedOwnedRosterReadback; journey: Journey; roster: QiMonRoster; privateMemberIDs: string[];
} {
  let journey = createJourney(seed, at(0));
  let roster = createQiMonRoster(journey, at(0));
  for (let index = 1; index <= size; index += 1) {
    journey = appendPlay(journey, index * 2 - 1);
    const play = journey.events.at(-1)!;
    roster = discoverQiMon(journey, roster, play.eventId,
      revisionForQiMonRoster(roster), revisionForJourney(journey), at(index * 2));
    const offer = projectQiMonRoster(journey, roster).offers[0];
    roster = inviteQiMon(journey, roster, offer.id,
      revisionForQiMonRoster(roster), revisionForJourney(journey), at(index * 2));
  }
  const privateMemberIDs = projectQiMonRoster(journey, roster).members.map((member) => member.id);
  roster = selectQiMonTeam(journey, roster, privateMemberIDs,
    revisionForQiMonRoster(roster), revisionForJourney(journey), at(size * 2 + 1));
  return { journey, roster, privateMemberIDs, readback: {
    savedJourney: serializeJourney(journey), savedRoster: serializeQiMonRoster(roster, journey, at(size * 2 + 2)),
    expectedJourneyRevision: revisionForJourney(journey), expectedRosterRevision: revisionForQiMonRoster(roster),
  } };
}

describe("session-only owned QiMon friend rules", () => {
  it("freezes only selected saved recruits and sends session aliases without provenance", () => {
    const host = savedTeam("host-origin", 3);
    const beforeJourney = host.readback.savedJourney, beforeRoster = host.readback.savedRoster;
    const prepared = prepareOwnedTeam(host.readback, matchId, "one");
    expect(prepared.wire.team.roster.map((card) => card.id)).toEqual(["one-1", "one-2", "one-3"]);
    expect(prepared.wire.team.roster.map((card) => card.role))
      .toEqual(projectQiMonRoster(host.journey, host.roster).team.map((card) => card.role));
    const wire = JSON.stringify(prepared.wire);
    for (const id of host.privateMemberIDs) expect(wire).not.toContain(id);
    expect(wire).not.toContain(prepared.journeyRevision);
    expect(wire).not.toContain(prepared.rosterRevision);
    expect(wire).not.toContain("sourceEventId");
    expect(host.readback.savedJourney).toBe(beforeJourney);
    expect(host.readback.savedRoster).toBe(beforeRoster);
  });

  it("refuses stale readback, invalid source authority, empty team, and forged local preparation", () => {
    const host = savedTeam("host-source", 1);
    expect(() => prepareOwnedTeam({ ...host.readback, expectedJourneyRevision: "older" }, matchId, "one"))
      .toThrow(/current checked head/);
    expect(() => prepareOwnedTeam({ ...host.readback, expectedRosterRevision: "older" }, matchId, "one"))
      .toThrow(/current checked head/);
    expect(() => prepareOwnedTeam({ ...host.readback, savedJourney: host.readback.savedJourney + " " }, matchId, "one"))
      .toThrow(/current checked head/);
    const existingName = projectQiMonRoster(host.journey, host.roster).members[0].card.name;
    const forged = host.readback.savedRoster.replace(existingName, "Invented QiMon");
    expect(forged).not.toBe(host.readback.savedRoster);
    expect(() => prepareOwnedTeam({ ...host.readback, savedRoster: forged }, matchId, "one"))
      .toThrow(/saved QiMon roster/);
    const remote = prepareOwnedTeam(savedTeam("guest-source", 1).readback, matchId, "two");
    expect(() => startOwnedMatch({ ...prepareOwnedTeam(host.readback, matchId, "one") }, remote.wire))
      .toThrow(/checked saved bytes/);
    const emptyRoster = createQiMonRoster(host.journey, at(3));
    expect(() => prepareOwnedTeam({ ...host.readback,
      savedRoster: serializeQiMonRoster(emptyRoster, host.journey, at(4)),
      expectedRosterRevision: revisionForQiMonRoster(emptyRoster),
    }, matchId, "one")).toThrow(/Select one to three/);
  });

  it("rejects other rules, match, seat, extra fields, duplicate aliases and private source fields", () => {
    const host = prepareOwnedTeam(savedTeam("host-wire", 2).readback, matchId, "one");
    const guest = prepareOwnedTeam(savedTeam("guest-wire", 2).readback, matchId, "two");
    expect(guest.wire.rulesDigest).toBe(OWNED_NEARBY_RULES_DIGEST);
    expect(() => startOwnedMatch(host, { ...guest.wire, rulesDigest: "0".repeat(64) }))
      .toThrow(/incompatible/);
    expect(() => startOwnedMatch(host, { ...guest.wire, matchId: hostNonce })).toThrow(/another match/);
    expect(() => startOwnedMatch(host, { ...guest.wire, seat: "one" })).toThrow(/malformed|another match/);
    expect(() => startOwnedMatch(host, { ...guest.wire, originDigest: "private" })).toThrow(/malformed formation/);
    expect(() => startOwnedMatch(host, { ...guest.wire, team: { ...guest.wire.team,
      roster: [guest.wire.team.roster[0], guest.wire.team.roster[0]],
    } })).toThrow(/invalid QiMon card/);
    expect(() => startOwnedMatch(host, { ...guest.wire, team: { ...guest.wire.team,
      roster: [{ ...guest.wire.team.roster[0], sourceEventId: "private" }],
    } })).toThrow(/invalid QiMon card/);
  });

  it("replays human choices on both phones, including swap, with identical revisions", () => {
    const hostSource = savedTeam("host-three", 3), guestSource = savedTeam("guest-three", 3);
    const host = prepareOwnedTeam(hostSource.readback, matchId, "one");
    const guest = prepareOwnedTeam(guestSource.readback, matchId, "two");
    let hostMatch = startOwnedMatch(host, guest.wire);
    let guestMatch = startOwnedMatch(guest, host.wire);
    expect(battleRevision(hostMatch.state)).toBe(battleRevision(guestMatch.state));
    const hostCommand = createOwnedCommand(hostMatch, "swap", "one-2");
    const guestCommand = createOwnedCommand(guestMatch, "pulse");
    const hostChoice = createOwnedChoice(hostMatch, hostCommand, hostNonce);
    const guestChoice = createOwnedChoice(guestMatch, guestCommand, guestNonce);
    expect(verifyOwnedChoice(hostMatch, "two", guestChoice.commitment, guestChoice.reveal)).toEqual(guestCommand);
    expect(verifyOwnedChoice(guestMatch, "one", hostChoice.commitment, hostChoice.reveal)).toEqual(hostCommand);
    const hostRound = resolveOwnedRound(hostMatch, hostCommand, guestCommand);
    guestMatch = verifyOwnedRound(guestMatch, hostRound.wire);
    hostMatch = hostRound.match;
    expect(battleRevision(hostMatch.state)).toBe(battleRevision(guestMatch.state));
    expect(hostMatch.state.teams[0].activeQiMonId).toBe("one-2");
    expect(hostMatch.state.history).toHaveLength(1);
    expect(JSON.stringify(hostRound.wire)).not.toContain(hostSource.privateMemberIDs[0]);
    expect(() => resolveOwnedRound(hostMatch, hostCommand, guestCommand)).toThrow(/stale/);
    expect(() => verifyOwnedRound(guestMatch, hostRound.wire)).toThrow(/stale/);
  });

  it("rejects changed reveals and forged round receipts before advancing", () => {
    const host = prepareOwnedTeam(savedTeam("host-tamper", 1).readback, matchId, "one");
    const guest = prepareOwnedTeam(savedTeam("guest-tamper", 1).readback, matchId, "two");
    const hostMatch = startOwnedMatch(host, guest.wire);
    const guestMatch = startOwnedMatch(guest, host.wire);
    const hostCommand = createOwnedCommand(hostMatch, "pulse");
    const guestCommand = createOwnedCommand(guestMatch, "guard");
    const locked = createOwnedChoice(guestMatch, guestCommand, guestNonce);
    expect(() => verifyOwnedChoice(hostMatch, "two", locked.commitment,
      { ...locked.reveal, nonce: hostNonce })).toThrow(/differs/);
    expect(() => verifyOwnedChoice(hostMatch, "two", locked.commitment,
      { ...locked.reveal, command: { ...guestCommand, action: "pulse" } })).toThrow(/differs/);
    expect(() => verifyOwnedChoice(hostMatch, "two", locked.commitment,
      { ...locked.reveal, profile: "private" })).toThrow(/malformed/);
    const round = resolveOwnedRound(hostMatch, hostCommand, guestCommand);
    expect(() => verifyOwnedRound(guestMatch, { ...round.wire, eventDigest: "0".repeat(64) }))
      .toThrow(/differs/);
    expect(() => verifyOwnedRound(guestMatch, { ...round.wire, afterRevision: "sha256:" + "0".repeat(64) }))
      .toThrow(/differs/);
    expect(() => verifyOwnedRound(guestMatch, { ...round.wire, notes: "private" })).toThrow(/malformed/);
    expect(() => verifyOwnedRound(guestMatch, { ...round.wire, commands: [guestCommand, hostCommand] }))
      .toThrow(/another seat/);
    expect(guestMatch.state.round).toBe(1);
  });

  it("finishes a bounded 20-round human draw without creating a saved practice", () => {
    const hostSource = savedTeam("host-draw", 1), guestSource = savedTeam("guest-draw", 1);
    const hostBytes = [hostSource.readback.savedJourney, hostSource.readback.savedRoster];
    const guestBytes = [guestSource.readback.savedJourney, guestSource.readback.savedRoster];
    const host = prepareOwnedTeam(hostSource.readback, matchId, "one");
    const guest = prepareOwnedTeam(guestSource.readback, matchId, "two");
    let hostMatch = startOwnedMatch(host, guest.wire);
    let guestMatch = startOwnedMatch(guest, host.wire);
    for (let round = 1; round <= 20; round += 1) {
      const hostCommand = createOwnedCommand(hostMatch, "guard");
      const guestCommand = createOwnedCommand(guestMatch, "guard");
      const result = resolveOwnedRound(hostMatch, hostCommand, guestCommand);
      guestMatch = verifyOwnedRound(guestMatch, result.wire);
      hostMatch = result.match;
      expect(battleRevision(hostMatch.state)).toBe(battleRevision(guestMatch.state));
    }
    expect(hostMatch.state.status).toBe("complete");
    expect(hostMatch.state.winner).toBe("draw");
    expect(hostMatch.state.history).toHaveLength(20);
    expect(() => createOwnedCommand(hostMatch, "pulse")).toThrow();
    expect([hostSource.readback.savedJourney, hostSource.readback.savedRoster]).toEqual(hostBytes);
    expect([guestSource.readback.savedJourney, guestSource.readback.savedRoster]).toEqual(guestBytes);
  });
});
