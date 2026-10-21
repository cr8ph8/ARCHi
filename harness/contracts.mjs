import { createHash } from 'node:crypto';

export const FORMAT = 'archi-harness-observation';
export const SHA256 = /^sha256:[a-f0-9]{64}$/;
export const CHECKS = Object.freeze([
  'verify-current-context', 'check-artifact-exists', 'check-artifact-format',
  'check-saved-cell-values', 'check-percentage-units', 'check-tool-schema', 'check-tool-result',
]);
export const AUTHORITY = Object.freeze({
  executeTools: false, changeProvider: false, writeMemory: false,
  mutateState: false, grantPermission: false, promoteCode: false,
});

// Copy data descriptors before reading values. This is JSON hygiene, not a
// sandbox for hostile JavaScript objects or same-process code.
export function snapshot(input) {
  let nodes = 0;
  let characters = 0;
  const active = new Set();
  function copy(value, depth) {
    if (++nodes > 4096 || depth > 12) throw new TypeError('Input exceeds structural bounds');
    if (value === null || typeof value === 'boolean') return value;
    if (typeof value === 'string') {
      characters += value.length;
      if (characters > 65536) throw new TypeError('Input exceeds text bounds');
      return value;
    }
    if (typeof value === 'number' && Number.isFinite(value)) return value;
    if (typeof value !== 'object' || active.has(value)) throw new TypeError('Expected acyclic JSON data');
    const array = Array.isArray(value);
    const prototype = Object.getPrototypeOf(value);
    if (array ? prototype !== Array.prototype : prototype !== Object.prototype && prototype !== null) {
      throw new TypeError('Expected plain JSON data');
    }
    const descriptors = Object.getOwnPropertyDescriptors(value);
    const keys = Reflect.ownKeys(descriptors);
    if (keys.some(key => typeof key !== 'string')) throw new TypeError('Symbol keys are forbidden');
    if (array) {
      const length = descriptors.length.value;
      if (length > 256 || keys.length !== length + 1) throw new TypeError('Expected bounded dense array');
      for (let i = 0; i < length; i++) {
        if (!Object.hasOwn(descriptors, String(i))) throw new TypeError('Sparse arrays are forbidden');
      }
    }
    const result = array ? [] : Object.create(null);
    active.add(value);
    for (const key of keys) {
      if (array && key === 'length') continue;
      characters += key.length;
      if (characters > 65536) throw new TypeError('Input exceeds text bounds');
      const descriptor = descriptors[key];
      if (!Object.hasOwn(descriptor, 'value') || !descriptor.enumerable) {
        throw new TypeError('Accessors and hidden fields are forbidden');
      }
      if (['__proto__', 'prototype', 'constructor'].includes(key)) throw new TypeError('Reserved field');
      result[key] = copy(descriptor.value, depth + 1);
    }
    active.delete(value);
    return Object.freeze(result);
  }
  return copy(input, 0);
}

export function exact(value, keys, name) {
  const actual = value && typeof value === 'object' ? Object.keys(value).sort() : [];
  const expected = [...keys].sort();
  if (!value || typeof value !== 'object' || Array.isArray(value)
      || actual.length !== expected.length || actual.some((key, index) => key !== expected[index])) {
    throw new TypeError(`${name} has an invalid envelope`);
  }
}

export function id(value, name) {
  if (typeof value !== 'string' || !/^[a-zA-Z0-9][a-zA-Z0-9._:-]{0,95}$/.test(value)) {
    throw new TypeError(`${name} must be a bounded opaque identifier`);
  }
}

export function integer(value, name, max = Number.MAX_SAFE_INTEGER) {
  if (!Number.isSafeInteger(value) || value < 0 || value > max) throw new TypeError(`Invalid ${name}`);
}

export function digest(value, name) {
  if (typeof value !== 'string' || !SHA256.test(value)) throw new TypeError(`Invalid ${name}`);
}

function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

export function hash(value) {
  return `sha256:${createHash('sha256').update(canonical(snapshot(value))).digest('hex')}`;
}

export function validateRequest(input) {
  const r = snapshot(input);
  exact(r, ['format', 'schemaVersion', 'requestId', 'contextDigest', 'contextRevision',
    'policyRevision', 'modelRevision', 'observedAtMs', 'expiresAtMs', 'features', 'usage'], 'request');
  if (r.format !== FORMAT || r.schemaVersion !== 1) throw new TypeError('Unsupported request version');
  for (const key of ['requestId', 'policyRevision', 'modelRevision']) id(r[key], key);
  digest(r.contextDigest, 'contextDigest');
  for (const key of ['contextRevision', 'observedAtMs', 'expiresAtMs']) integer(r[key], key);
  if (r.expiresAtMs <= r.observedAtMs || r.expiresAtMs - r.observedAtMs > 300000) {
    throw new TypeError('Observation validity must be between 1ms and five minutes');
  }
  const f = r.features;
  exact(f, ['outputFormat', 'errors', 'baseCompleted', 'artifactExists', 'artifactValid', 'percentageCells'], 'features');
  if (!['text', 'pdf', 'docx', 'xlsx', 'code'].includes(f.outputFormat)) throw new TypeError('Invalid output format');
  for (const key of ['baseCompleted', 'artifactExists', 'artifactValid', 'percentageCells']) {
    if (typeof f[key] !== 'boolean') throw new TypeError(`Invalid ${key}`);
  }
  if (f.artifactValid && !f.artifactExists) throw new TypeError('An absent artifact cannot be valid');
  if (f.percentageCells && f.outputFormat !== 'xlsx') throw new TypeError('Percentage checks require a workbook');
  if (!Array.isArray(f.errors) || f.errors.length > 8 || new Set(f.errors).size !== f.errors.length
      || f.errors.some(e => !['query-parse', 'tool-schema', 'permission-denied', 'rate-limit', 'unavailable'].includes(e))) {
    throw new TypeError('Invalid error categories');
  }
  exact(r.usage, ['modelCalls', 'toolCalls', 'tokens', 'elapsedMs'], 'usage');
  for (const key of Object.keys(r.usage)) integer(r.usage[key], key, 1000000000);
  return r;
}

export function validateState(input) {
  const s = snapshot(input);
  exact(s, ['requestId', 'contextDigest', 'contextRevision', 'policyRevision', 'modelRevision',
    'nowMs', 'catalogueSha256', 'sourceSha256', 'enabled', 'revokedHarnessIds'], 'current state');
  for (const key of ['requestId', 'policyRevision', 'modelRevision']) id(s[key], key);
  for (const key of ['contextDigest', 'catalogueSha256', 'sourceSha256']) digest(s[key], key);
  for (const key of ['contextRevision', 'nowMs']) integer(s[key], key);
  if (typeof s.enabled !== 'boolean' || !Array.isArray(s.revokedHarnessIds)
      || s.revokedHarnessIds.length > 32 || new Set(s.revokedHarnessIds).size !== s.revokedHarnessIds.length) {
    throw new TypeError('Invalid observer policy');
  }
  for (const entry of s.revokedHarnessIds) id(entry, 'revoked harness');
  return s;
}

export function freshness(r, s) {
  if (r.requestId !== s.requestId || r.contextDigest !== s.contextDigest || r.contextRevision !== s.contextRevision) {
    return 'stale-context';
  }
  if (r.policyRevision !== s.policyRevision || r.modelRevision !== s.modelRevision) return 'stale-policy';
  if (s.nowMs < r.observedAtMs || s.nowMs >= r.expiresAtMs) return 'expired';
  return null;
}
