import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { PROTECTED_RUNTIME_PATHS, sealRuntimePolicy, verifyRuntimeCandidate } from "./runtime-integrity-guard.mjs";

const repository = fileURLToPath(new URL("../", import.meta.url));
const guardPath = "scripts/runtime-integrity-guard.mjs";
const monitorPath = "scripts/episode-trace.mjs";
const monitorTestPath = "scripts/episode-trace.test.mjs";
const sha256 = (bytes) => `sha256:${createHash("sha256").update(bytes).digest("hex")}`;
const cleanEnvironment = { PATH: path.dirname(process.execPath), HOME: os.tmpdir(), LANG: "C" };

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "archi-integrity-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const trusted = path.join(root, "trusted"), candidate = path.join(root, "candidate");
  fs.mkdirSync(trusted); fs.mkdirSync(candidate);
  for (const relative of PROTECTED_RUNTIME_PATHS) {
    for (const destination of [trusted, candidate]) {
      fs.mkdirSync(path.dirname(path.join(destination, relative)), { recursive: true });
      fs.copyFileSync(path.join(repository, relative), path.join(destination, relative));
    }
  }
  const policy = sealRuntimePolicy({ trustedRoot: trusted, sourceRevision: "a".repeat(40) });
  const policyPath = path.join(trusted, "policy.json");
  fs.writeFileSync(policyPath, policy.bytes);
  const verify = () => verifyRuntimeCandidate({ candidateRoot: candidate,
    policyBytes: fs.readFileSync(policyPath), expectedPolicyDigest: policy.sha256 });
  const cli = () => spawnSync(process.execPath, [path.join(trusted, guardPath), "verify",
    "--candidate-root", candidate, "--policy", policyPath, "--policy-sha256", policy.sha256],
  { cwd: trusted, env: cleanEnvironment, encoding: "utf8", timeout: 10_000 });
  return { root, trusted, candidate, policy, policyPath, verify, cli };
}

function weakenMonitor(candidate) {
  const target = path.join(candidate, monitorPath);
  const original = fs.readFileSync(target, "utf8");
  const weakened = original.replace("return validateTraceShape(trace, options);", "return true;");
  assert.notEqual(original, weakened, "The attack must modify the real exported evidence verifier");
  fs.writeFileSync(target, weakened);
  fs.writeFileSync(path.join(candidate, monitorTestPath), `import test from 'node:test';
import assert from 'node:assert/strict';
import { validateEpisodeTrace } from './episode-trace.mjs';
test('rewritten test accepts an absent monitoring record', () => assert.equal(validateEpisodeTrace({}), true));
`);
}

test("unchanged protected files pass without authorizing execution; unrelated edits remain proposals", (t) => {
  const f = fixture(t);
  fs.writeFileSync(path.join(f.candidate, "proposal.txt"), "An unreviewed proposal");
  const report = f.verify();
  assert.equal(report.decision, "PASS");
  assert.equal(report.actionAuthorized, false);
  assert.equal(report.candidateExecuted, false);
  assert.equal(report.protectedFiles, PROTECTED_RUNTIME_PATHS.length);
  const cli = f.cli();
  assert.equal(cli.status, 0, cli.stderr);
  assert.deepEqual(JSON.parse(cli.stdout), report);
});

test("removing evidence validation and rewriting its test can pass locally but fails the external check", (t) => {
  const f = fixture(t);
  weakenMonitor(f.candidate);
  // A candidate-controlled source manifest is no substitute for the external policy.
  fs.writeFileSync(path.join(f.candidate, "SOURCE_SHA256SUMS"), "attacker recomputed local manifest\n");
  const local = spawnSync(process.execPath, ["--test", monitorTestPath],
    { cwd: f.candidate, env: cleanEnvironment, encoding: "utf8", timeout: 10_000 });
  assert.equal(local.status, 0, local.stdout + local.stderr);
  const report = f.verify();
  assert.equal(report.decision, "REJECT");
  assert.deepEqual(report.findings.map((finding) => finding.path).sort(), [monitorPath, monitorTestPath].sort());
  const cli = f.cli();
  assert.equal(cli.status, 1, cli.stderr);
  assert.equal(JSON.parse(cli.stdout).decision, "REJECT");
});

test("replacing the candidate checker cannot replace the separately invoked checker", (t) => {
  const f = fixture(t);
  fs.writeFileSync(path.join(f.candidate, guardPath), "process.exit(0);\n");
  assert.equal(f.verify().decision, "REJECT");
  assert.equal(f.cli().status, 1);
});

test("modified policy and missing independent pin fail closed", (t) => {
  const f = fixture(t);
  fs.appendFileSync(f.policyPath, " ");
  assert.throws(f.verify, /digest mismatch/);
  assert.equal(f.cli().status, 1);
  assert.throws(() => verifyRuntimeCandidate({ candidateRoot: f.candidate, policyBytes: f.policy.bytes }), /pinned/);
});

test("a policy cannot silently remove a protected file even with a newly supplied digest", (t) => {
  const f = fixture(t);
  const policy = JSON.parse(f.policy.bytes);
  policy.files.pop();
  const bytes = Buffer.from(JSON.stringify(policy));
  assert.throws(() => verifyRuntimeCandidate({ candidateRoot: f.candidate,
    policyBytes: bytes, expectedPolicyDigest: sha256(bytes) }), /Invalid trusted policy/);
});

test("missing files, linked files and linked ancestors are rejected", (t) => {
  const f = fixture(t);
  const target = path.join(f.candidate, monitorPath);
  fs.unlinkSync(target);
  assert.equal(f.verify().decision, "REJECT");
  fs.symlinkSync(path.join(f.trusted, monitorPath), target);
  assert.equal(f.verify().decision, "REJECT");
  fs.unlinkSync(target);
  fs.linkSync(path.join(f.trusted, monitorPath), target);
  assert.equal(f.verify().decision, "REJECT");
  fs.unlinkSync(target);
  fs.rmSync(path.join(f.candidate, "scripts"), { recursive: true });
  fs.symlinkSync(path.join(f.trusted, "scripts"), path.join(f.candidate, "scripts"));
  assert.equal(f.verify().decision, "REJECT");
});

test("oversized protected content is rejected", (t) => {
  const f = fixture(t);
  fs.writeFileSync(path.join(f.candidate, monitorPath), Buffer.alloc(2 * 1024 * 1024 + 1));
  assert.equal(f.verify().findings.find((finding) => finding.path === monitorPath)?.reason,
    "missing-or-unsafe-protected-file");
});

test("CLI refuses a candidate-owned policy or checker", (t) => {
  const f = fixture(t);
  const args = ["verify", "--candidate-root", f.candidate,
    "--policy", f.policyPath, "--policy-sha256", f.policy.sha256];
  const fromCandidate = spawnSync(process.execPath, [path.join(f.candidate, guardPath), ...args],
    { env: cleanEnvironment, encoding: "utf8", timeout: 10_000 });
  assert.equal(fromCandidate.status, 1);
  assert.match(JSON.parse(fromCandidate.stdout).error, /outside/);
  const candidatePolicy = path.join(f.candidate, "policy.json");
  fs.copyFileSync(f.policyPath, candidatePolicy);
  args[args.indexOf("--policy") + 1] = candidatePolicy;
  const badPolicy = spawnSync(process.execPath, [path.join(f.trusted, guardPath), ...args],
    { env: cleanEnvironment, encoding: "utf8", timeout: 10_000 });
  assert.equal(badPolicy.status, 1);
  assert.match(JSON.parse(badPolicy.stdout).error, /outside/);
});

test("sealing requires a source revision and cannot overwrite or store the policy in its checkout", (t) => {
  const f = fixture(t);
  assert.throws(() => sealRuntimePolicy({ trustedRoot: f.trusted }), /approved source revision/);
  for (const output of [f.policyPath, path.join(f.root, "existing.json")]) {
    fs.writeFileSync(output, "preserved");
    const result = spawnSync(process.execPath, [path.join(f.trusted, guardPath), "seal",
      "--trusted-root", f.trusted, "--source-revision", "a".repeat(40), "--output", output],
    { env: cleanEnvironment, encoding: "utf8", timeout: 10_000 });
    assert.equal(result.status, 1);
    assert.equal(fs.readFileSync(output, "utf8"), "preserved");
  }
});

function uidIsolationPrerequisite() {
  if (process.platform !== "linux" || process.getuid?.() !== 0) {
    return "Needs an isolated Linux root runner to drop the attack process to UID/GID 65534";
  }
  for (const map of ["/proc/self/uid_map", "/proc/self/gid_map"]) {
    const mapped = fs.readFileSync(map, "utf8").trim().split("\n").some((line) => {
      const [start, , count] = line.trim().split(/\s+/).map(Number);
      return start <= 65534 && start + count > 65534;
    });
    if (!mapped) return "The host namespace does not map UID/GID 65534; OS isolation is untested";
  }
  return false;
}

test("a separate Linux UID can alter its candidate but cannot overwrite the trusted checker or policy", {
  skip: process.env.ARCHI_REQUIRE_UID_ISOLATION === "1" ? false : uidIsolationPrerequisite(),
}, (t) => {
  assert.equal(uidIsolationPrerequisite(), false, "Required UID isolation prerequisites must be present");
  const f = fixture(t);
  fs.chmodSync(f.root, 0o755);
  function giveCandidateToProposer(directory) {
    fs.chownSync(directory, 65534, 65534);
    fs.chmodSync(directory, 0o755);
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const target = path.join(directory, entry.name);
      if (entry.isDirectory()) giveCandidateToProposer(target);
      else { fs.chownSync(target, 65534, 65534); fs.chmodSync(target, 0o644); }
    }
  }
  giveCandidateToProposer(f.candidate);
  const attack = `const fs = require('node:fs');
const [checker, policy, candidate] = process.argv.slice(1);
for (const target of [checker, policy]) {
  try { fs.writeFileSync(target, 'tampered'); process.exit(2); }
  catch (error) { if (error.code !== 'EACCES') throw error; }
}
fs.writeFileSync(candidate, 'candidate changed by untrusted uid');
console.log(JSON.stringify({deniedTrustedWrites: 2, candidateWritten: true}));`;
  const attempt = spawnSync(process.execPath, ["-e", attack, path.join(f.trusted, guardPath),
    f.policyPath, path.join(f.candidate, monitorPath)], { uid: 65534, gid: 65534,
    cwd: f.candidate, env: cleanEnvironment, encoding: "utf8", timeout: 10_000 });
  assert.equal(attempt.status, 0, attempt.stderr);
  assert.deepEqual(JSON.parse(attempt.stdout), { deniedTrustedWrites: 2, candidateWritten: true });
  assert.equal(f.verify().decision, "REJECT");
});
