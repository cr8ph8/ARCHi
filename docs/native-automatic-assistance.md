# Local Qwen assistance and optional external reference

Updated 29 September 2026 · existing native desktop app. The current routing summary supersedes the 13 September local-only policy description; the dated verification below retains its original scope. See [native Qwen setup](native-qwen.md) for the existing model connection workflow; this guide records the current route and payload boundaries.

## Current routing rule

**Qwen is the base assistant. External fallback requires the user's explicit Local + Codex fallback choice.** First-run or unreadable saved preferences select Local only. A local failure under that route stops locally; a qualifying failure under the explicitly selected fallback route can dispatch one Codex request.

| Choice | What Send does | If it cannot finish |
| --- | --- | --- |
| Local only — first-run default (`.automatic`) | Connects local Qwen when needed and uses the selected local work policy. | Stops locally. No external connection or request follows. |
| Local + Codex fallback (`.native`) | Starts with local Qwen under the selected local work policy. | An eligible connection, generation or timeout failure can send at most one Codex request. Invalid output, cancellation and optional-context failure do not authorize fallback. |
| Local · manual connection | Uses the selected installed Qwen through local Ollama after Connect. | Shows the local failure. The user can reconnect/retry or choose another route. |
| Codex · external | Sends the current request through the user's connected Codex/ChatGPT account, after explicit route selection and Send. | Shows the failure; no automatic provider change or retry. |
| Compare · local + Codex | Sends deliberate independent requests to connected local Qwen and Codex. | Retains individual outcomes; one lane does not retry or replace the other. |

The internal `.automatic` case means **Local only**, while `.native` means **Local + Codex fallback**. Explicit route choices persist across restart independently of companion profiles. Choosing a route or connecting a provider does not send the draft/shared document. **Local work** separately selects Auto, Compact or Reasoning; Auto's narrow greeting rule is not a learned capability-ranking router.

The local Reasoning and Compact/context assignments are saved in versioned device settings. The 25 September delivery recorded Reasoning = `qwen3.5:9b`, Compact/context = `qwen3:1.7b` and Auto selected across a restart; these installed selections are distinct from factory defaults. Connect verifies the selected installed model. The native selector does not download a model or accept a remote Ollama endpoint. Both Qwen and external generative models have model/data provenance and licensing questions; local execution controls where this request is processed and does not certify training provenance or output rights.

## What an external request contains

Selecting Codex or Compare and pressing Send, or an eligible recovery after Send under Local + Codex fallback, shares the question, the **full deliberately shared document copy**, its source/selection metadata and confirmed reply settings. Selecting one passage does not trim the document payload to that passage. Kept lessons, personal-profile context, temporary memories, local conversation and local partial answers remain local. Kept multi-source reading dependencies and representation measurements prevent automatic external fallback; captured context retains its exact-copy allowance checks.

The request captures immutable settings, source and selection on Send. Changing the draft or a preference while work is pending affects a subsequent Send; it does not relabel the historical receipt. Switching routes cancels the old work. Fallback uses the owned captured request and must pass the current eligibility checks. A subsequent explicit external Send captures the then-current visible request and receives a new request ID.

External processing is subject to the selected provider/account terms. ARCHi makes no copyright, confidentiality or exclusive-ownership guarantee. The Codex adapter uses an ephemeral, restricted shared-text session; this runtime restriction is not a guarantee about provider-side data handling. The adapter does not report a resolved model identity, and the UI says so.

**Available adapters:** local Qwen through Ollama, and Codex through the existing ChatGPT account. **Planned, not connected:** a direct ChatGPT/OpenAI API adapter and Claude. They must not appear as working choices before a real adapter, credential handling, disclosure, cost controls and request/cancellation checks exist. None was added or configured in this increment.

## What remains intact

- One desktop companion and the existing native request owner; no new assistant state owner.
- Immutable settings and input receipts; separate Compare outcomes, local model identity and invocation accounting.
- Stop, source/placement/selection changes, model/context changes and shutdown fence late callbacks.
- Local context commits only after the validated final answer. Failure and cancellation cannot promote tentative context.
- Kept lessons remain explicit and local. External output is a reference, not an automatic lesson, permission, edit or evolution event.
- The existing provider choices remain under user control. Qwen success/failure is not a quality judgment establishing which provider is best for a person.

## Historical verification: 13 September 2026

See `output/local-first-routing-2026-09-13/` for pre-edit snapshots and focused test logs. That increment's final focused run passed **35 XCTest cases and 25 Swift Testing cases, with zero failures**. Tests used controlled assistants and no live providers. Coverage included local selection/no-work, successful local answers, connection and generation failures, invalid responses, timeouts, cancellation, local identity/budget failures, an already-connected Codex lane, stale callbacks, local retry, explicit external choice after failure, independent Compare and captured preferences. This is historical evidence for the local-only policy, not a fresh qualification of every current route.

The explicit diagnostic documented for that local-only increment is:

```sh
desktop/.build/debug/ARCHiDesktop --automatic-assistant-smoke
```

It performs one real local Qwen answer on synthetic text and an injected local outage. Its external adapter is an in-process counter that refuses work, so a regression reports attempted external use without contacting a real external provider. It emits `archi-automatic-assistant-check/v2`. This diagnostic was **not run** for the routing change; controlled test evidence and a live local answer are separate.

## Historical checkpoint: 8 September

The earlier increment introduced an optional Qwen-to-Codex fallback to address connection/recovery problems. Its bounded real demonstration succeeded with Qwen, then used an injected local outage to reach real Codex. The 13 September policy superseded that behavior; later increments added the current explicitly selected, bounded fallback route. These receipts remain evidence of the 8 September implementation, **not current-route acceptance**:

- `output/assistant-arc-2026-09-08/delivery.json`
- `output/assistant-arc-2026-09-08/automatic-live.json`
- `output/assistant-arc-2026-09-08/hampton-before.json`
- `output/assistant-arc-2026-09-08/codex-answer-before.json`

The existing Hampton admission outcome still distinguishes accepted, rejected and stopped attempts with a stage/reason. It verifies structure, references and current request ownership; it does not establish factual correctness or ARC benchmark capability. The separate ARC lab and Arena are outside this desktop routing increment.
