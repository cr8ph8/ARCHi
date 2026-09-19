import { canonicalJson, validateArcManifest } from "./contract";
import { createArcCapabilityProposal } from "./evaluate";

export const ARC_PORTABLE_SCHEMA = "archi-arc-evaluation-bundle/v1" as const;
export const ARC_PORTABLE_MAX_TASKS = 64;
export const ARC_PORTABLE_MAX_BYTES = 2 * 1024 * 1024;

/** Data exchange, not an attestation. The receiver must score the raw inputs again. */
export function inspectPortableArcBundle(text: string) {
  // UTF-8 length without a DOM or Node dependency.
  let bytes = 0;
  for (const character of text) {
    const value = character.codePointAt(0)!;
    bytes += value <= 0x7f ? 1 : value <= 0x7ff ? 2 : value <= 0xffff ? 3 : 4;
    if (bytes > ARC_PORTABLE_MAX_BYTES) throw new RangeError("ARC bundle exceeds 2 MiB");
  }
  const bundle: unknown = JSON.parse(text);
  if (typeof bundle !== "object" || bundle === null || Array.isArray(bundle)) {
    throw new TypeError("ARC bundle must be an object");
  }
  const record = bundle as Record<string, unknown>;
  if (Object.keys(record).sort().join(",") !== "evaluations,manifest,schema,solver" || record.schema !== ARC_PORTABLE_SCHEMA) {
    throw new TypeError("ARC bundle has unsupported schema or fields");
  }
  const manifest = validateArcManifest(record.manifest);
  if (!manifest.ok) throw new TypeError(manifest.issues.join("; "));
  if (manifest.value.tasks.length > ARC_PORTABLE_MAX_TASKS) throw new RangeError("ARC desktop bundle exceeds 64 tasks");
  const proposal = createArcCapabilityProposal({ manifest: record.manifest, evaluations: record.evaluations, solver: record.solver });
  return { bundle: record, proposal };
}

export function exportPortableArcBundle(input: { manifest: unknown; evaluations: unknown; solver: unknown }): string {
  const text = canonicalJson({ schema: ARC_PORTABLE_SCHEMA, ...input });
  inspectPortableArcBundle(text);
  return text;
}
