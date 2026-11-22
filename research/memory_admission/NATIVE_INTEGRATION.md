# Native integration boundary

## Audited source and scope

This integration note records a read-only audit of ARCHi main at
`ffee7ea9e77632de7cb13d816bff85dc498d9c1a`, performed on November 22, 2026.
The portable memory-admission experiment is an isolated reference implementation.
Its SQLite database contains synthetic records and is not an ARCHi native profile.
No Swift implementation, installed application, model service, or real profile was
exercised by that audit.

The authoritative ownership descriptions are
[CONTRIBUTING.md](../../CONTRIBUTING.md) and
[docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md). The
[audited source revision](https://github.com/cr8ph8/ARCHi/tree/ffee7ea9e77632de7cb13d816bff85dc498d9c1a)
provides the baseline for every statement about existing behavior below. Later
branches must be inspected independently before these statements are carried
forward.

## What the native application currently admits

| Existing owner | Actual responsibility at the audited revision |
| --- | --- |
| `HamptonProposalValidator` | Parses reasoning, memory-selection, and memory-reminder responses; checks closed JSON shape, exact role/request identity, bounded text, and supplied-reference membership. |
| `HamptonAdmissionOutcome` | Reports `accepted`, `rejected`, or `stopped`; explicitly limits acceptance to structural checks under current request ownership. |
| `HamptonReasonsAssistant` | Publishes an answer and tentative session context; has no action or durable-write port. |
| `HamptonSessionContext` | Retains exact app-produced spans with snapshot checks, expiry, source revocation, and reminder eligibility. This is temporary context. |
| `CompanionStore` | Owns explicit reviewed lesson creation, revision, withdrawal, and the publication of saved choices after persistence succeeds. |
| `CompanionGraph` | Builds a read-only projection of existing records and receipts; creates no inferred relationship database or mutation authority. |

There is **no semantic entity or memory-merge API in the inspected native path**.
Native `accepted` does not mean semantic identity was established, a factual claim
was proved, or permission to change durable memory was granted. A portable lab
`COMMIT` must not be substituted for that native status.

The relevant source files are:

- `desktop/Sources/ARCHiDesktop/HamptonProposalValidation.swift`
- `desktop/Sources/ARCHiDesktop/HamptonAdmissionOutcome.swift`
- `desktop/Sources/ARCHiDesktop/HamptonReasonsAssistant.swift`
- `desktop/Sources/ARCHiDesktop/HamptonSessionContext.swift`
- `desktop/Sources/ARCHiDesktop/CompanionGraph.swift`

## Existing durable lesson seam

`desktop/Sources/ARCHiDesktop/CompanionLessons.swift` defines
`LessonCorrectionDraft`: a reviewable draft carrying an expected preference
revision, the exact prior lesson when revising, desired content, and optional
source, origin, and expiry fields.

In `desktop/Sources/ARCHiDesktop/CompanionStore.swift`, `keepLesson(_:)` checks the
current revision, prior value, source binding, content validity, expiry, and
capacity. `withdrawLesson(id:expectedRevision:)` checks revision and existence.
Both use the private `commitPreferenceDocument(_:)` boundary. That method
increments the document revision and updates admitted in-memory state only after
the persistence operation succeeds. Keep must also preserve unrelated saved
choices rather than implicitly saving other drafts.

`desktop/Sources/ARCHiDesktop/KeptLessons.swift` defines the existing
`NativePreferenceDocument` and
`NativePreferencePersistence.write(document:to:expected:)`. At the audited main
revision, persistence compares exact loaded bytes twice and atomically replaces
the file. Its source explicitly states that this is **not a cross-process
database transaction**. Do not infer native concurrency guarantees from the
reference lab's SQLite transactions.

[PR #18](https://github.com/cr8ph8/ARCHi/pull/18) contains separate native profile
serialization work. It is not present in this audited main revision. A future
integration must inspect and reconcile its current implementation before relying
on a shared lock across Keep, withdrawal, preference saves, and recovery.

## How future evidence checks should fit

A model may prepare a candidate or explain a possible relationship. Its output
must not acquire a new durable-write route. A useful first native integration is
to attach scoped evidence to an explicitly reviewed lesson draft and validate
that evidence through the existing owner. A semantic merge would require its own
defined operation and review behavior; it cannot be obtained by renaming Keep.

Bind evidence to the exact proposed effect, relevant source records, policy and
validator versions, and current owner revision. Recheck freshness at the actual
mutation boundary under the reconciled synchronization mechanism. Hash equality
establishes byte consistency, not source truth or identity. Source-content
identity and a monotonic owner revision have different meanings and must remain
explicit.

Graph inspection must remain read-only. A chain of similarity links supplies no
automatic permission to merge records. Displaying a path or evidence summary
must not keep a lesson, invoke inference, or award companion development.

## Required Mac follow-up

Use a reconciled, disposable checkout and synthetic preference location on macOS
14 or later with Swift 6 and the macOS SDK. Retain explicit results for:

1. Native compilation and the existing `HamptonProposalValidationTests`,
   `HamptonSessionContextTests`, and `LessonStoreTests` populations.
2. Reviewed Keep, revision, withdrawal, discard, and save-close-reopen behavior,
   comparing saved bytes and reconstructed records through an independent reader.
3. Changed source, stale draft, forged prior value, cancellation, expiry, and
   persistence failure, including preservation of unrelated saved choices.
4. Competing operations and profile recovery through the actual reconciled native
   synchronization boundary. A sequential conflict check is insufficient evidence
   for cross-process serialization.
5. The user-visible review flow and confirmation that an accepted model answer
   cannot automatically keep or merge durable records.

Existing lesson and context tests already cover many of these cases. Reuse them
and add only checks for concrete new behavior. Keep executed failures, skipped
prerequisites, and unobserved installed-app behavior distinct.

[PR #23](https://github.com/cr8ph8/ARCHi/pull/23) supplies a separate source-evaluation
contract and evidence-verification workflow, stacked on PR #20. Reuse that work
after dependency reconciliation instead of introducing another source-inventory
framework. Its qualification is separate from application runtime acceptance.

Portable results establish behavior only for the reference policy, fixtures,
evidence binding, and reference transaction implementation actually exercised.
Native mutation rates, live-model performance, semantic truth, and installed-Mac
qualification remain unmeasured until those respective paths run.
