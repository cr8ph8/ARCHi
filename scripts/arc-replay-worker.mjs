import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { stripTypeScriptTypes } from "node:module";
import path from "node:path";
import { pathToFileURL } from "node:url";

// Only the pinned existing checker is executed. The fixture's solver identity
// remains supplied metadata; no solver module is loaded or run.
const [snapshot, execution] = process.argv.slice(2);
if (!snapshot || !execution) throw new Error("Expected snapshot and execution directories");
const configuration = JSON.parse(await readFile(path.join(snapshot, "scripts/arc-replay-config.json"), "utf8"));
const compiled = {};
for (const name of ["contract", "evaluate", "portable"]) {
  const source = await readFile(path.join(snapshot, `arc/src/${name}.ts`), "utf8");
  let text = stripTypeScriptTypes(source, { mode: "strip" });
  for (const [, specifier] of text.matchAll(/from\s+["']([^"']+)["']/g)) {
    assert.ok(["./contract", "./evaluate"].includes(specifier), "Unexpected checker dependency");
  }
  text = text.replace(/from (["'])\.\/(contract|evaluate)\1/g, 'from "./$2.mjs"');
  compiled[`${name}.mjs`] = `sha256:${createHash("sha256").update(text).digest("hex")}`;
  await writeFile(path.join(execution, `${name}.mjs`), text, { flag: "wx", mode: 0o600 });
}
const { canonicalJson, ARC_NO_WRITE_AUTHORITY } = await import(pathToFileURL(path.join(execution, "contract.mjs")));
const { inspectPortableArcBundle } = await import(pathToFileURL(path.join(execution, "portable.mjs")));
const { evaluateArcTask } = await import(pathToFileURL(path.join(execution, "evaluate.mjs")));
const input = await readFile(path.join(snapshot, configuration.input), "utf8");
const golden = JSON.parse(await readFile(path.join(snapshot, configuration.golden), "utf8"));
const { bundle, proposal } = inspectPortableArcBundle(input);
const receipts = bundle.evaluations.flatMap(({ task, predictions }) => evaluateArcTask({
  manifest: bundle.manifest, solver: bundle.solver, task, predictions,
}));

// Compare to the pre-existing oracle, not a value learned from this run.
assert.equal(proposal.proposalHash, golden.proposalHash, "Golden proposal mismatch");
assert.equal(proposal.manifestHash, golden.manifestHash, "Golden manifest mismatch");
assert.deepEqual(proposal.receiptHashes, golden.receiptHashes, "Golden receipt mismatch");
assert.deepEqual(receipts.map((receipt) => receipt.receiptHash).sort(), golden.receiptHashes);
assert.deepEqual(proposal.counts, golden.counts, "Golden counts mismatch");
assert.deepEqual(proposal.counts, configuration.expectedCounts, "Expected one correct and one incorrect prediction");
assert.equal(proposal.exactRate, golden.exactRate);
assert.equal(proposal.status, "proposed");
assert.equal(proposal.certification, "not-certified");
assert.equal(proposal.integration, "none");
assert.deepEqual(proposal.authority, ARC_NO_WRITE_AUTHORITY);
for (const receipt of receipts) {
  assert.equal(receipt.attestation, "unattested");
  assert.equal(receipt.reproducible, false);
  assert.deepEqual(receipt.authority, ARC_NO_WRITE_AUTHORITY);
}
const semantic = {
  schema: "archi-arc-checker-replay-output/v1",
  operation: configuration.operation,
  solverExecuted: false,
  inferenceCalls: 0,
  authority: ARC_NO_WRITE_AUTHORITY,
  proposal,
  receipts,
};
await writeFile(path.join(execution, "semantic.json"), `${canonicalJson(semantic)}\n`, { flag: "wx", mode: 0o600 });
await writeFile(path.join(execution, "compiled-hashes.json"), `${JSON.stringify(compiled, null, 2)}\n`, { flag: "wx", mode: 0o600 });
