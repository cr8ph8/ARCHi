# Review applied work after moving on

27 September 2026 · native development alpha

**Work together → Applied work to review** makes earlier applied edits with no
saved review discoverable in the current profile. Ordinary edits and saved-method
uses share the queue. The most recent edit still visible in its current working
copy keeps its existing review card and is not listed twice.

1. Open Work together. The queue shows up to three eligible earlier edits,
   oldest first; **Show all** exposes the remaining entries.
2. Choose **Review** to inspect its provider, date, request reference, exact method
   version when present, and recorded check details.
3. Rate **Helpful** or **Needs correction** only if you can verify the result from
   your own work. Document and reply text are not retained in this journal.
   Opening the receipt does not restore the document.
4. The sheet stays open after rating. Existing controls can keep a method from a
   Helpful result, draft a correction, or open learning review. Each is a separate
   explicit action. **Done** closes the sheet without another write.

Historical reviews have no Undo action. The current working copy's Undo remains
bound to its own latest applied edit. A review updates the existing document
journal and Usage through their current owners; it does not automatically save a
lesson, method, or companion development.

## Runtime and research connection

This closes a discovery gap in Hampton's existing attributable-feedback loop:
checked Apply → retained outcome → human review → later method/Q2E ordering.
Applied work does not become useful evidence simply by appearing in the queue.
No new scoring rule or mathematical claim is introduced. Existing outcome and
resource rules remain in `HamptonMethodOutcomes`, `HamptonMethodResourceOutcomes`
and the document Q2E adapter.

The queue is a read-only projection of the existing journal, not another store.
It requires complete matching application digests, valid learning references,
passed mechanical checks and no prior review/counterexample. New task wording,
length constraints or selected method do not filter historical review obligations.
Withdrawn source support blocks review without removing the historical receipt.

The complete scope remains bounded to 64 journal identities. Conflicting copies,
oversized scope, stale disk history, profile recovery, a pending receipt or active
work cannot appear as an ordinary empty queue. The owner checks freshness again
at each review action. Profile/companion changes close an open sheet; navigation
to correction or evolution also dismisses it.

## Evidence and remaining work

Seven projection cases and three production-owner cases passed. They cover
ordinary/method work, ordering, deduplication, invalid evidence, stale history,
restart without document restoration, explicit review/Keep, and preservation of
a different current copy's Undo. Fixtures are disposable and use in-process
clients; this increment makes no model calls and runs no ARC puzzles.

The installed app reopened with Liminal intact and displayed **No earlier edits
awaiting review** in Work together. All 23 saved profile files and 12 Unity/reader
resource files remained unchanged; the strict app signature passed. The owner
profile contained no eligible pending review, so populated receipt interaction
was checked through disposable owners, not by rating personal work. Populated owner use, meaningful
Helpful judgments and later transfer remain separate acceptance work.

See [method finder](native-method-finder.md),
[method lifecycle](native-document-procedures.md) and
[everyday outcomes](everyday-learning-and-world-outcomes.md).
