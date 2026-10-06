# Task-scoped lessons and document-method outcomes

19 September 2026 · Native source implementation

ARCHi can now keep a lesson for **Chat**, **Reading documents** or **Revising passages**, and order available saved document methods using their retained outcomes. This extends the existing lesson and document-work owners; it creates no additional memory database or outcome journal.

A normal Swift build and installer completed during implementation, and the installed app opened. A narrow native observation of **Work together** showed **For this work · Chat**, **0 matching lessons**, **Teach this activity**, **Revision experience**, **Saved procedures (0)** and **Qwen connected · nothing sent yet**. This confirms the new surface in the installed app, not a populated lesson/method workflow or generated answer. No profile writes, model calls, test suite or benchmark reruns were performed for this observation.

## Use

1. In the **For this work** card, choose **Teach this activity**. Review the lesson editor's **Use for** setting, write the lesson and choose **Keep lesson**. Starting a draft does not save it.
2. Choose an activity to make the lesson available for that activity without repeating its topic words. Choose **Matching topic phrase** to retain the original whole-word matching behavior. Exact-shared-copy restrictions and expiry apply in either case.
3. Open **Revision experience** to see retained document outcomes for the current shorter-text and exact-numbers/links requirements. In **Saved procedures**, available matching methods appear first. Choose **Use for this passage**, review the prepared instruction and Send explicitly; review and Apply still remain separate actions.

Kept lessons are supplied only to local Qwen. The card shows the matching lesson count for the next local request. Switching between chat, document questions and revisions starts fresh local context when sending through Qwen, so temporary context from the previous activity is not silently carried into the next one. Kept lessons still follow their selected scope. Current instructions retain precedence.

## What the counts mean

Counts describe retained **assistant/provider attempts**, not unique global tasks, independent trials or general ability. The activity card groups document records by the current length and exact-token requirements. Each saved-method entry uses only the exact procedure ID, revision and digest captured when its requests were sent. Revising a method does not transfer an older version's counts to the new version; history can still show each version's own outcomes.

| Count | Meaning |
|---|---|
| Recorded attempts | Unique retained records in the selected scope. Identical duplicate records count once; conflicting records with the same ID contribute no counts. |
| Applied | Records currently marked applied; this count alone is not a usefulness judgment. |
| Helpful | A currently applied result with valid captured learning and Helpful review, matching expected/observed result digests, passed checks and no retained procedure counterexample. |
| Corrected or withdrawn | A non-Helpful review or permanent procedure counterexample marker. A later Helpful review cannot remove a procedure's marker. |
| Undone | Records currently marked undone. This can overlap corrected/withdrawn, so the categories must not be summed as a partition. |
| Awaiting review | A checked applied result without feedback or a negative marker. Withdrawing a review does not turn it into unreviewed success. |

Unavailable or externally changed history must be recovered before the interface displays its outcomes. The computation uses the existing bounded document journal, accepts at most 64 distinct record IDs and performs no writes.

## Ordering and persistence

Only available latest method versions matching the current requirements receive outcome-based ordering. Their bounded Beta(1,1) mean is:

```text
(helpful + 1) / (helpful + corrected_or_withdrawn + 2)
```

Exact integer cross-products compare these values; ties preserve the library's prior order. Attempts without a qualifying review do not become positive evidence. This is a suggestion-order heuristic derived from the existing Beta-critic approach, not a calibrated success probability, capability certificate or general Qi/Q2E controller. Ordering never selects a method, sends a request, applies an edit or changes an appearance.

Lesson preferences now use **`archi-native-preferences/v8`**, with optional `taskScope` values `conversation`, `documentQuestion` and `passageRevision`. Known v2–v7 preference documents load through the existing migration path in memory; loading does not rewrite their bytes. An explicit save uses v8. Existing lessons without a scope retain topic-phrase matching. The existing 16-lesson/64-KiB limits remain.

Method outcomes are computed from `preferences.document-work.json` using `archi-document-work/v1`. Methods and revision history remain in `preferences.document-procedures.json` using `archi-document-procedures/v2`; there is no new saved score or inferred learning record.

Structured retrieval, cross-domain dependency graphs, purposeful planning, broader Qi/Q2E coupling, automatic procedure induction and skill certification remain open. See [reviewed document procedures](native-document-procedures.md) for the existing execution and retention path.

Implementation: [KeptLessons.swift](../desktop/Sources/ARCHiDesktop/KeptLessons.swift), [CompanionStore.swift](../desktop/Sources/ARCHiDesktop/CompanionStore.swift), [HamptonTaskWork.swift](../desktop/Sources/ARCHiDesktop/HamptonTaskWork.swift), [HamptonMethodOutcomes.swift](../desktop/Sources/ARCHiDesktop/HamptonMethodOutcomes.swift), [LessonWorkspace.swift](../desktop/Sources/ARCHiDesktop/LessonWorkspace.swift) and [DocumentProcedureViews.swift](../desktop/Sources/ARCHiDesktop/DocumentProcedureViews.swift).
