import { describe, expect, it } from "vitest";
import { choosePracticeCommand, createBattle, previewBattleCommand } from "./battle-engine";
import { collectEcho, commitSession, createJourney, createPlaySession, revisionForJourney,
  serializeJourney, sha256String } from "./model";
import { assessQiMonMemory, createQiMonRoster, discoverQiMon, inspectQiMonRoster, inviteQiMon,
  projectQiMonRoster, qiMonMemorySources, QIMON_MEMORY_CONTEXT, revisionForQiMonRoster,
  serializeQiMonRoster, selectQiMonTeam, QIMON_ROSTER_LIMITS, type QiMonMemoryAssessment } from "./qimon-roster";
import { evaluateMemoryInfluence, rankQiMonPracticeChoices, type MemoryInfluenceInput } from "./qimon-memory-influence";

const at = (minute: number): string => new Date(Date.UTC(2026, 9, 28, 0, minute)).toISOString();
const row = (changes: Partial<MemoryInfluenceInput> = {}): MemoryInfluenceInput => ({ sourceID: "origin-one",
  eligible: true, contextMatch: .96, retrievalSalience: .98, polarity: -1, magnitude: .9, confidence: .92, ...changes });

function fixture() {
  const original = createJourney("memory-influence", at(0));
  let roster = createQiMonRoster(original, at(0));
  let session = createPlaySession(original);
  for (const echo of session.echoes.slice(0, 3)) session = collectEcho(session, echo.id);
  const journey = commitSession(original, session, session.proposals[0], at(1));
  const sourceEventId = journey.events.at(-1)!.eventId;
  roster = discoverQiMon(journey, roster, sourceEventId, revisionForQiMonRoster(roster), revisionForJourney(journey), at(2));
  roster = inviteQiMon(journey, roster, projectQiMonRoster(journey, roster).offers[0].id,
    revisionForQiMonRoster(roster), revisionForJourney(journey), at(3));
  const member = projectQiMonRoster(journey, roster).members[0];
  const battle = createBattle("memory-practice", { id: "one", label: "Your recruit", bondRole: member.card.role,
    roster: [member.card] }, { id: "two", label: "Practice partner", bondRole: "guardian",
    roster: [{ id: "practice-guardian", name: "Guardian", role: "guardian" }] });
  const assessment: QiMonMemoryAssessment = { memberId: member.id, sourceEventId, context: QIMON_MEMORY_CONTEXT,
    targetAction: "guard", polarity: 1, magnitude: 1, confidence: 1, retrievalSalience: 1 };
  return { original, journey, roster, member, battle, assessment };
}

describe("bounded memory influence", () => {
  it("matches independent fixture arithmetic and keeps retrieval unchanged under reversal", () => {
    const negative = evaluateMemoryInfluence([row()]);
    const positive = evaluateMemoryInfluence([row({ polarity: 1 })]);
    expect(negative.rows[0].retrieval).toBeCloseTo(.9408, 12);
    expect(negative.rows[0].weight).toBeCloseTo(.7789824, 12);
    expect(negative.influence).toBeCloseTo(-.7789824 / 1.7789824, 12);
    expect(positive.rows[0].retrieval).toBe(negative.rows[0].retrieval);
    expect(positive.influence).toBe(-negative.influence);
    expect(evaluateMemoryInfluence([row({ magnitude: 0 })]).rows[0].retrieval).toBe(negative.rows[0].retrieval);
    expect(evaluateMemoryInfluence([row({ confidence: 0 })]).rows[0].retrieval).toBe(negative.rows[0].retrieval);
  });

  it("separates unassessed, neutral and opposing evidence; weak evidence remains weak", () => {
    const positive = row({ polarity: 1, contextMatch: 1, retrievalSalience: 1, magnitude: 1, confidence: 1 });
    const unknown = evaluateMemoryInfluence([positive, row({ sourceID: "two", polarity: null })]);
    const neutral = evaluateMemoryInfluence([positive, row({ sourceID: "two", polarity: 0 })]);
    expect(unknown.influence).toBe(.5);
    expect(unknown.unassessedCount).toBe(1);
    expect(neutral.influence).toBeLessThan(.5);
    expect(neutral.neutralMass).toBeCloseTo(.7789824, 12);
    const opposed = evaluateMemoryInfluence([positive, { ...positive, sourceID: "two", polarity: -1 }]);
    expect(opposed.influence).toBe(0); expect(opposed.positiveMass).toBe(1); expect(opposed.negativeMass).toBe(1);
    expect(evaluateMemoryInfluence([row({ magnitude: .000001 })]).influence).toBeGreaterThan(-.000001);
    const excluded = evaluateMemoryInfluence([row({ eligible: false })]);
    expect(excluded.influence).toBe(0); expect(excluded.rows[0].retrieval).toBe(0);
  });

  it("rejects copied origins and malformed controls and stays bounded", () => {
    expect(() => evaluateMemoryInfluence([row(), row()])).toThrow(/unique/);
    for (const number of [NaN, Infinity, -.01, 1.01]) {
      expect(() => evaluateMemoryInfluence([row({ confidence: number })])).toThrow();
      expect(() => evaluateMemoryInfluence([row({ retrievalSalience: number })])).toThrow();
    }
    const many = Array.from({ length: 256 }, (_, index) => row({ sourceID: String(index), polarity: 1 }));
    expect(evaluateMemoryInfluence(many).influence).toBeLessThan(1);
    expect(evaluateMemoryInfluence(many.map((value) => ({ ...value, polarity: -1 as const }))).influence).toBeGreaterThan(-1);
  });
});

describe("QiMon roster memory integration", () => {
  it("preserves v1 authority and public-state policy until an explicit assessment", () => {
    const { journey, roster, battle } = fixture();
    const archive = serializeQiMonRoster(roster, journey, at(4));
    expect(JSON.parse(archive).archiveVersion).toBe(1);
    expect(roster.version).toBe(1);
    const restored = inspectQiMonRoster(archive, journey);
    expect(restored.status).toBe("valid");
    if (restored.status !== "valid") throw new Error(restored.message);
    expect(serializeQiMonRoster(restored.roster, journey, at(4))).toBe(archive);
    expect(rankQiMonPracticeChoices(battle, "one", journey, roster)[0].command)
      .toEqual(choosePracticeCommand(battle, "one"));
    expect(projectQiMonRoster(journey, roster).memoryInfluences).toHaveLength(0);
  });

  it("persists a reversible assessment in the existing owner and changes a real legal recommendation", () => {
    const { journey, roster, battle, assessment } = fixture();
    const baseline = choosePracticeCommand(battle, "one");
    const targetAction = baseline.action === "guard" ? "pulse" : "guard";
    const before = { journey: serializeJourney(journey), battle: JSON.stringify(battle), members: projectQiMonRoster(journey, roster).members };
    const positive = assessQiMonMemory(journey, roster, { ...assessment, targetAction },
      revisionForQiMonRoster(roster), revisionForJourney(journey), at(4));
    expect(positive.version).toBe(2);
    expect(positive.events.slice(0, roster.events.length)).toEqual(roster.events);
    const ranking = rankQiMonPracticeChoices(battle, "one", journey, positive);
    expect(ranking[0].command.action).toBe(targetAction);
    expect(previewBattleCommand(battle, ranking[0].command)).not.toBeNull();
    expect(ranking[0].memory.rows[0].retrieval).toBe(1);
    const negative = assessQiMonMemory(journey, positive, { ...assessment, targetAction, polarity: -1 },
      revisionForQiMonRoster(positive), revisionForJourney(journey), at(5));
    const reversed = rankQiMonPracticeChoices(battle, "one", journey, negative);
    expect(reversed[0].command).toEqual(baseline);
    const target = reversed.find((choice) => choice.command.action === targetAction)!;
    expect(target.memory.rows[0].retrieval).toBe(1);
    expect(target.memory.influence).toBe(-.5);
    expect(projectQiMonRoster(journey, negative).memoryInfluences).toHaveLength(1);
    expect(projectQiMonRoster(journey, negative).members).toEqual(before.members);
    expect(serializeJourney(journey)).toBe(before.journey); expect(JSON.stringify(battle)).toBe(before.battle);
    const archive = serializeQiMonRoster(negative, journey, at(6));
    expect(JSON.parse(archive).archiveVersion).toBe(2);
    const reloaded = inspectQiMonRoster(archive, journey);
    expect(reloaded.status).toBe("valid");
    if (reloaded.status !== "valid") throw new Error(reloaded.message);
    expect(rankQiMonPracticeChoices(battle, "one", journey, reloaded.roster)).toEqual(reversed);
    const unassessed = assessQiMonMemory(journey, negative, { ...assessment, targetAction, polarity: null },
      revisionForQiMonRoster(negative), revisionForJourney(journey), at(7));
    expect(rankQiMonPracticeChoices(battle, "one", journey, unassessed)[0].command).toEqual(baseline);
  });

  it("isolates actions and recruited members and never invents an assessment from retrieval", () => {
    const { journey, roster, member, battle, assessment } = fixture();
    const assessed = assessQiMonMemory(journey, roster, assessment,
      revisionForQiMonRoster(roster), revisionForJourney(journey), at(4));
    const before = serializeQiMonRoster(assessed, journey, at(5));
    for (let index = 0; index < 5; index += 1) {
      const ranked = rankQiMonPracticeChoices(battle, "one", journey, assessed);
      expect(ranked.find((choice) => choice.command.action === "pulse")!.memory.rows).toHaveLength(0);
      expect(qiMonMemorySources(journey, assessed, member.id)).toHaveLength(1);
      expect(qiMonMemorySources(journey, assessed, "foreign-member")).toHaveLength(0);
    }
    expect(rankQiMonPracticeChoices(battle, "two", journey, assessed)).toHaveLength(0);
    expect(serializeQiMonRoster(assessed, journey, at(5))).toBe(before);
  });

  it("fails closed for changed, missing or foreign source authority and rejects forged digests", () => {
    const { original, journey, roster, battle, assessment } = fixture();
    const assessed = assessQiMonMemory(journey, roster, assessment,
      revisionForQiMonRoster(roster), revisionForJourney(journey), at(4));
    expect(() => rankQiMonPracticeChoices(battle, "one", original, assessed)).toThrow();
    expect(() => rankQiMonPracticeChoices(battle, "one", createJourney("foreign", at(0)), assessed)).toThrow();
    const archive = JSON.parse(serializeQiMonRoster(assessed, journey, at(5)));
    archive.authority.events.at(-1).action.sourceEventSha256 = "0".repeat(64);
    archive.manifest.authoritySha256 = sha256String(JSON.stringify(archive.authority));
    expect(inspectQiMonRoster(JSON.stringify(archive), journey).status).toBe("invalid");
    const downgraded = JSON.parse(serializeQiMonRoster(assessed, journey, at(5)));
    downgraded.archiveVersion = 1;
    expect(inspectQiMonRoster(JSON.stringify(downgraded), journey)).toMatchObject({ status: "invalid", code: "unsupported-version" });
  });

  it("rejects stale edits, injected identity, unrelated sources and invalid assessments", () => {
    const { journey, roster, assessment } = fixture();
    const edit = (value: QiMonMemoryAssessment, r = revisionForQiMonRoster(roster), j = revisionForJourney(journey)) =>
      assessQiMonMemory(journey, roster, value, r, j, at(4));
    expect(() => edit(assessment, "stale")).toThrow(/changed/);
    expect(() => edit(assessment, revisionForQiMonRoster(roster), "stale")).toThrow(/changed/);
    expect(() => edit({ ...assessment, memberId: "foreign" })).toThrow(/recruit/);
    expect(() => edit({ ...assessment, sourceEventId: "missing" })).toThrow(/source event/);
    expect(() => edit({ ...assessment, context: "relay-v2" } as unknown as QiMonMemoryAssessment)).toThrow(/supported/);
    expect(() => edit({ ...assessment, sourceEventSha256: "fake" } as QiMonMemoryAssessment)).toThrow(/unknown/);
    for (const key of ["magnitude", "confidence", "retrievalSalience"] as const) {
      for (const value of [-1, NaN, Infinity, 1.01]) expect(() => edit({ ...assessment, [key]: value })).toThrow();
    }
    const assessed = edit(assessment);
    expect(() => assessQiMonMemory(journey, assessed, assessment, revisionForQiMonRoster(assessed), revisionForJourney(journey), at(5)))
      .toThrow(/already assessed/);
  });

  it("reserves enough history to withdraw every assessed relation at the event limit", () => {
    const { journey, roster, member, battle, assessment } = fixture();
    let current = roster;
    let polarity: -1 | 1 = 1;
    while (current.events.length < QIMON_ROSTER_LIMITS.events - 1) {
      current = assessQiMonMemory(journey, current, { ...assessment, polarity },
        revisionForQiMonRoster(current), revisionForJourney(journey), at(4));
      polarity = polarity === 1 ? -1 : 1;
    }
    expect(() => assessQiMonMemory(journey, current, { ...assessment, polarity },
      revisionForQiMonRoster(current), revisionForJourney(journey), at(5))).toThrow(/retain an event slot/);
    expect(() => selectQiMonTeam(journey, current, [member.id], revisionForQiMonRoster(current), revisionForJourney(journey), at(5)))
      .toThrow(/retain an event slot/);
    const withdrawn = assessQiMonMemory(journey, current, { ...assessment, polarity: null },
      revisionForQiMonRoster(current), revisionForJourney(journey), at(6));
    expect(withdrawn.events).toHaveLength(QIMON_ROSTER_LIMITS.events);
    expect(rankQiMonPracticeChoices(battle, "one", journey, withdrawn)[0].command).toEqual(choosePracticeCommand(battle, "one"));
    expect(inspectQiMonRoster(serializeQiMonRoster(withdrawn, journey, at(7)), journey).status).toBe("valid");
  });
});
