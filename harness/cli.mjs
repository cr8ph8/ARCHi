import fs from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = new URL('./', import.meta.url);
const modulePaths = ['contracts.mjs', 'strategies.mjs', 'router.mjs', 'catalogue.json', 'cli.mjs', 'fixtures.json'];

function readBytes(file, maximum = 65536) {
  // Limit before allocating or parsing. Reject symlinks and non-regular files.
  const descriptor = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
  try {
    const stat = fs.fstatSync(descriptor);
    if (!stat.isFile() || stat.size > maximum) throw new Error('Expected a bounded regular JSON file');
    const buffer = Buffer.alloc(maximum + 1);
    let length = 0;
    while (length <= maximum) {
      const count = fs.readSync(descriptor, buffer, length, buffer.length - length, null);
      if (count === 0) break;
      length += count;
    }
    if (length > maximum) throw new Error('JSON file exceeds size limit');
    return buffer.subarray(0, length);
  } finally { fs.closeSync(descriptor); }
}

function readJson(file, maximum = 65536) {
  return JSON.parse(readBytes(file, maximum).toString('utf8'));
}

function verifyIntegrity() {
  const integrity = readJson(new URL('integrity.json', root));
  if (integrity.format !== 'archi-harness-source-pins' || integrity.schemaVersion !== 1
      || Object.keys(integrity).sort().join('|') !== 'files|format|schemaVersion'
      || Object.keys(integrity.files).sort().join('|') !== [...modulePaths].sort().join('|')) {
    throw new Error('Invalid source-pin envelope');
  }
  for (const relative of modulePaths) {
    const file = new URL(relative, root);
    const actual = `sha256:${createHash('sha256').update(readBytes(file, 131072)).digest('hex')}`;
    if (actual !== integrity.files[relative]) throw new Error(`Source pin mismatch: ${relative}`);
  }
  return integrity;
}

async function main() {
  const [command, ...args] = process.argv.slice(2);
  if (!['check', 'observe'].includes(command) || command === 'check' && args.length !== 0
      || command === 'observe' && args.length !== 1) {
    throw new Error('Usage: node harness/cli.mjs check | observe <observation-packet.json>');
  }
  const integrity = verifyIntegrity();
  // Import reviewed code only after checking local drift. These co-located
  // pins are not signatures or protection from a compromised host/checker.
  const { hash, exact, snapshot } = await import('./contracts.mjs');
  const { createObserver } = await import('./router.mjs');
  const catalogue = readJson(new URL('catalogue.json', root));
  const observer = createObserver(catalogue, hash(catalogue), hash(integrity));
  if (command === 'observe') {
    const packet = snapshot(readJson(args[0]));
    exact(packet, ['request', 'current'], 'observation packet');
    // Wall time comes from this process, never from an input's asserted nowMs.
    const current = { ...packet.current, nowMs: Date.now() };
    return observer.observe(packet.request, current);
  }
  const fixtures = readJson(new URL('fixtures.json', root));
  exact(fixtures, ['format', 'discovery', 'heldOut'], 'fixtures');
  if (fixtures.format !== 'archi-harness-synthetic-fixtures') throw new Error('Invalid fixture format');
  const cases = [...fixtures.discovery, ...fixtures.heldOut];
  if (new Set(cases.map(c => c.id)).size !== cases.length) throw new Error('Fixture IDs overlap');
  const results = cases.map(test => {
    const request = {
      format: 'archi-harness-observation', schemaVersion: 1, requestId: test.id,
      contextDigest: hash({ fixture: test.id }), contextRevision: 1,
      policyRevision: 'offline-v1', modelRevision: 'synthetic-no-model',
      observedAtMs: 1000, expiresAtMs: 2000, features: test.features,
      usage: { modelCalls: 0, toolCalls: 0, tokens: 0, elapsedMs: 0 },
    };
    const current = {
      requestId: request.requestId, contextDigest: request.contextDigest, contextRevision: 1,
      policyRevision: request.policyRevision, modelRevision: request.modelRevision,
      nowMs: 1000, catalogueSha256: observer.catalogueSha256, sourceSha256: observer.sourceSha256,
      enabled: true, revokedHarnessIds: [],
    };
    const receipt = observer.observe(request, current);
    if (receipt.shadowHarnessId !== test.expected || receipt.mode !== 'shadow'
        || receipt.actualHarnessId !== 'base' || Object.values(receipt.authority).some(Boolean)) {
      throw new Error(`Synthetic route check failed: ${test.id}`);
    }
    return { id: test.id, passed: true, receiptSha256: receipt.receiptSha256 };
  });
  return { format: 'archi-harness-synthetic-report', qualification: 'synthetic-only',
    discoveryCases: fixtures.discovery.length, heldOutCases: fixtures.heldOut.length,
    passed: results.length, modelCalls: 0, toolCalls: 0, nativeIntegration: false,
    catalogueSha256: observer.catalogueSha256, sourceSha256: observer.sourceSha256, results };
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url))) {
  try { process.stdout.write(`${JSON.stringify(await main(), null, 2)}\n`); }
  catch (error) {
    // Input filenames, input contents, stack traces, and OS error paths are
    // omitted from stderr; malformed private data must not become a log.
    const message = error instanceof SyntaxError ? 'Invalid JSON' : 'Observation rejected; check input and reviewed source pins';
    process.stderr.write(`${message}\n`);
    process.exitCode = 1;
  }
}
