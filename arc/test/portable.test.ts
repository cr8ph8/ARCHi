import { describe, expect, it } from "vitest";
import fixture from "../fixtures/portable/smoke-evaluation-v1.json";
import golden from "../fixtures/golden/smoke-evidence-v1.json";
import thirdFixture from "../fixtures/portable/third-rate-evaluation-v1.json";
import thirdGolden from "../fixtures/golden/third-rate-evidence-v1.json";
import { exportPortableArcBundle, inspectPortableArcBundle } from "../src/portable";

describe("native portable ARC evidence", () => {
  it("exports raw evidence and preserves the established golden proposal", () => {
    const { schema: _schema, ...input } = fixture;
    const encoded = exportPortableArcBundle(input);
    const { proposal } = inspectPortableArcBundle(encoded);
    expect(proposal.proposalHash).toBe(golden.proposalHash);
    expect(proposal.receiptHashes).toEqual(golden.receiptHashes);
    expect(proposal.counts).toEqual(golden.counts);
  });
  it("cannot import summary or task identity instead of raw predictions", () => {
    expect(() => inspectPortableArcBundle(JSON.stringify({ ...fixture, accepted: true }))).toThrow(/fields/);
    expect(() => inspectPortableArcBundle(JSON.stringify({ ...fixture, taskID: "some-other-chat" }))).toThrow(/fields/);
    expect(() => inspectPortableArcBundle(JSON.stringify({ ...fixture, evaluations: [{ receiptHash: golden.receiptHashes[0] }] }))).toThrow();
  });
  it("keeps omitted predictions and tasks in the denominator", () => {
    const { proposal } = inspectPortableArcBundle(JSON.stringify({ ...fixture, evaluations: [] }));
    expect(proposal.counts.totalExamples).toBe(2);
    expect(proposal.counts.missing).toBe(2);
    expect(proposal.status).toBe("proposed");
    expect(proposal.authority.canonWritable).toBe(false);
  });
  it("bounds the portable input before parsing", () => {
    expect(() => inspectPortableArcBundle(" ".repeat(2 * 1024 * 1024 + 1))).toThrow(/2 MiB/);
  });
  it("freezes fractional rate serialization for native parity", () => {
    const { proposal } = inspectPortableArcBundle(JSON.stringify(thirdFixture));
    expect(proposal.proposalHash).toBe(thirdGolden.proposalHash);
    expect(proposal.exactRate).toBe(1 / 3);
    expect(proposal.counts).toEqual(thirdGolden.counts);
  });
});
