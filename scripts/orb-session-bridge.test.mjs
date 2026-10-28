import test from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { request as httpsRequest } from 'node:https';
import { randomUUID } from 'node:crypto';
import { startOrbBridge } from './orb-session-bridge.mjs';

const certDirectory = await fs.mkdtemp(join(tmpdir(), 'archi-orb-test-cert-'));
execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
  '-keyout', join(certDirectory, 'key.pem'), '-out', join(certDirectory, 'cert.pem'), '-subj', '/CN=localhost'], { stdio: 'pipe' });
const key = await fs.readFile(join(certDirectory, 'key.pem')), cert = await fs.readFile(join(certDirectory, 'cert.pem'));
await fs.rm(certDirectory, { recursive: true, force: true });

async function fixture(t) {
  const directory = await fs.mkdtemp(join(tmpdir(), 'archi-orb-transport-test-'));
  const snapshotPath = join(directory, 'presentation.json');
  const snapshot = { schemaVersion: 1, sessionID: randomUUID(), revision: 1, originDigest: 'a'.repeat(64),
    displayName: 'SYNTHETIC KIN', body: 'seed', cursor: 'seed', activity: 'idle', lightMode: 'rest',
    seedAssetSHA256: 'b'.repeat(64), bodyAssetSHA256: 'b'.repeat(64), quiet: false, reduceMotion: false,
    active: true, visible: true, updatedAtUnix: 1000,
    orb: { schemaVersion: 1, theme: 'room', anchor: 'world', listening: false, speaking: false } };
  await fs.writeFile(snapshotPath, JSON.stringify(snapshot));
  const clock = { now: 1000 };
  const bridge = await startOrbBridge({ snapshotPath, key, cert, now: () => clock.now });
  t.after(async () => { await bridge.close(); await fs.rm(directory, { recursive: true, force: true }); });
  const request = (path, { method = 'GET', token = bridge.token, payload, pin = bridge.certificateSHA256 } = {}) =>
    new Promise((accept, reject) => {
      const client = httpsRequest({ hostname: '127.0.0.1', port: bridge.port, path, method, ca: cert,
        checkServerIdentity: (_host, peer) => peer.fingerprint256.replaceAll(':', '').toLowerCase() === pin ? undefined : new Error('Certificate pin mismatch'),
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' } }, response => {
          const chunks = []; response.on('data', chunk => chunks.push(chunk));
          response.on('end', () => accept({ status: response.statusCode, body: Buffer.concat(chunks).toString('utf8'), headers: response.headers }));
        });
      client.on('error', reject);
      client.end(payload == null ? undefined : typeof payload === 'string' ? payload : JSON.stringify(payload));
    });
  const action = (sequence = 1, changes = {}) => ({ schemaVersion: 1, sessionID: snapshot.sessionID,
    originDigest: snapshot.originDigest, revision: 1, updatedAtUnix: 1000, sequence, action: 'theme', value: 'voxel', ...changes });
  return { directory, snapshotPath, snapshot, bridge, clock, request, action };
}

test('paired TLS transport returns the original bounded projection and a server clock', async t => {
  const f = await fixture(t), result = await f.request('/presentation');
  assert.equal(result.status, 200); assert.deepEqual(JSON.parse(result.body), f.snapshot);
  assert.equal(result.headers['cache-control'], 'no-store'); assert.equal(result.headers['x-archi-time'], '1000');
  assert.equal(result.headers['x-archi-next-sequence'], '1');
});
test('wrong pairing token cannot read state or write requests', async t => {
  const f = await fixture(t);
  assert.equal((await f.request('/presentation', { token: 'wrong' })).status, 401);
  assert.equal((await f.request('/request', { method: 'POST', token: 'wrong', payload: f.action() })).status, 401);
  await assert.rejects(fs.stat(f.snapshotPath + '.orb-request'));
});
test('a different certificate pin fails before application data is accepted', async t => {
  const f = await fixture(t);
  await assert.rejects(f.request('/presentation', { pin: '0'.repeat(64) }), /pin mismatch/);
});
test('a valid command reaches only the existing native sidecar, once', async t => {
  const f = await fixture(t), before = await fs.readFile(f.snapshotPath);
  const first = await f.request('/request', { method: 'POST', payload: f.action() });
  assert.equal(first.status, 200); assert.equal(JSON.parse(first.body).status, 'delivered');
  assert.deepEqual(JSON.parse(await fs.readFile(f.snapshotPath + '.orb-request')), f.action());
  assert.equal((await f.request('/request', { method: 'POST', payload: f.action() })).status, 409);
  assert.deepEqual(await fs.readFile(f.snapshotPath), before, 'Transport cannot mutate native presentation or a save.');
  assert.equal((await f.request('/presentation')).headers['x-archi-next-sequence'], '2');
});
test('concurrent duplicate packets produce one delivery', async t => {
  const f = await fixture(t);
  const responses = await Promise.all([f.request('/request', { method: 'POST', payload: f.action() }), f.request('/request', { method: 'POST', payload: f.action() })]);
  assert.deepEqual(responses.map(r => r.status).sort(), [200, 409]);
});
test('unknown actions, themes, foreign sessions and stale commands never reach native owners', async t => {
  const f = await fixture(t);
  for (const changes of [{ action: 'eval', value: 'code' }, { value: 'https://remote-assets' },
    { sessionID: randomUUID() }, { originDigest: 'c'.repeat(64) }, { revision: 2 },
    { sequence: 0 }, { sequence: 1.5 }, { updatedAtUnix: 994 }, { action: 'memory', value: 'write memory' }]) {
    assert.equal((await f.request('/request', { method: 'POST', payload: f.action(1, changes) })).status, 409);
  }
  await assert.rejects(fs.stat(f.snapshotPath + '.orb-request'));
});
test('acknowledgments travel through the existing ACK file', async t => {
  const f = await fixture(t);
  const ack = { ...f.action(), body: 'seed', active: true, orb: f.snapshot.orb };
  assert.equal((await f.request('/ack', { method: 'POST', payload: ack })).status, 200);
  assert.deepEqual(JSON.parse(await fs.readFile(f.snapshotPath + '.ack')), ack);
});
test('inactive, expired and replaced native sessions stop rendering and request delivery', async t => {
  const f = await fixture(t);
  f.clock.now = 1006;
  assert.equal((await f.request('/presentation')).status, 409);
  f.clock.now = 1000;
  for (const changes of [{ active: false }, { visible: false }, { sessionID: randomUUID() }, { revision: 0 }, { orb: null }]) {
    await fs.writeFile(f.snapshotPath, JSON.stringify({ ...f.snapshot, ...changes }));
    assert.equal((await f.request('/presentation')).status, 409);
    assert.equal((await f.request('/request', { method: 'POST', payload: f.action() })).status, 409);
  }
});
test('oversized bodies and symlink replacements are refused', async t => {
  const f = await fixture(t);
  assert.equal((await f.request('/request', { method: 'POST', payload: 'x'.repeat(16_385) })).status, 409);
  const other = join(f.directory, 'other.json');
  await fs.rename(f.snapshotPath, other); await fs.symlink(other, f.snapshotPath);
  assert.equal((await f.request('/presentation')).status, 409);
});
test('only presentation, ACK and action routes are exposed', async t => {
  const f = await fixture(t);
  assert.equal((await f.request('/../preferences.json')).status, 404);
  assert.equal((await f.request('/presentation?token=anything')).status, 404);
});
