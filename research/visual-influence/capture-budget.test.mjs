import assert from "node:assert/strict";
import http from "node:http";
import test from "node:test";
import { createManifest } from "./experiment.mjs";
import { collectOllama } from "./ollama.mjs";

async function fixture(t) {
  const calls = [];
  const server = http.createServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    calls.push(request.url);
    const body = request.url === "/api/tags"
      ? { models: [{ name: "fixture:local", model: "fixture:local", digest: "a".repeat(64) }] }
      : request.url === "/api/show" ? { capabilities: ["completion"] }
        : { model: "fixture:local", done: true, message: { content: "x".repeat(200 * 1024) },
            prompt_eval_count: 0, eval_count: 1024 };
    response.writeHead(200, { "content-type": "application/json" });
    response.end(JSON.stringify(body));
  });
  await new Promise((resolve, reject) => { server.once("error", reject); server.listen(0, "127.0.0.1", resolve); });
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  return { calls, baseUrl: `http://127.0.0.1:${server.address().port}` };
}

test("aggregate capture budget checkpoints prior records and explicitly stops oversized collection", async t => {
  const server = await fixture(t), manifest = createManifest({ replicates: 1 });
  const checkpoints = [];
  const { records } = await collectOllama(manifest, { model: "fixture:local", baseUrl: server.baseUrl,
    maxRequests: manifest.jobs.length, maxCaptureBytes: 1024 * 1024, timeoutMs: 1000,
    onRecord(record) { checkpoints.push(record); } });
  assert.deepEqual(records, checkpoints);
  assert.equal(records.length, manifest.jobs.length);
  assert.equal(records.filter(row => row.status === "completed").length, 2);
  const failed = records.filter(row => row.status === "error");
  assert.equal(failed.length, 1);
  assert.equal(failed[0].error.code, "CAPTURE_BYTE_LIMIT");
  assert.equal(failed[0].rawResponse, null);
  assert.equal(failed[0].response, undefined);
  assert.equal(failed[0].inputTokens, 0);
  assert.equal(failed[0].outputTokens, 1024);
  assert.ok(failed[0].discardedRecordBytes > 400 * 1024);
  assert.ok(records.slice(3).every(row => row.status === "skipped" && row.skipReason === "CAPTURE_BYTE_LIMIT"));
  assert.equal(server.calls.filter(route => route === "/api/chat").length, 3);
  assert.ok(Buffer.byteLength(records.map(row => JSON.stringify(row) + "\n").join("")) <= 1024 * 1024);
});

test("capture cap must reserve bounded metadata before any request", async t => {
  const server = await fixture(t);
  for (const maxCaptureBytes of [0, Infinity, 25 * 1024 * 1024]) {
    await assert.rejects(collectOllama(createManifest({ replicates: 1 }), {
      model: "fixture:local", baseUrl: server.baseUrl, maxCaptureBytes
    }), { code: "INVALID_CAPTURE_CAP" });
  }
  await assert.rejects(collectOllama(createManifest({ replicates: 50 }), {
    model: "fixture:local", baseUrl: server.baseUrl, maxRequests: 2000, maxCaptureBytes: 1024 * 1024
  }), { code: "INVALID_CAPTURE_CAP" });
  assert.deepEqual(server.calls, []);
});
