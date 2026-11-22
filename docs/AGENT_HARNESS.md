# ARCHi agent harness: a bounded first contract

`ARCHI-HARNESS-001` adds a reproducible evaluation handoff for the existing
native proposal, context, working-copy and request-binding tests. A planner
defines the acceptance contract, a generator produces a candidate, and a
separate evaluator runs the fixed recipe and checks its evidence.

The implemented boundary is **source-test evidence consistency**. The command
does not invoke or provision three language models. Role instructions below can
be used by separate agent sessions; enforcing their permissions belongs to the
controller that hosts those sessions. No model-performance or cost comparison
has been established by this change.

The source runner remains `script/accept_relationship_admission.py`. Its new
`--archi-repo` option lets a reviewed evaluator checkout test a separate candidate
checkout. Native business-state changes remain with the existing Swift owners.
An evidence result never authorizes Hampton COMMIT.

## Contract before code; candidate binding after code

There are two different artifacts:

1. **Frozen contract:** the user outcome, fixed scope and five mandatory suites.
   Freeze it before implementation and retain its digest in the controller's
   protected context. The example is
   `docs/contracts/archi-agent-harness-v1.json`.
2. **Evaluation request:** created once a candidate exists. It binds a unique
   request ID, the frozen contract, the candidate's current source manifest and
   Git commit, the evaluator code, and the observed host. Its digest is emitted
   before tests start. Retain that digest separately from candidate-writable
   files.

The final candidate hash cannot be part of requirements frozen before that
candidate has been built. Keeping these stages separate avoids silently changing
the acceptance target when the implementation changes.

| Requirement | Existing native suite |
| --- | --- |
| H01: shape, role/request identity, permitted references and authority-field rejection | `HamptonProposalValidationTests` |
| H02: current context, expiry and exact source binding | `HamptonSessionContextTests` |
| H03: exact edit target, bytes and revision | `WorkingCopyRevisionTests` |
| H04: proposal receipt, explicit Apply, revocation, Undo and export ownership | `WorkingCopyStoreTests` |
| H05: request/input/context substitution and preserved session state | `EvolutionRequestBindingTests` |

These suite descriptions identify the existing tests' scope. Passing them does
not establish factual truth of arbitrary model answers or complete behavior of
an installed application. Requirement H04 includes an existing regression that
receiving a candidate cannot apply it, as well as stale target/revision cases.

## Three role instructions

### Planner

Read the user's objective, `CONTRIBUTING.md`, the relevant native owners and this
contract. Describe the bounded outcome and exclusions. Map each requirement to
observable behavior. Use existing tests as the starting point, and identify any
missing behavior explicitly. Keep optional work separate. Hand the proposed
contract to the evaluator before implementation. The controller freezes the
agreed version; an agent cannot reduce mandatory criteria after seeing failures.

### Generator

Work in the candidate checkout. Implement the bounded feature and run development
checks. Preserve the native source/context/permission owners. Provide a concise
diff summary and reproduction instructions. Your self-checks help debugging;
they do not set the evaluator's result. Hand off the candidate at a stable point.
Make no further changes during an evaluation run. A correction produces a new
evaluation request and requires relevant checks to run again.

### Evaluator

Use a separately reviewed evaluator checkout and the controller's frozen contract
digest. Inspect behavior against the requirements before relying on a generator's
completion narrative. Run the fixed source-test recipe against the candidate.
Review raw evidence and use the verifier. Report defects, unsupported claims and
missing execution separately. Do not patch candidate code while evaluating it.
Return actionable findings to the generator. Preserve failed attempts and stop
at the controller's time or iteration budget without lowering the requirements.

For this first contract, the deterministic evaluator supplies the acceptance
result. A model reviewer can add observations but cannot convert a missing,
failed or stale mandatory result into PASS.

## Run on the review Mac

Requires Python 3.10+. The native recipe requires macOS 14+, Swift 6 and the
macOS SDK. Use a disposable review checkout with synthetic tests. Reconcile the
source with the authoring workspace before claiming anything about the user's
installed application. Keep the evaluator checkout, candidate checkout and
evidence directory separate where possible.

First freeze the reviewed contract into a new file outside the candidate:

```bash
python3 /path/to/evaluator/script/run_agent_harness.py freeze \
  --contract /path/to/evaluator/docs/contracts/archi-agent-harness-v1.json \
  --output /path/to/review/contract-001.json
```

Retain `contract_sha256` from the returned record. After the generator has handed
off a candidate, evaluate it using that independently retained digest:

```bash
python3 /path/to/evaluator/script/run_agent_harness.py evaluate \
  --candidate /path/to/candidate/ARCHi \
  --contract /path/to/review/contract-001.json \
  --contract-sha256 CONTRACT_SHA256_FROM_FREEZE \
  --output /path/to/review/run-001 \
  --command-timeout 900
```

Replace the digest placeholder with its actual 64-character value. The output
directory must be new and outside both source checkouts. The contract must be
outside the candidate checkout. The source runner uses a fresh Swift scratch
directory within that run's evidence directory. Each native command has the
specified timeout; the coordinator also bounds the overall subprocess.
On macOS and Linux, command process groups are cleaned up on timeout, controller
cancellation and command completion. This prevents ordinary child test processes
from continuing into the next suite. Deliberately detached processes require
stronger isolation and are outside this lifecycle mechanism.

The command emits `request_sha256` before execution. Retain it in the controller
or review record. To verify the same evidence later without running tests:

```bash
python3 /path/to/evaluator/script/run_agent_harness.py verify \
  --candidate /path/to/candidate/ARCHi \
  --evidence /path/to/review/run-001 \
  --request-sha256 REQUEST_SHA256_FROM_EVALUATION
```

Reverification requires the same candidate bytes, Git commit, evaluator bytes and
recorded paths. A changed candidate needs a new evaluation. Do not recalculate
the expected request pin from an untrusted changed request to make it pass.

### Result meanings

| Exit | Decision | Meaning |
| --- | --- | --- |
| 0 | `SOURCE_CHECKS_PASS` | Evidence is consistent and every required native source suite passed. |
| 1 | `BLOCKED` | Evidence is inconsistent, a mandatory test failed, or evaluation encountered an error. |
| 2 | `INCOMPLETE` | Required source execution was skipped or could not be established. |

`integrity`, `source_status` and individual findings remain separate. Consistent
evidence can truthfully report skipped or failed tests. Every result carries
`authorizes_commit: false` and `installed_app_qualified: false`, including exit 0.
The underlying acceptance runner retains its own incomplete installed-app
qualification and exit code; source-only readiness does not erase those gaps.

On Linux, the actual native suites stay SKIPPED and the coordinator exits 2.
Portable tests use synthetic native logs to test parser/verifier behavior; those
fixtures are never evidence of a native run.

## What the verifier checks

- The externally retained request digest and frozen contract digest.
- Exact required-suite selection; missing, duplicate and unexpected identities.
- Full source-file inventory before/after evaluation and at reverification,
  including tracked files and untracked files that Git does not ignore.
- Evaluator script identities and the report's candidate source references.
- Expected native commands, candidate working directory, fixed environment
  overrides, log locations and log digests.
- Native results re-derived from raw logs, using the existing nonzero-test and
  exact-suite classifiers. Framework test populations remain separate.
- Aggregate outcomes recomputed from the individual records.
- A separate execution receipt binds the actual observed runner exit, timeout
  and error state to the request and console log. Reverification cannot discard
  a recorded execution failure and accept only the raw suite summaries.
- Evidence objects with strict JSON decoding, including duplicate-key rejection.
- Safe consumed evidence paths; symlinks and traversal cannot redirect a log
  read outside the bundle. Swift build scratch is opaque and is not consumed as
  proof of qualification.

The bundle contains the frozen contract, bound request, before/after source
records, raw runner evidence, `execution.json`, coordinator console log and
`evaluation.json`.
The independent `verify` command recomputes the verdict; it does not trust a
previous `evaluation.json` as an acceptance token.

## Trust and coverage limits

This first implementation verifies consistency under an explicit trusted
controller/evaluator assumption. It does not establish operating-system
isolation, authenticated execution or statistically independent model judgment.
Two directories under the same writable account do not enforce role separation.
An actor controlling the runner, tests, logs, verifier and expected pins can
fabricate a consistent history. Tests can also print plausible summary text.

Run only reviewed candidate tests in an appropriately controlled environment.
The fixed test selection prevents an arbitrary command from entering through a
contract, but the selected repository code still executes. The recipe neither
provisions a sandbox nor proves absence of every side effect from that code.

The source inventory excludes Git-ignored/untracked inputs, dependency caches,
toolchains and external dependencies. It is not a digest of a built application
or a hermetic build. Before/after snapshots detect persistent drift, not a file
that changes and is restored between observations. Current timestamps and hashes
are recorded evidence, not external attestations.

The initial contract deliberately covers the five existing native suites. The
optional live-model demonstration, QiMovi tests, installed-app interaction,
complete restart, native media consumption and the separate Unity game retain
their own qualification requirements. No model download, cloud route, app launch,
installation, native save or release action is part of this coordinator.

## Portable verification

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s scripts/tests -p 'test_relationship_admission_acceptance.py' -v
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s scripts/tests -p 'test_agent_harness_evidence.py' -v
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s scripts/tests -p 'test_harness_process.py' -v
```

Use these checks to validate the evaluator's behavior against tampered, stale,
incomplete and well-formed synthetic evidence. Native results must come from a
separate observed Mac execution of the same candidate.
