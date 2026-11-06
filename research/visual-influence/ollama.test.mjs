import assert from "node:assert/strict";
import http from "node:http";
import test from "node:test";
import { collectOllama } from "./ollama.mjs";
import { createManifest } from "./experiment.mjs";

const MODEL = "fixture:local";
const DIGEST = "a".repeat(64);
const tags = () => ({ models: [{ name: MODEL, model: MODEL, digest: DIGEST }] });
const answer = () => ({ model: MODEL, done: true, message: { role: "assistant", content: "def inorder(root):\n    return []\n" },
  prompt_eval_count: 0, eval_count: 7 });

// Ephemeral loopback HTTP fixtures only; no installed model or inference.
async function fixture(t, handler) {
  const calls = [];
  const server = http.createServer(async (request, response) => {
    try {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const text = Buffer.concat(chunks).toString("utf8");
      const call = { path: request.url, method: request.method, body: text ? JSON.parse(text) : undefined };
      calls.push(call);
      const reply = handler?.(call, calls) ?? { body: call.path === "/api/tags" ? tags()
        : call.path === "/api/show" ? { capabilities: ["completion", "vision"] } : answer() };
      if (reply.hang) return;
      response.writeHead(reply.status ?? 200, { "content-type": "application/json", ...reply.headers });
      response.end(reply.raw ?? JSON.stringify(reply.body));
    } catch (error) { response.destroy(error); }
  });
  await new Promise((resolve, reject) => { server.once("error", reject); server.listen(0, "127.0.0.1", resolve); });
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  return { calls, baseUrl: `http://127.0.0.1:${server.address().port}` };
}

function options(server, extra = {}) {
  return { model: MODEL, baseUrl: server.baseUrl, maxRequests: 40, timeoutMs: 1000, ...extra };
}

test("text collection uses exact installed identity, bounded settings, checkpoints and native counters", async t => {
  const server = await fixture(t), manifest = createManifest({ replicates: 1 });
  const checkpoints = [];
  const result = await collectOllama(manifest, options(server, { onRecord(record) {
    checkpoints.push(record); record.condition = "callback-mutated-copy";
  } }));
  assert.equal(result.records.length, 20);
  assert.equal(result.preflight.status, "ready");
  assert.equal(result.preflight.modelDigest, DIGEST);
  assert.equal(checkpoints.length, 20);
  assert.ok(result.records.every(row => row.status === "completed" && row.condition !== "callback-mutated-copy"
    && row.modelDigest === DIGEST && row.inputTokens === 0 && row.outputTokens === 7 && row.latencyMs >= 0));
  assert.equal(server.calls.length, 22);
  assert.deepEqual(server.calls.slice(0, 2).map(call => [call.path, call.method]), [["/api/tags", "GET"], ["/api/show", "POST"]]);
  for (const call of server.calls.slice(2)) {
    assert.equal(call.path, "/api/chat");
    assert.equal(call.body.model, MODEL);
    assert.equal(call.body.stream, false);
    assert.equal(call.body.options.num_predict, 1024);
    assert.equal(call.body.options.temperature, 1);
    assert.equal(call.body.options.seed, 17);
    assert.ok(call.body.messages.every(message => message.images === undefined));
  }
});

test("unsafe origins, cloud names and insufficient request caps fail without network activity", async t => {
  const server = await fixture(t), manifest = createManifest({ replicates: 1 });
  for (const baseUrl of ["https://127.0.0.1:11434", "http://localhost:11434", "http://127.1:11434",
    "http://127.0.0.1@remote.example", "http://127.0.0.1:11434/api", "http://[::1]:0"]) {
    await assert.rejects(collectOllama(manifest, options(server, { baseUrl })));
  }
  for (const extra of [{ model: "fixture:cloud" }, { maxRequests: 19 }, { maxRequests: 2001 },
    { timeoutMs: 120001 }, { maxResponseBytes: 11 * 1024 * 1024 }]) {
    await assert.rejects(collectOllama(manifest, options(server, extra)));
  }
  assert.equal(server.calls.length, 0);
});

test("preflight skips missing exact models, missing digests and reported remote execution", async t => {
  const variants = [
    { list: { models: [] }, reason: "EXACT_INSTALLED_MODEL_NOT_FOUND", count: 1 },
    { list: { models: [{ name: MODEL, model: MODEL }] }, reason: "INSTALLED_DIGEST_UNAVAILABLE", count: 1 },
    { list: { models: [{ ...tags().models[0], remote_host: "https://remote.example" }] }, reason: "REMOTE_MODEL_DISABLED", count: 1 },
    { show: { capabilities: ["completion"], remote_model: "upstream" }, reason: "REMOTE_MODEL_DISABLED", count: 2 },
    { show: { capabilities: ["completion"], digest: "b".repeat(64) }, reason: "MODEL_DIGEST_MISMATCH", count: 2 }
  ];
  for (const variant of variants) {
    const server = await fixture(t, call => call.path === "/api/tags" ? { body: variant.list ?? tags() }
      : { body: variant.show });
    const result = await collectOllama(createManifest({ replicates: 1 }), options(server));
    assert.ok(result.records.every(row => row.status === "skipped" && row.skipReason === variant.reason));
    assert.equal(server.calls.length, variant.count);
  }
});

test("vision capability is required for the whole VLM matrix and only image conditions carry bytes", async t => {
  const manifest = createManifest({ mode: "vlm", replicates: 1 });
  const unsupported = await fixture(t, call => call.path === "/api/show" ? { body: { capabilities: ["completion"] } } : undefined);
  const skipped = await collectOllama(manifest, options(unsupported));
  assert.ok(skipped.records.every(row => row.status === "skipped" && row.skipReason === "VISION_CAPABILITY_REQUIRED"));
  assert.equal(unsupported.calls.length, 2);

  const supported = await fixture(t);
  const complete = await collectOllama(manifest, options(supported));
  assert.ok(complete.records.every(row => row.status === "completed"));
  for (const [index, call] of supported.calls.slice(2).entries()) {
    const expected = manifest.jobs[index].imageBase64;
    assert.deepEqual(call.body.messages[0].images, expected ? [expected] : undefined);
  }
});

test("error responses preserve known zero tokens, raw evidence and failure categories without retries", async t => {
  let generation = 0;
  const server = await fixture(t, call => {
    if (call.path !== "/api/chat") return;
    const index = generation++;
    if (index === 0) return { body: { ...answer(), done: false, prompt_eval_count: 11, eval_count: 0 } };
    if (index === 1) return { status: 500, body: { error: "fixture failure", prompt_eval_count: 0, eval_count: 3 } };
    if (index === 2) return { body: { ...answer(), model: "different:local" } };
    if (index === 3) return { raw: "{invalid-json" };
    if (index === 4) return { body: { model: MODEL, done: true, message: { content: "pass" } } };
  });
  const { records } = await collectOllama(createManifest({ replicates: 1 }), options(server));
  assert.deepEqual(records.slice(0, 4).map(row => row.error.code), ["INCOMPLETE_RESPONSE", "HTTP_ERROR", "MODEL_IDENTITY_MISMATCH", "INVALID_JSON"]);
  assert.equal(records[0].inputTokens, 11);
  assert.equal(records[0].outputTokens, 0);
  assert.equal(records[1].inputTokens, 0);
  assert.equal(records[1].outputTokens, 3);
  assert.equal(records[1].rawResponse.error, "fixture failure");
  assert.equal(records[3].rawResponse, "{invalid-json");
  assert.equal(records[4].inputTokens, null);
  assert.equal(records[4].outputTokens, null);
  assert.equal(generation, 20);
});

test("redirects, oversized responses and stalled preflight remain explicit errors", async t => {
  const variants = [
    { reply: { status: 302, headers: { location: "http://remote.example/redirect" }, body: {} }, code: "REDIRECT_DISABLED" },
    { reply: { raw: "x".repeat(2048) }, limits: { maxResponseBytes: 1024 }, code: "RESPONSE_TOO_LARGE" },
    { reply: { hang: true }, limits: { timeoutMs: 30 }, code: "TIMEOUT" }
  ];
  for (const variant of variants) {
    const server = await fixture(t, () => variant.reply);
    const { records } = await collectOllama(createManifest({ replicates: 1 }), options(server, variant.limits));
    assert.equal(server.calls.length, 1);
    assert.ok(records.every(row => row.status === "error" && row.error.code === variant.code));
  }
});

test("cancellation skips remaining jobs and checkpoint failure stops collection", async t => {
  const manifest = createManifest({ replicates: 1 }), controller = new AbortController();
  const server = await fixture(t);
  const result = await collectOllama(manifest, options(server, { signal: controller.signal,
    onRecord(record) { if (record.status === "completed") controller.abort(); } }));
  assert.equal(server.calls.length, 3);
  assert.equal(result.records[0].status, "completed");
  assert.ok(result.records.slice(1).every(row => row.status === "skipped" && row.skipReason === "ABORTED"));
  const failed = await fixture(t);
  await assert.rejects(collectOllama(manifest, options(failed, { onRecord() { throw new Error("checkpoint fixture failure"); } })), /checkpoint fixture failure/);
  assert.equal(failed.calls.length, 3);
});
