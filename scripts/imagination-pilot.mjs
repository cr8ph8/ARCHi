import assert from "node:assert/strict";
import { constants } from "node:fs";
import { open } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseJsonWithoutDuplicateKeys } from "../src/strict-json.ts";
import {
  createImaginationRequest, evaluateImagination, proposeImagination,
  FIXTURE_PROVIDER, UNAVAILABLE_AGIMA_PROVIDER,
} from "../imagination/src/planner.ts";

const root = fileURLToPath(new URL("../", import.meta.url));

async function readBounded(filename, maximum = 65_536) {
  const handle = await open(filename, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const stat = await handle.stat();
    if (!stat.isFile() || stat.size > maximum) throw new Error("Expected a bounded regular JSON file");
    const buffer = Buffer.alloc(stat.size + 1);
    let length = 0;
    while (length < buffer.length) {
      const next = await handle.read(buffer, length, buffer.length - length);
      if (next.bytesRead === 0) break;
      length += next.bytesRead;
    }
    if (length > stat.size || length > maximum) throw new Error("JSON file grew during bounded read");
    return new TextDecoder("utf-8", { fatal: true }).decode(buffer.subarray(0, length));
  } finally { await handle.close(); }
}

function response(request, candidates) {
  return JSON.stringify({ schema: "archi-imagination-candidates/v1", requestDigest: request.requestDigest, candidates });
}

export async function runDemo() {
  const fixture = parseJsonWithoutDuplicateKeys(await readBounded(path.join(root, "imagination/fixtures/sokoban-branches.json")));
  const request = createImaginationRequest(fixture.request);
  const current = { observation: request.observation, policyVersion: request.policyVersion };
  const text = response(request, fixture.candidates);
  const cases = [];
  function record(id, review, expectedStatus, expectedDisposition) {
    assert.equal(review.status, expectedStatus, id);
    assert.equal(review.disposition, expectedDisposition, id);
    assert.deepEqual(review.authority, { actionWritable: false, memoryWritable: false, permissionGrant: false });
    cases.push({ id, passed: true, review });
  }
  const provider = { identity: FIXTURE_PROVIDER, available: true, async generate() { return text; } };
  const branchReview = await proposeImagination(request, provider, () => current, { now: () => 2000 });
  assert.equal(branchReview.selectedCandidateId, "walk-around-and-push");
  assert.match(branchReview.candidates[0].violation, /deadlock/);
  record("compare-alternatives", branchReview, "reviewed", "PROPOSE");

  const partial = fixture.candidates.find(candidate => candidate.id === "partial-walk");
  record("false-success-claim", evaluateImagination(request,
    response(request, [{ ...partial, predictedSuccess: true }]), current, 2000), "reviewed", "ESCALATE");
  record("bounded-partial-plan", evaluateImagination(request, response(request, [partial]), current, 2000), "reviewed", "DAMP");
  record("stale-observation", evaluateImagination(request, text, {
    ...current, observation: { ...current.observation, revision: 2 },
  }, 2000), "stale", "REJECT");
  record("revoked-epoch-same-board", evaluateImagination(request, text, {
    ...current, observation: { ...current.observation, authorizationEpoch: 2 },
  }, 2000), "stale", "REJECT");
  record("no-trace-fallback", evaluateImagination(request, `<think>push UP</think>${text}`, current, 2000), "invalid", "REJECT");
  const limited = createImaginationRequest({ ...fixture.request, budget: { ...fixture.request.budget, maxTransitions: 3 } });
  record("aggregate-budget", evaluateImagination(limited, response(limited, fixture.candidates), current, 2000), "invalid", "REJECT");
  record("agima-unavailable", await proposeImagination(request, UNAVAILABLE_AGIMA_PROVIDER, () => current, { now: () => 2000 }), "unavailable", "ESCALATE");

  return { schema: "archi-imagination-demo/v1", scope: fixture.provenance,
    modelInferenceCalls: 0, actualEnvironmentActions: 0, nativeStateWrites: 0,
    passed: cases.length, failed: 0, cases };
}

async function main(args) {
  const command = args.shift();
  if (command === "demo" && args.length === 0) return runDemo();
  if (command === "agima" && args.length === 0) return {
    schema: "archi-imagination-provider-status/v1", provider: UNAVAILABLE_AGIMA_PROVIDER.identity,
    status: "unavailable", reason: UNAVAILABLE_AGIMA_PROVIDER.unavailableReason,
  };
  if (command === "review") {
    const options = {};
    while (args.length) {
      const flag = args.shift(), value = args.shift();
      if (!["--request", "--response", "--current", "--now-ms"].includes(flag) || !value || options[flag] !== undefined) throw new Error("Invalid or duplicate review option");
      options[flag] = value;
    }
    if (Object.keys(options).length !== 4 || !/^(0|[1-9][0-9]*)$/.test(options["--now-ms"])) throw new Error("review requires --request, --response, --current and integer --now-ms");
    const [requestText, responseText, currentText] = await Promise.all([
      readBounded(options["--request"]), readBounded(options["--response"]), readBounded(options["--current"]),
    ]);
    // CLI imports are explicitly fixture/offline input, never attested Agima output.
    return evaluateImagination(parseJsonWithoutDuplicateKeys(requestText), responseText,
      parseJsonWithoutDuplicateKeys(currentText), Number(options["--now-ms"]), FIXTURE_PROVIDER);
  }
  throw new Error("Usage: node scripts/imagination-pilot.mjs demo | agima | review --request file.json --response file.json --current file.json --now-ms N");
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const output = await main(process.argv.slice(2));
    process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
    if (["invalid", "stale", "unavailable", "cancelled", "timeout"].includes(output.status) ||
      ["REJECT", "ESCALATE"].includes(output.disposition)) process.exitCode = 2;
  } catch (error) {
    process.stderr.write(`IMAGINATION PILOT ERROR: ${error.message}\n`);
    process.exitCode = 1;
  }
}
