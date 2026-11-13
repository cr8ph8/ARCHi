import { describe, expect, it } from "vitest";
import {
  collectEcho, commitCareAction, commitSession, createCareIntent, createJourney, createPlaySession,
  hydrateJourney, journeyOriginSha256, revisionForJourney, serializeJourney, verifyJourneyTransition,
  type Journey, type JourneyTransitionContract,
} from "./model";

const start = "2026-11-13T00:00:00.000Z";
const later = "2026-11-13T00:01:00.000Z";
const copy = <T>(value: T): T => JSON.parse(JSON.stringify(value)) as T;
const care = (journey: Journey, action: "greet" | "rest" = "greet") =>
  commitCareAction(journey, createCareIntent(journey, action), later);

// Fixture captures an owner-approved expected event before submitting a different
// candidate to the checker. It does not confer permission to keep that candidate.
function contract(before: Journey, intended: Journey): JourneyTransitionContract {
  return Object.freeze({ schema: "archi-journey-transition/v1", originDigest: journeyOriginSha256(before),
    baseRevision: revisionForJourney(before), beforeAuthority: serializeJourney(before),
    expectedEvent: JSON.stringify(intended.events.at(-1)) });
}

function failed(before: Journey, candidate: Journey, expected: JourneyTransitionContract): string[] {
  const result = verifyJourneyTransition(before, candidate, expected);
  expect(result.accepted).toBe(false);
  return result.checks.filter((check) => check.status !== "PASS").map((check) => check.id);
}

describe("Journey continuity during an admitted operation", () => {
  it("checks every required postcondition and leaves all supplied values unchanged", () => {
    const before = createJourney("continuity", start), intended = care(before);
    const expected = contract(before, intended), original = JSON.stringify([before, intended, expected]);
    const result = verifyJourneyTransition(before, intended, expected);
    expect(result.accepted).toBe(true);
    expect(result.checks.map((check) => check.id)).toEqual([
      "contract", "snapshot", "identity", "history", "requested-effect", "scope", "replay", "projection",
    ]);
    expect(result.checks.every((check) => check.status === "PASS")).toBe(true);
    expect(Object.isFrozen(result)).toBe(true);
    expect(Object.isFrozen(result.checks)).toBe(true);
    expect(result.checks.every(Object.isFrozen)).toBe(true);
    expect(JSON.stringify([before, intended, expected])).toBe(original);
  });

  it("rejects a legal care action that is not the requested care action", () => {
    const before = createJourney("wrong-but-valid", start), intended = care(before, "rest"), other = care(before, "greet");
    const result = verifyJourneyTransition(before, other, contract(before, intended));
    expect(result.accepted).toBe(false);
    expect(result.checks.find((check) => check.id === "replay")?.status).toBe("PASS");
    expect(result.checks.find((check) => check.id === "requested-effect")?.status).toBe("FAIL");
  });

  it("rejects another legal field choice even when the identity and signals match", () => {
    const before = createJourney("field-effect", start);
    let session = createPlaySession(before);
    for (const echo of session.echoes.slice(0, 3)) session = collectEcho(session, echo.id);
    const intended = commitSession(before, session, session.proposals[0], later);
    const other = commitSession(before, session, session.proposals[1], later);
    const result = verifyJourneyTransition(before, other, contract(before, intended));
    expect(result.checks.find((check) => check.id === "identity")?.status).toBe("PASS");
    expect(result.checks.find((check) => check.id === "replay")?.status).toBe("PASS");
    expect(result.checks.find((check) => check.id === "requested-effect")?.status).toBe("FAIL");
    expect(result.accepted).toBe(false);
  });

  it("rejects a complete valid Journey belonging to another individual", () => {
    const before = createJourney("individual-one", start), intended = care(before);
    const other = care(createJourney("individual-two", start));
    expect(failed(before, other, contract(before, intended))).toContain("identity");
  });

  it("rejects a different valid history with the same origin", () => {
    const origin = createJourney("history-fork", start);
    const before = care(origin, "rest"), intended = care(before);
    const other = care(care(origin, "greet"));
    expect(journeyOriginSha256(other)).toBe(journeyOriginSha256(before));
    expect(failed(before, other, contract(before, intended))).toContain("history");
  });

  it("rejects a stale base and a base object mutated after contract capture", () => {
    const before = createJourney("stale", start), intended = care(before), expected = contract(before, intended);
    expect(failed(intended, intended, expected)).toContain("snapshot");
    const mutated = copy(before);
    mutated.events.push(copy(intended.events[0]));
    expect(failed(mutated, intended, expected)).toContain("snapshot");
  });

  it("rejects missing and extra effects even when each candidate replays", () => {
    const before = createJourney("effect-count", start), intended = care(before), expected = contract(before, intended);
    expect(failed(before, before, expected)).toContain("history");
    expect(failed(before, care(intended), expected)).toContain("history");
  });

  it("checks derived values omitted from the serialized authority", () => {
    const before = createJourney("projection", start), intended = care(before), corrupted = copy(intended);
    corrupted.care.energy = Math.max(10, intended.care.energy - 1);
    expect(serializeJourney(corrupted)).toBe(serializeJourney(intended));
    expect(failed(before, corrupted, contract(before, intended))).toContain("projection");
  });

  it("checks allowed fields separately from whether the candidate can be replayed", () => {
    const before = createJourney("scope", start), intended = care(before), corrupted = copy(intended);
    corrupted.bond += 1;
    expect(failed(before, corrupted, contract(before, intended))).toContain("scope");
  });

  it("rejects an altered core and an unrecognized candidate field", () => {
    const before = createJourney("core", start), intended = care(before), expected = contract(before, intended);
    const corrupted = copy(intended);
    (corrupted.core as unknown as { authority: string }).authority = "execute";
    expect(failed(before, corrupted, expected)).toContain("identity");
    expect(failed(before, { ...intended, reward: 100 } as Journey, expected)).toContain("scope");
  });

  it("rejects unknown fields inside a projection that this action is allowed to change", () => {
    const before = createJourney("nested-scope", start), intended = care(before);
    const careCandidate = copy(intended);
    Object.assign(careCandidate.care, { permission: "execute" });
    expect(failed(before, careCandidate, contract(before, intended))).toContain("scope");
    let session = createPlaySession(before);
    for (const echo of session.echoes.slice(0, 3)) session = collectEcho(session, echo.id);
    const field = commitSession(before, session, session.proposals[0], later), fieldCandidate = copy(field);
    Object.assign(fieldCandidate.affinities, { unapproved: 99 });
    expect(failed(before, fieldCandidate, contract(before, field))).toContain("scope");
  });

  it("requires complete replay instead of accepting the recoverable prefix of v3", () => {
    const before = createJourney("partial-replay", start), intended = care(before), corrupted = copy(intended);
    corrupted.events.push({ ...copy(intended.events[0]), sequence: 2, eventId: "invalid" });
    expect(hydrateJourney(JSON.parse(serializeJourney(corrupted)))?.events).toHaveLength(1);
    expect(failed(before, corrupted, contract(before, intended))).toContain("replay");
  });

  it("does not execute accessors or accept cycles", () => {
    const before = createJourney("plain-data", start), intended = care(before), expected = contract(before, intended);
    let reads = 0;
    const accessor = { ...intended };
    Object.defineProperty(accessor, "care", { enumerable: true, get() { reads += 1; throw new Error("Getter ran"); } });
    expect(failed(before, accessor, expected)).toContain("contract");
    expect(reads).toBe(0);
    const cyclic = copy(intended) as Journey & { loop?: unknown };
    cyclic.loop = cyclic;
    expect(failed(before, cyclic, expected)).toContain("contract");
  });

  it("fails closed on checker errors and cannot be promoted by submitted PASS fields", () => {
    const before = createJourney("no-promoter", start), intended = care(before), expected = contract(before, intended);
    const malformed = verifyJourneyTransition(before, intended, { ...expected, expectedEvent: "{" });
    expect(malformed.accepted).toBe(false);
    expect(malformed.checks[0].status).toBe("ERROR");
    const promoted = { ...expected, checks: [{ status: "PASS" }], accepted: true };
    expect(failed(before, intended, promoted)).toContain("contract");
  });

  it("retains the same identity and history after saving and reopening the admitted result", () => {
    const before = createJourney("reopen", start), intended = care(before);
    const restored = hydrateJourney(JSON.parse(serializeJourney(intended)))!;
    expect(verifyJourneyTransition(before, restored, contract(before, intended)).accepted).toBe(true);
    expect(journeyOriginSha256(restored)).toBe(journeyOriginSha256(before));
    expect(restored.events).toEqual(intended.events);
  });
});
