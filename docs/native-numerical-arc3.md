# Native numerical adaptation in interactive ARC3

25 September 2026 · Native implementation. Installation and observed use have separate delivery receipts.

ARCHi connects Hampton's bounded numerical update, potential-derived force and effective-delta coupling to its existing ARC3 observation-and-action owner. The selected approach changes what the planner does next: retain an observed route, explore an untried action, repair after conflicting evidence, or stop. This is active local execution, without a model call or an automatic benchmark campaign.

## Measurements and scope

The ordered coordinates are `retainARC3Usefulness`, `expandARC3Usefulness` and `repairARC3Usefulness`, initially `[0.5, 0.5, 0.5]`. They are authored task-policy coordinates, not calibrated success probabilities or measurements of latent IQ, EQ, AQ or MQ. They remain separate from document reading and revision coordinates and from the existing five aggregate pressures.

The native outcome projection reconciles at most 63 transitions and 64 unique attempts. It validates frame hashes, observation bounds, dispatch continuity, legal actions and prediction verdicts. Identical imports deduplicate; conflicting identities and ambiguous attribution stop the consumer. A selected binding freezes the attempt, transition, prior controller and their digests, rather than recursively embedding earlier controllers or frames.

| Observed result of an attributed action | Numerical observation |
| --- | --- |
| Environment reports a completed level or WIN | `1`, unless invalidated |
| Refuted predicted frame or GAME_OVER | `0`; correction takes precedence |
| New frame, revisited frame, unchanged frame or supported prediction alone | Unknown; no numerical step |
| Manual action, missing controller, pending or unreconciled attempt | No attributed update |

A manual action can still contribute validated transition history. The numerical window is the latest eight attributable non-reset actions, including unknown results, after the latest explicit RESET. Approach usefulness survives a level boundary within that window; scene-specific graph evidence and aggregate pressures restart at the boundary. RESET clears the approach window. Invalidated earlier evidence loses its positive influence; it is retained in the episode for inspection.

Before accepting attribution, the adapter checks the selected action, coordinates, game, level, starting frame, dispatch and prediction against the observed native attempt and transition. A legacy plan with no declared expectation that inherited an old cached prediction remains uncredited. New v5 plans own their complete expectation, including an explicit absence of a prediction.

## Update mathematics

For the currently observed approach `k`, set `target[k] = y` and leave the other target coordinates equal to the prior state. The same pure numerical primitives used by the document adapters compute:

```text
F = −g G⁻¹ P(q − target)
d = η (L innovation − error + F)
V(q) = ½ (q − target)ᵀ P(q − target)
q_next = clip(q + 2⁻ᵇ cap(d), 0, 1)
Δq_effective = q_next − q
Δlane = Mᵀ Δq_effective
```

The versioned authored configuration uses `L = P = G = I₃`, `η = 0.25`, `g = 0.25`, a step norm cap of `0.125`, zero allowed potential increase and at most twelve halvings. Innovation contains `y` at `k`; error contains `q[k]` there. The coupling matrix, with source coordinates as rows and retain/expand/repair weights as columns, is:

```text
[[ 0.5,   -0.125, 0  ],
 [-0.125,  0.5,   0  ],
 [ 0,      0,     0.5]]
```

The checked operator-norm upper bound is `0.625`. Replaying the current bounded evidence from the initial state prevents recounting the same outcomes as new experience. Actual constrained deltas adjust clipped lane weights; the numerical adjustment replaces the old per-lane Beta multiplier for v5. Aggregate support, conflict, coverage and budget pressures retain their existing roles.

The force is separately calculated but collinear with the innovation/error residual in this identity-matrix configuration. That does not demonstrate an independent benefit from the force. Potential descent is checked per observation while its target is fixed; changing targets do not establish global convergence. These fixed coefficients are engineering choices, not learned causal relationships or an established optimum.

## Active planner and dispatch boundary

The planner builds a bounded graph of validated same-level observations, excludes invalidated or conflicting edges and repeated cycles, and can follow a route of at most six steps toward untried actions. Each step replans. Action 6 candidates come from visible color-region centers, with a fixed grid as fallback; those regions are not asserted to be semantic objects. Prior progress can rank a non-coordinate action kind, never transfer an old click location to a different level.

Before dispatch, the native owner reconstructs the complete plan from the current observation, transitions, attempts, original predecessor and captured remaining batch allowance. The action, route expectation, numerical evidence and controller must match exactly. An internally consistent but stale receipt cannot substitute for current owner evidence. Recording the attempt and transport dispatch remain under the existing task ownership and cancellation rules.

The batch remains at most eight actions and the session at most 64 dispatches, including RESET. Numerical adaptation does not expand those limits, authorize a model call, start practice on its own or grant persistent skill/development credit. It controls the next available bounded action; it does not guarantee solving a game.

## Versioning and ownership

| Identifier | Contract |
| --- | --- |
| `hampton-native-qstate-control/v5` | ARC3 decisions with frozen evidence and recomputed numerical receipts |
| `hampton-arc3-outcome-projection/v1` | Bounded native attempt/transition attribution |
| `hampton-arc3-numerical-control/v1` | ARC3 update configuration and replay rule |
| `hampton-arc3-approach-usefulness/v1` | Ordered task usefulness coordinates |

Legacy v1/v2 records, v3 document revision and v4 reading remain readable under their existing contracts. New numerical ARC3 records use v5; old records are not rewritten to manufacture missing evidence. The native episode remains the source of truth; there is no second database.

This applies Hampton's operational recurrence, bounded force and typed coupling to a third native task domain. It does not complete model representation calibration, general memory dynamics, transferable skill certification, companion development or the entire research/patent scope. ARC Prize performance and useful transfer require separate outcome evidence. The existing failed representation-reader calibration remains off.

Implementation: [outcome projection](../desktop/Sources/ARCHiDesktop/HamptonARC3OutcomeAdapter.swift), [numerical replay](../desktop/Sources/ARCHiDesktop/HamptonARC3NumericalControl.swift), [planner](../desktop/Sources/ARCHiDesktop/ARC3Planner.swift), [session owner](../desktop/Sources/ARCHiDesktop/ARC3SessionStore.swift), [shared controller](../desktop/Sources/ARCHiDesktop/HamptonQ2EController.swift) and [numerical primitives](../desktop/Sources/ARCHiDesktop/HamptonNumericalDynamics.swift). Runtime setup remains in [Interactive ARC3](active-arc3.md); the separately scoped document integrations are [revision](native-numerical-adaptation.md) and [reading](native-numerical-reading.md).
