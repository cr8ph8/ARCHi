import http from 'node:http';
import { performance } from 'node:perf_hooks';
import { validateManifest } from './experiment.mjs';

const COLLECTOR = 'archi-experimental-ollama/v1';
const MAX_BYTES = 10 * 1024 * 1024;
const MAX_CAPTURE_BYTES = 24 * 1024 * 1024;
const RESERVED_RECORD_BYTES = 8192;
const MAX_REQUESTS = 2000;
const MAX_TIMEOUT_MS = 120000;

class CollectorError extends Error {
  constructor(code, message, rawResponse = null) {
    super(message);
    this.code = code;
    this.rawResponse = rawResponse;
  }
}

function fail(code, message) { throw new CollectorError(code, message); }
function counter(value) { return Number.isSafeInteger(value) && value >= 0 ? value : null; }
function errorDetails(error) {
  return { code: error.code || 'REQUEST_FAILED', message: String(error.message || error).slice(0, 1000) };
}
function cloudName(name) { return /(?:^|[:/-])cloud(?:$|[:/-])/i.test(name); }
function hasRemoteMetadata(value) {
  if (!value || typeof value !== 'object') return false;
  for (const [key, child] of Object.entries(value)) {
    const normalized = key.toLowerCase().replace(/[-_]/g, '');
    if (['remotehost', 'remotemodel', 'remoteurl', 'cloudmodel', 'cloudhost'].includes(normalized) && child) return true;
    if (['cloud', 'remote', 'iscloud', 'isremote'].includes(normalized) && child !== false && child !== null && child !== undefined && child !== '' && child !== 0) return true;
    if (['provider', 'deployment', 'location', 'modeltype'].includes(normalized) && typeof child === 'string' && /(?:cloud|remote)/i.test(child)) return true;
    if (['details', 'model_info', 'metadata', 'deployment'].includes(key) && hasRemoteMetadata(child)) return true;
  }
  return false;
}
function installedDigest(value) {
  return typeof value === 'string' && /^(?:sha256:)?[a-f0-9]{64}$/i.test(value) ? value : null;
}
function sameDigest(a, b) { return a.replace(/^sha256:/, '').toLowerCase() === b.replace(/^sha256:/, '').toLowerCase(); }

function validateOptions(manifest, options) {
  const { model, baseUrl, maxRequests, timeoutMs, maxResponseBytes, maxCaptureBytes, signal, onRecord } = options;
  if (typeof model !== 'string' || !model.trim() || model !== model.trim() || model.length > 200 || /[\s\x00-\x1f]/.test(model)) fail('INVALID_MODEL', 'An exact installed model name is required.');
  if (cloudName(model)) fail('REMOTE_MODEL_DISABLED', 'Cloud model names are disabled for this local experiment.');
  if (typeof baseUrl !== 'string' || !/^http:\/\/(127\.0\.0\.1|\[::1\])(?::([0-9]{1,5}))?\/?$/.test(baseUrl)) fail('INVALID_BASE_URL', 'Use a literal HTTP loopback origin: 127.0.0.1 or [::1], without credentials or a path.');
  const url = new URL(baseUrl);
  if (url.port && (Number(url.port) < 1 || Number(url.port) > 65535)) fail('INVALID_BASE_URL', 'The loopback port must be between 1 and 65535.');
  if (!Number.isSafeInteger(maxRequests) || maxRequests < 1 || maxRequests > MAX_REQUESTS) fail('INVALID_REQUEST_CAP', `maxRequests must be an integer from 1 to ${MAX_REQUESTS}.`);
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > MAX_TIMEOUT_MS) fail('INVALID_TIMEOUT', `timeoutMs must be between 1 and ${MAX_TIMEOUT_MS}.`);
  if (!Number.isSafeInteger(maxResponseBytes) || maxResponseBytes < 1 || maxResponseBytes > MAX_BYTES) fail('INVALID_RESPONSE_CAP', `maxResponseBytes must be between 1 and ${MAX_BYTES}.`);
  if (!Number.isSafeInteger(maxCaptureBytes) || maxCaptureBytes < 1024 * 1024 || maxCaptureBytes > MAX_CAPTURE_BYTES) fail('INVALID_CAPTURE_CAP', 'maxCaptureBytes must be between 1 and 24 MiB.');
  if (onRecord !== undefined && typeof onRecord !== 'function') fail('INVALID_CALLBACK', 'onRecord must be a function.');
  if (signal !== undefined && !(signal instanceof AbortSignal)) fail('INVALID_SIGNAL', 'signal must be an AbortSignal.');
  if (!manifest || !Array.isArray(manifest.jobs) || manifest.jobs.length < 1 || manifest.jobs.length > maxRequests) fail('REQUEST_CAP_EXCEEDED', 'The complete manifest must fit within maxRequests before collection starts.');
  if ((manifest.jobs.length + 1) * RESERVED_RECORD_BYTES > maxCaptureBytes) fail('INVALID_CAPTURE_CAP', 'Capture budget cannot reserve metadata for every requested job.');
  const settings = manifest.settings;
  if (!settings || !Number.isSafeInteger(settings.num_predict) || settings.num_predict < 1 || settings.num_predict > 1024 || !Number.isFinite(settings.temperature) || settings.temperature < 0 || settings.temperature > 2) fail('INVALID_SETTINGS', 'num_predict must be 1..1024; temperature must be finite and 0..2.');
  for (const job of manifest.jobs) {
    if (typeof job.prompt !== 'string' || Buffer.byteLength(job.prompt, 'utf8') > 16384) fail('PROMPT_TOO_LARGE', 'Every prompt must fit within 16 KiB.');
    if (job.imageBase64 !== undefined && job.imageBase64 !== null) {
      if (manifest.mode === 'text_model') fail('TEXT_MODE_IMAGE', 'Text mode cannot include image inputs.');
      const b64 = job.imageBase64;
      if (typeof b64 !== 'string' || b64.length > Math.ceil(MAX_BYTES / 3) * 4) fail('IMAGE_TOO_LARGE', 'Every decoded image must fit within 10 MiB.');
      if (!b64 || b64.length % 4 !== 0 || !/^[A-Za-z0-9+/]*={0,2}$/.test(b64)) fail('INVALID_IMAGE', 'Image data must be canonical base64.');
      const bytes = Buffer.from(b64, 'base64');
      if (bytes.length > MAX_BYTES) fail('IMAGE_TOO_LARGE', 'Every decoded image must fit within 10 MiB.');
      if (bytes.toString('base64') !== b64) fail('INVALID_IMAGE', 'Image data must be canonical base64.');
    }
  }
  validateManifest(manifest);
  return url;
}

// No automatic redirects, retries, proxies, pulls, or network activity on import.
function requestJson(origin, path, { body, timeoutMs, maxResponseBytes, signal }) {
  return new Promise((resolve, reject) => {
    let done = false;
    let request;
    let timer;
    const settle = (error, value) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      signal?.removeEventListener('abort', abort);
      if (error) {
        request?.destroy();
        reject(error);
      } else resolve(value);
    };
    const abort = () => settle(new CollectorError('ABORTED', 'Collection was canceled.'));
    if (signal?.aborted) return abort();
    const payload = body === undefined ? undefined : JSON.stringify(body);
    request = http.request({
      protocol: 'http:', hostname: origin.hostname.replace(/^\[|\]$/g, ''),
      port: origin.port || 80, path, method: payload === undefined ? 'GET' : 'POST',
      agent: false,
      headers: payload === undefined ? { accept: 'application/json' } : {
        accept: 'application/json', 'content-type': 'application/json', 'content-length': Buffer.byteLength(payload)
      }
    }, (response) => {
      if (response.statusCode >= 300 && response.statusCode < 400) {
        response.destroy();
        return settle(new CollectorError('REDIRECT_DISABLED', 'Ollama redirects are disabled.'));
      }
      const declared = response.headers['content-length'];
      if (declared && Number(declared) > maxResponseBytes) {
        response.destroy();
        return settle(new CollectorError('RESPONSE_TOO_LARGE', 'Ollama response exceeded the byte limit.'));
      }
      let size = 0;
      const chunks = [];
      response.on('data', chunk => {
        size += chunk.length;
        if (size > maxResponseBytes) {
          response.destroy();
          settle(new CollectorError('RESPONSE_TOO_LARGE', 'Ollama response exceeded the byte limit.'));
        } else chunks.push(chunk);
      });
      response.on('error', error => settle(new CollectorError('RESPONSE_FAILED', error.message)));
      response.on('end', () => {
        if (done) return;
        const text = Buffer.concat(chunks).toString('utf8');
        let data;
        try { data = JSON.parse(text); }
        catch { return settle(new CollectorError('INVALID_JSON', 'Ollama returned invalid JSON.', text)); }
        if (response.statusCode < 200 || response.statusCode >= 300) return settle(new CollectorError('HTTP_ERROR', `Ollama returned HTTP ${response.statusCode}.`, data));
        if (!data || Array.isArray(data) || typeof data !== 'object') return settle(new CollectorError('INVALID_RESPONSE', 'Ollama returned a non-object response.', data));
        if (data.error) return settle(new CollectorError('OLLAMA_ERROR', String(data.error), data));
        settle(null, data);
      });
    });
    request.on('error', error => settle(new CollectorError('CONNECTION_FAILED', error.message)));
    signal?.addEventListener('abort', abort, { once: true });
    timer = setTimeout(() => settle(new CollectorError('TIMEOUT', `Ollama request exceeded ${timeoutMs} ms.`)), timeoutMs);
    request.end(payload);
  });
}

/**
 * Explicit opt-in experimental adapter; importing this module makes no requests.
 * maxRequests caps generation requests (1..2000), with two additional metadata
 * requests. The complete matrix must fit. No pulls or native ARCHi transport.
 * onRecord is awaited once per job for durable caller-owned checkpoints; callback
 * failure stops collection. Per-request timeout <=120s and responses <=10MiB.
 * JSONL capture is capped at 24MiB including reserved error/skip metadata, below
 * the CLI's 32MiB input ceiling. An oversized next record becomes an explicit
 * capture error and subsequent generation requests are skipped, never truncated
 * into an apparently complete model response.
 * The installed digest is a preflight observation, not an immutable binding:
 * keep the local model tag unchanged while collecting.
 */
export async function collectOllama(manifest, {
  model, baseUrl = 'http://127.0.0.1:11434', maxRequests = 128,
  signal, onRecord, timeoutMs = MAX_TIMEOUT_MS, maxResponseBytes = MAX_BYTES,
  maxCaptureBytes = MAX_CAPTURE_BYTES
} = {}) {
  const origin = validateOptions(manifest, { model, baseUrl, maxRequests, signal, onRecord, timeoutMs, maxResponseBytes, maxCaptureBytes });
  const snapshot = structuredClone(manifest);
  const records = [];
  let capturedBytes = 0;
  let captureStopped = false;
  let modelDigest = null;
  const preflight = { status: 'pending', model, modelDigest: null, mode: snapshot.mode, collector: COLLECTOR, native_gate_verified: false };
  const request = (path, body) => requestJson(origin, path, { body, signal, timeoutMs, maxResponseBytes });
  const baseRecord = job => ({
    id: job.id, manifestSha256: snapshot.manifestSha256,
    taskId: job.taskId, condition: job.condition, promptStyle: job.promptStyle, replicate: job.replicate,
    evidenceOrigin: 'local_model', collector: COLLECTOR, model, modelDigest,
    modelDigestSource: 'ollama-tags-preflight', mode: snapshot.mode,
    native_gate_verified: false, rawResponse: null, inputTokens: null, outputTokens: null, latencyMs: 0
  });
  const emit = async record => {
    const size = Buffer.byteLength(JSON.stringify(record) + '\n');
    if (capturedBytes + size > maxCaptureBytes) fail('CAPTURE_BYTE_LIMIT', 'Capture metadata exceeded the reserved byte budget.');
    capturedBytes += size;
    records.push(record);
    if (onRecord) await onRecord(structuredClone(record));
  };
  const stopAll = async (status, reason, error = null) => {
    preflight.status = status;
    preflight.reason = reason;
    if (error) preflight.error = errorDetails(error);
    for (const job of snapshot.jobs) await emit({ ...baseRecord(job), status,
      ...(status === 'skipped' ? { skipReason: reason } : { error: errorDetails(error) }) });
    return { records, preflight };
  };
  if (signal?.aborted) return stopAll('skipped', 'ABORTED');
  let tags;
  let show;
  try {
    tags = await request('/api/tags');
    if (!Array.isArray(tags.models)) fail('INVALID_TAGS', 'Ollama tags response has no model list.');
    const matches = tags.models.filter(item => item && (item.name === model || item.model === model));
    if (matches.length !== 1) return stopAll('skipped', 'EXACT_INSTALLED_MODEL_NOT_FOUND');
    const selected = matches[0];
    if ((selected.name && selected.name !== model) || (selected.model && selected.model !== model)) return stopAll('skipped', 'MODEL_IDENTITY_MISMATCH');
    if (hasRemoteMetadata(selected) || cloudName(selected.name || selected.model || '')) return stopAll('skipped', 'REMOTE_MODEL_DISABLED');
    modelDigest = installedDigest(selected.digest);
    if (!modelDigest) return stopAll('skipped', 'INSTALLED_DIGEST_UNAVAILABLE');
    preflight.modelDigest = modelDigest;
    show = await request('/api/show', { model });
    if (hasRemoteMetadata(show)) return stopAll('skipped', 'REMOTE_MODEL_DISABLED');
    if (show.digest !== undefined && (!installedDigest(show.digest) || !sameDigest(show.digest, modelDigest))) return stopAll('skipped', 'MODEL_DIGEST_MISMATCH');
    if (snapshot.mode === 'vlm' && (!Array.isArray(show.capabilities) || !show.capabilities.includes('vision'))) return stopAll('skipped', 'VISION_CAPABILITY_REQUIRED');
  } catch (error) {
    return stopAll('error', error.code || 'PREFLIGHT_FAILED', error);
  }
  preflight.status = 'ready';
  preflight.capabilities = Array.isArray(show.capabilities) ? show.capabilities : [];
  for (const [index, job] of snapshot.jobs.entries()) {
    if (captureStopped) {
      await emit({ ...baseRecord(job), status: 'skipped', skipReason: 'CAPTURE_BYTE_LIMIT' });
      continue;
    }
    if (signal?.aborted) {
      await emit({ ...baseRecord(job), status: 'skipped', skipReason: 'ABORTED' });
      continue;
    }
    const started = performance.now();
    let record;
    try {
      const message = { role: 'user', content: job.prompt };
      if (snapshot.mode === 'vlm' && job.imageBase64) message.images = [job.imageBase64];
      const rawResponse = await request('/api/chat', {
        model, stream: false, messages: [message], options: {
          temperature: snapshot.settings.temperature, num_predict: snapshot.settings.num_predict,
          seed: (snapshot.seed + job.replicate) >>> 0
        }
      });
      if (hasRemoteMetadata(rawResponse)) throw new CollectorError('REMOTE_MODEL_DISABLED', 'Response reports remote model execution.', rawResponse);
      if (rawResponse.model !== model) throw new CollectorError('MODEL_IDENTITY_MISMATCH', 'Response model differs from the requested installed model.', rawResponse);
      if (rawResponse.done !== true || typeof rawResponse.message?.content !== 'string') throw new CollectorError('INCOMPLETE_RESPONSE', 'A completed chat response with message.content is required.', rawResponse);
      record = { ...baseRecord(job), status: 'completed', response: rawResponse.message.content,
        rawResponse, inputTokens: counter(rawResponse.prompt_eval_count), outputTokens: counter(rawResponse.eval_count),
        latencyMs: Math.round(performance.now() - started) };
    } catch (error) {
      record = { ...baseRecord(job), status: 'error', error: errorDetails(error),
        rawResponse: error.rawResponse ?? null,
        inputTokens: counter(error.rawResponse?.prompt_eval_count),
        outputTokens: counter(error.rawResponse?.eval_count),
        latencyMs: Math.round(performance.now() - started) };
    }
    const recordBytes = Buffer.byteLength(JSON.stringify(record) + '\n');
    const remainingMetadata = (snapshot.jobs.length - index - 1) * RESERVED_RECORD_BYTES;
    if (capturedBytes + recordBytes + remainingMetadata > maxCaptureBytes) {
      captureStopped = true;
      record = { ...baseRecord(job), status: 'error',
        error: { code: 'CAPTURE_BYTE_LIMIT', message: 'Response was not retained because it would exceed the aggregate capture budget; remaining requests were skipped.' },
        inputTokens: record.inputTokens, outputTokens: record.outputTokens, latencyMs: record.latencyMs,
        discardedRecordBytes: recordBytes };
    }
    await emit(record);
  }
  return { records, preflight };
}
