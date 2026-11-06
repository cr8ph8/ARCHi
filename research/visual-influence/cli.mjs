import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { createManifest, validateManifest, summarizeRecords, sha256 } from "./experiment.mjs";

const scriptRoot = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(scriptRoot, "../..");

function sourceIdentity() {
  const revision = spawnSync("git", ["-C", repositoryRoot, "rev-parse", "HEAD"], { encoding: "utf8" });
  const dirty = spawnSync("git", ["-C", repositoryRoot, "status", "--porcelain", "--untracked-files=normal"], { encoding: "utf8" });
  const files = ["experiment.mjs", "classify.py", "ollama.mjs", "cli.mjs"];
  const bytes = files.map(name => Buffer.concat([Buffer.from(name + "\0"), fs.readFileSync(path.join(scriptRoot, name)), Buffer.from("\0")]));
  return { sourceCommit: revision.status === 0 ? revision.stdout.trim() : "unrecorded",
    sourceDirty: dirty.status === 0 ? dirty.stdout.trim().length > 0 : null,
    implementationSha256: sha256(Buffer.concat(bytes)) };
}

const [command, ...arguments_] = process.argv.slice(2);
const options = Object.create(null);
for (let index = 0; index < arguments_.length; index += 2) {
  const key = arguments_[index], value = arguments_[index + 1];
  if (!key?.startsWith("--") || value === undefined || value.startsWith("--") || Object.hasOwn(options, key.slice(2))) {
    throw new Error("Options must be unique --name value pairs");
  }
  options[key.slice(2)] = value;
}

function requireOptions(allowed, required) {
  for (const key of Object.keys(options)) if (!allowed.includes(key)) throw new Error(`Unknown option --${key}`);
  for (const key of required) if (!options[key]) throw new Error(`Missing --${key}`);
}

function numberOption(name, fallback) {
  const value = options[name] === undefined ? fallback : Number(options[name]);
  if (!Number.isSafeInteger(value)) throw new Error(`--${name} must be an integer`);
  return value;
}

function readJSON(file) {
  const stat = fs.statSync(file);
  if (!stat.isFile() || stat.size > 32 * 1024 * 1024) throw new Error("Input must be a file of at most 32 MiB");
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function writeNew(file, value) {
  fs.mkdirSync(path.dirname(path.resolve(file)), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(value, null, 2) + "\n", { flag: "wx", mode: 0o600 });
}

try {
  if (command === "prepare") {
    requireOptions(["mode", "replicates", "seed", "out"], ["out"]);
    const manifest = createManifest({ mode: options.mode ?? "text_model", replicates: numberOption("replicates", 2),
      seed: numberOption("seed", 17), ...sourceIdentity() });
    writeNew(options.out, manifest);
    console.log(JSON.stringify({ status: "PREPARED", mode: manifest.mode, jobs: manifest.jobs.length,
      manifestSha256: manifest.manifestSha256, file: options.out, modelCalls: 0 }));
  } else if (command === "collect") {
    requireOptions(["manifest", "model", "base-url", "max-requests", "out"], ["manifest", "model", "out"]);
    const manifest = validateManifest(readJSON(options.manifest));
    if (manifest.implementationSha256 !== sourceIdentity().implementationSha256) {
      throw new Error("Harness changed since preparation; prepare a new run before collection");
    }
    const { collectOllama } = await import("./ollama.mjs");
    fs.mkdirSync(path.dirname(path.resolve(options.out)), { recursive: true });
    const descriptor = fs.openSync(options.out, "wx", 0o600);
    let result;
    try {
      result = await collectOllama(manifest, { model: options.model, baseUrl: options["base-url"] ?? "http://127.0.0.1:11434",
        maxRequests: numberOption("max-requests", manifest.jobs.length),
        onRecord(record) { fs.writeSync(descriptor, JSON.stringify(record) + "\n"); fs.fsyncSync(descriptor); } });
    } finally { fs.closeSync(descriptor); }
    const completed = result.records.filter(row => row.status === "completed").length;
    const complete = completed === manifest.jobs.length;
    console.log(JSON.stringify({ status: complete ? "COMPLETE" : "INCOMPLETE", file: options.out,
      completed,
      errors: result.records.filter(row => row.status === "error").length,
      skipped: result.records.filter(row => row.status === "skipped").length }));
    if (!complete) process.exitCode = 2;
  } else if (command === "summarize") {
    requireOptions(["manifest", "records", "out"], ["manifest", "records", "out"]);
    const manifest = readJSON(options.manifest), stat = fs.statSync(options.records);
    if (!stat.isFile() || stat.size > 32 * 1024 * 1024) throw new Error("Records exceed 32 MiB");
    const records = fs.readFileSync(options.records, "utf8").split("\n").filter(line => line.trim()).map(line => JSON.parse(line));
    const summary = { ...summarizeRecords(manifest, records), analysisImplementationSha256: sourceIdentity().implementationSha256 };
    writeNew(options.out, summary);
    console.log(JSON.stringify({ status: summary.completed === summary.requested ? "COMPLETE" : "INCOMPLETE",
      file: options.out, completed: summary.completed, requested: summary.requested,
      error: summary.error, skipped: summary.skipped, missing: summary.missing, nativeGateVerified: false }));
    if (summary.completed !== summary.requested) process.exitCode = 2;
  } else {
    console.log("Usage: node research/visual-influence/cli.mjs <prepare|collect|summarize> --name value ...\nSee research/visual-influence/README.md for exact commands and evidence limits.");
    if (command && !["help", "--help"].includes(command)) process.exitCode = 1;
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
