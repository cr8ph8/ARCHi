# Active document work in ARCHi

ARCHi uses its existing local Qwen/Reasons and native Work together pipeline for a bounded working task: revise one selected passage. This integrates observation, a declared objective, proposal, verification, explicit application and retained outcome into ordinary assistance. It does not run an ARC benchmark or establish general ARC-to-document transfer.

## Use

Choose a UTF-8 document in Work together, select a passage, and choose Rewrite or Shorten. Set the visible requirements, edit the instruction and Send through the selected provider. Review Before/After and the mechanical checks, then Apply or Dismiss. Apply affects only the app-owned copy; Undo is available for that exact result. Export creates a separate draft.

Local Qwen remains the local route. Existing explicit Codex/Compare choices use the same captured revision target and independent lane ownership; no new fallback, paid route or second model broker was introduced. Preparing a task does not send it.

## Review an applied change

The retained task offers **Helpful**, **Needs correction** and **Withdraw review** after Apply, including after its visible reply is cleared. These are explicit user judgments of the completed edit. Mechanical checks and Apply never select a verdict.

- **Helpful** records that the change helped your work. **Needs correction** records that the outcome needs improvement. **Withdraw review** retracts the current judgment; the event remains identified in task history.
- The review is saved in the document journal before its corresponding Usage update. Usage records usefulness separately from independent checker results. If either stage needs reconciliation, the task shows **Retry sync**; retrying uses the same feedback event rather than counting the work again.
- **Add to learning review** is a separate choice for a helpful outcome. It binds the observed edit to the original request and source fingerprints. Evolution remains a session choice until **Save evolution**; this action does not save unrelated preferences or change the Seed or kept appearance.
- If the request cited a kept lesson, **This lesson helped** is available only for the exact captured version that is still kept and unexpired. A model citation does not establish that the lesson helped. Editing, withdrawing or expiring a lesson does not silently substitute its replacement version.
- **Write a correction to keep** opens a draft in Memory with the original request reference. The user writes the guidance and chooses its scope, then explicitly selects **Keep**. Neither the verdict nor generated text creates a lesson automatically.

Changing a helpful judgment to correction or withdrawal excludes that document evidence from the current learning review and from a later Load of older evolution data. **Save evolution** retains the withdrawal in the evolution save itself; the document judgment remains retained independently. These changes preserve a previously kept appearance. Feedback is an input to review, not a completed adaptive Q2E controller or a certified learned procedure.

## Implemented contract

- `RevisionTarget` binds source SHA-256, source revision, exact UTF-16 selected occurrence and immutable requirements at Send.
- `DocumentWorkCapability` checks the existing closed proposal schema, exact current source, size, revision capacity, unchanged surrounding bytes, optional shorter Unicode-character length and exact numeric/literal-URL token counts.
- Token preservation is deliberately literal, including punctuation within URL tokens. It does not resolve URLs, recognize every relative link or establish semantic equivalence.
- Apply remains explicit. A pending receipt with the predicted output digest is persisted before mutation; the native owner then checks the actual resulting bytes. Undo uses the same pending/observed discipline. A failed final receipt is retained in the current session for explicit retry; Undo is enabled only after the completed Apply receipt is saved.
- A per-profile `preferences.document-work.json` sidecar retains up to 64 metadata records, preserving active work and every reviewed record. It contains IDs, digests, requirements, authored check labels, lifecycle states, optional captured learning references, feedback revisions and Usage acknowledgment. It contains no document text, prompts, model explanations or correction text. The lock and fresh disk baseline reject stale writes.
- A new verdict receives a new event ID and the next feedback revision; exact retries retain their ID. Previously applied legacy records remain readable without fabricated request or lesson references. New feedback requires retained completed-work evidence. Interrupted Undo preserves prior feedback as history, without authorizing a fresh positive learning claim.
- Reviewed records remain pinned even after Usage synchronization so that older evolution saves cannot revive withdrawn evidence through automatic history pruning. When 64 active or reviewed records fill the journal, new document work can be blocked. Explicit reviewed-history removal is future work; the app does not silently discard those judgments to make room.
- Restart cancels unexecuted proposals and marks interrupted mutations unverified; history never replays an action. Completed history remains inspectable but does not restore an unsaved working copy.
- Shared revision cards serve Work together, Chat and the Seed bubble. Existing selection/spatial invalidation remains in force: changing the selection, leaving its document surface, moving ARCHi or replacing context can retire a proposal. This update does not promise seamless task resumption across navigation/restart.
- Activity map retains document execution nodes after Apply clears a reply. Usage links require the exact existing request ID; document actions do not double-charge model usage or count as semantic acceptance.

## Evidence boundary

Mechanical checks do not prove truth, preserved meaning, writing quality, general intelligence, a learned skill or companion evolution. The user reviews those properties. A successful Apply must not automatically mark a task useful or a lesson learned.

For the initial working-copy delivery, the focused check group was `DocumentWorkCapabilityTests|DocumentWorkJournalTests|WorkingCopyStoreTests`: 7 XCTest cases and 10 Swift Testing cases passed across the recorded focused runs. No full suite, ARC environment, new model call or paid request ran for that integration. Installed native inspection confirmed the requirements controls and dark-mode layout; a fresh live Qwen revision was not executed during that inspection.

The feedback bridge is a subsequent increment. Its focused journal and integration checks use controlled task/receipt fixtures; validation and installation evidence belong in the [developer ledger](../PROJECT_ACCOUNTABILITY.md). This document does not claim that a live provider feedback cycle or installed native feedback interaction has been exercised.

## Hampton integration priorities after this delivery

1. **Outcome-led adaptation.** The explicit feedback bridge now retains user judgments and admits selected outcomes to learning review. Next, define how repeated reviewed outcomes and counterexamples affect bounded task decisions. The present increment does not automatically adjust numerical quotient state, generalize lessons or certify skills.
2. **Task-scoped memory and dependencies.** Extend the current lexical/topic and exact-source matching to declared task scopes and versioned lesson dependencies, including correction/withdrawal propagation. Keep generated hypotheses distinct from user-confirmed guidance.
3. **More typed working capabilities.** Add extraction and comparison with their own objectives, source observations and completion criteria. Reuse cancellation, providers and accounting rather than a second runtime.
4. **Reviewable procedure learning.** Retain expected effects, observed outcomes and counterexamples across reviewed tasks. Offer scoped procedure candidates; do not automatically promote task-local ARC3 observation/action mappings into general skills.
5. **Bounded orchestration.** Add an optional local reviewer/correction pass with a fixed call budget and retained disagreements. Review evidence cannot itself authorize Apply.
6. **Task continuity.** Resume only by reacquiring and validating the original source, preserving the same companion identity and causal history. Metadata history is not a complete working-state snapshot.

These are code-grounded implementation gaps, not claims that all historical Q2E equations have been installed or validated. The native Reasons roles, exact-span memory, kept lessons and admission controls already implement parts of Hampton's architecture. The recovered ARC donor's Beta critic currently influences static-grid verification ordering; it is not a general adaptive quotient controller throughout the app. A broader numerical controller needs explicit observable state definitions, bounded update contracts and measured application outcomes before integration claims are made.
