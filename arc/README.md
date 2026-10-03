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

Every receipt and summary carries literal false write-authority flags. The package has a separate non-DOM TypeScript configuration, and the repository structure check rejects import edges between `arc/` and the playable application in `src/`.

## Evidence semantics

- Exact means identical grid dimensions and identical values in every cell.
- Missing, invalid, and hidden-target outputs remain visible; they never disappear from the denominator.
- The denominator comes from the admitted manifest, not from whichever receipts are supplied.
- Receipt hashes are tamper-evident SHA-256 content hashes. They are not signatures and do not authenticate who produced the envelope.
- Imported receipt envelopes can be inspected, but they cannot create a capability proposal. The public proposal path requires frozen task content, raw predictions, and one solver identity, then scores them again inside the package.
- `reproducible` remains `false` and `attestation` remains `unattested` in this initial package because this repository does not yet have committed solver provenance.
- Results from different solvers cannot be mixed into one proposal. Even a perfect single-solver result produces `status: "proposed"` and `certification: "not-certified"`.
- `archi-arc-exact-v1` versions both exact scoring and `archi-canonical-json-v1` serialization. The smoke task, receipt, and proposal hashes are frozen in `fixtures/golden/smoke-evidence-v1.json` to detect accidental identity drift.

## Commands

```bash
npm run arc:typecheck
npm run arc:test
```

ARC-AGI-3 uses interactive environments rather than the static exact-grid contract implemented here. It needs a separate episode/transcript evaluator and is intentionally out of scope for this slice.

## Desktop evidence review

`src/portable.ts` exports or inspects `archi-arc-evaluation-bundle/v1`: the
frozen manifest, one solver identity, and raw task/prediction pairs. Portable
bundles are bounded to 2 MiB and 64 tasks. They contain no claimed summary,
application task ID, token totals, or billing fields. The native desktop
capabilities workspace re-scores them locally against the same versioned
contract; shared golden hashes check the adapter's parity.

`fixtures/portable/smoke-evaluation-v1.json` is the desktop demonstration. It
contains one correct and one incorrect fixed prediction and invokes no model.
The desktop retains proposed evidence only. Its fresh evaluation task ID can
be recorded in Token Steward separately from model tasks and user usefulness.
See `docs/native-arc-capabilities.md` at the repository root for that boundary.
