# Native document reading

Status: **19 September 2026 — built and installed.** The final installer compiled the section-boundary refinement successfully (3.72 seconds) and preserved the previous app. The final installed Work together surface showed **Read with context**, **Find relevant passages**, the existing Garnet companion and Qwen ready. This is the third concrete consumer of the [native Q2E controller](native-q2e-control.md), alongside passage revision and ARC3 planning.

Earlier in this same increment, before the final section-boundary refinement, `docs/native-q2e-control.md` was shared locally with the question “How does the Q2E controller use document feedback to choose the next approach?”. **Find relevant passages** showed **Try a bounded alternative**, **5 of 6 source sections · partial context**, and exact source ranges/digests. That populated preview was not repeated after the refinement. No content was sent; no tests or model calls ran. Answer generation, feedback persistence and the full write flow were not exercised.

In Work together, open a shared document or meeting notes, enter a question and choose **Find relevant passages**. The preview shows the selected source sections, ranges and partial/full coverage. **Send** captures the current source and question again, then uses the bounded section plan for local Qwen. An eligible completed answer has **Helpful** and **Needs correction** controls. These explicit judgments affect the next reading decision for that exact source.

## What the reader selects

[DocumentReadingPlan.swift](../desktop/Sources/ARCHiDesktop/DocumentReadingPlan.swift) indexes Markdown headings and their ancestry, ignoring apparent headings inside fenced code. Unheaded text is also indexed. Sections are split around a 2,600-byte target without splitting a grapheme; source ranges use UTF-16 offsets, while digests bind exact UTF-8 text. A current selected passage is retained within a complete section when possible, or as its own exact source span. Invalid or oversized selections stop preparation rather than being silently truncated.

Question terms match headings and section text using deterministic lexical scoring. The current bounds are six sections and 9,000 UTF-8 bytes including section titles, from a source of at most 100,000 bytes and a question of at most 16,000 bytes. The local assistant's existing encoded-request budget still applies after instructions and other local context are added.

The Q2E lane changes the actual section selection:

| Lane | Reading behavior |
|---|---|
| Retain | Prefer section IDs from a helpful answer to the exact same question and source, alongside current lexical relevance. |
| Expand | Favor relevant sections, using heading-branch diversity as a small tie-break. |
| Repair | Add neighboring source sections around the selected anchor, then fill remaining space by relevance. |
| Stop | No reading request is dispatched. |

The planner checks source/question digests, unique non-overlapping section identities, exact source ranges, selection coverage and the coverage flag. This validates which text was supplied. It does **not** establish that the excerpts contain everything needed or that the answer follows from them. Supplied and cited sections are distinguished in the reply; omitted coverage is visible.

## Decision, result and review

[HamptonDocumentReading.swift](../desktop/Sources/ARCHiDesktop/HamptonDocumentReading.swift) projects the latest eight completed, dispatched Qwen `ANSWER` tasks for the exact source digest from the existing Token Steward journal. Only the latest `document-reading:` user verdict for each task counts. Generic usefulness feedback, unreviewed answers, failures, `CLARIFY` and `ABSTAIN` do not become positive or negative reading evidence.

Those bounded records supply support/correction counts and per-lane Beta outcomes to the shared controller. Alternative count is the indexed section count, capped at 4,096; the action budget is one Send, with no stall count. Preferred section IDs come from the latest helpful record with the exact question digest. A changed source digest starts a separate history. This is an authored retrieval policy updated by explicit reviews, not learned coupling or a calibrated measure of reading ability.

The execution order is concrete:

1. Capture and validate the reading plan and Q2E decision against the current request.
2. Retain `DocumentReadingTrace` before Qwen dispatch: source, question and plan digests; section IDs; frozen decision.
3. While that Qwen lane is dispatched and pending, retain `DocumentReadingResult`: exact returned-answer digest, `ANSWER`/`CLARIFY`/`ABSTAIN` kind and cited section IDs from the supplied plan. Then finalize the lane.
4. Admit reading feedback only for a retained `ANSWER` and a dispatched, completed Qwen lane. The UI also checks current source revision, source digest, request ownership and displayed-answer digest. Repeated identical verdicts are idempotent; reversals append a new UUID evidence event.

[TokenSteward.swift](../desktop/Sources/ARCHiDesktop/TokenSteward.swift) stores this optional provenance in its existing task/outcome journal and validates the joins when reading it. Legacy tasks have nil reading fields. Changed traces/results and first late writes are rejected; exact retained records can replay without mutation. Generic feedback writers cannot use the reserved reading prefix. The increment creates no second memory database and adds no source, question or answer text to the persistent accounting journal. The existing transient request, reply and optional local-conversation paths keep their own scope.

## Route and capability boundaries

[AssistantRequest in CodexAssistant.swift](../desktop/Sources/ARCHiDesktop/CodexAssistant.swift) supplies selected excerpts only in the local reading input. The common request retains the full original shared copy for freshness and for the disclosed external route. Codex, Compare and eligible native fallback retain their existing sharing rules; reading selection is not an external redaction feature. A cloud-only result cannot receive reading-strategy feedback.

This is a native structured-retrieval implementation inspired by heading-aware/source-bound retrieval ideas. No STAIR model was installed or trained. There is no automatic skill certification, capability award, companion evolution or appearance change. Semantic retrieval across retained memories, cross-document dependency invalidation, factual verification and demonstrated transfer remain separate work.

## What this demonstrates

| Claim | Current evidence | Limit |
|---|---|---|
| Native, bounded source retrieval is reachable. | [Section selection and exact-source checks](../desktop/Sources/ARCHiDesktop/DocumentReadingPlan.swift), [reading controls](../desktop/Sources/ARCHiDesktop/HamptonDocumentReading.swift), and the installed preparation observations recorded above. | The populated preview preceded the final section-boundary refinement. Selecting relevant text does not verify an answer. |
| The implementation binds a reading decision, returned result and explicit review to one task. | [Trace/result types](../desktop/Sources/ARCHiDesktop/DocumentReadingTrace.swift), [journal lifecycle guards](../desktop/Sources/ARCHiDesktop/TokenSteward.swift), and [dispatch/result integration](../desktop/Sources/ARCHiDesktop/CompanionStore.swift). | This lineage is implemented and compiled; generation, feedback persistence and the full write flow were not exercised in this increment. |
| Hampton's authored controller design has an identifiable native adaptation. | [Native Q2E definitions and donor derivation](native-q2e-control.md), [pressure mapping and Beta updates](../desktop/Sources/ARCHiDesktop/HamptonQ2EController.swift), and [reading-specific observations and actions](../desktop/Sources/ARCHiDesktop/HamptonDocumentReading.swift). | Source traceability establishes which mechanism was implemented. It does not establish empirical advantage, learned coupling or a general intelligence measure. |
| Retrieval quality, adaptive benefit and transfer across tasks remain unestablished. | The retained evidence is compilation, installation and bounded native preparation, with the limitations above. | No controlled comparison, trained STAIR model, generalization result, skill certification or patent validation is claimed. |

For an author-led demonstration during actual use:

1. Share a document whose contents you can check, select **Local Qwen**, and ask one concrete question. Choose **Find relevant passages**; inspect the source ranges, section count and omitted coverage before Send.
2. Send the request. Compare the answer with the supplied sections and original source. Treat citation membership separately from factual support; a clarification or abstention is not a failed reading judgment.
3. For a completed `ANSWER`, use **Helpful** or **Needs correction** while that exact source and displayed answer remain current. Describe the particular omission or contradiction in the next question when needed.
4. Prepare another reading and inspect its approach and sections. An identical question can reuse helpful section IDs; a different question receives fresh lexical selection. Changing the source starts separate outcome history. Report the actual before/after observations without promising that one review must change the selected lane or improve the answer.

These are demonstration instructions, not a record of an additional run.

Source owners: [HamptonDocumentReading.swift](../desktop/Sources/ARCHiDesktop/HamptonDocumentReading.swift), [DocumentReadingPlan.swift](../desktop/Sources/ARCHiDesktop/DocumentReadingPlan.swift), [DocumentReadingTrace.swift](../desktop/Sources/ARCHiDesktop/DocumentReadingTrace.swift), [CompanionStore.swift](../desktop/Sources/ARCHiDesktop/CompanionStore.swift) and [TokenSteward.swift](../desktop/Sources/ARCHiDesktop/TokenSteward.swift).
