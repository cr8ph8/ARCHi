import assert from "node:assert/strict";
import test from "node:test";
import {
  createImaginationRequest,
  proposeImagination,
  UNAVAILABLE_AGIMA_PROVIDER,
} from "../src/planner.ts";
import type { ImaginationProvider, ImaginationRequest, ReviewResult } from "../src/planner.ts";

const START = ["#######", "#     #", "# @$. #", "#     #", "#######"];
const SOLVED = ["#######", "#     #", "#  @* #", "#     #", "#######"];

function request(expiresAtMs = 10_000) {
  return createImaginationRequest({
    requestId: "provider-test-1",
    observation: { revision: 3, authorizationEpoch: 2, state: { rows: [...START] } },
    policyVersion: "imagination-policy/v1",
    issuedAtMs: 1_000,
    expiresAtMs,
    budget: { maxCandidates: 2, maxHorizon: 3, maxTransitions: 6 },
  });
}

function current(bound: ImaginationRequest) {
  return {
    observation: {
      revision: bound.observation.revision,
      authorizationEpoch: bound.observation.authorizationEpoch,
      state: { rows: [...bound.observation.state.rows] },
    },
    policyVersion: bound.policyVersion,
  };
}

function response(bound: ImaginationRequest) {
  return JSON.stringify({
    schema: "archi-imagination-candidates/v1",
    requestDigest: bound.requestDigest,
    candidates: [{ id: "solve", actions: ["RIGHT"], predictedStates: [{ rows: SOLVED }], predictedSuccess: true }],
  });
}

function fixture(generate: ImaginationProvider["generate"]): ImaginationProvider {
  return {
    identity: { kind: "synthetic-fixture", id: "test-only-provider", revision: "v1" },
    available: true,
    generate,
  };
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(done => { resolve = done; });
  return { promise, resolve };
}

function assertNoAuthority(result: ReviewResult) {
  assert.deepEqual(result.authority, { actionWritable: false, memoryWritable: false, permissionGrant: false });
  assert.notEqual(result.disposition as string, "COMMIT");
}

function assertNoProposal(result: ReviewResult) {
  assertNoAuthority(result);
  assert.deepEqual(result.proposedActions, []);
  assert.equal(result.selectedCandidateId, null);
  assert.equal(result.evidenceClass, "not-evaluated");
}

test("provider entrypoint performs a real review using only a bound request and cancellation signal", { timeout: 1_000 }, async () => {
  const bound = request();
  const live = current(bound);
  let calls = 0;
  let reads = 0;
  const provider = fixture(async function (received, signal) {
    calls += 1;
    assert.equal(arguments.length, 2);
    assert.deepEqual(received, bound);
    assert.ok(signal instanceof AbortSignal);
    assert.equal(signal.aborted, false);
    for (const forbidden of ["execute", "dispatch", "commit", "saveMemory", "grantPermission"]) {
      assert.equal(Object.hasOwn(received, forbidden), false);
    }
    return response(received);
  });
  const before = JSON.stringify(live);
  const result = await proposeImagination(bound, provider, () => { reads += 1; return live; }, { now: () => 2_000 });
  assert.equal(calls, 1);
  assert.equal(reads, 2);
  assert.equal(result.status, "reviewed");
  assert.equal(result.disposition, "PROPOSE");
  assert.deepEqual(result.proposedActions, ["RIGHT"]);
  assert.deepEqual(result.provider, provider.identity);
  assert.equal(JSON.stringify(live), before);
  assertNoAuthority(result);
});

test("unavailable Agima is explicit and does not silently substitute a fixture", async () => {
  const bound = request();
  const result = await proposeImagination(bound, UNAVAILABLE_AGIMA_PROVIDER, () => current(bound), { now: () => 2_000 });
  assert.equal(result.status, "unavailable");
  assert.equal(result.disposition, "ESCALATE");
  assert.equal(result.provider.kind, "agima-bagel");
  assert.match(result.issues.join(" "), /not installed|no visual-model backend/i);
  assertNoProposal(result);
});

test("an unavailable provider is never invoked", async () => {
  const bound = request();
  let calls = 0;
  const provider = { ...fixture(async () => { calls += 1; return response(bound); }), available: false };
  const result = await proposeImagination(bound, provider, () => current(bound), { now: () => 2_000 });
  assert.equal(result.status, "unavailable");
  assert.equal(calls, 0);
  assertNoProposal(result);
});

test("an already stale request never invokes a provider", async () => {
  const bound = request();
  const live = current(bound);
  live.observation.authorizationEpoch += 1;
  let calls = 0;
  const provider = fixture(async () => { calls += 1; return response(bound); });
  const result = await proposeImagination(bound, provider, () => live, { now: () => 2_000 });
  assert.equal(result.status, "stale");
  assert.equal(calls, 0);
  assertNoProposal(result);
});

test("a pre-cancelled request never invokes a provider", async () => {
  const bound = request();
  const cancellation = new AbortController();
  cancellation.abort();
  let calls = 0;
  const provider = fixture(async () => { calls += 1; return response(bound); });
  const result = await proposeImagination(bound, provider, () => current(bound), { now: () => 2_000, signal: cancellation.signal });
  assert.equal(result.status, "cancelled");
  assert.equal(calls, 0);
  assertNoProposal(result);
});

test("cancellation before queued generation begins prevents the provider call", async () => {
  const bound = request();
  const cancellation = new AbortController();
  let calls = 0;
  const provider = fixture(async () => { calls += 1; return response(bound); });
  const pending = proposeImagination(bound, provider, () => current(bound), { now: () => 2_000, signal: cancellation.signal });
  cancellation.abort();
  const result = await pending;
  assert.equal(result.status, "cancelled");
  assert.equal(calls, 0);
  assertNoProposal(result);
});

test("state and authorization are checked again after generation", { timeout: 2_000 }, async t => {
  const mutations = [
    ["revision", (live: ReturnType<typeof current>) => { live.observation.revision += 1; }],
    ["revocation", (live: ReturnType<typeof current>) => { live.observation.authorizationEpoch += 1; }],
    ["state", (live: ReturnType<typeof current>) => { live.observation.state.rows = [...SOLVED]; }],
    ["policy", (live: ReturnType<typeof current>) => { live.policyVersion = "imagination-policy/v2"; }],
  ] as const;
  for (const [name, mutate] of mutations) {
    await t.test(name, async () => {
      const bound = request();
      const live = current(bound);
      const started = deferred<void>();
      const completion = deferred<string>();
      const provider = fixture(async () => { started.resolve(); return completion.promise; });
      const pending = proposeImagination(bound, provider, () => live, { now: () => 2_000 });
      await started.promise;
      mutate(live);
      completion.resolve(response(bound));
      const result = await pending;
      assert.equal(result.status, "stale");
      assert.equal(result.transitionsUsed, 0);
      assertNoProposal(result);
    });
  }
});

test("expiry during generation discards the otherwise valid response", { timeout: 1_000 }, async () => {
  const bound = request();
  let now = 2_000;
  const provider = fixture(async () => { now = bound.expiresAtMs; return response(bound); });
  const result = await proposeImagination(bound, provider, () => current(bound), { now: () => now });
  assert.equal(result.status, "stale");
  assertNoProposal(result);
});

test("a backwards clock during generation cannot extend the proposal lifetime", { timeout: 1_000 }, async () => {
  const bound = request();
  let now = 5_000;
  const provider = fixture(async () => { now = 4_000; return response(bound); });
  const result = await proposeImagination(bound, provider, () => current(bound), { now: () => now });
  assert.equal(result.status, "stale");
  assertNoProposal(result);
});

test("cancellation aborts an active provider and never accepts its later response", { timeout: 1_000 }, async () => {
  const bound = request();
  const cancellation = new AbortController();
  const started = deferred<void>();
  const completion = deferred<string>();
  let providerSignal: AbortSignal | undefined;
  const provider = fixture(async (_received, signal) => {
    providerSignal = signal;
    started.resolve();
    return completion.promise;
  });
  const pending = proposeImagination(bound, provider, () => current(bound), { now: () => 2_000, signal: cancellation.signal });
  await started.promise;
  cancellation.abort();
  const result = await pending;
  assert.equal(result.status, "cancelled");
  assert.equal(providerSignal?.aborted, true);
  assertNoProposal(result);
  const before = JSON.stringify(result);
  completion.resolve(response(bound));
  await new Promise<void>(resolve => setImmediate(resolve));
  assert.equal(JSON.stringify(result), before);
});

test("timeout aborts an active provider and rejects its late completion", { timeout: 1_000 }, async () => {
  const bound = request();
  const completion = deferred<string>();
  let providerSignal: AbortSignal | undefined;
  const provider = fixture(async (_received, signal) => {
    providerSignal = signal;
    return completion.promise;
  });
  const result = await proposeImagination(bound, provider, () => current(bound), { now: () => 2_000, timeoutMs: 5 });
  assert.equal(result.status, "timeout");
  assert.equal(providerSignal?.aborted, true);
  assertNoProposal(result);
  const before = JSON.stringify(result);
  completion.resolve(response(bound));
  await new Promise<void>(resolve => setImmediate(resolve));
  assert.equal(JSON.stringify(result), before);
});

test("provider failure returns a failed review without a fallback or proposal", async () => {
  const bound = request();
  let calls = 0;
  const provider = fixture(async () => { calls += 1; throw new Error("synthetic provider failure"); });
  const result = await proposeImagination(bound, provider, () => current(bound), { now: () => 2_000 });
  assert.equal(calls, 1);
  assert.equal(result.status, "invalid");
  assert.match(result.issues.join(" "), /synthetic provider failure/);
  assertNoProposal(result);
});

test("failure to obtain authoritative current context prevents generation", async () => {
  const bound = request();
  let calls = 0;
  const provider = fixture(async () => { calls += 1; return response(bound); });
  const result = await proposeImagination(bound, provider, () => { throw new Error("owner unavailable"); }, { now: () => 2_000 });
  assert.equal(result.status, "invalid");
  assert.equal(calls, 0);
  assertNoProposal(result);
});

test("invalid timeout budgets fail before invoking a provider", async () => {
  const bound = request();
  let calls = 0;
  const provider = fixture(async () => { calls += 1; return response(bound); });
  for (const timeoutMs of [0, -1, 30_001, NaN, Infinity]) {
    const result = await proposeImagination(bound, provider, () => current(bound), { now: () => 2_000, timeoutMs });
    assert.equal(result.status, "invalid");
    assertNoProposal(result);
  }
  assert.equal(calls, 0);
});

test("elapsed generation time is enforced even before the timeout timer runs", async () => {
  const bound = request();
  let now = 2_000;
  const provider = fixture(async () => { now = 4_000; return response(bound); });
  const result = await proposeImagination(bound, provider, () => current(bound), {
    now: () => now,
    timeoutMs: 100,
  });
  assert.equal(result.status, "timeout");
  assert.equal(result.transitionsUsed, 0);
  assertNoProposal(result);
});

test("cancellation during the final current-context read prevents acceptance", async () => {
  const bound = request();
  const cancellation = new AbortController();
  let reads = 0;
  const provider = fixture(async () => response(bound));
  const result = await proposeImagination(bound, provider, () => {
    reads += 1;
    if (reads === 2) cancellation.abort();
    return current(bound);
  }, { now: () => 2_000, signal: cancellation.signal });
  assert.equal(reads, 2);
  assert.equal(result.status, "cancelled");
  assert.equal(result.transitionsUsed, 0);
  assertNoProposal(result);
});

test("expiry during the final current-context read prevents acceptance", async () => {
  const bound = request(4_000);
  let now = 2_000;
  let reads = 0;
  const provider = fixture(async () => response(bound));
  const result = await proposeImagination(bound, provider, () => {
    reads += 1;
    if (reads === 2) now = bound.expiresAtMs;
    return current(bound);
  }, { now: () => now, timeoutMs: 5_000 });
  assert.equal(reads, 2);
  assert.equal(result.status, "stale");
  assert.equal(result.transitionsUsed, 0);
  assertNoProposal(result);
});

test("expiry during the initial current-context read prevents provider dispatch", async () => {
  const bound = request(4_000);
  let now = 2_000;
  let calls = 0;
  const provider = fixture(async () => { calls += 1; return response(bound); });
  const result = await proposeImagination(bound, provider, () => {
    now = bound.expiresAtMs;
    return current(bound);
  }, { now: () => now, timeoutMs: 5_000 });
  assert.equal(result.status, "stale");
  assert.equal(calls, 0);
  assertNoProposal(result);
});
