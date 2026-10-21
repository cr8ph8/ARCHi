export const ARC_SCORER_VERSION = "archi-arc-exact-v1" as const;

export const ARC_NO_WRITE_AUTHORITY = Object.freeze({
  canonWritable: false,
  journeyWritable: false,
  memoryWritable: false,
  permissionGrant: false,
  actionWritable: false,
  xpDelta: 0,
} as const);

export type ArcColor = 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9;
export type ArcGrid = readonly (readonly ArcColor[])[];

export interface ArcExample {
  readonly input: ArcGrid;
  readonly output?: ArcGrid;
}

export interface ArcTask {
  readonly taskId: string;
  readonly train: readonly (ArcExample & { readonly output: ArcGrid })[];
  readonly test: readonly ArcExample[];
}

export type ArcManifestMode = "fixture" | "offline-dataset";
export type ArcSourceStatus = "synthetic-fixture" | "unverified-offline-snapshot";

export interface ArcManifestTask {
  readonly taskId: string;
  readonly taskHash: string;
  readonly testExamples: number;
}

export interface ArcEvaluationManifest {
  readonly schemaVersion: 1;
  readonly manifestId: string;
  readonly mode: ArcManifestMode;
  readonly integration: "none";
  readonly scorerVersion: typeof ARC_SCORER_VERSION;
  readonly source: Readonly<{
    label: string;
    status: ArcSourceStatus;
    snapshot: string;
    contentHash: string;
  }>;
  readonly split: string;
  readonly tasks: readonly ArcManifestTask[];
}

export interface ArcSolverIdentity {
  readonly id: string;
  readonly version: string;
  readonly codeHash: string;
  readonly configurationHash: string;
}

export type ValidationResult<T> =
  | Readonly<{ ok: true; value: T }>
  | Readonly<{ ok: false; issues: readonly string[] }>;

const IDENTIFIER_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$/;
const SHA256_PATTERN = /^sha256:[0-9a-f]{64}$/;
const MAX_GRID_EDGE = 30;
const MAX_EXAMPLES_PER_SECTION = 20;
const MAX_MANIFEST_TASKS = 10_000;

type DataRecord = Record<string, unknown>;

function isDataRecord(value: unknown): value is DataRecord {
  try {
    if (typeof value !== "object" || value === null || Array.isArray(value)) return false;
    const prototype = Object.getPrototypeOf(value);
    if (prototype !== Object.prototype && prototype !== null) return false;
    const descriptors = Object.getOwnPropertyDescriptors(value);
    return Reflect.ownKeys(descriptors).every((key) => {
      if (typeof key !== "string") return false;
      const descriptor = descriptors[key];
      return !!descriptor && "value" in descriptor && descriptor.enumerable === true;
    });
  } catch {
    return false;
  }
}

function isDataArray(value: unknown): value is unknown[] {
  try {
    if (!Array.isArray(value) || Object.getPrototypeOf(value) !== Array.prototype) return false;
    const descriptors = Object.getOwnPropertyDescriptors(value);
    if (!Reflect.ownKeys(descriptors).every((key) => {
      if (typeof key !== "string") return false;
      const descriptor = descriptors[key];
      if (!descriptor || !("value" in descriptor)) return false;
      return key === "length" || (descriptor.enumerable === true
        && /^(?:0|[1-9][0-9]*)$/.test(key) && Number(key) < value.length);
    })) {
      return false;
    }
    return Array.from({ length: value.length }, (_, index) => index).every((index) =>
      Object.hasOwn(value, String(index)),
    );
  } catch {
    return false;
  }
}

function hasExactKeys(record: DataRecord, keys: readonly string[]): boolean {
  const actual = Reflect.ownKeys(record);
  return actual.length === keys.length && actual.every((key) => typeof key === "string" && keys.includes(key));
}

function isIdentifier(value: unknown): value is string {
  return typeof value === "string" && IDENTIFIER_PATTERN.test(value);
}

function isBoundedText(value: unknown, maximum = 160): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= maximum;
}

export function isSha256Digest(value: unknown): value is string {
  return typeof value === "string" && SHA256_PATTERN.test(value);
}

function fail<T>(issues: string[]): ValidationResult<T> {
  return Object.freeze({ ok: false, issues: Object.freeze([...issues]) });
}

function succeed<T>(value: T): ValidationResult<T> {
  return Object.freeze({ ok: true, value });
}

function cloneGrid(value: unknown, path: string, issues: string[]): ArcGrid | null {
  if (!isDataArray(value)) {
    issues.push(`${path} must be a data-only array`);
    return null;
  }
  if (value.length < 1 || value.length > MAX_GRID_EDGE) {
    issues.push(`${path} must contain 1-${MAX_GRID_EDGE} rows`);
    return null;
  }

  let width: number | null = null;
  const rows: ArcColor[][] = [];
  for (let rowIndex = 0; rowIndex < value.length; rowIndex += 1) {
    const row = value[rowIndex];
    if (!isDataArray(row)) {
      issues.push(`${path}[${rowIndex}] must be a data-only array`);
      continue;
    }
    if (row.length < 1 || row.length > MAX_GRID_EDGE) {
      issues.push(`${path}[${rowIndex}] must contain 1-${MAX_GRID_EDGE} cells`);
      continue;
    }
    if (width === null) width = row.length;
    if (row.length !== width) {
      issues.push(`${path} must be rectangular`);
      continue;
    }

    const clonedRow: ArcColor[] = [];
    for (let columnIndex = 0; columnIndex < row.length; columnIndex += 1) {
      const cell = row[columnIndex];
      if (!Number.isInteger(cell) || typeof cell !== "number" || cell < 0 || cell > 9) {
        issues.push(`${path}[${rowIndex}][${columnIndex}] must be an integer from 0 through 9`);
        continue;
      }
      clonedRow.push(cell as ArcColor);
    }
    if (clonedRow.length === row.length) rows.push(Object.freeze(clonedRow) as ArcColor[]);
  }

  if (issues.length > 0 || rows.length !== value.length) return null;
  return Object.freeze(rows);
}

export function validateArcGrid(value: unknown): ValidationResult<ArcGrid> {
  try {
    const issues: string[] = [];
    const grid = cloneGrid(value, "grid", issues);
    return grid ? succeed(grid) : fail(issues);
  } catch {
    return fail(["grid could not be safely reflected"]);
  }
}

function cloneExample(
  value: unknown,
  path: string,
  outputRequired: boolean,
  issues: string[],
): ArcExample | null {
  if (!isDataRecord(value)) {
    issues.push(`${path} must be a data-only object`);
    return null;
  }
  const expectedKeys = outputRequired || Object.hasOwn(value, "output") ? ["input", "output"] : ["input"];
  if (!hasExactKeys(value, expectedKeys)) {
    issues.push(`${path} has unexpected or missing fields`);
    return null;
  }

  const input = cloneGrid(value.input, `${path}.input`, issues);
  const output = Object.hasOwn(value, "output")
    ? cloneGrid(value.output, `${path}.output`, issues)
    : undefined;
  if (!input || (outputRequired && !output) || (Object.hasOwn(value, "output") && !output)) return null;
  return Object.freeze(output ? { input, output } : { input });
}

function validateArcTaskUnsafe(value: unknown): ValidationResult<ArcTask> {
  const issues: string[] = [];
  if (!isDataRecord(value)) return fail(["task must be a data-only object"]);
  if (!hasExactKeys(value, ["taskId", "train", "test"])) {
    return fail(["task has unexpected or missing fields"]);
  }
  if (!isIdentifier(value.taskId)) issues.push("task.taskId is not a bounded identifier");
  if (!isDataArray(value.train)) issues.push("task.train must be a data-only array");
  if (!isDataArray(value.test)) issues.push("task.test must be a data-only array");
  if (issues.length > 0) return fail(issues);

  const trainValues = value.train as unknown[];
  const testValues = value.test as unknown[];
  if (trainValues.length < 1 || trainValues.length > MAX_EXAMPLES_PER_SECTION) {
    issues.push(`task.train must contain 1-${MAX_EXAMPLES_PER_SECTION} examples`);
  }
  if (testValues.length < 1 || testValues.length > MAX_EXAMPLES_PER_SECTION) {
    issues.push(`task.test must contain 1-${MAX_EXAMPLES_PER_SECTION} examples`);
  }
  if (issues.length > 0) return fail(issues);

  const train = trainValues
    .map((example, index) => cloneExample(example, `task.train[${index}]`, true, issues))
    .filter((example): example is ArcExample & { readonly output: ArcGrid } => example?.output !== undefined);
  const test = testValues
    .map((example, index) => cloneExample(example, `task.test[${index}]`, false, issues))
    .filter((example): example is ArcExample => example !== null);
  if (issues.length > 0 || train.length !== trainValues.length || test.length !== testValues.length) {
    return fail(issues.length > 0 ? issues : ["task examples could not be admitted"]);
  }

  return succeed(
    Object.freeze({
      taskId: value.taskId as string,
      train: Object.freeze(train),
      test: Object.freeze(test),
    }),
  );
}

export function validateArcTask(value: unknown): ValidationResult<ArcTask> {
  try {
    return validateArcTaskUnsafe(value);
  } catch {
    return fail(["task could not be safely reflected"]);
  }
}

function validateArcManifestUnsafe(value: unknown): ValidationResult<ArcEvaluationManifest> {
  const issues: string[] = [];
  if (!isDataRecord(value)) return fail(["manifest must be a data-only object"]);
  if (
    !hasExactKeys(value, [
      "schemaVersion",
      "manifestId",
      "mode",
      "integration",
      "scorerVersion",
      "source",
      "split",
      "tasks",
    ])
  ) {
    return fail(["manifest has unexpected or missing fields"]);
  }

  if (value.schemaVersion !== 1) issues.push("manifest.schemaVersion must be 1");
  if (!isIdentifier(value.manifestId)) issues.push("manifest.manifestId is not a bounded identifier");
  if (value.mode !== "fixture" && value.mode !== "offline-dataset") {
    issues.push("manifest.mode must be fixture or offline-dataset");
  }
  if (value.integration !== "none") issues.push("manifest.integration must be none");
  if (value.scorerVersion !== ARC_SCORER_VERSION) {
    issues.push(`manifest.scorerVersion must be ${ARC_SCORER_VERSION}`);
  }
  if (!isIdentifier(value.split)) issues.push("manifest.split is not a bounded identifier");

  let source: ArcEvaluationManifest["source"] | null = null;
  if (!isDataRecord(value.source) || !hasExactKeys(value.source, ["label", "status", "snapshot", "contentHash"])) {
    issues.push("manifest.source has unexpected or missing fields");
  } else {
    if (!isBoundedText(value.source.label)) issues.push("manifest.source.label is invalid");
    if (value.source.status !== "synthetic-fixture" && value.source.status !== "unverified-offline-snapshot") {
      issues.push("manifest.source.status is invalid");
    }
    if (!isIdentifier(value.source.snapshot)) issues.push("manifest.source.snapshot is not a bounded identifier");
    if (!isSha256Digest(value.source.contentHash)) issues.push("manifest.source.contentHash must be a SHA-256 digest");
    if (value.mode === "fixture" && value.source.status !== "synthetic-fixture") {
      issues.push("fixture manifests must identify a synthetic-fixture source");
    }
    if (value.mode === "offline-dataset" && value.source.status !== "unverified-offline-snapshot") {
      issues.push("offline-dataset manifests must remain unverified-offline-snapshot sources");
    }
    if (issues.length === 0) {
      source = Object.freeze({
        label: value.source.label as string,
        status: value.source.status as ArcSourceStatus,
        snapshot: value.source.snapshot as string,
        contentHash: value.source.contentHash as string,
      });
    }
  }

  const tasks: ArcManifestTask[] = [];
  if (!isDataArray(value.tasks)) {
    issues.push("manifest.tasks must be a data-only array");
  } else if (value.tasks.length > MAX_MANIFEST_TASKS) {
    issues.push(`manifest.tasks cannot exceed ${MAX_MANIFEST_TASKS} entries`);
  } else {
    const identifiers = new Set<string>();
    for (let index = 0; index < value.tasks.length; index += 1) {
      const task = value.tasks[index];
      if (!isDataRecord(task) || !hasExactKeys(task, ["taskId", "taskHash", "testExamples"])) {
        issues.push(`manifest.tasks[${index}] has unexpected or missing fields`);
        continue;
      }
      if (!isIdentifier(task.taskId)) {
        issues.push(`manifest.tasks[${index}].taskId is not a bounded identifier`);
        continue;
      }
      if (identifiers.has(task.taskId)) {
        issues.push(`manifest contains duplicate taskId ${task.taskId}`);
        continue;
      }
      if (!isSha256Digest(task.taskHash)) {
        issues.push(`manifest.tasks[${index}].taskHash must be a SHA-256 digest`);
        continue;
      }
      if (
        typeof task.testExamples !== "number" ||
        !Number.isInteger(task.testExamples) ||
        task.testExamples < 1 ||
        task.testExamples > MAX_EXAMPLES_PER_SECTION
      ) {
        issues.push(`manifest.tasks[${index}].testExamples must be 1-${MAX_EXAMPLES_PER_SECTION}`);
        continue;
      }
      identifiers.add(task.taskId);
      tasks.push(
        Object.freeze({ taskId: task.taskId, taskHash: task.taskHash, testExamples: task.testExamples }),
      );
    }
  }

  if (issues.length > 0 || !source) return fail(issues);
  return succeed(
    Object.freeze({
      schemaVersion: 1,
      manifestId: value.manifestId as string,
      mode: value.mode as ArcManifestMode,
      integration: "none",
      scorerVersion: ARC_SCORER_VERSION,
      source,
      split: value.split as string,
      tasks: Object.freeze(tasks),
    }),
  );
}

export function validateArcManifest(value: unknown): ValidationResult<ArcEvaluationManifest> {
  try {
    return validateArcManifestUnsafe(value);
  } catch {
    return fail(["manifest could not be safely reflected"]);
  }
}

function validateArcSolverUnsafe(value: unknown): ValidationResult<ArcSolverIdentity> {
  const issues: string[] = [];
  if (!isDataRecord(value)) return fail(["solver must be a data-only object"]);
  if (!hasExactKeys(value, ["id", "version", "codeHash", "configurationHash"])) {
    return fail(["solver has unexpected or missing fields"]);
  }
  if (!isIdentifier(value.id)) issues.push("solver.id is not a bounded identifier");
  if (!isIdentifier(value.version)) issues.push("solver.version is not a bounded identifier");
  if (!isSha256Digest(value.codeHash)) issues.push("solver.codeHash must be a SHA-256 digest");
  if (!isSha256Digest(value.configurationHash)) {
    issues.push("solver.configurationHash must be a SHA-256 digest");
  }
  if (issues.length > 0) return fail(issues);
  return succeed(
    Object.freeze({
      id: value.id as string,
      version: value.version as string,
      codeHash: value.codeHash as string,
      configurationHash: value.configurationHash as string,
    }),
  );
}

export function validateArcSolver(value: unknown): ValidationResult<ArcSolverIdentity> {
  try {
    return validateArcSolverUnsafe(value);
  } catch {
    return fail(["solver could not be safely reflected"]);
  }
}

function utf8Bytes(text: string): number[] {
  const bytes: number[] = [];
  for (let index = 0; index < text.length; index += 1) {
    let codePoint = text.codePointAt(index) ?? 0xfffd;
    if (codePoint > 0xffff) index += 1;
    if (codePoint >= 0xd800 && codePoint <= 0xdfff) codePoint = 0xfffd;
    if (codePoint <= 0x7f) {
      bytes.push(codePoint);
    } else if (codePoint <= 0x7ff) {
      bytes.push(0xc0 | (codePoint >>> 6), 0x80 | (codePoint & 0x3f));
    } else if (codePoint <= 0xffff) {
      bytes.push(0xe0 | (codePoint >>> 12), 0x80 | ((codePoint >>> 6) & 0x3f), 0x80 | (codePoint & 0x3f));
    } else {
      bytes.push(
        0xf0 | (codePoint >>> 18),
        0x80 | ((codePoint >>> 12) & 0x3f),
        0x80 | ((codePoint >>> 6) & 0x3f),
        0x80 | (codePoint & 0x3f),
      );
    }
  }
  return bytes;
}

const SHA256_CONSTANTS = Object.freeze([
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
  0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
  0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
  0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
  0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
  0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
  0xc67178f2,
]);

function rotateRight(value: number, amount: number): number {
  return (value >>> amount) | (value << (32 - amount));
}

export function sha256Text(text: string): string {
  const bytes = utf8Bytes(text);
  const bitLength = bytes.length * 8;
  bytes.push(0x80);
  while (bytes.length % 64 !== 56) bytes.push(0);
  const high = Math.floor(bitLength / 0x1_0000_0000);
  const low = bitLength >>> 0;
  for (let shift = 24; shift >= 0; shift -= 8) bytes.push((high >>> shift) & 0xff);
  for (let shift = 24; shift >= 0; shift -= 8) bytes.push((low >>> shift) & 0xff);

  const state = new Uint32Array([
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ]);
  const words = new Uint32Array(64);

  for (let offset = 0; offset < bytes.length; offset += 64) {
    for (let index = 0; index < 16; index += 1) {
      const start = offset + index * 4;
      words[index] =
        ((bytes[start] ?? 0) << 24) |
        ((bytes[start + 1] ?? 0) << 16) |
        ((bytes[start + 2] ?? 0) << 8) |
        (bytes[start + 3] ?? 0);
    }
    for (let index = 16; index < 64; index += 1) {
      const x = words[index - 15] ?? 0;
      const y = words[index - 2] ?? 0;
      const sigma0 = rotateRight(x, 7) ^ rotateRight(x, 18) ^ (x >>> 3);
      const sigma1 = rotateRight(y, 17) ^ rotateRight(y, 19) ^ (y >>> 10);
      words[index] = ((words[index - 16] ?? 0) + sigma0 + (words[index - 7] ?? 0) + sigma1) >>> 0;
    }

    let a = state[0] ?? 0;
    let b = state[1] ?? 0;
    let c = state[2] ?? 0;
    let d = state[3] ?? 0;
    let e = state[4] ?? 0;
    let f = state[5] ?? 0;
    let g = state[6] ?? 0;
    let h = state[7] ?? 0;

    for (let index = 0; index < 64; index += 1) {
      const sum1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25);
      const choice = (e & f) ^ (~e & g);
      const temporary1 = (h + sum1 + choice + (SHA256_CONSTANTS[index] ?? 0) + (words[index] ?? 0)) >>> 0;
      const sum0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22);
      const majority = (a & b) ^ (a & c) ^ (b & c);
      const temporary2 = (sum0 + majority) >>> 0;
      h = g;
      g = f;
      f = e;
      e = (d + temporary1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (temporary1 + temporary2) >>> 0;
    }

    state[0] = ((state[0] ?? 0) + a) >>> 0;
    state[1] = ((state[1] ?? 0) + b) >>> 0;
    state[2] = ((state[2] ?? 0) + c) >>> 0;
    state[3] = ((state[3] ?? 0) + d) >>> 0;
    state[4] = ((state[4] ?? 0) + e) >>> 0;
    state[5] = ((state[5] ?? 0) + f) >>> 0;
    state[6] = ((state[6] ?? 0) + g) >>> 0;
    state[7] = ((state[7] ?? 0) + h) >>> 0;
  }

  return `sha256:${Array.from(state, (word) => word.toString(16).padStart(8, "0")).join("")}`;
}

function canonicalizeValue(value: unknown, ancestors: WeakSet<object>): string {
  if (value === null) return "null";
  if (typeof value === "string" || typeof value === "boolean") return JSON.stringify(value);
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new TypeError("Canonical JSON cannot contain non-finite numbers");
    return Object.is(value, -0) ? "0" : JSON.stringify(value);
  }
  if (typeof value !== "object") throw new TypeError(`Canonical JSON cannot contain ${typeof value}`);
  if (ancestors.has(value)) throw new TypeError("Canonical JSON cannot contain cycles");
  ancestors.add(value);
  try {
    if (Array.isArray(value)) {
      if (!isDataArray(value)) throw new TypeError("Canonical JSON arrays cannot contain accessors");
      return `[${value.map((entry) => canonicalizeValue(entry, ancestors)).join(",")}]`;
    }
    if (!isDataRecord(value)) throw new TypeError("Canonical JSON requires data-only plain objects");
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalizeValue(value[key], ancestors)}`)
      .join(",")}}`;
  } finally {
    ancestors.delete(value);
  }
}

export function canonicalJson(value: unknown): string {
  return canonicalizeValue(value, new WeakSet<object>());
}

export function digestCanonical(value: unknown): string {
  return sha256Text(canonicalJson(value));
}
