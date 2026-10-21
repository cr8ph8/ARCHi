import { describe, expect, it } from "vitest";
import goldenFixture from "../fixtures/golden/smoke-evidence-v1.json";
import manifestFixture from "../fixtures/manifest.json";
import taskFixture from "../fixtures/smoke/synthetic-increment-001.json";
import {
  ARC_NO_WRITE_AUTHORITY,
  ARC_SCORER_VERSION,
  canonicalJson,
  digestCanonical,
  sha256Text,
  validateArcGrid,
  validateArcManifest,
  validateArcTask,
  type ArcEvaluationManifest,
  type ArcTask,
} from "../src/contract";
import {
  createArcCapabilityProposal,
  evaluateArcTask,
  gridsExactlyEqual,
  verifyArcReceiptEnvelope,
  type ArcEvidenceReceipt,
} from "../src/evaluate";

function accepted<T>(result: { ok: true; value: T } | { ok: false; issues: readonly string[] }): T {
  if (!result.ok) throw new Error(result.issues.join("; "));
  return result.value;
}

const solver = Object.freeze({
  id: "archi-test-solver",
  version: "0.0.1",
  codeHash: digestCanonical("synthetic solver code"),
  configurationHash: digestCanonical({ mode: "deterministic-test" }),
});

function fixtures(): { manifest: ArcEvaluationManifest; task: ArcTask } {
  return {
    manifest: accepted(validateArcManifest(manifestFixture)),
    task: accepted(validateArcTask(taskFixture)),
  };
}

function evaluated(predictions: unknown[]): readonly ArcEvidenceReceipt[] {
  const { manifest, task } = fixtures();
  return evaluateArcTask({ manifest, task, predictions, solver });
}

function multipleTaskFixtures(): {
  manifest: ArcEvaluationManifest;
  first: ArcTask;
  second: ArcTask;
} {
  const { manifest, task: first } = fixtures();
  const second = accepted(
    validateArcTask({
      taskId: "synthetic-copy-002",
      train: [{ input: [[1, 0]], output: [[1, 0]] }],
      test: [{ input: [[2, 2]], output: [[2, 2]] }],
    }),
  );
  const expanded = accepted(
    validateArcManifest({
      ...manifest,
      manifestId: "archi-synthetic-multi-v1",
      source: { ...manifest.source, contentHash: digestCanonical("synthetic multi-task snapshot") },
      tasks: [
        manifest.tasks[0],
        { taskId: second.taskId, taskHash: digestCanonical(second), testExamples: second.test.length },
      ],
    }),
  );
  return { manifest: expanded, first, second };
}

describe("ARC evidence contract", () => {
  for (const entryPoint of ["evaluation", "proposal"] as const) {
    it.each(["hidden", "symbol", "symbol-accessor"] as const)(
      `rejects a %s extra on the ${entryPoint} envelope without invoking it`,
      (extra) => {
        const { manifest, task } = fixtures();
        const request = { manifest, task, predictions: [[[0, 0, 0]]], solver };
        const proposal = { manifest, evaluations: [{ task, predictions: request.predictions }], solver };
        const envelope = entryPoint === "evaluation" ? request : proposal;
        let called = false;
        const evaluator = () => { called = true; return true; };
        if (extra === "hidden") {
          Object.defineProperty(envelope, "evaluator", { value: evaluator });
        } else if (extra === "symbol") {
          Object.defineProperty(envelope, Symbol("evaluator"), { value: evaluator, enumerable: true });
        } else {
          Object.defineProperty(envelope, Symbol("evaluator"), { get: evaluator });
        }
        expect(() => entryPoint === "evaluation"
          ? evaluateArcTask(envelope as typeof request)
          : createArcCapabilityProposal(envelope as typeof proposal)).toThrow(/unexpected/);
        expect(called).toBe(false);
      },
    );
  }

  it("rejects a proposal envelope accessor before reading it", () => {
    const { manifest, task } = fixtures();
    let reads = 0;
    const proposal = Object.defineProperty({ manifest, evaluations: [{ task, predictions: [] }], solver },
      "evaluations", { enumerable: true, get() { reads += 1; return []; } });
    expect(() => createArcCapabilityProposal(proposal)).toThrow(/unexpected/);
    expect(reads).toBe(0);
  });

  it.each(["hidden", "symbol", "symbol-accessor"] as const)(
    "rejects a %s array extension before evaluating its values",
    (extra) => {
      const { manifest, task } = fixtures();
      const predictions = [[[2, 0, 2]]];
      let called = false;
      const getter = () => { called = true; return true; };
      if (extra === "hidden") Object.defineProperty(predictions, "claimedScore", { value: 1 });
      else if (extra === "symbol") Object.defineProperty(predictions, Symbol("claimedScore"), { value: 1 });
      else Object.defineProperty(predictions, Symbol("claimedScore"), { get: getter });
      expect(() => evaluateArcTask({ manifest, task, predictions, solver })).toThrow(/data-only array/);
      expect(validateArcGrid(predictions[0]).ok).toBe(true);
      expect(called).toBe(false);
    },
  );

  it("rejects hidden and symbol task fields through the same strict data contract", () => {
    const { task } = fixtures();
    expect(validateArcTask(Object.defineProperty({ ...task }, "claimedScore", { value: 1 })).ok).toBe(false);
    let called = false;
    const accessor = Object.defineProperty({ ...task }, Symbol("claimedScore"), {
      get() { called = true; return 1; },
    });
    expect(validateArcTask(accessor).ok).toBe(false);
    expect(called).toBe(false);
  });

  it("rejects optimizer-supplied evaluator controls without executing them", () => {
    const { manifest, task } = fixtures();
    const request = { manifest, task, predictions: [[[0, 0, 0]]], solver };
    let called = false;
    const evaluator = () => { called = true; return true; };
    expect(() => evaluateArcTask({ ...request, evaluator } as typeof request)).toThrow(/unexpected/);
    const proposal = { manifest, evaluations: [{ task, predictions: request.predictions }], solver };
    expect(() => createArcCapabilityProposal({ ...proposal, evaluator } as typeof proposal)).toThrow(/unexpected/);
    const accessor = Object.defineProperty({ ...request }, "manifest", {
      enumerable: true, get() { called = true; return manifest; },
    });
    expect(() => evaluateArcTask(accessor)).toThrow(/unexpected/);
    expect(called).toBe(false);
    expect(evaluateArcTask(request)[0]?.result).toBe("incorrect");
    expect(createArcCapabilityProposal(proposal).counts.exact).toBe(0);
  });

  it("rejects rewritten expected outputs against the admitted manifest", () => {
    const { manifest, task } = fixtures();
    const rewritten = { ...task, test: [{ ...task.test[0], output: [[0, 0, 0]] }] };
    expect(() => createArcCapabilityProposal({ manifest,
      evaluations: [{ task: rewritten, predictions: [[[0, 0, 0]]] }], solver,
    })).toThrow(/frozen manifest/);
    expect(Object.isFrozen(manifest.tasks)).toBe(true);
    expect(Object.isFrozen(task.test[0]?.output?.[0])).toBe(true);
    expect(evaluateArcTask({ manifest, task, predictions: [[[0, 0, 0]]], solver })[0]?.result).toBe("incorrect");
  });

  it("matches known SHA-256 vectors and canonicalizes object key order", () => {
    expect(sha256Text("")).toBe("sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    expect(sha256Text("abc")).toBe("sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    expect(sha256Text("ARCHi ✦ opal")).toBe("sha256:3f29221288703ed15086f45854dc1f57ec980cf837b83b9ea4f1a58f2c793721");
    expect(canonicalJson({ z: 3, a: [2, 1] })).toBe('{"a":[2,1],"z":3}');
    expect(digestCanonical({ a: 1, b: 2 })).toBe(digestCanonical({ b: 2, a: 1 }));
    expect(() => canonicalJson(new Array(1))).toThrow(/Canonical JSON arrays/);
  });

  it("admits a strict, deeply immutable copy of a labeled task", () => {
    const result = validateArcTask(taskFixture);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value).not.toBe(taskFixture);
    expect(Object.isFrozen(result.value)).toBe(true);
    expect(Object.isFrozen(result.value.train)).toBe(true);
    expect(Object.isFrozen(result.value.train[0]?.input)).toBe(true);
    expect(Object.isFrozen(result.value.train[0]?.input[0])).toBe(true);
    expect(taskFixture.test[0]?.input).toEqual([[1, 0, 1]]);
    const manifest = accepted(validateArcManifest(manifestFixture));
    expect(digestCanonical(result.value)).toBe(manifest.tasks[0]?.taskHash);
  });

  it.each([
    ["empty", []],
    ["ragged", [[1, 2], [3]]],
    ["fractional", [[1.5]]],
    ["negative", [[-1]]],
    ["outside the palette", [[10]]],
    ["oversized", [Array.from({ length: 31 }, () => 0)]],
  ])("rejects an %s grid", (_label, grid) => {
    expect(validateArcGrid(grid).ok).toBe(false);
  });

  it("rejects accessor-bearing and extra-field task objects without invoking the accessor", () => {
    const accessorTask: Record<string, unknown> = {};
    Object.defineProperty(accessorTask, "taskId", {
      enumerable: true,
      get() {
        throw new Error("must not execute");
      },
    });
    expect(() => validateArcTask(accessorTask)).not.toThrow();
    expect(validateArcTask(accessorTask).ok).toBe(false);
    expect(validateArcTask({ ...taskFixture, claimedScore: 1 }).ok).toBe(false);
    const decoratedGrid = [[1]] as number[][] & { claim?: string };
    decoratedGrid.claim = "exact";
    expect(validateArcGrid(decoratedGrid).ok).toBe(false);
    const throwingProxy = new Proxy(
      {},
      {
        getPrototypeOf() {
          throw new Error("proxy-trap-ran");
        },
      },
    );
    expect(() => validateArcTask(throwingProxy)).not.toThrow();
    expect(validateArcTask(throwingProxy).ok).toBe(false);
    const throwingGetProxy = new Proxy(
      { taskId: "proxy-task", train: [], test: [] },
      {
        get() {
          throw new Error("get-trap-ran");
        },
      },
    );
    expect(() => validateArcTask(throwingGetProxy)).not.toThrow();
    expect(validateArcTask(throwingGetProxy).ok).toBe(false);
  });

  it("scores only identical dimensions and cell values as exact", () => {
    expect(gridsExactlyEqual([[1, 0], [0, 1]], [[1, 0], [0, 1]])).toBe(true);
    expect(gridsExactlyEqual([[1, 0], [0, 1]], [[1, 0], [0, 2]])).toBe(false);
    expect(gridsExactlyEqual([[1, 0]], [[1], [0]])).toBe(false);
    expect(gridsExactlyEqual([[1]], [[1, 0]])).toBe(false);
  });

  it("derives exact and incorrect results instead of accepting a claimed score", () => {
    const receipts = evaluated([[[2, 0, 2]], [[6, 6], [0, 5]]]);
    expect(receipts.map((receipt) => receipt.result)).toEqual(["exact", "incorrect"]);
    expect(receipts.map((receipt) => receipt.exact)).toEqual([true, false]);
    expect(receipts[0]?.predictionHash).toBe(receipts[0]?.expectedOutputHash);
    expect(receipts[1]?.predictionHash).not.toBe(receipts[1]?.expectedOutputHash);
    expect(Object.isFrozen(receipts)).toBe(true);
    expect(Object.isFrozen(receipts[0])).toBe(true);
  });

  it("matches the frozen canonical task, receipt, and proposal vectors", () => {
    const { manifest, task } = fixtures();
    const predictions = [[[2, 0, 2]], [[6, 6], [0, 5]]];
    const receipts = evaluateArcTask({ manifest, task, predictions, solver });
    const proposal = createArcCapabilityProposal({
      manifest,
      evaluations: [{ task, predictions }],
      solver,
    });
    expect(goldenFixture.canonicalization).toBe("archi-canonical-json-v1");
    expect(goldenFixture.scorerVersion).toBe(ARC_SCORER_VERSION);
    expect(canonicalJson(task)).toBe(goldenFixture.canonicalTask);
    expect(digestCanonical(task)).toBe(goldenFixture.taskHash);
    expect(digestCanonical(manifest)).toBe(goldenFixture.manifestHash);
    expect(receipts.map((receipt) => receipt.receiptHash)).toEqual(goldenFixture.receiptHashes);
    expect(proposal.proposalHash).toBe(goldenFixture.proposalHash);
    expect(proposal.counts).toEqual(goldenFixture.counts);
    expect(proposal.exactRate).toBe(goldenFixture.exactRate);
  });

  it("rejects task content that does not match the frozen manifest", () => {
    const { manifest, task } = fixtures();
    const alteredTask = {
      ...task,
      train: task.train.map((example, index) =>
        index === 0 ? { ...example, output: [[9, 9], [9, 9]] } : example,
      ),
    };
    expect(() =>
      evaluateArcTask({ manifest, task: alteredTask, predictions: [[[2, 0, 2]]], solver }),
    ).toThrow(/content does not match/);
  });

  it("keeps missing, invalid, and hidden-target outcomes visible", () => {
    const missing = evaluated([[[2, 0, 2]]]);
    expect(missing[1]?.result).toBe("missing");
    expect(missing[1]?.reason).toBe("missing-prediction");

    const invalid = evaluated([[[2, 0, 2]], [[10]]]);
    expect(invalid[1]?.result).toBe("invalid");
    expect(invalid[1]?.predictionHash).toBeNull();

    const { manifest, task } = fixtures();
    const hiddenTask = {
      ...task,
      test: task.test.map((example, index) => (index === 0 ? { input: example.input } : example)),
    };
    const admittedHiddenTask = accepted(validateArcTask(hiddenTask));
    const hiddenManifest = {
      ...manifest,
      manifestId: "archi-hidden-target-test",
      tasks: manifest.tasks.map((entry) => ({ ...entry, taskHash: digestCanonical(admittedHiddenTask) })),
    };
    const hidden = evaluateArcTask({
      manifest: hiddenManifest,
      task: admittedHiddenTask,
      predictions: [[[2, 0, 2]]],
      solver,
    });
    expect(hidden[0]?.result).toBe("unscored");
    expect(hidden[0]?.exact).toBeNull();
    expect(hidden[0]?.expectedOutputHash).toBeNull();
    const proposal = createArcCapabilityProposal({
      manifest: hiddenManifest,
      evaluations: [
        { task: admittedHiddenTask, predictions: [[[2, 0, 2]], [[6, 6], [0, 6]]] },
      ],
      solver,
    });
    expect(proposal.counts).toMatchObject({ exact: 1, unscored: 1, totalExamples: 2, exactTasks: 0 });
    expect(proposal.scoredCoverageComplete).toBe(false);
  });

  it("verifies receipt content hashes and rejects tampering or authority escalation", () => {
    const receipt = evaluated([[[2, 0, 2]]])[0];
    expect(receipt).toBeDefined();
    expect(verifyArcReceiptEnvelope(receipt)).toEqual(receipt);

    const tampered = JSON.parse(JSON.stringify(receipt)) as Record<string, unknown>;
    tampered.taskId = "synthetic-tampered-001";
    expect(() => verifyArcReceiptEnvelope(tampered)).toThrow(/hash verification failed/);

    const escalated = JSON.parse(JSON.stringify(receipt)) as Record<string, unknown>;
    (escalated.authority as Record<string, unknown>).journeyWritable = true;
    expect(() => verifyArcReceiptEnvelope(escalated)).toThrow(/authority/);
  });

  it("rejects a receipt whose declared exact result conflicts with its digests", () => {
    const receipt = evaluated([[[2, 0, 2]], [[6, 6], [0, 5]]])[1];
    const forged = JSON.parse(JSON.stringify(receipt)) as Record<string, unknown>;
    forged.result = "exact";
    forged.exact = true;
    expect(() => verifyArcReceiptEnvelope(forged)).toThrow(/disagrees/);
  });
});

describe("ARC capability proposal boundary", () => {
  it("uses the frozen manifest denominator and remains proposal-only", () => {
    const { manifest, task } = fixtures();
    const proposal = createArcCapabilityProposal({
      manifest,
      evaluations: [{ task, predictions: [[[2, 0, 2]], [[6, 6], [0, 5]]] }],
      solver,
    });
    expect(proposal.status).toBe("proposed");
    expect(proposal.certification).toBe("not-certified");
    expect(proposal.solver).toEqual(solver);
    expect(proposal.counts).toMatchObject({ exact: 1, incorrect: 1, totalExamples: 2, exactTasks: 0 });
    expect(proposal.exactRate).toBe(0.5);
    expect(proposal.receiptCoverageComplete).toBe(true);
    expect(proposal.scoredCoverageComplete).toBe(true);
    expect(proposal.authority).toBe(ARC_NO_WRITE_AUTHORITY);
    expect(proposal.authority.canonWritable).toBe(false);
    expect(proposal.authority.journeyWritable).toBe(false);
    expect(proposal.authority.permissionGrant).toBe(false);
  });

  it("does not inflate a favorable prediction subset", () => {
    const { manifest, task } = fixtures();
    const subset = createArcCapabilityProposal({
      manifest,
      evaluations: [{ task, predictions: [[[2, 0, 2]]] }],
      solver,
    });
    expect(subset.counts).toMatchObject({ exact: 1, missing: 1, totalExamples: 2 });
    expect(subset.exactRate).toBe(0.5);
    expect(subset.receiptCoverageComplete).toBe(true);
    expect(subset.scoredCoverageComplete).toBe(false);
  });

  it("is deterministic and permits only one frozen solver per proposal", () => {
    const { manifest, task } = fixtures();
    const input = {
      manifest,
      evaluations: [{ task, predictions: [[[2, 0, 2]], [[6, 6], [0, 6]]] }],
      solver,
    };
    expect(createArcCapabilityProposal(input).proposalHash).toBe(createArcCapabilityProposal(input).proposalHash);
    expect(() =>
      createArcCapabilityProposal({
        manifest,
        evaluations: [{ task, predictions: [], solver: { ...solver, id: "other-solver" } }],
        solver,
      }),
    ).toThrow(/unexpected or missing fields/);
  });

  it("keeps multi-task order, omissions, and duplicate tasks auditable", () => {
    const { manifest, first, second } = multipleTaskFixtures();
    const firstRun = { task: first, predictions: [[[2, 0, 2]], [[6, 6], [0, 5]]] };
    const secondRun = { task: second, predictions: [[[2, 2]]] };
    const forward = createArcCapabilityProposal({ manifest, evaluations: [firstRun, secondRun], solver });
    const reversed = createArcCapabilityProposal({ manifest, evaluations: [secondRun, firstRun], solver });
    expect(reversed.proposalHash).toBe(forward.proposalHash);
    expect(forward.counts).toMatchObject({ exact: 2, incorrect: 1, totalExamples: 3, exactTasks: 1 });

    const omitted = createArcCapabilityProposal({ manifest, evaluations: [firstRun], solver });
    expect(omitted.counts).toMatchObject({ exact: 1, incorrect: 1, missing: 1, totalExamples: 3 });
    expect(omitted.receiptCoverageComplete).toBe(false);
    expect(() =>
      createArcCapabilityProposal({ manifest, evaluations: [firstRun, firstRun], solver }),
    ).toThrow(/evaluated more than once/);
  });

  it("cannot turn a self-rehashed receipt envelope into proposal evidence", () => {
    const { manifest, task } = fixtures();
    const incorrect = evaluated([[[2, 0, 2]], [[6, 6], [0, 5]]])[1];
    expect(incorrect).toBeDefined();
    const forged = JSON.parse(JSON.stringify(incorrect)) as Record<string, unknown>;
    forged.result = "exact";
    forged.exact = true;
    forged.predictionHash = forged.expectedOutputHash;
    delete forged.receiptHash;
    forged.receiptHash = digestCanonical(forged);
    expect(verifyArcReceiptEnvelope(forged).result).toBe("exact");

    const proposal = createArcCapabilityProposal({
      manifest,
      evaluations: [{ task, predictions: [[[2, 0, 2]], [[6, 6], [0, 5]]] }],
      solver,
    });
    expect(proposal.counts).toMatchObject({ exact: 1, incorrect: 1 });
    expect(() =>
      createArcCapabilityProposal({ manifest, evaluations: [forged], solver }),
    ).toThrow(/unexpected or missing fields/);
  });

  it("returns null rates for an empty manifest rather than fabricating a score", () => {
    const { manifest } = fixtures();
    const empty = { ...manifest, manifestId: "empty-manifest", tasks: [] };
    const proposal = createArcCapabilityProposal({ manifest: empty, evaluations: [], solver });
    expect(proposal.counts.totalExamples).toBe(0);
    expect(proposal.exactRate).toBeNull();
    expect(proposal.taskExactRate).toBeNull();
  });

  it("leaves neighboring state byte-for-byte unchanged", () => {
    const { manifest, task } = fixtures();
    const journeyLikeState = Object.freeze({
      plays: 4,
      bond: 12,
      expression: "scout",
      affinities: Object.freeze({ scout: 3 }),
      traces: Object.freeze(["kept"]),
    });
    const before = JSON.stringify(journeyLikeState);
    createArcCapabilityProposal({
      manifest,
      evaluations: [{ task, predictions: [[[2, 0, 2]], [[6, 6], [0, 6]]] }],
      solver,
    });
    expect(JSON.stringify(journeyLikeState)).toBe(before);
  });
});
