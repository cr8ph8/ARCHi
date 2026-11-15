# CRAM candidate-solver pilot

This isolated research package evaluates energy-guided candidates and independent
validation. It does not connect to native ARCHi, Ollama, QiMovi bookings, Unity or
saved companion state. It grants no production write authority.

There are three separately labeled experiments:

1. **Official CRAM reproduction handoff.** A pinned upstream checkout, environment
   checks and explicit stage runner. The official GPU benchmark was not executed
   in the CPU-only development environment. See [the GPU handoff](official/OFFICIAL_REPRODUCTION.md).
2. **Authored miniature learned-energy probe.** NumPy pseudolikelihood training on
   4x4 Sudoku, frozen disjoint solved-board splits, bounded search, an independent
   rule checker and exact MRV reference. This is not the paper's implementation,
   data, 9x9 evaluation or hardware. No GPU speed claim is made.
3. **Synthetic scheduling and disposable admission.** Hand-set pairwise energies
   with strong and weak penalties compete with exact enumeration. Candidates go
   through independent resource/availability/precedence checks and an explicitly
   disposable COMMIT reference. This models a possible QiMovi task; it is not a
   real production booking integration or a trained scheduling model.

## Reproduce the portable run

From the ARCHi repository root, use Python 3.12+ and an isolated environment. The
only optional third-party dependency is NumPy for the learned-energy probe:

```sh
python3 -m venv ../archi-cram-venv
../archi-cram-venv/bin/python -m pip install -r research/cram/requirements.txt
../archi-cram-venv/bin/python -m unittest discover -s research/cram -p 'test_*.py' -v
../archi-cram-venv/bin/python research/cram/run_pilot.py --output ../cram-pilot-run-001
```

Use a new output directory for every run; earlier evidence is not overwritten.
`--skip-learned-probe` runs scheduling and admission without NumPy and records the
learned probe as SKIPPED. It never marks missing computation PASS.

Outputs include the frozen protocol and source hashes, scheduling task inputs,
all candidates and admissions, 32 admission-case records, miniature Sudoku inputs,
learned weights, raw predictions and independent labels, environment preflight,
summary JSON and `EVIDENCE_SHA256SUMS`. No output should be committed as generated
source. `protocol.json` is a local experiment plan, not an external preregistration.

## Exact boundaries

| Component | Status and meaning |
| --- | --- |
| Dense pairwise model | Original CPU research code; no Sudoku geometry enters the model or search |
| Sudoku evaluator | Independent row/column/box and fixed-clue checks |
| Scheduling energy | Explicit hand-set cost and conflict penalties; independent domain validator |
| Exact references | MRV for miniature Sudoku; enumeration of all permitted schedules |
| DisposableGate | Single-process scratch owner for testing explicit COMMIT, evidence binding and refusal behavior |
| Native adapter | Not implemented; no generic native COMMIT API was found on the inspected main branch |
| Official CRAM GPU evaluation | SKIPPED until a pinned checkout and real CUDA/Triton environment are available |
| RTX 4090/Windows | Not observed or executed here; Linux/WSL2 is the proposed handoff route |

Main's `HamptonProposalValidator` checks shape/reference membership; its accepted
outcome is not semantic correctness or arbitrary write authority. A future adapter
must use the existing owner for the exact target and revalidate current evidence,
source revision, scope and explicit approval there. This package does not pretend
to implement that adapter. PRs 17/18 and other unmerged branches are not dependencies.

`DisposableGate` accepts only its own bound evaluation records, checks current
context/state hashes, independently rechecks schedules before COMMIT, and denies
other targets and governance changes. PASS, FAIL, SKIPPED, ERROR and ABSTAIN are
validator states. COMMIT, REJECT, DAMP and ESCALATE are admission decisions. An
UNSAT exact reference emits no candidate and is recorded as a proposer ABSTAIN.
Model energy, confidence, termination and claimed validity cannot authorize writes.

The protected state is one scratch JSON file. Reopen checks demonstrate only
that file's persistence. Same-instance thread serialization does not establish
cross-process concurrency safety. Replay memory is process-local; audit records
and their checksums have no external integrity anchor. This is a test owner, not
a production security boundary. Repeated proposal/state pairs are escalated,
including a repeated dry-run; an approval UI would need an owner-specific review
protocol before production use.

## Interpretation

Report candidate validity, energy stopping and budget exhaustion separately. A
stopped wrong candidate is a validity failure; a valid budget-exhausted candidate
can still pass the independent task checker. Comparisons share frozen inputs,
but the exact reference has known domain rules whereas the learned model acquires
costs from examples. Their timing comparison measures these particular programs
on these fixtures, not a universal model scaling result.

The 4x4 split is by solved board within one rule family, not held-out rules or
symmetry families. No hyperparameters were changed after inspecting its held-out
results. The scheduling fixture generator includes six deliberately impossible
tasks; an energy score cannot certify UNSAT. A production problem needs its own
fixtures, cost model, independent requirements and authority owner.

## Provenance

- ARCHi base: `ffee7ea9e77632de7cb13d816bff85dc498d9c1a`.
- Upstream CRAM: `62bbe830c7d6f87f2ba18f30a28039258b986454`.
- [Paper](https://arxiv.org/abs/2611.17309v1),
  [upstream code](https://github.com/Prefrontal-AI/CRAM).
- The pilot and wrappers are newly authored under ARCHi's MIT license. Upstream
  is not vendored; its unchanged checkout retains its Apache 2.0 license.

Run the repository's required `npm run check`, then regenerate and verify the full
`SOURCE_SHA256SUMS` before submitting a source change. Native macOS, Windows/WSL
GPU, installed-app and Unity checks remain separate prerequisites where relevant.
