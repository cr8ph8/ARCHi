import {
  ARC_NO_WRITE_AUTHORITY,
  ARC_SCORER_VERSION,
  digestCanonical,
  isSha256Digest,
  validateArcGrid,
  validateArcManifest,
  validateArcSolver,
  validateArcTask,
  type ArcEvaluationManifest,
  type ArcGrid,
  type ArcManifestTask,
  type ArcManifestMode,
  type ArcSolverIdentity,
  type ArcSourceStatus,
  type ArcTask,
} from "./contract";

export type ArcReceiptResult = "exact" | "incorrect" | "missing" | "invalid" | "unscored";
export type ArcReceiptReason = "missing-prediction" | "invalid-prediction" | null;

export interface ArcEvidenceReceipt {
  readonly schemaVersion: 1;
  readonly scorerVersion: typeof ARC_SCORER_VERSION;
  readonly mode: ArcManifestMode;
  readonly integration: "none";
  readonly manifestHash: string;
  readonly datasetHash: string;
  readonly split: string;
  readonly taskId: string;
  readonly taskHash: string;
  readonly testIndex: number;
  readonly taskInputHash: string;
  readonly solver: ArcSolverIdentity;
  readonly predictionHash: string | null;
  readonly expectedOutputHash: string | null;
  readonly result: ArcReceiptResult;
  readonly exact: boolean | null;
  readonly reason: ArcReceiptReason;
  readonly attestation: "unattested";
  readonly reproducible: false;
  readonly authority: typeof ARC_NO_WRITE_AUTHORITY;
  readonly receiptHash: string;
}

export interface ArcEvidenceCounts {
  readonly exact: number;
  readonly incorrect: number;
  readonly missing: number;
  readonly invalid: number;
  readonly unscored: number;
  readonly totalExamples: number;
  readonly exactTasks: number;
  readonly totalTasks: number;
}

export interface ArcCapabilityProposal {
  readonly schemaVersion: 1;
  readonly status: "proposed";
  readonly capability: "abstract-reasoning-evidence";
  readonly certification: "not-certified";
  readonly integration: "none";
  readonly scorerVersion: typeof ARC_SCORER_VERSION;
  readonly manifestHash: string;
  readonly datasetHash: string;
  readonly sourceStatus: ArcSourceStatus;
  readonly split: string;
  readonly solver: ArcSolverIdentity;
  readonly counts: ArcEvidenceCounts;
  readonly exactRate: number | null;
  readonly taskExactRate: number | null;
  readonly receiptCoverageComplete: boolean;
  readonly scoredCoverageComplete: boolean;
  readonly receiptHashes: readonly string[];
  readonly authority: typeof ARC_NO_WRITE_AUTHORITY;
  readonly proposalHash: string;
}

const IDENTIFIER_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$/;
const RECEIPT_KEYS = Object.freeze([
  "schemaVersion",
  "scorerVersion",
  "mode",
  "integration",
  "manifestHash",
  "datasetHash",
  "split",
  "taskId",
  "taskHash",
  "testIndex",
  "taskInputHash",
  "solver",
  "predictionHash",
  "expectedOutputHash",
  "result",
  "exact",
  "reason",
  "attestation",
  "reproducible",
  "authority",
  "receiptHash",
]);

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

function admitted<T>(result: ReturnType<typeof validateArcManifest> | { ok: true; value: T } | { ok: false; issues: readonly string[] }, label: string): T {
  if (!result.ok) throw new TypeError(`${label}: ${result.issues.join("; ")}`);
  return result.value as T;
}

function cloneAuthority(value: unknown): typeof ARC_NO_WRITE_AUTHORITY | null {
  if (!isDataRecord(value)) return null;
  if (!hasExactKeys(value, ["canonWritable", "journeyWritable", "memoryWritable", "permissionGrant", "actionWritable", "xpDelta"])) {
    return null;
  }
  return value.canonWritable === false &&
    value.journeyWritable === false &&
    value.memoryWritable === false &&
    value.permissionGrant === false &&
    value.actionWritable === false &&
    value.xpDelta === 0
    ? ARC_NO_WRITE_AUTHORITY
    : null;
}

export function gridsExactlyEqual(expected: unknown, prediction: unknown): boolean {
  const expectedGrid = validateArcGrid(expected);
  const predictedGrid = validateArcGrid(prediction);
  if (!expectedGrid.ok || !predictedGrid.ok) return false;
  if (expectedGrid.value.length !== predictedGrid.value.length) return false;
  return expectedGrid.value.every(
    (row, rowIndex) =>
      row.length === predictedGrid.value[rowIndex]?.length &&
      row.every((cell, columnIndex) => cell === predictedGrid.value[rowIndex]?.[columnIndex]),
  );
}

function freezeReceipt(payload: Omit<ArcEvidenceReceipt, "receiptHash">): ArcEvidenceReceipt {
  const receiptHash = digestCanonical(payload);
  return Object.freeze({ ...payload, receiptHash });
}

function evaluateAdmittedArcTask(
  manifest: ArcEvaluationManifest,
  manifestHash: string,
  manifestTask: ArcManifestTask,
  task: ArcTask,
  predictionsValue: unknown,
  solver: ArcSolverIdentity,
): readonly ArcEvidenceReceipt[] {
  if (!isDataArray(predictionsValue)) throw new TypeError("Predictions must be a data-only array");
  const taskHash = digestCanonical(task);
  if (manifestTask.taskHash !== taskHash) {
    throw new TypeError(`Task ${task.taskId} content does not match the frozen manifest`);
  }
  if (manifestTask.testExamples !== task.test.length) {
    throw new RangeError(`Task ${task.taskId} test count does not match the frozen manifest`);
  }
  if (predictionsValue.length > manifestTask.testExamples) {
    throw new RangeError(`Task ${task.taskId} has more predictions than manifest examples`);
  }

  const receipts: ArcEvidenceReceipt[] = [];
  for (let testIndex = 0; testIndex < manifestTask.testExamples; testIndex += 1) {
    const example = task.test[testIndex];
    if (!example) throw new RangeError(`Task ${task.taskId} is missing test example ${testIndex}`);
    const taskInputHash = digestCanonical({ taskId: task.taskId, testIndex, input: example.input });
    const expectedOutputHash = example.output ? digestCanonical(example.output) : null;
    const hasPrediction = Object.hasOwn(predictionsValue, String(testIndex)) && predictionsValue[testIndex] !== undefined;

    let predictionHash: string | null = null;
    let result: ArcReceiptResult = "missing";
    let exact: boolean | null = null;
    let reason: ArcReceiptReason = "missing-prediction";

    if (hasPrediction) {
      const prediction = validateArcGrid(predictionsValue[testIndex]);
      if (!prediction.ok) {
        result = "invalid";
        reason = "invalid-prediction";
      } else {
        predictionHash = digestCanonical(prediction.value);
        reason = null;
        if (!example.output) {
          result = "unscored";
        } else {
          exact = gridsExactlyEqual(example.output, prediction.value);
          result = exact ? "exact" : "incorrect";
        }
      }
    }

    receipts.push(
      freezeReceipt({
        schemaVersion: 1,
        scorerVersion: ARC_SCORER_VERSION,
        mode: manifest.mode,
        integration: "none",
        manifestHash,
        datasetHash: manifest.source.contentHash,
        split: manifest.split,
        taskId: task.taskId,
        taskHash,
        testIndex,
        taskInputHash,
        solver,
        predictionHash,
        expectedOutputHash,
        result,
        exact,
        reason,
        attestation: "unattested",
        reproducible: false,
        authority: ARC_NO_WRITE_AUTHORITY,
      }),
    );
  }
  return Object.freeze(receipts);
}

export function evaluateArcTask(input: Readonly<{
  manifest: unknown;
  task: unknown;
  predictions: unknown;
  solver: unknown;
}>): readonly ArcEvidenceReceipt[] {
  if (!isDataRecord(input) || !hasExactKeys(input, ["manifest", "task", "predictions", "solver"])) {
    throw new TypeError("Evaluation request has unexpected or missing fields");
  }
  const manifest = admitted<ArcEvaluationManifest>(validateArcManifest(input.manifest), "Invalid ARC manifest");
  const task = admitted<ArcTask>(validateArcTask(input.task), "Invalid ARC task");
  const solver = admitted<ArcSolverIdentity>(validateArcSolver(input.solver), "Invalid solver identity");
  const manifestTask = manifest.tasks.find((entry) => entry.taskId === task.taskId);
  if (!manifestTask) throw new RangeError(`Task ${task.taskId} is outside the frozen manifest`);
  return evaluateAdmittedArcTask(manifest, digestCanonical(manifest), manifestTask, task, input.predictions, solver);
}

export function verifyArcReceiptEnvelope(value: unknown): ArcEvidenceReceipt {
  if (!isDataRecord(value) || !hasExactKeys(value, RECEIPT_KEYS)) {
    throw new TypeError("Receipt has unexpected or missing fields");
  }
  if (value.schemaVersion !== 1) throw new TypeError("Receipt schemaVersion must be 1");
  if (value.scorerVersion !== ARC_SCORER_VERSION) throw new TypeError("Receipt scorerVersion is unsupported");
  if (value.mode !== "fixture" && value.mode !== "offline-dataset") throw new TypeError("Receipt mode is invalid");
  if (value.integration !== "none") throw new TypeError("Receipt integration must be none");
  for (const [field, fieldValue] of [
    ["manifestHash", value.manifestHash],
    ["datasetHash", value.datasetHash],
    ["taskHash", value.taskHash],
    ["taskInputHash", value.taskInputHash],
    ["receiptHash", value.receiptHash],
  ] as const) {
    if (!isSha256Digest(fieldValue)) throw new TypeError(`Receipt ${field} must be a SHA-256 digest`);
  }
  if (typeof value.split !== "string" || !IDENTIFIER_PATTERN.test(value.split)) {
    throw new TypeError("Receipt split is invalid");
  }
  if (typeof value.taskId !== "string" || !IDENTIFIER_PATTERN.test(value.taskId)) {
    throw new TypeError("Receipt taskId is invalid");
  }
  if (typeof value.testIndex !== "number" || !Number.isInteger(value.testIndex) || value.testIndex < 0 || value.testIndex > 19) {
    throw new TypeError("Receipt testIndex is invalid");
  }
  const solver = admitted<ArcSolverIdentity>(validateArcSolver(value.solver), "Invalid receipt solver");
  if (value.predictionHash !== null && !isSha256Digest(value.predictionHash)) {
    throw new TypeError("Receipt predictionHash is invalid");
  }
  if (value.expectedOutputHash !== null && !isSha256Digest(value.expectedOutputHash)) {
    throw new TypeError("Receipt expectedOutputHash is invalid");
  }
  if (!["exact", "incorrect", "missing", "invalid", "unscored"].includes(String(value.result))) {
    throw new TypeError("Receipt result is invalid");
  }
  if (value.exact !== null && typeof value.exact !== "boolean") throw new TypeError("Receipt exact value is invalid");
  if (value.reason !== null && value.reason !== "missing-prediction" && value.reason !== "invalid-prediction") {
    throw new TypeError("Receipt reason is invalid");
  }
  if (value.attestation !== "unattested" || value.reproducible !== false) {
    throw new TypeError("Receipt cannot claim attestation or reproducibility in this package");
  }
  const authority = cloneAuthority(value.authority);
  if (!authority) throw new TypeError("Receipt attempts to exceed evidence-only authority");

  const result = value.result as ArcReceiptResult;
  const predictionHash = value.predictionHash as string | null;
  const expectedOutputHash = value.expectedOutputHash as string | null;
  const exact = value.exact as boolean | null;
  const reason = value.reason as ArcReceiptReason;
  const coherent =
    (result === "exact" &&
      exact === true &&
      reason === null &&
      predictionHash !== null &&
      predictionHash === expectedOutputHash) ||
    (result === "incorrect" &&
      exact === false &&
      reason === null &&
      predictionHash !== null &&
      expectedOutputHash !== null &&
      predictionHash !== expectedOutputHash) ||
    (result === "unscored" && exact === null && reason === null && predictionHash !== null && expectedOutputHash === null) ||
    (result === "missing" && exact === null && reason === "missing-prediction" && predictionHash === null) ||
    (result === "invalid" && exact === null && reason === "invalid-prediction" && predictionHash === null);
  if (!coherent) throw new TypeError("Receipt result disagrees with its recomputable fields");

  const payload: Omit<ArcEvidenceReceipt, "receiptHash"> = Object.freeze({
    schemaVersion: 1,
    scorerVersion: ARC_SCORER_VERSION,
    mode: value.mode as ArcManifestMode,
    integration: "none",
    manifestHash: value.manifestHash as string,
    datasetHash: value.datasetHash as string,
    split: value.split as string,
    taskId: value.taskId as string,
    taskHash: value.taskHash as string,
    testIndex: value.testIndex,
    taskInputHash: value.taskInputHash as string,
    solver,
    predictionHash,
    expectedOutputHash,
    result,
    exact,
    reason,
    attestation: "unattested",
    reproducible: false,
    authority,
  });
  if (digestCanonical(payload) !== value.receiptHash) throw new TypeError("Receipt hash verification failed");
  return Object.freeze({ ...payload, receiptHash: value.receiptHash as string });
}

function freezeCounts(counts: ArcEvidenceCounts): ArcEvidenceCounts {
  return Object.freeze({ ...counts });
}

export function createArcCapabilityProposal(
  input: Readonly<{
    manifest: unknown;
    evaluations: unknown;
    solver: unknown;
  }>,
): ArcCapabilityProposal {
  if (!isDataRecord(input) || !hasExactKeys(input, ["manifest", "evaluations", "solver"])) {
    throw new TypeError("Proposal request has unexpected or missing fields");
  }
  const manifest = admitted<ArcEvaluationManifest>(validateArcManifest(input.manifest), "Invalid ARC manifest");
  const solver = admitted<ArcSolverIdentity>(validateArcSolver(input.solver), "Invalid solver identity");
  const manifestTaskById = new Map(manifest.tasks.map((task) => [task.taskId, task] as const));
  const manifestHash = digestCanonical(manifest);
  if (!isDataArray(input.evaluations)) throw new TypeError("Evaluations must be a data-only array");
  if (input.evaluations.length > manifest.tasks.length) {
    throw new RangeError("Evaluation input exceeds the frozen manifest task count");
  }

  const seenTasks = new Set<string>();
  const locallyEvaluatedReceipts: ArcEvidenceReceipt[] = [];
  for (let index = 0; index < input.evaluations.length; index += 1) {
    const evaluation = input.evaluations[index];
    if (!isDataRecord(evaluation) || !hasExactKeys(evaluation, ["task", "predictions"])) {
      throw new TypeError(`Evaluation ${index} has unexpected or missing fields`);
    }
    const task = admitted<ArcTask>(validateArcTask(evaluation.task), `Invalid task in evaluation ${index}`);
    if (seenTasks.has(task.taskId)) throw new TypeError(`Task ${task.taskId} is evaluated more than once`);
    const manifestTask = manifestTaskById.get(task.taskId);
    if (!manifestTask) throw new RangeError(`Task ${task.taskId} is outside the frozen manifest`);
    seenTasks.add(task.taskId);
    locallyEvaluatedReceipts.push(
      ...evaluateAdmittedArcTask(manifest, manifestHash, manifestTask, task, evaluation.predictions, solver),
    );
  }

  const expected = new Map<string, { taskId: string; testIndex: number }>();
  for (const task of manifest.tasks) {
    for (let testIndex = 0; testIndex < task.testExamples; testIndex += 1) {
      expected.set(`${task.taskId}:${testIndex}`, { taskId: task.taskId, testIndex });
    }
  }

  const uniqueByHash = new Map<string, ArcEvidenceReceipt>();
  const receiptByExample = new Map<string, ArcEvidenceReceipt>();
  for (const value of locallyEvaluatedReceipts) {
    const receipt = verifyArcReceiptEnvelope(value);
    if (uniqueByHash.has(receipt.receiptHash)) continue;
    if (
      receipt.manifestHash !== manifestHash ||
      receipt.datasetHash !== manifest.source.contentHash ||
      receipt.split !== manifest.split ||
      receipt.mode !== manifest.mode
    ) {
      throw new TypeError("Receipt belongs to a different manifest partition");
    }
    if (digestCanonical(receipt.solver) !== digestCanonical(solver)) {
      throw new TypeError("Receipt solver differs from the frozen run solver");
    }
    const key = `${receipt.taskId}:${receipt.testIndex}`;
    const manifestTask = manifestTaskById.get(receipt.taskId);
    if (!expected.has(key) || !manifestTask) throw new RangeError(`Receipt ${key} is outside the frozen manifest`);
    if (receipt.taskHash !== manifestTask.taskHash) throw new TypeError(`Receipt ${key} has the wrong task content hash`);
    if (receiptByExample.has(key)) throw new TypeError(`Conflicting receipts exist for ${key}`);
    uniqueByHash.set(receipt.receiptHash, receipt);
    receiptByExample.set(key, receipt);
  }

  const counts = {
    exact: 0,
    incorrect: 0,
    missing: 0,
    invalid: 0,
    unscored: 0,
    totalExamples: expected.size,
    exactTasks: 0,
    totalTasks: manifest.tasks.length,
  };
  for (const key of expected.keys()) {
    const receipt = receiptByExample.get(key);
    if (!receipt || receipt.result === "missing") counts.missing += 1;
    else if (receipt.result === "exact") counts.exact += 1;
    else if (receipt.result === "incorrect") counts.incorrect += 1;
    else if (receipt.result === "invalid") counts.invalid += 1;
    else counts.unscored += 1;
  }
  for (const task of manifest.tasks) {
    let taskExact = true;
    for (let testIndex = 0; testIndex < task.testExamples; testIndex += 1) {
      if (receiptByExample.get(`${task.taskId}:${testIndex}`)?.result !== "exact") taskExact = false;
    }
    if (taskExact) counts.exactTasks += 1;
  }

  const frozenCounts = freezeCounts(counts);
  const receiptHashes = Object.freeze([...uniqueByHash.keys()].sort());
  const payload: Omit<ArcCapabilityProposal, "proposalHash"> = Object.freeze({
    schemaVersion: 1,
    status: "proposed",
    capability: "abstract-reasoning-evidence",
    certification: "not-certified",
    integration: "none",
    scorerVersion: ARC_SCORER_VERSION,
    manifestHash,
    datasetHash: manifest.source.contentHash,
    sourceStatus: manifest.source.status,
    split: manifest.split,
    solver,
    counts: frozenCounts,
    exactRate: counts.totalExamples === 0 ? null : counts.exact / counts.totalExamples,
    taskExactRate: counts.totalTasks === 0 ? null : counts.exactTasks / counts.totalTasks,
    receiptCoverageComplete: receiptByExample.size === expected.size,
    scoredCoverageComplete: counts.exact + counts.incorrect === counts.totalExamples,
    receiptHashes,
    authority: ARC_NO_WRITE_AUTHORITY,
  });
  return Object.freeze({ ...payload, proposalHash: digestCanonical(payload) });
}

export function taskInputHash(task: ArcTask, testIndex: number): string {
  const example = task.test[testIndex];
  if (!example) throw new RangeError(`Task ${task.taskId} has no test example ${testIndex}`);
  return digestCanonical({ taskId: task.taskId, testIndex, input: example.input });
}

export function outputHash(grid: ArcGrid): string {
  const admittedGrid = validateArcGrid(grid);
  if (!admittedGrid.ok) throw new TypeError(`Invalid ARC grid: ${admittedGrid.issues.join("; ")}`);
  return digestCanonical(admittedGrid.value);
}
