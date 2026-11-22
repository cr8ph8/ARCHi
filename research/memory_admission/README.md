# Memory admission: scoped evidence and an empirical map

This offline lab asks whether a narrow, explicit admission contract can preserve
useful identity links while withholding unsupported or conflicting proposals.
It is a **synthetic reference experiment**, not an implementation of native
ARCHi memory merging. The inspected application has no semantic entity-merge API.

The actual experimental effect is deliberately small: add `right_id -> left_id`
to an alias map while preserving every original record and source. No native
profile is discovered or opened. No model, network, API key, or third-party
Python dependency is used.

## Run

Use Python 3.10+ from the repository root. These commands work with ordinary
Python/SQLite; the recorded execution was on Linux, not a Mac.

```sh
python3 -m unittest discover -s research/memory_admission -p test_admission.py -v
python3 -m research.memory_admission.run_experiment --output ../memory-admission-run
```

The output directory must be new and outside this source checkout. The runner
creates temporary SQLite stores and removes them after the experiment. It writes
`protocol-freeze.json`, `report.json`, and `report.md` to the selected output.
Do not point experimental stores at real profiles or use real private records as
fixtures. This code has no production integration entry point.

## What is frozen and checked

`contract.json` defines the operation, validators, source assumptions, and
acceptance requirements. `fixtures.py` independently specifies 24 fictional
cases. Their fingerprints are captured before each matrix run. Oracle entity
IDs and expected decisions never enter candidate payloads or owner snapshots.

The candidate binds an exact operation and two record IDs to a state-content
hash, monotonic revision, source-catalog hash, and policy hash. The content hash
excludes the separately bound revision; this makes the revision check's role in
rejecting restored-content/ABA requests observable.

Five validators check closed shape, exact bindings, source-asserted identity,
designated provenance roots, and the explicitly requested relationship. A
current identity claim needs agreeing active subject keys and at least two
distinct designated roots **per record**. Document copies do not create another
root. Known inactive assertions are ignored; an unavailable cited assertion
leaves the evidence incomplete. Actual source authenticity and independence
remain input assumptions, not facts proved by counting labels.

The evaluator returns a recommendation only. The owner requires a separate,
trusted review of the exact candidate hash. Inside `BEGIN IMMEDIATE`, it rechecks
revision, content, policy, review, replay, and the entire freshly recomputed
receipt. The alias, incremented revision, and durable replay entry are written
in one transaction. Forged PASS fields cannot replace computation.

Non-COMMIT paths preserve the entire governed state, including its commit
history. Experiment traces are separate observations outside that state. A
successful COMMIT consumes a proposal ID; rejected attempts do not. Governance
requests produce ESCALATE. Insufficient source support, SKIPPED, and ABSTAIN produce DAMP;
FAIL and ERROR block admission. Omega may demote an eligible recommendation and
cannot promote an ineligible one. Test fault injection can only assign non-PASS
outcomes and is not a proposer field.

## Compare the same proposals

The matrix replays identical candidate bytes into two newly initialized stores:

1. **Proposer-only synthetic control:** an intentionally unchecked writer applies
   each scripted request. This is not a measured LLM or ARCHi's native validator.
2. **Governed reference owner:** the full contract evaluates and applies the
   candidate, or leaves the store unchanged.

The scoring oracle independently compares hidden fixture identities and reads
the actual saved alias effect. It separates true eligible cases, true but
ineligible cases, false identities, and unknown identities. Unknown truth is not
treated as either success or error. Each row retains the proposal, receipt, and
before/after state for inspection.

Four illustrative faulty paths test whether the harness notices accepting
everything, trusting supplied PASS, counting copies as independent roots, and
omitting commit-time revision checking. These controls use an explicitly unsafe
reference writer. They are not one-line mutations of the native app.

## The important failure boundary

The 22-case contract cohort contains eight eligible true identities, six false
identity proposals with detectable disagreements, seven true identities with
insufficient evidence, and one unknown identity.

Two further cases intentionally give distinct hidden entities matching, false
assertions from every designated trusted source. The gate admits those claims.
They demonstrate a limit: consistency, provenance labels, and byte integrity do
not establish external truth. The report shows these cases both separately and
inside the **overall** false-merge denominator; they are never removed from the
overall result.

The matrix verdict covers only the fixture matrix and faulty controls. The 25
behavioral tests separately exercise receipt forgery, all non-PASS outcomes,
owner review, replay, stale sources, policy changes, content ABA, rollback,
barrier-controlled competing processes, and a worker terminated after UPDATE
but before COMMIT. An unexpected transaction error invalidates a matrix result
even when REJECT happens to match the expected fixture decision.

See [recorded validation](VALIDATION.md) and
[native integration boundaries](NATIVE_INTEGRATION.md). A passing reference
test is not native Mac qualification, OS isolation, authenticated execution,
arbitrary semantic correctness, or evidence of a model's natural error rate.
Timings are descriptive local measurements, without performance claims or
statistical population-risk bounds.

## Research connection

The architectural questions were prompted by
[Fault-tolerant quantum processor with minimal external control](https://arxiv.org/pdf/2611.23919)
and [Certified Discovery of Quantum Phase Diagrams](https://arxiv.org/pdf/2611.25064).
This implementation is original classical software inspired by narrow control
and scoped evidence. It implements neither quantum algorithm and imports none
of their physical theorems or fault-tolerance guarantees.

PR [#23](https://github.com/cr8ph8/ARCHi/pull/23) already provides a distinct
source-evaluation evidence workflow. Reuse it after source reconciliation for
future native qualification; this lab does not replace it or silently depend on
unmerged branches. The app's existing explicit lesson Keep/revise/withdraw
owners remain the integration boundary.
