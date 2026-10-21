import { createHash } from "node:crypto";
import { isProxy } from "node:util/types";
import { parseJsonWithoutDuplicateKeys } from "../../src/strict-json.ts";
import { parseSokoban, stepSokoban, isSolved, hasStaticDeadlock } from "./sokoban.ts";
import type { SokobanAction, SokobanState } from "./sokoban.ts";

export const IMAGINATION_VERSION = "archi-imagination-pilot/v1";
export const NO_WRITE_AUTHORITY = Object.freeze({
  actionWritable: false, memoryWritable: false, permissionGrant: false,
} as const);
export const MAX_RESPONSE_BYTES = 65_536;

export interface Observation {
  readonly revision: number;
  readonly authorizationEpoch: number;
  readonly state: SokobanState;
}
export interface CurrentContext {
  readonly observation: Observation;
  readonly policyVersion: string;
}
export interface ImaginationBudget {
  readonly maxCandidates: number;
  readonly maxHorizon: number;
  readonly maxTransitions: number;
}
export interface ImaginationRequest extends CurrentContext {
  readonly schema: "archi-imagination-request/v1";
  readonly requestId: string;
  readonly issuedAtMs: number;
  readonly expiresAtMs: number;
  readonly budget: ImaginationBudget;
  readonly requestDigest: string;
}
export interface ProviderIdentity {
  readonly kind: "synthetic-fixture" | "agima-bagel";
  readonly id: string;
  readonly revision: string;
}
export const FIXTURE_PROVIDER = Object.freeze({
  kind: "synthetic-fixture", id: "archi-hand-authored-fixtures", revision: "v1",
} as const);
export interface CandidateAssessment {
  readonly id: string;
  readonly actions: readonly SokobanAction[];
  readonly imaginedStates: readonly SokobanState[];
  readonly simulatedStates: readonly SokobanState[];
  readonly predictedSuccess: boolean;
  readonly simulatedSuccess: boolean;
  readonly predictionMismatches: number;
  readonly violation: string | null;
}
export interface ReviewResult {
  readonly schema: "archi-imagination-review/v1";
  readonly status: "reviewed" | "invalid" | "stale" | "unavailable" | "cancelled" | "timeout";
  readonly disposition: "PROPOSE" | "DAMP" | "REJECT" | "ESCALATE";
  readonly requestDigest: string | null;
  readonly provider: ProviderIdentity;
  readonly selectedCandidateId: string | null;
  readonly proposedActions: readonly SokobanAction[];
  readonly candidates: readonly CandidateAssessment[];
  readonly transitionsUsed: number;
  readonly issues: readonly string[];
  readonly authority: typeof NO_WRITE_AUTHORITY;
  readonly evidenceClass: "not-evaluated" | "deterministic-simulation";
}

type DataRecord = Record<string, unknown>;
const REQUEST_KEYS = ["requestId", "observation", "policyVersion", "issuedAtMs", "expiresAtMs", "budget"];
const ACTIONS = new Set(["UP", "DOWN", "LEFT", "RIGHT"]);

function requireValue(value: unknown, message: string): asserts value {
  if (!value) throw new TypeError(message);
}

/** Descriptor checks protect data boundaries; this is not an in-process JS sandbox. */
function record(value: unknown, keys: readonly string[], label: string): DataRecord {
  requireValue(!isProxy(value), `${label} must not be a Proxy`);
  requireValue(value !== null && typeof value === "object" && !Array.isArray(value), `${label} must be a record`);
  const prototype = Object.getPrototypeOf(value);
  requireValue(prototype === Object.prototype || prototype === null, `${label} must be a plain record`);
  const descriptors = Object.getOwnPropertyDescriptors(value);
  const actual = Reflect.ownKeys(value);
  requireValue(actual.length === keys.length && actual.every(key => typeof key === "string" && keys.includes(key)), `${label} has unexpected or missing fields`);
  requireValue(actual.every(key => "value" in descriptors[key as string]), `${label} must not contain accessors`);
  return value as DataRecord;
}

function array(value: unknown, maximum: number, label: string): unknown[] {
  requireValue(!isProxy(value), `${label} must not be a Proxy`);
  requireValue(Array.isArray(value) && Object.getPrototypeOf(value) === Array.prototype, `${label} must be a plain array`);
  const descriptors = Object.getOwnPropertyDescriptors(value);
  const length = Object.getOwnPropertyDescriptor(value, "length")?.value;
  requireValue(typeof length === "number" && Number.isSafeInteger(length) && length >= 0 && length <= maximum, `${label} exceeds its budget`);
  const keys = Reflect.ownKeys(value);
  requireValue(keys.length === length + 1 && keys.every(key => key === "length" ||
    typeof key === "string" && /^(0|[1-9][0-9]*)$/.test(key) && Number(key) < length && "value" in descriptors[key]), `${label} must be a dense data array`);
  return value;
}

function integer(value: unknown, maximum: number, label: string, minimum = 0): number {
  requireValue(typeof value === "number" && Number.isSafeInteger(value) && value >= minimum && value <= maximum, `${label} is out of range`);
  return value;
}

function identifier(value: unknown, label: string): string {
  requireValue(typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$/.test(value), `${label} is invalid`);
  return value;
}

function digest(value: unknown): string {
  // Only canonical objects constructed below reach this function.
  return `sha256:${createHash("sha256").update(JSON.stringify(value)).digest("hex")}`;
}

function observation(value: unknown): Observation {
  const input = record(value, ["revision", "authorizationEpoch", "state"], "observation");
  return Object.freeze({
    revision: integer(input.revision, Number.MAX_SAFE_INTEGER, "revision"),
    authorizationEpoch: integer(input.authorizationEpoch, Number.MAX_SAFE_INTEGER, "authorizationEpoch"),
    state: parseSokoban(input.state),
  });
}

function context(value: unknown): CurrentContext {
  const input = record(value, ["observation", "policyVersion"], "current context");
  return Object.freeze({ observation: observation(input.observation), policyVersion: identifier(input.policyVersion, "policyVersion") });
}

export function createImaginationRequest(value: unknown): ImaginationRequest {
  const input = record(value, REQUEST_KEYS, "request");
  const limits = record(input.budget, ["maxCandidates", "maxHorizon", "maxTransitions"], "budget");
  const issuedAtMs = integer(input.issuedAtMs, Number.MAX_SAFE_INTEGER, "issuedAtMs");
  const expiresAtMs = integer(input.expiresAtMs, Number.MAX_SAFE_INTEGER, "expiresAtMs");
  requireValue(expiresAtMs > issuedAtMs && expiresAtMs - issuedAtMs <= 300_000, "Request lifetime must be at most five minutes");
  const canonical = {
    schema: "archi-imagination-request/v1" as const,
    requestId: identifier(input.requestId, "requestId"),
    observation: observation(input.observation),
    policyVersion: identifier(input.policyVersion, "policyVersion"),
    issuedAtMs, expiresAtMs,
    budget: Object.freeze({
      maxCandidates: integer(limits.maxCandidates, 8, "maxCandidates", 1),
      maxHorizon: integer(limits.maxHorizon, 8, "maxHorizon", 1),
      maxTransitions: integer(limits.maxTransitions, 64, "maxTransitions", 1),
    }),
  };
  return Object.freeze({ ...canonical, requestDigest: digest(canonical) });
}

function parseRequest(value: unknown): ImaginationRequest {
  const input = record(value, ["schema", ...REQUEST_KEYS, "requestDigest"], "bound request");
  requireValue(input.schema === "archi-imagination-request/v1", "Unsupported request schema");
  const rebuilt = createImaginationRequest(Object.fromEntries(REQUEST_KEYS.map(key => [key, input[key]])));
  requireValue(input.requestDigest === rebuilt.requestDigest, "Request binding changed");
  return rebuilt;
}

function parseProvider(value: unknown): ProviderIdentity {
  const input = record(value, ["kind", "id", "revision"], "provider identity");
  requireValue(input.kind === "synthetic-fixture" || input.kind === "agima-bagel", "Unsupported provider kind");
  return Object.freeze({ kind: input.kind, id: identifier(input.id, "provider id"), revision: identifier(input.revision, "provider revision") });
}

function result(provider: ProviderIdentity, patch: Partial<ReviewResult>): ReviewResult {
  return Object.freeze({
    schema: "archi-imagination-review/v1", status: "invalid", disposition: "REJECT",
    requestDigest: null, selectedCandidateId: null, transitionsUsed: 0,
    proposedActions: Object.freeze([]), candidates: Object.freeze([]), issues: Object.freeze([]),
    evidenceClass: "not-evaluated", ...patch, provider, authority: NO_WRITE_AUTHORITY,
  });
}

function errorText(error: unknown): string {
  return error instanceof Error ? error.message : "Invalid imagination data";
}

function isCurrent(request: ImaginationRequest, current: CurrentContext, nowMs: number): boolean {
  integer(nowMs, Number.MAX_SAFE_INTEGER, "nowMs");
  return nowMs >= request.issuedAtMs && nowMs < request.expiresAtMs &&
    request.policyVersion === current.policyVersion &&
    digest(request.observation) === digest(current.observation);
}

/** Reviews hypotheses in a closed simulator. It never dispatches an action,
 * admits an outcome, writes memory, or authenticates caller-supplied context. */
export function evaluateImagination(
  requestValue: unknown, responseText: string, currentValue: unknown, nowMs: number,
  providerValue: ProviderIdentity = FIXTURE_PROVIDER,
): ReviewResult {
  let provider: ProviderIdentity = FIXTURE_PROVIDER;
  let request: ImaginationRequest | undefined;
  try {
    provider = parseProvider(providerValue);
    request = parseRequest(requestValue);
    const current = context(currentValue);
    if (!isCurrent(request, current, nowMs)) return result(provider, {
      status: "stale", requestDigest: request.requestDigest,
      issues: Object.freeze(["Observation, revision, authorization epoch, policy or request lifetime changed; request a new proposal"]),
    });
    requireValue(typeof responseText === "string" && Buffer.byteLength(responseText, "utf8") <= MAX_RESPONSE_BYTES, "Provider response exceeds byte budget");
    const response = record(parseJsonWithoutDuplicateKeys(responseText, "Imagination response"), ["schema", "requestDigest", "candidates"], "response");
    requireValue(response.schema === "archi-imagination-candidates/v1", "Unsupported candidate schema");
    requireValue(response.requestDigest === request.requestDigest, "Provider response belongs to a different request");
    const rawCandidates = array(response.candidates, request.budget.maxCandidates, "candidates");
    requireValue(rawCandidates.length > 0, "At least one candidate is required");
    const ids = new Set<string>();
    let totalTransitions = 0;
    const candidates = rawCandidates.map((raw) => {
      const candidate = record(raw, ["id", "actions", "predictedStates", "predictedSuccess"], "candidate");
      const id = identifier(candidate.id, "candidate id");
      requireValue(!ids.has(id), "Candidate IDs must be unique");
      ids.add(id);
      const actions = array(candidate.actions, request!.budget.maxHorizon, "actions").map(action => {
        requireValue(typeof action === "string" && ACTIONS.has(action), "Unknown Sokoban action");
        return action as SokobanAction;
      });
      requireValue(actions.length > 0, "Candidate must propose at least one action");
      const predictedStates = array(candidate.predictedStates, request!.budget.maxHorizon, "predictedStates").map(parseSokoban);
      requireValue(predictedStates.length === actions.length, "Each action requires exactly one imagined state");
      requireValue(typeof candidate.predictedSuccess === "boolean", "predictedSuccess must be a boolean");
      totalTransitions += actions.length;
      return { id, actions: Object.freeze(actions), predictedStates: Object.freeze(predictedStates), predictedSuccess: candidate.predictedSuccess };
    });
    requireValue(totalTransitions <= request.budget.maxTransitions, "Aggregate transition budget exceeded");

    let transitionsUsed = 0;
    const assessments: CandidateAssessment[] = candidates.map(candidate => {
      let state = request!.observation.state;
      let violation: string | null = hasStaticDeadlock(state) ? "Initial board contains a non-goal wall-corner box" : null;
      const simulatedStates: SokobanState[] = [];
      let predictionMismatches = 0;
      for (let index = 0; index < candidate.actions.length && violation === null; index += 1) {
        const step = stepSokoban(state, candidate.actions[index]);
        transitionsUsed += 1;
        state = step.state;
        simulatedStates.push(state);
        if (digest(state) !== digest(candidate.predictedStates[index])) predictionMismatches += 1;
        if (!step.legal) violation = `Illegal action at step ${index + 1}: ${step.reason ?? "blocked"}`;
        else if (step.deadlocked) violation = `Non-goal wall-corner deadlock at step ${index + 1}`;
      }
      const simulatedSuccess = violation === null && isSolved(state);
      if (simulatedSuccess !== candidate.predictedSuccess) predictionMismatches += 1;
      return Object.freeze({ id: candidate.id, actions: candidate.actions,
        imaginedStates: candidate.predictedStates, simulatedStates: Object.freeze(simulatedStates),
        predictedSuccess: candidate.predictedSuccess, simulatedSuccess, predictionMismatches, violation });
    });
    const eligible = assessments.filter(candidate => candidate.violation === null && candidate.predictionMismatches === 0);
    const ranked = [...eligible].sort((left, right) => Number(right.simulatedSuccess) - Number(left.simulatedSuccess) || left.actions.length - right.actions.length);
    const selected = ranked[0];
    const all = { status: "reviewed" as const, evidenceClass: "deterministic-simulation" as const,
      requestDigest: request.requestDigest, candidates: Object.freeze(assessments), transitionsUsed };
    if (!selected) return result(provider, { ...all,
      disposition: assessments.some(candidate => candidate.violation === null) ? "ESCALATE" : "REJECT",
      issues: Object.freeze(["No candidate has both legal simulator transitions and matching predictions"]),
    });
    return result(provider, { ...all, disposition: selected.simulatedSuccess ? "PROPOSE" : "DAMP",
      selectedCandidateId: selected.id,
      proposedActions: Object.freeze(selected.simulatedSuccess ? [...selected.actions] : selected.actions.slice(0, 1)),
      issues: Object.freeze([selected.simulatedSuccess
        ? "Simulator reaches the goal; this is a reviewable proposal, not execution permission"
        : "Goal not reached; offer only the first simulated action for review, then require a fresh observation and proposal"]),
    });
  } catch (error) {
    return result(provider, { requestDigest: request?.requestDigest ?? null, issues: Object.freeze([errorText(error)]) });
  }
}

export interface ImaginationProvider {
  readonly identity: ProviderIdentity;
  readonly available: boolean;
  readonly unavailableReason?: string;
  generate(request: ImaginationRequest, signal: AbortSignal): Promise<string>;
}

/** Host-owned provider adapter. Only a structured request and cancellation are
 * supplied to the provider. No dispatcher, native owner or write capability. */
export async function proposeImagination(
  requestValue: unknown, provider: ImaginationProvider,
  readCurrent: () => unknown,
  options: { readonly now?: () => number; readonly timeoutMs?: number; readonly signal?: AbortSignal } = {},
): Promise<ReviewResult> {
  let identity: ProviderIdentity = FIXTURE_PROVIDER;
  let request: ImaginationRequest | undefined;
  let timer: ReturnType<typeof setTimeout> | undefined;
  const controller = new AbortController();
  let cancel: (() => void) | undefined;
  try {
    identity = parseProvider(provider.identity);
    request = parseRequest(requestValue);
    const now = options.now ?? Date.now;
    const timeoutMs = integer(options.timeoutMs ?? 5_000, 30_000, "timeoutMs", 1);
    const initialContext = context(readCurrent());
    const startedAt = now();
    if (!isCurrent(request, initialContext, startedAt)) return result(identity, { status: "stale", requestDigest: request.requestDigest, issues: Object.freeze(["Request is already stale"]) });
    if (options.signal?.aborted) return result(identity, { status: "cancelled", requestDigest: request.requestDigest });
    if (!provider.available) return result(identity, { status: "unavailable", disposition: "ESCALATE", requestDigest: request.requestDigest,
      issues: Object.freeze([provider.unavailableReason ?? "Provider is unavailable; no substitute was run"]) });
    const startedMonotonic = performance.now();
    const stop = new Promise<{ kind: "cancelled" | "timeout" }>(resolve => {
      cancel = () => { resolve({ kind: "cancelled" }); controller.abort(); };
      options.signal?.addEventListener("abort", cancel, { once: true });
      timer = setTimeout(() => { resolve({ kind: "timeout" }); controller.abort(); }, timeoutMs);
    });
    const generated = Promise.resolve().then(() => {
      if (controller.signal.aborted) throw new Error("Generation was cancelled before dispatch");
      return provider.generate(request!, controller.signal);
    }).then(text => ({ kind: "response" as const, text }));
    const outcome = await Promise.race([generated, stop]);
    if (outcome.kind !== "response") return result(identity, { status: outcome.kind, requestDigest: request.requestDigest,
      issues: Object.freeze(["Generation ended without an accepted proposal"]) });
    // Owner reads may themselves take time or observe cancellation. Capture
    // context first, then check cancellation and deadlines immediately before review.
    const finalContext = context(readCurrent());
    const finishedAt = now();
    if (options.signal?.aborted) return result(identity, { status: "cancelled", requestDigest: request.requestDigest });
    if (finishedAt < startedAt) return result(identity, { status: "stale", requestDigest: request.requestDigest,
      issues: Object.freeze(["Clock moved backwards during generation; request a new proposal"]) });
    if (!isCurrent(request, finalContext, finishedAt)) return result(identity, { status: "stale", requestDigest: request.requestDigest,
      issues: Object.freeze(["Context or request lifetime changed during generation"]) });
    // A slow synchronous provider can resolve before a timer gets a turn.
    // Reject its late response even though a hard CPU stop is not provided here.
    if (finishedAt - startedAt >= timeoutMs || performance.now() - startedMonotonic >= timeoutMs) return result(identity, {
      status: "timeout", requestDigest: request.requestDigest,
      issues: Object.freeze(["Generation exceeded its elapsed deadline"]),
    });
    // The live owner must supply current values again after asynchronous work.
    return evaluateImagination(request, outcome.text, finalContext, finishedAt, identity);
  } catch (error) {
    return result(identity, { requestDigest: request?.requestDigest ?? null, issues: Object.freeze([errorText(error)]) });
  } finally {
    if (timer !== undefined) clearTimeout(timer);
    if (cancel) options.signal?.removeEventListener("abort", cancel);
    controller.abort();
  }
}

export const UNAVAILABLE_AGIMA_PROVIDER: ImaginationProvider = Object.freeze({
  identity: Object.freeze({ kind: "agima-bagel", id: "Agentic-Imagination/Agima", revision: "not-installed" }),
  available: false,
  unavailableReason: "Agima/BAGEL weights and CUDA inference are not installed; this pilot contains no visual-model backend",
  async generate(): Promise<string> { throw new Error("Agima provider unavailable"); },
});
