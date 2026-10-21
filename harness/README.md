# OO-Harness observation pilot

Status: implemented offline pilot, synthetic qualification only. Original ARCHi code inspired by a published method; this is not the authors' package, an LLM experiment, or an installed native adapter.

The pilot selects a proposed check plan without changing the acting assistant. Its classes reuse reviewed code through inheritance, but have no executor or state-store interface. No model or provider is called. Native Swift remains the owner of assistance, permissions, current documents, cancellation, and memory. The Unity preview, retained game, and ARC evidence lab are separate.

## Run

With Node.js 24+ from the repository root:

```bash
npm run harness:test
npm run harness:check
npm run check
```

The first two commands require Node built-ins only. The full repository check also needs `npm ci`. Source pins are checked before the CLI imports specialist modules. `check` runs four discovery-labelled fixtures and eight separately named held-out-labelled fixtures; all were authored alongside this deterministic implementation. These are regression fixtures, not statistically independent research data or evidence of learned generalization. There is no training, generated code, real task completion, or benchmark reproduction in this install.

```bash
npm run harness:observe -- /absolute/path/to/observation-packet.json
```

The CLI reads one bounded JSON file and prints a receipt. It does not save the receipt. Save wanted output explicitly under the ignored `output/` directory with local file permissions appropriate to its contents. Do not commit real observations, private documents, local profile files, or credentials. No raw text, filenames, prompts, tool arguments, or credentials are permitted in the input schema. IDs and hashes can still be sensitive metadata.

A packet has exactly `request` and `current`. `validateRequest` and `validateState` in [contracts.mjs](contracts.mjs) define the full closed schemas. The current-state record has to come from a trusted owner in a future integration. An imported packet cannot prove that it represents native state. The CLI overwrites `current.nowMs` with its own wall clock; it does not authenticate other supplied fields.

## Catalogue

| Class ID | Parent | Proposed checks beyond the parent |
| --- | --- | --- |
| `base` | none | Current-context check |
| `artifact` | `base` | Artifact existence and format |
| `spreadsheet` | `artifact` | Saved cell values and percentage units |
| `api-schema` | `base` | Tool schema and returned-result checks |

The checks are identifiers, not executable actions. No file contents are inspected by the pilot. `artifactValid` and completion flags are observations supplied by the caller; the observer does not independently verify them. These fields must be produced by appropriate checkers before any quality experiment can use them as labels.

Routing is a deterministic baseline. Permission denial and unavailable services retain the base route. A completed result with the required artifact recorded as valid retains base. Otherwise a workbook percentage need selects spreadsheet checks, missing/invalid artifacts select artifact checks, and recognized schema errors select API checks. No matching mechanism retains base. Revoking an ancestor invalidates all of its descendants. The base actual-route label is a boundary declaration; it does not attest that a base model ran.

## Implemented boundaries

- Input is copied from data descriptors; accessors, hidden/symbol keys, prototype fields, cycles, sparse arrays, unsupported values, unknown fields and excessive inputs are rejected. This does not sandbox hostile same-process JavaScript or proxy objects.
- Catalogue identity and lineage are allowlisted. Input cannot add an import path, prompt, executor, evaluator, class implementation, or tool.
- Every receipt binds the request digest, context revision and digest, policy and model revisions, catalogue digest, source-pin digest, validity interval, observed usage, check plan and selection.
- Output is deeply frozen. All execution, permission, provider, memory, state-mutation and promotion authority flags are false.
- `matchesCurrentObservation` reconstructs the full expected receipt and rechecks current expiry, policy, source, catalogue, enabled status, context and inherited revocations. A public checksum alone cannot admit a modified receipt. This function validates an offline observation; it never grants execution authority.
- The request validity interval is at most five minutes. Context revision must be a monotonically increasing generation from its future native owner. Undoing content must not reuse an old generation or revive withdrawn authorization.
- The CLI rejects symlink input files, non-regular files and inputs over 64 KiB. Error output omits input data, filenames and stack traces. Receipts remain unsigned, and their metadata is not authenticated.
- Source pins detect reviewed-source drift when the checker and pin file are trusted. A writer able to change both can replace both. This is not a process sandbox, remote attestation, digital signature, protection against a compromised host, or prevention of an import-time filesystem race.
- The observer is absent from the native dispatch path and browser app. A closed envelope and literal false flags are API contracts, not OS-enforced isolation.

## Rollback and updates

For a host using the module offline, set `enabled: false` in the owner-controlled current state: the result is disabled with an empty plan. To quarantine a lineage, add a parent or class ID to the owner-controlled `revokedHarnessIds`. `matchesCurrentObservation` refuses previously recorded observations after either change. These controls cannot revoke an action already taken by another program; the pilot never starts one.

No installed app, model, profile, memory, permission, game state, or PR #4 file is modified by this branch. Removing/reverting this focused commit removes the offline pilot and npm commands. There is no durable harness catalogue installation or migration to undo.

Changing a pinned implementation intentionally requires source review, tests, and refreshing `harness/integrity.json` plus the complete repository `SOURCE_SHA256SUMS`. A failure must not trigger automatic pin regeneration. Never accept an externally supplied digest as a trust root merely because it agrees with externally supplied code.

## Next native adapter

Before automatic observation, implement a separately reviewed macOS adapter through current native owners. It should emit a bounded metadata snapshot after an already authorized base request finishes, omit actor-visible recommendations, and isolate observer records from actor context. Bind cancellation/source generations and exact provider eligibility in the existing owner; do not create a parallel permission or memory store.

The native source needs Swift 6, the macOS SDK and synthetic request/cancellation/restore tests. This Linux build has no Swift toolchain and has not compiled, installed, launched or changed ARCHiDesktop. PR #4's pending native validation is independent. The full `LocalExpertPolicy` implementation referenced by earlier design notes is not present in this public baseline, so this pilot does not recreate it.

Keep execution and online evolution disabled until the experiment in [the research note](../docs/OO_HARNESS_RESEARCH.md) demonstrates a useful residual beyond deterministic routing. Any future model-enabled provider work requires its own configuration and actual validation; this install adds no API key or paid inference dependency.
