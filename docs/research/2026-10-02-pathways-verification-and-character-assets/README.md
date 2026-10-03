# Pathways, verification and character assets

Public research mapping, 2 October 2026. This review connects primary research to the native source owners and describes proposed visual-authoring work. The [source register](sources.json) identifies public references; the [sprite handoff](sprite-authoring.md) describes asset requirements. Private conversation and attachment provenance remain in the authored workspace. No runtime dependency or appearance was installed by this review.

## Decisions for ARCHi

| Input | Useful addition | Existing owner | Status |
|---|---|---|---|
| Connectome and ring-attractor research | Stable record nodes with separate, inspectable activity pathways; preserve task context across views | `MemoryMapSnapshot`, `KnowledgeParticleField`, `CompanionGraphWorkspace`, `LiminalKnowledgeBindings` | Record graph and bounded layout exist. Event replay, subsystem zoom and attraction measurements remain proposed. |
| VeriHarness | Challenge omitted requirements and shared assumptions; attach each finding to the property it actually checks | `DocumentWorkCapability`, `DocumentWorkRecord`, `DocumentMethodGraph`, existing review owner | Mechanical checks and owner reviews exist. Claim-level semantic findings are not installed. |
| Raven | Describe an executor's inputs, tools, constraints and budget before choosing it; expose handoff evidence | `AssistantExecutionSelection`, `LocalExpertPolicy`, `AssistantRoute`, `TokenSteward` | Existing selection and frozen provenance provide the integration points. No Raven runtime or general DAG executor is installed. |
| Character design and animation | Separate readable design sheets from clean animation exports; preserve character-specific identity | `CompanionPresenceArt`, `CompanionVisualAsset`, `KinLightRules`, existing native/Unity bridge | Design and animation remain separate qualification stages; no new sprite package installed. |

These references inform Hampton's representation, memory, adaptation, resource allocation, coordination and embodiment work. They do not supply a replacement canonical ledger or establish that the broader Q2E equations have been validated. ARCHi's current record owners stay authoritative; WikiOS remains a linked interface.

## What the research establishes

The MaleCNS paper maps an adult male fly's brain and nerve cord; the Cambridge published-record abstract reports 166,700 neurons and 11,710 types. That is structural evidence. Separate ring-attractor physiology supports a persistent heading representation with recurrent dynamics. The engineering inference for ARCHi is to distinguish stable structure, changing activity and observed body feedback. This is an analogy, not a biological model installed in the app. [MaleCNS published record](https://www.repository.cam.ac.uk/items/d3bc46f5-a88b-4fdd-8c7f-5e8aeb538e90), [Kim et al. research materials](https://research.janelia.org/jayaraman/KimRouaultScience2017_Downloads/).

VeriHarness separates disagreement resolution, consensus challenge and evidence-backed revision. Its verifier works against available environment evidence; benchmark grading and development feedback remain external evaluation signals. Our actionable inference is to check an artifact's requirements and final claims, including omissions, rather than equate agreement or mechanically valid formatting with correctness. No reported benchmark gains are adopted as ARCHi measurements. [Paper, sections 3–6](https://arxiv.org/html/2610.00972v1).

Raven composes model–harness executors and explicitly accounts for handoff reliability. Its sufficient conditions depend on compatible contracts, bounded errors and shared resource budgets; they are not unconditional guarantees. Current official code validates graph structure, but its completion and approval fallbacks are separate policy decisions. ARCHi should borrow explicit contracts while retaining its own owner and routing rules. No external framework is needed for this intake. [Paper](https://arxiv.org/html/2609.33439v1), [official graph implementation](https://raw.githubusercontent.com/EverMind-AI/Raven/main/raven/agent/subagent/dag_graph.py), [orchestration policy](https://evermind-ai.github.io/Raven/dag-orchestration/). Repository `main` is moving and was not pinned as a dependency.

## Native particle meaning and mathematics

Keep four meanings separate: a recorded relationship, a runtime data transfer, a retrieval-affinity suggestion and an approved numerical coupling. A line or glowing point must identify which meaning it has. A contradiction should stay discoverable beside the claim it challenges.

The current `KnowledgeParticleField.swift` uses 36 bounded deterministic relaxation steps. For ordinary, noncoincident nodes, its force has the form

\[
f_i=0.04(a_i-r_i)+\sum_{j\ne i}\frac{0.0014(r_i-r_j)}{\max(0.002,\|r_i-r_j\|^2)}
+0.009\sum_{j\in N(i)}(r_j-r_i),
\qquad r_i' = B_{0.86}\bigl(r_i+B_{0.04}(f_i)\bigr).
\]

Here `B` bounds a vector's norm, `a` is a type anchor and `r` is a layout coordinate. The implementation separately seeds coincident separation and fixes the companion at the origin. These are artificial display units. This is existing code, not a damped continuous-time simulation and not a measured model of cognition.

Hampton's state recurrence and the display coordinates have distinct consumers:

\[
q_{t+1}=q_t+\Delta q_t,\qquad r_i\in\mathbb R^2,\qquad \text{moving }r_i\text{ does not update }q.
\]

`HamptonQ2EController` retains its domain coordinate schema, captured inputs and outcome evidence. The map should show requested, transformed and applied changes only when the source owner actually records those quantities. Missing stages remain unknown; renderer interpolation must never manufacture them.

For a future pathway animation, one moving signal should reference an existing event ID, exact source/destination record versions and its actual disposition. Reopening, replaying or changing views must not dispatch work, duplicate receipts or award learning. Keep hit targets stable, pause hidden motion, support Reduce Motion and use text/symbols alongside color. A blocked or cancelled proposal must not animate into an applied-state node.

Attraction has three separate proposed channels: UI interaction, information affinity and measured controller recovery. If interaction recording is later implemented, start with explicit local opt-in, bounded retention and inspect/export/clear controls. Record exposure and presentation conditions as well as selections. Clicking, dwelling and visual prominence are not endorsement, gaze, brain measurements or permission. No such collection was enabled in this review.

## Verification at the point where evidence stops

Mechanical formatting checks can pass while a required attribution is absent. That motivates checking declared requirements separately from formatting. This is an engineering requirement, not a claim that a public benchmark or installed walkthrough has qualified semantic verification.

The next verification increment should let a task declare a small set of properties such as exact attribution, named qualifications or a required source interval. Freeze these with the task input. A finding should bind the requirement, exact artifact digest, source revision/location, check implementation, observed result and unresolved scope. A semantic checker can propose a finding; it does not author the owner's review. Repaired artifacts require fresh checks against the repaired digest.

Checking an input does not automatically verify a downstream conclusion. Changing a dependency invalidates affected evidence. No majority-vote confidence, green path or accumulated activity should become automatic Helpful credit. Retain the existing concept-to-method, explicit Send, Apply, owner review, correction and withdrawal routes. Improved verification procedures can become versioned candidate methods through these owners; they need attributable outcomes before claims of useful learning.

## Crisp implementation order

1. **Preserve review continuity.** Keep an unapplied revision inspectable while browsing its method/evidence, with freshness checked again before Apply. Navigation must preserve unsaved review state without weakening source/profile invalidation.
2. **Make requirements and evidence visible.** Extend the current check/review projection with narrowly scoped required facts and omissions, starting with attribution. No extra agent swarm or ten-rollout default.
3. **Finish map/body interaction and event traces.** Reuse exact existing bindings for two-way highlighting; add signals only for retained events. Measure performance before increasing visual density. The current map requests 15 Hz; 30 fps remains unqualified.
4. **Qualify one Liminal animation package.** Start with quiet idle, focus and reply-ready cues in the existing compositor, retain the original garnet Seed and v008 path, then exercise the same descriptor on iPhone and Unity. SEAi is a separate character proposal after that contract works.
5. **Clarify executor choice.** Add input/output, tool-access, budget and availability descriptions to the existing route preview. Reuse observed usage and method outcomes; do not create another skill store or give a descriptor authority to dispatch.

Completion of this intake means reviewed public references and a source-bound implementation handoff. It does not mean these five increments are installed, successful transfer is established, or the alpha/beta blockers are closed.
