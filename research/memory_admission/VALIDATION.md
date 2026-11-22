# Recorded validation

Date: 2026-11-22. Base inspected: `ffee7ea9e77632de7cb13d816bff85dc498d9c1a`.

These results concern a Python/SQLite reference owner on Linux. No native Swift,
installed Mac application, real profile, or live-model execution is included.

## Paired fixture outcomes

Both arms received the same candidate bytes and initial synthetic state.

| Measure | Unchecked synthetic control | Governed reference owner |
| --- | ---: | ---: |
| False identity merges, contract cohort | 6/6 | 0/6 |
| Fully eligible true identities admitted | 8/8 | 8/8 |
| True but insufficiently supported identities withheld | 0/7 | 7/7 |
| Unknown identities committed | 1/1 | 0/1 |
| False-consistent source challenges admitted | 2/2 | 2/2 |
| False identity merges, **all** cases | 8/8 | 2/8 |

The two challenge admissions are observed semantic errors under the hidden
oracle. Their expected outcome demonstrates an assumption boundary; it does not
turn those false identities into correct merges. The matrix matches its fixed
case specifications, but the source contract is insufficient for arbitrary truth.

All 14 non-COMMIT matrix outcomes preserved the complete governed state.
Original records and sources were preserved for every case. No unexpected
transaction error was observed. All four intentionally faulty controls produced
the prohibited effect, while the governed comparison refused for the expected
reason: identity/provenance checks, evidence mismatch, or stale revision.

## Separate behavioral suite

25 unittest methods passed, with no failures or skips. Subtests include the
distinct validator outcomes FAIL, SKIPPED, ERROR, ABSTAIN, and ESCALATE; those
subtests are not added as extra test methods.

Significant observed behaviors:

- Legitimate admission survived store reopening, with original records intact.
- Fabricated PASS, missing/duplicate checks, changed candidates, changed sources,
  mismatched review, and a different policy could not authorize a write.
- Reusing a committed proposal ID could not create another effect, including an
  otherwise valid, different pair of records.
- A content-identical snapshot with a later revision invalidated old evidence.
- An exception after SQL UPDATE rolled back both the alias and replay record.
- Two real spawned processes crossed a shared barrier with competing proposals
  evaluated against the same revision: exactly one committed.
- A real worker was terminated after UPDATE and before COMMIT. Reopening recovered
  the unchanged state, and a subsequent legitimate retry succeeded.

These process tests establish behavior of this reference transaction path on the
observed platform. They are not a power-loss durability study or native profile
concurrency qualification.

## Review and reproducibility

An independent review examined all 24 saved effects, oracle separation, outcome
denominators, evidence scope, and negative controls. It prompted clearer cohort
assumptions, a matrix-specific verdict, explicit execution-error accounting, and
more precise wording about designated roots. A constructor connection was also
changed to close explicitly. No fixture outcome or independence threshold was
changed to improve an observed score. The final contract and fixture hashes are
recorded before the final run; this is a development experiment, not a claim of
externally preregistered research.

Run both commands in [README](README.md). The matrix's report retains per-case
candidate hashes, receipts, before/after snapshots, source hashes, source commit,
worktree status, platform, Python, SQLite, and descriptive timings. Behavioral
test logs and exit status are retained separately. The source manifest covers
all tracked source files except itself.

Native verification remains **NOT RUN**. The next native integration work is
specified in [NATIVE_INTEGRATION](NATIVE_INTEGRATION.md) and must preserve the
existing reviewed lesson owners. The reference owner's internal COMMIT does
not confer permission to change an installed ARCHi profile.
