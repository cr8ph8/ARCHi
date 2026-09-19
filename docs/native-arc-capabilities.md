# Native ARC capabilities evidence

The desktop capabilities workspace imports `archi-arc-evaluation-bundle/v1`
JSON and re-scores raw grid predictions locally. This connects the existing
`arc/` Evidence Lab contract to a native review surface. It does not install a
solver, run an LLM, submit a competition result, or certify reasoning ability.

The portable input has exactly four fields:

```json
{
  "schema": "archi-arc-evaluation-bundle/v1",
  "manifest": {},
  "solver": {},
  "evaluations": [{"task": {}, "predictions": []}]
}
```

`manifest`, `solver`, and each raw task use the existing schemas in
`arc/src/contract.ts`. `arc/src/portable.ts` exports and checks bundles through
the existing evaluator. A working synthetic example is retained at
`arc/fixtures/portable/smoke-evaluation-v1.json`. It intentionally has one exact
and one incorrect prediction. The native demonstration uses identical inputs;
golden receipt and proposal hashes must match the established TypeScript
fixture.

## Evidence and accounting

- The native application creates an evaluation task UUID. Imported task IDs
  cannot bind an evaluation to an unrelated assistant answer.
- `ARCCapabilitiesEvent` returns this application task ID, start/finish times,
  a proposal hash when scoring and persistence succeeded, provenance status,
  and a three-state result: all examples exact, not all exact, or evaluation
  failed. This is the explicit join point for Token Steward.
- A successful import means the evidence was checked. It does not mean that
  the predictions were correct or that a user accepted an assistant task.
- This evaluation performs zero model invocations. It does not reconstruct
  the unknown cost of producing imported predictions. The bundle admits no
  token or financial totals.
- The denominator always comes from the frozen manifest. Missing tasks,
  missing predictions, invalid predictions, and hidden targets remain visible.
- A perfect score remains `proposed`, `not-certified`, `unattested`, and
  non-reproducible under the existing solver-provenance boundary. There are
  no Journey, memory, evolution, XP, permission, or action mutations.
- Source hashes are integrity checks, not source authentication. Source
  status remains synthetic or an unverified offline snapshot.

## Local persistence and bounds

The root application supplies a profile-scoped store URL. The store retains
raw bundles and locally assigned record metadata, then re-scores the raw
inputs on reopen. It does not load a cached claimed score as authority.
Duplicate proposal hashes do not duplicate the evidence shelf; each explicit
evaluation still receives its own accounting task ID.

Bounds: 2 MiB per input, 64 manifest tasks, 20 examples per task section,
30×30 grids, colors 0–9, 16 evidence records, and a 16 MiB archive. Reaching a
limit reports an error and preserves the existing records. Writes use an atomic
replacement under a nonblocking cooperative lock and compare the last loaded
content digest. A stale application session cannot overwrite another session's
saved evidence. An unreadable archive is preserved and further writes are
blocked until it is repaired or restored. A persistence failure is not reported
as success.

No background collector, inference, cloud call, paid budget, capability
promotion, or benchmark download is triggered by opening this workspace.
ARC-AGI-3 interactive environments remain outside the static grid contract.

## Verification

- `npm run arc:typecheck`
- `npm run arc:test`
- `swift test --build-system native --filter ARCCapabilitiesTests` in `desktop/`

Verified 16 September 2026: **28 TypeScript tests passed**, ARC typecheck and
structure check passed, **12 native ARC unit tests passed**, and the separate
880×640 native workspace fixture passed with real accessibility button actions.
The native fixture ran the deliberately mixed synthetic demonstration, retained
one exact/one incorrect example, and recorded one evaluation task in Token
Steward with zero model calls, zero charges and no companion-state changes.
The native unit group overlaps the larger focused run; counts are not additive.
Local delivery evidence is retained at `output/token-steward-arc-2026-09-16/delivery.json` in the development workspace; generated receipts are excluded from the source package.

The native tests cover shared golden hashes, fixture parity, complete
denominators, invalid and hidden-target predictions, frozen task tampering,
unknown fields, bounds, duplicate evidence, restart rescoring, and preserved
state on corrupt archives or failed writes, plus stale-writer protection and
one-third score canonicalization parity. The signed Development Review candidate
is staged, not installed. This slice adds offline evidence review; it does not
run a live ARC solver or certify an official benchmark result.
