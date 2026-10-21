# ARCHi ARC Evidence Lab

This package is an isolated, offline proving ground for ARC-format static grid tasks. It validates untrusted task data, performs deterministic cell-for-cell scoring, emits content-addressed evidence receipts, and derives proposal-only summaries from a frozen manifest.

It is deliberately **not** an ARC Prize API client, competition submission, leaderboard result, live benchmark integration, solver, or claim of general intelligence. The checked-in task is synthetic and exists only to verify the contracts.

## Authority boundary

```text
untrusted ARC-format task
  → strict validation
  → deterministic exact scorer
  → immutable receipt
  → proposed evidence summary

  ⛔ Journey, traces, bond, affinity, stage, or XP writes
  ⛔ memory or permission grants
  ⛔ browser storage, network calls, or external actions
```

Every receipt and summary carries literal false write-authority flags. The package has a separate non-DOM TypeScript configuration, and is separate from the playable application in `src/`.

## Evidence semantics

- Exact means identical grid dimensions and identical values in every cell.
- Missing, invalid, and hidden-target outputs remain visible; they never disappear from the denominator.
- The denominator comes from the admitted manifest, not from whichever receipts are supplied.
- Receipt hashes are tamper-evident SHA-256 content hashes. They are not signatures and do not authenticate who produced the envelope.
- Imported receipt envelopes can be inspected, but they cannot create a capability proposal. The public proposal path requires frozen task content, raw predictions, and one solver identity, then scores them again inside the package.
- `reproducible` remains `false` and `attestation` remains `unattested` in this initial package because this repository does not yet have committed solver provenance.
- Results from different solvers cannot be mixed into one proposal. Even a perfect single-solver result produces `status: "proposed"` and `certification: "not-certified"`.
- `archi-arc-exact-v1` versions both exact scoring and `archi-canonical-json-v1` serialization. The smoke task, receipt, and proposal hashes are frozen in `fixtures/golden/smoke-evidence-v1.json` to detect accidental identity drift.
- Evaluation and proposal requests reject every extra own property, including non-enumerable and symbol keys, and accessor-bearing envelopes before reading their values. A solver cannot supply an evaluator override or rewrite expected outputs against the admitted manifest. This is a data boundary, not process isolation: an optimizer with filesystem access could still replace evaluator source or submit a different manifest. Independent runner ownership, pinned manifest/source digests and OS-enforced write restrictions are required before running such an optimizer.

## Commands

```bash
npm run arc:typecheck
npm run arc:test
```

ARC-AGI-3 uses interactive environments rather than the static exact-grid contract implemented here. It needs a separate episode/transcript evaluator and is intentionally out of scope for this slice.
