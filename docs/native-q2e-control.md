# Native Q2E control for document work and ARC3

19 September 2026 · Built and installed; bounded native observation

Native ARCHi now has a shared operational controller with two consumers: document revision and bounded ARC3 planning. It computes an approach from actual domain records, freezes that decision before dispatch, and uses subsequent outcomes when deciding the next approach. The lanes have concrete consumers; they are not only diagnostic labels.

The normal build and installer completed, the previous app bundle was preserved, and the installed app opened. With no passage selected, Work together showed **Next approach · Pause and review**, a disabled **Prepare next step**, **Why this approach**, and **Qwen connected · nothing sent yet**. The existing Liminal/Garnet Seed remained visible. This observes the installed prerequisite state; a populated document-control workflow and ARC3 planning episode remain unexercised in this increment. No tests, benchmarks, model calls or games were run. The source and this narrow observation do not establish runtime performance, a trained world model, learned coupling or general intelligence.

## Source derivation and coordinates

`HamptonQ2EController.swift` adapts the donor solver's `src/arc_q2e/qstate_controller.py` and `qstate_coupling_matrix.py`: bounded diagnostic pressures select an authored control lane. The outcome update comes from Qi Experiments' `qi_experiments/critic.py` (`BetaCell`/`TabularBetaCritic`). The ARC compiler labels and heuristic weights are not imported as facts about writing or game semantics; the native policy declares its own operational coordinates.

Policy version: **`hampton-native-qstate-control/v1`**. Let `clip(x)` clamp to `[0,1]`, `S` be retained support, `C` contradictions, `U` unchanged/stalled steps, and `A` currently available alternatives. Counts have domain-specific meanings below.

| Coordinate | Native formula | Unit and meaning |
|---|---|---|
| `support` | `(S + 1) / (S + C + 2)` | Dimensionless Beta(1,1) outcome statistic, not calibrated success probability. Unreviewed work supplies no positive or negative review. |
| `coveragePressure` | `A > 0 ? 1 − support : 1` | Dimensionless need for another available approach. |
| `verifierPressure` | `clip(0.20·C + 0.15·U)` | Authored pressure from contradictions and stalled observations. |
| `alternativeCoverage` | `clip(A / 8)` | Dimensionless candidate-count saturation; eight is a policy scale, not a task-success target. |
| `resourceRemaining` | `remainingBudget / totalBudget` | Fraction of the domain's action budget remaining; not money, tokens or energy. |

Base lane weights are:

```text
retain = clip(support · (1 − verifierPressure))
expand = clip(.45·coveragePressure + .25·alternativeCoverage
              + .15·(1 − support) − .25·verifierPressure)
repair = clip(verifierPressure + .25·coveragePressure)
```

For a lane with retained attributed outcomes, its Beta mean is `(helpful + 1) / (helpful + corrections + 2)`, and its weight becomes `clip(baseWeight · (0.5 + mean))`. Both consumers supply these per-lane outcomes with different meanings: document reviews and failed checks, or ARC3 environment-reported progress and refutations/game over. Unknown outcomes leave the lane's critic unchanged. These tables are recomputed from existing records, not stored separately.

Selection uses explicit precedence rather than unconstrained maximum weight: invalid inputs/prerequisites, exhausted budget, no alternatives or eight stalled steps select **stop**. Verifier pressure at least `0.4`, three stalled steps, or a correction with dominant repair weight select **repair**. Positive support with retain weight at least expand weight selects **retain**; otherwise select **expand**. A revisioned decision retains signals, coordinates, weights, lane, reason and binding digest. Coordinate deltas compare with a compatible previous decision, or zero for a new context. They are explanatory differences, not a Lyapunov proof or a learned model update.

## The two execution loops

| Lane | Document consumer | ARC3 consumer |
|---|---|---|
| Retain | **Prepare next step** can prepare a supported, available saved method when the draft is empty. | Reuse the first edge of a bounded observed route to a state with untried actions, then replan. |
| Expand | Prepare one ordinary checked passage revision; preserve an existing authored draft. | Try a legal action not yet observed at this frame. |
| Repair | Detach prepared method attribution and prepare a fresh approach; preserve authored draft text. | Prefer another untried action with stronger penalties for refutations, invalidated transitions and game-over outcomes. |
| Stop | Preparation/controlled local Send does not proceed until prerequisites are resolved. | Retain a planning pause without dispatch or implicit RESET; leave manual controls available. |

**Document loop.** The adapter reads the latest eight records matching the current shorter-text and exact-numbers/links requirements. Helpful checked applied results supply support. A blocked proposal with a known failed mechanical check, permanent procedure counterexample or non-Helpful review supplies correction pressure. Transport failures and uncertain execution remain unknown. Alternatives are the available latest methods plus ordinary revision. The budget is one proposed revision per explicit Send; prerequisites include a current shared selection, current journals and no pending edit receipt.

The visible **Next approach** card explains the lane. **Prepare next step** changes only a draft or prepared method. Send captures the current decision for the local Qwen revision lane, and the existing document journal retains it before generation. Cloud lanes receive no local controller payload. Review and Apply still own changes to the working copy. Helpful/correction/withdrawal feedback updates the retained record; the next projection recomputes global and attributed lane outcomes instead of incrementing a second counter. Saved-method version history and outcome ordering remain separate from this recent requirement-scoped controller window.

**ARC3 loop.** `ARC3Planner` reads at most 63 transitions after the current reset/level boundary. Support counts non-invalidated, prediction-supported transitions that changed the visible frame; contradictions count refuted predictions. Stalling counts consecutive steps without reported progress or a newly observed changed state. Alternatives are untried legal candidates plus a reachable observed frontier route. Budget units are environment action dispatches; the explicit batch remains limited to 1–8 actions.

Per-lane ARC3 feedback additionally joins observed planned attempts to their exact before/action/after transition within the current game since RESET. Reported level progress or WIN is positive; prediction refutation or GAME_OVER is negative. Other frame changes remain unrated by this critic. A repeated attempt ID is counted once. Earlier level progress can prioritize a non-coordinate action kind; successful click coordinates are not transferred between levels.

Click candidates use up to 24 visible color-region points plus the existing grid fallback. Region color is not object identity. The partial observation graph excludes no-ops, contradictory/invalidated edges, terminal edges and repeatedly traversed edges. Route search is bounded to six steps, 64 queued states, and the remaining batch/episode budget. Only the first route action executes; the planner observes and replans before another action.

Before transport dispatch, `ARC3SessionStore` rechecks game, level, base frame, dispatch count and chosen legal action, then persists the frozen plan and expected digest with the requested attempt. A response separately records new/revisited/unchanged visible frame, environment level progress, win or game over. Prediction comparison can invalidate a route. Visible change alone is not level completion. Actual transitions therefore change the next plan without admitting a predicted frame as observed state.

## Ownership and limits

Document decisions are optional fields on existing `DocumentWorkRecord` entries; ARC3 plans belong to existing episode attempts/transitions. Older records without a decision receive no invented lane attribution. The controller is a pure computation and owns no independent canonical memory, identity, score database, model weights or execution port. Rebuilding a view cannot create another outcome. Neither consumer awards a skill certificate or changes the companion's appearance.

This completes a bounded native operational control path for these two domains. Remaining work includes learned/calibrated coupling, measured transfer, richer task goals, cross-domain dependency retrieval, general-purpose workflow planning and learned prediction. The authored matrix and Beta updates are useful implementation mechanisms; their presence does not establish beneficial generalization or completion of all Hampton research.

Implementation: [HamptonQ2EController.swift](../desktop/Sources/ARCHiDesktop/HamptonQ2EController.swift), [HamptonDocumentControl.swift](../desktop/Sources/ARCHiDesktop/HamptonDocumentControl.swift), [CompanionStore.swift](../desktop/Sources/ARCHiDesktop/CompanionStore.swift), [DocumentWorkJournal.swift](../desktop/Sources/ARCHiDesktop/DocumentWorkJournal.swift), [ARC3Planner.swift](../desktop/Sources/ARCHiDesktop/ARC3Planner.swift) and [ARC3SessionStore.swift](../desktop/Sources/ARCHiDesktop/ARC3SessionStore.swift). See also [task memory/outcomes](native-task-memory-outcomes.md) and the [remaining integration map](research/hampton-remaining-integration-2026-09-19.md).
