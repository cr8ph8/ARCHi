# Imagination pilot validation — 21 October 2026

## Source and scope

This independent developer contribution starts at ARCHi development revision
`c4cc639684dd520469930232f49dfc11af626547` on
`codex/desktop-unity-alpha-20260918`. The change adds an advisory Node/TypeScript
module, a closed Sokoban simulator, a provider contract, an executable CLI,
synthetic fixtures, tests and documentation. The root npm check includes its
type check and tests. Node type definitions are pinned in the existing lockfile.

The local environment was Node **v24.19.0**, **Linux x64**, with the repository's
pinned TypeScript/Vite/Vitest dependencies. No native Swift or Unity source was
changed. No native app, model weights, CUDA backend or user profile was installed
or accessed. Model inference, real environment dispatch and training counts are
all zero for this validation.

## Observed checks

| Check | Result |
| --- | --- |
| `npm run imagination:typecheck` | Passed |
| `npm run imagination:test` | **77 tests passed**, zero failures, cancellations or skips |
| `node scripts/imagination-pilot.mjs demo` | **8 synthetic scenarios passed**, zero failures |
| Application tests, reached by `npm run check` | **286 passed** |
| Foundation contracts | **11 passed** |
| PWA contracts | **10 passed** |
| ARC type check and contract tests | Type check passed; **28 tests passed** |
| `npm run build`, executed separately after the aggregate check stopped | TypeScript, production client build and PWA shell build passed |
| Complete source manifest | All **1,829** tracked source files, excluding the manifest itself, have matching SHA-256 entries and exact coverage |
| `git diff --check` | Passed |

The 77 imagination cases comprise 38 proposal-contract tests, 22 asynchronous
provider tests, 13 simulator tests and four CLI tests. Node's subtests are included
in those counts. The eight demo scenarios are behavioral fixtures, not an
independent benchmark sample or eight additional learned-model successes.

The initial restricted workspace run could not spawn Node subprocesses for
three CLI tests. The final focused run used the authorized local test environment
with subprocess support; all four CLI tests executed and passed.

## Aggregate check limitation

**`npm run check` does not pass on this environment.** It reaches the existing ARC
replay suite and reports two passing and ten failing tests. Its checked-in runtime
pin requires **Node v24.18.0, Darwin ARM64**, including an exact executable hash and
dependency versions. This Linux x64 runtime fails that identity comparison before
checker execution. Several replay tests consequently encounter the runtime error
instead of the later condition they were written to test.

The replay implementation, tests, configuration, worker and pins are byte-identical
to the base revision. This contribution does not rewrite that qualification to
match this machine. The new imagination checks and production build were run
separately to completion. The aggregate failure remains visible and must not be
reported as a full green repository check.

## What the tests establish

- Whole JSON envelopes and exact data fields are enforced; duplicate keys,
  accessors, proxies, undeclared authority fields and oversized plans are rejected.
- Each candidate is simulated from the same copied observation. Predicted boards
  and simulator boards remain separate. False board predictions and false success
  flags cannot become selected proposals.
- State contents, revisions, authorization epochs, policy and request lifetime
  bind every response. Edit/undo with a newer revision or epoch remains stale.
- Cancellation, expiry during owner reads, elapsed deadlines before timer delivery,
  backward clock changes, provider errors and late results do not yield proposals.
- The hand-authored branching example rejects a wall-corner push and proposes the
  four-action route `LEFT, UP, RIGHT, RIGHT` for review. An incomplete legal plan
  offers only its first action through `DAMP`.
- The Agima provider reports `unavailable`; no synthetic fallback impersonates it.

## Limits and next integration boundary

These checks establish a narrow implementation contract. They do not establish
Agima model quality, general planning gains, full Sokoban solvability detection,
physical safety or an authenticated action-admission system. SHA-256 binds supplied
data; it does not authenticate a caller. Revision and epoch ownership remain host
obligations. The provider interface accepts trusted host code, not an arbitrary-code
sandbox, and cancellation cannot forcibly stop code that ignores its signal.

Native assistance, permissions, saved memory and development remain with the
existing owners. A future native adapter must obtain current context from those
owners and display hypotheses without granting execution authority. Actual Agima
inference additionally needs pinned assets, CUDA infrastructure and a separately
executed evaluation. See [the integration guide](README.md) and
[upstream reference pins](upstream-reference.json).
