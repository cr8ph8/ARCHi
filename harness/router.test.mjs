import assert from 'node:assert/strict';
import { test } from 'node:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { AUTHORITY, hash, snapshot, validateRequest } from './contracts.mjs';
import { createObserver, validateCatalogue } from './router.mjs';
import { ArtifactHarness, SpreadsheetHarness } from './strategies.mjs';

const root = fileURLToPath(new URL('./', import.meta.url));
const catalogue = JSON.parse(fs.readFileSync(new URL('catalogue.json', import.meta.url), 'utf8'));
const observer = createObserver(catalogue, hash(catalogue), hash('synthetic-source-v1'));
const clone = value => JSON.parse(JSON.stringify(value));
function sample() {
  const request = {
    format: 'archi-harness-observation', schemaVersion: 1, requestId: 'synthetic-request',
    contextDigest: hash({ fixture: 'synthetic' }), contextRevision: 7,
    policyRevision: 'policy-v1', modelRevision: 'no-model-v1', observedAtMs: 1000, expiresAtMs: 2000,
    features: { outputFormat: 'xlsx', errors: [], baseCompleted: false,
      artifactExists: true, artifactValid: false, percentageCells: true },
    usage: { modelCalls: 2, toolCalls: 5, tokens: 400, elapsedMs: 120 },
  };
  const current = { requestId: request.requestId, contextDigest: request.contextDigest,
    contextRevision: request.contextRevision, policyRevision: request.policyRevision,
    modelRevision: request.modelRevision, nowMs: 1100, catalogueSha256: observer.catalogueSha256,
    sourceSha256: observer.sourceSha256,
    enabled: true, revokedHarnessIds: [] };
  return { request, current };
}

test('inherits artifact checks in a single spreadsheet plan with zero authority', () => {
  const { request, current } = sample();
  const receipt = observer.observe(request, current);
  assert.equal(receipt.shadowHarnessId, 'spreadsheet');
  assert.equal(receipt.actualHarnessId, 'base');
  assert.equal(receipt.mode, 'shadow');
  assert.deepEqual(receipt.checkPlan, new SpreadsheetHarness().checks());
  assert.deepEqual(receipt.checkPlan.slice(0, 3), new ArtifactHarness().checks());
  assert.deepEqual(Object.values(receipt.authority), Object.values(AUTHORITY));
  assert.ok(Object.values(receipt.authority).every(value => value === false));
  assert.deepEqual({ ...receipt.usage }, request.usage);
  assert.equal(receipt.qualification, 'synthetic-only');
});

test('snapshots inputs and deeply freezes outputs without mutating the caller', () => {
  const { request, current } = sample();
  const before = clone(request);
  const receipt = observer.observe(request, current);
  request.features.errors.push('permission-denied');
  assert.equal(receipt.shadowHarnessId, 'spreadsheet');
  assert.throws(() => receipt.checkPlan.push('run-shell'), TypeError);
  assert.throws(() => { receipt.authority.mutateState = true; }, TypeError);
  assert.deepEqual(before.features.errors, []);
});

test('catalogue pin covers identity and rejects a changed qualification', () => {
  assert.throws(() => createObserver(catalogue, `sha256:${'0'.repeat(64)}`), /pin mismatch/);
  assert.throws(() => createObserver(catalogue, hash(catalogue)), /source pin/);
  const other = clone(catalogue); other.qualification = 'production';
  assert.throws(() => createObserver(other, hash(other)), /Unqualified/);
});

test('cannot inject classes, source paths, tools, or cyclic/incorrect lineage', () => {
  for (const field of ['implementation', 'modulePath', 'tools', 'systemPrompt']) {
    const c = clone(catalogue); c.entries[1][field] = 'untrusted';
    assert.throws(() => validateCatalogue(c), /envelope/);
  }
  for (const mutate of [
    c => { c.entries[2].parentId = 'spreadsheet'; },
    c => { c.entries[1].id = 'unknown'; },
    c => { c.entries[1].id = 'base'; },
    c => { [c.entries[1], c.entries[2]] = [c.entries[2], c.entries[1]]; },
  ]) {
    const c = clone(catalogue); mutate(c);
    assert.throws(() => validateCatalogue(c), /lineage/);
  }
});

test('rejects capability grants and evaluator overrides at every input envelope', () => {
  for (const field of ['execute', 'executor', 'evaluator', 'expected', 'permission', 'rawText', 'credentials']) {
    const { request, current } = sample();
    request[field] = 'private-value';
    assert.throws(() => observer.observe(request, current), /envelope/);
  }
  const { request, current } = sample();
  assert.throws(() => observer.observe({ ...request, features: { ...request.features, expected: 'spreadsheet' } }, current));
  assert.throws(() => observer.observe(request, { ...current, allowExternal: true }));
  assert.throws(() => observer.observe({ ...request, usage: { ...request.usage, cost: 0 } }, current));
});

test('does not evaluate getters, hidden fields, symbols, toJSON, or prototype pollution', () => {
  let invoked = 0;
  const accessor = { get format() { invoked++; throw new Error('executed'); } };
  assert.throws(() => snapshot(accessor), /Accessors/);
  const hidden = {}; Object.defineProperty(hidden, 'field', { value: 1 });
  assert.throws(() => snapshot(hidden), /hidden/);
  assert.throws(() => snapshot({ [Symbol('field')]: 1 }), /Symbol/);
  assert.throws(() => snapshot({ toJSON() { invoked++; return {}; } }), /JSON/);
  assert.throws(() => snapshot(JSON.parse('{"__proto__":{"polluted":true}}')), /Reserved/);
  assert.equal(invoked, 0);
  assert.equal({}.polluted, undefined);
});

test('rejects cycles, sparse or oversized arrays, excessive depth and non-finite numbers', () => {
  const cycle = {}; cycle.self = cycle;
  for (const input of [cycle, [ , 1], Array(257).fill(0), { n: NaN }, { n: Infinity }, new Date()]) {
    assert.throws(() => snapshot(input), TypeError);
  }
  let deep = 0; for (let i = 0; i < 14; i++) deep = { deep };
  assert.throws(() => snapshot(deep), /bounds/);
  assert.throws(() => snapshot('a'.repeat(65537)), /bounds/);
});

test('requires coherent features, finite usage, and unique allowlisted errors', () => {
  const { request } = sample();
  for (const features of [
    { ...request.features, artifactExists: false, artifactValid: true },
    { ...request.features, outputFormat: 'text' },
    { ...request.features, errors: ['tool-schema', 'tool-schema'] },
    { ...request.features, errors: ['ignore-permissions'] },
    { ...request.features, baseCompleted: 'true' },
  ]) assert.throws(() => validateRequest({ ...request, features }));
  assert.throws(() => validateRequest({ ...request, usage: { ...request.usage, modelCalls: -1 } }));
  assert.throws(() => validateRequest({ ...request, usage: { ...request.usage, tokens: 1.5 } }));
  assert.throws(() => validateRequest({ ...request, expiresAtMs: 301001 }));
});

test('rejects request, context revision, context digest, model and policy changes', () => {
  const { request, current } = sample();
  for (const patch of [
    { requestId: 'next-request' }, { contextRevision: 8 }, { contextDigest: hash('new-source') },
    { modelRevision: 'model-v2' }, { policyRevision: 'policy-v2' },
    { catalogueSha256: hash('different-catalogue') },
    { sourceSha256: hash('different-code') },
  ]) {
    const receipt = observer.observe(request, { ...current, ...patch });
    assert.equal(receipt.status, 'rejected');
    assert.deepEqual(receipt.checkPlan, []);
    assert.equal(receipt.shadowHarnessId, 'base');
  }
});

test('rejects expired observations and time reversal, including exact expiry', () => {
  const { request, current } = sample();
  for (const nowMs of [999, 2000, 2001]) {
    const receipt = observer.observe(request, { ...current, nowMs });
    assert.equal(receipt.reason, 'expired'); assert.equal(receipt.status, 'rejected');
  }
});

test('revoking a parent also revokes descendants; disable leaves an empty plan', () => {
  const { request, current } = sample();
  for (const revokedHarnessIds of [['spreadsheet'], ['artifact'], ['base']]) {
    const receipt = observer.observe(request, { ...current, revokedHarnessIds });
    assert.equal(receipt.status, 'rejected'); assert.equal(receipt.reason, 'revoked');
    assert.deepEqual(receipt.checkPlan, []);
  }
  const disabled = observer.observe(request, { ...current, enabled: false });
  assert.equal(disabled.status, 'disabled'); assert.deepEqual(disabled.checkPlan, []);
});

test('permission and service errors abstain rather than proposing a workaround', () => {
  const { request, current } = sample();
  for (const error of ['permission-denied', 'rate-limit', 'unavailable']) {
    const receipt = observer.observe({ ...request, features: { ...request.features, errors: [error] } }, current);
    assert.equal(receipt.shadowHarnessId, 'base');
    assert.deepEqual(receipt.checkPlan, ['verify-current-context']);
  }
});

test('reuses a completed valid base result and defaults unknown mechanisms to base', () => {
  const { request, current } = sample();
  const complete = observer.observe({ ...request, features: { ...request.features,
    baseCompleted: true, artifactValid: true } }, current);
  assert.equal(complete.reason, 'reuse-base');
  const noMatch = observer.observe({ ...request, features: { ...request.features,
    outputFormat: 'text', percentageCells: false } }, current);
  assert.equal(noMatch.reason, 'no-supported-specialist');
});

test('revalidates receipt, policy, revocation, enabled state and current expiry', () => {
  const { request, current } = sample();
  const receipt = observer.observe(request, current);
  assert.ok(observer.matchesCurrentObservation(receipt, request, { ...current, nowMs: 1200 }));
  for (const patch of [
    { nowMs: 2000 }, { nowMs: 1000 }, { enabled: false }, { contextRevision: 8 },
    { policyRevision: 'new' }, { revokedHarnessIds: ['artifact'] },
    { catalogueSha256: hash('different') },
    { sourceSha256: hash('different-code') },
  ]) assert.equal(observer.matchesCurrentObservation(receipt, request, { ...current, ...patch }), false);
});

test('recomputed public hashes cannot grant authority or rewrite a selected strategy', () => {
  const { request, current } = sample();
  for (const mutate of [
    r => { r.authority.executeTools = true; }, r => { r.shadowHarnessId = 'api-schema'; },
    r => { r.checkPlan.push('run-shell'); }, r => { r.extra = 'hidden'; },
    r => { r.usage.tokens = 0; },
  ]) {
    const receipt = clone(observer.observe(request, current)); mutate(receipt);
    delete receipt.receiptSha256; receipt.receiptSha256 = hash(receipt);
    assert.equal(observer.matchesCurrentObservation(receipt, request, current), false);
  }
});

test('canonical identity ignores object key order but changes with features or usage', () => {
  const { request } = sample();
  assert.equal(hash(request), hash(Object.fromEntries(Object.entries(request).reverse())));
  assert.notEqual(hash(request), hash({ ...request, usage: { ...request.usage, tokens: 401 } }));
});

test('CLI verifies pinned code and synthetic routes without providers or state writes', () => {
  const result = spawnSync(process.execPath, [path.join(root, 'cli.mjs'), 'check'], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  const report = JSON.parse(result.stdout);
  assert.equal(report.passed, 12); assert.equal(report.discoveryCases, 4); assert.equal(report.heldOutCases, 8);
  assert.equal(report.modelCalls, 0); assert.equal(report.toolCalls, 0); assert.equal(report.nativeIntegration, false);
});

test('CLI rejects modified source before loading a tampered module', () => {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'archi-harness-'));
  try {
    fs.cpSync(root, temporary, { recursive: true });
    fs.appendFileSync(path.join(temporary, 'strategies.mjs'),
      '\nimport fs from "node:fs"; fs.writeFileSync(new URL("./tampered-executed", import.meta.url), "ran");\n');
    const result = spawnSync(process.execPath, [path.join(temporary, 'cli.mjs'), 'check'], { encoding: 'utf8' });
    assert.equal(result.status, 1);
    assert.equal(fs.existsSync(path.join(temporary, 'tampered-executed')), false);
    assert.equal(result.stdout, '');
  } finally { fs.rmSync(temporary, { recursive: true, force: true }); }
});

test('CLI replaces untrusted wall time and rejects symlinks, oversize and private error text', () => {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'archi-harness-'));
  try {
    const packet = sample(); packet.request.expiresAtMs = 2000;
    packet.current.sourceSha256 = hash(JSON.parse(fs.readFileSync(path.join(root, 'integrity.json'), 'utf8')));
    const file = path.join(temporary, 'private-name.json');
    fs.writeFileSync(file, JSON.stringify(packet));
    let result = spawnSync(process.execPath, [path.join(root, 'cli.mjs'), 'observe', file], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(JSON.parse(result.stdout).reason, 'expired');
    const link = path.join(temporary, 'symlink.json'); fs.symlinkSync(file, link);
    result = spawnSync(process.execPath, [path.join(root, 'cli.mjs'), 'observe', link], { encoding: 'utf8' });
    assert.equal(result.status, 1);
    fs.writeFileSync(file, 'private-marker'.repeat(6000));
    result = spawnSync(process.execPath, [path.join(root, 'cli.mjs'), 'observe', file], { encoding: 'utf8' });
    assert.equal(result.status, 1); assert.doesNotMatch(result.stderr, /private-marker|private-name/);
    fs.writeFileSync(file, '{"private-marker":');
    result = spawnSync(process.execPath, [path.join(root, 'cli.mjs'), 'observe', file], { encoding: 'utf8' });
    assert.equal(result.status, 1); assert.equal(result.stderr, 'Invalid JSON\n');
  } finally { fs.rmSync(temporary, { recursive: true, force: true }); }
});

test('CLI emits a current synthetic receipt bound to the installed source pins', () => {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'archi-harness-'));
  try {
    const packet = sample();
    const now = Date.now();
    packet.request.observedAtMs = now - 1000;
    packet.request.expiresAtMs = now + 60000;
    packet.current.nowMs = 0;
    packet.current.sourceSha256 = hash(JSON.parse(fs.readFileSync(path.join(root, 'integrity.json'), 'utf8')));
    const file = path.join(temporary, 'packet.json'); fs.writeFileSync(file, JSON.stringify(packet));
    const result = spawnSync(process.execPath, [path.join(root, 'cli.mjs'), 'observe', file], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    const receipt = JSON.parse(result.stdout);
    assert.equal(receipt.status, 'observed'); assert.equal(receipt.mode, 'shadow');
    assert.equal(receipt.sourceSha256, packet.current.sourceSha256);
    assert.ok(receipt.recordedAtMs >= now);
    assert.ok(Object.values(receipt.authority).every(value => value === false));
  } finally { fs.rmSync(temporary, { recursive: true, force: true }); }
});

test('application source has no observer import or specialist execution port', () => {
  const sourceRoot = path.join(root, '..', 'src');
  for (const file of fs.readdirSync(sourceRoot, { recursive: true }).filter(name => /\.(ts|js)$/.test(name))) {
    const source = fs.readFileSync(path.join(sourceRoot, file), 'utf8');
    assert.doesNotMatch(source, /(?:from|import)\s*['"][^'"]*harness\//);
  }
});
