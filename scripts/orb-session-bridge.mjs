#!/usr/bin/env node
// Development transport for ARCHi's existing private presentation file. It owns no assistant or game state.
import { createServer } from 'node:https';
import { randomBytes, timingSafeEqual, X509Certificate } from 'node:crypto';
import { constants, promises as fs } from 'node:fs';
import { mkdtempSync, readFileSync, chmodSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const maximumBytes = 16_384;
const themes = new Set(['room', 'fantasy', 'voxel', 'neon']);
const commands = new Set(['assistant', 'memory', 'qimon', 'arena']);
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function boundedRead(path) {
  const file = await fs.open(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const stat = await file.stat();
    if (!stat.isFile() || stat.size < 2 || stat.size > maximumBytes) throw new Error('Unavailable presentation');
    const data = Buffer.alloc(maximumBytes + 1);
    const { bytesRead } = await file.read(data, 0, data.length, 0);
    if (bytesRead !== stat.size || bytesRead > maximumBytes) throw new Error('Changed presentation');
    return data.subarray(0, bytesRead);
  } finally { await file.close(); }
}

function presentation(data, now) {
  const value = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(data));
  if (value.schemaVersion !== 1 || !uuid.test(value.sessionID) || !/^[0-9a-f]{64}$/.test(value.originDigest)
      || !Number.isSafeInteger(value.revision) || value.revision < 1
      || !Number.isFinite(value.updatedAtUnix) || Math.abs(now - value.updatedAtUnix) > 5
      || value.active !== true || value.visible !== true || value.sessionKind === 'localPractice'
      || (value.destination ?? 'companion') !== 'companion' || value.orb?.schemaVersion !== 1
      || !themes.has(value.orb.theme) || !['world', 'follow'].includes(value.orb.anchor)) throw new Error('Inactive presentation');
  return value;
}

async function receive(request) {
  const chunks = []; let count = 0;
  for await (const chunk of request) {
    count += chunk.length;
    if (count > maximumBytes) throw new Error('Oversized request');
    chunks.push(chunk);
  }
  if (count < 2) throw new Error('Empty request');
  return Buffer.concat(chunks, count);
}

/** Use loopback by default. LAN exposure is an explicit --host choice, protected by TLS pinning and a session token. */
export async function startOrbBridge({ snapshotPath, key, cert, host = '127.0.0.1', port = 0,
    token = randomBytes(32).toString('hex'), now = () => Date.now() / 1000 }) {
  const path = resolve(snapshotPath);
  const initial = presentation(await boundedRead(path), now());
  if (!/^[0-9a-f]{64}$/.test(token)) throw new Error('Use a 256-bit session token');
  const expected = Buffer.from(`Bearer ${token}`);
  let lastSequence = 0, lastRevision = initial.revision;
  // Serialize accepted sidecar writes so concurrent packets cannot reorder or replay actions.
  let writes = Promise.resolve();
  const fingerprint = new X509Certificate(cert).fingerprint256.replaceAll(':', '').toLowerCase();
  const server = createServer({ key, cert, minVersion: 'TLSv1.2' }, (request, response) => {
    void (async () => {
      response.setHeader('Cache-Control', 'no-store');
      response.setHeader('X-Content-Type-Options', 'nosniff');
      response.setHeader('Content-Type', 'application/json');
      const authorization = Buffer.from(request.headers.authorization ?? '');
      if (authorization.length !== expected.length || !timingSafeEqual(authorization, expected)) {
        response.writeHead(401); response.end('{"status":"unauthorized"}'); request.resume(); return;
      }
      const data = await boundedRead(path);
      const snapshot = presentation(data, now());
      if (snapshot.sessionID !== initial.sessionID || snapshot.originDigest !== initial.originDigest
          || snapshot.revision < lastRevision) throw new Error('Retired session');
      lastRevision = snapshot.revision;
      response.setHeader('X-ARCHi-Time', String(now()));
      if (request.method === 'GET' && request.url === '/presentation') {
        try {
          const old = JSON.parse((await boundedRead(path + '.orb-request')).toString('utf8'));
          if (old.sessionID === initial.sessionID && old.originDigest === initial.originDigest && Number.isSafeInteger(old.sequence))
            lastSequence = Math.max(lastSequence, old.sequence);
        } catch { /* no previous request */ }
        response.setHeader('X-ARCHi-Next-Sequence', String(lastSequence + 1));
        response.end(data); return;
      }
      if (request.method !== 'POST' || !['/ack', '/request'].includes(request.url)) {
        response.writeHead(404); response.end('{"status":"unavailable"}'); request.resume(); return;
      }
      const bytes = await receive(request);
      const payload = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
      if (payload.schemaVersion !== 1 || payload.sessionID !== initial.sessionID || payload.originDigest !== initial.originDigest
          || !Number.isSafeInteger(payload.revision) || payload.revision < snapshot.revision - 1 || payload.revision > snapshot.revision
          || !Number.isFinite(payload.updatedAtUnix) || Math.abs(now() - payload.updatedAtUnix) > 5) throw new Error('Stale message');
      const isAction = request.url === '/request';
      if (isAction && (!Number.isSafeInteger(payload.sequence) || payload.sequence <= 0
          || !(payload.action === 'theme' ? themes.has(payload.value)
              : payload.action === 'anchor' ? ['world', 'follow'].includes(payload.value)
              : commands.has(payload.action) && (payload.value == null || payload.value === '')))) throw new Error('Unsupported action');
      if (!isAction && (typeof payload.active !== 'boolean' || !['seed', 'firstLight'].includes(payload.body)
          || payload.orb?.schemaVersion !== 1)) throw new Error('Unsupported acknowledgment');
      const save = async () => {
        const current = presentation(await boundedRead(path), now());
        if (current.sessionID !== initial.sessionID || current.originDigest !== initial.originDigest) throw new Error('Retired session');
        if (isAction && payload.sequence <= lastSequence) { response.writeHead(409); response.end('{"status":"duplicate"}'); return; }
        const destination = path + (isAction ? '.orb-request' : '.ack');
        const temporary = destination + '.' + randomBytes(12).toString('hex') + '.tmp';
        try {
          await fs.writeFile(temporary, bytes, { flag: 'wx', mode: 0o600 });
          await fs.rename(temporary, destination);
          if (isAction) lastSequence = payload.sequence;
        } finally { await fs.unlink(temporary).catch(() => {}); }
        // Receipt confirms transport only. Native owners still validate and apply the request.
        response.end('{"status":"delivered"}');
      };
      const pending = writes.then(save);
      writes = pending.catch(() => {});
      await pending;
    })().catch(() => {
      if (!response.headersSent) response.writeHead(409);
      if (!response.writableEnded) response.end('{"status":"unavailable"}');
    });
  });
  server.headersTimeout = 5_000; server.requestTimeout = 5_000; server.maxConnections = 4;
  await new Promise((accept, reject) => { server.once('error', reject); server.listen(port, host, accept); });
  return { server, port: server.address().port, sessionID: initial.sessionID, certificateSHA256: fingerprint,
    token, close: () => new Promise(resolveClose => { server.close(resolveClose); server.closeAllConnections(); }) };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const args = process.argv.slice(2);
  const option = name => { const index = args.indexOf(name); return index >= 0 ? args[index + 1] : undefined; };
  const snapshotPath = option('--snapshot');
  if (!snapshotPath) { process.stderr.write('Usage: node scripts/orb-session-bridge.mjs --snapshot /private/session/presentation.json [--host 0.0.0.0] [--pairing-file /private/pairing.json]\n'); process.exitCode = 2; }
  else {
    const directory = mkdtempSync(join(tmpdir(), 'archi-orb-tls-')); chmodSync(directory, 0o700);
    let bridge;
    try {
      execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
        '-keyout', join(directory, 'key.pem'), '-out', join(directory, 'cert.pem'), '-subj', '/CN=ARCHi Orb session'], { stdio: 'pipe' });
      chmodSync(join(directory, 'key.pem'), 0o600);
      bridge = await startOrbBridge({ snapshotPath, key: readFileSync(join(directory, 'key.pem')),
        cert: readFileSync(join(directory, 'cert.pem')), host: option('--host') ?? '127.0.0.1' });
      const pairingFile = option('--pairing-file') ?? join(directory, 'pairing.json');
      await fs.writeFile(pairingFile, JSON.stringify({ schemaVersion: 1, port: bridge.port, sessionID: bridge.sessionID,
        certificateSHA256: bridge.certificateSHA256, token: bridge.token }, null, 2), { flag: 'wx', mode: 0o600 });
      process.stdout.write(`ARCHi orb transport listening on port ${bridge.port}. Private pairing settings: ${pairingFile}\n`);
      const stop = async () => { await bridge.close(); rmSync(directory, { recursive: true, force: true }); process.exit(0); };
      process.once('SIGINT', stop); process.once('SIGTERM', stop);
    } catch {
      if (bridge) await bridge.close();
      rmSync(directory, { recursive: true, force: true });
      process.stderr.write('Orb transport could not open a current native orb session. No pairing token was printed.\n'); process.exitCode = 1;
    }
  }
}
