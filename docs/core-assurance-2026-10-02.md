# Core assurance increment — 2 October 2026

This increment hardens native model transport, saved-memory admission and attributable local records. It preserves Hampton's existing state, memory and outcome owners. It does not train a model, change quotient definitions, enable general-answer RepE, or establish a whole-system security certification.

## Concrete failures corrected

| Boundary | Previous failure | New behavior |
|---|---|---|
| Codex configuration and response envelopes | JSON dictionary decoding could silently select one value when a security field or result key was repeated. | Reject duplicate keys, including escaped and nested duplicates, before trusting configuration, correlating a result or handling a notification. Non-object envelopes are rejected. |
| Qwen locality and response identity | Inventory, model verification and streamed responses could collapse ambiguous identity, locality, content or action fields. | Inspect keys before decoding discovery, connection, pre-generation verification and chat events. Ambiguous messages cannot publish text or complete successfully. |
| Optional usage accounting | Making every duplicate field fatal would unnecessarily discard answers with bad optional accounting. | Only the six explicitly named top-level usage fields retain diagnostic-only duplicate handling. Nested duplicates and all other fields remain strict. Invalid metrics remain unavailable, never correctness evidence. |
| Reply phase ordering | A legacy completion without phase metadata could remain eligible as a final answer after delayed metadata identified it as commentary. | Apply delayed explicit phase metadata to the settled item. Reject contradictory phases without mutating the accepted stream state. |
| Saved private-memory freshness | Another local session could forget personal context or withdraw a lesson while this session still used a cached copy. | Recheck the existing preference-file baseline before local dispatch and async admission. Changed or unreadable storage cancels affected work, clears temporary context and prevents fallback. |
| Completed-reply reuse | Follow-up context and reply-derived actions could continue to rely on cached preference memory after external withdrawal. | Receipt validation, lesson selection, conversation reuse and reply-derived correction reject a stale baseline. Reopening loads the current saved state; cancellation does not overwrite it. |

The memory check deliberately uses the existing bounded preference reader (at most 64 KB). It adds synchronous read/decoding work at relevant local admission points. It cannot retract information already sent before revocation, and is not a filesystem notification service. Editor/history/export visibility and non-assistant consumers were not changed in this increment.

## Code and ownership

- [HamptonProposalValidation.swift](../desktop/Sources/ARCHiDesktop/HamptonProposalValidation.swift): shared bounded key scanner; strict by default, explicit top-level telemetry exception only.
- [CodexAssistant.swift](../desktop/Sources/ARCHiDesktop/CodexAssistant.swift), [QwenAssistant.swift](../desktop/Sources/ARCHiDesktop/QwenAssistant.swift), and [LocalInferenceMetrics.swift](../desktop/Sources/ARCHiDesktop/LocalInferenceMetrics.swift): provider parsing boundaries.
- [AssistantReplyStream.swift](../desktop/Sources/ARCHiDesktop/AssistantReplyStream.swift): final-answer eligibility.
- [CompanionStore.swift](../desktop/Sources/ARCHiDesktop/CompanionStore.swift): memory freshness, cancellation and current-receipt admission.

These are operational hardening changes, not implementations of RIDE or LoopCD. The [research mapping](research/2026-10-02-direction-calibration-and-continuity/README.md) remains separately identified. Native Q2E consumes admitted domain observations; model confidence and representation scores do not become permission or factual proof.

## Local authority and lineage

ARCHi local records remain authoritative; WikiOS is a linked interface. [The ownership map](native-authority-and-lineage.md) identifies the existing owner of each record and the boundaries for future plugins. No additional state journal was created.

Exact source and page dependencies are retained before local task dispatch in `TokenStewardStore`. Restart preserves them; identical retries do not create new evidence; changed or late-first bindings are rejected. The existing graph presents historical references with explicit availability limits. Legacy tasks remain unrecorded.

Collected Marketplace designs now retain bounded catalog acquisition declarations with the exact package digest and revision in the existing preferences file. Download review is bound to its account, session, endpoint and inventory entry. Mismatched or conflicting claims cannot overwrite an earlier acquisition; manual imports and earlier items remain without inferred title evidence. The inspector labels publisher rights as declared rather than verified legal ownership.

Preferences v10 reads the prior known formats in memory; only an explicit save writes the new format. The migration also repairs a pre-existing loader mismatch that rejected the optional source-provenance field in valid kept-lesson origins. Lesson-only export excludes item acquisition metadata; removing an item removes its attached acquisition record. A binary rollback alone does not downgrade a v10 profile.

Three identical redirect-denial delegates were replaced by one shared `HTTPNoRedirectPolicy`. Endpoint, scheme, response and budget checks remain with their transports. Active domain stores were not deleted as presumed dead code.

## Focused evidence

The app and selected checks compiled from the curated checkout, based on `3670504`, with only this increment applied. Unrelated authored WikiOS, visual and phone work in the main checkout was preserved.

**74 focused tests passed:** 10 XCTest tests and 64 Swift Testing tests. Coverage includes duplicate configuration rejection before document dispatch, Qwen connection and re-verification, streamed identity/action ambiguity, optional metric compatibility, delayed phase handling, two-session memory revocation, cancellation/fallback, unchanged-memory success, typed proposal validation and numerical bounds. Parameterized paths are not added again to that count.

The numerical checks cover finite-step overshoot/backtracking, SPD metric force, actual clipped-delta coupling, declared norm bounds and rejection of malformed/nonfinite inputs. They establish these implementation properties, not universal stability or improved reasoning.

Provider tests use local fixtures; memory tests use temporary synthetic profiles. No live model calls, puzzle runs, training or broad benchmark suite ran. Existing accessibility deprecation warnings appeared while compiling other test files; those tests were not executed by this filter.

Read-only independent review found no additional issue in the first hardening patch. This is a bounded review, not a penetration test or a guarantee against a compromised provider.

The subsequent source-lineage and shared-network check set passed **90 checks**: 50 XCTest and 40 Swift Testing tests. Seven are the new provenance cases, including a synthetic app-owner dispatch and restarted graph inspection. Existing provider cases overlap the earlier run; these counts are not summed as unique tests.

The acquisition and profile migration set passed **53 focused XCTest checks**, including nine new acquisition tests, the v9 source-provenance restart repair, existing collection behavior and backup/recovery cases. The updated native Marketplace interaction and live-service fixtures compiled; they were not executed. There was no live catalog purchase or publisher-rights verification.

## Delivery record

The later installed Liminal repair added two original Seed PNGs without changing program logic. Both exact assets are included in the curated package, and the existing preserved-Seed verifier runs before package promotion. No artwork or physics was redesigned.

Installation and preservation results are recorded separately in the [delivery evidence](accountability/evidence/r02-core-assurance-2026-10-02.json). Raw local checks and the scoped patch are under `output/core-assurance-2026-10-02/`. Private profile hash inventories remain local and are not publication artifacts.

Remaining work includes useful real-task transfer, broader reader qualification, live provider compatibility and current physical-phone acceptance. These fixes do not remove those release blockers. The new lineage records improve attribution; preserving source facts and explicit limitations in everyday generated proposals still needs real-task qualification.
