import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import test from "node:test";

const cli = fileURLToPath(new URL("./cli.mjs", import.meta.url));
const root = path.resolve(path.dirname(cli), "../..");

function run(args, cwd) {
  return spawnSync(process.execPath, [cli, ...args], { cwd, encoding: "utf8", timeout: 20000, maxBuffer: 1024 * 1024 });
}

test("prepare resolves its own source revision from an unrelated working directory and never overwrites a run", t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "archi-visual-cli-"));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const file = path.join(directory, "manifest.json");
  const result = run(["prepare", "--mode", "text_model", "--out", file], directory);
  assert.equal(result.status, 0, result.stderr);
  const manifest = JSON.parse(fs.readFileSync(file, "utf8"));
  const revision = spawnSync("git", ["-C", root, "rev-parse", "HEAD"], { encoding: "utf8" });
  assert.equal(manifest.sourceCommit, revision.stdout.trim());
  assert.equal(typeof manifest.sourceDirty, "boolean");
  assert.match(manifest.implementationSha256, /^[0-9a-f]{64}$/);
  assert.equal(JSON.parse(result.stdout).modelCalls, 0);
  const bytes = fs.readFileSync(file);
  assert.equal(run(["prepare", "--out", file], directory).status, 1);
  assert.deepEqual(fs.readFileSync(file), bytes);
});

test("empty capture remains a visible incomplete report with null rates and exit code 2", t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "archi-visual-empty-"));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const manifest = path.join(directory, "manifest.json"), records = path.join(directory, "records.jsonl"), report = path.join(directory, "report.json");
  assert.equal(run(["prepare", "--out", manifest], directory).status, 0);
  fs.writeFileSync(records, "");
  const result = run(["summarize", "--manifest", manifest, "--records", records, "--out", report], directory);
  assert.equal(result.status, 2, result.stderr);
  const summary = JSON.parse(fs.readFileSync(report, "utf8"));
  assert.equal(summary.evidenceKind, "no_model_observations");
  assert.equal(summary.missing, 40);
  assert.equal(summary.admissionOutcomes, null);
  assert.ok(summary.conditions.every(row => row.steeringDelta === null));
  assert.match(summary.analysisImplementationSha256, /^[0-9a-f]{64}$/);
});

test("invalid or excessive requests fail before creating output", t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "archi-visual-options-"));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const file = path.join(directory, "must-not-exist.json");
  for (const args of [["--replicates", "100000"], ["--mode", "cloud"], ["--seed", "-1"], ["--unexpected", "value"]]) {
    assert.equal(run(["prepare", ...args, "--out", file], directory).status, 1);
    assert.equal(fs.existsSync(file), false);
  }
});
