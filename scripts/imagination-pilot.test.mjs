import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { createImaginationRequest } from "../imagination/src/planner.ts";
import { runDemo } from "./imagination-pilot.mjs";

const root = fileURLToPath(new URL("../", import.meta.url));
const cli = path.join(root, "scripts/imagination-pilot.mjs");
function run(args) {
  return spawnSync(process.execPath, [cli, ...args], { cwd: root, encoding: "utf8", timeout: 10_000, maxBuffer: 128 * 1024 });
}

test("CLI caller runs the branching proposal path and eight explicit contract scenarios", async () => {
  const first = await runDemo(), second = await runDemo();
  assert.deepEqual(first, second);
  assert.equal(first.passed, 8);
  assert.equal(first.failed, 0);
  assert.equal(first.modelInferenceCalls, 0);
  assert.equal(first.actualEnvironmentActions, 0);
  assert.equal(first.nativeStateWrites, 0);
  const review = first.cases[0].review;
  assert.deepEqual(review.proposedActions, ["LEFT", "UP", "RIGHT", "RIGHT"]);
  assert.equal(review.candidates[0].simulatedSuccess, false);
});

test("Agima availability command cannot silently substitute a fixture provider", () => {
  const result = run(["agima"]);
  assert.equal(result.error, undefined);
  assert.equal(result.status, 2);
  const parsed = JSON.parse(result.stdout);
  assert.equal(parsed.status, "unavailable");
  assert.equal(parsed.provider.kind, "agima-bagel");
  assert.match(parsed.reason, /no visual-model backend/);
});

test("CLI reviews exact bounded inputs and returns non-success for stale imports", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "archi-imagination-cli-"));
  try {
    const fixture = JSON.parse(await readFile(path.join(root, "imagination/fixtures/sokoban-branches.json"), "utf8"));
    const request = createImaginationRequest(fixture.request);
    const current = { observation: request.observation, policyVersion: request.policyVersion };
    const response = { schema: "archi-imagination-candidates/v1", requestDigest: request.requestDigest, candidates: fixture.candidates };
    for (const [name, value] of Object.entries({ request, current, response })) await writeFile(path.join(directory, `${name}.json`), JSON.stringify(value), { flag: "wx" });
    const args = ["review", "--request", path.join(directory, "request.json"), "--response", path.join(directory, "response.json"),
      "--current", path.join(directory, "current.json"), "--now-ms", "2000"];
    const review = run(args);
    assert.equal(review.status, 0, review.stderr);
    assert.equal(JSON.parse(review.stdout).selectedCandidateId, "walk-around-and-push");
    const stale = run([...args.slice(0, -1), "11000"]);
    assert.equal(stale.status, 2);
    assert.equal(JSON.parse(stale.stdout).status, "stale");
    assert.equal((await readFile(path.join(directory, "request.json"), "utf8")), JSON.stringify(request));
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("CLI rejects oversized, symlinked and malformed input instead of parsing a thought trace", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "archi-imagination-input-"));
  try {
    const ordinary = path.join(directory, "ordinary.json");
    const large = path.join(directory, "large.json");
    const link = path.join(directory, "link.json");
    await writeFile(ordinary, "{}");
    await writeFile(large, " ".repeat(65_537));
    await symlink(ordinary, link);
    for (const filename of [large, link]) {
      const outcome = run(["review", "--request", filename, "--response", ordinary, "--current", ordinary, "--now-ms", "2000"]);
      assert.equal(outcome.status, 1);
      assert.equal(outcome.stdout, "");
    }
    const malformed = run(["review", "--request", ordinary, "--request", ordinary]);
    assert.equal(malformed.status, 1);
    assert.match(malformed.stderr, /duplicate/);
  } finally { await rm(directory, { recursive: true, force: true }); }
});
