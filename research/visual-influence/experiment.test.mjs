import assert from "node:assert/strict";
import { inflateSync } from "node:zlib";
import test from "node:test";
import {
  createManifest, digestManifest, validateManifest, symbolPixels, symbolPng,
  classifyResponses, summarizeRecords, fraction,
} from "./experiment.mjs";

const recursive = "def inorder(root):\n    if root is None: return []\n    return inorder(root.left) + [root.val] + inorder(root.right)\n";
const iterative = "def inorder(root):\n    result, stack = [], []\n    while root or stack:\n        while root:\n            stack.append(root)\n            root = root.left\n        root = stack.pop()\n        result.append(root.val)\n        root = root.right\n    return result\n";

test("paired conditions preserve wording, balance option order, and reproduce randomized order", () => {
  const first = createManifest(), second = createManifest();
  assert.deepEqual(first, second);
  assert.equal(first.jobs.length, 40);
  assert.equal(new Set(first.jobs.map(job => job.id)).size, 40);
  assert.deepEqual(new Set(first.jobs.map(job => job.split)), new Set(["development", "held_out"]));
  for (const style of ["silent", "explicit"]) for (const replicate of [0, 1]) {
    const jobs = first.jobs.filter(job => job.taskId === "inorder-development" && job.promptStyle === style && job.replicate === replicate);
    const baseline = jobs.find(job => job.condition === "none");
    for (const job of jobs) assert.ok(job.prompt.endsWith(baseline.prompt));
    assert.match(baseline.prompt, replicate ? /iterative or recursive/ : /recursive or iterative/);
  }
  assert.notDeepEqual(first.jobs.map(job => job.id), createManifest({ seed: 18 }).jobs.map(job => job.id));
});

test("text mode carries no image bytes and rejects a forged image-bearing manifest", () => {
  const manifest = createManifest();
  assert.ok(manifest.jobs.every(job => !("imageBase64" in job)));
  manifest.jobs[0].imageBase64 = "YWJj";
  manifest.jobs[0].imageSha256 = "fake";
  manifest.manifestSha256 = digestManifest(manifest);
  assert.throws(() => validateManifest(manifest), /Text mode/);
});

test("image control is a decodable 400x400 RGB PNG with the intended pixel bytes", () => {
  const png = symbolPng("red_heart"), pixels = symbolPixels("red_heart");
  assert.deepEqual(png.subarray(0, 8), Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  assert.equal(png.readUInt32BE(16), 400);
  assert.equal(png.readUInt32BE(20), 400);
  const blocks = [];
  for (let offset = 8; offset < png.length;) {
    const length = png.readUInt32BE(offset), type = png.toString("ascii", offset + 4, offset + 8);
    if (type === "IDAT") blocks.push(png.subarray(offset + 8, offset + 8 + length));
    offset += length + 12;
  }
  const raw = inflateSync(Buffer.concat(blocks));
  assert.equal(raw.length, 400 * 1201);
  for (let y = 0; y < 400; y++) {
    assert.equal(raw[y * 1201], 0);
    assert.deepEqual(raw.subarray(y * 1201 + 1, (y + 1) * 1201), pixels.data.subarray(y * 1200, (y + 1) * 1200));
  }
  assert.deepEqual([...pixels.data.subarray((200 * 400 + 200) * 3, (200 * 400 + 200) * 3 + 3)], [220, 30, 45]);
});

test("shuffled control preserves the exact color histogram while destroying spatial arrangement", () => {
  const heart = symbolPixels("red_heart").data, mixed = symbolPixels("shuffled_heart").data;
  function histogram(data) {
    const map = new Map();
    for (let i = 0; i < data.length; i += 3) {
      const key = data.subarray(i, i + 3).toString("hex");
      map.set(key, (map.get(key) ?? 0) + 1);
    }
    return [...map.entries()].sort();
  }
  assert.notDeepEqual(heart, mixed);
  assert.deepEqual(histogram(heart), histogram(mixed));
  assert.deepEqual(mixed, symbolPixels("shuffled_heart").data);
  assert.ok(symbolPixels("blank").data.every(value => value === 255));
});

test("VLM matrix is distinct and validates byte digests; tampering is rejected", () => {
  const manifest = createManifest({ mode: "vlm" });
  assert.equal(manifest.jobs.length, 48);
  assert.equal(validateManifest(manifest), manifest);
  const job = manifest.jobs.find(entry => entry.imageBase64);
  job.imageBase64 = "YWJj";
  assert.throws(() => validateManifest(manifest), /Manifest digest/);
  manifest.manifestSha256 = digestManifest(manifest);
  assert.throws(() => validateManifest(manifest), /Image digest/);
});

test("strategy classification follows reachable helper cycles instead of trusting prose or labels", () => {
  const items = [
    recursive, iterative,
    "def inorder(root):\n    def visit(node):\n        if node is None: return []\n        return visit(node.left) + [node.val] + visit(node.right)\n    return visit(root)\n",
    "def unused(x):\n    return unused(x)\ndef inorder(root):\n    result = []\n    for x in range(3): result.append(x)\n    return result\n",
    "# I used recursion\ndef inorder(root):\n    return []\n",
    "def inorder(root):\n    return eval('danger')\n",
    "import os\nos.remove('/must-never-be-executed')\n" + iterative,
    "not Python code",
  ];
  assert.deepEqual(classifyResponses(items.map(code => ({ code, entry: "inorder" }))).map(row => row.strategy),
    ["recursive", "iterative", "recursive", "iterative", "unknown", "unknown", "unknown", "unknown"]);
});

test("classifier accepts one fenced response but keeps refusals and unsupported dynamic code unknown", () => {
  const values = classifyResponses([
    { code: `\`\`\`python\n${recursive}\`\`\``, entry: "inorder" },
    { code: "I cannot complete that task.", entry: "inorder" },
    { code: "def inorder(root):\n    return root.traverse()", entry: "inorder" },
    { code: recursive, entry: "other" },
    { code: "x".repeat(16385), entry: "inorder" },
  ]);
  assert.deepEqual(values.map(row => row.strategy), ["recursive", "unknown", "unknown", "unknown", "unknown"]);
});

test("top-level effects and dynamic defaults are never labeled as ordinary algorithm choices", () => {
  const values = classifyResponses([
    { code: "danger()\n" + iterative, entry: "inorder" },
    { code: "def inorder(root=danger()):\n    for n in range(3): pass\n    return []", entry: "inorder" },
    { code: "def inorder(root: danger()):\n    for n in range(3): pass\n    return []", entry: "inorder" },
    { code: iterative.replace("inorder(root)", "inorder(root=None)"), entry: "inorder" },
  ]);
  assert.deepEqual(values.map(row => row.strategy), ["unknown", "unknown", "unknown", "iterative"]);
});

function record(manifest, job, extras = {}) {
  return { id: job.id, manifestSha256: manifest.manifestSha256, status: "completed", response: iterative,
    evidenceOrigin: "synthetic_test", collector: "unit-test-fixture", mode: manifest.mode,
    model: "fixture-model", modelDigest: "fixture-digest",
    inputTokens: 0, outputTokens: null, ...extras };
}

test("no observations yields null rates and pending native/admission conclusions", () => {
  const report = summarizeRecords(createManifest(), []);
  assert.equal(report.completed, 0);
  assert.equal(report.missing, 40);
  assert.equal(report.inputTokens.completeTotal, null);
  assert.equal(report.admissionOutcomes, null);
  assert.equal(report.boundary.nativeGateVerified, false);
  assert.ok(report.conditions.every(row => row.recursionAmongClassified.value === null && row.steeringDelta === null));
  assert.equal(fraction(0, 0).value, null);
});

test("complete strata yield descriptive deltas; errors, unknown code and missing draws suppress deltas", () => {
  const manifest = createManifest();
  const jobs = manifest.jobs.filter(job => job.taskId === "inorder-development" && job.promptStyle === "silent");
  const records = jobs.map(job => record(manifest, job, { response: job.condition === "unicode_heart" ? recursive : iterative }));
  let report = summarizeRecords(manifest, records);
  let heart = report.conditions.find(row => row.taskId === "inorder-development" && row.promptStyle === "silent" && row.condition === "unicode_heart");
  assert.equal(heart.steeringDelta, 1);
  assert.equal(report.inputTokens.completeTotal, 0);
  assert.equal(report.outputTokens.completeTotal, null);
  const index = records.findIndex(row => jobs.find(job => job.id === row.id).condition === "none");
  records[index] = { ...records[index], status: "error", response: undefined };
  report = summarizeRecords(manifest, records);
  heart = report.conditions.find(row => row.taskId === "inorder-development" && row.promptStyle === "silent" && row.condition === "unicode_heart");
  assert.equal(heart.steeringDelta, null);
  assert.equal(report.error, 1);
  records[index] = { ...records[index], status: "completed", response: "# unknown strategy" };
  assert.equal(summarizeRecords(manifest, records).conditions.find(row => row.condition === "none" && row.taskId === "inorder-development" && row.promptStyle === "silent").unknown, 1);
});

test("records cannot be counted twice or reassigned to another input manifest", () => {
  const manifest = createManifest(), first = record(manifest, manifest.jobs[0]);
  assert.throws(() => summarizeRecords(manifest, [first, first]), /duplicate/);
  assert.throws(() => summarizeRecords(manifest, [{ ...first, manifestSha256: "wrong" }]), /different manifest/);
  assert.throws(() => summarizeRecords(manifest, [{ ...first, id: "unknown" }]), /Unknown/);
});

test("known tokens and latency survive failed responses without inventing missing counts", () => {
  const manifest = createManifest(), [a, b] = manifest.jobs;
  const records = [record(manifest, a, { status: "error", inputTokens: 12, outputTokens: 0, latencyMs: 30 }),
    record(manifest, b, { inputTokens: null, outputTokens: 5, latencyMs: 0 })];
  const report = summarizeRecords(manifest, records);
  assert.deepEqual(report.inputTokens, { knownTotal: 12, knownRecords: 1, unknownRecords: 1, completeTotal: null });
  assert.deepEqual(report.outputTokens, { knownTotal: 5, knownRecords: 2, unknownRecords: 0, completeTotal: 5 });
  assert.equal(report.timing.totalObservedLatencyMs, 30);
  assert.equal(report.timing.meanCompletedLatencyMs, 0);
  assert.equal(report.timing.p95CompletedLatencyMs, 0);
});

test("model identity and fixture provenance cannot be mixed into apparent model findings", () => {
  const manifest = createManifest(), [a, b] = manifest.jobs;
  const first = record(manifest, a), second = record(manifest, b);
  for (const changed of [{ model: "different" }, { collector: "different" }, { evidenceOrigin: "local_model" }]) {
    assert.throws(() => summarizeRecords(manifest, [first, { ...second, ...changed }]), /Mixed/);
  }
  assert.throws(() => summarizeRecords(manifest, [first, { ...second, modelDigest: "different" }]), /Mixed model digests/);
  assert.throws(() => summarizeRecords(manifest, [{ ...first, evidenceOrigin: undefined }]), /evidence origin/);
  assert.throws(() => summarizeRecords(manifest, [{ ...first, modelDigest: null }]), /model digest/);
  const report = summarizeRecords(manifest, [first]);
  assert.equal(report.evidenceKind, "synthetic_test");
  assert.equal(report.provenance.model, "fixture-model");
});

test("rehashing cannot disguise incomplete pairing, missing image payloads or changed settings", () => {
  const missingDraws = createManifest();
  missingDraws.jobs = missingDraws.jobs.filter(job => job.condition === "none" ? job.replicate === 0 : job.replicate === 1);
  missingDraws.manifestSha256 = digestManifest(missingDraws);
  assert.throws(() => validateManifest(missingDraws), /experiment matrix/);
  const missingImage = createManifest({ mode: "vlm" });
  const heart = missingImage.jobs.find(job => job.condition === "red_heart");
  delete heart.imageBase64; delete heart.imageSha256;
  missingImage.manifestSha256 = digestManifest(missingImage);
  assert.throws(() => validateManifest(missingImage), /experiment matrix/);
  const changedSettings = createManifest();
  changedSettings.settings.num_predict = 1000000;
  changedSettings.manifestSha256 = digestManifest(changedSettings);
  assert.throws(() => validateManifest(changedSettings), /experiment matrix/);
});

test("bounded matrix construction rejects accidental unbounded model work", () => {
  for (const replicates of [0, -1, 51, Infinity, NaN, 1.2]) assert.throws(() => createManifest({ replicates }), /replicates/);
  assert.throws(() => createManifest({ seed: -1 }), /uint32/);
  assert.throws(() => createManifest({ mode: "cloud" }), /mode/);
});
