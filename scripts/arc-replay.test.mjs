import assert from "node:assert/strict";
import { appendFile, mkdir, mkdtemp, readFile, rm, unlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { digest, pinnedPaths, projectRoot, runReplay } from "./arc-replay.mjs";

async function fixture(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(), "archi-checker-replay-test-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const root = path.join(directory, "project");
  await mkdir(root);
  for (const relative of [...pinnedPaths, "scripts/arc-replay-pins.json"]) {
    const target = path.join(root, relative);
    await mkdir(path.dirname(target), { recursive: true });
    await writeFile(target, await readFile(path.join(projectRoot, relative)), { flag: "wx" });
  }
  return { root, outputDirectory: path.join(directory, "run"), second: path.join(directory, "second") };
}
async function pins(fixture, update) {
  const file = path.join(fixture.root, "scripts/arc-replay-pins.json");
  const value = JSON.parse(await readFile(file, "utf8"));
  update(value);
  await writeFile(file, `${JSON.stringify(value, null, 2)}\n`);
}
async function retainedFailure(fixture, expected, attempted = 0) {
  const result = await runReplay(fixture);
  assert.equal(result.status, "FAILED");
  assert.equal(result.qualification, "not-qualified");
  assert.equal(result.semanticSHA256, null);
  assert.equal(result.checkerProcessAttempts, attempted);
  assert.equal(result.solverExecuted, false);
  assert.equal(result.inferenceCalls, 0);
  assert.match(result.failures.join("; "), expected);
  assert.deepEqual(JSON.parse(await readFile(path.join(fixture.outputDirectory, "manifest.json"), "utf8")), result);
  return result;
}

test("two fresh isolated checker replays have identical semantics and preserve the existing golden boundary", async (t) => {
  const paths = await fixture(t);
  const first = await runReplay(paths);
  const second = await runReplay({ root: paths.root, outputDirectory: paths.second });
  assert.equal(first.status, "PASS", first.failures.join("; "));
  assert.equal(second.status, "PASS", second.failures.join("; "));
  assert.equal(first.semanticSHA256, second.semanticSHA256);
  assert.deepEqual(first.sourceHashes, second.sourceHashes);
  assert.deepEqual(first.environment, second.environment);
  assert.notEqual(first.startedAt, second.startedAt);
  assert.deepEqual(first.result.counts, { exact: 1, incorrect: 1, missing: 0, invalid: 0,
    unscored: 0, totalExamples: 2, exactTasks: 0, totalTasks: 1 });
  assert.equal(first.result.proposalHash, "sha256:d07944169a6ee25b3e43ecf445a5644a7abadba13a855706ae562ad9bf67c4b7");
  assert.equal(first.inferenceCalls, 0);
  assert.equal(first.solverExecuted, false);
  const semantic = JSON.parse(await readFile(path.join(paths.outputDirectory, "execution/semantic.json"), "utf8"));
  assert.equal(semantic.proposal.certification, "not-certified");
  assert.equal(semantic.proposal.status, "proposed");
  assert.ok(semantic.receipts.every((receipt) => receipt.attestation === "unattested" && receipt.reproducible === false));
  assert.deepEqual(Object.values(semantic.authority), [false, false, false, false, false, 0]);
  for (const [relative, hash] of Object.entries(first.sourceHashes)) {
    assert.equal(digest(await readFile(path.join(paths.root, relative))), hash);
    assert.equal(digest(await readFile(path.join(paths.outputDirectory, "snapshot", relative))), hash);
  }
});

test("source modification invalidates qualification before checker execution", async (t) => {
  const paths = await fixture(t);
  await appendFile(path.join(paths.root, "arc/src/portable.ts"), '\nthrow new Error("must not execute changed source");\n');
  await retainedFailure(paths, /Pinned file changed.*arc\/src\/portable/);
});

test("changed imported checker dependency invalidates the same qualification", async (t) => {
  const paths = await fixture(t);
  await appendFile(path.join(paths.root, "arc/src/contract.ts"), "\n// changed dependency\n");
  await retainedFailure(paths, /Pinned file changed.*arc\/src\/contract/);
});

test("changed built-in runtime dependency identity invalidates qualification", async (t) => {
  const paths = await fixture(t);
  await pins(paths, (value) => { value.environment.versions.amaro = "different-type-stripper"; });
  await retainedFailure(paths, /Pinned runtime dependency changed/);
});

test("configuration change cannot silently reuse a previous qualification", async (t) => {
  const paths = await fixture(t);
  await appendFile(path.join(paths.root, "scripts/arc-replay-config.json"), "\n");
  await retainedFailure(paths, /Pinned file changed.*arc-replay-config/);
});

test("removing a fixed prediction changes input identity and retains failure", async (t) => {
  const paths = await fixture(t);
  const file = path.join(paths.root, "arc/fixtures/portable/smoke-evaluation-v1.json");
  const value = JSON.parse(await readFile(file, "utf8"));
  value.evaluations[0].predictions.pop();
  await writeFile(file, JSON.stringify(value));
  await retainedFailure(paths, /Pinned file changed.*smoke-evaluation/);
});

test("missing input produces a failure manifest without fabricated output", async (t) => {
  const paths = await fixture(t);
  await unlink(path.join(paths.root, "arc/fixtures/portable/smoke-evaluation-v1.json"));
  await retainedFailure(paths, /ENOENT/);
});

test("missing expected output refuses qualification rather than learning a new oracle", async (t) => {
  const paths = await fixture(t);
  await unlink(path.join(paths.root, "arc/fixtures/golden/smoke-evidence-v1.json"));
  await retainedFailure(paths, /ENOENT/);
});

test("malformed input rejected by the actual checker retains execution logs", async (t) => {
  const paths = await fixture(t);
  const relative = "arc/fixtures/portable/smoke-evaluation-v1.json";
  const bytes = Buffer.from('{"schema":"wrong"}');
  await writeFile(path.join(paths.root, relative), bytes);
  // A deliberately separate test pin set reaches the real checker. It does not
  // modify the repository's trusted input or its qualification definition.
  await pins(paths, (value) => { value.files[relative] = digest(bytes); });
  const result = await retainedFailure(paths, /Checker failed/, 1);
  assert.equal(result.phase, "checker-execution");
  assert.equal(result.execution.exitCode, 1);
  assert.match(await readFile(path.join(paths.outputDirectory, "stderr.log"), "utf8"), /unsupported schema or fields/);
});

test("an incompatible golden oracle is a retained failed replay", async (t) => {
  const paths = await fixture(t);
  const relative = "arc/fixtures/golden/smoke-evidence-v1.json";
  const value = JSON.parse(await readFile(path.join(paths.root, relative), "utf8"));
  value.proposalHash = `sha256:${"0".repeat(64)}`;
  const bytes = Buffer.from(JSON.stringify(value));
  await writeFile(path.join(paths.root, relative), bytes);
  await pins(paths, (pin) => { pin.files[relative] = digest(bytes); });
  await retainedFailure(paths, /Checker failed/, 1);
  assert.match(await readFile(path.join(paths.outputDirectory, "stderr.log"), "utf8"), /Golden proposal mismatch/);
});

test("a missing pin dependency cannot shrink the declared closure", async (t) => {
  const paths = await fixture(t);
  await pins(paths, (value) => { delete value.files["arc/src/contract.ts"]; });
  await retainedFailure(paths, /exact checker dependency closure/);
});

test("rerunning into an existing output never overwrites its retained manifest", async (t) => {
  const paths = await fixture(t);
  const first = await runReplay(paths);
  assert.equal(first.status, "PASS");
  const before = await readFile(path.join(paths.outputDirectory, "manifest.json"));
  await assert.rejects(runReplay(paths), /EEXIST/);
  assert.deepEqual(await readFile(path.join(paths.outputDirectory, "manifest.json")), before);
});
