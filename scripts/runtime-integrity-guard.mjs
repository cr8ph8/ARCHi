import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

// This list belongs to the trusted verifier release, never to the candidate.
export const PROTECTED_RUNTIME_PATHS = Object.freeze([
  ".github/workflows/source-checks.yml",
  "arc/fixtures/golden/smoke-evidence-v1.json",
  "arc/fixtures/manifest.json",
  "arc/src/contract.ts",
  "arc/src/evaluate.ts",
  "arc/test/evaluate.test.ts",
  "arc/tsconfig.json",
  "desktop/Sources/ARCHiDesktop/CompanionStore.swift",
  "desktop/Sources/ARCHiDesktop/DesktopProfileBackup.swift",
  "desktop/Sources/ARCHiDesktop/DesktopRecoveryIntegration.swift",
  "desktop/Sources/ARCHiDesktop/HamptonAdmissionOutcome.swift",
  "desktop/Sources/ARCHiDesktop/HamptonProposalValidation.swift",
  "desktop/Tests/ARCHiDesktopTests/DesktopInterestStoreTests.swift",
  "desktop/Tests/ARCHiDesktopTests/DesktopProfileBackupTests.swift",
  "desktop/Tests/ARCHiDesktopTests/DesktopRecoveryIntegrationTests.swift",
  "desktop/Tests/ARCHiDesktopTests/HamptonProposalValidationTests.swift",
  "package-lock.json",
  "package.json",
  "scripts/boundary-text.mjs",
  "scripts/boundary-text.test.mjs",
  "scripts/episode-trace.mjs",
  "scripts/episode-trace.test.mjs",
  "scripts/runtime-integrity-guard.mjs",
  "scripts/runtime-integrity-guard.test.mjs",
  "tsconfig.json",
].sort());

const MAX_FILE_BYTES = 2 * 1024 * 1024;
const MAX_POLICY_BYTES = 64 * 1024;
const digest = (bytes) => `sha256:${createHash("sha256").update(bytes).digest("hex")}`;
const exactKeys = (value, keys) => value !== null && typeof value === "object" && !Array.isArray(value)
  && JSON.stringify(Object.keys(value).sort()) === JSON.stringify([...keys].sort());

function directory(root) {
  if (!fs.lstatSync(root).isDirectory()) throw new Error("Root must be a real directory");
  return fs.realpathSync(root);
}

function within(root, target) {
  const relative = path.relative(root, target);
  return relative === "" || (!relative.startsWith(`..${path.sep}`) && relative !== ".." && !path.isAbsolute(relative));
}

function readRegular(root, relative, limit = MAX_FILE_BYTES) {
  const parts = relative.split("/");
  if (parts.some((part) => !part || part === "." || part === "..") || path.isAbsolute(relative)) {
    throw new Error("Unsafe relative path");
  }
  let current = root;
  for (const part of parts.slice(0, -1)) {
    current = path.join(current, part);
    if (!fs.lstatSync(current).isDirectory()) throw new Error("Linked or non-directory ancestor");
  }
  current = path.join(current, parts.at(-1));
  const entry = fs.lstatSync(current);
  if (!entry.isFile() || entry.nlink !== 1 || entry.size > limit) throw new Error("Not a bounded, unlinked regular file");
  const fd = fs.openSync(current, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW ?? 0));
  try {
    const opened = fs.fstatSync(fd);
    if (!opened.isFile() || opened.nlink !== 1 || opened.ino !== entry.ino || opened.dev !== entry.dev) {
      throw new Error("File changed during inspection");
    }
    const buffer = Buffer.alloc(limit + 1);
    let size = 0;
    while (size < buffer.length) {
      const count = fs.readSync(fd, buffer, size, buffer.length - size, null);
      if (count === 0) break;
      size += count;
    }
    if (size > limit || size !== opened.size) throw new Error("File exceeded its bound or changed");
    return buffer.subarray(0, size);
  } finally { fs.closeSync(fd); }
}

export function sealRuntimePolicy({ trustedRoot, sourceRevision }) {
  if (!/^[a-f0-9]{40}$/.test(sourceRevision ?? "")) throw new Error("A full approved source revision is required");
  const root = directory(trustedRoot);
  const files = PROTECTED_RUNTIME_PATHS.map((relative) => {
    const bytes = readRegular(root, relative);
    return { path: relative, bytes: bytes.length, sha256: digest(bytes) };
  });
  const bytes = Buffer.from(`${JSON.stringify({ schemaVersion: 1, sourceRevision, files }, null, 2)}\n`);
  return { bytes, sha256: digest(bytes) };
}

export function verifyRuntimeCandidate({ candidateRoot, policyBytes, expectedPolicyDigest }) {
  if (!/^sha256:[a-f0-9]{64}$/.test(expectedPolicyDigest ?? "")) throw new Error("An independently pinned policy digest is required");
  if (policyBytes.length > MAX_POLICY_BYTES || digest(policyBytes) !== expectedPolicyDigest) {
    throw new Error("Trusted policy digest mismatch");
  }
  const policy = JSON.parse(policyBytes.toString("utf8"));
  if (!exactKeys(policy, ["schemaVersion", "sourceRevision", "files"]) || policy.schemaVersion !== 1
      || !/^[a-f0-9]{40}$/.test(policy.sourceRevision) || !Array.isArray(policy.files)
      || policy.files.length !== PROTECTED_RUNTIME_PATHS.length) throw new Error("Invalid trusted policy");
  policy.files.forEach((file, index) => {
    if (!exactKeys(file, ["path", "bytes", "sha256"]) || file.path !== PROTECTED_RUNTIME_PATHS[index]
        || !Number.isSafeInteger(file.bytes) || file.bytes < 0 || file.bytes > MAX_FILE_BYTES
        || !/^sha256:[a-f0-9]{64}$/.test(file.sha256)) throw new Error("Invalid protected file policy");
  });
  const root = directory(candidateRoot);
  const findings = [];
  for (const file of policy.files) {
    try {
      const bytes = readRegular(root, file.path);
      const actual = digest(bytes);
      if (bytes.length !== file.bytes || actual !== file.sha256) {
        findings.push({ path: file.path, reason: "protected-content-changed", expected: file.sha256, actual });
      }
    } catch {
      findings.push({ path: file.path, reason: "missing-or-unsafe-protected-file" });
    }
  }
  return Object.freeze({ schemaVersion: 1, scope: "protected-source-integrity-only",
    decision: findings.length ? "REJECT" : "PASS", sourceRevision: policy.sourceRevision,
    policySha256: expectedPolicyDigest, protectedFiles: policy.files.length,
    candidateExecuted: false, actionAuthorized: false, findings });
}

function main() {
  const { positionals, values } = parseArgs({ allowPositionals: true, options: {
    "trusted-root": { type: "string" }, "source-revision": { type: "string" },
    output: { type: "string" }, "candidate-root": { type: "string" },
    policy: { type: "string" }, "policy-sha256": { type: "string" },
  } });
  if (positionals.length !== 1) throw new Error("Use seal or verify with explicit paths");
  if (positionals[0] === "seal") {
    const policy = sealRuntimePolicy({ trustedRoot: values["trusted-root"], sourceRevision: values["source-revision"] });
    const output = path.resolve(values.output);
    if (within(directory(values["trusted-root"]), fs.realpathSync(path.dirname(output)))) {
      throw new Error("Keep the trusted policy outside the source checkout");
    }
    fs.writeFileSync(output, policy.bytes, { flag: "wx", mode: 0o600 });
    process.stdout.write(`${JSON.stringify({ policySha256: policy.sha256 })}\n`);
  } else if (positionals[0] === "verify") {
    const root = directory(values["candidate-root"]);
    const policyPath = fs.realpathSync(values.policy);
    if (within(root, fs.realpathSync(fileURLToPath(import.meta.url))) || within(root, policyPath)) {
      throw new Error("Verifier and policy must be outside the candidate checkout");
    }
    const policyBytes = readRegular(path.dirname(policyPath), path.basename(policyPath), MAX_POLICY_BYTES);
    const report = verifyRuntimeCandidate({ candidateRoot: root, policyBytes, expectedPolicyDigest: values["policy-sha256"] });
    process.stdout.write(`${JSON.stringify(report)}\n`);
    if (report.decision !== "PASS") process.exitCode = 1;
  } else throw new Error("Unknown command");
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { main(); }
  catch (error) {
    process.stdout.write(`${JSON.stringify({ decision: "REJECT", scope: "protected-source-integrity-only",
      candidateExecuted: false, actionAuthorized: false, error: error.message })}\n`);
    process.exitCode = 1;
  }
}
