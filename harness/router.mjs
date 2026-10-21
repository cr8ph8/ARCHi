import { AUTHORITY, CHECKS, digest, exact, freshness, hash, snapshot, validateRequest, validateState } from './contracts.mjs';
import { BUILTINS } from './strategies.mjs';

export function validateCatalogue(input) {
  const c = snapshot(input);
  exact(c, ['format', 'schemaVersion', 'qualification', 'entries'], 'catalogue');
  if (c.format !== 'archi-harness-catalogue' || c.schemaVersion !== 1 || c.qualification !== 'synthetic-only'
      || !Array.isArray(c.entries) || c.entries.length !== Object.keys(BUILTINS).length) {
    throw new TypeError('Unqualified catalogue');
  }
  const seen = new Set();
  for (const entry of c.entries) {
    exact(entry, ['id', 'parentId'], 'catalogue entry');
    const builtin = Object.hasOwn(BUILTINS, entry.id) ? BUILTINS[entry.id] : null;
    if (!builtin || seen.has(entry.id) || entry.parentId !== builtin.parentId
        || entry.parentId !== null && !seen.has(entry.parentId)) throw new TypeError('Invalid harness lineage');
    seen.add(entry.id);
  }
  return c;
}

function classify(f) {
  if (f.errors.includes('permission-denied')) return ['base', 'permission-required'];
  if (f.errors.some(e => ['rate-limit', 'unavailable'].includes(e))) return ['base', 'service-unavailable'];
  if (f.baseCompleted && (f.outputFormat === 'text' || f.artifactExists && f.artifactValid)) return ['base', 'reuse-base'];
  if (f.outputFormat === 'xlsx' && f.percentageCells) return ['spreadsheet', 'saved-workbook-check'];
  if (f.outputFormat !== 'text' && (!f.artifactExists || !f.artifactValid)) return ['artifact', 'artifact-check'];
  if (f.errors.some(e => ['query-parse', 'tool-schema'].includes(e))) return ['api-schema', 'schema-check'];
  return ['base', 'no-supported-specialist'];
}

// An observation catalogue is bound to trusted code/policy by the host. The
// returned digest binds bytes but does not authenticate their producer.
export function createObserver(catalogueInput, expectedCatalogueSha256, sourceSha256) {
  const catalogue = validateCatalogue(catalogueInput);
  const catalogueSha256 = hash(catalogue);
  if (catalogueSha256 !== expectedCatalogueSha256) throw new TypeError('Catalogue pin mismatch');
  digest(sourceSha256, 'reviewed source pin');

  function observe(requestInput, stateInput) {
    const r = validateRequest(requestInput);
    const s = validateState(stateInput);
    let reason = freshness(r, s);
    if (s.catalogueSha256 !== catalogueSha256) reason = 'catalogue-mismatch';
    if (s.sourceSha256 !== sourceSha256) reason = 'source-mismatch';
    let shadowHarnessId = 'base';
    let status = reason ? 'rejected' : 'observed';
    if (!reason && !s.enabled) { reason = 'disabled'; status = 'disabled'; }
    if (!reason) [shadowHarnessId, reason] = classify(r.features);
    const lineage = [];
    for (let node = shadowHarnessId; node !== null; node = BUILTINS[node].parentId) lineage.push(node);
    if (lineage.some(node => s.revokedHarnessIds.includes(node))) {
      shadowHarnessId = 'base'; reason = 'revoked'; status = 'rejected';
    }
    const plan = status === 'observed' ? new BUILTINS[shadowHarnessId].type().checks() : [];
    if (new Set(plan).size !== plan.length || plan.some(check => !CHECKS.includes(check))) {
      throw new TypeError('Check plan outside the reviewed allowlist');
    }
    const payload = {
      format: 'archi-harness-receipt', schemaVersion: 1, mode: 'shadow', status,
      actualHarnessId: 'base', shadowHarnessId, reason, checkPlan: plan,
      requestId: r.requestId, requestSha256: hash(r), catalogueSha256, sourceSha256,
      contextDigest: r.contextDigest, contextRevision: r.contextRevision,
      policyRevision: r.policyRevision, modelRevision: r.modelRevision,
      observedAtMs: r.observedAtMs, expiresAtMs: r.expiresAtMs,
      recordedAtMs: s.nowMs, usage: r.usage, authority: AUTHORITY,
      qualification: catalogue.qualification,
    };
    return snapshot({ ...payload, receiptSha256: hash(payload) });
  }

  // Full deterministic reconstruction, rather than trusting an imported
  // receipt's authority fields, selection, checksum, or asserted score.
  function matchesCurrentObservation(receiptInput, requestInput, stateInput) {
    try {
      const receipt = snapshot(receiptInput);
      const state = validateState(stateInput);
      if (!state.enabled || receipt.status !== 'observed' || receipt.recordedAtMs > state.nowMs) return false;
      const reconstructed = observe(requestInput, { ...state, nowMs: receipt.recordedAtMs });
      if (hash(receipt) !== hash(reconstructed)) return false;
      return observe(requestInput, state).status === 'observed';
    } catch { return false; }
  }

  return Object.freeze({ observe, matchesCurrentObservation, catalogueSha256, sourceSha256 });
}
