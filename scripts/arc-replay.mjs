import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { constants } from "node:fs";
import { mkdir, open, readFile, realpath, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const projectRoot = fileURLToPath(new URL("../", import.meta.url));
export const pinnedPaths = Object.freeze([
  "arc/src/contract.ts", "arc/src/evaluate.ts", "arc/src/portable.ts",
  "arc/fixtures/portable/smoke-evaluation-v1.json",
  "arc/fixtures/golden/smoke-evidence-v1.json",
  "scripts/arc-replay-config.json", "scripts/arc-replay-worker.mjs", "scripts/arc-replay.mjs",
]);
const authority = Object.freeze({
  canonWritable: false, journeyWritable: false, memoryWritable: false,
  permissionGrant: false, actionWritable: false, xpDelta: 0,
});
export const digest = (data) => `sha256:${createHash("sha256").update(data).digest("hex")}`;
export function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}`;
  return JSON.stringify(value);
}
function requireCondition(condition, message) { if (!condition) throw new Error(message); }

async function boundedRegularFile(filename, maximum = 2 * 1024 * 1024) {
  const handle = await open(filename, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const stat = await handle.stat();
    requireCondition(stat.isFile() && stat.size <= maximum, "Expected a bounded regular file");
    const bytes = Buffer.alloc(stat.size + 1);
    let length = 0;
    while (length < bytes.length) {
      const next = await handle.read(bytes, length, bytes.length - length);
      if (next.bytesRead === 0) break;
      length += next.bytesRead;
    }
    requireCondition(length <= stat.size && length <= maximum, "File grew during bounded read");
    return bytes.subarray(0, length);
  } finally { await handle.close(); }
}

export async function runtimeIdentity() {
  const executable = await realpath(process.execPath);
  const bytes = await boundedRegularFile(executable, 512 * 1024 * 1024);
  return { node: process.version, platform: process.platform, architecture: process.arch,
    versions: { ...process.versions }, executableSHA256: digest(bytes) };
}

/** A fresh process and copied source tree are reproducibility isolation, not an
 * operating-system security sandbox. Only reviewed, exact pinned code runs. */
export async function runReplay({ root = projectRoot, outputDirectory }) {
  requireCondition(typeof outputDirectory === "string" && outputDirectory.length > 0, "A fresh output directory is required");
  const output = path.resolve(outputDirectory);
  // Never reuse an output directory or replace a prior success/failure receipt.
  await mkdir(output, { mode: 0o700 });
  const startedAt = new Date().toISOString();
  const started = performance.now();
  const manifest = {
    schema: "archi-arc-checker-replay-run/v1", status: "FAILED", qualification: "not-qualified",
    scope: "Existing deterministic checker replay over fixed synthetic predictions",
    startedAt, finishedAt: null, elapsedMilliseconds: null,
    authority, solverExecuted: false, inferenceCalls: 0, checkerProcessAttempts: 0,
    environment: null, pinsSHA256: null, sourceHashes: {}, semanticSHA256: null,
    artifactHashes: {}, phase: "preflight", failures: [],
    boundaries: ["No solver execution", "No inference or provider", "No capability certification",
      "No model training", "No user data", "No companion state mutation",
      "Fixture solver identity remains unattested; checker repeatability does not attest that solver"],
  };
  try {
    const pinsBytes = await boundedRegularFile(path.join(root, "scripts/arc-replay-pins.json"));
    manifest.pinsSHA256 = digest(pinsBytes);
    const pins = JSON.parse(pinsBytes.toString("utf8"));
    requireCondition(pins.schema === "archi-arc-checker-replay-pins/v1", "Unsupported replay pins schema");
    requireCondition(canonical(Object.keys(pins.files ?? {}).sort()) === canonical([...pinnedPaths].sort()), "Pins must cover the exact checker dependency closure");
    manifest.environment = await runtimeIdentity();
    requireCondition(canonical(manifest.environment) === canonical(pins.environment), "Pinned runtime dependency changed; qualification invalidated");

    // Capture each exact file once; execute the copied bytes, never a later live read.
    const snapshot = path.join(output, "snapshot");
    const buffers = new Map();
    for (const relative of pinnedPaths) {
      const bytes = await boundedRegularFile(path.join(root, relative));
      manifest.sourceHashes[relative] = digest(bytes);
      requireCondition(digest(bytes) === pins.files[relative], `Pinned file changed; qualification invalidated: ${relative}`);
      buffers.set(relative, bytes);
    }
    // This also rejects a caller swapping the harness used for the run while
    // pointing --root at another tree with different claimed harness bytes.
    requireCondition(digest(await boundedRegularFile(fileURLToPath(import.meta.url))) === pins.files["scripts/arc-replay.mjs"], "Executing harness differs from pinned source");
    const config = JSON.parse(buffers.get("scripts/arc-replay-config.json").toString("utf8"));
    requireCondition(config.schema === "archi-arc-checker-replay-config/v1"
      && config.operation === "rescore-fixed-synthetic-predictions"
      && config.dependencies === "node-builtins-only"
      && config.input === "arc/fixtures/portable/smoke-evaluation-v1.json"
      && config.golden === "arc/fixtures/golden/smoke-evidence-v1.json"
      && config.timeoutMilliseconds === 10000 && config.maximumOldSpaceMiB === 128
      && config.solverExecution === false && config.inferenceCalls === 0 && config.stateWriteAuthority === false,
    "Replay configuration exceeded the fixed checker boundary");
    for (const [relative, bytes] of buffers) {
      const target = path.join(snapshot, relative);
      await mkdir(path.dirname(target), { recursive: true, mode: 0o700 });
      await writeFile(target, bytes, { flag: "wx", mode: 0o600 });
    }
    await writeFile(path.join(snapshot, "pins.json"), pinsBytes, { flag: "wx", mode: 0o600 });
    const execution = path.join(output, "execution");
    await mkdir(execution, { mode: 0o700 });
    manifest.phase = "checker-execution";
    manifest.checkerProcessAttempts = 1;
    const child = spawnSync(process.execPath, ["--max-old-space-size=128",
      path.join(snapshot, "scripts/arc-replay-worker.mjs"), snapshot, execution], {
      cwd: execution, encoding: "utf8", timeout: config.timeoutMilliseconds,
      maxBuffer: 1024 * 1024, killSignal: "SIGKILL",
      env: { PATH: path.dirname(process.execPath), LANG: "C", TZ: "UTC" },
    });
    manifest.execution = { exitCode: child.status, signal: child.signal,
      error: child.error ? String(child.error.message) : null };
    for (const [name, text] of [["stdout.log", child.stdout ?? ""], ["stderr.log", child.stderr ?? ""]]) {
      await writeFile(path.join(output, name), text, { flag: "wx", mode: 0o600 });
      manifest.artifactHashes[name] = digest(text);
    }
    requireCondition(!child.error && child.status === 0, "Checker failed; inspect retained stderr.log and execution outcome");
    manifest.phase = "output-validation";
    const semanticBytes = await boundedRegularFile(path.join(execution, "semantic.json"));
    const semantic = JSON.parse(semanticBytes.toString("utf8"));
    const golden = JSON.parse(buffers.get(config.golden).toString("utf8"));
    requireCondition(semantic.schema === "archi-arc-checker-replay-output/v1"
      && semantic.operation === config.operation && semantic.solverExecuted === false && semantic.inferenceCalls === 0
      && canonical(semantic.authority) === canonical(authority), "Invalid checker replay output authority");
    requireCondition(semantic.proposal?.proposalHash === golden.proposalHash
      && canonical(semantic.proposal?.counts) === canonical(config.expectedCounts)
      && canonical(semantic.receipts?.map((value) => value.receiptHash).sort()) === canonical(golden.receiptHashes),
    "Checker output differs from pinned golden result");
    manifest.semanticSHA256 = digest(canonical(semantic));
    manifest.artifactHashes["execution/semantic.json"] = digest(semanticBytes);
    manifest.artifactHashes["execution/compiled-hashes.json"] = digest(await boundedRegularFile(path.join(execution, "compiled-hashes.json")));
    manifest.result = { proposalHash: semantic.proposal.proposalHash, receiptHashes: semantic.proposal.receiptHashes,
      counts: semantic.proposal.counts, exactRate: semantic.proposal.exactRate };
    manifest.status = "PASS";
    manifest.qualification = "pinned-synthetic-checker-replay-only";
    manifest.phase = "complete";
  } catch (error) {
    manifest.failures.push(String(error.message ?? error));
  }
  manifest.finishedAt = new Date().toISOString();
  manifest.elapsedMilliseconds = Math.max(0, Math.round(performance.now() - started));
  await writeFile(path.join(output, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`, { flag: "wx", mode: 0o600 });
  return manifest;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  try {
    const options = {};
    while (args.length) {
      const name = args.shift(), value = args.shift();
      requireCondition(["--output", "--root"].includes(name) && value && !value.startsWith("--") && options[name] === undefined,
        "Usage: node scripts/arc-replay.mjs --output <fresh-directory> [--root <project-root>]");
      options[name] = value;
    }
    const result = await runReplay({ root: options["--root"] ?? projectRoot, outputDirectory: options["--output"] });
    process.stdout.write(`${JSON.stringify({ status: result.status, qualification: result.qualification,
      semanticSHA256: result.semanticSHA256, manifest: path.resolve(options["--output"], "manifest.json"), failures: result.failures })}\n`);
    process.exitCode = result.status === "PASS" ? 0 : 1;
  } catch (error) {
    process.stderr.write(`ARC REPLAY ERROR: ${error.message}\n`);
    process.exitCode = 1;
  }
}
