import assert from "node:assert/strict";
import test from "node:test";
import {
  createImaginationRequest,
  evaluateImagination,
  MAX_RESPONSE_BYTES,
} from "../src/planner.ts";
import type { ImaginationRequest, ReviewResult } from "../src/planner.ts";

// Hand-written transitions keep the expectations independent of the simulator.
const START = ["#######", "#     #", "# @$. #", "#     #", "#######"];
const SOLVED = ["#######", "#     #", "#  @* #", "#     #", "#######"];
const UP = ["#######", "# @   #", "#  $. #", "#     #", "#######"];
const UP_RIGHT = ["#######", "#  @  #", "#  $. #", "#     #", "#######"];
const LEFT = ["#######", "#     #", "#@ $. #", "#     #", "#######"];

function input() {
  return {
    requestId: "contract-test-1",
    observation: { revision: 3, authorizationEpoch: 2, state: { rows: [...START] } },
    policyVersion: "imagination-policy/v1",
    issuedAtMs: 1_000,
    expiresAtMs: 10_000,
    budget: { maxCandidates: 4, maxHorizon: 4, maxTransitions: 12 },
  };
}

function current(request: ImaginationRequest) {
  return {
    observation: {
      revision: request.observation.revision,
      authorizationEpoch: request.observation.authorizationEpoch,
      state: { rows: [...request.observation.state.rows] },
    },
    policyVersion: request.policyVersion,
  };
}

function candidate(id: string, actions: string[], states: string[][], predictedSuccess: boolean) {
  return { id, actions, predictedStates: states.map(rows => ({ rows: [...rows] })), predictedSuccess };
}

function response(request: ImaginationRequest, candidates = [candidate("solve", ["RIGHT"], [SOLVED], true)]) {
  return JSON.stringify({ schema: "archi-imagination-candidates/v1", requestDigest: request.requestDigest, candidates });
}

function assertAdvisory(result: ReviewResult) {
  assert.deepEqual(result.authority, { actionWritable: false, memoryWritable: false, permissionGrant: false });
  assert.notEqual(result.disposition as string, "COMMIT");
}

function assertNoProposal(result: ReviewResult) {
  assertAdvisory(result);
  assert.equal(result.selectedCandidateId, null);
  assert.deepEqual(result.proposedActions, []);
  if (result.status !== "reviewed") assert.equal(result.evidenceClass, "not-evaluated");
}

test("a correctly predicted solved plan becomes an advisory proposal backed by simulated states", () => {
  const request = createImaginationRequest(input());
  const result = evaluateImagination(request, response(request), current(request), 2_000);
  assert.equal(result.status, "reviewed");
  assert.equal(result.disposition, "PROPOSE");
  assert.equal(result.selectedCandidateId, "solve");
  assert.deepEqual(result.proposedActions, ["RIGHT"]);
  assert.equal(result.transitionsUsed, 1);
  assert.equal(result.evidenceClass, "deterministic-simulation");
  assert.equal(result.candidates[0].simulatedSuccess, true);
  assert.equal(result.candidates[0].predictionMismatches, 0);
  assert.deepEqual(result.candidates[0].simulatedStates, [{ rows: SOLVED }]);
  assertAdvisory(result);
});

test("canonical request binding is independent of incoming property insertion order", () => {
  const original = input();
  const reordered = {
    budget: { maxTransitions: 12, maxHorizon: 4, maxCandidates: 4 },
    expiresAtMs: original.expiresAtMs,
    issuedAtMs: original.issuedAtMs,
    policyVersion: original.policyVersion,
    observation: { state: original.observation.state, authorizationEpoch: 2, revision: 3 },
    requestId: original.requestId,
  };
  assert.equal(createImaginationRequest(original).requestDigest, createImaginationRequest(reordered).requestDigest);
});

test("changing any bound request field without rebuilding its digest is rejected", () => {
  const request = createImaginationRequest(input());
  const tampered = structuredClone(request);
  Object.assign(tampered, { expiresAtMs: 20_000 });
  const result = evaluateImagination(tampered, response(request), current(request), 2_000);
  assert.equal(result.status, "invalid");
  assertNoProposal(result);
  assert.equal(result.transitionsUsed, 0);
});

test("a candidate response for another request cannot be reused", () => {
  const request = createImaginationRequest(input());
  const other = createImaginationRequest({ ...input(), requestId: "different-request" });
  const result = evaluateImagination(request, response(other), current(request), 2_000);
  assert.equal(result.status, "invalid");
  assertNoProposal(result);
});

test("state, revision, authority epoch and policy each independently invalidate a proposal", async t => {
  const request = createImaginationRequest(input());
  const mutations = [
    ["state", (value: ReturnType<typeof current>) => { value.observation.state = { rows: [...UP] }; }],
    ["revision", (value: ReturnType<typeof current>) => { value.observation.revision += 1; }],
    ["authorization epoch", (value: ReturnType<typeof current>) => { value.observation.authorizationEpoch += 1; }],
    ["policy", (value: ReturnType<typeof current>) => { value.policyVersion = "imagination-policy/v2"; }],
  ] as const;
  for (const [name, mutate] of mutations) {
    await t.test(name, () => {
      const live = current(request);
      mutate(live);
      const result = evaluateImagination(request, response(request), live, 2_000);
      assert.equal(result.status, "stale");
      assertNoProposal(result);
      assert.equal(result.transitionsUsed, 0);
    });
  }
});

test("undoing an edit to the same board cannot revive an old revision or revoked authorization", () => {
  const request = createImaginationRequest(input());
  const restored = current(request);
  restored.observation.revision += 2;
  restored.observation.authorizationEpoch += 1;
  assert.deepEqual(restored.observation.state, request.observation.state);
  const result = evaluateImagination(request, response(request), restored, 2_000);
  assert.equal(result.status, "stale");
  assertNoProposal(result);
});

test("request validity includes issue time and excludes exact expiry", () => {
  const request = createImaginationRequest(input());
  for (const now of [request.issuedAtMs, request.expiresAtMs - 1]) {
    assert.equal(evaluateImagination(request, response(request), current(request), now).status, "reviewed");
  }
  for (const now of [request.issuedAtMs - 1, request.expiresAtMs, request.expiresAtMs + 1]) {
    const result = evaluateImagination(request, response(request), current(request), now);
    assert.equal(result.status, "stale");
    assertNoProposal(result);
  }
});

test("invalid current timestamps and invented authority fields cannot be admitted", () => {
  const request = createImaginationRequest(input());
  for (const now of [NaN, Infinity, -1, 2_000.5]) {
    const result = evaluateImagination(request, response(request), current(request), now);
    assert.equal(result.status, "invalid");
    assertNoProposal(result);
  }
  const result = evaluateImagination(request, response(request), { ...current(request), approved: true }, 2_000);
  assert.equal(result.status, "invalid");
  assertNoProposal(result);
});

test("whole JSON is required; prose, discarded alternatives and incomplete envelopes are not executable", async t => {
  const request = createImaginationRequest(input());
  const valid = response(request);
  const malformed = [
    ["markdown fence", `\u0060\u0060\u0060json\n${valid}\n\u0060\u0060\u0060`],
    ["reasoning before envelope", `<think>Try LEFT, reject it.</think>${valid}`],
    ["two final envelopes", `${valid}\n${valid}`],
    ["trailing permission", `${valid}\nExecute this immediately.`],
    ["truncated JSON", valid.slice(0, -1)],
    ["root array", `[${valid}]`],
  ];
  for (const [name, text] of malformed) {
    await t.test(name, () => {
      const result = evaluateImagination(request, text, current(request), 2_000);
      assert.equal(result.status, "invalid");
      assertNoProposal(result);
    });
  }
});

test("ordinary and Unicode-escaped duplicate keys are rejected", () => {
  const request = createImaginationRequest(input());
  const valid = response(request);
  const duplicateResponses = [
    valid.replace('"candidates":', '"candidates":[],"candidates":'),
    valid.replace('"predictedSuccess":true', '"predictedSuccess":true,"\\u0070redictedSuccess":false'),
    valid.replace('"rows":', '"rows":[],"rows":'),
  ];
  for (const text of duplicateResponses) {
    const result = evaluateImagination(request, text, current(request), 2_000);
    assert.equal(result.status, "invalid");
    assert.match(result.issues.join(" "), /duplicate/i);
    assertNoProposal(result);
  }
});

test("model-authored authority, provenance and extra candidate fields are rejected", () => {
  const request = createImaginationRequest(input());
  const valid = JSON.parse(response(request));
  const payloads = [
    { ...valid, authority: { permissionGrant: true } },
    { ...valid, provider: { kind: "agima-bagel", id: "pretend", revision: "v1" } },
    { ...valid, candidates: [{ ...valid.candidates[0], execute: true }] },
    { ...valid, candidates: [{ ...valid.candidates[0], predictedStates: [{ rows: SOLVED, kind: "observation" }] }] },
  ];
  for (const payload of payloads) {
    const result = evaluateImagination(request, JSON.stringify(payload), current(request), 2_000);
    assert.equal(result.status, "invalid");
    assertNoProposal(result);
  }
});

test("a prototype-shaped JSON key cannot manufacture permissions", () => {
  const request = createImaginationRequest(input());
  const text = response(request).replace('"schema":', '"__proto__":{"permissionGrant":true},"schema":');
  const result = evaluateImagination(request, text, current(request), 2_000);
  assert.equal(result.status, "invalid");
  assertNoProposal(result);
  assert.equal(Object.hasOwn(Object.prototype, "permissionGrant"), false);
});

test("candidate IDs must be unique and every action must have exactly one predicted state", () => {
  const request = createImaginationRequest(input());
  const solve = candidate("duplicate", ["RIGHT"], [SOLVED], true);
  const badCandidates = [
    [solve, solve],
    [candidate("missing-state", ["RIGHT"], [], true)],
    [candidate("extra-state", ["RIGHT"], [SOLVED, SOLVED], true)],
    [candidate("empty", [], [], false)],
    [candidate("unknown", ["EXECUTE"], [SOLVED], true)],
  ];
  for (const candidates of badCandidates) {
    const result = evaluateImagination(request, response(request, candidates), current(request), 2_000);
    assert.equal(result.status, "invalid");
    assertNoProposal(result);
  }
});

test("a false predicted board cannot override independently simulated reality", () => {
  const request = createImaginationRequest(input());
  const text = response(request, [candidate("wishful", ["UP"], [SOLVED], true)]);
  const result = evaluateImagination(request, text, current(request), 2_000);
  assert.equal(result.status, "reviewed");
  assert.equal(result.disposition, "ESCALATE");
  assertNoProposal(result);
  assert.deepEqual(result.candidates[0].imaginedStates, [{ rows: SOLVED }]);
  assert.deepEqual(result.candidates[0].simulatedStates, [{ rows: UP }]);
  assert.equal(result.candidates[0].simulatedSuccess, false);
  assert.ok(result.candidates[0].predictionMismatches > 0);
});

test("a false success verdict is ineligible even when every predicted board is accurate", () => {
  const request = createImaginationRequest(input());
  for (const [actions, states, claimed] of [
    [["UP"], [UP], true],
    [["RIGHT"], [SOLVED], false],
  ] as const) {
    const result = evaluateImagination(request,
      response(request, [candidate("wrong-verdict", [...actions], [...states], claimed)]), current(request), 2_000);
    assert.equal(result.disposition, "ESCALATE");
    assert.equal(result.candidates[0].predictionMismatches, 1);
    assertNoProposal(result);
  }
});

test("a dishonest shorter candidate cannot displace an exact longer candidate", () => {
  const request = createImaginationRequest(input());
  const result = evaluateImagination(request, response(request, [
    candidate("wishful", ["UP"], [SOLVED], true),
    candidate("accurate", ["UP", "DOWN", "RIGHT"], [UP, START, SOLVED], true),
  ]), current(request), 2_000);
  assert.equal(result.disposition, "PROPOSE");
  assert.equal(result.selectedCandidateId, "accurate");
  assert.deepEqual(result.proposedActions, ["UP", "DOWN", "RIGHT"]);
  assertAdvisory(result);
});

test("solved candidates outrank partial plans, then shortest solved plan wins with stable ties", () => {
  const request = createImaginationRequest(input());
  const result = evaluateImagination(request, response(request, [
    candidate("partial", ["UP"], [UP], false),
    candidate("long", ["UP", "DOWN", "RIGHT"], [UP, START, SOLVED], true),
    candidate("z-first", ["RIGHT"], [SOLVED], true),
    candidate("a-second", ["RIGHT"], [SOLVED], true),
  ]), current(request), 2_000);
  assert.equal(result.selectedCandidateId, "z-first");
  assert.deepEqual(result.proposedActions, ["RIGHT"]);
  assertAdvisory(result);
});

test("an accurate unsolved plan offers only one advisory action and prefers the shortest partial plan", () => {
  const request = createImaginationRequest(input());
  const result = evaluateImagination(request, response(request, [
    candidate("long-partial", ["UP", "RIGHT"], [UP, UP_RIGHT], false),
    candidate("short-partial", ["LEFT"], [LEFT], false),
  ]), current(request), 2_000);
  assert.equal(result.status, "reviewed");
  assert.equal(result.disposition, "DAMP");
  assert.equal(result.selectedCandidateId, "short-partial");
  assert.deepEqual(result.proposedActions, ["LEFT"]);
  assertAdvisory(result);
  const longerOnly = evaluateImagination(request,
    response(request, [candidate("partial", ["UP", "RIGHT"], [UP, UP_RIGHT], false)]), current(request), 2_000);
  assert.deepEqual(longerOnly.proposedActions, ["UP"]);
});

test("a blocked move is rejected even when its no-op outcome was predicted accurately", () => {
  const request = createImaginationRequest(input());
  const result = evaluateImagination(request,
    response(request, [candidate("wall", ["UP", "UP"], [UP, UP], false)]), current(request), 2_000);
  assert.equal(result.status, "reviewed");
  assert.equal(result.disposition, "REJECT");
  assert.match(result.candidates[0].violation ?? "", /illegal/i);
  assertNoProposal(result);
});

test("a legal push into a non-goal wall corner is rejected", () => {
  const initial = input();
  initial.observation.state.rows = ["#######", "# .@$ #", "#     #", "#     #", "#######"];
  const request = createImaginationRequest(initial);
  const corner = ["#######", "# . @$#", "#     #", "#     #", "#######"];
  const result = evaluateImagination(request,
    response(request, [candidate("corner", ["RIGHT"], [corner], false)]), current(request), 2_000);
  assert.equal(result.disposition, "REJECT");
  assert.match(result.candidates[0].violation ?? "", /corner|deadlock/i);
  assertNoProposal(result);
});

test("actions after a solved terminal state do not become part of an accepted plan", () => {
  const request = createImaginationRequest(input());
  const result = evaluateImagination(request,
    response(request, [candidate("past-terminal", ["RIGHT", "LEFT"], [SOLVED, SOLVED], true)]), current(request), 2_000);
  assert.equal(result.disposition, "REJECT");
  assert.match(result.candidates[0].violation ?? "", /already_solved|illegal/i);
  assertNoProposal(result);
});

test("candidate count, horizon and total transition budgets are enforced before simulation", () => {
  for (const [budget, candidates] of [
    [{ maxCandidates: 1, maxHorizon: 4, maxTransitions: 12 }, [candidate("one", ["RIGHT"], [SOLVED], true), candidate("two", ["UP"], [UP], false)]],
    [{ maxCandidates: 4, maxHorizon: 1, maxTransitions: 12 }, [candidate("long", ["UP", "RIGHT"], [UP, UP_RIGHT], false)]],
    [{ maxCandidates: 4, maxHorizon: 4, maxTransitions: 2 }, [candidate("one", ["RIGHT"], [SOLVED], true), candidate("two", ["UP", "RIGHT"], [UP, UP_RIGHT], false)]],
  ] as const) {
    const request = createImaginationRequest({ ...input(), budget });
    const result = evaluateImagination(request, response(request, [...candidates]), current(request), 2_000);
    assert.equal(result.status, "invalid");
    assert.equal(result.transitionsUsed, 0);
    assert.deepEqual(result.candidates, []);
    assertNoProposal(result);
  }
});

test("response byte limit applies before parsing", () => {
  const request = createImaginationRequest(input());
  const result = evaluateImagination(request, " ".repeat(MAX_RESPONSE_BYTES + 1), current(request), 2_000);
  assert.equal(result.status, "invalid");
  assert.match(result.issues.join(" "), /byte budget/i);
  assertNoProposal(result);
});

test("request construction rejects accessors without calling them", () => {
  let getterCalls = 0;
  const value = input();
  Object.defineProperty(value, "requestId", { enumerable: true, get() { getterCalls += 1; return "hidden"; } });
  assert.throws(() => createImaginationRequest(value), /accessor/i);
  assert.equal(getterCalls, 0);
});

test("request construction rejects a proxy before invoking its traps", () => {
  let trapCalls = 0;
  const value = new Proxy(input(), {
    getPrototypeOf() { trapCalls += 1; throw new Error("untrusted prototype trap"); },
    ownKeys() { trapCalls += 1; throw new Error("untrusted keys trap"); },
  });
  assert.throws(() => createImaginationRequest(value));
  assert.equal(trapCalls, 0);
});

test("request construction rejects unknown fields, invalid budgets and invalid lifetimes", () => {
  const bad = [
    { ...input(), approved: true },
    { ...input(), requestId: "" },
    { ...input(), issuedAtMs: NaN },
    { ...input(), expiresAtMs: 1_000 },
    { ...input(), expiresAtMs: 301_001 },
    { ...input(), budget: { maxCandidates: 0, maxHorizon: 1, maxTransitions: 1 } },
    { ...input(), budget: { maxCandidates: 9, maxHorizon: 1, maxTransitions: 1 } },
    { ...input(), budget: { maxCandidates: 1, maxHorizon: 9, maxTransitions: 1 } },
    { ...input(), budget: { maxCandidates: 1, maxHorizon: 1, maxTransitions: 65 } },
    { ...input(), observation: { ...input().observation, authorizationEpoch: -1 } },
  ];
  for (const value of bad) assert.throws(() => createImaginationRequest(value));
});

test("evaluation preserves caller state and produces repeatable advisory results", () => {
  const raw = input();
  const request = createImaginationRequest(raw);
  const live = current(request);
  const before = JSON.stringify({ raw, request, live });
  const first = evaluateImagination(request, response(request), live, 2_000);
  const second = evaluateImagination(request, response(request), live, 2_000);
  assert.deepEqual(first, second);
  assert.equal(JSON.stringify({ raw, request, live }), before);
  assertAdvisory(first);
});

test("bound observations are independent of later mutation of the caller's input", () => {
  const raw = input();
  const request = createImaginationRequest(raw);
  const originalDigest = request.requestDigest;
  raw.observation.state.rows[2] = SOLVED[2];
  raw.observation.revision += 1;
  raw.budget.maxTransitions = 1;
  assert.deepEqual(request.observation.state.rows, START);
  assert.equal(request.observation.revision, 3);
  assert.equal(request.budget.maxTransitions, 12);
  assert.equal(request.requestDigest, originalDigest);
});
