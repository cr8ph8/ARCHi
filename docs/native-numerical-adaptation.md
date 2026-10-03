# Native numerical adaptation for document revision

25 September 2026 · Source integration; installation and workflow evidence are recorded separately.

Document preparation wording updated 27 September 2026 for [explicit method selection](native-method-finder.md); the numerical definitions and evidence limits are unchanged.

ARCHi now connects numerical quotient updates, a potential-derived force and typed coupling to the existing document-revision controller. The resulting preference affects **Prepare next step** and the application-authored guidance delivered to local Qwen. The document journal remains the owner of observations, decisions, edits and reviews. There is no separate learning database.

This is the first native numerical domain adapter. It operates on reviewed task approaches. Document reading now has a separate [numerical reading adapter](native-numerical-reading.md); ARC3 retains its existing control policy. Neither adapter enables representation steering or modifies model weights.

## Three different kinds of coordinates

| State | Meaning | Current use |
| --- | --- | --- |
| Five native pressures | Support, coverage pressure, verifier pressure, alternative coverage and remaining action budget | Existing prerequisite checks, base lane weights and selection rules |
| Three approach-usefulness coordinates | Bounded policy state for retain, expand and repair, initialized to `(0.5, 0.5, 0.5)` | Numerical feedback from attributable document outcomes |
| Model-derived IQ/EQ/AQ/MQ or other latent quotients | Requires an explicitly defined and qualified model-to-coordinate mapping | Not supplied by this adapter |

The three usefulness coordinates are an authored operational definition. They are not a person's traits, a universal intelligence scale or calibrated success probabilities. They do not rename the five pressures or claim to recover latent quotient dimensions from ordinary Qwen replies.

## What enters an update

`HamptonQ2EOutcomeAdapter` reconciles the existing document journal, then selects the latest eight attempts matching the current shorter-text and numbers/links requirements. This scope can span documents; it is not an exact-passage comparison or a transfer measurement. Duplicate identical records are counted once. Conflicting records, invalid records, repeated feedback identities or evidence-size failures stop the consumer through the existing recovery path.

The numerical projection uses only local Qwen bindings that have a retained approach attribution and a known disposition. External provider rows cannot establish the effect of guidance they did not receive:

- **Support:** an applied result satisfying the established checks and retained Helpful rule.
- **Correction:** a non-Helpful review, including withdrawal, a permanent procedure counterexample, or a blocked proposal with a known failed mechanical check. Withdrawal is a negative policy observation under the existing outcome rule; it is not a new independent task.
- **Unknown:** unreviewed or insufficiently established outcomes. Unknown and unattributed bindings cause no numerical step.

The projection starts at the declared initial state and replays these current bindings in original task chronology, using record ID as the time-tie breaker. Rebuilding a view cannot add experience. A changed review replaces its earlier influence when the next projection is rebuilt. Window expiry can also change the projection; this is bounded recent adaptation, not an indefinitely accumulated ability score.

## Declared numerical configuration

Let `q` be the three-coordinate usefulness vector. For one attributable outcome on coordinate `k`, set `y = 1` for support and `y = 0` for correction. The target equals the current state on every other coordinate and equals `y` on `k`.

The adapter supplies `L = P = G = I₃`, learning rate `η = 0.25`, force gain `g = 0.25`, step norm cap `0.125`, allowed potential increase `0` and at most twelve halvings. These are versioned, authored domain settings; they have not been established as optimal.

The innovation vector contains `y` only at `k`; the error vector contains the current `qₖ` only at `k`. The force and combined proposed increment are calculated separately:

```text
F = −g G⁻¹ P(q − target)
d = η (L innovation − error + F)
V(q) = ½ (q − target)ᵀ P(q − target)
```

`HamptonNumericalDynamics` norm-caps `d`, tries a complete candidate `clip(q + 2⁻ᵇ cap(d), 0, 1)`, and checks the actual effective step and full candidate potential. The same target and `P` remain fixed during all attempts for that observation. If no candidate meets the limits, the state stays unchanged. Invalid dimensions, nonfinite arithmetic or invalid matrices reject the numerical computation; the owner does not silently substitute successful evidence.

The next observation can have a different target. A decrease in this per-observation potential establishes only the stated finite numerical condition. It does not prove global convergence across changing targets, semantic correctness or beneficial task performance.

With this adapter's identity matrices and one-coordinate observation, the force is collinear with the innovation-minus-error term. Their combination is an authored effective gain before the norm cap. Calling the force separately makes the mechanism explicit; it does not demonstrate an independent benefit from that term.

## Coupling to a real decision

The adapter uses the actual constrained difference, not the requested increment:

```text
Δq_effective = candidate − previous
Δlane = Mᵀ Δq_effective

                 retain   expand   repair
retainUsefulness  0.5     −0.125    0
expandUsefulness −0.125    0.5      0
repairUsefulness  0        0        0.5
```

Source and destination coordinate identities must match their declared order. The native helper checks a conservative upper bound on the operator norm; the adapter permits at most `0.625`. It does not estimate a causal interaction matrix or silently rescale an over-bound matrix.

Coupled changes accumulate across the replay and are added to the existing base lane weights, which remain clipped to `[0,1]`. For v3 document decisions this replaces the old per-lane Beta multiplier. Aggregate support/correction pressures still use the same reconciled observations, so the numerical projection is not an additional independent evidence source.

Hard selection rules remain in force. Missing prerequisites, exhausted budget or no available approach stop work. Correction and stalling rules retain their precedence; the numerical weights cannot bypass them.

| Selected approach | Actual document behavior |
| --- | --- |
| Retain | Preserve an explicitly selected method and authored draft. With no method attached and an empty draft, prepare an ordinary checked revision. Local guidance follows the user's supplied method and requirements. |
| Expand | With no method attached and an empty draft, prepare an ordinary checked revision for one bounded proposal; otherwise preserve the current method and draft. |
| Repair | Preserve the current method binding and authored draft. With no method attached and an empty draft, prepare a fresh approach that checks the current constraints. |
| Stop | Do not prepare or dispatch the controlled local request until the inputs are resolved. |

Prepare enables Revise mode, preserves authored draft text and sends nothing. Choosing a saved method requires the [method finder or full-library preview](native-method-finder.md) and explicit confirmation; Helpful history and numerical preference do not select one automatically. Confirmation rechecks the current draft, passage, requirements, owners and source support. A stale attached method remains visible and blocks Send, including after supporting-source withdrawal. Repair keeps that binding; **Detach procedure** is an explicit user action.

Send captures the current decision, checks it again against current owner history before generation and journals it. Same-request sibling provider lanes are excluded from that freshness comparison. If the relevant review or method changed during connection, dispatch stops instead of using stale support.

Only fixed application-authored lane guidance is included in the local model input. Numerical state, historical bindings and recorded explanations remain native data. External provider lanes receive no local controller payload. Proposal checks, explicit Apply and subsequent review remain responsible for document changes; numerical acceptance does not approve an edit.

## Receipts and compatibility

The existing `DocumentWorkRecord.q2eDecision` field retains the v3 decision and its numerical receipt. Each replay step binds the source record digest, attributed approach, disposition, force, candidate, effective delta and coupling result. Validation recomputes the numerical receipt from its frozen bindings; pre-dispatch equality additionally checks current owner history. Receipt consistency is not source authentication by itself.

| Identifier | Contract |
| --- | --- |
| `hampton-native-qstate-control/v1` | Legacy read contract; no invented predecessor or outcome lineage |
| `hampton-native-qstate-control/v2` | Existing five-pressure and outcome-binding contract; remains supported for retained records and other domains |
| `hampton-native-qstate-control/v3` | Document-revision decisions with recomputed numerical receipts |
| `hampton-document-numerical-control/v1` | This document domain configuration and replay rule |
| `hampton-approach-usefulness/v1` | Ordered retain, expand and repair usefulness coordinates |
| `hampton-numerical-dynamics/v1` | Pure bounded candidate, force and coupling primitives |

Legacy records are not rewritten or awarded missing approach attribution. The five-pressure schema remains `hampton-native-five-pressures/v1`; its effective deltas and the three-coordinate numerical deltas describe different state objects.

## Remaining boundary

This integrates the numerical mechanisms into document revision. [Document reading](native-numerical-reading.md) and [interactive ARC3](native-numerical-arc3.md) have separate numerical adapters. Further domains still need their own declared measurements, targets, coupling destinations and update schedules. Model representation readers and inference steering remain separately qualified features. General capability transfer, richer memory dynamics, multi-agent coupling and development-channel updates are not completed by a useful document review. No skill certificate, companion appearance change, extra model call, automatic practice campaign or spending authorization follows from this numerical receipt.

Implementation: [numerical primitives](../desktop/Sources/ARCHiDesktop/HamptonNumericalDynamics.swift), [document adapter](../desktop/Sources/ARCHiDesktop/HamptonDocumentNumericalControl.swift), [controller](../desktop/Sources/ARCHiDesktop/HamptonQ2EController.swift), [outcome adapter](../desktop/Sources/ARCHiDesktop/HamptonQ2EOutcomeAdapter.swift), [Prepare consumer](../desktop/Sources/ARCHiDesktop/HamptonDocumentControl.swift), [task owner](../desktop/Sources/ARCHiDesktop/CompanionStore.swift) and [local prompt contract](../desktop/Sources/ARCHiDesktop/CodexAssistant.swift).

The broader representation-reading/control research is described by [Zou et al., Representation Engineering](https://arxiv.org/abs/2310.01405v4). This task-outcome adapter does not reproduce those model interventions or establish their benefit in ARCHi.
