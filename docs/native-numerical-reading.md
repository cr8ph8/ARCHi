# Native numerical adaptation for document reading

25 September 2026 · Source integration; installation and workflow evidence are recorded separately.

ARCHi extends the native numerical controller into **Read with context**. Explicit reviews of completed local Qwen answers change a bounded preference for retaining helpful passages, widening coverage or repairing the reading context. The selected approach changes the excerpts supplied to the next local answer and the application's reading instruction. Token Steward remains the owner of task, answer and review provenance; this adapter adds no separate learning database.

This is a second declared task domain alongside [document revision](native-numerical-adaptation.md). Its input is attributable task feedback. It does not extract latent IQ/EQ/AQ/MQ from Qwen, steer hidden activations or change model weights.

## What the reading state means

The numerical state has three ordered coordinates: `retainReadingUsefulness`, `expandReadingUsefulness` and `repairReadingUsefulness`. Each starts at `0.5`. These are authored policy coordinates, not calibrated answer-correctness probabilities, a person's characteristics or a general intelligence score. They are separate from the controller's existing five pressures: support, coverage, verification, alternatives and remaining budget.

One observation belongs to one completed local Qwen reading task. Its frozen binding identifies the source set, question, chosen sections, native approach, returned answer and latest explicit reading review. A **Helpful** review supplies `1`; **Needs correction** supplies `0`. Generic task usefulness does not establish a reading judgment. Unreviewed answers, clarification, abstention, failed local lanes and external-provider answers supply no numerical step.

The projection reconciles matching-source records before selecting the latest eight completed local `ANSWER` tasks, including answers that have not been reviewed. Unreviewed answers remain unknown within that window. Conflicting task identities, malformed records, repeated review identities and size-limit failures stop the consumer rather than become a smaller favorable sample. A source-set digest includes the primary text and any explicitly retained reference identities, revisions and digests. Changed primary text or a changed reference version therefore has a different context. Tasks are ordered deterministically by original start time with task ID breaking ties, then replayed in original chronology.

Repeated presentation does not accumulate experience. Reversing a review replaces that task's previous observation when the projection is rebuilt. It does not create another task or erase incurred usage. Window expiry can change the projection too; this is adaptation from recent source-scoped evidence, not unlimited accumulation of ability. Reading histories remain separate from document-revision histories.

## Numerical update and coupling

For a reviewed approach `k`, let `y` be its current binary review. The target equals the current state except at `k`, where it equals `y`. The adapter retains the distinction between the innovation/error increment and the potential-derived force:

```text
F = −g G⁻¹ P(q − target)
d = η (L innovation − error + F)
V(q) = ½ (q − target)ᵀ P(q − target)

q_candidate = clip(q + 2⁻ᵇ cap(d), 0, 1)
Δq_effective = q_candidate − q
Δlane = Mᵀ Δq_effective
```

The versioned domain configuration sets `L = P = G = I₃`, `η = 0.25`, `g = 0.25`, a step norm cap of `0.125`, zero allowed potential increase and at most twelve halvings. Innovation contains `y` only at the reviewed coordinate; error contains the prior value of that coordinate. Its authored coupling matrix has source coordinates as rows and retain/expand/repair weights as columns:

```text
M = [[ 0.5,   -0.125, 0  ],
     [-0.125,  0.5,   0  ],
     [ 0,      0,     0.5]]
```

The checked operator-norm upper bound must not exceed `0.625`. Coupled changes accumulate across the bounded replay and adjust clipped lane weights. These fixed coefficients are not a learned causal matrix or an established optimum. With identity `L`, `P` and `G`, the force is collinear with innovation minus error: together they set an effective gain before the norm cap. Their separate calculation does not demonstrate an independent force benefit.

The finite candidate helper checks the complete transformed state, the effective step norm and the potential difference. The target and potential remain fixed during a single observation's backtracking attempts. A rejected update leaves the state unchanged. Typed coupling uses the actual constrained delta, with coordinate order and a declared matrix-norm bound checked before lane adjustments are produced.

These are operational applications of recurrence, finite-potential checking and effective-delta coupling. The numerical configuration is authored policy. A lower chosen potential does not establish that an answer is correct, that the approach improves useful work, or that the whole sequence converges while observation targets change. The task coordinates do not substitute for qualified model-state measurements.

## How the state changes ordinary reading

The numerical adjustment is added to the existing base approach weights under the existing prerequisite and action limits. It replaces the old per-lane multiplier for new v4 reading decisions; the aggregate pressures still come from the same evidence and do not count as an independent second observation.

| Approach | Effect on the next local reading |
| --- | --- |
| Retain | Prefer sections from a helpful reading of the same question when those exact sections still exist. Recheck claims against the current excerpts. |
| Expand | Favor relevant sections with a small branch-diversity preference and make missing coverage explicit. |
| Repair | Include bounded neighboring context around the anchor and ask Qwen to reconsider conflicts and gaps. |
| Stop | Supply no controlled reading request until its prerequisites are resolved. |

The passage planner remains deterministic and extractive. It preserves exact text spans, source ranges and digests, honors a valid selected passage, and retains at most six sections within its 9 KB context limit. An approach may select the same passages when the whole document already fits; lane selection is not a claim that every request produces different context. Citations identify supplied source text; they do not verify entailment.

Only the selected excerpts and fixed application-authored approach instruction enter local Qwen input. Historical reviews and numerical receipts remain native data. Existing external-route input and permission rules stay separate from this local reading context.

## Freshness, receipts and compatibility

The new reading decision retains a bounded evidence projection and a recomputable numerical receipt. It binds the approach's update to actual source and answer provenance rather than to a detached count or model confidence.

Before a new trace is admitted, Token Steward reloads the owner journal under its existing transaction lock and compares current relevant reading evidence with the captured projection. It checks again before Qwen's dispatch flag is written. This closes the interval in which another writer could reverse feedback after preparation or trace capture. The current pending task is excluded from its own evidence comparison. A mismatch stops dispatch rather than silently applying stale guidance.

Source-copy freshness and request ownership are checked separately. A kept source that changed on disk cannot authorize supplying its old text. The new request contract also binds the planned passages to the captured approach and preferred-section evidence. A valid source span alone does not establish that the selected policy produced that plan.

| Identifier | Contract |
| --- | --- |
| `hampton-native-qstate-control/v4` | Reading decisions with frozen outcomes and recomputed numerical receipts |
| `hampton-reading-outcome-projection/v1` | Source-scoped, bounded task and review projection |
| `hampton-reading-numerical-control/v1` | Reading update configuration and replay rule |
| `hampton-reading-approach-usefulness/v1` | Ordered reading usefulness coordinates |

Existing v1/v2 decisions and v3 document-revision decisions retain their historical read and recomputation behavior; old records are not rewritten or awarded missing feedback. ARC3 has its separately scoped [v5 numerical adapter](native-numerical-arc3.md); other domains retain their own policies.

## Research placement and remaining work

The implementation places context reduction and feedback at an inspectable point in ordinary work: native source selection before local generation, attributable review afterward, and bounded adaptation of the next selection. Its operation is extractive passage selection. It does not demonstrate complete quotient-based understanding or hallucination prevention.

This domain applies the native bounded-update, potential-derived-force and typed-coupling interfaces to reviewed reading approaches. Representation reading and steering, learned coupling, a joint covariance model, broader memory dynamics, capability transfer and developmental credit require their own definitions and evidence. A successful numerical update grants no extra tool authority, spending, automatic practice or companion evolution.

Implementation owners: [reading outcome adapter](../desktop/Sources/ARCHiDesktop/HamptonReadingOutcomeAdapter.swift), [reading numerical adapter](../desktop/Sources/ARCHiDesktop/HamptonReadingNumericalControl.swift), [reading preparation](../desktop/Sources/ARCHiDesktop/HamptonDocumentReading.swift), [passage planner](../desktop/Sources/ARCHiDesktop/DocumentReadingPlan.swift), [reading provenance](../desktop/Sources/ARCHiDesktop/DocumentReadingTrace.swift), [native controller](../desktop/Sources/ARCHiDesktop/HamptonQ2EController.swift), [numerical primitives](../desktop/Sources/ARCHiDesktop/HamptonNumericalDynamics.swift), [task journal](../desktop/Sources/ARCHiDesktop/TokenSteward.swift) and [local request contract](../desktop/Sources/ARCHiDesktop/CodexAssistant.swift).
